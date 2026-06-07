#!/bin/sh
# ==============================================================================
# V1.0.1
# CF-Server-Monitor 安装/卸载脚本 (Alpine Linux 兼容版)
# 支持: Alpine Linux (OpenRC / 裸机 / Docker 容器)
# Fixes: 1. 独立协程无 wait 阻塞 2. 原子化原子覆盖 3. 兼容 OpenRC/无 init 场景
#        4. 严格 set -u 闭环 5. 自动安装 bash 保证探针脚本语法兼容
# ==============================================================================

set -eu

# 颜色定义（busybox sh 下仅 printf '%b' 可用，所以统一用 printf）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 路径定义
SERVICE_NAME="cf-probe"
OPENRC_FILE="/etc/init.d/${SERVICE_NAME}"
SCRIPT_FILE="/usr/local/bin/${SERVICE_NAME}.sh"
PID_FILE="/var/run/${SERVICE_NAME}.pid"
LOG_FILE="/var/log/${SERVICE_NAME}.log"

# ---------------------------------------------------------------
# 统一输出工具
# ---------------------------------------------------------------
print_banner() {
    printf '%b╔══════════════════════════════════════════════════╗%b\n' "${CYAN}" "${NC}"
    printf '%b║     CF-Server-Monitor 探针管理工具 (Alpine)      ║%b\n' "${CYAN}" "${NC}"
    printf '%b╚══════════════════════════════════════════════════╝%b\n' "${CYAN}" "${NC}"
}

info()  { printf '%b[✓]%b %s\n' "${GREEN}" "${NC}" "$1"; }
warn()  { printf '%b[!]%b %s\n' "${YELLOW}" "${NC}" "$1"; }
error() { printf '%b[✗]%b %s\n' "${RED}"   "${NC}" "$1"; exit 1; }
step()  { printf '%b[→]%b %s\n' "${BLUE}"  "${NC}" "$1"; }

check_root() {
    if [ "$(id -u)" != "0" ]; then
        error "请使用 root 权限运行此脚本: sudo sh $0"
    fi
}

# ---------------------------------------------------------------
# OS / Init 系统探测
# ---------------------------------------------------------------
detect_os() {
    if [ -f /etc/alpine-release ]; then
        OS_ID="alpine"
    elif [ -f /etc/os-release ]; then
        OS_ID=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr -d "'")
    else
        OS_ID=$(uname -s | tr '[:upper:]' '[:lower:]')
    fi
    OS_ID=${OS_ID:-"unknown"}

    case "$OS_ID" in
        alpine) PKG_MGR="apk" ;;
        *) warn "检测到非 Alpine 系统: $OS_ID，仍将尝试使用 apk" ; PKG_MGR="apk" ;;
    esac

    # 探测 init 系统
    if command -v rc-service >/dev/null 2>&1 && [ -d /etc/runlevels ]; then
        INIT_SYSTEM="openrc"
    elif [ -d /run/systemd/system ]; then
        INIT_SYSTEM="systemd"
    else
        INIT_SYSTEM="manual"
    fi
}

# ---------------------------------------------------------------
# 依赖安装（Alpine 版）
# ---------------------------------------------------------------
install_deps() {
    step "检查系统依赖组件..."

    # 必须先装 bash — 探针脚本内部使用了大量 bash-only 语法
    # coreutils: 提供完整的 df -P、date、nproc、stat 等
    # procps:    提供完整的 ps -e、pgrep、pkill
    # iproute2:  提供 ss
    local required_pkgs="bash curl grep sed coreutils procps iproute2"

    if ! command -v apk >/dev/null 2>&1; then
        error "未找到 apk 包管理器，当前系统不是 Alpine Linux。"
    fi

    step "刷新 APK 索引并安装基础依赖..."
    apk update --quiet >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    apk add --no-cache --quiet $required_pkgs >/dev/null 2>&1 || \
        apk add --no-cache $required_pkgs || \
        error "依赖包安装失败，请检查网络或手动执行: apk add $required_pkgs"

    local required_cmds="bash curl awk grep sed ps df ss nproc pgrep pkill"
    for cmd in $required_cmds; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "缺少必要依赖: $cmd，请手动安装后重试。"
        fi
    done

    info "基础依赖组件检查通过（bash/coreutils/procps/iproute2/curl）"

    # 提示 init 情况
    case "$INIT_SYSTEM" in
        openrc)  info "检测到 OpenRC，将注册为系统服务。" ;;
        systemd) warn "检测到 systemd — 建议使用原版 install.sh。此处将以手动方式启动。" ;;
        manual)  warn "未检测到 init 系统（通常是 Docker 容器），将采用后台进程方式运行。" ;;
    esac
}

