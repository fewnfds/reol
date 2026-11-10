extends RefCounted
## Paid practice exercises original bodies, shared time, geometry and qi ledger.

const Fixtures = preload("res://tests/sim/test_conflicts.gd")
const Schema = preload("res://scripts/sim/capability_practice_schema.gd")
const ARENA := Vector2(3232.0, 3232.0)
var _fixtures := Fixtures.new()


class PracticeMap extends WorldMapData:
	var cover: Dictionary = {}


	func get_terrain(cell: Vector2i) -> int:
		return TERRAIN_ROCK if cover.has(cell) else TERRAIN_GRASS


	func get_elevation(_cell: Vector2i) -> int:
		return 0


	func independent_copy() -> WorldMapData:
		var copy := PracticeMap.new()
		copy.cover = cover.duplicate(true)
		return copy


class HealthPermission extends SimHealth:
	## Isolates a health permission becoming unavailable, without inventing
	## wound records. A separate scenario below produces a genuine sourced hit.
	var blocked: bool = false


	func can_fight(actor: String) -> bool:
		return not blocked and super.can_fight(actor)


func run(runner: Object) -> void:
	_definitions(runner)
	_prerequisites_and_costs(runner)
	_actual_lesson_and_completion(runner)
	_npc_and_distant_owners(runner)
	for cause: String in ["health", "occupied", "blocked", "control_lost", "manual_override", "displaced"]:
		_midwalk_stop(runner, cause)
	_actual_harm_interrupts(runner)
	_source_then_same_ms_practice(runner)
	_shape_and_joint_rejections(runner)
	print("SCENARIO capability practice: actual lesson prerequisites, one original payment, millisecond completion, JSON/fine/coarse continuation, two-region NPCs, safe interrupted motion and genuine impact, original source allocation, atomic forged-candidate rejection")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _fixtures._world(runner)
	if world == null:
		return null
	world.bind_map_data(PracticeMap.new())
	_fixtures._put(world, "chen_shouzhuo", ARENA)
	return world


