extends SceneTree
## Render the real product and real commands, using genuine source histories.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var clock: Node = root.get_node("GameClock")
	clock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	root.size = Vector2i(1280, 720)
	var runtime: Node = main._continuity
	var helper: RefCounted = load("res://tests/runtime/helpers/drawing_replay.gd").new()
	var research: Dictionary = helper.prepare_research(runtime)
	if not bool(research.get("ok", false)):
		printerr("DRAWING actual preparation failed ", research)
		quit(1)
		return
	runtime.object_adapter.select_object(helper.RING)
	main.camera.global_position = main.player.global_position + Vector2(370, 140)
	if not await _capture("research"):
		quit(1)
		return
	var drawing: Dictionary = helper.prepare_draw(runtime)
	if not bool(drawing.get("ok", false)):
		printerr("DRAWING actual draw failed ", drawing)
		quit(1)
		return
	runtime.object_adapter.select_object(helper.RING)
	main.camera.global_position = main.player.global_position + Vector2(370, 140)
	if not await _capture("inflight"):
		quit(1)
		return
	if not helper._finish_artifact(runtime):
		quit(1)
		return
	runtime.object_adapter.select_object(helper.RING)
	if not await _capture("completed"):
		quit(1)
		return
	runtime.object_adapter.panel.hide()
	runtime.capability_adapter.show_panel()
	runtime.capability_adapter._select("drawing_ring")
	if not await _capture("source"):
		quit(1)
		return
	var snapshots: GDScript = load("res://scripts/runtime/world_session_snapshot.gd")
	print("DRAWING native candidate ", not snapshots.stage(runtime, snapshots.capture(runtime)).is_empty())
	quit(0)


func _capture(label: String) -> bool:
	for _frame: int in 450:
		await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	var path: String = "res://docs/qa/drawing_%s_20261104.png" % label
	var ok: bool = picture.get_size() == Vector2i(1280, 720) and picture.save_png(path) == OK
	print("DRAWING native ", label, " ", picture.get_size(), " saved=", ok)
	return ok
