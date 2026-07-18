#!/system/bin/sh

MODDIR=${0%/*}
FLAG="$MODDIR/.applied"

log() { echo "[HyperOS_Perf][server] $1"; }

log "server 启动，MODDIR=$MODDIR"

# 检查 .applied 标志文件
if [ ! -f "$FLAG" ]; then
    log "⚠ 未检测到 .applied 文件，说明未执行 action.sh 或已还原。"
    log "⚠ 服务退出，不进行后台守护。"
    exit 0
fi

# 环境自检
SOC=$(getprop ro.board.platform)
case "$SOC" in
    sm7435*|taro*) log "SoC: $SOC ✓" ;;
    *) log "⚠ SoC='$SOC' 非预期平台，5 秒后继续..." ; sleep 5 ;;
esac

# 等系统 boot 完
sleep 15
log "开始防回刷循环"

watch_cpu() {
    for c in $(seq 4 7); do
        F="/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_governor"
        [ -f "$F" ] || continue
        G=$(cat "$F" 2>/dev/null)
        case "$G" in
            performance|"") ;;
            *)
                if ! echo "performance" > "$F" 2>/dev/null; then
                    MAXF=$(cat "/sys/devices/system/cpu/cpu${c}/cpufreq/cpuinfo_max_freq" 2>/dev/null)
                    echo "$MAXF" > "/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_min_freq" 2>/dev/null
                fi
                ;;
        esac
    done
}

watch_gpu() {
    GPU_DIR=""
    for d in /sys/class/devfreq/*; do
        [ -f "$d/governor" ] && grep -q gpu "$d/name" 2>/dev/null && GPU_DIR="$d" && break
    done
    [ -z "$GPU_DIR" ] && return
    G=$(cat "$GPU_DIR/governor" 2>/dev/null)
    [ "$G" != "performance" ] && echo "performance" > "$GPU_DIR/governor" 2>/dev/null
}

watch_thermal() {
    TP="/sys/class/thermal/thermal_pause"
    [ -f "$TP" ] && [ "$(cat $TP 2>/dev/null)" != "0" ] && echo 0 > "$TP" 2>/dev/null
    for n in /sys/class/thermal/thermal_message/*; do
        [ -f "$n/mitigation" ] && [ "$(cat $n/mitigation 2>/dev/null)" != "0" ] && echo 0 > "$n/mitigation" 2>/dev/null
    done
}

while true; do
    watch_cpu
    watch_gpu
    watch_thermal
    sleep 45
done
