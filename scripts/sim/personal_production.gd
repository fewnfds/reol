class_name SimPersonalProduction
extends RefCounted
## Batches have one physical container in the owner's original inventory ledger.
## A stopped process retains material and labor; scene nodes never own either.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const Schema = preload("res://scripts/sim/production_schema.gd")
const MAX_ROUTE_STEPS: int = 1024
var definitions: Dictionary = {}
var batches: Dictionary = {}
var active: Dictionary = {}
var next_batch: int = 1
var next_job: int = 1
var _owner: WeakRef
var world: RefCounted:
	get:
		return _owner.get_ref()


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "pickup_ms", "max_batches", "recipes"]) or data.version != 1 or not Shape.count(data.pickup_ms, 1, 600000) or not Shape.count(data.max_batches, 1, 4096) or not data.recipes is Dictionary or data.recipes.is_empty():
		return false
	for id: Variant in data.recipes:
		var row: Variant = data.recipes[id]
		if not SimInventory._nonempty(id) or not Shape.keys(row, ["label", "place", "fuel", "inputs", "outputs", "work_ms"]) or not SimInventory._nonempty(row.label) or not SimInventory._nonempty(row.place) or not Shape.count(row.work_ms, 1, 86400000):
			return false
		for field: String in ["fuel", "inputs", "outputs"]:
			if not row[field] is Dictionary or row[field].is_empty() or not SimInventory._positive_items(row[field]):
				return false
		for item: String in row.fuel:
			if row.inputs.has(item) or row.outputs.has(item):
				return false
		for item: String in row.inputs:
			if row.outputs.has(item):
				return false
	return true


func bind_world(authority: RefCounted) -> void:
	# Rebind a validated candidate without resetting its saved process.
	_owner = weakref(authority)


func initialize(authority: RefCounted, rules: Dictionary) -> bool:
	if authority == null or not valid_definitions(rules):
		return false
	_owner = weakref(authority)
	definitions = rules.duplicate(true)
	return true


func create(actor: String, region: String, recipe: String, facility: String = "") -> Dictionary:
	if not definitions.recipes.has(recipe) or not world.regions.has(region) or batches.size() >= int(definitions.max_batches) or not _ready(actor):
		return reply(false, "先停稳并腾出双手，再准备一批自己的原料。")
	var home: String = world.artifacts.actor_home(actor)
	var sim: VillageSimulation = world.regions[home]
	var terms: Dictionary = definitions.recipes[recipe]
	if facility.is_empty() and not world.regions[region].places.has(terms.place) or not facility.is_empty() and not _facility_ready(facility, recipe, actor):
		return reply(false, "当地没有合适的作业场所。")
	var id: String = "production_batch:%d" % next_batch
	var batch: Dictionary = {"owner": actor, "home": home, "region": region, "recipe": recipe, "facility": facility, "created_ms": world.elapsed_ms,
		"supplied_ms": -1, "completed_ms": -1, "collected_ms": -1, "work_ms": 0, "state": "open"}
	var job: Dictionary = _job(actor, id, "make")
	if not _reserve(job, batch) or not _route(job, batch):
		_release_reservations(job, batch)
		return reply(false, "可自行处分的原料不足，或到不了作业场所；公物不能代用。")
	if not sim.inventory.create_container(id, {}):
		_release_reservations(job, batch)
		return reply(false, "无法保存这批在制物。")
	next_batch += 1
	batches[id] = batch
	_accept(job, batch)
	return reply(true, "带自己的材料到场，再点火动手；成品仍需实际取走。", id)


func begin(actor: String, id: String, kind: String) -> Dictionary:
	if not batches.has(id) or batches[id].owner != actor or not kind in ["make", "collect"] or not _ready(actor):
		return reply(false, "只能腾手后接着处理自己的那批东西。")
	var batch: Dictionary = batches[id]
	if kind == "make" and batch.state != "open" or kind == "collect" and batch.state != "ready":
		return reply(false, "这一批的阶段不适合这样处理。")
	var job: Dictionary = _job(actor, id, kind)
	if kind == "make" and int(batch.supplied_ms) < 0 and not _reserve(job, batch):
		return reply(false, "原料尚未投入，先备齐可处分的私料。")
	if not str(batch.facility).is_empty() and kind == "make" and not _facility_ready(str(batch.facility), str(batch.recipe), actor):
		_release_reservations(job, batch)
		return reply(false, "原工作台已不适用，原批次与物料仍留在现场。")
	if not _route(job, batch):
		_release_reservations(job, batch)
		return reply(false, "眼下到不了这一批东西所在的场所。")
	_accept(job, batch)
	return reply(true, "已动身；继续原批次不会再次点火取料。" if kind == "make" and int(batch.supplied_ms) >= 0 else "已动身处理原批次。", id)


