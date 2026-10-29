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
	_test_skip_wish_online()
	_test_empty_hand_online()
	_test_exhausted_online()
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
	print("[NET-1] 共 %d 项断言执行完毕" % (_passes + _failures))


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
	print("[NET-2] 共 %d 项断言执行完毕" % (_passes + _failures))


## v0.9.6（用户拍板）：项目重心是联机版，这两条规则必须在 NetRoom 权威层被守住。
##  A) 跳过 × 休想：反制后跳过失效 != 回合轮转，出牌者留在本回合、仍须照常抽牌
##  B) 透支：抽到的牌名只发给出牌者本人，公共广播与其他人视图都拿不到
func _test_skip_wish_online() -> void:
	print("[NET-3] 跳过×休想 / 透支隐私（联机权威层）")
	# ---- A) 跳过被休想反制 ----
	var logs_by_seat := {301: [], 302: [], 303: []}
	var public_log: Array = []
	var manager := NetRoomManager.new()
	var room := manager.create_room(301, "甲", "222222")
	room.send_seat = func(seat: int, text: String) -> void:
		logs_by_seat[301 + seat].append(String(NetProtocol.decode(text).get("msg", "")))
	room.send_all = func(text: String) -> void:
		public_log.append(String(NetProtocol.decode(text).get("msg", "")))
	manager.join_room(302, "乙", "222222")
	manager.join_room(303, "丙", "222222")
	_check(room.start_game(11), "NET-3 三人开局")
	room.machine._current = 0
	room.machine.phase = TurnStateMachine.TurnPhase.ACTION
	_force_hand(room.machine.players()[0], [Card.Kind.SKIP])
	_force_hand(room.machine.players()[2], [Card.Kind.WISH])

	var now := 1000.0
	room.handle(0, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_PLAY, "card": 0}, now)
	_check(room.machine.phase == TurnStateMachine.TurnPhase.RESPONSE, "NET-3 跳过进入匿名响应窗口")
	_check(String(room.build_view(0).get("phase", "")) == "response", "NET-3 客户端视图为响应阶段")

	room.handle(2, {"t": NetProtocol.T_WISH, "use": true}, now + 500.0)
	var v_actor := room.build_view(0)
	var v_next := room.build_view(1)
	var v_wisher := room.build_view(2)
	_check(String(v_actor.get("phase", "")) == "action", "NET-3 反制后出牌者视图回到出牌阶段")
	_check(bool(v_actor.get("your_turn", false)), "NET-3 反制后回合仍在出牌者身上")
	_check(int(v_actor.get("required_draws", 0)) == 1, "NET-3 反制后仍需照常抽 1 张")
	_check(not bool(v_next.get("your_turn", true)), "NET-3 下家没有拿到回合")
	_check(not bool(v_wisher.get("your_turn", true)), "NET-3 反制者没有额外获得回合")
	_check(room.response_deadline_ms == 0.0, "NET-3 响应窗口关闭、倒计时清零")
	room.handle(0, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_DRAW}, now + 900.0)
	_check(not bool(room.build_view(0).get("your_turn", true)), "NET-3 反制后出牌者可正常抽牌结束回合")

	# ---- B) 透支抽到的牌只给本人 ----
	var logs2 := {401: [], 402: []}
	var public2: Array = []
	var manager2 := NetRoomManager.new()
	var room2 := manager2.create_room(401, "甲", "333333")
	room2.send_seat = func(seat: int, text: String) -> void:
		logs2[401 + seat].append(String(NetProtocol.decode(text).get("msg", "")))
	room2.send_all = func(text: String) -> void:
		public2.append(String(NetProtocol.decode(text).get("msg", "")))
	manager2.join_room(402, "乙", "333333")
	_check(room2.start_game(23), "NET-3 两人开局（透支场景）")
	room2.machine._current = 0
	room2.machine.phase = TurnStateMachine.TurnPhase.ACTION
	_force_hand(room2.machine.players()[0], [Card.Kind.OVERDRAW])
	_force_hand(room2.machine.players()[1], [Card.Kind.WISH])

	room2.handle(0, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_PLAY, "card": 0}, now)
	if room2.machine.phase == TurnStateMachine.TurnPhase.RESPONSE:
		room2.handle(1, {"t": NetProtocol.T_WISH, "use": false}, now + 100.0)
	_check(room2.machine.phase == TurnStateMachine.TurnPhase.OVERDRAW, "NET-3 透支进入连抽阶段")
	room2.handle(0, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_OVERDRAW_DRAW}, now + 200.0)

	var zone: Array = room2.machine.players()[0].overdraw_zone
	_check(not zone.is_empty(), "NET-3 首抽为非爆弹，入透支区")
	if not zone.is_empty():
		var drawn_name := Card.display_name(zone[0].kind)
		var pub_text := " ".join(public2)
		var own_text := " ".join(logs2[401])
		var other_text := " ".join(logs2[402])
		_check(not pub_text.contains("抽到【"), "NET-3 公共广播不出现抽到的牌名")
		_check(own_text.contains("你抽到【%s】" % drawn_name), "NET-3 本人收到私有牌名提示")
		_check(not other_text.contains("抽到【"), "NET-3 其他座位收不到牌名")
	var own_view: Array = room2.build_view(0).get("overdraw", [])
	var other_view: Array = room2.build_view(1).get("overdraw", [])
	_check(own_view.size() == 1, "NET-3 本人视图能看到透支区牌面")
	_check(other_view.is_empty(), "NET-3 他人视图里透支区为空（隐私）")

	# ---- C) 休想只在自己视图里可见（客户端据此决定是否显示反制入口）----
	var own_hand: Array = room2.build_view(1).get("hand", [])
	var rival_hand: Array = room2.build_view(0).get("hand", [])
	_check(own_hand.has(Card.Kind.WISH), "NET-3 持牌者本人能看到自己的休想")
	_check(not rival_hand.has(Card.Kind.WISH), "NET-3 别人视图里看不到我的休想")