# ---------------------------------------------------------------
# 清理旧进程 / 旧服务
# ---------------------------------------------------------------
stop_old_service() {
    step "清理可能存在的旧服务进程..."

    # OpenRC 服务
    if [ "$INIT_SYSTEM" = "openrc" ] && [ -f "$OPENRC_FILE" ]; then
        rc-service "$SERVICE_NAME" stop >/dev/null 2>&1 || true
        rc-update del "$SERVICE_NAME" default >/dev/null 2>&1 || true
        rm -f "$OPENRC_FILE"
    fi

    # PID 文件方式的后台进程
    if [ -f "$PID_FILE" ]; then
        local old_pid
        old_pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [ -n "$old_pid" ] && kill -0 "$old_pid" >/dev/null 2>&1; then
            kill -TERM "$old_pid" >/dev/null 2>&1 || true
            sleep 1
            kill -9 "$old_pid" >/dev/null 2>&1 || true
        fi
        rm -f "$PID_FILE"
    fi

    # 兜底：按进程名杀
    if pgrep -f "${SERVICE_NAME}.sh" >/dev/null 2>&1; then
        pkill -9 -f "${SERVICE_NAME}.sh" >/dev/null 2>&1 || true
    fi
}

# ---------------------------------------------------------------
# 注入探针脚本（内部使用 bash，保证语法兼容）
# ---------------------------------------------------------------
create_script() {
    local report_interval=${1:-60}
    local ping_type=${2:-http}
    step "注入工业级监控采集探针..."

    # 先写占位符内容，再用 sed 替换 PING_TYPE_PLACEHOLDER
    cat > "${SCRIPT_FILE}" << 'PROBE_EOF'
#!/bin/bash
# 激活严格的未定义变量检查与错误即刻退出
set -eu

SERVER_ID="${1:-}"
SECRET="${2:-}"
WORKER_URL="${3:-}"
REPORT_INTERVAL="${4:-60}"
PING_TYPE="${5:-PING_TYPE_PLACEHOLDER}"

# 严苛环境下的规范 JSON 字段转义函数
escape_json() {
    local val="${1:-}"
    val="${val//\\/\\\\}"
    val="${val//\"/\\\"}"
    val="${val//$'\n'/ }"
    val="${val//$'\r'/}"
    echo -n "$val"
}

safe_div() {
    local num="${1:-0}"
    local den="${2:-0}"
    local def="${3:-0}"
    if [ "${den}" -eq 0 ]; then echo "${def}"; else echo $(( num / den )); fi
}

get_net_bytes() {
    awk 'NR>2 {rx+=$2; tx+=$10} END {printf "%.0f %.0f", rx, tx}' /proc/net/dev 2>/dev/null || echo "0 0"
}

get_cpu_stat() {
    awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8+$9, $5+$6}' /proc/stat 2>/dev/null || echo "0 0"
}

get_http_ping() {
    local rtt
    rtt=$(curl -o /dev/null -s -m 1 --connect-timeout 1 -w "%{time_total}" "http://${1:-}" 2>/dev/null | awk '{printf "%.0f", $1*1000}')
    if [ -n "$rtt" ] && [ "$rtt" -gt 0 ] 2>/dev/null; then
        echo "$rtt"
    else
        echo ""
    fi
}

get_tcp_ping() {
    local host="${1:-}"
    local port="${2:-443}"
    local scheme="http"
    local timing

    if [ -z "${host}" ]; then
        echo ""
        return
    fi

    if [ "${port}" = "443" ]; then
        scheme="https"
    fi

    timing=$(curl -k -o /dev/null -s \
        --connect-timeout 2 \
        --max-time 3 \
        -w "%{time_namelookup} %{time_connect}" \
        "${scheme}://${host}:${port}/" 2>/dev/null || true)

    awk -v t="${timing}" 'BEGIN{
        split(t, a, " ")
        dns = a[1] + 0
        conn = a[2] + 0
        if (conn <= 0 || conn < dns) {
            print ""
            exit
        }
        ms = int((conn - dns) * 1000 + 0.5)
        if (ms < 1) ms = 1
        print ms
    }'
}

