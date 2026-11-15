extends RefCounted
## Building/fixture state lives in object records. Work uses the world's common
## approach/reservation/timer/cancel contract, not a separate construction clock.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Positions = preload("res://scripts/sim/kernel/work_positions.gd")
var definitions: Dictionary = {}
var completed: Dictionary = {}


func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/construction.json"))
	if parsed is Dictionary:
		definitions = parsed.get("types", {})
		for key: String in definitions.keys():
			var errors: PackedStringArray = Positions.errors(definitions[key].get("work_positions", {}))
			if not errors.is_empty():
				push_error(key + ": " + str(errors))
				definitions.erase(key)


func footprint(definition: String, tile: int, facing: int = 0) -> PackedInt32Array:
	var result := PackedInt32Array()
	if not definitions.has(definition) or tile < 0 or tile >= Terrain.SIZE * Terrain.SIZE:
		return result
	var dimensions: Array = definitions[definition].size
	var size := Vector2i(int(dimensions[0]), int(dimensions[1]))
	if facing % 2 != 0:
		size = Vector2i(size.y, size.x)
	var origin: Vector2i = Terrain.cell(tile)
	if origin.x + size.x > Terrain.SIZE or origin.y + size.y > Terrain.SIZE:
		return result
	for y: int in size.y:
		for x: int in size.x:
			result.append(tile + y * Terrain.SIZE + x)
	return result


func in_range(world: RefCounted, target: int, origin: Vector2, radius: float, operation: String = "", flying: bool = false) -> bool:
	if world.actor_slots.has(target):
		var point: Vector2 = world.position_at(target)
		return origin.distance_to(point) <= 1.5 + radius - 0.35 and Terrain.blocking_fraction(world.terrain.blocked, origin, point) < 0
	return Positions.permits(world, target, operation, origin, radius, flying)


func interaction_point(world: RefCounted, target: int, origin: Vector2, radius: float = 0.35, flying: bool = false, operation: String = "") -> Vector2:
	if in_range(world, target, origin, radius, operation, flying): return origin
	if world.actor_slots.has(target):
		return world.terrain.project_point(world.position_at(target), radius, flying)
	var candidates: Array[Vector2] = Positions.candidates(world, target, operation, origin, radius, flying)
	for candidate: Vector2 in candidates:
		if world.terrain.segment_clear(origin, candidate, radius, flying): return candidate
	var deferred := Vector2(-1, -1)
	var nav: RefCounted = world.lanes[0].navigation
	for candidate: Vector2 in candidates:
		if not nav.plan(origin, candidate, radius, flying).is_empty(): return candidate
		if nav.deferred and deferred.x < 0: deferred = candidate
	return deferred


func start_construction(world: RefCounted, target: int, at: int) -> String:
	var record: Dictionary = world.objects.records.get(target, {})
	if record.get("kind", "") != "blueprint": return "unavailable"
	if record.get("construction_started", false): return "started"
	var spec: Dictionary = definitions[record.definition]
	if spec.get("facts", {}).get("movement_blocked", false):
		for body: RefCounted in world.pages:
			for row: int in body.ids.size():
				if body.ids[row] <= 0 or body.health[row] <= 0 or body.flight[row] != 0: continue
				for member: int in record.cells:
					if world._body_overlaps_tile(world.position_at(body.ids[row], at), body.radii[row], member): return "occupied"
		for member: int in record.cells: world.queue_structure(member, true, false)
	record["construction_started"] = true
	world.objects.layout_revision += 1
	return "started"


func blueprint(world: RefCounted, actor: int, definition: String, tile: int, facing: int = 0) -> Dictionary:
	facing = posmod(facing, 4)
	var cells: PackedInt32Array = footprint(definition, tile, facing)
	if cells.is_empty():
		return {"reason": "invalid_definition_or_tile"}
	var spec: Dictionary = definitions[definition]
	var layer: String = str(spec.get("layer", "ground"))
	var site: String = placement(world, layer, cells)
	if site != "accepted":
		return {"reason": site}
	var amount: int = int(spec.amount)
	var item: String = str(spec.item)
	if world.objects.amount(actor, item) < amount:
		return {"reason": "missing_materials"}
	var id: int = world.objects.create("blueprint", definition, tile)
	var record: Dictionary = world.objects.records[id]
	record["facing"] = facing
	record["layer"] = layer
	record["remaining_ms"] = int(spec.work_ms)
	record["construction_started"] = false
	record["max_hp"] = int(spec.max_hp)
	world.objects.reindex(id, cells)
	world.objects.transfer(actor, id, item, amount)
	world._sync_inventory(actor)
	world.livelihood.remember(world, actor, id, world.operation_time())
	return {"reason": "accepted", "target": id}


