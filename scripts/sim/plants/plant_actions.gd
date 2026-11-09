extends RefCounted
## Plant-owned action processes using the common body, route and reservation
## contract. No second actor position, item stock or clock.
const Shape = preload("res://scripts/sim/avian_schema.gd")
const VERBS: Array[String] = ["harvest", "cut", "uproot", "remove", "transplant", "water"]
var active: Dictionary = {}
var receipts: Dictionary = {}
var next_id: int = 1
var _owner: WeakRef
var plants: SimPlants:
	get: return _owner.get_ref()
var world: RegionalSimulation:
	get: return plants.world


func _init(owner: SimPlants) -> void:
	_owner = weakref(owner)


func begin(actor: String, id: String, verb: String, destination: Dictionary = {}, operation: String = "") -> Dictionary:
	if not plants.bodies.has(id) or verb not in VERBS or not world.accepts_commands() or world.elapsed_ms != world.target_ms:
		return _reply(false, "unavailable")
	var signature: Dictionary = {"actor": actor, "plant": id, "kind": verb, "destination": destination.duplicate(true)}
	if not operation.is_empty() and receipts.has(operation):
		return receipts[operation].result.duplicate(true) if receipts[operation].request == signature else _reply(false, "operation_conflict")
	if active.has(actor):
		return {"ok": true, "id": active[actor].id} if active[actor].id == operation and active[actor].request == signature else _reply(false, "busy")
	var row: Dictionary = plants.bodies[id]
	var region: String = str(row.region)
	if not world.synchronize_region(region) or not SimActionContract.can_begin(world, region, actor) or not _eligible(actor, id, verb, destination):
		return _reply(false, "conditions_or_consent")
	var sim: VillageSimulation = world.regions[region]
	# Registered resource places are already known work destinations. Seeking
	# one may start from afar; arbitrary individual plants still require sight.
	if str(row.legacy_source).is_empty() and SimRouteTravel.point(sim.actors[actor]).distance_to(TileGrid.cell_to_world(plants.cell_of(id))) > float(sim.config.observation_radius) * TileGrid.TILE_SIZE:
		return _reply(false, "unobserved")
	for job: Dictionary in active.values():
		if job.plant == id or verb == "transplant" and destination == job.destination:
			return _reply(false, "reserved")
	var stand: Array = _stand(actor, id)
	if stand.is_empty():
		return _reply(false, "unreachable")
	var action_id: String = operation if not operation.is_empty() else "plant_action:%d" % next_id
	if operation.is_empty():
		while receipts.has(action_id) or _operation_active(action_id):
			next_id += 1
			action_id = "plant_action:%d" % next_id
	if receipts.has(action_id) or _operation_active(action_id):
		return _reply(false, "operation_conflict")
	var item: String = str(plants.definitions.types[row.definition].product.item) if verb == "harvest" else "water"
	var source: String = plants.container_id(id) if verb == "harvest" else "actor:" + actor
	if verb in ["harvest", "water"] and not sim.inventory.reserve(action_id, source, item, 1, actor):
		return _reply(false, "no_product_or_water")
	next_id += 1
	var job: Dictionary = {"id": action_id, "request": signature, "actor": actor, "plant": id, "kind": verb, "region": region,
		"destination": destination.duplicate(true), "target_location": row.location.duplicate(true), "stand": stand,
		"started_ms": world.elapsed_ms, "work_started_ms": 0, "due_ms": world.elapsed_ms + 1,
		"phase": "travel", "path": [], "segment_from": sim.actors[actor].position.duplicate(), "segment_started_ms": world.elapsed_ms,
		"previous_autonomous": SimActionContract.occupy(world, region, actor)}
	active[actor] = job
	if not _route(job, stand):
		_finish(job, "failed", "unreachable")
		return _reply(false, "unreachable")
	return {"ok": true, "id": action_id}


func _operation_active(id: String) -> bool:
	for job: Dictionary in active.values():
		if job.id == id:
			return true
	return false


