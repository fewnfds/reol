extends "res://tools/qa/thermal_devices_restart.gd"
## Ordinary Main, original warm-stone actions and physical travel. Only the
## initial kitchen position is arranged; no Q, charges or receipts are injected.

const STORE_SAVE: String = "res://logs/thermal_store_restart.json"
const STORE_EXPECTED: String = "res://logs/thermal_store_expected.json"
const STONE: String = "hearth_stone"
const FUTURE_MS: int = 62347


func _run() -> void:
	_started_ms = Time.get_ticks_msec()
	create_timer(25.0, true, false, true).timeout.connect(_watchdog)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] not in ["--phase=write", "--phase=read"]:
		_fail("pass one native write/read phase")
		return
	_phase = "write" if args[0] == "--phase=write" else "read"
	_report = {"phase": _phase, "result": "running", "scope": "ordinary Main, one original paid pulse, geographic weather and complete process restart", "screenshots": []}
	_clock = root.get_node("GameClock")
	_clock.set_paused(true)
	root.size = Vector2i(1600, 900)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	_runtime = _main._continuity
	_codec = load("res://scripts/runtime/world_session_snapshot.gd")
	if _phase == "write":
		if not _require(_runtime.select_starting_avatar("subject:player"), "ordinary human selection failed"):
			return
		_clock.set_paused(true)
		var kitchen: Vector2i = _runtime.world_sim.artifacts.object_cell(STONE)
		_runtime._home._player.spawn_at(kitchen)
		_runtime._home._sync_player_cell()
		if not _stone_action("study") or not _stone_action("take"):
			return
		var field: Vector2i = _find_field(kitchen)
		if not _require(field.x >= 0 and _runtime.travel_to("home", field), "no reachable isolated field"):
			return
		var steps: int = 0
		while not _runtime.player_journey.is_empty():
			if not _require(steps < 256 and _within_budget(), "real field journey exceeded budget"):
				return
			if not _advance(maxi(1, int(_runtime.player_journey.due_ms) - _clock.elapsed_ms)):
				return
			steps += 1
			await process_frame
		if not _require(_runtime.controlled_cell() == field, "original body did not arrive at field") or not _stone_action("warm") or not _advance(173):
			return
		if not _require(_runtime.world_sim.environment_fields.storage_summary() == {"logical_cells": 25, "q_slots": 6}, "ordinary paid pulse did not select unique orbit Q"):
			return
		if not _require(_runtime.save_game(ProjectSettings.globalize_path(STORE_SAVE)) == OK, "ordinary compressed checkpoint save failed"):
			return
		var expected: Dictionary = {"saved_digest": _digest(), "save_sha256": FileAccess.get_sha256(STORE_SAVE), "at_ms": _clock.elapsed_ms, "field": [field.x, field.y]}
		if not _advance(FUTURE_MS):
			return
		expected["future_digest"] = _digest()
		if not _require(_write_json(STORE_EXPECTED, expected), "cannot write uninterrupted evidence"):
			return
		_report.merge(expected)
	else:
		var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(STORE_EXPECTED))
		if not _require(expected is Dictionary and expected.has("future_digest") and FileAccess.get_sha256(STORE_SAVE) == expected.save_sha256, "native evidence unavailable or changed"):
			return
		if not _require(_runtime.load_game(ProjectSettings.globalize_path(STORE_SAVE)) == OK, "fresh ordinary loader rejected expanded v3 checkpoint"):
			return
		if not _require(_digest() == expected.saved_digest and _clock.elapsed_ms == int(expected.at_ms), "complete loaded world differs"):
			return
		if not _require(_runtime.world_sim.environment_fields.storage_summary() == {"logical_cells": 25, "q_slots": 6}, "fresh load did not rebuild compressed ownership") or not _advance(FUTURE_MS):
			return
		if not _require(_digest() == expected.future_digest, "independent native future differs"):
			return
		_report.merge(expected)
		for _frame: int in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "res://logs/thermal_store_read.png"
		var picture: Image = root.get_texture().get_image()
		if not _require(picture != null and picture.save_png(path) == OK, "native world capture failed"):
			return
		_report.screenshots.append(path)
	if not _clock_consistent() or not _within_budget():
		return
	_report["storage"] = _runtime.world_sim.environment_fields.storage_summary()
	_report["elapsed_real_ms"] = Time.get_ticks_msec() - _started_ms
	_report["result"] = "passed"
	_write_json(_report_path(), _report)
	print("THERMAL_STORE_NATIVE ", _phase, " passed ", _report)
	quit(0)


func _stone_action(verb: String) -> bool:
	_runtime.prepare_player_command()
	var result: Dictionary = _runtime.world_sim.artifacts.begin("player", verb, STONE)
	if not _require(bool(result.ok), "original stone action refused: " + verb + str(result)):
		return false
	var due: int = int(_runtime.world_sim.artifacts.active.player.due_ms)
	return _advance(due - _clock.elapsed_ms) and _require(not _runtime.world_sim.artifacts.active.has("player"), "original stone action unfinished")


func _find_field(kitchen: Vector2i) -> Vector2i:
	var world: RegionalSimulation = _runtime.world_sim
	for y: int in range(-18, 19, 6):
		for x: int in range(-18, 19, 6):
			if absi(x) + absi(y) < 12:
				continue
			var point: Vector2i = kitchen + Vector2i(x, y)
			if not world.map_data.terrain_is_walkable(point) or _runtime._find_path(kitchen, point).is_empty():
				continue
			var available: bool = true
			for dy: int in range(-3, 4):
				for dx: int in range(-3, 4):
					var cell: Vector2i = point + Vector2i(dx, dy)
					available = available and world.environment_fields._valid_cell(cell) and not world.construction.thermal_roofed(cell) and not world.construction.thermal_barrier(cell)
			if available:
				return point
	return Vector2i(-1, -1)


func _report_path() -> String:
	return "res://logs/thermal_store_native_%s.json" % _phase
