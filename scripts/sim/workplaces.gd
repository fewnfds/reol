class_name SimWorkplaces
extends RefCounted
## Fixed opening rooms are saved in their original place, not regenerated on load.
## Furniture grants access to an existing institutional book; it issues no rights.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const RULES_PATH: String = "res://data/definitions/workplaces.json"
const VERSION: int = 1



static func return_action(_rules: Dictionary) -> Dictionary:
	return _rules.return_action.duplicate(true)


static func enable_opening(config: Dictionary, places: Dictionary, actor_cells: Dictionary, terrain: WorldMapData, institution_id: String, _rules: Dictionary) -> bool:
	if config.has("workplaces_version") or not config.get("actions") is Dictionary or not config.get("institution") is Dictionary or config.institution.get("id") != institution_id:
		return false
	var candidate: Dictionary = places.duplicate(true)
	if not attach_opening_layout(candidate, actor_cells, terrain, institution_id, _rules):
		return false
	var settings: Dictionary = config.duplicate(true)
	settings["workplaces_version"] = VERSION
	settings.actions["workspace_return"] = return_action(_rules)
	if not valid_places(candidate, settings, terrain, _rules):
		return false
	places.clear()
	places.merge(candidate, true)
	config.clear()
	config.merge(settings, true)
	return true


static func attach_opening_layout(places: Dictionary, actor_cells: Dictionary, terrain: WorldMapData, institution_id: String, _rules: Dictionary) -> bool:
	if not valid_rules(_rules) or terrain == null or not SimInventory._nonempty(institution_id) or not places.get("records") is Dictionary or not Shape.cell_valid(places.records.get("cell")):
		return false
	for place: Variant in places.values():
		if not place is Dictionary or place.has("workspace"):
			return false
	var anchor: Vector2i = SimRouteTravel.cell(places.records.cell)
	var used: Dictionary = {}
	for place: Dictionary in places.values():
		if not Shape.cell_valid(place.get("cell")):
			return false
		used[SimRouteTravel.cell(place.cell)] = true
	for raw: Variant in actor_cells.values():
		var cell: Variant = raw.get("cell") if raw is Dictionary else raw
		if not Shape.cell_valid(cell):
			return false
		used[SimRouteTravel.cell(cell)] = true
	for template: int in range(_rules.room_templates.size()):
		for orientation: int in range(4):
			var layout: Dictionary = _layout(anchor, institution_id, template, orientation, _rules)
			if not _terrain_valid(layout, terrain):
				continue
			var occupied: bool = false
			for cell: Vector2i in _blocked_cells(layout):
				if used.has(cell):
					occupied = true
					break
			if occupied or not _entry_reachable(layout, terrain, used):
				continue
			places.records["workspace"] = layout
			return true
	return false


static func valid_places(places: Dictionary, config: Dictionary, terrain: WorldMapData = null, _rules: Dictionary = {}) -> bool:
	if not config.has("workplaces_version"):
		for place: Variant in places.values():
			if place is Dictionary and place.has("workspace"):
				return false
		return not config.get("actions", {}).has("workspace_return")
	if not valid_rules(_rules) or not Shape.count(config.workplaces_version, VERSION, VERSION) or not config.get("institution") is Dictionary or not SimInventory._nonempty(config.institution.get("id")) or not config.get("actions") is Dictionary or not Shape.same_record(config.actions.get("workspace_return"), return_action(_rules)):
		return false
	if not places.get("records") is Dictionary or not Shape.cell_valid(places.records.get("cell")):
		return false
	for id: Variant in places:
		if not places[id] is Dictionary or id != "records" and places[id].has("workspace"):
			return false
	var saved: Variant = places.records.get("workspace")
	if not saved is Dictionary or not Shape.count(saved.get("template"), 0, _rules.room_templates.size() - 1) or not Shape.count(saved.get("orientation"), 0, 3):
		return false
	var expected: Dictionary = _layout(SimRouteTravel.cell(places.records.cell), str(config.institution.id), int(saved.template), int(saved.orientation), _rules)
	if not _same_value(saved, expected):
		return false
	for raw: Array in expected.roof:
		if not Shape.cell_valid(raw):
			return false
	for place: Dictionary in places.values():
		if not Shape.cell_valid(place.get("cell")) or blocked(places, SimRouteTravel.cell(place.cell)):
			return false
	return terrain == null or _terrain_valid(expected, terrain)


