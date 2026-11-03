extends RefCounted
## An original resident sees and speaks before deciding to interrupt real work.

const Loans = preload("res://tests/sim/test_source_loan.gd")
const Support = preload("res://tests/sim/spirit_source_test_support.gd")
const Rooms = preload("res://tests/sim/test_workplaces.gd")
const GUARD: String = "shi_tou"
const SOURCE: String = "hearth_seam"
const STONE: String = "hearth_stone"
var _loans := Loans.new()


class CareMap extends WorldMapData:
	var cover: Dictionary = {}
	var levels: Dictionary = {}


	func get_terrain(cell: Vector2i) -> int:
		return TERRAIN_ROCK if cover.has(cell) else TERRAIN_GRASS


	func get_elevation(cell: Vector2i) -> int:
		return int(levels.get(cell, 0))


	func independent_copy() -> WorldMapData:
		var copy := CareMap.new()
		copy.cover = cover.duplicate(true)
		copy.levels = levels.duplicate(true)
		return copy


func run(runner: Object) -> void:
	for method: String in ["_explicit_arrangement_and_real_attendance", "_existing_work_and_needs_take_priority", "_unseen_or_unheard_use", "_warning_is_communication_not_a_hit", "_cancel_and_source_completion", "_lost_sight_or_ability_stops_escalation", "_finite_arrangement_expiry", "_known_basis_is_personal_communication", "_advance_explanation_binds_only_one_job", "_old_basis_is_not_backend_audit", "_actual_drive_off_interrupts_original_source", "_strict_candidates", "_saved_warning_and_sparse_future", "_native_need_carry_yields_at_one_millisecond", "_strict_explanation_candidates", "_warning_observation_requires_its_own_encounter"]:
		print("SOURCE CARE CASE " + method)
		call(method, runner)
		print("SOURCE CARE CASE DONE " + method)
	print("SCENARIO source care: actual native attendance and prior needs, finite sight/communication, personal basis versus bookkeeping, finite warning, original source cancellation and sourced NPC-initiated conflict, strict saved futures")


func _make(runner: Object, options: Dictionary = {}) -> RegionalSimulation:
	var world: RegionalSimulation = _loans._make(runner, options.get("source_options", {}))
	if world == null:
		return null
	world.bind_map_data(CareMap.new())
	var definitions: Dictionary = world._content.source_care.duplicate(true)
	definitions.merge(options.get("care_rules", {}), true)
	world._content.source_care = definitions
	if not world.source_care.initialize(world, definitions):
		runner.assert_true(false, "care fixture configures its finite rules before any care history exists")
		return null
	var guard: Dictionary = world.regions.home.actors[GUARD]
	guard.autonomous = true
	if options.has("guard_hunger"):
		guard.hunger = float(options.guard_hunger)
	if options.has("guard_energy"):
		guard.energy = float(options.guard_energy)
	if bool(options.get("prior_delivery", false)):
		runner.assert_true(world.regions.home.submit_action(GUARD, "deliver_water"), "care fixture has an actual already accepted native delivery before care is installed")
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/source_care.json"))
	if options.has("duration_ms"):
		for arrangement: Dictionary in scenario.arrangements:
			arrangement.duration_ms = int(options.duration_ms)
	if not world.source_care.spawn_opening(scenario):
		runner.assert_true(false, "care fixture explicitly installs the one finite accepted original-resident arrangement")
		return null
	return world


func _wait_for_attendance(world: RegionalSimulation, runner: Object) -> Dictionary:
	var limit: int = world.elapsed_ms + 900000
	while world.elapsed_ms < limit:
		var active: Dictionary = world.regions.home.actors[GUARD].active
		if active.get("action") == "check_kitchen" and active.get("phase") == "work" and int(active.due_ms) - world.elapsed_ms >= 115000:
			return active
		if not world.advance_to_ms(mini(limit, world.elapsed_ms + 1000)):
			break
	runner.assert_true(false, "finite guard reaches original check_kitchen work through its actual autonomous decision and route")
	return {}


func _start_source(world: RegionalSimulation, runner: Object, offset: Vector2i = Vector2i.ZERO) -> String:
	var cell: Vector2i = SimRouteTravel.cell(world.regions.home.places.kitchen.cell)
	world.regions.home.set_actor_cell("player", cell + offset)
	world.invalidate_region("home")
	var answer: Dictionary = world.spirit_sources.begin("player", SOURCE, "body", STONE)
	runner.assert_true(answer.ok, "original physical source process can begin independently of local recognition: " + str(answer.line))
	return str(world.spirit_sources.active.player.id) if answer.ok else ""


