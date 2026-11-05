extends SceneTree
## Offline query benchmark with real lifecycle-owned artifacts. Example:
## godot --headless --path . --script res://tests/benchmarks/environment_source_bindings.gd -- --side 64
## Run under an external time/memory guard; this script never draws or advances
## the world and measures neither frame time, GPU, nor process RSS.

const Fixture = preload("res://tests/sim/test_regional_simulation.gd")
const SIDES: Array[int] = [64, 128, 256, 512]
const QUERY_BUDGET: int = 16_384
const QUERY_COUNT: int = 256
const MARGIN: int = 16

var _fixture := Fixture.new()
var _fixture_failures: Array[String] = []
var _report: Dictionary = {
	"benchmark": "environment_source_bindings",
	"ok": false,
	"scope": "real lifecycle-created ground artifacts, flat two-region fixture; one definition and accounting region",
	"limitations": "offline local base-target queries only; no world ticks, response update, rendering, FPS, GPU, process RSS or save/load",
	"memory_scope": "Godot static allocation counters, not process RSS, whole-machine RAM or GPU memory",
	"guard": "an external process guard must enforce time and memory limits",
	"first_failure": null,
}


class FlatMap extends WorldMapData:
	func get_terrain(cell: Vector2i) -> int:
		return TERRAIN_GRASS if in_bounds(cell) else -1

	func get_elevation(cell: Vector2i) -> int:
		return 0 if in_bounds(cell) else -1


func _initialize() -> void:
	call_deferred("_run")


