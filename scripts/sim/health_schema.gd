extends RefCounted
## Independent candidate checks for sourced bodily consequences and care.
## Recovery history proves timing, rates and sums. Historical rest samples are
## saved observations; the other domains do not retain a replayable sleep log.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const MINUTE_MS: int = 60000
const JOB_KEYS: Array[String] = [
	"id", "patient", "doctor", "patient_region", "doctor_region", "source",
	"verb", "consent", "started_ms", "due_ms", "finished_ms", "status",
	"patient_autonomous", "doctor_autonomous", "patient_position",
	"doctor_position", "diagnosis",
]
const WOUND_KEYS: Array[String] = [
	"actor", "region", "type", "at_ms", "remaining", "treated_ms",
	"recovered_ms", "recovery",
]


static func inventory_scope(data: Variant, region: String, rules: Dictionary) -> Dictionary:
	var scope: Dictionary = {"containers": {}, "operations": {}, "reservations": {}}
	if not data is Dictionary or not data.get("jobs") is Dictionary or not SimInventory._nonempty(rules.get("material")):
		return scope
	for id: Variant in data.jobs:
		var job: Variant = data.jobs[id]
		if id is String and job is Dictionary and job.get("verb") == "treat" and job.get("patient_region") == region:
			scope.operations[id + ":material"] = true
	return scope


static func validate(data: Variant, domain: RefCounted) -> bool:
	# Health predates every conflict source. Raising this floor must not allow
	# a candidate to erase a genuine impact after already suffering it.
	if not Shape.keys(data, ["version", "source_floor", "conflict_source_floor", "next_id", "wounds", "jobs"]) or not Shape.count(data.version, 2, 2) or not Shape.count(data.source_floor, 1, domain.world.artifacts.next_id) or not Shape.count(data.conflict_source_floor, 1, 1) or not Shape.count(data.next_id, 1) or not data.wounds is Dictionary or not data.jobs is Dictionary or data.jobs.size() != int(data.next_id) - 1:
		return false
	var sources: Dictionary = {}
	for event: Dictionary in domain.world.artifacts.events:
		var number: int = _number(str(event.id), "artifact:event:")
		if number >= int(data.source_floor) and event.kind in ["backlash", "fractured"] and domain.eligible(str(event.actor)):
			sources[event.id] = event
	var conflict_sources: Dictionary = domain.conflict_sources()
	for id: Variant in conflict_sources:
		var source: Variant = conflict_sources[id]
		if not id is String or not valid_conflict_source(id, source, domain):
			return false
		if conflict_number(id) >= int(data.conflict_source_floor):
			sources[id] = source
	if sources.size() != data.wounds.size():
		return false
	for id: Variant in data.wounds:
		if not id is String or not sources.has(id) or not _wound(data.wounds[id], sources[id], domain):
			return false
	var material: Dictionary = {}
	var treated: Dictionary = {}
	var participants: Dictionary = {}
	var previous_start: int = -1
	for index: int in range(1, int(data.next_id)):
		var id: String = "health:action:%d" % index
		var job: Variant = data.jobs.get(id)
		if not _job(job, id, data, domain) or int(job.started_ms) < previous_start:
			return false
		previous_start = int(job.started_ms)
		# Both sides occupy the same original bodies, including when a doctor
		# becomes a patient in a later process. Adjacent intervals are legal.
		for actor: String in [job.patient, job.doctor]:
			if int(job.started_ms) < int(participants.get(actor, -1)):
				return false
			participants[actor] = int(job.due_ms) if job.status == "active" else int(job.finished_ms)
		if job.verb == "treat":
			var key: String = str(job.patient_region) + ":" + id + ":material"
			material[key] = {"kind": "consume", "container": "actor:" + str(job.patient), "item": domain.definitions.material, "amount": domain.definitions.material_amount}
			if job.status == "completed":
				if treated.has(job.source):
					return false
				treated[job.source] = int(job.finished_ms)
	for id: String in data.wounds:
		if int(data.wounds[id].treated_ms) != int(treated.get(id, -1)):
			return false
	return _inventory(material, domain)


