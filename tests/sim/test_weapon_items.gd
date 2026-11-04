extends RefCounted
## Unique nonthermal tools reuse original artifact custody and action records.

const Fixtures = preload("res://tests/sim/test_regional_simulation.gd")
const SWORD: String = "tool:training_sword"
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_capabilities_and_recognition(runner)
	_real_custody_and_cancellation(runner)
	_joint_continuation(runner)
	_bad_states_are_atomic(runner)
	print("SCENARIO weapon items: original unique custody, nonthermal verbs, personal familiarity without heat/sword mastery and in-flight joint continuation")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _fixtures._make_world(runner)
	if world == null:
		return null
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))
	opening.objects.append({"id": SWORD, "definition": "wooden_sword", "region": "home", "container": "dorm"})
	runner.assert_true(world.artifacts.spawn_opening(opening), "the same original authority assembles a stone and a real wooden sword")
	world.regions.home.set_actor_cell("player", SimRouteTravel.cell(world.regions.home.places.dorm.cell))
	world.invalidate_region("home")
	return world


func _canonical(world: RegionalSimulation) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(world.to_dict()))


func _finish(world: RegionalSimulation, runner: Object) -> void:
	var due: int = int(world.artifacts.active.player.due_ms)
	runner.assert_true(world.advance_to_ms(due), "the original shared clock finishes the tool operation")


func _capabilities_and_recognition(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var domain: SimArtifacts = world.artifacts
	runner.assert_eq(domain.objects[SWORD].size(), 3, "nonthermal tools contain only definition and canonical location")
	runner.assert_true(not domain.objects[SWORD].has("charge") and not domain.objects[SWORD].has("damage"), "a wooden sword gains no invented heat or stone damage")
	runner.assert_true(domain.has_capability(SWORD, "weapon") and not domain.has_capability(SWORD, "heat_storage"), "weapon capability does not inherit thermal capability")
	runner.assert_true(domain.has_capability("hearth_stone", "heat_storage") and not domain.has_capability("hearth_stone", "weapon"), "legacy stone retains its original thermal capability")
	runner.assert_eq(domain.objects.hearth_stone, {"definition": "warm_stone", "region": "home", "container": "kitchen", "charge": 6, "damage": 1}, "legacy stone serialization keeps exactly the former shape")
	var verbs: Dictionary = domain.verbs_for(SWORD)
	runner.assert_true(verbs.has("take") and verbs.has("study") and not verbs.has("charge") and not verbs.has("warm"), "tool exposes only its configured handling operations")
	verbs.clear()
	runner.assert_true(domain.verbs_for(SWORD).has("take"), "a caller cannot mutate the action definition through a UI query")
	var before: String = _canonical(world)
	for verb: String in ["charge", "heat", "dry", "force", "warm"]:
		runner.assert_true(not bool(domain.begin("player", verb, SWORD).ok), "nonthermal tool rejects unsupported operation before spending: " + verb)
	runner.assert_eq(_canonical(world), before, "rejected thermal operations leave all actual world facts unchanged")
	var view: Dictionary = domain.describe("player", SWORD)
	runner.assert_true(view.known and not view.method and str(view.line).contains("剑招"), "seeing a weapon provides a physical clue without granting technique")
	world.regions.home.set_actor_cell("chen_shouzhuo", SimRouteTravel.cell(world.regions.home.places.dorm.cell))
	world.invalidate_region("home")
	runner.assert_true(not domain.describe("chen_shouzhuo", SWORD).method, "past stone handling does not silently teach wooden weapon familiarity")
	runner.assert_true(domain.begin("player", "study", SWORD).ok, "actor deliberately studies the tool's physical handling")
	_finish(world, runner)
	runner.assert_true(domain.describe("player", SWORD).method, "completed tool handling is remembered personally")
	runner.assert_true(not domain.describe("chen_shouzhuo", SWORD).method, "nearby observer does not inherit tool handling")
	runner.assert_true(not domain.describe("player", "hearth_stone").get("method", false), "tool study does not teach stone channeling")
	runner.assert_true(not bool(domain._warming_readiness("player", SWORD).ok), "warmth initiative safely rejects a nonthermal held-tool candidate")


func _real_custody_and_cancellation(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var domain: SimArtifacts = world.artifacts
	var original_count: int = domain.objects.size()
	runner.assert_eq(domain.held_weapon("player"), "", "an uncollected sword is not equipped by merely opening a panel")
	runner.assert_true(domain.begin("player", "take", SWORD).ok, "actual handling begins against the original object")
	world.advance_to_ms(1000)
	runner.assert_eq(domain.objects[SWORD].container, "dorm", "an unfinished taking operation does not grant the object early")
	runner.assert_true(domain.cancel("player"), "unfinished taking can be cancelled")
	runner.assert_eq(domain.objects[SWORD].container, "dorm", "cancelled taking leaves the actual item at its source")
	runner.assert_true(domain.begin("player", "take", SWORD).ok, "the same object can be taken after cancellation")
	_finish(world, runner)
	runner.assert_eq(domain.held_weapon("player"), SWORD, "the completed transfer exposes the real held weapon")
	runner.assert_eq(domain.objects[SWORD].container, "actor:player", "custody is a single canonical container reference")
	runner.assert_eq(domain.objects.size(), original_count, "taking makes no duplicated object")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "wooden_sword"), 0, "the unique weapon is not also a counted stack")
	world.regions.home.set_actor_cell("chen_shouzhuo", SimRouteTravel.cell(world.regions.home.places.dorm.cell))
	world.invalidate_region("home")
	runner.assert_true(not bool(domain.begin("chen_shouzhuo", "take", SWORD).ok), "another person cannot take an already held weapon without permission")
	runner.assert_true(domain.begin("player", "place", SWORD).ok, "holder can spend actual time returning the weapon")
	_finish(world, runner)
	runner.assert_eq(domain.objects[SWORD].container, "dorm", "returning uses the tool's storage place rather than a fictitious kitchen recipe")
	runner.assert_eq(domain.held_weapon("player"), "", "returned weapon is no longer available as held")


