class_name SettingsView
extends Control
## 设置面板：出牌节奏、音效音量、人声音量、静音、震动。
## 改动立即生效并写入 user://settings.cfg；面板本身由调用方添加/释放。

signal closed

const TEXT := Color("5d4037")
const SUB := Color("8d6e63")
const GREEN := Color("2e7d32")
const GREY := Color("546e7a")

var _pace_buttons: Array[Button] = []
var _sfx_value: Label
var _voice_value: Label
var _music_value: Label
var _panel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.load_settings()
	_build()
	resized.connect(_center)


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.58)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(720, 0)
	_panel.add_theme_stylebox_override("panel", _panel_style())
	_panel.resized.connect(_center)
	add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	_panel.add_child(v)

	var title := Label.new()
	title.text = "设置"
	UiFont.apply_title(title)
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", TEXT)
	v.add_child(title)

	# ---- 节奏 ----
	v.add_child(_section("出牌节奏"))
	var pace_row := HBoxContainer.new()
	pace_row.add_theme_constant_override("separation", 10)
	v.add_child(pace_row)
	for i in Settings.PACE_NAMES.size():
		var b := _button(Settings.PACE_NAMES[i], 150, 62)
		b.pressed.connect(_on_pace_selected.bind(i))
		pace_row.add_child(b)
		_pace_buttons.append(b)
	_refresh_pace_buttons()

	# ---- 音量 ----
	v.add_child(_section("音效音量"))
	var sfx_row := HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation", 16)
	v.add_child(sfx_row)
	var sfx_slider := _slider(Settings.sfx_volume)
	sfx_slider.value_changed.connect(_on_sfx_volume.bind(sfx_slider))
	sfx_row.add_child(sfx_slider)
	_sfx_value = _value_label()
	sfx_row.add_child(_sfx_value)

	v.add_child(_section("人声音量"))
	var voice_row := HBoxContainer.new()
	voice_row.add_theme_constant_override("separation", 16)
	v.add_child(voice_row)
	var voice_slider := _slider(Settings.voice_volume)
	voice_slider.value_changed.connect(_on_voice_volume.bind(voice_slider))
	voice_row.add_child(voice_slider)
	_voice_value = _value_label()
	voice_row.add_child(_voice_value)
	_refresh_value_labels()

	# ---- 开关 ----
	var mute := CheckButton.new()
	mute.text = "静音（音效与人声全部关闭）"
	mute.button_pressed = Settings.muted
	mute.add_theme_font_size_override("font_size", 28)
	mute.add_theme_color_override("font_color", TEXT)
	mute.toggled.connect(_on_mute)
	v.add_child(mute)

	var vib := CheckButton.new()
	vib.text = "出牌/和牌时震动（手机）"
	vib.button_pressed = Settings.vibrate
	vib.add_theme_font_size_override("font_size", 28)
	vib.add_theme_color_override("font_color", TEXT)
	vib.toggled.connect(_on_vibrate)
	v.add_child(vib)

	var done := _button("完成", 240, 72)
	done.add_theme_font_size_override("font_size", 32)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.pressed.connect(close)
	v.add_child(done)


func close() -> void:
	closed.emit()
	queue_free()


func _center() -> void:
	_panel.position = (size - _panel.size) * 0.5


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", SUB)
	return l


func _value_label() -> Label:
	var l := Label.new()
	l.custom_minimum_size = Vector2(90, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", TEXT)
	return l


func _slider(value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(420, 40)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return s


func _on_pace_selected(index: int) -> void:
	Settings.pace_index = index
	Settings.save_settings()
	_refresh_pace_buttons()


func _refresh_pace_buttons() -> void:
	for i in _pace_buttons.size():
		var b := _pace_buttons[i]
		var selected := i == Settings.pace_index
		b.add_theme_stylebox_override("normal", _button_style(GREEN if selected else GREY))
		b.add_theme_stylebox_override("hover", _button_style((GREEN if selected else GREY).lightened(0.12)))
		b.add_theme_stylebox_override("pressed", _button_style((GREEN if selected else GREY).darkened(0.15)))
		b.add_theme_stylebox_override("focus", _button_style(GREEN if selected else GREY))


func _on_sfx_volume(value: float, _slider: HSlider) -> void:
	Settings.sfx_volume = value
	Settings.save_settings()
	_refresh_value_labels()


func _on_voice_volume(value: float, _slider: HSlider) -> void:
	Settings.voice_volume = value
	Settings.save_settings()
	_refresh_value_labels()


func _refresh_value_labels() -> void:
	if _sfx_value != null:
		_sfx_value.text = "%d%%" % roundi(Settings.sfx_volume * 100.0)
	if _voice_value != null:
		_voice_value.text = "%d%%" % roundi(Settings.voice_volume * 100.0)
	if _music_value != null:
		_music_value.text = "%d%%" % roundi(Settings.music_volume * 100.0)


func _on_music_volume(value: float, _slider: HSlider) -> void:
	Settings.music_volume = value
	Settings.save_settings()
	_refresh_value_labels()


func _on_mute(on: bool) -> void:
	Settings.muted = on
	Settings.save_settings()


func _on_vibrate(on: bool) -> void:
	Settings.vibrate = on
	Settings.save_settings()


func _button(text: String, min_w: int, min_h: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", Color.WHITE)
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, _button_style(GREY))
	return b


func _button_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 3)
	return sb


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("fff8e7")
	sb.set_corner_radius_all(28)
	sb.content_margin_left = 48
	sb.content_margin_right = 48
	sb.content_margin_top = 36
	sb.content_margin_bottom = 36
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 24
	return sb
