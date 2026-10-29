# @trace PLAT-002, MECH-001..013
## 联机房间（M2.1/M2.2）：座位管理 + 权威规则结算。
## 核心：直接实例化现有 TurnStateMachine（规则唯一实现，不做第二套），
## 每次动作后按座位下发"各自可见状态"（手牌只发本人，休想持有信息天然保密）。
class_name NetRoom
extends RefCounted

const RESPONSE_SECONDS := 3.0        # 匿名响应倒计时（v0.9.3 用户拍板：8 秒太长，改 3 秒）
const OFFLINE_GRACE_MS := 4000       # 掉线玩家回合计时：超时自动抽牌托管
const MAX_SEATS := 5

var code := ""
var host_session := -1
var seats: Array[int] = []           # seat -> session_id（-1 = 空位/掉线）
var seat_names: Array[String] = []
var started := false

var machine: TurnStateMachine
var _rng: SeededRandom
var _deck: Deck
var _config: GameConfig

var response_deadline_ms := 0.0      # RESPONSE 阶段自动结算时刻
var last_ms := 0.0                   # 最近一次服务器时钟（用于视图下发剩余响应毫秒）
var _peek_owner_seat := -1           # 预知结果归属座位（结算前记下，避免发给关窗口的人/下家）
var _offline_since_ms := 0.0         # 当前回合玩家掉线起始（托管计时）
var _game_over_sent := false

# 由 server_main 注入的发送回调
var send_seat: Callable              # func(seat: int, text: String)
var send_all: Callable               # func(text: String)


func _init(room_code: String) -> void:
	code = room_code


## 返回分配的座位号；房间满返回 -1。
func join(session_id: int, player_name: String) -> int:
	if seats.size() < MAX_SEATS and not seats.has(session_id):
		seats.append(session_id)
		seat_names.append(player_name)
		return seats.size() - 1
	return -1


func is_full() -> bool:
	return seats.size() >= MAX_SEATS


func connected_count() -> int:
	return seats.size()


func seat_of(session_id: int) -> int:
	return seats.find(session_id)


## 房主点开始：建状态机发牌，广播开局状态。
func start_game(seed_value: int) -> bool:
	if started or seats.size() < 2:
		return false
	started = true
	_rng = SeededRandom.new()
	_deck = Deck.new(_rng)
	_config = GameConfig.new()
	machine = TurnStateMachine.new(_deck, _config, _rng)
	var names := PackedStringArray()
	for n in seat_names:
		names.append(n)
	machine.start_game(names, seed_value)
	machine.log_message.connect(func(message: String) -> void:
		send_all.call(NetProtocol.encode({"t": NetProtocol.T_LOG, "msg": message})))
	# v0.9.6：私密日志只发给指定座位（透支抽到的具体牌名等，其他人收不到）
	machine.log_private.connect(func(message: String, player_index: int) -> void:
		if send_seat.is_valid() and player_index >= 0 and player_index < seats.size() \
				and seats[player_index] >= 0:
			send_seat.call(player_index, NetProtocol.encode({"t": NetProtocol.T_LOG, "msg": message})))
	machine.bomb_exploded.connect(func(player_name: String) -> void:
		send_all.call(NetProtocol.encode({
			"t": NetProtocol.T_EVENT, "e": NetProtocol.E_BOMB, "name": player_name})))
	# 动作演出：纯表现事件，广播给全房间（客户端据此播飞牌/横幅/抖动）
	machine.action_fx.connect(func(fx: Dictionary) -> void:
		var payload := fx.duplicate()
		payload["t"] = NetProtocol.T_FX
		send_all.call(NetProtocol.encode(payload)))
	broadcast_view()
	return true


## 处理某座位的消息；now_ms 由服务器时钟提供（倒计时/托管用）。
func handle(seat: int, msg: Dictionary, now_ms: float) -> void:
	last_ms = now_ms
	_capture_peek_owner()
	if machine == null:
		return
	var t: String = msg.get("t", "")
	match t:
		NetProtocol.T_ACT:
			if seat == machine.current_index():
				_handle_act(seat, msg, now_ms)
		NetProtocol.T_WISH:
			_handle_wish(seat, msg)
	_post_process(seat, now_ms)


