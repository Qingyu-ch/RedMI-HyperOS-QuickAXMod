#!/system/bin/sh
# 回滚所有系统修改至默认状态（不删除属性，设置默认值）

MODDIR=${0%/*}
BACKUP="$MODDIR/backup"
FLAG="$MODDIR/.applied"

log() { echo "[HyperOS_Perf] $1"; }

log "========================================"
log "红米小米性能释放 - Uninstall"
log "MODDIR=$MODDIR"
log "========================================"

# ---- 检查 backup 目录 ----
if [ ! -d "$BACKUP" ]; then
    echo "⚠ backup 目录不存在，可能从未执行过 Action，将跳过备份恢复，仅重置 VM 和属性"
else
    echo "将从 backup 恢复节点，并重置 VM/属性至默认"
fi

echo ""
echo "----- 开始回滚 -----"

# ============================================
# 1. CPU governor 恢复
# ============================================
echo "[1] CPU governor"
for c in $(seq 0 7); do
    BF="$BACKUP/cpu${c}_gov.bak"
    if [ -f "$BF" ]; then
        F="/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_governor"
        [ -f "$F" ] && cat "$BF" > "$F" 2>/dev/null && echo "  cpu$c governor 已恢复"
    else
        echo "  ⚠ cpu$c governor 备份缺失，跳过"
    fi
done

# ============================================
# 2. CPU min_freq 恢复（仅大核有备份时）
# ============================================
echo "[2] CPU min_freq"
for c in $(seq 4 7); do
    MBF="$BACKUP/cpu${c}_min.bak"
    if [ -f "$MBF" ]; then
        MF="/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_min_freq"
        [ -f "$MF" ] && cat "$MBF" > "$MF" 2>/dev/null && echo "  cpu$c min_freq 已恢复"
    fi
done

# ============================================
# 3. GPU 恢复
# ============================================
echo "[3] GPU"
GPU_DIR=""
for d in /sys/class/devfreq/*; do
    [ -f "$d/governor" ] && grep -q gpu "$d/name" 2>/dev/null && GPU_DIR="$d" && break
done
if [ -n "$GPU_DIR" ]; then
    [ -f "$BACKUP/gpu_gov.bak" ] && cat "$BACKUP/gpu_gov.bak" > "$GPU_DIR/governor" 2>/dev/null && echo "  GPU governor 已恢复"
    [ -f "$BACKUP/gpu_min.bak" ] && cat "$BACKUP/gpu_min.bak" > "$GPU_DIR/min_freq" 2>/dev/null && echo "  GPU min_freq 已恢复"
    AV="${GPU_DIR}/available_frequencies"
    if [ -f "$AV" ]; then
        MAXF=$(cat "$AV" | tr ' ' '\n' | sort -n | tail -1)
        echo "$MAXF" > "$GPU_DIR/max_freq" 2>/dev/null && echo "  GPU max_freq 已重置为 $MAXF"
    fi
else
    echo "  ⚠ GPU devfreq 未找到，跳过"
fi

# ============================================
# 4. Thermal 恢复
# ============================================
echo "[4] Thermal"
TP="/sys/class/thermal/thermal_pause"
[ -f "$BACKUP/thermal_pause.bak" ] && [ -f "$TP" ] && cat "$BACKUP/thermal_pause.bak" > "$TP" 2>/dev/null && echo "  thermal_pause 已恢复"

# ============================================
# 5. LMK minfree 恢复
# ============================================
echo "[5] LMK minfree"
if [ -f "$BACKUP/lmk_minfree.bak" ]; then
    LMF="/sys/module/lowmemorykiller/parameters/minfree"
    [ -f "$LMF" ] && cat "$BACKUP/lmk_minfree.bak" > "$LMF" 2>/dev/null && echo "  LMK minfree 已恢复"
fi

# ============================================
# 6. VM 参数恢复为系统默认值
# ============================================
echo "[6] VM parameters (defaults)"
echo 60 > /proc/sys/vm/swappiness 2>/dev/null && echo "  swappiness -> 60"
echo 100 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null && echo "  vfs_cache_pressure -> 100"
echo 20 > /proc/sys/vm/dirty_ratio 2>/dev/null && echo "  dirty_ratio -> 20"
echo 10 > /proc/sys/vm/dirty_background_ratio 2>/dev/null && echo "  dirty_background_ratio -> 10"
echo 0 > /proc/sys/vm/laptop_mode 2>/dev/null && echo "  laptop_mode -> 0"
echo 3 > /proc/sys/vm/page-cluster 2>/dev/null && echo "  page-cluster -> 3"

# ============================================
# 7. 系统属性恢复为默认值（不删除）
# ============================================
echo "[7] System properties (default values)"
resetprop persist.sys.power.mode "" 2>/dev/null
resetprop persist.vendor.drv.game_mode 0 2>/dev/null
resetprop persist.vendor.drv.fg.boost 0 2>/dev/null
resetprop persist.vendor.drv.boost 0 2>/dev/null
resetprop sys.miui.ndcd.enable true 2>/dev/null
resetprop debug.miui.disable_vsync false 2>/dev/null
resetprop ro.config.zram.enabled true 2>/dev/null
resetprop window_animation_scale 1.0 2>/dev/null
resetprop transition_animation_scale 1.0 2>/dev/null
resetprop animator_duration_scale 1.0 2>/dev/null
resetprop net.ipv4.tcp_congestion_control cubic 2>/dev/null
resetprop ro.sys.fw.dex2oat_thread_count 2 2>/dev/null
echo "  所有模块设置的属性已重置为默认值（重启后彻底恢复）"

# 关闭 fixed-performance-mode（如果开启过）
if [ "$(getprop ro.build.version.sdk)" -ge 34 ]; then
    cmd power set-fixed-performance-mode-enabled false 2>/dev/null && echo "  fixed-performance-mode 已关闭"
fi

# ============================================
# 8. Shell-level settings 恢复默认值
# ============================================
echo "[8] Shell-level settings (defaults)"
settings put global force_gpu_rendering 0 2>/dev/null
settings put global power_save_mode 1 2>/dev/null
settings put global low_power 0 2>/dev/null
cmd power set-adaptive-power-saving-enabled true 2>/dev/null && echo "  adaptive power saving enabled"
cmd power set-mode 1 2>/dev/null && echo "  power mode set to balanced"
settings put global app_standby_enabled 1 2>/dev/null
settings put system screen_brightness_mode 1 2>/dev/null && echo "  auto brightness enabled"
pm enable com.android.backgrounddexoptjob/.BackgroundDexOptJobService 2>/dev/null && echo "  background dexopt job enabled"
settings put global gpu_renderer_apps "" 2>/dev/null
echo "  Shell-level settings restored"
