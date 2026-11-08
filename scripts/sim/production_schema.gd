extends RefCounted
## Candidate-only validation: batches name original ledger containers, never stock.
const Shape = preload("res://scripts/sim/avian_schema.gd")


static func inventory_scope(data: Variant, region: String, rules: Dictionary) -> Dictionary:
	var scope: Dictionary = {"containers": {}, "operations": {}, "reservations": {}}
	if not data is Dictionary or not data.get("batches") is Dictionary or not data.get("active") is Dictionary:
		return scope
	for id: Variant in data.batches:
		var batch: Variant = data.batches[id]
		if not id is String or not batch is Dictionary or batch.get("home") != region or not rules.recipes.has(batch.get("recipe")):
			continue
		var terms: Dictionary = rules.recipes[batch.recipe]
		scope.containers[id] = true
		for item: String in terms.inputs.merged(terms.fuel):
			scope.operations[id + ":input:" + item] = true
		for item: String in terms.fuel:
			scope.operations[id + ":fuel:" + item] = true
		scope.operations[id + ":finish"] = true
		for item: String in terms.outputs:
			scope.operations[id + ":collect:" + item] = true
	for job: Variant in data.active.values():
		if job is Dictionary and data.batches.has(job.get("batch")) and data.batches[job.batch] is Dictionary and data.batches[job.batch].get("home") == region and job.get("reservations") is Array:
			for id: Variant in job.reservations:
				if id is String:
					scope.reservations[id] = true
	return scope


static func validate(data: Variant, domain: RefCounted) -> bool:
	if not Shape.keys(data, ["version", "batches", "active", "next_batch", "next_job"]) or data.version != 2 or not data.batches is Dictionary or not data.active is Dictionary or not Shape.count(data.next_batch, 1, int(domain.definitions.max_batches) + 1) or not Shape.count(data.next_job, int(data.next_batch)) or data.batches.size() != int(data.next_batch) - 1:
		return false
	var expected: Dictionary = {}
	var reservations: Dictionary = {}
	var job_ids: Dictionary = {}
	for index: int in range(1, int(data.next_batch)):
		var id: String = "production_batch:%d" % index
		if not _batch(data.batches.get(id), id, data, domain, expected, job_ids):
			return false
	for actor: Variant in data.active:
		if not actor is String or not _job(actor, data.active[actor], data, domain, reservations, job_ids):
			return false
	# Check both directions. An orphan receipt, extra reservation or another
	# domain's operation touching a batch cannot slip through the scope grant.
	for region: String in domain.world.regions:
		var inventory: SimInventory = domain.world.regions[region].inventory
		for id: String in inventory.operations:
			var op: Dictionary = inventory.operations[id]
			var touches: bool = id.begins_with("production_")
			for field: String in ["container", "source", "target"]:
				touches = touches or str(op.get(field, "")).begins_with("production_batch:")
			if touches and (not expected.has(id) or expected[id].region != region or not Shape.same_record(op, expected[id].record)):
				return false
		for id: String in inventory.reservations:
			var note: Dictionary = inventory.reservations[id]
			if id.begins_with("production_") or str(note.container).begins_with("production_batch:"):
				if not reservations.has(id) or reservations[id].region != region or not Shape.same_record(note, reservations[id].record):
					return false
		for note: Dictionary in inventory.custody.values():
			if str(note.container).begins_with("production_batch:"):
				return false
	return true


