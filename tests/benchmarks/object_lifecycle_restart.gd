extends SceneTree
## Two separate Godot processes, using the ordinary Main and session save/load.
## Example (run under an external resource/time guard):
## godot --headless --path . --script res://tests/benchmarks/object_lifecycle_restart.gd -- --phase write --file logs/restart_sample.json
## godot --headless --path . --script res://tests/benchmarks/object_lifecycle_restart.gd -- --phase read --file logs/restart_sample.json
## Write refuses existing outputs. The companion .expected.json records the
## exact checkpoint, river observation, and independently continued writer state.
## This is one item and one small pile, not a large-item save or rendering test.

var _clock: ReolGameClock
var _snapshots: GDScript

const ITEM_ID: String = "restart_physical_item"
const SPAWN_COMMAND: String = "restart_spawn"
const CARRY_COMMAND: String = "restart_carry"
const RETURN_COMMAND: String = "restart_return"
const DROP_COMMAND: String = "restart_drop"
const ACTION_COMMAND: String = "restart_pickup"
const SPAWN_CONTAINER: String = "ground:restart_spawn"
const ITEM_CONTAINER: String = "ground:restart_return"
const GROUND_CONTAINER: String = "ground:restart_drop"
const RESERVATION: String = "object_lifecycle:restart_pickup"
const DURATION_MS: int = 4000
const CHECKPOINT_STEP_MS: int = 1000
const MATERIAL: String = "wood"
const MAX_TRIP_MINUTES: int = 250
const MINUTE_MS: int = 60000


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
	result["scope"] = "headless ordinary Main; one item, one small material pile, home-river-home travel and one timed action; not a large-item save, rendered FPS or large-world capacity test"
	print(JSON.stringify(result, "", true, true))
	quit(0)


