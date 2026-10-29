# @trace MECH-002, MECH-008, MECH-001
## 单个玩家状态：手牌、存活、透支区（MECH-008）。
## 移植自 Unity 版 Gameplay/PlayerState.cs，逻辑 1:1。
class_name PlayerState
extends RefCounted

var name: String
var alive := true
var hand: Array[Card] = []

## 透支区：面朝上公开，喊停全入手，炸则全弃（MECH-008）。
var overdraw_zone: Array[Card] = []


func _init(p_name: String) -> void:
	name = p_name


func has_defuse() -> bool:
	for card in hand:
		if card.kind == Card.Kind.DEFUSE:
			return true
	return false


func eliminate() -> void:
	alive = false


func defuse_index() -> int:
	for i in hand.size():
		if hand[i].kind == Card.Kind.DEFUSE:
			return i
	return -1


func func_card_count() -> int:
	var n := 0
	for card in hand:
		if card.kind != Card.Kind.BOMB:
			n += 1
	return n
