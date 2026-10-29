# @trace UI-001, MECH-013
## 程序化卡牌视觉组件（占位美术·拍桌版）。
## 白卡面 + 投影 + 双层描边 + 类别色条 + 大牌名 + 占位插画（大号首字）+ 悬停抬升 + 选中高亮。
## 设计师出图后：替换占位插画区为 TextureRect 贴图即可，其余结构不变。
## 明度阶梯对齐策划案：卡面 #F2EFE9 → 高亮 #E8B04B，深色桌面上的浅色卡。
class_name CardView
extends Control

const COLOR_FACE := Color("F2EFE9")        # 卡面
const COLOR_FACE_BACK := Color("24384A")   # 牌背
const COLOR_EDGE := Color("B9B2A4")        # 卡面外描边
const COLOR_EDGE_DARK := Color("6B6558")   # 外框深描边
const COLOR_TEXT := Color("2B2B2B")        # 卡面文字
const COLOR_HIGHLIGHT := Color("E8B04B")   # 高亮金

# 类别色（v0.9：四类视觉分组）
const COLOR_ACTION := Color("4A90D9")      # 行动牌·蓝
const COLOR_COUNTER := Color("9B59B6")     # 反制牌·紫
const COLOR_COLLECT := Color("2ECC71")     # 收集牌·绿
const COLOR_BOMB := Color("E74C3C")        # 爆弹·红
const COLOR_DEFUSE := Color("E8B04B")      # 拆除·金

const CARD_SIZE := Vector2(112, 168)

var kind: int = Card.Kind.SKIP
var face_up := true
var selected := false
var _hovering := false

var _panel: Panel
var _back_panel: Panel
var _name_label: Label
var _art_label: Label
var _cat_label: Label


func _init(p_kind: int = Card.Kind.SKIP, p_face_up := true) -> void:
	kind = p_kind
	face_up = p_face_up
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	pivot_offset = CARD_SIZE / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	_build()


static func category_color(p_kind: int) -> Color:
	if Card.is_plier(p_kind):
		return COLOR_COLLECT
	match p_kind:
		Card.Kind.WISH:
			return COLOR_COUNTER
		Card.Kind.BOMB:
			return COLOR_BOMB
		Card.Kind.DEFUSE:
			return COLOR_DEFUSE
		_:
			return COLOR_ACTION


static func category_name(p_kind: int) -> String:
	if Card.is_plier(p_kind):
		return "收集"
	match p_kind:
		Card.Kind.WISH:
			return "反制"
		Card.Kind.BOMB, Card.Kind.DEFUSE:
			return "特殊"
		_:
			return "行动"


## 迷你牌背（对手手牌扇形用），18×26 深蓝金边小卡
static func make_mini_back() -> Panel:
	var mini := Panel.new()
	mini.custom_minimum_size = Vector2(18, 26)
	mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_FACE_BACK
	style.set_corner_radius_all(3)
	style.border_color = Color(COLOR_HIGHLIGHT, 0.55)
	style.set_border_width_all(1)
	style.shadow_size = 2
	style.shadow_color = Color(0, 0, 0, 0.3)
	mini.add_theme_stylebox_override("panel", style)
	return mini


func set_kind(p_kind: int) -> void:
	kind = p_kind
	if _panel != null:
		_restyle()


func set_selected(p_selected: bool) -> void:
	selected = p_selected
	if _panel != null:
		_apply_selection()


func _face_style() -> StyleBoxFlat:
	var face_style := StyleBoxFlat.new()
	face_style.bg_color = COLOR_FACE
	face_style.set_corner_radius_all(11)
	face_style.border_color = COLOR_EDGE_DARK
	face_style.set_border_width_all(2)
	# 卡牌投影：拍桌游戏的悬浮感
	face_style.shadow_size = 10
	face_style.shadow_color = Color(0, 0, 0, 0.4)
	face_style.shadow_offset = Vector2(0, 4)
	return face_style


