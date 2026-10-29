# @trace MECH-001..009, MECH-011, NUM-001, NUM-002, LEV-001
## 无头自检：验证牌组构成、发牌、弃牌堆重洗、透支、偷牌、胜利条件与整局收敛。
## 运行方式（可复现）：
##   Godot --headless --path . --import
##   Godot --headless --path . -s res://tests/run_tests.gd
## 退出码 0 = 全部通过；非 0 = 存在失败用例。
extends SceneTree

const Card = preload("res://scripts/core/card.gd")
const Deck = preload("res://scripts/core/deck.gd")
const GameConfig = preload("res://scripts/data/game_config.gd")
const SeededRandom = preload("res://scripts/core/random_service.gd")
const TurnStateMachine = preload("res://scripts/gameplay/turn_state_machine.gd")

var _failures: PackedStringArray = []


func _initialize() -> void:
	_test_config_validation()
	_test_deck_composition()
	_test_dealing()
	_test_discard_refill()
	_test_turn_rotation()
	_test_overdraw_stop()
	_test_overdraw_bomb()
	_test_wish_counter()
	_test_pliers_trio()
	_test_pliers_flush()
	_test_pliers_validation()
	_test_single_plier()
	_test_steal()
	_test_full_games()
	_report()


## v0.6：响应窗口内全部玩家不休想（测试辅助）。
func _resolve_responses(machine: TurnStateMachine) -> void:
	var guard := 0
	while machine.phase == TurnStateMachine.TurnPhase.RESPONSE and guard < 20:
		machine.respond_wish(false)
		guard += 1


func _check(condition: bool, case_name: String) -> void:
	if condition:
		print("  PASS  " + case_name)
	else:
		_failures.append(case_name)
		print("  FAIL  " + case_name)


func _new_machine(player_names: PackedStringArray, seed_value: int) -> TurnStateMachine:
	var rng := SeededRandom.new(seed_value)
	var machine := TurnStateMachine.new(Deck.new(rng), GameConfig.new(), rng)
	machine.start_game(player_names, seed_value)
	return machine


# NUM-002 v0.9：功能牌总数恒为 48（12 种各 4 张）；NUM-001：爆弹=拆除=玩家数−1
func _test_config_validation() -> void:
	print("[1] 数值配置校验（NUM-001/NUM-002）")
	var config := GameConfig.new()
	_check(config.total_func_cards() == 48, "功能牌总数应为 48，实际 %d" % config.total_func_cards())
	_check(config.overdraw_count == 4, "透支牌 4 张")
	_check(config.total_pliers() == 20, "拆弹工具类合计 20 张，实际 %d" % config.total_pliers())
	_check(config.pliers_counts() == PackedInt32Array([4, 4, 4, 4, 4]),
			"5 种工具等量各 4 张（v0.9 用户拍板）")
	_check(config.wish_count == 4, "休想牌 4 张")
	_check(config.validate().is_empty(), "配置校验无警告")
	var ok := true
	for p in range(2, 6):
		if config.bomb_count_for(p) != p - 1 or config.defuse_in_pile_for(p) != p - 1:
			ok = false
	_check(ok, "爆弹数与牌堆拆除数均 = 玩家数 − 1")


func _test_deck_composition() -> void:
	print("[2] 牌组构成（NUM-001/NUM-002）")
	var config := GameConfig.new()
	var rng := SeededRandom.new(42)
	var deck := Deck.new(rng)
	# 4 人局：48 功能 + 3 爆弹 + 3 拆除 = 54
	deck.build(4, config.skip_count, config.attack_count, config.peek_count,
			config.shuffle_count, config.steal_count, config.overdraw_count,
			config.pliers_counts(), config.wish_count, 3, 3)
	_check(deck.draw_count() == 54, "4 人局整副 54 张，实际 %d" % deck.draw_count())
	var counts := {}
	for i in 54:
		var card := deck.try_draw_top()
		counts[card.kind] = counts.get(card.kind, 0) + 1
	_check(counts.get(Card.Kind.SKIP, 0) == 4, "跳过 4 张")
	_check(counts.get(Card.Kind.ATTACK, 0) == 4, "攻击 4 张")
	_check(counts.get(Card.Kind.PEEK, 0) == 4, "预知 4 张")
	_check(counts.get(Card.Kind.SHUFFLE, 0) == 4, "洗牌 4 张")
	_check(counts.get(Card.Kind.STEAL, 0) == 4, "偷牌 4 张")
	_check(counts.get(Card.Kind.OVERDRAW, 0) == 4, "透支 4 张")
	var plier_ok := true
	for kind_plier in Card.plier_kind_list():
		if counts.get(kind_plier, 0) != 4:
			plier_ok = false
	_check(plier_ok, "5 种工具各 4 张")
	_check(counts.get(Card.Kind.WISH, 0) == 4, "休想 4 张")
	_check(counts.get(Card.Kind.DEFUSE, 0) == 3, "牌堆中拆除 3 张")
	_check(counts.get(Card.Kind.BOMB, 0) == 3, "爆弹 3 枚")


