extends RefCounted
## Different effect channels use the same source-change path. Clean tiles are
## compared with the existing full reconstruction; no item names are involved.

const Baseline = preload("res://scripts/sim/environment_field_cache.gd")
const Ground = preload("res://scripts/sim/environment_ground_field.gd")
const Temperature = preload("res://scripts/sim/environment_temperature_state.gd")
const Phases = preload("res://scripts/sim/environment_phase_state.gd")
const Change = preload("res://scripts/sim/environment_source_change.gd")
const SegmentFixture = preload("res://tests/sim/test_environment_temperature_segments.gd")
const MAP := Vector2i(32, 16)
const CHANNELS: int = 7


func run(runner: Object) -> void:
	_incremental_matches_full(runner)
	_response_participation(runner)
	_cold_tile_proof(runner)
	_cold_tile_falls_back(runner)
	print("SCENARIO sparse effect changes: exact maxima, effect participation and atomic fallback")


func _warm(field: RefCounted, area: Rect2i, runner: Object) -> bool:
	var requested: Dictionary = field.request_area(area)
	if not bool(requested.get("ok", false)):
		runner.assert_true(false, "the field area can be requested")
		return false
	while int(field.diagnostics().pending_tiles) > 0:
		var progress: Dictionary = field.rebuild(64, Baseline.MAX_WORK)
		if not bool(progress.get("ok", false)):
			runner.assert_true(false, "the field finishes warming")
			return false
	return true


func _candidate(field: RefCounted, handle: Variant, runner: Object) -> Dictionary:
	var work: int = 0
	for _step: int in 1000:
		var progress: Dictionary = field.step_source_change(handle, Baseline.MAX_WORK)
		if not bool(progress.get("ok", false)):
			runner.assert_true(false, "field candidate remains valid: %s" % str(progress))
			return progress
		work += int(progress.work)
		if bool(progress.done):
			var result: Dictionary = field.finish_source_change(handle)
			return {"ok": bool(result.get("ok", false)), "proof": result.get("proof"), "total_work": work}
	runner.assert_true(false, "field candidate finishes within its bounded work")
	return {"ok": false}


