extends RefCounted
## Production state lives on the physical carrier. This module has no clock,
## run scheduler, inventory copy or writable Resource instance.
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const Costs = preload("res://scripts/sim/kernel/action_costs.gd")
const Results = preload("res://scripts/sim/kernel/activity_results.gd")
const Labor = preload("res://scripts/sim/kernel/labor_progress.gd")
const MAX_CONTRIBUTORS: int = 128

static func readiness(operation: Dictionary, actor: Dictionary, target: Dictionary, buildings: Dictionary) -> String:
	var recipe: Dictionary = operation.recipe
	var capabilities: Dictionary = buildings.get(target.get("definition", ""), {}).get("capabilities", {})
	if recipe.id not in capabilities.get(recipe.facility_capability, {}).get("recipes", []): return "unsupported_recipe"
	if target.get("kind") == "blueprint": return "unfinished_facility"
	var process: Dictionary = target.get("process", {})
	if not process.is_empty():
		if process.operation != operation.id: return "in_process_conflict"
		if process.stage == "passive" and int(actor.get("at_ms", 0)) < int(process.ready_ms): return "unattended_in_progress"
	else:
		if Stock.input_group(actor, recipe.inputs, recipe.purpose, int(target.get("organization", 0))).is_empty(): return "missing_items"
		var reason: String = Costs.check_view(actor, recipe.costs)
		if not reason.is_empty(): return reason
	if not target.has("inventory") or not target.has("capacity"): return "unknown_target_state"
	var used: int = 0
	for count: int in target.inventory.values(): used += count
	for count: int in recipe.outputs.values(): used += count
	if int(target.capacity) >= 0 and used > int(target.capacity): return "no_output_capacity"
	return ""

static func view(record: Dictionary, action: Dictionary = {}, at: int = 0) -> Dictionary:
	if not record.has("process"): return {}
	var process: Dictionary = record.process
	var remaining: int = int(process.remaining_ms)
	if _matches(record, action) and action.has("started_ms"):
		remaining = int(action.base_work_ms) - mini(int(action.base_work_ms), maxi(0, at - int(action.started_ms)) * int(action.base_work_ms) / int(action.scheduled_ms))
	return {"id": process.id, "operation": process.operation, "stage": process.stage, "remaining_ms": remaining, "ready_ms": process.ready_ms}

static func start(world: RefCounted, actor: int, action: Dictionary, at: int) -> String:
	var operation: Dictionary = world.Operations.OPERATIONS[action.kind]
	var recipe: Dictionary = operation.recipe
	var record: Dictionary = world.objects.records[action.target]
	var process: Dictionary = record.get("process", {})
	if int(action.expected_process) != int(process.get("id", 0)): return "process_changed"
	if int(action.get("expected_run", 0)) > 0: return "process_changed" # The reserved precursor never started this batch.
	var output_source: Dictionary = world.institutions.input_right(world, actor, recipe.inputs, recipe.purpose, int(record.organization)) if process.is_empty() else Stock.attribution(record.work_stock[recipe.inputs.keys()[0]][0])
	if output_source.is_empty(): return "missing_items"
	if not world.objects.can_receive(action.target, recipe.outputs, Stock.right(int(output_source.owner), int(output_source.organization))): return "no_output_capacity"
	if process.is_empty():
		var right: Dictionary = output_source
		if not Costs.pay(world, actor, recipe.costs): return "insufficient_resource"
		record["work_stock"] = {}
		for item: String in recipe.inputs:
			var moved: int = world.objects.transfer(actor, action.target, item, int(recipe.inputs[item]), right, {}, "stock", "work_stock")
			assert(moved == int(recipe.inputs[item]))
		process = {"id": world.next_process, "operation": operation.id, "stage": "work", "remaining_ms": int(recipe.work_ms), "ready_ms": 0, "contributions": {}}
		world.next_process += 1
		record["process"] = process
		# A continuation requested while this worker was still approaching must
		# follow this actual batch, rather than reopen the now-empty carrier later.
		for waiter: Dictionary in world.actions.values():
			if waiter.target == action.target and waiter.kind == action.kind and waiter.get("expected_run", 0) == action.run_id:
				waiter.expected_process = process.id
				waiter.expected_run = 0
		world._sync_inventory(actor)
	elif process.stage == "passive":
		if at < int(process.ready_ms): return "unattended_in_progress"
		process.stage = "finish"
	action["expected_process"] = process.id
	action["process_id"] = process.id
	action["process_stage"] = process.stage
	return "started"

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
		return Results.completed({"process_id": process.id, "recipe": recipe.id, "stage": "passive", "worked_ms": worked, "remaining_ms": process.remaining_ms, "ready_ms": process.ready_ms}, "process_waiting")
	var right: Dictionary = Stock.attribution(record.work_stock[recipe.inputs.keys()[0]][0])
	var converted: Dictionary = world.institutions.convert_at(world, action.target, recipe.inputs, recipe.outputs, right, at, "work_stock")
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
	converted.facts.merge({"process_id": process.id, "recipe": recipe.id, "stage": "completed", "worked_ms": worked, "remaining_ms": 0, "labor": labor, "omitted_work_ms": omitted_work, "learning": []})
	if not recipe.method.is_empty() and recipe.practice_points > 0:
		for participant: int in participants:
			if participant == 0 or not world.combat.alive(world, participant): continue
			var points: int = int(recipe.practice_points) * int(process.contributions[participant]) / (int(recipe.work_ms) + int(recipe.finish_ms))
			if points <= 0: continue
			var learned: Dictionary = Growth.advance(world.objects.records[participant], recipe.method, points, "practice", 0, at)
			if converted.facts.learning.size() < 16: converted.facts.learning.append({"actor": participant, "points": int(learned.points_gained)})
			world.Equipment.rebuild(world, participant)
	record.erase("process")
	record.erase("work_stock")
	return converted

