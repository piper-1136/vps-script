#!/usr/bin/env bash
# ============================================================
# 进程网络连接分析 (默认分析 xray)
# 使用 lsof 获取指定 PID 的网络连接
# 结合 iftop 采样流量, 只显示流量在跑(超过阈值)的 IP
# 并对这些 IP 标记归属地+组织(中国电信/Cloudflare/Amazon等)
# 依赖: lsof, curl; 流量过滤需要 iftop (需root)
# ============================================================

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'
BOLD='\033[1m'
RESET='\033[0m'

CACHE_DIR="/tmp/geoip_cache"
PROC_NAME="xray"
TOP=20               # 显示连接数最多的前N个IP
SAMPLESEC=5          # iftop 采样秒数
MIN_KB=10            # 流量阈值(KB), 低于此值的IP不显示
WITH_TRAFFIC=1       # 默认结合流量过滤; -a(所有) 时关闭
LOCAL_IPS=""

# 获取本机IP(第一个公网/内网地址)
get_local_ip() {
    LOCAL_IPS=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$LOCAL_IPS" ] && LOCAL_IPS=$(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
}

# ---------- 基础工具 ----------
check_lsof() {
    command -v lsof >/dev/null 2>&1 || {
        echo -e "${RED}未找到 lsof，请先安装: ${YELLOW}apt install lsof${RESET} 或 ${YELLOW}yum install lsof${RESET}"
        exit 1
    }
    [ "$(id -u)" = "0" ] || echo -e "${YELLOW}提示: 非root运行，lsof 可能看不到其他用户进程的连接，建议 sudo $0${RESET}"
}

check_iftop() {
    command -v iftop >/dev/null 2>&1 || {
        echo -e "${YELLOW}未安装 iftop，无法按流量过滤(将显示全部连接)${RESET}"
        echo -e "${YELLOW}安装: ${GREEN}apt install iftop${RESET} 或 ${GREEN}yum install iftop${RESET}"
        return 1
    }
}

check_curl() {
    command -v curl >/dev/null 2>&1 || {
        echo -e "${YELLOW}未找到 curl，归属地查询将显示 N/A${RESET}"
        return 1
    }
}

# ---------- 找到进程 PID ----------
find_pid() {
    local pids
    pids=$(pgrep -x "$PROC_NAME" 2>/dev/null)
    [ -z "$pids" ] && pids=$(pgrep -f "$PROC_NAME" 2>/dev/null)
    # 排除脚本自身
    pids=$(echo "$pids" | grep -v "^$$\$" )
    echo "$pids" | tr '\n' ' '
}

# 判断是否为内网/保留地址
is_private_ip() {
    case "$1" in
        10.*|127.*|169.254.*|192.168.*|172.16.*|172.1[7-9].*|172.2[0-9].*|172.3[0-1].*|0.*|224.*|239.*|::1|::|fe80:*|fc*|fd*)
            return 0 ;;
        *) return 1 ;;
    esac
}

# ---------- IP归属地+组织查询 (带缓存) ----------
# 返回: 国家/城市 组织(简化,如 中国电信/Cloudflare/Amazon)
query_geo() {
    local ip="$1"
    [ -z "$ip" ] && { echo "N/A"; return; }

    is_private_ip "$ip" && { echo "内网"; return; }

    command -v curl >/dev/null 2>&1 || { echo "N/A"; return; }

    [ -d "$CACHE_DIR" ] || mkdir -p "$CACHE_DIR"
    local f="$CACHE_DIR/$ip"
    [ -f "$f" ] && { cat "$f"; return; }

    local data cc city org isp as out
    data=$(curl -s --max-time 5 "http://ip-api.com/json/${ip}?lang=en&fields=status,countryCode,city,isp,org,as" 2>/dev/null)

    if echo "$data" | grep -q '"status":"success"'; then
        cc=$(echo "$data"  | grep -o '"countryCode":"[^"]*"' | head -1 | cut -d'"' -f4)
        city=$(echo "$data"| grep -o '"city":"[^"]*"'        | head -1 | cut -d'"' -f4)
        org=$(echo "$data" | grep -o '"org":"[^"]*"'         | head -1 | cut -d'"' -f4)
        isp=$(echo "$data" | grep -o '"isp":"[^"]*"'         | head -1 | cut -d'"' -f4)
        as=$(echo "$data"  | grep -o '"as":"[^"]*"'          | head -1 | cut -d'"' -f4)

        [ -z "$org" ] && org="$isp"
        [ -z "$org" ] && org="$as"

        out=""
        if [ -n "$cc" ]; then out="$cc"; fi
        [ -n "$city" ] && out="$out/$city"
        # 直接使用查询返回的组织名原文, 不做翻译映射
        [ -n "$org" ] && out="$out $org"
        [ -z "$out" ] && out="N/A"
        echo "$out" > "$f"
        echo "$out"
    else
        echo "N/A" > "$f"
        echo "N/A"
    fi
}

