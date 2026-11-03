extends SceneTree
## Native-size views of an actual normal walk behind the records-office wall.


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var runtime: Node = main._continuity
	var error: Error = runtime.load_game(ProjectSettings.globalize_path("res://logs/perception_hidden.json"))
	if error != OK:
		printerr("Perception visual source failed: ", error)
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	root.position = Vector2i.ZERO
	main.camera.global_position = main.player.global_position
	var clock: Node = root.get_node("GameClock")
	clock.set_paused(true)
	var domain: RefCounted = runtime.world_sim.conflicts
	var row: Dictionary = domain.conflicts[domain.conflict_for("player")]
	var perception: Script = load("res://scripts/sim/conflict_perception.gd")
	if bool(perception.cues(domain, row, str(row.defender)).visible) or row.people.chen_shouzhuo.sight.is_empty():
		printerr("Perception visual is not a genuinely hidden remembered opponent")
		quit(1)
		return
	if not await _picture("res://logs/perception_native_hidden_1280.png"):
		quit(1)
		return
	clock.advance_msec(1700)
	main.camera.global_position = main.player.global_position
	if not await _picture("res://logs/perception_native_search_1280.png"):
		quit(1)
		return
	print("Perception native views: ordinary door/wall walk, old sight, actual search, 1280x720")
	quit(0)


func _picture(path: String) -> bool:
	for _frame: int in 36:
		await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	var error: Error = picture.save_png(path)
	print("Perception native capture ", path, " ", picture.get_size(), " save=", error)
	return error == OK and picture.get_size() == Vector2i(1280, 720)