get_ping() {
    local host="$1"
    local port="${2:-443}"

    if [ "${PING_TYPE}" = "tcp" ]; then
        get_tcp_ping "$host" "$port"
    else
        get_http_ping "$host"
    fi
}

# 静态测试节点定义
CT_NODE="gd-ct-dualstack.ip.zstaticcdn.com"
CU_NODE="gd-cu-dualstack.ip.zstaticcdn.com"
CM_NODE="gd-cm-dualstack.ip.zstaticcdn.com"
BD_NODE="lf3-ips.zstaticcdn.com"

# ==============================================================================
# 高并发/无竞态后台网络 Worker 协程
# ==============================================================================
run_network_worker() {
    set -eu
    local last_ip=0
    local last_ping=0

    while true; do
        local now; now=$(date +%s)

        if [ $((now - last_ip)) -ge 600 ] || [ "$last_ip" -eq 0 ]; then
            (curl -s -m 2 --connect-timeout 2 https://cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -q "ip=" && echo "1" || echo "0") > /dev/shm/.cf_ipv4.tmp && mv /dev/shm/.cf_ipv4.tmp /dev/shm/.cf_ipv4 || true
            (curl -6 -s -m 2 --connect-timeout 2 https://cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -q "ip=" && echo "1" || echo "0") > /dev/shm/.cf_ipv6.tmp && mv /dev/shm/.cf_ipv6.tmp /dev/shm/.cf_ipv6 || true
            last_ip="$now"
        fi

        if [ $((now - last_ping)) -ge 30 ] || [ "$last_ping" -eq 0 ]; then
            get_ping "$CT_NODE" > /dev/shm/.cf_ping_ct.tmp && mv /dev/shm/.cf_ping_ct.tmp /dev/shm/.cf_ping_ct || true
            get_ping "$CU_NODE" > /dev/shm/.cf_ping_cu.tmp && mv /dev/shm/.cf_ping_cu.tmp /dev/shm/.cf_ping_cu || true
            get_ping "$CM_NODE" > /dev/shm/.cf_ping_cm.tmp && mv /dev/shm/.cf_ping_cm.tmp /dev/shm/.cf_ping_cm || true
            get_ping "$BD_NODE" > /dev/shm/.cf_ping_bd.tmp && mv /dev/shm/.cf_ping_bd.tmp /dev/shm/.cf_ping_bd || true
            last_ping="$now"
        fi
        sleep 5
    done
}

# 首次基础数据初始化
NET_STAT=$(get_net_bytes)
RX_PREV=$(echo "$NET_STAT" | awk '{print $1}'); RX_PREV=${RX_PREV:-0}
TX_PREV=$(echo "$NET_STAT" | awk '{print $2}'); TX_PREV=${TX_PREV:-0}

CPU_STAT=$(get_cpu_stat)
PREV_CPU_TOTAL=$(echo "$CPU_STAT" | awk '{print $1}'); PREV_CPU_TOTAL=${PREV_CPU_TOTAL:-0}
PREV_CPU_IDLE=$(echo "$CPU_STAT" | awk '{print $2}'); PREV_CPU_IDLE=${PREV_CPU_IDLE:-0}

PREV_LOOP_TIME=$(date +%s)

echo "[INFO] CF-Server-Monitor Probe Engine Started Successfully."

run_network_worker &

while true; do
    LOOP_START_TIME=$(date +%s)

    MEM_TOTAL_KB=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0); MEM_TOTAL_KB=${MEM_TOTAL_KB:-0}
    MEM_AVAIL_KB=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0); MEM_AVAIL_KB=${MEM_AVAIL_KB:-0}
    if [ "${MEM_AVAIL_KB}" -eq 0 ]; then
        MEM_FREE_KB=$(awk '/^MemFree:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0); MEM_FREE_KB=${MEM_FREE_KB:-0}
        MEM_BUFF_KB=$(awk '/^Buffers:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0); MEM_BUFF_KB=${MEM_BUFF_KB:-0}
        MEM_CACH_KB=$(awk '/^Cached:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0); MEM_CACH_KB=${MEM_CACH_KB:-0}
        MEM_AVAIL_KB=$((MEM_FREE_KB + MEM_BUFF_KB + MEM_CACH_KB))
    fi
    RAM_TOTAL=$((MEM_TOTAL_KB / 1024))
    RAM_USED=$(((MEM_TOTAL_KB - MEM_AVAIL_KB) / 1024))
    [ "${RAM_USED}" -lt 0 ] && RAM_USED=0

    if [ "${RAM_TOTAL}" -gt 0 ]; then
        RAM=$(awk -v u="${RAM_USED}" -v t="${RAM_TOTAL}" 'BEGIN {printf "%.2f", (u/t)*100}')
    else
        RAM="0.00"
    fi

    SWAP_TOTAL_KB=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0); SWAP_TOTAL_KB=${SWAP_TOTAL_KB:-0}
    SWAP_FREE_KB=$(awk '/^SwapFree:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0); SWAP_FREE_KB=${SWAP_FREE_KB:-0}
    SWAP_TOTAL=$((SWAP_TOTAL_KB / 1024))
    SWAP_USED=$(((SWAP_TOTAL_KB - SWAP_FREE_KB) / 1024))
    [ "${SWAP_USED}" -lt 0 ] && SWAP_USED=0

    DISK_INFO=$(df -P / 2>/dev/null | tail -n1 || echo "")
    DISK_TOTAL=0; DISK_USED=0; DISK=0
    if [ -n "${DISK_INFO}" ]; then
        DISK_TOTAL=$(echo "${DISK_INFO}" | awk '{print int($2/1024)}')
        DISK_USED=$(echo "${DISK_INFO}" | awk '{print int($3/1024)}')
        DISK=$(echo "${DISK_INFO}" | awk '{print $5}' | tr -d '%')
    fi

    CPU_STAT=$(get_cpu_stat)
    CPU_TOTAL_NOW=$(echo "$CPU_STAT" | awk '{print $1}'); CPU_TOTAL_NOW=${CPU_TOTAL_NOW:-0}
    CPU_IDLE_NOW=$(echo "$CPU_STAT" | awk '{print $2}'); CPU_IDLE_NOW=${CPU_IDLE_NOW:-0}
    DIFF_TOTAL=$((CPU_TOTAL_NOW - PREV_CPU_TOTAL))
    DIFF_IDLE=$((CPU_IDLE_NOW - PREV_CPU_IDLE))

    if [ "${DIFF_TOTAL}" -le 0 ]; then
        CPU="0.00"
    else
        CPU=$(awk -v t="${DIFF_TOTAL}" -v i="${DIFF_IDLE}" 'BEGIN {p=(1-i/t)*100; if(p<0)p=0; if(p>100)p=100; printf "%.2f", p}')
    fi
    PREV_CPU_TOTAL=${CPU_TOTAL_NOW}
    PREV_CPU_IDLE=${CPU_IDLE_NOW}

    if [ -f /etc/os-release ]; then
        OS_RAW=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr -d "'")
    else
        OS_RAW=$(uname -srm)
    fi
    OS=${OS_RAW:-"Alpine Linux"}
    ARCH=$(uname -m)
    BOOT_TIME=$(awk '$1=="btime"{print $2*1000; exit}' /proc/stat 2>/dev/null)
    BOOT_TIME=${BOOT_TIME:-0}
    CPU_INFO=$(grep -m 1 'model name' /proc/cpuinfo 2>/dev/null | awk -F: '{print $2}' | xargs || echo "")
    [ -z "${CPU_INFO}" ] && CPU_INFO=${ARCH}
    CPU_CORES=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo "1")
    LOAD=$(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}' || echo "0 0 0")
    PROCESSES=$(ps -e 2>/dev/null | wc -l || echo 0)
    TCP_CONN=$(ss -ant 2>/dev/null | grep -c -v State || wc -l < /proc/net/tcp 2>/dev/null || echo 0)
    UDP_CONN=$(ss -anu 2>/dev/null | grep -c -v State || wc -l < /proc/net/udp 2>/dev/null || echo 0)

    NET_STAT=$(get_net_bytes)
    RX_NOW=$(echo "$NET_STAT" | awk '{print $1}'); RX_NOW=${RX_NOW:-0}
    TX_NOW=$(echo "$NET_STAT" | awk '{print $2}'); TX_NOW=${TX_NOW:-0}

    TIME_DELTA=$((LOOP_START_TIME - PREV_LOOP_TIME))
    [ "${TIME_DELTA}" -le 0 ] && TIME_DELTA=${REPORT_INTERVAL}

    RX_DELTA=$((RX_NOW - RX_PREV))
    TX_DELTA=$((TX_NOW - TX_PREV))
    [ "${RX_DELTA}" -lt 0 ] && RX_DELTA=0
    [ "${TX_DELTA}" -lt 0 ] && TX_DELTA=0

    RX_SPEED=$(safe_div "${RX_DELTA}" "${TIME_DELTA}" "0")
    TX_SPEED=$(safe_div "${TX_DELTA}" "${TIME_DELTA}" "0")

    RX_PREV=${RX_NOW}
    TX_PREV=${TX_NOW}
    PREV_LOOP_TIME=${LOOP_START_TIME}

    [ -f /dev/shm/.cf_ipv4 ] && IPV4=$(cat /dev/shm/.cf_ipv4) || IPV4="0"
    [ -f /dev/shm/.cf_ipv6 ] && IPV6=$(cat /dev/shm/.cf_ipv6) || IPV6="0"
    [ -f /dev/shm/.cf_ping_ct ] && PING_CT=$(cat /dev/shm/.cf_ping_ct) || PING_CT=""
    [ -f /dev/shm/.cf_ping_cu ] && PING_CU=$(cat /dev/shm/.cf_ping_cu) || PING_CU=""
    [ -f /dev/shm/.cf_ping_cm ] && PING_CM=$(cat /dev/shm/.cf_ping_cm) || PING_CM=""
    [ -f /dev/shm/.cf_ping_bd ] && PING_BD=$(cat /dev/shm/.cf_ping_bd) || PING_BD=""

    EOS=$(escape_json "${OS}")
    EARCH=$(escape_json "${ARCH}")
    ECPU=$(escape_json "${CPU_INFO}")

    PAYLOAD=$(cat <<EOF
{"id":"$SERVER_ID","secret":"$SECRET","metrics":{"cpu":"$CPU","ram":"$RAM","ram_total":"$RAM_TOTAL","ram_used":"$RAM_USED","swap_total":"$SWAP_TOTAL","swap_used":"$SWAP_USED","disk":"$DISK","disk_total":"$DISK_TOTAL","disk_used":"$DISK_USED","load":"$LOAD","boot_time":"$BOOT_TIME","net_rx":"$RX_NOW","net_tx":"$TX_NOW","net_in_speed":"$RX_SPEED","net_out_speed":"$TX_SPEED","os":"$EOS","arch":"$EARCH","cpu_info":"$ECPU","cpu_cores":"$CPU_CORES","processes":"$PROCESSES","tcp_conn":"$TCP_CONN","udp_conn":"$UDP_CONN","ip_v4":"$IPV4","ip_v6":"$IPV6","ping_ct":"$PING_CT","ping_cu":"$PING_CU","ping_cm":"$PING_CM","ping_bd":"$PING_BD"}}
EOF
)
    curl -s -o /dev/null -X POST -H "Content-Type: application/json" -d "$PAYLOAD" -m 4 --connect-timeout 2 "$WORKER_URL" 2>/dev/null || true

    LOOP_END_TIME=$(date +%s)
    EXEC_DURATION=$((LOOP_END_TIME - LOOP_START_TIME))
    SLEEP_TIME=$((REPORT_INTERVAL - EXEC_DURATION))
    [ "${SLEEP_TIME}" -le 0 ] && SLEEP_TIME=1
    sleep "${SLEEP_TIME}"
done
PROBE_EOF

    # Alpine 的 sed 支持 -i，但 busybox sed 不支持。确保安装了 GNU sed 或用迂回写法
    # 这里使用临时文件方式以兼容任何 sed
    local tmpfile
    tmpfile="${SCRIPT_FILE}.tmp"
    sed "s/PING_TYPE_PLACEHOLDER/${ping_type}/g" "${SCRIPT_FILE}" > "$tmpfile" && mv "$tmpfile" "${SCRIPT_FILE}"

    chmod +x "${SCRIPT_FILE}"
    info "探针脚本注入完成: ${SCRIPT_FILE}"
}

