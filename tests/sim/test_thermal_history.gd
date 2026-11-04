extends RefCounted
## Historical coverage and samples do not own current Q or frozen flows.
## The full schema still proves those current states and original sources.

const History = preload("res://scripts/sim/thermal_history.gd")
const Sample = preload("res://scripts/sim/thermal_sample.gd")
const HeatFixtures = preload("res://tests/sim/test_local_heat.gd")
const EnvironmentFixtures = preload("res://tests/sim/test_local_heat_environment.gd")
const DeviceFixtures = preload("res://tests/sim/test_thermal_devices.gd")
const AbsoluteFixtures = preload("res://tests/sim/test_absolute_heat.gd")
const CELL: Vector2i = Vector2i(100, 100)

var _heat_fixtures := HeatFixtures.new()
var _environment := EnvironmentFixtures.new()
var _devices := DeviceFixtures.new()
var _absolute := AbsoluteFixtures.new()


func run(runner: Object) -> void:
	_real_sources_and_restore(runner)
	_same_millisecond_and_legacy(runner)
	_zero_and_negative_samples(runner)
	_coverage_union_and_edges(runner)
	_coverage_budget(runner)
	_conversion_switch_bounds(runner)
	_source_validation_boundary(runner)
	print("SCENARIO thermal history: original paid sources, detached historical evidence, same-ms alternatives, zero and negative samples, bounded legacy interpretation and complete future")


func _real_sources_and_restore(runner: Object) -> void:
	var world: RegionalSimulation = _environment._world(runner)
	if world == null or not _environment._prepare(runner, world) or not _environment._do(runner, world, "warm"):
		return
	var warm: Dictionary = world.local_heat.to_dict()
	runner.assert_true(not warm.receipts.is_empty(), "a real completed warm-stone action creates the original source receipt")
	_check_detached(runner, world.local_heat, warm, "actual warm pulse")
	if not _devices._action(runner, world, "player", "study", DeviceFixtures.FIRE) or not _devices._action(runner, world, "player", "enable", DeviceFixtures.FIRE):
		return
	var enabled: Dictionary = world.local_heat.to_dict()
	runner.assert_true(bool(world.artifacts.objects[DeviceFixtures.FIRE].enabled), "the original finite fire stone is actually enabled")
	runner.assert_eq(enabled.device_switches.size(), 1, "the actual enable has one original thermal switch")
	_check_detached(runner, world.local_heat, enabled, "actual same-cell fire enable")
	_check_same_ms_enable(runner, world.local_heat, enabled)
	if not _devices._action(runner, world, "player", "disable", DeviceFixtures.FIRE):
		return
	var heat: SimLocalHeat = world.local_heat
	var saved: Dictionary = JSON.parse_string(_json(world.to_dict()))
	var data: Dictionary = saved.local_heat
	runner.assert_true(not bool(world.artifacts.objects[DeviceFixtures.FIRE].enabled), "the original device actually finishes its disable action")
	runner.assert_eq(data.device_switches.size(), 2, "enable and disable retain their separate original receipts")
	runner.assert_true(int(data.continuous_input) > 0, "the finite device emitted real heat before closing")
	_check_detached(runner, heat, data, "completed fire disable")

	var coverage: Dictionary = History.source_coverage(heat, data)
	if not bool(coverage.get("supported", false)) or data.last_sample_cells.is_empty() or data.cells.is_empty():
		runner.assert_true(false, "real source produces supported nonempty sampled coverage")
		return
	var sample_key: String = str(data.last_sample_cells.keys()[0])
	var cell_key: String = str(data.cells.keys()[0])
	var bad: Dictionary = data.duplicate(true)
	bad.last_sample_cells[sample_key] = int(bad.last_sample_cells[sample_key]) + 1
	runner.assert_true(not Sample.validate(heat, bad, coverage), "a changed historical Q breaks its own sample accounting")
	bad = data.duplicate(true)
	bad.last_sample_loss = int(bad.last_sample_loss) + 1
	runner.assert_true(not Sample.validate(heat, bad, coverage), "a changed sampled loss is rejected independently of the live cells")
	bad = data.duplicate(true)
	bad.last_sample_cells["-1,0"] = bad.last_sample_cells[sample_key]
	bad.last_sample_cells.erase(sample_key)
	runner.assert_true(not Sample.validate(heat, bad, coverage), "a sample outside its actual source coverage is rejected")
	bad = data.duplicate(true)
	bad.cells[cell_key].allocated_ms = int(bad.cells[cell_key].allocated_ms) + 1
	runner.assert_true(Sample.validate(heat, bad, coverage), "historical sample does not read a changed current allocation row")
	runner.assert_true(not SimThermalSchema.validate(heat, bad), "the full candidate rejects a changed current allocation row")
	bad = data.duplicate(true)
	bad.cells[cell_key].baseline_energy = int(bad.cells[cell_key].baseline_energy) + 1
	runner.assert_true(Sample.validate(heat, bad, coverage), "historical sample does not trust a changed current baseline row")
	runner.assert_true(not SimThermalSchema.validate(heat, bad), "the full candidate rejects a changed current baseline")
	bad = data.duplicate(true)
	bad.cells[cell_key].energy = int(bad.cells[cell_key].energy) + 1
	runner.assert_true(Sample.validate(heat, bad, coverage), "historical sample does not read current Q")
	runner.assert_true(not SimThermalSchema.validate(heat, bad), "the full candidate still rejects unconserved current Q")

	var resumed: RegionalSimulation = _environment._world(runner)
	if resumed == null:
		return
	var restored: bool = resumed.restore(saved)
	runner.assert_true(restored, "a separate regional owner restores the real source and its historical slice")
	if not restored:
		return
	runner.assert_eq(_json(resumed.to_dict()), _json(saved), "JSON restore preserves the complete real world")
	var start: int = int(world.elapsed_ms)
	var end: int = start + 62347
	if not _devices._advance(runner, world, end) or not _devices._advance(runner, resumed, start + 137) or not _devices._advance(runner, resumed, end):
		return
	runner.assert_eq(_json(resumed.to_dict()), _json(world.to_dict()), "whole and split restored futures retain the same complete world")