func _test_dealing() -> void:
	print("[3] 发牌规则（NUM-001：每人 4 功能 + 1 拆除）")
	var machine := _new_machine(PackedStringArray(["甲", "乙", "丙", "丁"]), 7)
	var ok := true
	for player in machine.players():
		var func_n := 0
		var defuse_n := 0
		for card in player.hand:
			if card.kind == Card.Kind.DEFUSE:
				defuse_n += 1
			else:
				func_n += 1
		if func_n != 4 or defuse_n != 1:
			ok = false
	_check(ok, "每名玩家恰好 4 功能牌 + 1 拆除牌")
	# 牌池 = 48−16 + 3爆弹 + 3拆除 = 38（NUM-001 v0.9：R = 46 − 2P）
	_check(machine.draw_pile_count() == 38, "开局牌池 38 张，实际 %d" % machine.draw_pile_count())


func _test_discard_refill() -> void:
	print("[4] 弃牌堆重洗（MECH-011）")
	var config := GameConfig.new()
	var rng := SeededRandom.new(99)
	var deck := Deck.new(rng)
	deck.build(2, 6, 5, 6, 4, 5, 4, PackedInt32Array([3, 3, 3, 3, 3]), 4, 1, 1)
	var draw_pile: Array[Card] = []
	while true:
		var card := deck.try_draw_top()
		if card == null:
			break
		draw_pile.append(card)
	_check(deck.draw_count() == 0, "抽干牌池")
	var first := deck.try_draw_top()
	_check(first == null, "弃牌堆为空时抽牌失败")
	for card in draw_pile:
		if card.kind != Card.Kind.BOMB:
			deck.send_to_discard(card)
	var recovered := deck.try_draw_top()
	_check(recovered != null, "弃牌重洗后可继续抽牌（MECH-011）")


func _test_turn_rotation() -> void:
	print("[5] 轮转规则 v0.6：出 1 张功能牌 / 抽 1 张牌后立即轮到下一位（MECH-009）")
	var machine := _new_machine(PackedStringArray(["甲", "乙", "丙"]), 31)
	var first := machine.current_index()
	var idx := -1
	for i in machine.current().hand.size():
		if machine.current().hand[i].kind == Card.Kind.SHUFFLE:
			idx = i
			break
	if idx < 0:
		machine.current().hand.append(Card.new(Card.Kind.SHUFFLE, 9998))
		idx = machine.current().hand.size() - 1
	machine.play_shuffle(idx)
	# v0.9.1：一律进入匿名响应倒计时（不暴露持牌信息），无人反制即结算
	_check(machine.phase == TurnStateMachine.TurnPhase.RESPONSE, "出牌后进入匿名响应倒计时")
	_check(machine.respond_wish(false), "无人反制，效果结算")
	_check(machine.phase == TurnStateMachine.TurnPhase.ACTION, "结算后回到 ACTION")
	_check(machine.current_index() != first, "打出 1 张功能牌后轮到下一位")

	# 抽 1 张牌也轮转（抽到爆弹则按拆除结算后轮转；全员出局则跳过校验）
	var before := machine.current_index()
	machine.normal_draw()
	if machine.phase == TurnStateMachine.TurnPhase.BOMB_PLACEMENT:
		machine.confirm_bomb_placement(0)
	if machine.phase != TurnStateMachine.TurnPhase.GAME_OVER:
		_check(machine.current_index() != before, "抽 1 张牌后回合结束轮转")
	else:
		print("  SKIP  该种子下抽牌直接终局，轮转校验跳过")


