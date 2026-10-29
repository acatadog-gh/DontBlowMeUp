#!/bin/zsh
# 双击运行：用 Godot 编辑器打开本工程
cd "$(dirname "$0")/../.." || exit 1
. tools/mac/_godot.sh
godot_or_die
ensure_imported
echo "工程：$(pwd)"
echo "打开编辑器…"
exec "$GODOT" --path . -e
