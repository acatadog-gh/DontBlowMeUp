# @trace PLAT-002, PLAT-003
## 联机版客户端（M2.1/M2.2）：大厅（昵称/创建/加入）→ 房间等待 → 联机对局。
## 视觉复用拍桌版（CardView + 桌垫 + 扇形手牌），数据全部来自服务器按座位下发的视图。
## 运行前先启动服务器：Godot --headless --path 工程目录 -s scripts/server/server_main.gd
extends Control

const DESKTOP_COLOR := Color("1C2733")
const FELT_COLOR := Color("223A4C")
const PANEL_COLOR := Color("3A566B")
const GOLD := Color("E8B04B")
const DEFAULT_SERVER := "ws://127.0.0.1:8920"
# 手牌展示：牌少时舒展、牌多时收紧，每张至少露出这么宽，避免挤成一团
const HAND_IDEAL_STEP := 96.0
const HAND_MIN_STEP := 30.0
const HAND_OVERVIEW_MIN := 9      # 手牌达到这个张数才出现「手牌全览」
const OPPONENT_SLOTS := {
	1: [Vector2(581, 40)],
	2: [Vector2(30, 196), Vector2(1132, 196)],
	3: [Vector2(30, 196), Vector2(581, 40), Vector2(1132, 196)],
	4: [Vector2(30, 196), Vector2(320, 40), Vector2(842, 40), Vector2(1132, 196)],
}

enum UiState { LOBBY, ROOM, GAME }
var ui_state: UiState = UiState.LOBBY

var net: NetClient
var my_name := "玩家"
var room_code := ""
var my_seat := -1
var view := {}                      # 最近一次服务器状态视图
var _selected_pliers: Array[int] = []
var _pending_steal_index := -1
var _response_token := 0
var _response_deadline_ms := 0.0

# UI 引用
var _lobby_overlay: PanelContainer
var _name_edit: LineEdit
var _addr_edit: LineEdit
var _code_edit: LineEdit
var _lobby_status: Label
var _room_overlay: PanelContainer
var _room_title: Label
var _room_players: Label
var _start_btn: Button
var _status_label: Label
var _counts_label: Label
var _zone_label: Label
var _opponents_row: Control
var _hand_area: Control
var _hand_cards: Array[CardView] = []
var _action_row: HBoxContainer
var _target_row: HBoxContainer
var _kind_row: HBoxContainer
var _op_panel: Control
var _bomb_row: HBoxContainer
var _bomb_slider: HSlider
var _log_label: RichTextLabel
var _log_panel: PanelContainer
var _deck_stack: Control
var _deck_count_label: Label
var _center_play: Control
var _center_hint: Label
var _discard_stack: Control
var _discard_count_label: Label
var _hand_count_label: Label
var _fx_layer: Control
var _result_overlay: PanelContainer
var _result_label: Label
var _seat_anchors: Dictionary = {}     # 座位 → 屏幕锚点（飞牌起终点用）
var _banner: PanelContainer
var _hover_index := -1
var _hand_base_x: Array[float] = []
var _hover_tween: Tween
var _overview_btn: Button
var _hand_overview: PanelContainer


func _ready() -> void:
	var font: Font = load("res://assets/fonts/NotoSansSC-Regular.ttf")
	if font != null:
		var ui_theme := Theme.new()
		ui_theme.default_font = font
		ui_theme.default_font_size = 15
		self.theme = ui_theme
	net = NetClient.new()
	net.connected_ok.connect(_on_net_ok)
	net.connection_failed.connect(_on_net_fail)
	net.disconnected.connect(_on_net_down)
	net.received.connect(_on_msg)
	add_child(net)
	_build_ui()
	_show_lobby()


# ---- 通用样式（与拍桌版一致）----

func _glass_style(radius := 10, alpha := 0.55) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.12, 0.2, alpha)
	style.set_corner_radius_all(radius)
	style.border_color = Color(1, 1, 1, 0.12)
	style.set_border_width_all(1)
	return style


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


func _overlay_panel(pos: Vector2, min_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = pos
	panel.custom_minimum_size = min_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.14, 0.22, 0.95)
	style.set_corner_radius_all(14)
	style.border_color = Color("C9A227")
	style.set_border_width_all(2)
	style.shadow_size = 16
	style.shadow_color = Color(0, 0, 0, 0.5)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	return panel


