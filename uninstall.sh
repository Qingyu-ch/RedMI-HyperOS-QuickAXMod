#!/system/bin/sh
# AxManager 免Root 插件 - Note14P+ Perf Uninstall
# 回滚所有系统修改至默认状态

MODDIR=${0%/*}
BACKUP="$MODDIR/backup"

WAIT_CONFIRM() {
    local reason="$1"
    echo ""
    echo "⚠ 警告：$reason"
    echo "⚠ 即将恢复系统默认参数，5 秒后开始回滚..."
    local i
    for i in 5 4 3 2 1; do
        echo -ne "\r⏳ ${i}s 后开始回滚，可取消..."
        sleep 1
    done
    echo -e "\r开始回滚。          "
}

echo "========================================"
echo "[Note14P+_Perf] Uninstall - 开始回滚"
echo "MODDIR=$MODDIR"
echo "========================================"

# ---- 环境检查（仅打印，不弹窗） ----
if [ "$AXERON" != "true" ]; then
    echo "⚠ AXERON!='true'，部分操作可能受限"
fi

# ---- 检查 backup 目录 ----
if [ ! -d "$BACKUP" ]; then
    WAIT_CONFIRM "backup 目录不存在，可能从未执行过 Action，将跳过备份恢复，仅重置 VM 和属性"
else
    WAIT_CONFIRM "即将从 backup 恢复节点，并重置 VM/属性至默认"
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
        if [ -f "$F" ]; then
            echo "$(cat "$BF")" > "$F" 2>/dev/null && echo "  cpu$c governor 已恢复"
        else
            echo "  ⚠ cpu$c governor 节点不存在，跳过"
        fi
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
        if [ -f "$MF" ]; then
            echo "$(cat "$MBF")" > "$MF" 2>/dev/null && echo "  cpu$c min_freq 已恢复"
        fi
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
    if [ -f "$BACKUP/gpu_gov.bak" ]; then
        echo "$(cat "$BACKUP/gpu_gov.bak")" > "$GPU_DIR/governor" 2>/dev/null && echo "  GPU governor 已恢复"
    fi
    if [ -f "$BACKUP/gpu_min.bak" ]; then
        echo "$(cat "$BACKUP/gpu_min.bak")" > "$GPU_DIR/min_freq" 2>/dev/null && echo "  GPU min_freq 已恢复"
    fi
    # max_freq 未备份，恢复为 available_frequencies 最大值（通常就是默认）
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
if [ -f "$BACKUP/thermal_pause.bak" ]; then
    if [ -f "$TP" ]; then
        cat "$BACKUP/thermal_pause.bak" > "$TP" 2>/dev/null && echo "  thermal_pause 已恢复"
    else
        echo "  ⚠ thermal_pause 节点不存在，跳过"
    fi
fi
# thermal_message/mitigation 未备份，无需恢复

# ============================================
# 5. LMK minfree 恢复
# ============================================
echo "[5] LMK minfree"
if [ -f "$BACKUP/lmk_minfree.bak" ]; then
    LMF="/sys/module/lowmemorykiller/parameters/minfree"
    if [ -f "$LMF" ]; then
        cat "$BACKUP/lmk_minfree.bak" > "$LMF" 2>/dev/null && echo "  LMK minfree 已恢复"
    else
        echo "  ⚠ LMK minfree 节点不存在，跳过"
    fi
fi

# ============================================
# 6. VM 参数恢复为系统默认值（无备份，写死）
# ============================================
echo "[6] VM parameters (defaults)"
echo 60 > /proc/sys/vm/swappiness 2>/dev/null && echo "  swappiness -> 60"
echo 100 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null && echo "  vfs_cache_pressure -> 100"
echo 20 > /proc/sys/vm/dirty_ratio 2>/dev/null && echo "  dirty_ratio -> 20"
echo 10 > /proc/sys/vm/dirty_background_ratio 2>/dev/null && echo "  dirty_background_ratio -> 10"
echo 0 > /proc/sys/vm/laptop_mode 2>/dev/null && echo "  laptop_mode -> 0"
echo 3 > /proc/sys/vm/page-cluster 2>/dev/null && echo "  page-cluster -> 3"

# ============================================
# 7. 清除所有由本模块设置的 resetprop 属性
# ============================================
echo "[7] Reset properties (delete all set by module)"
PROPS_TO_DELETE="
persist.sys.perf.profile
persist.vendor.drv.game_mode
persist.vendor.drv.fg.boost
persist.vendor.drv.boost
sys.miui.ndcd.enable
debug.miui.disable_vsync
debug.hwui.renderer
debug.composition.type
hwui.use_vulkan
window_animation_scale
transition_animation_scale
animator_duration_scale
net.tcp.default_init_rwnd
net.ipv4.tcp_congestion_control
net.core.rmem_default
net.core.wmem_default
ro.config.zram.enabled
persist.sys.pointer_speed
debug.egl.hw
debug.sf.hw
persist.sys.ui.hw
video.accelerate.hw
ro.sys.fw.dex2oat_thread_count
"

for prop in $PROPS_TO_DELETE; do
    resetprop --delete "$prop" 2>/dev/null
done
echo "  所有模块设置的属性已删除（重启后彻底恢复）"

# ============================================
# 8. 其他未备份的修改（IO、显示、触控等）无法精确恢复，给出提示
# ============================================
echo ""
echo "⚠ 以下修改因未备份原始值，未恢复："
echo "  - IO scheduler (已改为 mq-deadline)"
echo "  - read_ahead_kb (已改为 4096)"
echo "  - IO stats (已关闭) / nr_requests (256)"
echo "  - 显示刷新率 (已设为 120)"
echo "  - 触控采样率 (已设为 480)"
echo "  这些参数重启后会自动恢复系统默认，无需担心。"

echo ""
echo "========================================"
echo "[Note14P+_Perf] Uninstall 回滚完成"