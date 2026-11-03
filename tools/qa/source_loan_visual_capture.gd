extends SceneTree
## Native presentation captures of genuine ordinary in-progress archives.


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
	if runtime.load_game(ProjectSettings.globalize_path("res://tests/fixtures/session_v37.json")) != OK:
		printerr("Source-loan native view could not load original source process")
		quit(1)
		return
	clock.set_paused(true)
	main.camera.global_position = main.player.global_position
	if not runtime.spirit_adapter.show_panel("hearth_stone") or not await _picture("source_loan_channel_20261104.png"):
		quit(1)
		return
	if runtime.load_game(ProjectSettings.globalize_path("res://tests/fixtures/session_v37_inspection.json")) != OK:
		printerr("Source-loan native view could not load actual inspector journey")
		quit(1)
		return
	clock.set_paused(true)
	main.camera.global_position = main.player.global_position
	var ui: Node = runtime.interaction_adapter
	ui.show_panel()
	for index: int in ui.receiver_choice.item_count:
		if ui.receiver_choice.get_item_metadata(index) == "subject:chen_shouzhuo":
			ui.receiver_choice.select(index)
	for index: int in ui.verb_choice.item_count:
		if ui.verb_choice.get_item_metadata(index) == "verify_return":
			ui.verb_choice.select(index)
	ui.rebuild_choices()
	ui.refresh_progress()
	if not await _picture("source_loan_inspection_20261104.png"):
		quit(1)
		return
	print("Source-loan native views: original source process and issuer inspection, 1280x720")
	quit(0)


func _picture(filename: String) -> bool:
	for _frame: int in 24:
		await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	var error: Error = picture.save_png("res://docs/qa/" + filename)
	print("Source-loan capture ", filename, " ", picture.get_size(), " save=", error)
	return error == OK and picture.get_size() == Vector2i(1280, 720)
