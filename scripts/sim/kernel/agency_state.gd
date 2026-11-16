extends RefCounted
## Candidate validation for the personal-purpose owner. No restoration side effects.
const Defs = preload("res://scripts/sim/kernel/agency_defs.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Planner = preload("res://scripts/sim/kernel/agency_planner.gd")

static func valid(owner: RefCounted, world: RefCounted) -> bool:
	if not Defs.ERRORS.is_empty() or owner.catalog_signature != Defs.SIGNATURE or owner.next_goal < 1 or owner.records.size() > world.actor_slots.size(): return false
	var ids: Dictionary = {}
	for actor: Variant in owner.records:
		if not actor is int or not world.actor_slots.has(actor) or not world.combat.alive(world, actor): return false
		var entry: Variant = owner.records[actor]
		if not entry is Dictionary or entry.size() != 9 or not entry.get("borrowed_autonomy") is bool or not entry.get("goals") is Dictionary or entry.goals.size() > owner.GOAL_LIMIT or not entry.get("intention") is Dictionary or not entry.get("appraisals") is Dictionary or entry.appraisals.size() > owner.APPRAISAL_LIMIT: return false
		if not entry.get("dispositions") is Dictionary or entry.dispositions.size() != Defs.DISPOSITIONS.size(): return false
		for key: Variant in entry.dispositions:
			if key not in Defs.DISPOSITIONS or not (entry.dispositions[key] is int or entry.dispositions[key] is float) or not is_finite(float(entry.dispositions[key])) or entry.dispositions[key] < 0 or entry.dispositions[key] > 2: return false
		if not entry.get("explore_ms") is int or entry.explore_ms < 0 or entry.explore_ms > world.elapsed_ms + 60000 or not entry.get("explore_count") is int or entry.explore_count < 0 or not entry.get("idle_attempts") is int or entry.idle_attempts < 0 or entry.idle_attempts > 6: return false
		var budget: Variant = entry.get("budget")
		if not budget is Dictionary or budget.size() != 4 or not budget.get("window_ms") is int or budget.window_ms < 0 or budget.window_ms > world.elapsed_ms or not budget.get("work") is int or budget.work < 0 or budget.work > Planner.WORK_LIMIT or not budget.get("cursor") is int or budget.cursor < 0 or budget.cursor >= 128: return false
		if not budget.get("goal_cursor") is int or budget.goal_cursor < 0 or budget.goal_cursor >= owner.GOAL_LIMIT: return false
		for id: Variant in entry.goals:
			var goal: Variant = entry.goals[id]
			if not id is int or id < 1 or id >= owner.next_goal or ids.has(id) or not goal is Dictionary or goal.size() != 9 or goal.get("id") != id or not goal.get("definition") is String or not Defs.GOALS.has(goal.definition): return false
			ids[id] = true
			if not goal.get("params") is Dictionary or not owner._params_valid(goal.definition, goal.params, world.objects.next_id) or not goal.get("source") is int or goal.source < 0 or goal.source >= world.objects.next_id: return false
			if not goal.get("created_ms") is int or goal.created_ms < 0 or goal.created_ms > world.elapsed_ms or goal.get("state") not in ["active", "completed", "cancelled"] or not goal.get("closed_ms") is int: return false
			if (goal.state == "active" and goal.closed_ms != -1) or (goal.state != "active" and (goal.closed_ms < goal.created_ms or goal.closed_ms > world.elapsed_ms)): return false
			if not goal.get("progress") is int or goal.progress < 0 or (Defs.GOALS[goal.definition].driver != "delivery" and goal.progress != 0) or (Defs.GOALS[goal.definition].driver == "delivery" and goal.progress > goal.params.amount): return false
			if int(goal.params.get("organization", 0)) > 0 and not world.institutions.organizations.has(goal.params.organization): return false
			if Defs.GOALS[goal.definition].driver == "delivery" and goal.state == "active" and goal.progress >= goal.params.amount: return false
			if not goal.get("method") is Dictionary or not _method_valid(goal.method, goal, world): return false
			if Defs.GOALS[goal.definition].driver == "responsibility":
				if goal.params.matter >= world.institutions.next_matter or goal.params.share >= world.institutions.next_share: return false
				if goal.state == "active":
					var share: Dictionary = world.institutions.shares.get(int(goal.params.share), {})
					if share.get("actor") != actor or share.get("matter") != goal.params.matter or share.get("state") != "accepted": return false
			if Defs.GOALS[goal.definition].driver == "duty":
				if goal.params.appointment >= world.institutions.next_appointment: return false
				if goal.state == "active" and not world.institutions.Duties.views(world.institutions, actor).has(int(goal.params.appointment)): return false
		var intention: Dictionary = entry.intention
		if not intention.is_empty():
			if intention.size() != 6 or not intention.get("goal") is int or not entry.goals.has(intention.goal) or not intention.get("approach") is String or intention.approach not in Defs.GOALS[entry.goals[intention.goal].definition].approaches: return false
			if not intention.get("anchor") is int or intention.anchor < 0 or intention.anchor >= world.objects.next_id or not intention.get("operation") is String or (not intention.operation.is_empty() and not Operations.OPERATIONS.has(intention.operation)): return false
			if not intention.get("selected_ms") is int or intention.selected_ms < 0 or intention.selected_ms > world.elapsed_ms or not intention.get("task_id") is int or intention.task_id < 0 or intention.task_id >= world.decisions.next_task: return false
			if intention.task_id > 0 and (entry.goals[intention.goal].state != "active" or world.decisions.records.get(actor, {}).get("task", {}).get("id") != intention.task_id): return false
		for key: Variant in entry.appraisals:
			var account: Variant = entry.appraisals[key]
			if not key is String or not account is Dictionary or account.size() != 7 or not account.get("operation") is String or (account.operation != "inspect" and not Operations.OPERATIONS.has(account.operation)) or not account.get("target") is int or account.target <= 0 or account.target >= world.objects.next_id or key != "%s:%d" % [account.operation, account.target]: return false
			if not account.get("reason") is String or not account.reason.is_valid_identifier() or not account.get("failures") is int or account.failures < 1 or account.failures > 6: return false
			if not account.get("at_ms") is int or account.at_ms < 0 or account.at_ms > world.elapsed_ms or not account.get("until_ms") is int or account.until_ms <= account.at_ms or account.until_ms > account.at_ms + 60000 or not account.get("revision") is int or account.revision < 0: return false
	# A living obligor must have exactly one reference, including while manual.
	# Historical/dead obligors need no writable personal-purpose record.
	for share: Dictionary in world.institutions.shares.values():
		if share.state != "accepted" or not world.combat.alive(world, int(share.actor)): continue
		var count: int = 0
		for goal: Dictionary in owner.records.get(int(share.actor), {}).get("goals", {}).values():
			if goal.state == "active" and Defs.GOALS[goal.definition].driver == "responsibility" and goal.params.share == share.id: count += 1
		if count != 1: return false
	for appointment: Dictionary in world.institutions.appointments.values():
		if not appointment.active or world.institutions.Defs.ROLES[appointment.role].duty.is_empty() or not world.combat.alive(world, int(appointment.actor)): continue
		var count: int = 0
		for goal: Dictionary in owner.records.get(int(appointment.actor), {}).get("goals", {}).values():
			if goal.state == "active" and Defs.GOALS[goal.definition].driver == "duty" and goal.params.appointment == appointment.id: count += 1
		if count != 1: return false
	return true

static func _method_valid(method: Dictionary, goal: Dictionary, world: RefCounted) -> bool:
	if method.is_empty(): return true
	if method.size() != 4 or not method.get("approach") is String or method.approach not in Defs.GOALS[goal.definition].approaches: return false
	if not method.get("operation") is String or (not method.operation.is_empty() and not Operations.OPERATIONS.has(method.operation)): return false
	if not method.get("anchor") is int or method.anchor < 0 or method.anchor >= world.objects.next_id or not method.get("selected_ms") is int or method.selected_ms < goal.created_ms or method.selected_ms > world.elapsed_ms: return false
	return true
