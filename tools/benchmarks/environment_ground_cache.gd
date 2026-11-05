extends SceneTree
## Offline cache benchmark. Run through environment_ground_cache_guard.py.
## All sources are real lifecycle-created artifacts or original inventory piles;
## the fixture's world is not the player's live world. This does not draw frames,
## simulate motion, change actual temperature, run GPU work, or measure FPS.

const Fixture = preload("res://tests/sim/test_regional_simulation.gd")
const Cache = preload("res://scripts/sim/environment_ground_cache.gd")
const SIDES: Array[int] = [64, 128, 256, 512]
const SAMPLE_BUDGET: int = 16384
const ADVANCE_WORK: int = 4096
const ADVANCE_USEC: int = 2000
const MAX_ADVANCES: int = 5000000
const HOT_READS: int = 1024
const HOT_BATCHES: int = 20
const REFERENCE_SAMPLES: int = 16

var _fixture := Fixture.new()
var _fixture_failures: Array[String] = []
var _artifact_cells := PackedInt32Array()
var _report: Dictionary = {
	"benchmark": "environment_ground_cache",
	"ok": false,
	"scope": "real ground lifecycle artifacts and stock in a flat two-region fixture",
	"limitations": "offline CPU base-target cache only; no rendered FPS, GPU, actual temperature, time advancement or save/load",
	"memory_scope": "Godot static counters are not process RSS; external guard samples process memory over the whole child lifetime",
	"first_failure": null,
}


class FlatMap extends WorldMapData:
	func get_terrain(cell: Vector2i) -> int:
		return TERRAIN_GRASS if in_bounds(cell) else -1

	func get_elevation(cell: Vector2i) -> int:
		return 0 if in_bounds(cell) else -1


