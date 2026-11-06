extends RefCounted
## Compact response columns preserve owner semantics and never publish a
## partially validated save. These are not a substitute for world integration.

const Columns = preload("res://scripts/persistence/environment_response_columns.gd")
const Temperature = preload("res://scripts/sim/environment_temperature_state.gd")
const Phases = preload("res://scripts/sim/environment_phase_state.gd")
const Targets = preload("res://scripts/sim/environment_response_targets.gd")
const Compiler = preload("res://scripts/sim/environment_target_compiler.gd")
const TargetsFixture = preload("res://tests/sim/test_environment_response_targets.gd")
const SegmentFixture = preload("res://tests/sim/test_environment_temperature_segments.gd")
const AREA := Rect2i(0, 0, 32, 16)


func run(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	if fixture.is_empty():
		return
	_roundtrip(runner, fixture)
	_compiler_validation(runner, fixture, AREA, false)
	var balanced_area := Rect2i(0, 0, 16, 16)
	var balanced: Dictionary = _fixture(runner, balanced_area, true)
	if not balanced.is_empty():
		_compiler_validation(runner, balanced, balanced_area, true)
	_offset_multiblock_roundtrip(runner)
	_atomic_rejections(runner, fixture)
	_proof_invalidation(runner, fixture)
	print("SCENARIO response packed columns: independent exact anchors, complete coverage, atomic reject and proof invalidation")


func _fixture(runner: Object, area: Rect2i = AREA, equal_thermal: bool = false) -> Dictionary:
	var definitions := SegmentFixture.new()
	var thermal := Temperature.new()
	var elemental := Phases.new()
	var settings: Dictionary = {"climate": definitions._climate(), "weather": definitions._weather(),
		"weather_epoch_ms": 0, "seed": 42, "tau_ms": 1000, "tide_grid_ms": 10_000}
	var field := TargetsFixture.FixtureField.new()
	if equal_thermal:
		var balanced_channels: PackedInt32Array = field.channels.duplicate()
		balanced_channels[6] = balanced_channels[5]
		field.channels = balanced_channels
	var targets := Targets.new()
	var size: Vector2i = area.end
	var count: int = area.size.x * area.size.y
	if not thermal.configure(size, count, 0) or not elemental.configure(size, count, 0) or not targets.configure(thermal, elemental, settings, Callable(field, "read")):
		runner.assert_true(false, "response source fixture configures")
		return {}
	var result: Dictionary = targets.begin(area, 0, true, "event")
	if not bool(result.get("ok", false)):
		runner.assert_true(false, "two-block response activation begins")
		return {}
	var handle: Variant = result.handle
	for _iteration: int in 100:
		result = targets.step(handle, 128)
		if not bool(result.get("ok", false)):
			runner.assert_true(false, "two-block activation prepares: " + str(result))
			return {}
		if not bool(result.get("pending", true)):
			break
	if bool(result.get("pending", true)):
		runner.assert_true(false, "two-block activation terminates")
		return {}
	result = targets.finish(handle)
	if not bool(result.get("ok", false)) or not bool(targets.commit(result.proof).get("ok", false)):
		runner.assert_true(false, "two-block activation commits")
		return {}
	return {"thermal": thermal, "elemental": elemental, "settings": settings, "field": field}


func _roundtrip(runner: Object, fixture: Dictionary) -> void:
	var thermal: RefCounted = fixture.thermal
	var elemental: RefCounted = fixture.elemental
	var captured: Dictionary = Columns.capture(thermal, elemental, AREA)
	runner.assert_true(bool(captured.get("ok", false)), "active owner columns capture")
	if not bool(captured.get("ok", false)):
		return
	var data: Dictionary = captured.data
	runner.assert_eq(data.chunks.size(), 2, "two aligned physical blocks are captured")
	runner.assert_true(data.chunks[0].thermal.starts is PackedInt64Array and data.chunks[0].phases.initials is PackedFloat64Array, "anchors are packed columns, not per-cell dictionaries")
	# Plain Variant serialization preserves int64 and float64 without enabling
	# object deserialization. The surrounding file layer owns atomic writes.
	var bytes: PackedByteArray = var_to_bytes(data)
	var decoded: Variant = bytes_to_var(bytes)
	var restored_t := Temperature.new()
	var restored_p := Phases.new()
	runner.assert_true(Columns.restore(restored_t, restored_p, decoded), "binary packed columns restore into independent owners")
	if not restored_t._configured or not restored_p._configured:
		return
	runner.assert_eq(restored_t.snapshot(), thermal.snapshot(), "every temperature anchor and revision roundtrips")
	runner.assert_eq(restored_p.snapshot(), elemental.snapshot(), "every five-channel anchor and revision roundtrips")
	for cell: Vector2i in [Vector2i.ZERO, Vector2i(15, 15), Vector2i(16, 0), Vector2i(31, 15)]:
		runner.assert_eq(restored_t.actual_at(cell, 7777), thermal.actual_at(cell, 7777), "temperature future is exact across blocks")
		runner.assert_eq(restored_p.actual_at(cell, 7777), elemental.actual_at(cell, 7777), "phase future is exact across blocks")
		runner.assert_true(Columns.validate_cell(restored_t._chunks[Vector2i(cell.x >> 4, cell.y >> 4)], restored_p._chunks[Vector2i(cell.x >> 4, cell.y >> 4)], ((cell.y & 15) << 4) + (cell.x & 15), cell, fixture.settings, 7777, fixture.field.channels), "targets match known climate, tide and field")
	var altered_channels: PackedInt32Array = fixture.field.channels.duplicate()
	altered_channels[5] += 100
	runner.assert_true(not Columns.validate_cell(restored_t._chunks[Vector2i.ZERO], restored_p._chunks[Vector2i.ZERO], 0, Vector2i.ZERO, fixture.settings, 7777, altered_channels), "a different rebuilt field cannot pass target validation")
	var before: Dictionary = restored_t.actual_at(Vector2i.ZERO, 0)
	var mutable: PackedFloat64Array = decoded.chunks[0].thermal.initials
	mutable[0] += 20.0
	decoded.chunks[0].thermal.initials = mutable
	runner.assert_eq(restored_t.actual_at(Vector2i.ZERO, 0), before, "mutating decoded data cannot mutate restored owner")
	runner.assert_eq(thermal.actual_at(Vector2i.ZERO, 0), before, "mutating decoded data cannot mutate source owner")


func _compiler_validation(runner: Object, fixture: Dictionary, area: Rect2i, balanced: bool) -> void:
	# Use the same restored anchors for the independent reference and cached
	# compiler. In the balanced case heat cancels but elemental tide remains.
	var captured: Dictionary = Columns.capture(fixture.thermal, fixture.elemental, area)
	if not bool(captured.get("ok", false)):
		runner.assert_true(false, "compiler comparison captures response anchors")
		return
	var saved: Dictionary = captured.data
	var restored_t := Temperature.new()
	var restored_p := Phases.new()
	if not Columns.restore(restored_t, restored_p, saved):
		runner.assert_true(false, "compiler comparison restores response anchors")
		return
	var compiler := Compiler.new()
	if not compiler.configure(fixture.settings):
		runner.assert_true(false, "compiler comparison binds validated settings")
		return
	var label: String = "balanced heat" if balanced else "heat source"
	for cell: Vector2i in [Vector2i.ZERO, Vector2i(15, 15)]:
		var key := Vector2i(cell.x >> 4, cell.y >> 4)
		var index: int = ((cell.y & 15) << 4) + (cell.x & 15)
		var reference: bool = Columns.validate_cell(restored_t._chunks[key], restored_p._chunks[key], index, cell, fixture.settings, 7777, fixture.field.channels)
		var cached: bool = Columns.validate_cell(restored_t._chunks[key], restored_p._chunks[key], index, cell, fixture.settings, 7777, fixture.field.channels, compiler)
		runner.assert_true(reference, label + " reference accepts intact saved target")
		runner.assert_eq(cached, reference, label + " cached and reference validation agree")
	if balanced:
		runner.assert_eq(restored_t._chunks[Vector2i.ZERO].targets[0], 20.0, "equal heat and cold leave neutral temperature")
		var phase_target: float = restored_p._chunks[Vector2i.ZERO].targets[0]
		runner.assert_true(phase_target > 0.0 and phase_target < float(fixture.field.channels[0]), "equal heat and cold still apply nonzero elemental tide")
	# A finite positive but incorrect phase target passes structural decoding;
	# the rebuilt field must make both semantic validation paths reject it.
	var altered: PackedFloat64Array = saved.chunks[0].phases.targets
	altered[0] += 1.0
	saved.chunks[0].phases.targets = altered
	var bad_t := Temperature.new()
	var bad_p := Phases.new()
	if not Columns.restore(bad_t, bad_p, saved):
		runner.assert_true(false, "finite tampered phase passes structural decoding")
		return
	var bad_reference: bool = Columns.validate_cell(bad_t._chunks[Vector2i.ZERO], bad_p._chunks[Vector2i.ZERO], 0, Vector2i.ZERO, fixture.settings, 7777, fixture.field.channels)
	var bad_cached: bool = Columns.validate_cell(bad_t._chunks[Vector2i.ZERO], bad_p._chunks[Vector2i.ZERO], 0, Vector2i.ZERO, fixture.settings, 7777, fixture.field.channels, compiler)
	runner.assert_true(not bad_reference, label + " reference rejects tampered elemental target")
	runner.assert_eq(bad_cached, bad_reference, label + " cached path also rejects tampered elemental target")


func _offset_multiblock_roundtrip(runner: Object) -> void:
	# Exercise chunk-row transitions and a non-zero origin together; linear
	# two-block tests alone cannot catch a swapped chunk coordinate or stride.
	var area := Rect2i(16, 16, 32, 32)
	var fixture: Dictionary = _fixture(runner, area)
	if fixture.is_empty():
		return
	var capture: Dictionary = Columns.capture(fixture.thermal, fixture.elemental, area)
	if not bool(capture.get("ok", false)):
		runner.assert_true(false, "offset multi-row area captures")
		return
	var data: Dictionary = capture.data
	var expected_keys: Array = [[1, 1], [2, 1], [1, 2], [2, 2]]
	for index: int in expected_keys.size():
		runner.assert_eq(data.chunks[index].key, expected_keys[index], "offset chunks stay in row-major order")
	var restored_t := Temperature.new()
	var restored_p := Phases.new()
	if not Columns.restore(restored_t, restored_p, data):
		runner.assert_true(false, "offset multi-row area restores")
		return
	runner.assert_eq(restored_t.snapshot(), fixture.thermal.snapshot(), "offset thermal anchors survive all chunk rows")
	runner.assert_eq(restored_p.snapshot(), fixture.elemental.snapshot(), "offset phase anchors survive all chunk rows")
	for cell: Vector2i in [Vector2i(16, 16), Vector2i(47, 16), Vector2i(16, 47), Vector2i(47, 47)]:
		runner.assert_eq(restored_t.actual_at(cell, 7777), fixture.thermal.actual_at(cell, 7777), "offset thermal corner stays queryable")
		runner.assert_eq(restored_p.actual_at(cell, 7777), fixture.elemental.actual_at(cell, 7777), "offset phase corner stays queryable")


func _atomic_rejections(runner: Object, fixture: Dictionary) -> void:
	var restored_t := Temperature.new()
	var restored_p := Phases.new()
	var good: Dictionary = Columns.capture(fixture.thermal, fixture.elemental, AREA).data
	if not Columns.restore(restored_t, restored_p, good):
		runner.assert_true(false, "atomic rejection fixture restores")
		return
	var expected_t: Dictionary = restored_t.snapshot()
	var expected_p: Dictionary = restored_p.snapshot()
	var bad: Dictionary = Columns.capture(fixture.thermal, fixture.elemental, AREA).data
	var invalid: PackedFloat64Array = bad.chunks[1].phases.targets
	invalid[6] = -1.0
	bad.chunks[1].phases.targets = invalid
	runner.assert_true(not Columns.restore(restored_t, restored_p, bad), "negative phase target rejects the complete candidate")
	runner.assert_eq(restored_t.snapshot(), expected_t, "bad phase leaves old temperature untouched")
	runner.assert_eq(restored_p.snapshot(), expected_p, "bad phase leaves old phase untouched")
	bad = Columns.capture(fixture.thermal, fixture.elemental, AREA).data
	bad.chunks[1].key = [0, 0]
	runner.assert_true(not Columns.restore(restored_t, restored_p, bad), "duplicate or out-of-order chunks cannot hide missing coverage")
	bad = Columns.capture(fixture.thermal, fixture.elemental, AREA).data
	var present: PackedByteArray = bad.chunks[0].thermal.present
	present[17] = 0
	bad.chunks[0].thermal.present = present
	runner.assert_true(not Columns.restore(restored_t, restored_p, bad), "a missing cell is not treated as a zero temperature")
	bad = Columns.capture(fixture.thermal, fixture.elemental, AREA).data
	var bad_time: PackedInt64Array = bad.chunks[0].phases.starts
	bad_time[1] += 1
	bad.chunks[0].phases.starts = bad_time
	runner.assert_true(not Columns.restore(restored_t, restored_p, bad), "different same-cell owner times are rejected")
	bad = Columns.capture(fixture.thermal, fixture.elemental, AREA).data
	var bad_temperature: PackedFloat64Array = bad.chunks[0].thermal.initials
	bad_temperature[0] = -300.0
	bad.chunks[0].thermal.initials = bad_temperature
	runner.assert_true(not Columns.restore(restored_t, restored_p, bad), "sub-absolute-zero temperatures are rejected")
	bad = Columns.capture(fixture.thermal, fixture.elemental, AREA).data
	bad.temperature.last_change_ms = 2
	bad.phases.last_change_ms = 2
	runner.assert_true(not Columns.restore(restored_t, restored_p, bad), "last change must correspond to a real saved anchor")
	runner.assert_eq(restored_t.snapshot(), expected_t, "all failed candidates leave temperature unchanged")
	runner.assert_eq(restored_p.snapshot(), expected_p, "all failed candidates leave phases unchanged")


func _proof_invalidation(runner: Object, fixture: Dictionary) -> void:
	var saved: Dictionary = Columns.capture(fixture.thermal, fixture.elemental, AREA).data
	var thermal: RefCounted = fixture.thermal
	var elemental: RefCounted = fixture.elemental
	var change: Array[Dictionary] = [{"cell": Vector2i.ZERO, "target_c": 20.0, "target_per_ms": 0.0, "until_ms": 10_000, "tau_ms": 1000}]
	var proof: Dictionary = thermal.prepare_targets(change, 500, 1)
	runner.assert_true(bool(proof.get("ok", false)), "a private temperature candidate can exist before restoration")
	var phase_open: Dictionary = elemental.begin_bulk(500, 1)
	runner.assert_true(bool(phase_open.get("ok", false)), "a private phase candidate can exist before restoration")
	if not bool(proof.get("ok", false)) or not bool(phase_open.get("ok", false)):
		return
	runner.assert_true(not bool(Columns.capture(thermal, elemental, AREA).get("ok", true)), "capture rejects in-flight candidates")
	runner.assert_true(Columns.restore(thermal, elemental, saved), "an independent fully validated restore replaces both owners")
	runner.assert_true(not bool(thermal.commit(proof).get("ok", true)), "restoration invalidates a previous small-batch proof")
	runner.assert_true(not bool(elemental.cancel_bulk(phase_open.handle).get("ok", true)), "restoration invalidates a previous bulk handle")