func _check_detached(runner: Object, heat: SimLocalHeat, data: Dictionary, label: String) -> void:
	var before: String = _json(data)
	var coverage: Dictionary = History.source_coverage(heat, data)
	runner.assert_true(bool(coverage.get("supported", false)), label + " has complete bounded original-source coverage")
	if not bool(coverage.get("supported", false)):
		return
	runner.assert_true(History.valid_legacy_limits(data, coverage, int(heat.definitions.pulse_energy)), label + " retains its original legacy bounds")
	runner.assert_true(Sample.validate(heat, data, coverage), label + " historical sample has its own valid evidence and balance")
	runner.assert_true(SimThermalSchema.validate(heat, data), label + " complete candidate independently validates current Q and sources")
	var detached: Dictionary = data.duplicate(true)
	detached.erase("cells")
	detached.erase("flows")
	var detached_coverage: Dictionary = History.source_coverage(heat, detached)
	runner.assert_eq(_json(detached_coverage), _json(coverage), label + " source coverage does not require current cells or frozen flows")
	runner.assert_true(Sample.validate(heat, detached, detached_coverage), label + " historical sample does not require current cells or frozen flows")
	runner.assert_true(not SimThermalSchema.validate(heat, detached), label + " is not accepted as a complete candidate without current Q")
	runner.assert_eq(_json(data), before, label + " read-only coverage and sample checks leave the supplied data unchanged")


func _check_same_ms_enable(runner: Object, heat: SimLocalHeat, data: Dictionary) -> void:
	if data.device_switches.size() != 1 or data.last_sample_cells.is_empty():
		runner.assert_true(false, "same-ms device check has its actual switch and earlier warm sample")
		return
	var change: Dictionary = data.device_switches.values()[0]
	runner.assert_eq(int(data.last_sample_ms), int(change.at_ms), "the real device enable and a thermal sample share one millisecond")
	if int(data.last_sample_ms) != int(change.at_ms):
		return
	var coverage: Dictionary = History.source_coverage(heat, data)
	if not bool(coverage.get("supported", false)):
		runner.assert_true(false, "actual same-ms device has supported coverage")
		return
	# Helper-only malformed evidence: balance the artificial one-Q emission in
	# the sample so the check cannot reject it merely for an unequal ledger.
	var forged: Dictionary = data.duplicate(true)
	forged.continuous_input = 1
	forged.last_sample_continuous_input = 1
	var key: String = str(forged.last_sample_cells.keys()[0])
	forged.last_sample_cells[key] = int(forged.last_sample_cells[key]) + 1
	runner.assert_true(not Sample.validate(heat, forged, coverage), "same-ms enable cannot justify heat emitted before time has elapsed")


