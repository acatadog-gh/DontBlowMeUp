# @trace NUM-001, NUM-002, LEV-001, MECH-012, MECH-013
## 全部可调数值集中在数据类（架构约束：数值不写死在玩法脚本里）。
## 默认值来自策划案冻结清单 NUM-001 / NUM-002。
## v0.9（2026-10-29 用户拍板）：全等量配比——12 种功能牌各 4 张，共 48 张。
## 移植自 Unity 版 Data/GameConfig.cs，逻辑 1:1。
class_name GameConfig
extends RefCounted

## 功能牌数量（NUM-002 v0.9，合计 48：跳过4/攻击4/预知4/洗牌4/偷牌4/透支4/休想4/工具5种各4）
var skip_count := 4
var attack_count := 4
var peek_count := 4
var shuffle_count := 4
var steal_count := 4
var overdraw_count := 4
# MECH-013 拆弹工具类（v0.9 用户拍板：5 种等量各 4 张；效果由组合规模决定，与种类无关）
var pliers_tiger_count := 4      # 老虎钳
var pliers_needle_count := 4     # 尖嘴钳
var pliers_pipe_count := 4       # 管钳
var pliers_cutter_count := 4     # 断线钳
var pliers_hydraulic_count := 4  # 液压钳
var wish_count := 4

## 发牌（NUM-001）
var func_cards_per_player := 4

## 人数档位（LEV-001）
var min_players := 2
var max_players := 5


## 拆弹工具各类张数（build 用）。
func pliers_counts() -> PackedInt32Array:
	return PackedInt32Array([pliers_tiger_count, pliers_needle_count,
			pliers_pipe_count, pliers_cutter_count, pliers_hydraulic_count])


## 拆弹工具总张数（v0.7 = 14）。
func total_pliers() -> int:
	var total := 0
	for count in pliers_counts():
		total += count
	return total


## 功能牌总数，应恒等于 48（NUM-002 v0.9：12 种功能牌各 4 张）。
func total_func_cards() -> int:
	return skip_count + attack_count + peek_count + shuffle_count + steal_count \
			+ overdraw_count + total_pliers() + wish_count


## 爆弹数 = 玩家数 − 1（NUM-001）。
func bomb_count_for(player_count: int) -> int:
	return player_count - 1


## 牌堆中拆除数 = 玩家数 − 1（NUM-001）。
func defuse_in_pile_for(player_count: int) -> int:
	return player_count - 1


## 校验数值一致性（对应 Unity 版 OnValidate）。返回警告列表，空列表 = 通过。
func validate() -> PackedStringArray:
	var warnings := PackedStringArray()
	if total_func_cards() != 48:
		warnings.append("[GameConfig] 功能牌总数应为 48（NUM-002 v0.9），当前 %d" % total_func_cards())
	if pliers_tiger_count != pliers_needle_count or pliers_needle_count != pliers_pipe_count \
			or pliers_pipe_count != pliers_cutter_count or pliers_cutter_count != pliers_hydraulic_count:
		warnings.append("[GameConfig] 5 种拆弹工具应等量（v0.8 用户拍板）")
	func_cards_per_player = maxi(1, func_cards_per_player)
	min_players = maxi(2, min_players)
	max_players = clampi(max_players, min_players, 5)
	return warnings