static func _wound(wound: Variant, source: Dictionary, domain: RefCounted) -> bool:
	var contusion: bool = source.get("type") == "contusion"
	var keys: Array = WOUND_KEYS.duplicate()
	if contusion:
		keys.append("impact")
	if not Shape.keys(wound, keys):
		return false
	if contusion and (not Shape.count(wound.impact, 1, int(domain.definitions.contusion.max_impact)) or wound.impact != source.impact or wound.treated_ms != -1):
		return false
	var required: int = int(source.impact) * int(domain.definitions.contusion.recovery_per_impact) if contusion else int(domain.definitions.recovery.required)
	if wound.actor != source.actor or wound.region != source.region or wound.region != domain.home(str(source.actor)) or wound.type != ("contusion" if contusion else "meridian_irritation") or not Shape.count(wound.at_ms, 0, domain.world.elapsed_ms) or wound.at_ms != source.at_ms or not Shape.count(wound.remaining, 0, required) or not Shape.count(wound.treated_ms, -1, domain.world.elapsed_ms) or not Shape.count(wound.recovered_ms, -1, domain.world.elapsed_ms) or not wound.recovery is Array:
		return false
	if wound.treated_ms != -1 and int(wound.treated_ms) < int(wound.at_ms) or wound.recovered_ms != -1 and int(wound.recovered_ms) < int(wound.at_ms):
		return false
	var remaining: int = required
	var expected_ms: int = _first_pulse(int(wound.at_ms))
	var recovered_ms: int = -1
	for raw: Variant in wound.recovery:
		if not Shape.keys(raw, ["at_ms", "resting", "treated", "amount"]) or remaining == 0 or not Shape.count(raw.at_ms, expected_ms, expected_ms) or int(raw.at_ms) > domain.world.elapsed_ms or not raw.resting is bool or not raw.treated is bool or not Shape.count(raw.amount, 1):
			return false
		# A treatment completed at this boundary cannot improve the minute
		# which already elapsed before its completion.
		var treated: bool = int(wound.treated_ms) >= 0 and int(raw.at_ms) >= int(wound.treated_ms) + MINUTE_MS
		if raw.treated != treated:
			return false
		var amount: int = mini(remaining, int(domain.recovery_amount(wound, bool(raw.resting), treated)))
		if int(raw.amount) != amount:
			return false
		remaining -= amount
		if remaining == 0:
			recovered_ms = expected_ms
		expected_ms += MINUTE_MS
	# A candidate cannot omit a past pulse, insert a partial minute, or keep
	# gaining recovery after this particular condition has resolved.
	return int(wound.remaining) == remaining and int(wound.recovered_ms) == recovered_ms and (remaining == 0 or expected_ms > domain.world.elapsed_ms)


static func _job(job: Variant, id: String, data: Dictionary, domain: RefCounted) -> bool:
	if not Shape.keys(job, JOB_KEYS) or job.id != id:
		return false
	for field: String in ["id", "patient", "doctor", "patient_region", "doctor_region", "source", "verb", "consent", "status", "diagnosis"]:
		if not job[field] is String:
			return false
	if job.verb not in ["diagnose", "treat"] or job.status not in ["active", "completed", "cancelled", "failed"] or job.patient == job.doctor or not domain.eligible(str(job.patient)) or not domain.can_diagnose(str(job.doctor)) or job.patient_region != domain.home(str(job.patient)) or job.doctor_region != domain.home(str(job.doctor)) or not data.wounds.has(job.source) or data.wounds[job.source].actor != job.patient:
		return false
	var wound: Dictionary = data.wounds[job.source]
	if wound.type != "meridian_irritation":
		return false
	if not Shape.count(job.started_ms, int(wound.at_ms), domain.world.elapsed_ms) or not Shape.count(job.due_ms, int(job.started_ms) + 1) or int(job.due_ms) - int(job.started_ms) != domain.duration(str(job.verb)) or not job.patient_autonomous is bool or not job.doctor_autonomous is bool or not Shape.position_valid(job.patient_position) or not Shape.position_valid(job.doctor_position):
		return false
	var patient_at: Vector2 = Vector2(float(job.patient_position[0]), float(job.patient_position[1]))
	var doctor_at: Vector2 = Vector2(float(job.doctor_position[0]), float(job.doctor_position[1]))
	if not job.doctor_autonomous or patient_at.distance_to(doctor_at) > float(domain.definitions.interaction_cells) * TileGrid.TILE_SIZE:
		return false
	if int(wound.recovered_ms) >= 0 and int(wound.recovered_ms) <= int(job.started_ms):
		return false
	if not _consent(job, domain):
		return false
	if job.verb == "diagnose":
		if not job.diagnosis.is_empty():
			return false
	else:
		var diagnosis: Variant = data.jobs.get(job.diagnosis)
		if not Shape.keys(diagnosis, JOB_KEYS) or diagnosis.verb != "diagnose" or diagnosis.status != "completed" or diagnosis.patient != job.patient or diagnosis.doctor != job.doctor or diagnosis.source != job.source or not Shape.count(diagnosis.finished_ms, 0, int(job.started_ms)):
			return false
		if int(wound.treated_ms) >= 0 and int(wound.treated_ms) <= int(job.started_ms):
			return false
	if job.status == "active":
		if not Shape.count(job.finished_ms, -1, -1) or int(job.due_ms) <= domain.world.elapsed_ms or not domain._connected(job):
			return false
		for role: String in ["patient", "doctor"]:
			var actor: String = str(job[role])
			var body: Dictionary = domain.world.regions[job[role + "_region"]].synchronize_actors()[actor]
			if body.autonomous or not body.active.is_empty() or not Shape.same_record({"value": body.position}, {"value": job[role + "_position"]}) or not domain.world.actor_controls(actor, "action") or not domain.world.actor_controls(actor, "motion") or not _free_elsewhere(actor, domain):
				return false
	else:
		if not Shape.count(job.finished_ms, int(job.started_ms), mini(int(job.due_ms), domain.world.elapsed_ms)) or job.status == "completed" and job.finished_ms != job.due_ms:
			return false
	return true


