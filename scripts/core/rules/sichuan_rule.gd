class_name SichuanRule
extends MahjongRule
## 四川麻将·血战到底：只用万筒条（108 张），不能吃（但和牌可含顺子，即平胡）；开局定缺；
## 缺门牌未打光不能胡；一炮多响，直到只剩一名未胡玩家或牌摸完。

## 花猪赔三家，每家的赔付（相当于满贯 6 番）
const FLOWER_PIG_PAY := 64


func get_id() -> String:
	return "sichuan"


func get_display_name() -> String:
	return "四川麻将 · 血战到底"


func get_description() -> String:
	return "只用万条筒，无吃。开局每人定缺一门，缺门牌打光才能胡。可一炮多响，直到只剩一人未胡。"


func allows_multiple_winners() -> bool:
	return true


## 四川：不能吃，但自摸形成的顺子可以组成平胡（和牌时允许顺子）
func allows_sequences() -> bool:
	return true


func requires_missing_suit() -> bool:
	return true


func evaluate_win(hand: Hand, ctx: WinContext) -> WinResult:
	if ctx.missing_suit >= 0:
		for t in hand.all_tiles():
			if t.suit == ctx.missing_suit:
				return null
	return super.evaluate_win(hand, ctx)


func score_fans(hand: Hand, ctx: WinContext, res: WinResult) -> void:
	var counts := WinChecker.counts_of(hand.concealed)
	var seven := hand.melds.is_empty() and WinChecker.is_seven_pairs(counts)
	var pung_pung := false
	if not seven:
		pung_pung = _all_pungs(hand)
	if seven:
		res.add_fan("七对", 2)
	elif pung_pung:
		res.add_fan("碰碰胡", 2)
	else:
		res.add_fan("平胡", 1)
	if hand.suits_present().size() == 1:
		res.add_fan("清一色", 2)
	var roots := _count_roots(hand)
	if roots > 0:
		res.add_fan("根×%d" % roots, roots)
	if ctx.self_drawn:
		res.add_fan("自摸", 1)
	if ctx.robbed_kong:
		res.add_fan("抢杠胡", 1)


## 根：4 张同花色为一组。杠 = 4 张，碰 + 单张 = 4 张，暗杠 = 4 张
func _count_roots(hand: Hand) -> int:
	var roots := 0
	var cc := WinChecker.counts_of(hand.concealed)
	for k in 27:
		var total := cc[k]
		for m in hand.melds:
			if m.kind() == k:
				if m.type == Meld.Type.PUNG:
					total += 3
				elif m.is_kong():
					total += 4
		roots += total // 4
	return roots


func _all_pungs(hand: Hand) -> bool:
	for m in hand.melds:
		if m.is_open() and m.type != Meld.Type.PUNG and not m.is_kong():
			return false
	return WinChecker.can_decompose_pungs(WinChecker.counts_of(hand.concealed), 4 - hand.melds.size())


## 点数 = 2^番数（番数上限 6）；自摸三家付，点炮者单付
func settle_win(res: WinResult, winner: int, discarder: int, self_drawn: bool, _dealer: int) -> Array:
	var pay := 1 << mini(res.fan_total, 6)
	var transfers: Array = []
	if self_drawn:
		for s in PLAYER_COUNT:
			if s != winner:
				transfers.append({"from": s, "to": winner, "amount": pay})
	else:
		transfers.append({"from": discarder, "to": winner, "amount": pay})
	return transfers


## 明杠：放杠者付 2；补杠：每家 1；暗杠：每家 2
func kong_transfers(kong_type: int, kong_seat: int, discarder: int) -> Array:
	var transfers: Array = []
	match kong_type:
		Meld.Type.KONG_OPEN:
			transfers.append({"from": discarder, "to": kong_seat, "amount": 2})
		Meld.Type.KONG_ADDED:
			for s in PLAYER_COUNT:
				if s != kong_seat:
					transfers.append({"from": s, "to": kong_seat, "amount": 1})
		Meld.Type.KONG_CONCEALED:
			for s in PLAYER_COUNT:
				if s != kong_seat:
					transfers.append({"from": s, "to": kong_seat, "amount": 2})
	return transfers


## 流局结算：花猪赔 + 查大叫。返回转账列表 [{from, to, amount}]
## p_hands: Array[Hand]（按座位），p_missing: Array[int]（每家定缺，-1 无）
func settle_draw(p_hands: Array, p_missing: Array) -> Array:
	var transfers: Array = []
	# 1. 花猪：缺门未清
	var pigs: Array[int] = []
	var normal: Array[int] = []
	for i in p_hands.size():
		var h := p_hands[i] as Hand
		if p_missing[i] >= 0 and _hand_has_suit(h, p_missing[i]):
			pigs.append(i)
		else:
			normal.append(i)
	# 花猪赔非花猪
	for pig in pigs:
		for nseat in normal:
			transfers.append({"from": pig, "to": nseat, "amount": FLOWER_PIG_PAY})
	# 2. 查大叫：非花猪中，未听牌赔听牌
	var tenpai: Array[int] = []
	var noten: Array[int] = []
	for s in normal:
		var h2 := p_hands[s] as Hand
		if _is_tenpai(h2, p_missing[s]):
			tenpai.append(s)
		else:
			noten.append(s)
	for nseat in noten:
		for tseat in tenpai:
			var h3 := p_hands[tseat] as Hand
			var amt := _max_tenpai_pay(h3, p_missing[tseat])
			transfers.append({"from": nseat, "to": tseat, "amount": amt})
	return transfers


func _hand_has_suit(hand: Hand, suit: int) -> bool:
	for t in hand.all_tiles():
		if t.suit == suit:
			return true
	return false


func _is_tenpai(hand: Hand, missing: int) -> bool:
	var waits := waiting_kinds_of(hand)
	if waits.is_empty():
		return false
	if missing < 0:
		return true
	for k in waits:
		if Tile.suit_of_kind(k) != missing:
			return true
	return false


## 听牌者最大可能的赔付（假设摸到最优等待牌，按自摸算）
func _max_tenpai_pay(hand: Hand, missing: int) -> int:
	var max_amt := 1 << 1  # 平胡 = 2^1 = 2
	var waits := waiting_kinds_of(hand)
	for k in waits:
		if missing >= 0 and Tile.suit_of_kind(k) == missing:
			continue  # 缺门花色的等待不算
		var tile := Tile.from_kind(k)
		if tile == null:
			continue
		var h2 := hand.clone()
		h2.add(tile)
		var ctx := WinContext.new()
		ctx.missing_suit = missing
		ctx.self_drawn = true  # 查大叫按自摸算
		var res := evaluate_win(h2, ctx)
		if res == null:
			continue
		var amt := 1 << mini(res.fan_total, 6)
		if amt > max_amt:
			max_amt = amt
	return max_amt
