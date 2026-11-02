extends SceneTree
## 无需第三方测试框架：
## godot --headless --editor --path . --import
## godot --headless --path . --script tests/ui_regression.gd

var _checks := 0
var _failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	ThemeDB.fallback_font = load("res://assets/fonts/NotoSansSC.ttf")
	_test_highlight()
	for canvas_size in [Vector2(1920, 1080), Vector2(2400, 1080), Vector2(1920, 1440)]:
		var game := _fixture(canvas_size)
		await process_frame
		_test_hand_spacing(game)
		await _test_seat_alignment(game)
		_test_selection_and_reuse(game)
		await _test_overlapping_click(game)
		await _test_flight_and_overlays(game)
		game.free()
		await process_frame
	print("UI regression: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _fixture(canvas_size: Vector2) -> GameView:
	var game := GameView.new()
	game.rule = MahjongRule.create("sichuan")
	game._human = HumanPlayer.new(0, "你")
	game._players = [game._human, Player.new(1, "麻将小王子"), Player.new(2, "陈晨"), Player.new(3, "阿杰")]
	for p: Player in game._players:
		p.missing_suit = 0
		var kinds: Array = [9, 9, 9, 11, 11, 11, 12, 13, 14, 15, 16, 17, 19, 22] if p == game._human else range(9, 22)
		for kind: int in kinds:
			p.hand.add(Tile.from_kind(kind, p.hand.count_kind(kind)))
	game._drawn_tile = game._human.hand.concealed.back()
	game._allowed = game._human.hand.concealed.duplicate()
	game._mode = "discard"
	game.theme = UiTheme.build()
	root.add_child(game)
	# 本测试只覆盖布局/输入；不播放音频，避免 Dummy 音频线程在退出时持有播放资源。
	game._sfx._streams.clear()
	game._sfx._voices.clear()
	game.set_anchors_preset(Control.PRESET_TOP_LEFT)
	game.size = canvas_size
	_expect(game.size.is_equal_approx(canvas_size), "Fixture must use the requested canvas size")
	game._match = MatchController.new(game.rule, game._players)
	game._round = game._match.start_next_round()
	game._refresh()
	return game


func _entry_for(entries: Array, tile: Tile) -> Dictionary:
	for e in entries:
		if e["tile"] == tile:
			return e
	return {}


func _settle(game: GameView, entries: Array) -> void:
	game._apply_entries(entries)
	for v: TileView in game._views.values():
		var tween: Tween = v.get_meta("tw")
		tween.pause()
		tween.custom_step(1.0)


func _test_highlight() -> void:
	var tile := TileView.new()
	tile.set_glow(Color(UiTheme.GOLD, 0.95))
	for width in [50.0, 56.0, 114.0, 124.0]:
		var outline := tile._highlight_style(width)
		_expect(not outline.draw_center, "Highlight must not fill a large gold rectangle")
		_expect(outline.border_width_left >= 1 and outline.border_width_left <= 2, "Highlight must stay 1–2 px")
		_expect(outline.shadow_size == 0, "Highlight must not add an outer halo")
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			_expect(is_zero_approx(outline.get_expand_margin(side)), "Highlight must not extend beyond the tile")
		var tile_rect := Rect2(Vector2.ZERO, Vector2(width, width * 1.42))
		_expect(tile_rect.encloses(tile_rect.grow(-TileView.HIGHLIGHT_INSET)), "Highlight must be inset")
	tile.free()


func _test_hand_spacing(game: GameView) -> void:
	var hand := game._ordered_hand()
	var entries := game._build_entries()
	var safe := game._safe_rect()
	var previous_right := 0.0
	for i in hand.size():
		var e := _entry_for(entries, hand[i])
		var sz: Vector2 = e["size"]
		var center: Vector2 = e["center"]
		var left := center.x - sz.x * 0.5
		var right := center.x + sz.x * 0.5
		_expect(left >= safe.position.x and right <= safe.end.x, "14-tile hand must fit horizontally")
		if i > 0:
			var expected_gap := GameView.HAND_TILE_GAP
			if hand[i] == game._drawn_tile:
				expected_gap += game._hand_tile_width() * 0.34
			_expect(absf(left - previous_right - expected_gap) < 0.01, "Tile gap must include drawn-tile separation")
		previous_right = right
	var ordinary := _entry_for(entries, hand[0])
	var drawn := _entry_for(entries, game._drawn_tile)
	_expect(is_equal_approx(ordinary["center"].y - drawn["center"].y, GameView.HAND_DRAWN_LIFT), "Drawn tile must lift only 10 px")
	_expect(drawn["glow"].a > ordinary["glow"].a, "Drawn tile must be clearer than an unselected tile")
	game._allowed.erase(game._drawn_tile)
	var forbidden := _entry_for(game._build_entries(), game._drawn_tile)
	_expect(forbidden["dim"] and is_zero_approx(forbidden["glow"].a), "Forbidden drawn tile must not look selectable")
	game._allowed = game._human.hand.concealed.duplicate()


func _test_seat_alignment(game: GameView) -> void:
	var side_height := game._hand_tile_width() * 0.44 * 1.42
	var expected_right := game.size.x - side_height - 45.0
	for nickname in ["李伟", "麻将小王子"]:
		for score in [0, 128, -2048]:
			for suit in 3:
				game._players[1].display_name = nickname
				game._players[1].score = score
				game._players[1].missing_suit = suit
				game._refresh_labels()
				await process_frame
				var label := game._score_labels[1]
				var chip := game._chips[1]
				_expect(label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "Right player must be right-aligned")
				_expect(is_equal_approx(label.get_rect().end.x, expected_right), "Right name must stay next to its hand")
				_expect(is_equal_approx(chip.get_rect().end.x, expected_right), "Right missing-suit chip must align with name")
				_expect(chip.position.y >= label.get_rect().end.y + 4.0, "Missing-suit chip must not overlap name")
				_expect(is_equal_approx(game._score_labels[3].position.x, game.size.x - expected_right), "Side names must be mirrored")


func _test_selection_and_reuse(game: GameView) -> void:
	# 先创建手牌，再把同一 TileView 用作碰、杠牌，重现依赖创建顺序的遮挡问题。
	_settle(game, game._build_entries())
	var claimed: Array[Tile] = []
	for i in 3:
		claimed.append(game._human.hand.concealed.pop_front())
	var reused: TileView = game._views[claimed[0].get_instance_id()]
	game._human.hand.melds.append(Meld.new(Meld.Type.PUNG, claimed, 1))
	var kong: Array[Tile] = []
	for i in 3:
		kong.append(game._human.hand.concealed.pop_front())
	kong.append(Tile.from_kind(kong[0].kind(), 3))
	game._human.hand.melds.append(Meld.new(Meld.Type.KONG_OPEN, kong, 2))
	game._allowed = game._human.hand.concealed.duplicate()
	var hand := game._ordered_hand()
	var baseline := game.size.y - game._hand_tile_width() * 1.42 - 20.0
	for selected: Tile in [hand[0], hand[1], hand[0], game._drawn_tile]:
		game._selected_tile = selected
		var entries := game._build_entries()
		_settle(game, entries)
		var view: TileView = game._views[selected.get_instance_id()]
		_expect(is_equal_approx(view.position.y, baseline - GameView.HAND_SELECTION_LIFT), "Selection lift must be applied exactly once")
		_expect(view.scale.is_equal_approx(Vector2.ONE), "Selection must not widen into adjacent borders")
		_expect(view.get_index() == game._tiles_layer.get_child_count() - 1, "Selected tile must be the top tile, even after reselection")
		_expect(view.mouse_filter == Control.MOUSE_FILTER_STOP, "Selected tile must remain clickable")
		_expect(view.z_index == 0, "Tile ordering must stay local, below HUD and dialogs")
		for meld: Meld in game._human.hand.melds:
			for t: Tile in meld.tiles:
				var meld_view: TileView = game._views[t.get_instance_id()]
				_expect(meld_view.get_index() < view.get_index(), "Pung/kong tiles must stay below selection")
				_expect(meld_view.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Pung/kong tiles must not intercept input")
	_expect(game._views[claimed[0].get_instance_id()] == reused, "Layer repair must preserve reused TileViews")
	game._on_tile_tapped(reused)
	_expect(game._selected_tile == game._drawn_tile, "Tapping a meld must not change selection")
	game._selected_tile = null
	_settle(game, game._build_entries())
	var drawn_view: TileView = game._views[game._drawn_tile.get_instance_id()]
	_expect(drawn_view.get_index() == game._tiles_layer.get_child_count() - 1, "Deselection must restore drawn-tile order")
	game._mode = "wait"
	_settle(game, game._build_entries())
	for t: Tile in hand:
		_expect(game._views[t.get_instance_id()].mouse_filter == Control.MOUSE_FILTER_IGNORE, "Waiting hands must not intercept input")
	game._mode = "discard"


func _test_overlapping_click(game: GameView) -> void:
	var selected := game._human.hand.concealed[0]
	game._selected_tile = selected
	_settle(game, game._build_entries())
	var view: TileView = game._views[selected.get_instance_id()]
	var point := view.get_global_rect().position + Vector2(view.size.x * 0.4, 10)
	var meld: TileView = game._views[game._human.hand.melds[0].tiles[0].get_instance_id()]
	_expect(meld.get_global_rect().has_point(point), "Click fixture must overlap the meld area")
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = point
	click.global_position = point
	click.pressed = true
	root.push_input(click, true)
	_expect(game._human._answer == selected, "Clicking the overlap must confirm the selected hand tile")
	click.pressed = false
	root.push_input(click, true)
	game._human._answer = null
	game._mode = "discard"


func _test_flight_and_overlays(game: GameView) -> void:
	var flying := game._drawn_tile
	game._human.hand.remove(flying)
	game._human.discards.append(flying)
	game._pool.append(flying)
	game._drawn_tile = null
	game._last_discard = flying
	game._flying[flying.get_instance_id()] = true
	game._selected_tile = game._human.hand.concealed[0]
	game._refresh()
	var view: TileView = game._views[flying.get_instance_id()]
	_expect(view.get_meta("flying", false), "Discard must start its flight")
	_expect(view.get_index() == game._tiles_layer.get_child_count() - 1, "Flying tile must be above selection")
	game._refresh()  # 飞行中收到刷新，不能改变飞牌的层级或中断动画。
	_expect(view.get_index() == game._tiles_layer.get_child_count() - 1, "Refresh must preserve flying-tile order")
	_expect(game._fx_layer.get_index() > game._tiles_layer.get_index(), "Effects must stay above all tiles")
	_expect(game._pause_layer.get_index() > game._world.get_index(), "Pause layer must stay above the table")
	await create_timer(0.65).timeout
	_expect(not view.get_meta("flying", false), "Discard must land")
	var selected: TileView = game._views[game._selected_tile.get_instance_id()]
	_expect(view.get_index() < selected.get_index(), "Landed tile must return below the hand")
	_expect(view.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Landed tile must not intercept input")
	var pool_entry := _entry_for(game._build_entries(), flying)
	_expect(view.position.is_equal_approx(pool_entry["center"] - pool_entry["size"] * 0.5), "Landed tile must reach its river position")
