extends SceneTree
## Native-size views of the genuine earned preparation; only the view is posed.


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var runtime: Node = main._continuity
	var error: Error = runtime.load_game(ProjectSettings.globalize_path("res://logs/conflict_inflight.json"))
	if error != OK:
		printerr("Conflict visual source failed: ", error)
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	root.position = Vector2i.ZERO
	main.camera.global_position = main.player.global_position
	var clock: Node = root.get_node("GameClock")
	clock.set_paused(true)
	runtime.conflict_adapter.panel.show()
	runtime.conflict_adapter.refresh()
	if not await _picture("res://logs/conflict_native_methods_1280.png"):
		quit(1)
		return
	runtime.conflict_adapter.panel.hide()
	clock.advance_msec(350)
	if runtime.world_sim.conflicts.projectiles.is_empty() or not await _picture("res://logs/conflict_native_projectile_1280.png"):
		printerr("Conflict visual lacks an actual emitted projectile")
		quit(1)
		return
	print("Conflict native views: earned source, actual methods and projectile, 1280x720")
	quit(0)


func _picture(path: String) -> bool:
	for _frame: int in 36:
		await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	var error: Error = picture.save_png(path)
	print("Conflict native capture ", path, " ", picture.get_size(), " save=", error)
	return error == OK and picture.get_size() == Vector2i(1280, 720)
