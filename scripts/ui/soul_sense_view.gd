class_name SoulSenseView
extends Control
## Abstract spiritual perception. This screen never receives world truth objects.

var perception: Dictionary = {}
var selected: String = ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func update_perception(view: Dictionary, selected_id: String) -> void:
	perception = view.duplicate(true)
	selected = selected_id
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#09191f"))
	var center: Vector2 = size * Vector2(0.53, 0.48)
	for radius: float in [72.0, 144.0, 216.0, 278.0]:
		draw_arc(center, radius, 0.0, TAU, 72, Color("#203e45"), 1)
	draw_line(center + Vector2(-290, 0), center + Vector2(290, 0), Color("#19333b"), 1)
	draw_line(center + Vector2(0, -230), center + Vector2(0, 230), Color("#19333b"), 1)
	var awake: bool = bool(perception.get("awake", false))
	var own_color := Color("#d6b973") if awake else Color("#627a7e")
	draw_circle(center, 28, Color("#142c34"))
	draw_arc(center, 18, 0.35, TAU - 0.35, 32, own_color, 4)
	draw_line(center + Vector2(12, -12), center + Vector2(24, -26), Color("#72b7b3"), 2)
	var font: Font = ThemeDB.fallback_font
	draw_string(font, center + Vector2(-54, 56), "你所在的封纹", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, own_color)
	var labels: Array[Rect2] = [Rect2(center + Vector2(-58, 35), Vector2(120, 24))]
	var signal_index: int = 0
	for signal_row: Dictionary in perception.get("signals", []):
		signal_index += 1
		var offset := Vector2(float(signal_row.offset[0]), float(signal_row.offset[1]))
		var point: Vector2 = center + offset * 0.85
		if offset.length() < 36:
			point += Vector2(32, -24)
		var color := Color("#d4c589") if signal_row.id == selected else Color("#7bb7b1")
		draw_circle(point, 8, color)
		draw_arc(point, 16, 0, TAU, 24, Color(color, 0.45), 2)
		var caption: String = "气息%d" % signal_index if signal_row.label == "一道呼吸的气息" else str(signal_row.label)
		var width: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 8
		var label_point: Vector2 = point + Vector2(-width * 0.5, -24)
		for _attempt in range(16):
			var bounds := Rect2(label_point - Vector2(0, 16), Vector2(width, 20))
			var overlap: bool = false
			for placed: Rect2 in labels:
				overlap = overlap or bounds.intersects(placed)
			if not overlap:
				labels.append(bounds)
				break
			label_point.y -= 22
		if label_point.y < point.y - 26:
			draw_line(point + Vector2(0, -16), label_point + Vector2(width * 0.5, 5), Color(color, 0.35), 1)
		draw_string_outline(font, label_point, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color("#09191f"))
		draw_string(font, label_point, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
	draw_string(font, Vector2(28, 140), "封纹内外 · 仅呈现你此刻感到的灵机", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#71999b"))