func _warning_fixture(runner: Object, options: Dictionary = {}) -> Dictionary:
	var world: RegionalSimulation = _make(runner, options)
	if world == null:
		return {}
	var attendance: Dictionary = _wait_for_attendance(world, runner)
	if attendance.is_empty():
		return {}
	var source: String = _start_source(world, runner, Vector2i(2, 0))
	if source.is_empty():
		return {}
	var limit: int = world.elapsed_ms + 10000
	while world.source_care.warnings.is_empty() and world.elapsed_ms < limit:
		world.advance_to_ms(world.elapsed_ms + 100)
	runner.assert_eq(world.source_care.warnings.size(), 1, "actual guard's finite observation produces one personally received warning")
	if world.source_care.warnings.is_empty():
		return {}
	return {"world": world, "source": source, "warning": world.source_care.warnings.values()[0], "attendance": attendance}


func _canonical(world: RegionalSimulation) -> String:
	return Support.canonical(world.to_dict())


func _assert_restore(world: RegionalSimulation, runner: Object, options: Dictionary = {}) -> RegionalSimulation:
	var restored: RegionalSimulation = _make(runner, options)
	if restored == null:
		return null
	restored.bind_map_data(world.map_data.independent_copy())
	var accepted: bool = restored.restore(JSON.parse_string(_canonical(world)))
	runner.assert_true(accepted, "independent candidate restores original care, native work, source and causal records")
	if not accepted:
		return null
	runner.assert_eq(_canonical(restored), _canonical(world), "independent restored present retains every original domain and finite private record")
	return restored


func _explicit_arrangement_and_real_attendance(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	if world == null:
		return
	var care: SimSourceCare = world.source_care
	runner.assert_eq(care.arrangements.size(), 1, "one explicit opening arrangement concerns one original guard")
	runner.assert_eq(world.regions.home.config.actor_profiles[GUARD].duty, "deliver_water", "temporary care does not permanently replace the original person's native duty")
	runner.assert_true(world.regions.home.actors[GUARD].active.is_empty(), "opening arrangement creates no immediate fake body action")
	runner.assert_true(care.warnings.is_empty() and care.explanations.is_empty(), "opening care creates no imagined observation, speech or warning")
	var before: String = _canonical(world)
	care.basis_for("player", GUARD)
	care.pending("player")
	runner.assert_eq(_canonical(world), before, "opening care views do not invent observations, choices or social memory")
	var attendance: Dictionary = _wait_for_attendance(world, runner)
	if attendance.is_empty():
		return
	runner.assert_eq(attendance.action, "check_kitchen", "finite care delegates to the existing native action executor")
	var kitchen: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(world.regions.home.places.kitchen.cell))
	runner.assert_true(SimRouteTravel.point(world.regions.home.actors[GUARD]).is_equal_approx(kitchen), "original guard reaches the actual check destination through its native action rather than a duplicate guard node")
	runner.assert_eq(attendance.due_ms - attendance.segment_started_ms, 120000, "actual native check retains its original finite two-minute work duration")
	runner.assert_true(not world.body_action_owns(GUARD), "care intention does not register a second bodily owner alongside native work")
	_assert_restore(world, runner)


func _existing_work_and_needs_take_priority(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner, {"prior_delivery": true})
	if world == null:
		return
	var active: Dictionary = world.regions.home.actors[GUARD].active.duplicate(true)
	world.advance_to_ms(world.elapsed_ms + 1000)
	runner.assert_eq(world.regions.home.actors[GUARD].active.get("id"), active.id, "care does not clear or replace an already accepted original delivery")
	runner.assert_eq(world.regions.home.actors[GUARD].active.get("action"), "deliver_water", "original delivery keeps its own body and route before the care intention")
	for need: String in ["hunger", "energy"]:
		var options: Dictionary = {"guard_hunger": 10.0} if need == "hunger" else {"guard_energy": 10.0}
		world = _make(runner, options)
		if world == null:
			return
		world.advance_to_ms(world.elapsed_ms + 1000)
		runner.assert_eq(world.regions.home.actors[GUARD].active.get("action"), "eat" if need == "hunger" else "rest", "original urgent need wins before finite care: " + need)
		runner.assert_true(world.source_care.warnings.is_empty(), "person addressing an original urgent need does not concurrently enforce care")


