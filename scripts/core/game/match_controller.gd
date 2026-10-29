class_name MatchController
extends RefCounted
## 一场比赛：若干局，轮庄，总分排名。

var rule: MahjongRule
var players: Array = []
var round_index: int = 0
var total_rounds: int = 4
var current: RoundController = null


func _init(p_rule: MahjongRule, p_players: Array) -> void:
	rule = p_rule
	players = p_players
	total_rounds = rule.get_rounds()


func is_over() -> bool:
	return round_index >= total_rounds


func dealer_of_next_round() -> int:
	return round_index % MahjongRule.PLAYER_COUNT


func start_next_round() -> RoundController:
	current = RoundController.new(rule, players, dealer_of_next_round())
	round_index += 1
	return current


func ranking() -> Array:
	var sorted := players.duplicate()
	sorted.sort_custom(func(a: Player, b: Player) -> bool: return a.score > b.score)
	return sorted