# ---------------------------------------------------------------
# 创建 OpenRC 服务脚本 / 手动启停入口
# ---------------------------------------------------------------
create_service() {
    local esc_id; esc_id=$(printf '%s' "$SERVER_ID" | sed 's/\\/\\\\/g; s/"/\\"/g')
    local esc_sec; esc_sec=$(printf '%s' "$SECRET" | sed 's/\\/\\\\/g; s/"/\\"/g')
    local esc_url; esc_url=$(printf '%s' "$WORKER_URL" | sed 's/\\/\\\\/g; s/"/\\"/g')
    local esc_ping; esc_ping=$(printf '%s' "$PING_TYPE" | sed 's/\\/\\\\/g; s/"/\\"/g')

    local exec_line
    exec_line="/bin/bash \"${SCRIPT_FILE}\" \"${esc_id}\" \"${esc_sec}\" \"${esc_url}\" \"${REPORT_INTERVAL}\" \"${esc_ping}\""

    if [ "$INIT_SYSTEM" = "openrc" ]; then
        step "构建 OpenRC init 脚本..."
        cat > "${OPENRC_FILE}" << EOF
#!/sbin/openrc-run
# CF-Server-Monitor Probe Agent (Alpine Linux)

description="CF Server Monitor Probe Agent"
command="/bin/bash"
command_args="${SCRIPT_FILE} ${esc_id} ${esc_sec} ${esc_url} ${REPORT_INTERVAL} ${esc_ping}"
command_background="yes"
pidfile="${PID_FILE}"
output_log="${LOG_FILE}"
error_log="${LOG_FILE}"

depend() {
    need net
    use dns
    after firewall
}
EOF
        chmod +x "${OPENRC_FILE}"
        info "OpenRC 服务脚本生成: ${OPENRC_FILE}"
    else
        step "非 OpenRC 环境 — 将使用手动后台进程方式运行..."
        info "启停命令将写入: ${SCRIPT_FILE}.ctl（同时打印在下方）"
    fi

    # 记录用于手动启停的命令（两种模式都用）
    echo "#!/bin/sh
# CF-Server-Monitor 手动启停脚本（Alpine Linux）
# 自动生成，请勿直接修改参数。
START_CMD='${exec_line} > ${LOG_FILE} 2>&1 &'
PID_FILE='${PID_FILE}'
LOG_FILE='${LOG_FILE}'

case \"\${1:-start}\" in
    start)
        if [ -f \"\$PID_FILE\" ] && kill -0 \"\$(cat \$PID_FILE)\" >/dev/null 2>&1; then
            echo '探针已在运行。'
            exit 0
        fi
        nohup ${exec_line} >> \$LOG_FILE 2>&1 &
        echo \$! > \$PID_FILE
        disown >/dev/null 2>&1 || true
        echo '探针已启动（PID: '\"\$(cat \$PID_FILE)\"'）'
        ;;
    stop)
        if [ -f \"\$PID_FILE\" ]; then
            PID=\$(cat \$PID_FILE)
            kill -TERM \$PID >/dev/null 2>&1 || true
            sleep 1
            kill -9 \$PID >/dev/null 2>&1 || true
            rm -f \$PID_FILE
            echo '探针已停止。'
        else
            pkill -9 -f '${SERVICE_NAME}.sh' >/dev/null 2>&1 || true
            echo '未找到 PID 文件，已尝试按进程名清理。'
        fi
        ;;
    status)
        if [ -f \"\$PID_FILE\" ] && kill -0 \"\$(cat \$PID_FILE)\" >/dev/null 2>&1; then
            echo '运行中（PID: '\"\$(cat \$PID_FILE)\"'）'
        else
            echo '未运行'
        fi
        ;;
    restart)
        \$0 stop
        sleep 1
        \$0 start
        ;;
    log)
        tail -f \$LOG_FILE
        ;;
    *)
        echo '用法: $0 {start|stop|status|restart|log}'
        exit 1
        ;;
