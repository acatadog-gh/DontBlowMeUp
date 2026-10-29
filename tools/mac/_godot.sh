#!/bin/sh
# ============================================================
#  _godot.sh —— 定位 Godot 4.x，被 tools/mac/*.command 用 `.` 引入
#  查找顺序：
#    1. 环境变量 GODOT_BIN
#    2. /Applications/Godot.app、~/Applications/Godot*.app
#    3. Homebrew: /opt/homebrew/bin/godot、/usr/local/bin/godot
#    4. PATH 里的 godot / godot4
#  成功后设置 $GODOT；找不到调用 godot_or_die 退出。
# ============================================================
find_godot() {
	if [ -n "${GODOT_BIN:-}" ] && [ -x "$GODOT_BIN" ]; then
		GODOT="$GODOT_BIN"
		return 0
	fi
	for candidate in \
		"/Applications/Godot.app/Contents/MacOS/Godot" \
		"$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
		"/opt/homebrew/bin/godot" \
		"/usr/local/bin/godot"; do
		if [ -x "$candidate" ]; then
			GODOT="$candidate"
			return 0
		fi
	done
	for app in /Applications/Godot*.app "$HOME"/Applications/Godot*.app; do
		if [ -x "$app/Contents/MacOS/Godot" ]; then
			GODOT="$app/Contents/MacOS/Godot"
			return 0
		fi
	done
	for name in godot godot4 Godot; do
		if command -v "$name" >/dev/null 2>&1; then
			GODOT="$(command -v "$name")"
			return 0
		fi
	done
	return 1
}

godot_or_die() {
	find_godot && return 0
	echo "❌ 找不到 Godot 4.x。任一办法即可："
	echo "   1) 把 Godot.app 拖到 /Applications"
	echo "   2) export GODOT_BIN=/路径/Godot"
	echo "   3) 把 godot 加进 PATH（brew install --cask godot）"
	exit 1
}

# 首次运行（没有 .godot 缓存）时导入一次，否则脚本模式跑不起来
ensure_imported() {
	[ -d .godot ] && return 0
	echo "首次运行：导入工程资源（约 10 秒）…"
	"$GODOT" --headless --path . --import >/dev/null 2>&1
}
