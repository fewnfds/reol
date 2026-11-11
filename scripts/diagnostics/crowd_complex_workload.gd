extends RefCounted
## Temporary scenario assembly over real owners. Only setup installs already
## built structures; capture uses ordinary movement, field and lifecycle code.
const ARTIFACTS: String = "res://data/definitions/artifacts.json"
const SOURCES: String = "res://data/definitions/environment_sources.json"
var source_ids: Array[String] = []
var source_cells: Array[Vector2i] = []
var requested_rooms: int = 48
var requested_sources: int = 128
var source_moves: int = 0
var source_move_attempts: int = 0
var _next_change_ms: int = 0
var _world: RegionalSimulation
var _center: Vector2i
var _nearby_count: int = 0
var _mobile_sources: int = 0


static func configure(main: Node) -> bool:
	var content := ReolContentDB.new()
	if not content.load_all():
		return false
	var bundle: Dictionary = content.content_bundle()
	var artifacts: Dictionary = bundle.documents[ARTIFACTS]
	var sources: Dictionary = bundle.documents[SOURCES]
	# Passive physical sources use existing validated profiles; no special
	# stress-only field equation or fake visual emitter is introduced.
	for profile: String in ["intrinsic_hot", "intrinsic_cold", "ordinary_metal", "ordinary_water", "ordinary_plant"]:
		var id: String = "stress_" + profile
		artifacts.types[id] = artifacts.types.plain_slate.duplicate(true)
		sources.bindings.artifacts[id] = profile
	var terrain: Array = []
	var descriptor: Dictionary = WorldMapData.flat_descriptor(20261111)
	var map := WorldMapData.from_descriptor(descriptor)
	for y: int in range(140, 373):
		for x: int in range(140, 373):
			if map.get_terrain(Vector2i(x, y)) != WorldMapData.TERRAIN_GRASS:
				terrain.append([x, y, WorldMapData.TERRAIN_GRASS])
	return main.configure_opening_map(descriptor, terrain) and main.configure_opening_content(ReolContentBundle.from_documents(bundle.documents))


func prepare(runtime: WorldContinuityRuntime, room_count: int, source_count: int) -> String:
	_world = runtime.world_sim
	requested_rooms = room_count
	requested_sources = source_count
	_center = runtime.centers.home
	var construction: SimConstruction = _world.construction
	var cells: Array[Vector2i] = []
	var rooms: Array[Rect2i] = []
	# Keep a broad road/circuit around the player. Four 28x28 sites can hold
	# 64 enclosed 3x3 rooms, with a passable, thermally closed door in each.
	for site_index: int in range(4):
		var origin: Vector2i = _center + Vector2i(16 + (site_index % 2) * 30, -28 + (site_index / 2) * 30)
		var site: String = "sect_yard" if construction.sites.is_empty() else "construction_site:%d" % (construction.sites.size() + 1)
		construction.sites[site] = {"region": "home", "owner": str(_world.regions.home.config.institution.id),
			"origin": [origin.x, origin.y], "size": [28, 28], "created_by": "player", "created_ms": _world.elapsed_ms}
		for row: int in 4:
			for column: int in 4:
				if rooms.size() >= requested_rooms:
					break
				var area := Rect2i(origin + Vector2i(column, row) * 7 + Vector2i.ONE, Vector2i(5, 5))
				var clear: bool = true
				for cell: Vector2i in SimConstruction.cells_in(area):
					if construction.protected_cell(cell) or not _world.map_data.terrain_is_walkable(cell):
						clear = false
				if not clear:
					continue
				rooms.append(area)
				for cell: Vector2i in SimConstruction.cells_in(area):
					var relative: Vector2i = cell - area.position
					var edge: bool = relative.x in [0, 4] or relative.y in [0, 4]
					if edge:
						_add_structure(construction, site, "wood_door" if relative == Vector2i(2, 4) else "wood_wall", cell)
					else:
						_add_structure(construction, site, "wood_roof", cell)
					cells.append(cell)
	if rooms.size() != requested_rooms:
		return "Complex fixture could only place %d/%d rooms" % [rooms.size(), requested_rooms]
	construction._reindex()
	construction.space_changed.emit(cells)
	if not _world.environment_fields.before_topology_change(_world.elapsed_ms, cells) or not _world.environment_fields.after_topology_change(_world.elapsed_ms):
		return "Complex fixture could not adopt real enclosure/thermal geometry"
	# Staged positions only: all settlements' bodies are placed near the same
	# observer, then continue through their original accepted actions.
	var reachable: Array[Vector2i] = VillageRuntime.find_reachable_cells(runtime.home_runtime()._world, _center, 60, 32768)
	var cursor: int = 0
	for sim: VillageSimulation in _world.regions.values():
		for id: String in sim.actor_ids():
			if id == "player":
				continue
			if cursor >= reachable.size():
				return "Complex fixture exhausted actual reachable ground"
			sim.set_actor_cell(id, reachable[cursor])
			cursor += 1
			_nearby_count += 1
	for index: int in requested_sources:
		var type: String = ["intrinsic_hot", "intrinsic_cold", "ordinary_metal", "ordinary_water", "ordinary_plant"][index % 5]
		var cell: Vector2i = _center + Vector2i(-12 + (index % 16) * 2, -14 + (index / 16) * 2)
		# Sources are physical artifacts in registered ground slots. Enclosures
		# and actors are separate spatial layers; avoid actual solid fixtures.
		while _world.construction.blocked(cell) or not _world.object_lifecycle.ground.can_place("home", cell).ok:
			cell.y += 1
		var id: String = "stress_source:%d" % index
		var destination: Dictionary = {"region": "home", "cell": [cell.x, cell.y]}
		if index < requested_sources / 4:
			var people: Array = _world.regions.home.actor_ids()
			var carrier: String = str(people[index % people.size()])
			if carrier != "player":
				destination = {"region": "home", "container": "actor:" + carrier}
				_mobile_sources += 1
		var result: Dictionary = _world.object_lifecycle.execute({"command": "stress_spawn:%d" % index, "op": "spawn",
			"id": id, "definition": "stress_" + type, "to": destination})
		if not result.ok:
			return "Complex source assembly: " + str(result)
		source_ids.append(id)
		source_cells.append(cell)
	_next_change_ms = _world.elapsed_ms + 500
	return ""


