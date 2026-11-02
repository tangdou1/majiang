extends SceneTree
## 用 tests/run_ui_tests.py 运行：涉及设置保存，必须隔离用户数据目录。

var _checks := 0
var _failures := 0


func _init() -> void:
	var test_root := OS.get_environment("MAJIANG_TEST_DATA_ROOT").replace("\\", "/")
	if test_root.is_empty() or not OS.get_user_data_dir().replace("\\", "/").begins_with(test_root + "/"):
		push_error("请通过 python3 tests/run_ui_tests.py 运行，避免写入玩家的真实设置。")
		quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	ThemeDB.fallback_font = load("res://assets/fonts/NotoSansSC.ttf")
	if OS.get_cmdline_user_args().has("--verify-saved"):
		Settings.load_settings()
		_expect(Settings.reduced_motion, "A fresh process must restore reduced motion")
		_expect(Settings.pace_index == 1 and Settings.muted, "Restart must preserve unrelated settings")
		var game := _fixture(Vector2(1920, 1080), Settings.reduced_motion)
		game._round.turn_changed.emit(0)
		_expect(not game._ambient.visible and not game._ambient.emitting, "New games must apply the saved ambient preference")
		_expect(game._turn_indicator.visible and game._turn_indicator._pulse == null, "New games must apply the saved steady indicator preference")
		game.free()
		await process_frame
	else:
		_test_persistence()
		await _test_menu_settings()
		for canvas in [Vector2(1920, 1080), Vector2(2400, 1080), Vector2(1920, 1440)]:
			var game := _fixture(canvas)
			await process_frame
			await _test_indicator(game)
			game._abort_round()
			_expect(not game._turn_indicator.visible and game._turn_indicator._pulse == null, "Exit must stop the turn indicator")
			game.free()
			await process_frame
		var game := _fixture(Vector2(1920, 1080))
		await _test_live_toggle(game)
		await _test_reduced_flight(game)
		await _test_restoring_full_effects(game)
		game.free()
		await process_frame
		# 供 runner 的第二个进程验证真正的跨进程持久化。
		Settings.reduced_motion = true
		Settings.save_settings()
	print("Effects regression: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _test_persistence() -> void:
	Settings.load_settings()
	_expect(not Settings.reduced_motion, "Fresh installs must keep full effects by default")
	var legacy := ConfigFile.new()
	legacy.set_value("game", "pace_index", 1)
	legacy.set_value("audio", "sfx_volume", 0.35)
	legacy.set_value("audio", "voice_volume", 0.8)
	legacy.set_value("audio", "muted", true)
	_expect(legacy.save(Settings.PATH) == OK, "Legacy fixture must save")
	Settings.reduced_motion = true
	Settings._loaded = false
	Settings.load_settings()
	_expect(not Settings.reduced_motion, "Old configs without the setting must default to full effects")
	for enabled in [true, false]:
		Settings.reduced_motion = enabled
		Settings.save_settings()
		var saved := ConfigFile.new()
		_expect(saved.load(Settings.PATH) == OK, "Settings file must be readable")
		_expect(saved.get_value("visual", "reduced_motion") == enabled, "Visual preference must save")
		Settings.reduced_motion = not enabled
		Settings._loaded = false
		Settings.load_settings()
		_expect(Settings.reduced_motion == enabled, "Visual preference must reload")
		_expect(Settings.pace_index == 1 and Settings.muted, "Visual preference must not change pace/mute")
		_expect(is_equal_approx(Settings.sfx_volume, 0.35) and is_equal_approx(Settings.voice_volume, 0.8), "Visual preference must not change volume")


func _test_menu_settings() -> void:
	var menu := MenuView.new()
	menu.theme = UiTheme.build()
	root.add_child(menu)
	menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	menu.size = Vector2(1920, 1080)
	menu._open_settings()
	var popup := menu.get_node("SettingsView") as SettingsView
	await process_frame
	await process_frame
	_expect(Rect2(Vector2.ZERO, menu.size).encloses(popup._panel.get_rect()), "Settings panel must fit a landscape canvas")
	var toggle := popup.find_child("ReducedMotionToggle", true, false) as CheckButton
	_expect(toggle != null and not toggle.button_pressed, "Menu must expose the saved switch state")
	toggle.button_pressed = true
	_expect(Settings.reduced_motion, "Menu switch must update settings immediately")
	popup.close()
	await process_frame
	menu._open_settings()
	popup = menu.get_node("SettingsView") as SettingsView
	toggle = popup.find_child("ReducedMotionToggle", true, false) as CheckButton
	_expect(toggle.button_pressed, "Reopening settings must restore switch state")
	toggle.button_pressed = false
	menu.free()
	await process_frame


func _fixture(canvas: Vector2, reduced_motion: bool = false) -> GameView:
	Settings.reduced_motion = reduced_motion
	var game := GameView.new()
	game.theme = UiTheme.build()
	game.rule = MahjongRule.create("sichuan")
	game._human = HumanPlayer.new(0, "你")
	game._players = [game._human, Player.new(1, "麻将小王子"), Player.new(2, "陈晨"), Player.new(3, "阿杰")]
	for p: Player in game._players:
		p.missing_suit = 0
		for i in 14 if p == game._human else 13:
			p.hand.add(Tile.from_kind(9 + i))
	game._allowed = game._human.hand.concealed.duplicate()
	root.add_child(game)
	game._sfx._streams.clear()
	game._sfx._voices.clear()
	game.set_anchors_preset(Control.PRESET_TOP_LEFT)
	game.size = canvas
	game._match = MatchController.new(game.rule, game._players)
	game._round = game._match.start_next_round()
	game._round.pace_time = Settings.pace()
	game._speed = Settings.pace()
	game._connect_round(game._round)
	game._refresh()
	return game


func _test_indicator(game: GameView) -> void:
	var dot := game._turn_indicator
	_expect(not dot.visible and dot._pulse == null, "No indicator before the first turn")
	_expect(dot.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Indicator must never intercept clicks")
	for seat in [0, 1, 2, 3]:
		game._round.turn_changed.emit(seat)
		_expect(dot.visible and dot._pulse != null, "Turn changes must activate the breathing indicator")
		var pulse := dot._pulse
		game._refresh_labels()
		game._refresh_labels()
		_expect(dot._pulse == pulse, "Label refresh must not restart or duplicate breathing")
		for nickname in ["李伟", "麻将小王子"]:
			for score in [-2048, 999999]:
				game._players[seat].display_name = nickname
				game._players[seat].score = score
				game._refresh_labels()
				var label := game._score_labels[seat]
				var width := minf(label.size.x, label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x)
				var text_rect := Rect2(label.position, Vector2(width, label.size.y))
				if seat == 1:
					text_rect.position.x += label.size.x - width
				_expect(not dot.get_rect().intersects(text_rect), "Indicator must not overlap the name/score")
				_expect(not dot.get_rect().intersects(game._chips[seat].get_rect()), "Indicator must not overlap missing-suit chip")
				_expect(game._safe_rect().encloses(dot.get_rect()), "Indicator must stay inside the table")
				_expect(is_equal_approx(dot.get_rect().get_center().y, label.get_rect().get_center().y), "Indicator must align vertically with the name")
				var gap := text_rect.position.x - dot.get_rect().end.x if seat == 1 or seat == 2 else dot.position.x - text_rect.end.x
				_expect(is_equal_approx(gap, TurnIndicator.GAP), "Indicator must follow actual text width")
				for entry in game._build_entries():
					var tile_size: Vector2 = entry["size"]
					if not is_zero_approx(entry["rot"]):
						tile_size = Vector2(tile_size.y, tile_size.x)
					_expect(not dot.get_rect().intersects(Rect2(entry["center"] - tile_size * 0.5, tile_size)), "Indicator must not overlap tiles")
	var pulse := dot._pulse
	pulse.pause()
	pulse.custom_step(1.1)
	_expect(is_equal_approx(dot.modulate.a, 1.0), "Breathing must reach the bright phase")
	pulse.custom_step(1.1)
	_expect(is_equal_approx(dot.modulate.a, 0.6), "Breathing must remain visible in its dim phase")
	pulse.play()
	game._open_pause()
	var paused_alpha := dot.modulate.a
	await create_timer(0.12).timeout
	_expect(is_equal_approx(dot.modulate.a, paused_alpha), "Breathing must freeze while paused")
	game._close_pause()
	game._players[3].finished = true
	game._refresh_labels()
	_expect(not dot.visible and dot._pulse == null, "A won player must not keep the turn indicator")
	game._players[3].finished = false
	game._round.turn_changed.emit(1)
	game._round.round_started.emit(0)
	_expect(not dot.visible, "New-round missing-suit phase must hide the indicator")
	game._round.turn_changed.emit(2)
	game._round.round_over = true
	game._refresh_labels()
	_expect(not dot.visible, "Round-over state must hide the indicator")
	game._round.round_over = false
	game._round.turn_changed.emit(0)
	game._round.round_finished.emit(false)
	_expect(not dot.visible and dot._pulse == null, "Round-finished signal must stop breathing")
	game._round.turn_changed.emit(0)


func _test_live_toggle(game: GameView) -> void:
	game._round.turn_changed.emit(0)
	game._celebrate(0, false)
	game._burst_at(Vector2(800, 400), UiTheme.GOLD, 1.4)
	Vfx.sparkle(game._fx_layer, Vector2(800, 400), UiTheme.GOLD, 16)
	_expect(game._flash_tween != null and game._fireworks_tween != null, "Full mode must still have celebration effects")
	game._world.position = Vector2(3, -2)
	game._overlay.color.a = 0.2
	game._open_pause()
	game._open_settings_in_pause()
	var popup := game.get_node("PauseSettingsView") as SettingsView
	var toggle := popup.find_child("ReducedMotionToggle", true, false) as CheckButton
	_expect(not toggle.button_pressed, "Pause setting must match menu preference")
	var old_pulse := game._turn_indicator._pulse
	toggle.button_pressed = true
	_expect(paused and Settings.reduced_motion, "Switch must work without unpausing the game")
	_expect(game._world.position == Vector2.ZERO and is_zero_approx(game._overlay.color.a), "Switch must immediately clear shake and flash")
	_expect(game._shake_tween == null and game._flash_tween == null and game._fireworks_tween == null, "Switch must cancel scheduled strong effects")
	_expect(not old_pulse.is_valid() and game._turn_indicator._pulse == null, "Switch must cancel the old pulse tween")
	_expect(game._turn_indicator.visible and is_equal_approx(game._turn_indicator.modulate.a, 1.0), "Reduced-motion turn indicator must stay steadily visible")
	_expect(not game._ambient.visible and not game._ambient.emitting and game._ambient.process_mode == Node.PROCESS_MODE_DISABLED, "Ambient particles must stop immediately")
	await process_frame
	await process_frame
	for effect in game._fx_layer.get_children():
		_expect(effect is Label, "Existing decorative particles/rays must be removed")
		if effect is Label:
			_expect(effect.scale == Vector2.ONE and effect.modulate.a > 0.0, "Existing call text must remain readable without scaling")
	_expect(Settings.pace_index == 1 and Settings.muted and is_equal_approx(Settings.sfx_volume, 0.35), "Toggle must not affect pace/audio")
	# 原彩纸的 5 秒清理计时器也必须随粒子销毁，否则会回调已释放对象。
	await create_timer(5.2).timeout
	_expect(game._fx_layer.get_child_count() == 0, "Cancelled fireworks must not respawn after toggling")
	_expect(game._world.position == Vector2.ZERO and is_zero_approx(game._overlay.color.a), "Old tweens must not restore shake/flash later")
	popup.close()
	game._close_pause()
	game._celebrate(0, true)
	_expect(game._flash_tween == null and game._fireworks_tween == null and game._shake_tween == null, "Future wins must honor reduced motion")
	var stamp := game._fx_layer.get_child(0) as Label
	_expect(stamp != null and stamp.text == "自摸" and stamp.scale == Vector2.ONE, "Reduced wins must retain readable call text")
	var fx_host := Node2D.new()
	game.add_child(fx_host)
	Vfx.sparkle(fx_host, Vector2.ZERO, UiTheme.GOLD, 16)
	var spark := fx_host.get_child(0) as CPUParticles2D
	_expect(spark.amount == 4 and spark.initial_velocity_max < 100.0, "Selection sparkles must use fewer/slower particles")
	Fx.burst(fx_host, Vector2.ZERO, UiTheme.GOLD)
	_expect(fx_host.get_child_count() == 2 and fx_host.get_child(1) is Fx, "Reduced impacts must retain only a soft ring")
	var ring := fx_host.get_child(1) as Fx
	_expect(ring.ring_color.a <= 0.35 and ring.line_width < 3.0, "Reduced impact ring must be softer")
	Vfx.rays(fx_host, Vector2.ZERO, UiTheme.GOLD, 360)
	Vfx.confetti(fx_host, 1920)
	_expect(fx_host.get_child_count() == 2, "Reduced mode must omit full-screen rays and confetti")
	fx_host.queue_free()


func _test_reduced_flight(game: GameView) -> void:
	game._mode = "discard"
	game._drawn_tile = game._human.hand.concealed.back()
	game._refresh()
	await create_timer(0.5).timeout
	var tile := game._drawn_tile
	game._human.hand.remove(tile)
	game._human.discards.append(tile)
	game._pool.append(tile)
	game._drawn_tile = null
	game._last_discard = tile
	game._flying[tile.get_instance_id()] = true
	game._selected_tile = game._human.hand.concealed[0]
	game._refresh()
	var view: TileView = game._views[tile.get_instance_id()]
	var flight: Tween = view.get_meta("tw")
	flight.pause()
	flight.custom_step(0.23)
	_expect(view.get_meta("flying", false) and view.scale.x <= 1.061, "Reduced flight must keep movement with a smaller scale pulse")
	flight.play()
	await create_timer(0.65).timeout
	_expect(not view.get_meta("flying", false) and view.scale.is_equal_approx(Vector2.ONE), "Reduced flight must still land normally")
	var selected: TileView = game._views[game._selected_tile.get_instance_id()]
	_expect(view.get_index() < selected.get_index(), "Reduced motion must preserve selection layering")
	_expect(view.mouse_filter == Control.MOUSE_FILTER_IGNORE and view.glow.a > 0.0, "Latest discard must retain highlight and ignore hand input")
	_expect(game._world.position == Vector2.ZERO and is_zero_approx(game._overlay.color.a), "Reduced impacts must not shake/flash the table")


func _test_restoring_full_effects(game: GameView) -> void:
	game._open_pause()
	game._open_settings_in_pause()
	var popup := game.get_node("PauseSettingsView") as SettingsView
	var toggle := popup.find_child("ReducedMotionToggle", true, false) as CheckButton
	_expect(toggle.button_pressed, "Reopened pause settings must remember reduced motion")
	toggle.button_pressed = false
	_expect(game._turn_indicator._pulse != null and game._ambient.emitting and game._ambient.visible, "Disabling reduced motion must restore pulse and ambience")
	popup.close()
	game._close_pause()
	game._celebrate(0, false)
	_expect(game._flash_tween != null and game._fireworks_tween != null, "Disabling reduced motion must restore celebration effects")
	game._flash_tween.pause()
	game._flash_tween.custom_step(0.12)
	_expect(is_equal_approx(game._overlay.color.a, 0.35), "Full mode must retain original flash strength")