func _write(runtime: Node, path: String) -> Dictionary:
	var world: RegionalSimulation = runtime.world_sim
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	if lifecycle == null or world.map_data == null or world.elapsed_ms != _clock.elapsed_ms:
		return _failure("missing_world_or_clock")
	var inventory: SimInventory = world.regions.home.inventory
	var home: VillageSimulation = world.regions.home
	if inventory.available("store", MATERIAL) < 3:
		return _failure("insufficient_opening_material")
	var total: int = _total(inventory, MATERIAL)
	var original_store: int = inventory.quantity("store", MATERIAL)
	var count: int = world.artifacts.objects.size()
	var center: Vector2i = SimRouteTravel.cell(world.regions.home.actors.player.cell)
	var first: Vector2i = _find_cell(lifecycle, center)
	if first.x < 0:
		return _failure("no_item_cell")
	var spawn: Dictionary = _spawn_request(first)
	var spawned: Dictionary = lifecycle.execute(spawn)
	if not bool(spawned.get("ok", false)) or spawned.get("reference") != _item_reference() or spawned.get("to") != _location(SPAWN_CONTAINER) or world.artifacts.objects.size() != count + 1:
		return _failure("spawn", spawned)
	var carried: Dictionary = lifecycle.execute(_carry_request())
	var old_slot: Dictionary = lifecycle.ground.locate("home", SPAWN_CONTAINER)
	var vacancy: Dictionary = lifecycle.ground.query(Rect2i(first, Vector2i.ONE))
	if not bool(carried.get("ok", false)) or carried.get("reference") != _item_reference() or carried.get("to") != _location("actor:player") or world.artifacts.objects[ITEM_ID].container != "actor:player" or world.artifacts.objects.size() != count + 1 or not bool(old_slot.get("ok", false)) or bool(old_slot.get("active", true)) or not bool(vacancy.get("ok", false)) or not vacancy.get("ids", []).is_empty():
		return _failure("carry_identity_or_old_ground", {"result": carried, "old_slot": old_slot, "vacancy": vacancy})
	var returned: Dictionary = lifecycle.execute(_return_request(first))
	if not bool(returned.get("ok", false)) or returned.get("reference") != _item_reference() or returned.get("to") != _location(ITEM_CONTAINER) or world.artifacts.objects.size() != count + 1:
		return _failure("return_item", returned)
	var second: Vector2i = _find_cell(lifecycle, center)
	if second.x < 0 or second == first:
		return _failure("no_material_cell")
	var drop: Dictionary = _drop_request(second)
	var dropped: Dictionary = lifecycle.execute(drop)
	if not bool(dropped.get("ok", false)) or dropped.get("to") != _location(GROUND_CONTAINER):
		return _failure("drop", dropped)
	if inventory.quantity("store", MATERIAL) != original_store - 3 or _total(inventory, MATERIAL) != total:
		return _failure("drop_conservation")
	var locations: Dictionary = {"item_cell": [first.x, first.y], "material_cell": [second.x, second.y], "item_container": ITEM_CONTAINER}
	var before_trip: Dictionary = _observe_trip(runtime, world, home, "home", locations)
	if not bool(before_trip.get("ok", false)):
		return before_trip
	var outward: Dictionary = _travel(runtime, world, "river")
	if not bool(outward.get("ok", false)):
		return outward
	var river: Dictionary = _observe_trip(runtime, world, home, "river", locations)
	if not bool(river.get("ok", false)):
		return river
	# Preserve the actual river checkpoint for the independent reader to stage.
	var river_snapshot: Dictionary = _snapshots.capture(runtime)
	var inward: Dictionary = _travel(runtime, world, "home")
	if not bool(inward.get("ok", false)):
		return inward
	var after_trip: Dictionary = _observe_trip(runtime, world, home, "home", locations)
	if not bool(after_trip.get("ok", false)):
		return after_trip
	var request: Dictionary = _action_request()
	var scheduled: Dictionary = lifecycle.schedule(request, "player", DURATION_MS)
	if not bool(scheduled.get("ok", false)):
		return _failure("schedule", scheduled)
	var due: int = int(scheduled.action.due_ms)
	if not _advance(world, CHECKPOINT_STEP_MS):
		return _failure("checkpoint_clock")
	# The rest of the world may have legitimately changed during travel. Use
	# quantities at the actual in-flight checkpoint as the continuation baseline.
	var expected: Dictionary = {"version": 2, "writer_pid": OS.get_process_id(), "due_ms": due,
		"checkpoint_ms": world.elapsed_ms, "item_cell": [first.x, first.y], "material_cell": [second.x, second.y],
		"item_container": ITEM_CONTAINER, "wood_total": _total(inventory, MATERIAL),
		"checkpoint_store": inventory.quantity("store", MATERIAL), "checkpoint_actor": inventory.quantity("actor:player", MATERIAL),
		"trip": {"before": before_trip, "river": river, "home": after_trip, "river_snapshot_hash": _hash(river_snapshot)},
		"river_snapshot": river_snapshot}
	var evidence: Dictionary = _check_trip(runtime, expected)
	if not bool(evidence.ok):
		return evidence
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
		"save_sha256": expected.save_sha256, "trip": expected.trip, "material_total": expected.wood_total, "material_ground_after": 1, "material_delivered": 2}


func _read(runtime: Node, path: String) -> Dictionary:
	var metadata: Dictionary = SimSaveStore.load_file(path + ".expected.json")
	if not bool(metadata.get("ok", false)):
		return _failure("read_expectation", metadata)
	var expected: Dictionary = metadata.data
	if expected.get("version") != 2 or not ReolGameClock._integer(expected.get("writer_pid")) or int(expected.writer_pid) == OS.get_process_id() or not expected.get("save_sha256") is String or not expected.get("checkpoint_hash") is String or not expected.get("continued_hash") is String:
		return _failure("invalid_expectation_or_same_process")
	if not _valid_expectation(expected):
		return _failure("invalid_trip_expectation")
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
	var evidence: Dictionary = _check_trip(runtime, expected)
	if not bool(evidence.ok):
		return evidence
	var checked: Dictionary = _checkpoint(world, expected)
	if not bool(checked.ok):
		return checked
	var river_checked: Dictionary = _check_river_snapshot(runtime, expected)
	if not bool(river_checked.ok):
		return river_checked
	var finished: Dictionary = _continue(runtime, expected)
	if not bool(finished.ok):
		return finished
	var continued_hash: String = _hash(_snapshots.capture(runtime))
	if continued_hash != expected.continued_hash:
		return _failure("continued_world_mismatch", {"actual": continued_hash, "expected": expected.continued_hash})
	return {"ok": true, "writer_pid": int(expected.writer_pid), "checkpoint_ms": expected.checkpoint_ms,
		"due_ms": expected.due_ms, "checkpoint_hash": expected.checkpoint_hash, "continued_hash": continued_hash,
		"save_sha256": expected.save_sha256, "trip": expected.trip, "material_total": expected.wood_total, "material_ground_after": 1, "material_delivered": 2}


