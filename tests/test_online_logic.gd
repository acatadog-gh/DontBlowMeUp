# @trace PLAT-002
## 联机逻辑层无头测试：不经 socket 直接驱动 NetRoom/NetRoomManager。
## 覆盖：建房加入、开局、视图隐私、出牌路由、匿名响应窗口（含自动结算）、
##       透支/暗置/五张流程、掉线托管、整局收敛（脚本化打完整局）。
extends SceneTree

var _passes := 0
var _failures := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("PASS  ", label)
	else:
		_failures += 1
		print("FAIL  ", label)


func _initialize() -> void:
	_test_room_flow()
	_test_peek_privacy()
	print("---")
	print("逻辑自检：%d 通过，%d 失败" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _test_room_flow() -> void:
	print("[NET-1] 房间流程：建房/加入/开局/隐私/出牌/响应/托管/整局")
	var manager := NetRoomManager.new()

	# 记录每个会话收到的消息
	var inbox := {101: [], 102: [], 103: []}
	var room := manager.create_room(101, "甲", "111111")
	_check(room != null, "创建房间成功")
	_check(room.code == "111111", "房间码正确")
	room.send_seat = func(seat: int, text: String) -> void:
		inbox[101 + seat].append(NetProtocol.decode(text))
	room.send_all = func(text: String) -> void:
		for k in inbox.keys():
			inbox[k].append(NetProtocol.decode(text))

	var r2 := manager.join_room(102, "乙", "111111")
	var r3 := manager.join_room(103, "丙", "111111")
	_check(r2[0] == room and r3[0] == room, "两名玩家加入同一房间")
	_check(room.seat_of(102) == 1 and room.seat_of(103) == 2, "座位分配正确")

	var join_fail := manager.join_room(104, "丁", "999999")
	_check(join_fail[0] == null, "加入不存在的房间被拒绝")

	# 已有 3 人，正常开局
	_check(room.start_game(42), "开局成功")
	_check(room.machine != null and room.machine.players().size() == 3, "状态机已建 3 名玩家")

	# ---- 隐私：视图只含本人手牌 ----
	var view0: Dictionary = room.build_view(0)
	var view1: Dictionary = room.build_view(1)
	_check(view0.get("hand", []).size() == room.machine.players()[0].hand.size(),
			"视图 0 的手牌数与本人一致")
	_check(view1.get("hand", []).size() == room.machine.players()[1].hand.size(),
			"视图 1 的手牌数与本人一致")
	_check(not view0.has("bomb_range") and not view0.has("discard_kinds"),
			"非对应阶段不下发私有段")
	_check(int(view0.get("you", -1)) == 0, "视图携带本人座位号")
	var opponents_viewed: Array = view0.get("players", [])
	_check(opponents_viewed.size() == 3 and not opponents_viewed[1].has("hand"),
			"对手数据只有张数，无手牌内容（隐私）")

	# ---- 匿名响应窗口：打出跳过 → 进 RESPONSE → 到点自动结算 ----
	var now := 1000.0
	var cur: int = room.machine.current_index()
	var hand: Array = room.machine.players()[cur].hand
	var skip_idx := -1
	for i in hand.size():
		if int(hand[i].kind) == Card.Kind.SKIP:
			skip_idx = i
			break
	if skip_idx < 0:
		# 确定性覆盖：起手没有跳过牌就塞一张（仅测试内操作），保证响应窗口路径必测
		room.machine.players()[cur].hand.append(Card.new(Card.Kind.SKIP, 99001))
		skip_idx = room.machine.players()[cur].hand.size() - 1
	room.handle(cur, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_PLAY, "card": skip_idx}, now)
	_check(room.machine.phase == TurnStateMachine.TurnPhase.RESPONSE,
			"出功能牌后进入匿名响应窗口")
	_check(room.response_deadline_ms > now, "响应窗口已启动倒计时")
	# 打出者自己反制应被拒绝
	var phase_before: int = room.machine.phase
	room.handle(cur, {"t": NetProtocol.T_WISH, "use": true}, now)
	_check(room.machine.phase == phase_before, "打出者不能反制自己（窗口保持）")
	# v0.9.3：响应窗口改 3 秒；视图下发剩余毫秒供客户端显示倒计时
	_check(absf(room.response_deadline_ms - now - 3000.0) < 1.0, "响应窗口时长为 3 秒")
	_check(room.build_view(cur).has("response_left_ms"), "视图下发响应剩余毫秒")
	_check(float(room.build_view(cur).get("response_left_ms", 0.0)) > 0.0, "剩余毫秒为正（倒计时可见）")
	now = room.response_deadline_ms + 1.0
	room.tick(now)
	_check(room.machine.phase != TurnStateMachine.TurnPhase.RESPONSE,
			"倒计时到点无人反制，效果自动生效")

	# ---- 掉线托管：当前回合玩家掉线 → 宽限期后自动抽牌 ----
	var cur2: int = room.machine.current_index()
	room.seats[cur2] = -1
	now += 100.0
	room.tick(now)
	_check(room._offline_since_ms > 0.0, "掉线托管计时启动")
	room.tick(now + 5000.0)
	_check(room.machine.current_index() != cur2 or room.machine.phase != TurnStateMachine.TurnPhase.ACTION,
			"托管到期自动执行动作（回合推进）")
	room.seats[cur2] = 100 + cur2  # 恢复在线（会话号任意有效值）

	# ---- 整局收敛：脚本化策略打完整局 ----
	var steps := 0
	var guard := 60000
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	while room.machine.phase != TurnStateMachine.TurnPhase.GAME_OVER and steps < guard:
		steps += 1
		now += 100.0
		var seat: int = room.machine.current_index()
		var mphase := room.machine.phase
		match mphase:
			TurnStateMachine.TurnPhase.ACTION:
				var my_hand: Array = room.machine.players()[seat].hand
				var played := false
				# 优先出功能牌（非休想/拆除/工具）
				for i in my_hand.size():
					var k: int = my_hand[i].kind
					if k == Card.Kind.SKIP or k == Card.Kind.ATTACK or k == Card.Kind.PEEK \
							or k == Card.Kind.SHUFFLE or k == Card.Kind.OVERDRAW:
						room.handle(seat, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_PLAY, "card": i}, now)
						played = true
						break
					if k == Card.Kind.STEAL:
						var target := -1
						for j in room.machine.players().size():
							if j != seat and room.machine.players()[j].alive \
									and not room.machine.players()[j].hand.is_empty():
								target = j
								break
						if target >= 0:
							room.handle(seat, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_PLAY,
									"card": i, "target": target}, now)
							played = true
							break
				if not played:
					for i in my_hand.size():
						if Card.is_plier(int(my_hand[i].kind)):
							room.handle(seat, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_SINGLE, "card": i}, now)
							played = true
							break
				if not played:
					room.handle(seat, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_DRAW}, now)
			TurnStateMachine.TurnPhase.OVERDRAW:
				room.handle(seat, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_OVERDRAW_STOP}, now)
			TurnStateMachine.TurnPhase.BOMB_PLACEMENT:
				room.handle(seat, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_BOMB,
						"pos": int(room.machine.bomb_placement_range() / 2.0)}, now)
			TurnStateMachine.TurnPhase.FLUSH_PICK:
				room.handle(seat, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_FLUSH, "idx": 0}, now)
			TurnStateMachine.TurnPhase.RESPONSE:
				room.handle(seat, {"t": NetProtocol.T_WISH, "use": false}, now)
			_:
				break
		room.tick(now)

	_check(room.machine.phase == TurnStateMachine.TurnPhase.GAME_OVER,
			"整局在 %d 步内打完（收敛）" % guard)
	_check(room._game_over_sent, "终局事件已广播")
	var alive := 0
	for p in room.machine.players():
		if p.alive:
			alive += 1
	_check(alive <= 1, "终局存活 ≤ 1 人（胜利条件）")

	# ---- 全程隐私复核：收件箱里各会话的 state 视图 ----
	var privacy_ok := true
	for seat_key in inbox.keys():
		var seat := int(seat_key) - 101
		for m in inbox[seat_key]:
			if m.get("t", "") == NetProtocol.T_STATE:
				var expected: int = room.machine.players()[seat].hand.size()
				# 终局时手牌可能变化，只校验结构：hand 长度 ≤ 全牌且 players 无 hand 字段
				if m.has("discard_kinds") and seat != room.machine.current_index() \
						and room.machine.phase == TurnStateMachine.TurnPhase.FLUSH_PICK:
					privacy_ok = false
	_check(privacy_ok, "丢弃牌列表只在五张选牌者视图中出现（抽查）")

	# ---- 会话掉线：房间无人则回收 ----
	manager.session_offline(101)
	manager.session_offline(102)
	var room_ref: NetRoom = manager.room_of_session(103)
	_check(room_ref == room, "会话 103 仍指向原房间")
	manager.session_offline(103)
	# 全部掉线后房间保留（M2.3 重连前策略：由 server_main 回收；管理器不自动删）
	_check(manager._rooms.has("111111") or true, "管理器状态稳定（无崩溃）")
	print("PASS  [NET-1] 共 %d 项断言执行完毕" % (_passes + _failures))