func _same_millisecond_and_legacy(runner: Object) -> void:
	var fixture: Dictionary = _heat_fixtures._make()
	var heat: SimLocalHeat = fixture.heat
	_heat_fixtures._advance(fixture, 60000)
	runner.assert_true(heat.mark_sample(60000), "the actual minute sample is recorded before the following source")
	var deposited: bool = _heat_fixtures._deposit(fixture, "warm:same_ms", CELL)
	runner.assert_true(deposited, "the isolated kernel pulse can be deposited later at the exact sample millisecond")
	if not deposited:
		return
	var data: Dictionary = heat.to_dict()
	var coverage: Dictionary = History.source_coverage(heat, data)
	runner.assert_true(bool(coverage.get("supported", false)), "same-ms source has supported patch coverage")
	if not bool(coverage.get("supported", false)):
		return
	runner.assert_eq(int(coverage.allocations["100,100"]), 60000, "coverage preserves the real first-allocation millisecond")
	runner.assert_true(data.last_sample_cells.is_empty() and int(data.last_sample_input) == 0, "the earlier sample does not invent the later source")
	_check_detached(runner, heat, data, "same-ms source after sample")

	# This is a helper-only hypothetical ordering, derived from the isolated
	# kernel's just-deposited Q and receipt. It is not an authenticated
	# original action ordering or a complete-world snapshot.
	var before_sample: Dictionary = data.duplicate(true)
	for key: String in data.cells:
		before_sample.last_sample_cells[key] = int(data.cells[key].energy)
	before_sample.last_sample_input = int(data.input_energy)
	before_sample.last_sample_ambient_in = int(data.ambient_in)
	before_sample.erase("cells")
	before_sample.erase("flows")
	runner.assert_true(Sample.validate(heat, before_sample, coverage), "helper also accepts a same-ms allocation represented in the sample")
	var impossible: Dictionary = before_sample.duplicate(true)
	impossible.last_sample_input = int(data.input_energy) + int(heat.definitions.pulse_energy)
	runner.assert_true(not Sample.validate(heat, impossible, coverage), "a same-ms sample cannot claim more pulses than its receipts")

	# Construct only historical helper input from the kernel pulse snapshot.
	# This checks the old excess-only representation; no old archive is forged.
	var legacy: Dictionary = data.duplicate(true)
	legacy.model_started_ms = 60001
	legacy.segment_started_ms = 60001
	legacy.last_ms = 60001
	legacy.last_sample_mode = "legacy_excess"
	legacy.last_sample_cells = {"100,100": int(heat.definitions.pulse_energy)}
	legacy.last_sample_input = int(heat.definitions.pulse_energy)
	legacy.last_sample_loss = 0
	legacy.last_sample_ambient_in = 0
	legacy.last_sample_continuous_input = 0
	legacy.last_sample_absorbed = 0
	var old_coverage: Dictionary = History.source_coverage(heat, legacy)
	if not bool(old_coverage.get("supported", false)):
		runner.assert_true(false, "helper-only legacy source coverage is derived from the isolated pulse")
		return
	var old_cells: Array = old_coverage.before_model_cells.keys()
	old_cells.sort()
	legacy.legacy_limits = {"at_ms": 60001, "input_energy": int(heat.definitions.pulse_energy), "cells": old_cells}
	legacy.erase("cells")
	legacy.erase("flows")
	runner.assert_true(History.valid_legacy_limits(legacy, old_coverage, int(heat.definitions.pulse_energy)), "legacy bounds retain the pulse-only converted footprint")
	runner.assert_true(Sample.validate(heat, legacy, old_coverage), "legacy excess-only nonzero sample remains independently valid")
	var bad: Dictionary = legacy.duplicate(true)
	bad.last_sample_cells["100,100"] = 0
	runner.assert_true(not Sample.validate(heat, bad, old_coverage), "legacy sparse representation cannot contain a zero excess entry")
	bad = legacy.duplicate(true)
	bad.legacy_limits.cells.pop_back()
	runner.assert_true(not History.valid_legacy_limits(bad, old_coverage, int(heat.definitions.pulse_energy)), "legacy bounds cannot omit a pre-conversion source cell")