func _checkpoint(world: RegionalSimulation, expected: Dictionary) -> Dictionary:
	if world.elapsed_ms != int(expected.checkpoint_ms) or _clock.elapsed_ms != world.elapsed_ms or world.target_ms != world.elapsed_ms or _clock.has_pending_advance():
		return _failure("checkpoint_time")
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var inventory: SimInventory = world.regions.home.inventory
	var action: Variant = lifecycle.actions.get(ACTION_COMMAND)
	if not action is Dictionary or action.status != "active" or action.actor != "player" or int(action.started_ms) != int(expected.trip.home.clock_ms) or int(action.due_ms) != int(expected.due_ms) or not lifecycle._same(action.request, _action_request()) or action.reservation != RESERVATION or not lifecycle.owns_actor("player"):
		return _failure("checkpoint_action")
	var reservation: Variant = inventory.reservations.get(RESERVATION)
	if not reservation is Dictionary or reservation.container != GROUND_CONTAINER or reservation.item != MATERIAL or int(reservation.amount) != 2 or reservation.owner_id != "player":
		return _failure("checkpoint_reservation")
	if inventory.quantity(GROUND_CONTAINER, MATERIAL) != 3 or inventory.available(GROUND_CONTAINER, MATERIAL) != 1 or inventory.quantity("store", MATERIAL) != int(expected.checkpoint_store) or inventory.quantity("actor:player", MATERIAL) != int(expected.checkpoint_actor) or _total(inventory, MATERIAL) != int(expected.wood_total):
		return _failure("checkpoint_quantity", {"ground": inventory.quantity(GROUND_CONTAINER, MATERIAL), "available": inventory.available(GROUND_CONTAINER, MATERIAL), "store": inventory.quantity("store", MATERIAL), "actor": inventory.quantity("actor:player", MATERIAL), "total": _total(inventory, MATERIAL), "expected_store": expected.checkpoint_store, "expected_actor": expected.checkpoint_actor, "expected_total": expected.wood_total})
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
	if not lifecycle.receipts.has(ACTION_COMMAND) or not inventory.operations.has(RESERVATION) or inventory.quantity(GROUND_CONTAINER, MATERIAL) != 1 or inventory.quantity("actor:player", MATERIAL) != int(expected.checkpoint_actor) + 2 or _total(inventory, MATERIAL) != int(expected.wood_total):
		return _failure("terminal_quantity_or_receipt")
	var receipt_count: int = lifecycle.receipts.size()
	var retry: Dictionary = lifecycle.schedule(_action_request(), "player", DURATION_MS)
	if not bool(retry.get("ok", false)) or retry.get("action", {}).get("status") != "completed" or lifecycle.receipts.size() != receipt_count:
		return _failure("retry", retry)
	if not _advance(world, 1) or inventory.quantity(GROUND_CONTAINER, MATERIAL) != 1 or inventory.quantity("actor:player", MATERIAL) != int(expected.checkpoint_actor) + 2 or _total(inventory, MATERIAL) != int(expected.wood_total) or lifecycle.receipts.size() != receipt_count:
		return _failure("duplicate_settlement")
	return _physical(world, expected)