func _initialize() -> void:
	call_deferred("_run")


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
	var side: int = int(options.side)
	_report["side"] = side
	_report["requested_cells"] = side * side
	_report["radius_mode"] = options.radii
	_report["full_field_requested"] = options.full_field
	_report["changes_requested"] = options.changes
	_report["advance_budget"] = {"work": ADVANCE_WORK, "target_usec": ADVANCE_USEC}
	_report["engine"] = Engine.get_version_info()
	_report["processor"] = OS.get_processor_name()
	_report["logical_processors"] = OS.get_processor_count()
	_report["static_before_bytes"] = OS.get_static_memory_usage()
	var start: int = Time.get_ticks_usec()
	var world: RegionalSimulation = _fixture._make_world(self)
	if world == null or not _fixture_failures.is_empty():
		_fail("fixture", {"assertions": _fixture_failures})
		return
	world.bind_map_data(FlatMap.new())
	if world.object_lifecycle == null or world.artifacts == null or world.construction == null:
		_fail("fixture_missing_owners")
		return
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	if int(lifecycle.ground.stats().active) != 0:
		_fail("fixture_ground_not_empty", lifecycle.ground.stats())
		return
	_report["fixture_setup_ms"] = _elapsed_ms(start)
	# Fixture-only stock is seeded before binding the cache. All floor piles are
	# subsequently created by the same real transfer API used by gameplay.
	var inventory: SimInventory = world.regions.home.inventory
	for item: String in ["wood", "grain", "water"]:
		inventory.containers.store[item] = inventory.quantity("store", item) + side * side
	start = Time.get_ticks_usec()
	var counts: Dictionary = _create_sources(world, side)
	_report["creation_ms"] = _elapsed_ms(start)
	if not bool(counts.ok):
		_fail("source_creation", counts)
		return
	_report["creation"] = counts
	_report["creation_scope"] = "row-major terrain/structure precheck and one public lifecycle spawn or stock_transfer per unblocked cell"
	_report["ground_after_creation"] = lifecycle.ground.stats()
	_report["static_after_creation_bytes"] = OS.get_static_memory_usage()
	if int(lifecycle.ground.stats().active) != int(counts.artifacts) + int(counts.material_piles):
		_fail("source_count_mismatch", counts)
		return

	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/environment_sources.json"))
	if not raw is Dictionary or not raw.get("profiles") is Dictionary or not raw.get("bindings") is Dictionary:
		_fail("definition_file")
		return
	var configured: Dictionary = _prepare_definitions(raw, str(options.radii))
	if not bool(configured.ok):
		_fail("definition_profiles", configured)
		return
	start = Time.get_ticks_usec()
	var definitions := EnvironmentSourceDefinitions.new()
	if not definitions.configure(raw):
		_fail("definition_configuration")
		return
	var oracle := SimEnvironmentSourceBindings.new()
	if not oracle.configure(world, definitions):
		_fail("oracle_configuration")
		return
	var service: RefCounted = Cache.new()
	if not service.configure(world, definitions):
		_fail("cache_configuration")
		return
	_report["configuration_ms"] = _elapsed_ms(start)
	_report["configuration_digest"] = definitions.digest()
	_report["configuration_scope"] = "definition validation + independent A1 oracle kernel + cache configure; assembly measured separately"
	_report["static_after_configuration_bytes"] = OS.get_static_memory_usage()
	var initial_time: int = world.elapsed_ms
	var initial_target: int = world.target_ms
	start = Time.get_ticks_usec()
	var assembled: Dictionary = _drain(service)
	_report["assembly_ms"] = _elapsed_ms(start)
	_report["assembly"] = assembled
	if not bool(assembled.ok):
		_fail("assembly", assembled)
		return
	_report["static_after_assembly_bytes"] = OS.get_static_memory_usage()
	@warning_ignore("integer_division")
	var window := Rect2i((side / 32) * 16, (side / 32) * 16, 16, 16)
	start = Time.get_ticks_usec()
	var requested: Dictionary = service.request_area(window)
	if not bool(requested.get("ok", false)):
		_fail("local_window_request", requested)
		return
	var local: Dictionary = _drain(service)
	_report["local_window"] = {"rect": [window.position.x, window.position.y, window.size.x, window.size.y],
		"request_and_build_ms": _elapsed_ms(start), "request": requested, "drain": local}
	if not bool(local.ok):
		_fail("local_window_build", local)
		return
	var reads: Dictionary = _measure_reads(service, oracle, window)
	_report["hot_reads"] = reads
	if not bool(reads.ok):
		_fail("hot_reads_or_reference", reads)
		return
	if bool(options.full_field):
		start = Time.get_ticks_usec()
		var full_request: Dictionary = service.request_area(Rect2i(0, 0, side, side))
		if not bool(full_request.get("ok", false)):
			_fail("full_field_request", full_request)
			return
		var full: Dictionary = _drain(service)
		_report["full_field"] = {"request_and_build_ms": _elapsed_ms(start), "request": full_request, "drain": full,
			"scope": "the complete selected square; one 16x16 local window was already warm"}
		if not bool(full.ok):
			_fail("full_field_build", full)
			return
	else:
		_report["full_field"] = {"status": "not_requested"}

	if bool(options.changes):
		var pool: PackedInt32Array = _local_artifacts(world, side, window)
		if pool.size() < 64:
			_fail("insufficient_local_artifacts", {"count": pool.size()})
			return
		var changes: Dictionary = {}
		for amount: int in [1, 16, 64]:
			var selected := PackedInt32Array()
			for i: int in amount:
				selected.append(pool[i])
			var batch: Dictionary = _mutation_batch(world, service, oracle, side, selected, "local_%d" % amount)
			changes["local_%d" % amount] = batch
			if not bool(batch.ok):
				_report["changes"] = changes
				_fail("local_change", batch)
				return
		var scattered := PackedInt32Array()
		@warning_ignore("integer_division")
		var scattered_count: int = maxi(1, int(lifecycle.ground.stats().active) / 100)
		for i: int in scattered_count:
			@warning_ignore("integer_division")
			var at: int = i * _artifact_cells.size() / scattered_count
			scattered.append(_artifact_cells[at])
		var batch: Dictionary = _mutation_batch(world, service, oracle, side, scattered, "scattered_1_percent")
		changes["scattered_1_percent"] = batch
		changes["scope"] = "actual lifecycle move ground -> actor -> original cell; count is 1% of all generated ground sources, selected among artifacts evenly over generation order"
		_report["changes"] = changes
		if not bool(batch.ok):
			_fail("scattered_change", batch)
			return
	else:
		_report["changes"] = {"status": "not_requested"}
	if world.elapsed_ms != initial_time or world.target_ms != initial_target:
		_fail("world_time_changed", {"before": initial_time, "elapsed": world.elapsed_ms, "target": world.target_ms})
		return
	_report["diagnostics_before_close"] = service.diagnostics()
	_report["static_before_close_bytes"] = OS.get_static_memory_usage()
	start = Time.get_ticks_usec()
	service.close()
	service = null
	_report["cache_close_usec"] = Time.get_ticks_usec() - start
	_report["static_after_close_bytes"] = OS.get_static_memory_usage()
	_report["close_scope"] = "cache close only; fixture, oracle and original world remain alive until child process exits"
	_report["static_peak_bytes"] = OS.get_static_memory_peak_usage()
	_report["world_time_ms"] = initial_time
	_report["ok"] = true
	_print_and_quit(0)


