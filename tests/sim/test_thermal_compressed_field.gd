extends RefCounted
## Compare the compressed authority against the same geographic world using
## original per-cell and per-flow rules. Sources and time are never fabricated.

const RegionalFixtures = preload("res://tests/sim/test_regional_simulation.gd")
const EnvironmentFixture = preload("res://tests/sim/test_local_heat_environment.gd")
const Probe = preload("res://scripts/sim/thermal_reclaim_probe.gd")
const GEOGRAPHY: String = "res://data/scenarios/world_geography.json"
const CONTINUITY: String = "res://data/scenarios/world_continuity.json"
const SERVICES: String = "res://data/definitions/settlement_services.json"
const ARTIFACTS: String = "res://data/scenarios/artifacts.json"
const STONE: String = "hearth_stone"
const FIRE: String = "fire_stone"

var _regional := RegionalFixtures.new()
var _environment := EnvironmentFixture.new()


class ReferenceHeat extends SimLocalHeat:
	func _compile_cell_store(_state: Dictionary) -> void:
		_cell_store.expand_all()

	func _rebuild_frozen_groups() -> void:
		_frozen_groups = null


func run(runner: Object) -> void:
	var compressed: RegionalSimulation = _world(runner, false)
	var reference: RegionalSimulation = _world(runner, true)
	if compressed == null or reference == null:
		return
	if not _prepare_and_warm(runner, compressed, reference):
		return
	if not _queries_and_probe(runner, compressed, reference):
		return
	var resumed: RegionalSimulation = _restore_and_continue(runner, compressed, reference)
	if resumed == null:
		return
	_overlap_and_device(runner, compressed, reference, resumed)
	print("SCENARIO compressed heat field: real geographic climate and artifact charges, original fine reference, detached queries, bounded probe, v3 JSON continuation, weather, overlapping source and enabled device")


func _world(runner: Object, reference: bool) -> RegionalSimulation:
	var source := ReolContentDB.new()
	if not source.load_all():
		runner.assert_true(false, "compressed heat fixture loads the original content bundle")
		return null
	var profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(GEOGRAPHY))
	var content: ReolContentDB = ReolGeographicContent.build(source.content_bundle(), profile)
	if content == null:
		runner.assert_true(false, "the original authored geography compiles into complete content")
		return null
	var villages: Dictionary = {}
	for region: String in ["home", "river"]:
		var village: VillageSimulation = _regional._make_village(content, region, false)
		if village == null:
			runner.assert_true(false, "compressed heat fixture constructs the original village in " + region)
			return null
		villages[region] = village
	var world := RegionalSimulation.new()
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONTINUITY))
	if not world.initialize(settings, villages, content):
		runner.assert_true(false, "compressed heat fixture initializes the shared-time regional world")
		return null
	if reference:
		# Replace only the initially empty thermal owner, before any artifact
		# action. Both worlds keep the same bodies, climate and topology hooks.
		var heat := ReferenceHeat.new()
		if world.elapsed_ms != 0 or not heat.initialize(world, content.local_heat):
			runner.assert_true(false, "fine reference binds at the same original opening time")
			return null
		heat.set_geometry(world.construction.thermal_roofed, world.construction.thermal_barrier, true)
		world.environment_fields = heat
	var services: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SERVICES))
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ARTIFACTS))
	if not world.configure_services(services) or not world.set_active_region("") or not world.clothing.spawn_opening() or not world.artifacts.spawn_opening(opening):
		runner.assert_true(false, "fixture issues original services, garments and finite artifact stock")
		return null
	world.services.set_navigation(Callable(_regional, "_path"))
	world.regions.home.set_actor_cell("player", world.artifacts.object_cell(STONE))
	world.invalidate_region("home")
	return world


func _prepare_and_warm(runner: Object, compressed: RegionalSimulation, reference: RegionalSimulation) -> bool:
	if not _environment._prepare(runner, compressed) or not _environment._prepare(runner, reference):
		return false
	if not _same(runner, compressed, reference, "original study and custody match the uncompressed world"):
		return false
	var initial_charge: int = int(compressed.artifacts.objects[STONE].charge)
	for index: int in range(4):
		var center := Vector2i(116 + index * 8, 116)
		for world: RegionalSimulation in [compressed, reference]:
			# Fixture placement moves the one real carrier, never a copied source.
			world.regions.home.set_actor_cell("player", center)
			world.invalidate_region("home")
			if not _environment._do(runner, world, "warm"):
				return false
			if world.artifacts.events.is_empty() or world.artifacts.events.back().kind != "warmed":
				runner.assert_true(false, "each original artifact action actually releases heat")
				return false
		var logical: int = (index + 1) * 25
		runner.assert_eq(compressed.environment_fields.storage_summary(), {"logical_cells": logical, "q_slots": (index + 1) * 6}, "each isolated genuine source retains twenty-five cells in six exact Q slots")
		runner.assert_eq(reference.environment_fields.storage_summary(), {"logical_cells": logical, "q_slots": logical}, "reference keeps one physical Q slot per fine cell")
		runner.assert_eq(int(compressed.artifacts.objects[STONE].charge), initial_charge - index - 1, "the original source pays exactly one finite charge per warm")
		if not _same(runner, compressed, reference, "complete worlds match after source %d" % (index + 1)):
			return false
	return true


