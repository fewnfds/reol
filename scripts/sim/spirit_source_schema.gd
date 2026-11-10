extends RefCounted
## Independent candidate checks. Original validated jobs prove all later spending;
## source receipts add only their actual output to the original target ledger.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const JOB_KEYS: Array[String] = ["id", "actor", "region", "source", "target", "object", "cell", "position", "started_ms", "due_ms", "previous_autonomous"]
const RESULT_KEYS: Array[String] = ["finished_ms", "result", "before", "after", "output", "loss", "artifact_floor", "soul_floor", "conflict_floor", "practice_floor", "line"]


static func validate(data: Variant, domain: RefCounted) -> bool:
	if not Shape.keys(data, ["version", "rules_version", "activation_ms", "last_ms", "sources", "active", "records", "qi_baselines", "charge_baselines", "next_id"]) or not Shape.count(data.version, 3, 3) or not Shape.count(data.rules_version, int(domain.definitions.version), int(domain.definitions.version)):
		return false
	if not Shape.count(data.activation_ms, 0, int(domain.world.elapsed_ms)) or not Shape.count(data.last_ms, int(data.activation_ms), int(domain.world.elapsed_ms)) or data.last_ms != domain.world.elapsed_ms or not Shape.count(data.next_id, 1):
		return false
	for key: String in ["sources", "active", "records", "qi_baselines", "charge_baselines"]:
		if not data[key] is Dictionary:
			return false
	var expected: Dictionary = domain.empty_state(int(data.activation_ms), domain.definitions, domain.world).sources
	if not Shape.keys(data.sources, expected.keys()):
		return false
	var allocated: Dictionary = {}
	var objects: Dictionary = {}
	var reserved: Dictionary = {}
	var all_jobs: Array[Dictionary] = []
	for actor: Variant in data.active:
		var job: Variant = data.active[actor]
		if not actor is String or not _job(job, data, domain, false) or job.actor != actor or allocated.has(job.id) or objects.has(job.object):
			return false
		allocated[job.id] = true
		objects[job.object] = true
		reserved[job.source] = int(reserved.get(job.source, 0)) + int(domain.definitions.source_cost)
		all_jobs.append(job)
		var body: Dictionary = domain.world.regions[job.region].synchronize_actors()[actor]
		if bool(body.autonomous) or not domain._same_position(job) or not domain.readiness(actor, str(job.source), str(job.target), str(job.object), true).is_empty():
			return false
	for id: Variant in data.records:
		var record: Variant = data.records[id]
		if not id is String or not _job(record, data, domain, true) or record.id != id or allocated.has(id):
			return false
		allocated[id] = true
		all_jobs.append(record)
	# Every allocated process remains either active or as an immutable result.
	if allocated.size() != int(data.next_id) - 1:
		return false
	all_jobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return domain.number(str(a.id)) < domain.number(str(b.id)))
	var prior_start: int = int(data.activation_ms)
	for job: Dictionary in all_jobs:
		if int(job.started_ms) < prior_start:
			return false
		prior_start = int(job.started_ms)
	if not _historical_exclusion(data, domain, all_jobs):
		return false
	for id: String in data.sources:
		var row: Variant = data.sources[id]
		if not Shape.keys(row, ["amount", "released", "spent", "lost"]):
			return false
		var rule: Dictionary = domain.definitions.sources[id]
		for key: String in ["amount", "released", "spent", "lost"]:
			if not Shape.count(row[key]):
				return false
		if int(row.amount) > int(rule.capacity) or int(reserved.get(id, 0)) > int(row.amount) or not _source_ledger(id, row, data, rule, int(domain.definitions.source_cost)):
			return false
	if not _baselines(data, domain, all_jobs):
		return false
	return _qi_ledger(data, domain) and _charge_ledger(data, domain)