func _physical(world: RegionalSimulation, expected: Dictionary) -> Dictionary:
	if not world.artifacts.objects.has(ITEM_ID) or world.object_lifecycle.created.get(ITEM_ID) != SPAWN_COMMAND:
		return _failure("physical_identity")
	var item: Dictionary = world.artifacts.objects[ITEM_ID]
	var cell: Array = expected.item_cell
	if item.definition != "plain_slate" or item.region != "home" or item.container != expected.item_container or world.artifacts.object_cell(ITEM_ID) != Vector2i(int(cell[0]), int(cell[1])):
		return _failure("physical_location")
	var item_slot: Dictionary = world.object_lifecycle.ground.locate("home", str(expected.item_container))
	var old_slot: Dictionary = world.object_lifecycle.ground.locate("home", SPAWN_CONTAINER)
	if not bool(item_slot.get("ok", false)) or not bool(item_slot.get("active", false)) or item_slot.get("cell") != Vector2i(int(cell[0]), int(cell[1])) or item_slot.get("reference") != _item_reference() or not bool(old_slot.get("ok", false)) or bool(old_slot.get("active", true)):
		return _failure("physical_ground_slots", {"item": item_slot, "old": old_slot})
	var material_cell: Array = expected.material_cell
	var slot: Dictionary = world.object_lifecycle.ground.locate("home", GROUND_CONTAINER)
	var reference: Dictionary = {"kind": "stock", "domain": "village", "region": "home", "container": GROUND_CONTAINER, "item": MATERIAL}
	if not bool(slot.get("ok", false)) or not bool(slot.get("active", false)) or slot.get("cell") != Vector2i(int(material_cell[0]), int(material_cell[1])) or slot.get("reference") != reference:
		return _failure("material_location", slot)
	return {"ok": true}


func _travel(runtime: Node, world: RegionalSimulation, destination: String) -> Dictionary:
	var start: int = _clock.elapsed_ms
	if runtime.world_sim != world or not runtime.travel_to(destination):
		return _failure("travel_rejected", {"destination": destination})
	for _minute: int in MAX_TRIP_MINUTES:
		if runtime.player_journey.is_empty():
			break
		var target: int = _clock.elapsed_ms + MINUTE_MS
		_clock.advance_ticks(1)
		if not _committed(world, target):
			return _failure("travel_clock", {"destination": destination, "target_ms": target, "world_ms": world.elapsed_ms, "world_target_ms": world.target_ms, "clock_ms": _clock.elapsed_ms})
	if runtime.world_sim != world or not runtime.player_journey.is_empty() or runtime.current_region != destination or world.active_region != destination or _clock.elapsed_ms <= start:
		return _failure("travel_incomplete", {"destination": destination, "current_region": runtime.current_region, "elapsed_ms": _clock.elapsed_ms - start})
	return {"ok": true}


func _observe_trip(runtime: Node, world: RegionalSimulation, home: VillageSimulation, region: String, locations: Dictionary) -> Dictionary:
	if runtime.world_sim != world or world.regions.home != home or runtime.current_region != region or world.active_region != region or not runtime.player_journey.is_empty() or not _committed(world, _clock.elapsed_ms):
		return _failure("trip_boundary", {"region": region})
	if not world.synchronize_region("home") or home.elapsed_ms != _clock.elapsed_ms:
		return _failure("trip_home_sync", {"region": region})
	var checked: Dictionary = _physical(world, locations)
	if not bool(checked.ok):
		return checked
	var inventory: SimInventory = home.inventory
	if inventory.quantity(GROUND_CONTAINER, MATERIAL) != 3:
		return _failure("trip_ground_quantity", {"region": region, "quantity": inventory.quantity(GROUND_CONTAINER, MATERIAL)})
	var player_cell: Vector2i = SimRouteTravel.cell(home.actors.player.cell)
	if runtime.controlled_cell() != player_cell:
		return _failure("trip_player_location", {"region": region})
	var item_cell: Vector2i = world.artifacts.object_cell(ITEM_ID)
	var material_slot: Dictionary = world.object_lifecycle.ground.locate("home", GROUND_CONTAINER)
	var material_cell: Vector2i = material_slot.cell
	return {"ok": true, "region": runtime.current_region, "active_region": world.active_region,
		"clock_ms": _clock.elapsed_ms, "world_ms": world.elapsed_ms, "target_ms": world.target_ms,
		"player_cell": [player_cell.x, player_cell.y], "item_id": ITEM_ID,
		"item_container": world.artifacts.objects[ITEM_ID].container, "item_cell": [item_cell.x, item_cell.y],
		"material_container": GROUND_CONTAINER, "material_cell": [material_cell.x, material_cell.y], "material_quantity": inventory.quantity(GROUND_CONTAINER, MATERIAL)}


