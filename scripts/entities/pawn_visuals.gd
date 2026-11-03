class_name PawnVisuals
extends RefCounted
## Shared layered presentation, with a vector fallback for missing assets.
## It owns presentation only, never body state or clothing custody.

const Appearance = preload("res://scripts/entities/humanoid_appearance.gd")

const INK := Color("#243237")
const SKIN := Color("#dfc9a5")
const GOLD := Color("#e2c581")
const PAPER := Color("#eee4cb")
const NAME_WIDTH: float = 132.0
const NAME_SIZE: int = 13


static func draw_actor(
	canvas: CanvasItem, ground: Vector2, body: Vector2, robe: Color,
	caption: String, selected: bool, player: bool = false, clothing: Dictionary = {}, pose: Dictionary = {}
) -> void:
	if clothing.has("body"):
		robe = Color(str(clothing.body.color))
		if clothing.body.wet:
			robe = robe.darkened(0.28)
	# The oval stays on the ground when the body is at a higher altitude.
	canvas.draw_set_transform(ground + Vector2(2, 4), 0.0, Vector2(1.0, 0.42))
	canvas.draw_circle(Vector2.ZERO, 15.0, Color(0.04, 0.08, 0.08, 0.34))
	canvas.draw_set_transform(Vector2.ZERO)
	if selected:
		canvas.draw_arc(ground + Vector2(0, 3), 20.0, 0.15, PI - 0.15, 20, GOLD, 2.0, true)
		canvas.draw_arc(ground + Vector2(0, 3), 20.0, PI + 0.15, TAU - 0.15, 20, GOLD, 2.0, true)
	if Appearance.shared().draw_layers(canvas, body + Vector2(0, 13), robe, clothing, pose):
		draw_caption(canvas, body + Vector2(0, -37), caption, GOLD if selected else PAPER)
		return
	# Feet, tapered robe, sleeves and crossed lapel stay readable at low zoom.
	canvas.draw_rect(Rect2(body + Vector2(-7, 7), Vector2(5, 6)), INK)
	canvas.draw_rect(Rect2(body + Vector2(3, 7), Vector2(5, 6)), INK)
	var outline := PackedVector2Array([
		body + Vector2(-8, -13), body + Vector2(8, -13),
		body + Vector2(12, 7), body + Vector2(6, 10),
		body + Vector2(-7, 10), body + Vector2(-12, 7),
	])
	canvas.draw_colored_polygon(outline, robe.darkened(0.22))
	canvas.draw_colored_polygon(PackedVector2Array([
		body + Vector2(-7, -12), body + Vector2(6, -12),
		body + Vector2(8, 7), body + Vector2(-8, 7),
	]), robe)
	canvas.draw_line(body + Vector2(-6, -12), body + Vector2(3, -3), PAPER.darkened(0.16), 2.0)
	canvas.draw_line(body + Vector2(6, -12), body + Vector2(-3, -3), robe.darkened(0.4), 2.0)
	canvas.draw_rect(Rect2(body + Vector2(-8, -1), Vector2(16, 3)), INK.lightened(0.08))
	canvas.draw_circle(body + Vector2(-12, -5), 2.5, SKIN)
	canvas.draw_circle(body + Vector2(12, -5), 2.5, SKIN)
	if clothing.has("outer"):
		var cape: Color = Color(str(clothing.outer.color))
		canvas.draw_colored_polygon(PackedVector2Array([
			body + Vector2(-9, -15), body + Vector2(9, -15),
			body + Vector2(17, 6), body + Vector2(9, 12),
			body + Vector2(-9, 12), body + Vector2(-17, 6),
		]), cape.darkened(0.2))
		for index: int in range(-3, 4):
			canvas.draw_line(body + Vector2(index * 2, -12), body + Vector2(index * 4, 9), cape.lightened(0.12), 2.0, true)
		canvas.draw_line(body + Vector2(-8, -11), body + Vector2(8, -11), INK, 2.0)
	canvas.draw_circle(body + Vector2(0, -20), 7.0, INK)
	canvas.draw_circle(body + Vector2(0, -18), 5.5, SKIN)
	canvas.draw_arc(body + Vector2(0, -20), 6.0, PI, TAU, 12, INK, 4.0, true)
	canvas.draw_circle(body + Vector2(0, -27), 3.0, INK)
	if player:
		canvas.draw_line(body + Vector2(-4, -26), body + Vector2(5, -26), GOLD, 2.0)
	draw_caption(canvas, body + Vector2(0, -37), caption, GOLD if selected else PAPER)


static func draw_caption(canvas: CanvasItem, baseline: Vector2, caption: String, color: Color = PAPER) -> void:
	if caption.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var width: float = minf(NAME_WIDTH, font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x)
	canvas.draw_style_box(_name_backing(), Rect2(baseline + Vector2(-width * 0.5 - 5, -13), Vector2(width + 10, 18)))
	canvas.draw_string_outline(font, baseline + Vector2(-NAME_WIDTH * 0.5, 0), caption, HORIZONTAL_ALIGNMENT_CENTER, NAME_WIDTH, NAME_SIZE, 2, Color(0.04, 0.07, 0.08, 0.9))
	canvas.draw_string(font, baseline + Vector2(-NAME_WIDTH * 0.5, 0), caption, HORIZONTAL_ALIGNMENT_CENTER, NAME_WIDTH, NAME_SIZE, color)


static func _name_backing() -> StyleBoxFlat:
	# A shared style avoids allocating one resource for every actor redraw.
	if _caption_style == null:
		_caption_style = StyleBoxFlat.new()
		_caption_style.bg_color = Color(0.035, 0.065, 0.065, 0.7)
		_caption_style.set_corner_radius_all(3)
	return _caption_style


static var _caption_style: StyleBoxFlat
