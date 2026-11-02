class_name Settings
extends RefCounted
## 全局设置：出牌节奏、音效/人声音量、静音、震动。
## 持久化到 user://settings.cfg；音量通过独立的音频总线（SFX / Voice）控制，改动立即生效。

const PATH := "user://settings.cfg"

const BUS_SFX := "SFX"
const BUS_VOICE := "Voice"

## 出牌节奏（秒）：快 / 中 / 慢
const PACE_VALUES := [0.22, 0.42, 0.7]
const PACE_NAMES := ["快", "中", "慢"]

static var pace_index: int = 2
static var sfx_volume: float = 0.9
static var voice_volume: float = 1.0
static var muted: bool = false
static var vibrate: bool = true

static var _loaded: bool = false


static func pace() -> float:
	return PACE_VALUES[clampi(pace_index, 0, PACE_VALUES.size() - 1)]


static func pace_name() -> String:
	return PACE_NAMES[clampi(pace_index, 0, PACE_NAMES.size() - 1)]


## 读取设置并立刻应用到音频总线；只需调用一次（重复调用无副作用）
static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		pace_index = clampi(int(cfg.get_value("game", "pace_index", pace_index)), 0, PACE_VALUES.size() - 1)
		vibrate = bool(cfg.get_value("game", "vibrate", vibrate))
		sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
		voice_volume = clampf(float(cfg.get_value("audio", "voice_volume", voice_volume)), 0.0, 1.0)
		muted = bool(cfg.get_value("audio", "muted", muted))
	apply_audio()


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "pace_index", pace_index)
	cfg.set_value("game", "vibrate", vibrate)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "voice_volume", voice_volume)
	cfg.set_value("audio", "muted", muted)
	cfg.save(PATH)
	apply_audio()


## 把当前音量写进音频总线（静音时整条总线静音）
static func apply_audio() -> void:
	var sfx := _ensure_bus(BUS_SFX)
	var voice := _ensure_bus(BUS_VOICE)
	AudioServer.set_bus_volume_db(sfx, linear_to_db(maxf(sfx_volume, 0.001)))
	AudioServer.set_bus_volume_db(voice, linear_to_db(maxf(voice_volume, 0.001)))
	AudioServer.set_bus_mute(sfx, muted)
	AudioServer.set_bus_mute(voice, muted)


## 找到总线，没有就新建（发送到 Master）
static func _ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return idx
	idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	return idx
