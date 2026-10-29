# @trace UI-001, LEV-001, PLAT-001, MECH-008, MECH-012, MECH-013
## 本地热座（Pass & Play）主界面。v0.9 拍桌版：市面棋牌手游式牌桌布局。
## 布局：顶部状态条 → 上方对手槽（头像+牌背扇形）→ 中央椭圆桌垫（牌堆｜出牌展示｜弃牌堆）
##       → 动作按钮区 → 底部本人大手牌扇形。日志收进右下角弹出面板。
## 卡牌用 CardView 程序化占位美术（设计师出图后替换插画区贴图即可）。
## 交互逻辑与 v0.8.2 完全一致：响应窗口（静默化）、钳子组合、预知弹窗、暗置爆弹。
extends Control

var _sm: TurnStateMachine
var _pending_steal_index := -1
var _selected_pliers: Array[int] = []
var _response_token := 0                   # 响应倒计时令牌：刷新即作废旧倒计时

# 飞牌动画（第 3 步）：出牌→中央、抽牌→手牌
var _fx_layer: Control                     # 特效层（全屏置顶，不挡鼠标）
var _has_flight := false
var _flight_from := Vector2.ZERO
var _flight_to := Vector2.ZERO
var _flight_kind := 0
var _flight_face := true

# UI 引用
var _status_label: Label
var _counts_label: Label
var _zone_label: Label
var _opponents_row: Control              # 对手槽容器（绝对定位）
var _hand_area: Control                  # 扇形手牌区
var _hand_cards: Array[CardView] = []
var _action_row: HBoxContainer
var _target_row: HBoxContainer
var _kind_row: HBoxContainer
var _op_panel: Control                     # 操作层（隐形，点击优先级高于手牌）
var _target_center: Control                # 选择行容器（需置顶于手牌之上）
var _kind_center: Control
var _bomb_row: HBoxContainer
var _bomb_slider: HSlider
var _start_overlay: PanelContainer       # 开局浮层
var _player_spin: SpinBox
var _log_label: RichTextLabel
var _log_panel: PanelContainer
var _log_btn: Button
var _deck_stack: Control
var _deck_count_label: Label
var _center_play: Control                # 中央出牌展示
var _center_hint: Label
var _discard_stack: Control
var _discard_count_label: Label
var _hand_count_label: Label


func _ready() -> void:
	_apply_cjk_font()
	_build_ui()
	_show_start_panel()


func _apply_cjk_font() -> void:
	var font: Font = load("res://assets/fonts/NotoSansSC-Regular.ttf")
	if font != null:
		var ui_theme := Theme.new()
		ui_theme.default_font = font
		ui_theme.default_font_size = 15
		self.theme = ui_theme


# ---- 配色 ----
const DESKTOP_COLOR := Color("1C2733")     # 桌外深色
const FELT_COLOR := Color("223A4C")        # 桌垫毛毡
const PANEL_COLOR := Color("3A566B")
const GOLD := Color("E8B04B")
const RESPONSE_SECONDS := 3                # 休想匿名响应倒计时（v0.9.3 用户拍板：8 秒改 3 秒）


# ---- 通用样式 ----

func _glass_style(radius := 10, alpha := 0.55) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.12, 0.2, alpha)
	style.set_corner_radius_all(radius)
	style.border_color = Color(1, 1, 1, 0.12)
	style.set_border_width_all(1)
	return style


## 精致按钮：深色玻璃底 + 白字，hover 金边
func _style_button(btn: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.2, 0.3, 0.9)
	style.set_corner_radius_all(9)
	style.border_color = Color(1, 1, 1, 0.18)
	style.set_border_width_all(1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	var hover: StyleBoxFlat = style.duplicate()
	hover.border_color = GOLD
	hover.set_border_width_all(2)
	hover.bg_color = Color(0.12, 0.26, 0.38, 0.95)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("disabled", style)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", GOLD)
	btn.add_theme_color_override("font_pressed_color", GOLD)
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))


