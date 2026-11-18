extends RefCounted
## Production state lives on the physical carrier. This module has no clock,
## run scheduler, inventory copy or writable Resource instance.
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const Costs = preload("res://scripts/sim/kernel/action_costs.gd")
const Results = preload("res://scripts/sim/kernel/activity_results.gd")
const Labor = preload("res://scripts/sim/kernel/labor_progress.gd")
const MAX_CONTRIBUTORS: int = 128

static func _count(values: Dictionary) -> int:
	var count: int = 0
	for amount: int in values.values(): count += amount
	return count

static func input_right(world: RefCounted, actor: int, target: int, recipe: Dictionary) -> Dictionary:
	var record: Dictionary = world.objects.records[target]
	for right: Dictionary in world.objects.groups(target):
		if right.entrust > 0 or right.organization != record.organization: continue
		if right.organization == 0 and right.owner not in [0, actor]: continue
		var enough: bool = true
		for item: String in recipe.inputs:
			if world.objects.available_amount(target, item, right) < int(recipe.inputs[item]): enough = false; break
		if enough: return right
	return {}

static func known_inputs(actor: Dictionary, target: Dictionary, inputs: Dictionary) -> Dictionary:
	if not target.has("contents"): return {}
	var groups: Dictionary = {}
	for item: String in inputs:
		for batch: Dictionary in target.contents.get(item, []):
			if batch.entrusted or int(batch.organization) != int(target.get("organization", 0)): continue
			if int(batch.organization) == 0 and int(batch.owner) not in [0, int(actor.get("id", 0))]: continue
			var key: String = "%d:%d" % [int(batch.owner), int(batch.organization)]
			if not groups.has(key): groups[key] = {}
			groups[key][item] = int(groups[key].get(item, 0)) + int(batch.get("available", batch.count))
	for group: Dictionary in groups.values():
		var complete: bool = true
		for item: String in inputs:
			if int(group.get(item, 0)) < int(inputs[item]): complete = false; break
		if complete: return group
	# Supplemental private inputs retain the operator's title; they cannot
	# complete another partial unowned group just by sharing this container.
	var organization: int = int(target.get("organization", 0))
	return groups.get("0:%d" % organization, {}) if organization > 0 else groups.get("%d:0" % int(actor.get("id", 0)), {})

static func has_inputs(actor: Dictionary, target: Dictionary, inputs: Dictionary) -> bool:
	var available: Dictionary = known_inputs(actor, target, inputs)
	for item: String in inputs:
		if int(available.get(item, 0)) < int(inputs[item]): return false
	return true

static func readiness(operation: Dictionary, actor: Dictionary, target: Dictionary, buildings: Dictionary) -> String:
	var recipe: Dictionary = operation.recipe
	var capabilities: Dictionary = buildings.get(target.get("definition", ""), {}).get("capabilities", {})
	if recipe.id not in capabilities.get(recipe.facility_capability, {}).get("recipes", []): return "unsupported_recipe"
	if target.get("kind") == "blueprint": return "unfinished_facility"
	var process: Dictionary = target.get("process", {})
	if not process.is_empty():
		if process.get("paused", false): return "batch_paused"
		if process.operation != operation.id: return "in_process_conflict"
		if process.stage == "passive" and int(actor.get("at_ms", 0)) < int(process.ready_ms): return "unattended_in_progress"
		return ""
	if not target.has("inventory") or not target.has("capacity") or not target.has("contents"): return "unknown_target_state"
	if not has_inputs(actor, target, recipe.inputs): return "missing_items"
	var reason: String = Costs.check_view(actor, recipe.costs)
	if not reason.is_empty(): return reason
	var needed: int = maxi(0, _count(recipe.outputs) - _count(recipe.inputs))
	if int(target.capacity) >= 0 and _count(target.inventory) + needed + int(target.get("reserved_capacity", 0)) > int(target.capacity): return "no_output_capacity"
	return ""

static func view(record: Dictionary, action: Dictionary = {}, at: int = 0) -> Dictionary:
	if not record.has("process"): return {}
	var process: Dictionary = record.process
	var remaining: int = int(process.remaining_ms)
	if _matches(record, action) and action.has("started_ms"):
		remaining = int(action.base_work_ms) - mini(int(action.base_work_ms), maxi(0, at - int(action.started_ms)) * int(action.base_work_ms) / int(action.scheduled_ms))
	var right: Dictionary = process.input_right
	return {"id": process.id, "operation": process.operation, "stage": process.stage, "remaining_ms": remaining, "ready_ms": process.ready_ms,
		"paused": process.paused, "passive_remaining_ms": process.passive_remaining_ms,
		"output_owner": int(right.owner), "output_organization": int(right.organization)}

