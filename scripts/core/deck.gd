# @trace MECH-001, MECH-011, NUM-001
## 公共牌池 + 弃牌堆。抽牌堆是全体玩家共享的公共牌池（用户已确认口径）。
## 牌堆耗尽时弃牌堆（不含已引爆爆弹）重洗为新牌堆（MECH-011）。
## 移植自 Unity 版 Core/Deck.cs，逻辑 1:1。
class_name Deck
extends RefCounted

var _draw: Array[Card] = []
var _discard: Array[Card] = []
var _exploded_bombs: Array[Card] = []
var _rng: SeededRandom
var _next_id := 0


func _init(rng: SeededRandom) -> void:
	_rng = rng


func draw_count() -> int:
	return _draw.size()


func discard_count() -> int:
	return _discard.size()


## 按 NUM-001 构建整副牌并洗混：bombs=P-1，defuse_in_pile=P-1，功能牌 49 张（v0.8 工具类 15 张等量）。
## pliers_counts 为 5 种拆弹工具各自的张数（MECH-013）。
func build(player_count: int, skip_count: int, attack_count: int, peek_count: int,
		shuffle_count: int, steal_count: int, overdraw_count: int,
		pliers_counts: PackedInt32Array, wish_count: int,
		bomb_count: int, defuse_in_pile_count: int) -> void:
	_draw.clear()
	_discard.clear()
	_exploded_bombs.clear()
	_next_id = 0

	_add_many(Card.Kind.SKIP, skip_count)
	_add_many(Card.Kind.ATTACK, attack_count)
	_add_many(Card.Kind.PEEK, peek_count)
	_add_many(Card.Kind.SHUFFLE, shuffle_count)
	_add_many(Card.Kind.STEAL, steal_count)
	_add_many(Card.Kind.OVERDRAW, overdraw_count)
	var plier_kinds := Card.plier_kind_list()
	for i in mini(pliers_counts.size(), plier_kinds.size()):
		_add_many(plier_kinds[i], pliers_counts[i])
	_add_many(Card.Kind.WISH, wish_count)
	_add_many(Card.Kind.DEFUSE, defuse_in_pile_count)
	_add_many(Card.Kind.BOMB, bomb_count)
	shuffle()


func _add_many(kind: Card.Kind, count: int) -> void:
	for i in count:
		_draw.append(Card.new(kind, _next_id))
		_next_id += 1


## 向牌堆追加单张牌（分阶段建牌用）。
func add_to_draw(card: Card) -> void:
	var new_id := card.id
	if new_id < 0:
		new_id = _next_id
		_next_id += 1
	_draw.append(Card.new(card.kind, new_id))


func shuffle() -> void:
	for i in range(_draw.size() - 1, 0, -1):
		var j := _rng.next(i + 1)
		var tmp := _draw[i]
		_draw[i] = _draw[j]
		_draw[j] = tmp


## 从牌堆顶抽 1 张；空则先执行 MECH-011 重洗。返回是否成功（失败时 card 为 null）。
func try_draw_top() -> Card:
	if _draw.is_empty():
		refill_from_discard()
	if _draw.is_empty():
		return null
	return _draw.pop_back()


## MECH-011：弃牌堆重洗为新牌堆（已引爆的爆弹不回收）。
func refill_from_discard() -> bool:
	if _discard.is_empty():
		return false
	for card in _discard:
		_draw.append(card)
	_discard.clear()
	shuffle()
	return true


## MECH-002：拆除救回的爆弹由玩家暗置回牌堆任意位置 0..Count。
func insert_at(card: Card, index: int) -> void:
	index = clampi(index, 0, _draw.size())
	_draw.insert(index, card)


func send_to_discard(card: Card) -> void:
	_discard.append(card)


## MECH-013 五张组合：读取弃牌堆内容（只读）。
func discard_list() -> Array[Card]:
	return _discard


## MECH-013 五张组合：从弃牌堆取走下标 index 的牌。
func take_from_discard(index: int) -> Card:
	if index < 0 or index >= _discard.size():
		return null
	var card := _discard[index]
	_discard.remove_at(index)
	return card


## 爆弹引爆：进入已引爆列表，永不回到牌堆。
func send_to_exploded(card: Card) -> void:
	_exploded_bombs.append(card)


## MECH-005：偷看牌堆顶 count 张（从顶往下）。
func peek_top(count: int) -> Array[Card]:
	var result: Array[Card] = []
	var i := _draw.size() - 1
	while i >= 0 and result.size() < count:
		result.append(_draw[i])
		i -= 1
	return result
