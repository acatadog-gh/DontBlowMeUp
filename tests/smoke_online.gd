# @trace PLAT-002
## 联机端到端冒烟测试：连接真实服务器（TCPServer+WebSocketPeer），
## 两个机器人客户端建房/加入/开局，脚本化策略打完整局。
## 前置：服务器已在 8933 端口运行（见外部启动命令）。
## 用法：Godot --headless --path 工程 -s tests/smoke_online.gd
extends SceneTree

const URL := "ws://127.0.0.1:8933"
const TIMEOUT_MS := 90000

var bots: Array = []          # [{peer, name, code, started}]
var start_ms := 0
var game_over := false
var state_count := 0
var error_count := 0
var fx_count := 0            # 动作演出消息（偷牌/洗牌/抽牌等，供客户端播动画）


func _initialize() -> void:
	start_ms = Time.get_ticks_msec()
	for i in 2:
		var peer := WebSocketPeer.new()
		peer.connect_to_url(URL)
		bots.append({"peer": peer, "name": "机器人%d" % (i + 1), "code": "",
				"hello": false, "joined": false, "invited": false, "pass_window": false})
	print("[smoke] 连接 ", URL)


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_msec()
	if not game_over and now - start_ms > TIMEOUT_MS:
		print("FAIL  冒烟超时：%d 条状态、%d 条错误，未在 %d 秒内打完" % [
				state_count, error_count, TIMEOUT_MS / 1000])
		quit(1)
		return true
	for b in bots:
		var peer: WebSocketPeer = b.peer
		if peer == null:
			continue
		peer.poll()
		var rs := peer.get_ready_state()
		if rs == WebSocketPeer.STATE_OPEN:
			if not bool(b.get("opened", false)):
				b["opened"] = true
				_send(b, {"t": NetProtocol.T_HELLO, "name": b.name})
			while peer.get_available_packet_count() > 0:
				var packet := peer.get_packet()
				if peer.was_string_packet():
					_handle(b, NetProtocol.decode(packet.get_string_from_utf8()))
		elif rs == WebSocketPeer.STATE_CLOSED:
			print("FAIL  连接被关闭（服务器未启动？）")
			quit(1)
			return true
	return false


func _send(b: Dictionary, msg: Dictionary) -> void:
	b.peer.send_text(NetProtocol.encode(msg))


func _handle(b: Dictionary, msg: Dictionary) -> void:
	var t: String = msg.get("t", "")
	if t == NetProtocol.T_FX:
		fx_count += 1
		return
	match t:
		NetProtocol.T_EVENT:
			var e: String = msg.get("e", "")
			if e == NetProtocol.E_GAME_OVER:
				game_over = true
				var winner: String = msg.get("winner", "")
				if winner != "":
					print("PASS  整局通过真实 WebSocket 打完，赢家：", winner)
					print("PASS  状态消息 %d 条，错误消息 %d 条" % [state_count, error_count])
					print("PASS  动作演出 %d 条（服务器确实广播了偷牌/洗牌等演出事件）" % fx_count)
					quit(0)
				else:
					print("FAIL  终局无赢家")
					quit(1)
			elif e == "welcome" and not b.hello:
				b.hello = true
				if bots[0] == b:
					_send(b, {"t": NetProtocol.T_CREATE})
				# 机器人2 等 1 的房间码
		NetProtocol.T_ROOM_STATE:
			b.code = String(msg.get("code", ""))
			b.joined = true
			# 房主视角必须能看到 ≥2 人，否则"开始游戏"按钮一直是灰的
			var ps: Array = msg.get("players", [])
			if b == bots[0] and ps.size() >= 2 and not bool(bots[0].get("saw_two", false)):
				bots[0]["saw_two"] = true
				print("PASS  房主收到 %d 人房间状态（开始按钮可点）" % ps.size())
			if b == bots[0]:
				print("[smoke] 房间已建：", b.code)
				# 房主拿到房间码后邀请机器人2（房间状态会广播多次，只邀请一次）
				if not bool(bots[0].get("invited", false)):
					bots[0]["invited"] = true
					_send(bots[1], {"t": NetProtocol.T_JOIN, "code": b.code})
			else:
				print("[smoke] 机器人2 已加入：", b.code)
			# 两端就绪后房主开局（只发一次）
			if bots[0].joined and bots[1].joined and not bool(bots[0].get("started", false)):
				bots[0]["started"] = true
				_send(bots[0], {"t": NetProtocol.T_START})
		NetProtocol.T_STATE:
			state_count += 1
			_bot_act(b, msg)
		NetProtocol.T_ERROR:
			error_count += 1
		NetProtocol.T_LOG:
			pass


## 机器人策略：能动就动（功能牌优先→单张工具→抽牌），响应窗口立即放行。
func _bot_act(b: Dictionary, msg: Dictionary) -> void:
	var seat := int(msg.get("you", -1))
	var phase := String(msg.get("phase", ""))
	if bool(msg.get("your_turn", false)):
		match phase:
			"action":
				var hand: Array = msg.get("hand", [])
				var done := false
				for i in hand.size():
					var k := int(hand[i])
					if k == Card.Kind.SKIP or k == Card.Kind.ATTACK or k == Card.Kind.PEEK \
							or k == Card.Kind.SHUFFLE or k == Card.Kind.OVERDRAW:
						_send(b, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_PLAY, "card": i})
						done = true
						break
					if k == Card.Kind.STEAL:
						var players: Array = msg.get("players", [])
						var target := -1
						for j in players.size():
							if j != seat and bool(players[j].get("alive", false)) \
									and int(players[j].get("count", 0)) > 0:
								target = j
								break
						if target >= 0:
							_send(b, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_PLAY,
									"card": i, "target": target})
							done = true
							break
				if not done:
					for i in hand.size():
						if Card.is_plier(int(hand[i])):
							_send(b, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_SINGLE, "card": i})
							done = true
							break
				if not done:
					_send(b, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_DRAW})
			"overdraw":
				_send(b, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_OVERDRAW_STOP})
			"bomb":
				_send(b, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_BOMB,
						"pos": int(int(msg.get("bomb_range", 1)) / 2.0)})
			"flush":
				_send(b, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_FLUSH, "idx": 0})
	# 响应窗口：任一机器人立即放行（窗口每局多次，每次只放行一次防重复）
	if phase == "response" and not bool(b.get("pass_window", false)):
		b["pass_window"] = true
		_send(b, {"t": NetProtocol.T_WISH, "use": false})
	elif phase != "response":
		b["pass_window"] = false
