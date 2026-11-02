extends SceneTree
## 界面冒烟测试：godot --headless --script res://tests/ui_smoke.gd
##
## 真正实例化主场景（菜单 → 玩法说明 → 倒计时进入牌桌），自动替人类玩家定缺/出牌，
## 跑完至少一局，再验证暂停、设置、退出回菜单这条链路。任何脚本错误会在 stderr 里暴露。

const MAX_FRAMES := 4000

var _markers: Array[String] = []
var _main: Control = null
var _picked: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("== 界面冒烟测试 ==")
	Engine.max_fps = 0

	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)
	await process_frame
	_mark("主场景就绪，菜单已显示")

	# 菜单上的玩法说明（首次启动会自动弹出）
	if _main._menu != null:
		var help := HelpView.new()
		_main._menu.add_child(help)
		await process_frame
		help.close()
		await process_frame
		_mark("玩法说明可打开/关闭")

	# 开始对局：这里直接调入口，跳过按钮点击
	# 注意：_run_match 是 call_deferred 启动的，必须在下一帧之前就接好自动应答，
	# 否则会错过第一次 awaiting（定缺）而一直卡住。
	_main._start_match("sichuan", 0.0)
	var view: GameView = _main._game
	if view == null:
		print("SMOKE 失败：没有创建牌桌")
		quit(1)
		return
	view._human.awaiting.connect(_on_human_awaiting.bind(view))
	await process_frame
	_mark("牌桌创建，等待定缺/出牌")

	# 跑到第一局结束
	var frames := 0
	while frames < MAX_FRAMES:
		frames += 1
		await process_frame
		if view._aborted:
			break
		if view._round != null and view._round.round_over and _main._game == view:
			break
	if view._round == null or not view._round.round_over:
		print("SMOKE 失败：%d 帧内没有打完一局" % frames)
		quit(1)
		return
	_mark("第一局结束（余牌 %d）" % view._round.wall.remaining())
	await process_frame

	# 暂停 / 设置 / 继续
	view._open_pause()
	await process_frame
	var paused_ok: bool = paused
	view._open_settings_in_pause()
	await process_frame
	_mark("暂停面板与设置面板可打开")
	view._open_help_in_pause()
	await process_frame
	view._close_pause()
	await process_frame
	if paused:
		print("SMOKE 失败：暂停没有恢复")
		quit(1)
		return
	_mark("暂停可用（paused=%s）" % str(paused_ok))

	# 重新开始：应该换一张新牌桌（比分清零）
	_mark("请求重新开始")
	view._request_restart()
	frames = 0
	while frames < 300 and (_main._game == null or _main._game == view):
		frames += 1
		await process_frame
	if _main._game == null or _main._game == view:
		print("SMOKE 失败：重新开始没有创建新牌桌")
		quit(1)
		return
	var view2: GameView = _main._game
	_mark("重新开始成功（新牌桌 round_index=%d）" % view2._match.round_index)

	# 在“等待人类输入”（定缺）挂起的状态下直接退出，验证挂起输入也能干净中止
	frames = 0
	while frames < 120 and view2._human.missing_suit < 0:
		frames += 1
		await process_frame
	view2._request_exit()
	frames = 0
	while frames < 240 and _main._menu == null:
		frames += 1
		await process_frame
	if _main._menu == null:
		print("SMOKE 失败：退出后没有回到菜单")
		quit(1)
		return
	_mark("挂起输入下退出回菜单成功")

	print("SMOKE 通过：")
	for m in _markers:
		print("  · " + m)
	quit(0)


## 自动替人类玩家作答（必须延迟提交：_ask 在 emit 之后才建立 await）
func _on_human_awaiting(kind: String, payload: Variant, view: GameView) -> void:
	var value: Variant = null
	match kind:
		"missing":
			_picked += 1
			value = _picked % 3
		"discard":
			var allowed: Array = payload
			if not allowed.is_empty():
				value = allowed[_picked % allowed.size()]
				_picked += 1
		_:
			value = null
	view._human.submit.call_deferred(value)


func _mark(text: String) -> void:
	_markers.append(text)
	print("  ✓ " + text)
