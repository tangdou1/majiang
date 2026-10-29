class_name Vfx
extends RefCounted
## 额外的视觉特效库：圆形光点粒子、选牌火花、叫牌放射光线、胡牌彩纸、牌桌漂浮光点。
## 所有节点都是一次性的，播放结束后自动释放。

static var _dot: GradientTexture2D = null


## 圆形柔光贴图（粒子用），只生成一次
static func dot() -> GradientTexture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		_dot.width = 64
		_dot.height = 64
	return _dot


static func _fade_ramp(color: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	return g


## 选牌火花：牌被抬起时向四周散开的小光点
static func sparkle(parent: Node, pos: Vector2, color: Color, amount: int = 18) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.texture = dot()
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = amount
	p.lifetime = 0.7
	p.spread = 180.0
	p.initial_velocity_min = 110.0
	p.initial_velocity_max = 260.0
	p.gravity = Vector2(0, 340)
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.3
	p.color_ramp = _fade_ramp(color)
	p.emitting = true
	parent.add_child(p)
	Fx.get_tree_safe_free(p, 1.2, parent)


## 叫牌放射光线：一圈旋转渐隐的光芒
static func rays(parent: Node, pos: Vector2, color: Color, radius: float) -> void:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = Vector2(radius * 2.0, radius * 2.0)
	c.position = pos - c.size * 0.5
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(0.2, 0.2)
	c.draw.connect(func() -> void:
		var ctr := c.size * 0.5
		var n := 16
		for i in n:
			var a := TAU * float(i) / n
			var a2 := a + TAU / (n * 2.0) * 0.5
			var col := Color(color.r, color.g, color.b, 0.26)
			c.draw_colored_polygon(PackedVector2Array([ctr, ctr + Vector2.from_angle(a) * radius, ctr + Vector2.from_angle(a2) * radius]), col)
		c.draw_circle(ctr, radius * 0.22, Color(1, 1, 1, 0.35)))
	parent.add_child(c)
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "rotation", 0.7, 1.1)
	tw.tween_property(c, "modulate:a", 0.0, 1.1)
	tw.chain().tween_callback(c.queue_free)


## 胡牌彩纸：从屏幕顶部落下的多色纸片
static func confetti(parent: Node, width: float) -> void:
	var colors := [Color("ffd54f"), Color("ef5350"), Color("42a5f5"), Color("66bb6a"), Color("ffffff")]
	for col: Color in colors:
		var p := CPUParticles2D.new()
		p.position = Vector2(width * 0.5, -30.0)
		p.amount = 36
		p.lifetime = 4.2
		p.one_shot = true
		p.explosiveness = 0.0
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(width * 0.5, 10.0)
		p.direction = Vector2(0, 1)
		p.spread = 30.0
		p.initial_velocity_min = 140.0
		p.initial_velocity_max = 300.0
		p.gravity = Vector2(0, 160)
		p.angular_velocity_min = -540.0
		p.angular_velocity_max = 540.0
		p.damping_min = 0.5
		p.damping_max = 1.4
		p.scale_amount_min = 6.0
		p.scale_amount_max = 11.0
		p.color = col
		p.emitting = true
		parent.add_child(p)
		Fx.get_tree_safe_free(p, 5.0, parent)


## 牌桌漂浮光点：常驻、缓慢上升，给桌面增加氛围（需要自行设置 position 与 emission_rect_extents）
static func ambient() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = dot()
	p.amount = 42
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(0, -1)
	p.spread = 14.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 22.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.22
	p.color = Color(1.0, 0.92, 0.65, 0.32)
	p.z_index = -1
	p.emitting = true
	return p
