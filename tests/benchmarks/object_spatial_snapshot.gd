extends SceneTree
## Synthetic captured geometry only; no real world objects, simulation or frames.
## Run a fresh process under the project guard, for example:
## godot --headless --path . --script res://tests/benchmarks/object_spatial_snapshot.gd -- 512

const Snapshot = preload("res://scripts/sim/object_spatial_snapshot.gd")
const SAMPLES: int = 1000
const RANDOM_SEED: int = 6162026
const CAPTURE_TIME_MS: int = 12345
const SINGLE_QUERY_BUDGET: int = 1024


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 1 or (args.size() == 1 and args[0] not in ["64", "128", "256", "512"]):
		_fail("expected optional dimension 64, 128, 256 or 512")
		return
	var dimension: int = 64 if args.is_empty() else int(args[0])
	var count: int = dimension * dimension
	var static_before_bytes: int = OS.get_static_memory_usage()
	var snapshot := Snapshot.new(count, count)
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	var build_start: int = Time.get_ticks_usec()
	for y: int in dimension:
		for x: int in dimension:
			cells[0] = Vector2i(x, y)
			var id: int = y * dimension + x
			var added: Dictionary = snapshot.append({"kind": "synthetic", "id": str(id)}, cells, "ground", "placed")
			if not bool(added.get("ok", false)):
				_fail("append rejected cell %s: %s" % [str(cells[0]), str(added.get("reason", "unknown"))])
				return
	var sealed: Dictionary = snapshot.seal(CAPTURE_TIME_MS)
	var build_us: int = Time.get_ticks_usec() - build_start
	if not bool(sealed.get("ok", false)):
		_fail("snapshot seal failed")
		return
	var stats: Dictionary = snapshot.stats()
	if int(stats.get("objects", -1)) != count or int(stats.get("entries", -1)) != count or not bool(stats.get("sealed", false)):
		_fail("captured geometry counts differ from the requested density")
		return
	var static_after_build_bytes: int = OS.get_static_memory_usage()
	var rng := RandomNumberGenerator.new()
	rng.seed = RANDOM_SEED
	var costs_us: Array[int] = []
	var work_max: int = 0
	for _sample: int in SAMPLES:
		var x: int = rng.randi_range(0, dimension - 1)
		var y: int = rng.randi_range(0, dimension - 1)
		var begin: int = Time.get_ticks_usec()
		var result: Dictionary = snapshot.query(Rect2i(x, y, 1, 1), "ground", "placed", SINGLE_QUERY_BUDGET)
		costs_us.append(Time.get_ticks_usec() - begin)
		if not bool(result.get("ok", false)) or not bool(result.get("complete", false)) or result.get("scope") != "captured_references" or bool(result.get("live", true)) or int(result.get("world_time_ms", -1)) != CAPTURE_TIME_MS:
			_fail("single-cell query failed or lost snapshot provenance")
			return
		var references: Array = result.get("references", [])
		if references.size() != 1 or references[0] != {"kind": "synthetic", "id": str(y * dimension + x)}:
			_fail("single-cell query returned an incorrect reference")
			return
		work_max = maxi(work_max, int(result.get("work_used", -1)))
	if not _check_cross_bucket(snapshot, dimension):
		_fail("17x17 cross-bucket query did not return exactly its requested cells")
		return
	var insufficient: Dictionary = snapshot.query(Rect2i(0, 0, dimension, dimension), "ground", "placed", 32)
	if bool(insufficient.get("ok", true)) or bool(insufficient.get("complete", true)) or insufficient.get("reason") != "budget_exhausted" or insufficient.has("references") or int(insufficient.get("work_used", 33)) > 32:
		_fail("small full-map budget must fail without publishing partial results")
		return
	if not _check_layer_fixture():
		_fail("ground, roof or contained relation was misclassified")
		return
	costs_us.sort()
	var report: Dictionary = {
		"scope": "synthetic_geometry_only",
		"not_actual_world_objects": true,
		"not_world_fps_or_process_memory": true,
		"dimension": dimension,
		"objects": count,
		"entries": count,
		"buckets": int(stats.buckets),
		"samples": SAMPLES,
		"seed": RANDOM_SEED,
		"capture_world_time_ms": CAPTURE_TIME_MS,
		"build_ms": float(build_us) / 1000.0,
		"query_ms": {"p50": _percentile_ms(costs_us, 0.50), "p95": _percentile_ms(costs_us, 0.95),
			"p99": _percentile_ms(costs_us, 0.99), "max": float(costs_us.back()) / 1000.0},
		"query_work_max": work_max,
		"query_budget": SINGLE_QUERY_BUDGET,
		"memory_static_before_bytes": static_before_bytes,
		"memory_static_after_build_bytes": static_after_build_bytes,
		"memory_static_peak_bytes": OS.get_static_memory_peak_usage(),
		"memory_scope": "Godot static allocations; peak covers whole process lifetime, not process RSS or private bytes; debug builds only",
		"engine": Engine.get_version_info(),
		"processor": OS.get_processor_name(),
		"logical_processors": OS.get_processor_count(),
		"guard": "Run under an external owned-process 30-second / 1-GiB guard",
	}
	print("BENCH_OBJECT_SPATIAL ", JSON.stringify(report, "", true, true))
	quit(0)


