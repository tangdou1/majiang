class_name GameView
extends Control
## 横屏牌桌界面（1920×1080 设计）。
## - 自己的手牌沿屏幕底边（最长边）排列，对家在上，左右家在两侧
## - 所有牌都是持久化视图（按 Tile 实例跟踪），位置变化用补间动画过渡
## - 出牌：牌沿弧线飞向牌河，落地时冲击波 + 粒子 + 震屏，并播放对应花色的撞击音
## 界面只负责展示与收集输入，规则全部在 core 层。

signal exit_requested
signal _continue_pressed

const HUMAN_NAME := "你"
const GOLD := Color("ffd54f")
const CREAM := Color("fff8e7")
const SUIT_COLORS := [Color("ef5350"), Color("42a5f5"), Color("66bb6a")]

var rule: MahjongRule
var _match: MatchController
var _round: RoundController
var _players: Array = []
var _human: HumanPlayer
var _sfx: Sfx
var _speed: float = 0.7
var _reveal: bool = false             # 一局结束后翻开 AI 的手牌
var _ambient: CPUParticles2D         # 牌桌上的漂浮光点
var _chips: Array[PanelContainer] = []  # 每家的定缺标签

var _world: Control          # 牌桌内容（震屏作用于此）
var _tiles_layer: Control    # 所有牌视图
var _fx_layer: Control       # 粒子、冲击波
var _overlay: ColorRect      # 胡牌时的金色闪光
var _title: Label
var _info: Label
var _score_labels: Array[Label] = []
var _banner: Label
var _action_bar: HBoxContainer
var _result_box: PanelContainer

var _views: Dictionary = {}          # key -> TileView
var _flying: Dictionary = {}         # tile id -> true（本次将以弧线飞行的牌）
var _discard_origin: Dictionary = {} # tile id -> Vector2（对家/左右家出牌的起点）
var _pool: Array = []                # 本局出过的牌（按先后），用于合并牌河
var _mode: String = ""               # "" | "discard" | "option" | "missing" | "wait"
var _allowed: Array = []
var _selected_tile: Tile = null
var _last_discard: Tile = null
var _cur_turn: int = -1
var _scores_before: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_static_ui()
	_layout_static()
	resized.connect(_on_resized)


func start_match(rule_id: String, speed: float) -> void:
	_speed = speed
	rule = MahjongRule.create(rule_id)
	_players = []
	_human = HumanPlayer.new(0, HUMAN_NAME)
	_players.append(_human)
	var names := NameGen.pick(MahjongRule.PLAYER_COUNT - 1)
	for s in range(1, MahjongRule.PLAYER_COUNT):
		_players.append(AIPlayer.new(s, names[s - 1], 0.35 + randf() * 0.5))
	_human.awaiting.connect(_on_human_awaiting)
	_match = MatchController.new(rule, _players)
	_title.text = rule.get_display_name()
	_run_match.call_deferred()


# ============================ 对局循环 ============================

func _run_match() -> void:
	while not _match.is_over():
		_round = _match.start_next_round()
		_round.pace_time = _speed
		_reveal = false
		_connect_round(_round)
		_scores_before = _players.map(func(p: Player) -> int: return p.score)
		_flash_banner("第 %d 局" % _match.round_index, CREAM)
		_refresh()
		await _round.play()
		_mode = ""
		_action_bar_clear()
		_refresh()
		await _show_round_result()
	await _show_final_result()