func _make_label(text: String, size := 14, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


# ---- UI 构建 ----

func _build_ui() -> void:
	# 桌外深色底
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = DESKTOP_COLOR
	add_child(bg)

	# 中央椭圆桌垫（毛毡 + 金描边 + 投影）——大桌面，按钮悬浮在桌沿，不用色带切屏
	var pad := Panel.new()
	pad.position = Vector2(170, 88)
	pad.size = Vector2(940, 322)
	var pad_style := StyleBoxFlat.new()
	pad_style.bg_color = FELT_COLOR
	pad_style.set_corner_radius_all(160)
	pad_style.border_color = Color("C9A227")
	pad_style.set_border_width_all(2)
	pad_style.shadow_size = 24
	pad_style.shadow_color = Color(0, 0, 0, 0.5)
	pad.add_theme_stylebox_override("panel", pad_style)
	add_child(pad)
	# 毛毡内圈高光线
	var pad_inner := Panel.new()
	pad_inner.position = pad.position + Vector2(14, 14)
	pad_inner.size = pad.size - Vector2(28, 28)
	var inner_style := StyleBoxFlat.new()
	inner_style.bg_color = Color(1, 1, 1, 0.03)
	inner_style.set_corner_radius_all(140)
	inner_style.border_color = Color(1, 1, 1, 0.06)
	inner_style.set_border_width_all(1)
	pad_inner.add_theme_stylebox_override("panel", inner_style)
	add_child(pad_inner)

	# ---- 顶部状态条 ----
	var top_bar := Panel.new()
	top_bar.position = Vector2(0, 0)
	top_bar.size = Vector2(1280, 36)
	top_bar.add_theme_stylebox_override("panel", _glass_style(0, 0.75))
	add_child(top_bar)

	_status_label = _make_label("尚未开局", 14, GOLD)   # 挂到操作条内（见下）
	var title_label := _make_label("别炸我！", 14, GOLD)
	title_label.position = Vector2(16, 8)
	add_child(title_label)
	_counts_label = _make_label("", 13, Color(1, 1, 1, 0.75))
	_counts_label.position = Vector2(920, 9)
	add_child(_counts_label)

	# ---- 对手槽（绝对定位，覆盖全屏，不挡鼠标）----
	_opponents_row = Control.new()
	_opponents_row.position = Vector2.ZERO
	_opponents_row.size = Vector2(1280, 720)
	_opponents_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_opponents_row)

	# ---- 牌堆（桌垫左）----
	_deck_stack = Control.new()
	_deck_stack.position = Vector2(295, 152)
	add_child(_deck_stack)
	var deck_label := _make_label("牌堆", 12, Color(1, 1, 1, 0.55))
	deck_label.position = Vector2(330, 302)
	add_child(deck_label)
	_deck_count_label = _make_label("", 14, Color.WHITE)
	_deck_count_label.position = Vector2(316, 320)
	_deck_count_label.custom_minimum_size = Vector2(80, 0)
	_deck_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_deck_count_label)

	# ---- 中央出牌展示 ----
	_center_play = Control.new()
	_center_play.position = Vector2(576, 140)
	add_child(_center_play)
	_center_hint = _make_label("出牌区", 12, Color(1, 1, 1, 0.3))
	_center_hint.position = Vector2(612, 210)
	add_child(_center_hint)
	_zone_label = _make_label("", 13, GOLD)
	_zone_label.position = Vector2(440, 356)
	_zone_label.custom_minimum_size = Vector2(400, 0)
	_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_zone_label)

	# ---- 弃牌堆（桌垫右）----
	_discard_stack = Control.new()
	_discard_stack.position = Vector2(860, 152)
	add_child(_discard_stack)
	var discard_label := _make_label("弃牌堆", 12, Color(1, 1, 1, 0.55))
	discard_label.position = Vector2(900, 302)
	add_child(discard_label)
	_discard_count_label = _make_label("", 14, Color.WHITE)
	_discard_count_label.position = Vector2(886, 320)
	_discard_count_label.custom_minimum_size = Vector2(80, 0)
	_discard_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_discard_count_label)

	# ---- 三区硬分离：牌桌区(0-414) / 操作区(414-506) / 手牌区(506-720) ----
	# 手牌区先声明（画在下层），操作区后声明（画在上层、优先接收点击），
	# 卡片再怎么悬停放大/选中抬升也只会"滑进操作条底下"，绝不会抢走按钮点击。

	# ---- 扇形手牌区（底部）----
	_hand_area = Control.new()
	_hand_area.position = Vector2(0, 506)
	_hand_area.size = Vector2(1280, 214)
	add_child(_hand_area)

	# ---- 操作层（隐形，几何上位于桌垫与手牌之间）----
	# 不画底色，按钮悬浮在桌面上；但这一层在手牌区之后声明，点击优先级更高，
	# 卡片永远不会抢走按钮——分区靠几何位置，不靠色带。
	_op_panel = Control.new()
	_op_panel.position = Vector2(0, 414)
	_op_panel.size = Vector2(1280, 92)
	add_child(_op_panel)

	# 回合状态文字：居中悬浮，像游戏 HUD 提示
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.position = Vector2(0, 2)
	_status_label.size = Vector2(1280, 22)
	_op_panel.add_child(_status_label)

	var action_center := CenterContainer.new()
	action_center.position = Vector2(0, 30)
	action_center.size = Vector2(1280, 48)
	action_center.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 容器只管排版，不拦截点击
	_op_panel.add_child(action_center)
	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 8)
	_action_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_center.add_child(_action_row)

	var target_center := CenterContainer.new()
	target_center.position = Vector2(0, 28)
	target_center.size = Vector2(1280, 56)
	target_center.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 关键：与 action_center 同位重叠，
	_op_panel.add_child(target_center)                          # 不穿透会吃掉动作按钮的点击
	_target_center = target_center
	_target_row = HBoxContainer.new()
	_target_row.add_theme_constant_override("separation", 8)
	_target_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_center.add_child(_target_row)

	var kind_center := CenterContainer.new()
	kind_center.position = Vector2(0, 28)
	kind_center.size = Vector2(1280, 56)
	kind_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_op_panel.add_child(kind_center)
	_kind_center = kind_center
	_kind_row = HBoxContainer.new()
	_kind_row.add_theme_constant_override("separation", 8)
	_kind_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kind_center.add_child(_kind_row)

	# 暗置爆弹（同样悬浮，与手牌完全隔离）
	_bomb_row = HBoxContainer.new()
	_bomb_row.add_theme_constant_override("separation", 10)
	_bomb_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_bomb_row.position = Vector2(0, 34)
	_bomb_row.size = Vector2(1280, 44)
	_bomb_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bomb_label := _make_label("暗置爆弹位置：", 14)
	_bomb_row.add_child(bomb_label)
	_bomb_slider = HSlider.new()
	_bomb_slider.min_value = 0
	_bomb_slider.max_value = 1
	_bomb_slider.custom_minimum_size = Vector2(260, 24)
	_bomb_row.add_child(_bomb_slider)
	var bomb_confirm := Button.new()
	bomb_confirm.text = "确认暗置"
	_style_button(bomb_confirm)
	bomb_confirm.pressed.connect(_on_confirm_bomb)
	_bomb_row.add_child(bomb_confirm)
	_op_panel.add_child(_bomb_row)

	# 本人手牌数（手牌区右上角）
	_hand_count_label = _make_label("", 12, Color(1, 1, 1, 0.6))
	_hand_count_label.position = Vector2(1080, 512)
	add_child(_hand_count_label)

	# ---- 日志（顶栏右侧常驻按钮 + 弹出面板）----
	_log_btn = Button.new()
	_log_btn.text = "记录"
	_log_btn.position = Vector2(1204, 4)
	_log_btn.size = Vector2(64, 28)
	_style_button(_log_btn)
	_log_btn.pressed.connect(_toggle_log)
	add_child(_log_btn)

	_log_panel = PanelContainer.new()
	_log_panel.position = Vector2(920, 470)
	_log_panel.size = Vector2(348, 244)
	_log_panel.add_theme_stylebox_override("panel", _glass_style(10, 0.92))
	_log_panel.visible = false
	add_child(_log_panel)
	var log_box := VBoxContainer.new()
	_log_panel.add_child(log_box)
	var log_title := _make_label("对局日志", 12, Color(1, 1, 1, 0.5))
	log_box.add_child(log_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label = RichTextLabel.new()
	_log_label.fit_content = true
	_log_label.scroll_active = false
	_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_label.add_theme_color_override("default_color", Color(1, 1, 1, 0.85))
	_log_label.add_theme_font_size_override("normal_font_size", 12)
	scroll.add_child(_log_label)
	log_box.add_child(scroll)

	# ---- 开局浮层 ----
	_start_overlay = PanelContainer.new()
	_start_overlay.position = Vector2(470, 250)
	_start_overlay.custom_minimum_size = Vector2(340, 160)
	var start_style := StyleBoxFlat.new()
	start_style.bg_color = Color(0.06, 0.14, 0.22, 0.95)
	start_style.set_corner_radius_all(14)
	start_style.border_color = Color("C9A227")
	start_style.set_border_width_all(2)
	start_style.shadow_size = 16
	start_style.shadow_color = Color(0, 0, 0, 0.5)
	_start_overlay.add_theme_stylebox_override("panel", start_style)
	add_child(_start_overlay)
	var start_box := VBoxContainer.new()
	start_box.add_theme_constant_override("separation", 10)
	_start_overlay.add_child(start_box)
	var start_title := _make_label("《别炸我！》", 22, GOLD)
	start_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_box.add_child(start_title)
	var spin_row := HBoxContainer.new()
	spin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	spin_row.add_theme_constant_override("separation", 8)
	start_box.add_child(spin_row)
	spin_row.add_child(_make_label("玩家数：", 14))
	_player_spin = SpinBox.new()
	_player_spin.min_value = 2
	_player_spin.max_value = 5
	_player_spin.value = 4
	_player_spin.custom_minimum_size = Vector2(80, 0)
	spin_row.add_child(_player_spin)
	var start_btn := Button.new()
	start_btn.text = "开 始 游 戏"
	_style_button(start_btn)
	start_btn.pressed.connect(_on_start_game)
	var btn_center := CenterContainer.new()
	btn_center.add_child(start_btn)
	start_box.add_child(btn_center)

	# ---- 特效层（置顶，飞牌/爆炸/红闪都在这层）----
	_fx_layer = Control.new()
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)


