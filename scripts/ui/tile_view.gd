class_name TileView
extends Control
## 自绘麻将牌：象牙白底、立体边、双线内框；万/筒/条按传统样式绘制；背面为菱形纹；支持发光描边。

signal tapped(view: TileView)

const IVORY := Color("fbf7ec")
const IVORY_EDGE := Color("b89f6a")
const RED := Color("c62828")
const INK := Color("1c1c1c")
const BACK := Color("23694a")
const BACK_EDGE := Color("123d2a")
const BACK_INNER := Color("3a8f68")

# 筒：深蓝 / 象牙 / 红 同心环
const DOT_BLUE := Color("1d4f9a")
const DOT_RED := Color("c8322b")
const DOT_TEAL := Color("1f8a7a")
# 条：竹绿
const BAMBOO := Color("2f9a5c")
const BAMBOO_DARK := Color("12472c")
const BAMBOO_LIGHT := Color("9be3b3")
const LEAF := Color("3fae6b")

const COLS := [0.3, 0.5, 0.7]
const ROWS := [0.22, 0.5, 0.78]
const DOT_LAYOUT := {
	1: [4], 2: [1, 7], 3: [0, 4, 8], 4: [0, 2, 6, 8], 5: [0, 2, 4, 6, 8],
	6: [0, 2, 3, 5, 6, 8], 7: [0, 2, 3, 4, 5, 6, 8], 8: [0, 1, 2, 3, 5, 6, 7, 8], 9: [0, 1, 2, 3, 4, 5, 6, 7, 8],
}

var tile: Tile = null
var face_down: bool = false
var glow: Color = Color(0, 0, 0, 0)   ## 发光颜色（alpha 为 0 时不显示）


func setup(p_tile: Tile, p_face_down: bool = false) -> TileView:
	tile = p_tile
	face_down = p_face_down
	queue_redraw()
	return self


func set_glow(c: Color) -> void:
	if glow != c:
		glow = c
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit(self)
		accept_event()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 2.0 or h < 2.0:
		return
	var rect := Rect2(Vector2.ZERO, size)
	if glow.a > 0.01:
		var g := StyleBoxFlat.new()
		g.bg_color = Color(glow.r, glow.g, glow.b, glow.a * 0.35)
		g.set_corner_radius_all(int(w * 0.2))
		var pad := w * 0.12
		draw_style_box(g, Rect2(-pad, -pad, w + pad * 2, h + pad * 2))

	var sb := StyleBoxFlat.new()
	sb.bg_color = BACK if face_down else IVORY
	sb.border_color = BACK_EDGE if face_down else IVORY_EDGE
	sb.set_border_width_all(maxi(1, int(w * 0.03)))
	sb.border_width_bottom = int(w * 0.1)
	sb.set_corner_radius_all(int(w * 0.12))
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = int(w * 0.12)
	sb.shadow_offset = Vector2(0, w * 0.05)
	draw_style_box(sb, rect)

	if face_down:
		_draw_back(w, h)
		return
	if tile == null:
		return
	# 双线内框（传统牌面的边框）
	var inset := w * 0.07
	draw_rect(Rect2(inset, inset, w - inset * 2, h - w * 0.1 - inset * 2), Color(0.55, 0.45, 0.25, 0.25), false, maxf(1.0, w * 0.015))
	match tile.suit:
		0:
			_draw_character(w, h)
		1:
			_draw_circles(w, h)
		_:
			_draw_bamboo(w, h)


func _draw_back(w: float, h: float) -> void:
	var inner := StyleBoxFlat.new()
	inner.bg_color = BACK_INNER
	inner.set_corner_radius_all(int(w * 0.08))
	draw_style_box(inner, Rect2(w * 0.12, h * 0.08, w * 0.76, h * 0.8))
	# 菱形花纹
	var c := Color(1, 1, 1, 0.22)
	var cx := w * 0.5
	var cy := h * 0.47
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, cy - h * 0.2), Vector2(cx + w * 0.22, cy),
		Vector2(cx, cy + h * 0.2), Vector2(cx - w * 0.22, cy)]), c)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, cy - h * 0.1), Vector2(cx + w * 0.1, cy),
		Vector2(cx, cy + h * 0.1), Vector2(cx - w * 0.1, cy)]), Color(1, 0.9, 0.5, 0.35))