func placement(world: RefCounted, layer: String, cells: PackedInt32Array, ignore: int = 0) -> String:
	for member: int in cells:
		if layer == "floor" and (world.terrain.substrate(member) == "water" or world.terrain.flooring[member] != 0):
			return "water_or_existing_floor"
		for id: int in world.objects.by_tile.get(member, []):
			if id == ignore:
				continue
			var other: Dictionary = world.objects.records[id]
			var other_layer: String = str(other.get("layer", "ground"))
			var loose_stock: bool = other.kind == "pile" or (other.kind == "resource" and world.nature.vegetation_level(other) == 0)
			if layer == "floor":
				if other_layer == "floor":
					return "occupied"
				if world.nature.vegetation_level(other) >= 2:
					return "clear_shrub_tree_or_stump_first"
			elif not loose_stock and (other_layer == layer or (layer == "ground" and other_layer not in ["floor", "roof"])):
				return "occupied"
	return "accepted"


func duration(world: RefCounted, action: Dictionary) -> int:
	var record: Dictionary = world.objects.records[action.target]
	match action.kind:
		"construct": return maxi(1, int(record.get("remaining_ms", 1)))
		"rest": return 2000
		"eat": return 1000
		"cook": return 4000
	return 300


func seed_fixture(world: RefCounted, definition: String, tile: int, facing: int = 0) -> int:
	var spec: Dictionary = definitions[definition]
	var kind: String = "chest" if spec.get("capabilities", {}).has("storage") else str(spec.kind)
	var id: int = world.objects.create(kind, definition, tile)
	var record: Dictionary = world.objects.records[id]
	record["facing"] = posmod(facing, 4)
	record.hp = int(spec.max_hp)
	record["max_hp"] = int(spec.max_hp)
	record["layer"] = spec.get("layer", "ground")
	world.objects.reindex(id, footprint(definition, tile, facing))
	world.objects.transfer(world.source_objects[0], id, str(spec.item), int(spec.amount))
	record["materials"] = record.inventory
	record.inventory = {}
	if kind == "chest":
		record.capacity = int(spec.capabilities.storage.capacity)
	for member: int in record.cells:
		world.queue_structure(member, bool(spec.facts.get("movement_blocked", false)), bool(spec.facts.get("enclosure_boundary", false)))
	return id


func available(world: RefCounted, action: Dictionary) -> bool:
	var record: Dictionary = world.objects.records[action.target]
	var spec: Dictionary = definitions.get(record.definition, {})
	match action.kind:
		"construct": return record.kind == "blueprint"
		"rest": return spec.get("capabilities", {}).has("rest") and record.kind != "blueprint"
		"cook": return spec.get("capabilities", {}).has("workbench") and record.kind != "blueprint"
		"eat": return record.kind in ["chest", "workbench", "pile", "furniture"]
	return false


func interrupt(world: RefCounted, action: Dictionary, now: int) -> void:
	if action.kind not in ["construct", "sow"] or not action.has("started_ms") or not world.objects.records.has(action.target):
		return
	var record: Dictionary = world.objects.records[action.target]
	if action.kind == "construct" and record.kind != "blueprint": return
	record.remaining_ms = maxi(1, int(record.remaining_ms) - maxi(0, now - int(action.started_ms)))