func _toggle_log() -> void:
	_log_panel.visible = not _log_panel.visible


# ---- 开局 ----

func _show_start_panel() -> void:
	_start_overlay.visible = true
	_hand_area.visible = false
	_op_panel.visible = false
	_opponents_row.visible = false
	_hand_count_label.text = ""
	_zone_label.text = ""
	_center_hint.text = ""
	for child in _deck_stack.get_children():
		child.queue_free()
	for child in _discard_stack.get_children():
		child.queue_free()
	for child in _center_play.get_children():
		child.queue_free()
	_deck_count_label.text = ""
	_discard_count_label.text = ""
	_status_label.text = "尚未开局"


func _on_start_game() -> void:
	var p := int(_player_spin.value)
	var names := PackedStringArray()
	for i in p:
		names.append("玩家%d" % (i + 1))
	var rng := SeededRandom.new()
	var sm := TurnStateMachine.new(Deck.new(rng), GameConfig.new(), rng)
	sm.log_message.connect(_on_log)
	sm.bomb_exploded.connect(_on_bomb_exploded)
	_sm = sm
	_sm.start_game(names, int(Time.get_unix_time_from_system()))
	_start_overlay.visible = false
	_log_label.clear()
	_log_panel.visible = false
	_pending_steal_index = -1
	_selected_pliers.clear()
	_refresh()


# ---- 对局刷新 ----

func _on_log(message: String) -> void:
	_log_label.append_text(message + "\n")


## 输入诊断：GUI 按钮吃掉的点击不会走到这里；走到这里 = 点在了空白/被忽略区域。
## 按钮"按不动"时看输出台有没有这行，能区分"没点到按钮"还是"点了没生效"。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		print("[诊断] 本次点击落在空白区域：", event.position)


func _clear_rows() -> void:
	for row in [_action_row, _target_row, _kind_row]:
		for child in row.get_children():
			child.queue_free()


func _refresh() -> void:
	if _sm == null:
		return
	_clear_rows()

	if _sm.phase == TurnStateMachine.TurnPhase.GAME_OVER:
		_status_label.text = "游戏结束" + (("— 赢家：" + _sm.winner.name) if _sm.winner != null else "— 无存活玩家")
		_show_start_panel()
		return

	_start_overlay.visible = false
	_hand_area.visible = true
	_op_panel.visible = true
	_opponents_row.visible = true

	_counts_label.text = "牌堆 %d ｜ 弃牌 %d ｜ 已引爆 %d" % [
		_sm.draw_pile_count(), _sm.discard_count(), _sm.exploded_bombs_total]
	_refresh_piles()
	_refresh_opponents()

	match _sm.phase:
		TurnStateMachine.TurnPhase.ACTION:
			_refresh_action()
		TurnStateMachine.TurnPhase.OVERDRAW:
			_refresh_overdraw()
		TurnStateMachine.TurnPhase.RESPONSE:
			_refresh_response()
		TurnStateMachine.TurnPhase.FLUSH_PICK:
			_refresh_flush_pick()
		TurnStateMachine.TurnPhase.BOMB_PLACEMENT:
			_bomb_row.visible = true
			_bomb_slider.max_value = _sm.bomb_placement_range()
			_bomb_slider.value = _sm.bomb_placement_range() / 2.0
			# 暗置阶段手牌不可操作：置灰显示，明示"现在只能操作暗置滑条"
			_rebuild_hand([], false)