static func _job(job: Variant, data: Dictionary, domain: RefCounted, finished: bool) -> bool:
	var keys: Array = JOB_KEYS.duplicate()
	if finished:
		keys.append_array(RESULT_KEYS)
	if not Shape.keys(job, keys) or not job.id is String or not _id(job.id, int(data.next_id)) or not job.actor is String or not data.sources.has(job.source) or job.target not in ["body", "stone"] or not job.previous_autonomous is bool:
		return false
	if domain.actor_home(str(job.actor)) != job.region or not domain.world.artifacts.objects.has(job.object) or domain.world.artifacts.objects[job.object].definition != domain.definitions.artifact_type or domain.definitions.sources[job.source].region != job.region:
		return false
	if not Shape.cell_valid(job.cell) or not Shape.position_valid(job.position) or TileGrid.world_to_cell(Vector2(float(job.position[0]), float(job.position[1]))) != SimRouteTravel.cell(job.cell):
		return false
	if Vector2(float(job.position[0]), float(job.position[1])).distance_to(TileGrid.cell_to_world(domain.source_cell(str(job.source)))) > float(domain.definitions.interaction_cells) * TileGrid.TILE_SIZE:
		return false
	if not Shape.count(job.started_ms, int(data.activation_ms), int(data.last_ms)) or not Shape.count(job.due_ms, int(job.started_ms), SimInventory.MAX_COUNT) or int(job.due_ms) - int(job.started_ms) != int(domain.definitions.duration_ms):
		return false
	if not domain.world.heat_methods.base_known_from(str(job.actor), str(job.object), int(job.started_ms)):
		return false
	if not data.qi_baselines.has(job.actor) or job.target == "stone" and not data.charge_baselines.has(job.object):
		return false
	if not finished:
		return int(job.due_ms) > int(data.last_ms)
	if job.result not in ["success", "failed", "cancelled"] or not SimInventory._nonempty(job.line) or not Shape.count(job.finished_ms, int(job.started_ms), mini(int(data.last_ms), int(job.due_ms))):
		return false
	if job.result != "cancelled" and int(job.finished_ms) != int(job.due_ms):
		return false
	if not _floors(job, domain):
		return false
	for key: String in ["before", "after", "output", "loss"]:
		if not Shape.count(job[key]):
			return false
	if job.result != "success":
		return int(job.before) == 0 and int(job.after) == 0 and int(job.output) == 0 and int(job.loss) == 0
	var offered: int = int(domain.definitions.qi_gain) if job.target == "body" else int(domain.definitions.charge_gain)
	var maximum: int = domain.max_qi(str(job.actor)) if job.target == "body" else int(domain.world.artifacts.definitions.types[domain.world.artifacts.objects[job.object].definition].max_charge)
	return int(job.before) < maximum and int(job.output) == mini(offered, maximum - int(job.before)) and int(job.after) == int(job.before) + int(job.output) and int(job.loss) == offered - int(job.output)


static func _id(value: String, next_id: int) -> bool:
	if value.get_slice_count(":") != 2 or not value.begins_with("spirit:"):
		return false
	var suffix: String = value.get_slice(":", 1)
	return suffix.is_valid_int() and suffix == str(int(suffix)) and int(suffix) >= 1 and int(suffix) < next_id


static func _historical_exclusion(data: Dictionary, domain: RefCounted, jobs: Array[Dictionary]) -> bool:
	var artifacts: Array = domain.world.artifacts.events.duplicate()
	artifacts.append_array(domain.world.artifacts.active.values())
	var souls: Array = domain.world.soul_vessels.events.duplicate()
	souls.append_array(domain.world.soul_vessels.active.values())
	for index: int in jobs.size():
		var job: Dictionary = jobs[index]
		var end: int = int(job.get("finished_ms", job.due_ms))
		var reserved: int = 0
		for prior_index: int in range(index):
			var prior: Dictionary = jobs[prior_index]
			var prior_end: int = int(prior.get("finished_ms", prior.due_ms))
			if prior_end > int(job.started_ms):
				if prior.actor == job.actor or prior.object == job.object:
					return false
				if prior.source == job.source:
					reserved += int(domain.definitions.source_cost)
		# Reconstruct the stock at this actual reservation, after prior
		# completions and before any later release. A future refill cannot
		# retroactively fund simultaneous starts with an empty source.
		var rule: Dictionary = domain.definitions.sources[job.source]
		var amount: int = int(rule.initial)
		var released: int = 0
		var completions: Array[Dictionary] = []
		for prior_index: int in range(index):
			var prior: Dictionary = jobs[prior_index]
			if prior.source == job.source and prior.get("result") == "success" and int(prior.finished_ms) <= int(job.started_ms):
				completions.append(prior)
		completions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.finished_ms) < int(b.finished_ms) or int(a.finished_ms) == int(b.finished_ms) and domain.number(str(a.id)) < domain.number(str(b.id)))
		for prior: Dictionary in completions:
			var supplied: int = _refill(rule, int(data.activation_ms), int(prior.finished_ms))
			amount = mini(int(rule.capacity), amount + supplied - released) - int(domain.definitions.source_cost)
			released = supplied
		amount = mini(int(rule.capacity), amount + _refill(rule, int(data.activation_ms), int(job.started_ms)) - released)
		if amount - reserved < int(domain.definitions.source_cost):
			return false
		for original: Dictionary in artifacts:
			var original_end: int = int(original.get("at_ms", original.get("due_ms", 0)))
			var overlaps: bool = int(original.started_ms) < end and int(job.started_ms) < original_end
			if overlaps and (original.actor == job.actor or original.get("method", {}).get("guide") == job.actor or original.object == job.object or original.get("draw", {}).get("target") == job.object):
				return false
		for original: Dictionary in souls:
			var original_end: int = int(original.get("at_ms", original.get("due_ms", 0)))
			if int(original.started_ms) < end and int(job.started_ms) < original_end and (original.actor == job.actor or original.get("target") == job.object):
				return false
	return true


