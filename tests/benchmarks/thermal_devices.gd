extends SceneTree
## Small real-world simulation probe. Run with one argument, 1 or 2, under the
## external 30-second / 1-GiB process guard; no rendering capacity is measured.

const Fixtures = preload("res://tests/sim/test_thermal_devices.gd")
const SAMPLES: int = 40
const STEP_MS: int = 1000
const FUTURE_MS: int = 7337
const FIRE: String = "fire_stone"
const COLD: String = "cold_stone"

var _failed: int = 0


func _initialize() -> void:
	call_deferred("_run")


func assert_true(condition: bool, label: String) -> void:
	if not condition:
		_failed += 1
		printerr("BENCHMARK_CHECK_FAILED " + label)


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failed += 1
		printerr("BENCHMARK_CHECK_FAILED %s: expected %s, got %s" % [label, str(expected), str(actual)])


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_valid_int() or int(args[0]) not in [1, 2]:
		_fail("expected one device-count argument: 1 or 2")
		return
	var count: int = int(args[0])
	var fixture := Fixtures.new()
	var active: RegionalSimulation = fixture._world(self)
	var quiet: RegionalSimulation = fixture._world(self)
	if active == null or quiet == null or _failed > 0:
		_fail("could not assemble two original regional worlds")
		return
	var setup_start: int = Time.get_ticks_usec()
	var enabled: bool = false
	if count == 1:
		enabled = fixture._action(self, active, "player", "study", FIRE) and fixture._action(self, active, "player", "enable", FIRE)
	else:
		enabled = fixture._enable_pair(self, active)
	var enable_setup_ms: float = _ms_since(setup_start)
	if not enabled or _failed > 0:
		_fail("genuine personal study and device activation failed")
		return
	var start_ms: int = int(active.elapsed_ms)
	setup_start = Time.get_ticks_usec()
	var aligned: bool = quiet.advance_to_ms(start_ms)
	var quiet_alignment_ms: float = _ms_since(setup_start)
	if not aligned or int(quiet.elapsed_ms) != start_ms or _failed > 0:
		_fail("quiet world could not reach the same initial world time")
		return
	if not bool(active.artifacts.objects[FIRE].enabled) or bool(active.artifacts.objects[COLD].enabled) != (count == 2):
		_fail("the actual enabled original devices do not match the requested count")
		return
	if bool(quiet.artifacts.objects[FIRE].enabled) or bool(quiet.artifacts.objects[COLD].enabled):
		_fail("the comparison world is not a quiet opening")
		return

	# Both measurements begin at the same clock, but are sequential in one
	# process: the quiet case runs first and no frame/render loop is measured.
	var quiet_result: Dictionary = _measure(fixture, quiet, "quiet")
	if quiet_result.is_empty() or _failed > 0:
		_fail("quiet measurement or its independent restore failed")
		return
	var active_result: Dictionary = _measure(fixture, active, "enabled")
	if active_result.is_empty() or _failed > 0:
		_fail("enabled measurement or its independent restore failed")
		return
	var quiet_start: Dictionary = quiet_result.initial
	var quiet_end: Dictionary = quiet_result.final
	var active_start: Dictionary = active_result.initial
	var active_end: Dictionary = active_result.final
	assert_true(int(quiet_start.cells) == 0 and int(quiet_end.cells) == 0 and int(quiet_start.flows) == 0 and int(quiet_end.flows) == 0, "disabled opening remains a quiet field")
	assert_eq(int(quiet_end.continuous_input), 0, "quiet opening spends no source energy")
	assert_eq(int(quiet_end.absorbed_energy), 0, "quiet opening absorbs no heat")
	assert_true(int(active_start.cells) > 0 and int(active_start.flows) > 0, "real activation creates physical field cells and nonzero flows")
	assert_true(int(active_end.continuous_input) > int(active_start.continuous_input), "measured source consumes its real stock")
	if count == 2:
		assert_true(int(active_end.absorbed_energy) > int(active_start.absorbed_energy), "measured sink stores its actual absorbed heat")
	else:
		assert_eq(int(active_end.absorbed_energy), 0, "the disabled sink does not acquire heat")
	if _failed > 0:
		_fail("measured worlds did not satisfy the intended source/sink conditions")
		return
	var actors: int = 0
	for simulation: VillageSimulation in active.regions.values():
		actors += simulation.actors.size()
	var report: Dictionary = {"benchmark": "thermal_devices", "engine": Engine.get_version_info(),
		"os": OS.get_name(), "processor": OS.get_processor_name(), "logical_processors": OS.get_processor_count(),
		"device_count": count, "regions": active.regions.size(), "actors": actors,
		"start_time_ms": start_ms, "step_ms": STEP_MS, "samples_per_scenario": SAMPLES,
		"enable_setup_ms": enable_setup_ms, "quiet_alignment_ms": quiet_alignment_ms,
		"quiet": quiet_result, "enabled": active_result,
		"limitations": "Single guarded headless process; quiet measured before enabled; two fixture regions and one fixed source location. Forty samples are descriptive, not rendering FPS or a 16-device capacity claim."}
	print("BENCHMARK_JSON " + JSON.stringify(report, "", true, true))
	quit(0)


