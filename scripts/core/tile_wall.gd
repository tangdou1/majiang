class_name TileWall
extends RefCounted
## 牌墙（四川麻将无王牌）：108 张洗牌后放在一个牌堆里。
## 发牌每人 13 张后余牌 56 张；摸牌从前端取，杠后从尾端补牌；摸完即流局。
## 总数恒为 108：余牌 + 各家手牌与副露 + 牌河。

var _live: Array[Tile] = []


func _init(kinds: Array, copies: int = 4) -> void:
	for kind in kinds:
		for c in copies:
			_live.append(Tile.from_kind(kind, c))
	_live.shuffle()


## 正常摸牌；余牌摸完返回 null（流局）
func draw() -> Tile:
	if _live.is_empty():
		return null
	return _live.pop_front()


## 杠后补牌：从尾端取一张
func draw_replacement() -> Tile:
	if _live.is_empty():
		return null
	return _live.pop_back()


## 余牌张数（界面显示）
func remaining() -> int:
	return _live.size()


## 墙内总张数（即余牌）
func total_size() -> int:
	return _live.size()
