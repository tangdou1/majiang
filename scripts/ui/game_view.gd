class_name GameView
extends Control
## 横屏牌桌界面（1920×1080 设计）。
## - 自己的手牌沿屏幕底边（最长边）排列，对家在上，左右家在两侧
## - 所有牌都是持久化视图（按 Tile 实例跟踪），位置变化用补间动画过渡
## - 出牌：牌沿弧线飞向牌河，落地时冲击波 + 粒子 + 震屏，并播放对应花色的撞击音
## 界面只负责展示与收集输入，规则全部在 core 层。

signal exit_requested
signal restart_requested(rule_id: String, pace: float)
signal _continue_pressed

const HUMAN_NAME := "你"
## 颜色一律来自 UiTheme 设计令牌，界面之间不再各自写十六进制
const GOLD := UiTheme.GOLD
const CREAM := UiTheme.CREAM
## 仅在 _tiles_layer 内重排兄弟节点，同时统一绘制和点击顺序。
## 不提升 z_index，避免手牌/飞牌越过特效、暂停和结算界面。
enum TileLayer { TABLE, MELD, HAND, DRAWN, SELECTED, FLYING }
const HAND_TILE_GAP := 4.0
const HAND_SELECTION_LIFT := 42.0
const HAND_DRAWN_LIFT := 10.0
const SEAT_LABEL_WIDTH := 250.0
## 三门花色（万 / 筒 / 条）。用 static var 而非 const：跨类常量数组的编译期求值不够稳妥
static var SUIT_COLORS: Array = UiTheme.SUIT

var rule: MahjongRule
var _match: MatchController
var _round: RoundController
var _players: Array = []
var _human: HumanPlayer
var _sfx: Sfx
var _speed: float = 1.0
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
var _turn_indicator: TurnIndicator
var _shake_tween: Tween
var _flash_tween: Tween
var _fireworks_tween: Tween
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

var _rule_id: String = "sichuan"
var _drawn_tile: Tile = null        # 自己刚摸到的牌（单独摆放并高亮）
var _tile_seat: Dictionary = {}     # tile id -> 出牌者座位（报牌时区分音色）
var _payments: Array = []           # 本局每一笔收付（带 reason）
var _hint: Label                    # 听牌提示
var _hint_key: String = ""          # 手牌状态指纹：没变化就不重算听牌（省手机 CPU）
var _pause_layer: Control
var _aborted: bool = false          # 退出/重开后，让所有协程干净地收尾
var _continue_flag: bool = false    # 结算面板的“继续”信号：先置位再 emit，避免错过


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 暂停时界面仍然响应（真正的流程冻结靠暂停中的计时器与 await）
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_static_ui()
	_layout_static()
	_apply_effects_setting()
	resized.connect(_on_resized)


func start_match(rule_id: String, speed: float) -> void:
	_speed = speed
	_rule_id = rule_id
	_aborted = false
	_cur_turn = -1
	_drawn_tile = null
	_payments.clear()
	_tile_seat.clear()
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
		if _aborted:
			return
		_round = _match.start_next_round()
		_round.pace_time = _speed
		_reveal = false
		_connect_round(_round)
		_scores_before = _players.map(func(p: Player) -> int: return p.score)
		_flash_banner("第 %d 局" % _match.round_index, CREAM)
		_refresh()
		await _round.play()
		if _aborted:
			return
		_mode = ""
		_action_bar_clear()
		_refresh()
		await _show_round_result()
		if _aborted:
			return
	await _show_final_result()