# The reusable world fixture records failures through the runner interface.
func assert_true(condition: bool, label: String) -> void:
	if not condition:
		_fixture_failures.append(label)


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fixture_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _run() -> void:
	var options: Dictionary = _arguments(OS.get_cmdline_user_args())
	if not bool(options.ok):
		_fail("arguments", options)
		return
	var side: int = options.side
	_report["side"] = side
	_report["requested_cells"] = side * side
	_report["radius_cells"] = 16
	_report["query_budget"] = QUERY_BUDGET
	_report["engine"] = Engine.get_version_info()
	_report["processor"] = OS.get_processor_name()
	_report["logical_processors"] = OS.get_processor_count()
	_report["memory_static_before_bytes"] = OS.get_static_memory_usage()
	var started: int = Time.get_ticks_usec()
	var world: RegionalSimulation = _fixture._make_world(self)
	if world == null or not _fixture_failures.is_empty():
		_fail("world_fixture_failed", {"assertions": _fixture_failures})
		return
	world.bind_map_data(FlatMap.new())
	if world.object_lifecycle == null or world.artifacts == null or world.construction == null:
		_fail("fixture_missing_owners")
		return
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	if int(lifecycle.ground.stats().active) != 0 or not lifecycle.created.is_empty():
		_fail("fixture_requires_empty_ground", lifecycle.ground.stats())
		return
	_report["fixture_setup_ms"] = _elapsed_ms(started)
	_report["initial_artifacts"] = world.artifacts.objects.size()
	_report["generated"] = 0
	_report["blocked_terrain_cells"] = 0
	_report["blocked_built_structure_cells"] = 0
	_report["blocked_workspace_cells"] = 0
	started = Time.get_ticks_usec()
	for y: int in side:
		for x: int in side:
			var point := Vector2i(x, y)
			if not world.map_data.terrain_is_walkable(point):
				_report.blocked_terrain_cells += 1
				continue
			if world.construction.blocked(point):
				if world.construction._blocked.has(point):
					_report.blocked_built_structure_cells += 1
				else:
					_report.blocked_workspace_cells += 1
				continue
			var index: int = y * side + x
			var request: Dictionary = {"command": "field_bench_spawn_%d" % index, "op": "spawn",
				"id": _object_id(index), "definition": "plain_slate", "to": {"region": "home", "cell": [x, y]}}
			var result: Dictionary = lifecycle.execute(request)
			if not bool(result.get("ok", false)):
				_fail("spawn_failed", {"cell": [x, y], "result": result})
				return
			_report.generated += 1
	_report["creation_ms"] = _elapsed_ms(started)
	_report["creation_scope"] = "row-major terrain and structure checks plus one public lifecycle spawn per allowed cell"
	_report["ground_after_creation"] = lifecycle.ground.stats()
	_report["memory_static_after_creation_bytes"] = OS.get_static_memory_usage()
	var blocked: int = int(_report.blocked_terrain_cells) + int(_report.blocked_built_structure_cells) + int(_report.blocked_workspace_cells)
	if int(_report.generated) + blocked != side * side or int(lifecycle.ground.stats().active) != int(_report.generated) \
		or world.artifacts.objects.size() != int(_report.initial_artifacts) + int(_report.generated):
		_fail("generation_count_mismatch")
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/environment_sources.json"))
	if not raw is Dictionary or not raw.get("profiles") is Dictionary or not raw.profiles.get("ordinary_earth") is Dictionary:
		_fail("invalid_definition_file")
		return
	# Benchmark-only candidate: a maximum supported radius, plus a thermal
	# channel. Neither fixture edits the shipped JSON nor changes game content.
	raw.profiles.ordinary_earth.radius_cells = 16
	raw.profiles.ordinary_earth.thermal_grade = 1000
	started = Time.get_ticks_usec()
	var definitions := EnvironmentSourceDefinitions.new()
	if not definitions.configure(raw):
		_fail("definition_configuration_failed")
		return
	var bindings := SimEnvironmentSourceBindings.new()
	if not bindings.configure(world, definitions):
		_fail("source_configuration_failed")
		return
	_report["definition_and_kernel_setup_ms"] = _elapsed_ms(started)
	_report["configuration_digest"] = definitions.digest()
	_report["memory_static_after_configuration_bytes"] = OS.get_static_memory_usage()
	var initial_time: int = world.elapsed_ms
	var initial_target: int = world.target_ms
	var initial_revision: int = lifecycle.ground.revision
	var initial_objects: int = world.artifacts.objects.size()
	var region_times: Dictionary = {}
	for region: String in world.regions:
		region_times[region] = world.regions[region].elapsed_ms
	var measured: Dictionary = _measure_queries(world, bindings, side)
	if not bool(measured.get("ok", false)):
		_fail("sample_query_failed", measured)
		return
	_report["queries"] = measured
	if world.elapsed_ms != initial_time or world.target_ms != initial_target or lifecycle.ground.revision != initial_revision \
		or world.artifacts.objects.size() != initial_objects:
		_fail("query_mutated_time_or_object_counts")
		return
	for region: String in region_times:
		if world.regions[region].elapsed_ms != region_times[region]:
			_fail("query_advanced_region", {"region": region})
			return
	_report["world_time_ms"] = initial_time
	_report["ground_revision"] = initial_revision
	_report["memory_static_end_bytes"] = OS.get_static_memory_usage()
	_report["memory_static_peak_bytes"] = OS.get_static_memory_peak_usage()
	_report["ok"] = true
	_print_and_quit(0)