func _queries_and_probe(runner: Object, compressed: RegionalSimulation, reference: RegionalSimulation) -> bool:
	var heat: SimLocalHeat = compressed.environment_fields
	var before: String = _state(compressed)
	var key: String = "116,116"
	var actual: Dictionary = heat.cell_row(key)
	var view: Dictionary = heat.cells
	var keys: Array[String] = heat.cell_keys()
	runner.assert_true(heat.has_cell(Vector2i(116, 116)) and not heat.has_cell(Vector2i(115, 110)), "point membership distinguishes allocated and unallocated cells")
	runner.assert_eq(heat.cell_count(), 100, "logical cell count is independent of compressed slot count")
	runner.assert_eq(keys.size(), 100, "enumeration returns every original coordinate")
	runner.assert_true(view.has(key) and view.is_read_only() and view[key].is_read_only(), "complete cell projection and its rows are read-only")
	if actual.is_empty() or not view.has(key):
		runner.assert_true(false, "both read-only APIs expose the genuine source cell")
		return false
	var old_energy: int = int(actual.energy)
	# The nested coordinate array and detached single-row copy can be changed;
	# neither is allowed to mutate the original Q or its coordinate metadata.
	var detached_cell: Array = view[key].cell
	detached_cell[0] = -900
	actual.energy = old_energy + 1
	actual.cell[0] = -901
	runner.assert_eq(int(heat.cell_row(key).energy), old_energy, "changing a detached row cannot write back the physical Q")
	runner.assert_eq(heat.cell_row(key).cell, [116, 116], "changing nested projected arrays cannot move the original cell")
	runner.assert_eq(heat.storage_summary(), {"logical_cells": 100, "q_slots": 24}, "read-only queries do not expand the authority")
	runner.assert_true(_state(compressed) == before, "cell projections do not settle time or change the complete original world")
	var report: Dictionary = Probe.inspect(heat)
	if not bool(report.get("complete", false)):
		runner.assert_true(false, "a bounded probe completes against an actual compressed regional world")
		return false
	runner.assert_true(not bool(report.can_reclaim) and report.cells.size() == 100, "the bounded report names every logical cell without authorizing reclamation")
	var exact: Dictionary = Probe.inspect(heat, int(report.work_used))
	var limited: Dictionary = Probe.inspect(heat, int(report.work_used) - 1)
	runner.assert_true(_json(exact) == _json(report), "the exact work budget reproduces the complete deterministic report")
	runner.assert_true(not bool(limited.complete) and limited.reason == "work_budget_exhausted" and limited.cells.is_empty() and limited.pending.is_empty(), "one unit below the complete budget returns unknown without partial results")
	runner.assert_true(_json(Probe.inspect(reference.environment_fields)) == _json(report), "the same physical world reports identical dependencies from original fine cells")
	runner.assert_true(_state(compressed) == before, "successful and budget-limited inspection cannot change the world")
	return _same(runner, compressed, reference, "queries preserve the same complete fine and compressed world")


