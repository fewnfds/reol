extends RefCounted
## Integration of the existing field/temperature coordinator with the actual
## five-channel owner. Real-world lifecycle tests are separate.

const Field = preload("res://scripts/sim/environment_field_cache.gd")
const Temperature = preload("res://scripts/sim/environment_temperature_state.gd")
const Phases = preload("res://scripts/sim/environment_phase_state.gd")
const SourceChange = preload("res://scripts/sim/environment_source_change.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const Tide = preload("res://scripts/sim/environment_field_tide.gd")
const SegmentFixture = preload("res://tests/sim/test_environment_temperature_segments.gd")

const MAP := Vector2i(20, 1)
const A := Vector2i(1, 0)
const B := Vector2i(17, 0)
const VALUES := [1000, 2000, 3000, 4000, 5000]
const GRID: int = 10_000
const HORIZON: int = 30_000


func run(runner: Object) -> void:
	_continuous_move(runner)
	_boundary_transition(runner)
	_failure_and_cancel(runner)
	_restore_invalidates_proof(runner)
	print("SCENARIO environmental field response: five channels, retargeting, boundaries and atomic candidates")


func _fixture(runner: Object, phase_initial: String = "_phase_zero") -> Dictionary:
	var field := Field.new()
	var temperature := Temperature.new()
	var phases := Phases.new()
	var coordinator := SourceChange.new()
	var source := SegmentFixture.new()
	var settings: Dictionary = {"climate": source._climate(), "weather": source._weather(),
		"weather_epoch_ms": 0, "seed": 42, "tau_ms": 1000, "tide_grid_ms": GRID}
	var configured: bool = field.configure(MAP, 4) and temperature.configure(MAP, 20, 0) and phases.configure(MAP, 20, 0)
	if configured:
		configured = coordinator.configure(field, temperature, settings, Callable(self, "_temperature_initial"), phases, Callable(self, phase_initial))
	runner.assert_true(configured, "the field, temperature and five-channel owners configure together")
	return {"field": field, "temperature": temperature, "phases": phases, "coordinator": coordinator} if configured else {}


func _temperature_initial(_cell: Vector2i, _at_ms: int) -> Dictionary:
	return {"ok": true, "value_c": 20.0}


func _phase_zero(_cell: Vector2i, _at_ms: int) -> Dictionary:
	return {"ok": true, "values": PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])}


func _phase_bad(_cell: Vector2i, _at_ms: int) -> Dictionary:
	return {"ok": true, "values": PackedFloat64Array([-1.0, 0.0, 0.0, 0.0, 0.0])}


func _source(cell: Vector2i) -> Dictionary:
	return {"cell": cell, "radius": 1, "channels": [1000, 2000, 3000, 4000, 5000, 1000, 0]}


func _prepare(runner: Object, ctx: Dictionary, operation: String, cell: Vector2i, at_ms: int) -> Dictionary:
	var coordinator: RefCounted = ctx.coordinator
	var input: Dictionary = {} if operation == "remove" else _source(cell)
	var opened: Dictionary = coordinator.begin(0, operation, input, at_ms, HORIZON)
	runner.assert_true(bool(opened.get("ok", false)), "the source candidate opens: %s" % str(opened))
	if not bool(opened.get("ok", false)):
		return opened
	for _step: int in 1000:
		var result: Dictionary = coordinator.step(opened.handle, 100_000, 256)
		if not bool(result.get("ok", false)):
			return result
		if not bool(result.get("pending", true)):
			var sealed: Dictionary = coordinator.finish(opened.handle)
			if bool(sealed.get("ok", false)):
				return {"ok": true, "handle": opened.handle, "proof": sealed.proof}
			return sealed
	runner.assert_true(false, "bounded candidate work eventually finishes")
	return {"ok": false, "reason": "drive_limit"}