static func start(world: RefCounted, actor: int, action: Dictionary, at: int) -> String:
	var operation: Dictionary = world.Operations.OPERATIONS[action.kind]
	var recipe: Dictionary = operation.recipe
	var record: Dictionary = world.objects.records[action.target]
	var process: Dictionary = record.get("process", {})
	if int(action.expected_process) != int(process.get("id", 0)): return "process_changed"
	if process.is_empty():
		var right: Dictionary = input_right(world, actor, int(action.target), recipe)
		if right.is_empty(): return "missing_items"
		var growth: int = maxi(0, _count(recipe.outputs) - _count(recipe.inputs))
		if world.objects.free_capacity(int(action.target)) < growth: return "no_output_capacity"
		var binding: Dictionary = world.institutions.Orders.binding(world.institutions, int(action.target), str(operation.id))
		if binding.is_empty(): return "production_target_met"
		if not Costs.pay(world, actor, recipe.costs): return "insufficient_resource"
		process = {"id": world.next_process, "operation": operation.id, "stage": "work", "remaining_ms": int(recipe.work_ms), "ready_ms": 0, "contributions": {}, "input_right": right, "locked_inputs": recipe.inputs.duplicate(), "net_growth": growth, "paused": false, "passive_remaining_ms": 0, "order": binding.order, "allocation": binding.allocation}
		world.next_process += 1
		record["process"] = process
		world.institutions.Orders.reserve(world.institutions, process)
	elif process.paused: return "batch_paused"
	elif process.stage == "passive":
		if at < int(process.ready_ms): return "unattended_in_progress"
		process.stage = "finish"
	action["expected_process"] = process.id
	action["process_id"] = process.id
	action["process_stage"] = process.stage
	return "started"

static func control(world: RefCounted, target: int, process_id: int, mode: String, at: int) -> String:
	var record: Dictionary = world.objects.records.get(target, {})
	var process: Dictionary = record.get("process", {})
	if process.is_empty() or int(process.id) != process_id: return "process_changed"
	if mode not in ["pause", "resume", "cancel"]: return "invalid_configuration"
	var worker: int = int(world.reservations.get(target, 0))
	if mode == "cancel":
		world.institutions.Orders.release(world.institutions, process)
		record.erase("process") # Old run's interrupt cannot rewrite the cancelled batch.
		if worker > 0 and world.actions.get(worker, {}).get("process_id") == process_id: world.end_run(worker, at, "batch_cancelled")
	elif mode == "pause":
		if process.paused: return "management_updated"
		if worker > 0 and world.actions.get(worker, {}).get("process_id") == process_id: world.end_run(worker, at, "batch_paused")
		if process.stage == "passive":
			process.passive_remaining_ms = maxi(0, int(process.ready_ms) - at)
			process.ready_ms = 0
		process.paused = true
	else:
		if not process.paused: return "management_updated"
		if process.stage == "passive": process.ready_ms = at + int(process.passive_remaining_ms)
		process.passive_remaining_ms = 0
		process.paused = false
	world.institutions.Workflow.process_due(world.institutions, target, process)
	return "management_updated"

static func _matches(record: Dictionary, action: Dictionary) -> bool:
	var process: Dictionary = record.get("process", {})
	return not process.is_empty() and int(process.id) > 0 and process.id == action.get("process_id", -1) and process.stage == action.get("process_stage", "")

static func _contribute(process: Dictionary, actor: int, worked: int) -> void:
	if worked <= 0: return
	while not process.contributions.has(actor) and process.contributions.size() >= MAX_CONTRIBUTORS:
		var oldest: int = -1
		for id: int in process.contributions:
			if id != 0: oldest = id; break
		process.contributions[0] = int(process.contributions.get(0, 0)) + int(process.contributions[oldest])
		process.contributions.erase(oldest)
	process.contributions[actor] = int(process.contributions.get(actor, 0)) + worked

