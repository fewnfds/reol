extends SceneTree
## Native 1280x720 views of ordinary, immutable in-progress worlds.


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
	for view: String in ["warning", "explained", "conflict"]:
		var archive: String = "res://tests/fixtures/session_v38%s.json" % ("" if view == "warning" else "_" + view)
		if runtime.load_game(ProjectSettings.globalize_path(archive)) != OK:
			printerr("Care native view refused original ", view)
			quit(1)
			return
		clock.set_paused(true)
		main.camera.global_position = main.player.global_position
		runtime.object_adapter.panel.hide()
		runtime.interaction_adapter.panel.hide()
		if view == "warning":
			# Reproduce normal source UI still being open when the person speaks.
			if not runtime.spirit_adapter.select_source("hearth_seam"):
				printerr("Care warning capture could not open original source view")
				quit(1)
				return
			runtime.interaction_adapter._heard_care_alerts.clear()
			runtime.interaction_adapter.receive_current_care_alerts()
			if runtime.spirit_adapter.panel.visible or not runtime.interaction_adapter.panel.visible or not runtime.world_sim.spirit_sources.owns_actor("player"):
				printerr("Care warning UI did not reveal itself while preserving actual channel")
				quit(1)
				return
		elif view == "explained":
			runtime.interaction_adapter.show_panel()
			var entry: Dictionary = runtime.world_sim.source_care.explanations.values().front()
			var ui: Node = runtime.interaction_adapter
			for index: int in ui.receiver_choice.item_count:
				if ui.receiver_choice.get_item_metadata(index) == runtime.world_sim.embodiment.subject_for_actor(str(entry.receiver)):
					ui.receiver_choice.select(index)
			for index: int in ui.verb_choice.item_count:
				if ui.verb_choice.get_item_metadata(index) == "explain_source":
					ui.verb_choice.select(index)
			ui.rebuild_choices()
			for index: int in ui.object_choice.item_count:
				if ui.object_choice.get_item_metadata(index).get("id") == entry.basis:
					ui.object_choice.select(index)
			runtime.interaction_adapter._receipt = {"domain": "source_care", "id": entry.id, "performer": runtime.world_sim.embodiment.subject_for_actor(str(entry.receiver))}
			runtime.interaction_adapter._reply.text = runtime.world_sim.source_care.definitions.labels.accepted
			runtime.interaction_adapter.refresh_progress()
		else:
			runtime.conflict_adapter.refresh()
		if not await _picture("source_care_%s_20261104.png" % view):
			quit(1)
			return
	print("Care native views: actual received warning, accepted explanation and paid NPC-initiated action, 1280x720")
	quit(0)


func _picture(filename: String) -> bool:
	for _frame: int in 24:
		await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	var error: Error = picture.save_png("res://docs/qa/" + filename)
	print("Care capture ", filename, " ", picture.get_size(), " save=", error)
	return error == OK and picture.get_size() == Vector2i(1280, 720)
