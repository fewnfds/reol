extends SceneTree
## Actual original finite emitters, bounded read-only light queries. Run with
## -- 1 or -- 5 under the project's 30-second/1-GiB owned-process guard.

const SAMPLES: int = 60
var _failed: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] not in ["1", "5"]:
		_fail("expected actual source count 1 or 5")
		return
	var count: int = int(args[0])
	var fixture: RefCounted = load("res://tests/sim/test_local_light.gd").new()
	var world: RegionalSimulation = fixture._world(self, 9000000000, true, count)
	if world == null:
		_fail("original world did not initialize")
		return
	var at: Vector2i = world.artifacts.object_cell("fire_stone")
	var points: Array[Vector2i] = []
	for y: int in range(at.y - 10, at.y + 11):
		for x: int in range(at.x - 10, at.x + 11):
			points.append(Vector2i(x, y))
	var off: Dictionary = _measure(world, points)
	for index: int in count:
		var id: String = "fire_stone" if index == 0 else "extra_fire_%d" % index
		for verb: String in ["study", "enable"]:
			if not fixture._devices._action(self, world, "player", verb, id):
				_fail("original paid action did not activate the declared source")
				return
	var on: Dictionary = _measure(world, points)
	if off.is_empty() or on.is_empty():
		_fail("query failed or changed authoritative world state")
		return
	var active: int = world.local_heat.device_emission_rates(world.elapsed_ms).rates.size()
	if _failed > 0 or active != count or int(on.peak) <= 0 or int(off.peak) != 0:
		_fail("requested counts are not actual emitting devices")
		return
	print("BENCHMARK_JSON ", JSON.stringify({"benchmark": "local_light", "engine": Engine.get_version_info(),
		"processor": OS.get_processor_name(), "logical_processors": OS.get_processor_count(),
		"actual_emitters": active, "actual_thermal_cells": world.local_heat.cells.size(),
		"sample_count": SAMPLES, "query_cells": points.size(), "off": off, "on": on,
		"scope": "Headless development executable, original nonautonomous fixture bodies and actual personal study/enable. Before activation vs after paid setup, not a same-time speedup claim. Sixty bounded synchronous queries, not rendering/FPS, 128-source capacity or long-time stress evidence."}))
	quit(0)


func _measure(world: RegionalSimulation, points: Array[Vector2i]) -> Dictionary:
	var before: String = _canonical(world)
	var costs: Array[int] = []
	var peak: int = 0
	for _sample: int in SAMPLES:
		var start: int = Time.get_ticks_usec()
		var patch: Dictionary = SimLocalLight.local_patch(world, points)
		costs.append(Time.get_ticks_usec() - start)
		if not bool(patch.supported) or patch.values.size() != points.size():
			return {}
		for value: int in patch.values.values():
			peak = maxi(peak, value)
	if _canonical(world) != before:
		return {}
	return {"query_us": costs, "peak": peak, "world_sha256": before.sha256_text()}


func _canonical(world: RegionalSimulation) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(world.to_dict()))


func assert_true(condition: bool, label: String) -> void:
	if not condition:
		_failed += 1
		_fail(label)


func _fail(message: String) -> void:
	printerr("LOCAL_LIGHT_BENCHMARK_FAILED ", message)
	quit(1)