func _incremental_matches_full(runner: Object) -> void:
	var fast := Ground.new()
	var full := Baseline.new()
	if not fast.configure(MAP, 4) or not full.configure(MAP, 4):
		runner.assert_true(false, "both fields configure")
		return
	var inputs: Array[Dictionary] = [
		{"slot": 0, "cell": Vector2i(14, 6), "radius": 4, "channels": [6000, 0, 0, 0, 0, 0, 0]},
		{"slot": 1, "cell": Vector2i(14, 6), "radius": 4, "channels": [6000, 0, 0, 0, 0, 0, 0]},
		{"slot": 2, "cell": Vector2i(14, 6), "radius": 4, "channels": [4000, 0, 0, 0, 0, 0, 0]},
	]
	for source: Dictionary in inputs:
		var a: Dictionary = fast.set_source(source.slot, source.cell, source.radius, source.channels)
		var b: Dictionary = full.set_source(source.slot, source.cell, source.radius, source.channels)
		if not bool(a.get("ok", false)) or not bool(b.get("ok", false)):
			runner.assert_true(false, "all overlapping sources initialize")
			return
	if not _warm(fast, Rect2i(Vector2i.ZERO, MAP), runner):
		return
	var replacement := {"cell": Vector2i(17, 6), "radius": 4, "channels": [2000, 0, 0, 0, 0, 5000, 0]}
	var first: Dictionary = fast.begin_source_change(0, "set", replacement)
	var second: Dictionary = full.begin_source_change(0, "set", replacement)
	if not bool(first.get("ok", false)) or not bool(second.get("ok", false)):
		runner.assert_true(false, "cross-tile replacement begins in both fields")
		return
	var a: Dictionary = _candidate(fast, first.handle, runner)
	var b: Dictionary = _candidate(full, second.handle, runner)
	if not bool(a.get("ok", false)) or not bool(b.get("ok", false)):
		return
	var exact_masks: bool = true
	for id: int in first.tile_ids:
		var result: Dictionary = fast.candidate_tile_copy(a.proof, id)
		var expected: Dictionary = full.candidate_tile_copy(b.proof, id)
		runner.assert_eq(result.channels, expected.channels, "incremental tile equals full maximum reconstruction")
		if not result.get("change_mask") is PackedByteArray:
			exact_masks = false
			continue
		var rect: Rect2i = result.rect
		for index: int in rect.size.x * rect.size.y:
			@warning_ignore("integer_division")
			var cell := rect.position + Vector2i(index % rect.size.x, index / rect.size.x)
			var old: Dictionary = fast.read_base(cell)
			var expected_mask: int = 0
			for channel: int in CHANNELS:
				if int(old.channels[channel]) != int(result.channels[index * CHANNELS + channel]):
					expected_mask |= 1 << channel
			if int(result.change_mask[index]) != expected_mask:
				exact_masks = false
	runner.assert_true(exact_masks, "each cell reports exactly the changed channel bits")
	runner.assert_true(int(a.total_work) < int(b.total_work), "clean local changes use less counted work than full rebuilding")
	runner.assert_true(bool(fast.commit_source_change(a.proof).get("ok", false)), "the incremental candidate commits")
	runner.assert_true(bool(full.commit_source_change(b.proof).get("ok", false)), "the full candidate commits")
	# Removing the tied old winner now exposes the weaker remaining source.
	first = fast.begin_source_change(1, "remove")
	second = full.begin_source_change(1, "remove")
	if not bool(first.get("ok", false)) or not bool(second.get("ok", false)):
		runner.assert_true(false, "the former tied winner can be removed")
		return
	a = _candidate(fast, first.handle, runner)
	b = _candidate(full, second.handle, runner)
	if not bool(a.get("ok", false)) or not bool(b.get("ok", false)):
		return
	for id: int in first.tile_ids:
		runner.assert_eq(fast.candidate_tile_copy(a.proof, id).channels, full.candidate_tile_copy(b.proof, id).channels, "removing the winner exposes the next exact maximum")
	runner.assert_true(bool(fast.cancel_source_change(first.handle).get("ok", false)), "incremental removal remains cancellable")
	runner.assert_true(bool(full.cancel_source_change(second.handle).get("ok", false)), "reference removal remains cancellable")


func _initial_temperature(_cell: Vector2i, _at_ms: int) -> Dictionary:
	return {"ok": true, "value_c": 20.0}


func _initial_phases(_cell: Vector2i, _at_ms: int) -> Dictionary:
	return {"ok": true, "values": PackedFloat64Array([0, 0, 0, 0, 0])}


func _prepare(coordinator: RefCounted, slot: int, source: Dictionary, runner: Object) -> Dictionary:
	var opened: Dictionary = coordinator.begin(slot, "set", source, 0, 30_000)
	if not bool(opened.get("ok", false)):
		runner.assert_true(false, "coordinator begins: %s" % str(opened))
		return opened
	for _step: int in 1000:
		var progress: Dictionary = coordinator.step(opened.handle, Baseline.MAX_WORK, 256)
		if not bool(progress.get("ok", false)):
			runner.assert_true(false, "coordinator advances: %s" % str(progress))
			return progress
		if not bool(progress.get("pending", true)):
			var finished: Dictionary = coordinator.finish(opened.handle)
			return {"ok": bool(finished.get("ok", false)), "proof": finished.get("proof"), "handle": opened.handle,
				"temperature_chunks": finished.get("temperature_chunks", []), "phase_chunks": finished.get("phase_chunks", [])}
	runner.assert_true(false, "coordinator completes bounded work")
	return {"ok": false}


