extends SceneTree
## Two separate Godot processes, using the ordinary Main and session save/load.
## Example (run under an external resource/time guard):
## godot --headless --path . --script res://tests/benchmarks/object_lifecycle_restart.gd -- --phase write --file logs/restart_sample.json
## godot --headless --path . --script res://tests/benchmarks/object_lifecycle_restart.gd -- --phase read --file logs/restart_sample.json
## Write refuses existing outputs. The companion .expected.json records the
## exact checkpoint and independently continued writer state; no rendering claim.

var _clock: ReolGameClock
var _snapshots: GDScript

const ITEM_ID: String = "restart_physical_item"
const SPAWN_COMMAND: String = "restart_spawn"
const DROP_COMMAND: String = "restart_drop"
const ACTION_COMMAND: String = "restart_pickup"
const GROUND_CONTAINER: String = "ground:restart_drop"
const RESERVATION: String = "object_lifecycle:restart_pickup"
const DURATION_MS: int = 4000
const CHECKPOINT_STEP_MS: int = 1000
const MATERIAL: String = "wood"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_clock = root.get_node("GameClock") as ReolGameClock
	_snapshots = load("res://scripts/runtime/world_session_snapshot.gd")
	var options: Dictionary = _arguments(OS.get_cmdline_user_args())
	if not bool(options.get("ok", false)):
		_fail("arguments", options)
		return
	var path: String = options.path
	if options.phase == "write":
		for suffix: String in ["", ".tmp", ".bak", ".bak.tmp", ".expected.json", ".expected.json.tmp", ".expected.json.bak", ".expected.json.bak.tmp"]:
			if FileAccess.file_exists(path + suffix):
				_fail("output_exists", {"path": path + suffix})
				return
	if not _clock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true}):
		_fail("clock_initialization")
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var runtime: Node = main._continuity
	if runtime == null or runtime.world_sim == null:
		main.free()
		_fail("main_initialization")
		return
	var result: Dictionary = _write(runtime, path) if options.phase == "write" else _read(runtime, path)
	main.free()
	if not bool(result.get("ok", false)):
		_fail(str(result.get("reason", "unknown")), result)
		return
	result["phase"] = options.phase
	result["pid"] = OS.get_process_id()
	result["engine"] = Engine.get_version_info().string
	result["scope"] = "headless ordinary Main; one item, one material transfer and one timed action; not rendered FPS or large-world capacity"
	print(JSON.stringify(result, "", true, true))
	quit(0)


