class_name SettingsView
extends Control
## 设置面板：出牌节奏、音效音量、人声音量、静音、轻动效。
## 改动立即生效并写入 user://settings.cfg；面板本身由调用方添加/释放。

signal closed
signal effects_changed

const TEXT := UiTheme.INK
const SUB := UiTheme.INK_MUTED
const GREEN := UiTheme.GREEN
const GREY := UiTheme.GREY

var _pace_buttons: Array[Button] = []
var _sfx_value: Label
var _voice_value: Label
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
	_set_check_text_color(mute)
	mute.toggled.connect(_on_mute)
	v.add_child(mute)

	var light_effects := CheckButton.new()
	light_effects.name = "ReducedMotionToggle"
	light_effects.text = "轻动效"
	light_effects.custom_minimum_size.y = 56
	light_effects.button_pressed = Settings.reduced_motion
	light_effects.add_theme_font_size_override("font_size", 28)
	_set_check_text_color(light_effects)
	light_effects.toggled.connect(_on_reduced_motion)
	v.add_child(light_effects)
	var effects_tip := _section("关闭震屏与全屏闪光，减少粒子；保留出牌与叫牌提示。")
	effects_tip.add_theme_font_size_override("font_size", 22)
	v.add_child(effects_tip)

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
		var base := GREEN if i == Settings.pace_index else GREY
		for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			b.add_theme_stylebox_override(state, UiTheme.button_style(base, state))


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


func _on_mute(on: bool) -> void:
	Settings.muted = on
	Settings.save_settings()


func _on_reduced_motion(on: bool) -> void:
	Settings.reduced_motion = on
	Settings.save_settings()
	effects_changed.emit()


## CheckButton 在按下、悬停等状态会使用不同的主题文字颜色。
func _set_check_text_color(button: CheckButton) -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, TEXT)


func _button(text: String, min_w: int, min_h: int) -> Button:
	return UiTheme.make_button(text, GREY, min_w, min_h, UiTheme.FS_LEAD)


func _panel_style() -> StyleBoxFlat:
	return UiTheme.panel_style(UiTheme.CARD, UiTheme.R_CARD, 48, 36)