## 牌堆 / 中央出牌展示 / 弃牌堆
func _refresh_piles() -> void:
	for child in _deck_stack.get_children():
		child.queue_free()
	for child in _discard_stack.get_children():
		child.queue_free()
	for child in _center_play.get_children():
		child.queue_free()

	# 牌堆：叠 3 层牌背（0.72 缩放）
	var layers := mini(3, maxi(1, ceili(_sm.draw_pile_count() / 12.0)))
	for i in layers:
		var back := CardView.new(Card.Kind.SKIP, false)
		back.scale = Vector2(0.72, 0.72)
		back.position = Vector2(i * 4, -i * 4)
		_deck_stack.add_child(back)
	_deck_count_label.text = "%d 张" % _sm.draw_pile_count()

	var discards := _sm.discard_cards()
	if not discards.is_empty():
		# 弃牌堆：牌背 + 顶牌（0.72）
		var back := CardView.new(Card.Kind.SKIP, false)
		back.scale = Vector2(0.72, 0.72)
		back.position = Vector2(4, 4)
		_discard_stack.add_child(back)
		var top_view := CardView.new(discards[discards.size() - 1].kind, true)
		top_view.scale = Vector2(0.72, 0.72)
		_discard_stack.add_child(top_view)
		# 中央出牌展示：最新打出的牌放大 + 微斜（拍桌感）
		var played := CardView.new(discards[discards.size() - 1].kind, true)
		played.scale = Vector2(1.16, 1.16)
		played.rotation_degrees = -3.0
		played.position = Vector2(8, 10)
		_center_play.add_child(played)
		_center_hint.text = "最近打出"
		_center_hint.position = Vector2(600, 348)
	else:
		# 空槽轮廓
		var slot := Panel.new()
		slot.size = Vector2(96, 144)
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = Color(1, 1, 1, 0.04)
		slot_style.set_corner_radius_all(10)
		slot_style.border_color = Color(1, 1, 1, 0.15)
		slot_style.set_border_width_all(1)
		slot.add_theme_stylebox_override("panel", slot_style)
		_center_play.add_child(slot)
		_center_hint.text = "出牌区"
		_center_hint.position = Vector2(612, 210)
	_discard_count_label.text = "%d 张" % _sm.discard_count()


## 对手槽按牌桌方位分布：我在底部，对手按回合顺序（顺时针）落在 左 → 上 → 右。
## 1 对手=正上方；2=左/右；3=左/上/右；4=左/上左/上右/右。
const OPPONENT_SLOTS := {
	1: [Vector2(581, 40)],
	2: [Vector2(30, 196), Vector2(1132, 196)],
	3: [Vector2(30, 196), Vector2(581, 40), Vector2(1132, 196)],
	4: [Vector2(30, 196), Vector2(320, 40), Vector2(842, 40), Vector2(1132, 196)],
}


func _refresh_opponents() -> void:
	for child in _opponents_row.get_children():
		child.queue_free()
	var me_idx := _sm.current_index()
	var opponents: Array[int] = []
	for i in _sm.players().size():
		if i != me_idx:
			opponents.append(i)
	var slots: Array = OPPONENT_SLOTS[opponents.size()]
	for placed in opponents.size():
		var i: int = opponents[placed]
		var player := _sm.players()[i]
		var slot_w := 118.0
		var slot := Control.new()
		slot.position = slots[placed]
		slot.size = Vector2(118, 96)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_opponents_row.add_child(slot)

		# 槽底玻璃板
		var plate := Panel.new()
		plate.size = Vector2(slot_w, 92)
		var plate_style := StyleBoxFlat.new()
		plate_style.bg_color = Color(PANEL_COLOR.r, PANEL_COLOR.g, PANEL_COLOR.b,
				0.55 if player.alive else 0.2)
		plate_style.set_corner_radius_all(10)
		if i == _sm.current_index() and player.alive:
			plate_style.border_color = GOLD
			plate_style.set_border_width_all(2)
		plate.add_theme_stylebox_override("panel", plate_style)
		slot.add_child(plate)

		# 圆头像（占位：名字首字）
		var avatar := Panel.new()
		avatar.position = Vector2(slot_w / 2.0 - 21, 6)
		avatar.size = Vector2(42, 42)
		var avatar_style := StyleBoxFlat.new()
		avatar_style.bg_color = Color("5B7C93") if player.alive else Color("4A4A4A")
		avatar_style.set_corner_radius_all(21)
		avatar.add_theme_stylebox_override("panel", avatar_style)
		slot.add_child(avatar)
		var initial := _make_label(player.name.left(1), 20, Color.WHITE)
		initial.position = Vector2(slot_w / 2.0 - 10, 12)
		slot.add_child(initial)

		# 名字
		var name_label := _make_label(player.name, 12,
				Color(1, 1, 1, 0.4) if not player.alive else Color.WHITE)
		name_label.position = Vector2(8, 50)
		name_label.custom_minimum_size = Vector2(slot_w - 16, 0)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(name_label)

		if player.alive:
			# 牌背小扇形（最多 7 张，重叠 + 微旋转）
			var fan := Control.new()
			fan.position = Vector2(slot_w / 2.0 - 24, 66)
			slot.add_child(fan)
			var shown := mini(player.hand.size(), 7)
			for j in shown:
				var mini := CardView.make_mini_back()
				mini.position = Vector2(j * 7.0, 0)
				mini.pivot_offset = Vector2(9, 13)
				mini.rotation_degrees = (j - (shown - 1) / 2.0) * 3.0
				fan.add_child(mini)
			var count_label := _make_label("%d 张" % player.hand.size(), 11, Color(1, 1, 1, 0.65))
			count_label.position = Vector2(slot_w - 42, 68)
			slot.add_child(count_label)
		else:
			var out_label := _make_label("已出局", 12, Color("E74C3C"))
			out_label.position = Vector2(8, 68)
			out_label.custom_minimum_size = Vector2(slot_w - 16, 0)
			out_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			slot.add_child(out_label)

	# 本人手牌数
	var me := _sm.players()[me_idx]
	var text := "%s（你）：%d 张手牌" % [me.name, me.hand.size()]
	if me.overdraw_zone.size() > 0:
		text += " ｜ 透支区 %d 张" % me.overdraw_zone.size()
	_hand_count_label.text = text