func _measure_queries(world: RegionalSimulation, bindings: SimEnvironmentSourceBindings, side: int) -> Dictionary:
	var points: Array[Vector2i] = []
	var distinct: Dictionary = {}
	var buckets: Dictionary = {}
	var fallback_count: int = 0
	var span: int = side - 2 * MARGIN
	for row: int in 16:
		for column: int in 16:
			# Uniform deterministic grid of 256 interior queries; actual objects,
			# not empty blocked coordinates, anchor every measured center.
			var x: int = MARGIN + int(float((2 * column + 1) * span) / 32.0)
			var y: int = MARGIN + int(float((2 * row + 1) * span) / 32.0)
			var point := Vector2i(x, y)
			if not world.artifacts.objects.has(_object_id(y * side + x)):
				fallback_count += 1
				point = _nearby_object(world, side, point, span)
				if point.x < 0:
					return {"ok": false, "reason": "no_interior_source", "grid_point": [x, y]}
			points.append(point)
			distinct[point] = true
			buckets[Vector2i(point.x >> 4, point.y >> 4)] = true
	if points.size() != QUERY_COUNT:
		return {"ok": false, "reason": "wrong_query_count"}
	var low_budget: Dictionary = bindings.sample_base(points[0], 1)
	if bool(low_budget.get("ok", true)) or bool(low_budget.get("complete", true)) \
		or low_budget.get("reason") != "budget_exhausted" or low_budget.has("elements"):
		return {"ok": false, "reason": "partial_budget_result", "result": low_budget}
	# One warmup excludes first-use profile caching from the percentile sample.
	var warmup: Dictionary = bindings.sample_base(points[0], QUERY_BUDGET)
	if not bool(warmup.get("ok", false)):
		return {"ok": false, "reason": "warmup_failed", "result": warmup}
	var times_usec: Array[int] = []
	var candidates: Array[int] = []
	var work: Array[int] = []
	var sources: Array[int] = []
	for point: Vector2i in points:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = bindings.sample_base(point, QUERY_BUDGET)
		times_usec.append(Time.get_ticks_usec() - started)
		if not bool(result.get("ok", false)) or not bool(result.get("complete", false)) \
			or result.get("elements") != [0, 0, 1000, 100, 0] or result.get("thermal_grade") != 1000 \
			or int(result.get("source_count", 0)) < 1 or int(result.get("candidate_count", 0)) < 1 \
			or int(result.get("work_used", 0)) > QUERY_BUDGET:
			return {"ok": false, "reason": "incorrect_sample", "cell": [point.x, point.y], "result": result}
		candidates.append(int(result.candidate_count))
		work.append(int(result.work_used))
		sources.append(int(result.source_count))
	return {"ok": true, "samples": points.size(), "warmup_queries": 1, "fallback_from_blocked": fallback_count,
		"distinct_cells": distinct.size(), "distinct_16x16_buckets": buckets.size(),
		"query_time_us": _percentiles(times_usec), "candidate_count": _percentiles(candidates),
		"work_units": _percentiles(work), "contributing_sources": _percentiles(sources),
		"low_budget": {"budget": 1, "reason": low_budget.reason, "complete": false},
		"scope": "256 deterministic interior cells spread over the filled area, each on an actual source; per-query wall time after one warmup"}


func _nearby_object(world: RegionalSimulation, side: int, original: Vector2i, span: int) -> Vector2i:
	var offset: int = (original.y - MARGIN) * span + original.x - MARGIN
	for shift: int in span * span:
		var candidate: int = (offset + shift) % (span * span)
		var point := Vector2i(MARGIN + candidate % span, MARGIN + int(float(candidate) / float(span)))
		if world.artifacts.objects.has(_object_id(point.y * side + point.x)):
			return point
	return Vector2i(-1, -1)


func _arguments(args: PackedStringArray) -> Dictionary:
	var side: int = 64
	if args.size() > 0:
		if args.size() != 2 or args[0] != "--side" or not args[1].is_valid_int():
			return {"ok": false, "reason": "expected --side 64|128|256|512"}
		side = args[1].to_int()
	if side not in SIDES:
		return {"ok": false, "reason": "unsupported_side", "side": side}
	return {"ok": true, "side": side}


func _object_id(index: int) -> String:
	return "field_bench_slate_%d" % index


func _percentiles(values: Array[int]) -> Dictionary:
	values.sort()
	return {"p50": _percentile(values, 0.50), "p95": _percentile(values, 0.95),
		"p99": _percentile(values, 0.99), "max": values.back()}


func _percentile(sorted: Array[int], fraction: float) -> int:
	var index: int = clampi(int(ceil(float(sorted.size()) * fraction)) - 1, 0, sorted.size() - 1)
	return sorted[index]


func _elapsed_ms(start_usec: int) -> float:
	return float(Time.get_ticks_usec() - start_usec) / 1000.0


func _fail(reason: String, detail: Dictionary = {}) -> void:
	_report["first_failure"] = {"reason": reason, "detail": detail}
	_print_and_quit(1)


func _print_and_quit(exit_code: int) -> void:
	print("ENV_SOURCE_BENCHMARK " + JSON.stringify(_report, "", true, true))
	quit(exit_code)
