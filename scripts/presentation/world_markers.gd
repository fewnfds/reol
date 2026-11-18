extends RefCounted
## One screen-space overlay for observed names and the current selection.
const Art = preload("res://scripts/presentation/art.gd")
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const SubjectView = preload("res://scripts/presentation/ui/subject_view.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")
const Relation = preload("res://scripts/sim/kernel/frame.gd").NameRelation
const NAME_COLORS: Dictionary = {
	Relation.NEUTRAL: Color("f4d78d"),
	Relation.FELLOW: Color("8fc6ff"),
	Relation.REPORT: Color("a7ed97"),
	Relation.HOSTILE: Color("f96c66"),
}
const NAME_SIZE: int = 12
const NAME_ZOOM: float = 0.60
const OUTLINE := Color("182326")
var font: Font
var _observed: Dictionary = {}
var _text: Dictionary = {}


static func selection_rect(host: Node2D) -> Rect2:
	var frame: RefCounted = host.frame
	var id: int = host.selected
	if frame.actor_slots.has(id):
		if not SubjectView.visible(frame, id, host.fog_enabled): return Rect2()
		return Rect2(host._displayed(id) * Art.TILE - Vector2(13, 7), Vector2(26, 14))
	var descriptions: Dictionary = frame.perception.get("memories", {}) if host.fog_enabled else frame.objects
	var record: Dictionary = descriptions.get(id, {})
	if not record.is_empty():
		var extent := Rect2i(Terrain.cell(int(record.tile)), Vector2i.ONE)
		for tile: int in record.get("cells", PackedInt32Array()):
			extent = extent.merge(Rect2i(Terrain.cell(tile), Vector2i.ONE))
		return Rect2(Vector2(extent.position) * Art.TILE, Vector2(extent.size) * Art.TILE)
	if host.selected_tile >= 0 and (id == 0 or frame.entities.has(id)):
		return Rect2(Vector2(Terrain.cell(host.selected_tile)) * Art.TILE, Vector2.ONE * Art.TILE)
	return Rect2()


func paint(canvas: Node2D, host: Node2D) -> void:
	if host.frame == null: return
	var labels: Dictionary = host.frame.actor_labels
	if not is_same(_observed, labels):
		for id: int in _text.keys():
			if not labels.has(id) or labels[id].name != _observed[id].name: _text.erase(id)
		_observed = labels
	var viewport_rect: Rect2 = canvas.get_viewport_rect()
	if host.camera.zoom.x >= NAME_ZOOM:
		for id: int in labels:
			if id != host.selected: _paint_name(canvas, host, id, viewport_rect)
	if labels.has(host.selected): _paint_name(canvas, host, host.selected, viewport_rect)
	var selection: Rect2 = selection_rect(host)
	if selection.has_area():
		var screen := Rect2(host.view.project(selection.position), selection.size * host.camera.zoom)
		_paint_corners(canvas, screen, Style.GOLD if host.selected == 1 else Color("92e6f1"))


func _paint_name(canvas: Node2D, host: Node2D, id: int, viewport_rect: Rect2) -> void:
	var slot: int = int(host.frame.actor_slots.get(id, -1))
	if slot < 0 or host.frame.health[slot] <= 0 or not SubjectView.visible(host.frame, id, host.fog_enabled): return
	var foot: Vector2 = host.view.project(host._displayed(id) * Art.TILE)
	if not _text.has(id):
		var line := TextLine.new()
		line.add_string(_observed[id].name, font, NAME_SIZE)
		_text[id] = line
	var text: TextLine = _text[id]
	var size: Vector2 = text.get_size()
	var origin: Vector2 = (foot + Vector2(-0.5 * size.x, 5.0 * host.camera.zoom.y)).round()
	if not viewport_rect.intersects(Rect2(origin, size).grow(2.0)): return
	var rid: RID = canvas.get_canvas_item()
	text.draw_outline(rid, origin, 2, OUTLINE)
	text.draw(rid, origin, NAME_COLORS[_observed[id].relation])


static func _paint_corners(canvas: Node2D, rect: Rect2, color: Color) -> void:
	var shortest: float = minf(rect.size.x, rect.size.y)
	var length: float = minf(9.0, shortest * 0.25)
	var width: float = minf(2.0, shortest * 0.18)
	var points := PackedVector2Array()
	for x: int in 2:
		for y: int in 2:
			var corner: Vector2 = rect.position + rect.size * Vector2(x, y)
			points.append_array(PackedVector2Array([
				corner, corner + Vector2((1 - 2 * x) * length, 0),
				corner, corner + Vector2(0, (1 - 2 * y) * length),
			]))
	canvas.draw_multiline(points, OUTLINE, width + minf(2.0, width), true)
	canvas.draw_multiline(points, color, width, true)
