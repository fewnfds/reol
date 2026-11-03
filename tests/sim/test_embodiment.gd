extends RefCounted
## Nonhuman substitutes verify the boundary, not playable nonhuman content.

const Fixtures = preload("res://tests/sim/test_regional_simulation.gd")


func run(runner: Object) -> void:
	_test_residence_is_not_control(runner)
	_test_nonhuman_forms_and_atomic_restore(runner)
	_test_real_actions_and_carried_goods(runner)


func _configured(runner: Object) -> SimEmbodiment:
	var content := ReolContentDB.new()
	runner.assert_true(content.load_all(), "body forms load with the actual content pack")
	var registry := SimEmbodiment.new()
	runner.assert_true(registry.configure(content.body_forms), "embodiment accepts validated forms")
	return registry


func _test_residence_is_not_control(runner: Object) -> void:
	var registry: SimEmbodiment = _configured(runner)
	runner.assert_true(registry.add_subject("traveler") and registry.add_subject("elder"), "two independent subjects need no shared human stats")
	runner.assert_true(registry.add_carrier("body", "human", {"kind": "test_body", "id": "one"}), "body is a reference to physical truth")
	runner.assert_true(registry.add_carrier("ring", "soul_ring", {"kind": "test_object", "id": "ring"}), "an object can be a distinct carrier")
	runner.assert_true(registry.reside("traveler", "body") and registry.reside("elder", "ring"), "subjects reside in separate carriers")
	runner.assert_true(not registry.controls("elder", "ring", "communication"), "residence alone grants no action permission")
	runner.assert_true(registry.grant_control("traveler", "body", "motion"), "explicit authority grants a specific channel")
	runner.assert_true(not registry.grant_control("elder", "body", "motion"), "second writer cannot silently replace the existing controller")
	runner.assert_true(not registry.release_control("elder", "body", "motion"), "another subject cannot release the holder's channel")
	runner.assert_true(not registry.controls("traveler", "ring", "communication"), "carrying a ring would not control its resident")
	runner.assert_true(registry.grant_control("elder", "ring", "communication"), "resident soul can receive its own communication channel")
	runner.assert_true(not registry.grant_control("elder", "ring", "motion"), "a ring with no locomotion cannot walk")
	runner.assert_true(registry.controls("traveler", "body", "motion"), "ring communication leaves the wearer's control untouched")
	runner.assert_true(not registry.add_carrier("duplicate", "human", {"kind": "test_body", "id": "one"}), "two bodies cannot alias the same physical source")
	var before: String = JSON.stringify(registry.to_dict(), "", true, true)
	for _index in 10:
		registry.footprint("body")
		registry.capable("ring", "walk")
		registry.controls("elder", "body", "motion")
	runner.assert_eq(JSON.stringify(registry.to_dict(), "", true, true), before, "queries neither grant control nor mutate state")