func finish(world: RefCounted, actor: int, action: Dictionary, at: int) -> String:
	if not available(world, action):
		return "unavailable"
	var record: Dictionary = world.objects.records[action.target]
	var spec: Dictionary = definitions.get(record.definition, {})
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	match action.kind:
		"construct":
			var cells: PackedInt32Array = record.cells
			if record.get("layer", "ground") == "floor":
				var reason: String = placement(world, "floor", cells, action.target)
				if reason != "accepted":
					return reason
				for member: int in cells:
					for other: int in world.objects.by_tile.get(member, []).duplicate():
						if world.objects.records[other].kind == "plant" and int(world.objects.records[other].get("host", 0)) == 0:
							world.nature.remove(world, other, at)
					world.terrain.set_floor(member, true)
			if spec.get("facts", {}).get("movement_blocked", false):
				for body: RefCounted in world.pages:
					for index: int in body.ids.size():
						if body.ids[index] > 0 and body.health[index] > 0 and body.flight[index] == 0:
							for member: int in cells:
								if world._body_overlaps_tile(world.position_at(body.ids[index], at), body.radii[index], member):
									return "occupied"
			record.kind = str(spec.kind)
			record["materials"] = record.inventory
			record.inventory = {}
			if spec.get("capabilities", {}).has("storage"):
				record.kind = "chest"
				record.capacity = int(spec.capabilities.storage.capacity)
			record.hp = int(spec.max_hp)
			record.erase("remaining_ms")
			record.erase("construction_started")
			if record.get("layer", "ground") not in ["roof", "floor"]:
				for member: int in cells:
					world.queue_structure(member, bool(spec.facts.get("movement_blocked", false)), bool(spec.facts.get("enclosure_boundary", false)))
			world.objects.layout_revision += 1
			world.objects.reindex(action.target, cells)
		"rest": page.energy[row] = mini(10000, page.energy[row] + 2000)
		"eat":
			if world.objects.amount(action.target, "meal") <= 0:
				return "no_food"
			world.objects.add(action.target, "meal", -1)
			page.hunger[row] = mini(10000, page.hunger[row] + 3000)
			world.effects.apply_bundle(world, actor, actor, 0, "", preload("res://data/definitions/actions/meal_effect.tres").values(), at, 0, "activation")
		"cook":
			if world.objects.amount(actor, "grain") < 2 or world.objects.amount(actor, "water") < 1:
				return "missing_ingredients"
			if record.capacity >= 0 and world.objects.count_inventory(action.target) + 3 > record.capacity: return "no_output_capacity"
			world.objects.add(actor, "grain", -2)
			world.objects.add(actor, "water", -1)
			world.objects.add(action.target, "meal", 3)
	completed[action.kind] = int(completed.get(action.kind, 0)) + 1
	return "completed"


func demolish(world: RefCounted, target: int, at: int = -1) -> bool:
	if not world.objects.records.has(target):
		return false
	var record: Dictionary = world.objects.records[target]
	if record.tile < 0:
		return false
	if record.kind == "resource":
		# Keep source identity/stock indices valid; all timber becomes loose stock.
		record["vegetation_level"] = 0
		world.objects.layout_revision += 1
		return true
	world.forget_target(target, at)
	if record.kind == "floor":
		for tile: int in record.get("cells", PackedInt32Array([record.tile])):
			world.terrain.set_floor(tile, false)
	if record.kind == "plant":
		world.nature.remove(world, target, at)
		return true
	var guest: int = int(record.get("guest", 0))
	if guest > 0 and world.objects.records.has(guest):
		world.nature.remove(world, guest, at)
	var pile: int = 0
	if world.objects.count_inventory(target) > 0 or not record.get("materials", {}).is_empty():
		pile = world.objects.create("pile", "salvage", record.tile)
		for item: String in record.inventory.keys():
			world.objects.transfer(target, pile, item, world.objects.amount(target, item))
		for item: String in record.get("materials", {}):
			var count: int = record.materials[item]
			# Same material moves from the structure body into loose inventory.
			world.objects.add(pile, item, count)
			world.objects.totals[item] -= count
		record.erase("materials")
	var spec: Dictionary = definitions.get(record.definition, {})
	if (record.kind != "blueprint" or record.get("construction_started", false)) and record.get("layer", "ground") != "roof" and (spec.get("facts", {}).get("movement_blocked", false) or spec.get("facts", {}).get("enclosure_boundary", false)):
		for tile: int in record.get("cells", PackedInt32Array([record.tile])):
			world.queue_structure(tile, false, false, true)
	return world.objects.remove_empty(target)