func _unseen_or_unheard_use(runner: Object) -> void:
	for condition: String in ["wall", "height", "communication", "away"]:
		var world: RegionalSimulation = _make(runner)
		if world == null:
			return
		if _wait_for_attendance(world, runner).is_empty():
			return
		var kitchen: Vector2i = SimRouteTravel.cell(world.regions.home.places.kitchen.cell)
		if condition == "wall":
			(world.map_data as CareMap).cover[kitchen + Vector2i(1, 0)] = true
		elif condition == "height":
			(world.map_data as CareMap).levels[kitchen + Vector2i(2, 0)] = 1
		elif condition == "communication":
			runner.assert_true(world.embodiment.release_control("subject:" + GUARD, "body:" + GUARD, "communication"), "actual guard loses its communication channel before an unheard request")
		else:
			world.regions.home.cancel_action(GUARD, "fixture_actual_departure")
			world.regions.home.set_actor_cell(GUARD, kitchen + Vector2i(15, 0))
			world.invalidate_region("home")
			runner.assert_true(world.regions.home.submit_action(GUARD, "inspect"), "departed guard really owns another finite native route and task while source work takes place")
		var source: String = _start_source(world, runner, Vector2i(2, 0))
		if source.is_empty():
			return
		var deadline: int = int(world.spirit_sources.active.player.due_ms)
		world.advance_to_ms(deadline)
		runner.assert_true(world.source_care.warnings.is_empty(), "source scheduling alone cannot manufacture a visible and received warning: " + condition)
		runner.assert_true(world.conflicts.conflicts.is_empty(), "unseen or unheard source operation cannot create an omniscient drive-off: " + condition)
		runner.assert_eq(world.spirit_sources.records[source].result, "success", "original physical source work remains possible without remote enforcement: " + condition)
		runner.assert_eq(world.regions.home.actors.player.qi, 14, "invisible operation really changes the original body rather than a mock response")


func _warning_is_communication_not_a_hit(runner: Object) -> void:
	var fixture: Dictionary = _warning_fixture(runner)
	if fixture.is_empty():
		return
	var world: RegionalSimulation = fixture.world
	var warning: Dictionary = fixture.warning
	runner.assert_eq(warning.actor, "player", "warning names the actual observed source operator")
	runner.assert_eq(warning.source_job, fixture.source, "warning names the same actual in-progress source job")
	runner.assert_eq(int(warning.due_ms) - int(warning.started_ms), 90000, "person actually receives the full configured reasonable warning interval")
	runner.assert_eq(warning.status, "active", "warning begins as a real communication rather than an immediate conflict")
	runner.assert_true(world.spirit_sources.active.has("player") and world.spirit_sources.reserved(SOURCE) == 6, "warning preserves the original body process and sole original source reservation")
	runner.assert_eq(world.regions.home.actors.player.qi, 10, "warning grants or deducts no personal energy")
	runner.assert_eq(world.spirit_sources.sources[SOURCE].spent, 0, "warning does not spend the reserved physical source early")
	runner.assert_true(world.conflicts.conflicts.is_empty() and world.conflicts.actions.is_empty(), "received warning itself starts no enemy action or combat cost")
	runner.assert_true(not world.regions.home.social.knowledge.su_zhi.has(warning.event), "private actual warning does not become unrelated residents' automatic knowledge")
	var prior: String = _canonical(world)
	var pending: Array[Dictionary] = world.source_care.pending("player")
	for process: Dictionary in pending:
		world.source_care.observe("player", process)
	world.source_care.basis_for("player", GUARD)
	runner.assert_eq(_canonical(world), prior, "warning/pending/basis views neither reroll, extend grace, communicate nor update evidence")
	var inquiry: Dictionary = world.source_care.inquire("player", GUARD, "hearth_watch")
	runner.assert_true(inquiry.ok, "operator may actually hear the involved guard describe its own finite arrangement")
	prior = _canonical(world)
	var subject: String = world.embodiment.subject_for_actor("player")
	var public_pending: Array[Dictionary] = SimInteractionRequests.pending(world, subject)
	var read_warning: bool = false
	var read_arrangement: bool = false
	for process: Dictionary in public_pending:
		if process.domain != "source_care":
			continue
		var observed: Dictionary = SimInteractionRequests.observe(world, subject, process)
		if process.id == warning.id:
			read_warning = true
			runner.assert_eq(observed.status, "pending", "public request observation retains the actually received warning's standard pending status")
		elif process.id == "hearth_watch":
			read_arrangement = true
			runner.assert_eq(observed.status, "completed", "public request observation retains the actually heard arrangement's standard completed status")
	runner.assert_true(read_warning and read_arrangement, "ordinary public pending exposes both personally known care processes")
	var unknown: Dictionary = {"domain": "source_care", "id": "care:warning:99999", "performer": world.embodiment.subject_for_actor(GUARD)}
	runner.assert_eq(SimInteractionRequests.observe(world, subject, unknown).status, "unconfirmed", "public request observation refuses an unknown care reference without leaking private records")
	runner.assert_eq(_canonical(world), prior, "ordinary public pending and observe preserve world facts, original source work, grace and personal knowledge")
	_assert_restore(world, runner)