func _create_sources(world: RegionalSimulation, side: int) -> Dictionary:
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var artifacts: int = 0
	var materials: int = 0
	var blocked: int = 0
	for y: int in side:
		for x: int in side:
			var point := Vector2i(x, y)
			if not world.map_data.terrain_is_walkable(point) or world.construction.blocked(point):
				blocked += 1
				continue
			var index: int = y * side + x
			var request: Dictionary
			if index % 4 == 0:
				@warning_ignore("integer_division")
				var material: String = ["wood", "grain", "water", "wood"][(index / 4) % 4]
				request = {"command": "cache_bench_stock_%d" % index, "op": "stock_transfer",
					"from": {"region": "home", "container": "store"}, "to": {"region": "home", "cell": [x, y]},
					"item": material, "amount": 1}
			else:
				request = {"command": "cache_bench_spawn_%d" % index, "op": "spawn",
					"id": _object_id(index), "definition": "plain_slate", "to": {"region": "home", "cell": [x, y]}}
			var result: Dictionary = lifecycle.execute(request)
			if not bool(result.get("ok", false)):
				return {"ok": false, "cell": [x, y], "result": result}
			if index % 4 == 0:
				materials += 1
			else:
				artifacts += 1
				_artifact_cells.append(index)
	return {"ok": true, "artifacts": artifacts, "material_piles": materials, "blocked": blocked}


func _prepare_definitions(raw: Dictionary, mode: String) -> Dictionary:
	if not raw.profiles.get("ordinary_earth") is Dictionary or not raw.profiles.get("ordinary_plant") is Dictionary \
		or not raw.profiles.get("ordinary_water") is Dictionary or not raw.bindings.get("materials") is Dictionary:
		return {"ok": false, "reason": "missing_profile"}
	# Benchmark-only candidate. It never writes or changes the shipped content.
	raw.profiles["benchmark_grain"] = raw.profiles.ordinary_plant.duplicate(true)
	raw.bindings.materials.grain = "benchmark_grain"
	raw.profiles.ordinary_earth.radius_cells = 16
	raw.profiles.ordinary_earth.thermal_grade = 1000
	raw.profiles.ordinary_plant.radius_cells = 16 if mode == "max" else 4
	raw.profiles.ordinary_plant.thermal_grade = 2000
	raw.profiles.ordinary_water.radius_cells = 16 if mode == "max" else 8
	raw.profiles.ordinary_water.thermal_grade = -1500
	raw.profiles.benchmark_grain.radius_cells = 16 if mode == "max" else 2
	raw.profiles.benchmark_grain.thermal_grade = 500
	return {"ok": true}


func _drain(service: RefCounted) -> Dictionary:
	var durations: Array[int] = []
	var total_work: int = 0
	for iteration: int in MAX_ADVANCES:
		var start: int = Time.get_ticks_usec()
		var result: Dictionary = service.advance(ADVANCE_WORK, ADVANCE_USEC)
		durations.append(Time.get_ticks_usec() - start)
		if not bool(result.get("ok", false)):
			return {"ok": false, "reason": "advance_failed", "result": result, "calls": iteration + 1}
		total_work += int(result.get("work_used", 0))
		if result.get("state") == "ready" and int(result.get("pending_tiles", 0)) == 0 and int(result.get("pending_sources", 0)) == 0:
			return {"ok": true, "calls": iteration + 1, "work_used": total_work,
				"call_wall_usec": _percentiles(durations), "last": result}
	return {"ok": false, "reason": "advance_limit", "calls": MAX_ADVANCES, "work_used": total_work}


