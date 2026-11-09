class_name SimEnvironmentLayout
extends RefCounted
## Disposable geometry over the original map/buildings. Actual temperature
## remains in SimEnvironmentTemperatureState, never in this layout index.
const SCALE: int = 10000
const MAX_CELLS: int = WorldMapData.WORLD_SIZE * WorldMapData.WORLD_SIZE
var rooms: Dictionary = {}
var room_of: Dictionary[Vector2i, Vector2i] = {}
var barriers: Dictionary[Vector2i, Dictionary] = {}
var _owner: WeakRef
var _terrain: Dictionary[Vector2i, bool] = {}


static func terms(rule: Dictionary) -> Dictionary:
	if rule.has("environment"):
		return rule.environment
	var barrier: bool = bool(rule.facts.thermal_barrier)
	return {"source": "", "thermal": 2000 if barrier else SCALE, "elements": 8000 if barrier else SCALE,
		"light": 0 if bool(rule.facts.sight_blocked) else SCALE, "contents_thermal": SCALE,
		"contents_elements": SCALE, "contents_light": SCALE, "room_tau_ms": 180000}


static func valid_terms(value: Variant) -> bool:
	if not SimAvianLife.Schema.keys(value, ["source", "thermal", "elements", "light", "contents_thermal", "contents_elements", "contents_light", "room_tau_ms"]) or not value.source is String:
		return false
	for field: String in ["thermal", "elements", "light", "contents_thermal", "contents_elements", "contents_light"]:
		if not SimAvianLife.Schema.count(value[field], 0, SCALE):
			return false
	return SimAvianLife.Schema.count(value.room_tau_ms, 30000, 3600000)


func rebuild(world: RegionalSimulation) -> bool:
	_owner = weakref(world)
	rooms.clear()
	room_of.clear()
	barriers.clear()
	_terrain.clear()
	var edges: Dictionary = {}
	var bounds: Array[Rect2i] = []
	var types: Dictionary = world.construction.definitions.types.duplicate(false)
	for id: String in world.construction.sites:
		bounds.append(world.construction.site_bounds(id).grow(1))
	for id: String in world.construction._project_ids():
		var row: Dictionary = world.construction.projects[id]
		if row.state != "built" or types[row.type].layer != "ground":
			continue
		var rule: Dictionary = types[row.type]
		var exposure: Dictionary = terms(rule)
		for cell: Vector2i in world.construction.project_cells(id):
			barriers[cell] = exposure.duplicate()
			if bool(rule.door) and bool(row.open):
				barriers[cell].thermal = SCALE
				barriers[cell].elements = SCALE
				barriers[cell].light = SCALE
			if bool(rule.facts.enclosure_boundary):
				edges[cell] = {"id": id, "project": row}
	# Existing offices are original fixed structures, not new wall entities.
	types["@office_wall"] = {"door": false}
	types["@office_door"] = {"door": true}
	for sim: VillageSimulation in world.regions.values():
		var office: Dictionary = sim.places.get("records", {}).get("workspace", {})
		if office.is_empty():
			continue
		var area := Rect2i(SimRouteTravel.cell(office.door), Vector2i.ONE)
		for raw: Array in office.walls:
			var cell: Vector2i = SimRouteTravel.cell(raw)
			edges[cell] = {"id": "office:" + str(cell), "project": {"type": "@office_wall", "open": false}}
			barriers[cell] = {"thermal": 2000, "elements": 8000, "light": 0, "room_tau_ms": 180000}
			area = area.expand(cell)
		var door: Vector2i = SimRouteTravel.cell(office.door)
		edges[door] = {"id": "office_door:" + str(door), "project": {"type": "@office_door", "open": true}}
		bounds.append(area.grow(1))
	# Merge only overlapping local work areas, not the hull of distant sites.
	var merged: bool = true
	while merged:
		merged = false
		for a: int in bounds.size():
			for b: int in range(a + 1, bounds.size()):
				if bounds[a].intersects(bounds[b]):
					bounds[a] = bounds[a].merge(bounds[b])
					bounds.remove_at(b)
					merged = true
					break
			if merged:
				break
	var visited: int = 0
	for area: Rect2i in bounds:
		area = area.intersection(Rect2i(Vector2i.ZERO, Vector2i(WorldMapData.WORLD_SIZE, WorldMapData.WORLD_SIZE)))
		visited += area.get_area()
		if visited > MAX_CELLS:
			return false
		var spaces: Dictionary = SimEnclosedSpace.detect_edges(area, edges, types, Callable(), true)
		var seen: Dictionary = {}
		for cell: Vector2i in spaces:
			var space: Dictionary = spaces[cell]
			var anchor: Vector2i = space.cells[0]
			if not bool(space.enclosed) or seen.has(anchor):
				continue
			seen[anchor] = true
			var covered: int = 0
			var tau_sum: int = 0
			var faces: int = 0
			for point: Vector2i in space.cells:
				covered += int(world.construction.roofed(point))
				for side: Vector2i in SimEnclosedSpace.SIDES:
					if edges.has(point + side):
						tau_sum += int(barriers.get(point + side, {}).get("room_tau_ms", 30000))
						faces += 1
			if covered * 4 < space.cells.size() * 3:
				continue
			var tau: int = maxi(30000, tau_sum / maxi(1, faces))
			# Open apertures and missing roof expose the whole mixed compartment.
			tau = maxi(30000, tau / (1 + int(space.open_doors) * 4 + (space.cells.size() - covered)))
			rooms[anchor] = {"cells": space.cells, "tau_ms": tau, "roofed": covered}
			for point: Vector2i in space.cells:
				room_of[point] = anchor
	return true


