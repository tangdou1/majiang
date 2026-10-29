class_name RoundController
extends RefCounted
## 一局四川麻将的流程控制（协程状态机）。不含任何界面代码：
## 界面通过信号感知变化，通过 Player 的决策接口获得输入。
##
## 流程：摸牌 → 自摸阶段（胡/杠）→ 打牌 → 别家响应（胡/碰/杠）→ 下家

signal round_started(dealer: int)
signal tile_drawn(seat: int, tile: Tile)
signal tile_discarded(seat: int, tile: Tile)
signal meld_made(seat: int, meld: Meld)
signal player_won(seat: int, result: WinResult, self_drawn: bool)
signal transfers_applied(transfers: Array)
signal message(seat: int, text: String)
signal turn_changed(seat: int)
signal round_finished(draw: bool)

var rule: MahjongRule
var players: Array = []     ## Array[Player]，4 人
var dealer: int = 0
var pace_time: float = 0.45 ## AI 动作间隔（秒）；测试时设为 0
var wall: TileWall
var round_over: bool = false
var draw_game: bool = false


func _init(p_rule: MahjongRule, p_players: Array, p_dealer: int) -> void:
	rule = p_rule
	players = p_players
	dealer = p_dealer
	wall = TileWall.new(rule.get_tile_kinds(), rule.get_copies())


func player(seat: int) -> Player:
	return players[seat]


func active_count() -> int:
	var n := 0
	for p in players:
		if not (p as Player).finished:
			n += 1
	return n


func _next(seat: int) -> int:
	return (seat + 1) % MahjongRule.PLAYER_COUNT


# ============================ 主流程 ============================

func play() -> void:
	for p in players:
		(p as Player).reset_for_round()
	_deal()
	round_started.emit(dealer)
	await _pace()

	if rule.requires_missing_suit():
		for p in players:
			var suit: int = await (p as Player).decide_missing_suit(rule)
			(p as Player).missing_suit = suit
			message.emit((p as Player).seat, "定缺·" + Tile.SUIT_CHARS[suit])
		await _pace()

	var current := dealer
	var need_draw := true
	var replacement := false

	while not round_over:
		var p: Player = players[current]
		if p.finished:
			current = _next(current)
			continue

		if need_draw:
			var drawn: Tile = wall.draw_replacement() if replacement else wall.draw()
			replacement = false
			if drawn == null:
				_finish_draw()
				break
			p.hand.add(drawn)
			tile_drawn.emit(current, drawn)
			turn_changed.emit(current)
			await _pace()

			var action := await _self_phase(p, drawn)
			if action == "hu":
				if round_over:
					break
				current = _next(current)
				need_draw = true
				continue
			if action == "kong":
				replacement = true
				need_draw = true
				continue

		# ---- 打牌 ----
		turn_changed.emit(current)
		var allowed := _allowed_discards(p)
		var discard: Tile = await p.decide_discard(allowed, rule)
		# 防御：出牌必须是手中且可打的牌，否则改打第一张可打牌
		if discard == null or not p.hand.concealed.has(discard) or not allowed.has(discard):
			discard = allowed[0]
		p.hand.remove(discard)
		p.discards.append(discard)
		tile_discarded.emit(current, discard)
		await _pace()

		# ---- 别家响应 ----
		var outcome := await _claim_phase(current, discard)
		if outcome == "hu" or outcome == "none":
			if round_over:
				break
			current = _next(current)
			need_draw = true
		else:
			# "meld:<seat>:<pung|kong>"：由声明者继续出牌；杠则需补牌
			var parts := outcome.split(":")
			current = int(parts[1])
			need_draw = parts[2] == "kong"
			replacement = need_draw

	round_finished.emit(draw_game)


func _deal() -> void:
	for _i in range(MahjongRule.HAND_SIZE):
		for k in MahjongRule.PLAYER_COUNT:
			var seat := (dealer + k) % MahjongRule.PLAYER_COUNT
			(players[seat] as Player).hand.add(wall.draw())