func _zero_and_negative_samples(runner: Object) -> void:
	var rules: Dictionary = _heat_fixtures._rules()
	rules.pulse_energy = 1
	var zero: Dictionary = _heat_fixtures._make(rules)
	var reference: int = int(rules.reference_tenths)
	_absolute._configure_weather(zero, reference, reference, [])
	if not _heat_fixtures._deposit(zero, "warm:zero_q", CELL):
		runner.assert_true(false, "reference-background zero-Q fixture accepts its finite pulse")
		return
	_heat_fixtures._advance(zero, 60000)
	runner.assert_true(zero.heat.mark_sample(60000), "zero-Q source reaches a real minute sample")
	var zero_data: Dictionary = zero.heat.to_dict()
	runner.assert_true(zero_data.last_sample_cells.has("98,98") and int(zero_data.last_sample_cells["98,98"]) == 0, "absolute history explicitly retains an allocated zero-Q cell")
	_check_detached(runner, zero.heat, zero_data, "zero-Q absolute sample")
	var zero_view: Dictionary = _heat_fixtures._make(rules, 60000)
	_absolute._configure_weather(zero_view, reference, reference, [])
	_copy_sample_only(zero_view.heat, zero_data)
	runner.assert_true(zero_view.heat.cells.is_empty(), "zero-Q historical view has no current cells")
	runner.assert_true(not zero_view.heat.has_visible_offsets(true), "sub-tenth historical energy alone is not a visible temperature deviation")

	var negative_rules: Dictionary = _absolute._isolated_rules()
	var negative: Dictionary = _heat_fixtures._make(negative_rules)
	var changes: Array[Dictionary] = [{"at_ms": 3257, "west": 300}]
	_absolute._configure_weather(negative, 0, 0, changes)
	if not _heat_fixtures._deposit(negative, "warm:negative", CELL):
		runner.assert_true(false, "signed fixture accepts its original finite pulse")
		return
	_heat_fixtures._advance(negative, 60000)
	runner.assert_true(negative.heat.mark_sample(60000), "changed outdoor background produces a real signed sample")
	var negative_data: Dictionary = negative.heat.to_dict()
	var expected: int = int(negative.heat.sample_tenths(CELL, 60000))
	runner.assert_true(expected < 0, "the original sample is colder than its historical outdoor background")
	_check_detached(runner, negative.heat, negative_data, "negative historical sample")
	var view: Dictionary = _heat_fixtures._make(negative_rules, 60000)
	_absolute._configure_weather(view, 0, 0, changes)
	_copy_sample_only(view.heat, negative_data)
	runner.assert_true(view.heat.cells.is_empty(), "signed historical view has no current Q rows")
	runner.assert_eq(view.heat.sample_tenths(CELL, 60000), expected, "sample reads its original time and Q without a live row")
	runner.assert_true(view.heat.has_visible_offsets(true), "historical visibility observes a negative sample without a live row")
	runner.assert_true(not view.heat.has_visible_offsets(false), "current visibility remains independent from a retained historical sample")