static func _refill(rule: Dictionary, activation: int, at_ms: int) -> int:
	@warning_ignore("integer_division")
	var pulses: int = (at_ms - activation) / int(rule.refill_ms)
	@warning_ignore("integer_division")
	var required: int = (int(rule.deep_supply) + int(rule.refill_amount) - 1) / int(rule.refill_amount)
	return mini(int(rule.deep_supply), mini(pulses, required) * int(rule.refill_amount))


static func _source_ledger(id: String, row: Dictionary, data: Dictionary, rule: Dictionary, cost: int) -> bool:
	var completed: Array[Dictionary] = []
	for record: Dictionary in data.records.values():
		if record.source == id and record.result == "success":
			completed.append(record)
	completed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.finished_ms) < int(b.finished_ms) or int(a.finished_ms) == int(b.finished_ms) and int(a.id.get_slice(":", 1)) < int(b.id.get_slice(":", 1)))
	var amount: int = int(rule.initial)
	var released: int = 0
	var spent: int = 0
	var lost: int = 0
	for record: Dictionary in completed:
		var expected_release: int = _refill(rule, int(data.activation_ms), int(record.finished_ms))
		var gain: int = expected_release - released
		var accepted: int = mini(gain, int(rule.capacity) - amount)
		amount += accepted
		lost += gain - accepted
		released = expected_release
		amount -= cost
		spent += cost
		if amount < 0:
			return false
	var final_release: int = _refill(rule, int(data.activation_ms), int(data.last_ms))
	var remaining: int = final_release - released
	var accepted: int = mini(remaining, int(rule.capacity) - amount)
	amount += accepted
	lost += remaining - accepted
	return int(row.amount) == amount and int(row.released) == final_release and int(row.spent) == spent and int(row.lost) == lost and int(rule.initial) + final_release == amount + spent + lost