func _cancel_and_source_completion(runner: Object) -> void:
	var fixture: Dictionary = _warning_fixture(runner)
	if fixture.is_empty():
		return
	var world: RegionalSimulation = fixture.world
	var warning: Dictionary = fixture.warning
	runner.assert_true(world.spirit_sources.cancel("player"), "warned operator may use the original actual source cancellation")
	world.advance_to_ms(int(warning.due_ms) + 1000)
	runner.assert_eq(world.spirit_sources.records[fixture.source].result, "cancelled", "warning cancellation retains its original actual source record")
	runner.assert_true(warning.status != "active" and warning.conflict == "", "stopped original operation cannot later consume its warning into combat")
	runner.assert_eq(world.spirit_sources.reserved(SOURCE), 0, "stopping releases the single actual source reservation")
	runner.assert_eq(world.spirit_sources.sources[SOURCE].spent, 0, "stopped actual source consumes no physical batch")
	runner.assert_eq(world.regions.home.actors.player.qi, 10, "stopped actual source creates no output")
	runner.assert_true(world.conflicts.conflicts.is_empty(), "warning does not become delayed punishment after actual compliance")
	fixture = _warning_fixture(runner, {"care_rules": {"grace_ms": 119000}})
	if fixture.is_empty():
		return
	world = fixture.world
	warning = fixture.warning
	var due: int = int(world.spirit_sources.active.player.due_ms)
	runner.assert_eq(int(warning.due_ms), due, "configured first actual observation puts this warning deadline at exactly the original source completion millisecond")
	world.advance_to_ms(maxi(due, int(warning.due_ms)) + 100)
	runner.assert_eq(world.spirit_sources.records[fixture.source].result, "success", "original source completion before or at warning deadline takes effect normally")
	runner.assert_eq(world.spirit_sources.sources[SOURCE].spent, 6, "successful original source completion spends one real batch")
	runner.assert_eq(world.regions.home.actors.player.qi, 14, "successful original source output is never clawed back for a narrative fight")
	runner.assert_true(world.conflicts.conflicts.is_empty() and warning.conflict == "", "no already-finished original source job can be escalated at the same or later deadline")


func _lost_sight_or_ability_stops_escalation(runner: Object) -> void:
	for reason: String in ["wall", "needs", "control", "authority", "exhausted"]:
		var options: Dictionary = {"source_options": {"qi": {"player": 10, GUARD: 0}}} if reason == "exhausted" else {}
		var fixture: Dictionary = _warning_fixture(runner, options)
		if fixture.is_empty():
			return
		var world: RegionalSimulation = fixture.world
		var warning: Dictionary = fixture.warning
		var kitchen: Vector2i = SimRouteTravel.cell(world.regions.home.places.kitchen.cell)
		match reason:
			"wall": (world.map_data as CareMap).cover[kitchen + Vector2i(1, 0)] = true
			"needs": world.regions.home.actors[GUARD].hunger = 10.0
			"control": world.embodiment.release_control("subject:" + GUARD, "body:" + GUARD, "action")
			"authority": world.regions.home.institutions.appoint("sect", "steward", "")
		world.invalidate_region("home")
		world.advance_to_ms(int(warning.due_ms) + 100)
		runner.assert_true(warning.status != "active" and warning.conflict == "", "present enforcement conditions are rechecked instead of following stale warning coordinates: " + reason)
		runner.assert_true(world.conflicts.conflicts.is_empty(), "unavailable actual guard opens no fictitious conflict: " + reason)
		runner.assert_eq(world.source_care.warnings.size(), 1, "same original source job cannot be warned again to wash out its ended grace")
		if reason == "needs":
			runner.assert_true(world.regions.home.actors[GUARD].active.get("action") != "check_kitchen", "hungry original guard stops its finite care visit before its warning can escalate")
			var next_decision: int = int(world.regions.home.actors[GUARD].retry_ms)
			world.advance_to_ms(maxi(world.elapsed_ms + 1, next_decision))
			runner.assert_true(world.regions.home.actors[GUARD].active.get("action") == "eat", "actual hungry guard leaves its own care check to address the original need")


func _finite_arrangement_expiry(runner: Object) -> void:
	# The real guard first pursues its existing meal purpose. This finite term
	# lets that original work finish, then expires during the actual warning.
	var options: Dictionary = {"duration_ms": 100000}
	var fixture: Dictionary = _warning_fixture(runner, options)
	if fixture.is_empty():
		return
	var world: RegionalSimulation = fixture.world
	var warning: Dictionary = fixture.warning
	var arrangement: Dictionary = world.source_care.arrangements.values()[0]
	runner.assert_eq(int(arrangement.until_ms) - int(arrangement.started_ms), 100000, "temporary appointment keeps its explicit finite initial term")
	runner.assert_true(world.elapsed_ms < int(arrangement.until_ms) and int(arrangement.until_ms) < int(warning.due_ms), "actual finite attendance and warning occur before the original arrangement expires within the still-running source process")
	world.advance_to_ms(int(warning.due_ms) + 100)
	runner.assert_true(arrangement.status != "active", "temporary care actually expires on common world time")
	runner.assert_true(warning.status != "active" and warning.conflict == "", "expired authorization cannot escalate a still-running original source operation")
	runner.assert_true(world.conflicts.conflicts.is_empty(), "expiry creates no fictitious attacker or remote replacement appointment")
	runner.assert_eq(int(arrangement.until_ms) - int(arrangement.started_ms), 100000, "continued simulation cannot extend the initial appointment until the player returns")
	_assert_restore(world, runner, options)