func _measure_reads(service: RefCounted, oracle: SimEnvironmentSourceBindings, window: Rect2i) -> Dictionary:
	var durations: Array[int] = []
	var batches: Array[int] = []
	for _batch: int in HOT_BATCHES:
		var batch_start: int = Time.get_ticks_usec()
		for i: int in HOT_READS:
			var index: int = i % (window.size.x * window.size.y)
			@warning_ignore("integer_division")
			var point := window.position + Vector2i(index % window.size.x, index / window.size.x)
			var start: int = Time.get_ticks_usec()
			var result: Dictionary = service.read_base(point)
			durations.append(Time.get_ticks_usec() - start)
			if not bool(result.get("ok", false)) or bool(result.get("pending", true)):
				return {"ok": false, "reason": "hot_read_pending", "cell": [point.x, point.y], "result": result}
		batches.append(Time.get_ticks_usec() - batch_start)
	for i: int in REFERENCE_SAMPLES:
		var point := window.position + Vector2i((i * 7) % 16, (i * 11) % 16)
		var cached: Dictionary = service.read_base(point)
		var reference: Dictionary = oracle.sample_base(point, SAMPLE_BUDGET)
		if not bool(cached.get("ok", false)) or bool(cached.get("pending", true)) or not bool(reference.get("ok", false)) \
			or cached.get("elements") != reference.get("elements") or cached.get("thermal_grade") != reference.get("thermal_grade"):
			return {"ok": false, "reason": "independent_sample_mismatch", "cell": [point.x, point.y], "cached": cached, "reference": reference}
	return {"ok": true, "batch_size": HOT_READS, "batches": HOT_BATCHES,
		"batch_total_usec": _percentiles(batches), "per_read_usec": _percentiles(durations),
		"independent_reference_samples": REFERENCE_SAMPLES,
		"scope": "20 batches of 1024 sequential reads across a warm 16x16 window; 16 separate A1 oracle checks excluded from timing"}


func _local_artifacts(world: RegionalSimulation, side: int, window: Rect2i) -> PackedInt32Array:
	var result := PackedInt32Array()
	for y: int in range(window.position.y, window.end.y):
		for x: int in range(window.position.x, window.end.x):
			var index: int = y * side + x
			if world.artifacts.objects.has(_object_id(index)):
				result.append(index)
	return result


func _mutation_batch(world: RegionalSimulation, service: RefCounted, oracle: SimEnvironmentSourceBindings, side: int, indices: PackedInt32Array, label: String) -> Dictionary:
	var durations: Array[int] = []
	var start: int = Time.get_ticks_usec()
	for index: int in indices:
		var id: String = _object_id(index)
		var item: Dictionary = world.artifacts.objects[id]
		var request: Dictionary = {"command": "cache_bench_%s_hold_%d" % [label, index], "op": "move", "id": id,
			"from": {"region": item.region, "container": item.container}, "to": {"region": "home", "container": "actor:player"}}
		var one: int = Time.get_ticks_usec()
		var moved: Dictionary = world.object_lifecycle.execute(request)
		durations.append(Time.get_ticks_usec() - one)
		if not bool(moved.get("ok", false)):
			return {"ok": false, "reason": "hold_failed", "index": index, "result": moved}
	var commit_ms: float = _elapsed_ms(start)
	start = Time.get_ticks_usec()
	var drain: Dictionary = _drain(service)
	var resync_ms: float = _elapsed_ms(start)
	if not bool(drain.ok):
		return {"ok": false, "reason": "removed_resync", "drain": drain}
	if label.begins_with("local_"):
		@warning_ignore("integer_division")
		var changed_point := Vector2i(indices[0] % side, indices[0] / side)
		var comparison: Dictionary = _compare_one(service, oracle, changed_point)
		if not bool(comparison.ok):
			return {"ok": false, "reason": "removed_reference_mismatch", "detail": comparison}
	# Restore originals to their previous cells so each next batch starts with the
	# same real geometry. The restoration cost is separately reported.
	start = Time.get_ticks_usec()
	for index: int in indices:
		var id: String = _object_id(index)
		var item: Dictionary = world.artifacts.objects[id]
		@warning_ignore("integer_division")
		var point := Vector2i(index % side, index / side)
		var request: Dictionary = {"command": "cache_bench_%s_restore_%d" % [label, index], "op": "move", "id": id,
			"from": {"region": item.region, "container": item.container}, "to": {"region": "home", "cell": [point.x, point.y]}}
		var restored: Dictionary = world.object_lifecycle.execute(request)
		if not bool(restored.get("ok", false)):
			return {"ok": false, "reason": "restore_failed", "index": index, "result": restored}
	var restoration_commit_ms: float = _elapsed_ms(start)
	start = Time.get_ticks_usec()
	var restored_drain: Dictionary = _drain(service)
	var restoration_resync_ms: float = _elapsed_ms(start)
	if not bool(restored_drain.ok):
		return {"ok": false, "reason": "restore_resync", "drain": restored_drain}
	if label.begins_with("local_"):
		@warning_ignore("integer_division")
		var restored_point := Vector2i(indices[0] % side, indices[0] / side)
		var comparison: Dictionary = _compare_one(service, oracle, restored_point)
		if not bool(comparison.ok):
			return {"ok": false, "reason": "restored_reference_mismatch", "detail": comparison}
	return {"ok": true, "count": indices.size(), "commit_total_ms": commit_ms,
		"per_commit_usec": _percentiles(durations), "resync_ms": resync_ms, "drain": drain,
		"restoration_commit_ms": restoration_commit_ms, "restoration_resync_ms": restoration_resync_ms,
		"restoration_drain": restored_drain,
		"scope": "synchronous original-object commits followed by draining only requested cache tiles; local batches cross-check A1 after removal and restoration outside timings"}


