class_name MenuView
extends Control
## 横屏主菜单：左侧品牌与装饰牌，右侧规则卡片与开始按钮。

signal start_requested(rule_id: String, pace: float)

## 动画节奏固定为最慢档，便于观察其他玩家的出牌过程
const PACE := 0.7

var _sfx: Sfx = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _draw() -> void:
	var steps := 48
	for i in steps:
		var t := float(i) / steps
		draw_rect(Rect2(0, size.y * t, size.x, size.y / steps + 1), Color("123f2c").lerp(Color("071f16"), t))
	draw_rect(Rect2(14, 14, size.x - 28, size.y - 28), Color(0.95, 0.85, 0.6, 0.18), false, 4.0)


func _build() -> void:
	# 左侧：品牌
	var brand := VBoxContainer.new()
	brand.position = Vector2(140, 170)
	brand.add_theme_constant_override("separation", 6)
	add_child(brand)
	var title := Label.new()
	title.text = "单机麻将"
	UiFont.apply_title(title)
	title.add_theme_font_size_override("font_size", 150)
	title.add_theme_color_override("font_color", Color("ffe082"))
	title.add_theme_color_override("font_outline_color", Color(0.3, 0.1, 0, 0.9))
	title.add_theme_constant_override("outline_size", 14)
	brand.add_child(title)
	var sub := Label.new()
	sub.text = "四 川 麻 将 · 血 战 到 底"
	sub.add_theme_font_size_override("font_size", 40)
	sub.add_theme_color_override("font_color", Color("c8e6c9"))
	brand.add_child(sub)

	# 左下：装饰牌（展示花色）
	var deco := HBoxContainer.new()
	deco.position = Vector2(140, 720)
	deco.add_theme_constant_override("separation", 8)
	add_child(deco)
	var sample := [[0, 1], [0, 5], [0, 9], [1, 3], [1, 7], [2, 2], [2, 6], [2, 9]]
	for s in sample:
		var tv := TileView.new()
		tv.custom_minimum_size = Vector2(84, 118)
		tv.size = Vector2(84, 118)
		tv.setup(Tile.new(s[0], s[1]))
		deco.add_child(tv)

	# 右侧：卡片
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(760, 0)
	card.position = Vector2(1000, 220)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("fff8e7")
	sb.set_corner_radius_all(28)
	sb.content_margin_left = 44
	sb.content_margin_right = 44
	sb.content_margin_top = 36
	sb.content_margin_bottom = 36
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 24
	card.add_theme_stylebox_override("panel", sb)
	add_child(card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	card.add_child(v)
	var name_l := Label.new()
	name_l.text = "四川麻将 · 血战到底"
	UiFont.apply_title(name_l)
	name_l.add_theme_font_size_override("font_size", 46)
	name_l.add_theme_color_override("font_color", Color("5d4037"))
	v.add_child(name_l)
	for line in [
		"· 开局每人定缺一门（万 / 筒 / 条）",
		"· 缺门牌打光前不能和牌",
		"· 只能碰、杠、胡，没有吃与立直",
		"· 一人和牌后其余人继续，直到牌摸完",
		"· 杠牌即时收分，流局可能查花猪",
	]:
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 26)
		l.add_theme_color_override("font_color", Color("4e342e"))
		v.add_child(l)

	var listen := _button("试听人声", Color("5d4037"), 360)
	listen.add_theme_font_size_override("font_size", 26)
	listen.custom_minimum_size = Vector2(360, 60)
	listen.pressed.connect(_play_sample)
	v.add_child(listen)

	var start := _button("开始对局", Color("2e7d32"), 360)
	start.add_theme_font_size_override("font_size", 40)
	start.custom_minimum_size = Vector2(360, 96)
	start.pressed.connect(func() -> void: start_requested.emit("sichuan", PACE))
	v.add_child(start)


## 试听：报牌 + 叫牌（用于确认手机的声音输出）
func _play_sample() -> void:
	if _sfx == null:
		_sfx = Sfx.new()
		add_child(_sfx)
	_sfx.speak_tile(0, 2)
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_callback(_sfx.speak_tile.bind(1, 3))
	tw.tween_interval(0.9)
	tw.tween_callback(_sfx.speak_call.bind("peng"))


func _button(text: String, color: Color, min_w: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 64)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color("ffe082"))
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color.lightened(0.12) if state.begins_with("hover") else color
		if state == "pressed":
			sb.bg_color = color.darkened(0.2)
		sb.set_corner_radius_all(18)
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 4)
		b.add_theme_stylebox_override(state, sb)
	return b
