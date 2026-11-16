extends RefCounted
## Building/fixture state lives in object records. Work uses the world's common
## approach/reservation/timer/cancel contract, not a separate construction clock.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Positions = preload("res://scripts/sim/kernel/work_positions.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Query = preload("res://scripts/sim/kernel/operation_query.gd")
const Results = preload("res://scripts/sim/kernel/activity_results.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const Production = preload("res://scripts/sim/kernel/production.gd")
const Labor = preload("res://scripts/sim/kernel/labor_progress.gd")
const Sources = preload("res://scripts/sim/kernel/stock_sources.gd")
var definitions: Dictionary = {}
var completed: Dictionary = {}
var sources := PackedInt64Array() # Derived from completed carriers, never a second stock.


func _init() -> void:
	if not Query.BUILDINGS.is_empty():
		definitions = Query.BUILDINGS.duplicate(true)
		for key: String in definitions.keys():
			var errors: PackedStringArray = Positions.errors(definitions[key].get("work_positions", {}))
			errors.append_array(Sources.errors(definitions[key]))
			if not errors.is_empty():
				push_error(key + ": " + str(errors))
				definitions.erase(key)


func footprint(definition: String, tile: int, facing: int = 0) -> PackedInt32Array:
	return placed_cells(definitions.get(definition, {}), tile, facing)


static func placed_cells(spec: Dictionary, tile: int, facing: int = 0) -> PackedInt32Array:
	var result := PackedInt32Array()
	if spec.is_empty() or tile < 0 or tile >= Terrain.SIZE * Terrain.SIZE:
		return result
	var dimensions: Array = spec.size
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


func blueprint(world: RefCounted, actor: int, definition: String, tile: int, facing: int = 0, organization: int = 0) -> Dictionary:
	facing = posmod(facing, 4)
	var cells: PackedInt32Array = footprint(definition, tile, facing)
	if cells.is_empty():
		return {"reason": "invalid_definition_or_tile"}
	var spec: Dictionary = definitions[definition]
	var layer: String = str(spec.get("layer", "ground"))
	var site: String = placement(world, layer, cells)
	if site != "accepted":
		return {"reason": site}
	if layer == "floor":
		var clearing: String = clearing_reason(world, actor, cells)
		if not clearing.is_empty(): return {"reason": clearing}
	var amount: int = int(spec.amount)
	var item: String = str(spec.item)
	if organization > 0 and not world.institutions.permits(actor, organization, "construct"): return {"reason": "not_authorized"}
	var right: Dictionary = world.institutions.input_right(world, actor, {item: amount}, "construct", organization)
	if right.is_empty():
		return {"reason": "missing_materials"}
	var id: int = world.objects.create("blueprint", definition, tile)
	var record: Dictionary = world.objects.records[id]
	record["facing"] = facing
	record["layer"] = layer
	record["remaining_ms"] = int(spec.work_ms)
	record["construction_started"] = false
	record["max_hp"] = int(spec.max_hp)
	record.owner = right.owner
	record.organization = right.organization
	world.objects.reindex(id, cells)
	world.objects.transfer(actor, id, item, amount, right)
	world._sync_inventory(actor)
	world.knowledge.created(world, actor, id, world.operation_time())
	return {"reason": "accepted", "target": id}

func clearing_reason(world: RefCounted, actor: int, cells: PackedInt32Array) -> String:
	for tile: int in cells:
		for id: int in world.objects.by_tile.get(tile, []):
			if world.objects.records[id].kind != "plant" or int(world.objects.records[id].get("host", 0)) > 0: continue
			var reason: String = world.objects.Stock.access_reason(world.operation_actor(actor), world.operation_target(id), "uproot")
			if not reason.is_empty(): return reason
	return ""

func access_dependencies(world: RefCounted, target: int) -> Dictionary:
	var record: Dictionary = world.objects.records[target]
	var result: Dictionary = {}
	var plants: Array = []
	if record.kind == "blueprint" and record.get("layer", "ground") == "floor":
		for tile: int in record.cells:
			for id: int in world.objects.by_tile.get(tile, []):
				var plant: Dictionary = world.objects.records[id]
				if plant.kind == "plant" and int(plant.get("host", 0)) == 0: plants.append({"id": id, "owner": plant.owner, "organization": plant.organization, "operation": "uproot"})
		result["construct"] = plants
	var guest: int = int(record.get("guest", 0))
	if not record.get("work_stock", {}).is_empty():
		var right: Dictionary = world.objects.Stock.attribution(record.work_stock.values()[0][0])
		result["demolish"] = [{"id": target, "owner": right.owner, "organization": right.organization, "operation": "demolish"}]
	if guest > 0 and world.objects.records.has(guest):
		var plant: Dictionary = world.objects.records[guest]
		if not result.has("demolish"): result["demolish"] = []
		result.demolish.append({"id": guest, "owner": plant.owner, "organization": plant.organization, "operation": "uproot"})
	return result


func placement(world: RefCounted, layer: String, cells: PackedInt32Array, ignore: int = 0) -> String:
	if cells.is_empty(): return "invalid_definition_or_tile"
	for member: int in cells:
		if member < 0 or member >= Terrain.SIZE * Terrain.SIZE: return "invalid_definition_or_tile"
		var occupants: Array[Dictionary] = []
		for id: int in world.objects.by_tile.get(member, []):
			if id != ignore: occupants.append(world.objects.records[id])
		var reason: String = placement_at(layer, world.terrain.surface_at(member), occupants, world.nature.definitions)
		if reason != "accepted": return reason
	return "accepted"


static func placement_at(layer: String, surface: int, occupants: Array[Dictionary], plants: Dictionary) -> String:
	# Pure rule for authoritative placement and the player's detached known view.
	# Visibility and available materials are additional admission checks of each caller.
	if layer == "floor" and ((surface & 7) == Terrain.Substrate.WATER or (surface & 8) != 0): return "water_or_existing_floor"
	for other: Dictionary in occupants:
		var other_layer: String = str(other.get("layer", "ground"))
		var vegetation: int = int(plants.get(other.definition, {}).get("vegetation_level", 0)) if other.kind == "plant" else (int(other.get("vegetation_level", 3)) if other.kind == "resource" else 0)
		var loose_stock: bool = other.kind == "pile" or (other.kind == "resource" and vegetation == 0)
		if layer == "floor":
			if other_layer == "floor": return "occupied"
			if vegetation >= 2: return "clear_shrub_tree_or_stump_first"
		elif not loose_stock and (other_layer == layer or (layer == "ground" and other_layer not in ["floor", "roof"])): return "occupied"
	return "accepted"


func create_completed(world: RefCounted, definition: String, tile: int, facing: int = 0, capacity: int = -2) -> int:
	if footprint(definition, tile, facing).is_empty(): return 0
	var spec: Dictionary = definitions[definition]
	var kind: String = "chest" if spec.get("capabilities", {}).has("storage") else str(spec.kind)
	var id: int = world.objects.create(kind, definition, tile)
	world.objects.records[id]["facing"] = posmod(facing, 4)
	install(world, id, capacity)
	return id


func install(world: RefCounted, id: int, capacity: int = -2) -> void:
	# Called only after a completed facility's definition, anchor and facing exist.
	# Seeding and construction completion share the same spatial transaction.
	var record: Dictionary = world.objects.records[id]
	var spec: Dictionary = definitions[record.definition]
	record.kind = "chest" if spec.get("capabilities", {}).has("storage") else str(spec.kind)
	record["facing"] = posmod(int(record.get("facing", 0)), 4)
	record["layer"] = str(spec.get("layer", "ground"))
	record.hp = int(spec.max_hp)
	record["max_hp"] = int(spec.max_hp)
	world.objects.reindex(id, footprint(record.definition, record.tile, record.facing))
	if record.kind == "chest":
		record.capacity = int(spec.capabilities.storage.capacity) if capacity == -2 else capacity
		world.register_depot(id)
	Sources.install(world, id)
	for member: int in record.cells:
		if record.layer == "floor": world.terrain.set_floor(member, true)
		elif record.layer != "roof": world.queue_structure(member, bool(spec.facts.get("movement_blocked", false)), bool(spec.facts.get("enclosure_boundary", false)))


func uninstall(world: RefCounted, record: Dictionary) -> void:
	var source_index: int = sources.find(int(record.id))
	if source_index >= 0: sources.remove_at(source_index)
	if record.kind == "floor":
		for tile: int in record.get("cells", PackedInt32Array([record.tile])): world.terrain.set_floor(tile, false)
	var spec: Dictionary = definitions.get(record.definition, {})
	if (record.kind != "blueprint" or record.get("construction_started", false)) and record.get("layer", "ground") not in ["floor", "roof"] and (spec.get("facts", {}).get("movement_blocked", false) or spec.get("facts", {}).get("enclosure_boundary", false)):
		for tile: int in record.get("cells", PackedInt32Array([record.tile])): world.queue_structure(tile, false, false, true)


func seed_fixture(world: RefCounted, definition: String, tile: int, facing: int = 0) -> int:
	var spec: Dictionary = definitions[definition]
	var id: int = create_completed(world, definition, tile, facing)
	if id == 0: return 0
	var record: Dictionary = world.objects.records[id]
	world.objects.transfer(world.source_objects[0], id, str(spec.item), int(spec.amount))
	world.objects.install_materials(id)
	return id


func available(world: RefCounted, action: Dictionary, actor: int = 1) -> bool:
	var operation: Dictionary = Operations.OPERATIONS.get(action.get("operation_id", action.kind), {})
	return not operation.is_empty() and Query.evaluate(operation, world.operation_actor(actor), world.operation_target(action.target), {}, definitions).ready


func interrupt(world: RefCounted, action: Dictionary, now: int) -> Dictionary:
	if action.kind == "craft": return Production.interrupt(world, action, now)
	if action.kind not in ["construct", "sow"] or not world.objects.records.has(action.target):
		return {}
	var record: Dictionary = world.objects.records[action.target]
	if action.kind == "construct" and record.kind != "blueprint": return {}
	if action.kind == "sow" and record.get("stage", -1) != world.nature.Stage.SEEDING: return {}
	if not action.has("started_ms"): return {"worked_ms": 0, "remaining_ms": int(record.remaining_ms)}
	# The last quantum belongs to successful completion, never to a canceled run.
	var worked: int = Labor.credited(int(action.get("base_work_ms", record.remaining_ms)), int(action.get("scheduled_ms", record.remaining_ms)), now - int(action.started_ms))
	record.remaining_ms -= worked
	return {"worked_ms": worked, "remaining_ms": record.remaining_ms}


func finish(world: RefCounted, actor: int, action: Dictionary, at: int) -> String:
	return commit(world, actor, action, at).reason

func commit(world: RefCounted, actor: int, action: Dictionary, at: int) -> Dictionary:
	if not available(world, action, actor):
		return Results.refused("unavailable")
	if action.kind == "craft":
		var outcome: Dictionary = Production.commit(world, actor, action, at)
		if outcome.status == "completed" and outcome.facts.stage == "completed":
			var operation: String = str(action.get("operation_id", action.kind))
			completed[operation] = int(completed.get(operation, 0)) + 1
		return outcome
	if action.kind == "collect_source":
		var outcome: Dictionary = Sources.collect(world, actor, action.target, at, int(action.get("amount", 2147483647)))
		if outcome.status == "completed":
			var operation: String = str(action.get("operation_id", action.kind))
			completed[operation] = int(completed.get(operation, 0)) + 1
		return outcome
	var record: Dictionary = world.objects.records[action.target]
	var spec: Dictionary = definitions.get(record.definition, {})
	var facts: Dictionary = {}
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	match action.kind:
		"construct":
			facts = {"definition": record.definition, "worked_ms": int(record.remaining_ms), "remaining_ms": 0}
			var cells: PackedInt32Array = record.cells
			if record.get("layer", "ground") == "floor":
				var reason: String = placement(world, "floor", cells, action.target)
				if reason != "accepted":
					return Results.refused(reason)
				reason = clearing_reason(world, actor, cells)
				if not reason.is_empty(): return Results.refused(reason)
			if spec.get("facts", {}).get("movement_blocked", false):
				for body: RefCounted in world.pages:
					for index: int in body.ids.size():
						if body.ids[index] > 0 and body.health[index] > 0 and body.flight[index] == 0:
							for member: int in cells:
								if world._body_overlaps_tile(world.position_at(body.ids[index], at), body.radii[index], member):
									return Results.refused("occupied")
			if record.get("layer", "ground") == "floor":
				for member: int in cells:
					for other: int in world.objects.by_tile.get(member, []).duplicate():
						if world.objects.records[other].kind == "plant" and int(world.objects.records[other].get("host", 0)) == 0:
							world.nature.remove(world, other, at)
			world.objects.install_materials(action.target)
			facts["entrustments"] = world.institutions.complete_asset(world, action.target, "materials", at)
			record.erase("remaining_ms")
			record.erase("construction_started")
			install(world, action.target)
		"rest":
			var before: int = page.energy[row]
			page.energy[row] = mini(10000, before + roundi(2000 * Growth.rest_scale(world.objects.records[actor])))
			facts = {"energy_restored": page.energy[row] - before}
			if page.body_heat[row] >= 5.0 and page.body_heat[row] <= 40.0:
				facts["condition_recovery"] = Growth.recover_rest(world.objects.records[actor])
				if not facts.condition_recovery.is_empty(): world.Equipment.rebuild(world, actor)
		"eat":
			if not world.institutions.consume_at(world, actor, action.target, "meal", 1, "eat"):
				return Results.refused("no_food")
			var before: int = page.hunger[row]
			page.hunger[row] = mini(10000, before + 3000)
			facts = {"consumed": {"meal": 1}, "hunger_restored": page.hunger[row] - before}
			world.effects.apply_bundle(world, actor, actor, 0, "", preload("res://data/definitions/actions/meal_effect.tres").values(), at, 0, "activation")
	completed[action.kind] = int(completed.get(action.kind, 0)) + 1
	return Results.completed(facts)


func demolish(world: RefCounted, target: int, at: int = -1) -> bool:
	return demolish_result(world, target, at).status == "completed"

func demolish_result(world: RefCounted, target: int, at: int = -1, actor: int = 0) -> Dictionary:
	if not world.objects.records.has(target):
		return Results.refused("target_gone")
	var record: Dictionary = world.objects.records[target]
	if record.tile < 0:
		return Results.refused("invalid_target")
	# Equipment cannot be salvaged by this facility operation. Check before any
	# target callbacks, guest removal or material movement can commit changes.
	if not record.get("equipment", {}).is_empty(): return Results.refused("equipped_target")
	var guest: int = int(record.get("guest", 0))
	if actor > 0:
		var actor_view: Dictionary = world.operation_actor(actor)
		var reason: String = world.objects.Stock.access_reason(actor_view, world.operation_target(target), "demolish")
		if not reason.is_empty(): return Results.refused(reason)
		if guest > 0 and world.objects.records.has(guest):
			reason = world.objects.Stock.access_reason(actor_view, world.operation_target(guest), "uproot")
			if not reason.is_empty(): return Results.refused(reason)
	if record.kind == "resource":
		# Keep source identity/stock indices valid; all timber becomes loose stock.
		record["vegetation_level"] = 0
		world.objects.layout_revision += 1
		return Results.completed({"vegetation_level": 0})
	if not world.objects.can_consolidate(target, ["stock", "materials", "work_stock"]): return Results.refused("salvage_capacity")
	world.forget_target(target, at)
	if record.kind == "plant":
		world.nature.remove(world, target, at)
		return Results.completed({"removed": target, "definition": record.definition})
	if guest > 0 and world.objects.records.has(guest):
		world.nature.remove(world, guest, at)
	var pile: int = 0
	var salvage: Dictionary = {}
	if world.objects.count_inventory(target) > 0 or not record.get("materials", {}).is_empty() or not record.get("work_stock", {}).is_empty():
		pile = world.objects.create("pile", "salvage", record.tile)
		for item: String in world.objects.inventory_summary(target):
			salvage[item] = world.objects.transfer(target, pile, item, world.objects.amount(target, item))
		for field: String in ["materials", "work_stock"]:
			for item: String in record.get(field, {}).keys():
				var count: int = world.objects.transfer(target, pile, item, world.objects.Stock.count(record[field], item), {}, {}, field)
				salvage[item] = int(salvage.get(item, 0)) + count
			assert(record.get(field, {}).is_empty())
			record.erase(field)
	record.erase("process")
	return Results.completed({"removed": target, "definition": record.definition, "salvage_pile": pile, "salvage": salvage}) if world.remove_static(target, at) else Results.refused("failed")
