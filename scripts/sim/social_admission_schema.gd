extends RefCounted
## Cross-check statements against actual human memories and real collection jobs.

const Shape = preload("res://scripts/sim/avian_schema.gd")


static func validate(data: Variant, domain: RefCounted) -> bool:
	if not Shape.keys(data, ["version", "active", "entries", "grants", "next_id", "rng_state"]) or data.version != 1 or not data.active is Dictionary or not data.entries is Array or not data.grants is Dictionary or not Shape.count(data.next_id, 1) or not data.rng_state is String or not data.rng_state.is_valid_int() or str(int(data.rng_state)) != data.rng_state:
		return false
	var world: RefCounted = domain.world
	var ids: Dictionary = {}
	var rows: Dictionary = {}
	var requests: Dictionary = {}
	var previous: int = 0
	for row: Variant in data.entries:
		if not Shape.keys(row, ["id", "actor", "receiver", "region", "method", "status", "line", "at_ms", "evidence", "request", "social_event"]) or not _id(row.id, int(data.next_id), ids) or not _people(row, domain) or not row.line is String or not row.evidence is String or not row.request is String or not row.social_event is String or not Shape.count(row.at_ms, previous, int(world.elapsed_ms)):
			return false
		previous = int(row.at_ms)
		var sim: RefCounted = world.regions[row.region]
		var event: Dictionary = sim.social.objective_event(row.social_event)
		var details: Dictionary = {"participants": {"text": row.line, "status": row.status, "action": row.method, "terms": {"scope": domain.definitions.scope, "evidence": row.evidence}}}
		if event.get("kind") != "admission_statement" or event.get("actor") != row.actor or event.get("target") != row.receiver or int(event.get("tick", -1)) != floori(float(row.at_ms) / 60000.0) or event.get("details") != details or event.get("witnesses") != []:
			return false
		var statuses: Array = {"claim": ["requires_check", "believed", "doubted"], "show_pass": ["pass_seen", "unconfirmed"], "verify": ["not_registrar", "confirmed", "unconfirmed"], "receipt": ["receipt_seen"]}[row.method]
		if not statuses.has(row.status) and not row.status in ["interrupted", "unheard"]:
			return false
		if row.method == "claim" and row.status in ["believed", "doubted"]:
			var request: Dictionary = {}
			for candidate: Dictionary in sim.social.requests.values():
				if candidate.id == row.request:
					request = candidate
			var key: String = str(row.region) + ":" + str(row.request)
			if requests.has(key) or request.is_empty() or request.requester != row.actor or request.responder != row.receiver or request.task != "oral_admission" or (request.status == "accepted") != (row.status == "believed") or request.context.get("terms") != {"region": row.region, "scope": domain.definitions.scope, "statement": "registered_access"} or request.policy != sim.social._normalized_policy(domain.definitions.policy) or request.tick != floori(float(row.at_ms) / 60000.0):
				return false
			requests[key] = true
		elif not row.request.is_empty():
			return false
		if row.status in ["confirmed", "pass_seen"]:
			if not _real_pass(row.evidence, row.actor, row.region, world):
				return false
		elif row.status == "receipt_seen":
			var audit: Dictionary = rows.get(row.evidence, {})
			if audit.get("actor") != row.actor or audit.get("method") != "verify" or not audit.get("status") in ["confirmed", "unconfirmed"]:
				return false
		elif not row.evidence.is_empty():
			return false
		rows[row.id] = row
	for actor: Variant in data.active:
		var job: Variant = data.active[actor]
		if not Shape.keys(job, ["id", "actor", "receiver", "region", "method", "evidence", "started_ms", "due_ms", "previous_autonomous"]) or not _id(job.id, int(data.next_id), ids) or job.actor != actor or not _people(job, domain) or not job.evidence is String or not job.previous_autonomous is bool or not Shape.count(job.started_ms, 0, int(world.elapsed_ms)) or not Shape.count(job.due_ms, int(world.elapsed_ms) + 1) or job.due_ms - job.started_ms != domain.definitions.actions[job.method]:
			return false
		var body: Dictionary = world.regions[job.region].synchronize_actors()[actor]
		if body.autonomous or not body.active.is_empty() or not world.actor_controls(actor, "communication") or not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or world.artifacts.owns_actor(actor) or world.soul_vessels.owns_actor(actor) or world.sparring.owns_actor(actor) or world.services != null and world.services.owns_actor(actor):
			return false
		if job.method == "show_pass":
			if not _real_pass(job.evidence, actor, job.region, world):
				return false
		elif job.method == "receipt":
			var audit: Dictionary = rows.get(job.evidence, {})
			if audit.get("actor") != actor or audit.get("method") != "verify" or not audit.get("status") in ["confirmed", "unconfirmed"]:
				return false
		elif not job.evidence.is_empty():
			return false
	for id: Variant in data.grants:
		var grant: Variant = data.grants[id]
		var row: Dictionary = rows.get(id, {})
		if not Shape.keys(grant, ["id", "actor", "receiver", "region", "issued_ms", "expires_ms", "used_by", "revoked_by"]) or grant.id != id or row.get("status") != "believed" or row.get("method") != "claim" or grant.actor != row.actor or grant.receiver != row.receiver or grant.region != row.region or not Shape.count(grant.issued_ms) or grant.issued_ms != row.at_ms or not Shape.count(grant.expires_ms) or grant.expires_ms - grant.issued_ms != domain.definitions.grant_ms or not grant.used_by is String or not grant.revoked_by is String:
			return false
		if not grant.revoked_by.is_empty():
			var revoke: Dictionary = rows.get(grant.revoked_by, {})
			if revoke.get("actor") != grant.actor or revoke.get("receiver") != grant.receiver or revoke.get("status") != "receipt_seen" or rows.get(revoke.get("evidence"), {}).get("status") != "unconfirmed" or int(revoke.at_ms) < int(grant.issued_ms):
				return false
		if not grant.used_by.is_empty() and not _collection(grant.used_by, grant, world, true):
			return false
	for row: Dictionary in rows.values():
		if (row.status == "believed") != data.grants.has(row.id):
			return false
	if world.services != null:
		var used: Dictionary = {}
		for job: Dictionary in world.services.jobs.values():
			if not job.options.has("admission"):
				continue
			var id: Variant = job.options.admission
			if not id is String or not data.grants.has(id) or not _collection(job.id, data.grants[id], world, job.status == "completed"):
				return false
			if job.status == "completed" or job.status == "active":
				if used.has(id):
					return false
				used[id] = true
	return true


