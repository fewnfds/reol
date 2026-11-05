extends SceneTree
## Original world-owner adapter/capture costs. Uses the same integration fixture;
## no object-density or rendered FPS claim. Run under an external resource guard.

const SAMPLES: int = 100
var failed: int = 0
var checks: int = 0
var _fixture: RefCounted


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Fixtures transitively reference runtime scripts with autoload names. Load
	# them after the SceneTree initializes those autoloads, like the main runner.
	var source: GDScript = load("res://tests/sim/test_world_object_query.gd")
	if source == null or not source.can_instantiate():
		quit(1)
		return
	_fixture = source.new()
	var assembled: Dictionary = _fixture._world(self)
	if assembled.is_empty() or failed > 0:
		quit(1)
		return
	var world: RegionalSimulation = assembled.world
	var references: Array = _fixture._refs(assembled.blueprint)
	var before: String = SnapshotValues.canonical_json(SnapshotValues.normalized(world.to_dict()))
	var describe_us: Array[int] = []
	var capture_us: Array[int] = []
	var visits: int = 0
	for _sample: int in SAMPLES:
		var started: int = Time.get_ticks_usec()
		for reference: Dictionary in references:
			var row: Dictionary = world.describe_object(reference)
			assert_true(bool(row.get("ok", false)), "real owner describes successfully")
		describe_us.append(Time.get_ticks_usec() - started)
		started = Time.get_ticks_usec()
		var result: Dictionary = world.capture_object_space(references)
		capture_us.append(Time.get_ticks_usec() - started)
		if not bool(result.get("ok", false)):
			assert_true(false, "real source capture succeeds")
			continue
		var query: Dictionary = result.snapshot.query(Rect2i(90, 90, 35, 35), "", "", 1024)
		assert_true(bool(query.get("ok", false)) and query.references.size() == references.size(), "area contains every captured original reference once")
		visits = maxi(visits, int(query.get("work_used", 0)))
	assert_eq(SnapshotValues.canonical_json(SnapshotValues.normalized(world.to_dict())), before, "measurement cannot advance or change the world")
	var human_count: int = 0
	for sim: VillageSimulation in world.regions.values():
		human_count += sim.actors.size()
	describe_us.sort()
	capture_us.sort()
	print("BENCH_WORLD_OBJECT_QUERY ", JSON.stringify({
		"scope": "original_world_owner_adapters", "samples": SAMPLES, "references_per_sample": references.size(),
		"regions": world.regions.size(), "humans": human_count, "birds": world.avian_life.birds.size(),
		"large_bodies": world.large_bodies.bodies.size(), "unique_items": world.artifacts.objects.size(),
		"describe_batch_ms": _costs(describe_us), "capture_batch_ms": _costs(capture_us),
		"query_work_max": visits, "checks": checks, "failed": failed,
		"not_rendered_fps": true, "not_dense_world_capacity": true,
		"processor": OS.get_processor_name(), "engine": Engine.get_version_info().string,
	}, "", true, true))
	quit(1 if failed else 0)


func _costs(sorted: Array[int]) -> Dictionary:
	return {"p50": float(sorted[49]) / 1000.0, "p95": float(sorted[94]) / 1000.0,
		"p99": float(sorted[98]) / 1000.0, "max": float(sorted.back()) / 1000.0}


func assert_true(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed += 1
		printerr("FAIL ", label)


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	assert_true(actual == expected, label)
