#!/system/bin/sh

MODDIR=${0%/*}
BACKUP="$MODDIR/backup"
FLAG="$MODDIR/.applied"

log() { echo "[HyperOS_Perf] $1"; }

# ==================== 等待确认函数 ====================
WAIT_CONFIRM() {
    local reason="$1"
    echo ""
    echo "⚠ 警告：$reason"
    echo "⚠ 操作将修改内核参数和系统属性，可能导致不稳定或发热增加。"
    echo -n "⏳ 5 秒内按取消，倒计时结束会继续执行..."
    for i in 5 4 3 2 1; do
        echo -ne "\r⏳ ${i}s ..."
        sleep 1
    done
    echo -e "\r 等待期结束，继续执行。          "
}

# ==================== 应用优化 ====================
apply() {
    log "开始应用性能优化..."

    # 免 Root Shell 层优化
    settings put global development_settings_enabled 1 2>/dev/null
    settings put global force_gpu_rendering 1 2>/dev/null
    settings put global power_save_mode 0 2>/dev/null
    settings put global low_power 0 2>/dev/null
    cmd power set-adaptive-power-saving-enabled false 2>/dev/null
    cmd power set-mode 0 2>/dev/null
    settings put global app_standby_enabled 0 2>/dev/null
    settings put system screen_off_timeout 1800000 2>/dev/null
    pm disable com.android.backgrounddexoptjob/.BackgroundDexOptJobService 2>/dev/null
    settings put global gpu_renderer_apps "*" 2>/dev/null

    # HyperOS 专有接口（API>=34 时启用）
    if [ "$(getprop ro.build.version.sdk)" -ge 34 ]; then
        cmd power set-fixed-performance-mode-enabled true 2>/dev/null && log "  fixed-performance-mode 已开启"
    fi

    # 环境检查
    SOC=$(getprop ro.board.platform)
    case "$SOC" in
        sm7435*|taro*) log "SoC: $SOC ✓" ;;
        *) log "⚠ SoC='$SOC' 非预期平台" ;;
    esac

    mkdir -p "$BACKUP"

    # 系统修改区块（含等待确认）
    WAIT_CONFIRM "即将修改 CPU/GPU/Thermal/IO 内核参数及系统属性"

    # [1] CPU Governor & 调度
    log "[1] CPU governor & schedutil"
    for c in $(seq 0 3); do
        F="/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_governor"
        [ -f "$F" ] && {
            cat "$F" > "$BACKUP/cpu${c}_gov.bak" 2>/dev/null
            echo "schedutil" > "$F" 2>/dev/null
            echo 5000 > "/sys/devices/system/cpu/cpu${c}/cpufreq/schedutil/rate_limit_us" 2>/dev/null
            echo 0 > "/sys/devices/system/cpu/cpu${c}/cpufreq/schedutil/iowait_boost_enable" 2>/dev/null
        }
    done
    for c in $(seq 4 7); do
        F="/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_governor"
        [ -f "$F" ] && {
            cat "$F" > "$BACKUP/cpu${c}_gov.bak" 2>/dev/null
            if ! echo "performance" > "$F" 2>/dev/null; then
                log "  cpu$c: performance 不可写，改用 schedutil+min=max"
                echo "schedutil" > "$F" 2>/dev/null
                MAXF=$(cat "/sys/devices/system/cpu/cpu${c}/cpufreq/cpuinfo_max_freq" 2>/dev/null)
                echo "$MAXF" > "/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_min_freq" 2>/dev/null
                cat "/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_min_freq" > "$BACKUP/cpu${c}_min.bak" 2>/dev/null
            fi
        }
    done
    echo 1 > /sys/module/cpu_boost/parameters/input_boost_enabled 2>/dev/null
    echo 1 > /sys/module/cpu_boost/parameters/dynamic_stune_boost 2>/dev/null
    echo 80 > /sys/module/cpu_boost/parameters/input_boost_ms 2>/dev/null

    # [2] GPU 提频
    log "[2] GPU min_freq"
    GPU_DIR=""
    for d in /sys/class/devfreq/*; do
        [ -f "$d/governor" ] && grep -q gpu "$d/name" 2>/dev/null && GPU_DIR="$d" && break
    done
    if [ -n "$GPU_DIR" ]; then
        cat "$GPU_DIR/governor" > "$BACKUP/gpu_gov.bak" 2>/dev/null
        cat "$GPU_DIR/min_freq" > "$BACKUP/gpu_min.bak" 2>/dev/null
        echo "performance" > "$GPU_DIR/governor" 2>/dev/null
        AV="${GPU_DIR}/available_frequencies"
        if [ -f "$AV" ]; then
            MAXF=$(cat "$AV" | tr ' ' '\n' | sort -n | tail -1)
            echo "$MAXF" > "$GPU_DIR/min_freq" 2>/dev/null
            echo "$MAXF" > "$GPU_DIR/max_freq" 2>/dev/null
            log "  GPU locked at max freq $MAXF"
        fi
    else
        log "  ⚠ GPU devfreq 未找到，跳过"
    fi

    # [3] Thermal 松绑 + 刷新云控
    log "[3] Thermal pause & refresh cloud control"
    TP="/sys/class/thermal/thermal_pause"
    [ -f "$TP" ] && {
        cat "$TP" > "$BACKUP/thermal_pause.bak" 2>/dev/null
        echo 0 > "$TP" 2>/dev/null
    }
    for n in /sys/class/thermal/thermal_message/*; do
        [ -f "$n/mitigation" ] && echo 0 > "$n/mitigation" 2>/dev/null
    done
    # 刷新 PowerKeeper 云控，防止温控策略回刷
    am broadcast --user 0 -a update_profile \
        com.miui.powerkeeper/com.miui.powerkeeper.cloudcontrol.CloudUpdateReceiver 2>/dev/null

    # [4] I/O 调度
    log "[4] IO scheduler & read-ahead"
    for d in /sys/block/sda/queue/scheduler /sys/block/dm-0/queue/scheduler /sys/block/mmcblk0/queue/scheduler; do
        [ -f "$d" ] && echo mq-deadline > "$d" 2>/dev/null
    done
    for d in /sys/block/sda/queue/read_ahead_kb /sys/block/mmcblk0/queue/read_ahead_kb; do
        [ -f "$d" ] && echo 2048 > "$d" 2>/dev/null
    done
    for q in /sys/block/*/queue; do
        echo 0 > "$q/iostats" 2>/dev/null
        echo 512 > "$q/nr_requests" 2>/dev/null
    done

    # [5] VM & LMK
    log "[5] VM & memory"
    echo 10 > /proc/sys/vm/swappiness 2>/dev/null
    echo 150 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null
    echo 20 > /proc/sys/vm/dirty_ratio 2>/dev/null
    echo 55 > /proc/sys/vm/dirty_background_ratio 2>/dev/null
    echo 0 > /proc/sys/vm/laptop_mode 2>/dev/null
    echo 400 > /proc/sys/vm/page-cluster 2>/dev/null
    if [ -f /sys/module/lowmemorykiller/parameters/minfree ]; then
        cat /sys/module/lowmemorykiller/parameters/minfree > "$BACKUP/lmk_minfree.bak" 2>/dev/null
        echo "18432,23040,27648,32256,55296,80640" > /sys/module/lowmemorykiller/parameters/minfree 2>/dev/null
    fi

    # [6] 显示 & 触控
    log "[6] Display & touch"
    for f in /sys/devices/platform/*/*/fps /sys/class/graphics/fb0/fps; do
        [ -f "$f" ] && echo 90 > "$f" 2>/dev/null  # 稳定90Hz，平衡功耗与流畅
    done
    for t in /sys/devices/virtual/input/*/sampling_rate /sys/class/input/*/sampling_rate; do
        [ -f "$t" ] && echo 360 > "$t" 2>/dev/null  # 适度提高触控采样
    done

    # [7] 系统属性（小米私有通道）
    log "[7] System properties"
    resetprop persist.sys.power.mode extreme 2>/dev/null
    resetprop persist.vendor.drv.game_mode 1 2>/dev/null
    resetprop persist.vendor.drv.fg.boost 1 2>/dev/null
    resetprop persist.vendor.drv.boost 1 2>/dev/null
    resetprop sys.miui.ndcd.enable false 2>/dev/null
    resetprop debug.miui.disable_vsync true 2>/dev/null
    resetprop ro.config.zram.enabled false 2>/dev/null
    resetprop window_animation_scale 0.5 2>/dev/null
    resetprop transition_animation_scale 0.5 2>/dev/null
    resetprop animator_duration_scale 0.75 2>/dev/null
    resetprop net.ipv4.tcp_congestion_control bbr 2>/dev/null
    resetprop ro.sys.fw.dex2oat_thread_count 4 2>/dev/null
    swapoff /dev/block/zram0 2>/dev/null

    log "应用完成。备份位于 $BACKUP"
    touch "$FLAG"
}

