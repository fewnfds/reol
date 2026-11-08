class_name SimActionContract
extends RefCounted
## Shared execution seams, not another action owner, planner or saved job shape.
## Domains retain routing, phase deadlines, effects and persistent records.


static func can_act(world: RegionalSimulation, region: String, actor: String) -> bool:
	return world != null and world.regions.has(region) and world.regions[region].actors.has(actor) and bool(world.regions[region].actors[actor].alive) and world.actor_controls(actor, "action") and world.actor_controls(actor, "motion")


static func can_begin(world: RegionalSimulation, region: String, actor: String) -> bool:
	return can_act(world, region, actor) and world.regions[region].actors[actor].active.is_empty() and not world.owns_for_scope(actor, &"body")


static func can_continue(world: RegionalSimulation, region: String, actor: String, domain: StringName, position: Array = []) -> bool:
	if not can_act(world, region, actor) or not world.regions[region].actors[actor].active.is_empty() or world.owns_for_scope(actor, &"body", domain):
		return false
	return position.is_empty() or world.regions[region].actors[actor].position == position


static func occupy(world: RegionalSimulation, region: String, actor: String) -> bool:
	var previous: bool = bool(world.regions[region].actors[actor].autonomous)
	world.regions[region].actors[actor].autonomous = false
	world.invalidate_region(region)
	return previous


static func release(world: RegionalSimulation, region: String, actor: String, previous: bool, reservation: String) -> void:
	world.regions[region].inventory.release(reservation)
	world.regions[region].actors[actor].autonomous = previous
	world.invalidate_region(region)


static func describe(world: RegionalSimulation, actor: String) -> Dictionary:
	# Project the supported concrete owners. A new domain must actually implement these
	# execution seams before being advertised here; no universal registry.
	for id: String in world.object_lifecycle._active_actions:
		var action: Dictionary = world.object_lifecycle.actions[id]
		if action.actor == actor:
			return view(world, "object_lifecycle", id, actor, action.request.op, "work", int(action.started_ms), int(action.due_ms), "active", action.request.get("id", ""))
	if world.construction.active.has(actor):
		var job: Dictionary = world.construction.active[actor]
		return view(world, "construction", job.id, actor, job.kind, job.phase, int(job.started_ms), int(job.due_ms), "active", job.project)
	if world.facility_use != null and world.facility_use.active.has(actor):
		var job: Dictionary = world.facility_use.active[actor]
		return view(world, "facility_use", job.id, actor, job.kind, job.phase, int(job.started_ms), int(job.due_ms), "active", job.project)
	return {"ok": false, "reason": "no_supported_action", "scope": "minimal_action", "visibility": "authority_only"}


static func view(world: RegionalSimulation, domain: String, id: String, actor: String, intent: String, phase: String, started: int, due: int, status: String, target: String) -> Dictionary:
	return {"ok": true, "scope": "minimal_action", "visibility": "authority_only", "domain": domain, "id": id, "actor": actor,
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
