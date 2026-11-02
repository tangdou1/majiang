class_name SichuanRule
extends MahjongRule
## 四川麻将·血战到底：只用万筒条（108 张），不能吃（但和牌可含顺子，即平胡）；开局定缺；
## 缺门牌未打光不能胡；一炮多响，直到只剩一名未胡玩家或牌摸完。

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
	var kongs := 0
	for m in hand.melds:
		if m.is_kong():
			kongs += 1
	if kongs > 0:
		res.add_fan("根×%d" % kongs, kongs)
	if ctx.self_drawn:
		res.add_fan("自摸", 1)


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
