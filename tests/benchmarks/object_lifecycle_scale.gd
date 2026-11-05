extends SceneTree
## Dense real artifacts in a two-region test world, not synthetic references.
## Run under an external resource guard. Example:
## godot --headless --path . --script res://tests/benchmarks/object_lifecycle_scale.gd -- --side 64 --save-load
## --disk-file requires a new JSON file in a new immediate parent directory.
## This is an offline simulation benchmark. It measures no frames, GPU or RSS.

const Fixture = preload("res://tests/sim/test_regional_simulation.gd")
const SIDES: Array[int] = [64, 128, 256, 512]
const SEED: int = 6162026
const QUERY_SAMPLES: int = 256
const INTEGRITY_SAMPLES: int = 1000
const BOUNDARY_CALLS: int = 100
const QUERY_BUDGET: int = 1024
const BATCH_ITEMS: int = 256
const STOCK_AMOUNTS: Dictionary = {"wood": 1, "grain": 4, "water": 16, "herb": 10000}

var _fixture := Fixture.new()
var _fixture_failures: Array[String] = []
var _report: Dictionary = {
	"benchmark": "object_lifecycle_scale",
	"ok": false,
	"scope": "two-region fixture, flat 512-square map, real lifecycle artifacts",
	"limits": "No rendering, FPS, GPU, process RSS, separate-process restart or normal-game capacity claim; all generated artifacts use one definition and one accounting region. Disk I/O is measured only when explicitly requested.",
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
	var disk_file: String = str(options.disk_file)
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
	_report["requested_disk_file"] = disk_file
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
	var stock_fixture: Dictionary = _seed_stock_fixture(world)
	if not bool(stock_fixture.get("ok", false)):
		_fail("stock_fixture_failed", stock_fixture)
		return
	_report["stock_fixture"] = stock_fixture
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
	var batch: Dictionary = _batch_roundtrip(world, cells, side)
	if not bool(batch.get("ok", false)):
		_fail("batch_roundtrip_failed", batch)
		return
	_report["batch_roundtrip"] = batch
	if world.artifacts.objects.size() != initial_objects + cells.size() or int(lifecycle.ground.stats().active) != cells.size():
		_fail("batch_duplicated_or_lost_object")
		return
	var mixed: Dictionary = _mixed_stock_measure(world, cells[0], side)
	if not bool(mixed.get("ok", false)):
		_fail("mixed_stock_failed", mixed)
		return
	_report["mixed_stock"] = mixed
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
	if not disk_file.is_empty():
		var disk_saved: Dictionary = _save_load(world, cells, side, initial_objects, disk_file)
		if not bool(disk_saved.get("ok", false)):
			_fail("disk_save_load_failed", disk_saved)
			return
		_report["disk_save_load"] = disk_saved
	else:
		_report["disk_save_load"] = {"measured": false}
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
	var disk_file: String = ""
	var disk_seen: bool = false
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
		elif args[i] == "--disk-file":
			if disk_seen or i + 1 >= args.size() or args[i + 1].begins_with("--"):
				return {"ok": false, "reason": "--disk-file requires one new JSON path"}
			var checked: Dictionary = _disk_path(args[i + 1])
			if not bool(checked.get("ok", false)):
				return checked
			disk_file = str(checked.path)
			disk_seen = true
			i += 2
		else:
			return {"ok": false, "reason": "unknown or repeated argument", "argument": args[i]}
	if side not in SIDES:
		return {"ok": false, "reason": "unsupported side", "side": side}
	return {"ok": true, "side": side, "save_load": save_load, "disk_file": disk_file}


func _disk_path(raw: String) -> Dictionary:
	var path: String = raw.replace("\\", "/")
	if path.is_empty() or path != path.strip_edges() or not (path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path()):
		return {"ok": false, "reason": "disk path must be an absolute, res:// or user:// path"}
	for segment: String in path.split("/", false):
		if segment == "." or segment == "..":
			return {"ok": false, "reason": "disk path cannot contain dot segments"}
	var filename: String = path.get_file()
	if not filename.is_valid_filename() or not filename.ends_with(".json"):
		return {"ok": false, "reason": "disk path requires a valid .json filename"}
	var absolute: String = ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path()
	var parent: String = absolute.get_base_dir()
	var grandparent: String = parent.get_base_dir()
	if parent == grandparent or not DirAccess.dir_exists_absolute(grandparent):
		return {"ok": false, "reason": "disk path requires an existing grandparent directory"}
	if FileAccess.file_exists(absolute) or DirAccess.dir_exists_absolute(absolute) or FileAccess.file_exists(parent) or DirAccess.dir_exists_absolute(parent):
		return {"ok": false, "reason": "disk file and its immediate parent must not exist", "path": absolute}
	return {"ok": true, "path": absolute}


func _seed_stock_fixture(world: RegionalSimulation) -> Dictionary:
	# This is benchmark opening data, not a player-facing source of materials.
	# Replace only the fixture's empty player container using the real ledger API.
	var inventory: SimInventory = world.regions.home.inventory
	var bag: String = "actor:player"
	var existing: Variant = inventory.containers.get(bag)
	if not existing is Dictionary or not existing.is_empty():
		return {"ok": false, "reason": "fixture_player_container_not_empty"}
	for note: Dictionary in inventory.reservations.values():
		if note.get("container") == bag:
			return {"ok": false, "reason": "fixture_player_container_reserved"}
	for note: Dictionary in inventory.custody.values():
		if note.get("container") == bag:
			return {"ok": false, "reason": "fixture_player_container_entrusted"}
	for operation: Dictionary in inventory.operations.values():
		if operation.get("source") == bag or operation.get("target") == bag or operation.get("container") == bag:
			return {"ok": false, "reason": "fixture_player_container_has_history"}
	inventory.containers.erase(bag)
	if not inventory.create_container(bag, STOCK_AMOUNTS):
		inventory.containers[bag] = existing
		return {"ok": false, "reason": "fixture_opening_create_failed"}
	world.invalidate_region("home")
	return {"ok": true, "container": bag, "quantities": STOCK_AMOUNTS.duplicate(),
		"supply": "fixture-only replacement of an empty opening container through SimInventory.create_container; not a player creation permission"}


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


func _batch_roundtrip(world: RegionalSimulation, cells: PackedInt32Array, side: int) -> Dictionary:
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var count: int = mini(BATCH_ITEMS, cells.size())
	var before_objects: int = world.artifacts.objects.size()
	var before_active: int = int(lifecycle.ground.stats().active)
	var store_items: Dictionary = world.regions.home.inventory.containers.store.duplicate(true)
	var entries: Array[Dictionary] = []
	var hold_times: Array[int] = []
	var drop_times: Array[int] = []
	var total_start: int = Time.get_ticks_usec()
	var hold_start: int = total_start
	for i: int in count:
		@warning_ignore("integer_division")
		var index: int = cells[i * cells.size() / count]
		var id: String = _object_id(index)
		var point: Vector2i = _point(index, side)
		var old_slot: String = str(world.artifacts.objects[id].container)
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = lifecycle.execute({"command": "bench_batch_hold_%d" % i, "op": "move", "id": id,
			"from": {"region": "home", "container": old_slot}, "to": {"region": "home", "container": "store"}})
		hold_times.append(Time.get_ticks_usec() - started)
		if not bool(result.get("ok", false)):
			return {"ok": false, "stage": "hold", "index": i, "id": id, "result": result}
		var vacancy: Dictionary = lifecycle.ground.query(Rect2i(point, Vector2i.ONE), QUERY_BUDGET)
		if not bool(vacancy.get("ok", false)) or not bool(vacancy.get("complete", false)) or vacancy.get("ids") != [] \
			or str(world.artifacts.objects[id].container) != "store":
			return {"ok": false, "stage": "held_location", "index": i, "id": id, "query": vacancy}
		entries.append({"id": id, "cell": point})
	var hold_total_ms: float = _elapsed_ms(hold_start)
	if world.artifacts.objects.size() != before_objects or int(lifecycle.ground.stats().active) != before_active - count \
		or world.regions.home.inventory.containers.store != store_items:
		return {"ok": false, "stage": "held_counts", "ground": lifecycle.ground.stats()}
	var drop_start: int = Time.get_ticks_usec()
	for i: int in entries.size():
		var entry: Dictionary = entries[i]
		var point: Vector2i = entry.cell
		var command: String = "bench_batch_drop_%d" % i
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = lifecycle.execute({"command": command, "op": "move", "id": entry.id,
			"from": {"region": "home", "container": "store"}, "to": {"region": "home", "cell": [point.x, point.y]}})
		drop_times.append(Time.get_ticks_usec() - started)
		if not bool(result.get("ok", false)):
			return {"ok": false, "stage": "drop", "index": i, "id": entry.id, "result": result}
		var placed: Dictionary = lifecycle.ground.query(Rect2i(point, Vector2i.ONE), QUERY_BUDGET)
		var description: Dictionary = world.describe_object({"kind": "artifact", "id": entry.id})
		if not bool(placed.get("ok", false)) or not bool(placed.get("complete", false)) or placed.get("ids") != ["ground:" + command] \
			or not _description_is_original(description, entry.id, point):
			return {"ok": false, "stage": "returned_identity", "index": i, "id": entry.id, "query": placed}
	var drop_total_ms: float = _elapsed_ms(drop_start)
	if world.artifacts.objects.size() != before_objects or int(lifecycle.ground.stats().active) != before_active \
		or world.regions.home.inventory.containers.store != store_items:
		return {"ok": false, "stage": "returned_counts", "ground": lifecycle.ground.stats()}
	return {"ok": true, "objects": count, "selection": "evenly spaced in the generated cell list",
		"destination": "home/store", "return": "original cells", "hold_total_ms_including_checks": hold_total_ms,
		"drop_total_ms_including_checks": drop_total_ms, "total_ms_including_checks": _elapsed_ms(total_start),
		"hold_call_ms": _percentiles(hold_times), "drop_call_ms": _percentiles(drop_times),
		"artifact_count_before_after": before_objects, "active_ground_before_after": before_active,
		"scope": "256 real distinct artifacts moved in two batches; quantities in the store ledger remain unchanged"}


func _mixed_stock_measure(world: RegionalSimulation, artifact_index: int, side: int) -> Dictionary:
	var inventory: SimInventory = world.regions.home.inventory
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var bag: String = "actor:player"
	var references: Array = [
		{"kind": "actor", "id": "player"},
		{"kind": "resource", "region": "home", "id": "herb_slope"},
		{"kind": "artifact", "id": _object_id(artifact_index)},
	]
	for item: String in STOCK_AMOUNTS:
		references.append(_stock_reference(bag, item))
	var before: Dictionary = _mixed_projection(world, references)
	if not bool(before.get("ok", false)):
		return {"ok": false, "stage": "initial_projection", "detail": before}
	var results: Array[Dictionary] = []
	for item: String in STOCK_AMOUNTS:
		var amount: int = int(STOCK_AMOUNTS[item])
		var carried_before: int = inventory.quantity(bag, item)
		var store_before: int = inventory.quantity("store", item)
		var total_before: int = _stock_total(inventory, item)
		if carried_before != amount:
			return {"ok": false, "stage": "opening_quantity", "item": item, "actual": carried_before}
		var moved: int = maxi(1, floori(float(amount) / 2.0))
		var started: int = Time.get_ticks_usec()
		var outward: Dictionary = lifecycle.execute({"command": "bench_stock_out_" + item, "op": "stock_transfer",
			"from": {"region": "home", "container": bag}, "to": {"region": "home", "container": "store"},
			"item": item, "amount": moved})
		var outward_ms: float = _elapsed_ms(started)
		if not bool(outward.get("ok", false)) or inventory.quantity(bag, item) != amount - moved \
			or inventory.quantity("store", item) != store_before + moved or _stock_total(inventory, item) != total_before:
			return {"ok": false, "stage": "split_or_transfer", "item": item, "result": outward}
		started = Time.get_ticks_usec()
		var returned: Dictionary = lifecycle.execute({"command": "bench_stock_return_" + item, "op": "stock_transfer",
			"from": {"region": "home", "container": "store"}, "to": {"region": "home", "container": bag},
			"item": item, "amount": moved})
		var return_ms: float = _elapsed_ms(started)
		if not bool(returned.get("ok", false)) or inventory.quantity(bag, item) != amount \
			or inventory.quantity("store", item) != store_before or _stock_total(inventory, item) != total_before:
			return {"ok": false, "stage": "merge_or_return", "item": item, "result": returned}
		results.append({"item": item, "opening_quantity": amount, "moved_each_way": moved,
			"total_in_all_home_containers": total_before, "outward_ms": outward_ms, "return_ms": return_ms})
	var after: Dictionary = _mixed_projection(world, references)
	if not bool(after.get("ok", false)):
		return {"ok": false, "stage": "returned_projection", "detail": after}
	var artifact: Dictionary = world.describe_object({"kind": "artifact", "id": _object_id(artifact_index)})
	if not _description_is_original(artifact, _object_id(artifact_index), _point(artifact_index, side)):
		return {"ok": false, "stage": "artifact_identity_after_stock"}
	return {"ok": true, "cases": results, "before": before, "after": after,
		"reference_types": ["actor", "resource", "artifact", "stock"], "natural_source_count": 1,
		"scope": "real same-ledger containers and one natural-source reference; fixture-only opening supply, not environmental propagation or player creation"}


func _mixed_projection(world: RegionalSimulation, references: Array) -> Dictionary:
	var rows: Array[Dictionary] = []
	var query_start: int = Time.get_ticks_usec()
	for reference: Dictionary in references:
		var row: Dictionary = world.describe_object(reference)
		if not bool(row.get("ok", false)) or row.get("reference") != reference or bool(row.get("stale", true)):
			return {"ok": false, "reason": "describe", "reference": reference, "result": row}
		if reference.kind == "stock" and int(row.get("attributes", {}).get("quantity", -1)) != int(STOCK_AMOUNTS[reference.item]):
			return {"ok": false, "reason": "stock_quantity", "reference": reference, "result": row}
		rows.append(row)
	var describe_total_ms: float = _elapsed_ms(query_start)
	var capture_start: int = Time.get_ticks_usec()
	var captured: Dictionary = world.capture_object_space(references)
	var capture_ms: float = _elapsed_ms(capture_start)
	if not bool(captured.get("ok", false)) or captured.get("scope") != "captured_references" \
		or bool(captured.get("live", true)) or int(captured.get("object_count", -1)) != references.size():
		return {"ok": false, "reason": "capture", "result": captured}
	var snapshot: SimObjectSpatialSnapshot = captured.snapshot
	var lookup_start: int = Time.get_ticks_usec()
	for i: int in references.size():
		var cells: Array = rows[i].spatial.cells
		if cells.is_empty():
			return {"ok": false, "reason": "empty_geometry", "reference": references[i]}
		var point: Vector2i = cells[0]
		var found: Dictionary = snapshot.query(Rect2i(point, Vector2i.ONE), "", "", QUERY_BUDGET)
		if not bool(found.get("ok", false)) or not bool(found.get("complete", false)) or not found.get("references", []).has(references[i]):
			return {"ok": false, "reason": "captured_query", "reference": references[i], "result": found}
	return {"ok": true, "reference_count": references.size(), "describe_total_ms": describe_total_ms,
		"capture_ms": capture_ms, "captured_cell_queries_ms": _elapsed_ms(lookup_start),
		"scope": "explicit reference set at its captured time, not a global or live index"}


func _stock_reference(container: String, item: String) -> Dictionary:
	return {"kind": "stock", "domain": "village", "region": "home", "container": container, "item": item}


func _stock_total(inventory: SimInventory, item: String) -> int:
	var total: int = 0
	for container: String in inventory.containers:
		total += inventory.quantity(container, item)
	return total


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


func _save_load(world: RegionalSimulation, cells: PackedInt32Array, side: int, initial_objects: int, disk_file: String = "") -> Dictionary:
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
	var disk_details: Dictionary = {}
	if not disk_file.is_empty():
		var expected_hash: String = encoded.sha256_text()
		disk_details = _write_new_disk_file(disk_file, encoded)
		if not bool(disk_details.get("ok", false)):
			return disk_details
		encoded = ""
		var read_result: Dictionary = _read_disk_file(disk_file, int(disk_details.bytes), expected_hash)
		if not bool(read_result.get("ok", false)):
			return read_result
		encoded = str(read_result.text)
		read_result.erase("text")
		disk_details.merge(read_result, true)
	begin = Time.get_ticks_usec()
	var parsed: Variant = JSON.parse_string(encoded)
	var parse_ms: float = _elapsed_ms(begin)
	encoded = ""
	if not parsed is Dictionary:
		return {"ok": false, "stage": "json_parse"}
	var ground_data: Dictionary = {}
	if not disk_file.is_empty():
		if not parsed.get("object_lifecycle") is Dictionary or not parsed.object_lifecycle.get("ground") is Dictionary:
			return {"ok": false, "stage": "missing_ground_index_data"}
		ground_data = parsed.object_lifecycle.ground
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
	parsed = null
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
	for item: String in STOCK_AMOUNTS:
		var original_inventory: SimInventory = world.regions.home.inventory
		var restored_inventory: SimInventory = candidate.regions.home.inventory
		if original_inventory.quantity("actor:player", item) != restored_inventory.quantity("actor:player", item) \
			or original_inventory.quantity("store", item) != restored_inventory.quantity("store", item) \
			or _stock_total(original_inventory, item) != _stock_total(restored_inventory, item):
			return {"ok": false, "stage": "restored_stock", "item": item}
	var index_result: Dictionary = {"measured": false}
	if not disk_file.is_empty():
		index_result = _measure_rebuilt_ground(candidate, ground_data, cells, side)
		if not bool(index_result.get("ok", false)):
			return {"ok": false, "stage": "index_rebuild", "detail": index_result}
	ground_data.clear()
	candidate = null
	var result: Dictionary = {"ok": true, "measured": true, "snapshot_ms": snapshot_ms, "json_ms": json_ms, "json_parse_ms": parse_ms,
		"factory_restore_ms": restore_ms, "json_characters": encoded_length, "integrity": integrity,
		"scope": "JSON in memory, independent content/map and WorldRestoreFactory in same process; no disk or process restart"}
	if not disk_file.is_empty():
		result["disk"] = disk_details
		result["ground_index_rebuild"] = index_result
		result["scope"] = "new disk JSON, independent content/map and WorldRestoreFactory in the same process; not a process restart or Main save"
	return result


func _write_new_disk_file(path: String, encoded: String) -> Dictionary:
	# Claim a new immediate directory first. The destination cannot be an old
	# user file, and another invocation with the same directory is rejected.
	var checked: Dictionary = _disk_path(path)
	if not bool(checked.get("ok", false)):
		return {"ok": false, "stage": "disk_path", "detail": checked}
	var directory: String = path.get_base_dir()
	var made: Error = DirAccess.make_dir_absolute(directory)
	if made != OK:
		return {"ok": false, "stage": "claim_output_directory", "error": made, "path": directory}
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		return {"ok": false, "stage": "disk_target_exists", "path": path}
	var started: int = Time.get_ticks_usec()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "stage": "disk_open_write", "error": FileAccess.get_open_error(), "path": path}
	var stored: bool = file.store_string(encoded)
	file.flush()
	var error: Error = file.get_error()
	var bytes: int = file.get_length()
	file.close()
	var write_ms: float = _elapsed_ms(started)
	if not stored or error != OK or bytes <= 0:
		return {"ok": false, "stage": "disk_write", "error": error, "bytes": bytes, "path": path}
	return {"ok": true, "path": path, "bytes": bytes, "write_ms": write_ms,
		"scope": "one newly claimed directory and file; no overwrite or process restart"}