func _canonical(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _restore(runner: Object, world: RegionalSimulation, label: String) -> RegionalSimulation:
	var before: String = _canonical(world.to_dict())
	var candidate: RegionalSimulation = _world(runner)
	if candidate == null:
		return null
	candidate.bind_map_data(world.map_data.independent_copy())
	var accepted: bool = candidate.restore(JSON.parse_string(before))
	runner.assert_true(accepted, label + " accepts the actual JSON candidate")
	runner.assert_eq(_canonical(world.to_dict()), before, label + " does not mutate the source world")
	if not accepted:
		return null
	runner.assert_eq(_canonical(candidate.to_dict()), before, label + " restores every original domain exactly")
	return candidate


func _reject(runner: Object, world: RegionalSimulation, bad: Dictionary, label: String) -> void:
	var candidate: RegionalSimulation = _world(runner)
	if candidate == null:
		return
	candidate.bind_map_data(world.map_data.independent_copy())
	var original: String = _canonical(world.to_dict())
	var before: String = _canonical(candidate.to_dict())
	var input: String = _canonical(bad)
	runner.assert_true(not candidate.restore(bad), label + " is rejected by the joint candidate")
	runner.assert_eq(_canonical(candidate.to_dict()), before, label + " commits no partial world")
	runner.assert_eq(_canonical(bad), input, label + " does not repair the passed candidate")
	runner.assert_eq(_canonical(world.to_dict()), original, label + " leaves the original world intact")


func _definitions(runner: Object) -> void:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/capability_practice.json"))
	runner.assert_true(SimCapabilityPractice.valid_definitions(rules), "bounded practice definition is valid")
	for fault: String in ["odd_steps", "free_qi", "bool_stamina", "zero_prepare", "unknown_prerequisite", "duplicate_direction", "boolean_direction", "excess_speed", "empty_budget"]:
		var bad: Dictionary = rules.duplicate(true)
		match fault:
			"odd_steps": bad.nodes.mobile_guard.steps = 3
			"free_qi": bad.nodes.mobile_guard.qi = 0
			"bool_stamina": bad.nodes.mobile_guard.stamina = true
			"zero_prepare": bad.nodes.mobile_guard.prepare_ms = 0
			"unknown_prerequisite": bad.nodes.mobile_guard.requires = "unknown_spell"
			"duplicate_direction": bad.nodes.mobile_guard.directions[1] = bad.nodes.mobile_guard.directions[0].duplicate()
			"boolean_direction": bad.nodes.mobile_guard.directions[0] = [true, 0]
			"excess_speed": bad.nodes.mobile_guard.speed_fraction = 1.01
			"empty_budget": bad.max_records = 0
		runner.assert_true(not SimCapabilityPractice.valid_definitions(bad), "definition rejects " + fault)


func _prerequisites_and_costs(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var domain: RefCounted = world.capability_practice
	var person: Dictionary = domain.body("chen_shouzhuo")
	var rule: Dictionary = domain.definitions.nodes.mobile_guard
	var qi: int = int(person.qi)
	var stamina: int = int(person.stamina)
	var source: String = _canonical(world.spirit_sources.to_dict())
	runner.assert_true(not domain.begin("player").ok and not domain.begin("absent_actor").ok and not domain.begin("chen_shouzhuo", "invented_node").ok, "opening a node or naming an absent body cannot replace a learned prerequisite")
	runner.assert_true(domain.active.is_empty() and domain.records.is_empty() and domain.next_id == 1, "failed prerequisites allocate no practice history")
	person.qi = int(rule.qi) - 1
	runner.assert_true(not domain.begin("chen_shouzhuo").ok, "insufficient original qi refuses before spending")
	person.qi = qi
	person.stamina = int(rule.stamina) - 1
	runner.assert_true(not domain.begin("chen_shouzhuo").ok, "insufficient original stamina refuses before spending")
	person.stamina = stamina
	world.set_local_action_owner(func(actor: String) -> bool: return actor == "chen_shouzhuo")
	runner.assert_true(not domain.begin("chen_shouzhuo").ok, "actual local motion ownership prevents parallel practice")
	world.set_local_action_owner(Callable())
	var hunger: float = float(person.hunger)
	person.hunger = float(world.regions.home.config.needs.eat_below)
	runner.assert_true(not domain.begin("chen_shouzhuo").ok, "an original immediate personal need takes precedence")
	person.hunger = hunger
	var map: PracticeMap = world.map_data as PracticeMap
	var anchor: Vector2i = SimRouteTravel.cell(person.cell)
	for direction: Array in rule.directions:
		map.cover[anchor + SimRouteTravel.cell(direction)] = true
	runner.assert_true(not domain.begin("chen_shouzhuo").ok, "no safe same-level return leg means no paid start")
	map.cover.clear()
	runner.assert_eq(_canonical(world.spirit_sources.to_dict()), source, "all rejected requests create no qi checkpoint or source effect")
	var response: Dictionary = domain.begin("chen_shouzhuo")
	runner.assert_true(response.ok, "an actually trained original body can begin the paid process")
	if not response.ok:
		return
	runner.assert_eq(person.qi, qi - int(rule.qi), "one accepted process debits original qi once")
	runner.assert_eq(person.stamina, stamina - int(rule.stamina), "one accepted process debits original stamina once")
	runner.assert_eq(world.spirit_sources.qi_baselines.chen_shouzhuo.qi, qi, "checkpoint precedes the exact real debit")
	runner.assert_eq(world.spirit_sources.qi_baselines.chen_shouzhuo.practice_floor, 1, "checkpoint includes the exact first practice cost")
	runner.assert_true(world.conflicts.barriers.is_empty() and world.conflicts.actions.is_empty(), "practice creates neither a spell action nor protective capacity")
	runner.assert_true(world.body_action_owns("chen_shouzhuo") and not world.native_action_allowed("chen_shouzhuo"), "one practice holds the original body against parallel native work")
	var paid: String = _canonical(world.to_dict())
	runner.assert_true(not domain.begin("chen_shouzhuo").ok, "duplicate start does not create a second process")
	runner.assert_eq(_canonical(world.to_dict()), paid, "duplicate start preserves costs, identity and history")
	runner.assert_true(domain.cancel("chen_shouzhuo"), "public cancel ends the genuine paid process")
	runner.assert_eq(person.qi, qi - int(rule.qi), "cancellation retains original qi spending")
	runner.assert_eq(person.stamina, stamina - int(rule.stamina), "cancellation retains original stamina spending")
	runner.assert_true(not domain.learned("chen_shouzhuo") and not domain.cancel("chen_shouzhuo"), "cancellation grants nothing and cannot be charged twice")
	runner.assert_eq(domain.next_boundary_ms(), SimCapabilityPractice.NEVER, "empty practice domain has no polling boundary")
	_restore(runner, world, "cancelled prepare stage")


func _actual_lesson_and_completion(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	_fixtures._pair(world, "chen_shouzhuo", "player")
	var domain: RefCounted = world.capability_practice
	runner.assert_true(world.conflicts.teach("chen_shouzhuo", "player").ok, "original teacher actually starts the missing prerequisite")
	var lesson: Dictionary = world.conflicts.lessons.values()[0]
	var lesson_due: int = int(lesson.due_ms)
	runner.assert_true(world.advance_to_ms(lesson_due - 1), "original lesson reaches one millisecond before completion")
	runner.assert_true(not domain.prerequisite("player", "mobile_guard", world.elapsed_ms) and not domain.begin("player").ok, "partial teaching never grants the advanced prerequisite")
	runner.assert_true(world.advance_to_ms(lesson_due), "actual original lesson completes")
	runner.assert_true(domain.prerequisite("player", "mobile_guard", world.elapsed_ms), "completed original proof enables the same practice API")
	var qi: int = int(domain.body("player").qi)
	var started: Dictionary = domain.begin("player")
	runner.assert_true(started.ok, "actually taught player starts one real paid practice")
	if not started.ok:
		return
	var row: Dictionary = domain.active.player
	var done: int = int(row.complete_ms)
	var start: int = int(row.started_ms)
	runner.assert_true(world.advance_to_ms(start + 12500), "actual practice advances inside the first walking leg")
	runner.assert_true(row.phase == "walk" and not domain.learned("player"), "partial physical practice remains unlearned")
	runner.assert_true(Schema.validate(JSON.parse_string(_canonical(domain.to_dict())), domain), "JSON numeric arrays validate during the real walking phase")
	var copy: RegionalSimulation = _restore(runner, world, "paid partial walking stage")
	if copy == null:
		return
	while world.elapsed_ms < done - 1:
		if not world.advance_to_ms(mini(done - 1, world.elapsed_ms + 733)):
			runner.assert_true(false, "fine practice steps reach the completion boundary")
			return
	runner.assert_true(not domain.learned("player"), "one millisecond before actual completion remains unlearned")
	runner.assert_true(world.advance_to_ms(done) and copy.advance_to_ms(done), "fine source and coarse restored worlds finish the real same process")
	runner.assert_true(domain.learned("player") and copy.capability_practice.learned("player"), "only completed original stages grant the use")
	runner.assert_eq(domain.learned_at("player"), done, "learned proof retains the exact completion millisecond")
	runner.assert_eq(domain.records[started.id].stopped_ms, done - int(domain.definitions.nodes.mobile_guard.settle_ms), "motion proof ends at the last walking step rather than the last observation")
	runner.assert_eq(_canonical(copy.to_dict()), _canonical(world.to_dict()), "JSON/coarse and fine motion retain exactly the same complete future")
	runner.assert_eq(domain.body("player").qi, qi - int(row.qi_spent), "all phases and resume retain exactly one original qi debit")
	var complete: String = _canonical(world.to_dict())
	runner.assert_true(not domain.begin("player").ok, "mastered node cannot be paid for repeatedly")
	world.capability_practice.settle_at_ms(done)
	runner.assert_eq(_canonical(world.to_dict()), complete, "same-time settlement cannot duplicate completion or its proof")
	_restore(runner, world, "completed actual paid practice")


func _npc_and_distant_owners(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var domain: RefCounted = world.capability_practice
	_fixtures._put(world, "river_chen_shouzhuo", ARENA + Vector2(640.0, 0.0))
	for actor: String in ["chen_shouzhuo", "river_chen_shouzhuo"]:
		domain.body(actor).autonomous = true
		var response: Dictionary = domain.begin(actor)
		runner.assert_true(response.ok, "same paid API accepts original NPC " + actor)
		if not response.ok:
			return
		runner.assert_true(not domain.body(actor).autonomous, "practice temporarily owns only this NPC's original body")
	runner.assert_eq(world.active_region, "", "neither original region needs to be displayed for NPC practice")
	var done: int = int(domain.active.chen_shouzhuo.complete_ms)
	runner.assert_true(world.advance_to_ms(done), "shared remote scheduler completes both actual bodies")
	for actor: String in ["chen_shouzhuo", "river_chen_shouzhuo"]:
		runner.assert_true(domain.learned(actor) and bool(domain.body(actor).autonomous), "NPC learns only from its own completed proof and regains its former autonomy: " + actor)
		runner.assert_eq(domain.qi_spending(actor).size(), 1, "each NPC retains its own one-time cost source")
	runner.assert_true(not domain.learned("player") and not domain.learned("river_player"), "unrelated controlled bodies gain no node from NPC practice")
	_restore(runner, world, "two original distant NPC proofs")


func _midwalk_stop(runner: Object, cause: String) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var gate := HealthPermission.new()
	if cause == "health":
		runner.assert_true(gate.initialize(world, world.health.definitions), "isolated health permission uses original valid health rules")
		world.health = gate
		runner.assert_true(world._bind_settlement(), "test health replacement rebinds the original settlement owners")
	var domain: RefCounted = world.capability_practice
	var person: Dictionary = domain.body("chen_shouzhuo")
	var qi: int = int(person.qi)
	var stamina: int = int(person.stamina)
	var response: Dictionary = domain.begin("chen_shouzhuo")
	runner.assert_true(response.ok, cause + " probe starts a genuine paid process")
	if not response.ok:
		return
	var row: Dictionary = domain.active.chen_shouzhuo
	runner.assert_true(world.advance_to_ms(int(row.started_ms) + 12500), cause + " probe actually reaches a partial walking position")
	var stopped: Vector2 = SimRouteTravel.point(person)
	var stopped_ms: int = world.elapsed_ms
	var target: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(row.path[0]))
	runner.assert_true(stopped.distance_to(Vector2(float(row.origin[0]), float(row.origin[1]))) > 1.0 and stopped.distance_to(target) > 1.0, "stop occurs inside a real segment rather than at its anchor or endpoint")
	match cause:
		"health": gate.blocked = true
		"occupied": world.set_local_action_owner(func(actor: String) -> bool: return actor == "chen_shouzhuo")
		"blocked": (world.map_data as PracticeMap).cover[SimRouteTravel.cell(row.path[0])] = true
		"control_lost":
			runner.assert_true(world.embodiment.release_control(world.embodiment.subject_for_actor("chen_shouzhuo"), world.embodiment.carrier_for_source("village_actor", "chen_shouzhuo"), "motion"), "actual embodiment releases the original motion channel")
		"manual_override": runner.assert_true(domain.cancel("chen_shouzhuo", "manual_override"), "public interruption cancels the original active practice")
		"displaced":
			stopped += Vector2(0.0, 8.0)
			_fixtures._put(world, "chen_shouzhuo", stopped)
	if cause != "manual_override":
		runner.assert_eq(domain.next_boundary_ms(), stopped_ms + 1, cause + " requests an immediate next boundary without busy polling")
		runner.assert_true(world.advance_to_ms(stopped_ms + 1), cause + " settles through the real shared scheduler")
	runner.assert_true(not domain.active.has("chen_shouzhuo") and not domain.learned("chen_shouzhuo"), cause + " releases occupation without granting the node")
	var ended: Dictionary = domain.records[response.id]
	runner.assert_eq(ended.reason, cause, cause + " keeps its specific terminal reason")
	runner.assert_eq(ended.stopped_ms, stopped_ms, cause + " retains the actual last walking sample time")
	runner.assert_true(SimRouteTravel.point(person).distance_to(stopped) < 0.01, cause + " does not advance through a newly blocked or unauthorised route")
	runner.assert_eq(person.qi, qi - int(row.qi_spent), cause + " keeps original qi cost")
	runner.assert_eq(person.stamina, stamina - int(row.stamina_spent), cause + " keeps original stamina cost")
	var copy: RegionalSimulation = _restore(runner, world, cause + " cancelled middle walking stage")
	if copy == null:
		return
	# The test-only gate is not a wound. Remove its veto before comparing later
	# healthy life; the genuine injury scenario below keeps its actual wound.
	gate.blocked = false
	world.set_local_action_owner(Callable())
	var deadline: int = int(row.complete_ms)
	runner.assert_true(world.advance_to_ms(deadline) and copy.advance_to_ms(deadline), cause + " can pass the abandoned deadline in both real worlds")
	runner.assert_true(not domain.learned("chen_shouzhuo") and not copy.capability_practice.learned("chen_shouzhuo"), cause + " never becomes learned at the abandoned deadline")
	runner.assert_eq(_canonical(copy.to_dict()), _canonical(world.to_dict()), cause + " has the same full JSON-restored future")


func _actual_harm_interrupts(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	_fixtures._pair(world, "chen_shouzhuo", "shi_tou", Vector2(300.0, 0.0))
	_fixtures._put(world, "su_zhi", ARENA + Vector2(80.0, 0.0))
	var domain: RefCounted = world.capability_practice
	var response: Dictionary = domain.begin("su_zhi")
	runner.assert_true(response.ok, "original noncombatant practitioner begins its own known-guard practice")
	if not response.ok:
		return
	var row: Dictionary = domain.active.su_zhi
	var qi: int = int(domain.body("su_zhi").qi)
	runner.assert_true(world.advance_to_ms(12500), "bystander genuinely walks before another person's encounter")
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "shi_tou").ok and world.conflicts.cast("chen_shouzhuo", "qi_bolt", Vector2.RIGHT).ok, "unrelated actual attacker emits a paid shot through the practicing bystander")
	runner.assert_true(world.advance_to_ms(14500), "original projectile and practice share real contact boundaries")
	runner.assert_true(world.health.combat_burden("su_zhi") > 0, "committed projectile creates the original sourced contusion")
	runner.assert_true(not domain.active.has("su_zhi") and domain.records.has(response.id), "actual harmful contact interrupts the physical practice")
	if not domain.records.has(response.id):
		return
	runner.assert_eq(domain.records[response.id].reason, "struck", "genuine conflict callback keeps its harmful-contact reason")
	runner.assert_true(not domain.learned("su_zhi") and world.conflicts.barriers.is_empty(), "partial practice grants neither the use nor a free combat barrier")
	runner.assert_eq(domain.body("su_zhi").qi, qi, "being interrupted neither refunds nor recharges original practice qi")
	var copy: RegionalSimulation = _restore(runner, world, "genuinely struck middle walking stage")
	if copy != null:
		runner.assert_true(world.advance_to_ms(int(row.complete_ms)) and copy.advance_to_ms(int(row.complete_ms)), "sourced injury and interrupted practice continue beyond the old deadline")
		runner.assert_eq(_canonical(copy.to_dict()), _canonical(world.to_dict()), "actual harm, qi and interrupted movement have the same whole restored future")


func _source_then_same_ms_practice(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var actor: String = "chen_shouzhuo"
	var person: Dictionary = world.capability_practice.body(actor)
	person.qi = int(person.qi) - int(world.spirit_sources.definitions.qi_gain)
	world.regions.home.set_actor_cell(actor, world.spirit_sources.source_cell("hearth_seam"))
	world.invalidate_region("home")
	var initial: int = int(person.qi)
	var source: Dictionary = world.spirit_sources.begin(actor, "hearth_seam", "body", "hearth_stone")
	runner.assert_true(source.ok, "same-ms ledger probe begins a real original finite-source conversion")
	if not source.ok:
		return
	var due: int = int(world.spirit_sources.active[actor].due_ms)
	runner.assert_true(world.advance_to_ms(due), "actual source completes before the new same-ms practice input")
	var receipt: Dictionary = world.spirit_sources.records[source.action]
	var paid: Dictionary = world.capability_practice.begin(actor)
	runner.assert_true(paid.ok, "source-restored body can pay a new practice at the exact completion millisecond")
	if not paid.ok:
		return
	runner.assert_eq(receipt.practice_floor, 1, "source receipt precedes the exact first practice allocation even within the same millisecond")
	runner.assert_eq(person.qi, initial + int(receipt.output) - int(world.capability_practice.definitions.nodes.mobile_guard.qi), "original qi ledger includes the real output and the later exact practice debit")
	var copy: RegionalSimulation = _restore(runner, world, "source completion then same-ms paid practice")
	if copy != null:
		var done: int = int(world.capability_practice.active[actor].complete_ms)
		runner.assert_true(world.advance_to_ms(done) and copy.advance_to_ms(done), "both allocation histories reach actual practice completion")
		runner.assert_eq(_canonical(copy.to_dict()), _canonical(world.to_dict()), "shared source/practice floor produces exactly the same complete future")


func _shape_and_joint_rejections(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var response: Dictionary = world.capability_practice.begin("chen_shouzhuo")
	runner.assert_true(response.ok and world.advance_to_ms(12500), "shape probes use an actual in-progress paid walking process")
	if not response.ok:
		return
	var valid: Dictionary = JSON.parse_string(_canonical(world.capability_practice.to_dict()))
	runner.assert_true(Schema.validate(valid, world.capability_practice), "unmodified JSON walking candidate passes shape")
	for fault: String in ["extra_field", "missing_field", "boolean_number", "boolean_step", "boolean_time", "wrong_cost", "unknown_node", "wrong_phase", "wrong_path", "boolean_direction", "bad_segment", "bad_milestone", "early_due", "id_gap"]:
		var bad: Dictionary = valid.duplicate(true)
		var row: Dictionary = bad.active.chen_shouzhuo
		match fault:
			"extra_field": row["learned"] = true
			"missing_field": row.erase("stopped_ms")
			"boolean_number": row.number = true
			"boolean_step": row.step_index = false
			"boolean_time": row.started_ms = false
			"wrong_cost": row.qi_spent = int(row.qi_spent) + 1
			"unknown_node": row.node = "invented_node"
			"wrong_phase": row.phase = "settle"
			"wrong_path": row.path[0][0] = int(row.path[0][0]) + 1
			"boolean_direction": row.direction = [true, 0]
			"bad_segment": row.segment_from[0] = float(row.segment_from[0]) + 4.0
			"bad_milestone": row.milestones[0].at_ms = int(row.milestones[0].at_ms) + 1
			"early_due": row.due_ms = int(row.due_ms) - 1
			"id_gap": bad.next_id = int(bad.next_id) + 1
		runner.assert_true(not Schema.validate(bad, world.capability_practice), "shape rejects " + fault)
	for fault: String in ["body_qi", "missing_checkpoint", "skipped_cost", "missing_start_event", "missing_milestone", "wrong_body_point", "modern_old_source"]:
		var bad: Dictionary = JSON.parse_string(_canonical(world.to_dict()))
		var row: Dictionary = bad.capability_practice.active.chen_shouzhuo
		match fault:
			"body_qi": bad.regions.home.actors.chen_shouzhuo.qi = int(bad.regions.home.actors.chen_shouzhuo.qi) + 1
			"missing_checkpoint": bad.spirit_sources.qi_baselines.erase("chen_shouzhuo")
			"skipped_cost": bad.spirit_sources.qi_baselines.chen_shouzhuo.practice_floor = 2
			"missing_start_event": row.start_event = "event:invented"
			"missing_milestone": row.milestones[0].event = "event:invented"
			"wrong_body_point": bad.regions.home.actors.chen_shouzhuo.position[0] = float(bad.regions.home.actors.chen_shouzhuo.position[0]) + 4.0
			"modern_old_source":
				bad.spirit_sources.version = 2
				for baseline: Dictionary in bad.spirit_sources.qi_baselines.values(): baseline.erase("practice_floor")
		_reject(runner, world, bad, "forged practice " + fault)