func _connect_round(r: RoundController) -> void:
	r.round_started.connect(func(_d: int) -> void:
		_last_discard = null
		_pool.clear()
		_reveal = false
		_refresh())
	r.tile_drawn.connect(func(seat: int, t: Tile) -> void:
		_cur_turn = seat
		if seat == 0:
			_sfx.play("draw", 1.0, -6.0)
		_refresh())
	r.tile_discarded.connect(func(seat: int, t: Tile) -> void:
		_last_discard = t
		_pool.append(t)
		_flying[t.get_instance_id()] = true
		if seat != 0:
			_discard_origin[t.get_instance_id()] = _seat_origin(seat)
		_sfx.play("whoosh", 0.95 + randf() * 0.15, -4.0)
		_refresh())
	r.meld_made.connect(func(seat: int, m: Meld) -> void:
		var center := _seat_origin(seat)
		if m.is_kong():
			_sfx.play("kong", 1.0, 0.0)
			_shake(10.0)
		else:
			_sfx.play("claim", 1.0, -2.0)
		_burst_at(center, GOLD, 1.4)
		_bubble(center + Vector2(0, -60), _meld_call_name_cn(m), GOLD)
		_call_stamp(_meld_call_name_cn(m), GOLD)
		_sfx.speak_call(_meld_call_name(m))
		_refresh())
	r.message.connect(func(seat: int, text: String) -> void:
		if seat >= 0:
			_flash_banner("%s · %s" % [_players[seat].display_name, text], GOLD)
		else:
			_flash_banner(text, CREAM)
		_refresh_labels())
	r.player_won.connect(func(seat: int, _res: WinResult, self_drawn: bool) -> void:
		_celebrate(seat, self_drawn))
	r.transfers_applied.connect(func(_tr: Array) -> void:
		_refresh_labels())
	r.turn_changed.connect(func(seat: int) -> void:
		_cur_turn = seat
		_refresh_labels())
	r.round_finished.connect(func(_draw: bool) -> void:
		_cur_turn = -1
		_reveal = true   # 本局结束：翻开所有 AI 的手牌
		_refresh()
		_refresh_labels())


# ============================ 人类输入 ============================

func _on_human_awaiting(kind: String, payload: Variant) -> void:
	match kind:
		"missing":
			_mode = "missing"
			_action_bar_prompt("请选择定缺花色（缺门牌打光前不能胡）")
			for s in 3:
				var b := _make_button(Tile.SUIT_CHARS[s], SUIT_COLORS[s].darkened(0.25), 120)
				b.pressed.connect(func() -> void: _choose(s))
				_action_bar.add_child(b)
		"discard":
			_mode = "discard"
			_allowed = payload
			_selected_tile = null
			_action_bar_prompt("轮到你出牌：点选一张牌，再点一次打出")
		"option":
			_mode = "option"
			_show_options(payload["options"], payload["phase"])
	_refresh()


func _show_options(options: Array, phase: String) -> void:
	_action_bar_prompt("自摸阶段：胡 / 杠" if phase == "self" else "要碰、杠或胡吗？")
	for opt in options:
		var color := Color("d32f2f") if opt["action"] == "hu" else Color("f9a825")
		var b := _make_button(_option_text(opt, phase), color, 150)
		b.pressed.connect(func() -> void: _choose(opt))
		_action_bar.add_child(b)
	var pass_btn := _make_button("过", Color("546e7a"), 120)
	pass_btn.pressed.connect(func() -> void: _choose(null))
	_action_bar.add_child(pass_btn)


func _choose(value: Variant) -> void:
	_action_bar_clear()
	_mode = "wait"
	_human.submit(value)
	_refresh()


func _on_tile_tapped(view: TileView) -> void:
	if _mode != "discard" or view.tile == null:
		return
	if not _allowed.has(view.tile):
		_flash_banner("这张牌现在不能打", Color("ff8a80"))
		_shake(3.0)
		return
	# 点击反馈：轻微下压
	var tw := view.create_tween()
	tw.tween_property(view, "scale", Vector2(0.92, 0.92), 0.05)
	tw.tween_property(view, "scale", Vector2(1.0, 1.0), 0.08)
	if _selected_tile == view.tile:
		var t := view.tile
		_selected_tile = null
		_mode = "wait"
		_action_bar_clear()
		_human.submit(t)
	else:
		_selected_tile = view.tile
		_sfx.play("select", 1.0, -3.0)
		Vfx.sparkle(_fx_layer, view.position + view.size * 0.5, GOLD, 16)
	_refresh()


func _option_text(opt: Dictionary, phase: String) -> String:
	match opt["action"]:
		"hu":
			return "自摸" if phase == "self" else "胡"
		"pung":
			return "碰"
		"kong":
			return "杠"
		"kong_concealed":
			return "暗杠"
		"kong_added":
			return "补杠"
	return "?"


# ============================ 布局与刷新 ============================

func _refresh() -> void:
	if _round == null or _tiles_layer == null:
		return
	_apply_entries(_build_entries())
	_refresh_labels()