func _eligible(actor: String, id: String, verb: String, destination: Dictionary) -> bool:
	var row: Dictionary = plants.bodies[id]
	if row.stage == "removed":
		return false
	if row.hp > 0 and not str(row.subject).is_empty() and (verb != "harvest" or not bool(row.contacts.get(actor, {}).get("consent", false))):
		return false
	if verb == "transplant":
		if not row.legacy_source.is_empty() or not Shape.keys(destination, ["cell", "support"]) or not Shape.cell_valid(destination.cell) or not destination.support is String:
			return false
		if not destination.support.is_empty() and row.region != world.construction.definitions.site.region:
			return false
		var cell: Vector2i = SimRouteTravel.cell(destination.cell)
		if cell.distance_to(plants.cell_of(id)) > 1.0 or not str(destination.support).is_empty() and (not world.construction.projects.has(destination.support) or SimRouteTravel.cell(world.construction.projects[destination.support].cell) != cell):
			return false # First transport seam: a real adjacent, reachable transfer.
		var conditions: Dictionary = plants.habitat(cell, destination.support)
		return row.hp > 0 and not conditions.is_empty() and plants.definitions.types[row.definition].substrates.has(conditions.substrate) and plants._rootable(cell, destination.support, id, bool(plants.definitions.types[row.definition].blocks))
	if not destination.is_empty():
		return false
	if verb == "harvest":
		return row.hp > 0 and row.stage == "fruiting"
	if verb == "cut":
		return row.hp > 0 and row.stage not in ["root", "dead"] and not bool(row.body_taken) and row.legacy_source.is_empty()
	if verb == "uproot":
		return row.hp > 0 and row.legacy_source.is_empty()
	if verb == "remove":
		return row.stage in ["root", "dead"] and row.legacy_source.is_empty()
	return row.hp > 0


func _stand(actor: String, id: String) -> Array:
	var sim: VillageSimulation = world.regions[plants.bodies[id].region]
	var from: Vector2i = SimRouteTravel.cell(sim.actors[actor].cell)
	var target: Vector2i = plants.cell_of(id)
	var best: Array = []
	var length: int = SimInventory.MAX_COUNT
	for direction: Vector2i in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
		var cell: Vector2i = target + direction
		if not world.map_data.terrain_is_walkable(cell) or world.construction.blocked(cell) or plants.blocked(cell):
			continue
		var path: Array[Vector2i] = sim.find_path(from, cell)
		if from != cell and path.is_empty():
			continue
		if path.size() < length:
			length = path.size()
			best = [cell.x, cell.y]
	return best


func _route(job: Dictionary, raw: Array) -> bool:
	var sim: VillageSimulation = world.regions[job.region]
	var body: Dictionary = sim.actors[job.actor]
	var from: Vector2i = SimRouteTravel.cell(body.cell)
	var to: Vector2i = SimRouteTravel.cell(raw)
	var path: Array[Vector2i] = sim.find_path(from, to)
	if from != to and path.is_empty():
		return false
	job.path = []
	for cell: Vector2i in path:
		job.path.append([cell.x, cell.y])
	if job.path.is_empty() and not SimRouteTravel.point(body).is_equal_approx(TileGrid.cell_to_world(to)):
		job.path.append(raw.duplicate())
	job.phase = "travel"
	SimRouteTravel.begin_segment(job, body, world.elapsed_ms, float(sim.motion_rules.motion.speed))
	return true


func next_boundary_ms() -> int:
	var result: int = SimInventory.MAX_COUNT
	for job: Dictionary in active.values():
		var sim: VillageSimulation = world.regions[job.region]
		result = mini(result, SimRouteTravel.crossing_ms(job, sim.actors[job.actor], world.elapsed_ms) if job.phase == "travel" else int(job.due_ms))
	return result