func _check_cross_bucket(snapshot: RefCounted, dimension: int) -> bool:
	var area := Rect2i(15, 15, 17, 17)
	var result: Dictionary = snapshot.query(area, "ground", "placed", 4096)
	if not bool(result.get("ok", false)) or not bool(result.get("complete", false)):
		return false
	var references: Array = result.get("references", [])
	if references.size() != 17 * 17:
		return false
	var seen: Dictionary[int, bool] = {}
	for reference: Variant in references:
		if not reference is Dictionary or reference.get("kind") != "synthetic" or not reference.get("id") is String or not str(reference.id).is_valid_int():
			return false
		var id: int = int(reference.id)
		if id < 0 or id >= dimension * dimension or seen.has(id):
			return false
		@warning_ignore("integer_division")
		var y: int = id / dimension
		var x: int = id % dimension
		if not area.has_point(Vector2i(x, y)):
			return false
		seen[id] = true
	return true


func _check_layer_fixture() -> bool:
	var snapshot := Snapshot.new(3, 3)
	var cells: Array[Vector2i] = [Vector2i(1, 1)]
	var ground: Dictionary = {"kind": "synthetic", "id": "ground"}
	var roof: Dictionary = {"kind": "synthetic", "id": "roof"}
	var contained: Dictionary = {"kind": "synthetic", "id": "contained"}
	if not bool(snapshot.append(ground, cells, "ground", "placed").get("ok", false)):
		return false
	if not bool(snapshot.append(roof, cells, "roof", "placed").get("ok", false)):
		return false
	if not bool(snapshot.append(contained, cells, "container", "contained").get("ok", false)):
		return false
	if not bool(snapshot.seal(CAPTURE_TIME_MS).get("ok", false)):
		return false
	var area := Rect2i(1, 1, 1, 1)
	for pair: Array in [["ground", "placed", ground], ["roof", "placed", roof], ["container", "contained", contained]]:
		var result: Dictionary = snapshot.query(area, str(pair[0]), str(pair[1]), 16)
		if not bool(result.get("ok", false)) or result.get("references", []) != [pair[2]]:
			return false
	return true


func _percentile_ms(sorted_costs_us: Array[int], percentile: float) -> float:
	var index: int = clampi(int(ceil(float(sorted_costs_us.size()) * percentile)) - 1, 0, sorted_costs_us.size() - 1)
	return float(sorted_costs_us[index]) / 1000.0


func _fail(message: String) -> void:
	printerr("ERROR BENCH_OBJECT_SPATIAL ", message)
	quit(1)