func _restore_and_continue(runner: Object, compressed: RegionalSimulation, reference: RegionalSimulation) -> RegionalSimulation:
	var midpoint: int = int(compressed.elapsed_ms) + 173
	if not _advance(runner, compressed, midpoint) or not _advance(runner, reference, midpoint):
		return null
	if not _same(runner, compressed, reference, "mid-segment physical worlds match before JSON"):
		return null
	var before: String = _state(compressed)
	var archive: Dictionary = JSON.parse_string(before)
	runner.assert_eq(int(archive.local_heat.version), 3, "compressed runtime retains the existing v3 heat save format")
	runner.assert_eq(archive.local_heat.cells.size(), 100, "the existing save contains all original logical cells")
	runner.assert_true(not archive.local_heat.has("q_slots") and not archive.local_heat.has("patches"), "derived compression is not saved as a second heat balance")
	var resumed: RegionalSimulation = _world(runner, false)
	if resumed == null:
		return null
	var restored: bool = resumed.restore(archive)
	runner.assert_true(restored, "independent ordinary world restores the complete v3 JSON checkpoint")
	if not restored:
		return null
	runner.assert_true(resumed.environment_fields != compressed.environment_fields and resumed.artifacts != compressed.artifacts, "restoration constructs independent physical owners")
	runner.assert_eq(resumed.environment_fields.storage_summary(), {"logical_cells": 100, "q_slots": 24}, "ordinary restore derives the compact representation from accepted original rows")
	if not _same(runner, resumed, compressed, "JSON restoration preserves all original world facts"):
		return null
	var boundary: int = SimWeather.next_phase_boundary_ms(compressed.weather.definitions, "home", compressed.weather.epoch_ms, midpoint)
	if boundary <= midpoint + 10000 or boundary >= SimInventory.MAX_COUNT - 27337:
		runner.assert_true(false, "the authored weather has a real upcoming phase boundary")
		return null
	var before_weather: String = SimWeather.kind_at(compressed.weather.definitions, "home", compressed.weather.epoch_ms, boundary - 1)
	var after_weather: String = SimWeather.kind_at(compressed.weather.definitions, "home", compressed.weather.epoch_ms, boundary)
	runner.assert_true(before_weather != after_weather, "continuation crosses an actual authored weather change")
	for target: int in [midpoint + 137, midpoint + 10000, boundary - 1, boundary, boundary + 1, boundary + 27337]:
		if not _advance(runner, compressed, target):
			return null
		for split_world: RegionalSimulation in [reference, resumed]:
			var start: int = int(split_world.elapsed_ms)
			var split: int = start + int((target - start) / 2)
			if split > start and not _advance(runner, split_world, split):
				return null
			if not _advance(runner, split_world, target):
				return null
		if not _same(runner, compressed, reference, "fine and compact worlds agree across irregular slices at %d" % target) or not _same(runner, compressed, resumed, "independent JSON world agrees across irregular slices at %d" % target):
			return null
	return resumed


func _overlap_and_device(runner: Object, compressed: RegionalSimulation, reference: RegionalSimulation, resumed: RegionalSimulation) -> void:
	var worlds: Array[RegionalSimulation] = [compressed, reference, resumed]
	var before_charge: int = int(compressed.artifacts.objects[STONE].charge)
	for world: RegionalSimulation in worlds:
		world.regions.home.set_actor_cell("player", Vector2i(117, 116))
		world.invalidate_region("home")
		if not _environment._do(runner, world, "warm"):
			return
		if world.artifacts.events.back().kind != "warmed":
			runner.assert_true(false, "the overlapping source is a genuinely completed action")
			return
	runner.assert_eq(int(compressed.artifacts.objects[STONE].charge), before_charge - 1, "the overlapping source spends its original remaining charge")
	runner.assert_eq(compressed.environment_fields.storage_summary(), {"logical_cells": 105, "q_slots": 48}, "an offset overlap expands the thirty-cell union while three isolated patches remain compressed")
	runner.assert_eq(reference.environment_fields.storage_summary(), {"logical_cells": 105, "q_slots": 105}, "the overlapping reference still retains one Q per physical cell")
	if not _same(runner, compressed, reference, "overlapping original sources match the fine world") or not _same(runner, compressed, resumed, "overlapping original sources match the independent resumed world"):
		return
	for world: RegionalSimulation in worlds:
		world.regions.home.set_actor_cell("player", world.artifacts.object_cell(FIRE))
		world.invalidate_region("home")
		if not _environment._do_actor(runner, world, "player", "study", FIRE) or not _environment._do_actor(runner, world, "player", "enable", FIRE):
			return
		runner.assert_true(bool(world.artifacts.objects[FIRE].enabled), "the actual stationary fire stone is enabled by its learned action")
		var summary: Dictionary = world.environment_fields.storage_summary()
		runner.assert_eq(int(summary.q_slots), int(summary.logical_cells), "an enabled device forces every original heat cell to fine storage")
	if not _same(runner, compressed, reference, "the enabled device preserves the fine world's exact physical state") or not _same(runner, compressed, resumed, "the enabled device preserves the resumed world's exact physical state"):
		return
	var stored: int = int(compressed.artifacts.objects[FIRE].stored_q)
	var future: int = int(compressed.elapsed_ms) + 1737
	for world: RegionalSimulation in worlds:
		if not _advance(runner, world, future):
			return
	runner.assert_true(int(compressed.artifacts.objects[FIRE].stored_q) < stored and int(compressed.environment_fields.continuous_input) > 0, "the enabled artifact spends its real finite stock through elapsed time")
	_same(runner, compressed, reference, "the finite device and expanded world follow the original fine future")
	_same(runner, compressed, resumed, "the finite device and resumed world follow the same future")


func _advance(runner: Object, world: RegionalSimulation, at_ms: int) -> bool:
	var ok: bool = world.advance_to_ms(at_ms)
	runner.assert_true(ok, "the original regional clock reaches %dms" % at_ms)
	return ok


func _same(runner: Object, left: RegionalSimulation, right: RegionalSimulation, label: String) -> bool:
	var equal: bool = _state(left) == _state(right)
	runner.assert_true(equal, label)
	return equal


func _state(world: RegionalSimulation) -> String:
	return _json(world.to_dict())


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
