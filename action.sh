#!/system/bin/sh
# AxManager 免Root 插件 - Redmi Note 14 Pro+ 性能释放 (v2)
# 所有系统修改合并为一个块，只弹一次警告

MODDIR=${0%/*}
BACKUP="$MODDIR/backup"

# ===== 等待期函数（全局） =====
WAIT_CONFIRM() {
    local reason="$1"
    echo ""
    echo "⚠ 警告：$reason"
    echo "⚠ 当前操作将修改内核参数和系统属性，可能导致不稳定或发热增加。"
    echo -n "⏳ 5 秒内按取消，倒计时结束会继续执行..."
    local i
    for i in 5 4 3 2 1; do
        echo -ne "\r⏳ ${i}s ..."
        sleep 1
    done
    echo -e "\r 等待期结束，继续执行。          "
}

UI_PRINT() { echo "[Note14P+_Perf] $1"; }

UI_PRINT "========================================"
UI_PRINT "Note14P+ Perf Tweak - Action"
UI_PRINT "AXERON=$AXERON  MODDIR=$MODDIR"
UI_PRINT "========================================"

# ----------------------------------------------------------
# [0] 免 Root Shell 层性能优化（settings / cmd / pm）
# ----------------------------------------------------------
UI_PRINT "[Wait] 开始免root优化 (no root)"

# 启用开发者选项（确保 settings 修改生效）
settings put global development_settings_enabled 1 2>/dev/null

# 强制全局 GPU 渲染
settings put global force_gpu_rendering 1 2>/dev/null

# 关闭省电模式（不影响电池百分比）
settings put global power_save_mode 0 2>/dev/null
settings put global low_power 0 2>/dev/null

# 禁用自适应省电
cmd power set-adaptive-power-saving-enabled false 2>/dev/null

# 设置性能模式（部分 MIUI/HyperOS 支持）
cmd power set-mode 0 2>/dev/null   # 0=高性能, 1=均衡, 2=省电

# 关闭触摸显示（省电+减少干扰）
settings put global show_touches 0 2>/dev/null
settings put global pointer_location 0 2>/dev/null

# 关闭严格模式（调试用，释放性能）
settings put global strict_mode_enabled 0 2>/dev/null

# 强制 4x MSAA（GPU 渲染质量，视情况可选）
settings put global multisampling_enabled 1 2>/dev/null

# 禁用背景检查（减少 App Standby 限制）
settings put global app_standby_enabled 0 2>/dev/null

# 设置屏幕超时为 30 分钟（防止频繁休眠唤醒）
settings put system screen_off_timeout 1800000 2>/dev/null

# 提高触控灵敏度（指针速度 7 已在后面 prop 中设置，此处再用 settings 冗余加固）
settings put system pointer_speed 7 2>/dev/null

# 禁用所有应用的 dex2oat 后台优化（释放 CPU）
pm disable com.android.backgrounddexoptjob/.BackgroundDexOptJobService 2>/dev/null

# 强制 GPU 渲染列表（白名单所有应用）
settings put global gpu_renderer_apps "*" 2>/dev/null

# ---- 快速环境检查（不弹窗，仅打印） ----
if [ "$AXERON" != "true" ]; then
    UI_PRINT "⚠ AXERON!='true'，未在 AxManager 托管下运行"
fi
SOC=$(getprop ro.board.platform)
case "$SOC" in
    sm7435*|taro*) UI_PRINT "SoC: $SOC ✓" ;;
    *) UI_PRINT "⚠ SoC='$SOC' 非 sm7435，大核路径可能不同" ;;
esac

# ---- 准备备份目录 ----
mkdir -p "$BACKUP"

# ============================================================
#  系统修改区块（内核参数 + 系统属性）
#  在此区块前统一弹一次警告
# ============================================================
WAIT_CONFIRM "即将修改 CPU/GPU/Thermal/IO 内核参数及大量系统属性"

UI_PRINT "----- 开始系统修改 -----"

# ----------------------------------------------------------
# 1. CPU Governor & 调度参数
# ----------------------------------------------------------
UI_PRINT "[1] CPU governor & schedutil"

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
            UI_PRINT "  cpu$c: performance 不可写，改用 schedutil+min=max"
            echo "schedutil" > "$F" 2>/dev/null
            MAXF=$(cat "/sys/devices/system/cpu/cpu${c}/cpufreq/cpuinfo_max_freq" 2>/dev/null)
            echo "$MAXF" > "/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_min_freq" 2>/dev/null
            cat "/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_min_freq" > "$BACKUP/cpu${c}_min.bak" 2>/dev/null
        fi
    }
done

# 开启 CPU boost
echo 1 > /sys/module/cpu_boost/parameters/input_boost_enabled 2>/dev/null
echo 1 > /sys/module/cpu_boost/parameters/dynamic_stune_boost 2>/dev/null
echo 50 > /sys/module/cpu_boost/parameters/input_boost_ms 2>/dev/null

# ----------------------------------------------------------
# 2. GPU 提频
# ----------------------------------------------------------
UI_PRINT "[2] GPU min_freq"
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
        UI_PRINT "  GPU locked at max freq $MAXF"
    fi
else
    UI_PRINT "  ⚠ GPU devfreq 未找到，跳过"
fi

# ----------------------------------------------------------
# 3. Thermal 松绑
# ----------------------------------------------------------
UI_PRINT "[3] Thermal pause"
TP="/sys/class/thermal/thermal_pause"
if [ -f "$TP" ]; then
    cat "$TP" > "$BACKUP/thermal_pause.bak" 2>/dev/null
    echo 0 > "$TP" 2>/dev/null
fi
# 额外：关闭 thermal throttling（如果节点存在）
for n in /sys/class/thermal/thermal_message/*; do
    [ -f "$n/mitigation" ] && echo 0 > "$n/mitigation" 2>/dev/null
done

# ----------------------------------------------------------
# 4. I/O 调度 & read_ahead
# ----------------------------------------------------------
UI_PRINT "[4] IO scheduler & read-ahead"
for d in /sys/block/sda/queue/scheduler /sys/block/dm-0/queue/scheduler /sys/block/mmcblk0/queue/scheduler; do
    [ -f "$d" ] && echo mq-deadline > "$d" 2>/dev/null
done
for d in /sys/block/sda/queue/read_ahead_kb /sys/block/mmcblk0/queue/read_ahead_kb; do
    [ -f "$d" ] && echo 4096 > "$d" 2>/dev/null
done
# 降低 IO 延迟
for q in /sys/block/*/queue; do
    echo 0 > "$q/iostats" 2>/dev/null
    echo 256 > "$q/nr_requests" 2>/dev/null
done

# ----------------------------------------------------------
# 5. VM & LMK 参数
# ----------------------------------------------------------
UI_PRINT "[5] VM & memory"
echo 10 > /proc/sys/vm/swappiness 2>/dev/null
echo 200 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null
echo 20 > /proc/sys/vm/dirty_ratio 2>/dev/null
echo 60 > /proc/sys/vm/dirty_background_ratio 2>/dev/null
echo 0 > /proc/sys/vm/laptop_mode 2>/dev/null
echo 300 > /proc/sys/vm/page-cluster 2>/dev/null
# LMK（低内存杀手）调宽松
if [ -f /sys/module/lowmemorykiller/parameters/minfree ]; then
    cat /sys/module/lowmemorykiller/parameters/minfree > "$BACKUP/lmk_minfree.bak" 2>/dev/null
    echo "18432,23040,27648,32256,55296,80640" > /sys/module/lowmemorykiller/parameters/minfree 2>/dev/null
fi

# ----------------------------------------------------------
# 6. 显示刷新率 & 触控
# ----------------------------------------------------------
UI_PRINT "[6] Display & touch"
# 强制最高刷新率（可能需要对应面板节点）
for f in /sys/devices/platform/*/*/fps /sys/class/graphics/fb0/fps; do
    [ -f "$f" ] && echo 120 > "$f" 2>/dev/null
done
# 触控采样率提升
for t in /sys/devices/virtual/input/*/sampling_rate /sys/class/input/*/sampling_rate; do
    [ -f "$t" ] && echo 480 > "$t" 2>/dev/null
done

# ----------------------------------------------------------
# 7. 系统属性（setprop / resetprop）全部合并于此
# ----------------------------------------------------------
UI_PRINT "[7] System properties (setprop/resetprop)"

# 禁用小米性能调度
resetprop --delete persist.sys.perf.profile 2>/dev/null
resetprop persist.vendor.drv.game_mode 1 2>/dev/null
resetprop persist.vendor.drv.fg.boost 1 2>/dev/null
resetprop persist.vendor.drv.boost 1 2>/dev/null
resetprop sys.miui.ndcd.enable false 2>/dev/null
resetprop debug.miui.disable_vsync true 2>/dev/null

# 强制 GPU 渲染
resetprop debug.hwui.renderer skiagl 2>/dev/null
resetprop debug.composition.type gpu 2>/dev/null
resetprop hwui.use_vulkan 1 2>/dev/null

# 动画加速
resetprop window_animation_scale 0.25 2>/dev/null
resetprop transition_animation_scale 0.25 2>/dev/null
resetprop animator_duration_scale 0.35 2>/dev/null

# 网络优化
resetprop net.tcp.default_init_rwnd 128 2>/dev/null
resetprop net.ipv4.tcp_congestion_control bbr 2>/dev/null
resetprop net.core.rmem_default 262144 2>/dev/null
resetprop net.core.wmem_default 65536 2>/dev/null

# 禁用 zRAM（节省 CPU 解压缩开销）
resetprop ro.config.zram.enabled false 2>/dev/null
swapoff /dev/block/zram0 2>/dev/null

# 触控响应优化
resetprop persist.sys.pointer_speed 7 2>/dev/null
resetprop debug.egl.hw 1 2>/dev/null
resetprop debug.sf.hw 1 2>/dev/null

# 其他
resetprop persist.sys.ui.hw 1 2>/dev/null
resetprop video.accelerate.hw 1 2>/dev/null
resetprop ro.sys.fw.dex2oat_thread_count 4 2>/dev/null

UI_PRINT "----- 系统修改完成 -----"

UI_PRINT "========================================"
UI_PRINT "Action 执行完毕。备份位于 $BACKUP"
UI_PRINT "建议重启或 Reignite 使 server.sh 持续防回刷"