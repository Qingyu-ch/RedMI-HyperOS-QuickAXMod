#!/system/bin/sh
# AxManager 免Root 插件 - Note14P+ Perf
# customize.sh: 装前校验 + 初始化，不匹配则中文警告+5秒等待

WAIT_CONFIRM() {
    local reason="$1"
    echo ""
    echo "⚠ 警告：$reason"
    echo "⚠ 当前环境可能不兼容此模块，继续安装后果自负。"
    echo -n "⏳ 5 秒内取消，之后会继续安装..."
    local i
    for i in 5 4 3 2 1; do
        echo -ne "\r⏳ ${i}s 内未按消，将会继续安装..."
        sleep 1
    done
    echo -e "\r✓ 等待期结束，继续安装。          "
}

echo "========================================"
echo "AXERON=$AXERON  AXERONVER=$AXERONVER"
echo "MODPATH=$MODPATH"
echo "ARCH=$ARCH  API=$API"
echo "========================================"

# ---- 2. 架构 ----
if [ "$IS64BIT" != "true" ]; then
    WAIT_CONFIRM "当前设备非 arm64，模块未测试"
fi

# ---- 4. Android 版本 ----
if [ "$API" -lt 34 ] 2>/dev/null; then
    WAIT_CONFIRM "Android API=$API (<34)，可能出现节点不存在"
fi

# ---- 5. SoC 校验 ----
SOC=$(getprop ro.board.platform)
case "$SOC" in
    sm7435*)
        echo "✓ SoC: $SOC (骁龙7s Gen3)"
        ;;
    *)
        WAIT_CONFIRM "SoC='$SOC'，其他平台大核路径/频率可能不同"
        ;;
esac

# ---- 6. 设备代号 ----
DEVICE=$(getprop ro.product.device)
case "$DEVICE" in
    bamboo*|Bamboo*)
        echo "✓ Device: $DEVICE"
        ;;
    "")
        WAIT_CONFIRM "无法读取 ro.product.device"
        ;;
    *)
        WAIT_CONFIRM "Device='$DEVICE'"
        ;;
esac

# ---- 7. 初始化 backup ----
echo "[init] 创建 backup 目录并预读节点原始值"
mkdir -p "$MODPATH/backup"

for c in $(seq 0 7); do
    F="/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_governor"
    BF="$MODPATH/backup/cpu${c}_gov.bak"
    [ -f "$F" ] && [ ! -f "$BF" ] && cat "$F" > "$BF" 2>/dev/null
done

TP="/sys/class/thermal/thermal_pause"
[ -f "$TP" ] && [ ! -f "$MODPATH/backup/thermal_pause.bak" ] \
    && cat "$TP" > "$MODPATH/backup/thermal_pause.bak" 2>/dev/null