static func interrupt(world: RefCounted, action: Dictionary, at: int) -> Dictionary:
	var record: Dictionary = world.objects.records.get(int(action.target), {})
	if not _matches(record, action) or not action.has("started_ms"): return {}
	var process: Dictionary = record.process
	var worked: int = Labor.credited(action.base_work_ms, action.scheduled_ms, at - int(action.started_ms))
	process.remaining_ms = int(action.base_work_ms) - worked
	_contribute(process, int(action.participants[0]), worked)
	return {"process_id": process.id, "worked_ms": worked, "remaining_ms": process.remaining_ms, "stage": process.stage}

static func commit(world: RefCounted, actor: int, action: Dictionary, at: int) -> Dictionary:
	var record: Dictionary = world.objects.records[action.target]
	if not _matches(record, action) or world.reservations.get(action.target, 0) != actor: return Results.refused("process_changed")
	var operation: Dictionary = world.Operations.OPERATIONS[action.get("operation_id", action.kind)]
	var recipe: Dictionary = operation.recipe
	var process: Dictionary = record.process
	var worked: int = int(process.remaining_ms)
	if process.stage == "work" and int(recipe.passive_ms) > 0:
		_contribute(process, actor, worked)
		process.stage = "passive"
		process.remaining_ms = int(recipe.finish_ms)
		process.ready_ms = at + int(recipe.passive_ms)
		world.institutions.Workflow.process_due(world.institutions, int(action.target), process)
		return Results.completed({"process_id": process.id, "recipe": recipe.id, "stage": "passive", "worked_ms": worked, "remaining_ms": process.remaining_ms, "ready_ms": process.ready_ms}, "process_waiting")
	var right: Dictionary = Stock.attribution(process.input_right)
	var projected: int = world.objects.count_inventory(int(action.target)) - _count(recipe.inputs) + _count(recipe.outputs) + world.institutions.Logistics.target_claimed(world.institutions, int(action.target))
	if int(record.capacity) >= 0 and projected > int(record.capacity): return Results.refused("no_output_capacity")
	var converted: Dictionary = world.institutions.convert_at(world, action.target, recipe.inputs, recipe.outputs, right, at, "stock")
	if converted.status != "completed": return converted
	_contribute(process, actor, worked)
	var labor: Array = []
	var omitted_work: int = 0
	var participants: Array = process.contributions.keys()
	participants.erase(actor)
	participants.push_front(actor)
	for participant: int in participants:
		if labor.size() < 16: labor.append({"actor": participant, "worked_ms": int(process.contributions[participant])})
		else: omitted_work += int(process.contributions[participant])
	converted.facts.merge({"order": process.order, "allocation": process.allocation, "process_id": process.id, "recipe": recipe.id, "stage": "completed", "worked_ms": worked, "remaining_ms": 0, "labor": labor, "omitted_work_ms": omitted_work, "learning": []})
	if not recipe.method.is_empty() and recipe.practice_points > 0:
		for participant: int in participants:
			if participant == 0 or not world.combat.alive(world, participant): continue
			var points: int = int(recipe.practice_points) * int(process.contributions[participant]) / (int(recipe.work_ms) + int(recipe.finish_ms))
			if points <= 0: continue
			var learned: Dictionary = Growth.advance(world.objects.records[participant], recipe.method, points, "practice", 0, at)
			if converted.facts.learning.size() < 16: converted.facts.learning.append({"actor": participant, "points": int(learned.points_gained)})
			world.Equipment.rebuild(world, participant)
	world.institutions.Orders.release(world.institutions, process)
	record.erase("process")
	world.institutions.Workflow.dirty(world.institutions, int(world.institutions._facility_department.get(int(action.target), 0)))
	return converted

