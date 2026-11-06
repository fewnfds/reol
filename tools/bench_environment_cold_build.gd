extends SceneTree
## Offline benchmark using real original lifecycle-created ground sources.
## The caller must use an external process time/memory guard. It measures only
## a cold CPU base field, not response evolution, rendering, GPU or Main.

const Definitions = preload("res://scripts/data/environment_source_definitions.gd")
const GroundCache = preload("res://scripts/sim/environment_ground_cache.gd")
const Bindings = preload("res://scripts/sim/environment_source_bindings.gd")
const MAX_PUMPS: int = 5_000_000
const MAX_WORK: int = 100_000
const MAX_USEC: int = 100_000
const SAMPLE_BUDGET: int = 16384

var _fixture: RefCounted
var _fixture_failures: Array[String] = []
var _output: String = ""
var _report: Dictionary = {
	"benchmark": "environment_cold_build", "ok": false, "first_failure": null,
	"scope": "real lifecycle stock and artifact sources; leased source assembly then requested cold CPU base field",
	"limits": "no rendered FPS, GPU, response history, walking-source trail, or ordinary Main integration; use external process memory/time guard",
	"memory_scope": "static counters exclude process allocations; external guard samples peak working/private bytes"}


func _initialize() -> void:
	call_deferred("_run")


func assert_true(condition: bool, label: String) -> void:
	if not condition:
		_fixture_failures.append(label)


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fixture_failures.append("%s: %s != %s" % [label, str(actual), str(expected)])


func _run() -> void:
	var options: Dictionary = _arguments(OS.get_cmdline_user_args())
	if not bool(options.get("ok", false)):
		_fail("arguments", options)
		return
	_output = str(options.output)
	var side: int = int(options.size)
	@warning_ignore("integer_division")
	var a := Vector2i(side / 2, side / 2)
	var b := a + Vector2i.RIGHT
	_report.merge({"size": side, "distribution": options.distribution,
		"radius_cells": 16, "advance_work": options.work, "advance_usec": options.usec,
		"engine": Engine.get_version_info(), "processor": OS.get_processor_name(),
		"logical_processors": OS.get_processor_count(), "static_before_bytes": OS.get_static_memory_usage()})
	var total_start: int = Time.get_ticks_usec()
	var fixture_script: Script = load("res://tests/sim/test_object_lifecycle.gd")
	if fixture_script == null:
		_fail("fixture_load")
		return
	_fixture = fixture_script.new()
	var start: int = Time.get_ticks_usec()
	var world: RegionalSimulation = _fixture._world(self)
	if world == null or not _fixture_failures.is_empty():
		_fail("world_fixture", {"assertions": _fixture_failures})
		return
	_report["fixture_ms"] = _elapsed_ms(start)
	var initial_ms: int = world.elapsed_ms
	var initial_target: int = world.target_ms
	start = Time.get_ticks_usec()
	var fill: Dictionary = _fill(world, side, a, b, str(options.distribution))
	_report["creation_ms"] = _elapsed_ms(start)
	_report["creation"] = fill
	if not bool(fill.get("ok", false)):
		_fail("creation", fill)
		return
	_report["static_after_creation_bytes"] = OS.get_static_memory_usage()
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/environment_sources.json"))
	if not raw is Dictionary or not raw.get("profiles") is Dictionary:
		_fail("definitions_file")
		return
	# Same profile as the existing response benchmark, with an optional mixed
	# negative source for testing heterogeneous channels and equal maxima.
	raw.profiles.ordinary_plant.radius_cells = 16
	raw.profiles.ordinary_earth.radius_cells = 16
	raw.profiles.ordinary_earth.thermal_grade = 2000
	if options.distribution == "mixed":
		raw.profiles.ordinary_water.radius_cells = 16
		raw.profiles.ordinary_water.thermal_grade = -1500
	start = Time.get_ticks_usec()
	var definitions := Definitions.new()
	if not definitions.configure(raw):
		_fail("definitions_configuration")
		return
	var oracle := Bindings.new()
	if not oracle.configure(world, definitions):
		_fail("oracle_configuration")
		return
	var cache := GroundCache.new()
	if not cache.configure(world, definitions):
		_fail("cache_configuration")
		return
	var lease := RefCounted.new()
	if not cache.acquire_compute_backend(lease):
		_fail("assembly_lease")
		return
	_report["configuration_ms"] = _elapsed_ms(start)
	_report["definition_digest"] = definitions.digest()
	start = Time.get_ticks_usec()
	var assembly: Dictionary = _drain(cache, int(options.work), int(options.usec), true)
	assembly["wall_ms"] = _elapsed_ms(start)
	_report["assembly"] = assembly
	if not bool(assembly.get("ok", false)):
		_fail("assembly", assembly)
		return
	if not cache.release_compute_backend(lease):
		_fail("release_lease")
		return
	_report["static_after_assembly_bytes"] = OS.get_static_memory_usage()
	start = Time.get_ticks_usec()
	var request: Dictionary = cache.request_area(Rect2i(0, 0, side, side))
	if not bool(request.get("ok", false)):
		_fail("field_request", request)
		return
	var build: Dictionary = _drain(cache, int(options.work), int(options.usec), false)
	build["request_and_wall_ms"] = _elapsed_ms(start)
	build["request"] = request
	_report["cpu_field"] = build
	if not bool(build.get("ok", false)):
		_fail("cpu_field", build)
		return
	_report["static_after_field_bytes"] = OS.get_static_memory_usage()
	start = Time.get_ticks_usec()
	var checked: Dictionary = _compare(cache, oracle, side, a, b)
	checked["wall_ms"] = _elapsed_ms(start)
	_report["independent_samples"] = checked
	if not bool(checked.get("ok", false)):
		_fail("independent_samples", checked)
		return
	if world.elapsed_ms != initial_ms or world.target_ms != initial_target:
		_fail("world_time_changed", {"before": initial_ms, "elapsed": world.elapsed_ms, "target": world.target_ms})
		return
	_report["diagnostics"] = cache.diagnostics()
	cache.close()
	_report["static_peak_bytes"] = OS.get_static_memory_peak_usage()
	_report["total_ms"] = _elapsed_ms(total_start)
	_report["ok"] = true
	_finish(0)


