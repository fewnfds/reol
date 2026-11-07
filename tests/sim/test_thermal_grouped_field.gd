extends RefCounted
## The original field remains the only Q owner. Compare derived acceleration
## against the same field's ungrouped flow path through real semantic changes.

const Fixtures = preload("res://tests/sim/test_local_heat.gd")
const EnvironmentFixture = preload("res://tests/sim/test_local_heat_environment.gd")
var _fixtures := Fixtures.new()


class ReferenceHeat extends SimLocalHeat:
	func _compile_cell_store(_state: Dictionary) -> void:
		_cell_store.expand_all()

	func _rebuild_frozen_groups() -> void:
		_frozen_groups = null


func run(runner: Object) -> void:
	var grouped: Dictionary = _make(false)
	var reference: Dictionary = _make(true)
	for fixture: Dictionary in [grouped, reference]:
		runner.assert_true(bool(fixture.configured), "original fixed-reference field initializes")
		fixture.world.background_schedule.assign([{"at_ms": 5500, "west": -20}, {"at_ms": 20003, "west": 15}])
		for index: int in range(4):
			runner.assert_true(_fixtures._deposit(fixture, "grouped:%d" % index, Vector2i(100 + index * 8, 100)), "original finite pulse allocates its declared patch")
	runner.assert_eq(grouped.heat.cells.size(), 100, "four original 5x5 patches retain all one hundred physical Q rows")
	runner.assert_true(grouped.heat._frozen_groups != null, "actual frozen field selects a beneficial derived group plan")
	runner.assert_true(reference.heat._frozen_groups == null, "the counterfactual uses original per-flow integration")
	runner.assert_eq(_state(grouped), _state(reference), "grouping is absent from and does not change the complete stored field")
	for at_ms: int in [137, 4999, 5500, 5501, 9999, 10000, 17337]:
		if not _reach(runner, grouped, at_ms) or not _reach(runner, reference, at_ms - 1) or not _reach(runner, reference, at_ms):
			return
		runner.assert_eq(_state(grouped), _state(reference), "whole versus sliced physical field matches at weather and frozen boundaries")
		_conserved(runner, grouped)

	var archive: Dictionary = JSON.parse_string(_state(grouped))
	var resumed: Dictionary = _make(false)
	resumed.world.elapsed_ms = grouped.world.elapsed_ms
	resumed.world.artifacts.events.assign(grouped.world.artifacts.events.duplicate(true))
	resumed.world.background_schedule.assign(grouped.world.background_schedule.duplicate(true))
	if not resumed.heat.restore(archive):
		runner.assert_true(false, "independent actual JSON field restores at its non-boundary timestamp")
		return
	runner.assert_true(resumed.heat._frozen_groups != null, "restore derives its own plan referencing its own normalized Q rows")
	runner.assert_eq(_state(resumed), _state(grouped), "reconstructed grouping changes no serialized fact")
	var original_plan: RefCounted = grouped.heat._frozen_groups
	var broken: Dictionary = archive.duplicate(true)
	broken.cells[broken.cells.keys()[0]].energy = -1
	runner.assert_true(not grouped.heat.restore(broken), "malformed physical Q candidate is rejected before assignment")
	runner.assert_true(grouped.heat._frozen_groups == original_plan and _state(grouped) == _state(reference), "failed restore keeps the accepted rows, plan and full field")

	for fixture: Dictionary in [grouped, reference, resumed]:
		fixture.heat.before_topology_change(fixture.world.elapsed_ms)
		fixture.world.roofed = true
		fixture.world.barriers["100,100"] = "wall"
		fixture.heat.after_topology_change(fixture.world.elapsed_ms)
		runner.assert_true(_fixtures._deposit(fixture, "new-original-pulse", Vector2i(100, 100)), "a genuine new source invalidates the preceding frozen rates")
	for at_ms: int in [20002, 20003, 20004, 33737, 60000]:
		if not _reach(runner, grouped, at_ms) or not _reach(runner, reference, at_ms) or not _reach(runner, resumed, at_ms - 1) or not _reach(runner, resumed, at_ms):
			return
		runner.assert_eq(_state(grouped), _state(reference), "source and topology changes preserve the complete ungrouped future")
		runner.assert_eq(_state(resumed), _state(reference), "independent resumed rows and sliced grouping preserve the same future")
	for fixture: Dictionary in [grouped, reference, resumed]:
		runner.assert_true(fixture.heat.mark_sample(60000), "the original minute sample records the physical rows and ledger")
		_conserved(runner, fixture)
	runner.assert_eq(_state(grouped), _state(reference), "minute sample values are unchanged by acceleration")
	runner.assert_eq(_state(resumed), _state(reference), "restored minute sampling uses no original row references")
	_real_sources(runner)
	print("SCENARIO grouped heat field: finite pulses and original artifact charges, climate jumps, topology/source hooks, arbitrary slices, minute samples, independent JSON and atomic rejection")