func _valid_expectation(expected: Dictionary) -> bool:
	for key: String in ["checkpoint_ms", "due_ms", "wood_total", "checkpoint_store", "checkpoint_actor"]:
		if not ReolGameClock._integer(expected.get(key)) or int(expected[key]) < 0:
			return false
	if not _valid_cell(expected.get("item_cell")) or not _valid_cell(expected.get("material_cell")) or expected.get("item_container") != ITEM_CONTAINER:
		return false
	var trip: Variant = expected.get("trip")
	if not trip is Dictionary or not expected.get("river_snapshot") is Dictionary or not trip.get("river_snapshot_hash") is String:
		return false
	for name: String in ["before", "river", "home"]:
		var record: Variant = trip.get(name)
		if not record is Dictionary or not _valid_cell(record.get("player_cell")):
			return false
		for key: String in ["clock_ms", "world_ms", "target_ms", "material_quantity"]:
			if not ReolGameClock._integer(record.get(key)) or int(record[key]) < 0:
				return false
	return true


func _valid_cell(value: Variant) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for coordinate: Variant in value:
		if not ReolGameClock._integer(coordinate) or int(coordinate) < 0 or int(coordinate) >= WorldMapData.WORLD_SIZE:
			return false
	return true


func _check_trip(runtime: Node, expected: Dictionary) -> Dictionary:
	if not _valid_expectation(expected):
		return _failure("invalid_trip_expectation")
	var trip: Dictionary = expected.trip
	for name: String in ["before", "river", "home"]:
		var record: Dictionary = trip[name]
		var region: String = "river" if name == "river" else "home"
		if not bool(record.get("ok", false)) or record.get("region") != region or record.get("active_region") != region or int(record.world_ms) != int(record.clock_ms) or int(record.target_ms) != int(record.clock_ms) or record.get("item_id") != ITEM_ID or record.get("item_container") != ITEM_CONTAINER or record.get("item_cell") != expected.item_cell or record.get("material_container") != GROUND_CONTAINER or record.get("material_cell") != expected.material_cell or int(record.material_quantity) != 3:
			return _failure("trip_record", {"stage": name, "record": record})
	var outward_ms: int = int(trip.river.clock_ms) - int(trip.before.clock_ms)
	var inward_ms: int = int(trip.home.clock_ms) - int(trip.river.clock_ms)
	if outward_ms <= 0 or inward_ms <= 0 or outward_ms > MAX_TRIP_MINUTES * MINUTE_MS or inward_ms > MAX_TRIP_MINUTES * MINUTE_MS or outward_ms % MINUTE_MS != 0 or inward_ms % MINUTE_MS != 0 or int(expected.checkpoint_ms) != int(trip.home.clock_ms) + CHECKPOINT_STEP_MS or int(expected.due_ms) != int(trip.home.clock_ms) + DURATION_MS:
		return _failure("trip_timing", {"outward_ms": outward_ms, "inward_ms": inward_ms})
	var river_center: Vector2i = runtime.centers.river
	var home_center: Vector2i = runtime.centers.home
	if SimRouteTravel.cell(trip.river.player_cell) != river_center or SimRouteTravel.cell(trip.home.player_cell) != home_center or runtime.current_region != "home" or runtime.world_sim.active_region != "home" or not runtime.player_journey.is_empty() or runtime.controlled_cell() != home_center:
		return _failure("trip_endpoints")
	return _check_receipts(runtime.world_sim, expected, int(trip.before.clock_ms))


