extends RefCounted
## Validate exact physical transitions, paid input and private reading sources.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const JOB_KEYS: Array[String] = ["id", "actor", "region", "verb", "object", "method", "source", "target", "consent", "started_ms", "due_ms", "previous_autonomous", "from_region", "from_container"]


static func validate(data: Dictionary, domain: RefCounted, practice: Array) -> bool:
	if not Shape.keys(data, ["version", "objects", "active", "events", "next_id"]) or data.version != 1 or not data.objects is Dictionary or not data.active is Dictionary or not data.events is Array or not Shape.count(data.next_id, 1):
		return false
	var jobs: Dictionary = {}
	var markers: Array[Dictionary] = []
	var paid: Dictionary = {}
	var event_fields: Array[String] = JOB_KEYS.duplicate()
	event_fields.append_array(["outcome", "finished_ms"])
	var last_time: int = -1
	for event: Variant in data.events:
		if not Shape.keys(event, event_fields) or not _common(event, domain) or not event.outcome in ["completed", "failed", "cancelled"] or not Shape.count(event.finished_ms, int(event.started_ms), domain.world.elapsed_ms) or int(event.finished_ms) < last_time or int(event.finished_ms) > int(event.due_ms):
			return false
		if event.outcome == "completed" and event.finished_ms != event.due_ms:
			return false
		last_time = int(event.finished_ms)
		if not _add(event, jobs, markers, int(data.next_id)):
			return false
		markers.append({"time": int(event.finished_ms), "phase": 0, "number": _number(str(event.id)), "job": event})
	for actor: Variant in data.active:
		var job: Variant = data.active[actor]
		if not Shape.keys(job, JOB_KEYS) or job.actor != actor or not _common(job, domain) or int(job.due_ms) <= domain.world.elapsed_ms or not _add(job, jobs, markers, int(data.next_id)):
			return false
		var body: Dictionary = domain.world.regions[job.region].actors[actor]
		if body.autonomous or not body.active.is_empty() or not domain.world.actor_controls(actor, "action") or not domain.world.actor_controls(actor, "motion"):
			return false
	if jobs.size() != int(data.next_id) - 1:
		return false
	markers.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if left.time != right.time:
			return left.time < right.time
		if left.number != right.number:
			return left.number < right.number
		return left.phase > right.phase)
	var physical: Dictionary = {}
	var read: Dictionary = {}
	var occupied_objects: Dictionary = {}
	var occupied_actors: Dictionary = {}
	for marker: Dictionary in markers:
		var job: Dictionary = marker.job
		if marker.phase == 1:
			if occupied_actors.has(job.actor) or occupied_objects.has(job.object):
				return false
			occupied_actors[job.actor] = job.id
			occupied_objects[job.object] = job.id
			if not _start(job, physical, read, domain, practice, paid):
				return false
		else:
			if occupied_actors.get(job.actor) != job.id or occupied_objects.get(job.object) != job.id:
				return false
			occupied_actors.erase(job.actor)
			occupied_objects.erase(job.object)
			if job.outcome != "completed":
				continue
			match str(job.verb):
				"write":
					physical[job.object] = {"method": job.method, "scribe": job.actor, "source": job.source, "created_ms": job.finished_ms, "region": job.region, "container": "actor:" + str(job.actor)}
				"read":
					if not read.has(job.actor):
						read[job.actor] = {}
					read[job.actor][job.method] = job.object
				"take", "place", "give":
					var place: Dictionary = domain.destination(str(job.target)) if job.verb == "place" else {}
					physical[job.object].region = place.region if job.verb == "place" else domain.home(str(job.target)) if job.verb == "give" else job.region
					physical[job.object].container = place.container if job.verb == "place" else "actor:" + str(job.target) if job.verb == "give" else "actor:" + str(job.actor)
	if not Shape.same_record(physical, data.objects):
		return false
	# Native inventory operations cannot outlive a deleted writing process.
	for region: String in domain.world.regions:
		var inventory: SimInventory = domain.world.regions[region].inventory
		for id: String in inventory.operations:
			if id.begins_with("method_record:"):
				if not paid.has(id) or paid[id].region != region or not Shape.same_record(inventory.operations[id], paid[id].operation):
					return false
	for id: String in paid:
		if not Shape.same_record(domain.world.regions[paid[id].region].inventory.operations.get(id), paid[id].operation):
			return false
	return true


static func _number(id: String) -> int:
	return id.trim_prefix("method_record:action:").to_int()


