extends SceneTree
## Capture the ordinary scene at native 1280x720, outside editor embedding.


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var runtime: Node = main._continuity
	var error: Error = runtime.load_game(ProjectSettings.globalize_path("res://tests/fixtures/session_v33.json"))
	if error != OK:
		printerr("Herb visual source failed: ", error)
		quit(1)
		return
	var clock: Node = root.get_node("GameClock")
	clock.set_paused(true)
	runtime.service_adapter.panel._select_page(5)
	for frame: int in 8:
		await process_frame
	var picture: Image = root.get_texture().get_image()
	error = picture.save_png("res://logs/herb_ecology_native_1280.png")
	print("Herb native visual: ", picture.get_size(), ", save=", error)
	quit(0 if error == OK and picture.get_size() == Vector2i(1280, 720) else 1)
