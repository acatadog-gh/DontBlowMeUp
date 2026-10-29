# @trace MECH-001
## 可指定种子的随机源（RandomNumberGenerator 包装）。
## 移植自 Unity 版 Core/RandomService.cs，逻辑 1:1。
class_name SeededRandom
extends RefCounted

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


func next(max_exclusive: int) -> int:
	return _rng.randi_range(0, max_exclusive - 1)
