# @trace MECH-001, MECH-002, MECH-003, MECH-004, MECH-005, MECH-006, MECH-007, MECH-008, MECH-009, MECH-011, MECH-012, MECH-013, NUM-001, NUM-002
## 回合状态机。
## v0.6 规则（用户拍板）：
##   - 轮转条件修订（MECH-009）：出 1 张功能牌或抽 1 张牌后，回合立即结束轮到下家；
##     唯一例外是攻击叠层（被攻击者须抽满 N 次）与透支连抽中（喊停/爆弹结算后回合结束）。
##   - MECH-012 休想：他人打出功能牌时可打休想卡令其失效；唯一可在非自己回合打出的牌；
##     不可反制拆除（自动触发）与休想本身。
##   - MECH-013 拆弹工具（v0.8 类别化，5 种等量收集标记，用户拍板）：
##     对子=同种×2，指定一名玩家、随机盲偷 1 张（不亮手牌，保密）；
##     三条=同种×3，念牌名索要（目标有则必须给）；
##     五张=五种各×1，从弃牌堆任选 1 张入手。
## 胜利条件（MECH-009）：所有爆弹引爆后唯一存活者获胜。
class_name TurnStateMachine
extends RefCounted

signal log_message(message: String)
signal bomb_exploded(player_name: String)   # 爆弹引爆（供 UI 播放爆炸特效）

enum TurnPhase { ACTION, OVERDRAW, BOMB_PLACEMENT, RESPONSE, FLUSH_PICK, GAME_OVER }

var _deck: Deck
var _config: GameConfig
var _rng: SeededRandom
var _players: Array[PlayerState] = []

var _current := 0
var _pending_draws := 0           # 攻击叠层：下家需多抽 N 次（MECH-004）
var _overdraw_used_this_turn := false  # MECH-008：每回合限打出 1 张透支
var _bomb_to_place: Card
var _required_draws := 1          # 本回合仍需抽的次数（≥1）

# RESPONSE 匿名响应倒计时（MECH-012；v0.9.1 用户拍板：不点名询问任何玩家，
# 持休想信息完全保密——窗口内持牌者自行打出，无人出牌倒计时结束效果生效）
var _pending_effect := {}         # {type, target, wanted_kind, actor}

var phase: TurnPhase = TurnPhase.ACTION
var winner: PlayerState
var last_peek_result := ""
var exploded_bombs_total := 0


func _init(deck: Deck, config: GameConfig, rng: SeededRandom) -> void:
	_deck = deck
	_config = config
	_rng = rng


func players() -> Array[PlayerState]:
	return _players


func current() -> PlayerState:
	return _players[_current]


func draw_pile_count() -> int:
	return _deck.draw_count()


func discard_count() -> int:
	return _deck.discard_count()


func discard_cards() -> Array[Card]:
	return _deck.discard_list()


func bomb_placement_range() -> int:
	return _deck.draw_count()


func current_index() -> int:
	return _current


func overdraw_used_this_turn() -> bool:
	return _overdraw_used_this_turn


func pending_effect() -> Dictionary:
	return _pending_effect


func clear_peek() -> void:
	last_peek_result = ""


func _emit(message: String) -> void:
	log_message.emit(message)


## 发牌并开局（NUM-001）：每人 4 功能 + 1 拆除，爆弹与额外拆除洗入公共牌池。
func start_game(player_names: PackedStringArray, seed_value: int) -> void:
	var p := player_names.size()
	if p < _config.min_players or p > _config.max_players:
		push_error("人数须在 %d-%d（LEV-001）" % [_config.min_players, _config.max_players])
		return

	_players.clear()
	for player_name in player_names:
		_players.append(PlayerState.new(player_name))

	_rng._rng.seed = seed_value

	# 阶段 1：只含功能牌，每人发 4 张（NUM-001）
	_deck.build(p, _config.skip_count, _config.attack_count, _config.peek_count,
			_config.shuffle_count, _config.steal_count, _config.overdraw_count,
			_config.pliers_counts(), _config.wish_count, 0, 0)

	for round_i in _config.func_cards_per_player:
		for player in _players:
			var card := _deck.try_draw_top()
			if card != null:
				player.hand.append(card)

	# 阶段 2：每人补 1 张拆除（NUM-001：defuse_in_hand=1，恰好一张）
	for player in _players:
		player.hand.append(Card.new(Card.Kind.DEFUSE, -1))

	# 阶段 3：爆弹与额外拆除洗入公共牌池，重洗全场
	for i in _config.bomb_count_for(p):
		_deck.add_to_draw(Card.new(Card.Kind.BOMB, -1))
	for i in _config.defuse_in_pile_for(p):
		_deck.add_to_draw(Card.new(Card.Kind.DEFUSE, -1))
	_deck.shuffle()

	_current = 0
	_pending_draws = 0
	_required_draws = 1
	_overdraw_used_this_turn = false
	exploded_bombs_total = 0
	winner = null
	_pending_effect = {}
	phase = TurnPhase.ACTION
	_emit("开局：共 %d 名玩家，牌堆 %d 张，爆弹 %d 枚" % [p, _deck.draw_count(), _config.bomb_count_for(p)])
	_emit("当前回合：" + current().name)