## 扇形手牌布局
func _layout_hand() -> void:
	var n := _hand_cards.size()
	if n == 0:
		return
	await get_tree().process_frame
	if _hand_cards.size() != n:
		return
	var area_width := maxf(_hand_area.size.x, 900.0)
	var spread_deg := 4.0
	var total := minf((n - 1) * spread_deg, 36.0)
	var step := 0.0 if n == 1 else total / (n - 1)
	var spacing := minf(80.0, (area_width - CardView.CARD_SIZE.x - 60.0) / maxf(n - 1, 1))
	for i in n:
		var card := _hand_cards[i]
		var angle := -total / 2.0 + i * step if n > 1 else 0.0
		var x := area_width / 2.0 + (i - (n - 1) / 2.0) * spacing - CardView.CARD_SIZE.x / 2.0
		var y := _hand_area.size.y - CardView.CARD_SIZE.y - 8.0 + absf(angle) * 1.8
		if card.selected:
			y -= 16   # 选中抬升收敛：手牌整体留在手牌区内，不挤进操作条
		card.position = Vector2(x, y)
		card.rotation_degrees = angle


## interactive=false：手牌只展示不可点（置灰，如暗置爆弹阶段），绝不抢操作区的交互
func _rebuild_hand(selected_set: Array, interactive := true) -> void:
	for child in _hand_area.get_children():
		child.queue_free()
	_hand_cards.clear()
	if _sm == null:
		return
	var me := _sm.current()
	for i in me.hand.size():
		var card := me.hand[i]
		var view := CardView.new(card.kind, true)
		view.tooltip_text = _card_tip(card.kind) if interactive else ""
		if selected_set.has(i):
			view.selected = true
		if not interactive:
			view.modulate = Color(1, 1, 1, 0.45)
			view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			var card_index := i
			var card_view := view
			view.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.pressed \
						and event.button_index == MOUSE_BUTTON_LEFT:
					_on_hand_card(card_index, card_view))
		_hand_area.add_child(view)
		_hand_cards.append(view)
	_layout_hand()


func _refresh_action() -> void:
	_target_row.visible = false
	_kind_row.visible = false
	_bomb_row.visible = false
	var me := _sm.current()
	_status_label.text = "%s 的回合：点卡牌打出，或点「抽一张牌」" % me.name
	_action_row.visible = true
	_zone_label.text = ""

	_rebuild_hand(_selected_pliers)

	var draw_btn := Button.new()
	draw_btn.text = "抽一张牌"
	draw_btn.tooltip_text = "从公共牌堆顶抽 1 张并结束回合。抽到爆弹：有拆除可救回，没有就出局。"
	_style_button(draw_btn)
	_action_row.add_child(draw_btn)
	draw_btn.pressed.connect(func() -> void:
		_stage_draw_flight()
		_sm.normal_draw()
		_after_action())

	if _selected_pliers.size() > 0:
		var cancel_btn := Button.new()
		cancel_btn.text = "取消选择"
		_style_button(cancel_btn)
		cancel_btn.pressed.connect(func() -> void:
			_selected_pliers.clear()
			_refresh())
		_action_row.add_child(cancel_btn)
		var count := _selected_pliers.size()
		if count == 1:
			var single_btn := Button.new()
			single_btn.text = "单张打出（无效果）"
			single_btn.tooltip_text = "把这张工具牌直接弃置进弃牌堆并结束回合。单张没有任何效果，但会进弃牌堆——可以被五张组合回收。"
			_style_button(single_btn)
			var single_idx: int = _selected_pliers[0]
			single_btn.pressed.connect(func() -> void:
				if single_idx < _hand_cards.size():
					_stage_flight(_hand_cards[single_idx], me.hand[single_idx].kind, false)
				if _sm.play_single_plier(single_idx):
					_after_action()
				else:
					_refresh())
			_action_row.add_child(single_btn)
		var kinds: Array[int] = []
		for idx in _selected_pliers:
			kinds.append(me.hand[idx].kind)
		var distinct := {}
		for k in kinds:
			distinct[k] = true
		var same_all := distinct.size() == 1
		if count == 2 and same_all:
			_add_combo_button("同种×2：指定一人，随机偷走其 1 张手牌（不亮牌）", "pair")
		elif count == 3 and same_all:
			_add_combo_button("同种×3：念一个牌名，目标有就必须给", "trio")
		elif count == 5 and distinct.size() == 5:
			_add_combo_button("五种各×1：从弃牌堆任选 1 张回收", "flush")
		else:
			var hint := _make_label("", 12, Color(1, 1, 1, 0.7))
			if count == 2 or count == 3:
				hint.text = "对子/三条需选同一种工具（已选 %d 张、%d 种）" % [count, distinct.size()]
			elif count == 5:
				hint.text = "五张组合需 5 种工具各 1 张（当前 %d 种）" % distinct.size()
			else:
				hint.text = "可点「单张打出」直接弃置；或继续多选：同种×2=对子、同种×3=三条、五种各×1=五张"
			_action_row.add_child(hint)


