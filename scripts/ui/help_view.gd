class_name HelpView
extends Control
## 玩法说明：通过菜单或暂停面板中的“玩法”打开。

signal closed

const TEXT := Color("5d4037")
const SUB := Color("8d6e63")
const GREEN := Color("2e7d32")

const SECTIONS := [
	["怎么赢", "把 14 张牌凑成 4 组面子（三张相同或同花色顺子）+ 1 对将。四川麻将只有万、筒、条三门，共 108 张，没有吃，只能碰、杠、胡。"],
	["定缺", "开局每人指定一门缺门。手里还有缺门牌时不能和牌，出牌时也只能先打缺门牌，打光之后才能打别的花色。"],
	["番数与算分", "平胡 1 番、碰碰胡 2 番、七对 2 番、清一色 +2 番、自摸 +1 番、每有一根 +1 番。分数 = 2 的番数次方；自摸由其余三家各付，点炮只由放炮的人付。"],
	["血战到底", "有人和牌后，其余人继续打，直到只剩一人没和或牌墙摸完。杠牌当场收分：明杠由放杠者付 2 分，补杠每家 1 分，暗杠每家 2 分。"],
	["怎么出牌", "轮到你时，点一下牌选中（会抬起并描金），再点一下打出；不能打的牌会变暗。桌面端可以用 ←/→ 选牌、回车或空格打出。"],
	["听牌提示", "手牌右下角会显示“打 三万 → 听 二万、五万（剩 5 张）”，听到的牌会按四家已经打出的牌扣除剩余张数。"],
	["暂停与设置", "点右上角“菜单”或按 Esc 打开暂停面板：继续、玩法、设置、重新开始、返回菜单。设置里可以调出牌节奏、音效/人声音量和震动。"],
]

var _panel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.load_settings()
	_build()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.62)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(900, 760)
	_panel.add_theme_stylebox_override("panel", _panel_style())
	_panel.resized.connect(_center)
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	_panel.add_child(outer)

	var title := Label.new()
	title.text = "玩法说明"
	UiFont.apply_title(title)
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", TEXT)
	outer.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(800, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for item in SECTIONS:
		var head := Label.new()
		head.text = "· " + String(item[0])
		head.add_theme_font_size_override("font_size", 28)
		head.add_theme_color_override("font_color", Color("2e7d32"))
		list.add_child(head)
		var body := Label.new()
		body.text = String(item[1])
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(780, 0)
		body.add_theme_font_size_override("font_size", 24)
		body.add_theme_color_override("font_color", SUB)
		list.add_child(body)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 20)
	outer.add_child(footer)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var done := Button.new()
	done.text = "知道了"
	done.custom_minimum_size = Vector2(220, 66)
	done.add_theme_font_size_override("font_size", 30)
	done.add_theme_color_override("font_color", Color.WHITE)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = GREEN.darkened(0.15) if state == "pressed" else GREEN
		sb.set_corner_radius_all(16)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		done.add_theme_stylebox_override(state, sb)
	done.pressed.connect(close)
	footer.add_child(done)

	_center.call_deferred()


func close() -> void:
	Settings.save_settings()
	closed.emit()
	queue_free()


func _center() -> void:
	_panel.position = (size - _panel.size) * 0.5


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("fff8e7")
	sb.set_corner_radius_all(28)
	sb.content_margin_left = 48
	sb.content_margin_right = 48
	sb.content_margin_top = 32
	sb.content_margin_bottom = 32
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 24
	return sb