func _job(actor: String, id: String, kind: String) -> Dictionary:
	return {"id": "production_job:%d" % next_job, "actor": actor, "batch": id, "kind": kind, "phase": "travel", "path": [], "segment_from": [], "segment_started_ms": world.elapsed_ms, "due_ms": world.elapsed_ms + 1, "started_ms": world.elapsed_ms, "work_started_ms": world.elapsed_ms, "previous_autonomous": false, "reservations": []}


func _accept(job: Dictionary, batch: Dictionary) -> void:
	var sim: VillageSimulation = world.regions[batch.home]
	next_job += 1
	job.previous_autonomous = bool(sim.actors[job.actor].autonomous)
	sim.actors[job.actor].autonomous = false
	sim.actors[job.actor].goal = str(definitions.recipes[batch.recipe].label)
	active[job.actor] = job
	world.invalidate_region(str(batch.home))


func _ready(actor: String) -> bool:
	if world.elapsed_ms >= SimInventory.MAX_COUNT or world.elapsed_ms != world.target_ms or not world.actor_controls(actor, "motion") or not world.actor_controls(actor, "action") or world.local_action_owns(actor) or world.artifacts.owns_actor(actor) or world.services != null and world.services.owns_actor(actor):
		return false
	var home: String = world.artifacts.actor_home(actor)
	if home.is_empty() or not world.synchronize_region(home):
		return false
	return world.regions[home].actors[actor].active.is_empty() and world.embodiment.capable(world.embodiment.carrier_for_source("village_actor", actor), "grasp")


func owns_actor(actor: String) -> bool:
	return active.has(actor)


func _reserve(job: Dictionary, batch: Dictionary) -> bool:
	var inventory: SimInventory = world.regions[batch.home].inventory
	var terms: Dictionary = definitions.recipes[batch.recipe]
	var inputs: Dictionary = terms.inputs.merged(terms.fuel)
	for item: String in SimAvianLife.sorted_keys(inputs):
		var id: String = str(job.id) + ":" + item
		if not inventory.reserve(id, "actor:" + str(job.actor), item, int(inputs[item]), str(job.actor)):
			_release_reservations(job, batch)
			return false
		job.reservations.append(id)
	return true


func _release_reservations(job: Dictionary, batch: Dictionary) -> void:
	for id: String in job.reservations:
		world.regions[batch.home].inventory.release(id)
	job.reservations = []


func _facility_ready(id: String, recipe: String, actor: String) -> bool:
	if not world.construction.has_capability(id, "workbench") or world.construction.definitions.site.region != world.artifacts.actor_home(actor):
		return false
	var terms: Dictionary = world.construction.definitions.types[world.construction.projects[id].type].capabilities.workbench
	var slots: Array[Dictionary] = world.construction.operation_slots(id, "workbench")
	return recipe in terms.recipes and not slots.is_empty() and world.facility_use != null and world.facility_use.slot_available(id, str(slots[0].id), "work", actor)


func work_cell(batch: Dictionary) -> Vector2i:
	if str(batch.facility).is_empty():
		return SimRouteTravel.cell(world.regions[batch.region].places[definitions.recipes[batch.recipe].place].cell)
	var slots: Array[Dictionary] = world.construction.operation_slots(str(batch.facility), "workbench")
	return slots[0].cell if not slots.is_empty() else Vector2i(-1, -1)


func _route(job: Dictionary, batch: Dictionary) -> bool:
	var sim: VillageSimulation = world.regions[batch.home]
	var body: Dictionary = sim.actors[job.actor]
	var from: Vector2i = SimRouteTravel.cell(body.cell)
	var target: Vector2i = work_cell(batch)
	var route: Array[Vector2i] = sim.find_path(from, target)
	if route.is_empty() and from != target:
		return false
	job.path = []
	for cell: Vector2i in route:
		if cell != from:
			job.path.append([cell.x, cell.y])
	if not SimRouteTravel.point(body).is_equal_approx(TileGrid.cell_to_world(from)):
		job.path.push_front([from.x, from.y])
	if job.path.size() > MAX_ROUTE_STEPS:
		return false
	var duration: int = 1
	var point: Vector2 = SimRouteTravel.point(body)
	for raw: Array in job.path:
		var next: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(raw))
		duration += maxi(1, ceili(point.distance_to(next) / float(sim.motion_rules.motion.speed) * 1000.0))
		point = next
	var work: int = int(definitions.pickup_ms) if job.kind == "collect" else maxi(1, int(definitions.recipes[batch.recipe].work_ms) - int(batch.work_ms))
	if duration > SimInventory.MAX_COUNT - world.elapsed_ms - work:
		return false
	SimRouteTravel.begin_segment(job, body, world.elapsed_ms, float(sim.motion_rules.motion.speed))
	return true


