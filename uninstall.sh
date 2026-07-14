#!/system/bin/sh
#!/system/bin/sh
# AxManager 免Root 插件 - Uninstall 回滚

MODDIR=${0%/*}
BACKUP="$MODDIR/backup"

echo "[Note14P+_Perf] Uninstall: restoring backup from $BACKUP"

# CPU governor 回滚
for f in "$BACKUP"/cpu*_gov.bak; do
    [ -f "$f" ] || continue
    idx=$(basename "$f" | sed 's/cpu\([0-7]\)_gov.bak/\1/')
    G=$(cat "$f")
    echo "$G" > "/sys/devices/system/cpu/cpu${idx}/cpufreq/scaling_governor" 2>/dev/null
    # 如果之前顶了 min_freq，也放开
    echo "$(cat "/sys/devices/system/cpu/cpu${idx}/cpufreq/cpuinfo_min_freq")" \
        > "/sys/devices/system/cpu/cpu${idx}/cpufreq/scaling_min_freq" 2>/dev/null
done

# GPU
[ -f "$BACKUP/gpu_gov.bak" ] && \
    echo "$(cat "$BACKUP/gpu_gov.bak")" > /sys/class/devfreq/*/governor 2>/dev/null
[ -f "$BACKUP/gpu_min.bak" ] && \
    echo "$(cat "$BACKUP/gpu_min.bak")" > /sys/class/devfreq/*/min_freq 2>/dev/null

# Thermal
[ -f "$BACKUP/thermal_pause.bak" ] && \
    cat "$BACKUP/thermal_pause.bak" > /sys/class/thermal/thermal_pause 2>/dev/null

# IO scheduler 回滚（懒一点：不回滚也行，原值没记就 skip）
# Prop 不回滚，resetprop 删不掉 ro.，persist.* 重启后小米自己会重写

echo "[Note14P+_Perf] Uninstall done"