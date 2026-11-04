extends SceneTree
## Native two-process evidence: -- --phase=write, then -- --phase=read.
## Only ordinary human commands, original materials and GameClock advance rules.
## QA outputs belong to logs; this script never edits fixtures or seeds projects.

const SAVE: String = "res://logs/structure_restart.json"
const EXPECTED: String = "res://logs/structure_expected.json"
const MARKER: String = "structure_native_v1"
const MAX_STEPS: int = 1024
const MAX_REAL_MS: int = 30000
const SAMPLE_COUNT: int = 30
const LAYOUT: Array[Dictionary] = [
	{"name": "door", "type": "wood_door", "offset": Vector2i(2, 2), "mask": 10},
	{"name": "west_end", "type": "wood_wall", "offset": Vector2i(1, 2), "mask": 2},
	{"name": "tee", "type": "wood_wall", "offset": Vector2i(3, 2), "mask": 11},
	{"name": "straight", "type": "wood_wall", "offset": Vector2i(4, 2), "mask": 10},
	{"name": "corner", "type": "wood_wall", "offset": Vector2i(5, 2), "mask": 12},
	{"name": "north_end", "type": "wood_wall", "offset": Vector2i(3, 1), "mask": 4},
	{"name": "south_end", "type": "wood_wall", "offset": Vector2i(5, 3), "mask": 1},
]

var _main: Node
var _runtime: Node
var _adapter: Node
var _clock: ReolGameClock
var _snapshot_codec: Variant
var _phase: String = "invalid"
var _origin: Vector2i
var _rows: Array[Dictionary] = []
var _report: Dictionary = {}
var _events: Array[Dictionary] = []
var _fog_updates: int = 0
var _started_ms: int = 0
var _failed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_started_ms = Time.get_ticks_msec()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--phase=write") == args.has("--phase=read"):
		_fail("pass exactly one of --phase=write or --phase=read after --")
		return
	_phase = "write" if args.has("--phase=write") else "read"
	_report = {
		"marker": MARKER, "phase": _phase, "result": "running",
		"engine": Engine.get_version_info(), "started_utc": Time.get_datetime_string_from_system(true),
		"max_real_ms": MAX_REAL_MS, "max_steps_per_command": MAX_STEPS,
		"scope": "native scene; original human body, construction, inventory, clock, sight and fog",
		"screenshots": [], "commands": [],
	}
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs"))
	if directory_error != OK:
		_fail("cannot create isolated QA output directory")
		return
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	root.size = Vector2i(1600, 900)
	root.position = Vector2i.ZERO
	_runtime = _main._continuity
	_clock = root.get_node("GameClock")
	# SceneTree --script is parsed before autoload globals are available. Load
	# runtime collaborators only after deferred scene assembly has completed.
	_snapshot_codec = load("res://scripts/runtime/world_session_snapshot.gd")
	if not _require(_runtime != null and _runtime.world_sim != null, "ordinary scene assembly failed"):
		return
	_adapter = _runtime.construction_adapter
	if not _require(_adapter != null, "construction runtime unavailable"):
		return
	_clock.set_paused(true)
	_main.fog.visibility_updated.connect(_on_visibility_updated)
	_domain().structures_changed.connect(_on_structure_changed)
	var completed: bool
	if _phase == "write":
		completed = await _write_phase()
	else:
		completed = await _read_phase()
	if not completed or _failed:
		return
	_report["result"] = "passed"
	_report["elapsed_world_ms"] = _clock.elapsed_ms
	_report["elapsed_real_ms"] = Time.get_ticks_msec() - _started_ms
	_report["structure_events"] = _events
	if not _write_json(_report_path(), _report):
		_fail("cannot write final QA report")
		return
	print("STRUCTURE_NATIVE ", _phase, " passed report=", _report_path(), " world_ms=", _clock.elapsed_ms)
	quit(0)


