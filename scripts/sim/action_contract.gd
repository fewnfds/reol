class_name SimActionContract
extends RefCounted
## Shared execution seams, not another action owner, planner or saved job shape.
## Domains retain routing, phase deadlines, effects and persistent records.


static func can_act(world: RegionalSimulation, region: String, actor: String) -> bool:
	return world != null and world.regions.has(region) and world.regions[region].has_actor(actor) and bool(world.regions[region].actor_state(actor).alive) and world.actor_controls(actor, "action") and world.actor_controls(actor, "motion")


static func can_begin(world: RegionalSimulation, region: String, actor: String) -> bool:
	return can_act(world, region, actor) and world.regions[region].actor_state(actor).active.is_empty() and not world.owns_for_scope(actor, &"body")


static func can_continue(world: RegionalSimulation, region: String, actor: String, domain: StringName, position: Array = []) -> bool:
	if not can_act(world, region, actor) or not world.regions[region].actor_state(actor).active.is_empty() or world.owns_for_scope(actor, &"body", domain):
		return false
	return position.is_empty() or world.regions[region].actor_state(actor).position == position


static func occupy(world: RegionalSimulation, region: String, actor: String) -> bool:
	var previous: bool = bool(world.regions[region].actor_state(actor).autonomous)
	world.regions[region].actor_state(actor).autonomous = false
	world.invalidate_region(region)
	return previous


static func release(world: RegionalSimulation, region: String, actor: String, previous: bool, reservation: String) -> void:
	world.regions[region].inventory.release(reservation)
	world.regions[region].actor_state(actor).autonomous = previous
	world.invalidate_region(region)


static func describe(world: RegionalSimulation, actor: String) -> Dictionary:
	# Project the supported concrete owners. A new domain must actually implement these
	# execution seams before being advertised here; no universal registry.
	for id: String in world.object_lifecycle._active_actions:
		var action: Dictionary = world.object_lifecycle.actions[id]
		if action.actor == actor:
			return view(world, "object_lifecycle", id, actor, action.request.op, "work", int(action.started_ms), int(action.due_ms), "active", action.request.get("id", ""))
	if world.plants != null and world.plants.active.has(actor):
		var job: Dictionary = world.plants.active[actor]
		return view(world, "plants", job.id, actor, job.kind, job.phase, int(job.started_ms), int(job.due_ms), "active", job.plant)
	if world.construction.active.has(actor):
		var job: Dictionary = world.construction.active[actor]
		return view(world, "construction", job.id, actor, job.kind, job.phase, int(job.started_ms), int(job.due_ms), "active", job.project)
	if world.facility_use != null and world.facility_use.active.has(actor):
		var job: Dictionary = world.facility_use.active[actor]
		return view(world, "facility_use", job.id, actor, job.kind, job.phase, int(job.started_ms), int(job.due_ms), "active", job.project)
	for region: VillageSimulation in world.regions.values():
		if region.actors.has(actor) and not region.actors[actor].active.is_empty():
			return from_job(world, "native", region.actors[actor].active, actor)
	if world.services != null and world.services.active_jobs.has(actor):
		return from_job(world, "services", world.services.jobs[world.services.active_jobs[actor]], actor)
	for name: StringName in [&"clothing", &"spirit_sources", &"method_records", &"personal_production", &"resting", &"admissions", &"soul_vessels", &"capability_practice"]:
		var domain: RefCounted = world.get(name)
		if domain != null and domain.active.has(actor):
			return from_job(world, String(name), domain.active[actor], actor)
	if world.soul_vessels.agency.errands.has(actor):
		return from_job(world, "soul_vessels", world.soul_vessels.agency.errands[actor], actor)
	for job: Dictionary in world.artifacts.active.values():
		if job.actor == actor or job.get("method", {}).get("guide") == actor:
			return from_job(world, "artifacts", job, actor)
	for id: String in world.health._participants.active_ids(world.health._actor_care(actor)):
		return from_job(world, "health", world.health.jobs[id], actor)
	for id: String in world.private_exchange.active_jobs:
		var job: Dictionary = world.private_exchange.jobs[id]
		if actor in [job.buyer, job.seller]:
			return from_job(world, "private_exchange", job, actor)
	if world.field_opportunities.owns_actor(actor):
		return from_job(world, "field_opportunities", world.field_opportunities.trips[world.field_opportunities.purposes[actor].trip], actor)
	var encounter: String = world.conflicts.conflict_for(actor)
	if not encounter.is_empty():
		var row: Dictionary = world.conflicts.conflicts[encounter]
		var id: String = str(row.people[actor].action)
		if not id.is_empty():
			var result: Dictionary = from_job(world, "conflicts", world.conflicts.actions[id], actor)
			result.phase = world.conflicts.phase(actor, world.elapsed_ms)
			return result
		return view(world, "conflicts", encounter, actor, "engage", "ready", int(row.started_ms), world.elapsed_ms, "active", world.conflicts.opponent(actor))
	for lesson: Dictionary in world.conflicts.lessons.values():
		if lesson.status == "active" and actor in [lesson.teacher, lesson.pupil]:
			return from_job(world, "conflicts", lesson, actor)
	if world.sparring.owns_actor(actor):
		return from_job(world, "sparring", world.sparring.bout, actor)
	return {"ok": false, "reason": "no_supported_action", "scope": "unit_action", "visibility": "authority_only"}


static func from_job(world: RegionalSimulation, domain: String, job: Dictionary, actor: String, status: String = "active") -> Dictionary:
	var intent: String = str(job.get("kind", job.get("verb", job.get("action", job.get("method", job.get("node", "interact"))))))
	var target: String = str(job.get("project", job.get("plant", job.get("object", job.get("target", job.get("batch", job.get("bed", "")))))))
	return view(world, domain, str(job.get("id", domain + ":" + actor)), actor, intent, str(job.get("phase", "work")), int(job.get("started_ms", world.elapsed_ms)), int(job.get("due_ms", world.elapsed_ms)), status, target)


static func job_finished(world: RegionalSimulation, domain: String, job: Dictionary, actor: String, status: String, reason: String = "") -> void:
	publish_finished(world, from_job(world, domain, job, actor, status), reason if not reason.is_empty() else status)


static func view(world: RegionalSimulation, domain: String, id: String, actor: String, intent: String, phase: String, started: int, due: int, status: String, target: String) -> Dictionary:
	return {"ok": true, "scope": "unit_action", "visibility": "authority_only", "domain": domain, "id": id, "actor": actor,
		"intent": intent, "phase": phase, "started_ms": started, "due_ms": due, "world_time_ms": world.elapsed_ms,
		"remaining_ms": maxi(0, due - world.elapsed_ms) if status == "active" else 0, "status": status, "target": target}


static func publish_finished(world: RegionalSimulation, outcome: Dictionary, reason: String) -> void:
	# Transient, recursively detached scalar projection; no saved history. The
	# original owner has completed effects, erased active membership and released
	# reservations before observers run.
	var notice: Dictionary = outcome.duplicate(true)
	notice["reason"] = reason
	notice["finished_ms"] = world.elapsed_ms
	notice.make_read_only()
	world.publish_action_finished(notice)