func _add_combo_button(tip: String, combo: String) -> void:
	var btn := Button.new()
	btn.text = "工具·%s" % {"pair": "对子", "trio": "三条", "flush": "五张"}[combo]
	btn.tooltip_text = tip
	_style_button(btn)
	btn.pressed.connect(_on_pliers_combo.bind(combo))
	_action_row.add_child(btn)


func _refresh_overdraw() -> void:
	_target_row.visible = false
	_kind_row.visible = false
	_bomb_row.visible = false
	_action_row.visible = true
	var me := _sm.current()
	_status_label.text = "%s 透支连抽中" % me.name
	_rebuild_hand([])
	_zone_label.text = "透支区（%d 张）面朝上公开：喊停全部入手，再抽抽中爆弹全弃" % me.overdraw_zone.size()
	var keep_btn := Button.new()
	keep_btn.text = "再抽一张（风险加大）"
	_style_button(keep_btn)
	keep_btn.pressed.connect(func() -> void:
		_stage_draw_flight()
		_sm.overdraw_draw()
		_after_action())
	_action_row.add_child(keep_btn)
	var stop_btn := Button.new()
	stop_btn.text = "喊停！%d 张全部入手" % me.overdraw_zone.size()
	_style_button(stop_btn)
	stop_btn.pressed.connect(func() -> void: _sm.stop_overdraw(); _after_action())
	_action_row.add_child(stop_btn)


func _refresh_response() -> void:
	_target_row.visible = false
	_kind_row.visible = false
	_bomb_row.visible = false
	_action_row.visible = true
	_rebuild_hand([])
	var effect: Dictionary = _sm.pending_effect()
	var actor := _sm.players()[effect.actor]
	_status_label.text = "响应时间：%s 打出了【%s】——持有休想牌的玩家可反制" % [
		actor.name, _effect_label(effect.type)]
	# 匿名倒计时（v0.9.1）：不点名、不扫描，是否持有休想只有玩家自己知道
	_response_token += 1
	_run_response_countdown(_response_token)
	var wish_btn := Button.new()
	wish_btn.text = "打出【休想】！（反制该功能牌）"
	wish_btn.tooltip_text = "只有手里真有休想牌的玩家才应点击；随后选择是谁打出。"
	_style_button(wish_btn)
	wish_btn.pressed.connect(_show_wish_picker)
	_action_row.add_child(wish_btn)
	var pass_btn := Button.new()
	pass_btn.text = "无人反制，立即继续"
	_style_button(pass_btn)
	pass_btn.pressed.connect(func() -> void:
		_response_token += 1
		_sm.respond_wish(false)
		_after_action())
	_action_row.add_child(pass_btn)


func _run_response_countdown(token: int) -> void:
	var remain := RESPONSE_SECONDS
	while remain > 0:
		if _sm == null or _sm.phase != TurnStateMachine.TurnPhase.RESPONSE \
				or _response_token != token:
			return
		_zone_label.text = "匿名响应中：是否持有休想牌只有你自己知道，%d 秒后无人反制则效果生效" % remain
		await get_tree().create_timer(1.0).timeout
		remain -= 1
	if _sm != null and _sm.phase == TurnStateMachine.TurnPhase.RESPONSE \
			and _response_token == token:
		_sm.respond_wish(false)
		_after_action()