func _write_phase() -> bool:
	if not _require(_runtime.select_starting_avatar("subject:player"), "real human opening selection failed"):
		return false
	var store: Vector2i = SimRouteTravel.cell(_runtime.world_sim.regions.home.places.store.cell)
	_adapter.approach_store()
	if not await _finish_journey(store):
		return false
	_adapter.register_yard()
	if not _require(_domain().sites.has("sect_yard"), "real register_yard command failed: " + _adapter._reply.text):
		return false
	_origin = _domain().site_bounds().position
	_report["origin"] = _cell_array(_origin)
	_report["store_wood_before"] = _inventory().quantity("store", "wood")
	if not await _travel(_origin):
		return false
	for specification: Dictionary in LAYOUT:
		_runtime.prepare_player_command()
		var cell: Vector2i = _origin + Vector2i(specification.offset)
		var placed: Dictionary = _domain().place("player", str(specification.type), cell)
		if not _require(bool(placed.ok), "real blueprint rejected: " + str(placed.line)):
			return false
		var id: String = str(placed.project)
		var blueprint: Dictionary = SimStructureQuery.locate(_runtime.world_sim, {"kind": "construction", "id": id})
		if not _require(bool(blueprint.get("ok", false)) and blueprint.state == "blueprint" and not bool(blueprint.wall_connection) and SimStructureQuery.wall_mask(_runtime.world_sim, cell) == 0, "blueprint acquired built-wall connectivity"):
			return false
		var began: Dictionary = _domain().begin("player", id, "build")
		if not _require(bool(began.ok), "real construction start rejected: " + str(began.line)):
			return false
		if not await _finish_construction(id, "build"):
			return false
		_rows.append({"name": str(specification.name), "id": id, "type": str(specification.type), "cell": _cell_array(cell), "expected_mask": int(specification.mask)})
	_report["store_wood_after"] = _inventory().quantity("store", "wood")
	_report["stock_note"] = "Concurrent NPC logistics can change the store. Project transfer/consume receipts prove construction cost."
	if not _verify_structures_and_costs():
		return false
	var observer: Vector2i = _origin + Vector2i(2, 1)
	if not await _travel(observer):
		return false
	_prepare_view()
	await _settle_view()
	var closed: Dictionary = _door_observation()
	_report["closed_before_save"] = closed
	if not _require(_closed_observation_valid(closed), "closed-door stationary sight baseline failed"):
		return false
	if not await _capture("closed"):
		return false
	if not _benchmark_queries():
		return false
	if not _require(_runtime.save_game(ProjectSettings.globalize_path(SAVE)) == OK, "ordinary structure saver failed"):
		return false
	var digest: String = _snapshot_digest()
	var expected: Dictionary = {
		"marker": MARKER, "digest": digest, "origin": _cell_array(_origin),
		"rows": _rows, "observer": _cell_array(observer), "target": _cell_array(_origin + Vector2i(2, 3)),
		"elapsed_world_ms": _clock.elapsed_ms, "avatar_subject": _runtime.avatar_subject,
		"costs": _report.costs, "store_wood_before": _report.store_wood_before, "store_wood_after": _report.store_wood_after,
	}
	if not _write_json(EXPECTED, expected):
		_fail("cannot write fresh-process expected metadata")
		return false
	_report["digest"] = digest
	_report["restart_save"] = SAVE
	_report["restart_expected"] = EXPECTED
	_report["restart_status"] = "written; fresh-process read phase required"
	return _clock_consistent()


