#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "请使用root运行"
    exit 1
fi

SWAP_FILE="/swapfile"

read -p "Swap大小(GB，回车默认2): " SIZE
size="${SIZE:-2}"

case "$size" in
    *[!0-9]*) echo "大小无效"; exit 1;;
esac

# 已有swap则先关闭并删除
if swapon --show | grep -q .; then
    echo "已有Swap，先关闭并删除..."
    swapoff -a
    rm -f "$SWAP_FILE"
fi

echo "创建 ${size}G Swap ..."

if ! fallocate -l "${size}G" "$SWAP_FILE" 2>/dev/null; then
    echo "fallocate 失败，改用 dd ..."
    rm -f "$SWAP_FILE"
    dd if=/dev/zero of="$SWAP_FILE" bs=1M count=$((size * 1024)) status=progress
fi

chmod 600 "$SWAP_FILE"
mkswap "$SWAP_FILE"
swapon "$SWAP_FILE"

# 写入fstab持久化（先清理旧记录防重复）
sed -i "/^${SWAP_FILE}[[:space:]]/d" /etc/fstab
echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab

read -p "设置vm.swappiness（回车默认10）: " SWAP
swappiness="${SWAP:-10}"
echo "vm.swappiness = $swappiness" > /etc/sysctl.d/99-swappiness.conf
sysctl -w vm.swappiness="$swappiness" >/dev/null

echo
swapon --show
free -h