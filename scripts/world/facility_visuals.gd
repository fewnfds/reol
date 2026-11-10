class_name FacilityVisuals
extends RefCounted
## Small orthographic silhouettes for facilities. No nodes, rules or inventory.

const INK := Color("#22302f")
const WALL := Color("#b9b08d")
const ROOF := Color("#546d68")
const TIMBER := Color("#7f6747")
const LABEL_WIDTH: float = 152.0


static func draw_facility(canvas: CanvasItem, place_id: String, point: Vector2, label: String, accent: Color, herb_phase: String = "", workspace: Dictionary = {}, known_cell: Callable = Callable()) -> void:
	canvas.draw_set_transform(point)
	match place_id:
		"well": _draw_well(canvas, point)
		"garden": _draw_garden(canvas, herb_phase)
		"gate": _draw_gate(canvas, accent)
		"records":
			if not workspace.is_empty():
				_draw_office(canvas, workspace, known_cell)
			else:
				_draw_work_area(canvas, place_id, accent)
		_: _draw_work_area(canvas, place_id, accent)
	canvas.draw_set_transform(Vector2.ZERO)
	if not workspace.is_empty() and known_cell.is_valid() and not bool(known_cell.call(SimRouteTravel.cell(workspace.clerk_cell))):
		return # Seeing an outside wall does not identify the hidden workplace.
	var font: Font = ThemeDB.fallback_font
	var baseline: Vector2 = point + Vector2(-LABEL_WIDTH * 0.5, -38)
	canvas.draw_string_outline(font, baseline, label, HORIZONTAL_ALIGNMENT_CENTER, LABEL_WIDTH, 13, 3, Color(0.04, 0.07, 0.07, 0.95))
	canvas.draw_string(font, baseline, label, HORIZONTAL_ALIGNMENT_CENTER, LABEL_WIDTH, 13, accent.lightened(0.35))


static func _draw_office(canvas: CanvasItem, layout: Dictionary, known_cell: Callable) -> void:
	var anchor: Vector2i = SimRouteTravel.cell(layout.clerk_cell)
	for raw: Array in layout.roof:
		if known_cell.is_valid() and not bool(known_cell.call(SimRouteTravel.cell(raw))):
			continue
		var offset: Vector2 = Vector2(SimRouteTravel.cell(raw) - anchor) * TileGrid.TILE_SIZE
		canvas.draw_rect(Rect2(offset - Vector2.ONE * 32, Vector2.ONE * 64), Color("#8e8061"))
		canvas.draw_rect(Rect2(offset - Vector2.ONE * 31, Vector2.ONE * 62), Color("#9e8f70"))
		canvas.draw_line(offset + Vector2(-30, -10), offset + Vector2(30, -10), Color("#938366"), 1.0)
	for raw: Array in layout.walls:
		if known_cell.is_valid() and not bool(known_cell.call(SimRouteTravel.cell(raw))):
			continue
		var offset: Vector2 = Vector2(SimRouteTravel.cell(raw) - anchor) * TileGrid.TILE_SIZE
		canvas.draw_rect(Rect2(offset + Vector2(-31, -20), Vector2(62, 45)), INK)
		canvas.draw_rect(Rect2(offset + Vector2(-28, -17), Vector2(56, 36)), WALL)
		canvas.draw_rect(Rect2(offset + Vector2(-29, -23), Vector2(58, 8)), TIMBER)
	if not known_cell.is_valid() or bool(known_cell.call(SimRouteTravel.cell(layout.door))):
		var door: Vector2 = Vector2(SimRouteTravel.cell(layout.door) - anchor) * TileGrid.TILE_SIZE
		canvas.draw_rect(Rect2(door + Vector2(-29, -23), Vector2(6, 45)), TIMBER)
		canvas.draw_rect(Rect2(door + Vector2(23, -23), Vector2(6, 45)), TIMBER)
	for id: String in ["desk", "archive"]:
		if known_cell.is_valid() and not bool(known_cell.call(SimRouteTravel.cell(layout.fixtures[id].cell))):
			continue
		var offset: Vector2 = Vector2(SimRouteTravel.cell(layout.fixtures[id].cell) - anchor) * TileGrid.TILE_SIZE
		canvas.draw_rect(Rect2(offset + Vector2(-24, -19), Vector2(48, 38)), INK)
		canvas.draw_rect(Rect2(offset + Vector2(-21, -16), Vector2(42, 31)), TIMBER)
		if id == "desk":
			canvas.draw_rect(Rect2(offset + Vector2(-13, -12), Vector2(16, 20)), Color("#d7d0aa"))
			for row: int in 3:
				canvas.draw_line(offset + Vector2(-10, -7 + row * 5), offset + Vector2(-2, -7 + row * 5), INK, 1.0)
			canvas.draw_rect(Rect2(offset + Vector2(10, -8), Vector2(5, 10)), Color("#2a4446"))
		else:
			for row: int in 3:
				canvas.draw_rect(Rect2(offset + Vector2(-17, -12 + row * 8), Vector2(34, 6)), Color("#b7b499"))
			canvas.draw_rect(Rect2(offset + Vector2(3, -12), Vector2(9, 18)), Color("#6cb2a0"))
			canvas.draw_rect(Rect2(offset + Vector2(5, -9), Vector2(5, 11)), Color("#a4d1b5"))
	# Cutaway projection: the saved roof still shelters the actual room.
	if not known_cell.is_valid() or bool(known_cell.call(anchor)):
		canvas.draw_rect(Rect2(-15, 3, 30, 24), TIMBER.darkened(0.1), false, 3.0)