static func _batch(batch: Variant, id: String, data: Dictionary, domain: RefCounted, expected: Dictionary, jobs: Dictionary) -> bool:
	var world: RefCounted = domain.world
	if not Shape.keys(batch, ["owner", "home", "region", "recipe", "facility", "created_ms", "supplied_ms", "completed_ms", "collected_ms", "work_ms", "state"]) or not batch.owner is String or not world.regions.has(batch.home) or not world.regions.has(batch.region) or not domain.definitions.recipes.has(batch.recipe) or not world.regions[batch.home].actors.has(batch.owner) or not batch.state in ["open", "ready", "collected"]:
		return false
	var terms: Dictionary = domain.definitions.recipes[batch.recipe]
	var inventory: SimInventory = world.regions[batch.home].inventory
	if not batch.facility is String:
		return false
	if not str(batch.facility).is_empty():
		if not world.construction.projects.has(batch.facility) or batch.region != world.construction.definitions.site.region or batch.home != batch.region:
			return false
		var building: Dictionary = world.construction.projects[batch.facility]
		var capability: Dictionary = world.construction.definitions.types[building.type].capabilities.get("workbench", {})
		if building.state not in ["built", "ruined", "removed"] or batch.recipe not in capability.get("recipes", []) or not Shape.count(batch.created_ms, int(building.completed_ms), world.elapsed_ms):
			return false
	if batch.facility.is_empty() and not world.regions[batch.region].places.has(terms.place) or not inventory.containers.has(id) or not Shape.count(batch.work_ms, 0, int(terms.work_ms)) or not Shape.count(batch.created_ms, 0, world.elapsed_ms):
		return false
	for field: String in ["supplied_ms", "completed_ms", "collected_ms"]:
		if not Shape.count(batch[field], -1, world.elapsed_ms):
			return false
	var supplied: bool = int(batch.supplied_ms) >= 0
	var completed: bool = batch.state != "open"
	var collected: bool = batch.state == "collected"
	if supplied and batch.supplied_ms < batch.created_ms or not supplied and (completed or batch.work_ms != 0) or completed != (int(batch.completed_ms) >= 0) or collected != (int(batch.collected_ms) >= 0):
		return false
	if supplied and int(batch.work_ms) > world.elapsed_ms - int(batch.supplied_ms) or completed and (batch.work_ms != terms.work_ms or int(batch.completed_ms) - int(batch.supplied_ms) < int(terms.work_ms)) or collected and int(batch.collected_ms) - int(batch.completed_ms) < int(domain.definitions.pickup_ms):
		return false
	var materials: Dictionary = terms.inputs.merged(terms.fuel)
	var allowed: Dictionary = materials.merged(terms.outputs)
	var remaining: Dictionary = {} if not supplied or collected else terms.outputs if completed else terms.inputs
	for item: String in inventory.containers[id]:
		if not allowed.has(item) or inventory.quantity(id, item) != int(remaining.get(item, 0)):
			return false
	for item: String in remaining:
		if inventory.quantity(id, item) != int(remaining[item]):
			return false
	var supply_job: String = ""
	for item: String in materials:
		if not supplied:
			continue
		var receipt: Variant = inventory.operations.get(id + ":input:" + item)
		if not receipt is Dictionary or not receipt.get("reservation_id") is String:
			return false
		var reservation: String = receipt.reservation_id
		var job: String = reservation.trim_suffix(":" + item)
		if reservation != job + ":" + item or not allocated(job, "production_job:", int(data.next_job)) or not supply_job.is_empty() and supply_job != job or jobs.has(job) and jobs[job] != id:
			return false
		supply_job = job
		jobs[job] = id
		expected[id + ":input:" + item] = {"region": batch.home, "record": _transfer("actor:" + str(batch.owner), id, item, int(materials[item]), reservation)}
	if supplied:
		for item: String in terms.fuel:
			expected[id + ":fuel:" + item] = {"region": batch.home, "record": {"kind": "consume", "container": id, "item": item, "amount": int(terms.fuel[item])}}
	if completed:
		expected[id + ":finish"] = {"region": batch.home, "record": {"kind": "transform", "container": id, "inputs": SimInventory._copy_items(terms.inputs), "outputs": SimInventory._copy_items(terms.outputs)}}
	if collected:
		for item: String in terms.outputs:
			expected[id + ":collect:" + item] = {"region": batch.home, "record": _transfer(id, "actor:" + str(batch.owner), item, int(terms.outputs[item]), "")}
	for op: String in expected:
		if op.begins_with(id + ":") and not Shape.same_record(inventory.operations.get(op), expected[op].record):
			return false
	return true


