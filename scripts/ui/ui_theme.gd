class_name UiTheme
extends RefCounted
## 全局设计令牌 + 控件工厂。
##
## 项目是代码驱动 UI（没有 .tres 主题），所有颜色/圆角/阴影/字号此前散落在各文件里，
## 同一语义在不同界面用了不同数值（按钮圆角 16/18/20、面板阴影 18/24、hover 有的有有的没有）。
## 这里把「同一语义＝同一数值」固化下来，并提供控件工厂；build() 生成的 Theme 挂到根节点，
## 让没有显式设置样式的控件也有一致的默认值。

# ============================ 光 ============================

## 全场景统一光照方向：光从左上方打过来，所以投影落到右下方。
## 所有阴影（牌、按钮、面板）的偏移都从这里派生，不再各自写 (0, 4)。
const SHADOW_DIR := Vector2(0.45, 0.89)

## 阴影抬升档位：贴地 / 悬浮 / 模态
const LIFT_LOW := 6.0
const LIFT_MID := 12.0
const LIFT_HIGH := 24.0


## 由抬升量算出阴影偏移（方向恒定，只变距离）
static func lift_offset(lift: float) -> Vector2:
	return SHADOW_DIR * lift * 0.35


## 由抬升量算出一个带统一方向的阴影 StyleBox 配置
static func apply_shadow(sb: StyleBoxFlat, lift: float, alpha: float = 0.4) -> void:
	sb.shadow_color = Color(0, 0, 0, alpha)
	sb.shadow_size = int(round(lift))
	sb.shadow_offset = lift_offset(lift)

# ============================ 调色板 ============================

## 牌桌：木框与毛毡
const WOOD := Color("2a170c")
const WOOD_LIGHT := Color("8a6239")
const FELT_TOP := Color("17653f")
const FELT_BOTTOM := Color("0b3d27")
const BRASS := Color("e8c170")
const MENU_TOP := Color("123f2c")
const MENU_BOTTOM := Color("071f16")

## 象牙纸与墨色（面板 / 正文）
const CARD := Color("fff8e7")
const CREAM := Color("fff8e7")
const INK := Color("5d4037")        # 标题
const INK_BODY := Color("4e342e")   # 正文
const INK_MUTED := Color("8d6e63")  # 次要说明

## 强调色
const GOLD := Color("ffd54f")
const GOLD_SOFT := Color("ffe082")
const GREEN := Color("2e7d32")
const GREY := Color("546e7a")
const SLATE := Color("455a64")
const BROWN := Color("6d4c41")
const DANGER := Color("b71c1c")
const ACCENT_RED := Color("d32f2f")
const WARN := Color("f9a825")

## 分数涨跌 / 牌桌浅色文字
const POS := Color("2e7d32")
const NEG := Color("c62828")
const ON_FELT := Color("c8e6c9")
const HU := Color("ff8a80")

## 三门花色（万 / 筒 / 条）
const SUIT := [
	Color("ef5350"),
	Color("42a5f5"),
	Color("66bb6a"),
]

# ============================ 圆角 / 字号 ============================

const R_CHIP := 12
const R_BTN := 18
const R_BTN_LARGE := 20
const R_CARD := 28
const R_PANEL := 30

const FS_TINY := 20
const FS_CAPTION := 22
const FS_BODY := 24
const FS_LABEL := 26
const FS_LEAD := 28
const FS_BTN := 30
const FS_BTN_LARGE := 34
const FS_SUBHEAD := 40
const FS_TITLE := 46
const FS_H1 := 52
const FS_H2 := 60
const FS_BANNER := 72
const FS_DISPLAY := 150
const FS_STAMP := 170

# ============================ HDR 发光 ============================

## 把颜色推到 HDR 范围（>1.0），这样才能被 glow 后处理拾取。
## 没开 HDR 2D 或渲染器不支持时原样返回，避免颜色被钳制成过曝白块。
static func hot(c: Color, energy: float = 2.2) -> Color:
	if not Glow.available():
		return c
	return Color(c.r * energy, c.g * energy, c.b * energy, c.a)

# ============================ 控件工厂 ============================

## 按钮三种状态的底色：常态 / 悬停提亮 / 按下压暗
static func button_color(color: Color, state: String) -> Color:
	match state:
		"hover":
			return color.lightened(0.12)
		"hover_pressed":
			return color.lightened(0.12).darkened(0.2)
		"pressed":
			return color.darkened(0.2)
		_:
			return color


static func button_style(color: Color, state: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = button_color(color, state)
	sb.set_corner_radius_all(R_BTN)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	# 常态抬得高一点，按下时阴影收到贴地——按下感由此而来
	apply_shadow(sb, LIFT_LOW if state == "pressed" or state == "hover_pressed" else LIFT_MID, 0.35)
	return sb


## 全项目统一按钮：底色、圆角、阴影方向、四态一致
static func make_button(text: String, color: Color, min_w: int = 0,
		min_h: int = 80, font_size: int = FS_BTN_LARGE) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", GOLD_SOFT)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(state, button_style(color, state))
	return b


## 纸牌样式面板（结算、暂停、设置、玩法共用）
static func panel_style(bg: Color = CARD, radius: int = R_CARD,
		pad_h: int = 34, pad_v: int = 28) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	apply_shadow(sb, LIFT_HIGH, 0.5)
	# 纸牌内缘一道极淡高光，呼应左上光源
	sb.border_width_top = 2
	sb.border_color = Color(1, 1, 1, 0.35)
	return sb


## 定缺标签
static func chip_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.1)
	sb.set_corner_radius_all(R_CHIP)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sb.border_color = Color(1, 1, 1, 0.5)
	sb.set_border_width_all(2)
	apply_shadow(sb, LIFT_LOW, 0.28)
	return sb

# ============================ 全局 Theme ============================

## 生成挂在根节点上的 Theme：统一字号阶梯与滚动条外观。
## 按钮/面板的样式仍由工厂显式设置（避免波及 CheckButton 这类子类型）。
static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FS_LABEL

	t.set_color("font_color", "Label", INK_BODY)
	t.set_font_size("font_size", "Label", FS_LABEL)

	# 滚动条：结算/玩法面板里的 ScrollContainer 用得上
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.36, 0.25, 0.18, 0.12)
	track.set_corner_radius_all(6)
	track.content_margin_left = 4
	track.content_margin_right = 4
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("scroll_focus", "VScrollBar", track)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(BROWN, 0.45)
	grabber.set_corner_radius_all(6)
	grabber.content_margin_left = 4
	grabber.content_margin_right = 4
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var g := grabber.duplicate() as StyleBoxFlat
		if state == "grabber_highlight":
			g.bg_color = Color(BROWN, 0.62)
		elif state == "grabber_pressed":
			g.bg_color = Color(GREEN, 0.75)
		t.set_stylebox(state, "VScrollBar", g)

	return t