func at_workplace(job: Dictionary, batch: Dictionary) -> bool:
	var body: Dictionary = world.regions[batch.home].actors[job.actor]
	var cell: Vector2i = work_cell(batch)
	return SimRouteTravel.point(body).is_equal_approx(TileGrid.cell_to_world(cell))


func next_boundary_ms() -> int:
	var boundary: int = SimInventory.MAX_COUNT
	for job: Dictionary in active.values():
		if not world.actor_controls(str(job.actor), "action") or not world.actor_controls(str(job.actor), "motion"):
			return world.elapsed_ms + 1
		var body: Dictionary = world.regions[batches[job.batch].home].actors[job.actor]
		boundary = mini(boundary, SimRouteTravel.crossing_ms(job, body, world.elapsed_ms) if job.phase == "travel" else int(job.due_ms))
	return boundary


func settle_at_ms(now: int) -> void:
	for actor: String in SimAvianLife.sorted_keys(active):
		var job: Dictionary = active[actor]
		var batch: Dictionary = batches[job.batch]
		world.synchronize_region(str(batch.home))
		var sim: VillageSimulation = world.regions[batch.home]
		var body: Dictionary = sim.actors[actor]
		if not world.actor_controls(actor, "motion") or not world.actor_controls(actor, "action") or not str(batch.facility).is_empty() and job.kind == "make" and not _facility_ready(str(batch.facility), str(batch.recipe), actor):
			cancel(actor)
			continue
		if job.phase == "work" and not at_workplace(job, batch):
			cancel(actor)
			continue
		if job.phase == "travel":
			if not job.path.is_empty() and sim._step_validator.is_valid() and not bool(sim._step_validator.call(SimRouteTravel.cell(body.cell), SimRouteTravel.cell(job.path[0]) - SimRouteTravel.cell(body.cell))):
				cancel(actor)
				continue
			sim.project_actor_route(actor, job, now)
		if now < int(job.due_ms):
			continue
		if job.phase == "travel":
			if not job.path.is_empty():
				sim.set_actor_position(actor, TileGrid.cell_to_world(SimRouteTravel.cell(job.path.pop_front())))
			if not job.path.is_empty():
				SimRouteTravel.begin_segment(job, body, now, float(sim.motion_rules.motion.speed))
			else:
				_arrived(job, batch)
		elif job.kind == "collect":
			_collect(job, batch)
		else:
			_finish(job, batch)


func _arrived(job: Dictionary, batch: Dictionary) -> void:
	var terms: Dictionary = definitions.recipes[batch.recipe]
	var inventory: SimInventory = world.regions[batch.home].inventory
	if not at_workplace(job, batch):
		cancel(str(job.actor))
		return
	if job.kind == "make" and int(batch.supplied_ms) < 0:
		# Stage the whole lot in an independent ledger. Nothing in the original
		# bag/reservations changes unless every input and ignition succeeds.
		var candidate := SimInventory.new()
		var materials: Dictionary = terms.inputs.merged(terms.fuel)
		if job.reservations.size() != materials.size() or not candidate.restore(inventory.to_dict()):
			cancel(str(job.actor))
			return
		var seen: Dictionary = {}
		for id: String in job.reservations:
			if not candidate.reservations.has(id):
				cancel(str(job.actor))
				return
			var note: Dictionary = candidate.reservations[id]
			if not materials.has(note.item) or seen.has(note.item) or id != str(job.id) + ":" + str(note.item) or not Shape.same_record(note, {"container": "actor:" + str(job.actor), "item": str(note.item), "amount": int(materials[note.item]), "owner_id": str(job.actor)}):
				cancel(str(job.actor))
				return
			seen[note.item] = true
			if not candidate.transfer(str(job.batch) + ":input:" + str(note.item), str(note.container), str(job.batch), str(note.item), int(note.amount), id):
				cancel(str(job.actor))
				return
		for item: String in terms.fuel:
			if not candidate.consume(str(job.batch) + ":fuel:" + item, str(job.batch), item, int(terms.fuel[item])):
				cancel(str(job.actor))
				return
		_commit(inventory, candidate)
		job.reservations = []
		batch.supplied_ms = world.elapsed_ms
	job.phase = "work"
	job.path = []
	job.work_started_ms = world.elapsed_ms
	job.due_ms = world.elapsed_ms + (int(definitions.pickup_ms) if job.kind == "collect" else maxi(1, int(terms.work_ms) - int(batch.work_ms)))


