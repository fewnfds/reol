extends RefCounted
## Personal water stays reserved in the original pocket through real labor.

const Fixtures = preload("res://tests/sim/test_village_simulation.gd")
const IRRIGATE: Dictionary = {"label": "浇灌野药", "kind": "irrigate", "target": "garden", "resource": "herb_slope", "item": "water", "amount": 1, "minutes": 2, "contribution": 0}
const BAG: String = "actor:player"
var _fixtures: RefCounted = Fixtures.new()


func run(runner: Object) -> void:
	_test_definition_contract(runner)
	_test_reservation_labor_and_completion(runner)
	_test_cancellation_and_control(runner)
	_test_lost_reservation(runner)
	_test_rain_during_work(runner)
	_test_public_water_and_private_mixture(runner)
	_test_inflight_snapshot(runner)
	_test_bad_snapshot_rejection(runner)
	print("SCENARIO irrigation: original personal-water reservation, real travel/work, cancellation and custody, zero credit, in-flight continuation and strict candidate rejection")


func _make(runner: Object, soil_mode: String = "dry") -> VillageSimulation:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "irrigation fixture content loads: " + str(content.errors))
		return null
	# Dry soil is an explicit starting rule for this scenario, not a mutation of
	# an already enabled process or an invented irrigation receipt.
	var ecology: Dictionary = content.land_resources.types.wild_herbs.ecology
	ecology.initial_water = 0 if soil_mode == "dry" else int(ecology.soil_capacity) - (1 if soil_mode == "almost_full" else 0)
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/village.json"))
	settings.actions["irrigate_herb"] = IRRIGATE.duplicate(true)
	settings.scenario.helpers = []
	var cells: Dictionary = {}
	var index: int = 0
	for id: String in settings.actor_profiles:
		settings.actor_profiles[id]["autonomous"] = false
		cells[id] = [100 + index, 100]
		index += 1
	var places: Dictionary = {}
	for entry: Dictionary in settings.place_defs:
		places[entry.id] = {"label": entry.label, "cell": [100 + int(entry.offset[0]), 100 + int(entry.offset[1])]}
	var sim := VillageSimulation.new()
	if not sim.initialize(content, settings, cells, places):
		runner.assert_true(false, "irrigation fixture initializes: " + str(sim.errors))
		return null
	sim.set_navigation(_fixtures._manhattan_path)
	runner.assert_true(sim.land_resources.set_ecology_conditions("herb_slope", sim.elapsed_ms, 200, soil_mode == "almost_full"), "the fixture caches its explicit warm/rain condition for future intervals")
	return sim


func _state(sim: VillageSimulation) -> String:
	return _canonical(sim.to_dict())


func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)


func _irrigated(sim: VillageSimulation) -> int:
	return int(sim.land_resources.sources.herb_slope.ecology.irrigated)


func _work(sim: VillageSimulation, runner: Object) -> bool:
	var deadline: int = sim.elapsed_ms + 3600000
	while not sim.actors.player.active.is_empty() and sim.actors.player.active.phase == "travel" and sim.elapsed_ms < deadline:
		if not sim.advance_to_ms(mini(deadline, sim.next_boundary_ms())):
			break
	var reached: bool = not sim.actors.player.active.is_empty() and sim.actors.player.active.phase == "work"
	runner.assert_true(reached, "the original route reaches the herb source before irrigation work begins")
	return reached


