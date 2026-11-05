extends SceneTree
## Dense real artifacts in a two-region test world, not synthetic references.
## Run under an external resource guard. Example:
## godot --headless --path . --script res://tests/benchmarks/object_lifecycle_scale.gd -- --side 64 --save-load
## This is an offline simulation benchmark. It measures no frames, GPU or RSS.

const Fixture = preload("res://tests/sim/test_regional_simulation.gd")
const SIDES: Array[int] = [64, 128, 256, 512]
const SEED: int = 6162026
const QUERY_SAMPLES: int = 256
const INTEGRITY_SAMPLES: int = 1000
const BOUNDARY_CALLS: int = 100
const QUERY_BUDGET: int = 1024

var _fixture := Fixture.new()
var _fixture_failures: Array[String] = []
var _report: Dictionary = {
	"benchmark": "object_lifecycle_scale",
	"ok": false,
	"scope": "two-region fixture, flat 512-square map, real lifecycle artifacts",
	"limits": "No rendering, FPS, GPU, process RSS, disk write, separate-process restart or normal-game capacity claim; all generated items use one definition and one accounting region.",
	"first_failure": null,
}


class FlatMap extends WorldMapData:
	func get_terrain(cell: Vector2i) -> int:
		return TERRAIN_GRASS if in_bounds(cell) else -1

	func get_elevation(cell: Vector2i) -> int:
		return 0 if in_bounds(cell) else -1


func _initialize() -> void:
	call_deferred("_run")