static func _real_pass(id: String, actor: String, region: String, world: RefCounted) -> bool:
	if world.services == null or not world.services.jobs.has(id):
		return false
	var job: Dictionary = world.services.jobs[id]
	return job.kind == "access" and job.status == "completed" and job.actor == actor and job.region == region and job.options.get("scope") == "gate"


static func _collection(id: String, grant: Dictionary, world: RefCounted, complete: bool) -> bool:
	if world.services == null or not world.services.jobs.has(id):
		return false
	var job: Dictionary = world.services.jobs[id]
	if job.kind != "collect_herb" or job.actor != grant.actor or job.region != grant.region or job.options.get("admission") != grant.id or int(job.started_ms) < int(grant.issued_ms) or int(job.started_ms) >= int(grant.expires_ms):
		return false
	if complete:
		return job.status == "completed" and grant.used_by == id and world.services.operations.has(id + ":collection")
	return job.status in ["active", "failed", "cancelled"] and grant.used_by != id


static func _people(row: Dictionary, domain: RefCounted) -> bool:
	return row.actor is String and row.receiver is String and row.region is String and domain.world.regions.has(row.region) and domain.actor_home(row.actor) == row.region and domain.actor_home(row.receiver) == row.region and row.actor != row.receiver and domain.definitions.actions.has(row.method)


static func _id(value: Variant, next_id: int, seen: Dictionary) -> bool:
	if not value is String or seen.has(value) or not value.begins_with("admission:") or value.get_slice_count(":") != 2:
		return false
	var suffix: String = value.get_slice(":", 1)
	if not suffix.is_valid_int() or suffix != str(int(suffix)) or not Shape.count(int(suffix), 1, next_id - 1):
		return false
	seen[value] = true
	return true