static func _baselines(data: Dictionary, domain: RefCounted, jobs: Array[Dictionary]) -> bool:
	var first_actor: Dictionary = {}
	var first_stone: Dictionary = {}
	for job: Dictionary in jobs:
		if not first_actor.has(job.actor):
			first_actor[job.actor] = job
		if job.target == "stone" and not first_stone.has(job.object):
			first_stone[job.object] = job
	var first_cast: Dictionary = {}
	var first_practice: Dictionary = {}
	var first_ring: Dictionary = {}
	var expected_actors: Dictionary = first_actor.duplicate()
	# Old warm-stone actions did not create a checkpoint. Only the new paid
	# ring and device actions establish a first baseline; existing artifacts still enter
	# _spending from whatever original artifact_floor was actually captured.
	var artifact_jobs: Array = domain.world.artifacts.events.duplicate()
	artifact_jobs.append_array(domain.world.artifacts.active.values())
	for job: Dictionary in artifact_jobs:
		if job.verb not in ["use_research", "draw", "enable"] or int(job.qi_spent) <= 0:
			continue
		var actor: String = str(job.actor)
		var cost: Dictionary = {"domain": "artifact", "number": domain.number(str(job.get("action", job.id))), "at_ms": int(job.started_ms), "amount": int(job.qi_spent)}
		if not _valid_cost(cost, domain):
			return false
		if not first_ring.has(actor) or int(cost.number) < int(first_ring[actor].number):
			first_ring[actor] = cost
			expected_actors[actor] = true
	var conflicts: Variant = domain.world.get("conflicts")
	if conflicts != null:
		var allocated: Dictionary = {}
		for region: String in domain.world.regions:
			for actor: String in domain.world.regions[region].synchronize_actors():
				for cost: Dictionary in conflicts.qi_spending(actor):
					if not _valid_cost(cost, domain) or cost.domain != "conflict" or allocated.has(cost.number):
						return false
					allocated[cost.number] = true
					if int(cost.amount) > 0 and (not first_cast.has(actor) or int(cost.number) < int(first_cast[actor].number)):
						first_cast[actor] = cost
						expected_actors[actor] = true
	var practice: Variant = domain.world.get("capability_practice")
	if practice != null:
		var allocated: Dictionary = {}
		for actor: String in domain.world._actor_ids(domain.world.regions):
			for cost: Dictionary in practice.qi_spending(actor):
				if not _valid_cost(cost, domain) or cost.domain != "practice" or allocated.has(cost.number): return false
				allocated[cost.number] = true
				if int(cost.amount) > 0 and (not first_practice.has(actor) or int(cost.number) < int(first_practice[actor].number)):
					first_practice[actor] = cost
					expected_actors[actor] = true
	if not Shape.keys(data.qi_baselines, expected_actors.keys()) or not Shape.keys(data.charge_baselines, first_stone.keys()):
		return false
	for actor: String in data.qi_baselines:
		var row: Variant = data.qi_baselines[actor]
		var source_ms: int = int(first_actor[actor].started_ms) if first_actor.has(actor) else SimInventory.MAX_COUNT
		var cast_ms: int = int(first_cast[actor].at_ms) if first_cast.has(actor) else SimInventory.MAX_COUNT
		var practice_ms: int = int(first_practice[actor].at_ms) if first_practice.has(actor) else SimInventory.MAX_COUNT
		var ring_ms: int = int(first_ring[actor].at_ms) if first_ring.has(actor) else SimInventory.MAX_COUNT
		if not Shape.keys(row, ["at_ms", "qi", "artifact_floor", "soul_floor", "conflict_floor", "practice_floor"]) or not Shape.count(row.at_ms, int(data.activation_ms), int(data.last_ms)) or int(row.at_ms) != mini(ring_ms, mini(source_ms, mini(cast_ms, practice_ms))) or not Shape.count(row.qi, 0, domain.max_qi(actor)) or not _floors(row, domain):
			return false
		if first_cast.has(actor):
			var number: int = int(first_cast[actor].number)
			# A cast-first checkpoint is taken immediately before its exact
			# allocation. A source may have opened earlier in the same ms, so
			# its global floor can be smaller, but never skip this first cost.
			if int(row.conflict_floor) > number or (cast_ms < mini(ring_ms, mini(source_ms, practice_ms)) and int(row.conflict_floor) != number):
				return false
		if first_practice.has(actor):
			var number: int = int(first_practice[actor].number)
			if int(row.practice_floor) > number or practice_ms < mini(ring_ms, mini(source_ms, cast_ms)) and int(row.practice_floor) != number: return false
		if first_ring.has(actor):
			var number: int = int(first_ring[actor].number)
			if int(row.artifact_floor) > number or ring_ms < mini(source_ms, mini(cast_ms, practice_ms)) and int(row.artifact_floor) != number:
				return false
	for id: String in data.charge_baselines:
		var row: Variant = data.charge_baselines[id]
		var shape: Dictionary = domain.world.artifacts.definitions.types[domain.world.artifacts.objects[id].definition]
		if not Shape.keys(row, ["at_ms", "charge", "damage", "artifact_floor"]) or not Shape.count(row.at_ms, int(data.activation_ms), int(data.last_ms)) or row.at_ms != first_stone[id].started_ms or not Shape.count(row.charge, 0, int(shape.max_charge)) or not Shape.count(row.damage, 0, int(shape.damage_max) - 1) or not Shape.count(row.artifact_floor, 1, int(domain.world.artifacts.next_id)):
			return false
	return true


static func _floors(row: Dictionary, domain: RefCounted) -> bool:
	return Shape.count(row.artifact_floor, 1, int(domain.world.artifacts.next_id)) and Shape.count(row.soul_floor, 1, int(domain.world.soul_vessels.next_id)) and Shape.count(row.conflict_floor, 1, domain.conflict_cost_floor()) and Shape.count(row.practice_floor, 1, domain.practice_cost_floor())


static func _cost_floor(row: Dictionary, kind: String) -> int:
	return int(row[kind + "_floor"])