func _connect_round(r: RoundController) -> void:
	r.round_started.connect(func(_d: int) -> void:
		_cur_turn = -1
		_last_discard = null
		_pool.clear()
		_reveal = false
		_drawn_tile = null
		_payments.clear()
		_tile_seat.clear()
		_refresh())
	r.tile_drawn.connect(func(seat: int, t: Tile) -> void:
		_cur_turn = seat
		if seat == 0:
			_drawn_tile = t
			_sfx.play("draw", 1.0, -6.0)
		_refresh())
	r.tile_discarded.connect(func(seat: int, t: Tile) -> void:
		_last_discard = t
		_pool.append(t)
		_tile_seat[t.get_instance_id()] = seat
		if seat == 0:
			_drawn_tile = null
		_flying[t.get_instance_id()] = true
		if seat != 0:
			_discard_origin[t.get_instance_id()] = _seat_origin(seat)
		_sfx.play("whoosh", 0.95 + randf() * 0.15, -4.0)
		_refresh())
	r.meld_made.connect(func(seat: int, m: Meld) -> void:
		_cur_turn = seat
		var center := _seat_origin(seat)
		if m.is_kong():
			_sfx.play("kong", 1.0, 0.0)
			_shake(10.0)
		else:
			_sfx.play("claim", 1.0, -2.0)
		_burst_at(center, GOLD, 1.4)
		_bubble(center + Vector2(0, -60), _meld_call_name_cn(m), GOLD)
		_call_stamp(_meld_call_name_cn(m), GOLD)
		_sfx.speak_call(_meld_call_name(m), seat)
		if m.from_seat >= 0 and m.from_seat != seat and not m.tiles.is_empty():
			var src := _players[m.from_seat] as Player
			var taken := m.tiles[m.tiles.size() - 1]
			_bubble(_seat_origin(m.from_seat) + Vector2(0, -46),
				"来自%s的%s" % [src.display_name, _tile_name(taken)], CREAM, 26)
		_drawn_tile = null
		_refresh())
	r.message.connect(func(seat: int, text: String) -> void:
		if seat >= 0:
			_flash_banner("%s · %s" % [_players[seat].display_name, text], GOLD)
		else:
			_flash_banner(text, CREAM)
		_refresh_labels())
	r.player_won.connect(func(seat: int, _res: WinResult, self_drawn: bool) -> void:
		_celebrate(seat, self_drawn)
		_refresh_labels())
	r.transfers_applied.connect(func(tr: Array) -> void:
		_payments.append_array(tr)
		_refresh_labels())
	r.turn_changed.connect(func(seat: int) -> void:
		_cur_turn = seat
		_refresh_labels())
	r.round_finished.connect(func(_draw: bool) -> void:
		_cur_turn = -1
		_drawn_tile = null
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
			var prompt := "轮到你出牌：点选一张牌，再点一次打出"
			if not OS.has_feature("mobile"):
				prompt += "（←/→ 选牌，回车打出）"
			_action_bar_prompt(prompt)
		"option":
			_mode = "option"
			_show_options(payload["options"], payload["phase"])
	_refresh()


func _show_options(options: Array, phase: String) -> void:
	_action_bar_prompt("自摸阶段：胡 / 杠" if phase == "self" else "要碰、杠或胡吗？")
	for opt in options:
		var color := UiTheme.ACCENT_RED if opt["action"] == "hu" else UiTheme.WARN
		var b := _make_button(_option_text(opt, phase), color, 150)
		b.pressed.connect(func() -> void: _choose(opt))
		_action_bar.add_child(b)
	var pass_btn := _make_button("过", UiTheme.GREY, 120)
	pass_btn.pressed.connect(func() -> void: _choose(null))
	_action_bar.add_child(pass_btn)


func _choose(value: Variant) -> void:
	_action_bar_clear()
	_mode = "wait"
	_human.submit(value)
	_refresh()


## 桌面端键盘：←/→ 选牌，回车/空格打出，Esc 暂停
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var pause_open := _pause_layer != null and _pause_layer.visible
	if key.keycode == KEY_ESCAPE:
		if pause_open:
			_close_pause()
		else:
			_open_pause()
		get_viewport().set_input_as_handled()
		return
	if pause_open or _mode != "discard":
		return
	match key.keycode:
		KEY_LEFT, KEY_A:
			_cycle_selection(-1)
		KEY_RIGHT, KEY_D:
			_cycle_selection(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_confirm_selection()
		_:
			return
	get_viewport().set_input_as_handled()


func _cycle_selection(step: int) -> void:
	var pool: Array = []
	for c in _ordered_hand():
		if _allowed.has(c):
			pool.append(c)
	if pool.is_empty():
		return
	var idx := pool.find(_selected_tile)
	idx = 0 if idx < 0 else posmod(idx + step, pool.size())
	_selected_tile = pool[idx]
	_sfx.play("select", 1.0, -3.0)
	_refresh()


func _confirm_selection() -> void:
	if _selected_tile == null:
		return
	var t := _selected_tile
	_selected_tile = null
	_mode = "wait"
	_action_bar_clear()
	_human.submit(t)
	_refresh()


func _on_tile_tapped(view: TileView) -> void:
	if _mode != "discard" or view.tile == null or not _human.hand.concealed.has(view.tile):
		return
	if not _allowed.has(view.tile):
		_flash_banner("这张牌现在不能打", UiTheme.HU)
		_shake(3.0)
		return
	# 点击反馈走独立挤压属性，不与布局/飞牌的 scale 补间争抢。
	var tw := view.create_tween()
	tw.tween_property(view, "squash", Vector2(0.97, 0.97), 0.05)
	tw.tween_property(view, "squash", Vector2.ONE, 0.08)
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


## 自己的手牌显示顺序：正常牌按排序 + 刚摸到的牌放最后
func _ordered_hand() -> Array:
	var out: Array = []
	var drawn := _current_drawn()
	for t in _human.hand.concealed:
		if t != drawn:
			out.append(t)
	if drawn != null:
		out.append(drawn)
	return out


## 刚摸到、且确实还在手上的那张牌（不在“必须打缺门”之外的 14 张状态时不显示）
func _current_drawn() -> Tile:
	if _drawn_tile == null:
		return null
	var hand := _human.hand
	var sets := 4 - hand.melds.size()
	if hand.concealed.size() != sets * 3 + 2:
		return null
	if not hand.concealed.has(_drawn_tile):
		return null
	return _drawn_tile


## 这张牌是谁打出的（报牌时用于区分音色）
func _discard_seat(t: Tile) -> int:
	var id := t.get_instance_id()
	if _tile_seat.has(id):
		return int(_tile_seat[id])
	return 0


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


# ============================ 听牌提示 ============================

## 场上可见的每种牌张数（自己手牌 + 四家牌河 + 别家副露），用来算“还剩几张”
## 注意：绝不能算其他玩家手中的暗牌（否则等于开透视挂且导致剩余牌数计算不符合玩家已知信息）
func _visible_kind_counts() -> PackedInt32Array:
	var c := PackedInt32Array()
	c.resize(WinChecker.KINDS)
	c.fill(0)
	if _human == null:
		return c
	# 1. 玩家自己的全部手牌（暗牌 + 副露）完全可见
	for t in _human.hand.all_tiles():
		c[t.kind()] += 1
	# 2. 四家牌河（已打出的弃牌）全部可见
	for p in _players:
		var pl := p as Player
		for t in pl.discards:
			c[t.kind()] += 1
	# 3. 其他玩家的公开副露（碰、明杠、补杠、暗杠）全部可见
	for p in _players:
		var pl := p as Player
		if pl != _human:
			for m in pl.hand.melds:
				for t in m.tiles:
					c[t.kind()] += 1
	return c


## 听牌张数（扣掉已经现身的牌）
func _waits_total(waits: Array, visible: PackedInt32Array) -> int:
	var total := 0
	for k in waits:
		total += maxi(0, 4 - visible[k])
	return total


## “二万、五万（剩 3 张）”这样的文字；waits 为空时返回空串
func _waits_text(waits: Array, visible: PackedInt32Array) -> String:
	if waits.is_empty():
		return ""
	var names := PackedStringArray()
	var total := 0
	for k in waits:
		var left := maxi(0, 4 - visible[k])
		names.append(Tile.NUMBER_NAMES[k % 9] + Tile.SUIT_CHARS[k / 9])
		total += left
	return "%s（剩 %d 张）" % ["、".join(names), total]


func _waiting_kinds(hand: Hand) -> Array:
	if rule == null or _human == null:
		return []
	# 四川麻将等定缺规则：缺门牌未打光前不能胡牌，因此若手中仍有定缺花色的牌则不能算听牌
	if rule.requires_missing_suit() and _human.missing_suit >= 0:
		for t in hand.all_tiles():
			if t.suit == _human.missing_suit:
				return []
	var waits: Array = rule.waiting_kinds_of(hand)
	if _human.missing_suit >= 0:
		waits = waits.filter(func(k: int) -> bool: return Tile.suit_of_kind(k) != _human.missing_suit)
	return waits


## 打哪张能听牌：优先看当前选中的那张，否则给出剩余张数最多的一种
func _best_discard_hint(hand: Hand, visible: PackedInt32Array) -> String:
	# 1. 如果当前选中了某张可打牌，明确反馈打出该牌的效果
	if _selected_tile != null and hand.concealed.has(_selected_tile) and _allowed.has(_selected_tile):
		var h2 := hand.clone()
		h2.remove(_selected_tile)
		var waits := _waiting_kinds(h2)
		if not waits.is_empty():
			return "打 %s → 听 %s" % [_tile_name(_selected_tile), _waits_text(waits, visible)]
		return "打 %s 不听牌" % _tile_name(_selected_tile)

	# 2. 未选牌时，从可打牌中找听牌剩余张数最多的一种推荐
	var best_text := ""
	var best_total := -1
	var tested_kinds := {}
	for t in _allowed:
		if not hand.concealed.has(t) or tested_kinds.has(t.kind()):
			continue
		tested_kinds[t.kind()] = true
		var h2 := hand.clone()
		h2.remove(t)
		var waits := _waiting_kinds(h2)
		if waits.is_empty():
			continue
		var total := _waits_total(waits, visible)
		var text := "打 %s → 听 %s" % [_tile_name(t), _waits_text(waits, visible)]
		if total > best_total:
			best_total = total
			best_text = text
	return best_text


func _update_hint() -> void:
	if _hint == null or rule == null or _human == null or _round == null:
		return
	var visible := _visible_kind_counts()
	var ids := 0
	for t in _human.hand.concealed:
		ids += t.get_instance_id()
	# key 包含 visible 的哈希值，当别人出牌/副露改变桌面可见牌时能实时更新“剩 X 张”
	var key := "%d|%d|%d|%d|%d|%d|%d" % [hash(_mode), int(_round.round_over),
		_human.hand.concealed.size(), ids,
		_selected_tile.get_instance_id() if _selected_tile != null else 0, int(_human.finished),
		hash(visible)]
	if key == _hint_key:
		return
	_hint_key = key
	var text := ""
	if _human.finished:
		text = "已和牌"
	elif not _round.round_over:
		var hand := _human.hand
		var sets := 4 - hand.melds.size()
		var size := hand.concealed.size()
		if size == sets * 3 + 2 and _mode == "discard":
			text = _best_discard_hint(hand, visible)
		elif size == sets * 3 + 1 and (not rule.requires_missing_suit() or _human.missing_suit >= 0):
			var waits := _waiting_kinds(hand)
			var w := _waits_text(waits, visible)
			if w != "":
				text = "已听牌：" + w
	_hint.text = text
	_hint.visible = text != ""


# ============================ 布局与刷新 ============================

func _refresh() -> void:
	if _round == null or _tiles_layer == null:
		return
	_apply_entries(_build_entries())
	_refresh_labels()


## 桌面安全区：木框(26) 内再留一圈余量。所有牌与文字都必须落在这里面。
## 注：stretch 为 canvas_items + expand，画布只会比 1920x1080 更大（宽或高一侧增长），
## 但纵向牌数会随副露增加（4 杠 + 2 张手牌可达 18 张），竖排仍可能溢出桌外。
const SAFE_INSET := 34.0


func _safe_rect() -> Rect2:
	return Rect2(SAFE_INSET, SAFE_INSET,
		maxf(size.x - SAFE_INSET * 2.0, 240.0),
		maxf(size.y - SAFE_INSET * 2.0, 240.0))


## 把一段横向排列（宽 len、居中于 center_x）夹进安全区
func _clamp_row_start(center_x: float, len: float) -> float:
	var r := _safe_rect()
	var x := center_x - len * 0.5
	return clampf(x, r.position.x, maxf(r.position.x, r.end.x - len))


## 给 14 张手牌、牌间距和摸牌间隔一起预留宽度；静态信息区也使用同一尺寸。
func _hand_tile_width() -> float:
	return minf(124.0, (size.x - 240.0 - HAND_TILE_GAP * 13.0) / 14.34)


## 计算每张牌的目标位置（屏幕坐标）。返回 Array[Dictionary]
func _build_entries() -> Array:
	var out: Array = []
	var w := size.x
	var h := size.y
	var hw := _hand_tile_width()
	var hh := hw * 1.42
	var hand_top := h - hh - 20.0

	# ---- 自己：手牌（底边，最长边）；刚摸到的牌单独摆在最右侧 ----
	var hand := _human.hand
	var drawn := _current_drawn()
	var ordered := _ordered_hand()
	var n := ordered.size()
	var gap := hw * 0.34 if drawn != null else 0.0
	var total := hw * n + HAND_TILE_GAP * maxi(0, n - 1) + gap
	var hand_x := _clamp_row_start(w * 0.5, total)
	var x := hand_x
	for t: Tile in ordered:
		var is_drawn := t == drawn
		if is_drawn:
			x += gap
		var lifted := _mode == "discard" and _selected_tile == t
		var lift := HAND_SELECTION_LIFT if lifted else (HAND_DRAWN_LIFT if is_drawn else 0.0)
		var center := Vector2(x + hw * 0.5, hand_top + hh * 0.5 - lift)
		var dim := _mode == "discard" and not _allowed.has(t)
		var glow := Color(0, 0, 0, 0)
		if not dim:
			if lifted:
				glow = Color(GOLD, 0.95)
			elif is_drawn:
				glow = Color(GOLD, 0.55)
			elif _mode == "discard":
				glow = Color(GOLD, 0.18)
		var layer := TileLayer.SELECTED if lifted else (TileLayer.DRAWN if is_drawn else TileLayer.HAND)
		out.append(_entry(t, true, center, Vector2(hw, hh), 0.0, glow, dim, _deck_pos(), null, layer))
		x += hw + HAND_TILE_GAP
	# 手牌上方：副露
	var mw := hw * 0.62
	var mh := mw * 1.42
	var mx := hand_x
	var my := hand_top - mh * 0.5 - 16.0
	for m in hand.melds:
		for t in m.tiles:
			out.append(_entry(t, true, Vector2(mx + mw * 0.5, my), Vector2(mw, mh), 0.0, Color(0, 0, 0, 0), false, _seat_origin(0), null, TileLayer.MELD))
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
	var x0 := _clamp_row_start(w * 0.5, step * items.size())
	for i in items.size():
		var it: Array = items[i]
		out.append(_entry(it[0], it[1], Vector2(x0 + step * i + sw * 0.5, 124.0), Vector2(sw, sh), 0.0, Color(0, 0, 0, 0), false, Vector2(w * 0.5, 124.0), it[2]))

	# ---- 左家 / 右家：竖向 ----
	_side(out, _players[3] as Player, 3, true, sw, sh)
	_side(out, _players[1] as Player, 1, false, sw, sh)
	return out


func _side(out: Array, p: Player, seat: int, is_left: bool, sw: float, sh: float) -> void:
	var r := _safe_rect()
	var items := _seat_items(p, seat)
	if items.is_empty():
		return
	var rot := PI / 2.0 if is_left else -PI / 2.0
	var cx := r.position.x + sh * 0.5 if is_left else r.end.x - sh * 0.5
	var y := maxf(156.0, r.position.y + sw * 0.5)
	# 竖直方向放不下时（副露多 / 超长屏）压缩间距，保证最后一张仍在桌内
	var step := sw * 0.96
	if items.size() > 1:
		var max_step := (r.end.y - sw * 0.5 - y) / float(items.size() - 1)
		step = clampf(minf(step, max_step), 4.0, sw * 0.96)
	for i in items.size():
		var it: Array = items[i]
		out.append(_entry(it[0], it[1], Vector2(cx, y + step * i), Vector2(sw, sh), rot, Color(0, 0, 0, 0), false, _seat_origin(seat), it[2]))


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
	var ox := _clamp_row_start(size.x * 0.5, POOL_COLS * POOL_CELL.x)
	var oy := maxf(168.0, _safe_rect().position.y)
	for i in tiles.size():
		var r := i / POOL_COLS
		var c := i % POOL_COLS
		var center := Vector2(ox + c * POOL_CELL.x + POOL_CELL.x * 0.5, oy + r * POOL_CELL.y + POOL_CELL.y * 0.5)
		var t: Tile = tiles[i]
		var glow := Color(GOLD, 0.8) if t == _last_discard else Color(0, 0, 0, 0)
		out.append(_entry(t, true, center, POOL_TILE, 0.0, glow, false, center))


func _entry(t: Tile, face: bool, center: Vector2, sz: Vector2, rot: float, glow: Color, dim: bool, spawn: Vector2, key: Variant = null, layer: int = TileLayer.TABLE) -> Dictionary:
	var k: Variant = key if key != null else t.get_instance_id()
	return {"key": k, "tile": t, "face": face, "center": center, "size": sz, "rot": rot,
		"glow": glow, "dim": dim, "spawn": spawn, "layer": layer}


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
			v.tapped.connect(_on_tile_tapped)
			_tiles_layer.add_child(v)
			_views[key] = v
			var origin: Vector2 = e["center"]
			if t != null and _discard_origin.has(t.get_instance_id()):
				origin = _discard_origin[t.get_instance_id()]
			elif t != null and not _flying.has(t.get_instance_id()):
				origin = e["spawn"]
			v.position = origin - sz * 0.5
			v.scale = Vector2.ONE * (0.94 if Settings.reduced_motion else 0.3)
			v.modulate.a = 0.0
		# 牌视图会在手牌、牌河和副露之间复用，点击权限必须跟着位置刷新。
		# 只有自己的手牌接收点击，碰/杠和牌河不应截走选牌事件。
		var interactive := _mode == "discard" and t != null and _human.hand.concealed.has(t)
		v.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
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
	_order_tile_views(entries)


## 持久化视图不能依赖创建先后：选中牌始终在副露之上，飞牌始终在牌桌最上层。
## 同层保持布局里的顺序，正在退场的旧视图留在底层；外部 HUD / 模态层级不变。
func _order_tile_views(entries: Array) -> void:
	for layer in range(TileLayer.TABLE, TileLayer.FLYING + 1):
		for e in entries:
			var v: TileView = _views[e["key"]]
			var effective_layer: int = TileLayer.FLYING if v.get_meta("flying", false) else e["layer"]
			if effective_layer == layer:
				_tiles_layer.move_child(v, -1)


func _move(v: TileView, e: Dictionary, is_new: bool) -> void:
	if v.has_meta("flying") and v.get_meta("flying"):
		return  # 正在飞行，等落地后再同步位置（否则会打断落地效果）
	var center: Vector2 = e["center"]
	var sz: Vector2 = e["size"]
	# center 已包含选牌/摸牌抬升，这里不能再减一次。
	var target := center - sz * 0.5
	var tw := _tween_of(v)
	tw.set_parallel(true)
	var dur := 0.42 if is_new else 0.34
	tw.tween_property(v, "position", target, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(v, "rotation", e["rot"], dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 选中状态用抬升 + 细描边表达，不横向放大挤到相邻牌。
	tw.tween_property(v, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(v, "modulate", Color(0.6, 0.6, 0.6, 1) if e["dim"] else Color.WHITE, 0.2)
	tw.tween_property(v, "modulate:a", 1.0, 0.25)


## 弧线飞行：从当前位置飞到牌河，落地时播放冲击效果
func _fly_discard(v: TileView, e: Dictionary, fid: int) -> void:
	_flying.erase(fid)
	_discard_origin.erase(fid)
	var t: Tile = e["tile"]
	var target: Vector2 = e["center"]
	var start := v.position + v.size * 0.5
	var ctrl := (start + target) * 0.5 + Vector2(0, -60.0 if Settings.reduced_motion else -220.0)
	v.set_meta("flying", true)
	var tw := _tween_of(v)
	tw.tween_method(_arc_step.bind(v, start, ctrl, target), 0.0, 1.0, 0.46).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(v, "rotation", e["rot"], 0.46)
	tw.parallel().tween_property(v, "modulate", Color.WHITE, 0.2)
	tw.tween_callback(_on_discard_land.bind(t, target, v))


func _arc_step(t: float, v: TileView, s: Vector2, c: Vector2, e: Vector2) -> void:
	var p := s.lerp(c, t).lerp(c.lerp(e, t), t)
	v.position = p - v.size * 0.5
	v.scale = Vector2.ONE * (1.0 + (0.06 if Settings.reduced_motion else 0.3) * sin(PI * t))


func _on_discard_land(t: Tile, pos: Vector2, v: TileView) -> void:
	v.set_meta("flying", false)
	_refresh()  # 同步到牌河的最终位置
	# 落桌挤压回弹：牌先被压扁再弹回，配合震屏才有重量感（走 squash，不抢 scale 补间）
	var light := Settings.reduced_motion
	v.squash = Vector2(1.04, 0.96) if light else Vector2(1.18, 0.82)
	var st := v.create_tween()
	st.tween_property(v, "squash", Vector2.ONE if light else Vector2(0.94, 1.06), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	st.tween_property(v, "squash", Vector2.ONE, 0.16).set_trans(Tween.TRANS_CUBIC if light else Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_bubble(pos + Vector2(0, -52), _tile_name(t), CREAM)
	_sfx.play_tile_impact(t.suit, t.rank)
	_sfx.play("shimmer", 1.0, -14.0)
	_burst_at(pos, SUIT_COLORS[t.suit], 0.9)
	Vfx.sparkle(_fx_layer, pos, SUIT_COLORS[t.suit].lightened(0.3), 12, true)
	_shake(5.0)
	# 落地后稍等一下再报牌名，让撞击声先出现
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(_sfx.speak_tile.bind(t.suit, t.rank, _discard_seat(t)))


func _retire(key: Variant) -> void:
	var v: TileView = _views[key]
	_views.erase(key)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := v.create_tween().set_parallel(true)
	tw.tween_property(v, "modulate:a", 0.0, 0.3)
	tw.tween_property(v, "scale", Vector2.ONE * (0.94 if Settings.reduced_motion else 0.4), 0.3)
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
	var active_seat := _active_turn_seat()
	for i in _players.size():
		var p := _players[i] as Player
		var l := _score_labels[i]
		l.text = "%s  %+d" % [p.display_name, p.score] if p.score != 0 else "%s  0" % p.display_name
		l.add_theme_color_override("font_color", GOLD if i == active_seat else CREAM)
		var chip := _chips[i]
		chip.visible = p.missing_suit >= 0
		if p.missing_suit >= 0:
			(chip.get_child(0) as Label).text = "缺" + Tile.SUIT_CHARS[p.missing_suit]
			chip.add_theme_stylebox_override("panel", _chip_style(SUIT_COLORS[p.missing_suit]))
	_layout_seat_labels()
	_update_hint()
	_info.text = "第 %d/%d 局 · 庄家 %s · 余牌 %d" % [
		_match.round_index, _match.total_rounds, _players[_round.dealer].display_name,
		_round.wall.remaining()]


## 血战到底中已胡玩家不再行动；开局定缺、局末和退出时也不显示行动标记。
func _active_turn_seat() -> int:
	if _aborted or _round == null or _round.round_over or _cur_turn < 0 or _cur_turn >= _players.size():
		return -1
	return -1 if (_players[_cur_turn] as Player).finished else _cur_turn


func _refresh_turn_indicator() -> void:
	if _turn_indicator == null:
		return
	var seat := _active_turn_seat()
	_turn_indicator.set_active(seat >= 0, Settings.reduced_motion)
	if seat < 0:
		return
	var label := _score_labels[seat]
	var font := label.get_theme_font("font")
	var text_width := minf(label.size.x,
		font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x)
	var text_x := label.position.x
	if seat == 1:
		text_x += label.size.x - text_width
	# 左/下家在文字右侧，右/上家在文字左侧；向桌内留白放置，不挤占手牌或定缺标签。
	var dot_x := text_x - TurnIndicator.GAP - TurnIndicator.DIAMETER if seat == 1 or seat == 2 else text_x + text_width + TurnIndicator.GAP
	_turn_indicator.position = Vector2(dot_x, label.position.y + (label.size.y - TurnIndicator.DIAMETER) * 0.5)


# ============================ 特效 ============================

func _burst_at(pos: Vector2, color: Color, strength: float) -> void:
	Fx.burst(_fx_layer, pos, color, strength)


func _shake(amount: float) -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = null
	_world.position = Vector2.ZERO
	if Settings.reduced_motion:
		return
	# 碰杠/胡牌可能连续触发，不让多个震屏补间互相抢位置。
	_shake_tween = _world.create_tween()
	for i in 6:
		_shake_tween.tween_property(_world, "position", Vector2(randf_range(-amount, amount), randf_range(-amount, amount)), 0.03)
	_shake_tween.tween_property(_world, "position", Vector2.ZERO, 0.04)


func _stop_attention_effects() -> void:
	for tw: Tween in [_shake_tween, _flash_tween, _fireworks_tween]:
		if tw != null and tw.is_valid():
			tw.kill()
	_shake_tween = null
	_flash_tween = null
	_fireworks_tween = null
	_world.position = Vector2.ZERO
	_overlay.color.a = 0.0


## 暂停面板内切换也立即生效，清掉正在播放/尚未触发的强特效，不打断飞牌和规则流程。
func _apply_effects_setting() -> void:
	Vfx.apply_ambient_setting(_ambient)
	_refresh_turn_indicator()
	if not Settings.reduced_motion:
		return
	_stop_attention_effects()
	for child in _fx_layer.get_children():
		if child is Label:
			_soften_text_fx(child)
		else:
			child.queue_free()
	if _banner.modulate.a > 0.0:
		_soften_text_fx(_banner)


func _soften_text_fx(label: Label) -> void:
	label.scale = Vector2.ONE
	# 若恰好在文字淡入前切换，也要保留这条提示，不能停在透明状态。
	label.modulate.a = 1.0
	label.add_theme_color_override("font_color", label.get_theme_color("font_color").clamp())
	label.add_theme_font_size_override("font_size", mini(120, label.get_theme_font_size("font_size")))
	label.add_theme_constant_override("outline_size", mini(12, label.get_theme_constant("outline_size")))
	var tw := _tween_of(label)
	tw.tween_interval(0.6)
	tw.tween_property(label, "modulate:a", 0.0, 0.35)
	if label != _banner:
		tw.tween_callback(label.queue_free)


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
func _bubble(pos: Vector2, text: String, color: Color, font_size: int = 40) -> void:
	var l := Label.new()
	UiFont.apply_title(l)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size = Vector2(180, 60)
	l.position = pos - l.size * 0.5
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2.ONE if Settings.reduced_motion else Vector2(0.4, 0.4)
	l.modulate.a = 0.0 if Settings.reduced_motion else 1.0
	_fx_layer.add_child(l)
	var tw := _tween_of(l)
	if Settings.reduced_motion:
		tw.tween_property(l, "modulate:a", 1.0, 0.18)
	else:
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
	_stop_attention_effects()
	_sfx.play("hu", 1.0, 0.0)
	var call := "zimo" if self_drawn else "hu"
	var vt := create_tween()
	vt.tween_interval(0.35)
	vt.tween_callback(_sfx.speak_call.bind(call, seat))
	_flash_banner("%s %s！" % [_players[seat].display_name, "自摸" if self_drawn else "胡"], UiTheme.HU)
	_call_stamp("自摸" if self_drawn else "胡", UiTheme.HU)
	Vfx.confetti(_fx_layer, size.x)
	if Settings.reduced_motion:
		return  # 文字与报牌照常，省去全屏闪光、烟花和彩纸。
	_overlay.color = Color(1.0, 0.85, 0.3, 0.0)
	_flash_tween = _overlay.create_tween()
	_flash_tween.tween_property(_overlay, "color:a", 0.35, 0.12)
	_flash_tween.tween_property(_overlay, "color:a", 0.0, 0.8)
	_shake(10.0)
	_fireworks_tween = _overlay.create_tween()
	var w := size.x
	var h := size.y
	for i in 7:
		var p := Vector2(randf_range(w * 0.15, w * 0.85), randf_range(h * 0.12, h * 0.6))
		var col: Color = [GOLD, Color("ff7043"), Color("64b5f6"), Color("81c784")][i % 4]
		_fireworks_tween.tween_callback(_burst_at.bind(p, col, 1.5))
		_fireworks_tween.tween_interval(0.18)


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
	l.add_theme_font_size_override("font_size", 120 if Settings.reduced_motion else 170)
	l.add_theme_color_override("font_color", color.lightened(0.25) if Settings.reduced_motion else UiTheme.hot(color.lightened(0.25), 1.9))
	l.add_theme_color_override("font_outline_color", Color(0.25, 0.05, 0.0, 0.95))
	l.add_theme_constant_override("outline_size", 12 if Settings.reduced_motion else 22)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size = Vector2(420, 260)
	l.position = center - l.size * 0.5
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2.ONE if Settings.reduced_motion else Vector2(2.6, 2.6)
	l.modulate.a = 0.0
	_fx_layer.add_child(l)
	var tw := _tween_of(l)
	tw.set_parallel(true)
	if not Settings.reduced_motion:
		tw.tween_property(l, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 1.0, 0.18 if Settings.reduced_motion else 0.12)
	tw.chain().tween_interval(0.7)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.4)
	tw.chain().tween_callback(l.queue_free)
	_shake(8.0)


func _flash_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color if Settings.reduced_motion else UiTheme.hot(color, 1.45))
	_banner.modulate.a = 0.0 if Settings.reduced_motion else 1.0
	_banner.scale = Vector2.ONE if Settings.reduced_motion else Vector2(0.5, 0.5)
	var tw := _tween_of(_banner)
	if Settings.reduced_motion:
		tw.tween_property(_banner, "modulate:a", 1.0, 0.18)
	else:
		tw.tween_property(_banner, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.9)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.4)


# ============================ 结算 ============================

func _show_round_result() -> void:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(760, 440)  # 固定高度：内容多时靠滚动查看，不挡住上方玩家手牌
	box.add_theme_stylebox_override("panel", _panel_style(CREAM, 30))
	add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	box.add_child(v)

	var any_win := false
	for p in _players:
		if (p as Player).win_result != null:
			any_win = true
	var title := Label.new()
	if _round.draw_game:
		title.text = "牌墙摸完 · 本局结束" if any_win else "流局"
	else:
		title.text = "本局结束"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFont.apply_title(title)
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", UiTheme.INK)
	v.add_child(title)

	# 结算内容区：可上下滑动查看，标题与按钮固定不动
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	for p in _players:
		var pl := p as Player
		if pl.win_result != null:
			var fl := Label.new()
			fl.text = "%s：%s" % [pl.display_name, pl.win_result.summary()]
			fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			fl.add_theme_font_size_override("font_size", 24)
			fl.add_theme_color_override("font_color", UiTheme.DANGER)
			content.add_child(fl)
	content.add_child(HSeparator.new())
	for p in _players:
		var pl := p as Player
		var delta := pl.score - int(_scores_before[pl.seat])
		var row := Label.new()
		row.text = "%s    %+d    （累计 %d）" % [pl.display_name, delta, pl.score]
		row.add_theme_font_size_override("font_size", 30)
		row.add_theme_color_override("font_color", UiTheme.GREEN if delta >= 0 else UiTheme.NEG)
		content.add_child(row)
	# 收付明细：谁给谁多少、因为什么
	if not _payments.is_empty():
		content.add_child(HSeparator.new())
		var head := Label.new()
		head.text = "本局收付"
		head.add_theme_font_size_override("font_size", 24)
		head.add_theme_color_override("font_color", UiTheme.INK_MUTED)
		content.add_child(head)
		var shown := 0
		for tr in _payments:
			if shown >= 12:
				var more := Label.new()
				more.text = "……"
				more.add_theme_font_size_override("font_size", 20)
				more.add_theme_color_override("font_color", UiTheme.INK_MUTED)
				content.add_child(more)
				break
			shown += 1
			var from_seat := int(tr["from"])
			var to_seat := int(tr["to"])
			var reason := "胡牌" if String(tr.get("reason", "")) == "win" else "杠分"
			var line := Label.new()
			line.text = "%s → %s    %d（%s）" % [
				(_players[from_seat] as Player).display_name,
				(_players[to_seat] as Player).display_name,
				int(tr["amount"]), reason]
			line.add_theme_font_size_override("font_size", 20)
			line.add_theme_color_override("font_color", UiTheme.INK_BODY)
			content.add_child(line)
	var btn := _make_button("查看总结" if _match.is_over() else "下一局", UiTheme.GREEN, 320)
	btn.pressed.connect(_press_continue)
	v.add_child(btn)
	await _center_box(box)
	_result_box = box
	await _wait_continue()
	if is_instance_valid(box):
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
	title.add_theme_color_override("font_color", UiTheme.INK)
	v.add_child(title)
	var rank := 1
	for p in _match.ranking():
		var pl := p as Player
		var row := Label.new()
		row.text = "第 %d 名    %s    %d 分" % [rank, pl.display_name, pl.score]
		row.add_theme_font_size_override("font_size", 36)
		row.add_theme_color_override("font_color", UiTheme.INK)
		v.add_child(row)
		rank += 1
	var replay := _make_button("再来一场", UiTheme.GREEN, 320)
	replay.pressed.connect(_request_restart)
	v.add_child(replay)
	var back := _make_button("返回菜单", UiTheme.SLATE, 320)
	back.pressed.connect(_request_exit)
	v.add_child(back)
	await _center_box(box)
	await _wait_continue()
	if not _aborted and is_instance_valid(box):
		box.queue_free()
		exit_requested.emit()


func _center_box(box: Control) -> void:
	await get_tree().process_frame
	box.position = (size - box.size) * 0.5


func _panel_style(bg: Color, radius: int) -> StyleBoxFlat:
	return UiTheme.panel_style(bg, radius, 34, 28)


# ============================ 暂停 / 退出 / 重开 ============================

## 结算面板等“继续”。先置标记再 emit，这样中止发生在等待之前也不会漏掉
func _press_continue() -> void:
	_continue_flag = true
	_continue_pressed.emit()


func _wait_continue() -> void:
	if _continue_flag:
		_continue_flag = false
		return
	await _continue_pressed
	_continue_flag = false


func _build_pause_layer() -> void:
	_pause_layer = Control.new()
	_pause_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_layer.visible = false
	add_child(_pause_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(CREAM, 30))
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)

	var title := Label.new()
	title.text = "暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiFont.apply_title(title)
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", UiTheme.INK)
	v.add_child(title)

	var resume := _make_button("继续游戏", UiTheme.GREEN, 340)
	resume.name = "ResumeButton"
	resume.pressed.connect(_close_pause)
	v.add_child(resume)

	var settings_btn := _make_button("设置", UiTheme.SLATE, 340)
	settings_btn.pressed.connect(_open_settings_in_pause)
	v.add_child(settings_btn)

	var help_btn := _make_button("玩法", UiTheme.BROWN, 340)
	help_btn.pressed.connect(_open_help_in_pause)
	v.add_child(help_btn)

	var restart := _make_button("重新开始", UiTheme.WARN, 340)
	restart.pressed.connect(_request_restart)
	v.add_child(restart)

	var quit := _make_button("返回菜单", UiTheme.DANGER, 340)
	quit.pressed.connect(_request_exit)
	v.add_child(quit)

	var tip := Label.new()
	tip.text = "本局进度不会保存"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 20)
	tip.add_theme_color_override("font_color", UiTheme.INK_MUTED)
	v.add_child(tip)


func _open_pause() -> void:
	if _pause_layer == null or _pause_layer.visible:
		return
	if _round == null:
		exit_requested.emit()
		return
	move_child(_pause_layer, get_child_count() - 1)
	_pause_layer.visible = true
	get_tree().paused = true
	var resume := _pause_layer.find_child("ResumeButton", true, false) as Button
	if resume != null:
		resume.grab_focus()


func _close_pause() -> void:
	if _pause_layer == null:
		return
	_pause_layer.visible = false
	get_tree().paused = false


func _open_help_in_pause() -> void:
	if has_node("PauseHelpView"):
		return
	var view := HelpView.new()
	view.name = "PauseHelpView"
	add_child(view)


func _open_settings_in_pause() -> void:
	if has_node("PauseSettingsView"):
		return
	Settings.load_settings()
	var view := SettingsView.new()
	view.name = "PauseSettingsView"
	view.closed.connect(_apply_pace_setting)
	view.effects_changed.connect(_apply_effects_setting)
	add_child(view)


func _apply_pace_setting() -> void:
	_speed = Settings.pace()
	if _round != null:
		_round.pace_time = _speed


## 干净地结束本局：取消协程、唤醒挂起的等待，之后才真正释放牌桌
func _abort_round() -> void:
	if _aborted:
		return
	_aborted = true
	_cur_turn = -1
	_refresh_turn_indicator()
	_stop_attention_effects()
	if get_tree() != null:
		get_tree().paused = false
	_mode = ""
	_selected_tile = null
	_action_bar_clear()
	if _round != null:
		_round.cancel()
	_press_continue()


## 等本局协程真正退出（最多约 2 秒），避免牌桌被释放后还有回调打进来
func _wait_round_stopped() -> void:
	if _round == null:
		return
	var frames := 0
	while _round.running and frames < 120:
		frames += 1
		await get_tree().process_frame
	await get_tree().process_frame


func _request_exit() -> void:
	if _aborted:
		return
	_abort_round()
	await _wait_round_stopped()
	await get_tree().process_frame
	exit_requested.emit()


func _request_restart() -> void:
	if _aborted:
		return
	_abort_round()
	await _wait_round_stopped()
	await get_tree().process_frame
	restart_requested.emit(_rule_id, Settings.pace())


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
	_info.add_theme_color_override("font_color", UiTheme.ON_FELT)
	_info.add_theme_font_size_override("font_size", 22)
	add_child(_info)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 26)
	_hint.add_theme_color_override("font_color", UiTheme.hot(GOLD, 1.35))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("outline_size", 8)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	add_child(_hint)

	for i in MahjongRule.PLAYER_COUNT:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 26)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if i == 1 else HORIZONTAL_ALIGNMENT_LEFT
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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

	_turn_indicator = TurnIndicator.new()
	add_child(_turn_indicator)

	var menu_btn := _make_button("菜单", UiTheme.SLATE, 110)
	menu_btn.name = "MenuButton"
	menu_btn.add_theme_font_size_override("font_size", 26)
	menu_btn.pressed.connect(_open_pause)
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
	_build_pause_layer()


