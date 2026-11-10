extends RefCounted
## Physical transitions are replayed independently before replacing live garments.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const JOB_KEYS: Array[String] = ["id", "actor", "region", "verb", "object", "target", "from_region", "from_container", "from_worn", "started_ms", "due_ms", "previous_autonomous", "at", "position"]


static func validate(data: Variant, domain: RefCounted) -> bool:
	if not Shape.keys(data, ["version", "seeded", "objects", "active", "events", "next_id"]) or data.version != 1 or not data.seeded is bool or not data.objects is Dictionary or not data.active is Dictionary or not data.events is Array or not Shape.count(data.next_id, 1):
		return false
	var physical: Dictionary = domain.opening_objects() if data.seeded else {}
	if not data.seeded and (not data.objects.is_empty() or not data.active.is_empty() or not data.events.is_empty() or data.next_id != 1):
		return false
	var markers: Array[Dictionary] = []
	var jobs: Dictionary = {}
	var event_keys: Array[String] = JOB_KEYS.duplicate()
	event_keys.append_array(["outcome", "finished_ms"])
	var last: int = -1
	for event: Variant in data.events:
		if not Shape.keys(event, event_keys) or not _common(event, domain) or event.outcome not in ["completed", "failed", "cancelled"] or not Shape.count(event.finished_ms, int(event.started_ms), mini(int(event.due_ms), domain.world.elapsed_ms)) or int(event.finished_ms) < last:
			return false
		if event.outcome == "completed" and event.finished_ms != event.due_ms:
			return false
		last = int(event.finished_ms)
		if not _add(event, jobs, markers, int(data.next_id)):
			return false
		markers.append({"time": int(event.finished_ms), "phase": 0, "number": _number(str(event.id)), "job": event})
	for actor: Variant in data.active:
		var job: Variant = data.active[actor]
		if not Shape.keys(job, JOB_KEYS) or actor != job.actor or not _common(job, domain) or int(job.due_ms) <= domain.world.elapsed_ms or not _add(job, jobs, markers, int(data.next_id)):
			return false
		var body: Dictionary = domain.world.regions[job.region].synchronize_actors()[actor]
		if body.autonomous or not body.active.is_empty() or body.cell != job.at or not Shape.same_record({"value": body.position}, {"value": job.position}) or not domain.world.actor_controls(actor, "action") or not domain.world.actor_controls(actor, "motion") or domain.world.local_action_owns(actor) or domain.world.artifacts.owns_actor(actor) or domain.world.services != null and domain.world.services.owns_actor(actor):
			return false
	if jobs.size() != int(data.next_id) - 1:
		return false
	markers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.time != b.time:
			return a.time < b.time
		if a.number != b.number:
			return a.number < b.number
		return a.phase > b.phase)
	var actors: Dictionary = {}
	var objects: Dictionary = {}
	for marker: Dictionary in markers:
		var job: Dictionary = marker.job
		if marker.phase == 1:
			if actors.has(job.actor) or objects.has(job.object) or not _start(job, physical, domain):
				return false
			actors[job.actor] = job.id
			objects[job.object] = job.id
		else:
			if actors.get(job.actor) != job.id or objects.get(job.object) != job.id:
				return false
			actors.erase(job.actor)
			objects.erase(job.object)
			if job.outcome == "completed":
				domain.transition(physical[job.object], job)
	if physical.size() != data.objects.size():
		return false
	var max_rain: int = 0
	for region: String in domain.world.regions:
		max_rain += SimWeather.rain_budget(domain.world.weather.to_dict(), domain.world.weather.definitions, region, domain.world.elapsed_ms)
	for id: String in physical:
		var actual: Variant = data.objects.get(id)
		if not Shape.keys(actual, physical[id].keys()) or not Shape.count(actual.wet, 0, 100):
			return false
		@warning_ignore("integer_division")
		var limit: int = max_rain / int(domain.world.weather.definitions.rain_source_per_pulse) * int(domain.definitions.types[physical[id].type].absorb_per_pulse)
		if int(actual.wet) > limit:
			return false
		physical[id].wet = int(actual.wet)
		if not Shape.same_record(actual, physical[id]):
			return false
	return true


static func _number(id: String) -> int:
	return id.trim_prefix("clothing:action:").to_int()


static func _add(job: Dictionary, jobs: Dictionary, markers: Array[Dictionary], limit: int) -> bool:
	var number: int = _number(str(job.id))
	if number < 1 or number >= limit or job.id != "clothing:action:%d" % number or jobs.has(job.id):
		return false
	jobs[job.id] = true
	markers.append({"time": int(job.started_ms), "phase": 1, "number": number, "job": job})
	return true


static func _common(job: Dictionary, domain: RefCounted) -> bool:
	for field: String in ["id", "actor", "region", "verb", "object", "target", "from_region", "from_container"]:
		if not job[field] is String:
			return false
	if domain.home(job.actor).is_empty() or job.region != domain.home(job.actor) or job.verb not in domain.VERBS or not job.from_worn is bool or not job.previous_autonomous is bool or not Shape.count(job.started_ms, 0, domain.world.elapsed_ms) or not Shape.count(job.due_ms, 1) or int(job.due_ms) - int(job.started_ms) != domain.duration(str(job.verb)) or not Shape.cell_valid(job.at) or not Shape.position_valid(job.position):
		return false
	if TileGrid.world_to_cell(Vector2(float(job.position[0]), float(job.position[1]))) != SimRouteTravel.cell(job.at):
		return false
	return domain.valid_location(job.from_region, job.from_container)


static func _start(job: Dictionary, physical: Dictionary, domain: RefCounted) -> bool:
	if not physical.has(job.object):
		return false
	var item: Dictionary = physical[job.object]
	if item.owner != job.actor or item.region != job.from_region or item.container != job.from_container or item.worn != job.from_worn:
		return false
	var held: bool = item.region == job.region and item.container == "actor:" + str(job.actor)
	var at: Vector2i = SimRouteTravel.cell(job.at)
	if job.verb == "take":
		return job.target.is_empty() and item.region == job.region and not held and not item.worn and not str(item.container).begins_with("actor:") and at.distance_to(domain.cell(str(item.region), str(item.container))) <= float(domain.definitions.interaction_cells)
	if not held:
		return false
	if job.verb == "place":
		return not item.worn and domain.world.regions[job.region].places.has(job.target) and at.distance_to(domain.cell(str(job.region), str(job.target))) <= float(domain.definitions.interaction_cells)
	if not job.target.is_empty():
		return false
	if job.verb == "remove":
		return bool(item.worn)
	if item.worn:
		return false
	for other: Dictionary in physical.values():
		if other.region == job.region and other.container == item.container and other.worn and domain.definitions.types[other.type].slot == domain.definitions.types[item.type].slot:
			return false
	return true