func _fill(world: RegionalSimulation, side: int, a: Vector2i, b: Vector2i, distribution: String) -> Dictionary:
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var inventory: SimInventory = world.regions.home.inventory
	for item: String in ["wood", "water"]:
		inventory.containers.store[item] = inventory.quantity("store", item) + side * side
	var source: Dictionary = lifecycle.execute(_fixture._spawn("bench_slate_start", "bench_slate", "plain_slate", [a.x, a.y]))
	if not bool(source.get("ok", false)):
		return {"ok": false, "reason": "slate", "result": source}
	var stocks: int = 0
	var water: int = 0
	var blocked: int = 0
	for y: int in side:
		for x: int in side:
			var cell := Vector2i(x, y)
			if cell == a or cell == b:
				continue
			if not world.map_data.terrain_is_walkable(cell) or world.construction.blocked(cell):
				blocked += 1
				continue
			var material: String = "water" if distribution == "mixed" and (x + y) % 4 == 0 else "wood"
			var command: String = "bench_stock_%d_%d" % [x, y]
			var request: Dictionary = _fixture._transfer(command, _fixture._location("store"), _fixture._ground(x, y), material, 1)
			var result: Dictionary = lifecycle.execute(request)
			if not bool(result.get("ok", false)):
				return {"ok": false, "reason": "stock", "cell": [x, y], "result": result, "stocks": stocks}
			stocks += 1
			if material == "water":
				water += 1
	return {"ok": true, "stocks": stocks, "water": water, "artifacts": 1, "blocked": blocked,
		"empty_destination": [b.x, b.y], "scope": "each ground pile created by an original lifecycle transfer"}


func _drain(cache: RefCounted, work: int, usec: int, assembly_only: bool) -> Dictionary:
	var durations: Array[int] = []
	var total_work: int = 0
	for iteration: int in MAX_PUMPS:
		var start: int = Time.get_ticks_usec()
		var result: Dictionary = cache.advance(work, usec)
		durations.append(Time.get_ticks_usec() - start)
		if not bool(result.get("ok", false)):
			return {"ok": false, "reason": "advance_failed", "result": result, "calls": iteration + 1}
		total_work += int(result.get("work_used", 0))
		var sources_ready: bool = result.get("state") == "ready" and int(result.get("pending_sources", 0)) == 0
		if sources_ready and (assembly_only or int(result.get("pending_tiles", 0)) == 0):
			return {"ok": true, "calls": iteration + 1, "work_used": total_work,
				"call_usec": _percentiles(durations), "last": result}
	return {"ok": false, "reason": "pump_limit", "calls": MAX_PUMPS, "work_used": total_work}


