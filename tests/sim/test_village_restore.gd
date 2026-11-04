extends RefCounted
## Candidate restoration uses real regional rules and saved facts, without a scene.

const RegionalFixtures = preload("res://tests/sim/test_regional_simulation.gd")
const ConstructionFixtures = preload("res://tests/sim/test_construction.gd")


func run(runner: Object) -> void:
	_test_two_region_snapshots(runner)
	_test_independent_foraging_versions(runner)
	_test_inflight_resource_work(runner)
	_test_inflight_meal_and_rejection(runner)
	_test_cross_domain_scopes(runner)
	print("SCENARIO village candidate: two actual regions, ongoing finite resources and meal, strict failures and cross-domain scopes")


func _test_two_region_snapshots(runner: Object) -> void:
	var fixtures := RegionalFixtures.new()
	var world: RegionalSimulation = fixtures._make_world(runner)
	if world == null:
		return
	for region: String in ["home", "river"]:
		var original: VillageSimulation = world.regions[region]
		var saved: Dictionary = _round_trip(original.to_dict())
		var before: String = _json(saved)
		var actor: String = "player" if region == "home" else "river_player"
		var candidate: VillageSimulation = VillageSimulation.from_snapshot(world._content, saved)
		runner.assert_not_null(candidate, region + " restores independently without an initialized village")
		if candidate == null:
			continue
		runner.assert_eq(_json(candidate.to_dict()), before, region + " restores the same bodies, ledger, sources and clock")
		runner.assert_eq(candidate.institutions.entries.size(), saved.institutions.entries.size(), region + " restores its old entries without issuing new opening credit")
		runner.assert_true(not candidate._navigation.is_valid(), region + " does not inherit a live navigation callback")
		candidate.actors[actor].mood = 11.0
		runner.assert_eq(_json(saved), before, region + " candidate edits cannot change the input snapshot")
		runner.assert_eq(_json(original.to_dict()), before, region + " candidate edits cannot change the original village")
		saved.actors[actor].mood = 22.0
		runner.assert_eq(float(candidate.actors[actor].mood), 11.0, region + " later input edits cannot alter the candidate")


func _test_independent_foraging_versions(runner: Object) -> void:
	var fixtures := RegionalFixtures.new()
	var world: RegionalSimulation = fixtures._make_world(runner)
	if world == null:
		return
	var older: Dictionary = _round_trip(world.regions.home.to_dict())
	var documents: Dictionary = world._content.content_bundle().documents.duplicate(true)
	var path: String = "res://data/definitions/personal_foraging.json"
	var previous: int = int(documents[path].actions.keep_wood.minutes)
	documents[path].actions.keep_wood.minutes = previous + 5
	var newer_content := ReolContentDB.new()
	var loaded: bool = newer_content.load_bundle(ReolContentBundle.from_documents(documents))
	runner.assert_true(loaded, "newer same-ID forage definition loads as a separate content version")
	if not loaded:
		return
	var newer: Dictionary = older.duplicate(true)
	newer.config.actions.keep_wood = newer_content.personal_foraging.actions.keep_wood.duplicate(true)
	runner.assert_true(VillageSimulation.from_snapshot(newer_content, older) == null, "foraging configuration from another content version is rejected")
	var changed: VillageSimulation = VillageSimulation.from_snapshot(newer_content, newer)
	runner.assert_not_null(changed, "newer candidate uses its own matching forage definition")
	var retained: VillageSimulation = VillageSimulation.from_snapshot(world._content, older)
	runner.assert_not_null(retained, "older candidate remains readable after newer content is assembled")
	if changed != null and retained != null:
		runner.assert_eq(int(changed.config.actions.keep_wood.minutes), previous + 5, "new version retains its own forage duration")
		runner.assert_eq(int(retained.config.actions.keep_wood.minutes), previous, "old version retains its own forage duration")
		runner.assert_eq(_json(world.regions.home.to_dict()), _json(older), "constructing both versions leaves the original region intact")