static func actors_clear(places: Dictionary, actors: Dictionary) -> bool:
	for raw: Variant in actors.values():
		var cell: Variant = raw.get("cell") if raw is Dictionary else raw
		if not Shape.cell_valid(cell) or blocked(places, SimRouteTravel.cell(cell)):
			return false
		if raw is Dictionary:
			for step: Variant in raw.get("active", {}).get("path", []):
				if not Shape.cell_valid(step) or blocked(places, SimRouteTravel.cell(step)):
					return false
	return true


static func blocked(places: Dictionary, cell: Vector2i) -> bool:
	var layout: Dictionary = places.get("records", {}).get("workspace", {})
	if layout.is_empty():
		return false
	for raw: Array in layout.get("walls", []):
		if SimRouteTravel.cell(raw) == cell:
			return true
	for id: String in ["desk", "archive"]:
		if layout.get("fixtures", {}).get(id) is Dictionary and SimRouteTravel.cell(layout.fixtures[id].cell) == cell:
			return true
	return false


static func roofed(places: Dictionary, cell: Vector2i) -> bool:
	var layout: Dictionary = places.get("records", {}).get("workspace", {})
	for raw: Array in layout.get("roof", []):
		if SimRouteTravel.cell(raw) == cell:
			return true
	return false


static func wall_at(places: Dictionary, cell: Vector2i) -> bool:
	# A saved door coordinate is an opening, not a closed wall. Desk/archive
	# collision is deliberately independent of this physical wall fact.
	for raw: Array in places.get("records", {}).get("workspace", {}).get("walls", []):
		if SimRouteTravel.cell(raw) == cell:
			return true
	return false


static func has_desk_duty(sim: RefCounted, actor: String) -> bool:
	if sim.config.get("workplaces_version", 0) != VERSION or not sim.has_actor(actor):
		return false
	for permission: String in sim._content.workplaces.permissions:
		if sim.institutions.has_permission(str(sim.config.institution.id), actor, permission):
			return true
	return false


static func at_desk(sim: RefCounted, actor: String) -> bool:
	if not sim.has_actor(actor) or not sim.places.get("records", {}).get("workspace") is Dictionary:
		return false
	var layout: Dictionary = sim.places.records.workspace
	var point: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(layout.clerk_cell))
	return sim.actor_position(sim.actor_state(actor)).distance_to(point) <= float(sim._content.workplaces.desk_reach_px)


static func assessment(sim: RefCounted, issuer: String, permission: String, own_service_job: Dictionary = {}) -> Dictionary:
	if not sim.has_actor(issuer) or not bool(sim.actor_state(issuer).alive) or not sim.institutions.has_permission(str(sim.config.institution.id), issuer, permission):
		return _reply(false, "no_authority", "桌案不能代替任职；此人无权代表当地办理。")
	if not sim.config.has("workplaces_version"):
		return _reply(true, "legacy_counter", "沿用原有柜台办理。") if own_service_job.is_empty() else _reply(false, "records_unavailable", "现场核验须回到实际桌案与登记载体前办理。")
	if not valid_places(sim.places, sim.config, null, sim._content.workplaces):
		return _reply(false, "records_unavailable", "值事房或机构记功簿不可用，公账暂不能办理。")
	if not at_desk(sim, issuer):
		return _reply(false, "off_duty", "有权人暂未回到桌前，待其归岗再核验公账。")
	var available: bool = sim.workspace_action_available(issuer)
	if not own_service_job.is_empty():
		available = Shape.keys(own_service_job, ["services", "id"]) and own_service_job.services is SettlementServices and own_service_job.id is String and own_service_job.services.workplace_job_available(sim, issuer, str(own_service_job.id))
	if not available:
		return _reply(false, "officer_busy", "值事人正忙于别事，尚不能分身核验。")
	var response: Dictionary = _reply(true, "ready", "桌案、机构记功簿和在岗值事人均可用。")
	response["carrier"] = str(sim.places.records.workspace.fixtures.register.id)
	response["institution"] = str(sim.config.institution.id)
	return response


