class_name Meld
extends RefCounted
## 副露：碰、明杠、补杠、暗杠（四川麻将无吃）。

enum Type { PUNG, KONG_OPEN, KONG_ADDED, KONG_CONCEALED }

var type: int
var tiles: Array[Tile] = []
var from_seat: int = -1   ## 放杠/放碰者座位；暗杠为自己


func _init(p_type: int, p_tiles: Array[Tile], p_from_seat: int = -1) -> void:
	type = p_type
	tiles = p_tiles
	from_seat = p_from_seat


func is_kong() -> bool:
	return type != Type.PUNG


func is_open() -> bool:
	return type != Type.KONG_CONCEALED


func kind() -> int:
	return tiles[0].kind()


func type_name() -> String:
	match type:
		Type.PUNG: return "碰"
		Type.KONG_OPEN: return "明杠"
		Type.KONG_ADDED: return "补杠"
	return "暗杠"
