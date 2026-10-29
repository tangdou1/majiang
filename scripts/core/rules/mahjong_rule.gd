class_name MahjongRule
extends RefCounted
## 麻将玩法基类（模板方法）。子类覆写虚函数即可定义新玩法。当前实现：四川血战到底。

const PLAYER_COUNT := 4
const HAND_SIZE := 13


func get_id() -> String:
	return "base"


func get_display_name() -> String:
	return "麻将"


func get_description() -> String:
	return ""


func get_rounds() -> int:
	return 4


func get_tile_kinds() -> Array:
	var kinds: Array = []
	for k in WinChecker.KINDS:
		kinds.append(k)
	return kinds


func get_copies() -> int:
	return 4



func allows_chow() -> bool:
	return false


func allows_seven_pairs() -> bool:
	return true


func requires_missing_suit() -> bool:
	return false


func allows_multiple_winners() -> bool:
	return false


func get_min_fan() -> int:
	return 1


## 和牌时是否允许顺子（吃牌是另一回事，四川始终不能吃）
func allows_sequences() -> bool:
	return false


## 手牌形状是否和牌（不计番）
func is_win_shape(hand: Hand) -> bool:
	var sets := 4 - hand.melds.size()
	if hand.concealed.size() != 3 * sets + 2:
		return false
	var counts := WinChecker.counts_of(hand.concealed)
	var shape_ok := WinChecker.can_decompose_sets(counts, sets) if allows_sequences() else WinChecker.can_decompose_pungs(counts, sets)
	if shape_ok:
		return true
	if allows_seven_pairs() and hand.melds.is_empty():
		return WinChecker.is_seven_pairs(counts)
	return false


## 完整判定：形状 + 番种 + 起胡。不能胡返回 null
func evaluate_win(hand: Hand, ctx: WinContext) -> WinResult:
	if not is_win_shape(hand):
		return null
	var res := WinResult.new()
	score_fans(hand, ctx, res)
	if res.fan_total < get_min_fan():
		return null
	return res


func score_fans(_hand: Hand, _ctx: WinContext, _res: WinResult) -> void:
	pass


func waiting_kinds_of(hand: Hand) -> Array[int]:
	var counts := WinChecker.counts_of(hand.concealed)
	return WinChecker.waiting_kinds(counts, 4 - hand.melds.size(), allows_seven_pairs() and hand.melds.is_empty(), allows_sequences())


## 转账列表：[{ "from", "to", "amount" }]
func settle_win(_res: WinResult, _winner: int, _discarder: int, _self_drawn: bool, _dealer: int) -> Array:
	return []


## 杠分转账
func kong_transfers(_kong_type: int, _kong_seat: int, _discarder: int) -> Array:
	return []


static func create(_id: String = "sichuan") -> MahjongRule:
	return SichuanRule.new()


static func all_ids() -> Array[String]:
	return ["sichuan"]