func _compare_one(service: RefCounted, oracle: SimEnvironmentSourceBindings, point: Vector2i) -> Dictionary:
	var cached: Dictionary = service.read_base(point)
	var reference: Dictionary = oracle.sample_base(point, SAMPLE_BUDGET)
	if not bool(cached.get("ok", false)) or bool(cached.get("pending", true)) or not bool(reference.get("ok", false)) \
		or cached.get("elements") != reference.get("elements") or cached.get("thermal_grade") != reference.get("thermal_grade"):
		return {"ok": false, "cell": [point.x, point.y], "cached": cached, "reference": reference}
	return {"ok": true}


func _arguments(args: PackedStringArray) -> Dictionary:
	var options: Dictionary = {"ok": true, "side": 64, "radii": "max", "full_field": true, "changes": true}
	var index: int = 0
	while index < args.size():
		match args[index]:
			"--side":
				index += 1
				if index >= args.size() or not args[index].is_valid_int():
					return {"ok": false, "reason": "invalid_side"}
				options.side = args[index].to_int()
			"--radii":
				index += 1
				if index >= args.size():
					return {"ok": false, "reason": "invalid_radii"}
				options.radii = args[index]
			"--no-full-field": options.full_field = false
			"--no-changes": options.changes = false
			_: return {"ok": false, "reason": "unknown_argument", "argument": args[index]}
		index += 1
	if options.side not in SIDES or options.radii not in ["max", "mixed"]:
		return {"ok": false, "reason": "unsupported_options", "side": options.side, "radii": options.radii}
	return options


func _object_id(index: int) -> String:
	return "cache_bench_slate_%d" % index


func _percentiles(values: Array[int]) -> Dictionary:
	if values.is_empty():
		return {"count": 0}
	values.sort()
	return {"count": values.size(), "p50": _percentile(values, 0.5), "p95": _percentile(values, 0.95),
		"p99": _percentile(values, 0.99), "max": values.back()}


func _percentile(values: Array[int], fraction: float) -> int:
	var index: int = clampi(int(ceil(float(values.size()) * fraction)) - 1, 0, values.size() - 1)
	return values[index]


func _elapsed_ms(start: int) -> float:
	return float(Time.get_ticks_usec() - start) / 1000.0


func _fail(reason: String, detail: Dictionary = {}) -> void:
	_report["first_failure"] = {"reason": reason, "detail": detail}
	_print_and_quit(1)


func _print_and_quit(code: int) -> void:
	print("ENV_GROUND_CACHE_BENCHMARK " + JSON.stringify(_report, "", true, true))
	quit(code)