func _read_disk_file(path: String, expected_bytes: int, expected_hash: String) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "stage": "disk_open_read", "error": FileAccess.get_open_error(), "path": path}
	var bytes: int = file.get_length()
	var text: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	var read_ms: float = _elapsed_ms(started)
	started = Time.get_ticks_usec()
	var actual_hash: String = FileAccess.get_sha256(path)
	var verification_ms: float = _elapsed_ms(started)
	if (read_error != OK and read_error != ERR_FILE_EOF) or bytes != expected_bytes or actual_hash != expected_hash:
		return {"ok": false, "stage": "disk_content_mismatch", "bytes": bytes, "error": read_error}
	return {"ok": true, "text": text, "read_ms": read_ms, "content_verification_ms": verification_ms,
		"sha256": actual_hash}


func _measure_rebuilt_ground(candidate: RegionalSimulation, ground_data: Dictionary, cells: PackedInt32Array, side: int) -> Dictionary:
	var rebuilt := SimGroundPlacements.new()
	if not rebuilt.configure(candidate):
		return {"ok": false, "reason": "configure"}
	var started: int = Time.get_ticks_usec()
	if not rebuilt.restore(ground_data):
		return {"ok": false, "reason": "restore"}
	var rebuild_ms: float = _elapsed_ms(started)
	var actual: Dictionary = rebuilt.stats()
	var expected: Dictionary = candidate.object_lifecycle.ground.stats()
	for field: String in ["slots", "active", "inactive", "cells", "buckets", "reference_characters", "metadata_characters"]:
		if actual.get(field) != expected.get(field):
			return {"ok": false, "reason": "stats", "field": field, "actual": actual, "expected": expected}
	var samples: int = mini(100, cells.size())
	for i: int in samples:
		@warning_ignore("integer_division")
		var index: int = cells[i * cells.size() / samples]
		var point: Vector2i = _point(index, side)
		var found: Dictionary = rebuilt.query(Rect2i(point, Vector2i.ONE), QUERY_BUDGET)
		var expected_slot: String = str(candidate.artifacts.objects[_object_id(index)].container)
		if not bool(found.get("ok", false)) or not bool(found.get("complete", false)) or found.get("ids") != [expected_slot]:
			return {"ok": false, "reason": "sample_query", "index": index, "result": found}
	return {"ok": true, "measured": true, "restore_and_rebuild_ms": rebuild_ms, "samples": samples,
		"scope": "separate scratch ground index rebuilt from loaded slot data; factory restore already includes its own validation and index rebuild"}


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