# The existing world fixture reports failed setup via the test-runner interface.
func assert_true(condition: bool, label: String) -> void:
	if not condition:
		_fixture_failures.append(label)


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fixture_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _run() -> void:
	var options: Dictionary = _arguments(OS.get_cmdline_user_args())
	if not bool(options.get("ok", false)):
		_fail("arguments", options)
		return
	var side: int = int(options.side)
	var do_save_load: bool = bool(options.save_load)
	_report["side"] = side
	_report["requested_cells"] = side * side
	_report["seed"] = SEED
	_report["engine"] = Engine.get_version_info()
	_report["processor"] = OS.get_processor_name()
	_report["logical_processors"] = OS.get_processor_count()
	_report["memory_scope"] = "Godot static allocation counters only; not process RSS, private bytes, machine memory or GPU memory"
	_report["guard"] = "external process guard required; this script does not set a time or memory limit"
	_report["generated"] = 0
	_report["blocked_built_structure_cells"] = 0
	_report["blocked_workspace_cells"] = 0
	_report["blocked_terrain_cells"] = 0
	_report["requested_save_load"] = do_save_load
	_report["memory_static_before_bytes"] = OS.get_static_memory_usage()
	var setup_start: int = Time.get_ticks_usec()
	var world: RegionalSimulation = _fixture._make_world(self)
	if world == null or not _fixture_failures.is_empty():
		_fail("world_fixture_failed", {"assertions": _fixture_failures})
		return
	world.bind_map_data(FlatMap.new())
	if world.object_lifecycle == null or world.artifacts == null or world.construction == null:
		_fail("fixture_missing_owners")
		return
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var initial_ground: Dictionary = lifecycle.ground.stats()
	if int(initial_ground.active) != 0 or not lifecycle.created.is_empty():
		_fail("fixture_requires_empty_lifecycle", {"ground": initial_ground, "created": lifecycle.created.size()})
		return
	var initial_objects: int = world.artifacts.objects.size()
	_report["fixture_setup_ms"] = _elapsed_ms(setup_start)
	_report["initial_artifacts"] = initial_objects
	var idle_before: Dictionary = _boundary_measure(lifecycle)
	if not bool(idle_before.get("ok", false)):
		_fail("initial_idle_boundary_changed", idle_before)
		return
	var cells := PackedInt32Array()
	var create_start: int = Time.get_ticks_usec()
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
			var request: Dictionary = {"command": _spawn_command(index), "op": "spawn", "id": _object_id(index),
				"definition": "plain_slate", "to": {"region": "home", "cell": [x, y]}}
			var added: Dictionary = lifecycle.execute(request)
			if not bool(added.get("ok", false)):
				_report["creation_ms"] = _elapsed_ms(create_start)
				_fail("generation_failed", {"cell": [x, y], "object_id": _object_id(index), "result": added})
				return
			cells.append(index)
			_report.generated += 1
	_report["creation_ms"] = _elapsed_ms(create_start)
	_report["creation_scope"] = "row-major whole-area terrain/structure precheck plus one public lifecycle spawn per unblocked cell"
	_report["ground_stats_after_creation"] = lifecycle.ground.stats()
	_report["memory_static_after_creation_bytes"] = OS.get_static_memory_usage()
	if cells.is_empty() or int(lifecycle.ground.stats().active) != cells.size() or world.artifacts.objects.size() != initial_objects + cells.size():
		_fail("generation_count_mismatch", {"active_ground": lifecycle.ground.stats().active, "objects": world.artifacts.objects.size()})
		return
	var blocked: int = int(_report.blocked_built_structure_cells) + int(_report.blocked_workspace_cells) + int(_report.blocked_terrain_cells)
	if cells.size() + blocked != side * side:
		_fail("area_accounting_mismatch")
		return
	var idle_after: Dictionary = _boundary_measure(lifecycle)
	if not bool(idle_after.get("ok", false)) or world.artifacts.objects.size() != initial_objects + cells.size():
		_fail("idle_boundary_changed", idle_after)
		return
	_report["idle_boundary_before_creation"] = idle_before
	_report["idle_boundary_after_creation"] = idle_after
	_report["idle_scope"] = "100 synchronous lifecycle next-boundary calls; no world advance or frame. Compare scales, not a tick/FPS measurement."
	var samples: Dictionary = _measure_queries(world, cells, side)
	if not bool(samples.get("ok", false)):
		_fail("sample_query_failed", samples)
		return
	_report["queries"] = samples
	@warning_ignore("integer_division")
	var moved_index: int = cells[cells.size() / 2]
	var move_result: Dictionary = _move_roundtrip(world, moved_index, side)
	if not bool(move_result.get("ok", false)):
		_fail("move_roundtrip_failed", move_result)
		return
	_report["move_roundtrip"] = move_result
	if world.artifacts.objects.size() != initial_objects + cells.size() or int(lifecycle.ground.stats().active) != cells.size():
		_fail("move_duplicated_or_lost_object")
		return
	var integrity: Dictionary = _sample_integrity(world, null, cells, side)
	if not bool(integrity.get("ok", false)):
		_fail("original_integrity_failed", integrity)
		return
	_report["integrity_before_restore"] = integrity
	var progression: Dictionary = _simulate(world)
	if not bool(progression.ok):
		_fail("world_progression_failed", progression)
		return
	_report["world_progression"] = progression
	if do_save_load:
		var saved: Dictionary = _save_load(world, cells, side, initial_objects)
		if not bool(saved.get("ok", false)):
			_fail("save_load_failed", saved)
			return
		_report["save_load"] = saved
	else:
		_report["save_load"] = {"measured": false}
	_report["final_ground_stats"] = lifecycle.ground.stats()
	_report["final_artifacts"] = world.artifacts.objects.size()
	_report["memory_static_end_bytes"] = OS.get_static_memory_usage()
	_report["memory_static_peak_bytes"] = OS.get_static_memory_peak_usage()
	_report["ok"] = true
	print(JSON.stringify(_report, "", true, true))
	quit(0)