func bind_world(world: RegionalSimulation) -> void:
	_owner = weakref(world)


func compile_room(domain: RefCounted, anchor: Vector2i, at_ms: int) -> Dictionary:
	# Perfect mixing within a roofed compartment is an explicit approximation.
	# This returns targets only; the original temperature owner holds all heat.
	var room: Dictionary = rooms[anchor]
	var target: float = 0.0
	var slope: float = 0.0
	var until: int = SimEnvironmentTemperatureState.MAX_TIME
	for cell: Vector2i in room.cells:
		var read: Dictionary = domain._field.read_base(cell)
		if not bool(read.get("ok", false)) or bool(read.get("pending", true)):
			return {"ok": false, "reason": "room_field_unavailable"}
		var segment: Dictionary = domain._compiler.compile(cell, at_ms, read.channels[5], read.channels[6])
		if not bool(segment.get("ok", false)):
			return segment
		target += float(segment.target_c)
		slope += float(segment.target_per_ms)
		until = mini(until, int(segment.until_ms))
	# Average arithmetic may leave sub-ULP noise that JSON canonicalization
	# legitimately removes. Quantize once before both publication and validation.
	return {"ok": true, "target_c": _json_number(target / room.cells.size()), "target_per_ms": _json_number(slope / room.cells.size()),
		"until_ms": until, "tau_ms": int(room.tau_ms)}


static func _json_number(value: float) -> float:
	# Same canonical number before runtime publication and independent restore.
	# Godot JSON intentionally removes insignificant binary average noise.
	return float(JSON.parse_string(JSON.stringify(value)))


func transmission(from: Vector2i, to: Vector2i, channel: int) -> int:
	var world: RegionalSimulation = _owner.get_ref() if _owner != null else null
	if world == null:
		return 0
	var field: String = "thermal" if channel >= 5 else "elements"
	return SimLightPropagation.transmission(from, to, func(cell: Vector2i) -> int:
		if cell == from:
			return SCALE # A wall source exposes its own outer surface.
		if not _terrain.has(cell):
			_terrain[cell] = world.map_data != null and world.map_data.get_terrain(cell) == WorldMapData.TERRAIN_ROCK
		if _terrain[cell]:
			return 2000 if channel >= 5 else 8000
		return int(barriers.get(cell, {}).get(field, SCALE)), 16)


static func container_transmission(world: RegionalSimulation, container: String, channel: String) -> int:
	var id: String = container.trim_suffix(":contents")
	if id == container or not world.construction.projects.has(id):
		return SCALE
	var project: Dictionary = world.construction.projects[id]
	if project.state != "built":
		return SCALE
	return int(terms(world.construction.definitions.types[project.type])["contents_" + channel])