## 计算每张牌的目标位置（屏幕坐标）。返回 Array[Dictionary]
func _build_entries() -> Array:
	var out: Array = []
	var w := size.x
	var h := size.y
	var hw := minf(124.0, (w - 240.0) / 14.2)
	var hh := hw * 1.42
	var hand_top := h - hh - 20.0

	# ---- 自己：手牌（底边，最长边） ----
	var hand := _human.hand
	var n := hand.concealed.size()
	var gap := hw * 0.35 if n % 3 == 2 else 0.0
	var total := hw * n + gap
	var x := (w - total) * 0.5
	for i in n:
		var t: Tile = hand.concealed[i]
		if i == n - 1:
			x += gap
		var lifted := _selected_tile == t
		var center := Vector2(x + hw * 0.5, hand_top + hh * 0.5 - (42.0 if lifted else 0.0))
		var glow := Color(0, 0, 0, 0)
		var dim := false
		if _mode == "discard":
			if _allowed.has(t):
				glow = Color(1.0, 0.85, 0.3, 0.9 if lifted else 0.45)
			else:
				dim = true
		out.append(_entry(t, true, center, Vector2(hw, hh), 0.0, glow, dim, _deck_pos()))
		x += hw
	# 手牌上方：副露
	var mw := hw * 0.62
	var mh := mw * 1.42
	var mx := (w - total) * 0.5
	var my := hand_top - mh * 0.5 - 16.0
	for m in hand.melds:
		for t in m.tiles:
			out.append(_entry(t, true, Vector2(mx + mw * 0.5, my), Vector2(mw, mh), 0.0, Color(0, 0, 0, 0), false, _seat_origin(0)))
			mx += mw * 0.95
		mx += 14.0

	# ---- 四家合并牌河（按出牌先后平铺，居中展示） ----
	_pool_entries(out)

	# ---- 对家：副露 + 背面 ----
	var sw := hw * 0.44
	var sh := sw * 1.42
	var top_p := _players[2] as Player
	var items := _seat_items(top_p, 2)
	var step := sw * 0.98
	var x0 := (w - step * items.size()) * 0.5
	for i in items.size():
		var it: Array = items[i]
		out.append(_entry(it[0], it[1], Vector2(x0 + step * i + sw * 0.5, 124.0), Vector2(sw, sh), 0.0, Color(0, 0, 0, 0), false, Vector2(w * 0.5, 124.0), it[2]))

	# ---- 左家 / 右家：竖向 ----
	_side(out, _players[3] as Player, 3, true, sw, sh)
	_side(out, _players[1] as Player, 1, false, sw, sh)
	return out


func _side(out: Array, p: Player, seat: int, is_left: bool, sw: float, sh: float) -> void:
	var w := size.x
	var items := _seat_items(p, seat)
	var rot := PI / 2.0 if is_left else -PI / 2.0
	var cx := 30.0 + sh * 0.5 if is_left else w - 30.0 - sh * 0.5
	var y := 156.0
	for it in items:
		out.append(_entry(it[0], it[1], Vector2(cx, y + sw * 0.5), Vector2(sw, sh), rot, Color(0, 0, 0, 0), false, _seat_origin(seat), it[2]))
		y += sw * 0.96


## 副露 + 背面牌序列。返回 [tile|null, face_down, key]
func _seat_items(p: Player, seat: int) -> Array:
	var items: Array = []
	for m in p.hand.melds:
		for t in m.tiles:
			items.append([t, true, t.get_instance_id()])
	if _reveal:
		var shown := p.hand.concealed.duplicate()
		shown.sort_custom(func(a: Tile, b: Tile) -> bool: return a.kind() < b.kind())
		for t in shown:
			items.append([t, true, t.get_instance_id()])
		return items
	for i in p.hand.concealed.size():
		items.append([null, false, "b%d_%d" % [seat, i]])
	return items


## 合并牌河：所有人的牌按出牌先后排列（每行 POOL_COLS 张），居中展示
const POOL_COLS := 18
const POOL_CELL := Vector2(62.0, 84.0)
const POOL_TILE := Vector2(56.0, 76.0)