func _write(runtime: Node, path: String) -> Dictionary:
	var world: RegionalSimulation = runtime.world_sim
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	if lifecycle == null or world.map_data == null or world.elapsed_ms != _clock.elapsed_ms:
		return _failure("missing_world_or_clock")
	var inventory: SimInventory = world.regions.home.inventory
	if inventory.available("store", MATERIAL) < 3:
		return _failure("insufficient_opening_material")
	var total: int = _total(inventory, MATERIAL)
	var original_store: int = inventory.quantity("store", MATERIAL)
	var original_actor: int = inventory.quantity("actor:player", MATERIAL)
	var count: int = world.artifacts.objects.size()
	var center: Vector2i = SimRouteTravel.cell(world.regions.home.actors.player.cell)
	var first: Vector2i = _find_cell(lifecycle, center)
	if first.x < 0:
		return _failure("no_item_cell")
	var spawn: Dictionary = {"command": SPAWN_COMMAND, "op": "spawn", "id": ITEM_ID, "definition": "plain_slate", "to": _ground(first)}
	var spawned: Dictionary = lifecycle.execute(spawn)
	if not bool(spawned.get("ok", false)):
		return _failure("spawn", spawned)
	var second: Vector2i = _find_cell(lifecycle, center)
	if second.x < 0:
		return _failure("no_material_cell")
	var drop: Dictionary = {"command": DROP_COMMAND, "op": "stock_transfer", "from": _location("store"), "to": _ground(second), "item": MATERIAL, "amount": 3}
	var dropped: Dictionary = lifecycle.execute(drop)
	if not bool(dropped.get("ok", false)) or dropped.get("to") != _location(GROUND_CONTAINER):
		return _failure("drop", dropped)
	if inventory.quantity("store", MATERIAL) != original_store - 3 or _total(inventory, MATERIAL) != total:
		return _failure("drop_conservation")
	var request: Dictionary = _action_request()
	var scheduled: Dictionary = lifecycle.schedule(request, "player", DURATION_MS)
	if not bool(scheduled.get("ok", false)):
		return _failure("schedule", scheduled)
	var due: int = int(scheduled.action.due_ms)
	if not _advance(world, CHECKPOINT_STEP_MS):
		return _failure("checkpoint_clock")
	var expected: Dictionary = {"version": 1, "writer_pid": OS.get_process_id(), "due_ms": due,
		"checkpoint_ms": world.elapsed_ms, "item_cell": [first.x, first.y], "material_cell": [second.x, second.y],
		"initial_objects": count, "wood_total": total, "initial_store": original_store, "initial_actor": original_actor,
		"checkpoint_store": inventory.quantity("store", MATERIAL)}
	var preflight: Dictionary = _checkpoint(world, expected)
	if not bool(preflight.ok):
		return preflight
	var checkpoint: Dictionary = _snapshots.capture(runtime)
	var saved: Error = runtime.save_game(path)
	if saved != OK:
		return _failure("write_save", {"error": int(saved)})
	var loaded: Dictionary = SimSaveStore.load_file(path)
	if not bool(loaded.get("ok", false)) or _hash(loaded.data) != _hash(checkpoint):
		return _failure("checkpoint_disk_mismatch")
	expected["checkpoint_hash"] = _hash(checkpoint)
	expected["save_sha256"] = FileAccess.get_sha256(path)
	var finished: Dictionary = _continue(runtime, expected)
	if not bool(finished.ok):
		return finished
	expected["continued_hash"] = _hash(_snapshots.capture(runtime))
	var meta_error: Error = SimSaveStore.save_file(path + ".expected.json", expected)
	if meta_error != OK:
		return _failure("write_expectation", {"error": int(meta_error)})
	return {"ok": true, "checkpoint_ms": expected.checkpoint_ms, "due_ms": due,
		"checkpoint_hash": expected.checkpoint_hash, "continued_hash": expected.continued_hash,
		"save_sha256": expected.save_sha256, "material_total": total, "material_ground_after": 1, "material_delivered": 2}


func _read(runtime: Node, path: String) -> Dictionary:
	var metadata: Dictionary = SimSaveStore.load_file(path + ".expected.json")
	if not bool(metadata.get("ok", false)):
		return _failure("read_expectation", metadata)
	var expected: Dictionary = metadata.data
	if expected.get("version") != 1 or not ReolGameClock._integer(expected.get("writer_pid")) or int(expected.writer_pid) == OS.get_process_id() or not expected.get("save_sha256") is String or not expected.get("checkpoint_hash") is String or not expected.get("continued_hash") is String:
		return _failure("invalid_expectation_or_same_process")
	if FileAccess.get_sha256(path) != expected.save_sha256:
		return _failure("save_digest_mismatch")
	var loaded: Dictionary = SimSaveStore.load_file(path)
	if not bool(loaded.get("ok", false)) or _hash(loaded.data) != expected.checkpoint_hash:
		return _failure("checkpoint_hash_mismatch")
	var before: RegionalSimulation = runtime.world_sim
	var staged: Dictionary = _snapshots.stage(runtime, loaded.data)
	if staged.is_empty() or runtime.world_sim != before or staged.world == before:
		return _failure("candidate_stage")
	if runtime.load_game(path) != OK or runtime.world_sim == before:
		return _failure("ordinary_load")
	var world: RegionalSimulation = runtime.world_sim
	if _hash(_snapshots.capture(runtime)) != expected.checkpoint_hash:
		return _failure("restored_checkpoint_mismatch")
	var checked: Dictionary = _checkpoint(world, expected)
	if not bool(checked.ok):
		return checked
	var finished: Dictionary = _continue(runtime, expected)
	if not bool(finished.ok):
		return finished
	var continued_hash: String = _hash(_snapshots.capture(runtime))
	if continued_hash != expected.continued_hash:
		return _failure("continued_world_mismatch", {"actual": continued_hash, "expected": expected.continued_hash})
	return {"ok": true, "writer_pid": int(expected.writer_pid), "checkpoint_ms": expected.checkpoint_ms,
		"due_ms": expected.due_ms, "checkpoint_hash": expected.checkpoint_hash, "continued_hash": continued_hash,
		"save_sha256": expected.save_sha256, "material_total": expected.wood_total, "material_ground_after": 1, "material_delivered": 2}


