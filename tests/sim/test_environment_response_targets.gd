extends RefCounted
## A fixture supplies cache-shaped input; the integration test must use the
## actual GroundCache/owner separately. No test claims this is a live world.

const Targets = preload("res://scripts/sim/environment_response_targets.gd")
const Temperature = preload("res://scripts/sim/environment_temperature_state.gd")
const Phase = preload("res://scripts/sim/environment_phase_state.gd")
const Segments = preload("res://scripts/sim/environment_temperature_segments.gd")
const SegmentFixture = preload("res://tests/sim/test_environment_temperature_segments.gd")
const Climate = preload("res://scripts/sim/climate_rules.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const Tide = preload("res://scripts/sim/environment_field_tide.gd")
const AREA := Rect2i(0, 0, 16, 16)


func run(runner: Object) -> void:
	_activation_and_boundaries(runner)
	_stale_and_failure(runner)
	print("SCENARIO environment response targets: bounded compilation, activation, shared boundary renewal and stale-field rejection")


func _fixture() -> Dictionary:
	var definitions := SegmentFixture.new()
	var temperature := Temperature.new()
	var phases := Phase.new()
	temperature.configure(Vector2i(16, 16), 256, 0)
	phases.configure(Vector2i(16, 16), 256, 0)
	var settings: Dictionary = {"climate": definitions._climate(), "weather": definitions._weather(),
		"weather_epoch_ms": 0, "seed": 42, "tau_ms": 1000, "tide_grid_ms": 10_000}
	var field := FixtureField.new()
	var coordinator := Targets.new()
	var ok: bool = coordinator.configure(temperature, phases, settings, Callable(field, "read"))
	return {"ok": ok, "temperature": temperature, "phases": phases, "settings": settings,
		"field": field, "coordinator": coordinator}


func _activation_and_boundaries(runner: Object) -> void:
	var fixture: Dictionary = _fixture()
	runner.assert_true(bool(fixture.ok), "actual response owners and compiler configure")
	if not fixture.ok:
		return
	var coordinator: RefCounted = fixture.coordinator
	var temperature: RefCounted = fixture.temperature
	var phases: RefCounted = fixture.phases
	var field: FixtureField = fixture.field
	var opened: Dictionary = coordinator.begin(AREA, 0, true, "event")
	runner.assert_true(bool(opened.get("ok", false)), "aligned activation begins")
	if not bool(opened.get("ok", false)):
		return
	var progress: Dictionary = coordinator.step(opened.handle, 1)
	runner.assert_true(bool(progress.get("ok", false)) and int(progress.get("cells", -1)) == 1 and bool(progress.get("pending", false)), "input consumes only its cell budget")
	runner.assert_eq(temperature.snapshot().cells.size(), 0, "partial temperature anchors remain private")
	runner.assert_eq(phases.snapshot().cells.size(), 0, "partial phase anchors remain private")
	var ready: Dictionary = _drive(runner, coordinator, opened.handle, 17)
	if not bool(ready.get("ok", false)):
		return
	var sealed: Dictionary = coordinator.finish(opened.handle)
	runner.assert_true(bool(sealed.get("ok", false)), "both candidates seal after all cells")
	if not bool(sealed.get("ok", false)):
		return
	runner.assert_eq(temperature.snapshot().cells.size(), 0, "sealed temperature remains private")
	runner.assert_eq(phases.snapshot().cells.size(), 0, "sealed phases remain private")
	runner.assert_true(bool(coordinator.commit(sealed.proof).get("ok", false)), "both candidates publish")
	runner.assert_eq(temperature.snapshot().cells.size(), 256, "temperature tracks each real area cell")
	runner.assert_eq(phases.snapshot().cells.size(), 256, "all five phases track each real area cell")
	var cell := Vector2i.ZERO
	var sampled: Dictionary = Tide.sample(42, cell, 0)
	var background: Dictionary = Climate.background_at(fixture.settings.climate, fixture.settings.weather, 0, cell, 0)
	var target: Dictionary = Segments.compile_segment(cell, 0, fixture.settings.climate, fixture.settings.weather, 0, 42,
		field.channels[5], field.channels[6], 1000, 10_000, Temperature.MAX_TIME)
	runner.assert_true(bool(target.get("ok", false)) and bool(sampled.get("ok", false)), "reference climate and tide segment is available")
	if not bool(target.get("ok", false)) or not bool(sampled.get("ok", false)):
		return
	var start: float = float(background.temperature_tenths) / 10.0
	runner.assert_eq(temperature.actual_at(cell, 0).value_c, start, "activation temperature is real background")
	var values: PackedFloat64Array = phases.actual_at(cell, 0).values
	for channel: int in Phase.CHANNELS:
		runner.assert_eq(values[channel], float(Rules.effective_grade(field.channels[channel], sampled.multiplier)), "activation phase starts with the existing tide-scaled field")
	var expected: float = float(target.target_c) + (start - float(target.target_c)) * exp(-0.5)
	_near(runner, float(temperature.actual_at(cell, 500).value_c), expected, 1.0e-8, "temperature establishes along shared time")
	runner.assert_eq(temperature.next_boundary_ms(), 10_000, "temperature records the tide boundary")
	runner.assert_eq(phases.next_boundary_ms(), 10_000, "phase records the tide boundary")
	var thermal_at_boundary: Dictionary = temperature.actual_at(cell, 10_000)
	var phases_at_boundary: Dictionary = phases.actual_at(cell, 10_000)
	opened = coordinator.begin(AREA, 10_000, false, "event")
	runner.assert_true(bool(opened.get("ok", false)), "the actual target boundary can be renewed")
	if not bool(opened.get("ok", false)):
		return
	ready = _drive(runner, coordinator, opened.handle, 256)
	if not bool(ready.get("ok", false)):
		return
	sealed = coordinator.finish(opened.handle)
	if not bool(sealed.get("ok", false)):
		runner.assert_true(false, "renewal candidate must seal: " + str(sealed))
		return
	runner.assert_true(bool(coordinator.commit(sealed.proof).get("ok", false)), "the new target segments publish at the same world time")
	runner.assert_eq(temperature.actual_at(cell, 10_000), thermal_at_boundary, "renewal preserves actual temperature at the boundary")
	runner.assert_eq(phases.actual_at(cell, 10_000), phases_at_boundary, "renewal preserves all actual phase values at the boundary")
	runner.assert_eq(temperature.next_boundary_ms(), 20_000, "next temperature segment is bounded by the next tide")
	runner.assert_eq(phases.next_boundary_ms(), 20_000, "next phase segment is bounded by the next tide")
	runner.assert_true(not bool(coordinator.commit(sealed.proof).get("ok", true)), "consumed proof cannot replay")


func _stale_and_failure(runner: Object) -> void:
	var fixture: Dictionary = _fixture()
	var coordinator: RefCounted = fixture.coordinator
	var temperature: RefCounted = fixture.temperature
	var phases: RefCounted = fixture.phases
	var field: FixtureField = fixture.field
	var opened: Dictionary = coordinator.begin(AREA, 0, true, "event")
	var ready: Dictionary = _drive(runner, coordinator, opened.handle, 256)
	if not bool(ready.get("ok", false)):
		return
	field.revision += 1
	var sealed: Dictionary = coordinator.finish(opened.handle)
	runner.assert_eq(sealed.get("reason"), "field_stale", "a changed field cannot publish an older prepared candidate")
	runner.assert_eq(temperature.snapshot().cells.size(), 0, "stale rejection leaves temperature unchanged")
	runner.assert_eq(phases.snapshot().cells.size(), 0, "stale rejection leaves phase unchanged")
	field.calls = 0
	field.fail_after = 130
	opened = coordinator.begin(AREA, 0, true, "event")
	ready = _drive(runner, coordinator, opened.handle, 32, false)
	runner.assert_eq(ready.get("reason"), "fixture_failure", "callback failure during preparation is propagated")
	runner.assert_eq(temperature.snapshot().cells.size(), 0, "mid-input failure releases thermal candidate")
	runner.assert_eq(phases.snapshot().cells.size(), 0, "mid-input failure releases phase candidate")
	field.fail_after = -1
	field.calls = 0
	field.pending = true
	opened = coordinator.begin(AREA, 0, true, "event")
	ready = coordinator.step(opened.handle, 1)
	runner.assert_eq(ready.get("reason"), "field_pending", "an unfinished base field is never treated as zero")
	runner.assert_eq(temperature.snapshot().cells.size(), 0, "pending base cannot publish temperature")
	runner.assert_eq(phases.snapshot().cells.size(), 0, "pending base cannot publish phases")
	field.pending = false
	opened = coordinator.begin(AREA, 0, true, "wrong context")
	ready = coordinator.step(opened.handle, 1)
	runner.assert_eq(ready.get("reason"), "fixture_context", "context validation is delegated to the authority callback")
	runner.assert_eq(temperature.snapshot().cells.size(), 0, "incorrect context cannot publish anything")
	var too_large: Dictionary = coordinator.begin(Rect2i(0, 0, 16, 32), 0, true, "event")
	runner.assert_eq(too_large.get("reason"), "invalid_area", "out-of-world tiles are rejected before either owner opens")


func _drive(runner: Object, coordinator: RefCounted, handle: Variant, budget: int, expect_success: bool = true) -> Dictionary:
	for _iteration: int in 4_000:
		var result: Dictionary = coordinator.step(handle, budget)
		if not bool(result.get("ok", false)):
			if expect_success:
				runner.assert_true(false, "response compilation failed: " + str(result))
			return result
		if int(result.get("cells", -1)) < 0 or int(result.get("cells", -1)) > budget:
			runner.assert_true(false, "each stage respects its visited-cell budget")
			return {"ok": false, "reason": "budget"}
		if not bool(result.get("pending", true)):
			return result
	runner.assert_true(false, "response compilation should finish within the fixture iteration bound")
	return {"ok": false, "reason": "drive_limit"}


func _near(runner: Object, actual: float, expected: float, tolerance: float, message: String) -> void:
	runner.assert_true(is_finite(actual) and absf(actual - expected) <= tolerance, "%s: expected %s ± %s, got %s" % [message, str(expected), str(tolerance), str(actual)])


class FixtureField:
	extends RefCounted
	var channels := PackedInt32Array([3000, 2000, 1000, 500, 250, 1000, 0])
	var revision: int = 1
	var calls: int = 0
	var fail_after: int = -1
	var pending: bool = false

	func read(_cell: Vector2i, context: Variant) -> Dictionary:
		calls += 1
		if context != "event":
			return {"ok": false, "reason": "fixture_context"}
		if fail_after >= 0 and calls > fail_after:
			return {"ok": false, "reason": "fixture_failure"}
		return {"ok": true, "pending": pending, "channels": channels.duplicate(), "revision": revision}
