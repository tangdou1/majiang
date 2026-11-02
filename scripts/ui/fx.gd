class_name Fx
extends Control
## 视觉特效：冲击波圆环、粒子爆发。一次性节点，播放完自动销毁。

var radius: float = 10.0
var ring_color: Color = Color.WHITE
var line_width: float = 6.0


func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, ring_color, line_width, true)


## 在 parent 的 pos 处播放冲击波 + 粒子爆发
static func burst(parent: Node, pos: Vector2, color: Color, strength: float = 1.0) -> void:
	var ring := Fx.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.position = pos
	# HDR：让冲击波参与 bloom
	var hot := UiTheme.hot(color, 1.8)
	ring.ring_color = Color(hot.r, hot.g, hot.b, 0.9)
	ring.line_width = 6.0 * strength
	# 俯视桌面：光圈压在桌面上，应是压扁的椭圆而不是正圆
	ring.scale = Vector2(1.0, 0.42)
	parent.add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "radius", 90.0 * strength, 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(ring.queue_free)

	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = int(22 * strength)
	p.lifetime = 0.65
	p.spread = 180.0
	p.initial_velocity_min = 140.0 * strength
	p.initial_velocity_max = 320.0 * strength
	p.gravity = Vector2(0, 260)
	# 俯视桌面：从一条横向短线上升起，碎屑沿桌面铺开，而不是从一点球状炸开
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(16.0 * strength, 2.0)
	p.texture = Vfx.dot()
	p.scale_amount_min = 0.14 * strength
	p.scale_amount_max = 0.34 * strength
	p.color = UiTheme.hot(color, 1.8)
	p.emitting = true
	parent.add_child(p)
	get_tree_safe_free(p, 1.0, parent)


## 延迟释放节点（避免依赖 Tree 的 create_timer 引用）
static func get_tree_safe_free(node: Node, seconds: float, parent: Node) -> void:
	var tw := parent.create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(node.queue_free)
