extends RefCounted
## Real ordinary-world sources exercise separate sparse temperature and five-
## phase responses, residuals, candidate rejection, and continued time.

const RegionalFixture = preload("res://tests/sim/test_regional_simulation.gd")
const LifecycleFixture = preload("res://tests/sim/test_object_lifecycle.gd")
const MapFixture = preload("res://tests/sim/test_world_object_query.gd")
const SOURCE_PATH: String = "res://data/definitions/environment_sources.json"
const HOT_OLD := Vector2i(256, 256)
const HOT_NEW := Vector2i(272, 256)
const COLD := Vector2i(400, 256)
const WOOD := Vector2i(320, 320)

var _regional := RegionalFixture.new()
var _lifecycle := LifecycleFixture.new()


func run(runner: Object) -> void:
	_sparse_sources_and_restore(runner)
	print("SCENARIO sparse field restore: independent actual domains, present sources, residuals, validation and continued world time")


func _world(runner: Object) -> RegionalSimulation:
	var source := ReolContentDB.new()
	if not source.load_all():
		runner.assert_true(false, "sparse field fixture loads original definitions")
		return null
	var documents: Dictionary = source.content_bundle().documents.duplicate(true)
	var definitions: Dictionary = documents[SOURCE_PATH]
	definitions.profiles["test_pure_hot"] = definitions.profiles.none.duplicate(true)
	definitions.profiles.test_pure_hot.thermal_grade = 1000
	definitions.profiles.test_pure_hot.radius_cells = 4
	definitions.profiles["test_pure_cold"] = definitions.profiles.test_pure_hot.duplicate(true)
	definitions.profiles.test_pure_cold.thermal_grade = -1000
	definitions.bindings.artifacts.plain_slate = "test_pure_hot"
	definitions.bindings.artifacts.stone_slab = "test_pure_cold"
	var content := ReolContentDB.new()
	if not content.load_bundle(ReolContentBundle.from_documents(documents)):
		runner.assert_true(false, "sparse test profiles use a validated independent content bundle")
		return null
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/world_continuity.json"))
	var instances: Dictionary = {}
	for id: String in ["home", "river"]:
		var village: VillageSimulation = _regional._make_village(content, id, false)
		if village == null:
			runner.assert_true(false, "sparse fixture creates the real region " + id)
			return null
		instances[id] = village
	var world := RegionalSimulation.new()
	if not world.initialize(settings, instances, content):
		runner.assert_true(false, "sparse fixture creates the ordinary world")
		return null
	world.set_active_region("")
	var terrain := MapFixture.FlatMap.new()
	if not terrain.configure_nature(content.natural_environment):
		runner.assert_true(false, "sparse fixture binds ordinary terrain")
		return null
	world.bind_map_data(terrain)
	var opening: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))
	if not opening is Dictionary or not world.artifacts.spawn_opening(opening) or not world.environment_fields.activate_sources():
		runner.assert_true(false, "original authored sources and environment activate")
		return null
	return world


