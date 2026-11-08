extends RefCounted
## Validates original ledger receipts, slots, route segments and body exclusivity.
const Shape = preload("res://scripts/sim/avian_schema.gd")


static func valid(domain: SimFacilityUse) -> bool:
	var world: RegionalSimulation = domain.world
	var inventory: SimInventory = world.regions[world.construction.definitions.site.region].inventory
	var jobs: Dictionary = {}
	# Validate every active row before any cross-slot query can inspect a peer.
	for actor: Variant in domain.active:
		var job: Variant = domain.active[actor]
		if not actor is String or not job is Dictionary or not job.get("project") is String or not world.construction.projects.has(job.project) or not job.get("id") is String or not job.get("kind") in ["sit", "deposit", "withdraw"] or not job.get("item") is String or not Shape.count(job.get("amount"), 0) or not Shape.cell_valid(job.get("stand")):
			return false
	for id: Variant in domain.transfers:
		var row: Variant = domain.transfers[id]
		if not _id(id, domain.next_job) or not Shape.keys(row, ["actor", "project", "kind", "item", "amount", "at_ms"]) or not world.construction.authorized(str(row.actor)) or not row.project is String or not world.construction.projects.has(row.project) or row.kind not in ["deposit", "withdraw"] or not SimInventory._nonempty(row.item) or not Shape.count(row.amount, 1) or not Shape.count(row.at_ms, int(world.construction.projects[row.project].completed_ms), world.elapsed_ms):
			return false
		var project: Dictionary = world.construction.projects[row.project]
		if project.state not in ["built", "ruined", "removed"] or not world.construction.definitions.types[project.type].capabilities.has("storage"):
			return false
		var source: String = "actor:" + str(row.actor) if row.kind == "deposit" else str(row.project) + ":contents"
		var target: String = str(row.project) + ":contents" if row.kind == "deposit" else "actor:" + str(row.actor)
		if not Shape.same_record(inventory.operations.get(str(id) + ":transfer"), {"kind": "transfer", "source": source, "target": target, "item": str(row.item), "amount": int(row.amount), "reservation_id": str(id)}):
			return false
		jobs[id] = true
	for actor: Variant in domain.active:
		var job: Variant = domain.active[actor]
		if not actor is String or not Shape.keys(job, ["id", "actor", "project", "slot", "kind", "item", "amount", "duration_ms", "phase", "path", "stand", "support", "segment_from", "segment_started_ms", "due_ms", "started_ms", "work_started_ms", "previous_autonomous", "reserved"]) or job.actor != actor or not _id(job.id, domain.next_job) or jobs.has(job.id) or not world.construction.authorized(actor) or not job.project is String or not world.construction.projects.has(job.project) or not job.slot is String or not job.support is String or job.kind not in ["sit", "deposit", "withdraw"] or job.phase not in ["travel", "use"] or not job.path is Array or job.path.size() > 1024 or not job.item is String or not job.previous_autonomous is bool or not job.reserved is bool or not Shape.cell_valid(job.stand) or not Shape.count(job.duration_ms, 1, 86400000):
			return false
		var row: Dictionary = domain.slot(job.project, job.slot)
		if row.is_empty() or row.cell != SimRouteTravel.cell(job.stand) or not domain._can_continue(job):
			return false
		jobs[job.id] = true
		var body: Dictionary = world.regions[world.construction.definitions.site.region].actors[actor]
		if bool(body.autonomous) or not body.active.is_empty():
			return false
		for field: String in ["started_ms", "work_started_ms", "segment_started_ms"]:
			if not Shape.count(job[field], int(world.construction.projects[job.project].completed_ms), world.elapsed_ms):
				return false
		if int(job.work_started_ms) < int(job.started_ms) or int(job.segment_started_ms) < int(job.started_ms) or not Shape.count(job.due_ms, world.elapsed_ms + 1):
			return false
		if job.kind == "sit":
			if job.reserved or job.amount != 0 or job.item != "":
				return false
		elif not job.reserved or not Shape.count(job.amount, 1) or not SimInventory._nonempty(job.item) or not domain._storage_ready(job) or not Shape.same_record(inventory.reservations.get(job.id), {"container": domain._source(job), "item": str(job.item), "amount": int(job.amount), "owner_id": actor}):
			return false
		if job.phase == "travel":
			var current: Vector2i = SimRouteTravel.cell(body.cell)
			for raw: Variant in job.path:
				if not Shape.cell_valid(raw):
					return false
				var next: Vector2i = SimRouteTravel.cell(raw)
				if absi(next.x - current.x) > 1 or absi(next.y - current.y) > 1 or not world.construction.terrain_open(next):
					return false
				current = next
			if current != row.cell or not SimRouteTravel.valid_segment(job, body, world.elapsed_ms, float(world.regions[world.construction.definitions.site.region].motion_rules.motion.speed)):
				return false
		else:
			var duration: int = int(job.duration_ms) if job.kind == "sit" else int(world.construction.definitions.operate_ms)
			if not job.path.is_empty() or not SimRouteTravel.point(body).is_equal_approx(TileGrid.cell_to_world(row.cell)) or int(job.due_ms) != int(job.work_started_ms) + duration:
				return false
	# Scope grants must not hide orphan operations or reservations.
	for id: String in inventory.operations:
		var operation: Dictionary = inventory.operations[id]
		var touches: bool = id.begins_with("facility_use:")
		for field: String in ["container", "source", "target"]:
			var value: String = str(operation.get(field, ""))
			touches = touches or value.begins_with("construction:") and value.ends_with(":contents")
		if touches and (not id.ends_with(":transfer") or not domain.transfers.has(id.trim_suffix(":transfer"))):
			return false
	for id: String in inventory.reservations:
		if id.begins_with("facility_use:") and not domain.active.values().any(func(job: Dictionary) -> bool: return job.id == id and job.reserved):
			return false
	var claims: Dictionary = {}
	for process: RefCounted in [domain, world.construction, world.resting, world.personal_production]:
		for actor: String in process.active:
			var job: Dictionary = process.active[actor]
			var cell: Vector2i
			if process == world.resting:
				cell = SimRouteTravel.cell(world.construction.projects[job.bed].cell)
			elif process == world.personal_production:
				var batch: Dictionary = world.personal_production.batches[job.batch]
				if str(batch.facility).is_empty(): continue
				if not world.personal_production._facility_accessible(batch, actor, str(job.kind)): return false
				cell = world.personal_production.work_cell(batch)
			else:
				cell = SimRouteTravel.cell(job.stand)
			if claims.has(cell): return false
			claims[cell] = actor
	return true


static func _id(value: Variant, limit: int) -> bool:
	if not value is String:
		return false
	var raw: String = value.trim_prefix("facility_use:")
	return value.begins_with("facility_use:") and raw.is_valid_int() and str(int(raw)) == raw and int(raw) >= 1 and int(raw) < limit