# ---- 出牌阶段动作（MECH-009 v0.6：打出功能牌后经响应窗口结算，随后回合结束）----

## 提出功能牌效果：牌已进弃牌堆。
## v0.9.1（用户拍板）：一律进入匿名响应窗口——不扫描、不点名、不暴露谁持有休想；
## 倒计时内持牌者可自行打出（UI 传入 responder_index），无人打出则效果生效。
func _propose(type: String, hand_index: int, target := -1, wanted_kind := -1, extra := {}) -> void:
	_pending_effect = {"type": type, "actor": _current, "target": target, "wanted_kind": wanted_kind}
	_pending_effect.merge(extra)
	phase = TurnPhase.RESPONSE
	if type == "pliers":
		_emit(current().name + " 打出了拆弹工具组合，进入休想响应时间（持牌者可反制）……")
	else:
		_emit(current().name + " 打出【%s】，进入休想响应时间（持牌者可反制）……" % Card.display_name(_card_kind_of(type)))


func _card_kind_of(type: String) -> Card.Kind:
	match type:
		"skip": return Card.Kind.SKIP
		"attack": return Card.Kind.ATTACK
		"peek": return Card.Kind.PEEK
		"shuffle": return Card.Kind.SHUFFLE
		"steal": return Card.Kind.STEAL
		"overdraw": return Card.Kind.OVERDRAW
		"pliers": return Card.Kind.PLIERS_TIGER
	return Card.Kind.SKIP


## MECH-003：跳过。
func play_skip(hand_index: int) -> bool:
	var card := _take_from_hand(hand_index)
	if card == null:
		return false
	_deck.send_to_discard(card)
	_propose("skip", hand_index)
	return true


## MECH-004：攻击。
func play_attack(hand_index: int) -> bool:
	var card := _take_from_hand(hand_index)
	if card == null:
		return false
	_deck.send_to_discard(card)
	_propose("attack", hand_index)
	return true


## MECH-005：预知（结算时查看牌堆顶 3 张，仅打出者可见）。
func play_peek(hand_index: int) -> bool:
	var card := _take_from_hand(hand_index)
	if card == null:
		return false
	_deck.send_to_discard(card)
	_propose("peek", hand_index)
	return true


## MECH-006：洗牌。
func play_shuffle(hand_index: int) -> bool:
	var card := _take_from_hand(hand_index)
	if card == null:
		return false
	_deck.send_to_discard(card)
	_propose("shuffle", hand_index)
	return true


## MECH-007：偷牌；目标空手不可打出（牌退回手中，不消耗）。
func play_steal(hand_index: int, target_player_index: int) -> bool:
	var target := _players[target_player_index]
	if target.hand.is_empty():
		push_error("目标手牌为空，偷牌不可打出（MECH-007）")
		return false
	var card := _take_from_hand(hand_index)
	if card == null:
		return false
	_deck.send_to_discard(card)
	_propose("steal", hand_index, target_player_index)
	return true


## MECH-008（v0.5）：打出「透支」牌（每回合限 1 张）。响应通过后进入连抽阶段。
func play_overdraw(hand_index: int) -> bool:
	if _overdraw_used_this_turn:
		push_error("本回合已透支过")
		return false
	var card := _take_from_hand(hand_index)
	if card == null:
		return false
	if card.kind != Card.Kind.OVERDRAW:
		current().hand.insert(hand_index, card)
		push_error("打出的不是透支牌")
		return false
	_deck.send_to_discard(card)
	_propose("overdraw", hand_index)
	return true