static func _draw_work_area(canvas: CanvasItem, kind: String, accent: Color) -> void:
	canvas.draw_rect(Rect2(-27, -23, 54, 46), Color(0.24, 0.24, 0.18, 0.35))
	match kind:
		"kitchen":
			canvas.draw_rect(Rect2(-23, -18, 29, 33), Color("#79796a"))
			canvas.draw_circle(Vector2(-9, -5), 10, INK)
			canvas.draw_circle(Vector2(-9, -5), 7, Color("#aa7650"))
			canvas.draw_rect(Rect2(10, -15, 16, 29), TIMBER)
			canvas.draw_rect(Rect2(12, -11, 12, 5), WALL)
		"store":
			for row: int in 3:
				canvas.draw_rect(Rect2(-24, -19 + row * 13, 48, 10), TIMBER.darkened(0.1))
				canvas.draw_rect(Rect2(-19, -17 + row * 13, 16, 6), Color("#b9b18b"))
				canvas.draw_rect(Rect2(5, -17 + row * 13, 15, 6), Color("#9b875c"))
		"dorm":
			for column: int in 2:
				canvas.draw_rect(Rect2(-25 + column * 28, -22, 23, 45), TIMBER)
				canvas.draw_rect(Rect2(-22 + column * 28, -18, 17, 9), WALL)
				canvas.draw_rect(Rect2(-22 + column * 28, -6, 17, 24), ROOF)
		_:
			canvas.draw_rect(Rect2(-23, -14, 46, 28), TIMBER)
			canvas.draw_rect(Rect2(-15, -10, 18, 16), WALL)
			canvas.draw_line(Vector2(-11, -6), Vector2(-1, -6), accent, 2.0)


static func _draw_building(canvas: CanvasItem, kind: String, accent: Color) -> void:
	canvas.draw_rect(Rect2(-21, -10, 42, 30), INK)
	canvas.draw_rect(Rect2(-18, -8, 36, 25), WALL)
	canvas.draw_rect(Rect2(-6, 1, 12, 19), TIMBER.darkened(0.3))
	canvas.draw_rect(Rect2(-16, -4, 7, 8), ROOF.darkened(0.25))
	canvas.draw_rect(Rect2(9, -4, 7, 8), ROOF.darkened(0.25))
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(-27, -11), Vector2(-18, -28), Vector2(18, -28), Vector2(27, -11),
	]), INK)
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(-23, -13), Vector2(-16, -25), Vector2(16, -25), Vector2(23, -13),
	]), ROOF)
	canvas.draw_line(Vector2(-17, -26), Vector2(17, -26), accent.darkened(0.05), 2.0)
	canvas.draw_line(Vector2(-26, -11), Vector2(26, -11), INK, 3.0)
	match kind:
		"kitchen":
			canvas.draw_rect(Rect2(11, -34, 7, 12), INK)
			canvas.draw_rect(Rect2(13, -33, 3, 9), TIMBER)
			canvas.draw_circle(Vector2(-5, 6), 2.0, Color("#d99e62"))
		"store":
			canvas.draw_rect(Rect2(13, 8, 12, 12), TIMBER.darkened(0.2))
			canvas.draw_line(Vector2(14, 9), Vector2(24, 19), WALL, 1.0)
			canvas.draw_line(Vector2(24, 9), Vector2(14, 19), WALL, 1.0)
		"records":
			canvas.draw_rect(Rect2(-12, -9, 24, 7), INK)
			canvas.draw_line(Vector2(-7, -6), Vector2(7, -6), accent, 2.0)
			canvas.draw_rect(Rect2(-22, -8, 3, 28), TIMBER)
			canvas.draw_rect(Rect2(19, -8, 3, 28), TIMBER)
		"dorm":
			canvas.draw_rect(Rect2(8, 0, 9, 12), ROOF.darkened(0.35))
			canvas.draw_line(Vector2(12, 0), Vector2(12, 12), WALL.darkened(0.15), 1.0)