func _finish_draw() -> void:
	round_over = true
	draw_game = true
	message.emit(-1, "流局")


func _pace() -> void:
	if pace_time > 0.0:
		await (Engine.get_main_loop() as SceneTree).create_timer(pace_time).timeout


# ============================ 自摸阶段 ============================

## 返回 "hu" / "kong" / "none"
func _self_phase(p: Player, drawn: Tile) -> String:
	var options := _self_options(p, drawn)
	if options.is_empty():
		return "none"
	var choice: Variant = await p.decide_option(options, "self", rule)
	if choice == null:
		return "none"
	var opt: Dictionary = choice
	match opt["action"]:
		"hu":
			var res := rule.evaluate_win(p.hand, _ctx(p, true, drawn, -1))
			if res == null:
				return "none"
			_record_win(p, res, true, -1)
			return "hu"
		"kong_concealed":
			_do_concealed_kong(p, opt["kind"])
			message.emit(p.seat, "暗杠")
			return "kong"
		"kong_added":
			_do_added_kong(p, opt["kind"])
			message.emit(p.seat, "补杠")
			return "kong"
	return "none"


func _self_options(p: Player, drawn: Tile) -> Array:
	var opts: Array = []
	if rule.evaluate_win(p.hand, _ctx(p, true, drawn, -1)) != null:
		opts.append({"action": "hu"})
	for k in p.hand.concealed_kong_kinds():
		if not _is_missing(p, k):
			opts.append({"action": "kong_concealed", "kind": k, "tiles": p.hand.tiles_of_kind(k)})
	for k in p.hand.added_kong_kinds():
		if not _is_missing(p, k):
			opts.append({"action": "kong_added", "kind": k, "tiles": p.hand.tiles_of_kind(k)})
	return opts


func _is_missing(p: Player, kind: int) -> bool:
	return p.missing_suit >= 0 and Tile.suit_of_kind(kind) == p.missing_suit


func _allowed_discards(p: Player) -> Array:
	var allowed: Array = p.hand.concealed.duplicate()
	if rule.requires_missing_suit() and p.missing_suit >= 0:
		var missing := allowed.filter(func(t: Tile) -> bool: return t.suit == p.missing_suit)
		if not missing.is_empty():
			return missing
	return allowed


# ============================ 别家响应 ============================

## 返回 "hu" / "none" / "meld:<seat>:pung|kong"
func _claim_phase(discarder: int, d: Tile) -> String:
	var order: Array[int] = []
	for i in range(1, MahjongRule.PLAYER_COUNT):
		order.append((discarder + i) % MahjongRule.PLAYER_COUNT)

	var responses := {}
	for seat in order:
		var p: Player = players[seat]
		var opts := _claim_options(p, d, discarder)
		if opts.is_empty():
			continue
		var choice: Variant = await p.decide_option(opts, "claim", rule)
		if choice != null:
			responses[seat] = choice

	# 1. 胡（一炮多响：全部响应者都胡；否则按座次取第一个）
	var winners: Array[int] = []
	for seat in order:
		if responses.has(seat) and responses[seat]["action"] == "hu":
			winners.append(seat)
	if not winners.is_empty():
		_pop_claimed_discard(discarder)
		# 一炮多响：这张牌实际只有一张，仅第一位和牌者保留在手中，其余人只结算和牌结果
		var first := true
		for seat in winners:
			var p: Player = players[seat]
			p.hand.add(d)
			var res := rule.evaluate_win(p.hand, _ctx(p, false, d, discarder))
			if res == null:
				p.hand.remove(d)
				continue
			_record_win(p, res, false, discarder)
			if not first:
				p.hand.remove(d)
			first = false
			if round_over:
				break
		return "hu"

	# 2. 碰 / 杠（按座次）
	for seat in order:
		if not responses.has(seat):
			continue
		var opt: Dictionary = responses[seat]
		if opt["action"] == "pung" or opt["action"] == "kong":
			_pop_claimed_discard(discarder)
			_do_claim_meld(players[seat], d, discarder, opt["action"])
			return "meld:%d:%s" % [seat, "kong" if opt["action"] == "kong" else "pung"]
	return "none"