func _arguments(args: PackedStringArray) -> Dictionary:
	var side: int = 64
	var save_load: bool = false
	var side_seen: bool = false
	var i: int = 0
	while i < args.size():
		if args[i] == "--side":
			if side_seen or i + 1 >= args.size() or not args[i + 1].is_valid_int():
				return {"ok": false, "reason": "--side requires one dimension: 64, 128, 256 or 512"}
			side = int(args[i + 1])
			side_seen = true
			i += 2
		elif args[i] == "--save-load" and not save_load:
			save_load = true
			i += 1
		else:
			return {"ok": false, "reason": "unknown or repeated argument", "argument": args[i]}
	if side not in SIDES:
		return {"ok": false, "reason": "unsupported side", "side": side}
	return {"ok": true, "side": side, "save_load": save_load}


func _boundary_measure(lifecycle: SimObjectLifecycle) -> Dictionary:
	var costs: Array[int] = []
	var first: int = -1
	for _i: int in BOUNDARY_CALLS:
		var begin: int = Time.get_ticks_usec()
		var value: int = lifecycle.next_boundary_ms()
		costs.append(Time.get_ticks_usec() - begin)
		if first < 0:
			first = value
		elif first != value:
			return {"ok": false, "first": first, "actual": value}
	return {"ok": true, "calls": BOUNDARY_CALLS, "next_ms": first,
		"active_actions": lifecycle._active_actions.size(), "call_ms": _percentiles(costs)}


