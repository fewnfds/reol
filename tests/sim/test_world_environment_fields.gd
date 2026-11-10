extends RefCounted
## Ordinary regional integration: original objects, one shared field and clock.
## A custom immutable content bundle supplies an intrinsic hot test profile.

const RegionalFixture = preload("res://tests/sim/test_regional_simulation.gd")
const LifecycleFixture = preload("res://tests/sim/test_object_lifecycle.gd")
const MapFixture = preload("res://tests/sim/test_world_object_query.gd")
const FIELDS = preload("res://scripts/sim/world_environment_fields.gd")
const SOURCE_PATH: String = "res://data/definitions/environment_sources.json"
const TEST_ITEM: String = "field_test_slate"
const FIRST := Vector2i(120, 120)
const SECOND := Vector2i(140, 120)

var _regional := RegionalFixture.new()
var _lifecycle := LifecycleFixture.new()


func run(runner: Object) -> void:
	_current_world_and_slices(runner)
	_objects_and_continuation(runner)
	_stock_split_and_merge(runner)
	_finite_device(runner)
	_people_and_plants(runner)
	print("SCENARIO ordinary world fields: time, actual source changes, stock, consumers and independent restoration")


func _world(runner: Object, overrides: Dictionary = {}) -> RegionalSimulation:
	var source := ReolContentDB.new()
	if not source.load_all():
		runner.assert_true(false, "field fixture loads current content")
		return null
	var documents: Dictionary = source.content_bundle().documents.duplicate(true)
	var definitions: Dictionary = documents[SOURCE_PATH]
	definitions.profiles["test_heat"] = definitions.profiles.intrinsic_hot.duplicate(true)
	definitions.profiles.test_heat.thermal_grade = 1000
	definitions.bindings.artifacts.plain_slate = "test_heat"
	for path: String in overrides:
		if documents.has(path):
			documents[path] = overrides[path].duplicate(true)
	var content := ReolContentDB.new()
	var bundle: Dictionary = ReolContentBundle.from_documents(documents)
	if not content.load_bundle(bundle):
		runner.assert_true(false, "field fixture binds the isolated current definitions: " + str(content.errors))
		return null
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/world_continuity.json"))
	var instances: Dictionary = {}
	for id: String in ["home", "river"]:
		var village: VillageSimulation = _regional._make_village(content, id, false)
		if village == null:
			runner.assert_true(false, "field fixture initializes the original " + id + " village")
			return null
		instances[id] = village
	var world := RegionalSimulation.new()
	if not world.initialize(settings, instances, content):
		runner.assert_true(false, "field fixture initializes the original regional world")
		return null
	world.set_active_region("")
	var terrain := MapFixture.FlatMap.new()
	if not terrain.configure_nature(content.natural_environment):
		runner.assert_true(false, "field fixture binds its own natural terrain")
		return null
	world.bind_map_data(terrain)
	var opening: Variant = overrides.get("res://data/scenarios/artifacts.json", JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json")))
	if not opening is Dictionary or not world.artifacts.spawn_opening(opening):
		runner.assert_true(false, "field fixture places original authored devices")
		return null
	return world


func _ready(runner: Object, world: RegionalSimulation) -> bool:
	if world == null:
		return false
	runner.assert_true(world.environment_fields is FIELDS, "the ordinary regional world owns the new field authority")
	if not (world.environment_fields is FIELDS):
		return false
	var active: bool = world.environment_fields.activate_sources()
	runner.assert_true(active, "the ordinary field activates against actual original sources")
	return active


func _advance(runner: Object, world: RegionalSimulation, at_ms: int, label: String) -> bool:
	var accepted: bool = world.advance_to_ms(at_ms, 4096)
	runner.assert_true(accepted and world.elapsed_ms == at_ms and world.target_ms == at_ms, label + ": " + str(world.errors))
	return accepted and world.elapsed_ms == at_ms and world.target_ms == at_ms


func _actual(runner: Object, world: RegionalSimulation, cell: Vector2i) -> Dictionary:
	var result: Dictionary = world.environment_fields.actual_at(cell, world.elapsed_ms)
	runner.assert_true(bool(result.get("ok", false)), "the current actual temperature exists at " + str(cell) + ": " + str(result))
	return result


func _phase(runner: Object, world: RegionalSimulation, cell: Vector2i) -> Dictionary:
	var result: Dictionary = world.environment_fields.elements_at(cell)
	runner.assert_true(bool(result.get("ok", false)), "the current actual five-element field exists at " + str(cell) + ": " + str(result))
	return result


func _near(runner: Object, left: float, right: float, label: String) -> void:
	runner.assert_true(is_finite(left) and is_finite(right) and absf(left - right) <= 0.000001, "%s: %s / %s" % [label, left, right])


func _current_world_and_slices(runner: Object) -> void:
	var whole: RegionalSimulation = _world(runner)
	var sliced: RegionalSimulation = _world(runner)
	if not _ready(runner, whole) or not _ready(runner, sliced):
		return
	var request: Dictionary = _lifecycle._spawn("slice_spawn", TEST_ITEM, "plain_slate", [FIRST.x, FIRST.y])
	for world: RegionalSimulation in [whole, sliced]:
		var result: Dictionary = world.object_lifecycle.execute(request)
		runner.assert_true(bool(result.get("ok", false)), "each world creates the same real source: " + str(result))
		if not bool(result.get("ok", false)):
			return
	if not _advance(runner, whole, 30000, "whole interval advances"):
		return
	for time: int in [5000, 17000, 30000]:
		if not _advance(runner, sliced, time, "sliced interval advances"):
			return
	for cell: Vector2i in [FIRST, FIRST + Vector2i.RIGHT, SECOND]:
		var first: Dictionary = _actual(runner, whole, cell)
		var second: Dictionary = _actual(runner, sliced, cell)
		var first_phase: Dictionary = _phase(runner, whole, cell)
		var second_phase: Dictionary = _phase(runner, sliced, cell)
		if bool(first.get("ok", false)) and bool(second.get("ok", false)):
			_near(runner, float(first.value_c), float(second.value_c), "shared-time temperature is independent of slicing")
		if bool(first_phase.get("ok", false)) and bool(second_phase.get("ok", false)):
			for channel: int in 5:
				_near(runner, float(first_phase.values[channel]), float(second_phase.values[channel]), "shared-time element is independent of slicing")
	# Reuse this source pair at a real response deadline. The production
	# scheduler must retain the private refresh cursor instead of running all
	# target cells atomically or publishing consumers against half an update.
	for world: RegionalSimulation in [whole, sliced]:
		if not _advance(runner, world, 59999, "prepare real response deadline"):
			return
	if not _advance(runner, whole, 60000, "unbounded response reference"):
		return
	var complete: bool = sliced.advance_to_ms(60000, 4096, 1)
	runner.assert_true(not complete and sliced.settlement.is_pending() and sliced.settled_ms() == 59999, "a one-work response refresh cannot publish a partial world boundary")
	runner.assert_eq(sliced.settlement.progress().step, "previous:environment_fields", "response work yields inside its original owner before health and other consumers")
	var continuations: int = 0
	while not complete and continuations < 4096:
		complete = sliced.advance_to_ms(60000, 4096, 1)
		continuations += 1
	runner.assert_true(complete and continuations > 2 and sliced.errors.is_empty(), "finite work allowances resume every response cell and finish the original boundary")
	runner.assert_eq(VillageRuntime._json_normalized(sliced.environment_fields.to_dict()), VillageRuntime._json_normalized(whole.environment_fields.to_dict()), "budgeted refresh preserves the exact field anchors, device stock receipts and sampled state")
	for world: RegionalSimulation in [whole, sliced]:
		if not _advance(runner, world, 61000, "continue after budgeted response"):
			return
	runner.assert_eq(VillageRuntime._json_normalized(sliced.environment_fields.to_dict()), VillageRuntime._json_normalized(whole.environment_fields.to_dict()), "resuming a refresh neither repeats work nor changes the subsequent field future")


func _objects_and_continuation(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if not _ready(runner, world):
		return
	var original: Dictionary = _actual(runner, world, FIRST)
	if not bool(original.get("ok", false)):
		return
	var created: Dictionary = world.object_lifecycle.execute(_lifecycle._spawn("field_spawn", TEST_ITEM, "plain_slate", [FIRST.x, FIRST.y]))
	runner.assert_true(bool(created.get("ok", false)), "ordinary creation publishes the source: " + str(created))
	if not bool(created.get("ok", false)):
		return
	var after_create: Dictionary = _actual(runner, world, FIRST)
	if not bool(after_create.get("ok", false)):
		return
	_near(runner, float(after_create.value_c), float(original.value_c), "creating a source does not jump actual temperature")
	if not _advance(runner, world, 30000, "source has time to establish"):
		return
	var hot: Dictionary = _actual(runner, world, FIRST)
	var vacant: Dictionary = _actual(runner, world, SECOND)
	var old_phase: Dictionary = _phase(runner, world, FIRST)
	var vacant_phase: Dictionary = _phase(runner, world, SECOND)
	if not bool(hot.get("ok", false)) or not bool(vacant.get("ok", false)) or not bool(old_phase.get("ok", false)) or not bool(vacant_phase.get("ok", false)):
		return
	runner.assert_true(float(hot.value_c) > float(original.value_c), "the intrinsic hot source gradually warms its actual cell")
	var moved: Dictionary = world.object_lifecycle.execute(_lifecycle._move("field_move", TEST_ITEM, created.to, _lifecycle._ground(SECOND.x, SECOND.y)))
	runner.assert_true(bool(moved.get("ok", false)), "the same original item moves to a new ground cell: " + str(moved))
	if not bool(moved.get("ok", false)):
		return
	var old_after: Dictionary = _actual(runner, world, FIRST)
	var new_after: Dictionary = _actual(runner, world, SECOND)
	var old_phase_after: Dictionary = _phase(runner, world, FIRST)
	var new_phase_after: Dictionary = _phase(runner, world, SECOND)
	if not bool(old_after.get("ok", false)) or not bool(new_after.get("ok", false)) or not bool(old_phase_after.get("ok", false)) or not bool(new_phase_after.get("ok", false)):
		return
	_near(runner, float(old_after.value_c), float(hot.value_c), "moving preserves the old actual temperature at the boundary")
	_near(runner, float(new_after.value_c), float(vacant.value_c), "moving does not instantly heat the new cell")
	_near(runner, float(old_phase_after.values[1]), float(old_phase.values[1]), "moving preserves the old actual element at the boundary")
	_near(runner, float(new_phase_after.values[1]), float(vacant_phase.values[1]), "moving does not instantly fill the new cell")
	if not _advance(runner, world, 45000, "moved source and residual advance"):
		return
	var residual: Dictionary = _actual(runner, world, FIRST)
	var warmed: Dictionary = _actual(runner, world, SECOND)
	if not bool(residual.get("ok", false)) or not bool(warmed.get("ok", false)):
		return
	runner.assert_true(float(residual.value_c) < float(hot.value_c) and float(residual.value_c) > float(original.value_c), "old location gradually loses its retained heat")
	runner.assert_true(float(warmed.value_c) > float(vacant.value_c), "new location gradually gains heat")
	var removed: Dictionary = world.object_lifecycle.execute({"command": "field_remove", "op": "remove", "id": TEST_ITEM, "from": moved.to.duplicate(true)})
	runner.assert_true(bool(removed.get("ok", false)), "ordinary removal removes the original source: " + str(removed))
	if not bool(removed.get("ok", false)):
		return
	var after_remove: Dictionary = _actual(runner, world, SECOND)
	if not bool(after_remove.get("ok", false)):
		return
	_near(runner, float(after_remove.value_c), float(warmed.value_c), "removing a source preserves its actual response")
	runner.assert_true(not world.artifacts.objects.has(TEST_ITEM), "removed item is not copied into another owner")
	_restore_and_continue(runner, world, FIRST, SECOND)


func _restore_and_continue(runner: Object, world: RegionalSimulation, first: Vector2i, second: Vector2i) -> void:
	var saved: Dictionary = world.to_dict()
	runner.assert_true(not saved.is_empty(), "the ordinary world captures actual field history")
	if saved.is_empty():
		return
	runner.assert_true(saved.has("local_heat") and not saved.has("environment_fields"), "runtime naming preserves the existing world snapshot key")
	var stable: String = _json(saved)
	var assembly: Dictionary = ReolWorldAssemblyInputs.from_world(world, {"home": [100, 100], "river": [150, 100]})
	var content := ReolContentDB.new()
	if not content.load_bundle(world._content.content_bundle()):
		runner.assert_true(false, "restore binds the archived custom content bundle")
		return
	var terrain := MapFixture.FlatMap.new()
	if not terrain.configure_nature(content.natural_environment):
		runner.assert_true(false, "restore candidate binds independent terrain")
		return
	var restored: RegionalSimulation = WorldRestoreFactory.restore(content, saved, assembly, terrain)
	runner.assert_true(restored != null, "ordinary regional factory restores actual field anchors")
	runner.assert_eq(_json(saved), stable, "staging a restore does not rewrite the saved source")
	if restored == null:
		return
	runner.assert_true(restored != world and restored.map_data != world.map_data, "restored world and map use separate owners")
	runner.assert_true(restored.environment_fields != null and restored.environment_fields != world.environment_fields, "restored environment fields have their own live authority")
	for cell: Vector2i in [first, second]:
		var a: Dictionary = _actual(runner, world, cell)
		var b: Dictionary = _actual(runner, restored, cell)
		var a_phase: Dictionary = _phase(runner, world, cell)
		var b_phase: Dictionary = _phase(runner, restored, cell)
		if bool(a.get("ok", false)) and bool(b.get("ok", false)):
			_near(runner, float(a.value_c), float(b.value_c), "restore retains actual temperature")
		if bool(a_phase.get("ok", false)) and bool(b_phase.get("ok", false)):
			for channel: int in 5:
				_near(runner, float(a_phase.values[channel]), float(b_phase.values[channel]), "restore retains actual element response")
	var broken: Dictionary = saved.duplicate(true)
	broken.local_heat.source_digest = "wrong-source-digest"
	var before: String = _json(world.to_dict())
	runner.assert_true(not world.restore(broken), "malformed field metadata cannot replace the live world")
	runner.assert_eq(_json(world.to_dict()), before, "failed field restore leaves every live world fact unchanged")
	for sim: VillageSimulation in restored.regions.values():
		sim.set_navigation(Callable(_regional, "_path"))
	if restored.services != null:
		restored.services.set_navigation(Callable(_regional, "_path"))
	if not _advance(runner, world, 55000, "original world continues") or not _advance(runner, restored, 50000, "restored world first slice") or not _advance(runner, restored, 55000, "restored world second slice"):
		return
	for cell: Vector2i in [first, second]:
		var a: Dictionary = _actual(runner, world, cell)
		var b: Dictionary = _actual(runner, restored, cell)
		var a_phase: Dictionary = _phase(runner, world, cell)
		var b_phase: Dictionary = _phase(runner, restored, cell)
		if bool(a.get("ok", false)) and bool(b.get("ok", false)):
			_near(runner, float(a.value_c), float(b.value_c), "restored residual has the same future")
		if bool(a_phase.get("ok", false)) and bool(b_phase.get("ok", false)):
			for channel: int in 5:
				_near(runner, float(a_phase.values[channel]), float(b_phase.values[channel]), "restored element residual has the same future")


func _stock_split_and_merge(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if not _ready(runner, world):
		return
	var inventory: SimInventory = world.regions.home.inventory
	var total: int = _lifecycle._total(inventory, "wood")
	var sources_before: int = int(world.environment_fields.diagnostics().source.source_count)
	var dropped: Dictionary = world.object_lifecycle.execute(_lifecycle._transfer("field_drop", _lifecycle._location("store"), _lifecycle._ground(FIRST.x, FIRST.y), "wood", 4))
	runner.assert_true(bool(dropped.get("ok", false)), "a real stock pile becomes one source: " + str(dropped))
	if not bool(dropped.get("ok", false)):
		return
	runner.assert_eq(int(world.environment_fields.diagnostics().source.source_count), sources_before + 1, "one pile adds one source regardless of count")
	var merged: Dictionary = world.object_lifecycle.execute(_lifecycle._transfer("field_merge", _lifecycle._location("store"), _lifecycle._ground(FIRST.x, FIRST.y), "wood", 3))
	runner.assert_true(bool(merged.get("ok", false)), "same material merges into the existing pile")
	if not bool(merged.get("ok", false)):
		return
	runner.assert_eq(int(world.environment_fields.diagnostics().source.source_count), sources_before + 1, "merging seven items still counts as one source")
	var split: Dictionary = world.object_lifecycle.execute(_lifecycle._transfer("field_split", dropped.to, _lifecycle._ground(SECOND.x, SECOND.y), "wood", 2))
	runner.assert_true(bool(split.get("ok", false)), "part of the real pile can form a separate pile")
	if not bool(split.get("ok", false)):
		return
	runner.assert_eq(int(world.environment_fields.diagnostics().source.source_count), sources_before + 2, "two separate piles are two sources")
	runner.assert_eq(_lifecycle._total(inventory, "wood"), total, "the original inventory conserves stock through split and merge")
	var first: Dictionary = _phase(runner, world, FIRST)
	var second: Dictionary = _phase(runner, world, SECOND)
	if bool(first.get("ok", false)) and bool(second.get("ok", false)):
		_near(runner, float(first.values[0]), float(second.values[0]), "two newly changed cells do not instantly gain element response")
	if not _advance(runner, world, 30000, "two piles establish their fields"):
		return
	first = _phase(runner, world, FIRST)
	second = _phase(runner, world, SECOND)
	if bool(first.get("ok", false)) and bool(second.get("ok", false)):
		# Receiver-side tide varies with position by up to 2%. Equal-size source
		# contribution must still be insensitive to stack quantity at each cell.
		runner.assert_true(absf(float(first.values[0]) - float(second.values[0])) < 20.0, "different quantities of the same material give one source per pile within tide variation")
	var first_now: Dictionary = first
	var second_now: Dictionary = second
	var reunited: Dictionary = world.object_lifecycle.execute(_lifecycle._transfer("field_reunite", split.to, _lifecycle._ground(FIRST.x, FIRST.y), "wood", 2))
	runner.assert_true(bool(reunited.get("ok", false)), "one ground pile can merge back into the other")
	if not bool(reunited.get("ok", false)):
		return
	runner.assert_eq(int(world.environment_fields.diagnostics().source.source_count), sources_before + 1, "reuniting piles removes exactly one source")
	first = _phase(runner, world, FIRST)
	second = _phase(runner, world, SECOND)
	if bool(first.get("ok", false)) and bool(second.get("ok", false)) and bool(first_now.get("ok", false)) and bool(second_now.get("ok", false)):
		_near(runner, float(first.values[0]), float(first_now.values[0]), "merging preserves destination's actual element")
		_near(runner, float(second.values[0]), float(second_now.values[0]), "merging preserves removed pile's residual at the boundary")
	if not _advance(runner, world, 45000, "reunited pile and residual continue"):
		return
	second = _phase(runner, world, SECOND)
	if bool(second.get("ok", false)) and bool(second_now.get("ok", false)):
		runner.assert_true(float(second.values[0]) > 0.0 and float(second.values[0]) < float(second_now.values[0]), "removed pile leaves an element residual that fades")
	runner.assert_eq(_lifecycle._total(inventory, "wood"), total, "reuniting preserves the original material total")


func _finite_device(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if not _ready(runner, world):
		return
	var point: Vector2i = world.artifacts.object_cell("fire_stone")
	world.regions.home.set_actor_cell("player", point)
	world.invalidate_region("home")
	for verb: String in ["study", "enable"]:
		var action: Dictionary = world.artifacts.begin("player", verb, "fire_stone")
		runner.assert_true(bool(action.get("ok", false)), "the original device action starts: " + verb + " " + str(action))
		if not bool(action.get("ok", false)):
			return
		var due: int = int(world.artifacts.active.player.due_ms)
		if not _advance(runner, world, due, "the original device action completes"):
			return
	runner.assert_true(bool(world.artifacts.objects.fire_stone.enabled), "the original finite device is enabled")
	var before: int = int(world.artifacts.objects.fire_stone.stored_q)
	var count: int = world.artifacts.objects.size()
	if not _advance(runner, world, world.elapsed_ms + 1000, "finite device emits for one second"):
		return
	var after: int = int(world.artifacts.objects.fire_stone.stored_q)
	var rate: int = int(world.artifacts.definitions.types.fire_stone.thermal.rate_q_per_ms)
	runner.assert_eq(before - after, mini(before, rate * 1000), "only the original stored quantity pays for emission")
	runner.assert_eq(world.artifacts.objects.size(), count, "enabling and emitting do not create another device")


func _people_and_plants(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if not _ready(runner, world):
		return
	var garden := Vector2i(int(world.regions.home.places.garden.cell[0]), int(world.regions.home.places.garden.cell[1]))
	var source_cell: Vector2i = garden + Vector2i.RIGHT
	world.regions.home.set_actor_cell("player", garden)
	world.invalidate_region("home")
	var created: Dictionary = world.object_lifecycle.execute(_lifecycle._spawn("consumer_source", TEST_ITEM, "plain_slate", [source_cell.x, source_cell.y]))
	runner.assert_true(bool(created.get("ok", false)), "person and herb share an actual nearby environmental source")
	if not bool(created.get("ok", false)) or not _advance(runner, world, 60000, "the original herb sample boundary is reached"):
		return
	var actual: Dictionary = _actual(runner, world, garden)
	var person: Dictionary = world.environment.local_conditions("player")
	var herb: Dictionary = world.regions.home.land_resources.sources.herb_slope.ecology
	if not bool(actual.get("ok", false)):
		return
	runner.assert_eq(int(person.get("temperature_tenths", -999999)), roundi(float(actual.value_c) * 10.0), "the person's conditions read the same actual field")
	runner.assert_eq(int(herb.get("sample_ms", -1)), world.elapsed_ms, "the herb retains the real common sample time")
	runner.assert_eq(int(herb.get("temperature_tenths", -999999)), roundi(float(actual.value_c) * 10.0), "the herb sample reads the same actual field")


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