func _checkpoint(world: RegionalSimulation, expected: Dictionary) -> Dictionary:
	if world.elapsed_ms != int(expected.checkpoint_ms) or _clock.elapsed_ms != world.elapsed_ms or world.target_ms != world.elapsed_ms:
		return _failure("checkpoint_time")
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var inventory: SimInventory = world.regions.home.inventory
	var action: Variant = lifecycle.actions.get(ACTION_COMMAND)
	if not action is Dictionary or action.status != "active" or int(action.due_ms) != int(expected.due_ms) or action.reservation != RESERVATION or not lifecycle.owns_actor("player"):
		return _failure("checkpoint_action")
	var reservation: Variant = inventory.reservations.get(RESERVATION)
	if not reservation is Dictionary or reservation.container != GROUND_CONTAINER or reservation.item != MATERIAL or int(reservation.amount) != 2 or reservation.owner_id != "player":
		return _failure("checkpoint_reservation")
	if inventory.quantity(GROUND_CONTAINER, MATERIAL) != 3 or inventory.available(GROUND_CONTAINER, MATERIAL) != 1 or inventory.quantity("store", MATERIAL) != int(expected.checkpoint_store) or inventory.quantity("actor:player", MATERIAL) != int(expected.initial_actor) or _total(inventory, MATERIAL) != int(expected.wood_total):
		return _failure("checkpoint_quantity", {"ground":inventory.quantity(GROUND_CONTAINER,MATERIAL),"available":inventory.available(GROUND_CONTAINER,MATERIAL),"store":inventory.quantity("store",MATERIAL),"actor":inventory.quantity("actor:player",MATERIAL),"total":_total(inventory,MATERIAL),"expected":expected})
	return _physical(world, expected)


func _continue(runtime: Node, expected: Dictionary) -> Dictionary:
	var world: RegionalSimulation = runtime.world_sim
	var left: int = int(expected.due_ms) - _clock.elapsed_ms
	if left <= 0 or not _advance(world, left):
		return _failure("deadline_clock")
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var inventory: SimInventory = world.regions.home.inventory
	var action: Variant = lifecycle.actions.get(ACTION_COMMAND)
	if not action is Dictionary or action.status != "completed" or int(action.finished_ms) != int(expected.due_ms) or lifecycle.owns_actor("player") or inventory.reservations.has(RESERVATION):
		return _failure("terminal_action")
	if not lifecycle.receipts.has(ACTION_COMMAND) or not inventory.operations.has(RESERVATION) or inventory.quantity(GROUND_CONTAINER, MATERIAL) != 1 or inventory.quantity("actor:player", MATERIAL) != int(expected.initial_actor) + 2 or _total(inventory, MATERIAL) != int(expected.wood_total):
		return _failure("terminal_quantity_or_receipt")
	var receipt_count: int = lifecycle.receipts.size()
	var retry: Dictionary = lifecycle.schedule(_action_request(), "player", DURATION_MS)
	if not bool(retry.get("ok", false)) or retry.get("action", {}).get("status") != "completed" or lifecycle.receipts.size() != receipt_count:
		return _failure("retry", retry)
	if not _advance(world, 1) or inventory.quantity(GROUND_CONTAINER, MATERIAL) != 1 or inventory.quantity("actor:player", MATERIAL) != int(expected.initial_actor) + 2 or _total(inventory, MATERIAL) != int(expected.wood_total) or lifecycle.receipts.size() != receipt_count:
		return _failure("duplicate_settlement")
	return _physical(world, expected)