static func _qi_ledger(data: Dictionary, domain: RefCounted) -> bool:
	for actor: String in data.qi_baselines:
		var baseline: Dictionary = data.qi_baselines[actor]
		var outputs: int = 0
		var successful: Array[Dictionary] = []
		for record: Dictionary in data.records.values():
			if record.actor == actor and record.target == "body" and record.result == "success":
				successful.append(record)
				outputs += int(record.output)
		var spending: Array[Dictionary] = _spending(domain, actor)
		var spent: int = 0
		var conflict_costs: Dictionary = {}
		for cost: Dictionary in spending:
			if not _valid_cost(cost, domain):
				return false
			if cost.domain in ["conflict", "practice"]:
				var key: String = str(cost.domain) + ":" + str(int(cost.number))
				if conflict_costs.has(key):
					return false
				conflict_costs[key] = true
			var floor_value: int = _cost_floor(baseline, str(cost.domain))
			if int(cost.number) >= floor_value:
				if int(cost.at_ms) < int(baseline.at_ms):
					return false
				spent += int(cost.amount)
			elif int(cost.at_ms) > int(baseline.at_ms):
				return false
		var body: Dictionary = domain.world.regions[domain.actor_home(actor)].synchronize_actors()[actor]
		if int(body.qi) != int(baseline.qi) + outputs - spent:
			return false
		for receipt: Dictionary in successful:
			if int(receipt.artifact_floor) < int(baseline.artifact_floor) or int(receipt.soul_floor) < int(baseline.soul_floor) or int(receipt.conflict_floor) < int(baseline.conflict_floor) or int(receipt.practice_floor) < int(baseline.practice_floor):
				return false
			var before: int = int(baseline.qi)
			for prior: Dictionary in successful:
				if int(prior.finished_ms) < int(receipt.finished_ms) or int(prior.finished_ms) == int(receipt.finished_ms) and domain.number(str(prior.id)) < domain.number(str(receipt.id)):
					before += int(prior.output)
			for cost: Dictionary in spending:
				var lower: int = _cost_floor(baseline, str(cost.domain))
				var upper: int = _cost_floor(receipt, str(cost.domain))
				if int(cost.number) >= lower and int(cost.number) < upper:
					if int(cost.at_ms) > int(receipt.finished_ms):
						return false
					before -= int(cost.amount)
			if before != int(receipt.before):
				return false
	return true


static func _valid_cost(cost: Dictionary, domain: RefCounted) -> bool:
	if not Shape.keys(cost, ["domain", "number", "at_ms", "amount"]) or cost.domain not in ["artifact", "soul", "conflict", "practice"] or not Shape.count(cost.number, 1) or not Shape.count(cost.at_ms, 0, int(domain.world.elapsed_ms)) or not Shape.count(cost.amount):
		return false
	return (cost.domain != "conflict" or int(cost.number) < domain.conflict_cost_floor()) and (cost.domain != "practice" or int(cost.number) < domain.practice_cost_floor())


static func _spending(domain: RefCounted, actor: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var artifact_jobs: Array = domain.world.artifacts.events.duplicate()
	artifact_jobs.append_array(domain.world.artifacts.active.values())
	for job: Dictionary in artifact_jobs:
		var number: int = domain.number(str(job.get("action", job.id)))
		if job.actor == actor:
			rows.append({"domain": "artifact", "number": number, "at_ms": int(job.started_ms), "amount": int(job.qi_spent)})
		if job.get("method", {}).get("guide") == actor:
			rows.append({"domain": "artifact", "number": number, "at_ms": int(job.started_ms), "amount": int(job.method.guide_qi)})
	var soul_jobs: Array = domain.world.soul_vessels.events.duplicate()
	soul_jobs.append_array(domain.world.soul_vessels.active.values())
	for job: Dictionary in soul_jobs:
		if job.actor == actor:
			rows.append({"domain": "soul", "number": domain.number(str(job.get("action", job.id))), "at_ms": int(job.started_ms), "amount": int(job.qi_spent)})
	var conflicts: Variant = domain.world.get("conflicts")
	if conflicts != null:
		rows.append_array(conflicts.qi_spending(actor))
	var practice: Variant = domain.world.get("capability_practice")
	if practice != null: rows.append_array(practice.qi_spending(actor))
	return rows


static func _charge_ledger(data: Dictionary, domain: RefCounted) -> bool:
	for id: String in data.charge_baselines:
		var baseline: Dictionary = data.charge_baselines[id]
		var item: Dictionary = domain.world.artifacts.objects[id]
		var state: Dictionary = {"charge": int(baseline.charge), "damage": int(baseline.damage)}
		var steps: Array[Dictionary] = []
		for event: Dictionary in domain.world.artifacts.events:
			if event.object == id and domain.number(str(event.id)) >= int(baseline.artifact_floor):
				if int(event.at_ms) < int(baseline.at_ms):
					return false
				steps.append({"floor": domain.number(str(event.id)), "kind": "artifact", "order": 0, "record": event})
		for record: Dictionary in data.records.values():
			if record.object == id and record.target == "stone" and record.result == "success":
				if int(record.artifact_floor) < int(baseline.artifact_floor):
					return false
				steps.append({"floor": int(record.artifact_floor), "kind": "source", "order": domain.number(str(record.id)), "record": record})
		# Source output committed while artifact.next_id was F precedes the
		# next artifact event allocated F. Multiple outputs use original IDs.
		steps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.floor) < int(b.floor) or int(a.floor) == int(b.floor) and (a.kind == "source" and b.kind == "artifact" or a.kind == b.kind and int(a.order) < int(b.order)))
		var prior_ms: int = int(baseline.at_ms)
		for step: Dictionary in steps:
			var record: Dictionary = step.record
			var at_ms: int = int(record.finished_ms) if step.kind == "source" else int(record.at_ms)
			if at_ms < prior_ms:
				return false
			prior_ms = at_ms
			if step.kind == "source":
				if int(state.damage) >= int(domain.world.artifacts.definitions.types[item.definition].damage_max) or int(state.charge) != int(record.before):
					return false
				state.charge = int(record.after)
			elif not _artifact_effect(state, record, item, domain):
				return false
		if int(state.charge) != int(item.charge) or int(state.damage) != int(item.damage):
			return false
	return true