static func _draw_well(canvas: CanvasItem, point: Vector2) -> void:
	canvas.draw_set_transform(point + Vector2(0, 7), 0.0, Vector2(1.0, 0.55))
	canvas.draw_circle(Vector2.ZERO, 20.0, INK)
	canvas.draw_circle(Vector2.ZERO, 16.0, Color("#9da69a"))
	canvas.draw_circle(Vector2.ZERO, 11.0, Color("#29434b"))
	canvas.draw_set_transform(point)
	canvas.draw_rect(Rect2(-20, -17, 4, 27), TIMBER)
	canvas.draw_rect(Rect2(16, -17, 4, 27), TIMBER)
	canvas.draw_rect(Rect2(-24, -20, 48, 5), INK)
	canvas.draw_line(Vector2(1, -16), Vector2(1, 7), WALL, 1.5)
	canvas.draw_rect(Rect2(-4, 4, 10, 7), TIMBER.lightened(0.12))


static func _draw_garden(canvas: CanvasItem, herb_phase: String) -> void:
	canvas.draw_rect(Rect2(-25, -21, 50, 42), Color(0.2, 0.31, 0.2, 0.4))
	var leaf: Color = Color("#74966c")
	var tip: Color = Color("#afbd83")
	var height: float = 6.0
	match herb_phase:
		"unknown":
			leaf = Color("#7b8470")
			tip = leaf
		"dry":
			leaf = Color("#a18b56")
			tip = Color("#bdab73")
			height = 3.0
		"dormant":
			leaf = Color("#7b897c")
			tip = Color("#a1ac99")
			height = 2.0
		"growing":
			height = 4.0
	for row: int in range(3):
		var y: float = -12.0 + row * 11.0
		for column: int in range(4):
			var x: float = -15.0 + column * 10.0 + float((row * 3 + column) % 5 - 2)
			canvas.draw_rect(Rect2(x, y + 2 - height, 2, height), tip)
			canvas.draw_rect(Rect2(x - 3, y + 3 - height, 3, 2), leaf)
			canvas.draw_rect(Rect2(x + 2, y + 1 - height, 3, 2), tip)
			if herb_phase == "harvestable":
				canvas.draw_rect(Rect2(x, y - height, 3, 2), Color("#d8d29e"))
	canvas.draw_rect(Rect2(21, -19, 3, 12), TIMBER)
	canvas.draw_rect(Rect2(19, -22, 8, 6), WALL)


static func _draw_gate(canvas: CanvasItem, accent: Color) -> void:
	canvas.draw_rect(Rect2(-23, -24, 6, 45), TIMBER.darkened(0.2))
	canvas.draw_rect(Rect2(17, -24, 6, 45), TIMBER.darkened(0.2))
	canvas.draw_rect(Rect2(-26, -24, 52, 7), INK)
	canvas.draw_line(Vector2(-28, -27), Vector2(28, -27), ROOF, 5.0)
	canvas.draw_rect(Rect2(-11, -20, 22, 10), INK)
	canvas.draw_line(Vector2(-6, -15), Vector2(6, -15), accent, 2.0)
	canvas.draw_rect(Rect2(-25, 17, 10, 5), Color("#8f9684"))
	canvas.draw_rect(Rect2(15, 17, 10, 5), Color("#8f9684"))
