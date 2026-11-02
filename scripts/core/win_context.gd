class_name WinContext
extends RefCounted
## 胡牌时的上下文（影响番种与结算）。

var winner_seat: int = 0
var self_drawn: bool = false
var is_dealer: bool = false
var winning_tile: Tile = null
var discarder_seat: int = -1
var missing_suit: int = -1   ## 定缺花色，-1 表示无
var robbed_kong: bool = false  ## 抢杠胡：补杠时胡走这张牌
