# 输入链路诊断：无头实例化主场景，用 Viewport.push_input 模拟真实鼠标点击，
# 验证按钮能否被"真的点击"触发（区分代码 bug 与编辑器嵌入窗口环境问题）。
extends SceneTree

var _main: Control


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	_main = packed.instantiate()
	root.add_child(_main)
	# 无头模式默认窗口 64x64，手动放大到设计分辨率再测（canvas_items 拉伸下 scale=1）
	root.size = Vector2(1280, 720)
	await process_frame
	await process_frame

	# 开 4 人局
	_main._player_spin.value = 4
	_main._on_start_game()
	await process_frame
	var sm: TurnStateMachine = _main._sm
	print("[diag] 开局 phase=%s 当前=%s 手牌=%d" % [
		sm.phase, sm.current().name, sm.current().hand.size()])

	# ---- 测试 1：合成点击「抽一张牌」按钮 ----
	var draw_btn: Button = _find_button(_main._action_row, "抽一张牌")
	if draw_btn == null:
		print("[diag] FAIL 找不到抽牌按钮")
		quit(1)
		return
	draw_btn.pressed.connect(func() -> void: print("[diag] >>> draw_btn.pressed 信号已触发！"))
	var center: Vector2 = draw_btn.get_global_rect().get_center()
	print("[diag] root.size=%s visible_rect=%s content_scale=%s" % [
		root.size, root.get_visible_rect(), root.content_scale_factor])
	# 悬停后查询鼠标下命中的控件
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	root.push_input(motion)
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await process_frame
	var hovered: Control = root.gui_get_hovered_control()
	print("[diag] 按钮中心=%s push_input悬停=%s" % [center,
		hovered.name if hovered != null else "<无>"])
	# 打印整条布局链的矩形，定位坐标错位
	var action_row: Container = _main._action_row
	var row_parent: Control = action_row.get_parent()
	print("[diag] action_center rect=%s | action_row rect=%s size=%s 子节点数=%d" % [
		row_parent.get_global_rect(), action_row.get_global_rect(),
		action_row.size, action_row.get_child_count()])
	print("[diag] draw_btn rect=%s 可见=%s 禁用=%s" % [
		draw_btn.get_global_rect(), draw_btn.is_visible_in_tree(), draw_btn.disabled])
	if hovered != null and hovered != draw_btn:
		var chain: Array[String] = []
		var node: Node = hovered
		while node != null and node is Control:
			chain.append("%s(过滤=%s)" % [node.name, node.mouse_filter])
			node = node.get_parent()
		print("[diag] 命中控件链: ", " → ".join(chain))
	# 改用 Input.parse_input_event 模拟点击（真实输入管线）
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = center
	press.global_position = center
	Input.parse_input_event(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = center
	release.global_position = center
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await process_frame
	await process_frame
	var advanced: bool = sm.current_index() != 0
	print("[diag] 测试1 点击抽牌按钮(parse_input_event) → 回合推进=%s" % advanced)

	# ---- 测试 2：合成点击一张手牌（工具牌→选中；功能牌→打出）----
	await process_frame
	var phase_now: int = sm.phase
	print("[diag] 测试2 当前 phase=%s" % phase_now)
	if sm.phase == TurnStateMachine.TurnPhase.ACTION and _main._hand_cards.size() > 0:
		var card_view: CardView = _main._hand_cards[0]
		var kind_before: int = sm.current().hand[0].kind
		var hand_before: int = sm.current().hand.size()
		_click_control(card_view)
		await process_frame
		await process_frame
		var hand_after: int = sm.current().hand.size()
		print("[diag] 测试2 点击手牌0（%s）: 手牌数 %d→%d phase=%s" % [
			Card.display_name(kind_before), hand_before, hand_after, sm.phase])

	# ---- 测试 3：透支全流程（直接调状态机 + 合成点击透支按钮）----
	var m2 := TurnStateMachine.new(Deck.new(SeededRandom.new()), GameConfig.new(), SeededRandom.new())
	m2.start_game(PackedStringArray(["甲", "乙"]), 42)
	# 给甲塞一张透支
	var me := m2.current()
	me.hand.append(Card.new(Card.Kind.OVERDRAW, 9901))
	m2.play_overdraw(me.hand.size() - 1)
	print("[diag] 测试3 打出透支后 phase=%s（应为 RESPONSE 匿名窗口）" % m2.phase)
	m2.respond_wish(false)
	print("[diag] 测试3 响应结算后 phase=%s（应为 OVERDRAW）" % m2.phase)
	var zone_before := me.overdraw_zone.size()
	m2.overdraw_draw()
	print("[diag] 测试3 overdraw_draw 后透支区 %d→%d 张 phase=%s" % [
		zone_before, me.overdraw_zone.size(), m2.phase])
	m2.stop_overdraw()
	print("[diag] 测试3 喊停后 phase=%s 当前=%s（应轮到乙）" % [m2.phase, m2.current().name])

	print("[diag] 完成")
	quit(0)


## 找 row 里文本匹配的按钮
func _find_button(row: Container, text: String) -> Button:
	for child in row.get_children():
		if child is Button and child.text == text:
			return child
	return null


## 用 Viewport.push_input 模拟一次真实鼠标点击（移动+按下+抬起）
func _click_control(c: Control) -> bool:
	if not c.is_visible_in_tree():
		print("[diag] WARN 目标不可见: ", c)
		return false
	var center: Vector2 = c.get_global_rect().get_center()
	_push_mouse(center, true)
	_push_mouse(center, false)
	return true


func _push_mouse(pos: Vector2, pressed: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	root.push_input(motion)
	var btn := InputEventMouseButton.new()
	btn.button_index = MOUSE_BUTTON_LEFT
	btn.pressed = pressed
	btn.position = pos
	btn.global_position = pos
	root.push_input(btn)