func _finish(job: Dictionary, batch: Dictionary) -> void:
	var terms: Dictionary = definitions.recipes[batch.recipe]
	if batch.state != "open" or not at_workplace(job, batch):
		cancel(str(job.actor))
		return
	batch.work_ms = int(terms.work_ms)
	if not world.regions[batch.home].inventory.transform(str(job.batch) + ":finish", str(job.batch), terms.inputs, terms.outputs):
		_release(job, batch, "这批在制物尚不能完成，工时和物料留在原处。")
		return
	batch.state = "ready"
	batch.completed_ms = world.elapsed_ms
	_release(job, batch, "这一批已做成，成品仍在作业场所，尚未装进你的行囊。")


func _collect(job: Dictionary, batch: Dictionary) -> void:
	var inventory: SimInventory = world.regions[batch.home].inventory
	var terms: Dictionary = definitions.recipes[batch.recipe]
	if batch.state != "ready" or not at_workplace(job, batch):
		cancel(str(job.actor))
		return
	var candidate := SimInventory.new()
	if not candidate.restore(inventory.to_dict()):
		cancel(str(job.actor))
		return
	for item: String in terms.outputs:
		if candidate.available(str(job.batch), item) != int(terms.outputs[item]) or not candidate.transfer(str(job.batch) + ":collect:" + item, str(job.batch), "actor:" + str(job.actor), item, int(terms.outputs[item])):
			_release(job, batch, "行囊暂时装不下完整一批；成品仍留在原处。")
			return
	_commit(inventory, candidate)
	batch.state = "collected"
	batch.collected_ms = world.elapsed_ms
	_release(job, batch, "这一批成品已实际装入原行囊，可以自用或按当地条件交易。")


static func _commit(inventory: SimInventory, candidate: SimInventory) -> void:
	# Keep the original ledger identity; other domains still hold this instance.
	inventory.containers = candidate.containers
	inventory.reservations = candidate.reservations
	inventory.operations = candidate.operations
	inventory.custody = candidate.custody


func cancel(actor: String) -> bool:
	if not active.has(actor):
		return false
	var job: Dictionary = active[actor]
	var batch: Dictionary = batches[job.batch]
	if job.kind == "make" and job.phase == "work":
		batch.work_ms = mini(int(definitions.recipes[batch.recipe].work_ms), int(batch.work_ms) + maxi(0, world.elapsed_ms - int(job.work_started_ms)))
	_release(job, batch, "加工已停，原批次/已做工时保留；已燃的柴不会退回。")
	return true


func _release(job: Dictionary, batch: Dictionary, line: String) -> void:
	_release_reservations(job, batch)
	var sim: VillageSimulation = world.regions[batch.home]
	sim.actors[job.actor].autonomous = bool(job.previous_autonomous)
	sim.actors[job.actor].goal = line
	sim.actors[job.actor].retry_ms = mini(SimInventory.MAX_COUNT, world.elapsed_ms + int(sim.config.decision_interval) * 60000)
	active.erase(job.actor)
	world.invalidate_region(str(batch.home))


func progress(id: String) -> int:
	var batch: Dictionary = batches[id]
	for job: Dictionary in active.values():
		if job.batch == id and job.kind == "make" and job.phase == "work":
			return mini(int(definitions.recipes[batch.recipe].work_ms), int(batch.work_ms) + maxi(0, world.elapsed_ms - int(job.work_started_ms)))
	return int(batch.work_ms)


static func reply(ok: bool, line: String, id: String = "") -> Dictionary:
	return {"ok": ok, "line": line, "batch": id}


func to_dict() -> Dictionary:
	return {"version": 2, "batches": batches.duplicate(true), "active": active.duplicate(true), "next_batch": next_batch, "next_job": next_job}


static func empty_state() -> Dictionary:
	return {"version": 2, "batches": {}, "active": {}, "next_batch": 1, "next_job": 1}


func restore(data: Variant) -> bool:
	if not Schema.validate(data, self):
		return false
	batches = data.batches.duplicate(true)
	active = data.active.duplicate(true)
	next_batch = int(data.next_batch)
	next_job = int(data.next_job)
	return true
