#!/usr/bin/env bash
# ============================================================
# VPS Script Manager
# GitHub: https://github.com/piper-1136/vps-script
# ============================================================

REPO="piper-1136/vps-script"
BRANCH="main"
API_URL="https://api.github.com/repos/${REPO}/git/trees/${BRANCH}?recursive=1"
RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
SELF_NAME="menu.sh"

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
BLUE='\033[34m'
BOLD='\033[1m'
RESET='\033[0m'

SCRIPTS=()

# 保证交互输入始终来自真实终端，而不是管道
# 这样无论用 curl|bash 还是 bash <(curl ...) 都能正常读取输入
if [ -t 0 ]; then
    TTY_IN="/dev/stdin"
else
    if [ -r /dev/tty ]; then
        TTY_IN="/dev/tty"
    else
        echo -e "${RED}无法获取交互终端，请改用: bash <(curl -fsSL https://raw.githubusercontent.com/${REPO}/${BRANCH}/menu.sh)${RESET}"
        exit 1
    fi
fi

read_input() {
    local prompt="$1"
    local __resultvar="$2"
    local _val
    read -rp "$prompt" _val < "$TTY_IN"
    printf -v "$__resultvar" '%s' "$_val"
}

clear_screen() {
    printf '\033[H\033[2J'
}

check_deps() {
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}未找到 curl，请先安装: apt install curl 或 yum install curl${RESET}"
        exit 1
    fi
}

get_scripts() {
    SCRIPTS=()
    local json
    json=$(curl -fsSL --connect-timeout 10 \
        -H "Accept: application/vnd.github+json" \
        "$API_URL" 2>/dev/null)

    if [ -z "$json" ]; then
        echo -e "${RED}无法连接 GitHub API（网络问题或触发速率限制）${RESET}"
        return 1
    fi

    # 检测 API 报错（比如限流）
    if echo "$json" | grep -q '"message"'; then
        local msg
        msg=$(echo "$json" | grep -o '"message": *"[^"]*"' | head -1 | sed 's/"message": *"//; s/"$//')
        if [ -n "$msg" ] && ! echo "$json" | grep -q '"tree"'; then
            echo -e "${RED}GitHub API 返回错误: ${msg}${RESET}"
            return 1
        fi
    fi

    local files
    if command -v jq >/dev/null 2>&1; then
        files=$(echo "$json" | jq -r '.tree[]? | select(.type=="blob") | select(.path | test("\\.sh$")) | .path' 2>/dev/null)
    else
        files=$(echo "$json" | grep -o '"path": *"[^"]*\.sh"' | sed 's/"path": *"//; s/"$//')
    fi

    while IFS= read -r file; do
        [ -z "$file" ] && continue
        [ "$(basename "$file")" = "$SELF_NAME" ] && continue
        SCRIPTS+=("$file")
    done < <(echo "$files" | sort)

    if [ "${#SCRIPTS[@]}" -eq 0 ]; then
        echo -e "${YELLOW}没有找到 .sh 脚本${RESET}"
        return 1
    fi
    return 0
}

# 脚本文件对应的简短中文描述
get_desc() {
    local name="$1"
    case "$name" in
        docker-bash.sh)      echo "进入 Docker 容器终端";;
        docker-port-safe.sh) echo "Docker 端口安全处理";;
        port-forward.sh)     echo "iptables 端口转发";;
        *)                   echo "$name";;
    esac
}

show_menu() {
    clear_screen
    echo
    echo -e "${CYAN}${BOLD}VPS Script Manager${RESET}  ${BLUE}${REPO}@${BRANCH}${RESET}"
    echo

    if ! get_scripts; then
        echo
        read_input "按 Enter 退出..." _dummy
        exit 1
    fi

    local i=1
    for script in "${SCRIPTS[@]}"; do
        printf " ${CYAN}%2d${RESET}) %s\n" "$i" "$(get_desc "$script")"
        i=$((i + 1))
    done

    echo
}

run_script() {
    local index="$1"
    local script="${SCRIPTS[$((index - 1))]}"
    local url="${RAW_URL}/${script}"

    local tmpfile
    tmpfile=$(mktemp)
    trap 'rm -f "$tmpfile"' EXIT

    if curl -fsSL --connect-timeout 10 "$url" -o "$tmpfile"; then
        chmod +x "$tmpfile"
        bash "$tmpfile" < "$TTY_IN"
    else
        echo -e "${RED}✗ 下载失败${RESET}"
    fi

    echo
    exit 0
}

# ============================================================
# 主流程
# ============================================================
check_deps

while true; do
    show_menu

    choice=""
    read_input "选择: " choice

    case "$choice" in
        0)
            echo
            echo "退出"
            exit 0
            ;;
        r|"")
            continue
            ;;
        *[!0-9]*)
            echo
            echo -e "${RED}无效选择${RESET}"
            sleep 1
            ;;
        *)
            if [ "$choice" -ge 1 ] && [ "$choice" -le "${#SCRIPTS[@]}" ]; then
                run_script "$choice"
            else
                echo
                echo -e "${RED}无效选择${RESET}"
                sleep 1
            fi
            ;;
    esac
done
