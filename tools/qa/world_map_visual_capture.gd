extends SceneTree
## Native view after the ordinary loader commits an independent map.


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var runtime: Node = main._continuity
	var error: Error = runtime.load_game(ProjectSettings.globalize_path("res://tests/fixtures/session_v34.json"))
	if error != OK:
		printerr("Map visual source failed: ", error)
		quit(1)
		return
	var clock: Node = root.get_node("GameClock")
	clock.set_paused(true)
	clock.advance_msec(1020050 - int(clock.elapsed_ms))
	root.size = Vector2i(1280, 720)
	root.position = Vector2i.ZERO
	for frame: int in 32:
		await process_frame
	var picture: Image = root.get_texture().get_image()
	error = picture.save_png("res://logs/world_map_native_1280.png")
	var same_map: bool = runtime.world_sim.map_data == main.world.map_data()
	print("World map native visual: ", picture.get_size(), ", save=", error, ", view_uses_session_map=", same_map)
	quit(0 if error == OK and same_map and picture.get_size() == Vector2i(1280, 720) else 1)
