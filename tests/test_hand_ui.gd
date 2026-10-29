extends SceneTree
## [UI-2] 手牌展示回归：牌多时的扇形布局、悬停让位、手牌全览面板。
## 背景：手牌一多就挤成一团看不清；此前只有协议层冒烟，UI 层无人验证，
## 曾漏掉「抽牌按钮容器 hidden」「等待时手牌被压透明」这类纯 UI bug。
## 这里用合成方式直接驱动 net_main 的手牌渲染，验证位置/可见性/让位。

var _passes := 0
var _failures := 0


func _initialize() -> void:
	await _test_big_hand_layout()
	await _test_small_hand_layout()
	await _test_hover_shift()
	await _test_overview_panel()
	await _test_action_fx()
	print("逻辑自检：%d 通过，%d 失败" % [_passes, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("PASS  ", label)
	else:
		_failures += 1
		print("FAIL  ", label)


func _new_scene() -> Control:
	var scene: Control = load("res://scenes/net_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame      # 等 _ready 把 UI 骨架建好
	return scene


## 构造一份最小可用视图：hand 为牌种类数组。
func _set_hand(scene: Control, kinds: Array) -> void:
	scene.my_seat = 0
	scene.view = {
		"phase": "action", "your_turn": true, "hand": kinds,
		"players": [{"name": "甲", "count": kinds.size(), "alive": true, "on": true, "cur": true},
				{"name": "乙", "count": 5, "alive": true, "on": true, "cur": false}],
	}


func _rebuild(scene: Control, kinds: Array) -> void:
	_set_hand(scene, kinds)
	scene._rebuild_hand([], true, true)
	# _layout_hand 内部要等一帧拿尺寸，这里多等两帧
	await process_frame
	await process_frame


## [UI-2.1] 15 张大手牌：不能重叠到看不见，也不能溢出屏幕。
func _test_big_hand_layout() -> void:
	print("[UI-2.1] 大手牌扇形布局")
	var scene := await _new_scene()
	var kinds: Array = []
	for i in 15:
		kinds.append(Card.Kind.SKIP)
	await _rebuild(scene, kinds)
	_check(scene._hand_cards.size() == 15, "15 张手牌全部建出")
	var min_gap := 9999.0
	for i in range(1, scene._hand_cards.size()):
		var gap: float = scene._hand_cards[i].position.x - scene._hand_cards[i - 1].position.x
		min_gap = minf(min_gap, gap)
	_check(min_gap >= scene.HAND_MIN_STEP - 0.5,
			"相邻手牌间距 %.1f ≥ 最小露出宽度 %.1f" % [min_gap, scene.HAND_MIN_STEP])
	var first: Control = scene._hand_cards[0]
	var last: Control = scene._hand_cards[-1]
	_check(first.position.x >= 0.0, "最左不越界（x=%.1f）" % first.position.x)
	_check(last.position.x + CardView.CARD_SIZE.x <= 1280.0,
			"最右不越界（右边缘 %.1f）" % (last.position.x + CardView.CARD_SIZE.x))
	_check(scene._overview_btn.visible, "手牌 ≥9 张时显示「手牌全览」按钮")
	# 悬停层级：右侧压左侧，保证从左到右能依次阅读
	_check(scene._hand_cards[0].z_index < scene._hand_cards[14].z_index,
			"手牌 z 序从左到右递增")
	scene.queue_free()


## [UI-2.2] 5 张小手牌：应该舒展排布，不出现全览按钮。
func _test_small_hand_layout() -> void:
	print("[UI-2.2] 小手牌舒展排布")
	var scene := await _new_scene()
	var kinds: Array = []
	for i in 5:
		kinds.append(Card.Kind.SHUFFLE)
	await _rebuild(scene, kinds)
	var gap: float = scene._hand_cards[1].position.x - scene._hand_cards[0].position.x
	_check(absf(gap - scene.HAND_IDEAL_STEP) < 0.5,
			"牌少时用理想间距 %.0f（实际 %.1f）" % [scene.HAND_IDEAL_STEP, gap])
	_check(not scene._overview_btn.visible, "手牌 <9 张时不显示全览按钮")
	scene.queue_free()


## [UI-2.3] 悬停让位：悬停牌两侧的手牌向两边让开。
func _test_hover_shift() -> void:
	print("[UI-2.3] 悬停让位")
	var scene := await _new_scene()
	var kinds: Array = []
	for i in 12:
		kinds.append(Card.Kind.PEEK)
	await _rebuild(scene, kinds)
	var base_left: float = scene._hand_cards[3].position.x
	var base_right: float = scene._hand_cards[5].position.x
	scene._on_card_hover(4)
	await create_timer(0.25).timeout
	_check(scene._hand_cards[3].position.x < base_left - 20.0,
			"悬停牌左侧向左让位（%.1f → %.1f）" % [base_left, scene._hand_cards[3].position.x])
	_check(scene._hand_cards[5].position.x > base_right + 20.0,
			"悬停牌右侧向右让位（%.1f → %.1f）" % [base_right, scene._hand_cards[5].position.x])
	scene._on_card_unhover()
	await create_timer(0.25).timeout
	_check(absf(scene._hand_cards[3].position.x - base_left) < 1.0,
			"移开鼠标后手牌归位")
	scene.queue_free()


## [UI-2.4] 手牌全览面板：网格铺开全部手牌，点一张即关闭。
func _test_overview_panel() -> void:
	print("[UI-2.4] 手牌全览面板")
	var scene := await _new_scene()
	var kinds: Array = []
	for i in 14:
		kinds.append(Card.Kind.DEFUSE)
	await _rebuild(scene, kinds)
	scene._show_hand_overview()
	_check(scene._hand_overview != null, "全览面板已创建")
	var grid: GridContainer = _find_grid(scene._hand_overview)
	_check(grid != null, "面板内含网格容器")
	_check(grid != null and grid.get_child_count() == 14, "网格内 14 张牌全部铺开")
	scene._close_hand_overview()
	_check(scene._hand_overview == null, "关闭后面板引用已清空")
	scene.queue_free()


## [UI-2.5] 动作演出：偷牌要有飞牌 + 横幅，洗牌要有横幅（且都不能报错）。
func _test_action_fx() -> void:
	print("[UI-2.5] 动作演出（偷牌/洗牌）")
	var scene := await _new_scene()
	var kinds: Array = [Card.Kind.STEAL, Card.Kind.SHUFFLE]
	await _rebuild(scene, kinds)
	scene._on_fx({"fx": NetProtocol.FX_STEAL, "actor": 0, "target": 1,
			"kind": -1, "count": 1})
	await process_frame
	var flying := 0
	for child in scene._fx_layer.get_children():
		if child is CardView:
			flying += 1
	_check(flying >= 1, "偷牌生成了飞行的牌（%d 张）" % flying)
	await process_frame
	_check(scene._banner != null and is_instance_valid(scene._banner),
			"偷牌显示动作横幅")
	scene._on_fx({"fx": NetProtocol.FX_SHUFFLE, "actor": 0, "target": -1,
			"kind": -1, "count": 1})
	await process_frame
	await process_frame
	_check(scene._banner != null and is_instance_valid(scene._banner),
			"洗牌显示动作横幅（牌堆抖动）")
	scene.queue_free()


func _find_grid(node: Node) -> GridContainer:
	if node is GridContainer:
		return node
	for child in node.get_children():
		var found := _find_grid(child)
		if found != null:
			return found
	return null