func _test_overdraw_stop() -> void:
	print("[6] 透支·喊停（MECH-008：打出透支牌→响应→连抽→喊停即回合结束）")
	var machine := _new_machine(PackedStringArray(["甲", "乙", "丙"]), 11)
	var actor := machine.current()
	actor.hand.append(Card.new(Card.Kind.OVERDRAW, 9999))
	var before := actor.hand.size()
	_check(machine.play_overdraw(actor.hand.size() - 1), "打出透支牌进入响应窗口")
	_resolve_responses(machine)
	_check(machine.phase == TurnStateMachine.TurnPhase.OVERDRAW, "无人休想，进入透支连抽")
	machine.overdraw_draw()
	var zone_size := actor.overdraw_zone.size()
	_check(zone_size >= 0, "透支抽牌不崩溃")
	machine.stop_overdraw()
	_check(machine.phase == TurnStateMachine.TurnPhase.ACTION, "喊停后回合结束轮到下一位")
	_check(machine.current() != actor, "喊停后已轮转")
	_check(actor.hand.size() == before - 1 + zone_size, "打出透支牌 −1、透支区 %d 张入手，手牌 %d" % [zone_size, actor.hand.size()])
	_check(actor.overdraw_zone.is_empty(), "喊停后透支区清空")


func _test_overdraw_bomb() -> void:
	print("[7] 透支·抽到爆弹（MECH-008）")
	# 穷举多个种子，覆盖「抽到爆弹」分支
	var bomb_hit := false
	var valid_end := true
	for seed_value in range(1, 60):
		var machine := _new_machine(PackedStringArray(["甲", "乙"]), seed_value)
		var me := machine.current()
		me.hand.append(Card.new(Card.Kind.OVERDRAW, 9999))
		machine.play_overdraw(me.hand.size() - 1)
		_resolve_responses(machine)
		var guard := 0
		while machine.phase == TurnStateMachine.TurnPhase.OVERDRAW and guard < 200:
			machine.overdraw_draw()
			guard += 1
			if machine.current().overdraw_zone.is_empty() and machine.phase != TurnStateMachine.TurnPhase.OVERDRAW:
				# 透支区被清空 = 抽到爆弹（全弃）或透支中止
				if machine.phase == TurnStateMachine.TurnPhase.BOMB_PLACEMENT:
					bomb_hit = true
					machine.confirm_bomb_placement(0)
				break
		if machine.phase != TurnStateMachine.TurnPhase.ACTION \
				and machine.phase != TurnStateMachine.TurnPhase.OVERDRAW \
				and machine.phase != TurnStateMachine.TurnPhase.BOMB_PLACEMENT \
				and machine.phase != TurnStateMachine.TurnPhase.GAME_OVER:
			valid_end = false
	_check(bomb_hit, "60 个种子内覆盖到透支抽中爆弹分支")
	_check(valid_end, "透支流程终态全部合法")


func _test_wish_counter() -> void:
	print("[8] 休想·反制功能牌（MECH-012）")
	var machine := _new_machine(PackedStringArray(["甲", "乙", "丙"]), 17)
	var actor := machine.current()
	actor.hand.append(Card.new(Card.Kind.STEAL, 9997))
	var victim := machine.players()[1]
	var responder := machine.players()[2]
	var victim_count := victim.hand.size()
	# 乙给 1 张手牌作为将被偷的目标，丙持休想
	victim.hand.append(Card.new(Card.Kind.SKIP, 9996))
	responder.hand.append(Card.new(Card.Kind.WISH, 9995))
	_check(machine.play_steal(actor.hand.size() - 1, 1), "打出偷牌进入匿名响应窗口")
	_check(machine.phase == TurnStateMachine.TurnPhase.RESPONSE, "响应窗口开启（匿名，不暴露持牌者）")
	# v0.9.1：由持牌者本人主动打出（传入其下标），不再按座次轮询
	_check(machine.respond_wish(true, 2), "丙打出休想，偷牌失效")
	_check(machine.phase == TurnStateMachine.TurnPhase.ACTION, "休想后回合结束轮转")
	_check(victim.hand.size() == victim_count + 1, "偷牌失效：目标手牌未被偷走")
	_check(responder.hand.size() == 5, "休想牌已消耗（丙剩 5 张）")
	_check(not actor.alive == false, "打出者存活")
	# v0.9.1：无人持有休想牌也一律开匿名窗口（开窗本身不泄露任何信息）
	var m2 := _new_machine(PackedStringArray(["甲", "乙"]), 23)
	for pl in m2.players():
		for i in range(pl.hand.size() - 1, -1, -1):
			if pl.hand[i].kind == Card.Kind.WISH:
				pl.hand.remove_at(i)
	var a2 := m2.current()
	a2.hand.append(Card.new(Card.Kind.SKIP, 9994))
	m2.play_skip(a2.hand.size() - 1)
	_check(m2.phase == TurnStateMachine.TurnPhase.RESPONSE, "无人持休想：仍开匿名窗口")
	_check(not m2.respond_wish(true, 1), "无牌者尝试反制被拒绝（乙没有休想）")
	_check(m2.respond_wish(false), "无人反制，效果结算")
	_check(m2.phase == TurnStateMachine.TurnPhase.ACTION, "结算后轮转")


