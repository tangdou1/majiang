class_name WinChecker
extends RefCounted
## 胡牌形状判定与向听数估算。纯静态工具。
## 面子 = 刻子，或同花色连续三张的顺子（顺子只能由自己摸牌形成，吃牌仍然不允许）。

const KINDS := 27


static func counts_of(tiles: Array) -> PackedInt32Array:
	var c := PackedInt32Array()
	c.resize(KINDS)
	c.fill(0)
	for t in tiles:
		c[(t as Tile).kind()] += 1
	return c


## counts 能否分解为 sets 个刻子 + 1 对将
static func can_decompose_pungs(counts: PackedInt32Array, sets: int) -> bool:
	var c := counts.duplicate()
	for k in KINDS:
		if c[k] >= 2:
			c[k] -= 2
			var ok := _pungs(c, sets)
			c[k] += 2
			if ok:
				return true
	return false


static func _pungs(c: PackedInt32Array, need: int) -> bool:
	var i := -1
	for k in KINDS:
		if c[k] > 0:
			i = k
			break
	if i < 0:
		return need == 0
	if need == 0 or c[i] < 3:
		return false
	c[i] -= 3
	var ok := _pungs(c, need - 1)
	c[i] += 3
	return ok


## counts 能否分解为 sets 个面子（刻子或顺子）+ 1 对将。顺子只在同一花色内连续（kind % 9 <= 6）
static func can_decompose_sets(counts: PackedInt32Array, sets: int) -> bool:
	var c := counts.duplicate()
	for k in KINDS:
		if c[k] >= 2:
			c[k] -= 2
			var ok := _sets(c, sets)
			c[k] += 2
			if ok:
				return true
	return false


static func _sets(c: PackedInt32Array, need: int) -> bool:
	var i := -1
	for k in KINDS:
		if c[k] > 0:
			i = k
			break
	if i < 0:
		return need == 0
	if need == 0:
		return false
	if c[i] >= 3:
		c[i] -= 3
		var ok := _sets(c, need - 1)
		c[i] += 3
		if ok:
			return true
	if i % 9 <= 6 and c[i + 1] > 0 and c[i + 2] > 0:
		c[i] -= 1
		c[i + 1] -= 1
		c[i + 2] -= 1
		var ok2 := _sets(c, need - 1)
		c[i] += 1
		c[i + 1] += 1
		c[i + 2] += 1
		if ok2:
			return true
	return false


## 七对（允许 4 张同种视为两对）
static func is_seven_pairs(counts: PackedInt32Array) -> bool:
	var pairs := 0
	for k in KINDS:
		var n := counts[k]
		if n == 2:
			pairs += 1
		elif n == 4:
			pairs += 2
		elif n != 0:
			return false
	return pairs == 7


## 向听数（贪心估算）：0 为听牌，-1 为已和。仅用于 AI 决策。
static func shanten(counts: PackedInt32Array, melds: int) -> int:
	var c := counts.duplicate()
	var m := melds
	var t := 0
	var p := 0
	for k in KINDS:
		while c[k] >= 3:
			c[k] -= 3
			m += 1
	for k in KINDS:
		if k % 9 <= 6:
			while c[k] > 0 and c[k + 1] > 0 and c[k + 2] > 0:
				c[k] -= 1
				c[k + 1] -= 1
				c[k + 2] -= 1
				m += 1
	m = mini(m, 4)
	for k in KINDS:
		if c[k] >= 2:
			c[k] -= 2
			p = 1
			break
	var max_t := 4 - m
	for k in KINDS:
		while c[k] >= 2 and t < max_t:
			c[k] -= 2
			t += 1
	for k in KINDS:
		if k % 9 <= 7:
			while c[k] > 0 and c[k + 1] > 0 and t < max_t:
				c[k] -= 1
				c[k + 1] -= 1
				t += 1
		if k % 9 <= 6:
			while c[k] > 0 and c[k + 2] > 0 and t < max_t:
				c[k] -= 1
				c[k + 2] -= 1
				t += 1
	return 8 - 2 * m - mini(t, max_t) - p


## 听哪些 kind（counts 为 13 张或 4*n+1 形式的暗牌计数）
static func waiting_kinds(counts: PackedInt32Array, sets: int, seven_ok: bool, sequences: bool = false) -> Array[int]:
	var out: Array[int] = []
	var c := counts.duplicate()
	for k in KINDS:
		if c[k] >= 4:
			continue
		c[k] += 1
		var win := can_decompose_sets(c, sets) if sequences else can_decompose_pungs(c, sets)
		if not win and seven_ok:
			win = is_seven_pairs(c)
		c[k] -= 1
		if win:
			out.append(k)
	return out
