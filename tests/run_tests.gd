extends SceneTree
## 无头自动化测试：godot --headless --script res://tests/run_tests.gd
## 只依赖 core 层的纯逻辑（不建任何界面），用来守住规则与结算。

var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("== 单机麻将 · core 逻辑测试 ==")
	_test_tiles()
	_test_win_shapes()
	_test_waits()
	_test_missing_suit()
	_test_scores()
	_test_kong_transfers()
	await _test_full_round()
	_report()
	quit(1 if not _failures.is_empty() else 0)


# ------------------------------------------------ 工具

func _ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures.append(what)


func _hand(kinds: Array) -> Hand:
	var h := Hand.new()
	for k in kinds:
		h.concealed.append(Tile.from_kind(k))
	h.sort_concealed()
	return h


func _ctx(missing: int = -1, self_drawn: bool = false) -> WinContext:
	var c := WinContext.new()
	c.missing_suit = missing
	c.self_drawn = self_drawn
	return c


# ------------------------------------------------ 牌

func _test_tiles() -> void:
	var t := Tile.new(Tile.Suit.BAMBOO, 9)
	_ok(t.kind() == 26, "条9 的 kind 应为 26")
	_ok(Tile.from_kind(26).suit == Tile.Suit.BAMBOO, "kind 26 应属于条")
	_ok(Tile.from_kind(9).label() == "一筒", "kind 9 应为一筒")
	var wall := TileWall.new(SichuanRule.new().get_tile_kinds(), 4)
	_ok(wall.remaining() == 108, "四川麻将牌墙应为 108 张")


# ------------------------------------------------ 和牌形状（四川：允许顺子）

func _test_win_shapes() -> void:
	var rule := SichuanRule.new()
	# 123万 456万 789万 111筒 22条
	var flat := _hand([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 9, 9, 19, 19])
	_ok(rule.is_win_shape(flat), "平胡（含顺子）应能和牌")

	# 111万 555筒 999条 222条 33万
	var pungs := _hand([0, 0, 0, 13, 13, 13, 26, 26, 26, 19, 19, 19, 2, 2])
	_ok(rule.is_win_shape(pungs), "碰碰胡应能和牌")

	var seven := _hand([0, 0, 4, 4, 9, 9, 13, 13, 18, 18, 22, 22, 26, 26])
	_ok(rule.is_win_shape(seven), "七对应能和牌")

	var not_win := _hand([0, 1, 3, 4, 6, 7, 9, 10, 12, 14, 15, 17, 19, 20])
	_ok(not rule.is_win_shape(not_win), "散牌不应算和牌")


# ------------------------------------------------ 听牌

func _test_waits() -> void:
	var rule := SichuanRule.new()
	# 13 张：123万 456万 789万 111筒 单钓 9条
	var h := _hand([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 9, 9, 26])
	var waits := rule.waiting_kinds_of(h)
	_ok(waits.has(26), "单钓 9条 应在听牌表里")
	_ok(waits.size() >= 1, "听牌表不应为空")


# ------------------------------------------------ 定缺

func _test_missing_suit() -> void:
	var rule := SichuanRule.new()
	var h := _hand([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 9, 9, 19, 19])
	_ok(rule.evaluate_win(h, _ctx()) != null, "未定缺时应能和牌")
	_ok(rule.evaluate_win(h, _ctx(Tile.Suit.BAMBOO)) == null, "手里还有条、缺条时不能和牌")


# ------------------------------------------------ 番数与结算

func _test_scores() -> void:
	var rule := SichuanRule.new()
	var seven := _hand([0, 0, 4, 4, 9, 9, 13, 13, 18, 18, 22, 22, 26, 26])
	var res := rule.evaluate_win(seven, _ctx())
	_ok(res != null, "七对应能通过判定")
	if res != null:
		_ok(res.fan_total == 2, "七对应为 2 番（实际 %d）" % res.fan_total)
		var tr := rule.settle_win(res, 1, 0, false, 0)
		_ok(tr.size() == 1, "点炮应由放炮者一家付")
		_ok(tr.size() == 1 and int(tr[0]["amount"]) == 4, "2 番点炮应支付 4 分")
		var tr2 := rule.settle_win(res, 1, -1, true, 0)
		_ok(tr2.size() == 3, "自摸应由其余三家付")

	var clear_seven := _hand([0, 0, 1, 1, 3, 3, 4, 4, 6, 6, 7, 7, 8, 8])
	var res2 := rule.evaluate_win(clear_seven, _ctx())
	_ok(res2 != null and res2.fan_total == 4, "清一色七对应为 4 番（实际 %s）" % ("null" if res2 == null else str(res2.fan_total)))


# ------------------------------------------------ 杠分

func _test_kong_transfers() -> void:
	var rule := SichuanRule.new()
	var open_kong := rule.kong_transfers(Meld.Type.KONG_OPEN, 0, 2)
	_ok(open_kong.size() == 1 and int(open_kong[0]["amount"]) == 2, "明杠应由放杠者付 2 分")
	var concealed := rule.kong_transfers(Meld.Type.KONG_CONCEALED, 0, -1)
	_ok(concealed.size() == 3, "暗杠应由其余三家各付")
	var added := rule.kong_transfers(Meld.Type.KONG_ADDED, 0, -1)
	_ok(added.size() == 3, "补杠应由其余三家各付")


# ------------------------------------------------ 一整局（四个 AI 自动对打）

func _test_full_round() -> void:
	var rule := SichuanRule.new()
	var players: Array = []
	for s in MahjongRule.PLAYER_COUNT:
		players.append(AIPlayer.new(s, "AI%d" % s, 0.5))
	var round := RoundController.new(rule, players, 0)
	round.pace_time = 0.0
	await round.play()

	var total := round.wall.remaining()
	for p in players:
		var pl := p as Player
		total += pl.hand.total_tile_count() + pl.discards.size()
	_ok(total == 108, "一局结束后牌数应守恒为 108（实际 %d）" % total)

	var sum := 0
	for p in players:
		sum += (p as Player).score
	_ok(sum == 0, "分数转移应为零和（实际 %d）" % sum)
	print("   一局打完：余牌 %d，比分 %s" % [round.wall.remaining(),
		str(players.map(func(p: Player) -> int: return p.score))])


func _report() -> void:
	if _failures.is_empty():
		print("全部通过：%d 项检查" % _checks)
		return
	print("失败 %d / %d 项：" % [_failures.size(), _checks])
	for f in _failures:
		print("  ✗ " + f)