func _build() -> void:
	# ---- 牌背 ----
	_back_panel = Panel.new()
	_back_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_back_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不吞点击，事件穿透到本控件
	var back_style := StyleBoxFlat.new()
	back_style.bg_color = COLOR_FACE_BACK
	back_style.set_corner_radius_all(11)
	back_style.border_color = COLOR_HIGHLIGHT
	back_style.set_border_width_all(2)
	back_style.shadow_size = 10
	back_style.shadow_color = Color(0, 0, 0, 0.4)
	back_style.shadow_offset = Vector2(0, 4)
	_back_panel.add_theme_stylebox_override("panel", back_style)
	add_child(_back_panel)

	# 牌背内框（双线装饰）
	var back_inner := Panel.new()
	back_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back_inner.position = Vector2(6, 6)
	back_inner.size = CARD_SIZE - Vector2(12, 12)
	var inner_style := StyleBoxFlat.new()
	inner_style.bg_color = Color(0, 0, 0, 0)
	inner_style.border_color = Color(COLOR_HIGHLIGHT, 0.4)
	inner_style.set_border_width_all(1)
	inner_style.set_corner_radius_all(7)
	back_inner.add_theme_stylebox_override("panel", inner_style)
	_back_panel.add_child(back_inner)

	var back_mark := Label.new()
	back_mark.text = "危"
	back_mark.add_theme_font_size_override("font_size", 44)
	back_mark.add_theme_color_override("font_color", Color(1, 1, 1, 0.22))
	back_mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	back_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_back_panel.add_child(back_mark)

	var back_title := Label.new()
	back_title.text = "别炸我！"
	back_title.add_theme_font_size_override("font_size", 12)
	back_title.add_theme_color_override("font_color", Color(COLOR_HIGHLIGHT, 0.7))
	back_title.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	back_title.position.y -= 28
	back_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_back_panel.add_child(back_title)

	# ---- 卡面 ----
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不吞点击
	_panel.add_theme_stylebox_override("panel", _face_style())
	add_child(_panel)

	# 顶部类别色条
	var band := Panel.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.position = Vector2(4, 4)
	band.size = Vector2(CARD_SIZE.x - 8, 24)
	var band_style := StyleBoxFlat.new()
	band_style.bg_color = category_color(kind)
	band_style.set_corner_radius_all(8)
	band.add_theme_stylebox_override("panel", band_style)
	_panel.add_child(band)

	var band_label := Label.new()
	band_label.text = category_name(kind)
	band_label.add_theme_font_size_override("font_size", 12)
	band_label.add_theme_color_override("font_color", Color.WHITE)
	band_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	band_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	band_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	band.add_child(band_label)

	# 牌名
	_name_label = Label.new()
	_name_label.text = Card.display_name(kind)
	_name_label.add_theme_font_size_override("font_size", 19)
	_name_label.add_theme_color_override("font_color", COLOR_TEXT)
	_name_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_name_label.position.y = 32
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_name_label)

	# 占位插画区（设计师出图后替换为贴图）
	var art := Panel.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = Vector2(12, 62)
	art.size = Vector2(CARD_SIZE.x - 24, 78)
	var art_style := StyleBoxFlat.new()
	var art_color := category_color(kind)
	art_style.bg_color = Color(art_color.r, art_color.g, art_color.b, 0.16)
	art_style.set_corner_radius_all(8)
	art_style.border_color = Color(art_color.r, art_color.g, art_color.b, 0.4)
	art_style.set_border_width_all(1)
	art.add_theme_stylebox_override("panel", art_style)
	_panel.add_child(art)

	_art_label = Label.new()
	_art_label.text = Card.display_name(kind).left(1)
	_art_label.add_theme_font_size_override("font_size", 44)
	_art_label.add_theme_color_override("font_color", art_color)
	_art_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_art_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	art.add_child(_art_label)

	# 底部小字
	_cat_label = Label.new()
	_cat_label.text = _footer_text()
	_cat_label.add_theme_font_size_override("font_size", 10)
	_cat_label.add_theme_color_override("font_color", Color(COLOR_TEXT, 0.55))
	_cat_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_cat_label.position.y -= 22
	_cat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_cat_label)

	mouse_entered.connect(func() -> void: _apply_hover(true))
	mouse_exited.connect(func() -> void: _apply_hover(false))

	# 正面/背面互斥显示（牌堆等 face_up=false 的场合只露牌背）
	_panel.visible = face_up
	_back_panel.visible = not face_up


func _footer_text() -> String:
	if Card.is_plier(kind):
		return "单张无效果"
	match kind:
		Card.Kind.BOMB:
			return "抽到即爆！"
		Card.Kind.DEFUSE:
			return "保命牌"
		Card.Kind.WISH:
			return "可反制"
		_:
			return ""


func _restyle() -> void:
	_name_label.text = Card.display_name(kind)
	_art_label.text = Card.display_name(kind).left(1)
	_cat_label.text = _footer_text()
	var band: Panel = _panel.get_child(0)
	var band_style: StyleBoxFlat = band.get_theme_stylebox("panel").duplicate()
	band_style.bg_color = category_color(kind)
	band.add_theme_stylebox_override("panel", band_style)
	var band_label: Label = band.get_child(0)
	band_label.text = category_name(kind)
	var art: Panel = _panel.get_child(2)
	var art_style: StyleBoxFlat = art.get_theme_stylebox("panel").duplicate()
	var c := category_color(kind)
	art_style.bg_color = Color(c.r, c.g, c.b, 0.16)
	art_style.border_color = Color(c.r, c.g, c.b, 0.4)
	art.add_theme_stylebox_override("panel", art_style)


func _apply_selection() -> void:
	var style := _face_style()
	if selected:
		style.border_color = COLOR_HIGHLIGHT
		style.set_border_width_all(3)
	_panel.add_theme_stylebox_override("panel", style)


func _apply_hover(hovering: bool) -> void:
	_hovering = hovering
	if not face_up:
		return  # 牌背（牌堆）不缩放不抬高
	var target := 1.22 if hovering else 1.0
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE * target, 0.09)
	# 手牌多时会互相重叠：悬停的牌必须浮到最上层才看得清全貌
	z_index = 64 if hovering else 0