# ---- UI 构建 ----

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = DESKTOP_COLOR
	add_child(bg)

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

	var top_bar := Panel.new()
	top_bar.position = Vector2.ZERO
	top_bar.size = Vector2(1280, 36)
	top_bar.add_theme_stylebox_override("panel", _glass_style(0, 0.75))
	add_child(top_bar)
	var title := _make_label("别炸我！·联机", 14, GOLD)
	title.position = Vector2(16, 8)
	add_child(title)
	_counts_label = _make_label("", 13, Color(1, 1, 1, 0.75))
	_counts_label.position = Vector2(880, 9)
	add_child(_counts_label)

	_opponents_row = Control.new()
	_opponents_row.position = Vector2.ZERO
	_opponents_row.size = Vector2(1280, 720)
	_opponents_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_opponents_row)

	_deck_stack = Control.new()
	_deck_stack.position = Vector2(295, 152)
	add_child(_deck_stack)
	_deck_count_label = _make_label("", 14, Color.WHITE)
	_deck_count_label.position = Vector2(316, 320)
	_deck_count_label.custom_minimum_size = Vector2(80, 0)
	_deck_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_deck_count_label)

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

	_discard_stack = Control.new()
	_discard_stack.position = Vector2(860, 152)
	add_child(_discard_stack)
	_discard_count_label = _make_label("", 14, Color.WHITE)
	_discard_count_label.position = Vector2(886, 320)
	_discard_count_label.custom_minimum_size = Vector2(80, 0)
	_discard_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_discard_count_label)

	_hand_area = Control.new()
	_hand_area.position = Vector2(0, 506)
	_hand_area.size = Vector2(1280, 214)
	add_child(_hand_area)

	_op_panel = Control.new()
	_op_panel.position = Vector2(0, 414)
	_op_panel.size = Vector2(1280, 92)
	add_child(_op_panel)

	_status_label = _make_label("", 14, GOLD)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.position = Vector2(0, 2)
	_status_label.size = Vector2(1280, 22)
	_op_panel.add_child(_status_label)

	var rows: Array[HBoxContainer] = []
	for center_def in [[30, 48], [28, 56], [28, 56]]:
		var center := CenterContainer.new()
		center.position = Vector2(0, center_def[0])
		center.size = Vector2(1280, center_def[1])
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_op_panel.add_child(center)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(row)
		rows.append(row)
	_action_row = rows[0]
	_target_row = rows[1]
	_kind_row = rows[2]

	_bomb_row = HBoxContainer.new()
	_bomb_row.add_theme_constant_override("separation", 10)
	_bomb_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_bomb_row.position = Vector2(0, 34)
	_bomb_row.size = Vector2(1280, 44)
	_bomb_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bomb_row.add_child(_make_label("暗置爆弹位置：", 14))
	_bomb_slider = HSlider.new()
	_bomb_slider.min_value = 0
	_bomb_slider.max_value = 1
	_bomb_slider.custom_minimum_size = Vector2(260, 24)
	_bomb_row.add_child(_bomb_slider)
	var bomb_confirm := Button.new()
	bomb_confirm.text = "确认暗置"
	_style_button(bomb_confirm)
	bomb_confirm.pressed.connect(func() -> void:
		net.send({"t": NetProtocol.T_ACT, "a": NetProtocol.A_BOMB, "pos": int(_bomb_slider.value)}))
	_bomb_row.add_child(bomb_confirm)
	_op_panel.add_child(_bomb_row)

	_hand_count_label = _make_label("", 12, Color(1, 1, 1, 0.6))
	_hand_count_label.position = Vector2(1000, 512)
	add_child(_hand_count_label)

	_overview_btn = Button.new()
	_overview_btn.text = "手牌全览"
	_overview_btn.position = Vector2(1150, 504)
	_overview_btn.size = Vector2(116, 28)
	_style_button(_overview_btn)
	_overview_btn.visible = false
	_overview_btn.pressed.connect(_show_hand_overview)
	add_child(_overview_btn)

	var log_btn := Button.new()
	log_btn.text = "记录"
	log_btn.position = Vector2(1204, 4)
	log_btn.size = Vector2(64, 28)
	_style_button(log_btn)
	log_btn.pressed.connect(func() -> void: _log_panel.visible = not _log_panel.visible)
	add_child(log_btn)

	_log_panel = PanelContainer.new()
	_log_panel.position = Vector2(920, 470)
	_log_panel.size = Vector2(348, 244)
	_log_panel.add_theme_stylebox_override("panel", _glass_style(10, 0.92))
	_log_panel.visible = false
	add_child(_log_panel)
	var log_box := VBoxContainer.new()
	_log_panel.add_child(log_box)
	log_box.add_child(_make_label("对局日志", 12, Color(1, 1, 1, 0.5)))
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

	_fx_layer = Control.new()
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)

	_build_lobby()
	_build_room_overlay()
	_build_result_overlay()


