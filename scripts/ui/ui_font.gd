class_name UiFont
extends RefCounted
## 字体工厂：标题使用思源宋体（衬线，粗体），正文使用思源黑体（中等字重）。

static var _title: Font = null


## 标题字体：Noto Serif SC，字重 800
static func title() -> Font:
	if _title == null:
		var fv := FontVariation.new()
		fv.base_font = load("res://assets/fonts/NotoSerifSC.ttf")
		fv.variation_opentype = {0x77676874: 800}  # "wght"
		_title = fv
	return _title


## 为控件设置标题字体
static func apply_title(c: Control) -> void:
	c.add_theme_font_override("font", title())