func _text(s: String, cx: float, baseline: float, fs: int, col: Color, width: float) -> void:
	var font := get_theme_default_font()
	draw_string(font, Vector2(cx - width * 0.5, baseline), s, HORIZONTAL_ALIGNMENT_CENTER, width, fs, col)


# ---------------- 万 ----------------
func _draw_character(w: float, h: float) -> void:
	_text(Tile.NUMBER_NAMES[tile.rank - 1], w * 0.5, h * 0.52, int(h * 0.36), INK, w)
	_text("万", w * 0.5, h * 0.9, int(h * 0.24), RED, w)


# ---------------- 筒 ----------------
func _draw_circles(w: float, h: float) -> void:
	if tile.rank == 1:
		_ring_dot(Vector2(w * 0.5, h * 0.5), minf(w, h) * 0.33)
		return
	var r := minf(w * 0.15, h * 0.098)
	if tile.rank >= 7:
		r = minf(w * 0.13, h * 0.085)
	for i in DOT_LAYOUT[tile.rank]:
		var p := Vector2(COLS[i % 3] * w, ROWS[i / 3] * h)
		_ring_dot(p, r)


## 传统筒子：蓝色外环、象牙白环、红色内环，中心蓝点，并带一点高光
func _ring_dot(p: Vector2, r: float) -> void:
	draw_circle(p, r, DOT_BLUE)
	draw_circle(p, r * 0.84, IVORY)
	draw_circle(p, r * 0.68, DOT_TEAL)
	draw_circle(p, r * 0.52, IVORY)
	draw_circle(p, r * 0.38, DOT_RED)
	draw_circle(p, r * 0.2, IVORY)
	draw_circle(p, r * 0.1, DOT_BLUE)
	draw_arc(p, r * 0.92, PI * 1.05, PI * 1.45, 12, Color(1, 1, 1, 0.55), maxf(1.0, r * 0.1), true)


# ---------------- 条 ----------------
const JADE := Color("2c9462")
const JADE_DEEP := Color("135236")
const JADE_HI := Color("bff0cf")
const BIRD_RED := Color("d23b2f")
const BIRD_GOLD := Color("f2b632")


func _draw_bamboo(w: float, h: float) -> void:
	if tile.rank == 1:
		_sparrow(w, h)
		return
	var idx: Array = DOT_LAYOUT[tile.rank]
	var sw := w * 0.11
	var sh := h * 0.21
	if tile.rank >= 7:
		sh = h * 0.17
		sw = w * 0.095
	for i in idx:
		var cx: float = COLS[i % 3] * w
		var cy: float = ROWS[i / 3] * h
		_stick(Vector2(cx, cy), sw, sh)


## 单根翡翠竹条：圆角竹身、三道竹节、左侧高光（不画竹叶）
func _stick(c: Vector2, sw: float, sh: float) -> void:
	var top := c.y - sh * 0.5
	var rect := Rect2(c.x - sw * 0.5, top, sw, sh)
	var sb := StyleBoxFlat.new()
	sb.bg_color = JADE
	sb.border_color = JADE_DEEP
	sb.set_border_width_all(maxi(1, int(sw * 0.1)))
	sb.set_corner_radius_all(int(sw * 0.5))
	draw_style_box(sb, rect)
	for j in 3:
		var y := top + sh * (0.22 + 0.27 * j)
		var band := Rect2(rect.position.x - sw * 0.04, y - sh * 0.025, sw * 1.08, sh * 0.05)
		draw_rect(band, JADE_DEEP)
	draw_line(Vector2(c.x - sw * 0.2, top + sh * 0.08), Vector2(c.x - sw * 0.2, top + sh * 0.92), Color(JADE_HI, 0.7), maxf(1.0, sw * 0.12))


