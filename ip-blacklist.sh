#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "请使用root运行"
    exit 1
fi

RULES_FILE="/etc/iptables_ip_blacklist.rules"

install_iptables() {
    if ! command -v iptables >/dev/null 2>&1; then
        echo "iptables不存在，正在安装..."
        if command -v apt >/dev/null 2>&1; then
            apt update
            apt install -y iptables iptables-persistent
        elif command -v yum >/dev/null 2>&1; then
            yum install -y iptables-services
        else
            echo "无法自动安装iptables"
            exit 1
        fi
    fi
}

init_chain() {
    # 创建黑名单链（已存在则不报错）
    iptables -N BLACKLIST 2>/dev/null

    # 在主链中插入引用（若已引用则排查后跳过）
    if ! iptables -C INPUT -j BLACKLIST 2>/dev/null; then
        iptables -I INPUT -j BLACKLIST
    fi
}

save_rules() {
    echo "保存黑名单规则..."
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save
    else
        iptables-save > "$RULES_FILE"
    fi
    echo "保存完成"
}

load_rules() {
    if [ -f "$import_RULES_FILE" ]; then
        iptables-restore < "$import_RULES_FILE" 2>/dev/null
    fi
}

show_blacklist() {
    echo
    echo "====== 当前黑名单 ======"
    if iptables -L BLACKLIST -n --line-numbers 2>/dev/null | grep -q DROP; then
        iptables -L BLACKLIST -n --line-numbers | grep DROP
    else
        echo "(空)"
    fi
    echo
}

add_blacklist() {
    iptables -L BLACKLIST -n >/dev/null 2>&1 || init_chain

    read -p "输入IP或IP段(如 1.2.3.4 或 1.2.3.0/24): " IP

    if [ -z "$IP" ]; then
        echo "IP不能为空"
        return
    fi

    if iptables -C BLACKLIST -s "$IP" -j DROP 2>/dev/null; then
        echo "已存在: $IP"
        return
    fi

    iptables -A BLACKLIST -s "$IP" -j DROP
    echo "已添加: $IP (DROP)"
    save_rules
}

remove_blacklist() {
    mapfile -t RULES < <(
        iptables -L BLACKLIST -n --line-numbers 2>/dev/null | grep DROP
    )

    if [ ${#RULES[@]} -eq 0 ]; then
        echo "黑名单为空"
        return
    fi

    echo "====== 移除列表 ======"
    for i in "${!RULES[@]}"; do
        echo "$((i+1))) ${RULES[$i]}"
    done

    read -p "输入移除编号: " NUM

    if ! [[ "$NUM" =~ ^[0-9]+$ ]]; then
        echo "输入错误"
        return
    fi

    REAL_LINE=$(echo "${RULES[$((NUM-1))]}" | awk '{print $1}')

    if [ -z "$REAL_LINE" ]; then
        echo "不存在"
        return
    fi

    iptables -D BLACKLIST "$REAL_LINE"
    echo "已移除"
    save_rules
}

menu() {
    while true; do
        echo
        echo "======================"
        echo "  IP黑名单管理"
        echo "======================"
        echo "1. 添加IP/IP段到黑名单"
        echo "2. 查看黑名单"
        echo "3. 移除黑名单"
        echo "4. 退出"
        echo

        read -p "选择: " CHOICE

        case $CHOICE in
            1) add_blacklist ;;
            2) show_blacklist ;;
            3) remove_blacklist ;;
            4) exit ;;
            *) echo "错误选择" ;;
        esac
    done
}

install_iptables
init_chain
load_rules
menu