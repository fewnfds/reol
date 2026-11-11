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
var _permeability := PackedInt32Array()


func _init() -> void:
	_permeability.resize(MAX_CELLS)
	_permeability.fill(-1)


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
	_permeability.fill(-1)
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
			if bool(rule.facts.enclosure_boundary):
				edges[cell] = {"id": id, "project": row}
	# Existing offices are original fixed structures, not new wall entities.
	types["@office_wall"] = {"door": false}
	types["@office_door"] = {"door": true, "aperture": true}
	for sim: VillageSimulation in world.regions.values():
		var office: Dictionary = sim.places.get("records", {}).get("workspace", {})
		if office.is_empty():
			continue
		var area := Rect2i(SimRouteTravel.cell(office.door), Vector2i.ONE)
		for raw: Array in office.walls:
			var cell: Vector2i = SimRouteTravel.cell(raw)
			edges[cell] = {"id": "office:" + str(cell), "project": {"type": "@office_wall"}}
			barriers[cell] = {"thermal": 2000, "elements": 8000, "light": 0, "room_tau_ms": 180000}
			area = area.expand(cell)
		var door: Vector2i = SimRouteTravel.cell(office.door)
		edges[door] = {"id": "office_door:" + str(door), "project": {"type": "@office_door"}}
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
			tau = maxi(30000, tau / (1 + int(space.openings) * 4 + (space.cells.size() - covered)))
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
	var pair: Vector2i = transmission_pair(from, to)
	return pair.x if channel >= 5 else pair.y


func transmission_pair(from: Vector2i, to: Vector2i) -> Vector2i:
	# Same supercover/corner order and integer truncation as LightPropagation.
	# Thermal and elemental permeability share geometry, so traverse it once.
	# Source and target surfaces keep their original exposed-face convention.
	var world: RegionalSimulation = _owner.get_ref() if _owner != null else null
	var extent := Vector2i(absi(to.x - from.x), absi(to.y - from.y))
	if world == null or extent.x > 16 or extent.y > 16:
		return Vector2i.ZERO
	var thermal: int = SCALE
	var elements: int = SCALE
	var direction := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var crossed := Vector2i.ZERO
	var at: Vector2i = from
	while at != to:
		var x_cross: int = (1 + 2 * crossed.x) * extent.y
		var y_cross: int = (1 + 2 * crossed.y) * extent.x
		if x_cross == y_cross:
			var first: int = _cell_permeability(at + Vector2i(direction.x, 0), world)
			var second: int = _cell_permeability(at + Vector2i(0, direction.y), world)
			thermal = (thermal * (first & 65535) / SCALE) * (second & 65535) / SCALE
			elements = (elements * (first >> 16) / SCALE) * (second >> 16) / SCALE
			at += direction
			crossed += Vector2i.ONE
		elif x_cross < y_cross:
			at.x += direction.x
			crossed.x += 1
		else:
			at.y += direction.y
			crossed.y += 1
		if at != to:
			var terms: int = _cell_permeability(at, world)
			thermal = thermal * (terms & 65535) / SCALE
			elements = elements * (terms >> 16) / SCALE
		if thermal == 0 and elements == 0:
			break
	return Vector2i(thermal, elements)


func _cell_permeability(cell: Vector2i, world: RegionalSimulation) -> int:
	var inside: bool = cell.x >= 0 and cell.y >= 0 and cell.x < WorldMapData.WORLD_SIZE and cell.y < WorldMapData.WORLD_SIZE
	var index: int = cell.y * WorldMapData.WORLD_SIZE + cell.x
	if inside and _permeability[index] >= 0:
		return _permeability[index]
	var rock: bool = world.map_data != null and world.map_data.get_terrain(cell) == WorldMapData.TERRAIN_ROCK
	var thermal: int = 2000 if rock else SCALE
	var elements: int = 8000 if rock else SCALE
	if not rock and barriers.has(cell):
		thermal = int(barriers[cell].get("thermal", SCALE))
		elements = int(barriers[cell].get("elements", SCALE))
	var packed: int = thermal | (elements << 16)
	if inside:
		_permeability[index] = packed
	return packed


func capture_transmission(area: Rect2i) -> Dictionary:
	var world: RegionalSimulation = _owner.get_ref() if _owner != null else null
	var bounds := Rect2i(Vector2i.ZERO, Vector2i(WorldMapData.WORLD_SIZE, WorldMapData.WORLD_SIZE))
	if world == null or not area.has_area() or not bounds.encloses(area):
		return {"ok": false, "reason": "geometry_area"}
	# One packed pair per cell, derived from the original terrain/structure.
	# Source surfaces, target surfaces and diagonal corners are handled by the
	# same integer ray convention on the device, never precomputed N² rays.
	var values := PackedInt32Array([1, area.position.x, area.position.y, area.size.x, area.size.y, 16])
	values.resize(6 + area.get_area())
	var index: int = 6
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			values[index] = _cell_permeability(Vector2i(x, y), world)
			index += 1
	return {"ok": true, "geometry": values}


static func container_transmission(world: RegionalSimulation, container: String, channel: String) -> int:
	var id: String = container.trim_suffix(":contents")
	if id == container or not world.construction.projects.has(id):
		return SCALE
	var project: Dictionary = world.construction.projects[id]
	if project.state != "built":
		return SCALE
	return int(terms(world.construction.definitions.types[project.type])["contents_" + channel])