# ---------- 获取进程的所有连接 (lsof) ----------
# 每行输出: peerIp|状态
get_pid_connections() {
    local pid="$1"
    # lsof: -n不解析主机名 -P不解析端口 -i网络文件 -a AND
    lsof -nP -a -p "$pid" -i 2>/dev/null \
        | tail -n +2 \
        | while IFS= read -r line; do
              case "$line" in
                  *'->'*)
                      # 提取 本地IP:端口->对端IP:端口 形态; 兼容IPv4/IPv6
                      local conn peer state
                      # 从行中提取 NAME: IP->IP 段
                      conn=$(echo "$line" | grep -oE '[0-9.]+:[0-9]+->[0-9.]+:[0-9]+' | head -1)
                      [ -z "$conn" ] && continue
                      peer=${conn#*->}
                      peer=${peer%:*}           # 去掉端口
                      state=$(echo "$line" | sed -n 's/.*(\([^)]*\)).*/\1/p')
                      [ -z "$peer" ] && continue
                      # 排除内网/回环对端
                      is_private_ip "$peer" && continue
                      echo "$peer|$state"
                      ;;
              esac
          done
}

# ---------- iftop 采样, 得到有流量的IP (KB) ----------
# 返回每行: peerIp|KB (仅保留累计流量 >= MIN_KB 的IP, 同时避免本机IP)
# iftop -t 文本格式: host行(含对端IP和右侧累计值) 与 "=> 本机" 方向行交替
get_traffic() {
    local seconds="$1"
    iftop -n -t -s "$seconds" -L 500 2>/dev/null \
        | grep -vE '=>|<=|<=' \
        | awk -v thr="$MIN_KB" -v localip="$LOCAL_IPS" '{
            # 只处理含对端IP的host行
            if (match($0, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
                host=substr($0, RSTART, RLENGTH);
                # 跳过本机IP(避免把本机当对端)
                if (host == localip) next;

                # 抽取全部带单位数值: 第1个=last2s速率, 最后一个=累计总量
                # 单位: B=字节, KB, MB, GB; 统一折算为KB
                speed=0; total=0; cnt=0; buf=$0;
                while (match(buf, /[0-9.]+[kKmMgGgBbB]/)) {
                    v=substr(buf, RSTART, RLENGTH);
                    buf=substr(buf, RSTART+RLENGTH);
                    num=v+0; uc=tolower(substr(v, length(v), 1));
                    if      (uc=="g") num*=1048576;
                    else if (uc=="m") num*=1024;
                    else if (uc=="b") num/=1024;
                    if (cnt==0) speed=num;   # 第一个=实时速率(last2s)
                    total=num;                # 最后一个=累计
                    cnt++;
                }

                # 用实时速率(speed)过滤: 只显示有速率(>=MIN_KB KB/s)的IP
                if (speed >= thr) printf "%s %.1f %.1f\n", host, speed, total;
            }
        }'
}

# ============================================================
# 主流程
# ============================================================
while [ $# -gt 0 ]; do
    case "$1" in
        -p|--process) shift; PROC_NAME="$1"; shift ;;
        -t|--time)    shift; SAMPLESEC="$1"; shift ;;
        -n)           shift; TOP="$1"; shift ;;
        -k)           shift; MIN_KB="$1"; shift ;;
        -a|--all)     WITH_TRAFFIC=0; shift ;;
        -h|--help)
            cat <<EOF
用法: $0 [选项]

默认分析 xray 进程, 显示流量在跑(超过阈值)的IP并标归属地/组织

选项:
  -p, --process <名>  指定进程名 (默认 xray)
  -t <秒>             iftop 采样秒数 (默认 $SAMPLESEC)
  -k <KB>             流量过滤阈值KB, 低于此值不显示 (默认 $MIN_KB)
  -n <数量>           显示前N个IP (默认 $TOP)
  -a, --all           显示全部连接, 不按流量过滤
  -h, --help          帮助
EOF
            exit 0
            ;;
        *) echo -e "${RED}未知选项: $1${RESET}"; exit 1 ;;
    esac
done

check_lsof
check_curl
get_local_ip

PIDS=$(find_pid)
if [ -z "$PIDS" ]; then
    echo -e "${RED}未找到进程: $PROC_NAME${RESET}"
    # 尝试列出相似进程
    echo -e "${YELLOW}当前含'$PROC_NAME'的进程:${RESET}"
    pgrep -af "$PROC_NAME" 2>/dev/null | head || echo "   无"
    exit 1
