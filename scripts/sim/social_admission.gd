class_name SimSocialAdmission
extends RefCounted
## A statement can persuade a person without changing an institution's record.
## Bodies, goods, formal accounts and human relationship memories stay original.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const Schema = preload("res://scripts/sim/social_admission_schema.gd")
var definitions: Dictionary = {}
var active: Dictionary = {}
var entries: Array[Dictionary] = []
var grants: Dictionary = {}
var next_id: int = 1
var _owner: WeakRef
var _rng := RandomNumberGenerator.new()
var world: RefCounted:
	get:
		return _owner.get_ref()


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "seed", "talk_cells", "scope", "action", "grant_ms", "actions", "risk", "policy"]) or data.version != 1 or not Shape.count(data.seed) or not Shape.count(data.talk_cells, 1, 32) or data.scope != "gate" or data.action != "collect_herb" or not Shape.count(data.grant_ms, 1) or not (data.risk is int or data.risk is float) or not is_finite(float(data.risk)) or data.risk < 0 or data.risk > 1 or not Shape.keys(data.actions, ["claim", "show_pass", "verify", "receipt"]):
		return false
	for duration: Variant in data.actions.values():
		if not Shape.count(duration, 1, int(data.grant_ms)):
			return false
	return data.policy is Dictionary and not SimSocialMemory.new()._normalized_policy(data.policy).is_empty()


func bind_world(authority: RefCounted) -> void:
	# Rebind a validated candidate without resetting its saved process.
	_owner = weakref(authority)


func initialize(parent: RefCounted, rules: Dictionary) -> bool:
	if not valid_definitions(rules):
		return false
	_owner = weakref(parent)
	definitions = rules.duplicate(true)
	_rng.seed = int(definitions.seed)
	return true


func actor_home(actor: String) -> String:
	for region: String in world.regions:
		if world.regions[region].actors.has(actor):
			return region
	return ""


func owns_actor(actor: String) -> bool:
	return active.has(actor)


func nearby(actor: String, receiver: String) -> bool:
	var region: String = actor_home(actor)
	return not region.is_empty() and actor != receiver and actor_home(receiver) == region and SimRouteTravel.point(world.regions[region].actors[actor]).distance_to(SimRouteTravel.point(world.regions[region].actors[receiver])) <= float(definitions.talk_cells) * TileGrid.TILE_SIZE


func start(actor: String, receiver: String, method: String) -> Dictionary:
	var region: String = actor_home(actor)
	if not definitions.actions.has(method) or world.services == null or region.is_empty() or world.elapsed_ms != world.target_ms:
		return _reply(false, "眼下没有这种交谈办法。")
	world.synchronize_region(region)
	if not nearby(actor, receiver) or not world.actor_controls(actor, "communication") or not world.actor_controls(receiver, "communication") or not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion"):
		return _reply(false, "先走到能当面说话的距离。")
	var sim: RefCounted = world.regions[region]
	var body: Dictionary = sim.actors[actor]
	if not body.active.is_empty() or world.local_action_owns(actor) or world.artifacts.owns_actor(actor) or world.services.owns_actor(actor):
		return _reply(false, "先完成或停止手头的行动。")
	var evidence: String = ""
	if method == "show_pass":
		evidence = pass_evidence(actor, region)
		if evidence.is_empty():
			return _reply(false, "你没有可出示的当地有效通行凭据。")
	if method == "receipt":
		var audit: Dictionary = latest_audit(actor)
		if audit.is_empty():
			return _reply(false, "你尚未取得核验回执。")
		evidence = str(audit.id)
	var duration: int = int(definitions.actions[method])
	if duration > SimInventory.MAX_COUNT - world.elapsed_ms:
		return _reply(false, "这次交谈已超出可继续记录的时刻。")
	if int(definitions.grant_ms) > SimInventory.MAX_COUNT - world.elapsed_ms - duration:
		return _reply(false, "这段放行期限已超出可记录的时刻。")
	active[actor] = {"id": _allocate(), "actor": actor, "receiver": receiver, "region": region, "method": method, "evidence": evidence, "started_ms": world.elapsed_ms, "due_ms": world.elapsed_ms + duration, "previous_autonomous": bool(body.autonomous)}
	body.autonomous = false
	body.goal = "当面说明通行的依据"
	world.invalidate_region(region)
	return _reply(true, "已开口，需要%d秒；对方仍有自己的判断。" % ceili(float(duration) / 1000.0))


