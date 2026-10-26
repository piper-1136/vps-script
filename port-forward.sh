#!/usr/bin/env bash
# pf-forward: iptables 端口转发管理（适用于 VLESS Reality 等 TCP/UDP 中转）
#
# 特点：
#   - 使用独立链 PF_PRE / PF_POST / PF_FWD，不碰 Docker、ufw 等其他规则
#   - 规则保存在 /etc/pf-forward.conf，由 systemd 服务开机重建，不使用 iptables-restore 覆盖全局规则
#   - 自动处理 DNAT + MASQUERADE + FORWARD 放行（含回程）+ MSS clamp + ip_forward 持久化
#
# 用法：
#   bash pf-forward.sh            交互菜单
#   pf-forward apply              按配置重建规则（开机服务使用）
#   pf-forward add tcp 443 1.2.3.4 443
#   pf-forward del 1              删除第 1 条
#   pf-forward list

set -u

CONF="/etc/pf-forward.conf"
SYSCTL_FILE="/etc/sysctl.d/99-pf-forward.conf"
BIN="/usr/local/sbin/pf-forward"
SERVICE="/etc/systemd/system/pf-forward.service"

if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 运行"
    exit 1
fi

# ---------- 基础 ----------

install_iptables() {
    command -v iptables >/dev/null 2>&1 && return 0
    echo "iptables 不存在，正在安装..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y iptables
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y iptables
    elif command -v yum >/dev/null 2>&1; then
        yum install -y iptables
    else
        echo "无法自动安装 iptables，请手动安装"
        exit 1
    fi
    command -v iptables >/dev/null 2>&1 || { echo "iptables 安装失败"; exit 1; }
}

enable_forward() {
    mkdir -p /etc/sysctl.d
    echo 'net.ipv4.ip_forward=1' > "$SYSCTL_FILE"
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
}

valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

valid_ip() {
    local a b c d n
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -r a b c d <<<"$1"
    for n in "$a" "$b" "$c" "$d"; do
        [ "$((10#$n))" -le 255 ] || return 1
    done
    return 0
}

ensure_chain() {   # table chain parent
    iptables -t "$1" -N "$2" 2>/dev/null
    iptables -t "$1" -C "$3" -j "$2" 2>/dev/null || iptables -t "$1" -I "$3" 1 -j "$2"
}

# ---------- 按配置重建规则 ----------

apply_rules() {
    touch "$CONF"

    ensure_chain nat    PF_PRE  PREROUTING
    ensure_chain nat    PF_POST POSTROUTING
    ensure_chain filter PF_FWD  FORWARD

    iptables -t nat -F PF_PRE
    iptables -t nat -F PF_POST
    iptables -F PF_FWD

    # 回程放行
    iptables -A PF_FWD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    local proto src ip dport
    while read -r proto src ip dport; do
        [ -z "${proto:-}" ] && continue
        case "$proto" in \#*) continue ;; esac

        iptables -t nat -A PF_PRE  -p "$proto" --dport "$src" \
            -j DNAT --to-destination "$ip:$dport"
        iptables -t nat -A PF_POST -p "$proto" -d "$ip" --dport "$dport" \
            -j MASQUERADE
        iptables       -A PF_FWD   -p "$proto" -d "$ip" --dport "$dport" \
            -j ACCEPT
    done < "$CONF"

    # 防止隧道/小 MTU 链路上 Reality 握手卡住
    iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN \
        -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN \
        -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null
}

# ---------- 开机自启 ----------

install_self() {
    local self
    self=$(readlink -f "$0" 2>/dev/null)
    if [ -f "$self" ] && [ "$self" != "$BIN" ]; then
        install -m 755 "$self" "$BIN"
    fi
    if [ ! -x "$BIN" ]; then
        echo "警告：无法安装到 $BIN（请把脚本保存为文件后再运行），开机自启未配置"
        return 1
    fi
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        cat > "$SERVICE" <<EOF
[Unit]
Description=pf-forward iptables port forwarding
After=network-online.target docker.service ufw.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$BIN apply
ExecReload=$BIN apply

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable pf-forward.service >/dev/null 2>&1
    else
        echo "警告：未检测到 systemd，请自行配置开机执行：$BIN apply"
    fi
}

# ---------- 功能 ----------

list_rules() {
    touch "$CONF"
    echo
    echo "====== 当前端口转发 ======"
    if [ ! -s "$CONF" ]; then
        echo "(无)"
    else
        printf "%-4s %-6s %-8s %s\n" "编号" "协议" "本机端口" "目标"
        local n=0 proto src ip dport
        while read -r proto src ip dport; do
            [ -z "${proto:-}" ] && continue
            n=$((n+1))
            printf "%-6s %-6s %-10s %s:%s\n" "$n" "$proto" "$src" "$ip" "$dport"
        done < "$CONF"
    fi
    echo
    echo "--- nat/PF_PRE 命中计数（pkts 增长说明有流量进来）---"
    iptables -t nat -L PF_PRE -n -v 2>/dev/null | sed 1,2d
    echo
}