## 当前仍在牌河中的牌（按出牌顺序；被吃碰杠走的牌不再显示）
func _pool_tiles() -> Array:
	var out: Array = []
	for t in _pool:
		for p in _players:
			if (p as Player).discards.has(t):
				out.append(t)
				break
	return out


func _pool_entries(out: Array) -> void:
	var tiles := _pool_tiles()
	var ox := (size.x - POOL_COLS * POOL_CELL.x) * 0.5
	var oy := 168.0
	for i in tiles.size():
		var r := i / POOL_COLS
		var c := i % POOL_COLS
		var center := Vector2(ox + c * POOL_CELL.x + POOL_CELL.x * 0.5, oy + r * POOL_CELL.y + POOL_CELL.y * 0.5)
		var t: Tile = tiles[i]
		var glow := Color(1.0, 0.85, 0.3, 0.6) if t == _last_discard else Color(0, 0, 0, 0)
		out.append(_entry(t, true, center, POOL_TILE, 0.0, glow, false, center))


func _entry(t: Tile, face: bool, center: Vector2, sz: Vector2, rot: float, glow: Color, dim: bool, spawn: Vector2, key: Variant = null) -> Dictionary:
	var k: Variant = key if key != null else t.get_instance_id()
	return {"key": k, "tile": t, "face": face, "center": center, "size": sz, "rot": rot,
		"glow": glow, "dim": dim, "spawn": spawn}


func _seat_origin(seat: int) -> Vector2:
	var w := size.x
	var h := size.y
	match seat:
		0: return Vector2(w * 0.5, h - 120.0)
		2: return Vector2(w * 0.5, 110.0)
		3: return Vector2(60.0, 400.0)
		_: return Vector2(w - 60.0, 400.0)


func _deck_pos() -> Vector2:
	return Vector2(size.x * 0.5 - 380.0, 300.0)


## 把目标布局应用到视图：新牌从出生点弹出，已有牌补间移动，消失的牌淡出
func _apply_entries(entries: Array) -> void:
	var seen := {}
	for e in entries:
		var key: Variant = e["key"]
		seen[key] = true
		var t: Tile = e["tile"]
		var sz: Vector2 = e["size"]
		var v: TileView = _views.get(key)
		var is_new := v == null
		if is_new:
			v = TileView.new()
			v.size = sz
			v.pivot_offset = sz * 0.5
			v.mouse_filter = Control.MOUSE_FILTER_STOP if e["face"] and not e["tile"] == null else Control.MOUSE_FILTER_IGNORE
			v.tapped.connect(_on_tile_tapped)
			_tiles_layer.add_child(v)
			_views[key] = v
			var origin: Vector2 = e["center"]
			if t != null and _discard_origin.has(t.get_instance_id()):
				origin = _discard_origin[t.get_instance_id()]
			elif t != null and not _flying.has(t.get_instance_id()):
				origin = e["spawn"]
			v.position = origin - sz * 0.5
			v.scale = Vector2(0.3, 0.3)
			v.modulate.a = 0.0
		v.setup(t, not e["face"])
		v.size = sz
		v.pivot_offset = sz * 0.5
		v.set_glow(e["glow"])
		var fid := t.get_instance_id() if t != null else -1
		if t != null and _flying.has(fid):
			_fly_discard(v, e, fid)
		else:
			_move(v, e, is_new)
	for key in _views.keys():
		if not seen.has(key):
			_retire(key)