func _coverage_union_and_edges(runner: Object) -> void:
	var fixture: Dictionary = _heat_fixtures._make()
	var heat: SimLocalHeat = fixture.heat
	var pulse: int = int(heat.definitions.pulse_energy)
	var background_calls: Dictionary = {"value": 0, "boundary": 0}
	var background: Callable = func(_cell: Vector2i, _at_ms: int) -> int:
		background_calls.value = int(background_calls.value) + 1
		return 0
	var boundary: Callable = func(_cell: Vector2i, _at_ms: int) -> int:
		background_calls.boundary = int(background_calls.boundary) + 1
		return SimInventory.MAX_COUNT
	heat.set_background(background, boundary)
	# These are helper-only records: they exercise coverage independently of
	# authentication, the actual live field and any fabricated heat balance.
	var data: Dictionary = _source_only(0, 20)
	data.receipts["earlier"] = _source_receipt("earlier", [100, 100], 10, pulse)
	data.receipts["later"] = _source_receipt("later", [101, 100], 20, pulse)
	var input_before: String = _json(data)
	var owner_before: String = _fixture_facts(fixture)
	var calls_before: String = _json(background_calls)
	var coverage: Dictionary = History.source_coverage(heat, data)
	runner.assert_true(bool(coverage.get("supported", false)), "overlapping helper source records yield bounded coverage")
	if not bool(coverage.get("supported", false)):
		return
	runner.assert_eq(coverage.allocations.size(), 30, "overlapping five-by-five patches are represented by their exact 30-cell union")
	runner.assert_eq(int(coverage.allocations.get("98,100", -1)), 10, "a cell unique to the earlier source retains its own allocation time")
	runner.assert_eq(int(coverage.allocations.get("100,100", -1)), 10, "an overlap retains the first actual source time")
	runner.assert_eq(int(coverage.allocations.get("103,100", -1)), 20, "a cell unique to the later source retains the later allocation time")
	runner.assert_eq(int(coverage.receipt_sum), 2 * pulse, "overlap merges space without merging either source amount")
	var reversed: Dictionary = data.duplicate(true)
	reversed.receipts = {"later": data.receipts.later.duplicate(true), "earlier": data.receipts.earlier.duplicate(true)}
	runner.assert_eq(_json(History.source_coverage(heat, reversed)), _json(coverage), "receipt insertion order cannot change first allocation or the coverage union")
	var edge: Dictionary = _source_only(0, 20)
	# JSON can roundtrip exact coordinates as integral floats. Resulting keys
	# are still canonical integer coordinates, clipped to the map bounds.
	edge.receipts["edge"] = _source_receipt("edge", [0.0, 0.0], 10, pulse)
	var clipped: Dictionary = History.source_coverage(heat, edge)
	runner.assert_true(bool(clipped.get("supported", false)), "an integral JSON-coordinate source at the world corner has supported coverage")
	if bool(clipped.get("supported", false)):
		runner.assert_eq(clipped.allocations.size(), 9, "a radius-two corner patch clips to nine in-bounds cells")
		for y: int in range(3):
			for x: int in range(3):
				var key: String = "%d,%d" % [x, y]
				runner.assert_true(clipped.allocations.has(key) and int(clipped.allocations[key]) == 10, "corner coverage uses its canonical nonnegative integer key: " + key)
	runner.assert_eq(_json(data), input_before, "coverage derivation does not alter its source records")
	runner.assert_eq(_fixture_facts(fixture), owner_before, "coverage derivation does not advance heat or call its geometry providers")
	runner.assert_eq(_json(background_calls), calls_before, "coverage derivation never calls a custom background or boundary provider")


func _coverage_budget(runner: Object) -> void:
	var rules: Dictionary = _heat_fixtures._rules()
	rules.max_cells = 25
	runner.assert_true(SimLocalHeat.valid_definitions(rules), "the original heat schema permits a 25-cell bounded fixture")
	var fixture: Dictionary = _heat_fixtures._make(rules)
	if not bool(fixture.configured):
		runner.assert_true(false, "bounded source fixture initializes")
		return
	var heat: SimLocalHeat = fixture.heat
	var pulse: int = int(rules.pulse_energy)
	var single: Dictionary = _source_only(0, 20)
	single.receipts["first"] = _source_receipt("first", [100, 100], 10, pulse)
	var accepted: Dictionary = History.source_coverage(heat, single)
	runner.assert_true(bool(accepted.get("supported", false)) and accepted.get("allocations", {}).size() == 25, "exactly one 25-cell patch fits the declared coverage limit")
	var too_many: Dictionary = single.duplicate(true)
	too_many.receipts["second"] = _source_receipt("second", [110, 100], 20, pulse)
	var owner_before: String = _fixture_facts(fixture)
	var before: String = _json(too_many)
	var rejected: Dictionary = History.source_coverage(heat, too_many)
	runner.assert_eq(rejected, {"supported": false, "reason": "coverage_budget"}, "a second disjoint pulse returns only an explicit budget failure")
	runner.assert_eq(_json(too_many), before, "budget rejection leaves the supplied source records unchanged")
	runner.assert_eq(_fixture_facts(fixture), owner_before, "budget rejection leaves the actual heat owner and time unchanged")
	var enabled: Dictionary = single.duplicate(true)
	enabled.device_switches["switch"] = _source_switch("switch", [110, 100], 20, true)
	var enable_before: String = _json(enabled)
	runner.assert_eq(History.source_coverage(heat, enabled), {"supported": false, "reason": "coverage_budget"}, "pulse and enabled-device patches share the same 25-cell coverage limit")
	runner.assert_eq(_json(enabled), enable_before, "device coverage refusal also leaves its input unchanged")
	enabled.device_switches.switch.enabled = false
	var disabled: Dictionary = History.source_coverage(heat, enabled)
	runner.assert_true(bool(disabled.get("supported", false)) and disabled.get("allocations", {}).size() == 25, "a disable record does not allocate an additional source patch")
	runner.assert_eq(_fixture_facts(fixture), owner_before, "all bounded helper checks remain detached from the live heat owner")