func _test_inflight_resource_work(runner: Object) -> void:
	# Disable managed herb ecology in the established regional fixture. A local
	# candidate has no regional weather sampler, so this isolates finite source
	# work without fabricating a new climate history while it is detached.
	for verb: String in ["keep_wood", "gather_wood"]:
		var fixtures := RegionalFixtures.new()
		var world: RegionalSimulation = fixtures._make_world(runner, false, false, true, false)
		if world == null:
			return
		var original: VillageSimulation = world.regions.home
		var started: bool = original.submit_action("player", verb)
		runner.assert_true(started, verb + " starts the real finite-source action")
		if not started:
			continue
		runner.assert_true(original.advance_to_ms(60000), verb + " reaches its real work period")
		var action: Dictionary = original.actors.player.active
		runner.assert_true(not action.is_empty() and action.get("phase") == "work", verb + " is genuinely in progress when saved")
		if action.is_empty() or action.get("phase") != "work":
			continue
		var saved: Dictionary = _round_trip(original.to_dict())
		var action_id: String = str(action.id)
		var amount: int = int(original.config.actions[verb].amount)
		var source_before: int = original.inventory.quantity("resource:woodlot", "wood")
		var store_before: int = original.inventory.quantity("store", "wood")
		var bag_before: int = original.inventory.quantity("actor:player", "wood")
		var extracted_before: int = int(original.land_resources.sources.woodlot.extracted)
		var produced_before: int = int(original.land_resources.sources.woodlot.produced)
		var candidate: VillageSimulation = VillageSimulation.from_snapshot(world._content, saved)
		runner.assert_not_null(candidate, verb + " restores its existing reservation and finite source")
		if candidate == null:
			continue
		candidate.set_navigation(fixtures._path)
		var due: int = int(candidate.actors.player.active.due_ms)
		runner.assert_true(candidate.advance_to_ms(due + 1000), verb + " settles after its saved deadline")
		runner.assert_true(candidate.actors.player.active.is_empty(), verb + " completes without another opening")
		runner.assert_true(candidate.inventory.operations.has(action_id + ":harvest"), verb + " records its original harvest")
		runner.assert_eq(int(candidate.land_resources.sources.woodlot.extracted), extracted_before + amount, verb + " extracts exactly one original batch")
		var produced: int = int(candidate.land_resources.sources.woodlot.produced) - produced_before
		runner.assert_eq(candidate.inventory.quantity("resource:woodlot", "wood"), source_before + produced - amount, verb + " conserves the source including actual growth")
		if verb == "keep_wood":
			runner.assert_eq(candidate.inventory.quantity("actor:player", "wood"), bag_before + amount, "private forage places the batch in its original carrier")
		else:
			runner.assert_eq(candidate.inventory.quantity("store", "wood"), store_before + amount, "public gather delivers the batch to the original store")
		var after: Dictionary = candidate.inventory.to_dict()
		runner.assert_true(candidate.advance_to_ms(candidate.elapsed_ms + 1000), verb + " advances after completion")
		runner.assert_eq(candidate.inventory.to_dict(), after, verb + " does not repeat its transfer on another boundary")
		runner.assert_eq(_json(original.to_dict()), _json(saved), verb + " candidate advancement leaves the original village untouched")


func _test_inflight_meal_and_rejection(runner: Object) -> void:
	var fixtures := RegionalFixtures.new()
	var world: RegionalSimulation = fixtures._make_world(runner, false, false, true, false)
	if world == null:
		return
	var original: VillageSimulation = world.regions.home
	var started: bool = original.submit_action("player", "eat")
	runner.assert_true(started, "meal fixture starts a real reserved action")
	if not started:
		return
	var travelling: Dictionary = _round_trip(original.to_dict())
	var before: String = _json(travelling)
	var action: Dictionary = travelling.actors.player.active
	runner.assert_true(not action.reservations.is_empty(), "the in-flight meal has an original reservation")
	if action.reservations.is_empty():
		return
	var broken: Dictionary = travelling.duplicate(true)
	broken.actors.player.definition_id = "missing_definition"
	_reject(runner, world._content, broken, "unknown actor definition")
	broken = travelling.duplicate(true)
	broken.places.kitchen.cell = [-1, 0]
	_reject(runner, world._content, broken, "invalid place position")
	broken = travelling.duplicate(true)
	broken.inventory.reservations.erase(str(action.reservations[0]))
	_reject(runner, world._content, broken, "missing action reservation")
	broken = travelling.duplicate(true)
	runner.assert_true(not broken.institutions.entries.is_empty(), "the genuine opening includes institutional entries")
	if not broken.institutions.entries.is_empty():
		broken.institutions.entries[0].amount = -1
		_reject(runner, world._content, broken, "corrupt institutional entry")
	runner.assert_true(VillageSimulation.from_snapshot(null, travelling) == null, "missing content is rejected")
	var invalid_content := ReolContentDB.new()
	if invalid_content.load_all():
		invalid_content.stock_information_policy.memory_lifetime_minutes = 0
		_reject(runner, invalid_content, travelling, "invalid stock-information policy")
	else:
		runner.assert_true(false, "separate candidate content loads for policy rejection")
	runner.assert_eq(_json(travelling), before, "rejected candidates do not mutate the source input")
	runner.assert_eq(_json(original.to_dict()), before, "rejected candidates do not mutate the original village")
	runner.assert_true(original.advance_to_ms(60000), "meal proceeds into its real work period")
	if original.actors.player.active.is_empty() or original.actors.player.active.get("phase") != "work":
		runner.assert_true(false, "meal remains in progress while the actor holds it")
		return
	var held: Dictionary = _round_trip(original.to_dict())
	var meal_id: String = str(held.actors.player.active.id)
	var candidate: VillageSimulation = VillageSimulation.from_snapshot(world._content, held)
	runner.assert_not_null(candidate, "held meal restores without new opening stock")
	if candidate == null:
		return
	var total_before: int = _total_item(candidate, "meal")
	var deadline: int = int(candidate.actors.player.active.due_ms)
	runner.assert_true(candidate.advance_to_ms(deadline + 1), "restored meal reaches its original completion")
	runner.assert_eq(_total_item(candidate, "meal"), total_before - 1, "completion consumes one real meal")
	runner.assert_true(candidate.inventory.operations.has(meal_id + ":eat"), "the original meal action owns its consume receipt")
	var consumed: Dictionary = candidate.inventory.operations[meal_id + ":eat"].duplicate(true) if candidate.inventory.operations.has(meal_id + ":eat") else {}
	runner.assert_true(candidate.advance_to_ms(candidate.elapsed_ms + 1000), "completed meal can be advanced again")
	runner.assert_eq(_total_item(candidate, "meal"), total_before - 1, "later settlement cannot consume a second meal")
	runner.assert_eq(candidate.inventory.operations.get(meal_id + ":eat", {}), consumed, "the original consume receipt is not duplicated")


