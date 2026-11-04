extends RefCounted
## Inspection reports dependencies without altering the original heat owner.

const Probe = preload("res://scripts/sim/thermal_reclaim_probe.gd")
const Devices = preload("res://tests/sim/test_thermal_devices.gd")
const HeatEnvironment = preload("res://tests/sim/test_local_heat_environment.gd")
const HeatFixtures = preload("res://tests/sim/test_local_heat.gd")
var _devices := Devices.new()
var _environment := HeatEnvironment.new()
var _heat_fixtures := HeatFixtures.new()


class SideEffectBackground extends RefCounted:
	var calls: int = 0

	func query(_cell: Vector2i, _at_ms: int) -> int:
		calls += 1
		return 0


func run(runner: Object) -> void:
	_device_and_weather(runner)
	_source_and_pending(runner)
	_unknown_does_not_advance(runner)
	print("SCENARIO thermal reclaim probe: bounded read-only dependency inspection, actual climate phase, original receipts, pending actions and independent JSON restore; no reclamation")


func _device_and_weather(runner: Object) -> void:
	var world: RegionalSimulation = _devices._world(runner)
	if world == null or not _devices._action(runner, world, "player", "study", Devices.FIRE) or not _devices._action(runner, world, "player", "enable", Devices.FIRE):
		return
	var before: String = _json(world.to_dict())
	var report: Dictionary = Probe.inspect(world.local_heat)
	runner.assert_true(bool(report.complete) and report.status == "complete", "synchronized world has a complete bounded dependency scan")
	runner.assert_true(not bool(report.can_reclaim), "the development scan never authorizes physical reclamation")
	if not bool(report.complete):
		return
	runner.assert_eq(_json(world.to_dict()), before, "inspection does not change the full original world")
	var point: Vector2i = world.artifacts.object_cell(Devices.FIRE)
	var row: Dictionary = _cell(report, point)
	runner.assert_true(not row.is_empty(), "the real enabled source has an inspected original cell")
	if row.is_empty():
		return
	runner.assert_true(row.enabled_devices.has(Devices.FIRE), "the real enabled finite device is named as a blocker")
	runner.assert_true(not row.activation_refs.is_empty() and not row.switch_refs.is_empty(), "actual enable history is retained as independent evidence")
	runner.assert_true(not row.frozen_flows.is_empty(), "the original frozen source flow is reported")
	runner.assert_true(row.blockers.has("enabled_device") and row.blockers.has("future_climate_unproved"), "current source and missing future proof both block retirement")
	runner.assert_true(not bool(row.can_reclaim), "individual cells cannot be reclaimed by this inspection")
	runner.assert_eq(int(row.q), int(world.local_heat.cells[row.key].energy), "reported Q is the original owner's Q")
	runner.assert_eq(int(row.background_q), world.local_heat._baseline(point, world.elapsed_ms), "reported baseline is computed from bound current climate")
	runner.assert_eq(int(row.residual_q), int(row.q) - int(row.background_q), "reported residual is signed Q minus background Q")
	runner.assert_true(bool(row.background_envelope.supported), "bound climate provides a conservative annual envelope")
	# The device has just allocated this cell; no interval has elapsed to move
	# its new background Q. Zero residual still cannot prove future safety.
	runner.assert_eq(int(row.residual_q), 0, "the actual newly allocated cell starts exactly at its local background")
	var region: String = str(row.region)
	var phase: int = SimWeather.next_phase_boundary_ms(world.weather.definitions, region, world.weather.epoch_ms, world.elapsed_ms)
	var before_phase: Dictionary = SimClimateRules.background_for_region(world._content.climate, world.weather.definitions, world.weather.epoch_ms, region, phase - 1)
	var after_phase: Dictionary = SimClimateRules.background_for_region(world._content.climate, world.weather.definitions, world.weather.epoch_ms, region, phase)
	runner.assert_true(not before_phase.is_empty() and not after_phase.is_empty(), "the real next weather phase has both background values")
	if not before_phase.is_empty() and not after_phase.is_empty():
		runner.assert_true(absi(int(after_phase.temperature_tenths) - int(before_phase.temperature_tenths)) > 5, "the actual phase changes background by more than the 0.5 C future-error limit")
		runner.assert_true(not bool(row.can_reclaim), "an instant zero residual cannot authorize forgetting thermal inertia")

	var exact: Dictionary = Probe.inspect(world.local_heat, int(report.work_used))
	runner.assert_eq(_json(exact), _json(report), "the exact work limit yields the same deterministically sorted complete report")
	var limited: Dictionary = Probe.inspect(world.local_heat, maxi(0, int(report.work_used) - 1))
	runner.assert_true(not bool(limited.complete) and limited.status == "unknown" and limited.reason == "work_budget_exhausted", "one unit below the full scan returns unknown")
	runner.assert_true(limited.cells.is_empty() and limited.pending.is_empty() and not bool(limited.can_reclaim), "budget exhaustion never presents partial rows as complete or safe")
	runner.assert_eq(_json(world.to_dict()), before, "repeated and budget-limited queries never change the owner")

	var archive: Dictionary = JSON.parse_string(before)
	var resumed: RegionalSimulation = _devices._world(runner)
	if resumed == null:
		return
	runner.assert_true(resumed.restore(archive), "a fresh regional candidate restores the actual current JSON world")
	if resumed.local_heat == null or resumed.elapsed_ms != world.elapsed_ms:
		return
	var restored: Dictionary = Probe.inspect(resumed.local_heat)
	runner.assert_eq(_json(restored), _json(report), "independent current restore gives the same complete diagnostic")
	runner.assert_eq(_json(resumed.to_dict()), before, "diagnosing the restored candidate does not modify it")


