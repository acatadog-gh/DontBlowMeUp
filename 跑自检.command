#!/bin/zsh
# 《别炸我！》一键自检：热座逻辑 + 联机逻辑 + UI 回归 + 端到端冒烟
# 用法：从 Finder 双击本文件。改完代码跑一遍，看最后的汇总是否全绿。
cd "$(dirname "$0")" || exit 1

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
[ -x "$GODOT" ] || GODOT="$(command -v godot 2>/dev/null)"
if [ ! -x "$GODOT" ]; then
	echo "❌ 找不到 Godot：请确认 /Applications/Godot.app 存在，或把 godot 加入 PATH"
	exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SMOKE_PORT=8933

echo "Godot：$("$GODOT" --version 2>/dev/null)"
echo

# ---- 1/4 热座逻辑（期望 77 PASS）----
echo "── 1/4 热座逻辑自检 ──"
"$GODOT" --headless --path . -s tests/run_tests.gd >"$TMP/hotseat.log" 2>&1
P1=$(grep -c "PASS" "$TMP/hotseat.log")
F1=$(grep -c "FAIL" "$TMP/hotseat.log")
echo "   PASS $P1 ｜ FAIL $F1（期望 PASS 77 / FAIL 0）"
[ "$F1" -gt 0 ] && grep "FAIL" "$TMP/hotseat.log" | head -10

# ---- 2/4 联机逻辑（期望 32 通过）----
echo "── 2/4 联机逻辑自检 ──"
"$GODOT" --headless --path . -s tests/test_online_logic.gd >"$TMP/online.log" 2>&1
# 结论行形如「逻辑自检：24 通过，0 失败」，别抓末尾的资源泄漏日志
SUMMARY=$(grep "逻辑自检：" "$TMP/online.log" | tail -1)
echo "   ${SUMMARY:-（没找到结论行，看 $TMP/online.log）}（期望 32 通过 / 0 失败）"
P2=$(echo "$SUMMARY" | grep -oE "[0-9]+ 通过" | grep -oE "[0-9]+"); P2=${P2:-0}
F2=$(echo "$SUMMARY" | grep -oE "[0-9]+ 失败" | grep -oE "[0-9]+"); F2=${F2:-0}
[ "$F2" -gt 0 ] && grep "FAIL" "$TMP/online.log" | head -10

# ---- 3/4 UI 回归（手牌展示 + 动作演出，期望 18 通过）----
echo "── 3/4 UI 回归（手牌布局/悬停让位/全览面板/动作演出）──"
"$GODOT" --headless --path . -s tests/test_hand_ui.gd >"$TMP/ui.log" 2>&1
SUMMARY4=$(grep "逻辑自检：" "$TMP/ui.log" | tail -1)
echo "   ${SUMMARY4:-（没找到结论行，看 $TMP/ui.log）}（期望 18 通过 / 0 失败）"
P4=$(echo "$SUMMARY4" | grep -oE "[0-9]+ 通过" | grep -oE "[0-9]+"); P4=${P4:-0}
F4=$(echo "$SUMMARY4" | grep -oE "[0-9]+ 失败" | grep -oE "[0-9]+"); F4=${F4:-0}
[ "$F4" -gt 0 ] && grep "FAIL" "$TMP/ui.log" | head -10

# ---- 4/4 端到端冒烟（临时起 8933 服务器，跑完自动关）----
echo "── 4/4 端到端冒烟（两个机器人打完整局）──"
if lsof -ti "tcp:$SMOKE_PORT" >/dev/null 2>&1; then
	echo "   ⚠  端口 $SMOKE_PORT 已被占用，跳过冒烟"
	P3=0; F3=0; SKIPPED=1
else
	"$GODOT" --headless --path . -s scripts/server/server_main.gd -- "port=$SMOKE_PORT" \
		>"$TMP/server.log" 2>&1 &
	SRV=$!
	sleep 2
	"$GODOT" --headless --path . -s tests/smoke_online.gd >"$TMP/smoke.log" 2>&1
	kill "$SRV" 2>/dev/null
	P3=$(grep -c "^PASS" "$TMP/smoke.log")
	F3=$(grep -c "FAIL" "$TMP/smoke.log")
	grep "^PASS" "$TMP/smoke.log" | head -4 | sed 's/^/   /'
	[ "$F3" -gt 0 ] && grep "FAIL" "$TMP/smoke.log" | head -10
fi

echo
echo "════════ 汇总 ════════"
echo "   热座逻辑  ：PASS $P1 / FAIL $F1   （基线 77 / 0）"
echo "   联机逻辑  ：PASS $P2 / FAIL $F2   （基线 32 / 0）"
echo "   UI 回归   ：PASS $P4 / FAIL $F4   （基线 18 / 0）"
if [ -n "$SKIPPED" ]; then
	echo "   端到端冒烟：已跳过（端口占用）"
else
	echo "   端到端冒烟：PASS $P3 / FAIL $F3   （基线 ≥2 / 0）"
fi

if [ "$F1" -eq 0 ] && [ "$F2" -eq 0 ] && [ "${F3:-0}" -eq 0 ] && [ "$F4" -eq 0 ] && [ "$P1" -eq 77 ] && [ "$P2" -eq 32 ] && [ "$P4" -eq 18 ]; then
	echo "   ✅ 全绿，可以导出发布"
else
	echo "   ❌ 有失败项，看上面的 FAIL 行"
fi
echo
echo "按回车关闭本窗口…"
read -r _
