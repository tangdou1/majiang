class_name HumanPlayer
extends Player
## 人类玩家：需要决策时发出 awaiting 信号并挂起，界面调用 submit() 回填结果。

signal awaiting(kind: String, payload: Variant)
signal _answered

var _answer: Variant = null
var _pending: bool = false   ## 是否有界面正在等待输入


func _init(p_seat: int, p_name: String) -> void:
	super(p_seat, p_name)


func is_human() -> bool:
	return true


## 界面调用：提交结果（Tile / Dictionary / int / null）
func submit(value: Variant) -> void:
	_answer = value
	_answered.emit()


func _ask(kind: String, payload: Variant) -> Variant:
	_answer = null
	_pending = true
	awaiting.emit(kind, payload)
	await _answered
	_pending = false
	return _answer


## 退出对局/重开时调用：让挂起的等待立刻返回 null，避免协程永远卡住
func cancel() -> void:
	if not _pending:
		return
	_answer = null
	_pending = false
	_answered.emit()


func decide_missing_suit(rule: MahjongRule) -> int:
	var v: Variant = await _ask("missing", rule)
	return int(v) if v != null else Tile.Suit.CHARACTER


func decide_discard(allowed: Array, _rule: MahjongRule) -> Tile:
	return await _ask("discard", allowed)


func decide_option(options: Array, phase: String, _rule: MahjongRule) -> Variant:
	return await _ask("option", {"options": options, "phase": phase})