## 动作后的收尾：预知私发、响应窗口开启、终局广播、视图下发。
func _post_process(actor_seat: int, now_ms: float) -> void:
	# 预知结果仅打出者可见（私有事件，发完即清）。
	# 归属以 _peek_owner_seat 为准：窗口可能被别人点"立即继续"关闭，
	# 或超时结算时 current_index 已轮转到下家，两者都不能当成接收者。
	if not machine.last_peek_result.is_empty():
		var owner := _peek_owner_seat if _peek_owner_seat >= 0 else actor_seat
		if send_seat.is_valid() and owner >= 0 and owner < seats.size() and seats[owner] >= 0:
			send_seat.call(owner, NetProtocol.encode({
				"t": NetProtocol.T_EVENT, "e": NetProtocol.E_PEEK,
				"text": machine.last_peek_result}))
		machine.clear_peek()
	_peek_owner_seat = -1
	# 进入响应窗口：启动服务器倒计时（匿名，不暴露持牌信息）
	if machine.phase == TurnStateMachine.TurnPhase.RESPONSE and response_deadline_ms == 0.0:
		note_response_window(now_ms)
	# 终局
	if machine.phase == TurnStateMachine.TurnPhase.GAME_OVER and not _game_over_sent:
		_game_over_sent = true
		send_all.call(NetProtocol.encode({
			"t": NetProtocol.T_EVENT, "e": NetProtocol.E_GAME_OVER,
			"winner": machine.winner.name if machine.winner != null else "",
			# MECH-015：牌池双空可能以"判和"收场，客户端据此区分"平局"与"无存活玩家"
			"draw": machine.draw_game,
			"why": "exhausted" if machine.exhausted_end else "bomb"}))
	broadcast_view()


func _handle_act(seat: int, msg: Dictionary, now_ms: float) -> void:
	var phase := machine.phase
	var a: String = msg.get("a", "")
	match a:
		NetProtocol.A_DRAW:
			if phase == TurnStateMachine.TurnPhase.ACTION:
				machine.normal_draw()
		NetProtocol.A_PLAY:
			if phase == TurnStateMachine.TurnPhase.ACTION:
				_handle_play(seat, msg)
		NetProtocol.A_SINGLE:
			if phase == TurnStateMachine.TurnPhase.ACTION:
				machine.play_single_plier(int(msg.get("card", -1)))
		NetProtocol.A_PLIERS:
			if phase == TurnStateMachine.TurnPhase.ACTION:
				var indices: Array[int] = []
				for c in msg.get("cards", []):
					indices.append(int(c))
				machine.play_pliers(indices, String(msg.get("combo", "")),
						int(msg.get("target", -1)), int(msg.get("wanted", -1)))
		NetProtocol.A_BOMB:
			if phase == TurnStateMachine.TurnPhase.BOMB_PLACEMENT:
				machine.confirm_bomb_placement(int(msg.get("pos", 0)))
		NetProtocol.A_FLUSH:
			if phase == TurnStateMachine.TurnPhase.FLUSH_PICK:
				machine.flush_pick(int(msg.get("idx", 0)))
		NetProtocol.A_OVERDRAW_DRAW:
			if phase == TurnStateMachine.TurnPhase.OVERDRAW:
				machine.overdraw_draw()
		NetProtocol.A_OVERDRAW_STOP:
			if phase == TurnStateMachine.TurnPhase.OVERDRAW:
				machine.stop_overdraw()


## 出牌分派：按本人手牌中该下标的牌种类路由到状态机对应方法。
func _handle_play(seat: int, msg: Dictionary) -> void:
	var card_index := int(msg.get("card", -1))
	var hand := machine.players()[seat].hand
	if card_index < 0 or card_index >= hand.size():
		return
	var kind: Card.Kind = hand[card_index].kind
	var target := int(msg.get("target", -1))
	match kind:
		Card.Kind.SKIP:
			machine.play_skip(card_index)
		Card.Kind.ATTACK:
			machine.play_attack(card_index)
		Card.Kind.PEEK:
			machine.play_peek(card_index)
		Card.Kind.SHUFFLE:
			machine.play_shuffle(card_index)
		Card.Kind.STEAL:
			machine.play_steal(card_index, target)
		Card.Kind.OVERDRAW:
			machine.play_overdraw(card_index)
		_:
			if Card.is_plier(kind):
				# 单张工具打出走 A_SINGLE；此路径忽略
				pass


func _handle_wish(seat: int, msg: Dictionary) -> void:
	if machine.phase != TurnStateMachine.TurnPhase.RESPONSE:
		return
	var use: bool = bool(msg.get("use", false))
	if not use:
		machine.respond_wish(false)
		response_deadline_ms = 0.0
		return
	if not machine.respond_wish(true, seat):
		# 服务器不泄露原因细节（没有休想牌 / 不能反制自己——本地语义一致）
		if send_seat.is_valid() and seats[seat] >= 0:
			send_seat.call(seat, NetProtocol.encode({
				"t": NetProtocol.T_ERROR, "msg": "反制无效（你没有休想牌，或不可反制该牌）"}))
	else:
		response_deadline_ms = 0.0