func settle_at_ms(now: int) -> void:
	var actors: Array = active.keys()
	actors.sort()
	for actor: String in actors:
		var job: Dictionary = active[actor]
		world.synchronize_region(job.region)
		var sim: VillageSimulation = world.regions[job.region]
		var expected: Array = [] if job.phase == "travel" else [TileGrid.cell_to_world(SimRouteTravel.cell(job.stand)).x, TileGrid.cell_to_world(SimRouteTravel.cell(job.stand)).y]
		if not SimActionContract.can_continue(world, job.region, actor, &"plants", expected) or not _eligible(actor, job.plant, job.kind, job.destination) or plants.bodies[job.plant].location != job.target_location:
			_finish(job, "cancelled", "target_or_control_changed")
			continue
		if job.phase == "travel":
			if not job.path.is_empty():
				var to: Vector2i = SimRouteTravel.cell(job.path[0])
				var from: Vector2i = SimRouteTravel.cell(sim.actors[actor].cell)
				if plants.blocked(to) or world.construction.blocked(to) or sim._step_validator.is_valid() and not sim._step_validator.call(from, to - from):
					_finish(job, "cancelled", "route_changed")
					continue
				sim.project_actor_route(actor, job, now)
			if now < int(job.due_ms):
				continue
			if not job.path.is_empty():
				sim.set_actor_position(actor, TileGrid.cell_to_world(SimRouteTravel.cell(job.path.pop_front())))
			if not job.path.is_empty():
				SimRouteTravel.begin_segment(job, sim.actors[actor], now, float(sim.motion_rules.motion.speed))
				continue
			job.phase = "work"
			job.work_started_ms = now
			job.due_ms = now + int(plants.definitions.action_ms)
		elif now >= int(job.due_ms):
			_complete(job)


func _complete(job: Dictionary) -> void:
	var id: String = job.plant
	if not plants._settle_body(id, world.elapsed_ms):
		_finish(job, "failed", "environment_unavailable")
		return
	if not _eligible(job.actor, id, job.kind, job.destination) or plants.bodies[id].location != job.target_location:
		_finish(job, "cancelled", "target_changed_during_settlement")
		return
	var row: Dictionary = plants.bodies[id].duplicate(true)
	var rule: Dictionary = plants.definitions.types[row.definition]
	var sim: VillageSimulation = world.regions[job.region]
	var inventory := SimInventory.new()
	if not inventory.restore(sim.inventory.to_dict()):
		_finish(job, "failed", "inventory_invalid")
		return
	var container: String = plants.container_id(id)
	var operation: String = str(job.id) + ":harvest"
	if job.kind == "harvest":
		if not inventory.transfer(operation, container, "actor:" + str(job.actor), str(rule.product.item), 1, job.id):
			_finish(job, "failed", "product_lost")
			return
	elif job.kind in ["cut", "uproot"]:
		var item: String = rule.body_product.item
		@warning_ignore("integer_division")
		var amount: int = 0 if row.body_taken else int(rule.body_product.amount) * mini(int(row.growth_ms), int(rule.mature_ms)) / int(rule.mature_ms)
		if amount > 0:
			inventory.containers[container][item] = inventory.quantity(container, item) + amount
			row.produced[item] = int(row.produced.get(item, 0)) + amount
			if not inventory.transfer(operation, container, "actor:" + str(job.actor), item, amount):
				_finish(job, "failed", "product_transfer_failed")
				return
		row.body_taken = true
		row.growth_ms = 0
		row.fruit_ms = 0
		row.generation = int(row.generation) + 1
		row.stage = "root" if job.kind == "cut" and bool(rule.regrow) else "removed"
	elif job.kind == "remove":
		row.stage = "removed"
	elif job.kind == "transplant":
		row.location = {"cell": job.destination.cell.duplicate() if str(job.destination.support).is_empty() else [], "support": job.destination.support}
		row.water = 0 if not str(row.location.support).is_empty() else int(plants.habitat(SimRouteTravel.cell(job.destination.cell)).moisture) * SimPlantRules.WATER_UNIT
		if job.destination.cell not in row.claimed_cells:
			row.claimed_cells.append(job.destination.cell.duplicate())
		row.hp = maxi(1, int(row.hp) - 1)
		row.conditions = plants.habitat(SimRouteTravel.cell(job.destination.cell), str(job.destination.support))
	elif job.kind == "water":
		inventory.release(job.id)
		if not inventory.consume(str(job.id) + ":water", "actor:" + str(job.actor), "water", 1):
			_finish(job, "failed", "water_lost")
			return
		if str(row.location.support).is_empty():
			row.water = mini(100 * SimPlantRules.WATER_UNIT, int(row.water) + 60 * SimPlantRules.WATER_UNIT)
	if job.kind in ["cut", "uproot", "remove"]:
		# Fruit attached to a removed crown cannot remain stranded in an
		# unreachable source container. Transfer the original remaining stock.
		for item: String in inventory.containers[container].keys():
			var amount: int = inventory.quantity(container, item)
			if amount > 0 and not inventory.transfer(str(job.id) + ":remains:" + item, container, "actor:" + str(job.actor), item, amount):
				_finish(job, "failed", "reserved_remains")
				return
	if row.stage == "removed":
		row.next_ms = SimInventory.MAX_COUNT
		var cell: Vector2i = plants.cell_of(id)
		row.location = {"cell": [cell.x, cell.y], "support": ""}
	if not plants._publish_source(id, row):
		_finish(job, "failed", "source_change_failed")
		return
	var old_support: String = str(plants.bodies[id].location.support)
	if row.location != plants.bodies[id].location or row.stage == "removed":
		if not old_support.is_empty():
			world.construction.cultivation[old_support].plant = ""
		if not str(row.location.support).is_empty() and row.stage != "removed":
			world.construction.cultivation[row.location.support].plant = id
	if job.kind == "water" and not old_support.is_empty():
		var terms: Dictionary = world.construction.definitions.types[world.construction.projects[old_support].type].capabilities.cultivation
		world.construction.cultivation[old_support].water = mini(int(terms.water_capacity), int(world.construction.cultivation[old_support].water) + 60 * SimPlantRules.WATER_UNIT)
	if job.kind == "harvest" and not str(row.legacy_source).is_empty():
		sim.land_resources.sources[row.legacy_source].extracted += 1
	sim.inventory.containers = inventory.containers
	sim.inventory.reservations = inventory.reservations
	sim.inventory.operations = inventory.operations
	sim.inventory.custody = inventory.custody
	plants._forget(id)
	plants.bodies[id] = row
	plants._track(id)
	plants._notify(id)
	_finish(job, "completed", "applied")