func _show_wish_picker() -> void:
	_response_token += 1  # 进入选人阶段停掉倒计时，由玩家手动继续
	for child in _target_row.get_children():
		child.queue_free()
	_target_row.visible = true
	_action_row.visible = false
	_zone_label.text = ""
	var actor: int = _sm.pending_effect().actor
	var hint := _make_label("谁要打出休想？（请持牌者点自己的名字）→", 14)
	_target_row.add_child(hint)
	for i in _sm.players().size():
		var player := _sm.players()[i]
		if i == actor or not player.alive:
			continue
		var idx := i
		var btn := Button.new()
		btn.text = player.name
		_style_button(btn)
		btn.pressed.connect(func() -> void:
			_target_row.visible = false
			_action_row.visible = true
			if _sm.respond_wish(true, idx):
				_after_action()
			else:
				_on_log("（反制无效：所选玩家没有休想牌，可重新选择或继续）"))
		_target_row.add_child(btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "返回"
	_style_button(cancel_btn)
	cancel_btn.pressed.connect(func() -> void:
		_target_row.visible = false
		_action_row.visible = true
		_refresh())
	_target_row.add_child(cancel_btn)


func _effect_label(type: String) -> String:
	if type == "pliers":
		return "拆弹工具组合"
	return Card.display_name(_kind_of(type))


func _kind_of(type: String) -> Card.Kind:
	match type:
		"skip": return Card.Kind.SKIP
		"attack": return Card.Kind.ATTACK
		"peek": return Card.Kind.PEEK
		"shuffle": return Card.Kind.SHUFFLE
		"steal": return Card.Kind.STEAL
		"overdraw": return Card.Kind.OVERDRAW
		"pliers": return Card.Kind.PLIERS_TIGER
	return Card.Kind.SKIP


func _refresh_flush_pick() -> void:
	_target_row.visible = false
	_kind_row.visible = false
	_bomb_row.visible = false
	_action_row.visible = true
	_rebuild_hand([])
	_status_label.text = "工具·五张：%s 请从弃牌堆选 1 张回收" % _sm.current().name
	var discards := _sm.discard_cards()
	if discards.is_empty():
		var none := _make_label("弃牌堆为空", 12, Color(1, 1, 1, 0.6))
		_action_row.add_child(none)
		return
	for i in discards.size():
		var btn := Button.new()
		btn.text = "%d:%s" % [i + 1, Card.display_name(discards[i].kind)]
		_style_button(btn)
		btn.pressed.connect(func() -> void: _sm.flush_pick(i); _after_action())
		_action_row.add_child(btn)


func _card_tip(kind: Card.Kind) -> String:
	if Card.is_plier(kind):
		return "%s：拆弹工具类（5 种等价的收集标记）。单张可直接打出——无效果，弃置并结束回合；同种×2=对子（指定一人随机偷 1 张，不亮牌）；同种×3=三条（念牌名索要，有就必须给）；五种各×1=五张（从弃牌堆回收 1 张）。先点选工具牌再点组合按钮。" % Card.display_name(kind)
	match kind:
		Card.Kind.SKIP:
			return "跳过：不抽牌，直接结束你的回合。"
		Card.Kind.ATTACK:
			return "攻击：结束你的回合，下一位必须连抽 2 张（可以叠加）。"
		Card.Kind.PEEK:
			return "预知：偷看牌堆顶 3 张，只有你自己看得到结果。"
		Card.Kind.SHUFFLE:
			return "洗牌：把整个牌池重新打乱。"
		Card.Kind.STEAL:
			return "偷牌：随机抽走指定玩家 1 张手牌。"
		Card.Kind.OVERDRAW:
			return "透支：打出后可连续多抽——随时喊停，抽到的牌全部入手并结束回合；中途抽到爆弹，本轮透支的牌全部弃掉。每回合限打一张。"
		Card.Kind.WISH:
			return "休想：别人打出功能牌时打出，令其失效。唯一可在非自己回合打出的牌；不能反制拆除和休想。"
		Card.Kind.DEFUSE:
			return "拆除：抽到爆弹时自动使用，把爆弹偷偷塞回牌堆任意位置。平时攥在手里。"
	return ""


func _after_action() -> void:
	_pending_steal_index = -1
	_selected_pliers.clear()
	if _has_flight:
		_has_flight = false
		await _fly_card(_flight_from, _flight_to, _flight_kind, _flight_face)
	_refresh()
	if _sm != null and not _sm.last_peek_result.is_empty():
		# 预知结果只弹一次：读取后立刻消费掉，后续任何刷新都不再重复弹出
		var result_text: String = _sm.last_peek_result
		_sm.clear_peek()
		var dlg := AcceptDialog.new()
		dlg.title = "预知结果（仅本人可见）"
		dlg.dialog_text = result_text
		dlg.ok_button_text = "看完了，传给下一位"
		dlg.close_requested.connect(func() -> void: dlg.queue_free())
		add_child(dlg)
		dlg.popup_centered()


# ---- 手牌交互 ----

func _on_hand_card(index: int, view: CardView) -> void:
	if _sm == null or _sm.phase != TurnStateMachine.TurnPhase.ACTION:
		return
	var me := _sm.current()
	var card := me.hand[index]
	var ok := false
	match card.kind:
		Card.Kind.SKIP:
			_stage_flight(view, card.kind, false)
			ok = _sm.play_skip(index)
		Card.Kind.ATTACK:
			_stage_flight(view, card.kind, false)
			ok = _sm.play_attack(index)
		Card.Kind.PEEK:
			_stage_flight(view, card.kind, false)
			ok = _sm.play_peek(index)
		Card.Kind.SHUFFLE:
			_stage_flight(view, card.kind, false)
			ok = _sm.play_shuffle(index)
		Card.Kind.STEAL:
			_pending_steal_index = index
			_refresh_steal_targets(index)
			return
		Card.Kind.OVERDRAW:
			if _sm.overdraw_used_this_turn():
				_on_log("本回合已经透支过了（每回合限一张），这张牌留着下回合用")
				return
			_stage_flight(view, card.kind, false)
			ok = _sm.play_overdraw(index)
		_:
			if Card.is_plier(card.kind):
				if _selected_pliers.has(index):
					_selected_pliers.erase(index)
				else:
					_selected_pliers.append(index)
				_refresh()
				return
			elif card.kind == Card.Kind.WISH:
				_on_log("休想卡只能在别人打出功能牌时打出（响应窗口），自己的回合打不出去")
				return
			elif card.kind == Card.Kind.DEFUSE:
				_on_log("拆除卡在抽到爆弹时自动使用，平时攥在手里就好")
				return
			else:
				_on_log("这张牌当前不能主动打出")
				return
	if ok:
		_after_action()
	else:
		_has_flight = false
		_refresh()


func _refresh_steal_targets(steal_index: int) -> void:
	for child in _target_row.get_children():
		child.queue_free()
	_target_row.visible = true
	var hint := _make_label("偷牌：选择目标 →", 14)
	_target_row.add_child(hint)
	var me_idx := _sm.current_index()
	for i in _sm.players().size():
		var target := _sm.players()[i]
		if i == me_idx or not target.alive:
			continue
		var btn := Button.new()
		btn.text = "%s（%d 张）" % [target.name, target.hand.size()]
		btn.custom_minimum_size = Vector2(0, 40)
		_style_button(btn)
		btn.disabled = target.hand.is_empty()
		btn.pressed.connect(func() -> void:
			if _sm.play_steal(steal_index, i):
				_after_action()
			else:
				_refresh())
		_target_row.add_child(btn)


# ---- 钳子组合 ----

func _on_pliers_combo(combo: String) -> void:
	var indices := _selected_pliers.duplicate()
	_selected_pliers.clear()
	if combo == "flush":
		if _sm.play_pliers(indices, "flush"):
			_after_action()
		else:
			_refresh()
		return
	_refresh_combo_targets(indices, combo)


func _refresh_combo_targets(indices: Array[int], combo: String) -> void:
	for child in _target_row.get_children():
		child.queue_free()
	_target_row.visible = true
	var label: String = {"pair": "对子", "trio": "三条"}[combo]
	var hint := _make_label("工具·%s：选择目标 →" % label, 14)
	_target_row.add_child(hint)
	var me_idx := _sm.current_index()
	for i in _sm.players().size():
		var target := _sm.players()[i]
		if i == me_idx or not target.alive or target.hand.is_empty():
			continue
		var btn := Button.new()
		btn.text = "%s（%d 张）" % [target.name, target.hand.size()]
		btn.custom_minimum_size = Vector2(0, 40)
		_style_button(btn)
		if combo == "trio":
			btn.pressed.connect(func() -> void: _refresh_kind_picker(indices, combo, i))
		else:
			btn.pressed.connect(func() -> void:
				if _sm.play_pliers(indices, combo, i):
					_after_action()
				else:
					_refresh())
		_target_row.add_child(btn)


func _refresh_kind_picker(indices: Array[int], combo: String, target_index: int) -> void:
	for child in _kind_row.get_children():
		child.queue_free()
	_target_row.visible = false
	_kind_row.visible = true
	var hint := _make_label("念一个牌名（对方有就必须给）→", 14)
	_kind_row.add_child(hint)
	for kind in Card.plier_kind_list() + [Card.Kind.SKIP, Card.Kind.ATTACK, Card.Kind.PEEK,
			Card.Kind.SHUFFLE, Card.Kind.STEAL, Card.Kind.OVERDRAW, Card.Kind.WISH, Card.Kind.DEFUSE]:
		var btn := Button.new()
		btn.text = Card.display_name(kind)
		btn.custom_minimum_size = Vector2(0, 40)
		_style_button(btn)
		btn.pressed.connect(func() -> void:
			_kind_row.visible = false
			if _sm.play_pliers(indices, combo, target_index, kind):
				_after_action()
			else:
				_refresh())
		_kind_row.add_child(btn)


func _on_confirm_bomb() -> void:
	if _sm == null or _sm.phase != TurnStateMachine.TurnPhase.BOMB_PLACEMENT:
		return
	_sm.confirm_bomb_placement(int(_bomb_slider.value))
	_after_action()


# ---- 飞牌动画与爆炸特效（第 3+4 步）----

## 暂存一次飞牌：出牌 from=卡牌当前位置 to=中央出牌区；抽牌 from=牌堆 to=手牌区。
func _stage_flight(view: Control, kind: int, is_draw: bool) -> void:
	_has_flight = true
	_flight_kind = kind
	_flight_face = not is_draw
	if is_draw:
		_flight_from = _deck_stack.global_position + Vector2(30, 50)
		_flight_to = _hand_area.global_position + Vector2(600, 100)
	else:
		_flight_from = view.global_position
		_flight_to = _center_play.global_position + Vector2(10, 4)


## 抽牌飞行的便捷入口。
func _stage_draw_flight() -> void:
	_stage_flight(null, Card.Kind.SKIP, true)


## 在特效层生成一张飞牌，从 from 补间到 to，落地即散。
func _fly_card(from: Vector2, to: Vector2, kind: int, face_up: bool) -> void:
	var flyer := CardView.new(kind, face_up)
	flyer.position = from
	flyer.z_index = 50
	_fx_layer.add_child(flyer)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(flyer, "position", to, 0.26) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(flyer, "rotation_degrees", randf_range(-6.0, 6.0), 0.26)
	await tw.finished
	flyer.queue_free()


## 爆弹引爆：红闪 + 震屏 + 爆炸粒子 + 大字Boom。
func _on_bomb_exploded(player_name: String) -> void:
	_flash_red()
	_shake_screen()
	_spawn_explosion(Vector2(640, 250))
	_show_boom_label(player_name)


func _flash_red() -> void:
	var flash := ColorRect.new()
	flash.color = Color(0.9, 0.12, 0.08, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.5, 0.07)
	tw.tween_property(flash, "color:a", 0.0, 0.55)
	tw.tween_callback(flash.queue_free)


func _shake_screen() -> void:
	var tw := create_tween()
	for i in 6:
		tw.tween_property(self, "position",
				Vector2(randf_range(-14, 14), randf_range(-10, 10)), 0.04)
	tw.tween_property(self, "position", Vector2.ZERO, 0.05)


func _spawn_explosion(center: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = center
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 90
	p.lifetime = 0.9
	p.spread = 180.0
	p.gravity = Vector2(0, 700)
	p.initial_velocity_min = 220.0
	p.initial_velocity_max = 560.0
	p.scale_amount_min = 4.0
	p.scale_amount_max = 13.0
	var gt := GradientTexture2D.new()
	gt.width = 16
	gt.height = 16
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.9, 0.45))
	grad.set_color(1, Color(1.0, 0.3, 0.08, 0.0))
	gt.gradient = grad
	p.texture = gt
	_fx_layer.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func _show_boom_label(player_name: String) -> void:
	var boom := _make_label("轰！%s 被炸出局！" % player_name, 54, Color("FFD54A"))
	boom.size = Vector2(1280, 80)
	boom.position = Vector2(0, 296)
	boom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boom.add_theme_color_override("font_outline_color", Color(0.25, 0.02, 0.02))
	boom.add_theme_constant_override("outline_size", 10)
	boom.pivot_offset = Vector2(640, 40)
	boom.scale = Vector2(0.3, 0.3)
	_fx_layer.add_child(boom)
	var tw := create_tween()
	tw.tween_property(boom, "scale", Vector2(1.12, 1.12), 0.12) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(boom, "scale", Vector2.ONE, 0.1)
	tw.tween_interval(0.9)
	tw.tween_property(boom, "modulate:a", 0.0, 0.35)
	tw.tween_callback(boom.queue_free)
