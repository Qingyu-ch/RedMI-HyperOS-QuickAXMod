#!/system/bin/sh
#!/system/bin/sh
# AxManager 免Root 插件 - server (后台防回刷)
# Reignite setsid 托管，BOOT_COMPLETED 后启动

MODDIR=${0%/*}

# 等系统 boot 完、perf daemon 起来后再开始盯
sleep 15

# ---- 关键节点防回刷 ----
watch_cpu() {
    # 大核 governor 被刷回 schedutil 就再锁一次
    for c in $(seq 4 7); do
        F="/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_governor"
        [ -f "$F" ] || continue
        G=$(cat "$F" 2>/dev/null)
        case "$G" in
            performance|"") ;;
            *)
                echo "performance" > "$F" 2>/dev/null || {
                    # 写不进就顶 min_freq
                    MAXF=$(cat "/sys/devices/system/cpu/cpu${c}/cpufreq/cpuinfo_max_freq" 2>/dev/null)
                    echo "$MAXF" > "/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_min_freq" 2>/dev/null
                }
                ;;
        esac
    done
}

watch_thermal() {
    TP="/sys/class/thermal/thermal_pause"
    [ -f "$TP" ] && [ "$(cat $TP 2>/dev/null)" != "0" ] && echo 0 > "$TP" 2>/dev/null
}

# 主循环
while true; do
    watch_cpu
    watch_thermal
    sleep 30
done