extends SceneTree
## Native 1280x720 capture through the real saved source and actual UI.


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var runtime: Node = main._continuity
	var error: Error = runtime.load_game(ProjectSettings.globalize_path("res://tests/fixtures/session_v34.json"))
	if error != OK:
		printerr("Spirit visual source failed: ", error)
		quit(1)
		return
	root.get_node("GameClock").set_paused(true)
	if not runtime.spirit_adapter.show_panel("hearth_stone"):
		printerr("Actual source panel did not open")
		quit(1)
		return
	for frame: int in 8:
		await process_frame
	var picture: Image = root.get_texture().get_image()
	error = picture.save_png("res://logs/spirit_source_native_1280.png")
	print("Spirit source native visual: ", picture.get_size(), ", save=", error)
	quit(0 if error == OK and picture.get_size() == Vector2i(1280, 720) else 1)
