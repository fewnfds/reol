extends RefCounted
## Shared native Control appearance and cached action glyphs.
const GOLD := Color("e6be71")
const TEAL := Color("7dc7be")
const DANGER := Color("dc827c")
static var _icons: Dictionary = {}

static func theme() -> Theme:
	var value := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	value.default_font = font
	value.default_font_size = 16
	value.set_stylebox("panel", "PanelContainer", box(Color("18251ff2"), Color("50665a")))
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var border: Color = GOLD if state in ["pressed", "focus"] else Color("52695d")
		var fill := Color("263a30") if state == "normal" else Color("3b5040")
		if state == "disabled": fill = Color("1d2923")
		value.set_stylebox(state, "Button", box(fill, border))
	value.set_color("font_color", "Button", Color("e0e8df"))
	value.set_color("font_disabled_color", "Button", Color("59685f"))
	value.set_color("font_color", "Label", Color("e1e7df"))
	value.set_constant("separation", "HBoxContainer", 6)
	value.set_constant("separation", "VBoxContainer", 6)
	value.set_constant("h_separation", "GridContainer", 6)
	value.set_constant("v_separation", "GridContainer", 6)
	value.set_constant("icon_max_width", "Button", 24)
	return value

static func box(fill: Color, border: Color) -> StyleBoxFlat:
	var value := StyleBoxFlat.new()
	value.bg_color = fill
	value.border_color = border
	value.set_border_width_all(1)
	value.set_corner_radius_all(4)
	value.content_margin_left = 8
	value.content_margin_right = 8
	value.content_margin_top = 6
	value.content_margin_bottom = 6
	return value

static func label(parent: Node, text: String = "") -> Label:
	var value := Label.new()
	value.text = text
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(value)
	return value

static func icon(key: String) -> Texture2D:
	if _icons.has(key): return _icons[key]
	var paths: Dictionary = {
		"bow": "M5 3q20 9 0 18L12 12zM3 12h18m-4-4 4 4-4 4",
		"robe": "M8 3h8l6 7-5 3v9H7v-9l-5-3zM8 3l4 7 4-7M12 10v12",
		"boots": "M4 3h6v12l4 2v5H3v-7zM14 3h6v12l3 2v5h-7",
		"charm": "M10 2h4v5M12 6l8 7-8 9-8-9zM9 13h6M12 10v6",
		"move": "M4 12h15m-6-6 6 6-6 6", "attack": "m5 19 14-14m-5 0h5v5M4 15l5 5",
		"stop": "M6 6h12v12H6z", "hold": "M12 3 4 7v6c0 4 8 8 8 8s8-4 8-8V7z",
		"work": "m4 5 15 15m-2-17 4 4-7 7-4-4z", "bag": "M4 8h16v13H4zM8 8V4h8v4",
		"person": "M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0M4 21c0-9 16-9 16 0",
		"plant": "M12 21V9M12 14C2 14 3 4 3 4s9 0 9 10M12 11C12 3 21 3 21 3s0 8-9 8",
		"map": "m2 5 7-3 6 3 7-3v17l-7 3-6-3-7 3zM9 2v17M15 5v17",
		"build": "m3 11 9-8 9 8M5 9v12h14V9M10 21v-7h4v7",
		"close": "m5 5 14 14M19 5 5 19", "rotate": "M20 9a8 8 0 1 0 0 6M20 3v6h-6",
		"eye": "M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0",
		"memory": "M12 3a9 9 0 1 1-9 9M12 6v6l4 3M3 3v6h6",
		"lock": "M5 10h14v11H5zM8 10V6a4 4 0 0 1 8 0v4", "play": "m7 3 14 9-14 9z",
		"pause": "M7 3v18M17 3v18", "menu": "M4 5h16M4 12h16M4 19h16",
		"save": "M4 3h14l3 3v15H3V3zM7 3v6h10V3M7 21v-8h10v8",
		"load": "M3 9h18v12H3zM7 9V4h10v5M12 12v6m-3-3 3 3 3-3",
		"check": "m4 12 5 5L20 5", "take": "M4 4h16v6H4zM12 11v10m-5-5 5 5 5-5",
		"put": "M4 14h16v7H4zM12 13V3m-5 5 5-5 5 5", "drop": "M3 19h18M12 3v12m-5-5 5 5 5-5",
		"talk": "M3 3h18v13H9l-6 5zM7 8h10M7 12h6", "link": "m9 15 6-6M7 10 4 13a5 5 0 0 0 7 7l3-3M10 7l3-3a5 5 0 0 1 7 7l-3 3",
		"potion": "M9 2h6v6l5 9q2 5-8 5T4 17l5-9zM7 14h10",
		"book": "M3 3h7l2 2 2-2h7v17h-7l-2 2-2-2H3zM12 5v17",
		"gear": "M12 3v4M12 17v4M3 12h4M17 12h4M6 6l3 3M15 15l3 3M6 18l3-3M15 9l3-3M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0",
		"skull": "M5 15a9 9 0 1 1 14 0v6H5zM8 18h8M9 10v3M15 10v3",
		"target": "M12 1v6M12 17v6M1 12h6M17 12h6M19 12a7 7 0 1 1-14 0 7 7 0 0 1 14 0"}
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path d="%s" fill="none" stroke="#e5e9de" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>' % str(paths.get(key, paths.gear))
	var bitmap := Image.new()
	bitmap.load_svg_from_string(svg)
	_icons[key] = ImageTexture.create_from_image(bitmap)
	return _icons[key]