## 每帧由 server_main 驱动：响应倒计时到点自动结算 + 掉线托管。
func tick(now_ms: float) -> void:
	last_ms = now_ms
	if machine == null:
		return
	# 1) 匿名响应窗口到点无人反制 → 效果生效
	if machine.phase == TurnStateMachine.TurnPhase.RESPONSE \
			and response_deadline_ms > 0.0 and now_ms >= response_deadline_ms:
		response_deadline_ms = 0.0
		_capture_peek_owner()
		machine.respond_wish(false)
		_post_process(machine.current_index(), now_ms)
		return
	# 2) 掉线托管：当前回合玩家掉线超过宽限期，自动执行最小动作
	if started and machine.phase != TurnStateMachine.TurnPhase.GAME_OVER \
			and seats[machine.current_index()] < 0:
		if _offline_since_ms == 0.0:
			_offline_since_ms = now_ms
		elif now_ms - _offline_since_ms >= OFFLINE_GRACE_MS:
			_offline_since_ms = 0.0
			match machine.phase:
				TurnStateMachine.TurnPhase.ACTION:
					machine.normal_draw()
				TurnStateMachine.TurnPhase.OVERDRAW:
					machine.stop_overdraw()
				TurnStateMachine.TurnPhase.BOMB_PLACEMENT:
					machine.confirm_bomb_placement(machine.bomb_placement_range() / 2)
				TurnStateMachine.TurnPhase.FLUSH_PICK:
					machine.flush_pick(0)
				TurnStateMachine.TurnPhase.RESPONSE:
					pass  # 倒计时路径处理
			_post_process(machine.current_index(), now_ms)
	else:
		_offline_since_ms = 0.0


## 广播响应窗口开启（v0.9.1 匿名语义：不暴露谁持牌）。
func note_response_window(now_ms: float) -> void:
	response_deadline_ms = now_ms + RESPONSE_SECONDS * 1000.0
	send_all.call(NetProtocol.encode({
		"t": NetProtocol.T_RESPONSE_WINDOW, "open": true, "seconds": int(RESPONSE_SECONDS)}))


## 结算前记下"预知结果该发给谁"（打出者）。窗口由谁关闭、是否超时都不影响归属。
func _capture_peek_owner() -> void:
	if machine == null or machine.phase != TurnStateMachine.TurnPhase.RESPONSE:
		return
	var eff: Dictionary = machine.pending_effect()
	if String(eff.get("type", "")) == "peek":
		_peek_owner_seat = int(eff.get("actor", -1))


## 构建座位 seat 的可见状态（隐私核心：手牌/透支区只含本人数据）。
func build_view(seat: int) -> Dictionary:
	var players: Array = []
	for i in seat_names.size():
		players.append({
			"name": seat_names[i],
			"count": machine.players()[i].hand.size(),
			"alive": machine.players()[i].alive,
			"cur": i == machine.current_index(),
			"on": seats[i] >= 0,
		})
	var discards := machine.discard_cards()
	var discard_top := -1
	if not discards.is_empty():
		discard_top = int(discards[discards.size() - 1].kind)
	var phase_name := "action"
	match machine.phase:
		TurnStateMachine.TurnPhase.ACTION:
			phase_name = "action"
		TurnStateMachine.TurnPhase.OVERDRAW:
			phase_name = "overdraw"
		TurnStateMachine.TurnPhase.BOMB_PLACEMENT:
			phase_name = "bomb"
		TurnStateMachine.TurnPhase.RESPONSE:
			phase_name = "response"
		TurnStateMachine.TurnPhase.FLUSH_PICK:
			phase_name = "flush"
		TurnStateMachine.TurnPhase.GAME_OVER:
			phase_name = "over"

	var view := {
		"t": NetProtocol.T_STATE,
		"you": seat,
		"phase": phase_name,
		"your_turn": seat == machine.current_index(),
		"hand": _kinds_of(machine.players()[seat].hand),
		"overdraw": _kinds_of(machine.players()[seat].overdraw_zone),
		"players": players,
		"draw": machine.draw_pile_count(),
		"discard_top": discard_top,
		"discard_count": machine.discard_count(),
		"required_draws": machine._required_draws,
		"exploded": machine.exploded_bombs_total,
		"winner": machine.winner.name if machine.winner != null else "",
		"draw_game": machine.draw_game,
		"exhausted": machine.exhausted_end,
	}
	# 公共倒计时：响应窗口剩余毫秒（客户端据此校准本地倒计时，不暴露任何持牌信息）
	if machine.phase == TurnStateMachine.TurnPhase.RESPONSE:
		view["response_left_ms"] = maxf(0.0, response_deadline_ms - last_ms)
	# 私有段：仅发给对应玩家
	if machine.phase == TurnStateMachine.TurnPhase.BOMB_PLACEMENT \
			and seat == machine.current_index():
		view["bomb_range"] = machine.bomb_placement_range()
	if machine.phase == TurnStateMachine.TurnPhase.FLUSH_PICK \
			and seat == machine.current_index():
		var kinds: Array = []
		for c in discards:
			kinds.append(int(c.kind))
		view["discard_kinds"] = kinds
	return view


func _kinds_of(cards: Array) -> Array:
	var kinds: Array = []
	for c in cards:
		kinds.append(int(c.kind))
	return kinds


## 给每个座位下发它各自的视图。
func broadcast_view() -> void:
	if machine == null:
		return
	for seat in seats.size():
		if seats[seat] >= 0 and send_seat.is_valid():
			send_seat.call(seat, NetProtocol.encode(build_view(seat)))