func _move(v: TileView, e: Dictionary, is_new: bool) -> void:
	if v.has_meta("flying") and v.get_meta("flying"):
		return  # 正在飞行，等落地后再同步位置（否则会打断落地效果）
	var center: Vector2 = e["center"]
	var sz: Vector2 = e["size"]
	var lift := -42.0 if (e["tile"] != null and _selected_tile == e["tile"]) else 0.0
	var target := center - sz * 0.5 + Vector2(0, lift)
	var tw := _tween_of(v)
	tw.set_parallel(true)
	var dur := 0.42 if is_new else 0.34
	tw.tween_property(v, "position", target, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(v, "rotation", e["rot"], dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(v, "scale", Vector2(1.04, 1.04) if lift < 0.0 else Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(v, "modulate", Color(0.6, 0.6, 0.6, 1) if e["dim"] else Color.WHITE, 0.2)
	tw.tween_property(v, "modulate:a", 1.0, 0.25)


## 弧线飞行：从当前位置飞到牌河，落地时播放冲击效果
func _fly_discard(v: TileView, e: Dictionary, fid: int) -> void:
	_flying.erase(fid)
	_discard_origin.erase(fid)
	var t: Tile = e["tile"]
	var target: Vector2 = e["center"]
	var start := v.position + v.size * 0.5
	var ctrl := (start + target) * 0.5 + Vector2(0, -220.0)
	v.set_meta("flying", true)
	var tw := _tween_of(v)
	tw.tween_method(_arc_step.bind(v, start, ctrl, target), 0.0, 1.0, 0.46).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(v, "rotation", e["rot"], 0.46)
	tw.parallel().tween_property(v, "modulate", Color.WHITE, 0.2)
	tw.tween_callback(_on_discard_land.bind(t, target, v))


func _arc_step(t: float, v: TileView, s: Vector2, c: Vector2, e: Vector2) -> void:
	var p := s.lerp(c, t).lerp(c.lerp(e, t), t)
	v.position = p - v.size * 0.5
	v.scale = Vector2.ONE * (1.0 + 0.3 * sin(PI * t))


func _on_discard_land(t: Tile, pos: Vector2, v: TileView) -> void:
	v.set_meta("flying", false)
	_refresh()  # 同步到牌河的最终位置
	_bubble(pos + Vector2(0, -52), _tile_name(t), CREAM)
	_sfx.play_tile_impact(t.suit, t.rank)
	_sfx.play("shimmer", 1.0, -14.0)
	_burst_at(pos, SUIT_COLORS[t.suit], 0.9)
	Vfx.sparkle(_fx_layer, pos, SUIT_COLORS[t.suit].lightened(0.3), 12)
	_shake(5.0)
	# 落地后稍等一下再报牌名，让撞击声先出现
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(_sfx.speak_tile.bind(t.suit, t.rank))


func _retire(key: Variant) -> void:
	var v: TileView = _views[key]
	_views.erase(key)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := v.create_tween().set_parallel(true)
	tw.tween_property(v, "modulate:a", 0.0, 0.3)
	tw.tween_property(v, "scale", Vector2(0.4, 0.4), 0.3)
	tw.chain().tween_callback(v.queue_free)


func _tween_of(v: Control) -> Tween:
	if v.has_meta("tw"):
		var old: Tween = v.get_meta("tw")
		if old != null and old.is_valid():
			old.kill()
	var tw := v.create_tween()
	v.set_meta("tw", tw)
	return tw


func _refresh_labels() -> void:
	if _round == null:
		return
	for i in _players.size():
		var p := _players[i] as Player
		var l := _score_labels[i]
		l.text = "%s  %+d" % [p.display_name, p.score] if p.score != 0 else "%s  0" % p.display_name
		l.add_theme_color_override("font_color", GOLD if i == _cur_turn else CREAM)
		var chip := _chips[i]
		chip.visible = p.missing_suit >= 0
		if p.missing_suit >= 0:
			(chip.get_child(0) as Label).text = "缺" + Tile.SUIT_CHARS[p.missing_suit]
			chip.add_theme_stylebox_override("panel", _chip_style(SUIT_COLORS[p.missing_suit]))
	_info.text = "第 %d/%d 局 · 庄家 %s · 余牌 %d" % [
		_match.round_index, _match.total_rounds, _players[_round.dealer].display_name,
		_round.wall.remaining()]


# ============================ 特效 ============================

func _burst_at(pos: Vector2, color: Color, strength: float) -> void:
	Fx.burst(_fx_layer, pos, color, strength)


func _shake(amount: float) -> void:
	var tw := _world.create_tween()
	for i in 6:
		tw.tween_property(_world, "position", Vector2(randf_range(-amount, amount), randf_range(-amount, amount)), 0.03)
	tw.tween_property(_world, "position", Vector2.ZERO, 0.04)


## 胡牌庆祝：金色闪光 + 多点烟花 + 震屏 + 大字
func _tile_name(t: Tile) -> String:
	return Tile.NUMBER_NAMES[t.rank - 1] + Tile.SUIT_CHARS[t.suit]


func _meld_call_name_cn(m: Meld) -> String:
	match m.type:
		Meld.Type.PUNG:
			return "碰"
		Meld.Type.KONG_OPEN:
			return "杠"
		Meld.Type.KONG_CONCEALED:
			return "暗杠"
		_:
			return "补杠"


## 牌旁边弹出的文字气泡（报牌/叫牌的可视化提示）
func _bubble(pos: Vector2, text: String, color: Color) -> void:
	var l := Label.new()
	UiFont.apply_title(l)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 40)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size = Vector2(180, 60)
	l.position = pos - l.size * 0.5
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(0.4, 0.4)
	_fx_layer.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.35)
	tw.tween_callback(l.queue_free)


func _meld_call_name(m: Meld) -> String:
	match m.type:
		Meld.Type.PUNG:
			return "peng"
		Meld.Type.KONG_OPEN:
			return "gang"
		Meld.Type.KONG_CONCEALED:
			return "angang"
		_:
			return "buggang"


func _celebrate(seat: int, self_drawn: bool) -> void:
	_sfx.play("hu", 1.0, 0.0)
	var call := "zimo" if self_drawn else "hu"
	var vt := create_tween()
	vt.tween_interval(0.35)
	vt.tween_callback(_sfx.speak_call.bind(call))
	_flash_banner("%s %s！" % [_players[seat].display_name, "自摸" if self_drawn else "胡"], Color("ff8a80"))
	_call_stamp("自摸" if self_drawn else "胡", Color("ff8a80"))
	Vfx.confetti(_fx_layer, size.x)
	_overlay.color = Color(1.0, 0.85, 0.3, 0.0)
	var tw := _overlay.create_tween()
	tw.tween_property(_overlay, "color:a", 0.35, 0.12)
	tw.tween_property(_overlay, "color:a", 0.0, 0.8)
	_shake(10.0)
	var fw := _overlay.create_tween()
	var w := size.x
	var h := size.y
	for i in 7:
		var p := Vector2(randf_range(w * 0.15, w * 0.85), randf_range(h * 0.12, h * 0.6))
		var col: Color = [GOLD, Color("ff7043"), Color("64b5f6"), Color("81c784")][i % 4]
		fw.tween_callback(_burst_at.bind(p, col, 1.5))
		fw.tween_interval(0.18)


## 叫牌大字：碰 / 杠 / 胡 / 自摸 时在屏幕中央砸下，并放射光线
func _call_stamp(text: String, color: Color) -> void:
	var w := size.x
	var h := size.y
	var center := Vector2(w * 0.5, h * 0.36)
	Vfx.rays(_fx_layer, center, color, 360.0)
	var l := Label.new()
	UiFont.apply_title(l)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 170)
	l.add_theme_color_override("font_color", color.lightened(0.25))
	l.add_theme_color_override("font_outline_color", Color(0.25, 0.05, 0.0, 0.95))
	l.add_theme_constant_override("outline_size", 22)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size = Vector2(420, 260)
	l.position = center - l.size * 0.5
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(2.6, 2.6)
	l.modulate.a = 0.0
	_fx_layer.add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 1.0, 0.12)
	tw.chain().tween_interval(0.7)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.4)
	tw.chain().tween_callback(l.queue_free)
	_shake(8.0)