func _real_sources(runner: Object) -> void:
	var environment := EnvironmentFixture.new()
	var world: RegionalSimulation = environment._world(runner)
	if world == null or not environment._prepare(runner, world):
		return
	var opening_charge: int = int(world.artifacts.objects.hearth_stone.charge)
	for index: int in range(4):
		# Test placement changes the original body, never a duplicate carrier or
		# synthetic thermal receipt. Each heat action pays the real unique stone.
		world.regions.home.set_actor_cell("player", Vector2i(116 + index * 8, 116))
		world.invalidate_region("home")
		if not environment._do(runner, world, "warm"):
			return
	runner.assert_eq(world.environment_fields.cells.size(), 100, "four genuine charged artifact actions retain one hundred original physical cells")
	runner.assert_eq(int(world.artifacts.objects.hearth_stone.charge), opening_charge - 4, "the original artifact pays every pulse exactly once")
	runner.assert_eq(world.environment_fields.input_energy, 4 * int(world.environment_fields.definitions.pulse_energy), "original artifact amounts and the physical field still match")
	runner.assert_eq(world.environment_fields.storage_summary().q_slots, 24, "the genuine isolated regional sources use six unique Q slots each")
	if not world.advance_to_ms(int(world.elapsed_ms) + 173):
		runner.assert_true(false, "genuine regional source reaches a non-boundary snapshot")
		return
	var archive: Dictionary = JSON.parse_string(_json(world.to_dict()))
	var copy: RegionalSimulation = environment._world(runner)
	if copy == null or not copy.restore(archive):
		runner.assert_true(false, "complete real regional JSON with grouped sources restores independently")
		return
	runner.assert_true(copy.environment_fields != world.environment_fields and copy.artifacts != world.artifacts, "restoration keeps independent original field and artifact owners")
	runner.assert_eq(_json(copy.to_dict()), _json(world.to_dict()), "the full real artifact world roundtrips without saving a second group balance")
	var target: int = int(world.elapsed_ms) + 27337
	runner.assert_true(world.advance_to_ms(target), "original regional source world reaches its future")
	runner.assert_true(copy.advance_to_ms(target - 20000) and copy.advance_to_ms(target - 1) and copy.advance_to_ms(target), "independent real world reaches the same future with different slices")
	runner.assert_eq(_json(copy.to_dict()), _json(world.to_dict()), "all real regional domains and source balances match after grouped continuation")


func _make(reference: bool) -> Dictionary:
	var fixture: Dictionary = _fixtures._make()
	if reference:
		var heat := ReferenceHeat.new()
		fixture.configured = heat.initialize(fixture.world, fixture.heat.definitions)
		heat.set_background(fixture.world.background, fixture.world.background_boundary)
		heat.set_geometry(fixture.world.roof, fixture.world.barrier)
		fixture.heat = heat
	return fixture


func _reach(runner: Object, fixture: Dictionary, at_ms: int) -> bool:
	fixture.world.elapsed_ms = at_ms
	var reached: bool = fixture.heat.settle_at_ms(at_ms)
	runner.assert_true(reached, "original physical clock reaches %d" % at_ms)
	return reached


func _state(fixture: Dictionary) -> String:
	return _json(fixture.heat.to_dict())


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _conserved(runner: Object, fixture: Dictionary) -> void:
	var q: int = 0
	for row: Dictionary in fixture.heat.cells.values():
		q += int(row.energy)
	runner.assert_eq(q + int(fixture.heat.loss_energy), int(fixture.heat.input_energy) + int(fixture.heat.ambient_in), "all original physical Q and ambient transfers conserve finite source energy")