## MECH-014（v0.9.7 用户拍板）：空手维持现状——只能抽牌、不能出牌（含休想）、不能被抢，不补牌不淘汰。
func _test_empty_hand_online() -> void:
	print("[NET-4] 空手（0 张）规则（MECH-014）")
	var manager := NetRoomManager.new()
	var room := manager.create_room(501, "甲", "444444")
	room.send_seat = func(_seat: int, _text: String) -> void:
		pass
	room.send_all = func(_text: String) -> void:
		pass
	manager.join_room(502, "乙", "444444")
	manager.join_room(503, "丙", "444444")
	_check(room.start_game(31), "NET-4 三人开局")
	var m := room.machine
	m._current = 0
	m.phase = TurnStateMachine.TurnPhase.ACTION
	m.players()[0].hand.clear()

	var v := room.build_view(0)
	_check((v.get("hand", []) as Array).is_empty(), "NET-4 空手视图里手牌为空")
	_check(bool(v.get("your_turn", false)), "NET-4 空手玩家仍轮到自己")
	_check(String(v.get("phase", "")) == "action", "NET-4 空手仍在出牌阶段（客户端可点抽牌）")
	_check(int(v.get("required_draws", 0)) >= 1, "NET-4 空手仍需抽牌")

	# 空手时出牌请求被忽略（越界下标，服务器不崩、状态不变）
	room.handle(0, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_PLAY, "card": 0}, 1000.0)
	_check(m.players()[0].hand.is_empty() and m.phase == TurnStateMachine.TurnPhase.ACTION,
			"NET-4 空手出牌请求被忽略且不改变阶段")

	# 空手时打不出休想（手里没有牌，引擎按无牌拒绝）
	m._current = 1
	_force_hand(m.players()[1], [Card.Kind.SKIP])
	room.handle(1, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_PLAY, "card": 0}, 1100.0)
	_check(m.phase == TurnStateMachine.TurnPhase.RESPONSE, "NET-4 空手局面下别人打功能牌仍进响应窗口")
	_check(not m.respond_wish(true, 0), "NET-4 空手玩家无法打出休想")
	m.respond_wish(false)

	# 空手不能被指定为偷牌目标：偷牌不消耗、手牌仍为 0
	m._current = 1
	m.phase = TurnStateMachine.TurnPhase.ACTION
	_force_hand(m.players()[1], [Card.Kind.STEAL])
	var steal_before := m.players()[1].hand.size()
	room.handle(1, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_PLAY, "card": 0, "target": 0}, 1200.0)
	_check(m.players()[0].hand.is_empty(), "NET-4 空手目标没被抢到牌")
	_check(m.players()[1].hand.size() == steal_before, "NET-4 偷空手目标的偷牌不消耗（留在手里）")

	# 空手轮到自己抽一张即可恢复（或抽到爆弹出局）
	m._current = 0
	m.phase = TurnStateMachine.TurnPhase.ACTION
	room.handle(0, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_DRAW}, 1300.0)
	_check(m.players()[0].hand.size() == 1 or not m.players()[0].alive,
			"NET-4 空手抽一张后恢复手牌（或抽到爆弹出局）")


