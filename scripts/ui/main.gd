extends Control
## 应用入口：安装中文字体，在菜单与牌桌之间切换。

var _menu: MenuView = null
var _game: GameView = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_install_font()
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
	_game.start_match(rule_id, pace)