func _compare(cache: RefCounted, oracle: RefCounted, side: int, a: Vector2i, b: Vector2i) -> Dictionary:
	var cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i(side - 1, 0), Vector2i(0, side - 1),
		Vector2i(side - 1, side - 1), a, b, a + Vector2i(15, 0), a + Vector2i(0, 15),
		Vector2i(15, 15), Vector2i(16, 16)]
	for point: Vector2i in cells:
		var cached: Dictionary = cache.read_base(point)
		var direct: Dictionary = oracle.sample_base(point, SAMPLE_BUDGET)
		if not bool(cached.get("ok", false)) or bool(cached.get("pending", true)) or not bool(direct.get("ok", false)) \
			or not bool(direct.get("complete", false)) or cached.get("elements") != direct.get("elements") \
			or cached.get("thermal_grade") != direct.get("thermal_grade") \
			or cached.get("config_digest") != direct.get("config_digest") or cached.get("rule_version") != direct.get("rule_version"):
			return {"ok": false, "reason": "independent_sample_mismatch", "cell": [point.x, point.y], "cached": cached, "direct": direct}
	return {"ok": true, "count": cells.size(), "scope": "independent original-source query; five elements and composed thermal at map edges, block boundary, source and near source"}


func _arguments(args: PackedStringArray) -> Dictionary:
	var options: Dictionary = {"ok": true, "size": 64, "work": 4096, "usec": 2000, "distribution": "uniform", "output": ""}
	for arg: String in args:
		if arg.begins_with("--size=") and arg.trim_prefix("--size=").is_valid_int():
			options.size = int(arg.trim_prefix("--size="))
		elif arg.begins_with("--work=") and arg.trim_prefix("--work=").is_valid_int():
			options.work = int(arg.trim_prefix("--work="))
		elif arg.begins_with("--usec=") and arg.trim_prefix("--usec=").is_valid_int():
			options.usec = int(arg.trim_prefix("--usec="))
		elif arg.begins_with("--distribution="):
			options.distribution = arg.trim_prefix("--distribution=")
		elif arg.begins_with("--output="):
			options.output = arg.trim_prefix("--output=")
		else:
			return {"ok": false, "reason": "unknown_argument", "argument": arg}
	if options.size not in [64, 128, 512] or options.distribution not in ["uniform", "mixed"] \
		or options.work < 1 or options.work > MAX_WORK or options.usec < 1 or options.usec > MAX_USEC:
		return {"ok": false, "reason": "invalid_options", "options": options}
	return options


func _percentiles(values: Array[int]) -> Dictionary:
	if values.is_empty():
		return {"count": 0}
	values.sort()
	return {"count": values.size(), "p50": _percentile(values, 0.50), "p95": _percentile(values, 0.95),
		"p99": _percentile(values, 0.99), "max": values.back()}


func _percentile(values: Array[int], fraction: float) -> int:
	return values[clampi(int(ceil(float(values.size()) * fraction)) - 1, 0, values.size() - 1)]


func _elapsed_ms(started: int) -> float:
	return float(Time.get_ticks_usec() - started) / 1000.0


func _fail(reason: String, detail: Dictionary = {}) -> void:
	_report["first_failure"] = {"reason": reason, "detail": detail}
	_finish(1)


func _finish(code: int) -> void:
	var payload: String = JSON.stringify(_report, "", true, true)
	if not _output.is_empty():
		var file := FileAccess.open(_output, FileAccess.WRITE)
		if file == null:
			_report["ok"] = false
			_report["first_failure"] = {"reason": "report_open", "path": _output, "error": FileAccess.get_open_error()}
			payload = JSON.stringify(_report, "", true, true)
			code = 1
		else:
			file.store_string(payload + "\n")
			file.close()
	print("ENV_COLD_BUILD_BENCHMARK " + payload)
	quit(code)