func _flash_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.modulate.a = 1.0
	_banner.scale = Vector2(0.5, 0.5)
	var tw := create_tween()
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.9)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.4)


# ============================ 结算 ============================

func _show_round_result() -> void:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(760, 0)
	box.add_theme_stylebox_override("panel", _panel_style(CREAM, 30))
	add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	box.add_child(v)

	var title := Label.new()
	title.text = "流局" if _round.draw_game else "本局结束"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFont.apply_title(title)
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color("5d4037"))
	v.add_child(title)

	for p in _players:
		var pl := p as Player
		if pl.win_result != null:
			var fl := Label.new()
			fl.text = "%s：%s" % [pl.display_name, pl.win_result.summary()]
			fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			fl.add_theme_font_size_override("font_size", 24)
			fl.add_theme_color_override("font_color", Color("b71c1c"))
			v.add_child(fl)
	v.add_child(HSeparator.new())
	for p in _players:
		var pl := p as Player
		var delta := pl.score - int(_scores_before[pl.seat])
		var row := Label.new()
		row.text = "%s    %+d    （累计 %d）" % [pl.display_name, delta, pl.score]
		row.add_theme_font_size_override("font_size", 30)
		row.add_theme_color_override("font_color", Color("2e7d32") if delta >= 0 else Color("c62828"))
		v.add_child(row)
	var btn := _make_button("查看总结" if _match.is_over() else "下一局", Color("2e7d32"), 320)
	btn.pressed.connect(func() -> void: _continue_pressed.emit())
	v.add_child(btn)
	await _center_box(box)
	_result_box = box
	await _continue_pressed
	box.queue_free()
	_result_box = null