static func _consent(job: Dictionary, domain: RefCounted) -> bool:
	var social: RefCounted = domain.social_for(str(job.patient), str(job.doctor))
	if social == null:
		return false
	for decision: Dictionary in social.requests.values():
		if decision.id != job.consent:
			continue
		return decision.requester == job.patient and decision.responder == job.doctor and decision.task == "health:" + str(job.verb) and decision.status == "accepted" and int(decision.tick) <= floori(float(job.started_ms) / MINUTE_MS) and Shape.same_record(decision.context.get("terms"), domain.terms(str(job.patient), str(job.doctor), str(job.verb), str(job.source)))
	return false


static func _free_elsewhere(actor: String, domain: RefCounted) -> bool:
	# Explicitly exclude this domain so validation also works when the caller
	# has already bound its empty candidate to the regional composition.
	for field: String in ["artifacts", "sparring", "soul_vessels", "admissions", "construction", "resting", "method_records", "personal_production", "clothing", "services", "conflicts"]:
		var other: RefCounted = domain.world.get(field)
		if other != null and other.owns_actor(actor):
			return false
	return true


static func _inventory(expected: Dictionary, domain: RefCounted) -> bool:
	var found: Dictionary = {}
	for region: String in domain.world.regions:
		var inventory: SimInventory = domain.world.regions[region].inventory
		for id: String in inventory.operations:
			if not id.begins_with("health:"):
				continue
			var key: String = region + ":" + id
			if not expected.has(key) or not Shape.same_record(inventory.operations[id], expected[key]):
				return false
			found[key] = true
		for id: String in inventory.reservations:
			if id.begins_with("health:"):
				return false
	return found.size() == expected.size()


static func _number(id: String, prefix: String) -> int:
	if not id.begins_with(prefix):
		return -1
	var suffix: String = id.trim_prefix(prefix)
	if not suffix.is_valid_int():
		return -1
	var value: int = suffix.to_int()
	return value if value >= 1 and id == prefix + str(value) else -1


static func conflict_number(id: String) -> int:
	return _number(id, "conflict:hit:")


static func conflict_next_id(domain: RefCounted) -> int:
	var conflicts: RefCounted = domain.world.get("conflicts")
	if conflicts == null:
		return 1
	var value: Variant = conflicts.get("next_hit_id")
	return int(value) if Shape.count(value, 1) else 0


static func valid_conflict_source(id: String, source: Variant, domain: RefCounted) -> bool:
	if not Shape.keys(source, ["id", "actor", "region", "type", "at_ms", "impact"]) or source.id != id or conflict_number(id) < 1 or conflict_number(id) >= conflict_next_id(domain):
		return false
	if not source.actor is String or not source.region is String or source.type != "contusion" or not domain.eligible(source.actor) or domain.home(source.actor) != source.region:
		return false
	return Shape.count(source.at_ms, 0, domain.world.elapsed_ms) and Shape.count(source.impact, 1, int(domain.definitions.contusion.max_impact))


static func _first_pulse(at_ms: int) -> int:
	@warning_ignore("integer_division")
	var minute: int = at_ms / MINUTE_MS
	return (minute + (1 if at_ms % MINUTE_MS == 0 else 2)) * MINUTE_MS