func _response_participation(runner: Object) -> void:
	var field := Ground.new()
	var temperature := Temperature.new()
	var phases := Phases.new()
	var coordinator := Change.new()
	var fixture := SegmentFixture.new()
	var settings := {"climate": fixture._climate(), "weather": fixture._weather(),
		"weather_epoch_ms": 0, "seed": 42, "tau_ms": 1000, "tide_grid_ms": 10_000}
	if not field.configure(MAP, 4) or not temperature.configure(MAP, 512, 0) or not phases.configure(MAP, 512, 0):
		runner.assert_true(false, "effect response owners configure")
		return
	if not coordinator.configure(field, temperature, settings, Callable(self, "_initial_temperature"), phases, Callable(self, "_initial_phases")):
		runner.assert_true(false, "effect coordinator configures")
		return
	field.set_source(0, Vector2i(8, 8), 3, [1000, 0, 0, 0, 0, 0, 0])
	field.set_source(1, Vector2i(8, 8), 3, [5000, 0, 0, 0, 0, 0, 0])
	if not _warm(field, Rect2i(Vector2i.ZERO, Vector2i(16, 16)), runner):
		return
	var unchanged_temperature: Dictionary = temperature.snapshot()
	var unchanged_phases: Dictionary = phases.snapshot()
	# The stronger source dominates this entire channel, so changing the weaker
	# source is a real source change but does not retarget either response.
	var muted := {"cell": Vector2i(8, 8), "radius": 3, "channels": [2000, 0, 0, 0, 0, 0, 0]}
	var ready: Dictionary = _prepare(coordinator, 0, muted, runner)
	if not bool(ready.get("ok", false)):
		return
	runner.assert_eq(ready.temperature_chunks.size(), 0, "a dominated source does not engage temperature")
	runner.assert_eq(ready.phase_chunks.size(), 0, "a dominated source does not engage phase responses")
	var committed: Dictionary = coordinator.commit(ready.proof)
	runner.assert_true(bool(committed.get("ok", false)), "a source-only change commits")
	runner.assert_eq(temperature.snapshot(), unchanged_temperature, "the unaffected temperature owner is not reanchored")
	runner.assert_eq(phases.snapshot(), unchanged_phases, "the unaffected phase owner is not reanchored")
	# Now the first source wins in an elemental channel and still does not
	# participate in the unrelated thermal response.
	var stronger := {"cell": Vector2i(8, 8), "radius": 3, "channels": [6000, 0, 0, 0, 0, 0, 0]}
	ready = _prepare(coordinator, 0, stronger, runner)
	if not bool(ready.get("ok", false)):
		return
	runner.assert_eq(ready.temperature_chunks.size(), 0, "an elemental-only change skips temperature")
	runner.assert_eq(ready.phase_chunks.size(), 1, "the affected response domain participates")
	committed = coordinator.commit(ready.proof)
	runner.assert_true(bool(committed.get("ok", false)), "the affected response commits with its field")
	runner.assert_eq(temperature.snapshot(), unchanged_temperature, "other optional channels are untouched")
	runner.assert_true(bool(phases.actual_at(Vector2i(8, 8), 1000).get("ok", false)), "the participating response starts from real initial conditions")
	var phase_before_heat: Dictionary = phases.snapshot()
	var hot := {"cell": Vector2i(8, 8), "radius": 3, "channels": [6000, 0, 0, 0, 0, 5000, 0]}
	ready = _prepare(coordinator, 0, hot, runner)
	if not bool(ready.get("ok", false)):
		return
	runner.assert_eq(ready.temperature_chunks.size(), 1, "a thermal-only change engages temperature")
	runner.assert_eq(ready.phase_chunks.size(), 0, "a thermal-only change skips phase responses")
	committed = coordinator.commit(ready.proof)
	runner.assert_true(bool(committed.get("ok", false)), "the thermal response commits")
	runner.assert_eq(phases.snapshot(), phase_before_heat, "thermal changes do not reanchor other response channels")
	var weaker := {"cell": Vector2i(8, 8), "radius": 3, "channels": [4000, 0, 0, 0, 0, 0, 0]}
	ready = _prepare(coordinator, 1, weaker, runner)
	if not bool(ready.get("ok", false)):
		return
	var temp_before_stale: Dictionary = temperature.snapshot()
	var phase_before_stale: Dictionary = phases.snapshot()
	field.set_source(2, Vector2i(24, 8), 1, [1, 0, 0, 0, 0, 0, 0])
	runner.assert_eq(coordinator.can_commit(ready.proof).get("reason"), "stale", "a source-only candidate still rejects an intervening field write")
	runner.assert_true(not bool(coordinator.commit(ready.proof).get("ok", true)), "a stale source-only candidate cannot publish")
	runner.assert_eq(temperature.snapshot(), temp_before_stale, "a stale source-only candidate cannot change temperature")
	runner.assert_eq(phases.snapshot(), phase_before_stale, "a stale source-only candidate cannot change phase responses")
	runner.assert_true(bool(coordinator.cancel(ready.handle).get("ok", false)), "the stale candidate remains cancellable")