func _publish(runner: Object, ctx: Dictionary, operation: String, cell: Vector2i, at_ms: int) -> bool:
	var ready: Dictionary = _prepare(runner, ctx, operation, cell, at_ms)
	runner.assert_true(bool(ready.get("ok", false)), "field and actual-state candidate reaches ready: %s" % str(ready))
	if not bool(ready.get("ok", false)):
		return false
	var result: Dictionary = ctx.coordinator.commit(ready.proof)
	runner.assert_true(bool(result.get("ok", false)), "all three completed candidates publish together")
	return bool(result.get("ok", false))


func _close(runner: Object, actual: float, expected: float, label: String) -> void:
	runner.assert_true(is_finite(actual) and absf(actual - expected) <= 0.000_001, "%s: %s vs %s" % [label, actual, expected])


func _target(cell: Vector2i, time_grid: int, channel: int) -> float:
	var tide: Dictionary = Tide.sample(42, cell, time_grid)
	return float(Rules.effective_grade(VALUES[channel], int(tide.multiplier)))


func _continuous_move(runner: Object) -> void:
	var ctx: Dictionary = _fixture(runner)
	if ctx.is_empty() or not _publish(runner, ctx, "set", A, 0):
		return
	var phases: RefCounted = ctx.phases
	var temperature: RefCounted = ctx.temperature
	runner.assert_eq(phases.actual_at(A, 0).values, PackedFloat64Array([0, 0, 0, 0, 0]), "new source does not instantly fill its surroundings")
	var old: PackedFloat64Array = phases.actual_at(A, 1000).values
	for channel: int in 5:
		_close(runner, old[channel], _target(A, 0, channel) * (1.0 - exp(-1.0)), "each phase establishes from its prior actual value")
	var old_temp: float = float(temperature.actual_at(A, 1000).value_c)
	runner.assert_true(old_temp > 20.0, "the hot source gradually heats its initial cell")
	var temp_snapshot: Dictionary = temperature.snapshot()
	var phase_snapshot: Dictionary = phases.snapshot()
	for t: int in [0, 1000, 500, 1000]:
		phases.actual_at(A, t)
		temperature.actual_at(A, t)
	runner.assert_eq(temperature.snapshot(), temp_snapshot, "temperature observation does not advance its state")
	runner.assert_eq(phases.snapshot(), phase_snapshot, "phase observation does not advance its state")
	if not _publish(runner, ctx, "set", B, 1000):
		return
	for channel: int in 5:
		_close(runner, phases.actual_at(A, 1000).values[channel], old[channel], "the old site keeps its actual influence at the move")
		_close(runner, phases.actual_at(A, 2000).values[channel], old[channel] * exp(-1.0), "the old site retains and gradually loses its residual")
		_close(runner, phases.actual_at(B, 1000).values[channel], 0.0, "the new site starts from its own initial condition")
		_close(runner, phases.actual_at(B, 2000).values[channel], _target(B, 0, channel) * (1.0 - exp(-1.0)), "the new site establishes its own five-channel field")
	_close(runner, float(temperature.actual_at(A, 1000).value_c), old_temp, "temperature is continuous at the source change")
	runner.assert_true(float(temperature.actual_at(A, 2000).value_c) < old_temp, "the old hot spot gradually cools")
	runner.assert_true(float(temperature.actual_at(B, 2000).value_c) > 20.0, "the new location gradually warms")
	if not _publish(runner, ctx, "remove", Vector2i.ZERO, 2000):
		return
	runner.assert_true(phases.actual_at(B, 2500).values[0] > 0.0, "removing the last source retains a real fading residual")
	runner.assert_eq(int(ctx.field.diagnostics().source_count), 0, "the fading residual is not a copied source")


