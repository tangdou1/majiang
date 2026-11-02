class_name TurnIndicator
extends Control
## 当前行动玩家的微光标记。只呼吸亮度，不缩放或闪烁；轻动效模式下常亮。

const DIAMETER := 20.0
const GAP := 8.0

var _active := false
var _reduced_motion := false
var _pulse: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ONE * DIAMETER
	size = custom_minimum_size
	visible = false
	# GameView 在暂停时仍处理菜单，光点则随牌局一起停下。
	process_mode = Node.PROCESS_MODE_PAUSABLE


func set_active(active: bool, reduced_motion: bool) -> void:
	if _active == active and _reduced_motion == reduced_motion:
		return
	_active = active
	_reduced_motion = reduced_motion
	_stop_pulse()
	visible = active
	modulate.a = 1.0
	if not active or reduced_motion:
		return
	modulate.a = 0.6
	_pulse = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse.tween_property(self, "modulate:a", 1.0, 1.1)
	_pulse.tween_property(self, "modulate:a", 0.6, 1.1)


func _stop_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null


func _exit_tree() -> void:
	_stop_pulse()


func _draw() -> void:
	var center := size * 0.5
	# 不依赖 HDR：兼容渲染器中也能清楚看到，不让泛光蔓延到姓名上。
	draw_circle(center, 9.0, Color(UiTheme.GOLD, 0.12), true, -1.0, true)
	draw_circle(center, 6.0, Color(UiTheme.GOLD, 0.28), true, -1.0, true)
	draw_circle(center, 3.5, UiTheme.GOLD_SOFT, true, -1.0, true)
