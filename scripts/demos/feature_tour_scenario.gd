extends RefCounted
## One-time opening data. Prebuilt examples receive real material receipts;
## all later actions and saving use the existing owners, never a shadow world.
const ARTIFACTS: String = "res://data/definitions/artifacts.json"
const SOURCES: String = "res://data/definitions/environment_sources.json"
var _world: RegionalSimulation
var _locations: Dictionary = {}


static func configure(main: Node) -> bool:
	var content := ReolContentDB.new()
	if not content.load_all():
		return false
	var bundle: Dictionary = content.content_bundle()
	for pair: Array in [["tour_hot_stone", "暖源石", "intrinsic_hot"], ["tour_cold_stone", "寒源石", "intrinsic_cold"]]:
		var rule: Dictionary = bundle.documents[ARTIFACTS].types.plain_slate.duplicate(true)
		rule.name = pair[1]
		rule.unknown_name = pair[1]
		rule.appearance = "试游场景中预置的来源石，可通过原取放动作移动。"
		bundle.documents[ARTIFACTS].types[pair[0]] = rule
		bundle.documents[SOURCES].bindings.artifacts[pair[0]] = pair[2]
	var descriptor: Dictionary = WorldMapData.flat_descriptor(20261112)
	var map := WorldMapData.from_descriptor(descriptor)
	var terrain: Array = []
	var center := Vector2i(256, 256)
	for y: int in range(204, 309):
		for x: int in range(204, 325):
			var cell := Vector2i(x, y)
			var type: int = WorldMapData.TERRAIN_WATER if Rect2i(center + Vector2i(-16, -12), Vector2i(3, 3)).has_point(cell) else WorldMapData.TERRAIN_GRASS
			if map.get_terrain(cell) != type:
				terrain.append([x, y, type])
	return main.configure_opening_map(descriptor, terrain) and main.configure_opening_content(ReolContentBundle.from_documents(bundle.documents))


func install(runtime: WorldContinuityRuntime) -> Dictionary:
	_world = runtime.world_sim
	var sim: VillageSimulation = _world.regions.home
	for item: String in ["water", "wood", "herb", "grain"]:
		sim.inventory.containers["actor:player"][item] = 6 if item == "herb" else 12
	sim.inventory.contents_changed.emit("actor:player")
	var center: Vector2i = runtime.centers.home
	for place: String in sim.places:
		_locations[place] = SimRouteTravel.cell(sim.places[place].cell)
	_locations.home = center
	_locations.river = runtime.centers.river
	_locations.pond = center + Vector2i(-15, -9)
	var owner: SimConstruction = _world.construction
	var origin: Vector2i = _find_yard(center)
	if origin.x < 0:
		return {"ok": false, "line": "没有找到可达的试游院落。"}
	var site: Dictionary = owner.register_site("player", origin, Vector2i(16, 9))
	if not site.ok:
		return site
	var cells: Array[Vector2i] = SimConstruction.cells_in(Rect2i(origin, Vector2i(16, 9)))
	if not _world.environment_fields.before_topology_change(_world.elapsed_ms, cells):
		return {"ok": false, "line": "试游房间环境尚未就绪。"}
	for room_index: int in 2:
		var corner: Vector2i = origin + Vector2i(room_index * 9, 0)
		for offset: Vector2i in SimConstruction.cells_in(Rect2i(Vector2i.ZERO, Vector2i(7, 5))):
			var edge: bool = offset.x in [0, 6] or offset.y in [0, 4]
			var type: String = "wood_roof"
			if edge:
				type = "wood_door" if offset == Vector2i(3, 4) else "wood_window" if offset == Vector2i(0, 2) else "stone_wall" if room_index == 1 else "wood_wall"
			if _structure(str(site.site), type, corner + offset).is_empty():
				return {"ok": false, "line": "预置房间材料登记失败。"}
		_locations["warm_room" if room_index == 0 else "cold_room"] = corner + Vector2i(3, 3)
		_locations["warm_door" if room_index == 0 else "cold_door"] = corner + Vector2i(3, 5)
	var fixtures: Array = [["wood_bed", 1, 1], ["wood_chest", 5, 1], ["wood_table", 1, 2], ["wood_chair", 3, 2],
		["cook_stove", 10, 1], ["desk_chair", 13, 1], ["long_bed", 14, 1], ["wood_screen", 10, 3],
		["planter", 0, 7], ["planter", 2, 7]]
	var planters: Array[String] = []
	for row: Array in fixtures:
		var id: String = _structure(str(site.site), str(row[0]), origin + Vector2i(int(row[1]), int(row[2])))
		if id.is_empty():
			return {"ok": false, "line": "预置家具登记失败。"}
		if row[0] == "planter":
			planters.append(id)
	owner._reindex()
	owner._schedule_check()
	owner.structures_changed.emit(cells)
	owner.space_changed.emit(cells)
	if not _world.environment_fields.after_topology_change(_world.elapsed_ms):
		return {"ok": false, "line": "试游房间环境装配失败。"}
	_locations.yard = origin + Vector2i(4, 6)
	_locations.plants = origin + Vector2i(1, 7)
	if not _plant("tour:herb", "perennial_herb", origin + Vector2i(1, 7)) or not _plant("tour:potted", "fire_herb", origin + Vector2i(2, 7), planters[1]) or not _plant("tour:annual", "annual_grass", origin + Vector2i(5, 7)) or not _plant("tour:lotus", "lotus", center + Vector2i(-15, -11)) or not _plant("tour:thorn", "desert_thorn", center + Vector2i(-12, -9)):
		return {"ok": false, "line": "试游植物生境不适用。"}
	for pair: Array in [["warm", "tour_hot_stone", _locations.warm_room], ["cold", "tour_cold_stone", _locations.cold_room], ["slab", "stone_slab", origin + Vector2i(7, 7)]]:
		var point: Vector2i = pair[2]
		var spawned: Dictionary = _world.object_lifecycle.execute({"command": "tour:spawn:" + str(pair[0]), "op": "spawn",
			"id": "tour:" + str(pair[0]), "definition": pair[1], "to": {"region": "home", "cell": [point.x, point.y]}})
		if not spawned.ok:
			return spawned
	_world.invalidate_region("home")
	runtime.construction_adapter.refresh_choices()
	return {"ok": true, "locations": _locations}


