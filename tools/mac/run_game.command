#!/bin/zsh
# 双击运行：热座版（同屏轮流操作）
# 也可以命令行跑： ./tools/mac/run_game.command
cd "$(dirname "$0")/../.." || exit 1
. tools/mac/_godot.sh
godot_or_die
ensure_imported
echo "工程：$(pwd)"
echo "Godot：$("$GODOT" --version 2>/dev/null)"
echo "启动热座版…（关窗口即退出）"
exec "$GODOT" --path . res://scenes/main.tscn