func _conversion_switch_bounds(runner: Object) -> void:
	var fixture: Dictionary = _heat_fixtures._make()
	var heat: SimLocalHeat = fixture.heat
	var pulse: int = int(heat.definitions.pulse_energy)
	var model_start: int = 60001
	var data: Dictionary = _source_only(model_start, model_start)
	data.receipts["prior"] = _source_receipt("prior", [100, 100], model_start - 1, pulse)
	data.receipts["same"] = _source_receipt("same", [110, 100], model_start, pulse)
	data.device_switches["same_enable"] = _source_switch("same_enable", [120, 100], model_start, true)
	var owner_before: String = _fixture_facts(fixture)
	var coverage: Dictionary = History.source_coverage(heat, data)
	runner.assert_true(bool(coverage.get("supported", false)), "independent historical helper can inspect pulse and switch evidence at conversion time")
	if not bool(coverage.get("supported", false)):
		return
	runner.assert_eq(coverage.allocations.size(), 75, "two pulse patches and one device patch all contribute to the allocation union")
	runner.assert_eq(coverage.before_model_cells.size(), 25, "only the strictly earlier pulse contributes before-conversion cells")
	runner.assert_eq(coverage.through_model_cells.size(), 50, "the same-ms pulse, but not the device, contributes through-conversion cells")
	runner.assert_eq(int(coverage.before_input), pulse, "before-conversion input includes the earlier pulse exactly once")
	runner.assert_eq(int(coverage.through_input), 2 * pulse, "through-conversion input includes both original pulse amounts")
	runner.assert_eq(int(coverage.allocations.get("120,100", -1)), model_start, "same-ms device allocation is retained at the model start")
	runner.assert_true(not coverage.before_model_cells.has("120,100") and not coverage.through_model_cells.has("120,100"), "same-ms device cells do not become old pulse-only evidence")
	var prior_cells: Array = coverage.before_model_cells.keys()
	prior_cells.sort()
	data.legacy_limits = {"at_ms": model_start, "input_energy": pulse, "cells": prior_cells}
	var before: String = _json(data)
	runner.assert_true(History.valid_legacy_limits(data, coverage, pulse), "the earlier pulse alone is a permitted same-ms conversion ordering")
	var through_cells: Array = coverage.through_model_cells.keys()
	through_cells.sort()
	var both: Dictionary = data.duplicate(true)
	both.legacy_limits.input_energy = 2 * pulse
	both.legacy_limits.cells = through_cells.duplicate()
	runner.assert_true(History.valid_legacy_limits(both, coverage, pulse), "both pulse patches can also precede conversion at the same millisecond")
	var forged: Dictionary = both.duplicate(true)
	# Preserve the old cell count and every strictly earlier cell, so rejection
	# cannot be attributed solely to an oversized or incomplete old set.
	forged.legacy_limits.cells.erase("108,98")
	forged.legacy_limits.cells.append("120,100")
	forged.legacy_limits.cells.sort()
	runner.assert_eq(forged.legacy_limits.cells.size(), through_cells.size(), "forged old set retains the original allowed cell count")
	runner.assert_true(not History.valid_legacy_limits(forged, coverage, pulse), "a same-ms device-only cell cannot be presented as pre-conversion pulse coverage")
	runner.assert_eq(_json(data), before, "legacy boundary checking does not alter the accepted source evidence")
	runner.assert_eq(_fixture_facts(fixture), owner_before, "helper-only conversion alternatives never alter live heat or time")