func _read_phase() -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED))
	if not _require(parsed is Dictionary and parsed.get("marker") == MARKER and parsed.get("rows") is Array and parsed.get("digest") is String, "missing or invalid write-phase metadata"):
		return false
	var expected: Dictionary = parsed
	_origin = SimRouteTravel.cell(expected.origin)
	for row: Dictionary in expected.rows:
		_rows.append(row.duplicate(true))
	var old_world: RegionalSimulation = _runtime.world_sim
	var old_domain: SimConstruction = _domain()
	var observer_callback := Callable(_adapter, "_on_structures_changed")
	if not _require(old_domain.structures_changed.is_connected(observer_callback), "new scene did not bind its original construction observer"):
		return false
	if not _require(_runtime.load_game(ProjectSettings.globalize_path(SAVE)) == OK, "fresh-process ordinary loader rejected the built world"):
		return false
	# Capture before any frame or command can change exploration or a live rule.
	var digest: String = _snapshot_digest()
	_report["digest"] = digest
	_report["expected_digest"] = str(expected.digest)
	if not _require(digest == str(expected.digest), "fresh-process complete snapshot differs from the saved world"):
		return false
	var rebound: Dictionary = {
		"world_replaced": _runtime.world_sim != old_world,
		"domain_replaced": _domain() != old_domain,
		"old_signal_disconnected": not old_domain.structures_changed.is_connected(observer_callback),
		"new_signal_connected": _domain().structures_changed.is_connected(observer_callback),
		"adapter_uses_loaded_domain": _adapter._observed_domain == _domain(),
		"sight_provider_uses_loaded_domain": _main.world._sight_obstacles.get_object() == _domain(),
		"sight_provider_method": str(_main.world._sight_obstacles.get_method()),
	}
	_report["fresh_process_rebinding"] = rebound
	for key: String in ["world_replaced", "domain_replaced", "old_signal_disconnected", "new_signal_connected", "adapter_uses_loaded_domain", "sight_provider_uses_loaded_domain"]:
		if not _require(bool(rebound[key]), "load rebinding failed: " + key):
			return false
	if not _require(rebound.sight_provider_method == "blocks_sight" and _runtime.human_player_active() and _clock.elapsed_ms == int(expected.elapsed_world_ms), "loaded avatar, clock or sight provider differs"):
		return false
	_domain().structures_changed.connect(_on_structure_changed)
	if not _clock_consistent() or not _verify_structures_and_costs():
		return false
	_prepare_view()
	await _settle_view()
	var closed: Dictionary = _door_observation()
	_report["closed_after_restart"] = closed
	if not _require(_closed_observation_valid(closed), "fresh-process closed-door baseline failed"):
		return false
	if not await _capture("closed"):
		return false
	if not await _operate_door("open", closed):
		return false
	if not await _capture("open"):
		return false
	if not await _operate_door("close", closed):
		return false
	if not await _capture("reclosed"):
		return false
	if not _benchmark_queries():
		return false
	if not await _travel(_origin + Vector2i(6, 2)):
		return false
	await _settle_view()
	var corner_visible: bool = _main.fog.is_cell_visible(_origin + Vector2i(5, 2))
	var south_end_visible: bool = _main.fog.is_cell_visible(_origin + Vector2i(5, 3))
	_report["corner_observation"] = {"cell": _cell_array(_runtime.controlled_cell()), "focus": _cell_array(_main.fog._focus_cell), "corner_visible": corner_visible, "south_end_visible": south_end_visible}
	if not _require(corner_visible and south_end_visible, "real east-side observer did not see the corner and south end"):
		return false
	if not await _capture("corner"):
		return false
	_report["restart_status"] = "fresh-process ordinary load matched the complete snapshot; loaded domain then opened and closed the door"
	return _clock_consistent()


func _domain() -> SimConstruction:
	return _runtime.world_sim.construction


func _inventory() -> SimInventory:
	return _runtime.world_sim.regions.home.inventory


func _travel(target: Vector2i) -> bool:
	if _runtime.controlled_cell() != target:
		if not _require(_runtime.travel_to("home", target), "real journey could not start for " + str(target)):
			return false
	return await _finish_journey(target)


