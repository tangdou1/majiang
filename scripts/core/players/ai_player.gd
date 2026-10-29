class_name AIPlayer
extends Player
## 电脑玩家：基于向听数的牌效决策。
## - 打牌：打出后向听数最小的牌，同向听时打孤张
## - 碰/杠：仅当副露后向听数不变差时才考虑（带随机性）
## - 定缺：牌数最少的花色

var aggression: float = 0.5


func _init(p_seat: int, p_name: String, p_aggression: float = 0.5) -> void:
	super(p_seat, p_name)
	aggression = p_aggression


func decide_missing_suit(_rule: MahjongRule) -> int:
	var counts := [0, 0, 0]
	for t in hand.concealed:
		counts[t.suit] += 1
	var best := 0
	for s in 3:
		if counts[s] < counts[best]:
			best = s
	return best


func decide_discard(allowed: Array, _rule: MahjongRule) -> Tile:
	if allowed.size() == 1:
		return allowed[0]
	var counts := hand.kind_counts()
	var best: Tile = null
	var best_score := INF
	for t in allowed:
		counts[t.kind()] -= 1
		var sh := WinChecker.shanten(counts, hand.melds.size())
		counts[t.kind()] += 1
		var score := float(sh) * 100.0 + _keep_value(t, counts) + randf() * 0.5
		if score < best_score:
			best_score = score
			best = t
	return best


## 牌价值：越小越该打
func _keep_value(t: Tile, counts: PackedInt32Array) -> float:
	var k := t.kind()
	var value := float(counts[k]) * 10.0
	for d: int in [-2, -1, 1, 2]:
		var r: int = t.rank + d
		if r >= 1 and r <= 9:
			value += float(counts[t.suit * 9 + r - 1]) * (3.0 if absi(d) == 1 else 1.5)
	if t.is_terminal():
		value -= 2.0
	return value


func decide_option(options: Array, phase: String, _rule: MahjongRule) -> Variant:
	for opt in options:
		if opt["action"] == "hu":
			return opt
	if phase == "self":
		for opt in options:
			if String(opt["action"]).begins_with("kong") and randf() < 0.7:
				return opt
		return null
	for opt in options:
		if opt["action"] == "kong" and randf() < 0.6 + aggression * 0.3:
			return opt
	for opt in options:
		if opt["action"] == "pung" and _meld_ok(opt) and randf() < 0.6 + aggression * 0.3:
			return opt
	return null


## 碰之后再打一张，向听数是否不劣于现在
func _meld_ok(opt: Dictionary) -> bool:
	var counts := hand.kind_counts()
	var before := WinChecker.shanten(counts, hand.melds.size())
	var used: Array = opt.get("tiles", [])
	for t in used:
		counts[(t as Tile).kind()] -= 1
	var best := 99
	for k in WinChecker.KINDS:
		if counts[k] <= 0:
			continue
		counts[k] -= 1
		best = mini(best, WinChecker.shanten(counts, hand.melds.size() + 1))
		counts[k] += 1
	return best <= before