static func _job(actor: String, job: Variant, data: Dictionary, domain: RefCounted, reservations: Dictionary, jobs: Dictionary) -> bool:
	if not Shape.keys(job, ["id", "actor", "batch", "kind", "phase", "path", "segment_from", "segment_started_ms", "due_ms", "started_ms", "work_started_ms", "previous_autonomous", "reservations"]) or job.actor != actor or not allocated(job.id, "production_job:", int(data.next_job)) or not data.batches.has(job.batch) or not job.kind in ["make", "collect"] or not job.phase in ["travel", "work"] or not job.path is Array or job.path.size() > domain.MAX_ROUTE_STEPS or not job.previous_autonomous is bool or not job.reservations is Array:
		return false
	var batch: Dictionary = data.batches[job.batch]
	var world: RefCounted = domain.world
	var sim: VillageSimulation = world.regions[batch.home]
	var body: Dictionary = sim.actors[batch.owner]
	var terms: Dictionary = domain.definitions.recipes[batch.recipe]
	if actor != batch.owner or bool(body.autonomous) or not body.active.is_empty() or not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or not world.embodiment.capable(world.embodiment.carrier_for_source("village_actor", actor), "grasp"):
		return false
	for other: RefCounted in [world.artifacts, world.admissions, world.soul_vessels, world.sparring, world.services, world.construction, world.resting, world.method_records]:
		if other != null and other.owns_actor(actor):
			return false
	if jobs.has(job.id) and jobs[job.id] != job.batch:
		return false
	if jobs.has(job.id) and (job.kind != "make" or job.started_ms > batch.supplied_ms or job.work_started_ms != batch.supplied_ms or batch.work_ms != 0):
		return false
	jobs[job.id] = job.batch
	if job.kind == "make" and batch.state != "open" or job.kind == "collect" and batch.state != "ready":
		return false
	for field: String in ["started_ms", "work_started_ms", "segment_started_ms"]:
		if not Shape.count(job[field], int(batch.created_ms), world.elapsed_ms):
			return false
	if job.work_started_ms < job.started_ms or job.segment_started_ms < job.started_ms or not Shape.count(job.due_ms, world.elapsed_ms + 1):
		return false
	var materials: Dictionary = terms.inputs.merged(terms.fuel)
	var needs_supply: bool = job.kind == "make" and int(batch.supplied_ms) < 0
	if job.reservations.size() != (materials.size() if needs_supply else 0) or needs_supply and job.phase != "travel":
		return false
	for id: Variant in job.reservations:
		if not id is String or reservations.has(id):
			return false
		var item: String = id.trim_prefix(str(job.id) + ":")
		if id != str(job.id) + ":" + item or not materials.has(item):
			return false
		var note: Dictionary = {"container": "actor:" + actor, "item": item, "amount": int(materials[item]), "owner_id": actor}
		if not Shape.same_record(sim.inventory.reservations.get(id), note):
			return false
		reservations[id] = {"region": batch.home, "record": note}
	var point: Vector2i = domain.work_cell(batch)
	var target: Array = [point.x, point.y]
	if job.phase == "travel":
		var current: Vector2i = SimRouteTravel.cell(body.cell)
		for raw: Variant in job.path:
			if not Shape.cell_valid(raw) or raw[0] >= ReolWorld.WORLD_SIZE or raw[1] >= ReolWorld.WORLD_SIZE:
				return false
			var next: Vector2i = SimRouteTravel.cell(raw)
			if absi(next.x - current.x) > 1 or absi(next.y - current.y) > 1:
				return false
			current = next
		if current != SimRouteTravel.cell(target) or not SimRouteTravel.valid_segment(job, body, world.elapsed_ms, float(sim.motion_rules.motion.speed)):
			return false
	else:
		var duration: int = int(domain.definitions.pickup_ms) if job.kind == "collect" else maxi(1, int(terms.work_ms) - int(batch.work_ms))
		if not job.path.is_empty() or not SimRouteTravel.point(body).is_equal_approx(TileGrid.cell_to_world(SimRouteTravel.cell(target))) or int(job.due_ms) != int(job.work_started_ms) + duration or job.kind == "make" and int(batch.supplied_ms) > int(job.work_started_ms):
			return false
	return true


static func allocated(id: Variant, prefix: String, limit: int) -> bool:
	if not id is String or not id.begins_with(prefix):
		return false
	var raw: String = id.trim_prefix(prefix)
	return raw.is_valid_int() and str(int(raw)) == raw and int(raw) >= 1 and int(raw) < limit


static func _transfer(source: String, target: String, item: String, amount: int, reservation: String) -> Dictionary:
	return {"kind": "transfer", "source": source, "target": target, "item": item, "amount": amount, "reservation_id": reservation}