func _test_nonhuman_forms_and_atomic_restore(runner: Object) -> void:
	var registry: SimEmbodiment = _configured(runner)
	for form: String in ["sparrow", "ancient_beast", "soul_ring"]:
		registry.add_subject("subject:" + form)
		registry.add_carrier("carrier:" + form, form, {"kind": "test", "id": form})
		registry.reside("subject:" + form, "carrier:" + form)
	runner.assert_true(registry.capable("carrier:sparrow", "fly") and not registry.capable("carrier:sparrow", "village_routine"), "bird locomotion does not imply human kitchen work")
	runner.assert_eq(registry.footprint("carrier:ancient_beast"), Vector2i(3, 3), "large body occupies multiple cells")
	runner.assert_true(not registry.capable("carrier:soul_ring", "grasp"), "ring does not inherit humanoid hands")
	var raw: Dictionary = registry.to_dict()
	var restored: SimEmbodiment = _configured(runner)
	runner.assert_true(restored.restore(JSON.parse_string(JSON.stringify(raw))), "references and residence survive a JSON boundary")
	runner.assert_eq(JSON.stringify(restored.to_dict(), "", true, true), JSON.stringify(raw, "", true, true), "restored registry contains no invented control")
	var invalids: Array[Dictionary] = []
	var bad: Dictionary = raw.duplicate(true)
	bad.residences["subject:sparrow"] = "missing"
	invalids.append(bad)
	bad = raw.duplicate(true)
	bad.carriers["carrier:sparrow"].source = raw.carriers["carrier:soul_ring"].source.duplicate()
	invalids.append(bad)
	bad = raw.duplicate(true)
	bad.controls["carrier:soul_ring"] = {"motion": "subject:soul_ring"}
	invalids.append(bad)
	bad = raw.duplicate(true)
	bad.controls["carrier:sparrow"] = {"motion": "unknown"}
	invalids.append(bad)
	bad = raw.duplicate(true)
	bad.controls["carrier:sparrow"] = {"motion": ["subject:sparrow", "subject:soul_ring"]}
	invalids.append(bad)
	bad = raw.duplicate(true)
	bad.carriers["carrier:sparrow"]["cell"] = [10, 10]
	invalids.append(bad)
	for invalid: Dictionary in invalids:
		var before: String = JSON.stringify(restored.to_dict(), "", true, true)
		runner.assert_true(not restored.restore(invalid), "dangling, duplicate or unauthorized embodiment shape is rejected")
		runner.assert_eq(JSON.stringify(restored.to_dict(), "", true, true), before, "failed registry restore is atomic")
	var forms: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ReolContentDB.BODY_FORMS_PATH))
	for value: Variant in [[0, 1], [1.5, 2], [true, 2], [INF, 1]]:
		var malformed: Dictionary = forms.duplicate(true)
		malformed.forms.sparrow.footprint = value
		runner.assert_true(not SimEmbodiment.valid_forms(malformed), "invalid geometry is rejected before content is used")


func _test_real_actions_and_carried_goods(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var world: RegionalSimulation = fixtures._make_world(runner)
	if world == null:
		return
	var village: VillageSimulation = world.regions.home
	var registry: SimEmbodiment = world.embodiment
	var subject: String = registry.subject_for_actor("player")
	var body: String = registry.carrier_for_source("village_actor", "player")
	runner.assert_true(subject != body and registry.residence_of(subject) == body, "real player subject and body are separate references")
	runner.assert_true(village.submit_action("player", "deliver_wood"), "existing work uses explicit self control")
	var limit: int = world.current_time + 100
	while village.inventory.quantity("actor:player", "wood") == 0 and world.current_time < limit:
		world.advance_to(world.current_time + 1)
	var carried: int = village.inventory.quantity("actor:player", "wood")
	runner.assert_true(carried > 0 and not village.actors.player.active.is_empty(), "real work has picked up physical cargo before interruption")
	registry.release_control(subject, body, "action")
	world.invalidate_region("home")
	runner.assert_true(world.advance_to(world.current_time + 1), "far scheduler notices lost action control at a boundary")
	world.synchronize_region("home")
	runner.assert_true(village.actors.player.active.is_empty(), "in-progress native work stops when control is lost")
	runner.assert_eq(village.inventory.quantity("actor:player", "wood"), carried, "lost control does not destroy or duplicate already carried goods")
	runner.assert_true(not village.submit_action("player", "rest"), "new work cannot bypass lost action control")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict()))
	var restored: RegionalSimulation = fixtures._make_world(runner)
	runner.assert_true(restored.restore(snapshot), "settled loss of control persists through normal regional save")
	runner.assert_true(not restored.actor_controls("player", "action"), "loading does not silently regenerate self control")
	runner.assert_eq(restored.regions.home.inventory.quantity("actor:player", "wood"), carried, "restored body retains the one physical cargo")
	var bad: Dictionary = snapshot.duplicate(true)
	bad.embodiment.carriers[body].source.id = "missing_body"
	var before: String = JSON.stringify(restored.to_dict(), "", true, true)
	runner.assert_true(not restored.restore(bad), "composition rejects a structurally valid but nonexistent source")
	runner.assert_eq(JSON.stringify(restored.to_dict(), "", true, true), before, "cross-domain validation cannot partially replace the world")
	var weak_owner: WeakRef = weakref(restored)
	restored = null
	runner.assert_true(weak_owner.get_ref() == null, "control callbacks do not retain a dead regional authority")
	print("SCENARIO embodiment: exclusive channels, distinct souls/bodies, nonhuman substitutes, real cargo survives lost control and JSON")
