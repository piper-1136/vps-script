#!/bin/bash

RULE_FILE="/etc/iptables_port_forward.rules"

# 检查root
if [ "$EUID" -ne 0 ]; then
    echo "请使用root运行"
    exit 1
fi

# 安装iptables
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

# 保存规则
save_rules() {
    echo "保存iptables规则..."

    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save
    else
        iptables-save > "$RULE_FILE"
    fi

    echo "保存完成"
}


# 加载保存规则
load_rules() {
    if [ -f "$RULE_FILE" ]; then
        iptables-restore < "$RULE_FILE"
    fi
}


# 显示转发规则
show_rules() {

    echo
    echo "====== 当前端口转发 ======"

    iptables -t nat -L PREROUTING \
        --line-numbers \
        -n \
        | grep DNAT

    echo
}


# 添加转发
add_forward(){

    read -p "外部监听端口: " SRC_PORT
    read -p "目标IP: " DST_IP
    read -p "目标端口: " DST_PORT

    echo "协议:"
    echo "1) TCP"
    echo "2) UDP"
    read -p "选择: " PROTO_NUM


    case $PROTO_NUM in
        1)
            PROTO=tcp
            ;;
        2)
            PROTO=udp
            ;;
        *)
            echo "错误"
            return
            ;;
    esac


    iptables -t nat -A PREROUTING \
        -p $PROTO \
        --dport $SRC_PORT \
        -j DNAT \
        --to-destination $DST_IP:$DST_PORT


    iptables -A FORWARD \
        -p $PROTO \
        -d $DST_IP \
        --dport $DST_PORT \
        -j ACCEPT


    echo 1 > /proc/sys/net/ipv4/ip_forward


    save_rules

    echo "添加成功"
}


# 删除规则
delete_forward(){

    mapfile -t RULES < <(
        iptables -t nat -L PREROUTING \
        --line-numbers \
        -n | grep DNAT
    )


    if [ ${#RULES[@]} -eq 0 ]; then
        echo "没有转发规则"
        return
    fi


    echo "====== 删除列表 ======"

    for i in "${!RULES[@]}"; do
        echo "$((i+1))) ${RULES[$i]}"
    done


    read -p "输入删除编号: " NUM


    if ! [[ "$NUM" =~ ^[0-9]+$ ]]; then
        echo "输入错误"
        return
    fi


    REAL_LINE=$(echo "${RULES[$((NUM-1))]}" | awk '{print $1}')


    if [ -z "$REAL_LINE" ]; then
        echo "不存在"
        return
    fi


    iptables -t nat -D PREROUTING $REAL_LINE


    save_rules

    echo "删除完成"
}



menu(){

while true
do

echo
echo "======================"
echo "  iptables端口转发"
echo "======================"
echo "1. 添加端口转发"
echo "2. 查看转发规则"
echo "3. 删除端口转发"
echo "4. 退出"
echo

read -p "选择: " CHOICE


case $CHOICE in

1)
    add_forward
    ;;

2)
    show_rules
    ;;

3)
    delete_forward
    ;;

4)
    exit
    ;;

*)
    echo "错误选择"
    ;;

esac

done

}



install_iptables

# 开启转发
sysctl -w net.ipv4.ip_forward=1 >/dev/null

load_rules

menu