func _sparse_sources_and_restore(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var hot: Dictionary = world.object_lifecycle.execute(_lifecycle._spawn("sparse_hot", "test_hot", "plain_slate", [HOT_OLD.x, HOT_OLD.y]))
	var cold: Dictionary = world.object_lifecycle.execute(_lifecycle._spawn("sparse_cold", "test_cold", "stone_slab", [COLD.x, COLD.y]))
	runner.assert_true(bool(hot.get("ok", false)) and bool(cold.get("ok", false)), "opposite pure thermal sources use the original object lifecycle")
	if not bool(hot.get("ok", false)) or not bool(cold.get("ok", false)) or not _advance(runner, world, 10000):
		return
	var wood: Dictionary = world.object_lifecycle.execute(_lifecycle._transfer("sparse_wood", _lifecycle._location("store"), _lifecycle._ground(WOOD.x, WOOD.y), "wood", 1))
	runner.assert_true(bool(wood.get("ok", false)), "an elemental-only pile uses the same object lifecycle")
	if not bool(wood.get("ok", false)) or not _advance(runner, world, 20000):
		return
	var moved: Dictionary = world.object_lifecycle.execute(_lifecycle._move("sparse_hot_move", "test_hot", hot.to, _lifecycle._ground(HOT_NEW.x, HOT_NEW.y)))
	runner.assert_true(bool(moved.get("ok", false)), "moving the original source keeps its old response and creates a new one")
	if not bool(moved.get("ok", false)):
		return
	var saved: Dictionary = JSON.parse_string(_json(world.to_dict()))
	if saved.is_empty():
		runner.assert_true(false, "ordinary world produces a save")
		return
	var temp: Array = saved.local_heat.temperature.cells
	var phases: Array = saved.local_heat.phases.cells
	runner.assert_true(_find_cell(temp, HOT_OLD) >= 0 and _find_cell(temp, HOT_NEW) >= 0, "old residual and new heat location are both saved")
	runner.assert_true(_find_cell(temp, COLD) >= 0, "pure cold has an actual temperature response")
	runner.assert_true(_find_cell(phases, WOOD) >= 0, "elemental-only source has an actual five-phase response")
	runner.assert_eq(_find_cell(temp, WOOD), -1, "an elemental-only source does not manufacture a thermal response")
	runner.assert_eq(_find_cell(phases, HOT_NEW), -1, "a pure thermal source does not manufacture elemental responses")
	runner.assert_eq(_find_cell(phases, COLD), -1, "a pure cold source does not manufacture elemental responses")
	if _find_cell(temp, HOT_NEW) < 0 or _find_cell(phases, WOOD) < 0:
		return
	runner.assert_eq(int(temp[_find_cell(temp, HOT_NEW)].response.start_ms), 20000, "new thermal response retains its real later anchor")
	runner.assert_eq(int(phases[_find_cell(phases, WOOD)].start_ms), 10000, "unrelated elemental response keeps its earlier anchor")
	var saved_text: String = _json(saved)
	var assembly: Dictionary = ReolWorldAssemblyInputs.from_world(world, {"home": [100, 100], "river": [150, 100]})
	var content := ReolContentDB.new()
	if not content.load_bundle(world._content.content_bundle()):
		runner.assert_true(false, "restoration uses the exact source definition bundle")
		return
	var terrain := MapFixture.FlatMap.new()
	if not terrain.configure_nature(content.natural_environment):
		runner.assert_true(false, "restoration binds a separate real map")
		return
	var restored: RegionalSimulation = WorldRestoreFactory.restore(content, saved, assembly, terrain)
	runner.assert_true(restored != null, "validated independent world accepts sparse independent responses")
	runner.assert_eq(_json(saved), saved_text, "restoration does not rewrite the input save")
	if restored == null:
		return
	_assert_rejected_missing(runner, world, saved, "temperature", HOT_NEW)
	_assert_rejected_missing(runner, world, saved, "temperature", COLD)
	_assert_rejected_missing(runner, world, saved, "phases", WOOD)
	for sim: VillageSimulation in restored.regions.values():
		sim.set_navigation(Callable(_regional, "_path"))
	if restored.services != null:
		restored.services.set_navigation(Callable(_regional, "_path"))
	if not _advance(runner, world, 40000) or not _advance(runner, restored, 30000) or not _advance(runner, restored, 40000):
		return
	for cell: Vector2i in [HOT_OLD, HOT_NEW, COLD, WOOD]:
		var original: Dictionary = world.environment_fields.actual_at(cell, world.elapsed_ms)
		var continued: Dictionary = restored.environment_fields.actual_at(cell, restored.elapsed_ms)
		runner.assert_true(bool(original.get("ok", false)) and bool(continued.get("ok", false)), "both worlds can read actual temperature")
		if bool(original.get("ok", false)) and bool(continued.get("ok", false)):
			runner.assert_true(absf(float(original.value_c) - float(continued.value_c)) < 0.000001, "saved temperature and residual have the same future")
		var a: Dictionary = world.environment_fields.elements_at(cell)
		var b: Dictionary = restored.environment_fields.elements_at(cell)
		runner.assert_true(bool(a.get("ok", false)) and bool(b.get("ok", false)), "both worlds can read actual elemental response")
		if bool(a.get("ok", false)) and bool(b.get("ok", false)):
			for channel: int in 5:
				runner.assert_true(absf(float(a.values[channel]) - float(b.values[channel])) < 0.000001, "saved elemental state has the same future")


func _assert_rejected_missing(runner: Object, world: RegionalSimulation, saved: Dictionary, field: String, cell: Vector2i) -> void:
	var candidate: Dictionary = saved.duplicate(true)
	var rows: Array = candidate.local_heat[field].cells
	var index: int = _find_cell(rows, cell)
	runner.assert_true(index >= 0, "deletion test has an actual source response")
	if index < 0:
		return
	rows.remove_at(index)
	var before: String = _json(world.to_dict())
	runner.assert_true(not world.restore(candidate), "deleting current source response is rejected: " + field + "/" + str(cell))
	runner.assert_eq(_json(world.to_dict()), before, "a rejected candidate leaves the entire live world unchanged")


func _find_cell(rows: Array, cell: Vector2i) -> int:
	for index: int in rows.size():
		var pair: Array = rows[index].cell
		if int(pair[0]) == cell.x and int(pair[1]) == cell.y:
			return index
	return -1


func _advance(runner: Object, world: RegionalSimulation, time: int) -> bool:
	var ok: bool = world.advance_to_ms(time, 4096)
	runner.assert_true(ok and world.elapsed_ms == time, "the world advances to " + str(time) + ": " + str(world.errors))
	return ok and world.elapsed_ms == time


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