func _finish_journey(target: Vector2i) -> bool:
	var started: int = _clock.elapsed_ms
	var steps: int = 0
	while not _runtime.player_journey.is_empty():
		if not _require(steps < MAX_STEPS and _within_budget(), "journey exceeded its bounded QA budget"):
			return false
		var due: int = int(_runtime.player_journey.due_ms)
		_clock.advance_msec(maxi(1, due - _clock.elapsed_ms))
		if not _clock_consistent():
			return false
		steps += 1
		await process_frame
	_report.commands.append({"kind": "journey", "target": _cell_array(target), "steps": steps, "started_ms": started, "completed_ms": _clock.elapsed_ms})
	return _require(_runtime.controlled_cell() == target and _body_position().is_equal_approx(TileGrid.cell_to_world(target)), "journey did not reach its actual target")


func _finish_construction(id: String, kind: String) -> bool:
	var started: int = _clock.elapsed_ms
	var steps: int = 0
	var phases: Array[String] = []
	while _domain().active.has("player"):
		if not _require(steps < MAX_STEPS and _within_budget(), "construction exceeded its bounded QA budget"):
			return false
		var job: Dictionary = _domain().active.player
		if not _require(str(job.project) == id and str(job.kind) == kind, "another process replaced the player's construction command"):
			return false
		var phase: String = str(job.phase)
		if not phases.has(phase):
			phases.append(phase)
		_clock.advance_msec(maxi(1, int(job.due_ms) - _clock.elapsed_ms))
		if not _clock_consistent():
			return false
		steps += 1
		await process_frame
	_report.commands.append({"kind": kind, "project": id, "phases": phases, "steps": steps, "started_ms": started, "completed_ms": _clock.elapsed_ms})
	var project: Dictionary = _domain().projects[id]
	if kind == "build":
		return _require(project.state == "built" and int(project.work_ms) == int(_domain().definitions.types[project.type].work_ms) and phases.has("pickup") and phases.has("work"), "real project did not finish transport and construction: " + str(project.line))
	return _require(bool(project.open) == (kind == "open"), "real door operation failed: " + str(project.line))


func _verify_structures_and_costs() -> bool:
	var receipts: Array[Dictionary] = []
	var total: int = 0
	for row: Dictionary in _rows:
		var id: String = str(row.id)
		if not _require(_domain().projects.has(id), "saved project missing: " + id):
			return false
		var project: Dictionary = _domain().projects[id]
		var cell: Vector2i = SimRouteTravel.cell(row.cell)
		var amount: int = int(_domain().definitions.types[row.type].amount)
		var supply: Dictionary = _inventory().operations.get(id + ":supply", {})
		var consumed: Dictionary = _inventory().operations.get(id + ":build", {})
		var mask: int = SimStructureQuery.wall_mask(_runtime.world_sim, cell)
		if not _require(project.state == "built" and project.type == row.type and SimRouteTravel.cell(project.cell) == cell and mask == int(row.expected_mask), "built structure or mask differs for " + str(row.name)):
			return false
		if not _require(supply.get("kind") == "transfer" and supply.get("source") == "store" and supply.get("target") == id and supply.get("item") == "wood" and int(supply.get("amount", -1)) == amount, "original supply receipt differs for " + id):
			return false
		if not _require(consumed == {"kind": "consume", "container": id, "item": "wood", "amount": amount} and _inventory().quantity(id, "wood") == 0, "original build consumption differs for " + id):
			return false
		row["actual_mask"] = mask
		receipts.append({"id": id, "amount": amount, "supply": supply.duplicate(true), "build": consumed.duplicate(true), "remaining_wood": _inventory().quantity(id, "wood"), "work_ms": int(project.work_ms)})
		total += amount
	_report["structures"] = _rows
	_report["costs"] = {"wood_total": total, "receipts": receipts}
	return _require(_rows.size() == 7 and total == 22, "six real walls and one real door must consume exactly 22 wood")


