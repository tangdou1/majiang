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
	ring.ring_color = Color(color.r, color.g, color.b, 0.9)
	ring.line_width = 6.0 * strength
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
	p.texture = Vfx.dot()
	p.scale_amount_min = 0.14 * strength
	p.scale_amount_max = 0.34 * strength
	p.color = color
	p.emitting = true
	parent.add_child(p)
	get_tree_safe_free(p, 1.0, parent)


## 延迟释放节点（避免依赖 Tree 的 create_timer 引用）
static func get_tree_safe_free(node: Node, seconds: float, parent: Node) -> void:
	var tw := parent.create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(node.queue_free)
