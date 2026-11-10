class_name PawnViewLayout
extends RefCounted
## Cell sharing is a simulation fact; spreading the drawings is presentation only.

const CROWD_RADIUS: float = 24.0


static func build(actors: Dictionary, center_actor_id: String = "", visitor_cell: Variant = null, at_ms: int = -1, native_routes: Dictionary = {}) -> Dictionary:
	var groups: Dictionary = {}
	var positions: Dictionary[String, Vector2] = {}
	for id: String in actors:
		var raw_cell: Variant = actors[id].get("cell", [])
		if not raw_cell is Array or raw_cell.size() != 2:
			continue
		var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		if at_ms >= 0:
			var body: Dictionary = actors[id]
			var route: Dictionary = body.get("active", {})
			var completion: Dictionary = native_routes.get(id, {})
			if route.get("phase") == "travel" and bool(completion.get("coarse", false)) and is_same(completion.route, route):
				var timeline: SimRouteTravel.Timeline = completion.timeline
				positions[id] = timeline.point_at(at_ms)
			else:
				positions[id] = SimRouteTravel.projected_point(route, body, at_ms) if route.get("phase") == "travel" else SimRouteTravel.point(body)
			cell = TileGrid.world_to_cell(positions[id])
		if not groups.has(cell):
			groups[cell] = []
		groups[cell].append(id)
	var result: Dictionary = {}
	for cell: Vector2i in groups:
		var ids: Array = groups[cell]
		ids.sort()
		var has_center: bool = ids.has(center_actor_id)
		var has_visitor: bool = visitor_cell is Vector2i and visitor_cell == cell
		var crowded: bool = ids.size() + (1 if has_visitor and not has_center else 0) > 1
		if has_center:
			result[center_actor_id] = {"offset": Vector2.ZERO, "caption_visible": true}
			ids.erase(center_actor_id)
		for index: int in ids.size():
			var offset := Vector2.ZERO
			if crowded:
				var angle: float = -PI * 0.5 + TAU * float(index) / float(ids.size())
				offset = Vector2(cos(angle), sin(angle)) * CROWD_RADIUS
			result[ids[index]] = {"offset": offset, "caption_visible": not crowded}
	for id: String in positions:
		result[id].position = positions[id]
		result[id].cell = TileGrid.world_to_cell(positions[id])
	return result