func _show_final_result() -> void:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(700, 0)
	box.add_theme_stylebox_override("panel", _panel_style(CREAM, 30))
	add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	box.add_child(v)
	var title := Label.new()
	title.text = "比赛结束"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFont.apply_title(title)
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Color("5d4037"))
	v.add_child(title)
	var rank := 1
	for p in _match.ranking():
		var pl := p as Player
		var row := Label.new()
		row.text = "第 %d 名    %s    %d 分" % [rank, pl.display_name, pl.score]
		row.add_theme_font_size_override("font_size", 36)
		row.add_theme_color_override("font_color", Color("5d4037"))
		v.add_child(row)
		rank += 1
	var again := _make_button("返回菜单", Color("2e7d32"), 320)
	again.pressed.connect(func() -> void: exit_requested.emit())
	v.add_child(again)
	await _center_box(box)
	await again.pressed


func _center_box(box: Control) -> void:
	await get_tree().process_frame
	box.position = (size - box.size) * 0.5


func _panel_style(bg: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 18
	return sb


# ============================ 界面搭建 ============================

func _build_static_ui() -> void:
	var vignette := TextureRect.new()
	vignette.texture = _vignette_texture()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	_world = Control.new()
	_world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_world)
	_tiles_layer = Control.new()
	_tiles_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tiles_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(_tiles_layer)
	_fx_layer = Control.new()
	_fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.add_child(_fx_layer)
	_ambient = Vfx.ambient()
	_world.add_child(_ambient)
	_world.move_child(_ambient, 0)

	var top := ColorRect.new()
	top.color = Color(0, 0, 0, 0.3)
	top.anchor_right = 1.0
	top.offset_bottom = 60.0
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)

	_title = Label.new()
	UiFont.apply_title(_title)
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", CREAM)
	add_child(_title)

	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 24)
	_info.add_theme_color_override("font_color", Color("c8e6c9"))
	_info.add_theme_font_size_override("font_size", 22)
	add_child(_info)

	for i in MahjongRule.PLAYER_COUNT:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 26)
		l.add_theme_color_override("font_color", CREAM)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		l.add_theme_constant_override("outline_size", 6)
		add_child(l)
		_score_labels.append(l)
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cl := Label.new()
		cl.add_theme_font_size_override("font_size", 22)
		cl.add_theme_color_override("font_color", Color.WHITE)
		chip.add_child(cl)
		add_child(chip)
		_chips.append(chip)

	var menu_btn := _make_button("菜单", Color("455a64"), 110)
	menu_btn.name = "MenuButton"
	menu_btn.add_theme_font_size_override("font_size", 26)
	menu_btn.pressed.connect(func() -> void: exit_requested.emit())
	add_child(menu_btn)

	_banner = Label.new()
	UiFont.apply_title(_banner)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 72)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_banner.add_theme_constant_override("outline_size", 14)
	_banner.modulate.a = 0.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)

	_action_bar = HBoxContainer.new()
	_action_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_bar.add_theme_constant_override("separation", 14)
	add_child(_action_bar)

	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(1, 0.85, 0.3, 0.0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	_sfx = Sfx.new()
	add_child(_sfx)


func _layout_static() -> void:
	var w := size.x
	var h := size.y
	_title.position = Vector2(24, 14)
	_info.position = Vector2(24, 46)
	_info.size = Vector2(700, 30)
	var menu := find_child("MenuButton", false, false) as Control
	if menu:
		menu.position = Vector2(w - 130, 6)
	for i in _score_labels.size():
		_score_labels[i].position = Vector2(w * 0.5 - 470 + i * 240, 14)
		_chips[i].position = Vector2(w * 0.5 - 470 + i * 240, 50)
	_ambient.position = Vector2(w * 0.5, h * 0.5)
	_ambient.emission_rect_extents = Vector2(w * 0.5, h * 0.5)
	_banner.position = Vector2(0, h * 0.42)
	_banner.size = Vector2(w, 110)
	_banner.pivot_offset = Vector2(w * 0.5, 55)
	_action_bar.position = Vector2(w * 0.5 - 420, 640)
	_action_bar.size = Vector2(840, 90)


func _on_resized() -> void:
	queue_redraw()
	_layout_static()
	if _round != null:
		_refresh()


func _chip_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.1)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sb.border_color = Color(1, 1, 1, 0.5)
	sb.set_border_width_all(2)
	return sb