fi

echo -e "${CYAN}${BOLD}== $PROC_NAME 进程 (PID: $PIDS) ==${RESET}"
for p in $PIDS; do
    cmd="?"
    [ -r "/proc/$p/cmdline" ] && cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
    echo -e "  PID $p: ${YELLOW}${cmd:-?}${RESET}"
done
echo

# 汇总每个 PID 的连接: 收集 peerIp -> (状态,出现次数)
TMP=$(mktemp)
for p in $PIDS; do
    get_pid_connections "$p" >> "$TMP"
done

if [ ! -s "$TMP" ]; then
    echo -e "${YELLOW}  该进程当前没有活动网络连接${RESET}"
    rm -f "$TMP"
    exit 0
fi

# 聚合: 每 IP 连接数
echo -e "${GREEN}${BOLD}--- $PROC_NAME 的连接 (按IP聚合) ---${RESET}"
awk -F'|' '{ counts[$1]++ } END { for (ip in counts) print ip, counts[ip] }' "$TMP" \
    | sort -k2 -rn > "${TMP}.agg"
echo -e "  共 $(wc -l < "${TMP}.agg") 个远端IP, $(wc -l < "$TMP") 条连接"
echo

# 采集流量 (可选, 需 iftop)
declare -A TRAFFIC_SPEED
declare -A TRAFFIC_TOTAL
HAVE_TRAFFIC=0
if [ "$WITH_TRAFFIC" = "1" ] && command -v iftop >/dev/null 2>&1 && [ "$(id -u)" = "0" ]; then
    echo -e "${CYAN}正在用 iftop 采样 ${SAMPLESEC} 秒, 识别有网速的IP (>=${MIN_KB}KB/s)...${RESET}"
    get_traffic "$SAMPLESEC" > "${TMP}.traf"
    if [ -s "${TMP}.traf" ]; then
        HAVE_TRAFFIC=1
        while read -r ip speed total; do
            TRAFFIC_SPEED[$ip]=$speed
            TRAFFIC_TOTAL[$ip]=$total
        done < "${TMP}.traf"
    fi
    rm -f "${TMP}.traf"
elif [ "$WITH_TRAFFIC" = "1" ]; then
    echo -e "${YELLOW}未安装 iftop 或非root, 跳过网速统计, 显示全部连接${RESET}"
fi

# 归属地查询与展示
if [ "$HAVE_TRAFFIC" = "1" ]; then
    echo -e "${CYAN}${BOLD}--- 有网速的IP (>=${MIN_KB}KB/s, TOP ${TOP}) ---${RESET}"
    printf "  %-18s %-9s %-10s %-5s %-30s %s\n" "IP" "速率(KB/s)" "累计(MB)" "连接" "归属地/组织" "状态"
else
    echo -e "${CYAN}${BOLD}--- 连接 TOP ${TOP} ---${RESET}"
    printf "  %-18s %-6s %-30s %s\n" "IP" "连接数" "归属地/组织" "状态"
fi
echo "  ------------------------------------------------------------------"

# 展示
shown=0
while read -r ip cnt; do
    # 网速过滤: 只显示有网速的IP
    if [ "$HAVE_TRAFFIC" = "1" ]; then
        sp=${TRAFFIC_SPEED[$ip]:-0}
        if ! awk "BEGIN{exit !($sp >= $MIN_KB)}"; then
            continue
        fi
    fi
    shown=$((shown+1))
    [ "$shown" -gt "$TOP" ] && break
    states=$(awk -F'|' -v ip="$ip" '$1==ip{print $2}' "$TMP" | sort -u | tr '\n' ',')
    states=${states%,}
    geo=$(query_geo "$ip")
    if [ "$HAVE_TRAFFIC" = "1" ]; then
        sp=${TRAFFIC_SPEED[$ip]:-0}
        tot=${TRAFFIC_TOTAL[$ip]:-0}
        totmb=$(awk "BEGIN{printf \"%.1f\", $tot/1024}")
        printf "  %-18s %-9.1f %-10s %-5s %-30s %s\n" "$ip" "$sp" "$totmb" "$cnt" "$geo" "$states"
    else
        printf "  %-18s %-6s %-30s %s\n" "$ip" "$cnt" "$geo" "$states"
    fi
done < "${TMP}.agg"

if [ "$shown" -eq 0 ]; then
    echo -e "${YELLOW}  (网速达到 ${MIN_KB}KB/s 的IP没有, 可调低 -k 或用 -a 显示全部)${RESET}"
fi

rm -f "$TMP" "${TMP}.agg"
echo