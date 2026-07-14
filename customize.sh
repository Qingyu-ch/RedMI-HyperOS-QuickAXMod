#!/system/bin/sh
#!/system/bin/sh
# AxManager 免Root 插件 - Note14P+ Perf
# customize.sh: 被 installer source，做设备校验 + 初始化
# 不要用 MODDIR=${0%/*}，这里用 MODPATH

ui_print "========================================"
ui_print "Note14P+ Perf - customize.sh"
ui_print "AXERON=$AXERON  AXERONVER=$AXERONVER"
ui_print "MODPATH=$MODPATH"
ui_print "ARCH=$ARCH  API=$API"
ui_print "========================================"

# ---- 1. 基础环境 ----
if [ "$AXERON" != "true" ]; then
    ui_print "✗ Not running under AxManager"
    abort
fi

if [ "$IS64BIT" != "true" ]; then
    ui_print "✗ Only arm64 device supported"
    abort
fi

# ---- 2. AxManager 版本对齐（module.prop 里 axeronPlugin=10400 的话，这里至少也要 10400）----
MIN_AXV=10400
if [ "$AXERONVER" -lt "$MIN_AXV" ] 2>/dev/null; then
    ui_print "✗ AxManager server $AXERONVER < required $MIN_AXV"
    ui_print "  Update AxManager and try again"
    abort
fi

# ---- 3. Android 版本（HyperOS 基于 A14+，API≥34）----
if [ "$API" -lt 34 ] 2>/dev/null; then
    ui_print "⚠ API=$API (<34), HyperOS expected, continue anyway"
fi

# ---- 4. SoC 校验（Note14P+ = sm7435, 海外版 maybe 同）----
SOC=$(getprop ro.board.platform)
case "$SOC" in
    sm7435*)
        ui_print "✓ SoC: $SOC (snapdragon 7s Gen3)"
        ;;
    *)
        ui_print "✗ SoC=$SOC, this module targets sm7435 (Note14P+)"
        ui_print "  If you know what you're doing, remove this check."
        abort
        ;;
esac

# ---- 5. 设备代号辅助校验（Note14P+ 国内 bamboo，海外 maybe 不同，宽松处理）----
DEVICE=$(getprop ro.product.device)
case "$DEVICE" in
    bamboo*|Bamboo*|"")
        ui_print "✓ Device: $DEVICE"
        ;;
    *)
        ui_print "⚠ Device=$DEVICE, expected 'bamboo' (Note14P+), continue"
        ;;
esac

# ---- 6. 初始化 backup 目录 + 预读关键节点（让 uninstall 即使没点过 Action 也有 bak 可回滚）----
ui_print "[init] Creating backup dir & pre-reading nodes"

mkdir -p "$MODPATH/backup"

# CPU governor 初始值
for c in $(seq 0 7); do
    F="/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_governor"
    BF="$MODPATH/backup/cpu${c}_gov.bak"
    if [ -f "$F" ] && [ ! -f "$BF" ]; then
        cat "$F" > "$BF" 2>/dev/null
    fi
done

# Thermal pause
TP="/sys/class/thermal/thermal_pause"
if [ -f "$TP" ] && [ ! -f "$MODPATH/backup/thermal_pause.bak" ]; then
    cat "$TP" > "$MODPATH/backup/thermal_pause.bak" 2>/dev/null
fi

# ---- 7. system/bin 下如果有自制二进制，在这里 set_perm ----
# 例：如果塞了个自己编译的 tweak_tool 到 system/bin/
# set_perm 0755 root shell "$MODPATH/system/bin/tweak_tool"
# 目前纯 sh 模块不需要，留着当模板

ui_print "========================================"
ui_print "customize.sh done. Install proceed."

echo "- 刷入完成"