## MECH-013（v0.8）：打出拆弹工具组合。hand_indices 为所选工具牌的手牌下标（降序无关）。
## combo: "pair"(同种×2) / "trio"(同种×3) / "flush"(五种各×1)；
## pair/trio 需 target（指定一名有手牌的玩家）；trio 需 wanted_kind。
## v0.8 规则修订（用户拍板）：对子=随机盲偷，不亮手牌。
func play_pliers(hand_indices: Array[int], combo: String, target_index := -1, wanted_kind := -1) -> bool:
	var need: int = {"pair": 2, "trio": 3, "flush": 5}.get(combo, -1)
	if need <= 0:
		push_error("未知拆弹工具组合：" + combo)
		return false
	if hand_indices.size() != need:
		push_error("拆弹工具组合 %s 需要 %d 张" % [combo, need])
		return false
	if combo == "pair" and (target_index < 0 or _players[target_index].hand.is_empty()):
		push_error("对子需要指定一个有手牌的目标")
		return false
	if combo == "trio":
		if target_index < 0 or _players[target_index].hand.is_empty():
			push_error("三条需要指定一个有手牌的目标")
			return false
		if wanted_kind < 0:
			push_error("三条需要念一个牌名")
			return false
	# 校验所选均为工具牌，且组合构成合法
	var indices := hand_indices.duplicate()
	indices.sort()
	indices.reverse()  # 从大到小移除，避免下标位移
	var kinds: Array[int] = []
	for idx in indices:
		if idx < 0 or idx >= current().hand.size() or not Card.is_plier(current().hand[idx].kind):
			push_error("所选牌中含有非拆弹工具牌")
			return false
		kinds.append(current().hand[idx].kind)
	match combo:
		"pair", "trio":
			if kinds[0] != kinds[1] or (combo == "trio" and kinds[1] != kinds[2]):
				push_error("%s 须为同一种工具（凑齐 %d 张）" % [combo, need])
				return false
		"flush":
			var distinct := {}
			for k in kinds:
				distinct[k] = true
			if distinct.size() != 5:
				push_error("五张组合须集齐 5 种不同的工具")
				return false
	var me := current()
	for idx in indices:
		var card: Card = me.hand[idx]
		me.hand.remove_at(idx)
		_deck.send_to_discard(card)
	_propose("pliers", -1, target_index, wanted_kind, {"combo": combo})
	return true


## MECH-013（v0.9.2 用户拍板）：单张工具牌可直接打出——无任何效果，
## 弃置进弃牌堆并结束回合；不进入响应窗口（无效果，无可反制）。
func play_single_plier(hand_index: int) -> bool:
	if phase != TurnPhase.ACTION:
		push_error("不在出牌阶段")
		return false
	if hand_index < 0 or hand_index >= current().hand.size():
		push_error("手牌下标非法")
		return false
	var card: Card = current().hand[hand_index]
	if not Card.is_plier(card.kind):
		push_error("只有拆弹工具牌可以单张打出")
		return false
	current().hand.remove_at(hand_index)
	_deck.send_to_discard(card)
	_emit("%s 单张打出【%s】（无效果，进弃牌堆），回合结束" % [
		current().name, Card.display_name(card.kind)])
	_end_turn()
	return true


# ---- RESPONSE 匿名响应倒计时（MECH-012）----

## v0.9.1：匿名响应。use_wish=false → 无人反制（或倒计时到点），效果结算；
## use_wish=true → responder_index 指定打出休想的玩家（由其本人在 UI 主动点选，
## 状态机不暴露持牌信息）。返回是否成功；失败时窗口保持打开。
func respond_wish(use_wish: bool, responder_index := -1) -> bool:
	if phase != TurnPhase.RESPONSE:
		push_error("当前不在响应阶段")
		return false
	if not use_wish:
		_resolve_pending()
		return true
	if responder_index < 0 or responder_index >= _players.size():
		push_error("响应者下标非法")
		return false
	if responder_index == int(_pending_effect.actor):
		push_error("不能反制自己打出的牌")
		return false
	var responder := _players[responder_index]
	var wish_index := -1
	for i in responder.hand.size():
		if responder.hand[i].kind == Card.Kind.WISH:
			wish_index = i
			break
	if wish_index < 0:
		push_error("该玩家没有休想牌")
		return false
	var wish_card: Card = responder.hand[wish_index]
	responder.hand.remove_at(wish_index)
	_deck.send_to_discard(wish_card)
	_emit("%s 打出【休想】！%s 的【%s】失效（两张牌均进弃牌堆）" % [
		responder.name, _players[int(_pending_effect.actor)].name,
		Card.display_name(_card_kind_of(_pending_effect.type))])
	_pending_effect = {}
	_end_turn()
	return true