func _test_pliers_trio() -> void:
	print("[9] 工具·三条：同种×3 念牌名索要（MECH-013 v0.7）")
	var machine := _new_machine(PackedStringArray(["甲", "乙"]), 19)
	var actor := machine.current()
	var target := machine.players()[1]
	actor.hand.append(Card.new(Card.Kind.PLIERS_TIGER, 9985))
	actor.hand.append(Card.new(Card.Kind.PLIERS_TIGER, 9986))
	actor.hand.append(Card.new(Card.Kind.PLIERS_TIGER, 9987))
	target.hand.clear()
	target.hand.append(Card.new(Card.Kind.ATTACK, 9988))
	var indices: Array[int] = [actor.hand.size() - 3, actor.hand.size() - 2, actor.hand.size() - 1]
	_check(machine.play_pliers(indices, "trio", 1, Card.Kind.ATTACK), "同种×3 打出三条（无人持休想直接结算）")
	_resolve_responses(machine)
	_check(machine.phase == TurnStateMachine.TurnPhase.ACTION, "三条结算后回合结束")
	var found := false
	for card in actor.hand:
		if card.kind == Card.Kind.ATTACK:
			found = true
	_check(found, "目标有念名的【攻击】，必须交出")
	_check(target.hand.is_empty(), "目标交出后无该牌")


func _test_pliers_flush() -> void:
	print("[10] 工具·五张：五种各×1 弃牌堆回收（MECH-013 v0.7）")
	var machine := _new_machine(PackedStringArray(["甲", "乙"]), 23)
	var actor := machine.current()
	# 保证弃牌堆非空：打出 1 张跳过并让它结算
	actor.hand.append(Card.new(Card.Kind.SKIP, 9979))
	machine.play_skip(actor.hand.size() - 1)
	_resolve_responses(machine)
	var discard_n := machine.discard_count()
	_check(discard_n >= 1, "弃牌堆有牌可回收（%d 张）" % discard_n)
	# 现在轮到乙；把 5 种工具各 1 张塞给当前玩家测试
	var cur := machine.current()
	var kinds := Card.plier_kind_list()
	for i in 5:
		cur.hand.append(Card.new(kinds[i], 9980 + i))
	var indices: Array[int] = []
	for i in 5:
		indices.append(cur.hand.size() - 5 + i)
	_check(machine.play_pliers(indices, "flush"), "五种各×1 打出五张（无人持休想直接结算）")
	_resolve_responses(machine)
	_check(machine.phase == TurnStateMachine.TurnPhase.FLUSH_PICK, "进入弃牌堆选牌阶段")
	machine.flush_pick(0)
	_check(machine.phase == TurnStateMachine.TurnPhase.ACTION, "回收后回合结束")
	_check(cur.hand.any(func(c: Card) -> bool: return c.kind == Card.Kind.SKIP), "回收到了弃牌堆中的【跳过】")