func _operate_door(kind: String, baseline: Dictionary) -> bool:
	var events_before: int = _events.size()
	var updates_before: int = _fog_updates
	_runtime.prepare_player_command()
	var began: Dictionary = _domain().begin("player", _door_id(), kind)
	if not _require(bool(began.ok), "loaded-domain door command rejected: " + str(began.line)):
		return false
	if not await _finish_construction(_door_id(), kind):
		return false
	# No manual fog invalidation/update: only the actual completion signal may
	# invalidate visibility for this stationary observer.
	await _settle_view()
	var observed: Dictionary = _door_observation()
	observed["structure_event_count"] = _events.size() - events_before
	observed["automatic_fog_updates"] = _fog_updates - updates_before
	_report[kind + "_after_restart"] = observed
	var opened: bool = kind == "open"
	if not _require(observed.cell == baseline.cell and observed.position == baseline.position and observed.focus == baseline.focus, "door operation moved the original body or fog focus"):
		return false
	if not _require(bool(observed.open) == opened and bool(observed.sight_blocked) != opened and bool(observed.target_visible) == opened and int(observed.mask) == int(baseline.mask), "stationary door sight/fog or connection mask differs"):
		return false
	if not _require(_events.size() > events_before and _fog_updates > updates_before, "loaded completion did not reach the actual structure/fog observer"):
		return false
	return _require(bool(_events.back().fog_dirty_after_structure_signal), "completion failed to invalidate stationary fog through the original signal chain")


func _door_observation() -> Dictionary:
	var cell: Vector2i = _origin + Vector2i(2, 2)
	return {
		"cell": _cell_array(_runtime.controlled_cell()), "position": _position_array(_body_position()),
		"focus": _cell_array(_main.fog._focus_cell), "door_cell": _cell_array(cell),
		"target": _cell_array(_origin + Vector2i(2, 3)),
		"open": bool(_domain().projects[_door_id()].open), "sight_blocked": _main.world.is_sight_blocked(cell),
		"target_visible": _main.fog.is_cell_visible(_origin + Vector2i(2, 3)),
		"mask": SimStructureQuery.wall_mask(_runtime.world_sim, cell), "fog_updates": _fog_updates,
		"world_ms": _clock.elapsed_ms,
	}


func _closed_observation_valid(observed: Dictionary) -> bool:
	return observed.cell == _cell_array(_origin + Vector2i(2, 1)) and observed.focus == observed.cell and not bool(observed.open) and bool(observed.sight_blocked) and not bool(observed.target_visible) and int(observed.mask) == 10


func _door_id() -> String:
	for row: Dictionary in _rows:
		if row.name == "door":
			return str(row.id)
	return ""


func _body_position() -> Vector2:
	return SimRouteTravel.point(_runtime.world_sim.regions.home.actors.player)


func _prepare_view() -> void:
	# Hide only other HUD layers; original world, entities and fog stay active.
	for layer: Node in _main.find_children("*", "CanvasLayer", true, false):
		if not _adapter.is_ancestor_of(layer):
			layer.visible = false
	_adapter.show_panel()
	_adapter.select_cell(_origin + Vector2i(2, 2))
	_adapter.refresh_choices(_door_id())
	_adapter.refresh()
	_main.camera.follow_focus = false
	_main.camera.zoom = Vector2(1.25, 1.25)
	_main.camera.global_position = TileGrid.cell_to_world(_origin + Vector2i(3, 2)) + Vector2(160, 0)
	_main.camera._clamp_to_world()
	_adapter.queue_redraw()


func _settle_view() -> void:
	await create_timer(0.25, true).timeout
	for frame: int in 8:
		await process_frame
	_adapter.queue_redraw()
	await RenderingServer.frame_post_draw


func _capture(label: String) -> bool:
	await _settle_view()
	var path: String = "res://logs/structure_%s_%s.png" % [_phase, label]
	var image: Image = root.get_texture().get_image()
	if not _require(image != null and image.save_png(path) == OK, "native screenshot failed: " + path):
		return false
	_report.screenshots.append({"path": path, "observation": _door_observation(), "fog_active": _main.fog.visible})
	return true