func _measure(fixture: Fixtures, world: RegionalSimulation, label: String) -> Dictionary:
	var initial: Dictionary = _metrics(world)
	fixture._conserved(self, world, label + " initial field conserves original energy")
	if _failed > 0:
		return {}
	var timings: Array[float] = []
	for index: int in range(SAMPLES):
		var target: int = int(world.elapsed_ms) + STEP_MS
		var started: int = Time.get_ticks_usec()
		var reached: bool = world.advance_to_ms(target)
		timings.append(_ms_since(started))
		if not reached or int(world.elapsed_ms) != target:
			assert_true(false, "%s actual clock reaches sample %d" % [label, index])
			return {}
	var final: Dictionary = _metrics(world)
	fixture._conserved(self, world, label + " measured field conserves original energy")
	if _failed > 0:
		return {}

	var started: int = Time.get_ticks_usec()
	var snapshot: Dictionary = world.to_dict()
	var capture_ms: float = _ms_since(started)
	if snapshot.is_empty():
		assert_true(false, label + " captures a complete world")
		return {}
	started = Time.get_ticks_usec()
	var encoded: String = JSON.stringify(snapshot, "", true, true)
	var encode_ms: float = _ms_since(started)
	started = Time.get_ticks_usec()
	var decoded: Variant = JSON.parse_string(encoded)
	var decode_ms: float = _ms_since(started)
	if not decoded is Dictionary:
		assert_true(false, label + " JSON roundtrip yields a world dictionary")
		return {}
	started = Time.get_ticks_usec()
	var candidate: RegionalSimulation = fixture._world(self)
	var candidate_setup_ms: float = _ms_since(started)
	if candidate == null or _failed > 0:
		assert_true(false, label + " assembles an independent candidate")
		return {}
	started = Time.get_ticks_usec()
	var restored: bool = candidate.restore(decoded)
	var restore_ms: float = _ms_since(started)
	assert_true(restored, label + " restores the actual complete world")
	if not restored:
		return {}
	assert_true(candidate != world and candidate.environment_fields != world.environment_fields and candidate.artifacts != world.artifacts, label + " restore uses independent original owners")
	var expected_snapshot: String = fixture._json(snapshot)
	assert_eq(fixture._json(candidate.to_dict()), expected_snapshot, label + " JSON restore preserves the complete measured state")
	if _failed > 0:
		return {}

	var from_ms: int = int(world.elapsed_ms)
	var whole: bool = world.advance_to_ms(from_ms + FUTURE_MS)
	var split: bool = candidate.advance_to_ms(from_ms + 337) and candidate.advance_to_ms(from_ms + 5000) and candidate.advance_to_ms(from_ms + FUTURE_MS)
	assert_true(whole and split, label + " both original and restored worlds reach the same future")
	if not whole or not split:
		return {}
	fixture._conserved(self, world, label + " original future conserves energy")
	fixture._conserved(self, candidate, label + " restored future conserves energy")
	assert_eq(fixture._json(candidate.to_dict()), fixture._json(world.to_dict()), label + " restored slices and original whole advance produce the same complete future")
	if _failed > 0:
		return {}
	return {"initial": initial, "final": final, "advance_ms": _distribution(timings),
		"persistence_ms": {"capture": capture_ms, "json_encode": encode_ms, "json_decode": decode_ms,
			"independent_candidate_setup": candidate_setup_ms, "restore": restore_ms},
		"json_bytes": encoded.to_utf8_buffer().size(), "restore_and_future_equal": true}


func _metrics(world: RegionalSimulation) -> Dictionary:
	# Values are measured directly from the owning field and original objects;
	# the report is a point-in-time observation, never an alternative ledger.
	var cell_energy: int = 0
	for row: Dictionary in world.environment_fields.cells.values():
		cell_energy += int(row.energy)
	return {"at_ms": int(world.elapsed_ms), "cells": world.environment_fields.cells.size(), "flows": world.environment_fields.flows.size(),
		"cell_energy": cell_energy, "input_energy": int(world.environment_fields.input_energy),
		"ambient_in": int(world.environment_fields.ambient_in), "loss_energy": int(world.environment_fields.loss_energy),
		"continuous_input": int(world.environment_fields.continuous_input), "absorbed_energy": int(world.environment_fields.absorbed_energy),
		"fire_emitted": int(world.environment_fields.device_input.get(FIRE, 0)), "cold_absorbed": int(world.environment_fields.device_absorbed.get(COLD, 0)),
		"fire_stored_q": int(world.artifacts.objects[FIRE].stored_q), "cold_stored_q": int(world.artifacts.objects[COLD].stored_q)}


func _distribution(values: Array[float]) -> Dictionary:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return {"samples": sorted.size(), "p50": _percentile(sorted, 0.50), "p95": _percentile(sorted, 0.95),
		"p99": _percentile(sorted, 0.99), "max": sorted[-1]}


func _percentile(values: Array[float], fraction: float) -> float:
	return values[clampi(ceili(values.size() * fraction) - 1, 0, values.size() - 1)]


func _ms_since(start: int) -> float:
	return float(Time.get_ticks_usec() - start) / 1000.0


func _fail(message: String) -> void:
	printerr("BENCHMARK_ERROR " + message)
	quit(1)
