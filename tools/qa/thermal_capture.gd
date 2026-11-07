extends SceneTree
## Native two-process thermal evidence. All gameplay uses ordinary load/clock/save;
## the small QA label is developer-only observation, never player knowledge.

const ARCHIVE: String = "res://tests/fixtures/session_v32.json"
const SAVE: String = "res://logs/thermal_restart.json"
const EXPECTED: String = "res://logs/thermal_expected.json"
const CELL: Vector2i = Vector2i(254, 255)
const COMPLETION_MS: int = 840050
const SAVE_MS: int = 900000
const FUTURE_MS: int = 1201000
var _main: Node
var _runtime: Node
var _clock: Node
var _codec: Variant
var _phase: String
var _report: Dictionary = {"observations": [], "screenshots": []}
var _label: Label


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--phase=write") == args.has("--phase=read"):
		_fail("choose one write/read phase")
		return
	_phase = "write" if args.has("--phase=write") else "read"
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	root.size = Vector2i(1600, 900)
	_runtime = _main._continuity
	_clock = root.get_node("GameClock")
	_codec = load("res://scripts/runtime/world_session_snapshot.gd")
	_clock.set_paused(true)
	if _runtime.load_game(ProjectSettings.globalize_path(ARCHIVE if _phase == "write" else SAVE)) != OK:
		_fail("ordinary loader rejected source")
		return
	var expected: Dictionary = {}
	if _phase == "write":
		if not _runtime.world_sim.artifacts.active.get("player", {}).get("verb") == "warm":
			_fail("original unfinished warm action missing")
			return
		_observe("unfinished")
		_clock.advance_msec(COMPLETION_MS - _clock.elapsed_ms)
		if _runtime.world_sim.environment_fields.receipts.size() != 1 or int(_runtime.world_sim.artifacts.objects.hearth_stone.charge) != 3:
			_fail("original finite source did not commit once")
			return
		_observe("source_completed")
		_prepare_view()
		await _capture("source_completed")
		_clock.advance_msec(SAVE_MS - _clock.elapsed_ms)
		_observe("before_save")
		if _runtime.save_game(ProjectSettings.globalize_path(SAVE)) != OK:
			_fail("ordinary saver failed")
			return
		expected = {"saved_digest": _digest(), "saved_ms": SAVE_MS}
	else:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED))
		if not parsed is Dictionary or parsed.get("saved_digest") != _digest():
			_fail("fresh-process complete saved snapshot differs")
			return
		expected = parsed
		_observe("fresh_process_loaded")
		_prepare_view()
		await _capture("fresh_process_loaded")
	_clock.advance_msec(FUTURE_MS - _clock.elapsed_ms)
	_observe("future_after_weather_boundary")
	if _runtime.world_sim.elapsed_ms != FUTURE_MS or _runtime.world_sim.target_ms != FUTURE_MS:
		_fail("future shared time retained an unexpected debt")
		return
	var future_digest: String = _digest()
	if _phase == "write":
		expected["future_digest"] = future_digest
		_write(EXPECTED, expected)
	elif expected.get("future_digest") != future_digest:
		_fail("fresh process future diverged from uninterrupted full session")
		return
	await _capture("future")
	_report.merge({"result": "passed", "phase": _phase, "saved_digest": expected.saved_digest,
		"future_digest": future_digest, "engine": Engine.get_version_info().string,
		"scope": "ordinary original source, climate, bodies, field and save/restart; QA label is developer omniscience"})
	_write("res://logs/thermal_%s.json" % _phase, _report)
	print("THERMAL_NATIVE ", _phase, " passed full future digest=", future_digest)
	quit(0)


func _observe(label: String) -> void:
	var world: RefCounted = _runtime.world_sim
	var heat: RefCounted = world.environment_fields
	var energy: int = 0
	for row: Dictionary in heat.cells.values():
		energy += int(row.energy)
	var row: Dictionary = {"label": label, "world_ms": world.elapsed_ms,
		"allocated_cells": heat.cells.size(), "offset_tenths": heat.current_tenths(CELL),
		"q": energy, "source_input": heat.input_energy, "ambient_in": heat.ambient_in,
		"outside_out": heat.loss_energy, "charge": world.artifacts.objects.hearth_stone.charge,
		"sample_mode": heat.last_sample_mode, "sample_ms": heat.last_sample_ms,
		"background": SimClimateRules.background_at(world._content.climate, world.weather.definitions,
			world.weather.epoch_ms, CELL, world.elapsed_ms)}
	row["conserved"] = energy + int(heat.loss_energy) == int(heat.input_energy) + int(heat.ambient_in)
	_report.observations.append(row)
	if not bool(row.conserved):
		_fail("energy ledger diverged")


func _prepare_view() -> void:
	for layer: Node in _main.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	_runtime.object_adapter.get_parent().show()
	_runtime.object_adapter.select_object("hearth_stone")
	# Only the original object panel is shown, plus explicitly marked QA data.
	for layer: Node in _runtime.object_adapter.find_children("*", "CanvasLayer", true, false):
		layer.visible = true
	_main.camera.follow_focus = false
	_main.camera.zoom = Vector2(1.5, 1.5)
	_main.camera.global_position = TileGrid.cell_to_world(CELL) + Vector2(120, 0)
	_main.camera._clamp_to_world()
	var layer := CanvasLayer.new()
	layer.layer = 100
	_main.add_child(layer)
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_label)


func _capture(label: String) -> void:
	if _label != null:
		var row: Dictionary = _report.observations[-1]
		_label.text = "THERMAL QA (developer observation)\n%s | t=%d ms | cells=%d | local delta=%.1f C\nQ + outside_out = source + outside_in: %s" % [
			label, int(row.world_ms), int(row.allocated_cells), float(row.offset_tenths) / 10.0, str(row.conserved)]
	await create_timer(0.15, true).timeout
	for frame: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "res://logs/thermal_%s_%s.png" % [_phase, label]
	var pixels: Image = root.get_texture().get_image()
	if pixels == null or pixels.save_png(path) != OK:
		_fail("native screenshot failed")
		return
	_report.screenshots.append(path)


func _digest() -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(_codec.capture(_runtime))).sha256_text()


func _write(path: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("QA file write failed")
		return
	file.store_string(JSON.stringify(data, "\t", true))
	file.close()


func _fail(message: String) -> void:
	printerr("THERMAL_NATIVE_FAILED ", _phase, " ", message)
	quit(1)