func _add_structure(owner: SimConstruction, site: String, type: String, cell: Vector2i) -> void:
	var id: String = "construction:%d" % owner.next_project
	owner.next_project += 1
	var rule: Dictionary = owner.definitions.types[type]
	owner.projects[id] = {"site": site, "type": type, "cell": [cell.x, cell.y], "rotation": 0,
		"hp": int(rule.max_hp), "state": "built", "created_by": "player", "created_ms": _world.elapsed_ms,
		"completed_ms": _world.elapsed_ms, "removed_ms": 0, "work_ms": int(rule.work_ms),
		"material_cell": [cell.x, cell.y], "carrier": "", "delivered": true, "line": "Temporary pressure scenario"}
	_world.regions.home.inventory.create_container(id, {})


func sample() -> void:
	if _world.elapsed_ms < _next_change_ms or source_ids.is_empty():
		return
	_next_change_ms = _world.elapsed_ms + 500
	# A blocked destination must not retry the same source forever. Keep the
	# work rate bounded but rotate attempts independently of successful moves.
	var index: int = source_move_attempts % source_ids.size()
	var id: String = source_ids[index]
	var item: Dictionary = _world.artifacts.objects[id]
	if str(item.container).begins_with("actor:"):
		# Carried sources already change through actual body crossing notices.
		index = _mobile_sources + (source_move_attempts % maxi(1, source_ids.size() - _mobile_sources))
		id = source_ids[index]
		item = _world.artifacts.objects[id]
	var origin: Vector2i = source_cells[index]
	var target: Vector2i = origin + Vector2i(0, 1 if (source_move_attempts / source_ids.size()) % 2 == 0 else -1)
	var result: Dictionary = _world.object_lifecycle.execute({"command": "stress_move:%d" % source_move_attempts, "op": "move", "id": id,
		"from": {"region": "home", "container": str(item.container)}, "to": {"region": "home", "cell": [target.x, target.y]}})
	source_move_attempts += 1
	if result.ok:
		source_cells[index] = target
		source_moves += 1


func evidence() -> Dictionary:
	return {"requested_rooms": requested_rooms, "actual_rooms": _world.environment_fields._layout.rooms.size(),
		"physical_sources": source_ids.size(), "mobile_sources": _mobile_sources, "source_moves": source_moves, "source_move_attempts": source_move_attempts, "staged_near_observer": _nearby_count,
		"structures": _world.construction.projects.size(), "fields": _world.environment_fields.diagnostics(),
		"setup": "temporary installed scenario; no ordinary save; structures installed at setup, original owners run during capture"}