func _check_receipts(world: RegionalSimulation, expected: Dictionary, at_ms: int) -> Dictionary:
	var first: Vector2i = SimRouteTravel.cell(expected.item_cell)
	var second: Vector2i = SimRouteTravel.cell(expected.material_cell)
	var requests: Array[Dictionary] = [_spawn_request(first), _carry_request(), _return_request(first), _drop_request(second)]
	var stock_reference: Dictionary = {"kind": "stock", "domain": "village", "region": "home", "container": GROUND_CONTAINER, "item": MATERIAL}
	var results: Array[Dictionary] = [
		{"ok": true, "reference": _item_reference(), "to": _location(SPAWN_CONTAINER)},
		{"ok": true, "reference": _item_reference(), "from": _location(SPAWN_CONTAINER), "to": _location("actor:player")},
		{"ok": true, "reference": _item_reference(), "from": _location("actor:player"), "to": _location(ITEM_CONTAINER)},
		{"ok": true, "reference": stock_reference, "from": _location("store"), "to": _location(GROUND_CONTAINER), "amount": 3, "item": MATERIAL, "inventory_operation": "object_lifecycle:" + DROP_COMMAND, "reservation": ""},
	]
	var previous_sequence: int = 0
	for index: int in requests.size():
		var request: Dictionary = requests[index]
		var receipt: Dictionary = world.object_lifecycle._receipt(request.command)
		if not world.object_lifecycle._same(receipt.get("request"), request) or not world.object_lifecycle._same(receipt.get("result"), results[index]) or not ReolGameClock._integer(receipt.get("at_ms")) or int(receipt.at_ms) != at_ms or not ReolGameClock._integer(receipt.get("sequence")) or int(receipt.sequence) <= previous_sequence:
			return _failure("trip_receipt", {"command": request.command, "receipt": receipt})
		previous_sequence = int(receipt.sequence)
	if not world.regions.home.inventory.operations.has("object_lifecycle:" + DROP_COMMAND):
		return _failure("trip_stock_operation")
	return {"ok": true}


func _check_river_snapshot(runtime: Node, expected: Dictionary) -> Dictionary:
	var snapshot: Dictionary = expected.river_snapshot
	if _hash(snapshot) != expected.trip.river_snapshot_hash:
		return _failure("river_snapshot_hash")
	var before: RegionalSimulation = runtime.world_sim
	var staged: Dictionary = _snapshots.stage(runtime, snapshot)
	if staged.is_empty() or runtime.world_sim != before or staged.world == before:
		return _failure("river_candidate_stage")
	var candidate: RegionalSimulation = staged.world
	var record: Dictionary = expected.trip.river
	var clock: Dictionary = snapshot.get("clock", {})
	var player: Dictionary = snapshot.get("player", {})
	var continuity: Dictionary = snapshot.get("continuity", {})
	if candidate.active_region != "river" or candidate.elapsed_ms != int(record.clock_ms) or candidate.target_ms != candidate.elapsed_ms or candidate.regions.home.elapsed_ms != candidate.elapsed_ms or int(clock.get("elapsed_ms", -1)) != candidate.elapsed_ms or player.get("cell") != record.player_cell or continuity.get("player_journey") != {} or candidate.regions.home.actors.player.cell != record.player_cell:
		return _failure("river_candidate_boundary")
	var checked: Dictionary = _physical(candidate, expected)
	if not bool(checked.ok):
		return checked
	if candidate.regions.home.inventory.quantity(GROUND_CONTAINER, MATERIAL) != 3:
		return _failure("river_candidate_quantity")
	var receipts: Dictionary = _check_receipts(candidate, expected, int(expected.trip.before.clock_ms))
	if not bool(receipts.ok):
		return receipts
	if _hash(_snapshots.capture(runtime)) != expected.checkpoint_hash:
		return _failure("river_stage_mutated_live_checkpoint")
	return {"ok": true}


func _advance(world: RegionalSimulation, amount: int) -> bool:
	var target: int = _clock.elapsed_ms + amount
	_clock.advance_msec(amount)
	return _committed(world, target)


func _committed(world: RegionalSimulation, target: int) -> bool:
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


func _item_reference() -> Dictionary:
	return {"kind": "artifact", "id": ITEM_ID}


func _spawn_request(cell: Vector2i) -> Dictionary:
	return {"command": SPAWN_COMMAND, "op": "spawn", "id": ITEM_ID, "definition": "plain_slate", "to": _ground(cell)}


func _carry_request() -> Dictionary:
	return {"command": CARRY_COMMAND, "op": "move", "id": ITEM_ID, "from": _location(SPAWN_CONTAINER), "to": _location("actor:player")}


func _return_request(cell: Vector2i) -> Dictionary:
	return {"command": RETURN_COMMAND, "op": "move", "id": ITEM_ID, "from": _location("actor:player"), "to": _ground(cell)}


func _drop_request(cell: Vector2i) -> Dictionary:
	return {"command": DROP_COMMAND, "op": "stock_transfer", "from": _location("store"), "to": _ground(cell), "item": MATERIAL, "amount": 3}


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