func _layout_static() -> void:
	var w := size.x
	var h := size.y
	_title.position = Vector2(24, 14)
	_info.position = Vector2(24, 46)
	_info.size = Vector2(700, 30)
	var hw := _hand_tile_width()
	var hh := hw * 1.42
	_hint.size = Vector2(580.0, 34.0)
	_hint.position = Vector2(maxf(w - 620.0, _safe_rect().position.x), h - hh - 118.0)
	var menu := find_child("MenuButton", false, false) as Control
	if menu:
		menu.position = Vector2(w - 130, 6)
	_layout_seat_labels()
	var safe := _safe_rect()
	_ambient.position = Vector2(w * 0.5, h * 0.5)
	_ambient.emission_rect_extents = Vector2(w * 0.5, h * 0.5)
	_banner.position = Vector2(0, h * 0.42)
	_banner.size = Vector2(w, 110)
	_banner.pivot_offset = Vector2(w * 0.5, 55)
	_action_bar.size = Vector2(840, 90)
	_action_bar.position = Vector2(clampf(w * 0.5 - 420, safe.position.x, maxf(safe.position.x, safe.end.x - 840)),
		minf(640.0, safe.end.y - 110.0))


## 文本/分数/定缺变化后也重算标签宽度，避免右家短名字和不同标签向左漂移。
func _layout_seat_labels() -> void:
	var w := size.x
	var h := size.y
	var hh := _hand_tile_width() * 1.42
	# 座位顺序：自己（下）、右家、对家（上）、左家。
	# 名字与定缺标记分组放在对应手牌旁，避免与中央牌河重叠。
	var side_tile_height := _hand_tile_width() * 0.44 * 1.42
	var seat_positions := [
		Vector2(side_tile_height + 45, h - hh - 160),
		Vector2(w - side_tile_height - 45 - SEAT_LABEL_WIDTH, h * 0.35),
		Vector2(w * 0.5 - 130, 8),
		Vector2(side_tile_height + 45, h * 0.35),
	]
	var safe := _safe_rect()
	for i in _score_labels.size():
		var pos: Vector2 = seat_positions[i]
		# 左右信息区镜像摆放：右家文字与标签都贴齐靠近手牌的一侧。
		pos.x = clampf(pos.x, safe.position.x, maxf(safe.position.x, safe.end.x - SEAT_LABEL_WIDTH))
		pos.y = clampf(pos.y, safe.position.y, maxf(safe.position.y, safe.end.y - 70.0))
		_score_labels[i].position = pos
		_score_labels[i].size = Vector2(SEAT_LABEL_WIDTH, 34)
		var chip := _chips[i]
		chip.size = chip.get_combined_minimum_size()
		var chip_offset := Vector2(0, _score_labels[i].size.y + 4.0)
		if i == 1:
			chip_offset.x = SEAT_LABEL_WIDTH - chip.size.x
		elif i == 2:
			chip_offset = Vector2(SEAT_LABEL_WIDTH, 0)
		chip.position = pos + chip_offset
	_refresh_turn_indicator()