func _physical(world: RegionalSimulation, expected: Dictionary) -> Dictionary:
	if world.artifacts.objects.size() != int(expected.initial_objects) + 1 or not world.artifacts.objects.has(ITEM_ID):
		return _failure("physical_identity")
	var item: Dictionary = world.artifacts.objects[ITEM_ID]
	var cell: Array = expected.item_cell
	if item.definition != "plain_slate" or item.region != "home" or item.container != "ground:" + SPAWN_COMMAND or world.artifacts.object_cell(ITEM_ID) != Vector2i(int(cell[0]), int(cell[1])):
		return _failure("physical_location")
	var material_cell: Array = expected.material_cell
	var slot: Dictionary = world.object_lifecycle.ground.locate("home", GROUND_CONTAINER)
	if not bool(slot.get("ok", false)) or not bool(slot.get("active", false)) or slot.get("cell") != Vector2i(int(material_cell[0]), int(material_cell[1])):
		return _failure("material_location", slot)
	return {"ok": true}


func _advance(world: RegionalSimulation, amount: int) -> bool:
	var target: int = _clock.elapsed_ms + amount
	_clock.advance_msec(amount)
	return _clock.elapsed_ms == target and world.elapsed_ms == target and world.target_ms == target and not _clock.has_pending_advance()


func _find_cell(lifecycle: SimObjectLifecycle, center: Vector2i) -> Vector2i:
	for radius: int in range(1, 33):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var cell: Vector2i = center + Vector2i(x, y)
				if bool(lifecycle.ground.can_place("home", cell).get("ok", false)):
					return cell
	return Vector2i(-1, -1)


func _total(inventory: SimInventory, item: String) -> int:
	var result: int = 0
	for container: String in inventory.containers:
		result += inventory.quantity(container, item)
	return result


func _action_request() -> Dictionary:
	return {"command": ACTION_COMMAND, "op": "stock_transfer", "from": _location(GROUND_CONTAINER), "to": _location("actor:player"), "item": MATERIAL, "amount": 2}


func _ground(cell: Vector2i) -> Dictionary:
	return {"region": "home", "cell": [cell.x, cell.y]}


func _location(container: String) -> Dictionary:
	return {"region": "home", "container": container}


func _hash(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value)).sha256_text()


func _arguments(args: PackedStringArray) -> Dictionary:
	var phase: String = ""
	var raw_path: String = ""
	var i: int = 0
	while i < args.size():
		if args[i] == "--phase" and phase.is_empty() and i + 1 < args.size():
			phase = args[i + 1]
			i += 2
		elif args[i] == "--file" and raw_path.is_empty() and i + 1 < args.size():
			raw_path = args[i + 1]
			i += 2
		else:
			return _failure("unknown_or_duplicate_argument")
	if phase not in ["write", "read"] or raw_path.is_empty():
		return _failure("expected_phase_and_file")
	var path: String = ProjectSettings.globalize_path(raw_path) if raw_path.begins_with("res://") else raw_path
	if path.begins_with("logs/"):
		path = ProjectSettings.globalize_path("res://" + path)
	if not path.is_absolute_path():
		return _failure("expected_absolute_or_logs_path")
	path = path.simplify_path().replace("\\", "/")
	var root_path: String = ProjectSettings.globalize_path("res://logs").simplify_path().replace("\\", "/")
	if not path.to_lower().begins_with(root_path.to_lower() + "/") or not path.to_lower().ends_with(".json"):
		return _failure("path_must_be_json_inside_project_logs")
	return {"ok": true, "phase": phase, "path": path}


func _failure(reason: String, detail: Dictionary = {}) -> Dictionary:
	return {"ok": false, "reason": reason, "detail": detail}


func _fail(reason: String, detail: Dictionary = {}) -> void:
	print(JSON.stringify({"ok": false, "reason": reason, "detail": detail}, "", true, true))
	quit(1)