func _test_definition_contract(runner: Object) -> void:
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/village.json"))
	settings.actions["irrigate_herb"] = IRRIGATE.duplicate(true)
	runner.assert_true(SimSchema.validate_config(settings), "the finite private-water irrigation definition passes the original action schema")
	for field: String in IRRIGATE:
		var missing: Dictionary = settings.duplicate(true)
		missing.actions.irrigate_herb.erase(field)
		runner.assert_true(not SimSchema.validate_config(missing), "irrigation requires its declared field: " + field)
	for change: Dictionary in [{"source": "well"}, {"target": "well"}, {"resource": "spring"}, {"resource": "absent"}, {"item": "herb"}, {"amount": 0}, {"amount": 1.5}, {"minutes": 0}, {"minutes": 1.5}, {"contribution": 1}, {"outputs": {"herb": 1}}]:
		var changed: Dictionary = settings.duplicate(true)
		for field: String in change:
			changed.actions.irrigate_herb[field] = change[field]
		runner.assert_true(not SimSchema.validate_config(changed), "irrigation rejects a foreign source, target, material, reward or malformed duration: " + str(change))


func _test_reservation_labor_and_completion(runner: Object) -> void:
	var sim: VillageSimulation = _make(runner)
	if sim == null:
		return
	sim.inventory.containers[BAG]["water"] = 2
	var energy: float = float(sim.actors.player.energy)
	runner.assert_true(sim.submit_action("player", "irrigate_herb"), "actual private water starts original bodily irrigation")
	var action: Dictionary = sim.actors.player.active
	if action.is_empty():
		return
	var reservation: String = str(action.id) + ":water"
	var operation: String = str(action.id) + ":irrigate"
	runner.assert_eq(action.reservations, [reservation], "irrigation has exactly the original action's water reservation")
	runner.assert_true(not bool(action.carrying), "irrigation does not masquerade as a picked-up public consignment")
	runner.assert_eq(sim.inventory.reservations[reservation], {"container": BAG, "item": "water", "amount": 1, "owner_id": "player"}, "the reserved water is in this actor's original pocket")
	runner.assert_eq(sim.inventory.quantity(BAG, "water"), 2, "beginning travel does not consume or transfer private water")
	runner.assert_eq(sim.inventory.available(BAG, "water"), 1, "only the reserved personal unit is protected from other uses")
	runner.assert_true(not sim.inventory.consume(str(action.id) + ":competing", BAG, "water", 2), "another use cannot consume the reserved unit")
	runner.assert_true(not sim.submit_action("player", "rest"), "the same original body cannot simultaneously take another native job")
	var motion := SimLocalMotion.new()
	motion.bind_body(sim.actors.player)
	runner.assert_true(not motion.begin_sidestep(sim.elapsed_ms, Vector2.UP, sim.actors.player), "the original local action cannot overlap irrigation's bodily work")
	runner.assert_true(SimSnapshotSchema.validate(sim.to_dict(), sim._content), "travel with a personal-pocket reservation is save-valid")
	if not _work(sim, runner):
		return
	action = sim.actors.player.active
	runner.assert_true(not bool(action.carrying) and action.reservations == [reservation], "arrival retains the same private reservation throughout labor")
	runner.assert_eq(int(action.due_ms) - int(action.segment_started_ms), 120000, "two actual minutes of labor start only on arrival")
	runner.assert_true(SimSnapshotSchema.validate(sim.to_dict(), sim._content), "working without a fictitious carrying flag is save-valid")
	runner.assert_true(sim.advance_to_ms(int(action.due_ms) - 1), "the body reaches one millisecond before completion")
	runner.assert_true(not sim.inventory.operations.has(operation) and _irrigated(sim) == 0, "incomplete work neither consumes water nor irrigates the source")
	runner.assert_eq(sim.inventory.quantity(BAG, "water"), 2, "the protected unit stays in the original pocket until completion")
	runner.assert_true(sim.advance_to_ms(int(action.due_ms)), "the actual completion boundary commits irrigation")
	runner.assert_true(sim.actors.player.active.is_empty() and sim.inventory.reservations.is_empty(), "completed work releases the body and its water reservation")
	runner.assert_eq(sim.inventory.quantity(BAG, "water"), 1, "completion spends exactly one original private water unit")
	runner.assert_eq(sim.inventory.operations.get(operation, {}), {"kind": "consume", "container": BAG, "item": "water", "amount": 1}, "the water has exactly one native consume source receipt")
	runner.assert_true(_irrigated(sim) > 0 and int(sim.land_resources.sources.herb_slope.ecology.water) > 0, "the same completed action puts finite water into the original source's soil")
	runner.assert_true(float(sim.actors.player.energy) < energy, "travel and labor use the original body's energy and time")
	runner.assert_true(sim.actors.player.receipts.is_empty() and sim.institutions.balance("sect", "player") == 0, "personal plant care does not grant public work credit")
	var after: String = _state(sim)
	sim._executor.settle("player")
	runner.assert_eq(_state(sim), after, "settling completed work again cannot duplicate input, cost or results")
	runner.assert_true(SimSnapshotSchema.validate(sim.to_dict(), sim._content), "completed water and soil provenance remain save-valid")