func _joint_continuation(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	runner.assert_true(world.artifacts.begin("player", "take", SWORD).ok, "real take starts before partial snapshot")
	world.advance_to_ms(17000)
	var snapshot: Dictionary = JSON.parse_string(_canonical(world))
	var restored: RegionalSimulation = _world(runner)
	runner.assert_true(restored.restore(snapshot), "independent candidate restores in-flight nonthermal action alongside original world")
	var target: int = 120000
	world.advance_to_ms(target)
	restored.advance_to_ms(target)
	runner.assert_eq(_canonical(restored), _canonical(world), "in-flight tool operation and all other world processes reach the same future")
	runner.assert_eq(restored.artifacts.held_weapon("player"), SWORD, "restored actual transfer produces the original weapon once")


func _bad_states_are_atomic(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var before: String = _canonical(world)
	var bad: Dictionary = JSON.parse_string(before)
	bad.artifacts.objects[SWORD]["charge"] = 12
	runner.assert_true(not world.restore(bad), "a tool cannot acquire a thermal payload through a forged save")
	runner.assert_eq(_canonical(world), before, "invalid tool shape cannot partially commit the world")
	runner.assert_true(world.artifacts.begin("player", "study", SWORD).ok, "real tool study provides a valid active candidate")
	before = _canonical(world)
	bad = JSON.parse_string(before)
	bad.artifacts.active.player.verb = "charge"
	runner.assert_true(not world.restore(bad), "candidate cannot reinterpret tool study as a thermal operation")
	runner.assert_eq(_canonical(world), before, "unsupported active tool verb leaves live study intact")
	_finish(world, runner)
	before = _canonical(world)
	bad = JSON.parse_string(before)
	bad.artifacts.events.back().kind = "warmed"
	runner.assert_true(not world.restore(bad), "candidate cannot turn tool familiarity into a heat source")
	runner.assert_eq(_canonical(world), before, "forged heat result cannot alter actual item, qi or local heat")
