class_name Player
extends RefCounted
## 玩家基类：座位、手牌、分数等状态，并定义决策接口（子类分别实现人类输入或 AI 计算）。

var seat: int
var display_name: String
var hand := Hand.new()
var score: int = 0
var missing_suit: int = -1
var finished: bool = false          ## 已胡（血战中退出行动）
var win_result: WinResult = null
var discards: Array[Tile] = []


func _init(p_seat: int, p_name: String) -> void:
	seat = p_seat
	display_name = p_name


func is_human() -> bool:
	return false


func reset_for_round() -> void:
	hand = Hand.new()
	missing_suit = -1
	finished = false
	win_result = null
	discards.clear()


## 定缺，返回 Tile.Suit
func decide_missing_suit(_rule: MahjongRule) -> int:
	return Tile.Suit.CHARACTER


## 从 allowed 中选择要打出的牌
func decide_discard(allowed: Array, _rule: MahjongRule) -> Tile:
	return allowed[0]


## 从可选行动中选一项；返回 Dictionary 或 null（过）。phase 为 "self" 或 "claim"
func decide_option(_options: Array, _phase: String, _rule: MahjongRule) -> Variant:
	return null
