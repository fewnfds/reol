extends SceneTree
## Native ordinary Main with real F8 placement and lifecycle stock transfer.
## A debug-only label explains the two screenshots; it is not a game feature.
## Example (use an external timeout/RSS guard, never --headless):
## godot --path . --script res://tests/benchmarks/world_fields_presentation.gd -- --tag run1 --world-editor
## Existing output files are never overwritten.

const UI = preload("res://scripts/ui/reol_ui_theme.gd")
const OUTPUT_DIR: String = "res://logs/world_fields_presentation"
const ESTABLISH_MS: int = 60000
const CAPTURE_FRAMES: int = 4
const LOAD_WARMUP_FRAMES: int = 60
const LOAD_SAMPLE_FRAMES: int = 600
const LOAD_STEP_MS: int = 100
const MATERIAL_COMMAND: String = "field_visual_wood"
const MATERIAL_CONTAINER: String = "ground:field_visual_wood"

var _main: Node
var _clock: Node
var _debug: Label
var _report: Dictionary = {"ok": false, "scope": "native ordinary sparse Main, CPU environmental fields, real F8 placement and real ground wood; test-only overlay and deterministic explicit clock; not full-density or whole-PC 16GB evidence"}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var options: Dictionary = _arguments(OS.get_cmdline_user_args())
	if not bool(options.get("ok", false)):
		_fail("arguments", options)
		return
	if DisplayServer.get_name() == "headless":
		_fail("native_window_required")
		return
	var prefix: String = OUTPUT_DIR + "/" + str(options.tag)
	var before_path: String = prefix + "-before.png"
	var editing_path: String = prefix + "-editing.png"
	var after_path: String = prefix + "-after.png"
	var report_path: String = prefix + ".json"
	for path: String in [before_path, editing_path, after_path, report_path]:
		if FileAccess.file_exists(path):
			_fail("output_exists", {"path": path})
			return
	var error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if error != OK and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(OUTPUT_DIR)):
		_fail("output_directory", {"error": int(error)})
		return
	_clock = root.get_node_or_null("GameClock")
	if _clock == null or not bool(_clock.call("restore_state", {"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})):
		_fail("clock_initialization")
		return
	_report["memory_static_before_main_bytes"] = OS.get_static_memory_usage()
	var setup_started: int = Time.get_ticks_usec()
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_fail("main_scene_missing")
		return
	_main = packed.instantiate()
	root.add_child(_main)
	current_scene = _main
	var runtime: Node = _main.get("_continuity")
	var world: RefCounted = runtime.get("world_sim") if runtime != null else null
	var avatar: Node = runtime.get("avatar_adapter") if runtime != null else null
	if runtime == null or world == null or avatar == null or not bool(avatar.call("choose", "subject:player")):
		_fail("main_initialization")
		return
	_clock.call("set_paused", true)
	var editor: Node = _main.get("_terrain_editor")
	# Resolve production scripts only after Main and GameClock are in the tree;
	# top-level runtime class annotations can compile their autoload references
	# before Godot has registered GameClock when launched with --script.
	var field_script: Variant = load("res://scripts/sim/world_environment_fields.gd")
	var field: RefCounted = world.get("local_heat")
	var field_matches: bool = field != null and field_script != null and is_instance_of(field, field_script)
	if editor == null or not field_matches or not _clock_stable(world, 0):
		_fail("field_editor_or_clock_unavailable", {
			"editor_present": editor != null, "field_present": field != null,
			"field_script_loaded": field_script != null, "field_type_matches": field_matches,
			"paused": bool(_clock.get("paused")), "pending": bool(_clock.call("has_pending_advance")),
			"clock_ms": int(_clock.get("elapsed_ms")), "world_ms": int(world.get("elapsed_ms")),
			"target_ms": int(world.get("target_ms")),
		})
		return
	_report["main_scene_load_and_world_opening_ms"] = _elapsed_ms(setup_started)
	_report["main_setup_scope"] = "Scene load, instantiation, ordinary seeded world and map creation, player selection and clock check; map generation is not separately instrumented."
	var center: Vector2i = runtime.call("controlled_cell")
	var first: Vector2i = _free_cell(world, center, Vector2i(-1, -1))
	var second: Vector2i = _free_cell(world, center, first)
	if first.x < 0 or second.x < 0:
		_fail("no_nearby_free_cells")
		return
	_report["slate_cell"] = [first.x, first.y]
	_report["wood_cell"] = [second.x, second.y]
	_report["visual_backend"] = {"display": DisplayServer.get_name(), "adapter": RenderingServer.get_video_adapter_name(), "driver": RenderingServer.get_current_rendering_driver_name()}
	_make_debug_label()
	var before: Dictionary = _sample(world, second)
	if not bool(before.get("ok", false)):
		_fail("before_sample", before)
		return
	_report["before"] = before
	_show("Before placement", before, first)
	if not await _capture(before_path, world, 0):
		_fail("before_capture")
		return
	# Drive the ordinary F8 input, then use the same editor command that an F8
	# canvas click dispatches. This is the real original item and lifecycle.
	var key := InputEventKey.new()
	key.keycode = KEY_F8
	key.pressed = true
	_main.call("_input", key)
	var editor_overlay: Control = editor.get("overlay")
	if editor_overlay == null or not editor_overlay.visible:
		_fail("f8_did_not_open_editor")
		return
	var generation_started: int = Time.get_ticks_usec()
	var placed: Dictionary = editor.call("place_object", "plain_slate", first)
	_report["single_slate_creation_call_ms"] = _elapsed_ms(generation_started)
	if not bool(placed.get("ok", false)) or not placed.get("reference") is Dictionary:
		_fail("f8_slate_placement", placed)
		return
	var item_id: String = str(placed.reference.get("id", ""))
	var lifecycle: RefCounted = world.get("object_lifecycle")
	if item_id.is_empty() or lifecycle == null or not bool(lifecycle.call("manages", item_id)):
		_fail("slate_identity")
		return
	_report["slate_id"] = item_id
	var after_slate: Dictionary = _sample(world, second)
	if not bool(after_slate.get("ok", false)):
		_fail("after_slate_sample", after_slate)
		return
	_show("F8 editor: real slate placed", after_slate, first)
	if not await _capture(editing_path, world, 0):
		_fail("editor_capture")
		return
	editor.call("close")
	var drop: Dictionary = {"command": MATERIAL_COMMAND, "op": "stock_transfer",
		"from": {"region": "home", "container": "store"},
		"to": {"region": "home", "cell": [second.x, second.y]}, "item": "wood", "amount": 3}
	var transfer_started: int = Time.get_ticks_usec()
	var dropped: Dictionary = lifecycle.call("execute", drop)
	_report["single_wood_transfer_call_ms"] = _elapsed_ms(transfer_started)
	if not bool(dropped.get("ok", false)) or dropped.get("to", {}).get("container") != MATERIAL_CONTAINER:
		_fail("wood_drop", dropped)
		return
	var initial: Dictionary = _sample(world, second)
	if not bool(initial.get("ok", false)):
		_fail("wood_initial_sample", initial)
		return
	var establish_started: int = Time.get_ticks_usec()
	_clock.call("advance_msec", ESTABLISH_MS)
	_report["initial_60s_game_time_advance_call_ms"] = _elapsed_ms(establish_started)
	if not _clock_stable(world, ESTABLISH_MS):
		_fail("common_time_not_committed", {"clock": _clock.get("elapsed_ms"), "world": world.get("elapsed_ms"), "target": world.get("target_ms")})
		return
	var after: Dictionary = _sample(world, second)
	if not bool(after.get("ok", false)) or float(after.get("elements", [0])[0]) <= 0.0:
		_fail("wood_field_not_established", after)
		return
	var participant_script: Variant = load("res://scripts/sim/world_environment_source_participant.gd")
	var source_key: String = participant_script.stock_key("home", MATERIAL_CONTAINER, "wood")
	var sources: RefCounted = field.get("_sources")
	var source: Dictionary = sources.call("get_source", source_key) if sources != null else {}
	var regions: Dictionary = world.get("regions")
	var home: RefCounted = regions.get("home")
	var inventory: RefCounted = home.get("inventory") if home != null else null
	if source.is_empty() or int(source.channels[1]) <= 0 or inventory == null or int(inventory.call("quantity", MATERIAL_CONTAINER, "wood")) != 3:
		_fail("wood_source_or_quantity")
		return
	var object_adapter: Node = runtime.get("object_adapter")
	if object_adapter != null:
		object_adapter.call("refresh")
	_report["after_slate"] = after_slate
	_report["wood_initial"] = initial
	_report["established"] = after
	_report["images"] = [before_path, editing_path, after_path]
	_show("After real wood: +60 s", after, first)
	if not await _capture(after_path, world, ESTABLISH_MS):
		_fail("established_capture")
		return
	var load_result: Dictionary = await _measure_load(world, field, lifecycle)
	if not bool(load_result.get("ok", false)):
		_fail("ordinary_load_measurement", load_result)
		return
	_report["ordinary_load"] = load_result
	if FileAccess.file_exists(report_path):
		_fail("output_exists_after_capture")
		return
	_report["ok"] = true
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		_fail("write_report", {"error": int(FileAccess.get_open_error())})
		return
	file.store_string(JSON.stringify(_report, "\t", true, true))
	file.close()
	print("WORLD_FIELDS_PRESENTATION_JSON:" + JSON.stringify(_report, "", true, true))
	_main.free()
	_main = null
	quit(0)


func _measure_load(world: RefCounted, field: RefCounted, lifecycle: RefCounted) -> Dictionary:
	# Every explicit advancement is checked before and after a render-frame
	# boundary. This is a deterministic stress cadence, not normal wall-time speed.
	var expected_ms: int = int(_clock.get("elapsed_ms"))
	if not _clock_stable(world, expected_ms):
		return {"ok": false, "reason": "initial_clock_not_stable"}
	var initial_ms: int = expected_ms
	var advance_us: Array[int] = []
	var frame_us: Array[int] = []
	var sampled_start_ms: int = 0
	var sampled_start_wall: int = 0
	var drawn_before: int = 0
	var before_fields: Dictionary = {}
	var before_counts: Dictionary = {}
	await process_frame
	if not _clock_stable(world, expected_ms):
		return _clock_failure(world, -1, "before_warmup", expected_ms)
	var last_frame_at: int = Time.get_ticks_usec()
	for index: int in range(LOAD_WARMUP_FRAMES + LOAD_SAMPLE_FRAMES):
		if index == LOAD_WARMUP_FRAMES:
			sampled_start_ms = expected_ms
			sampled_start_wall = last_frame_at
			drawn_before = Engine.get_frames_drawn()
		var advance_started: int = Time.get_ticks_usec()
		_clock.call("advance_msec", LOAD_STEP_MS)
		var advance_finished: int = Time.get_ticks_usec()
		expected_ms += LOAD_STEP_MS
		if not _clock_stable(world, expected_ms):
			return _clock_failure(world, index, "after_advance", expected_ms)
		if index == LOAD_WARMUP_FRAMES - 1:
			before_fields = field.call("diagnostics")
			before_counts = _entity_counts(world, lifecycle)
		if index >= LOAD_WARMUP_FRAMES:
			advance_us.append(advance_finished - advance_started)
		await process_frame
		var frame_finished: int = Time.get_ticks_usec()
		if not _clock_stable(world, expected_ms):
			return _clock_failure(world, index, "after_frame", expected_ms)
		if index >= LOAD_WARMUP_FRAMES:
			frame_us.append(frame_finished - last_frame_at)
		last_frame_at = frame_finished
	var drawn_after: int = Engine.get_frames_drawn()
	if advance_us.size() != LOAD_SAMPLE_FRAMES or frame_us.size() != LOAD_SAMPLE_FRAMES or drawn_after <= drawn_before:
		return {"ok": false, "reason": "incomplete_sample_or_no_render", "advance_samples": advance_us.size(), "frame_samples": frame_us.size(), "rendered_frames": drawn_after - drawn_before}
	advance_us.sort()
	frame_us.sort()
	var base_field: RefCounted = field.get("_field")
	return {
		"ok": true,
		"scope": "ordinary sparse opening on the CPU field, not a dense world, full-game capacity or whole-PC 16GB measurement",
		"timing_note": "Frame intervals include clock advancement, other frame work, rendering, frame cap/vsync and OS scheduling; advance times are synchronous call wall times, not isolated CPU/GPU times.",
		"time_policy": "Clock remains paused; each rendered-loop step explicitly requests 100 game milliseconds and verifies clock/world/target with no pending advance before and after the frame.",
		"warmup_frames": LOAD_WARMUP_FRAMES, "sample_frames": LOAD_SAMPLE_FRAMES,
		"game_ms_per_frame": LOAD_STEP_MS, "warmup_advanced_ms": sampled_start_ms - initial_ms,
		"sample_start_ms": sampled_start_ms, "sample_end_ms": expected_ms,
		"sample_advanced_ms": expected_ms - sampled_start_ms,
		"sample_wall_ms": float(last_frame_at - sampled_start_wall) / 1000.0,
		"rendered_frames_during_sample": drawn_after - drawn_before,
		"advance_call_ms": _distribution_ms(advance_us), "frame_interval_ms": _distribution_ms(frame_us),
		"field_diagnostics_before": before_fields, "field_diagnostics_after": field.call("diagnostics"),
		"base_field_diagnostics_after": base_field.call("diagnostics") if base_field != null else {},
		"entity_counts_before": before_counts, "entity_counts_after": _entity_counts(world, lifecycle),
		"godot_static_memory_current_bytes": OS.get_static_memory_usage(),
		"godot_static_memory_peak_bytes": OS.get_static_memory_peak_usage(),
		"memory_note": "Godot static allocations only; excludes other process/driver/VRAM and is not operating-system working-set or whole-machine RAM.",
		"processor": OS.get_processor_name(), "engine": Engine.get_version_info().string,
		"viewport_size": [root.size.x, root.size.y], "max_fps": Engine.max_fps,
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
	}


func _clock_failure(world: RefCounted, index: int, phase: String, expected_ms: int) -> Dictionary:
	return {"ok": false, "reason": "clock_or_world_drift", "frame": index, "phase": phase,
		"expected_ms": expected_ms, "clock_ms": int(_clock.get("elapsed_ms")),
		"world_ms": int(world.get("elapsed_ms")), "target_ms": int(world.get("target_ms")),
		"paused": bool(_clock.get("paused")), "pending": bool(_clock.call("has_pending_advance"))}


func _entity_counts(world: RefCounted, lifecycle: RefCounted) -> Dictionary:
	var regions: Dictionary = world.get("regions")
	var actors: int = 0
	var land_sources: int = 0
	for region: RefCounted in regions.values():
		var regional_actors: Dictionary = region.get("actors")
		actors += regional_actors.size()
		var resources: RefCounted = region.get("land_resources")
		if resources != null:
			var resource_sources: Dictionary = resources.get("sources")
			land_sources += resource_sources.size()
	var artifacts: RefCounted = world.get("artifacts")
	var avian: RefCounted = world.get("avian_life")
	var large: RefCounted = world.get("large_bodies")
	var artifact_objects: Dictionary = artifacts.get("objects") if artifacts != null else {}
	var bird_bodies: Dictionary = avian.get("birds") if avian != null else {}
	var large_bodies: Dictionary = large.get("bodies") if large != null else {}
	return {"regions": regions.size(), "regional_actor_records": actors, "bird_bodies": bird_bodies.size(),
		"large_bodies": large_bodies.size(), "unique_artifacts": artifact_objects.size(),
		"land_resource_records": land_sources, "lifecycle": lifecycle.call("diagnostics")}


func _distribution_ms(sorted: Array[int]) -> Dictionary:
	return {"samples": sorted.size(), "p50": _percentile_ms(sorted, 0.50),
		"p95": _percentile_ms(sorted, 0.95), "p99": _percentile_ms(sorted, 0.99),
		"max": float(sorted.back()) / 1000.0}


func _percentile_ms(sorted: Array[int], percentile: float) -> float:
	var index: int = clampi(ceili(float(sorted.size()) * percentile) - 1, 0, sorted.size() - 1)
	return float(sorted[index]) / 1000.0


func _elapsed_ms(start: int) -> float:
	return float(Time.get_ticks_usec() - start) / 1000.0


func _sample(world: RefCounted, cell: Vector2i) -> Dictionary:
	var field: RefCounted = world.get("local_heat")
	if field == null or not bool(field.call("activate_sources")):
		return {"ok": false, "reason": "field_activation"}
	var at_ms: int = int(world.get("elapsed_ms"))
	var actual: Dictionary = field.call("actual_at", cell, at_ms)
	var phases: Dictionary = field.call("elements_at", cell)
	if not bool(actual.get("ok", false)) or not SnapshotValues.finite_number(actual.get("value_c")) or not bool(phases.get("ok", false)) or not phases.get("values") is PackedFloat64Array or phases.values.size() != 5:
		return {"ok": false, "reason": "field_sample", "temperature": actual, "phases": phases}
	var content: RefCounted = world.get("_content")
	var definitions: RefCounted = content.get("environment_sources") if content != null else null
	if definitions == null:
		return {"ok": false, "reason": "source_definitions_unavailable"}
	return {"ok": true, "cell": [cell.x, cell.y], "at_ms": at_ms,
		"actual_c": float(actual.value_c), "elements": Array(phases.values), "source_digest": str(definitions.call("digest"))}


func _make_debug_label() -> void:
	var layer := CanvasLayer.new()
	layer.name = "WorldFieldsTestOverlay"
	layer.layer = 100
	_main.add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "DebugOnly"
	panel.theme = UI.create()
	panel.add_theme_stylebox_override("panel", UI.panel(UI.GOLD))
	panel.position = Vector2(780, 80)
	panel.custom_minimum_size = Vector2(470, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	_debug = UI.label(panel, "", UI.PAPER, 16)


func _show(stage: String, sample: Dictionary, slate: Vector2i) -> void:
	var values: Array = sample.elements
	_debug.text = "DEBUG ONLY · ENVIRONMENT FIELD\n%s\nSlate: %d,%d   Wood sample: %d,%d\nTime: %d ms   Temperature: %.2f °C\nWood %.2f  Fire %.2f  Earth %.2f\nMetal %.2f  Water %.2f" % [stage, slate.x, slate.y, int(sample.cell[0]), int(sample.cell[1]), int(sample.at_ms), float(sample.actual_c), float(values[0]), float(values[1]), float(values[2]), float(values[3]), float(values[4])]


func _capture(path: String, world: RefCounted, expected_ms: int) -> bool:
	var drawn_before: int = Engine.get_frames_drawn()
	for _index: int in CAPTURE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	if not _clock_stable(world, expected_ms) or Engine.get_frames_drawn() <= drawn_before or FileAccess.file_exists(path):
		return false
	var picture: Image = root.get_texture().get_image()
	return picture != null and not picture.is_empty() and picture.save_png(path) == OK


func _clock_stable(world: RefCounted, expected_ms: int) -> bool:
	return bool(_clock.get("paused")) and not bool(_clock.call("has_pending_advance")) and int(_clock.get("elapsed_ms")) == expected_ms and int(world.get("elapsed_ms")) == expected_ms and int(world.get("target_ms")) == expected_ms


func _free_cell(world: RefCounted, center: Vector2i, excluded: Vector2i) -> Vector2i:
	var map_data: RefCounted = world.get("map_data")
	var construction: RefCounted = world.get("construction")
	var lifecycle: RefCounted = world.get("object_lifecycle")
	if map_data == null or construction == null or lifecycle == null:
		return Vector2i(-1, -1)
	var ground: RefCounted = lifecycle.get("ground")
	if ground == null:
		return Vector2i(-1, -1)
	for radius: int in range(1, 9):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var point: Vector2i = center + Vector2i(x, y)
				if point == excluded or not bool(map_data.call("terrain_is_walkable", point)) or bool(construction.call("blocked", point)):
					continue
				var placed: Dictionary = ground.call("can_place", "home", point)
				if bool(placed.get("ok", false)):
					return point
	return Vector2i(-1, -1)


func _arguments(args: PackedStringArray) -> Dictionary:
	var remaining: PackedStringArray = args.duplicate()
	if not remaining.has("--world-editor"):
		return {"ok": false, "reason": "expected --world-editor to enable the ordinary F8 editor"}
	remaining.remove_at(remaining.find("--world-editor"))
	if remaining.size() != 2 or remaining[0] != "--tag" or remaining[1].is_empty() or remaining[1].length() > 32:
		return {"ok": false, "reason": "expected --tag <1-32 safe characters> --world-editor"}
	for character: String in remaining[1]:
		if character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return {"ok": false, "reason": "invalid_tag"}
	return {"ok": true, "tag": remaining[1]}


func _fail(reason: String, detail: Dictionary = {}) -> void:
	_report["ok"] = false
	_report["first_failure"] = {"reason": reason, "detail": detail}
	print("WORLD_FIELDS_PRESENTATION_JSON:" + JSON.stringify(_report, "", true, true))
	if is_instance_valid(_main):
		_main.free()
		_main = null
	quit(1)