static func valid(world: RefCounted) -> bool:
	if world.next_process < 1 or world.next_process > 999999999999: return false
	var seen: Dictionary = {}
	for id: int in world.objects.records:
		var record: Dictionary = world.objects.records[id]
		if record.has("work_stock"): return false
		if not record.has("process"): continue
		var process: Variant = record.process
		if not process is Dictionary or process.size() != 13: return false
		if not process.get("id") is int or process.id <= 0 or process.id >= world.next_process or seen.has(process.id): return false
		seen[process.id] = true
		if not process.get("operation") is String or not world.Operations.OPERATIONS.has(process.operation): return false
		var operation: Dictionary = world.Operations.OPERATIONS[process.operation]
		if operation.recipe.is_empty(): return false
		var recipe: Dictionary = operation.recipe
		for field: String in ["order", "allocation"]:
			if not process.get(field) is int or process[field] < 0 or (process[field] > 0 and world.institutions.matters.get(process[field], {}).get("kind") != "department"): return false
		if process.allocation > 0 and world.institutions.matters[process.allocation].parent_order != process.order: return false
		if process.order > 0:
			var order: Dictionary = world.institutions.matters[process.order]
			world.institutions.Departments.ensure(world.institutions)
			if order.operation != process.operation or order.organization != record.organization or order.parent_order != 0 or world.institutions._facility_department.get(id) != order.department: return false
		if record.kind == "blueprint" or recipe.id not in world.facilities.definitions.get(record.definition, {}).get("capabilities", {}).get(recipe.facility_capability, {}).get("recipes", []): return false
		if process.get("stage") not in ["work", "passive", "finish"] or not process.get("remaining_ms") is int or process.remaining_ms < 1 or not process.get("ready_ms") is int: return false
		var limit: int = int(recipe.work_ms) if process.stage == "work" else int(recipe.finish_ms)
		if process.remaining_ms > limit: return false
		if process.stage == "work":
			if process.ready_ms != 0: return false
		else:
			if recipe.passive_ms <= 0: return false
			if process.paused and process.stage == "passive":
				if process.ready_ms != 0: return false
			elif process.ready_ms <= 0 or process.ready_ms > world.elapsed_ms + recipe.passive_ms or (process.stage == "finish" and process.ready_ms > world.elapsed_ms): return false
			if process.stage == "passive" and process.remaining_ms != recipe.finish_ms: return false
		if not process.get("paused") is bool or not process.get("passive_remaining_ms") is int or process.passive_remaining_ms < 0 or process.passive_remaining_ms > recipe.passive_ms: return false
		if not process.get("net_growth") is int or process.net_growth != maxi(0, _count(recipe.outputs) - _count(recipe.inputs)): return false
		if not process.get("locked_inputs") is Dictionary or process.locked_inputs != recipe.inputs or not Stock.valid_right(process.get("input_right"), world.objects.next_id): return false
		var right: Dictionary = process.input_right
		if right.entrust != 0 or right.organization != record.organization: return false
		for item: String in recipe.inputs:
			if world.objects.amount(id, item, right) < int(recipe.inputs[item]): return false
		if record.capacity >= 0 and world.objects.count_inventory(id) + process.net_growth > record.capacity: return false
		if not process.get("contributions") is Dictionary or process.contributions.size() > MAX_CONTRIBUTORS: return false
		var total: int = 0
		var expected: int = int(recipe.work_ms) - int(process.remaining_ms) if process.stage == "work" else int(recipe.work_ms) + int(recipe.finish_ms) - int(process.remaining_ms)
		for actor: Variant in process.contributions:
			if not actor is int or actor < 0 or actor >= world.objects.next_id or not process.contributions[actor] is int or process.contributions[actor] <= 0 or process.contributions[actor] > expected - total: return false
			if actor > 0 and world.objects.records.has(actor) and world.objects.records[actor].kind != "actor": return false
			total += int(process.contributions[actor])
		if total != expected: return false
	for actor: int in world.actions:
		var action: Dictionary = world.actions[actor]
		var operation: Dictionary = world.Operations.OPERATIONS[action.kind]
		if operation.recipe.is_empty(): continue
		if not action.get("expected_process") is int or action.expected_process < 0 or action.expected_process >= world.next_process: return false
		var slot: int = world.actor_slots[actor]
		if not action.has("started_ms"):
			if action.has("process_id") or action.has("process_stage") or (world.pages[slot / 256].modes[slot % 256] == world.Units.Mode.ACTION and not action.get("waiting", false)): return false
			continue
		if not action.started_ms is int or action.started_ms < 0 or action.started_ms > world.elapsed_ms: return false
		var record: Dictionary = world.objects.records[action.target]
		if not _matches(record, action) or record.process.stage == "passive" or world.reservations.get(action.target, 0) != actor: return false
		if record.process.operation != action.kind or action.expected_process != action.process_id: return false
		if not action.get("base_work_ms") is int or not action.get("scheduled_ms") is int or action.base_work_ms != record.process.remaining_ms or action.scheduled_ms < 1 or action.scheduled_ms > 300000: return false
		if world.pages[slot / 256].due_ms[slot % 256] != action.started_ms + action.scheduled_ms: return false
	return true