func cancel(actor: String) -> bool:
	if _owner != null and world != null and world.has_method("accepts_commands") and not world.accepts_commands():
		return false
	if not active.has(actor):
		return false
	var job: Dictionary = active[actor]
	_finish(job, "interrupted", "交谈中断；已经听到的事不会抹去。")
	return true


func next_boundary_ms() -> int:
	var boundary: int = SimInventory.MAX_COUNT
	for job: Dictionary in active.values():
		if not world.actor_controls(job.actor, "action") or not world.actor_controls(job.actor, "communication") or not world.actor_controls(job.actor, "motion"):
			return world.elapsed_ms + 1
		boundary = mini(boundary, int(job.due_ms))
	return boundary


func settle_at_ms(now: int) -> void:
	var actors: Array = active.keys()
	actors.sort()
	for actor: String in actors:
		var job: Dictionary = active[actor]
		if not world.actor_controls(actor, "action") or not world.actor_controls(actor, "communication") or not world.actor_controls(actor, "motion"):
			_finish(job, "interrupted", "身体或传话受阻，交谈没有继续。")
		elif int(job.due_ms) <= now:
			world.synchronize_region(job.region)
			if not nearby(actor, job.receiver) or not world.actor_controls(job.receiver, "communication"):
				_finish(job, "unheard", "对方已经离开，没能听完这次说明。")
			else:
				_complete(job)


func _complete(job: Dictionary) -> void:
	var sim: RefCounted = world.regions[job.region]
	var institution: String = str(sim.config.institution.id)
	match str(job.method):
		"verify":
			if not sim.institutions.has_permission(institution, job.receiver, "authorize"):
				_finish(job, "not_registrar", "对方无权核验登记，请找负责签注的管事。")
				return
			var evidence: String = pass_evidence(job.actor, job.region)
			var row: Dictionary = _finish(job, "confirmed" if not evidence.is_empty() else "unconfirmed", "管事核对本地登记：确有可用通行。" if not evidence.is_empty() else "管事核对本地登记：没有查到可用通行；这次说法未获证实。", evidence)
			if evidence.is_empty():
				sim.social.remember_outcome(job.receiver, job.actor, "failed", str(row.social_event))
		"receipt":
			var audit: Dictionary = entry(job.evidence)
			if audit.is_empty() or audit.actor != job.actor or not audit.status in ["confirmed", "unconfirmed"]:
				_finish(job, "unheard", "没有能出示的这份核验回执。")
				return
			var row: Dictionary = _finish(job, "receipt_seen", "对方看到具名核验回执；以后会按这份依据判断。", job.evidence)
			if audit.status == "unconfirmed":
				_revoke(job.actor, job.receiver, str(row.id))
		"show_pass":
			if pass_evidence(job.actor, job.region) != job.evidence:
				_finish(job, "unconfirmed", "这份凭据眼下已无可核对的有效签注。")
			else:
				_finish(job, "pass_seen", "对方查见你实际出示的签注；正式资格仍以原登记为准。", job.evidence)
		"claim":
			if sim.institutions.has_permission(institution, job.receiver, "authorize"):
				_finish(job, "requires_check", "管事没有仅凭口头放行：若有登记，请让我核对。")
				return
			if _knows_unconfirmed(job.actor, job.receiver):
				_finish(job, "requires_check", "对方记得那份未获证实的回执，这次要求真实签注。")
				return
			var relation: Dictionary = sim.social.relation(job.receiver, job.actor)
			var context: Dictionary = {"benevolence": float(sim.config.actor_profiles[job.receiver].get("benevolence", 0.5)), "reliability": float(relation.reliability), "affinity": float(relation.affinity), "risk": float(definitions.risk), "terms": {"region": job.region, "scope": definitions.scope, "statement": "registered_access"}}
			var decision: Dictionary = sim.social.evaluate_request(job.actor, job.receiver, "oral_admission", context, definitions.policy, _rng, world.current_time)
			for previous: Dictionary in entries:
				if previous.request == decision.id and previous.region == job.region:
					_release(job, str(previous.line))
					return
			var accepted: bool = decision.status == "accepted"
			var row: Dictionary = _finish(job, "believed" if accepted else "doubted", "对方暂信你的说法，答应此次只取一枝药；这不是正式通行签注。" if accepted else "对方没有采信口头说法，要求先取得实际签注。", "", str(decision.id))
			if accepted:
				grants[row.id] = {"id": row.id, "actor": job.actor, "receiver": job.receiver, "region": job.region, "issued_ms": world.elapsed_ms, "expires_ms": world.elapsed_ms + int(definitions.grant_ms), "used_by": "", "revoked_by": ""}