esac
" > "${SCRIPT_FILE}.ctl"
    chmod +x "${SCRIPT_FILE}.ctl"
}

# ---------------------------------------------------------------
# 启动服务
# ---------------------------------------------------------------
start_service() {
    step "加载进程树并激活监控探针..."

    if [ "$INIT_SYSTEM" = "openrc" ]; then
        rc-update add "${SERVICE_NAME}" default >/dev/null 2>&1 || true
        rc-service "${SERVICE_NAME}" restart || error "OpenRC 服务启动失败，请检查日志: tail -n 30 ${LOG_FILE}"
    else
        sh "${SCRIPT_FILE}.ctl" start || error "后台进程启动失败，请检查日志: tail -n 30 ${LOG_FILE}"
    fi

    sleep 2

    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" >/dev/null 2>&1; then
        info "探针监控引擎已进入平稳运行状态。"
    else
        error "探针服务未能启动成功。请排查: tail -n 30 ${LOG_FILE}"
    fi
}

# ---------------------------------------------------------------
# 安装主流程
# ---------------------------------------------------------------
install_probe() {
    SERVER_ID=${1:-""}
    SECRET=${2:-""}
    WORKER_URL=${3:-""}
    REPORT_INTERVAL=${4:-}
    PING_TYPE=${5:-}

    if [ -z "$SERVER_ID" ] || [ -z "$SECRET" ] || [ -z "$WORKER_URL" ]; then
        printf '%b错误: 运行所需的入参不完整。%b\n\n' "${RED}" "${NC}"
        echo "用法:"
        echo "  sh $0 install <SERVER_ID> <SECRET> <WORKER_URL> [REPORT_INTERVAL] [PING_TYPE]"
        echo "  PING_TYPE: http (默认) | tcp"
        exit 1
    fi

    REPORT_INTERVAL=${REPORT_INTERVAL:-60}
    PING_TYPE=${PING_TYPE:-http}

    print_banner
    check_root
    detect_os
    install_deps
    stop_old_service
    create_script "$REPORT_INTERVAL" "$PING_TYPE"
    create_service
    start_service

    printf '\n%b=============================================%b\n' "${GREEN}" "${NC}"
    printf  '         CF-Server-Monitor 安装成功\n'
    printf  '%b=============================================%b\n' "${GREEN}" "${NC}"
    printf  '  服务状态 : %bActive (Running)%b\n' "${GREEN}" "${NC}"
    printf  '  运行模式 : '
    case "$INIT_SYSTEM" in
        openrc) echo "OpenRC 系统服务 (${OPENRC_FILE})" ;;
        *)      echo "手动后台进程 (PID: $(cat "$PID_FILE"))" ;;
    esac
    printf  '  管理指令 :\n'
    if [ "$INIT_SYSTEM" = "openrc" ]; then
        printf  '    ● 查看日志     : tail -f %s\n' "${LOG_FILE}"
        printf  '    ● 查看状态     : rc-service %s status\n' "${SERVICE_NAME}"
        printf  '    ● 启动/停止    : rc-service %s {start|stop|restart}\n' "${SERVICE_NAME}"
    else
        printf  '    ● 查看日志     : tail -f %s\n' "${LOG_FILE}"
        printf  '    ● 启动/停止    : sh %s {start|stop|restart|status|log}\n' "${SCRIPT_FILE}.ctl"
    fi
    printf  '    ● 彻底卸载     : sh %s uninstall\n' "$0"
    printf  '%b=============================================%b\n\n' "${GREEN}" "${NC}"
}