func _test_cross_domain_scopes(runner: Object) -> void:
	var fixtures := RegionalFixtures.new()
	var world: RegionalSimulation = fixtures._make_world(runner)
	if world == null:
		return
	var home: VillageSimulation = world.regions.home
	var recorded: bool = home.institutions.issue("scope:test", "sect", "chen_shouzhuo", "river_shi_tou", 1, "written_basis")
	runner.assert_true(recorded, "a real institution can record a remote person as subject")
	if not recorded:
		return
	var saved: Dictionary = _round_trip(home.to_dict())
	runner.assert_true(VillageSimulation.from_snapshot(world._content, saved) == null, "a remote subject cannot pass without its explicit regional scope")
	var with_subject: VillageSimulation = VillageSimulation.from_snapshot(world._content, saved, {"river_shi_tou": true})
	runner.assert_not_null(with_subject, "the original regional subject scope is passed to institution validation")
	if with_subject != null:
		runner.assert_eq(_json(with_subject.to_dict()), _json(saved), "the admitted external subject retains its one original entry")

	var construction := ConstructionFixtures.new()
	var construction_world: RegionalSimulation = construction._world(runner)
	if construction_world == null:
		return
	construction._site(runner, construction_world)
	var project: String = construction._place(runner, construction_world)
	if project.is_empty():
		return
	var begun: Dictionary = construction_world.construction.begin("player", project)
	runner.assert_true(bool(begun.get("ok", false)), "a real construction project reserves its original materials")
	if not bool(begun.get("ok", false)):
		return
	var state: Dictionary = _round_trip(construction_world.to_dict())
	if state.is_empty():
		runner.assert_true(false, "real construction world captures a consistent regional snapshot")
		return
	var source: Dictionary = state.regions.home
	var scope: Dictionary = SimConstruction.Schema.inventory_scope(state.construction, "home", construction_world._content.construction)
	runner.assert_true(not scope.containers.is_empty() and not scope.reservations.is_empty(), "construction scope names its real container and reservation")
	runner.assert_true(VillageSimulation.from_snapshot(construction_world._content, source) == null, "construction inventory cannot pass without its original scope")
	var with_inventory: VillageSimulation = VillageSimulation.from_snapshot(construction_world._content, source, {}, scope)
	runner.assert_not_null(with_inventory, "the real construction scope is passed to inventory validation")
	if with_inventory != null:
		runner.assert_eq(_json(with_inventory.to_dict()), _json(source), "the original external container and reservation remain intact")


func _reject(runner: Object, content: ReolContentDB, bad: Dictionary, label: String) -> void:
	var before: String = _json(bad)
	runner.assert_true(VillageSimulation.from_snapshot(content, bad) == null, label + " is rejected")
	runner.assert_eq(_json(bad), before, label + " rejection leaves its input unchanged")


func _total_item(sim: VillageSimulation, item: String) -> int:
	var total: int = 0
	for container: String in sim.inventory.containers:
		total += sim.inventory.quantity(container, item)
	return total


func _round_trip(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value, "", true, true))


func _json(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)