static func _layout(anchor: Vector2i, institution: String, template: int, orientation: int, _rules: Dictionary) -> Dictionary:
	var rule: Dictionary = _rules.room_templates[template]
	var bounds := Rect2i(SimRouteTravel.cell(rule.origin), SimRouteTravel.cell(rule.size))
	var door: Vector2i = anchor + _rotate(Vector2i(0, bounds.end.y - 1), orientation)
	var walls: Array = []
	var roof: Array = []
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var cell: Vector2i = anchor + _rotate(Vector2i(x, y), orientation)
			roof.append([cell.x, cell.y])
			if (x == bounds.position.x or x == bounds.end.x - 1 or y == bounds.position.y or y == bounds.end.y - 1) and cell != door:
				walls.append([cell.x, cell.y])
	var desk: Vector2i = anchor + _rotate(SimRouteTravel.cell(_rules.desk_offset), orientation)
	var archive: Vector2i = anchor + _rotate(SimRouteTravel.cell(_rules.archive_offset), orientation)
	return {"version": VERSION, "kind": "records_office", "label": str(_rules.labels.room),
		"institution": institution, "template": template, "orientation": orientation,
		"clerk_cell": [anchor.x, anchor.y], "door": [door.x, door.y], "walls": walls, "roof": roof,
		"fixtures": {
			"desk": {"kind": "desk", "label": str(_rules.labels.desk), "cell": [desk.x, desk.y]},
			"archive": {"kind": "archive_cabinet", "label": str(_rules.labels.archive), "cell": [archive.x, archive.y]},
			"register": {"id": institution + ":official_register", "kind": "institutional_register", "label": str(_rules.labels.register), "cell": [archive.x, archive.y], "institution": institution, "scope": "contribution"}
		}}


static func _terrain_valid(layout: Dictionary, terrain: WorldMapData) -> bool:
	var level: int = terrain.get_elevation(SimRouteTravel.cell(layout.clerk_cell))
	for raw: Array in layout.roof:
		var cell: Vector2i = SimRouteTravel.cell(raw)
		if not terrain.terrain_is_walkable(cell) or terrain.get_elevation(cell) != level:
			return false
	return true


static func _entry_reachable(layout: Dictionary, terrain: WorldMapData, _used: Dictionary) -> bool:
	# A doorway must open onto original walkable land, not a rock or cliff.
	var outward: Vector2i = _rotate(Vector2i.DOWN, int(layout.orientation))
	var door: Vector2i = SimRouteTravel.cell(layout.door)
	return terrain.terrain_can_step(door, outward)


static func _blocked_cells(layout: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for raw: Array in layout.walls:
		result.append(SimRouteTravel.cell(raw))
	result.append(SimRouteTravel.cell(layout.fixtures.desk.cell))
	result.append(SimRouteTravel.cell(layout.fixtures.archive.cell))
	return result


static func _rotate(cell: Vector2i, quarter_turns: int) -> Vector2i:
	match quarter_turns:
		1: return Vector2i(-cell.y, cell.x)
		2: return -cell
		3: return Vector2i(cell.y, -cell.x)
	return cell


static func _same_value(actual: Variant, expected: Variant) -> bool:
	if expected is Dictionary:
		if not actual is Dictionary or actual.size() != expected.size():
			return false
		for key: Variant in expected:
			if not actual.has(key) or not _same_value(actual[key], expected[key]):
				return false
		return true
	if expected is Array:
		if not actual is Array or actual.size() != expected.size():
			return false
		for index: int in range(expected.size()):
			if not _same_value(actual[index], expected[index]):
				return false
		return true
	if expected is int:
		return Shape.count(actual, int(expected), int(expected))
	return typeof(actual) == typeof(expected) and actual == expected


static func _reply(ok: bool, reason: String, line: String) -> Dictionary:
	return {"ok": ok, "reason": reason, "line": line, "place": "records"}


static func valid_rules(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != VERSION or not value.get("return_action") is Dictionary or not Shape.count(value.get("desk_reach_px"), 1):
		return false
	if not value.get("room_templates") is Array or value.room_templates.is_empty() or not Shape.cell_valid(value.get("desk_offset"), true) or not Shape.cell_valid(value.get("archive_offset"), true):
		return false
	for row: Variant in value.room_templates:
		if not row is Dictionary or not Shape.cell_valid(row.get("origin"), true) or not Shape.cell_valid(row.get("size")) or row.size[0] < 3 or row.size[1] < 3:
			return false
	if not value.get("permissions") is Array or not value.get("labels") is Dictionary:
		return false
	if not SimEmbodiment._unique_texts(value.permissions):
		return false
	for field: String in ["room", "desk", "archive", "register"]:
		if not SimInventory._nonempty(value.labels.get(field)):
			return false
	return Shape.keys(value.return_action, ["label", "kind", "target", "minutes", "contribution"]) and SimInventory._nonempty(value.return_action.label) and value.return_action.kind == "visit" and value.return_action.target == "records" and Shape.count(value.return_action.minutes, 1) and Shape.count(value.return_action.contribution)