func _test_pliers_validation() -> void:
	print("[11] 工具·组合校验：异种不可成对子/三条（MECH-013 v0.7）")
	var machine := _new_machine(PackedStringArray(["甲", "乙"]), 41)
	var actor := machine.current()
	actor.hand.append(Card.new(Card.Kind.PLIERS_TIGER, 9960))
	actor.hand.append(Card.new(Card.Kind.PLIERS_PIPE, 9961))
	var bad_indices: Array[int] = [actor.hand.size() - 2, actor.hand.size() - 1]
	_check(not machine.play_pliers(bad_indices, "pair", 1), "异种×2 不可打对子")
	_check(machine.phase == TurnStateMachine.TurnPhase.ACTION, "校验失败不改变阶段")
	_check(actor.hand.size() >= 2, "校验失败的牌退回手牌未消耗")
	# 同种×2 合法
	actor.hand.append(Card.new(Card.Kind.PLIERS_CUTTER, 9962))
	actor.hand.append(Card.new(Card.Kind.PLIERS_CUTTER, 9963))
	var good_indices: Array[int] = [actor.hand.size() - 2, actor.hand.size() - 1]
	var hand_size_before_pair := actor.hand.size()
	if _pick_steal_target(machine) < 0:
		machine.players()[1].hand.append(Card.new(Card.Kind.PEEK, 9964))
	_check(machine.play_pliers(good_indices, "pair", 1), "同种×2 可打对子")
	_resolve_responses(machine)
	_check(machine.phase == TurnStateMachine.TurnPhase.ACTION, "对子（随机盲偷）结算后回合结束")
	_check(actor.hand.size() == hand_size_before_pair - 1, "对子净结算：耗 2 张工具、偷进 1 张（v0.8 随机盲偷不亮牌）")


func _test_single_plier() -> void:
	print("[11b] 工具·单张打出：无效果弃置并结束回合（MECH-013 v0.9.2）")
	var machine := _new_machine(PackedStringArray(["甲", "乙"]), 53)
	var actor := machine.current()
	actor.hand.append(Card.new(Card.Kind.PLIERS_NEEDLE, 9959))
	var hand_size := actor.hand.size()
	var idx := hand_size - 1
	_check(machine.play_single_plier(idx), "单张工具牌可直接打出")
	_check(machine.phase == TurnStateMachine.TurnPhase.ACTION, "无效果直接结束回合（不开响应窗口）")
	_check(machine.current_index() != 0, "打出后轮到下一位")
	_check(actor.hand.size() == hand_size - 1, "该工具牌已离手")
	var in_discard := false
	for card in machine.discard_cards():
		if card.id == 9959:
			in_discard = true
	_check(in_discard, "打出的工具牌进了弃牌堆")
	# 非工具牌不可单张打出
	var machine2 := _new_machine(PackedStringArray(["甲", "乙"]), 54)
	machine2.current().hand.append(Card.new(Card.Kind.SKIP, 9958))
	_check(not machine2.play_single_plier(machine2.current().hand.size() - 1),
			"非工具牌不可走单张打出")


func _test_steal() -> void:
	print("[12] 偷牌（MECH-007）")
	var machine := _new_machine(PackedStringArray(["甲", "乙"]), 29)
	var me := machine.current()
	var other := machine.players()[1]
	var my_count := me.hand.size()
	var other_count := other.hand.size()
	var steal_index := -1
	for i in me.hand.size():
		if me.hand[i].kind == Card.Kind.STEAL:
			steal_index = i
			break
	if steal_index < 0:
		me.hand.append(Card.new(Card.Kind.STEAL, 9999))
		steal_index = me.hand.size() - 1
		my_count = me.hand.size()
	var success := machine.play_steal(steal_index, 1)
	_check(success, "偷牌可正常打出")
	_resolve_responses(machine)
	_check(machine.phase == TurnStateMachine.TurnPhase.ACTION, "偷牌结算后回合结束")
	_check(me.hand.size() == my_count, "打出偷牌 −1、偷到 +1，手牌数不变（%d）" % me.hand.size())
	_check(other.hand.size() == other_count - 1, "目标少 1 张")