func reconcile_target(id: String) -> void:
	# Target changes after the action phase must still leave a loadable complete
	# boundary. Preserve spent time, release ownership and never apply effects.
	for actor: String in active.keys():
		if not active.has(actor):
			continue
		var job: Dictionary = active[actor]
		if job.plant == id and (not _eligible(actor, id, job.kind, job.destination) or plants.bodies[id].location != job.target_location):
			_finish(job, "cancelled", "target_changed")


func cancel(actor: String) -> bool:
	if not active.has(actor) or not world.accepts_commands():
		return false
	_finish(active[actor], "cancelled", "interrupted")
	return true


func _finish(job: Dictionary, status: String, reason: String) -> void:
	active.erase(job.actor)
	SimActionContract.release(world, job.region, job.actor, bool(job.previous_autonomous), job.id)
	var result: Dictionary = {"ok": status == "completed", "id": job.id, "status": status, "reason": reason}
	var operations: Dictionary = {}
	var inventory: SimInventory = world.regions[job.region].inventory
	var rule: Dictionary = plants.definitions.types[plants.bodies[job.plant].definition]
	for suffix: String in [":harvest", ":water", ":remains:" + str(rule.product.item), ":remains:" + str(rule.body_product.item)]:
		var key: String = str(job.id) + suffix
		if inventory.operations.has(key):
			operations[key] = inventory.operations[key].duplicate(true)
	receipts[job.id] = {"request": job.request.duplicate(true), "result": result, "at_ms": world.elapsed_ms, "operations": operations}
	SimActionContract.publish_finished(world, SimActionContract.view(world, "plants", job.id, job.actor, job.kind, job.phase, int(job.started_ms), int(job.due_ms), status, job.plant), reason)


func _reply(ok: bool, reason: String) -> Dictionary:
	return {"ok": ok, "reason": reason}


func to_dict() -> Dictionary:
	return {"active": active.duplicate(true), "receipts": receipts.duplicate(true), "next_id": next_id}