# ---------------------------------------------------------------
# 卸载主流程
# ---------------------------------------------------------------
uninstall_probe() {
    print_banner
    printf '%b[!] 开始执行无残留深度卸载清理方案...%b\n\n' "${YELLOW}" "${NC}"
    check_root
    detect_os

    step "停用并撤销系统守护进程..."
    stop_old_service

    step "清理服务描述性系统文件..."
    rm -f "${OPENRC_FILE}"

    step "销毁探针物理可执行代码文件..."
    rm -f "${SCRIPT_FILE}"
    rm -f "${SCRIPT_FILE}.ctl"

    step "抹除共享内存高速缓存区..."
    rm -f /dev/shm/.cf_ipv4 /dev/shm/.cf_ipv6 /dev/shm/.cf_ping_* 2>/dev/null || true

    step "清理日志与 PID 文件..."
    rm -f "${PID_FILE}" "${LOG_FILE}" 2>/dev/null || true

    printf '\n%b╔══════════════════════════════════════════╗%b\n' "${GREEN}" "${NC}"
    printf  '║     ✓ 卸载完毕！系统环境无任何残留。     ║\n'
    printf  '%b╚══════════════════════════════════════════╝%b\n\n' "${GREEN}" "${NC}"
}

# ---------------------------------------------------------------
# 入口
# ---------------------------------------------------------------
case "${1:-install}" in
    install)
        shift 1 2>/dev/null || true
        install_probe "$@"
        ;;
    uninstall|remove|delete|purge)
        uninstall_probe
        ;;
    *)
        echo "未知指令. 可选命令: install | uninstall"
        exit 1
        ;;
esac
