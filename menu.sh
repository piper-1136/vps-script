#!/usr/bin/env bash

# ============================================================

# VPS Script Manager

# GitHub: https://github.com/piper-1136/vps-script

# ============================================================

REPO="piper-1136/vps-script"
BRANCH="main"

API_URL="https://api.github.com/repos/${REPO}/git/trees/${BRANCH}?recursive=1"
RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

# ============================================================

# Colors

# ============================================================

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
BLUE='\033[34m'
BOLD='\033[1m'
RESET='\033[0m'

# ============================================================

# 初始化

# ============================================================

SCRIPTS=()

# ============================================================

# 清屏

# 不使用 clear，避免 curl | bash 环境下出现终端控制字符问题

# ============================================================

clear_screen() {
printf '\033[H\033[2J'
}

# ============================================================

# 获取脚本列表

# ============================================================

get_scripts() {

```
SCRIPTS=()

local json

json=$(curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    "$API_URL" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$json" ]; then
    echo -e "${RED}无法连接 GitHub API${RESET}"
    return 1
fi

# 从 GitHub Tree 中提取 .sh 文件
while IFS= read -r file; do

    [ -z "$file" ] && continue

    # 排除入口脚本
    if [ "$file" = "menu.sh" ]; then
        continue
    fi

    SCRIPTS+=("$file")

done < <(
    printf '%s\n' "$json" |
    sed -n 's/.*"path": "\([^"]*\.sh\)".*/\1/p' |
    sort
)

if [ "${#SCRIPTS[@]}" -eq 0 ]; then
    echo -e "${YELLOW}没有找到 .sh 脚本${RESET}"
    return 1
fi

return 0
```

}

# ============================================================

# 显示菜单

# ============================================================

show_menu() {

```
clear_screen

echo
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║              VPS Script Manager              ║${RESET}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${RESET}"
echo

echo -e "仓库：${BLUE}${REPO}${RESET}"
echo -e "分支：${BLUE}${BRANCH}${RESET}"
echo

echo -e "${YELLOW}正在扫描 GitHub...${RESET}"

if ! get_scripts; then
    echo
    read -rp "按 Enter 退出..."
    exit 1
fi

echo
echo -e "${GREEN}找到 ${#SCRIPTS[@]} 个脚本${RESET}"
echo

local i=1

for script in "${SCRIPTS[@]}"; do
    printf "  ${CYAN}%2d${RESET}) %s\n" "$i" "$script"
    i=$((i + 1))
done

echo
echo -e "  ${YELLOW}r${RESET}) 刷新"
echo -e "  ${RED}0${RESET}) 退出"
echo
```

}

# ============================================================

# 执行脚本

# ============================================================

run_script() {

```
local index="$1"
local script="${SCRIPTS[$((index - 1))]}"
local url="${RAW_URL}/${script}"

echo
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}脚本：${RESET}${GREEN}${script}${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo

echo -e "${BLUE}下载地址：${RESET}"
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
            echo -e "${GREEN}✓ 执行完成${RESET}"
        else
            echo
            echo -e "${RED}✗ 执行失败${RESET}"
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

# ============================================================

# 主循环

# ============================================================

while true; do

```
show_menu

read -rp "请选择： " choice

case "$choice" in

    0)
        echo
        echo "退出。"
        exit 0
        ;;

    r|R)
        continue
        ;;

    '' )
        continue
        ;;

    *[!0-9]*)
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
