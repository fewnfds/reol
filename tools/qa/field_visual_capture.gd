extends SceneTree
## Native views from actual earned field archives, not generated mock states.


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	root.size = Vector2i(1280, 720)
	root.position = Vector2i.ZERO
	var runtime: Node = main._continuity
	var helper: RefCounted = load("res://tests/runtime/helpers/field_replay.gd").new()
	var clock: Node = root.get_node("GameClock")
	for kind: String in ["early_site", "claimed_ring", "npc_at_site", "late_empty"]:
		var archive: String = helper.NPC_ARCHIVE if kind in ["npc_at_site", "late_empty"] else helper.TRIP_ARCHIVE
		if runtime.load_game(ProjectSettings.globalize_path(archive)) != OK:
			printerr("FIELD native source load refused ", kind)
			quit(1)
			return
		clock.set_paused(true)
		if kind == "late_empty":
			var reply: Dictionary = helper.replay_npc(runtime, "visual_late", archive)
			if not bool(reply.get("ok", false)):
				quit(1)
				return
		if kind == "npc_at_site":
			clock.advance_msec(17000)
		if kind == "npc_at_site" and (not helper._ask(runtime, {"steps": []}) or not runtime.travel_to_site("broken_stele")):
			printerr("FIELD native actual site journey refused")
			quit(1)
			return
		if not helper._finish_trip(runtime):
			printerr("FIELD native actual journey did not arrive")
			quit(1)
			return
		if kind == "claimed_ring":
			if not runtime.object_adapter.select_object(helper.RING) or not runtime.object_adapter.submit("take").ok:
				quit(1)
				return
			clock.advance_msec(int(runtime.world_sim.artifacts.active.player.due_ms) - int(clock.elapsed_ms))
		helper._senses(runtime)
		main.camera.global_position = main.player.global_position + Vector2(370, 140)
		runtime.field_adapter.show_panel()
		if kind == "claimed_ring":
			runtime.field_adapter.panel.hide()
			runtime.object_adapter.select_object(helper.RING)
		for _frame: int in 450:
			await process_frame
		await RenderingServer.frame_post_draw
		var picture: Image = root.get_texture().get_image()
		var path: String = "res://" + "docs/qa/field_%s_20261104.png" % kind
		if picture.get_size() != Vector2i(1280, 720) or picture.save_png(path) != OK:
			printerr("FIELD native capture failed ", kind, " ", picture.get_size())
			quit(1)
			return
		print("FIELD native ", kind, " ", picture.get_size(), " at ", clock.elapsed_ms)
	quit(0)
