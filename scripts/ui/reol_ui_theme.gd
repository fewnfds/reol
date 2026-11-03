class_name ReolUITheme
extends RefCounted
## One small visual vocabulary for the demo, independent of simulation rules.

const PAPER := Color("#e6e1ce")
const MUTED := Color("#aab8ab")
const GOLD := Color("#d9be79")
const JADE := Color("#8fc3a9")
const INK := Color("#101c20")
const BORDER := Color("#52665e")
const WARNING := Color("#d9a478")

static var _shared: Theme


static func create() -> Theme:
	if _shared != null:
		return _shared
	var result := Theme.new()
	result.default_font_size = 14
	result.set_color("font_color", "Label", PAPER)
	result.set_color("default_color", "RichTextLabel", MUTED)
	result.set_color("font_color", "Button", PAPER)
	result.set_color("font_hover_color", "Button", Color.WHITE)
	result.set_color("font_pressed_color", "Button", GOLD)
	result.set_color("font_disabled_color", "Button", Color("#73807a"))
	result.set_stylebox("panel", "PanelContainer", panel())
	result.set_stylebox("normal", "Button", _button_box(Color("#243631"), BORDER))
	result.set_stylebox("hover", "Button", _button_box(Color("#344d42"), JADE))
	result.set_stylebox("pressed", "Button", _button_box(Color("#3c4a38"), GOLD))
	result.set_stylebox("disabled", "Button", _button_box(Color("#182624"), Color("#30413b")))
	var focus: StyleBoxFlat = _button_box(Color(0, 0, 0, 0), GOLD)
	focus.set_border_width_all(2)
	result.set_stylebox("focus", "Button", focus)
	result.set_constant("separation", "HBoxContainer", 6)
	result.set_constant("separation", "VBoxContainer", 6)
	result.set_constant("h_separation", "GridContainer", 6)
	result.set_constant("v_separation", "GridContainer", 6)
	result.set_stylebox("background", "ProgressBar", _button_box(Color("#23332d"), Color("#23332d")))
	result.set_stylebox("fill", "ProgressBar", _button_box(JADE.darkened(0.25), JADE.darkened(0.25)))
	_shared = result
	return result


static func panel(accent: Color = BORDER) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(INK, 0.96)
	style.border_color = accent
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0, 0, 0, 0.2)
	style.shadow_size = 5
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


static func label(parent: Node, text_value: String = "", color: Color = PAPER, font_size: int = 14) -> Label:
	var result := Label.new()
	result.text = text_value
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_color_override("font_color", color)
	result.add_theme_font_size_override("font_size", font_size)
	parent.add_child(result)
	return result


static func button(parent: Node, caption: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = caption
	result.custom_minimum_size.y = 30
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.focus_mode = Control.FOCUS_ALL
	result.pressed.connect(callback)
	parent.add_child(result)
	return result


static func _button_box(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style