func _on_resized() -> void:
	queue_redraw()
	_layout_static()
	if _round != null:
		_refresh()


func _chip_style(color: Color) -> StyleBoxFlat:
	return UiTheme.chip_style(color)


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
	return UiTheme.make_button(text, color, min_w, 80, UiTheme.FS_BTN_LARGE)


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
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.WOOD)
	for i in 60:
		var y := h * float(i) / 60.0
		draw_line(Vector2(0, y), Vector2(w, y), Color(0.45, 0.28, 0.14, 0.18 if i % 2 == 0 else 0.07), 2.0)
	draw_rect(Rect2(0, 0, w, 10), Color(0.8, 0.6, 0.35, 0.25))
	draw_rect(Rect2(0, h - 10, w, 10), Color(0, 0, 0, 0.45))
	# 2) 毡布面：纵向渐变 + 中心光晕 + 细微纹理
	# 色阶做密一点：60 段在 1080p 上能看出横向色带，加到 160 段后看不见台阶
	var m := 26.0
	var felt := Rect2(m, m, w - m * 2, h - m * 2)
	var steps := 160
	for i in steps:
		var t := float(i) / steps
		draw_rect(Rect2(felt.position.x, felt.position.y + felt.size.y * t, felt.size.x, felt.size.y / steps + 1),
			UiTheme.FELT_TOP.lerp(UiTheme.FELT_BOTTOM, t))
	# 光心固定在左上（与牌面高光、所有阴影方向一致），右下补一层很淡的接触阴影
	var center := Vector2(w * 0.5, h * 0.5)
	var light_c := Vector2(w * 0.44, h * 0.40)
	for k in 14:
		draw_circle(light_c, (w * 0.60) - k * 52.0, Color(0.45, 0.95, 0.65, 0.018))
	for k in 10:
		draw_circle(Vector2(w * 0.70, h * 0.76), (w * 0.46) - k * 58.0, Color(0.0, 0.06, 0.03, 0.014))
	for k in 260:
		var px := felt.position.x + fmod(float(k) * 97.31, felt.size.x)
		var py := felt.position.y + fmod(float(k) * 53.17, felt.size.y)
		draw_rect(Rect2(px, py, 2, 2), Color(1, 1, 1, 0.03))
	# 3) 金色描边 + 四角铆钉
	draw_rect(felt.grow(-10), Color(0.95, 0.8, 0.45, 0.45), false, 3.0)
	draw_rect(felt.grow(-16), Color(0.95, 0.8, 0.45, 0.15), false, 1.0)
	for c in [felt.position, felt.position + Vector2(felt.size.x, 0), felt.position + Vector2(0, felt.size.y), felt.end]:
		draw_circle(c, 9.0, UiTheme.BRASS)
		draw_circle(c, 4.0, UiTheme.WOOD)
	# 4) 中心水印
	var font := UiFont.title()
	var wm := "血 战 到 底"
	var fs := 56
	var wm_w := font.get_string_size(wm, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string(font, Vector2(center.x - wm_w * 0.5, h * 0.5 + 14), wm, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 0.88, 0.5, 0.12))
	draw_arc(center + Vector2(0, -6), 170.0, PI * 1.1, PI * 1.9, 80, Color(1, 0.85, 0.45, 0.10), 2.0, true)
