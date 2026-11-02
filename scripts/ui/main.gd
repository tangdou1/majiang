extends Control
## 应用入口：安装中文字体，在菜单与牌桌之间切换。

var _menu: MenuView = null
var _game: GameView = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Settings.load_settings()
	_install_font()
	# 统一设计令牌：字号阶梯与滚动条外观由主题给出，配色/圆角/阴影走 UiTheme 工厂
	theme = UiTheme.build()
	# 全屏泛光：整个视口共享一个 Environment，菜单与牌桌都吃到
	Glow.install(self)
	_show_menu()


## 全局正文字体（思源黑体 SC，字重 500）；标题字体见 UiFont
func _install_font() -> void:
	var fv := FontVariation.new()
	fv.base_font = load("res://assets/fonts/NotoSansSC.ttf")
	fv.variation_opentype = {0x77676874: 500}  # "wght" 字重轴
	ThemeDB.fallback_font = fv


func _show_menu() -> void:
	if _game != null:
		_game.queue_free()
		_game = null
	_menu = MenuView.new()
	add_child(_menu)
	_menu.start_requested.connect(_start_match)


func _start_match(rule_id: String, pace: float) -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
	_game = GameView.new()
	add_child(_game)
	_game.exit_requested.connect(_show_menu)
	_game.restart_requested.connect(_restart_match)
	_game.start_match(rule_id, pace)


## 牌桌里的“重新开始 / 再来一场”：换一张新牌桌，比分清零
func _restart_match(rule_id: String, pace: float) -> void:
	if _game != null:
		_game.queue_free()
		_game = null
	_start_match(rule_id, pace)