func _find_yard(center: Vector2i) -> Vector2i:
	var owner: SimConstruction = _world.construction
	var source: Vector2i = SimRouteTravel.cell(_world.regions.home.places.store.cell)
	var desired: Vector2i = center + Vector2i(-9, 7)
	for radius: int in range(0, 19):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var origin: Vector2i = desired + Vector2i(x, y)
				if origin.distance_to(source) > float(owner.definitions.site.source_cells) or origin.distance_to(center) > float(owner.definitions.site.observe_cells):
					continue
				var clear: bool = true
				for cell: Vector2i in SimConstruction.cells_in(Rect2i(origin, Vector2i(16, 9))):
					if not owner.terrain_open(cell) or owner.protected_cell(cell) or owner.occupied(cell) or SimMotionClearance.fixed_road_reserves(_world, cell):
						clear = false
						break
				if clear:
					return origin
	return Vector2i(-1, -1)


func _structure(site: String, type: String, cell: Vector2i) -> String:
	var owner: SimConstruction = _world.construction
	var inventory: SimInventory = _world.regions.home.inventory
	var rule: Dictionary = owner.definitions.types[type]
	var id: String = "construction:%d" % owner.next_project
	var job: String = "construction_job:%d" % owner.next_job
	if not inventory.create_container(id, {}) or not inventory.reserve(job, "store", str(rule.item), int(rule.amount), "player") or not inventory.transfer(id + ":supply", "store", id, str(rule.item), int(rule.amount), job) or not inventory.consume(id + ":build", id, str(rule.item), int(rule.amount)):
		return ""
	owner.next_project += 1
	owner.next_job += 1
	owner.projects[id] = {"site": site, "type": type, "cell": [cell.x, cell.y], "rotation": 0, "hp": int(rule.max_hp),
		"state": "built", "created_by": "player", "created_ms": _world.elapsed_ms, "completed_ms": _world.elapsed_ms,
		"removed_ms": 0, "work_ms": int(rule.work_ms), "material_cell": [cell.x, cell.y], "carrier": "", "delivered": true,
		"line": "试游开局已有设施；后续使用与拆改沿普通规则。"}
	if rule.capabilities.has("storage"):
		inventory.create_container(id + ":contents", {})
	if rule.capabilities.has("cultivation"):
		var terms: Dictionary = rule.capabilities.cultivation
		owner.cultivation[id] = {"substrate": terms.substrate, "water": int(terms.initial_water), "plant": ""}
	return id


func _plant(id: String, type: String, cell: Vector2i, support: String = "") -> bool:
	var rule: Dictionary = _world.plants.definitions.types[type]
	var maturity: int = int(rule.fruit_ms)
	if not _world.plants.spawn(id, type, "home", cell, support, false, maturity, maturity):
		return false
	# Authored initial yield with the same plant ledger used by later harvests.
	var item: String = str(rule.product.item)
	_world.regions.home.inventory.containers[_world.plants.container_id(id)][item] = 3
	_world.plants.bodies[id].produced[item] = 3
	_world.regions.home.inventory.contents_changed.emit(_world.plants.container_id(id))
	return true
