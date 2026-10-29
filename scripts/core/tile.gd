class_name Tile
extends RefCounted
## 一张麻将牌（四川麻将只用 万/筒/条 三门，共 27 种，每种 4 张）。
## kind 编号 0~26：万 0-8，筒 9-17，条 18-26。

enum Suit { CHARACTER, CIRCLE, BAMBOO }

const SUIT_CHARS := ["万", "筒", "条"]
const NUMBER_NAMES := ["一", "二", "三", "四", "五", "六", "七", "八", "九"]

var suit: int
var rank: int   ## 1~9
var copy: int   ## 同种第几张（0~3），仅用于标识


func _init(p_suit: int, p_rank: int, p_copy: int = 0) -> void:
	suit = p_suit
	rank = p_rank
	copy = p_copy


static func from_kind(kind: int, p_copy: int = 0) -> Tile:
	return Tile.new(kind / 9, kind % 9 + 1, p_copy)


static func suit_of_kind(kind: int) -> int:
	return kind / 9


func kind() -> int:
	return suit * 9 + rank - 1


func is_terminal() -> bool:
	return rank == 1 or rank == 9


func same_kind(other: Tile) -> bool:
	return other != null and kind() == other.kind()


## 排序键：先 kind 再副本
func sort_value() -> int:
	return kind() * 4 + copy


func label() -> String:
	return NUMBER_NAMES[rank - 1] + SUIT_CHARS[suit]


func _to_string() -> String:
	return label()