func _test_cancellation_and_control(runner: Object) -> void:
	for stage: String in ["travel", "work", "route_start", "route_lost", "control_lost"]:
		var sim: VillageSimulation = _make(runner)
		if sim == null:
			return
		sim.inventory.containers[BAG]["water"] = 1
		var energy: float = float(sim.actors.player.energy)
		if stage == "route_start":
			sim.set_navigation(func(_from: Vector2i, _to: Vector2i) -> Array[Vector2i]: return [])
			runner.assert_true(not sim.submit_action("player", "irrigate_herb"), "an unreachable herb source refuses the actual route")
		else:
			runner.assert_true(sim.submit_action("player", "irrigate_herb"), "cancellation scenario starts actual irrigation: " + stage)
			if sim.actors.player.active.is_empty():
				continue
			if stage == "work":
				if not _work(sim, runner):
					continue
				sim.advance_to_ms(sim.elapsed_ms + 60000)
			elif stage == "route_lost":
				sim.set_navigation(_fixtures._manhattan_path, func(_from: Vector2i, _step: Vector2i) -> bool: return false)
				sim.advance_to_ms(sim.elapsed_ms + 1)
			elif stage == "control_lost":
				sim.set_control_guard(func(_actor: String, _channel: String) -> bool: return false)
				sim.advance_to_ms(sim.elapsed_ms + 1)
			else:
				sim.advance_to_ms(sim.elapsed_ms + 117)
			sim.cancel_action("player")
		runner.assert_true(sim.actors.player.active.is_empty() and sim.inventory.reservations.is_empty(), "cancellation or inability releases the original body and water: " + stage)
		runner.assert_eq(sim.inventory.quantity(BAG, "water"), 1, "uncompleted irrigation preserves the actual water: " + stage)
		runner.assert_eq(_irrigated(sim), 0, "uncompleted irrigation grants no soil input: " + stage)
		if stage == "work":
			runner.assert_true(sim.elapsed_ms >= 60000 and float(sim.actors.player.energy) < energy, "cancelling labor does not refund its elapsed time or original energy")
		runner.assert_true(SimSnapshotSchema.validate(sim.to_dict(), sim._content), "cancelled irrigation is a coherent modern snapshot: " + stage)


func _test_lost_reservation(runner: Object) -> void:
	var sim: VillageSimulation = _make(runner)
	if sim == null:
		return
	sim.inventory.containers[BAG]["water"] = 1
	runner.assert_true(sim.submit_action("player", "irrigate_herb"), "lost-reservation scenario starts actual irrigation")
	if not _work(sim, runner):
		return
	var action: Dictionary = sim.actors.player.active
	var operation: String = str(action.id) + ":irrigate"
	sim.inventory.release(str(action.reservations[0]))
	sim.advance_to_ms(int(action.due_ms))
	runner.assert_true(sim.actors.player.active.is_empty() and sim.inventory.reservations.is_empty(), "a lost reservation fails to a terminal body state")
	runner.assert_true(not sim.inventory.operations.has(operation) and _irrigated(sim) == 0, "failed source preflight cannot partially spend water or wet soil")
	runner.assert_eq(sim.inventory.quantity(BAG, "water"), 1, "failed atomic completion leaves the original water intact")
	runner.assert_true(SimSnapshotSchema.validate(sim.to_dict(), sim._content), "failed completion leaves a restorable world")


