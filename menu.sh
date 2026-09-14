#!/usr/bin/env bash

# ============================================================

# VPS Script Manager

# Repository: https://github.com/piper-1136/vps-script

# ============================================================

set -u

REPO="piper-1136/vps-script"
BRANCH="main"

API_URL="https://api.github.com/repos/${REPO}/git/trees/${BRANCH}?recursive=1"
RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

# ------------------------------------------------------------

# 颜色

# ------------------------------------------------------------

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
BOLD='\033[1m'
RESET='\033[0m'

# ------------------------------------------------------------

# 检查依赖

# ------------------------------------------------------------

if ! command -v curl >/dev/null 2>&1; then
echo -e "${RED}错误：需要 curl${RESET}"
exit 1
fi

# ------------------------------------------------------------

# 获取脚本列表

# ------------------------------------------------------------

get_scripts() {
local json

```
json=$(curl -fsSL "$API_URL") || {
    echo -e "${RED}无法获取 GitHub 仓库文件列表${RESET}"
    return 1
}

mapfile -t SCRIPTS < <(
    printf '%s\n' "$json" |
    grep '"path":' |
    sed -E 's/.*"path": "([^"]+)".*/\1/' |
    grep -E '\.sh$' |
    grep -vE '(^|/)menu\.sh$' |
    sort
)

if [ "${#SCRIPTS[@]}" -eq 0 ]; then
    echo -e "${YELLOW}没有找到可执行的 .sh 脚本${RESET}"
    return 1
fi
```

}

# ------------------------------------------------------------

# 显示菜单

# ------------------------------------------------------------

show_menu() {
clear

```
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════╗"
echo "║              VPS Script Manager              ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "仓库: ${BLUE}${REPO}${RESET}"
echo -e "分支: ${BLUE}${BRANCH}${RESET}"
echo

echo -e "${YELLOW}正在扫描 GitHub...${RESET}"
get_scripts || return 1

echo
echo -e "${GREEN}找到 ${#SCRIPTS[@]} 个脚本${RESET}"
echo

for i in "${!SCRIPTS[@]}"; do
    printf "  ${CYAN}%2d${RESET}) %s\n" \
        "$((i + 1))" \
        "${SCRIPTS[$i]}"
done

echo
echo -e "  ${YELLOW}r${RESET}) 刷新"
echo -e "  ${RED}0${RESET}) 退出"
echo
```

}

# ------------------------------------------------------------

# 执行脚本

# ------------------------------------------------------------

run_script() {
local index="$1"
local script="${SCRIPTS[$((index - 1))]}"
local url="${RAW_URL}/${script}"

```
echo
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}准备执行：${RESET}${GREEN}${script}${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo

echo -e "${YELLOW}脚本地址：${RESET}"
echo "$url"
echo

read -rp "确认执行？[y/N] " confirm

case "$confirm" in
    y|Y)
        echo
        echo -e "${GREEN}开始执行...${RESET}"
        echo

        if curl -fsSL "$url" | bash; then
            echo
            echo -e "${GREEN}✓ 脚本执行完成${RESET}"
        else
            echo
            echo -e "${RED}✗ 脚本执行失败${RESET}"
        fi
        ;;
    *)
        echo
        echo "已取消"
        ;;
esac

echo
read -rp "按 Enter 返回菜单..."
```

}

# ------------------------------------------------------------

# 主循环

# ------------------------------------------------------------

while true; do

```
show_menu || {
    echo
    read -rp "按 Enter 退出..."
    exit 1
}

read -rp "请选择: " choice

case "$choice" in

    0)
        echo
        echo "退出"
        exit 0
        ;;

    r|R)
        continue
        ;;

    ''|*[!0-9]*)
        echo
        echo -e "${RED}无效选择${RESET}"
        sleep 1
        ;;

    *)
        if [ "$choice" -ge 1 ] &&
           [ "$choice" -le "${#SCRIPTS[@]}" ]; then

            run_script "$choice"

        else
            echo
            echo -e "${RED}无效选择${RESET}"
            sleep 1
        fi
        ;;

esac
```

done