## 结算待定效果（所有玩家放弃休想后调用）。
func _resolve_pending() -> void:
	if _pending_effect.is_empty():
		_end_turn()
		return
	var actor: int = _pending_effect.actor
	var type: String = _pending_effect.type
	match type:
		"skip":
			_emit("【跳过】生效，%s 不抽牌结束回合" % _players[actor].name)
			_pending_effect = {}
			_end_turn()
		"attack":
			_pending_draws += 2
			_emit("【攻击】生效！下家将多抽 %d 次" % _pending_draws)
			_pending_effect = {}
			_end_turn()
		"peek":
			var top := _deck.peek_top(3)
			var parts: PackedStringArray = []
			for i in top.size():
				parts.append("%d.%s" % [i + 1, Card.display_name(top[i].kind)])
			last_peek_result = " ".join(parts)
			_emit("【预知】生效（结果仅 %s 本人可见）" % _players[actor].name)
			_pending_effect = {}
			_end_turn()
		"shuffle":
			_deck.shuffle()
			_emit("【洗牌】生效，牌堆已重洗")
			_pending_effect = {}
			_end_turn()
		"steal":
			var target := _players[_pending_effect.target]
			var idx := _rng.next(target.hand.size())
			var stolen := target.hand[idx]
			target.hand.remove_at(idx)
			_players[actor].hand.append(stolen)
			_emit("【偷牌】生效：%s 从 %s 处偷走 1 张牌" % [_players[actor].name, target.name])
			_pending_effect = {}
			_end_turn()
		"overdraw":
			_overdraw_used_this_turn = true
			_players[actor].overdraw_zone.clear()
			_current = actor
			phase = TurnPhase.OVERDRAW
			_emit("【透支】生效！%s 可连续抽牌，随时喊停（炸则全弃）" % _players[actor].name)
			_pending_effect = {}
		"pliers":
			var combo: String = _pending_effect.combo
			var combo_label: String = {"pair": "对子", "trio": "三条", "flush": "五张"}.get(combo, combo)
			_emit("【拆弹工具·%s】生效" % combo_label)
			match combo:
				"pair":
					# v0.8：对子=随机盲偷 1 张（不亮手牌），与偷牌同结算（用户拍板）
					var target := _players[_pending_effect.target]
					var idx := _rng.next(target.hand.size())
					var stolen := target.hand[idx]
					target.hand.remove_at(idx)
					_players[actor].hand.append(stolen)
					_emit("【拆弹工具·对子】生效：%s 从 %s 处随机偷走 1 张手牌（不亮牌）" % [
						_players[actor].name, target.name])
					_pending_effect = {}
					_end_turn()
				"trio":
					var target := _players[_pending_effect.target]
					var found := -1
					for i in target.hand.size():
						if int(target.hand[i].kind) == _pending_effect.wanted_kind:
							found = i
							break
					if found >= 0:
						var got: Card = target.hand[found]
						target.hand.remove_at(found)
						_players[actor].hand.append(got)
						_emit("%s 手里有【%s】，必须交给 %s" % [
							target.name, Card.display_name(got.kind), _players[actor].name])
					else:
						_emit("%s 手里没有【%s】，无事发生" % [
							target.name, Card.display_name(_pending_effect.wanted_kind)])
					_pending_effect = {}
					_end_turn()
				"flush":
					if _deck.discard_count() == 0:
						_emit("弃牌堆为空，五张组合无事发生")
						_pending_effect = {}
						_end_turn()
					else:
						_current = actor
						phase = TurnPhase.FLUSH_PICK
						_pending_effect = {}
				_:
					_pending_effect = {}
					_end_turn()
		_:
			_pending_effect = {}
			_end_turn()


## MECH-013 五张结算：从弃牌堆任选 1 张入手，回合结束。
func flush_pick(discard_index: int) -> void:
	if phase != TurnPhase.FLUSH_PICK:
		push_error("当前不在弃牌堆选牌阶段")
		return
	var card := _deck.take_from_discard(discard_index)
	if card == null:
		push_error("弃牌堆下标非法")
		return
	current().hand.append(card)
	_emit("%s 从弃牌堆回收 1 张【%s】" % [current().name, Card.display_name(card.kind)])
	_end_turn()


# ---- 抽牌 ----