func _benchmark_queries() -> bool:
	var cells: Array[Vector2i] = SimConstruction.cells_in(_domain().site_bounds())
	if not _require(cells.size() == 35, "query sample requires the actual 35-cell yard"):
		return false
	var digest_before: String = _snapshot_digest()
	var samples: Array[int] = []
	var checksum: int = 0
	for sample: int in SAMPLE_COUNT:
		if not _require(_within_budget(), "query sample exceeded its bounded QA budget"):
			return false
		var started: int = Time.get_ticks_usec()
		for cell: Vector2i in cells:
			checksum += SimStructureQuery.wall_mask(_runtime.world_sim, cell)
		samples.append(Time.get_ticks_usec() - started)
	var sorted: Array[int] = samples.duplicate()
	sorted.sort()
	var unchanged: bool = _snapshot_digest() == digest_before
	_report["wall_mask_query_cost"] = {
		"scope": "read-only wall_mask query batches; not frame time or large-world capacity",
		"samples": SAMPLE_COUNT, "cells_per_batch": cells.size(), "total_queries": SAMPLE_COUNT * cells.size(),
		"unit": "microseconds per 35-cell batch", "percentile_method": "nearest rank",
		"p50": sorted[ceili(SAMPLE_COUNT * 0.50) - 1], "p95": sorted[ceili(SAMPLE_COUNT * 0.95) - 1], "p99": sorted[ceili(SAMPLE_COUNT * 0.99) - 1],
		"samples_usec": samples, "checksum": checksum, "complete_snapshot_unchanged": unchanged,
	}
	return _require(unchanged, "read-only wall queries changed the complete session snapshot")


func _snapshot_digest() -> String:
	var snapshot: Dictionary = _snapshot_codec.capture(_runtime)
	return SnapshotValues.canonical_json(SnapshotValues.normalized(snapshot)).sha256_text()


func _on_visibility_updated() -> void:
	_fog_updates += 1


func _on_structure_changed(cells: Array[Vector2i]) -> void:
	var encoded: Array = []
	for cell: Vector2i in cells:
		encoded.append(_cell_array(cell))
	_events.append({"world_ms": _clock.elapsed_ms, "cells": encoded, "fog_dirty_after_structure_signal": _main.fog._visibility_dirty, "focus": _cell_array(_main.fog._focus_cell)})


func _clock_consistent() -> bool:
	return _require(_clock.elapsed_ms == _runtime.world_sim.elapsed_ms and _clock.elapsed_ms == _runtime.world_sim.target_ms, "GameClock/world committed time or retained target diverged")


func _within_budget() -> bool:
	return Time.get_ticks_msec() - _started_ms <= MAX_REAL_MS


func _require(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	_report["result"] = "failed"
	_report["failure"] = message
	_report["elapsed_real_ms"] = Time.get_ticks_msec() - _started_ms
	_report["structure_events"] = _events
	if _runtime != null and _runtime.world_sim != null:
		_report["diagnostic"] = {"avatar": _runtime.avatar_subject, "world_ms": _runtime.world_sim.elapsed_ms, "target_ms": _runtime.world_sim.target_ms, "player": _runtime.world_sim.regions.home.actors.player.duplicate(true), "journey": _runtime.player_journey.duplicate(true), "construction": _domain().to_dict()}
	_write_json(_report_path(), _report)
	printerr("STRUCTURE_NATIVE_FAILED ", _phase, " ", message, " report=", _report_path())
	quit(1)


func _report_path() -> String:
	return "res://logs/structure_%s.json" % _phase


func _write_json(path: String, value: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t", true))
	file.close()
	return true


func _cell_array(cell: Vector2i) -> Array[int]:
	return [cell.x, cell.y]


func _position_array(point: Vector2) -> Array[float]:
	return [point.x, point.y]