func _action_bar_clear() -> void:
	for c in _action_bar.get_children():
		_action_bar.remove_child(c)
		c.queue_free()


func _action_bar_prompt(text: String) -> void:
	_action_bar_clear()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", GOLD)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 8)
	_action_bar.add_child(l)


func _make_button(text: String, color: Color, min_w: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 80)
	b.add_theme_font_size_override("font_size", 34)
	b.add_theme_color_override("font_color", Color.WHITE)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color.darkened(0.15) if state == "pressed" else color
		sb.set_corner_radius_all(20)
		sb.content_margin_left = 20
		sb.content_margin_right = 20
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 4)
		b.add_theme_stylebox_override(state, sb)
	return b


func _vignette_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.0, 0.0, 0.0))
	g.set_color(1, Color(0.0, 0.0, 0.0, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 512
	tex.height = 512
	return tex


func _draw() -> void:
	var w := size.x
	var h := size.y
	# 1) 深色木质桌框
	draw_rect(Rect2(Vector2.ZERO, size), Color("2a170c"))
	for i in 60:
		var y := h * float(i) / 60.0
		draw_line(Vector2(0, y), Vector2(w, y), Color(0.45, 0.28, 0.14, 0.18 if i % 2 == 0 else 0.07), 2.0)
	draw_rect(Rect2(0, 0, w, 10), Color(0.8, 0.6, 0.35, 0.25))
	draw_rect(Rect2(0, h - 10, w, 10), Color(0, 0, 0, 0.45))
	# 2) 毡布面：纵向渐变 + 中心光晕 + 细微纹理
	var m := 26.0
	var felt := Rect2(m, m, w - m * 2, h - m * 2)
	var steps := 60
	for i in steps:
		var t := float(i) / steps
		draw_rect(Rect2(felt.position.x, felt.position.y + felt.size.y * t, felt.size.x, felt.size.y / steps + 1),
			Color("17653f").lerp(Color("0b3d27"), t))
	var center := Vector2(w * 0.5, h * 0.5)
	for k in 14:
		draw_circle(center, (w * 0.62) - k * 52.0, Color(0.45, 0.95, 0.65, 0.018))
	for k in 260:
		var px := felt.position.x + fmod(float(k) * 97.31, felt.size.x)
		var py := felt.position.y + fmod(float(k) * 53.17, felt.size.y)
		draw_rect(Rect2(px, py, 2, 2), Color(1, 1, 1, 0.03))
	# 3) 金色描边 + 四角铆钉
	draw_rect(felt.grow(-10), Color(0.95, 0.8, 0.45, 0.45), false, 3.0)
	draw_rect(felt.grow(-16), Color(0.95, 0.8, 0.45, 0.15), false, 1.0)
	for c in [felt.position, felt.position + Vector2(felt.size.x, 0), felt.position + Vector2(0, felt.size.y), felt.end]:
		draw_circle(c, 9.0, Color("e8c170"))
		draw_circle(c, 4.0, Color("2a170c"))
	# 4) 中心水印
	var font := UiFont.title()
	var wm := "血 战 到 底"
	var fs := 56
	var wm_w := font.get_string_size(wm, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string(font, Vector2(center.x - wm_w * 0.5, h * 0.5 + 14), wm, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 0.88, 0.5, 0.12))
	draw_arc(center + Vector2(0, -6), 170.0, PI * 1.1, PI * 1.9, 80, Color(1, 0.85, 0.45, 0.10), 2.0, true)
