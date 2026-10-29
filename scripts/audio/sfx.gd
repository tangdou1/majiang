class_name Sfx
extends Node
## 音效与人声播放器：
## - 音效：预加载 assets/sfx，使用播放器池，支持变调与音量
## - 人声：assets/voice 中的中文报牌（如“二万”“三条”）与叫牌词（碰/杠/胡/自摸），单独一个播放器，新语音打断旧语音

const SOUNDS := ["whoosh", "impact_stone", "impact_glass", "impact_wood", "impact_jade",
	"shimmer", "select", "draw", "claim", "kong", "hu"]
const CALLS := ["peng", "gang", "hu", "zimo", "angang", "buggang"]
const POOL_SIZE := 14

var _streams := {}
var _voices := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _voice_player: AudioStreamPlayer
var spoken := 0   ## 已播报的语音次数（用于自检）


func _ready() -> void:
	for name in SOUNDS:
		_streams[name] = load("res://assets/sfx/%s.wav" % name)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	for name in CALLS:
		_voices[name] = load("res://assets/voice/%s.wav" % name)
	for s in range(1, 10):
		_voices["w%d" % s] = load("res://assets/voice/w%d.wav" % s)
		_voices["t%d" % s] = load("res://assets/voice/t%d.wav" % s)
		_voices["s%d" % s] = load("res://assets/voice/s%d.wav" % s)
	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = "Master"
	_voice_player.volume_db = 6.0
	add_child(_voice_player)


## 播放音效。pitch 为播放速率倍数，db 为音量偏移
func play(name: String, pitch: float = 1.0, db: float = 0.0) -> void:
	if not _streams.has(name) or _pool.is_empty():
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[name]
	p.pitch_scale = pitch
	p.volume_db = db
	p.play()


## 按牌的花色选择落地撞击音：万=石、筒=玻璃、条=木，并随点数变调
func play_tile_impact(suit: int, rank: int) -> void:
	var pitch := 0.82 + rank * 0.035
	match suit:
		0: play("impact_stone", pitch, -2.0)
		1: play("impact_glass", pitch, -4.0)
		_: play("impact_wood", pitch, -2.0)


## 报牌：播放“X万/X筒/X条”
func speak_tile(suit: int, rank: int) -> void:
	var prefix: String = ["w", "t", "s"][suit]
	_speak("%s%d" % [prefix, rank])


## 叫牌词：name 为 peng / gang / hu / zimo / angang / buggang
func speak_call(name: String) -> void:
	_speak(name)


func _speak(key: String) -> void:
	if not _voices.has(key):
		return
	spoken += 1
	_voice_player.stop()
	_voice_player.stream = _voices[key]
	_voice_player.play()