func _boundary_transition(runner: Object) -> void:
	var ctx: Dictionary = _fixture(runner)
	if ctx.is_empty() or not _publish(runner, ctx, "set", A, 0):
		return
	var phases: RefCounted = ctx.phases
	var before: Dictionary = phases.actual_at(A, GRID)
	runner.assert_true(bool(before.get("ok", false)), "the old response is defined at the exact segment endpoint")
	if not bool(before.get("ok", false)):
		return
	if not _publish(runner, ctx, "set", B, GRID):
		return
	_close(runner, phases.actual_at(A, GRID).values[0], before.values[0], "moving at a target boundary preserves its endpoint")
	_close(runner, phases.actual_at(B, GRID + 1000).values[0], _target(B, GRID, 0) * (1.0 - exp(-1.0)), "the new target uses the new global tide segment")
	runner.assert_eq(phases.actual_at(A, GRID - 1).get("reason"), "history_unavailable", "the prior segment is not reconstructed after retargeting")


func _failure_and_cancel(runner: Object) -> void:
	var bad: Dictionary = _fixture(runner, "_phase_bad")
	if bad.is_empty():
		return
	var temp_before: Dictionary = bad.temperature.snapshot()
	var phases_before: Dictionary = bad.phases.snapshot()
	var field_before: Dictionary = bad.field.diagnostics()
	var rejected: Dictionary = _prepare(runner, bad, "set", A, 0)
	runner.assert_true(not bool(rejected.get("ok", true)), "negative initial phase data rejects the entire candidate")
	runner.assert_eq(bad.temperature.snapshot(), temp_before, "failed phase initialization cannot publish temperature")
	runner.assert_eq(bad.phases.snapshot(), phases_before, "failed phase initialization cannot publish phase values")
	runner.assert_eq(bad.field.diagnostics().revision, field_before.revision, "failed initialization cannot publish the source")
	var ctx: Dictionary = _fixture(runner)
	if ctx.is_empty():
		return
	var opened: Dictionary = ctx.coordinator.begin(0, "set", _source(A), 0, HORIZON)
	runner.assert_true(bool(opened.get("ok", false)), "a cancellable candidate opens")
	if not bool(opened.get("ok", false)):
		return
	ctx.coordinator.step(opened.handle, 1, 1)
	runner.assert_true(bool(ctx.coordinator.cancel(opened.handle).get("ok", false)), "partial work can be cancelled")
	runner.assert_eq(int(ctx.field.diagnostics().source_count), 0, "cancel leaves the live field untouched")
	runner.assert_eq(ctx.temperature.actual_at(A, 0).get("reason"), "untracked", "cancel leaves no temperature anchor")
	runner.assert_eq(ctx.phases.actual_at(A, 0).get("reason"), "untracked", "cancel leaves no phase anchor")
	runner.assert_true(_publish(runner, ctx, "set", A, 0), "cancel releases all three candidates for a subsequent retry")


func _restore_invalidates_proof(runner: Object) -> void:
	var ctx: Dictionary = _fixture(runner)
	if ctx.is_empty() or not _publish(runner, ctx, "set", A, 0):
		return
	var ready: Dictionary = _prepare(runner, ctx, "set", B, 1000)
	if not bool(ready.get("ok", false)):
		runner.assert_true(false, "the pending source move prepares before restoration")
		return
	var phase_before: Dictionary = ctx.phases.snapshot()
	var temp_before: Dictionary = ctx.temperature.snapshot()
	var revision_before: int = int(ctx.field.diagnostics().revision)
	runner.assert_true(ctx.phases.restore(phase_before), "restoring an identical phase snapshot changes its proof identity")
	runner.assert_eq(ctx.coordinator.can_commit(ready.proof).get("reason"), "phase_stale", "a proof issued before owner restoration cannot publish")
	runner.assert_true(not bool(ctx.coordinator.commit(ready.proof).get("ok", true)), "stale phase proof rejects the whole commit")
	runner.assert_eq(ctx.temperature.snapshot(), temp_before, "stale proof leaves temperature unchanged")
	runner.assert_eq(int(ctx.field.diagnostics().revision), revision_before, "stale proof leaves the source unchanged")
	runner.assert_eq(ctx.phases.snapshot(), phase_before, "restore and rejected proof retain phase anchors")
	ctx.coordinator.cancel(ready.handle)