func _test_public_water_and_private_mixture(runner: Object) -> void:
	var sim: VillageSimulation = _make(runner)
	if sim == null:
		return
	sim.inventory.containers[BAG]["water"] = 0
	runner.assert_true(not sim.submit_action("player", "irrigate_herb"), "nearby public water does not replace absent private water")
	runner.assert_true(sim.inventory.reservations.is_empty() and _irrigated(sim) == 0, "rejected start does not reserve public goods or wet soil")
	var well: Array = sim.places.well.cell
	sim.set_actor_cell("player", Vector2i(int(well[0]), int(well[1])))
	runner.assert_true(sim.submit_action("player", "deliver_water"), "the original public hauling action can pick up its own real consignment")
	var deadline: int = sim.elapsed_ms + 3600000
	while not sim.actors.player.active.is_empty() and not bool(sim.actors.player.active.carrying) and sim.elapsed_ms < deadline:
		sim.advance_to_ms(mini(deadline, sim.next_boundary_ms()))
	sim.cancel_action("player")
	var held: int = sim.inventory.entrusted(BAG, "water")
	runner.assert_true(held > 0 and sim.inventory.available(BAG, "water") == 0, "cancelled public water remains physically held with its disposition limit")
	var custody: String = _canonical(sim.inventory.custody)
	runner.assert_true(not sim.submit_action("player", "irrigate_herb"), "holding public water does not authorize its private irrigation")
	runner.assert_eq(sim.inventory.quantity(BAG, "water"), held, "refused irrigation cannot appropriate the cancelled consignment")
	# A second fixture input is explicitly private; it coexists with the public
	# batch in the same container instead of rewriting the public responsibility.
	sim.inventory.containers[BAG]["water"] = held + 1
	runner.assert_true(sim.submit_action("player", "irrigate_herb"), "one additional private unit can be reserved alongside public water")
	if not _work(sim, runner):
		return
	sim.advance_to_ms(int(sim.actors.player.active.due_ms))
	runner.assert_eq(sim.inventory.quantity(BAG, "water"), held, "only the separate private unit is used on completion")
	runner.assert_eq(sim.inventory.entrusted(BAG, "water"), held, "the original public batch retains its exact disposition limit")
	runner.assert_eq(_canonical(sim.inventory.custody), custody, "plant care never rewrites public provenance or settles its responsibility")
	runner.assert_true(SimSnapshotSchema.validate(sim.to_dict(), sim._content), "public and private water stay jointly restorable after care")


func _test_rain_during_work(runner: Object) -> void:
	var full: VillageSimulation = _make(runner, "full")
	var wetting: VillageSimulation = _make(runner, "almost_full")
	if full == null or wetting == null:
		return
	full.inventory.containers[BAG]["water"] = 1
	runner.assert_true(not full.land_resources.can_irrigate("herb_slope") and not full.submit_action("player", "irrigate_herb"), "already saturated soil refuses unnecessary new work")
	runner.assert_true(full.inventory.reservations.is_empty() and full.inventory.quantity(BAG, "water") == 1, "refused saturated-soil work leaves the private water unreserved and intact")
	wetting.inventory.containers[BAG]["water"] = 1
	runner.assert_true(wetting.submit_action("player", "irrigate_herb"), "soil with remaining capacity accepts real care before later rain")
	if not _work(wetting, runner):
		return
	var action: Dictionary = wetting.actors.player.active
	var operation: String = str(action.id) + ":irrigate"
	wetting.advance_to_ms(int(action.due_ms) - 1)
	runner.assert_true(not wetting.land_resources.can_irrigate("herb_slope"), "actual cached rain can fill the soil while the original labor is in progress")
	wetting.advance_to_ms(int(action.due_ms))
	runner.assert_true(wetting.actors.player.active.is_empty() and wetting.inventory.operations.has(operation), "completion still records the actual input and its overflow instead of inventing a refund")
	runner.assert_eq(wetting.inventory.quantity(BAG, "water"), 0, "completed care spends its reserved private unit exactly once despite intervening rain")
	runner.assert_true(_irrigated(wetting) > 0 and wetting.inventory.reservations.is_empty(), "intervening rain does not erase the completed care's source or leave its reservation hanging")
	runner.assert_true(SimSnapshotSchema.validate(wetting.to_dict(), wetting._content), "saturated completion has a coherent recorded soil and water balance")