func pass_evidence(actor: String, region: String) -> String:
	if world.services == null or not world.services.has_access(actor, region, str(definitions.scope)):
		return ""
	return str(world.services.authorizations[region + ":" + actor + ":" + str(definitions.scope)].job)


func entry(id: String) -> Dictionary:
	for row: Dictionary in entries:
		if row.id == id:
			return row
	return {}


func latest_audit(actor: String) -> Dictionary:
	for index: int in range(entries.size() - 1, -1, -1):
		var row: Dictionary = entries[index]
		if row.actor == actor and row.method == "verify" and row.status in ["confirmed", "unconfirmed"]:
			return row
	return {}


func _knows_unconfirmed(actor: String, receiver: String) -> bool:
	for row: Dictionary in entries:
		if row.actor != actor or row.receiver != receiver:
			continue
		if row.method == "verify" and row.status == "unconfirmed" or row.method == "receipt" and entry(str(row.evidence)).get("status") == "unconfirmed":
			return true
	return false


func _revoke(actor: String, receiver: String, evidence: String) -> void:
	for grant: Dictionary in grants.values():
		if grant.actor == actor and grant.receiver == receiver and str(grant.revoked_by).is_empty():
			grant.revoked_by = evidence


func valid_grant(id: String, actor: String, region: String) -> bool:
	if not grants.has(id):
		return false
	var grant: Dictionary = grants[id]
	return grant.actor == actor and grant.region == region and str(grant.used_by).is_empty() and str(grant.revoked_by).is_empty() and world.elapsed_ms < int(grant.expires_ms) and world.actor_controls(grant.receiver, "communication")


func available_grant(actor: String, region: String) -> String:
	for row: Dictionary in entries:
		if valid_grant(str(row.id), actor, region):
			return str(row.id)
	return ""


func consume(id: String, job: String) -> void:
	grants[id].used_by = job


func view(actor: String) -> Dictionary:
	if active.has(actor):
		return {"busy": true, "line": "正在当面说明通行依据", "seconds": ceili(float(int(active[actor].due_ms) - world.elapsed_ms) / 1000.0)}
	for index: int in range(entries.size() - 1, -1, -1):
		if entries[index].actor == actor:
			return {"busy": false, "line": entries[index].line, "id": entries[index].id, "seconds": 0}
	return {"busy": false, "line": "", "id": "", "seconds": 0}


func _finish(job: Dictionary, status: String, line: String, evidence: String = "", request: String = "") -> Dictionary:
	var sim: RefCounted = world.regions[job.region]
	var witnesses: Array[String] = []
	var event: String = sim.social.record("admission_statement", job.actor, job.receiver, {"participants": {"text": line, "status": status, "action": job.method, "terms": {"scope": definitions.scope, "evidence": evidence}}}, witnesses, world.current_time)
	var row: Dictionary = {"id": str(job.id), "actor": job.actor, "receiver": job.receiver, "region": job.region, "method": job.method, "status": status, "line": line, "at_ms": world.elapsed_ms, "evidence": evidence, "request": request, "social_event": event}
	entries.append(row)
	_release(job, line)
	return row


func _release(job: Dictionary, line: String) -> void:
	var body: Dictionary = world.regions[job.region].actors[job.actor]
	body.autonomous = bool(job.previous_autonomous)
	body.goal = line
	active.erase(job.actor)
	world.invalidate_region(job.region)


func _allocate() -> String:
	var id: String = "admission:%d" % next_id
	next_id += 1
	return id


static func _reply(ok: bool, line: String) -> Dictionary:
	return {"ok": ok, "line": line}


static func empty_state(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return {"version": 1, "active": {}, "entries": [], "grants": {}, "next_id": 1, "rng_state": str(rng.state)}


func to_dict() -> Dictionary:
	return {"version": 1, "active": active.duplicate(true), "entries": entries.duplicate(true), "grants": grants.duplicate(true), "next_id": next_id, "rng_state": str(_rng.state)}


func restore(data: Dictionary) -> bool:
	if not Schema.validate(data, self):
		return false
	active = data.active.duplicate(true)
	entries.assign(data.entries.duplicate(true))
	grants = data.grants.duplicate(true)
	next_id = int(data.next_id)
	_rng.state = int(data.rng_state)
	return true
