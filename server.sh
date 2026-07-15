#!/system/bin/sh
# AxManager 免Root 插件 - server (后台防回刷)

MODDIR=${0%/*}

LOG() { echo "[Note14P+_Perf][server] $1"; }

LOG "server 启动，MODDIR=$MODDIR"

# ---- 环境自检（不拦，只 warn + 5s 后继续） ----
SOC=$(getprop ro.board.platform)
case "$SOC" in
    sm7435*)
        LOG "SoC: $SOC ✓"
        ;;
    *)
        LOG "⚠ SoC='$SOC' 非 sm7435，大核路径可能不对，5 秒后继续..."
        sleep 5
        ;;
esac

# 等系统 boot 完 + mi_perf 起来
sleep 15
LOG "开始防回刷循环"

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

watch_thermal() {
    TP="/sys/class/thermal/thermal_pause"
    [ -f "$TP" ] && [ "$(cat $TP 2>/dev/null)" != "0" ] && echo 0 > "$TP" 2>/dev/null
}

while true; do
    watch_cpu
    watch_thermal
    sleep 30
done