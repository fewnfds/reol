extends RefCounted
## Cross-domain bed, occupancy, route and elapsed-time validation.
const Shape = preload("res://scripts/sim/avian_schema.gd")


static func valid(data: Variant, domain: RefCounted) -> bool:
	if not Shape.keys(data, ["version", "allocations", "active", "next_job", "next_check_ms"]) or data.version != 1 or not data.allocations is Dictionary or not data.active is Dictionary or not Shape.count(data.next_job, 1) or not Shape.count(data.next_check_ms, domain.world.elapsed_ms + 1):
		return false
	var beds: bool = false
	for id: String in domain.world.construction.projects:
		beds = beds or domain.world.construction.is_bed(id)
	if beds == (data.next_check_ms == SimInventory.MAX_COUNT) or beds and int(data.next_check_ms) > domain.world.elapsed_ms + int(domain.definitions.check_ms):
		return false
	for bed: Variant in data.allocations:
		if not bed is String or not domain.world.construction.is_bed(bed) or not data.allocations[bed] is String or not domain.member(data.allocations[bed]):
			return false
	var occupied: Dictionary = {}
	var ids: Dictionary = {}
	for actor: Variant in data.active:
		var job: Variant = data.active[actor]
		if not actor is String or not _job(actor, job, data, domain) or occupied.has(job.bed) or ids.has(job.id):
			return false
		occupied[job.bed] = true
		ids[job.id] = true
	return true


static func _job(actor: String, job: Variant, data: Dictionary, domain: RefCounted) -> bool:
	if not Shape.keys(job, ["id", "actor", "bed", "phase", "path", "segment_from", "segment_started_ms", "due_ms", "started_ms", "arrived_ms", "previous_autonomous"]) or job.actor != actor or not domain.member(actor) or not job.id is String or not _id(str(job.id), int(data.next_job)) or not job.bed is String or not domain.world.construction.is_bed(job.bed) or not job.phase in ["travel", "sleep", "leave"] or not job.path is Array or not job.previous_autonomous is bool or not SimLocalMotion._vector(job.segment_from):
		return false
	var world: RefCounted = domain.world
	var body: Dictionary = world.regions[domain.definitions.region].actors[actor]
	if not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or bool(body.autonomous) or not body.active.is_empty() or world.construction.owns_actor(actor) or world.admissions.owns_actor(actor) or world.soul_vessels.owns_actor(actor) or world.sparring.owns_actor(actor) or world.artifacts.owns_actor(actor) or world.services != null and world.services.owns_actor(actor):
		return false
	if data.allocations.has(job.bed) and data.allocations[job.bed] != actor or world.construction._project_busy(job.bed):
		return false
	var bed: Dictionary = world.construction.projects[job.bed]
	for field: String in ["started_ms", "arrived_ms", "segment_started_ms"]:
		if not Shape.count(job[field], 0, world.elapsed_ms):
			return false
	if int(job.started_ms) < int(bed.completed_ms) or int(job.segment_started_ms) < int(job.started_ms) or not Shape.count(job.due_ms, world.elapsed_ms + 1):
		return false
	var target: Vector2i = SimRouteTravel.cell(bed.cell)
	if job.phase != "sleep":
		if job.phase == "travel" and job.arrived_ms != 0 or job.phase == "leave" and (int(job.arrived_ms) < int(job.started_ms) or int(job.segment_started_ms) < int(job.arrived_ms)):
			return false
		var current: Vector2i = SimRouteTravel.cell(body.cell)
		for raw: Variant in job.path:
			if not Shape.cell_valid(raw):
				return false
			var next: Vector2i = SimRouteTravel.cell(raw)
			if absi(next.x - current.x) > 1 or absi(next.y - current.y) > 1 or not world.construction.terrain_open(next):
				return false
			current = next
		if job.phase == "leave":
			if job.path.size() != 1 or current.distance_to(target) != 1.0 or not Vector2(float(job.segment_from[0]), float(job.segment_from[1])).is_equal_approx(TileGrid.cell_to_world(target)):
				return false
		elif current != target:
			return false
		if not SimRouteTravel.valid_segment(job, body, world.elapsed_ms, domain._speed()):
			return false
		var end: Vector2 = Vector2(float(job.segment_from[0]), float(job.segment_from[1])) if job.path.is_empty() else TileGrid.cell_to_world(SimRouteTravel.cell(job.path[0]))
		var duration: int = maxi(1, ceili(Vector2(float(job.segment_from[0]), float(job.segment_from[1])).distance_to(end) / domain._speed() * 1000.0))
		return int(job.due_ms) == int(job.segment_started_ms) + duration
	return job.path.is_empty() and int(job.arrived_ms) >= int(job.started_ms) and job.segment_started_ms == job.arrived_ms and int(job.due_ms) == int(job.arrived_ms) + int(domain.definitions.rest_ms) and SimRouteTravel.point(body).is_equal_approx(TileGrid.cell_to_world(target)) and Vector2(float(job.segment_from[0]), float(job.segment_from[1])).is_equal_approx(TileGrid.cell_to_world(target))


static func _id(value: String, limit: int) -> bool:
	var raw: String = value.trim_prefix("bed_use:")
	return value.begins_with("bed_use:") and raw.is_valid_int() and str(int(raw)) == raw and int(raw) >= 1 and int(raw) < limit