static func valid(world: RefCounted) -> bool:
	if world.next_process < 1 or world.next_process > 999999999999: return false
	var seen: Dictionary = {}
	for id: int in world.objects.records:
		var record: Dictionary = world.objects.records[id]
		if record.has("work_stock") != record.has("process"): return false
		if not record.has("process"): continue
		var process: Variant = record.process
		if not process is Dictionary or process.size() != 6: return false
		if not process.get("id") is int or process.id <= 0 or process.id >= world.next_process or seen.has(process.id): return false
		seen[process.id] = true
		if not process.get("operation") is String or not world.Operations.OPERATIONS.has(process.operation): return false
		var operation: Dictionary = world.Operations.OPERATIONS[process.operation]
		if operation.recipe.is_empty(): return false
		var recipe: Dictionary = operation.recipe
		if record.kind == "blueprint" or recipe.id not in world.facilities.definitions.get(record.definition, {}).get("capabilities", {}).get(recipe.facility_capability, {}).get("recipes", []): return false
		if process.get("stage") not in ["work", "passive", "finish"] or not process.get("remaining_ms") is int or process.remaining_ms < 1 or not process.get("ready_ms") is int: return false
		var limit: int = int(recipe.work_ms) if process.stage == "work" else int(recipe.finish_ms)
		if process.remaining_ms > limit: return false
		if process.stage == "work":
			if process.ready_ms != 0: return false
		else:
			if recipe.passive_ms <= 0 or process.ready_ms <= 0 or process.ready_ms > world.elapsed_ms + recipe.passive_ms or (process.stage == "finish" and process.ready_ms > world.elapsed_ms): return false
			if process.stage == "passive" and process.remaining_ms != recipe.finish_ms: return false
		var groups: Array = []
		for batches: Array in record.work_stock.values():
			for batch: Dictionary in batches:
				var right: Dictionary = Stock.attribution(batch)
				if not groups.has(right): groups.append(right)
		if groups.size() != 1 or Stock.summary(record.work_stock) != recipe.inputs: return false
		var right: Dictionary = groups[0]
		if right.organization != record.organization or (right.organization == 0 and right.owner <= 0) or right.phase == "produced": return false
		if right.organization > 0 and right.entrust <= 0: return false
		if right.entrust > 0 and world.institutions.entrustments.get(int(right.entrust), {}).get("purpose") != recipe.purpose: return false
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
		if not action.get("expected_run") is int or action.expected_run < 0 or action.expected_run >= world.next_run: return false
		var slot: int = world.actor_slots[actor]
		if not action.has("started_ms"):
			if action.has("process_id") or action.has("process_stage") or (world.pages[slot / 256].modes[slot % 256] == world.Units.Mode.ACTION and not action.get("waiting", false)): return false
			continue
		if not action.started_ms is int or action.started_ms < 0 or action.started_ms > world.elapsed_ms: return false
		var record: Dictionary = world.objects.records[action.target]
		if not _matches(record, action) or record.process.stage == "passive" or world.reservations.get(action.target, 0) != actor: return false
		if record.process.operation != action.kind or action.expected_process != action.process_id: return false
		if not action.get("base_work_ms") is int or not action.get("scheduled_ms") is int or action.base_work_ms != record.process.remaining_ms or action.scheduled_ms < 1 or action.scheduled_ms > 300000: return false
		if action.expected_run != 0: return false
		if world.pages[slot / 256].due_ms[slot % 256] != action.started_ms + action.scheduled_ms: return false
	return true