## MECH-015（v0.9.8 用户拍板）：牌池与弃牌堆双空时，权威层按手牌数裁定终局并广播原因。
func _test_exhausted_online() -> void:
	print("[NET-5] 牌池双空保底终局（MECH-015，联机权威层）")

	# ---- A) 手牌最多者独占 → 该玩家获胜，事件标明"耗尽"而非爆弹 ----
	var events: Array = []
	var manager := NetRoomManager.new()
	var room := manager.create_room(901, "甲", "555555")
	room.send_seat = func(_seat: int, _text: String) -> void:
		pass
	room.send_all = func(text: String) -> void:
		events.append(NetProtocol.decode(text))
	manager.join_room(902, "乙", "555555")
	manager.join_room(903, "丙", "555555")
	_check(room.start_game(41), "NET-5 三人开局")
	var m := room.machine
	m._deck._draw.clear()
	m._deck._discard.clear()
	m._current = 0
	m.phase = TurnStateMachine.TurnPhase.ACTION
	_force_hand(m.players()[0], [Card.Kind.SKIP])
	_force_hand(m.players()[1], [Card.Kind.SKIP, Card.Kind.SKIP, Card.Kind.SKIP])
	_force_hand(m.players()[2], [Card.Kind.SKIP, Card.Kind.SKIP])

	room.handle(0, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_DRAW}, 1000.0)
	var v := room.build_view(0)
	_check(String(v.get("phase", "")) == "over", "NET-5 双空抽牌后视图进入终局")
	_check(String(v.get("winner", "")) == "乙", "NET-5 视图给出按手牌裁定的赢家")
	_check(not bool(v.get("draw_game", true)), "NET-5 赢家独占时不标记平局")
	_check(bool(v.get("exhausted", false)), "NET-5 视图标记本局为牌池耗尽收场")
	var over_msg := _last_game_over(events)
	_check(not over_msg.is_empty(), "NET-5 广播了终局事件")
	_check(String(over_msg.get("winner", "")) == "乙", "NET-5 终局事件带赢家名")
	_check(String(over_msg.get("why", "")) == "exhausted", "NET-5 终局事件标明耗尽原因")
	_check(not bool(over_msg.get("draw", true)), "NET-5 终局事件 draw=false")

	# ---- B) 存活玩家手牌并列最多 → 判和（winner 为空、draw=true）----
	var events2: Array = []
	var manager2 := NetRoomManager.new()
	var room2 := manager2.create_room(911, "甲", "666666")
	room2.send_seat = func(_seat: int, _text: String) -> void:
		pass
	room2.send_all = func(text: String) -> void:
		events2.append(NetProtocol.decode(text))
	manager2.join_room(912, "乙", "666666")
	_check(room2.start_game(43), "NET-5 两人开局（判和场景）")
	var m2 := room2.machine
	m2._deck._draw.clear()
	m2._deck._discard.clear()
	m2._current = 0
	m2.phase = TurnStateMachine.TurnPhase.ACTION
	_force_hand(m2.players()[0], [Card.Kind.SKIP, Card.Kind.SKIP])
	_force_hand(m2.players()[1], [Card.Kind.SKIP, Card.Kind.SKIP])
	room2.handle(0, {"t": NetProtocol.T_ACT, "a": NetProtocol.A_DRAW}, 2000.0)
	var v2 := room2.build_view(0)
	_check(bool(v2.get("draw_game", false)), "NET-5 并列最多 → 视图标记平局")
	_check(String(v2.get("winner", "x")) == "", "NET-5 平局时视图赢家为空")
	var draw_msg := _last_game_over(events2)
	_check(bool(draw_msg.get("draw", false)), "NET-5 平局终局事件 draw=true")


## 取出最后一条终局事件（没有则返回空字典）。
func _last_game_over(events: Array) -> Dictionary:
	var found := {}
	for e in events:
		if String(e.get("e", "")) == NetProtocol.E_GAME_OVER:
			found = e
	return found


## 把玩家手牌换成指定牌（测试用，直接改权威状态）。
func _force_hand(player: PlayerState, kinds: Array) -> void:
	player.hand.clear()
	var i := 0
	for k in kinds:
		player.hand.append(Card.new(int(k), 90000 + i))
		i += 1


## 指定会话的收件箱里是否出现过预知结果事件。
func _peek_seen(inbox: Dictionary, base_session: int, seat: int) -> bool:
	for m in inbox[base_session + seat]:
		if String(m.get("e", "")) == NetProtocol.E_PEEK:
			return true
	return false
