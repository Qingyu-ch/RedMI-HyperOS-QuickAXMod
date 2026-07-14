#!/system/bin/sh
#!/system/bin/sh
# AxManager 免Root 插件 - Redmi Note 14 Pro+ 性能释放
# 触发：UI 点 Action

MODDIR=${0%/*}
BACKUP="$MODDIR/backup"
UI_PRINT() { echo "[Note14P+_Perf] $1"; }

UI_PRINT "========================================"
UI_PRINT "Note 14 Pro+ Perf Tweak - Action"
UI_PRINT "AXERON=$AXERON  MODDIR=$MODDIR"
UI_PRINT "========================================"

# ---- 环境检查 ----
if [ "$AXERON" != "true" ]; then
    UI_PRINT "⚠ Not running under AxManager, abort"
    exit 1
fi

# Note14P+ sm7435 粗略校验（可选）
SOC=$(getprop ro.board.platform)
case "$SOC" in
    sm7435*|taro*) UI_PRINT "SoC: $SOC ✓" ;;
    *) UI_PRINT "⚠ SoC=$SOC, expected sm7435, continue anyway" ;;
esac

# ---- 备份目录 ----
mkdir -p "$BACKUP"

# =============================================
# 1. CPU 大核(cpu4-7) 锁 performance governor
#    小核(cpu0-3) 用 schedutil 但拉激进
# =============================================
UI_PRINT "[1/6] CPU governor & schedutil"

for c in $(seq 0 3); do
    # 小核 A520 → schedutil
    F="/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_governor"
    [ -f "$F" ] && {
        cat "$F" > "$BACKUP/cpu${c}_gov.bak" 2>/dev/null
        echo "schedutil" > "$F" 2>/dev/null
        # schedutil 激进参数
        echo 10000 > "/sys/devices/system/cpu/cpu${c}/cpufreq/schedutil/rate_limit_us" 2>/dev/null
    }
done

for c in $(seq 4 7); do
    # 大核 A720 → performance（免root 下若写不进就降级 schedutil + min=max）
    F="/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_governor"
    [ -f "$F" ] && {
        cat "$F" > "$BACKUP/cpu${c}_gov.bak" 2>/dev/null
        if ! echo "performance" > "$F" 2>/dev/null; then
            UI_PRINT "  cpu$c: performance 不可写，改用 schedutil+min_freq 顶满"
            echo "schedutil" > "$F" 2>/dev/null
            MAXF=$(cat "/sys/devices/system/cpu/cpu${c}/cpufreq/cpuinfo_max_freq" 2>/dev/null)
            echo "$MAXF" > "/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_min_freq" 2>/dev/null
        fi
    }
done

# =============================================
# 2. GPU devfreq 提 min_freq (Adreno 810?)
# =============================================
UI_PRINT "[2/6] GPU min_freq"
GPU_DIR=""
for d in /sys/class/devfreq/*; do
    [ -f "$d/governor" ] && grep -q gpu "$d/name" 2>/dev/null && GPU_DIR="$d" && break
done
if [ -n "$GPU_DIR" ]; then
    cat "$GPU_DIR/governor" > "$BACKUP/gpu_gov.bak" 2>/dev/null
    cat "$GPU_DIR/min_freq" > "$BACKUP/gpu_min.bak" 2>/dev/null
    echo "simple_ondemand" > "$GPU_DIR/governor" 2>/dev/null
    # 提 min 到 avail_freq 次高（不顶满防过热）
    AV="${GPU_DIR}/available_frequencies"
    if [ -f "$AV" ]; then
        MIN=$(cat "$AV" | tr ' ' '\n' | sort -n | tail -2 | head -1)
        echo "$MIN" > "$GPU_DIR/min_freq" 2>/dev/null
        UI_PRINT "  GPU min set to $MIN"
    fi
else
    UI_PRINT "  GPU devfreq not found, skip"
fi

# =============================================
# 3. Thermal 松绑（HyperOS thermal_pause）
# =============================================
UI_PRINT "[3/6] Thermal pause"
TP="/sys/class/thermal/thermal_pause"
if [ -f "$TP" ]; then
    cat "$TP" > "$BACKUP/thermal_pause.bak" 2>/dev/null
    echo 0 > "$TP" 2>/dev/null && UI_PRINT "  thermal_pause=0 ✓"
else
    UI_PRINT "  thermal_pause node not found, skip"
fi

# =============================================
# 4. IO scheduler → mq-deadline
# =============================================
UI_PRINT "[4/6] IO scheduler"
for d in /sys/block/sda/queue/scheduler /sys/block/dm-0/queue/scheduler /sys/block/mmcblk0/queue/scheduler; do
    [ -f "$d" ] && {
        cat "$d" > "$BACKUP/$(basename $(dirname $(dirname $d)))_sched.bak" 2>/dev/null
        echo mq-deadline > "$d" 2>/dev/null
    }
done

# =============================================
# 5. read_ahead_kb 提一点
# =============================================
UI_PRINT "[5/6] Read-ahead"
for d in /sys/block/sda/queue/read_ahead_kb /sys/block/mmcblk0/queue/read_ahead_kb; do
    [ -f "$d" ] && echo 2048 > "$d" 2>/dev/null
done

# =============================================
# 6. 小米调度相关 prop (resetprop)
# =============================================
UI_PRINT "[6/6] Props"
resetprop --delete persist.sys.perf.profile 2>/dev/null
resetprop persist.vendor.drv.game_mode 1 2>/dev/null
resetprop persist.vendor.drv.fg.boost 1 2>/dev/null

UI_PRINT "========================================"
UI_PRINT "Action done. Reboot or Re-ignite to persist via service.sh"
UI_PRINT "Backup @ $BACKUP"