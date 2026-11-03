extends SceneTree
## Native views of real earned training and original moving guard archives.


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	root.size = Vector2i(1280, 720)
	root.position = Vector2i.ZERO
	var runtime: Node = main._continuity
	var clock: Node = root.get_node("GameClock")
	for kind: String in ["practice", "learned", "guard"]:
		var archive: String = "res://tests/fixtures/session_v39_guard.json" if kind == "guard" else "res://tests/fixtures/session_v39.json"
		if runtime.load_game(ProjectSettings.globalize_path(archive)) != OK:
			printerr("Native capability source load refused ", kind)
			quit(1)
			return
		clock.set_paused(true)
		if kind == "learned":
			clock.advance_msec(int(runtime.world_sim.capability_practice.active.player.complete_ms) - int(clock.elapsed_ms))
		main.camera.global_position = main.player.global_position
		if kind != "guard":
			runtime.capability_adapter.show_panel()
		else:
			runtime.capability_adapter.panel.hide()
			runtime.conflict_adapter.panel.hide()
		for _frame: int in 24:
			await process_frame
		await RenderingServer.frame_post_draw
		var picture: Image = root.get_texture().get_image()
		var path: String = "res://" + "docs/qa/capability_%s_20261104.png" % kind
		if picture.get_size() != Vector2i(1280, 720) or picture.save_png(path) != OK:
			printerr("Native capture wrong size or failed ", kind, " ", picture.get_size())
			quit(1)
			return
		print("Native capability ", kind, " ", picture.get_size(), " at ", clock.elapsed_ms)
	quit(0)