## 一条：小麻雀（翡翠绿身体、红冠、金色腹部、尾羽与小枝）
func _sparrow(w: float, h: float) -> void:
	var s := minf(w, h)
	var c := Vector2(w * 0.5, h * 0.5)
	# 小枝
	draw_line(c + Vector2(-s * 0.42, s * 0.2), c + Vector2(s * 0.36, s * 0.14), Color("7a4a24"), maxf(2.0, s * 0.03))
	draw_line(c + Vector2(0.2 * s, s * 0.16), c + Vector2(0.28 * s, s * 0.3), Color("7a4a24"), maxf(1.5, s * 0.02))
	# 尾羽（三根）
	for a in [-0.35, 0.0, 0.3]:
		var base := c + Vector2(-s * 0.22, s * 0.02)
		var tip := base + Vector2(-s * 0.24, s * (0.1 + a * 0.5))
		var n := Vector2(-(tip - base).y, (tip - base).x).normalized() * s * 0.035
		draw_colored_polygon(PackedVector2Array([base + n, tip, base - n]), LEAF.darkened(0.15))
	# 身体（椭圆）
	var body := PackedVector2Array()
	for k in 32:
		var t := TAU * float(k) / 32.0
		body.append(c + Vector2(cos(t) * s * 0.26, sin(t) * s * 0.17).rotated(-0.25))
	draw_colored_polygon(body, JADE)
	draw_polyline(body + PackedVector2Array([body[0]]), JADE_DEEP, maxf(1.5, s * 0.015), true)
	# 腹部金色羽
	var belly := PackedVector2Array()
	for k in 24:
		var t := TAU * float(k) / 24.0
		belly.append(c + Vector2(0.02 * s, 0.07 * s) + Vector2(cos(t) * s * 0.15, sin(t) * s * 0.08).rotated(-0.25))
	draw_colored_polygon(belly, BIRD_GOLD)
	# 翅膀
	var wing := PackedVector2Array([
		c + Vector2(-0.12 * s, -0.02 * s), c + Vector2(0.08 * s, -0.12 * s),
		c + Vector2(0.14 * s, -0.02 * s), c + Vector2(-0.02 * s, 0.07 * s)])
	draw_colored_polygon(wing, JADE_DEEP)
	draw_polyline(PackedVector2Array([wing[0], wing[2]]), JADE_HI, maxf(1.0, s * 0.012))
	# 头、红冠、喙、眼
	var head := c + Vector2(0.23 * s, -0.12 * s)
	draw_circle(head, s * 0.1, JADE)
	draw_arc(head, s * 0.1, 0, TAU, 24, JADE_DEEP, maxf(1.0, s * 0.012), true)
	draw_circle(head + Vector2(-0.02 * s, -0.09 * s), s * 0.045, BIRD_RED)
	draw_colored_polygon(PackedVector2Array([
		head + Vector2(0.09 * s, -0.02 * s), head + Vector2(0.19 * s, 0.01 * s), head + Vector2(0.09 * s, 0.035 * s)]), BIRD_GOLD)
	draw_circle(head + Vector2(0.04 * s, -0.02 * s), s * 0.03, Color.WHITE)
	draw_circle(head + Vector2(0.045 * s, -0.02 * s), s * 0.016, Color("1a1a1a"))
	# 脚
	draw_line(c + Vector2(0.02 * s, 0.14 * s), c + Vector2(0.0, 0.22 * s), BIRD_RED, maxf(1.0, s * 0.015))
	draw_line(c + Vector2(0.08 * s, 0.13 * s), c + Vector2(0.1 * s, 0.22 * s), BIRD_RED, maxf(1.0, s * 0.015))
