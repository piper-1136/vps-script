#!/usr/bin/env bash

set -u

if ! command -v docker >/dev/null 2>&1; then
    echo "未找到 docker 命令，请先安装 Docker"
    exit 1
fi

KEYWORD="${1:-}"

if [[ -z "$KEYWORD" ]]; then
    read -rp "请输入容器关键字: " KEYWORD
fi

if [[ -z "$KEYWORD" ]]; then
    echo "关键字不能为空"
    exit 1
fi

# 查询运行中的容器
mapfile -t CONTAINERS < <(
    docker ps --format '{{.ID}}\t{{.Names}}\t{{.Image}}' |
    grep -i -- "$KEYWORD"
)

if [[ ${#CONTAINERS[@]} -eq 0 ]]; then
    echo "未找到匹配的运行中容器: $KEYWORD"
    exit 1
fi

# 多个容器时让用户选择
if [[ ${#CONTAINERS[@]} -gt 1 ]]; then
    echo
    echo "找到多个匹配容器："
    echo

    for i in "${!CONTAINERS[@]}"; do
        IFS=$'\t' read -r ID NAME IMAGE <<< "${CONTAINERS[$i]}"
        printf "  [%d] %-20s %-20s %s\n" \
            "$((i + 1))" "$NAME" "$ID" "$IMAGE"
    done

    echo
    read -rp "请选择容器 [1-${#CONTAINERS[@]}]: " CHOICE

    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] ||
       (( CHOICE < 1 || CHOICE > ${#CONTAINERS[@]} )); then
        echo "无效选择"
        exit 1
    fi

    SELECTED="${CONTAINERS[$((CHOICE - 1))]}"
else
    SELECTED="${CONTAINERS[0]}"
fi

IFS=$'\t' read -r CONTAINER_ID CONTAINER_NAME IMAGE <<< "$SELECTED"

echo
echo "容器: $CONTAINER_NAME"
echo "镜像: $IMAGE"

# 优先检测 bash
if docker exec "$CONTAINER_ID" sh -c 'command -v bash >/dev/null 2>&1'; then
    SHELL_CMD="/bin/bash"
elif docker exec "$CONTAINER_ID" sh -c 'command -v sh >/dev/null 2>&1'; then
    SHELL_CMD="/bin/sh"
else
    echo "容器中既没有 bash，也没有 sh"
    exit 1
fi

echo "进入: $SHELL_CMD"
echo

exec docker exec -it "$CONTAINER_ID" "$SHELL_CMD"