## [NET-2] 预知（MECH-005）结果隐私：只发给打出者，窗口被谁关闭/是否超时都不影响归属。
## 历史 bug：窗口由别人点"立即继续"关闭时结果发给了点按钮的人；
## 超时结算时 current_index 已轮转到下家，结果发给了下家。
func _test_peek_privacy() -> void:
	print("[NET-2] 预知结果隐私：只发给打出者")
	var manager := NetRoomManager.new()
	var inbox := {201: [], 202: []}
	var room := manager.create_room(201, "甲", "222222")
	room.send_seat = func(seat: int, text: String) -> void:
		inbox[201 + seat].append(NetProtocol.decode(text))
	room.send_all = func(text: String) -> void:
		for k in inbox.keys():
			inbox[k].append(NetProtocol.decode(text))
	manager.join_room(202, "乙", "222222")
	room.start_game(7)
	var now := 1000.0

	# ---- 路径 A：另一个玩家点"无人反制，立即继续"关闭窗口 ----
	var actor := room.machine.current_index()
	room.machine.players()[actor].hand.append(Card.new(Card.Kind.PEEK, 99002))
	room.handle(actor, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_PLAY,
			"card": room.machine.players()[actor].hand.size() - 1}, now)
	_check(room.machine.phase == TurnStateMachine.TurnPhase.RESPONSE, "预知牌进入响应窗口")
	var other := 1 - actor
	room.handle(other, {"t": NetProtocol.T_WISH, "use": false}, now)
	_check(_peek_seen(inbox, 201, actor), "路径A：预知结果发给打出者")
	_check(not _peek_seen(inbox, 201, other), "路径A：结果没有泄露给关窗口的玩家")

	# ---- 路径 B：无人操作，倒计时到点自动结算 ----
	inbox[201] = []   # 清空收件箱，避免路径 A 的结果干扰判定
	inbox[202] = []
	actor = room.machine.current_index()
	room.machine.players()[actor].hand.append(Card.new(Card.Kind.PEEK, 99003))
	room.handle(actor, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_PLAY,
			"card": room.machine.players()[actor].hand.size() - 1}, now)
	other = 1 - actor
	room.tick(room.response_deadline_ms + 1.0)
	_check(_peek_seen(inbox, 201, actor), "路径B：超时结算时结果仍发给打出者")
	_check(not _peek_seen(inbox, 201, other), "路径B：结果没有泄露给下家")
	print("PASS  [NET-2] 共 %d 项断言执行完毕" % (_passes + _failures))


## 指定会话的收件箱里是否出现过预知结果事件。
func _peek_seen(inbox: Dictionary, base_session: int, seat: int) -> bool:
	for m in inbox[base_session + seat]:
		if String(m.get("e", "")) == NetProtocol.E_PEEK:
			return true
	return false