add_rule() {   # proto src ip dport
    local P="$1" SRC="$2" IP="$3" DPORT="$4" PROTOS proto

    case "$P" in
        both)    PROTOS="tcp udp" ;;
        tcp|udp) PROTOS="$P" ;;
        *) echo "协议无效（tcp/udp/both）"; return 1 ;;
    esac
    valid_port "$SRC"   || { echo "本机端口无效"; return 1; }
    valid_port "$DPORT" || { echo "目标端口无效"; return 1; }
    valid_ip   "$IP"    || { echo "目标IP无效"; return 1; }
    case "$IP" in
        127.*|0.*) echo "不支持转发到回环/0 地址，请让目标服务监听 0.0.0.0"; return 1 ;;
    esac

    touch "$CONF"
    for proto in $PROTOS; do
        if grep -qx "$proto $SRC $IP $DPORT" "$CONF"; then
            echo "$proto 规则已存在，跳过"
            continue
        fi
        if grep -qE "^$proto $SRC " "$CONF"; then
            echo "警告：$proto 本机端口 $SRC 已有其他转发，新规则不会生效（先删除旧的）"
            continue
        fi
        echo "$proto $SRC $IP $DPORT" >> "$CONF"
    done

    enable_forward
    apply_rules
    install_self

    if systemctl is-active --quiet firewalld 2>/dev/null; then
        echo "提示：检测到 firewalld 正在运行，可能与本脚本冲突，建议关闭或改用 firewall-cmd 配置"
    fi
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$SRC\$"; then
        echo "提示：本机 $SRC 端口有程序在监听（转发仍会优先生效，该程序将收不到此端口流量）"
    fi
    echo "添加成功"
}

add_interactive() {
    local P SRC IP DPORT
    read -r -p "协议 [tcp/udp/both，默认 tcp]: " P
    P=${P:-tcp}
    read -r -p "本机监听端口: " SRC
    read -r -p "目标IP: " IP
    read -r -p "目标端口: " DPORT
    add_rule "$P" "$SRC" "$IP" "$DPORT"
}

del_rule() {   # 编号（可为空则交互）
    touch "$CONF"
    local -a LINES
    mapfile -t LINES < <(grep -vE '^\s*(#|$)' "$CONF")
    if [ ${#LINES[@]} -eq 0 ]; then
        echo "没有转发规则"
        return
    fi

    local NUM="${1:-}"
    if [ -z "$NUM" ]; then
        list_rules
        read -r -p "输入删除编号: " NUM
    fi
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || [ "$NUM" -lt 1 ] || [ "$NUM" -gt ${#LINES[@]} ]; then
        echo "编号无效"
        return 1
    fi

    local target="${LINES[$((NUM-1))]}" tmp
    tmp=$(mktemp)
    grep -vxF -- "$target" "$CONF" > "$tmp"
    cat "$tmp" > "$CONF"
    rm -f "$tmp"

    apply_rules
    echo "已删除: $target"
}

uninstall_all() {
    read -r -p "将清除所有转发规则、链和开机服务，确认？[y/N] " A
    case "$A" in y|Y) ;; *) echo "已取消"; return ;; esac

    iptables -t nat -D PREROUTING  -j PF_PRE  2>/dev/null
    iptables -t nat -D POSTROUTING -j PF_POST 2>/dev/null
    iptables        -D FORWARD     -j PF_FWD  2>/dev/null
    iptables -t nat -F PF_PRE  2>/dev/null; iptables -t nat -X PF_PRE  2>/dev/null
    iptables -t nat -F PF_POST 2>/dev/null; iptables -t nat -X PF_POST 2>/dev/null
    iptables        -F PF_FWD  2>/dev/null; iptables        -X PF_FWD  2>/dev/null
    iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN \
        -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null

    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable pf-forward.service >/dev/null 2>&1
    fi
    rm -f "$SERVICE" "$CONF" "$BIN"
    command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload
    echo "已清理（ip_forward 的 sysctl 配置 $SYSCTL_FILE 保留，如不需要可手动删除）"
}

menu() {
    while true; do
        echo
        echo "======================"
        echo "  iptables 端口转发"
        echo "======================"
        echo "1. 添加端口转发"
        echo "2. 查看转发规则"
        echo "3. 删除端口转发"
        echo "4. 重新应用规则"
        echo "5. 卸载（清除全部规则和服务）"
        echo "0. 退出"
        echo
        read -r -p "选择: " CHOICE
        case "$CHOICE" in
            1) add_interactive ;;
            2) list_rules ;;
            3) del_rule ;;
            4) enable_forward; apply_rules; echo "已应用" ;;
            5) uninstall_all ;;
            0|q) exit 0 ;;
            *) echo "错误选择" ;;
        esac
    done
}

# ---------- 入口 ----------

install_iptables

case "${1:-}" in
    apply) enable_forward; apply_rules ;;
    add)   shift; [ $# -eq 4 ] || { echo "用法: $0 add <tcp|udp|both> <本机端口> <目标IP> <目标端口>"; exit 1; }
           add_rule "$@" ;;
    del)   shift; del_rule "${1:-}" ;;
    list)  list_rules ;;
    "")    menu ;;
    *)     echo "用法: $0 [apply|add|del|list]"; exit 1 ;;
esac