func _cold_tile_proof(runner: Object) -> void:
	var fast := Ground.new()
	var full := Baseline.new()
	var size := Vector2i(64, 16)
	if not fast.configure(size, 2) or not full.configure(size, 2):
		runner.assert_true(false, "cold field fixtures configure")
		return
	fast.set_source(1, Vector2i(55, 8), 2, [3000, 0, 0, 0, 0, 0, 0])
	full.set_source(1, Vector2i(55, 8), 2, [3000, 0, 0, 0, 0, 0, 0])
	var source := {"cell": Vector2i(2, 2), "radius": 2, "channels": [1000, 0, 0, 0, 0, 0, 0]}
	var first: Dictionary = fast.begin_source_change(0, "set", source)
	var second: Dictionary = full.begin_source_change(0, "set", source)
	if not bool(first.get("ok", false)) or not bool(second.get("ok", false)):
		runner.assert_true(false, "cold source candidates begin")
		return
	var a: Dictionary = _candidate(fast, first.handle, runner)
	var b: Dictionary = _candidate(full, second.handle, runner)
	if not bool(a.get("ok", false)) or not bool(b.get("ok", false)):
		return
	var result: Dictionary = fast.candidate_tile_copy(a.proof, int(first.tile_ids[0]))
	var expected: Dictionary = full.candidate_tile_copy(b.proof, int(second.tile_ids[0]))
	runner.assert_eq(result.channels, expected.channels, "a locally empty cold block matches complete reconstruction")
	var masks_correct: bool = result.get("change_mask") is PackedByteArray
	if masks_correct:
		for index: int in result.change_mask.size():
			var expected_mask: int = 1 if int(result.channels[index * CHANNELS]) != 0 else 0
			if int(result.change_mask[index]) != expected_mask:
				masks_correct = false
	runner.assert_true(masks_correct, "a proven empty cold block reports only the nonzero changed cells")
	runner.assert_true(int(a.total_work) < int(b.total_work), "cold proof uses less counted work than a full receiver rebuild")
	runner.assert_true(bool(fast.cancel_source_change(first.handle).get("ok", false)), "the cold candidate cancels")
	runner.assert_true(bool(full.cancel_source_change(second.handle).get("ok", false)), "the cold reference candidate cancels")


func _cold_tile_falls_back(runner: Object) -> void:
	var field := Ground.new()
	field.configure(Vector2i(16, 16), 2)
	field.set_source(1, Vector2i(4, 4), 2, [500, 0, 0, 0, 0, 0, 0])
	var opened: Dictionary = field.begin_source_change(0, "set", {"cell": Vector2i(2, 2), "radius": 2, "channels": [1000, 0, 0, 0, 0, 0, 0]})
	if not bool(opened.get("ok", false)):
		runner.assert_true(false, "cold source candidate begins")
		return
	var ready: Dictionary = _candidate(field, opened.handle, runner)
	if not bool(ready.get("ok", false)):
		return
	var tile: Dictionary = field.candidate_tile_copy(ready.proof, int(opened.tile_ids[0]))
	runner.assert_true(not tile.has("change_mask"), "a cold tile with other nearby sources uses the complete candidate fallback")
	runner.assert_true(bool(field.cancel_source_change(opened.handle).get("ok", false)), "the fallback can be cancelled without publishing")
