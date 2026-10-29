class_name Hand
extends RefCounted
## 手牌：暗牌 concealed + 副露 melds。

var concealed: Array[Tile] = []
var melds: Array[Meld] = []


func add(t: Tile) -> void:
	concealed.append(t)
	sort_concealed()


func remove(t: Tile) -> bool:
	var i := concealed.find(t)
	if i < 0:
		return false
	concealed.remove_at(i)
	return true


## 移除 kind 的 count 张，返回被移除的牌
func remove_kind(kind: int, count: int) -> Array[Tile]:
	var removed: Array[Tile] = []
	for t in concealed.duplicate():
		if removed.size() >= count:
			break
		if t.kind() == kind:
			concealed.erase(t)
			removed.append(t)
	return removed


func count_kind(kind: int) -> int:
	var n := 0
	for t in concealed:
		if t.kind() == kind:
			n += 1
	return n


func tiles_of_kind(kind: int) -> Array[Tile]:
	var out: Array[Tile] = []
	for t in concealed:
		if t.kind() == kind:
			out.append(t)
	return out


func kind_counts() -> PackedInt32Array:
	var c := PackedInt32Array()
	c.resize(27)
	c.fill(0)
	for t in concealed:
		c[t.kind()] += 1
	return c


func total_tile_count() -> int:
	var n := concealed.size()
	for m in melds:
		n += m.tiles.size()
	return n


func all_tiles() -> Array[Tile]:
	var out: Array[Tile] = []
	out.append_array(concealed)
	for m in melds:
		out.append_array(m.tiles)
	return out


func suits_present() -> Array[int]:
	var s: Array[int] = []
	for t in all_tiles():
		if not s.has(t.suit):
			s.append(t.suit)
	return s


func can_pung(t: Tile) -> bool:
	return count_kind(t.kind()) >= 2


func can_open_kong(t: Tile) -> bool:
	return count_kind(t.kind()) >= 3


## 暗杠候选：手中 4 张相同
func concealed_kong_kinds() -> Array[int]:
	var out: Array[int] = []
	var c := kind_counts()
	for k in 27:
		if c[k] == 4:
			out.append(k)
	return out


## 加杠候选：已碰的刻子 + 手中 1 张
func added_kong_kinds() -> Array[int]:
	var out: Array[int] = []
	for m in melds:
		if m.type == Meld.Type.PUNG and count_kind(m.kind()) >= 1:
			out.append(m.kind())
	return out


func find_pung_meld(kind: int) -> Meld:
	for m in melds:
		if m.type == Meld.Type.PUNG and m.kind() == kind:
			return m
	return null


func sort_concealed() -> void:
	concealed.sort_custom(func(a: Tile, b: Tile) -> bool: return a.sort_value() < b.sort_value())


func clone() -> Hand:
	var h := Hand.new()
	h.concealed = concealed.duplicate()
	h.melds = melds.duplicate()
	return h