func _measure_queries(world: RegionalSimulation, cells: PackedInt32Array, side: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var ground_times: Array[int] = []
	var describe_times: Array[int] = []
	var max_work: int = 0
	for _i: int in QUERY_SAMPLES:
		var index: int = cells[rng.randi_range(0, cells.size() - 1)]
		var point: Vector2i = _point(index, side)
		var id: String = _object_id(index)
		var begin: int = Time.get_ticks_usec()
		var result: Dictionary = world.object_lifecycle.ground.query(Rect2i(point, Vector2i.ONE), QUERY_BUDGET)
		ground_times.append(Time.get_ticks_usec() - begin)
		var expected_slot: String = str(world.artifacts.objects[id].container)
		if not bool(result.get("ok", false)) or not bool(result.get("complete", false)) or result.get("ids", []) != [expected_slot]:
			return {"ok": false, "kind": "ground_query", "cell": [point.x, point.y], "result": result}
		max_work = maxi(max_work, int(result.get("work_used", -1)))
		begin = Time.get_ticks_usec()
		var description: Dictionary = world.describe_object({"kind": "artifact", "id": id})
		describe_times.append(Time.get_ticks_usec() - begin)
		if not _description_is_original(description, id, point):
			return {"ok": false, "kind": "describe", "cell": [point.x, point.y], "description": description}
	return {"ok": true, "samples": QUERY_SAMPLES, "ground_query_ms": _percentiles(ground_times),
		"describe_ms": _percentiles(describe_times), "budget": QUERY_BUDGET, "max_work": max_work}


func _move_roundtrip(world: RegionalSimulation, index: int, side: int) -> Dictionary:
	var id: String = _object_id(index)
	var point: Vector2i = _point(index, side)
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var old_slot: String = str(world.artifacts.objects[id].container)
	var before_count: int = world.artifacts.objects.size()
	var begin: int = Time.get_ticks_usec()
	var held: Dictionary = lifecycle.execute({"command": "bench_hold", "op": "move", "id": id,
		"from": {"region": "home", "container": old_slot}, "to": {"region": "home", "container": "actor:player"}})
	var hold_ms: float = _elapsed_ms(begin)
	if not bool(held.get("ok", false)):
		return {"ok": false, "stage": "hold", "result": held}
	var vacancy: Dictionary = lifecycle.ground.query(Rect2i(point, Vector2i.ONE), QUERY_BUDGET)
	if not bool(vacancy.get("ok", false)) or vacancy.get("ids") != [] or str(world.artifacts.objects[id].container) != "actor:player":
		return {"ok": false, "stage": "old_cell_or_carrier", "query": vacancy}
	begin = Time.get_ticks_usec()
	var dropped: Dictionary = lifecycle.execute({"command": "bench_drop", "op": "move", "id": id,
		"from": {"region": "home", "container": "actor:player"}, "to": {"region": "home", "cell": [point.x, point.y]}})
	var drop_ms: float = _elapsed_ms(begin)
	if not bool(dropped.get("ok", false)):
		return {"ok": false, "stage": "drop", "result": dropped, "note": "A dense full-capacity registry can reject a replacement historical slot."}
	var final_query: Dictionary = lifecycle.ground.query(Rect2i(point, Vector2i.ONE), QUERY_BUDGET)
	if not bool(final_query.get("ok", false)) or final_query.get("ids") != ["ground:bench_drop"] or world.artifacts.objects.size() != before_count:
		return {"ok": false, "stage": "roundtrip_identity", "query": final_query}
	return {"ok": true, "object_id": id, "cell": [point.x, point.y], "hold_ms": hold_ms, "drop_ms": drop_ms,
		"scope": "one existing artifact; same source cell after release"}


func _sample_integrity(world: RegionalSimulation, candidate: RegionalSimulation, cells: PackedInt32Array, side: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	var begin: int = Time.get_ticks_usec()
	for _i: int in INTEGRITY_SAMPLES:
		var index: int = cells[rng.randi_range(0, cells.size() - 1)]
		var id: String = _object_id(index)
		var point: Vector2i = _point(index, side)
		var ref: Dictionary = {"kind": "artifact", "id": id}
		var original: Dictionary = world.describe_object(ref)
		if not _description_is_original(original, id, point):
			return {"ok": false, "kind": "original", "id": id, "description": original}
		if candidate != null:
			var restored: Dictionary = candidate.describe_object(ref)
			if not _description_is_original(restored, id, point) or restored != original or candidate.artifacts.objects[id] != world.artifacts.objects[id]:
				return {"ok": false, "kind": "restored_mismatch", "id": id, "original": original, "restored": restored}
	return {"ok": true, "samples": INTEGRITY_SAMPLES, "sampling": "seeded with replacement", "ms": _elapsed_ms(begin),
		"compared_restored_world": candidate != null}


func _save_load(world: RegionalSimulation, cells: PackedInt32Array, side: int, initial_objects: int) -> Dictionary:
	var begin: int = Time.get_ticks_usec()
	var snapshot: Dictionary = world.to_dict()
	var snapshot_ms: float = _elapsed_ms(begin)
	begin = Time.get_ticks_usec()
	var encoded: String = JSON.stringify(snapshot, "", true, true)
	var json_ms: float = _elapsed_ms(begin)
	var encoded_length: int = encoded.length()
	# The normal file boundary does not keep an earlier serialization tree alive
	# while parsing/loading. Retain the live original world for atomic swap tests.
	snapshot.clear()
	begin = Time.get_ticks_usec()
	var parsed: Variant = JSON.parse_string(encoded)
	var parse_ms: float = _elapsed_ms(begin)
	encoded = ""
	if not parsed is Dictionary:
		return {"ok": false, "stage": "json_parse"}
	var content := ReolContentDB.new()
	if not content.load_bundle(world._content.content_bundle()):
		return {"ok": false, "stage": "content_bundle", "errors": content.errors}
	var map := FlatMap.new()
	if not map.configure_nature(content.natural_environment):
		return {"ok": false, "stage": "candidate_map"}
	var assembly: Dictionary = ReolWorldAssemblyInputs.from_world(world, {"home": [100, 100], "river": [150, 100]})
	if assembly.is_empty():
		return {"ok": false, "stage": "assembly"}
	begin = Time.get_ticks_usec()
	var candidate: RegionalSimulation = WorldRestoreFactory.restore(content, parsed, assembly, map)
	var restore_ms: float = _elapsed_ms(begin)
	if candidate == null:
		return {"ok": false, "stage": "factory_restore", "restore_ms": restore_ms}
	if candidate == world or candidate.artifacts == world.artifacts or candidate.map_data == world.map_data:
		return {"ok": false, "stage": "not_independent"}
	if candidate.artifacts.objects.size() != initial_objects + cells.size() or candidate.object_lifecycle.created.size() != cells.size() or int(candidate.object_lifecycle.ground.stats().active) != cells.size():
		return {"ok": false, "stage": "restored_count_mismatch", "artifacts": candidate.artifacts.objects.size(),
			"created": candidate.object_lifecycle.created.size(), "ground": candidate.object_lifecycle.ground.stats()}
	var integrity: Dictionary = _sample_integrity(world, candidate, cells, side)
	if not bool(integrity.get("ok", false)):
		return {"ok": false, "stage": "restored_integrity", "detail": integrity}
	return {"ok": true, "measured": true, "snapshot_ms": snapshot_ms, "json_ms": json_ms, "json_parse_ms": parse_ms,
		"factory_restore_ms": restore_ms, "json_characters": encoded_length, "integrity": integrity,
		"scope": "JSON in memory, independent content/map and WorldRestoreFactory in same process; no disk or process restart"}


func _simulate(world: RegionalSimulation) -> Dictionary:
	var samples: Array[int] = []
	var initial_count: int = world.artifacts.objects.size()
	var yields: int = 0
	var started_ms: int = world.elapsed_ms
	for _slice: int in 120:
		var target: int = world.elapsed_ms + 500
		var started: int = Time.get_ticks_usec()
		var calls: int = 0
		while not world.advance_to_ms(target, 64):
			yields += 1
			calls += 1
			if calls > 64 or not world.errors.is_empty() or world.target_ms != target:
				return {"ok": false, "reason": "unsettled_time", "errors": world.errors, "elapsed_ms": world.elapsed_ms, "target_ms": world.target_ms}
		samples.append(Time.get_ticks_usec() - started)
	if world.artifacts.objects.size() != initial_count or world.elapsed_ms != started_ms + 60000 or world.target_ms != world.elapsed_ms:
		return {"ok": false, "reason": "changed_static_count_or_lost_time"}
	return {"ok": true, "span_ms": 60000, "slices": 120, "slice_ms": 500, "slice_work_ms": _percentiles(samples), "budget_yields": yields,
		"scope": "all existing world domains, 12 nonautonomous human fixture records, dense static artifacts; no rendering or general NPC AI"}


func _description_is_original(description: Dictionary, id: String, point: Vector2i) -> bool:
	var spatial: Variant = description.get("spatial")
	return bool(description.get("ok", false)) and description.get("reference") == {"kind": "artifact", "id": id} \
		and spatial is Dictionary and spatial.get("cells") == [point] and spatial.get("relation") == "placed" \
		and description.get("attributes", {}).get("definition_id") == "plain_slate"


func _point(index: int, side: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(index % side, index / side)


func _object_id(index: int) -> String:
	return "bench_slate_%d" % index


func _spawn_command(index: int) -> String:
	return "bench_spawn_%d" % index


func _elapsed_ms(start_usec: int) -> float:
	return float(Time.get_ticks_usec() - start_usec) / 1000.0


func _percentiles(costs: Array[int]) -> Dictionary:
	costs.sort()
	return {"p50": _percentile_ms(costs, 0.50), "p95": _percentile_ms(costs, 0.95),
		"p99": _percentile_ms(costs, 0.99), "max": float(costs.back()) / 1000.0}


func _percentile_ms(sorted: Array[int], percentile: float) -> float:
	var index: int = clampi(int(ceil(float(sorted.size()) * percentile)) - 1, 0, sorted.size() - 1)
	return float(sorted[index]) / 1000.0


func _fail(reason: String, detail: Dictionary = {}) -> void:
	_report["ok"] = false
	_report["first_failure"] = {"reason": reason, "detail": detail}
	print(JSON.stringify(_report, "", true, true))
	quit(1)