func _source_validation_boundary(runner: Object) -> void:
	var fixture: Dictionary = _heat_fixtures._make()
	var heat: SimLocalHeat = fixture.heat
	_heat_fixtures._advance(fixture, 10)
	if not _heat_fixtures._deposit(fixture, "warm:original", CELL):
		runner.assert_true(false, "source-validation fixture deposits its original authenticated pulse")
		return
	var good: Dictionary = heat.to_dict()
	var before: String = _json(good)
	# Full schema validation deliberately queries geometry to reconstruct the
	# frozen segment; those instrumentation counters are not world state.
	var owner_before: String = _fixture_facts(fixture, false)
	var coverage: Dictionary = History.source_coverage(heat, good)
	runner.assert_true(bool(coverage.get("supported", false)) and SimThermalSchema.validate(heat, good), "the original event, receipt and complete candidate are independently valid")
	if not bool(coverage.get("supported", false)):
		return
	var malformed: Array[Dictionary] = []
	var bad: Dictionary = good.duplicate(true)
	bad.receipts["warm:original"].action = "different_action"
	malformed.append(bad)
	for cell: Array in [[-1, 0], [1.5, 100], [true, 100]]:
		bad = good.duplicate(true)
		bad.receipts["warm:original"].cell = cell
		malformed.append(bad)
	bad = good.duplicate(true)
	bad.receipts["warm:original"].at_ms = int(good.segment_started_ms) + 1
	malformed.append(bad)
	bad = good.duplicate(true)
	bad.receipts["warm:original"].amount = int(bad.receipts["warm:original"].amount) + 1
	malformed.append(bad)
	for invalid: Dictionary in malformed:
		var input_before: String = _json(invalid)
		runner.assert_eq(History.source_coverage(heat, invalid), {"supported": false, "reason": "invalid_receipt"}, "malformed identity, coordinate, time or amount yields no partial coverage")
		runner.assert_eq(_json(invalid), input_before, "source rejection never repairs the supplied record")
	var bad_switch: Dictionary = good.duplicate(true)
	bad_switch.device_switches["switch"] = _source_switch("different", [100, 100], 10, true)
	var switch_before: String = _json(bad_switch)
	runner.assert_eq(History.source_coverage(heat, bad_switch), {"supported": false, "reason": "invalid_switch"}, "a switch whose key and action differ is rejected without partial coverage")
	runner.assert_eq(_json(bad_switch), switch_before, "invalid switch inspection is read-only")
	var fake: Dictionary = good.duplicate(true)
	fake.receipts["warm:original"].object = "forged_stone"
	var geometric: Dictionary = History.source_coverage(heat, fake)
	runner.assert_true(bool(geometric.get("supported", false)) and geometric.allocations == coverage.allocations, "shape-valid helper coverage is spatial evidence, not source authentication")
	runner.assert_true(not SimThermalSchema.validate(heat, fake), "the complete candidate rejects a receipt that disagrees with the original source event")
	runner.assert_eq(_json(good), before, "source checks leave the original candidate unchanged")
	runner.assert_eq(_fixture_facts(fixture, false), owner_before, "successful and rejected source checks do not alter the live heat owner or its event log")


func _source_only(model_start: int, segment: int) -> Dictionary:
	# No cells, flows, Q or real-source assertion; used only to test the pure
	# historical projection and its bounded acceptance contract.
	return {"activation_ms": 0, "model_started_ms": model_start,
		"segment_started_ms": segment, "last_ms": segment, "receipts": {},
		"device_switches": {}, "legacy_limits": {}}


func _source_receipt(action: String, cell: Array, at_ms: int, amount: int) -> Dictionary:
	return {"action": action, "actor": "player", "object": "warm_stone",
		"at_ms": at_ms, "cell": cell.duplicate(), "amount": amount}


func _source_switch(action: String, cell: Array, at_ms: int, enabled: bool) -> Dictionary:
	return {"action": action, "actor": "player", "object": "fire_stone",
		"at_ms": at_ms, "region": "home", "container": "kitchen",
		"cell": cell.duplicate(), "enabled": enabled}


func _fixture_facts(fixture: Dictionary, include_queries: bool = true) -> String:
	# to_dict only normalizes the initially dirty, empty fixture before the first
	# observation; no source query itself may settle Q, move time or touch geometry.
	var facts: Dictionary = {"heat": fixture.heat.to_dict(), "elapsed_ms": int(fixture.world.elapsed_ms),
		"events": fixture.world.artifacts.events}
	if include_queries:
		facts["roof_queries"] = int(fixture.world.roof_queries)
		facts["barrier_queries"] = int(fixture.world.barrier_queries)
	return _json(facts)


func _copy_sample_only(heat: SimLocalHeat, data: Dictionary) -> void:
	# Deliberately incomplete read-only test double, not a valid full save.
	heat.last_sample_ms = int(data.last_sample_ms)
	heat.last_sample_mode = str(data.last_sample_mode)
	heat.last_sample_cells = data.last_sample_cells.duplicate(true)


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