func _build_lobby() -> void:
	_lobby_overlay = _overlay_panel(Vector2(440, 170), Vector2(400, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_lobby_overlay.add_child(box)
	var title := _make_label("《别炸我！》联机大厅", 22, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var name_row := HBoxContainer.new()
	name_row.add_child(_make_label("昵称：", 14))
	_name_edit = LineEdit.new()
	_name_edit.text = "玩家"
	_name_edit.max_length = 8
	_name_edit.custom_minimum_size = Vector2(220, 0)
	name_row.add_child(_name_edit)
	box.add_child(name_row)

	var addr_row := HBoxContainer.new()
	addr_row.add_child(_make_label("服务器：", 14))
	_addr_edit = LineEdit.new()
	_addr_edit.text = DEFAULT_SERVER
	_addr_edit.custom_minimum_size = Vector2(280, 0)
	addr_row.add_child(_addr_edit)
	box.add_child(addr_row)
	box.add_child(_make_label("本机测试：先启动服务器（见 docs/online-plan.md），默认地址即可；\n联调填 ws://服务器IP:8920", 11, Color(1, 1, 1, 0.5)))

	var create_btn := Button.new()
	create_btn.text = "创 建 房 间"
	_style_button(create_btn)
	create_btn.pressed.connect(_on_create_room)
	box.add_child(create_btn)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	join_row.add_child(_make_label("邀请码：", 14))
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "6 位数字"
	_code_edit.custom_minimum_size = Vector2(120, 0)
	join_row.add_child(_code_edit)
	var join_btn := Button.new()
	join_btn.text = "加 入 房 间"
	_style_button(join_btn)
	join_btn.pressed.connect(_on_join_room)
	join_row.add_child(join_btn)
	box.add_child(join_row)

	_lobby_status = _make_label("", 13, Color("E74C3C"))
	box.add_child(_lobby_status)


func _build_room_overlay() -> void:
	_room_overlay = _overlay_panel(Vector2(420, 200), Vector2(440, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_room_overlay.add_child(box)
	_room_title = _make_label("房间", 24, GOLD)
	_room_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_room_title)
	_room_players = _make_label("", 14)
	_room_players.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_room_players)
	box.add_child(_make_label("把邀请码发给朋友，加入后即可开局（2-5 人）", 12, Color(1, 1, 1, 0.55)))
	_start_btn = Button.new()
	_start_btn.text = "开 始 游 戏"
	_style_button(_start_btn)
	_start_btn.pressed.connect(func() -> void: net.send({"t": NetProtocol.T_START}))
	var center := CenterContainer.new()
	center.add_child(_start_btn)
	box.add_child(center)
	var leave_btn := Button.new()
	leave_btn.text = "离开房间"
	_style_button(leave_btn)
	leave_btn.pressed.connect(_leave_to_lobby)
	var center2 := CenterContainer.new()
	center2.add_child(leave_btn)
	box.add_child(center2)


func _build_result_overlay() -> void:
	_result_overlay = _overlay_panel(Vector2(470, 270), Vector2(340, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_result_overlay.add_child(box)
	_result_label = _make_label("", 22, GOLD)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_label)
	var again_btn := Button.new()
	again_btn.text = "回到大厅"
	_style_button(again_btn)
	again_btn.pressed.connect(_leave_to_lobby)
	var center := CenterContainer.new()
	center.add_child(again_btn)
	box.add_child(center)
	_result_overlay.visible = false


# ---- 大厅 / 网络 ----

func _ensure_hello() -> void:
	my_name = _name_edit.text.strip_edges()
	if my_name.is_empty():
		my_name = "玩家"
	net.send({"t": NetProtocol.T_HELLO, "name": my_name})


func _on_create_room() -> void:
	if net.state != NetClient.NetState.OPEN:
		_connect_and_then(func() -> void: net.send({"t": NetProtocol.T_CREATE}))
	else:
		net.send({"t": NetProtocol.T_CREATE})


func _on_join_room() -> void:
	var code := _code_edit.text.strip_edges()
	if code.length() != 6:
		_lobby_status.text = "邀请码是 6 位数字"
		return
	room_code = code
	if net.state != NetClient.NetState.OPEN:
		_connect_and_then(func() -> void:
			net.send({"t": NetProtocol.T_JOIN, "code": room_code}))
	else:
		net.send({"t": NetProtocol.T_JOIN, "code": code})


func _connect_and_then(action: Callable) -> void:
	_lobby_status.text = "连接服务器中……"
	var url := _addr_edit.text.strip_edges()
	if url.is_empty():
		url = DEFAULT_SERVER
	_pending_action = action
	net.start(url)

var _pending_action: Callable = Callable()


func _on_net_ok() -> void:
	_lobby_status.text = ""
	_ensure_hello()
	if _pending_action.is_valid():
		var action := _pending_action
		_pending_action = Callable()
		action.call()


func _on_net_fail(reason: String) -> void:
	_lobby_status.text = reason
	_pending_action = Callable()


func _on_net_down(reason: String) -> void:
	_on_log("与服务器断开：%s" % reason)
	if ui_state != UiState.LOBBY:
		_show_lobby()
		_lobby_status.text = "与服务器断开：%s" % reason


func _show_lobby() -> void:
	ui_state = UiState.LOBBY
	view = {}
	_lobby_overlay.visible = true
	_room_overlay.visible = false
	_result_overlay.visible = false
	_hand_area.visible = false
	_op_panel.visible = false
	_opponents_row.visible = false
	for child in _deck_stack.get_children():
		child.queue_free()
	for child in _discard_stack.get_children():
		child.queue_free()
	for child in _center_play.get_children():
		child.queue_free()
	_deck_count_label.text = ""
	_discard_count_label.text = ""
	_counts_label.text = ""
	_status_label.text = ""
	_zone_label.text = ""


func _leave_to_lobby() -> void:
	net.send({"t": NetProtocol.T_LEAVE})
	net.close()
	_show_lobby()


# ---- 服务器消息处理 ----

func _on_msg(msg: Dictionary) -> void:
	var t: String = msg.get("t", "")
	match t:
		NetProtocol.T_ROOM_STATE:
			my_seat = int(msg.get("you", -1))
			room_code = String(msg.get("code", room_code))
			_show_room(msg)
		NetProtocol.T_STATE:
			view = msg
			# 服务器每次下发视图都带剩余响应毫秒，校准本地倒计时（漏收窗口消息也能显示）
			if String(msg.get("phase", "")) == "response" and msg.has("response_left_ms"):
				_response_deadline_ms = Time.get_ticks_msec() \
						+ float(msg.get("response_left_ms", 0.0))
			_render_game()
		NetProtocol.T_LOG:
			_on_log(String(msg.get("msg", "")))
		NetProtocol.T_EVENT:
			_on_event(msg)
		NetProtocol.T_ERROR:
			_on_log("⚠ %s" % msg.get("msg", ""))
		NetProtocol.T_FX:
			_on_fx(msg)
		NetProtocol.T_RESPONSE_WINDOW:
			if bool(msg.get("open", false)):
				_response_token += 1
				_response_deadline_ms = Time.get_ticks_msec() + float(int(msg.get("seconds", 8))) * 1000.0
				_run_response_countdown(_response_token)


func _on_event(msg: Dictionary) -> void:
	match String(msg.get("e", "")):
		NetProtocol.E_BOMB:
			var player_name := String(msg.get("name", ""))
			_flash_red()
			_shake_screen()
			_spawn_explosion(Vector2(640, 250))
			_show_boom_label(player_name)
		NetProtocol.E_PEEK:
			var dlg := AcceptDialog.new()
			dlg.title = "预知结果（仅本人可见）"
			dlg.dialog_text = String(msg.get("text", ""))
			dlg.ok_button_text = "看完了"
			dlg.close_requested.connect(func() -> void: dlg.queue_free())
			add_child(dlg)
			dlg.popup_centered()
		NetProtocol.E_GAME_OVER:
			var winner := String(msg.get("winner", ""))
			_result_label.text = "🎉 %s 获胜！" % winner if winner != "" else "无存活玩家"
			_result_overlay.visible = true
		NetProtocol.E_OFFLINE:
			_on_log("— %s 掉线了（托管中）—" % msg.get("name", ""))
		NetProtocol.E_CONNECTED:
			pass


func _show_room(msg: Dictionary) -> void:
	ui_state = UiState.ROOM
	_lobby_overlay.visible = false
	_result_overlay.visible = false
	_room_overlay.visible = true
	_hand_area.visible = false
	_op_panel.visible = false
	_opponents_row.visible = false
	var lines := "房间邀请码：%s" % msg.get("code", room_code)
	var my_host := false
	for p in msg.get("players", []):
		lines += "\n%s %s%s" % ["👑" if bool(p.get("host", false)) else "　",
				p.get("name", "?"), "" if bool(p.get("on", true)) else "（掉线）"]
		if int(p.get("seat", -1)) == my_seat and bool(p.get("host", false)):
			my_host = true
	_room_title.text = "房间 %s" % msg.get("code", room_code)
	_room_players.text = lines
	_start_btn.visible = my_host
	_start_btn.disabled = msg.get("players", []).size() < 2
	if not my_host:
		_room_players.text += "\n（等待房主开始）"


# ---- 对局渲染（全部来自服务器视图）----

func _render_game() -> void:
	if view.is_empty():
		return
	ui_state = UiState.GAME
	_lobby_overlay.visible = false
	_room_overlay.visible = false
	_result_overlay.visible = view.get("phase", "") == "over"
	_hand_area.visible = true
	_op_panel.visible = true
	_opponents_row.visible = true

	var phase := String(view.get("phase", "action"))
	var your_turn: bool = bool(view.get("your_turn", false))
	if phase != "response":
		_response_deadline_ms = 0.0   # 窗口关闭，停掉本地倒计时显示
	_counts_label.text = "牌堆 %d ｜ 弃牌 %d ｜ 已引爆 %d ｜ 房间 %s" % [
			int(view.get("draw", 0)), int(view.get("discard_count", 0)),
			int(view.get("exploded", 0)), room_code]
	_refresh_piles()
	_refresh_opponents()
	_clear_rows()
	if phase != "response":
		_zone_label.text = ""

	match phase:
		"action":
			if your_turn:
				_render_my_action()
			else:
				_render_wait()
		"overdraw":
			if your_turn:
				_render_my_overdraw()
			else:
				_render_wait()
		"bomb":
			_render_bomb(your_turn)
		"response":
			_render_response()
		"flush":
			if your_turn:
				_render_flush()
			else:
				_render_wait()
		"over":
			var winner := String(view.get("winner", ""))
			_status_label.text = "游戏结束" + ("——赢家：%s" % winner if winner != "" else "")
			_result_label.text = "🎉 %s 获胜！" % winner if winner != "" else "无存活玩家"


func _render_wait() -> void:
	var players: Array = view.get("players", [])
	var cur_name := ""
	for p in players:
		if bool(p.get("cur", false)):
			cur_name = String(p.get("name", ""))
			if not bool(p.get("on", true)):
				cur_name += "（掉线托管中）"
	_status_label.text = "轮到 %s 行动，请稍候……" % cur_name
	_zone_label.text = ""
	_rebuild_hand([], false, false)


func _render_my_action() -> void:
	_status_label.text = "你的回合：点卡牌打出，或点「抽一张牌」"
	_zone_label.text = ""
	var hand: Array = view.get("hand", [])
	_rebuild_hand(_selected_pliers, true, true)

	var draw_btn := Button.new()
	draw_btn.text = "抽一张牌"
	draw_btn.tooltip_text = "从公共牌堆顶抽 1 张并结束回合。抽到爆弹：有拆除可救回，没有就出局。"
	_style_button(draw_btn)
	draw_btn.pressed.connect(func() -> void:
		net.send({"t": NetProtocol.T_ACT, "a": NetProtocol.A_DRAW}))
	_action_row.add_child(draw_btn)

	if _selected_pliers.size() > 0 and _selected_pliers.size() <= int(hand.size()):
		var cancel_btn := Button.new()
		cancel_btn.text = "取消选择"
		_style_button(cancel_btn)
		cancel_btn.pressed.connect(func() -> void:
			_selected_pliers.clear()
			_render_game())
		_action_row.add_child(cancel_btn)
		var count := _selected_pliers.size()
		if count == 1:
			var single_btn := Button.new()
			single_btn.text = "单张打出（无效果）"
			single_btn.tooltip_text = "直接弃置进弃牌堆并结束回合；弃牌可被五张组合回收。"
			_style_button(single_btn)
			var single_idx: int = _selected_pliers[0]
			single_btn.pressed.connect(func() -> void:
				net.send({"t": NetProtocol.T_ACT, "a": NetProtocol.A_SINGLE, "card": single_idx})
				_selected_pliers.clear())
			_action_row.add_child(single_btn)
		var kinds: Array[int] = []
		for idx in _selected_pliers:
			if idx < hand.size():
				kinds.append(int(hand[idx]))
		var distinct := {}
		for k in kinds:
			distinct[k] = true
		var same_all := distinct.size() == 1 and kinds.size() == count
		if count == 2 and same_all:
			_add_combo_button("指定一人，随机偷走其 1 张手牌（不亮牌）", "pair")
		elif count == 3 and same_all:
			_add_combo_button("念一个牌名，目标有就必须给", "trio")
		elif count == 5 and distinct.size() == 5:
			_add_combo_button("从弃牌堆任选 1 张回收", "flush")
		elif count >= 2:
			var hint := _make_label("继续多选：同种×2=对子、同种×3=三条、五种各×1=五张", 12, Color(1, 1, 1, 0.7))
			_action_row.add_child(hint)


func _add_combo_button(tip: String, combo: String) -> void:
	var btn := Button.new()
	btn.text = "工具·%s" % {"pair": "对子", "trio": "三条", "flush": "五张"}[combo]
	btn.tooltip_text = tip
	_style_button(btn)
	btn.pressed.connect(_on_pliers_combo.bind(combo))
	_action_row.add_child(btn)


func _on_pliers_combo(combo: String) -> void:
	var indices := _selected_pliers.duplicate()
	_selected_pliers.clear()
	if combo == "flush":
		net.send({"t": NetProtocol.T_ACT, "a": NetProtocol.A_PLIERS,
				"cards": indices, "combo": "flush"})
		return
	_show_combo_targets(indices, combo)


func _show_combo_targets(indices: Array[int], combo: String) -> void:
	_target_row.visible = true
	_action_row.visible = false
	var label: String = {"pair": "对子", "trio": "三条"}[combo]
	_target_row.add_child(_make_label("工具·%s：选择目标 →" % label, 14))
	var players: Array = view.get("players", [])
	for i in players.size():
		var p: Dictionary = players[i]
		if i == my_seat or not bool(p.get("alive", false)) or int(p.get("count", 0)) == 0:
			continue
		var idx := i
		var btn := Button.new()
		btn.text = "%s（%d 张）" % [p.get("name", "?"), int(p.get("count", 0))]
		btn.custom_minimum_size = Vector2(0, 40)
		_style_button(btn)
		if combo == "trio":
			btn.pressed.connect(func() -> void: _show_kind_picker(indices, idx))
		else:
			btn.pressed.connect(func() -> void:
				_target_row.visible = false
				_action_row.visible = true
				net.send({"t": NetProtocol.T_ACT, "a": NetProtocol.A_PLIERS,
						"cards": indices, "combo": "pair", "target": idx}))
		_target_row.add_child(btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "返回"
	_style_button(cancel_btn)
	cancel_btn.pressed.connect(func() -> void:
		_target_row.visible = false
		_action_row.visible = true
		_render_game())
	_target_row.add_child(cancel_btn)


func _show_kind_picker(indices: Array[int], target_index: int) -> void:
	_target_row.visible = false
	_kind_row.visible = true
	_kind_row.add_child(_make_label("念一个牌名（对方有就必须给）→", 14))
	for kind in Card.plier_kind_list() + [Card.Kind.SKIP, Card.Kind.ATTACK, Card.Kind.PEEK,
			Card.Kind.SHUFFLE, Card.Kind.STEAL, Card.Kind.OVERDRAW, Card.Kind.WISH, Card.Kind.DEFUSE]:
		var btn := Button.new()
		btn.text = Card.display_name(kind)
		btn.custom_minimum_size = Vector2(0, 40)
		_style_button(btn)
		btn.pressed.connect(func() -> void:
			_kind_row.visible = false
			_action_row.visible = true
			net.send({"t": NetProtocol.T_ACT, "a": NetProtocol.A_PLIERS,
					"cards": indices, "combo": "trio", "target": target_index, "wanted": kind}))
		_kind_row.add_child(btn)


func _render_my_overdraw() -> void:
	_status_label.text = "透支连抽中（每回合限打一张透支）"
	var zone: Array = view.get("overdraw", [])
	_zone_label.text = "透支区（%d 张）面朝上公开：喊停全部入手，再抽抽中爆弹全弃" % zone.size()
	_rebuild_hand([], false, false)
	var keep_btn := Button.new()
	keep_btn.text = "再抽一张（风险加大）"
	_style_button(keep_btn)
	keep_btn.pressed.connect(func() -> void:
		net.send({"t": NetProtocol.T_ACT, "a": NetProtocol.A_OVERDRAW_DRAW}))
	_action_row.add_child(keep_btn)
	var stop_btn := Button.new()
	stop_btn.text = "喊停！%d 张全部入手" % zone.size()
	_style_button(stop_btn)
	stop_btn.pressed.connect(func() -> void:
		net.send({"t": NetProtocol.T_ACT, "a": NetProtocol.A_OVERDRAW_STOP}))
	_action_row.add_child(stop_btn)


func _render_response() -> void:
	# RESPONSE 阶段 current_index 仍是出牌者：your_turn=true 说明这张牌是你打的，
	# 自己不能反制自己的牌，只显示等待；休想按钮只给其他玩家（MECH-012）
	var i_am_actor: bool = bool(view.get("your_turn", false))
	if i_am_actor:
		_status_label.text = "你打出的牌正在等待其他玩家响应……"
	else:
		_status_label.text = "有人打出功能牌——持有【休想】的玩家可以反制"
	_zone_label.text = _response_countdown_text()
	_rebuild_hand([], false, false)
	if i_am_actor:
		return
	var wish_btn := Button.new()
	wish_btn.text = "打出【休想】！（反制该功能牌）"
	wish_btn.tooltip_text = "只有手里真有休想牌才应点击。"
	_style_button(wish_btn)
	wish_btn.pressed.connect(func() -> void:
		_response_token += 1
		net.send({"t": NetProtocol.T_WISH, "use": true}))
	_action_row.add_child(wish_btn)
	var pass_btn := Button.new()
	pass_btn.text = "无人反制，立即继续"
	_style_button(pass_btn)
	pass_btn.pressed.connect(func() -> void:
		_response_token += 1
		net.send({"t": NetProtocol.T_WISH, "use": false}))
	_action_row.add_child(pass_btn)


## 响应窗口剩余秒数：以服务器下发的剩余毫秒为准，本地时钟兜底。
func _response_left_sec() -> int:
	if _response_deadline_ms <= 0.0:
		return 0
	return maxi(0, int(ceilf((_response_deadline_ms - Time.get_ticks_msec()) / 1000.0)))


func _response_countdown_text() -> String:
	var left := _response_left_sec()
	if left <= 0:
		return "响应窗口已结束"
	return "匿名响应中：剩余 %d 秒，超时后不能再打出休想" % left


func _run_response_countdown(token: int) -> void:
	while token == _response_token and _response_deadline_ms > 0.0:
		if _response_left_sec() <= 0:
			return
		if String(view.get("phase", "")) == "response":
			_zone_label.text = _response_countdown_text()
			if bool(view.get("your_turn", false)):
				_status_label.text = "你打出的牌正在等待其他玩家响应（剩余 %d 秒）……" \
						% _response_left_sec()
		await get_tree().create_timer(0.25).timeout


func _render_flush() -> void:
	_status_label.text = "工具·五张：请从弃牌堆选 1 张回收"
	var kinds: Array = view.get("discard_kinds", [])
	if kinds.is_empty():
		_action_row.add_child(_make_label("弃牌堆为空", 12, Color(1, 1, 1, 0.6)))
		return
	for i in kinds.size():
		var idx := i
		var btn := Button.new()
		btn.text = "%d:%s" % [i + 1, Card.display_name(int(kinds[i]))]
		_style_button(btn)
		btn.pressed.connect(func() -> void:
			net.send({"t": NetProtocol.T_ACT, "a": NetProtocol.A_FLUSH, "idx": idx}))
		_action_row.add_child(btn)


func _render_bomb(your_turn: bool) -> void:
	if your_turn:
		var bomb_range := int(view.get("bomb_range", 1))
		_bomb_row.visible = true
		_bomb_slider.max_value = bomb_range
		_bomb_slider.value = bomb_range / 2.0
		_status_label.text = "你使用拆除卡！选择爆弹暗置位置（只有你知道）"
		_rebuild_hand([], false, false)
	else:
		_status_label.text = "有人使用拆除卡，爆弹已塞回牌堆……"
		_rebuild_hand([], false, false)


# ---- 视图渲染组件（复用拍桌版）----

func _clear_rows() -> void:
	# 动作排常驻可见（render_* 每次重建其内容）；只有目标/牌名排需要主动隐藏
	_action_row.visible = true
	for child in _action_row.get_children():
		child.queue_free()
	for row in [_target_row, _kind_row]:
		row.visible = false
		for child in row.get_children():
			child.queue_free()
	_bomb_row.visible = false


func _refresh_piles() -> void:
	for child in _deck_stack.get_children():
		child.queue_free()
	for child in _discard_stack.get_children():
		child.queue_free()
	for child in _center_play.get_children():
		child.queue_free()
	var draw_count := int(view.get("draw", 0))
	var layers := mini(3, maxi(1, ceili(draw_count / 12.0)))
	for i in layers:
		var back := CardView.new(Card.Kind.SKIP, false)
		back.scale = Vector2(0.72, 0.72)
		back.position = Vector2(i * 4, -i * 4)
		_deck_stack.add_child(back)
	_deck_count_label.text = "%d 张" % draw_count

	var discard_top := int(view.get("discard_top", -1))
	if discard_top >= 0:
		var back := CardView.new(Card.Kind.SKIP, false)
		back.scale = Vector2(0.72, 0.72)
		back.position = Vector2(4, 4)
		_discard_stack.add_child(back)
		var top_view := CardView.new(discard_top, true)
		top_view.scale = Vector2(0.72, 0.72)
		_discard_stack.add_child(top_view)
		var played := CardView.new(discard_top, true)
		played.scale = Vector2(1.16, 1.16)
		played.rotation_degrees = -3.0
		played.position = Vector2(8, 10)
		_center_play.add_child(played)
		_center_hint.text = "最近打出"
		_center_hint.position = Vector2(600, 348)
	else:
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
	_discard_count_label.text = "%d 张" % int(view.get("discard_count", 0))


func _refresh_opponents() -> void:
	for child in _opponents_row.get_children():
		child.queue_free()
	var players: Array = view.get("players", [])
	var opponents: Array[int] = []
	for i in players.size():
		if i != my_seat:
			opponents.append(i)
	if opponents.is_empty():
		return
	var slots: Array = OPPONENT_SLOTS[opponents.size()]
	for placed in opponents.size():
		var i: int = opponents[placed]
		var p: Dictionary = players[i]
		var slot_w := 118.0
		var alive: bool = bool(p.get("alive", true))
		var slot := Control.new()
		slot.position = slots[placed]
		slot.size = Vector2(118, 96)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_opponents_row.add_child(slot)
		_seat_anchors[i] = slot.position + Vector2(59.0, 48.0)   # 演出用锚点
		var plate := Panel.new()
		plate.size = Vector2(slot_w, 92)
		var plate_style := StyleBoxFlat.new()
		plate_style.bg_color = Color(PANEL_COLOR.r, PANEL_COLOR.g, PANEL_COLOR.b,
				0.55 if alive else 0.2)
		plate_style.set_corner_radius_all(10)
		if bool(p.get("cur", false)) and alive:
			plate_style.border_color = GOLD
			plate_style.set_border_width_all(2)
		plate.add_theme_stylebox_override("panel", plate_style)
		slot.add_child(plate)
		var avatar := Panel.new()
		avatar.position = Vector2(slot_w / 2.0 - 21, 6)
		avatar.size = Vector2(42, 42)
		var avatar_style := StyleBoxFlat.new()
		avatar_style.bg_color = Color("5B7C93") if alive else Color("4A4A4A")
		avatar_style.set_corner_radius_all(21)
		avatar.add_theme_stylebox_override("panel", avatar_style)
		slot.add_child(avatar)
		var initial := _make_label(String(p.get("name", "?")).left(1), 20, Color.WHITE)
		initial.position = Vector2(slot_w / 2.0 - 10, 12)
		slot.add_child(initial)
		var name_text := String(p.get("name", "?"))
		if not bool(p.get("on", true)):
			name_text += "（掉线）"
		var name_label := _make_label(name_text, 12, Color(1, 1, 1, 0.4) if not alive else Color.WHITE)
		name_label.position = Vector2(4, 50)
		name_label.custom_minimum_size = Vector2(slot_w - 8, 0)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(name_label)
		if alive:
			var fan := Control.new()
			fan.position = Vector2(slot_w / 2.0 - 24, 66)
			slot.add_child(fan)
			var shown := mini(int(p.get("count", 0)), 7)
			for j in shown:
				var mini := CardView.make_mini_back()
				mini.position = Vector2(j * 7.0, 0)
				mini.pivot_offset = Vector2(9, 13)
				mini.rotation_degrees = (j - (shown - 1) / 2.0) * 3.0
				fan.add_child(mini)
			var count_label := _make_label("%d 张" % int(p.get("count", 0)), 11, Color(1, 1, 1, 0.65))
			count_label.position = Vector2(slot_w - 42, 68)
			slot.add_child(count_label)
		else:
			var out_label := _make_label("已出局", 12, Color("E74C3C"))
			out_label.position = Vector2(8, 68)
			out_label.custom_minimum_size = Vector2(slot_w - 16, 0)
			out_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			slot.add_child(out_label)

	var me_info: Dictionary = players[my_seat] if my_seat >= 0 and my_seat < players.size() else {}
	var text := "%s（你）：%d 张手牌" % [me_info.get("name", ""), int(me_info.get("count", 0))]
	var zone: Array = view.get("overdraw", [])
	if not zone.is_empty():
		text += " ｜ 透支区 %d 张" % zone.size()
	_hand_count_label.text = text


func _layout_hand() -> void:
	var n := _hand_cards.size()
	if n == 0:
		_overview_btn.visible = false
		return
	await get_tree().process_frame
	if _hand_cards.size() != n:
		return
	var area_width := maxf(_hand_area.size.x - 48.0, 900.0)
	# 牌少时舒展，牌多时收紧；每张至少露出 HAND_MIN_STEP，保证看得到也点得到
	var spacing := HAND_IDEAL_STEP
	if n > 1 and (n - 1) * HAND_IDEAL_STEP + CardView.CARD_SIZE.x > area_width:
		spacing = maxf(HAND_MIN_STEP, (area_width - CardView.CARD_SIZE.x) / float(n - 1))
	var spread_deg := 4.0
	var total := minf((n - 1) * spread_deg, 30.0)
	var step := 0.0 if n == 1 else total / float(n - 1)
	var start_x := 640.0 - (n - 1) * spacing / 2.0
	var base_y := _hand_area.size.y - CardView.CARD_SIZE.y - 8.0
	_hand_base_x.clear()
	_hover_index = -1
	for i in n:
		var card := _hand_cards[i]
		var angle := -total / 2.0 + i * step if n > 1 else 0.0
		var x := start_x + i * spacing - CardView.CARD_SIZE.x / 2.0
		var y := base_y + absf(angle) * 1.8
		if card.selected:
			y -= 16.0
		_hand_base_x.append(x)
		card.position = Vector2(x, y)
		card.rotation_degrees = angle
		card.z_index = i            # 右压左：从左到右依次读得清
	_overview_btn.visible = n >= HAND_OVERVIEW_MIN


func _rebuild_hand(selected_set: Array, interactive: bool, clickable: bool) -> void:
	_close_hand_overview()
	for child in _hand_area.get_children():
		child.queue_free()
	_hand_cards.clear()
	var hand: Array = view.get("hand", [])
	for i in hand.size():
		var card_view := CardView.new(int(hand[i]), true)
		card_view.tooltip_text = _card_tip(int(hand[i])) if interactive else ""
		if selected_set.has(i):
			card_view.selected = true
		if not clickable:
			# 非交互（等待别人行动）：保持手牌清晰可读，只禁止点击
			card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			var card_index := i
			card_view.mouse_entered.connect(func() -> void: _on_card_hover(card_index))
			card_view.mouse_exited.connect(_on_card_unhover)
			card_view.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.pressed \
						and event.button_index == MOUSE_BUTTON_LEFT:
					_on_hand_card(card_index))
		_hand_area.add_child(card_view)
		_hand_cards.append(card_view)
	_layout_hand()


## 鼠标悬停某张牌：它两侧的手牌向两边让开，把这张完整露出来。
func _on_card_hover(index: int) -> void:
	_hover_index = index
	_apply_hover_shift()


func _on_card_unhover() -> void:
	_hover_index = -1
	_apply_hover_shift()


func _apply_hover_shift() -> void:
	if _hand_base_x.is_empty():
		return
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	for i in _hand_cards.size():
		if i >= _hand_base_x.size():
			break
		var offset := 0.0
		if _hover_index >= 0 and i != _hover_index:
			offset = 30.0 if i > _hover_index else -30.0
		_hover_tween.parallel().tween_property(_hand_cards[i], "position:x",
				_hand_base_x[i] + offset, 0.1)


## 手牌多到看不清时的一览面板：网格排布全部正面朝上，点一张即打出/选择。
func _show_hand_overview() -> void:
	_close_hand_overview()
	var hand: Array = view.get("hand", [])
	if hand.is_empty():
		return
	var panel := PanelContainer.new()
	panel.position = Vector2(84, 96)
	panel.custom_minimum_size = Vector2(1112, 500)
	panel.z_index = 60
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.12, 0.20, 0.97)
	style.set_corner_radius_all(14)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.shadow_size = 20
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	_hand_overview = panel
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var head := _make_label("手牌全览（%d 张）· 点一张即可打出或选中" % hand.size(), 17, GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1060, 380)
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for i in hand.size():
		var card := CardView.new(int(hand[i]), true)
		card.scale = Vector2(0.8, 0.8)
		card.pivot_offset = CardView.CARD_SIZE / 2.0
		card.custom_minimum_size = CardView.CARD_SIZE * 0.8
		card.tooltip_text = _card_tip(int(hand[i]))
		var index := i
		card.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_LEFT:
				_close_hand_overview()
				_on_hand_card(index))
		grid.add_child(card)
	var close_btn := Button.new()
	close_btn.text = "关闭全览"
	close_btn.custom_minimum_size = Vector2(180, 0)
	_style_button(close_btn)
	close_btn.pressed.connect(_close_hand_overview)
	box.add_child(close_btn)


func _close_hand_overview() -> void:
	if _hand_overview != null and is_instance_valid(_hand_overview):
		_hand_overview.queue_free()
	_hand_overview = null


func _card_tip(kind: int) -> String:
	if Card.is_plier(kind):
		return "%s：拆弹工具类。单张可直接打出（无效果）；同种×2=对子、同种×3=三条、五种各×1=五张。" % Card.display_name(kind)
	match kind:
		Card.Kind.SKIP:
			return "跳过：不抽牌，直接结束你的回合。"
		Card.Kind.ATTACK:
			return "攻击：下一位必须连抽 2 张（可叠加）。"
		Card.Kind.PEEK:
			return "预知：偷看牌堆顶 3 张，只有你自己看得到。"
		Card.Kind.SHUFFLE:
			return "洗牌：把整个牌池重新打乱。"
		Card.Kind.STEAL:
			return "偷牌：随机抽走指定玩家 1 张手牌。"
		Card.Kind.OVERDRAW:
			return "透支：连续抽牌随时喊停；中途抽到爆弹本轮全弃。每回合限一张。"
		Card.Kind.WISH:
			return "休想：别人打出功能牌时可反制。"
		Card.Kind.DEFUSE:
			return "拆除：抽到爆弹时自动使用。"
	return ""


func _on_hand_card(index: int) -> void:
	if view.is_empty() or String(view.get("phase", "")) != "action" \
			or not bool(view.get("your_turn", false)):
		return
	var hand: Array = view.get("hand", [])
	if index < 0 or index >= hand.size():
		return
	var kind := int(hand[index])
	match kind:
		Card.Kind.SKIP, Card.Kind.ATTACK, Card.Kind.PEEK, Card.Kind.SHUFFLE, Card.Kind.OVERDRAW:
			_selected_pliers.clear()
			net.send({"t": NetProtocol.T_ACT, "a": NetProtocol.A_PLAY, "card": index})
		Card.Kind.STEAL:
			_pending_steal_index = index
			_show_steal_targets(index)
		_:
			if Card.is_plier(kind):
				if _selected_pliers.has(index):
					_selected_pliers.erase(index)
				else:
					_selected_pliers.append(index)
				_render_game()
			elif kind == Card.Kind.WISH:
				_on_log("休想卡只能在别人打出功能牌时打出（响应窗口）")
			elif kind == Card.Kind.DEFUSE:
				_on_log("拆除卡在抽到爆弹时自动使用")


func _show_steal_targets(steal_index: int) -> void:
	_target_row.visible = true
	_action_row.visible = false
	_target_row.add_child(_make_label("偷牌：选择目标 →", 14))
	var players: Array = view.get("players", [])
	for i in players.size():
		var p: Dictionary = players[i]
		if i == my_seat or not bool(p.get("alive", false)):
			continue
		var idx := i
		var btn := Button.new()
		btn.text = "%s（%d 张）" % [p.get("name", "?"), int(p.get("count", 0))]
		btn.custom_minimum_size = Vector2(0, 40)
		_style_button(btn)
		btn.disabled = int(p.get("count", 0)) == 0
		btn.pressed.connect(func() -> void:
			_target_row.visible = false
			_action_row.visible = true
			net.send({"t": NetProtocol.T_ACT, "a": NetProtocol.A_PLAY,
					"card": steal_index, "target": idx}))
		_target_row.add_child(btn)


func _on_log(message: String) -> void:
	_log_label.append_text(message + "\n")


# ---- 特效（与拍桌版一致）----

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

# ---- 动作演出（服务器 T_FX：让偷牌/洗牌/抽牌有看得见的动作）----

func _seat_name(seat: int) -> String:
	var players: Array = view.get("players", [])
	if seat >= 0 and seat < players.size():
		return String((players[seat] as Dictionary).get("name", "玩家"))
	return "玩家"


## 座位的屏幕锚点：自己是手牌区上方，对手是对手头像牌中心。
func _seat_anchor(seat: int) -> Vector2:
	if seat == my_seat:
		return Vector2(640.0, 610.0)
	if _seat_anchors.has(seat):
		return _seat_anchors[seat] as Vector2
	return Vector2(640.0, 120.0)


func _deck_anchor() -> Vector2:
	return _deck_stack.position + Vector2(40.0, 60.0)


func _discard_anchor() -> Vector2:
	return _discard_stack.position + Vector2(40.0, 60.0)


func _center_anchor() -> Vector2:
	return _center_play.position + Vector2(65.0, 90.0)


func _fx_card_name(kind: int) -> String:
	return Card.display_name(kind) if kind >= 0 else "拆弹工具组合"


func _on_fx(msg: Dictionary) -> void:
	var fx_type := String(msg.get("fx", ""))
	var actor := int(msg.get("actor", -1))
	var target := int(msg.get("target", -1))
	var kind := int(msg.get("kind", -1))
	var count := int(msg.get("count", 1))
	var actor_name := _seat_name(actor)
	var target_name := _seat_name(target)
	match fx_type:
		NetProtocol.FX_PLAY:
			_fly_card(_seat_anchor(actor), _center_anchor(), kind, true)
			_show_banner("%s 打出【%s】" % [actor_name, _fx_card_name(kind)],
					CardView.category_color(kind))
		NetProtocol.FX_DRAW:
			# 只有本人知道自己抽到什么，别人只看得到牌背飞过去
			_fly_card(_deck_anchor(), _seat_anchor(actor), kind, actor == my_seat)
			_show_banner("%s 抽了 1 张牌" % actor_name, CardView.COLOR_ACTION)
		NetProtocol.FX_STEAL:
			# 偷牌保密：只有三条索取指定牌时才亮牌名
			_fly_card(_seat_anchor(target), _seat_anchor(actor), kind, kind >= 0)
			_show_banner("%s 从 %s 手上摸走 1 张" % [actor_name, target_name],
					CardView.COLOR_COLLECT)
		NetProtocol.FX_SHUFFLE:
			_shuffle_pile_anim()
			_show_banner("%s 洗牌了！牌堆重新打乱" % actor_name, CardView.COLOR_ACTION)
		NetProtocol.FX_PEEK:
			_peek_anim()
			_show_banner("%s 窥视牌堆顶 3 张（结果只有本人可见）" % actor_name,
					CardView.COLOR_COUNTER)
		NetProtocol.FX_ATTACK:
			_show_banner("%s 发动攻击！下家将多抽 %d 次" % [actor_name, count],
					CardView.COLOR_BOMB)
		NetProtocol.FX_SKIP:
			_show_banner("%s 选择跳过，不抽牌" % actor_name, CardView.COLOR_ACTION)
		NetProtocol.FX_OVERDRAW:
			_show_banner("%s 开始透支连抽！随时可以喊停" % actor_name,
					CardView.COLOR_ACTION)
		NetProtocol.FX_OVERDRAW_STOP:
			_show_banner("%s 喊停，透支区 %d 张入手" % [actor_name, count],
					CardView.COLOR_COLLECT)
		NetProtocol.FX_FLUSH:
			_fly_card(_discard_anchor(), _seat_anchor(actor), kind, true)
			_show_banner("%s 从弃牌堆回收【%s】" % [actor_name, _fx_card_name(kind)],
					CardView.COLOR_COLLECT)
		NetProtocol.FX_DEFUSE:
			_flash_gold()
			_show_banner("%s 使用拆除卡，成功拆弹！" % actor_name, CardView.COLOR_DEFUSE)
		NetProtocol.FX_BOMB_PLACE:
			_show_banner("%s 把爆弹暗置回牌堆（位置只有本人知道）" % actor_name,
					CardView.COLOR_BOMB)
		NetProtocol.FX_WISH:
			_show_banner("%s 打出【休想】，%s 的【%s】被反制！" % [
					actor_name, target_name, _fx_card_name(kind)], CardView.COLOR_COUNTER)


## 一张牌从 from 飞到 to：起飞小、落地放大、随后淡出（表示"这张牌已入手/入堆"）。
func _fly_card(from: Vector2, to: Vector2, kind: int, face_up: bool) -> void:
	var card := CardView.new(kind if kind >= 0 else Card.Kind.SKIP, face_up)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.pivot_offset = CardView.CARD_SIZE / 2.0
	card.scale = Vector2(0.5, 0.5)
	card.position = from - CardView.CARD_SIZE / 2.0
	card.z_index = 20
	_fx_layer.add_child(card)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "position", to - CardView.CARD_SIZE / 2.0, 0.5) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(card, "scale", Vector2(1.05, 1.05), 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "rotation_degrees", randf_range(-16.0, 16.0), 0.25)
	tw.set_parallel(false)
	tw.tween_property(card, "modulate:a", 0.0, 0.25).set_delay(0.12)
	tw.tween_callback(card.queue_free)


## 洗牌：牌堆快速抖动（视觉上"整堆牌被重洗"）。
func _shuffle_pile_anim() -> void:
	var base := _deck_stack.position
	var tw := create_tween()
	for i in 7:
		tw.tween_property(_deck_stack, "position",
				base + Vector2(randf_range(-11.0, 11.0), randf_range(-7.0, 7.0)), 0.05)
		tw.tween_property(_deck_stack, "rotation_degrees", randf_range(-9.0, 9.0), 0.05)
	tw.tween_property(_deck_stack, "position", base, 0.07)
	tw.tween_property(_deck_stack, "rotation_degrees", 0.0, 0.07)


## 预知：牌堆顶三张牌背浮起、停留、收回。
func _peek_anim() -> void:
	for i in 3:
		var mini := CardView.new(Card.Kind.SKIP, false)
		mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mini.pivot_offset = CardView.CARD_SIZE / 2.0
		mini.scale = Vector2(0.55, 0.55)
		mini.position = _deck_anchor() + Vector2(-46.0 + i * 46.0, 34.0) \
				- CardView.CARD_SIZE / 2.0
		mini.modulate.a = 0.0
		mini.z_index = 20
		_fx_layer.add_child(mini)
		var tw := create_tween()
		tw.tween_property(mini, "modulate:a", 1.0, 0.16).set_delay(i * 0.08)
		tw.tween_property(mini, "position:y", mini.position.y - 52.0, 0.32) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.55)
		tw.tween_property(mini, "modulate:a", 0.0, 0.24)
		tw.tween_callback(mini.queue_free)


func _flash_gold() -> void:
	var flash := ColorRect.new()
	flash.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.42, 0.08)
	tw.tween_property(flash, "color:a", 0.0, 0.45)
	tw.tween_callback(flash.queue_free)


## 屏幕中部的动作横幅：谁做了什么，短暂显示后淡出。
func _show_banner(text: String, color: Color) -> void:
	if _banner != null and is_instance_valid(_banner):
		_banner.queue_free()
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 30
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.10, 0.17, 0.94)
	style.set_corner_radius_all(22)
	style.border_color = color
	style.set_border_width_all(2)
	style.shadow_size = 14
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 11
	style.content_margin_bottom = 11
	panel.add_theme_stylebox_override("panel", style)
	var label := _make_label(text, 17, Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 7)
	panel.add_child(label)
	_fx_layer.add_child(panel)
	_banner = panel
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	panel.pivot_offset = panel.size / 2.0
	panel.position = Vector2((1280.0 - panel.size.x) / 2.0, 300.0)
	panel.scale = Vector2(0.68, 0.68)
	var tw := create_tween()
	tw.tween_property(panel, "scale", Vector2.ONE, 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.5)
	tw.tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func() -> void:
		if is_instance_valid(panel):
			panel.queue_free())
