# @trace MECH-001, MECH-002, MECH-008, MECH-012, MECH-013, NUM-002
## 卡牌类型与单张牌。数量构成见冻结清单 NUM-002。
## 移植自 Unity 版 Core/Card.cs，逻辑 1:1；v0.6 新增休想（MECH-012）与钳子（MECH-013）。
class_name Card
extends RefCounted

enum Kind { SKIP, ATTACK, PEEK, SHUFFLE, STEAL, OVERDRAW,
		PLIERS_TIGER, PLIERS_NEEDLE, PLIERS_PIPE, PLIERS_CUTTER, PLIERS_HYDRAULIC,
		WISH, DEFUSE, BOMB }

var kind: Kind
var id: int


func _init(p_kind: Kind = Kind.SKIP, p_id: int = -1) -> void:
	kind = p_kind
	id = p_id


func _to_string() -> String:
	return "%s#%d" % [Kind.keys()[kind].to_lower(), id]


static func is_bomb(card: Card) -> bool:
	return card != null and card.kind == Kind.BOMB


static func is_defuse(card: Card) -> bool:
	return card != null and card.kind == Kind.DEFUSE


## MECH-013：拆弹工具类（5 种，规则上等价的收集标记，效果由组合决定）。
static func is_plier(kind: Kind) -> bool:
	return kind >= Kind.PLIERS_TIGER and kind <= Kind.PLIERS_HYDRAULIC


## 全部 5 种拆弹工具（组合与 UI 用）。
static func plier_kind_list() -> Array:
	return [Kind.PLIERS_TIGER, Kind.PLIERS_NEEDLE, Kind.PLIERS_PIPE,
			Kind.PLIERS_CUTTER, Kind.PLIERS_HYDRAULIC]


## 全部界面与日志统一使用的中文牌名
static func display_name(kind: Kind) -> String:
	match kind:
		Kind.SKIP:
			return "跳过"
		Kind.ATTACK:
			return "攻击"
		Kind.PEEK:
			return "预知"
		Kind.SHUFFLE:
			return "洗牌"
		Kind.STEAL:
			return "偷牌"
		Kind.OVERDRAW:
			return "透支"
		Kind.PLIERS_TIGER:
			return "老虎钳"
		Kind.PLIERS_NEEDLE:
			return "尖嘴钳"
		Kind.PLIERS_PIPE:
			return "管钳"
		Kind.PLIERS_CUTTER:
			return "断线钳"
		Kind.PLIERS_HYDRAULIC:
			return "液压钳"
		Kind.WISH:
			return "休想"
		Kind.DEFUSE:
			return "拆除"
		Kind.BOMB:
			return "爆弹"
	return "?"