func _test_full_games() -> void:
	print("[13] 整局收敛与胜利条件（MECH-009 v0.7，含响应/工具组合阶段）")
	var all_finished := true
	var win_valid := true
	var bomb_total_valid := true
	var signal_fired_total := 0
	var total_games := 0
	for p in range(2, 6):
		for seed_value in range(1, 11):
			total_games += 1
			var names := PackedStringArray()
			for i in p:
				names.append("P%d" % (i + 1))
			var machine := _new_machine(names, seed_value * 100 + p)
			var signal_counter := {"count": 0}  # lambda 按值捕获局部变量，用容器才能累加
			machine.bomb_exploded.connect(func(_n: String) -> void: signal_counter["count"] += 1)
			var guard := 0
			while machine.phase != TurnStateMachine.TurnPhase.GAME_OVER and guard < 5000:
				guard += 1
				match machine.phase:
					TurnStateMachine.TurnPhase.ACTION:
						# 策略：先打光功能牌（出牌会切换阶段，须随检随退），再抽牌
						var played := true
						while played and machine.phase == TurnStateMachine.TurnPhase.ACTION:
							played = false
							var me := machine.current()
							for i in me.hand.size():
								var kind: int = me.hand[i].kind
								if kind == Card.Kind.SKIP:
									machine.play_skip(i)
									played = true
									break
								elif kind == Card.Kind.ATTACK:
									machine.play_attack(i)
									played = true
									break
								elif kind == Card.Kind.PEEK:
									machine.play_peek(i)
									played = true
									break
								elif kind == Card.Kind.SHUFFLE:
									machine.play_shuffle(i)
									played = true
									break
								elif kind == Card.Kind.STEAL:
									var target := _pick_steal_target(machine)
									if target >= 0 and machine.play_steal(i, target):
										played = true
										break
								elif kind == Card.Kind.OVERDRAW:
									if not machine.overdraw_used_this_turn() and machine.play_overdraw(i):
										played = true
										break
								elif Card.is_plier(kind):
									# 有同种×2 工具就打对子
									var by_kind := {}
									for j in me.hand.size():
										if Card.is_plier(me.hand[j].kind):
											var k: int = me.hand[j].kind
											if not by_kind.has(k):
												by_kind[k] = []
											by_kind[k].append(j)
									for k in by_kind:
										if by_kind[k].size() >= 2:
											var pliers_idx: Array[int] = [by_kind[k][0], by_kind[k][1]]
											var ptarget := _pick_steal_target(machine)
											if ptarget >= 0 and machine.play_pliers(pliers_idx, "pair", ptarget):
												played = true
											break
									if played:
										break
						if machine.phase == TurnStateMachine.TurnPhase.ACTION:
							machine.normal_draw()
					TurnStateMachine.TurnPhase.OVERDRAW:
						machine.stop_overdraw()
					TurnStateMachine.TurnPhase.RESPONSE:
						machine.respond_wish(false)
					TurnStateMachine.TurnPhase.FLUSH_PICK:
						machine.flush_pick(0)
					TurnStateMachine.TurnPhase.BOMB_PLACEMENT:
						machine.confirm_bomb_placement(machine.bomb_placement_range())
			if machine.phase != TurnStateMachine.TurnPhase.GAME_OVER:
				all_finished = false
				continue
			# 胜利条件校验
			if machine.winner == null or not machine.winner.alive:
				win_valid = false
			var alive_count := 0
			for player in machine.players():
				if player.alive:
					alive_count += 1
			if alive_count != 1:
				win_valid = false
			if machine.exploded_bombs_total != p - 1:
				bomb_total_valid = false
			signal_fired_total += int(signal_counter["count"])
	_check(all_finished, "%d 局全部在步数上限内打完（2-5 人 × 10 种子）" % total_games)
	_check(win_valid, "终局均为唯一存活赢家（胜利条件 MECH-009）")
	_check(bomb_total_valid, "每局引爆爆弹数 = 玩家数 − 1")
	var expected_explosions := 0
	for p in range(2, 6):
		expected_explosions += 10 * (p - 1)
	_check(signal_fired_total == expected_explosions,
			"bomb_exploded 信号每次引爆都触发（共 %d 次）" % expected_explosions)


## 找一个有手牌的合法偷牌/对子目标。
func _pick_steal_target(machine: TurnStateMachine) -> int:
	for t in machine.players().size():
		if t != machine.current_index() \
				and machine.players()[t].alive \
				and not machine.players()[t].hand.is_empty():
			return t
	return -1


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("全部自检通过 ✅")
		quit(0)
	else:
		print("失败 %d 项：" % _failures.size())
		for failure in _failures:
			print("  - " + failure)
		quit(1)
