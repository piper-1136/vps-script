#!/usr/bin/env bash
# 最小影响启用 TCP BBR：只设置拥塞控制算法，不改 qdisc、不改现有配置文件
# 用法:  sudo bash enable-bbr-min.sh              # 启用
#        sudo bash enable-bbr-min.sh --uninstall  # 回滚
set -euo pipefail

CONF="/etc/sysctl.d/99-bbr.conf"
MOD="/etc/modules-load.d/bbr.conf"

die() { echo "[x] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "请使用 root 运行"

if [[ "${1:-}" == "--uninstall" ]]; then
    rm -f "$CONF" "$MOD"
    [[ "$(sysctl -n net.ipv4.tcp_congestion_control)" == "bbr" ]] && sysctl -qw net.ipv4.tcp_congestion_control=cubic
    echo "[+] 已回滚，拥塞控制切回 cubic"
    exit 0
fi

kver="$(uname -r | cut -d- -f1)"
ver_ge() { [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" == "$1" ]]; }  # $2 >= $1

ver_ge 4.9 "$kver" || die "内核 $kver 过低，BBR 需要 >= 4.9"

modprobe tcp_bbr 2>/dev/null || true
grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control \
    || die "内核不支持 bbr (可用: $(cat /proc/sys/net/ipv4/tcp_available_congestion_control))"

if [[ "$(sysctl -n net.ipv4.tcp_congestion_control)" == "bbr" && -f "$CONF" ]]; then
    echo "[+] BBR 已启用，无需改动"; exit 0
fi

{
    echo "# Managed by enable-bbr-min.sh"
    echo "net.ipv4.tcp_congestion_control = bbr"
    # 内核 4.13+ 的 BBR 自带 pacing，无需 fq；仅老内核才需要
    if ! ver_ge 4.13 "$kver"; then
        echo "net.core.default_qdisc = fq"
    fi
} > "$CONF"

# 仅当 tcp_bbr 是可加载模块时，才写开机加载项
if lsmod | grep -q '^tcp_bbr'; then
    echo "tcp_bbr" > "$MOD"
fi

sysctl -qp "$CONF"

[[ "$(sysctl -n net.ipv4.tcp_congestion_control)" == "bbr" ]] || die "设置未生效"
echo "[+] BBR 已启用 (新建连接生效，已有连接不受影响)"

# 只提示，不修改
if grep -qsE '^\s*net\.ipv4\.tcp_congestion_control' /etc/sysctl.conf; then
    echo "[!] /etc/sysctl.conf 里也设置了 tcp_congestion_control，重启后可能覆盖本配置，请自行检查"
fi
