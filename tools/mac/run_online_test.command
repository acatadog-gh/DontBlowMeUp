#!/bin/zsh
# 双击运行：一键联机测试 —— 起服务器 + 开两个客户端
# 端口已被占用时会复用现有服务器（要重启就先关掉它的终端窗口）
cd "$(dirname "$0")/../.." || exit 1
. tools/mac/_godot.sh
godot_or_die
ensure_imported

PORT=8920
echo "工程：$(pwd)"
echo "Godot：$("$GODOT" --version 2>/dev/null)"
echo

if lsof -ti "tcp:$PORT" >/dev/null 2>&1; then
	echo "⚠  端口 $PORT 已在监听，复用现有服务器（要重启请先关掉它的终端窗口）"
else
	echo "启动服务器 ws://127.0.0.1:$PORT（另开一个终端窗口显示日志）…"
	osascript -e "tell application \"Terminal\" to do script \"cd '$PWD' && '$GODOT' --headless --path . -s scripts/server/server_main.gd -- port=$PORT\"" >/dev/null 2>&1
	if [ $? -ne 0 ]; then
		"$GODOT" --headless --path . -s scripts/server/server_main.gd -- "port=$PORT" \
			>/tmp/dontblowmeup-server.log 2>&1 &
		echo "   服务器日志：/tmp/dontblowmeup-server.log"
	fi
	sleep 2
fi

echo "启动客户端 1（当房主）…"
"$GODOT" --path . res://scenes/net_main.tscn >/dev/null 2>&1 &
sleep 2
echo "启动客户端 2（加入房间）…"
"$GODOT" --path . res://scenes/net_main.tscn >/dev/null 2>&1 &

echo
echo "✅ 两个客户端已启动。操作顺序："
echo "   1) 窗口1：填昵称 → 创建房间 → 记下 6 位邀请码"
echo "   2) 窗口2：填昵称 → 输入邀请码 → 加入房间"
echo "   3) 窗口1：人数变 2 后点『开始游戏』"
echo
echo "按回车关闭本窗口…"
read -r _
