#!/bin/bash

set -e

if [[ $EUID -ne 0 ]]; then
    echo "请使用 root 运行"
    exit 1
fi

enable_forward() {
    sysctl -w net.ipv4.ip_forward=1 >/dev/null

    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
}

add_rule() {

    echo
    read -p "监听端口: " LPORT
    read -p "目标IP: " DIP
    read -p "目标端口: " DPORT
    read -p "协议(tcp/udp/all)[tcp]: " PROTO

    PROTO=${PROTO:-tcp}

    enable_forward

    case "$PROTO" in
        tcp)
            iptables -t nat -A PREROUTING -p tcp --dport $LPORT -j DNAT --to-destination ${DIP}:${DPORT}
            iptables -A FORWARD -p tcp -d $DIP --dport $DPORT -j ACCEPT
            ;;
        udp)
            iptables -t nat -A PREROUTING -p udp --dport $LPORT -j DNAT --to-destination ${DIP}:${DPORT}
            iptables -A FORWARD -p udp -d $DIP --dport $DPORT -j ACCEPT
            ;;
        all)
            iptables -t nat -A PREROUTING --dport $LPORT -j DNAT --to-destination ${DIP}:${DPORT}
            iptables -A FORWARD -d $DIP --dport $DPORT -j ACCEPT
            ;;
        *)
            echo "协议错误"
            return
            ;;
    esac

    iptables -t nat -C POSTROUTING -j MASQUERADE 2>/dev/null || \
        iptables -t nat -A POSTROUTING -j MASQUERADE
    save_rule
    echo
    echo "转发成功："
    echo "$PROTO  $LPORT  --->  $DIP:$DPORT"
}

list_rule() {
    echo
    echo "========== NAT =========="
    iptables -t nat -L -n --line-numbers

    echo
    echo "========== FORWARD =========="
    iptables -L FORWARD -n --line-numbers
}

delete_rule() {

    echo
    echo "NAT规则："
    iptables -t nat -L PREROUTING -n --line-numbers

    read -p "删除PREROUTING规则编号(0取消): " NUM

    [[ "$NUM" == "0" ]] && return

    iptables -t nat -D PREROUTING $NUM

    echo "Forward规则："
    iptables -L FORWARD -n --line-numbers

    read -p "删除FORWARD规则编号(0跳过): " NUM2

    [[ "$NUM2" != "0" ]] && iptables -D FORWARD $NUM2
    save_rule
    echo "删除完成"
}

save_rule() {

    if command -v netfilter-persistent >/dev/null; then
        netfilter-persistent save
        echo "已保存"
        return
    fi

    if command -v iptables-save >/dev/null; then
        mkdir -p /etc/iptables
        iptables-save >/etc/iptables/rules.v4
        echo "保存到 /etc/iptables/rules.v4"
        return
    fi

    echo "未找到保存工具"
}

while true
do
    echo
    echo "=============================="
    echo "iptables端口转发"
    echo "=============================="
    echo "1. 添加端口转发"
    echo "2. 查看规则"
    echo "3. 删除规则"
    echo "0. 退出"
    echo

    read -p "请选择: " CH

    case "$CH" in
        1) add_rule ;;
        2) list_rule ;;
        3) delete_rule ;;
        0) exit ;;
        *) echo "输入错误" ;;
    esac
done