func _test_inflight_snapshot(runner: Object) -> void:
	for phase: String in ["travel", "work"]:
		var source: VillageSimulation = _make(runner)
		var target: VillageSimulation = _make(runner)
		if source == null or target == null:
			return
		source.inventory.containers[BAG]["water"] = 1
		runner.assert_true(source.submit_action("player", "irrigate_herb"), "snapshot scenario starts actual personal care: " + phase)
		if phase == "work" and not _work(source, runner):
			continue
		source.advance_to_ms(source.elapsed_ms + (34517 if phase == "work" else 117))
		var saved: Dictionary = JSON.parse_string(JSON.stringify(source.to_dict(), "", true, true))
		runner.assert_eq(saved.actors.player.active.phase, phase, "the saved case is truly in the intended bodily phase")
		runner.assert_true(target.restore(saved), "in-flight original private reservation restores from ordinary JSON: " + phase)
		var future: int = source.elapsed_ms + 900000
		runner.assert_true(source.advance_to_ms(future) and target.advance_to_ms(future), "both original and re-created bodies reach the same future")
		runner.assert_eq(_state(target), _state(source), "restored routes, water cost, soil and complete village continue identically: " + phase)


func _test_bad_snapshot_rejection(runner: Object) -> void:
	var sim: VillageSimulation = _make(runner)
	if sim == null:
		return
	sim.inventory.containers[BAG]["water"] = 2
	runner.assert_true(sim.submit_action("player", "irrigate_herb"), "candidate tests start the original labor")
	if not _work(sim, runner):
		return
	sim.advance_to_ms(sim.elapsed_ms + 34517)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(sim.to_dict(), "", true, true))
	var original: String = _state(sim)
	for damage: String in ["public_source", "other_owner", "missing_reservation", "renamed_reservation", "wrong_amount", "pretend_carrying", "shortened_work", "future_start", "wrong_place", "missing_facing"]:
		var bad: Dictionary = saved.duplicate(true)
		var action: Dictionary = bad.actors.player.active
		var id: String = str(action.reservations[0])
		match damage:
			"public_source": bad.inventory.reservations[id].container = "well"
			"other_owner": bad.inventory.reservations[id].owner_id = "su_zhi"
			"missing_reservation":
				action.reservations.clear()
				bad.inventory.reservations.erase(id)
			"renamed_reservation":
				bad.inventory.reservations[str(action.id) + ":renamed"] = bad.inventory.reservations[id]
				bad.inventory.reservations.erase(id)
				action.reservations[0] = str(action.id) + ":renamed"
			"wrong_amount": bad.inventory.reservations[id].amount = 2
			"pretend_carrying": action.carrying = true
			"shortened_work": action.due_ms = int(action.due_ms) - 1
			"future_start": action.started_ms = int(bad.elapsed_ms) + 1
			"wrong_place": action.destination = "well"
			"missing_facing": bad.actors.player.erase("facing")
		var candidate: String = _canonical(bad)
		runner.assert_true(not sim.restore(bad), "malformed irrigation candidate is rejected: " + damage)
		runner.assert_eq(_state(sim), original, "rejected irrigation snapshot leaves the entire live village intact: " + damage)
		runner.assert_eq(_canonical(bad), candidate, "validation cannot repair or mutate its input candidate: " + damage)