static func _artifact_effect(state: Dictionary, event: Dictionary, item: Dictionary, domain: RefCounted) -> bool:
	var shape: Dictionary = domain.world.artifacts.definitions.types[item.definition]
	if event.kind in ["charged", "overcharged", "fractured", "heated", "warmed"] and int(state.damage) >= int(shape.damage_max):
		return false
	match str(event.kind):
		"charged":
			if event.verb != "charge":
				return false
			var gain: int = int(shape.charge_gain)
			if event.has("method"):
				var method: Dictionary = domain.world.heat_methods.methods[event.method.id]
				if int(method.flow) > int(domain.world.heat_methods.definitions.safe_flow):
					return false
				gain = int(domain.world.heat_methods.definitions.flows[str(int(method.flow))].charge) * int(method.pulses)
			state.charge = mini(int(shape.max_charge), int(state.charge) + gain)
		"overcharged":
			if int(state.damage) >= int(shape.unsafe_damage):
				return false
			var gain: int = int(shape.force_charge_gain)
			if event.has("method"):
				var method: Dictionary = domain.world.heat_methods.methods[event.method.id]
				if int(method.flow) <= int(domain.world.heat_methods.definitions.safe_flow):
					return false
				gain = int(domain.world.heat_methods.definitions.flows[str(int(method.flow))].charge) * int(method.pulses)
			elif event.verb != "force":
				return false
			state.damage = mini(int(shape.damage_max), int(state.damage) + int(shape.force_damage))
			state.charge = mini(int(shape.max_charge), int(state.charge) + gain)
		"fractured":
			if int(state.damage) < int(shape.unsafe_damage):
				return false
			if event.has("method"):
				if int(domain.world.heat_methods.methods[event.method.id].flow) <= int(domain.world.heat_methods.definitions.safe_flow):
					return false
			elif event.verb != "force":
				return false
			state.damage = int(shape.damage_max)
			state.charge = 0
		"heated":
			var recipe: Dictionary = SimArtifacts.heat_recipe(shape, str(event.verb))
			if recipe.is_empty() or int(state.charge) < int(recipe.heat_cost):
				return false
			state.charge = int(state.charge) - int(recipe.heat_cost)
		"warmed":
			if int(state.charge) < int(shape.warming_charge):
				return false
			state.charge = int(state.charge) - int(shape.warming_charge)
		"failed":
			# An unsafe method can damage a sound but already-full stone before
			# reporting no gain. This is an original apply_charge side effect.
			if event.has("method") and int(state.damage) < int(shape.damage_max):
				var method: Dictionary = domain.world.heat_methods.methods[event.method.id]
				if int(method.flow) > int(domain.world.heat_methods.definitions.safe_flow):
					if int(state.damage) >= int(shape.unsafe_damage) or int(state.charge) != int(shape.max_charge):
						return false
					state.damage = mini(int(shape.damage_max), int(state.damage) + int(shape.force_damage))
	return true