func _source_and_pending(runner: Object) -> void:
	var world: RegionalSimulation = _environment._world(runner)
	if world == null or not _environment._prepare(runner, world):
		return
	var started: Dictionary = world.artifacts.begin("player", "warm", "hearth_stone")
	runner.assert_true(bool(started.ok), "the original carried warm source starts its real in-flight action")
	if not bool(started.ok):
		return
	var action: String = str(world.artifacts.active.player.id)
	var due: int = int(world.artifacts.active.player.due_ms)
	var before: String = _json(world.to_dict())
	var pending: Dictionary = Probe.inspect(world.local_heat)
	runner.assert_true(bool(pending.complete) and pending.status == "unknown" and pending.reason == "pending_target_unknown", "a complete scan marks the future source location unknown")
	var found: bool = false
	for entry: Dictionary in pending.pending:
		if entry.action == action:
			found = entry.verb == "warm" and entry.target == "unknown" and int(entry.due_ms) == due
	runner.assert_true(found and not bool(pending.can_reclaim), "the real pending source is reported without inventing its eventual cell")
	runner.assert_eq(_json(world.to_dict()), before, "inspecting the pending original action does not change time or charge")
	runner.assert_true(world.advance_to_ms(due), "the original regional scheduler completes the source")
	var after_completion: String = _json(world.to_dict())
	var report: Dictionary = Probe.inspect(world.local_heat)
	runner.assert_true(bool(report.complete), "the completed source and its historical evidence fit within the inspection budget")
	var point: Vector2i = world.artifacts.object_cell("hearth_stone")
	var row: Dictionary = _cell(report, point)
	runner.assert_true(not row.is_empty(), "the real completed source has a physical field cell")
	if not row.is_empty():
		runner.assert_true(row.receipt_refs.has(action) and row.blockers.has("receipt_history"), "the original warm receipt remains linked to its source patch")
		runner.assert_true(not bool(row.can_reclaim), "a receipt cell is never reclaimed by inspection")
	runner.assert_eq(_json(world.to_dict()), after_completion, "completed source inspection neither replays nor spends its receipt")
	# An allocation at the same millisecond as a prior sample may occur after
	# that sample. Wait for the next actual sample instead of inventing order.
	var sample_ms: int = int(world.local_heat.definitions.sample_ms)
	@warning_ignore("integer_division")
	var next_sample: int = (int(world.elapsed_ms) / sample_ms + 1) * sample_ms
	if not world.advance_to_ms(next_sample):
		runner.assert_true(false, "the original regional scheduler reaches the next thermal sample")
		return
	var sampled_before: String = _json(world.to_dict())
	var sampled: Dictionary = Probe.inspect(world.local_heat)
	var sampled_row: Dictionary = _cell(sampled, point)
	runner.assert_true(bool(sampled.complete) and not sampled_row.is_empty(), "the original source remains present at the next real sample")
	if not sampled_row.is_empty():
		runner.assert_true(bool(sampled_row.sample_ref) and sampled_row.blockers.has("sample_reference"), "the saved sample is a separate historical dependency")
		runner.assert_true(sampled_row.receipt_refs.has(action) and not bool(sampled_row.can_reclaim), "sampling never replaces the original receipt or authorizes reclamation")
	runner.assert_eq(_json(world.to_dict()), sampled_before, "sampling evidence inspection does not rewrite the original sample")


func _unknown_does_not_advance(runner: Object) -> void:
	var fixture: Dictionary = _heat_fixtures._make()
	var heat: SimLocalHeat = fixture.heat
	var old_time: int = int(fixture.world.elapsed_ms)
	var dirty: Dictionary = Probe.inspect(heat)
	runner.assert_true(not bool(dirty.complete) and dirty.reason == "unsynchronized", "unresolved geometry returns unknown without freezing it")
	runner.assert_true(heat._geometry_dirty and int(fixture.world.elapsed_ms) == old_time and heat.last_ms == old_time, "the unknown result leaves the dirty flag and clocks untouched")
	var provider := SideEffectBackground.new()
	heat.set_background(Callable(provider, "query"), Callable())
	heat.refresh_geometry()
	var before: String = _heat_fixtures._json(heat)
	var prior_calls: int = provider.calls
	var custom: Dictionary = Probe.inspect(heat)
	runner.assert_true(not bool(custom.complete) and custom.reason == "custom_background", "an arbitrary background cannot borrow the default climate envelope")
	runner.assert_eq(provider.calls, prior_calls, "read-only inspection never invokes an arbitrary background Callable")
	runner.assert_eq(_heat_fixtures._json(heat), before, "unsupported background inspection leaves the complete thermal state unchanged")
	fixture.world.elapsed_ms += 1
	var elapsed: int = int(fixture.world.elapsed_ms)
	var stale: Dictionary = Probe.inspect(heat)
	runner.assert_true(not bool(stale.complete) and stale.reason == "unsynchronized", "a clock ahead of the heat field is unknown")
	runner.assert_true(heat.last_ms == old_time and int(fixture.world.elapsed_ms) == elapsed, "the diagnostic never settles a pending interval")


func _cell(report: Dictionary, point: Vector2i) -> Dictionary:
	var wanted: String = "%d,%d" % [point.x, point.y]
	for row: Dictionary in report.get("cells", []):
		if row.key == wanted:
			return row
	return {}


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
