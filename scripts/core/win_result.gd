class_name WinResult
extends RefCounted
## 胡牌结果：番种列表与番数合计。

var fan_names: Array[String] = []
var fan_total: int = 0


func add_fan(name: String, value: int) -> void:
	fan_names.append("%s %d" % [name, value])
	fan_total += value


func summary() -> String:
	return "、".join(fan_names) + "（共 %d 番）" % fan_total
