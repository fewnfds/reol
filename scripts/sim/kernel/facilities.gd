extends RefCounted
## Building/fixture state lives in object records. Work uses the world's common
## approach/reservation/timer/cancel contract, not a separate construction clock.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
var definitions: Dictionary = {}
var completed: Dictionary = {}


func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/construction.json"))
	if parsed is Dictionary:
		definitions = parsed.get("types", {})


func footprint(definition: String, tile: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	if not definitions.has(definition) or tile < 0 or tile >= Terrain.SIZE * Terrain.SIZE:
		return result
	var size: Array = definitions[definition].size
	var origin: Vector2i = Terrain.cell(tile)
	if origin.x + int(size[0]) > Terrain.SIZE or origin.y + int(size[1]) > Terrain.SIZE:
		return result
	for y: int in int(size[1]):
		for x: int in int(size[0]):
			result.append(tile + y * Terrain.SIZE + x)
	return result


func interaction_tile(world: RefCounted, target: int, origin: Vector2 = Vector2(-1, -1)) -> int:
	var record: Dictionary = world.objects.records[target]
	var tile: int = record.tile
	if world.actor_slots.has(target):
		return world.terrain.nearest_open(Terrain.index(Vector2i(world.combat.position(world, target))))
	if record.kind in ["pile", "resource", "chest"] and world.terrain.blocked[tile] == 0:
		return tile
	var members: PackedInt32Array = record.get("cells", PackedInt32Array([tile]))
	var candidates: Array[int] = []
	for member: int in members:
		var point: Vector2i = Terrain.cell(member)
		for delta: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			var next: Vector2i = point + delta
			if next.x >= 0 and next.y >= 0 and next.x < Terrain.SIZE and next.y < Terrain.SIZE:
				var candidate: int = Terrain.index(next)
				if not members.has(candidate) and world.terrain.blocked[candidate] == 0 and not candidates.has(candidate):
					candidates.append(candidate)
	if origin.x < 0:
		return candidates[0] if not candidates.is_empty() else -1
	candidates.sort_custom(func(a: int, b: int): return Terrain.center(a).distance_squared_to(origin) < Terrain.center(b).distance_squared_to(origin))
	var start := Vector2i(origin)
	for candidate: int in candidates:
		# Search from the operation side: an isolated pocket fails cheaply. This
		# is cold action admission, never a per-body/per-step path search.
		if not world.lanes[0].graph.get_id_path(Terrain.cell(candidate), start).is_empty():
			return candidate
	return -1


func blueprint(world: RefCounted, actor: int, definition: String, tile: int) -> Dictionary:
	var cells: PackedInt32Array = footprint(definition, tile)
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
	record["layer"] = layer
	record["remaining_ms"] = int(spec.work_ms)
	record["max_hp"] = int(spec.max_hp)
	world.objects.reindex(id, cells)
	world.objects.transfer(actor, id, item, amount)
	world._sync_inventory(actor)
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


func seed_fixture(world: RefCounted, definition: String, tile: int) -> int:
	var spec: Dictionary = definitions[definition]
	var kind: String = "chest" if spec.get("capabilities", {}).has("storage") else str(spec.kind)
	var id: int = world.objects.create(kind, definition, tile)
	var record: Dictionary = world.objects.records[id]
	record.hp = int(spec.max_hp)
	record["max_hp"] = int(spec.max_hp)
	record["layer"] = spec.get("layer", "ground")
	world.objects.reindex(id, footprint(definition, tile))
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
						if body.ids[index] > 0 and cells.has(Terrain.index(Vector2i(body.positions[index]))):
							return "occupied"
			record.kind = str(spec.kind)
			record["materials"] = record.inventory
			record.inventory = {}
			if spec.get("capabilities", {}).has("storage"):
				record.kind = "chest"
				record.capacity = int(spec.capabilities.storage.capacity)
			record.hp = int(spec.max_hp)
			record.erase("remaining_ms")
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
		"cook":
			if world.objects.amount(actor, "grain") < 2 or world.objects.amount(actor, "water") < 1:
				return "missing_ingredients"
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
	if record.kind != "blueprint" and record.get("layer", "ground") != "roof" and (spec.get("facts", {}).get("movement_blocked", false) or spec.get("facts", {}).get("enclosure_boundary", false)):
		for tile: int in record.get("cells", PackedInt32Array([record.tile])):
			world.queue_structure(tile, false, false, true)
	return world.objects.remove_empty(target)