# ==================== 还原优化（设置默认值，不删除） ====================
restore() {
    log "开始还原设置（恢复系统默认值）..."

    # [1] CPU governor 从备份恢复
    for c in $(seq 0 7); do
        BF="$BACKUP/cpu${c}_gov.bak"
        if [ -f "$BF" ]; then
            F="/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_governor"
            [ -f "$F" ] && cat "$BF" > "$F" 2>/dev/null
        fi
    done

    # [2] CPU min_freq 从备份恢复
    for c in $(seq 4 7); do
        MBF="$BACKUP/cpu${c}_min.bak"
        if [ -f "$MBF" ]; then
            MF="/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_min_freq"
            [ -f "$MF" ] && cat "$MBF" > "$MF" 2>/dev/null
        fi
    done

    # [3] GPU 从备份恢复
    GPU_DIR=""
    for d in /sys/class/devfreq/*; do
        [ -f "$d/governor" ] && grep -q gpu "$d/name" 2>/dev/null && GPU_DIR="$d" && break
    done
    if [ -n "$GPU_DIR" ]; then
        [ -f "$BACKUP/gpu_gov.bak" ] && cat "$BACKUP/gpu_gov.bak" > "$GPU_DIR/governor" 2>/dev/null
        [ -f "$BACKUP/gpu_min.bak" ] && cat "$BACKUP/gpu_min.bak" > "$GPU_DIR/min_freq" 2>/dev/null
        AV="${GPU_DIR}/available_frequencies"
        if [ -f "$AV" ]; then
            MAXF=$(cat "$AV" | tr ' ' '\n' | sort -n | tail -1)
            echo "$MAXF" > "$GPU_DIR/max_freq" 2>/dev/null
        fi
    fi

    # [4] Thermal 从备份恢复
    TP="/sys/class/thermal/thermal_pause"
    [ -f "$BACKUP/thermal_pause.bak" ] && [ -f "$TP" ] && cat "$BACKUP/thermal_pause.bak" > "$TP" 2>/dev/null

    # [5] LMK 从备份恢复
    if [ -f "$BACKUP/lmk_minfree.bak" ]; then
        LMF="/sys/module/lowmemorykiller/parameters/minfree"
        [ -f "$LMF" ] && cat "$BACKUP/lmk_minfree.bak" > "$LMF" 2>/dev/null
    fi

    # [6] VM 参数恢复默认
    echo 60 > /proc/sys/vm/swappiness 2>/dev/null
    echo 100 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null
    echo 20 > /proc/sys/vm/dirty_ratio 2>/dev/null
    echo 10 > /proc/sys/vm/dirty_background_ratio 2>/dev/null
    echo 0 > /proc/sys/vm/laptop_mode 2>/dev/null
    echo 3 > /proc/sys/vm/page-cluster 2>/dev/null

    # [7] 系统属性恢复为默认值（不删除）
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

    # 关闭 fixed-performance-mode（如果开启过）
    if [ "$(getprop ro.build.version.sdk)" -ge 34 ]; then
        cmd power set-fixed-performance-mode-enabled false 2>/dev/null
    fi

    # [8] Shell-level settings 恢复默认值（不删除）
    settings put global force_gpu_rendering 0 2>/dev/null
    settings put global power_save_mode 1 2>/dev/null
    settings put global low_power 0 2>/dev/null
    cmd power set-adaptive-power-saving-enabled true 2>/dev/null
    cmd power set-mode 1 2>/dev/null
    settings put global app_standby_enabled 1 2>/dev/null
    settings put system screen_brightness_mode 1 2>/dev/null
    pm enable com.android.backgrounddexoptjob/.BackgroundDexOptJobService 2>/dev/null
    settings put global gpu_renderer_apps "" 2>/dev/null

    log "还原完成。部分参数需重启后彻底恢复。"
}

# ==================== 主逻辑 ====================
log "========================================"
log "红米小米性能释放 - Action"
log "AXERON=$AXERON  MODDIR=$MODDIR"
log "========================================"

if [ -f "$FLAG" ]; then
    echo "- 将在5秒后还原设置，如果为误触请立即退出！"
    sleep 5
    restore
    rm -f "$FLAG"
    echo "- 已经还原！"
    sleep 1
    exit 0
else
    echo "- 应用参数"
    apply
    echo "✓ 完成"
    sleep 1
    exit 0
fi