func _claim_options(p: Player, d: Tile, discarder: int) -> Array:
	var opts: Array = []
	if p.finished:
		return opts
	var h2 := p.hand.clone()
	h2.add(d)
	if rule.evaluate_win(h2, _ctx(p, false, d, discarder)) != null:
		opts.append({"action": "hu"})
	# 定缺花色的牌不能参与副露
	if p.missing_suit >= 0 and d.suit == p.missing_suit:
		return opts
	if p.hand.can_open_kong(d):
		opts.append({"action": "kong", "tiles": p.hand.tiles_of_kind(d.kind()).slice(0, 3)})
	if p.hand.can_pung(d):
		opts.append({"action": "pung", "tiles": p.hand.tiles_of_kind(d.kind()).slice(0, 2)})
	return opts


func _pop_claimed_discard(discarder: int) -> void:
	var pile: Array[Tile] = (players[discarder] as Player).discards
	if not pile.is_empty():
		pile.pop_back()


func _do_claim_meld(p: Player, d: Tile, discarder: int, action: String) -> void:
	if action == "kong":
		var tiles := p.hand.remove_kind(d.kind(), 3)
		tiles.append(d)
		var m := Meld.new(Meld.Type.KONG_OPEN, tiles, discarder)
		p.hand.melds.append(m)
		_apply(rule.kong_transfers(m.type, p.seat, discarder))
		meld_made.emit(p.seat, m)
		message.emit(p.seat, "杠")
	else:
		var tiles := p.hand.remove_kind(d.kind(), 2)
		tiles.append(d)
		var m := Meld.new(Meld.Type.PUNG, tiles, discarder)
		p.hand.melds.append(m)
		meld_made.emit(p.seat, m)
		message.emit(p.seat, "碰")


func _do_concealed_kong(p: Player, kind: int) -> void:
	var tiles := p.hand.remove_kind(kind, 4)
	var m := Meld.new(Meld.Type.KONG_CONCEALED, tiles, p.seat)
	p.hand.melds.append(m)
	_apply(rule.kong_transfers(m.type, p.seat, -1))
	meld_made.emit(p.seat, m)


func _do_added_kong(p: Player, kind: int) -> void:
	var m := p.hand.find_pung_meld(kind)
	var t := p.hand.tiles_of_kind(kind)[0]
	p.hand.remove(t)
	m.tiles.append(t)
	m.type = Meld.Type.KONG_ADDED
	_apply(rule.kong_transfers(m.type, p.seat, -1))
	meld_made.emit(p.seat, m)


# ============================ 胡牌与结算 ============================

func _ctx(p: Player, self_drawn: bool, t: Tile, discarder: int) -> WinContext:
	var ctx := WinContext.new()
	ctx.winner_seat = p.seat
	ctx.self_drawn = self_drawn
	ctx.is_dealer = p.seat == dealer
	ctx.winning_tile = t
	ctx.discarder_seat = discarder
	ctx.missing_suit = p.missing_suit
	return ctx


func _record_win(p: Player, res: WinResult, self_drawn: bool, discarder: int) -> void:
	p.finished = true
	p.win_result = res
	_apply(rule.settle_win(res, p.seat, discarder, self_drawn, dealer))
	player_won.emit(p.seat, res, self_drawn)
	if not rule.allows_multiple_winners() or active_count() <= 1:
		round_over = true


func _apply(transfers: Array) -> void:
	for tr in transfers:
		(players[tr["from"]] as Player).score -= tr["amount"]
		(players[tr["to"]] as Player).score += tr["amount"]
	if not transfers.is_empty():
		transfers_applied.emit(transfers)