## 正常抽牌（含攻击叠层：连续抽满 _required_draws 次）。抽到非爆弹 → 回合结束（MECH-009 v0.6）。
func normal_draw() -> void:
	if phase != TurnPhase.ACTION:
		push_error("当前阶段不可正常抽牌")
		return

	var card := _deck.try_draw_top()
	if card == null:
		# MECH-011 兜底：弃牌堆也为空，跳过回合
		_emit("牌池与弃牌堆均耗尽，" + current().name + " 跳过回合")
		_end_turn()
		return

	if card.kind == Card.Kind.BOMB:
		_resolve_bomb(card, false)
		return

	current().hand.append(card)
	_required_draws -= 1
	_emit(current().name + " 抽到一张【" + Card.display_name(card.kind) + "】，回合结束")
	if _required_draws <= 0:
		_end_turn()


# ---- 透支阶段（MECH-008）----

## 透支中抽一张。非爆弹入透支区（面朝上）；爆弹则透支区全弃并按拆除结算。
func overdraw_draw() -> void:
	if phase != TurnPhase.OVERDRAW:
		push_error("当前不在透支阶段")
		return

	var card := _deck.try_draw_top()
	if card == null:
		_emit("牌池与弃牌堆均耗尽，透支中止")
		stop_overdraw()
		return

	if card.kind == Card.Kind.BOMB:
		var zone_count := current().overdraw_zone.size()
		_discard_overdraw_zone()
		_emit("透支抽到爆弹！透支区 %d 张全弃" % zone_count)
		_resolve_bomb(card, true)
		return

	current().overdraw_zone.append(card)
	_emit("透支 +1：【%s】进透支区（共 %d 张，喊停全部入手，抽中爆弹全弃）" % [Card.display_name(card.kind), current().overdraw_zone.size()])


## MECH-008：喊停——透支区全部入手；v0.6 起喊停即回合结束。
func stop_overdraw() -> void:
	if phase != TurnPhase.OVERDRAW:
		push_error("当前不在透支阶段")
		return
	for card in current().overdraw_zone:
		current().hand.append(card)
	_emit(current().name + " 喊停，收入 %d 张，回合结束" % current().overdraw_zone.size())
	current().overdraw_zone.clear()
	_end_turn()


## MECH-002：确认爆弹暗置位置（0..牌堆张数），随后回合结束。
func confirm_bomb_placement(index: int) -> void:
	if phase != TurnPhase.BOMB_PLACEMENT:
		push_error("当前不在爆弹暗置阶段")
		return
	_deck.insert_at(_bomb_to_place, index)
	_emit(current().name + " 将爆弹暗置回牌堆（仅其本人知道位置），回合结束")
	_bomb_to_place = null
	phase = TurnPhase.ACTION
	_end_turn()


# ---- 内部 ----

func _resolve_bomb(bomb: Card, from_overdraw: bool) -> void:
	if current().has_defuse():
		var idx := current().defuse_index()
		_deck.send_to_discard(current().hand[idx])
		current().hand.remove_at(idx)
		_bomb_to_place = bomb
		phase = TurnPhase.BOMB_PLACEMENT
		_emit(current().name + " 使用拆除卡！请选择爆弹暗置位置 0-%d" % _deck.draw_count())
	else:
		_deck.send_to_exploded(bomb)
		exploded_bombs_total += 1
		current().eliminate()
		bomb_exploded.emit(current().name)
		_emit("轰！%s 被炸出局（第 %d 枚爆弹引爆）" % [current().name, exploded_bombs_total])
		if from_overdraw:
			_discard_overdraw_zone()
		_end_turn()


func _discard_overdraw_zone() -> void:
	for card in current().overdraw_zone:
		_deck.send_to_discard(card)
	current().overdraw_zone.clear()


func _end_turn() -> void:
	var alive := _players.filter(func(pl: PlayerState) -> bool: return pl.alive)
	if alive.size() <= 1:
		winner = alive[0] if alive.size() == 1 else null
		phase = TurnPhase.GAME_OVER
		if winner != null:
			_emit("游戏结束：唯一赢家是 %s（所有爆弹均已引爆）" % winner.name)
		else:
			_emit("游戏结束：无存活玩家")
		return

	while true:
		_current = (_current + 1) % _players.size()
		if _players[_current].alive:
			break

	_required_draws = maxi(1, _pending_draws)
	_pending_draws = 0
	_overdraw_used_this_turn = false
	_pending_effect = {}
	phase = TurnPhase.ACTION
	var suffix := ""
	if _required_draws > 1:
		suffix = "（被攻击，须抽 %d 次）" % _required_draws
	_emit("当前回合：" + current().name + suffix)


func _take_from_hand(hand_index: int) -> Card:
	if phase != TurnPhase.ACTION:
		push_error("当前阶段不可出牌")
		return null
	var card := current().hand[hand_index]
	current().hand.remove_at(hand_index)
	return card