func _known_basis_is_personal_communication(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	if world == null:
		return
	var note: String = _loans._borrow(world, runner)
	if note.is_empty():
		return
	if _wait_for_attendance(world, runner).is_empty():
		return
	var source: String = _start_source(world, runner, Vector2i(2, 0))
	if source.is_empty():
		return
	world.advance_to_ms(world.elapsed_ms + 1000)
	runner.assert_eq(world.source_care.warnings.size(), 1, "a valid private signature does not automatically become the guard's knowledge")
	var warning: Dictionary = world.source_care.warnings.values()[0]
	var reply: Dictionary = world.source_care.explain("player", GUARD, note)
	runner.assert_true(bool(reply.ok), "operator can explain its own known signed basis while the original source action remains active")
	runner.assert_eq(reply.code, "completed", "first valid attributed signing memory provides a repeatable accepted peaceful route")
	runner.assert_true(world.spirit_sources.active.has("player"), "finite speech uses the communication channel without cancelling original bodily source work")
	runner.assert_true(warning.status != "active" and warning.conflict == "", "guard's actually received accepted explanation resolves its own warning")
	var issue: String = str(world.site_affairs.notes[note].issue_event)
	var heard: Dictionary = world.regions.home.social.knowledge[GUARD].get(issue, {})
	runner.assert_true(not heard.is_empty() and not bool(heard.direct) and heard.source == "player", "guard knows an attributed retelling rather than remotely viewing the public ledger")
	var unchanged: String = _canonical(world)
	world.source_care.explain("player", GUARD, note)
	runner.assert_eq(_canonical(world), unchanged, "same explanation is cached rather than repeatedly rolling or extending the original term")
	Support.finish(runner, world)
	runner.assert_eq(world.site_affairs.notes[note].used, source, "legitimate accepted explanation does not consume a second right outside original source completion")
	runner.assert_true(world.conflicts.conflicts.is_empty(), "legitimate known-and-explained borrowing has a noncombat route")
	_assert_restore(world, runner)


func _advance_explanation_binds_only_one_job(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	if world == null:
		return
	var note: String = _loans._borrow(world, runner)
	if note.is_empty() or _wait_for_attendance(world, runner).is_empty():
		return
	var kitchen: Vector2i = SimRouteTravel.cell(world.regions.home.places.kitchen.cell)
	world.regions.home.set_actor_cell("player", kitchen + Vector2i(2, 0))
	world.invalidate_region("home")
	var reply: Dictionary = world.source_care.explain("player", GUARD, note)
	runner.assert_eq(reply.code, "completed", "actual known signing can be explained before the original physical source job starts")
	if str(reply.id).is_empty():
		return
	var explanation: Dictionary = world.source_care.explanations[reply.id]
	runner.assert_eq(explanation.source_job, "", "advance explanation invents no already-existing physical source job")
	runner.assert_eq(explanation.binding_event, "", "advance speech does not invent a later personal observation")
	var first: String = _start_source(world, runner, Vector2i(2, 0))
	if first.is_empty():
		return
	world.advance_to_ms(world.elapsed_ms + 1000)
	runner.assert_eq(explanation.source_job, first, "original actual sight binds advance explanation to exactly the observed physical job")
	runner.assert_true(not str(explanation.binding_event).is_empty(), "later binding has its own attributed historical evidence instead of rewriting old spoken content")
	runner.assert_true(world.source_care.warnings.is_empty(), "accepted actually bound advance explanation avoids a redundant warning")
	_assert_restore(world, runner)
	Support.finish(runner, world)
	if _wait_for_attendance(world, runner).is_empty():
		return
	var second: String = _start_source(world, runner, Vector2i(2, 0))
	if second.is_empty():
		return
	world.advance_to_ms(world.elapsed_ms + 1000)
	runner.assert_eq(explanation.source_job, first, "an old private explanation never silently transfers from its completed job to another use")
	runner.assert_eq(world.source_care.warnings.size(), 1, "advance explanation cannot grant blanket permission throughout the whole finite care term")
	if not world.source_care.warnings.is_empty():
		runner.assert_eq(world.source_care.warnings.values()[0].source_job, second, "second finite warning concerns the second actually observed original job")
	_assert_restore(world, runner)


func _old_basis_is_not_backend_audit(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	if world == null:
		return
	var note: String = _loans._borrow(world, runner)
	if note.is_empty():
		return
	var kitchen: Vector2i = SimRouteTravel.cell(world.regions.home.places.kitchen.cell)
	(world.map_data as CareMap).cover[kitchen + Vector2i(1, 0)] = true
	var first: String = _start_source(world, runner, Vector2i(2, 0))
	Support.finish(runner, world)
	runner.assert_eq(world.site_affairs.notes[note].used, first, "first unseen physical use really consumes the one official right")
	(world.map_data as CareMap).cover.clear()
	if _wait_for_attendance(world, runner).is_empty():
		return
	var second: String = _start_source(world, runner, Vector2i(2, 0))
	if second.is_empty():
		return
	world.advance_to_ms(world.elapsed_ms + 1000)
	var reply: Dictionary = world.source_care.explain("player", GUARD, note)
	runner.assert_true(bool(reply.ok), "guard may accept the actually retold old signing memory without access to hidden prior-use bookkeeping")
	runner.assert_eq(reply.code, "completed", "unknown past consumption does not turn the guard into a backend auditor of the old signed memory")
	Support.finish(runner, world)
	runner.assert_eq(world.site_affairs.notes[note].used, first, "mistaken personal acceptance never rewrites the original objectively consumed promise")
	runner.assert_eq(world.site_affairs.notes[note].attempts, [first], "unrecognized second physical use is not retroactively assigned to an already consumed note")
	runner.assert_eq(world.regions.home.actors.player.qi, 18, "both real source operations still use original bodily output and actual source reserves")
	runner.assert_true(world.conflicts.conflicts.is_empty(), "guard's limited personal information can create a mistaken peaceful outcome")


func _actual_drive_off_interrupts_original_source(runner: Object) -> void:
	var fixture: Dictionary = _warning_fixture(runner)
	if fixture.is_empty():
		return
	var world: RegionalSimulation = fixture.world
	var warning: Dictionary = fixture.warning
	var original_stamina: int = int(world.regions.home.actors[GUARD].stamina)
	var original_qi: int = int(world.regions.home.actors[GUARD].qi)
	world.advance_to_ms(int(warning.due_ms))
	runner.assert_eq(warning.status, "escalated", "still-visible unresolved original operation permits one finite drive-off at the real deadline")
	runner.assert_true(not str(warning.conflict).is_empty(), "escalated warning names its one original encounter")
	if str(warning.conflict).is_empty():
		return
	var encounter: Dictionary = world.conflicts.conflicts[warning.conflict]
	runner.assert_eq(encounter.initiator, GUARD, "actual guard is the original initiator rather than swapped into a hard-coded responder slot")
	runner.assert_eq(encounter.defender, "player", "original operator remains the actual warned defender")
	runner.assert_eq(world.spirit_sources.records[fixture.source].result, "cancelled", "only actual hostile opening interrupts the original source work")
	runner.assert_eq(int(world.spirit_sources.records[fixture.source].finished_ms), int(warning.due_ms), "real source cancellation and causal hostile opening share one atomic millisecond")
	runner.assert_eq(world.spirit_sources.sources[SOURCE].spent, 0, "interrupted original source spends none of its reserved batch")
	runner.assert_eq(world.spirit_sources.reserved(SOURCE), 0, "atomic hostile interruption releases the original unique source reservation")
	runner.assert_eq(world.regions.home.actors.player.qi, 10, "original defender obtains no unfinished source output")
	world.advance_to_ms(world.elapsed_ms + 700)
	var guard_acted: bool = false
	for action: Dictionary in world.conflicts.actions.values():
		if action.actor == GUARD:
			guard_acted = true
		else:
			runner.assert_true(action.actor != "player", "manual original player is never made to cast by being the encounter's defender")
	runner.assert_true(guard_acted, "autonomous original initiator actually selects and pays for a known method")
	runner.assert_true(int(world.regions.home.actors[GUARD].qi) < original_qi or int(world.regions.home.actors[GUARD].stamina) < original_stamina, "actual guard action retains a real original body cost")
	runner.assert_eq(world.source_care.warnings.size(), 1, "one original source job and warning cannot spawn a repeating attacker")
	_assert_restore(world, runner)


func _strict_candidates(runner: Object) -> void:
	var fixture: Dictionary = _warning_fixture(runner)
	if fixture.is_empty():
		return
	var world: RegionalSimulation = fixture.world
	var id: String = str(fixture.warning.id)
	var snapshot: Dictionary = JSON.parse_string(_canonical(world))
	for fault: String in ["extra", "future", "source", "person", "grace", "event", "conflict"]:
		var forged: Dictionary = snapshot.duplicate(true)
		var warning: Dictionary = forged.source_care.warnings[id]
		match fault:
			"extra": warning["all_sect_hostile"] = true
			"future": warning.started_ms = int(forged.elapsed_ms) + 1
			"source": warning.source_job = "spirit:999999"
			"person": warning.actor = "a_he"
			"grace": warning.due_ms = int(warning.due_ms) + 1000
			"event": warning.event = "event_999999"
			"conflict": warning.conflict = "conflict:encounter:999999"
		var before: String = _canonical(world)
		runner.assert_true(not world.restore(forged), "independent care candidate rejects " + fault)
		runner.assert_eq(_canonical(world), before, "bad care candidate preserves all original live owners and factual state: " + fault)


func _saved_warning_and_sparse_future(runner: Object) -> void:
	var fixture: Dictionary = _warning_fixture(runner)
	if fixture.is_empty():
		return
	var world: RegionalSimulation = fixture.world
	var restored: RegionalSimulation = _assert_restore(world, runner)
	if restored == null:
		return
	var target: int = int(fixture.warning.due_ms) + 1250
	runner.assert_true(world.advance_to_ms(target), "absent region advances through the original warning deadline into real conflict")
	var reached: bool = true
	while restored.elapsed_ms < target:
		reached = restored.advance_to_ms(mini(target, restored.elapsed_ms + 517)) and reached
	runner.assert_true(reached, "fine irregular local updates reach the same original warning and conflict future")
	runner.assert_eq(_canonical(restored), _canonical(world), "care history, source cancellation, NPC action costs and all unrelated original life have the same saved fine/sparse future")


func _native_need_carry_yields_at_one_millisecond(runner: Object) -> void:
	# This starting fullness is established before the finite appointment. The
	# original native hunger law reaches its threshold during the later warning.
	var options: Dictionary = {"guard_hunger": 55.07}
	var fixture: Dictionary = _warning_fixture(runner, options)
	if fixture.is_empty():
		return
	var world: RegionalSimulation = fixture.world
	var warning: Dictionary = fixture.warning
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 123), "real original need accumulation advances to a nonintegral-minute saved boundary")
	runner.assert_true(int(world.regions.home.actors[GUARD].need_carry.hunger) > 0, "native hunger retains its actual nonzero fixed-point remainder before the care interruption")
	var restored: RegionalSimulation = _assert_restore(world, runner, options)
	if restored == null:
		return
	var target: int = int(world.spirit_sources.active.player.due_ms)
	runner.assert_true(world.advance_to_ms(93333), "native care reaches the last millisecond before the actual fixed-point hunger threshold")
	runner.assert_eq(world.regions.home.actors[GUARD].active.get("action"), "check_kitchen", "nonzero carried hunger fraction cannot interrupt the original visit a millisecond early")
	runner.assert_true(world.advance_to_ms(93334), "original needs reach their first actual threshold millisecond")
	runner.assert_true(world.regions.home.actors[GUARD].active.is_empty(), "the original fixed-point hunger threshold, including its carried fraction, ends care at the first real millisecond")
	runner.assert_true(world.spirit_sources.active.has("player") and world.spirit_sources.sources[SOURCE].spent == 0, "guard's real personal need does not cancel or prematurely complete somebody else's source operation")
	runner.assert_true(world.advance_to_ms(target), "one absent-world request processes the native need boundary before source completion")
	var reached: bool = true
	while restored.elapsed_ms < target:
		reached = restored.advance_to_ms(mini(target, restored.elapsed_ms + 517)) and reached
	runner.assert_true(reached, "fine irregular continuation processes the same native need boundary")
	runner.assert_true(warning.status == "cancelled" and warning.conflict == "", "actual personal hunger overrides enforcement without needing a fictitious wound or source cancellation")
	runner.assert_eq(world.spirit_sources.records[fixture.source].result, "success", "remaining physical source work completes after the original guard leaves its care task")
	runner.assert_eq(_canonical(restored), _canonical(world), "nonzero original need carry cannot change actual warning, source or unrelated world futures between fine and sparse stepping")


func _strict_explanation_candidates(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	if world == null:
		return
	var note: String = _loans._borrow(world, runner)
	if note.is_empty() or _wait_for_attendance(world, runner).is_empty():
		return
	var kitchen: Vector2i = SimRouteTravel.cell(world.regions.home.places.kitchen.cell)
	world.regions.home.set_actor_cell("player", kitchen + Vector2i(2, 0))
	world.invalidate_region("home")
	var reply: Dictionary = world.source_care.explain("player", GUARD, note)
	runner.assert_eq(reply.code, "completed", "strict explanation fixture starts with an actual accepted personally known advance explanation")
	if str(reply.id).is_empty():
		return
	if _start_source(world, runner, Vector2i(2, 0)).is_empty():
		return
	world.advance_to_ms(world.elapsed_ms + 1000)
	var saved: Dictionary = JSON.parse_string(_canonical(world))
	for fault: String in ["extra", "actor", "source_event", "binding_event", "source_job", "decision", "accepted", "future", "until", "target", "claim"]:
		var forged: Dictionary = saved.duplicate(true)
		var entry: Dictionary = forged.source_care.explanations[reply.id]
		match fault:
			"extra": entry["all_future_uses"] = true
			"actor": entry.actor = "a_he"
			"source_event": entry.source_event = "event_999999"
			"binding_event": entry.binding_event = ""
			"source_job": entry.source_job = "spirit:999999"
			"decision": entry.decision = "request_999999"
			"accepted": entry.accepted = false
			"future": entry.at_ms = world.elapsed_ms + 1
			"until": entry.until_ms += 1
			"target": entry.target = "stone"
			"claim": entry.claim_event = "event_999999"
		var before: String = _canonical(world)
		runner.assert_true(not world.restore(forged), "independent care candidate refuses an invented personal explanation or binding: " + fault)
		runner.assert_eq(_canonical(world), before, "bad explanation candidate leaves every real live owner and original memory untouched: " + fault)


func _warning_observation_requires_its_own_encounter(runner: Object) -> void:
	var fixture: Dictionary = _warning_fixture(runner)
	if fixture.is_empty():
		return
	var world: RegionalSimulation = fixture.world
	var warning: Dictionary = fixture.warning
	var subject: String = world.embodiment.subject_for_actor("player")
	var unknown: String = world.embodiment.subject_for_actor("su_zhi")
	var process: Dictionary = {"domain": "source_care", "id": str(warning.id), "performer": world.embodiment.subject_for_actor(GUARD)}
	runner.assert_true(world.spirit_sources.cancel("player"), "old-warning observation fixture really stops the original physical source process")
	runner.assert_true(warning.status == "cancelled" and warning.conflict == "" and warning.end_event == "", "actual cancelled source leaves no personal spoken ending or linked care encounter to invent")
	runner.assert_eq(SimInteractionRequests.observe(world, subject, process).status, "pending", "operator remembers receiving an old warning without a later actual communicated conclusion")
	var kitchen: Vector2i = SimRouteTravel.cell(world.regions.home.places.kitchen.cell)
	world.regions.home.set_actor_cell("chen_shouzhuo", kitchen + Vector2i(3, 0))
	world.invalidate_region("home")
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "player").ok, "a different original person starts an actual ordinary encounter unrelated to the ended source job")
	var unrelated_id: String = world.conflicts.conflict_for("player")
	runner.assert_true(not unrelated_id.is_empty(), "unrelated ordinary encounter really owns the old warning recipient now")
	if unrelated_id.is_empty():
		return
	runner.assert_true(world.conflicts.conflicts[unrelated_id].cause.is_empty(), "ordinary encounter has no invented source-care warning cause")
	var before: String = _canonical(world)
	runner.assert_eq(SimInteractionRequests.observe(world, subject, process).status, "pending", "a later unrelated ordinary fight cannot become personal completion evidence for the old cancelled warning")
	runner.assert_eq(SimInteractionRequests.observe(world, unknown, process).status, "unconfirmed", "an uninformed third person cannot learn the old private warning through somebody else's ordinary fight")
	runner.assert_eq(_canonical(world), before, "querying old warning during unrelated combat changes no knowledge, source history or encounter")
	fixture = _warning_fixture(runner)
	if fixture.is_empty():
		return
	world = fixture.world
	warning = fixture.warning
	process = {"domain": "source_care", "id": str(warning.id), "performer": world.embodiment.subject_for_actor(GUARD)}
	runner.assert_true(world.advance_to_ms(int(warning.due_ms)), "second actual source warning reaches its own true hostile opening")
	var care_id: String = str(warning.conflict)
	runner.assert_true(warning.status == "escalated" and not care_id.is_empty(), "actual care warning really links to its own original encounter before observation")
	if care_id.is_empty():
		return
	runner.assert_eq(SimInteractionRequests.observe(world, subject, process).status, "completed", "participant's actual linked care encounter is personal evidence for its warning outcome")
	world.conflicts.cancel("player")
	runner.assert_true(world.conflicts.conflict_for("player").is_empty() and int(world.conflicts.conflicts[care_id].ended_ms) >= 0, "original participant genuinely ends that specific care encounter through the ordinary stop action")
	before = _canonical(world)
	runner.assert_eq(SimInteractionRequests.observe(world, subject, process).status, "completed", "ending the actual care fight cannot erase the participant's firsthand warning outcome")
	runner.assert_eq(SimInteractionRequests.observe(world, unknown, process).status, "unconfirmed", "uninformed third person gains no private warning from the already-ended care fight")
	runner.assert_eq(_canonical(world), before, "re-reading the actual ended encounter preserves original history and personal knowledge")