static func _add(job: Dictionary, jobs: Dictionary, markers: Array[Dictionary], limit: int) -> bool:
	var number: int = _number(str(job.id))
	if jobs.has(job.id) or number < 1 or number >= limit or job.id != "method_record:action:%d" % number:
		return false
	jobs[job.id] = job
	markers.append({"time": int(job.started_ms), "phase": 1, "number": number, "job": job})
	return true


static func _common(job: Dictionary, domain: RefCounted) -> bool:
	for field: String in ["id", "actor", "region", "verb", "object", "method", "source", "target", "consent", "from_region", "from_container"]:
		if not job[field] is String:
			return false
	if domain.home(job.actor).is_empty() or domain.home(job.actor) != job.region or not job.verb in domain.VERBS or not job.previous_autonomous is bool or not Shape.count(job.started_ms, 0, domain.world.elapsed_ms) or not Shape.count(job.due_ms, 1) or int(job.due_ms) - int(job.started_ms) != domain.duration(str(job.verb)):
		return false
	if not domain.world.heat_methods.methods.has(job.method) or domain.world.heat_methods.methods[job.method].created_ms > job.started_ms or not domain.valid_location(job.from_region, job.from_container):
		return false
	if job.verb == "place":
		if domain.destination(str(job.target)).is_empty():
			return false
	elif job.verb == "give":
		if job.target == job.actor or domain.home(job.target).is_empty() or not _consent(job, domain):
			return false
	elif not job.target.is_empty():
		return false
	if job.verb != "give" and not job.consent.is_empty() or job.verb != "write" and not job.source.is_empty():
		return false
	return true


static func _consent(job: Dictionary, domain: RefCounted) -> bool:
	var memory: SimSocialMemory = domain.social_for(str(job.actor), str(job.target))
	if memory == null:
		return false
	for decision: Dictionary in memory.requests.values():
		if decision.id == job.consent:
			return decision.requester == job.actor and decision.responder == job.target and decision.task == "receive_method_record" and decision.status == "accepted" and int(decision.tick) * 60000 <= int(job.started_ms) and Shape.same_record(decision.context.get("terms"), {"record": job.object}) and Shape.same_record(decision.policy, memory._normalized_policy(domain.definitions.policy))
	return false


static func _start(job: Dictionary, physical: Dictionary, read: Dictionary, domain: RefCounted, practice: Array, paid: Dictionary) -> bool:
	if job.verb == "write":
		if physical.has(job.object) or job.object != "method_record:%d" % _number(str(job.id)) or job.from_region != job.region or job.from_container != "actor:" + str(job.actor):
			return false
		var author: bool = domain.world.heat_methods.methods[job.method].creator == domain.world.embodiment.subject_for_actor(str(job.actor))
		var practiced: bool = domain.world.heat_methods.known_from(str(job.actor), str(job.method), practice, int(job.started_ms))
		var source: String = str(read.get(job.actor, {}).get(job.method, ""))
		if job.source != source or not author and not practiced and source.is_empty():
			return false
		paid[str(job.id) + ":material"] = {"region": job.region, "operation": {"kind": "consume", "container": "actor:" + str(job.actor), "item": domain.definitions.material, "amount": int(domain.definitions.cost)}}
		return true
	if not physical.has(job.object):
		return false
	var object: Dictionary = physical[job.object]
	if object.method != job.method or object.region != job.from_region or object.container != job.from_container or str(object.container).begins_with("actor:") and object.container != "actor:" + str(job.actor):
		return false
	var held: bool = object.container == "actor:" + str(job.actor) and object.region == job.region
	if job.verb == "take" and held or job.verb in ["place", "give"] and not held:
		return false
	return job.verb != "read" or not read.get(job.actor, {}).has(job.method)


static func cross_valid(domain: RefCounted) -> bool:
	var world: RefCounted = domain.world
	for actor: String in domain.active:
		if world.artifacts.owns_actor(actor) or world.soul_vessels.owns_actor(actor) or world.sparring.owns_actor(actor) or world.admissions.owns_actor(actor) or world.construction.owns_actor(actor) or world.resting.owns_actor(actor) or world.services != null and world.services.owns_actor(actor):
			return false
	var practices: Array = world.artifacts.events.duplicate()
	practices.append_array(world.artifacts.active.values())
	for job: Dictionary in practices:
		if job.get("method", {}).get("mode") == "record" and not world.heat_methods.base_known_from(str(job.actor), str(job.object), int(job.started_ms)):
			return false
	return true
