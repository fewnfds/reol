extends "res://tests/cultivation_ui_smoke.gd"

func _run() -> void:
	game = Game.new() # Product default: no developer actor count or fixture load.
	game.controls.bindings.config_path = "user://settlement-ui-controls.cfg"
	game.feedback.config_path = "user://settlement-ui-feedback.cfg"
	game.paused = true; game.runner.control(true, 1)
	root.add_child(game); current_scene = game; root.grab_focus()
	check(await until(func(): return game.frame != null, 8000), "Normal hundred-resident opening never published its first frame")
	if game.frame == null: game.queue_free(); quit(1); return
	check(game.frame.ids.size() == 100 and game.frame.player.inventory.is_empty() and game.frame.practice_mode.is_empty(), "Normal main scene inherited a developer fixture")
	await capture("settlement-normal-start")
	game.controls.action("context", {})
	game.controls._select(8, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == 8), "Normal NPC could not be inspected")
	game.controls.action("character", {})
	check(await until(func(): return game.ui.character != null and game.ui.character.subject_id == 8), "Normal NPC character view did not open")
	var bar: TabBar = game.ui.character._tabs.get_tab_bar()
	await process_frame; await process_frame
	var point: Vector2 = bar.get_global_transform_with_canvas() * bar.get_tab_rect(1).get_center()
	await mouse(MOUSE_BUTTON_LEFT, true, point); await mouse(MOUSE_BUTTON_LEFT, false, point)
	check(game.ui.character._practice.text.contains("木息法"), "Normal initial mentor was not an actual practitioner")
	await capture("settlement-normal-character")
	game.ui._drawer_name = ""; game.ui._drawer_panel.hide()
	await resume()
	check(await until(func(): return game.frame.world_ms >= 5000, 8000), "Normal autonomous world did not advance")
	await pause()
	var path: String = "user://settlement-ui-fixture.reol"
	var sequence: int = game.runner.send({"kind": "save", "path": path})
	check(await until(func(): return game._last_receipt.contains("save #%d " % sequence) and game._last_receipt.ends_with(": saved")), "Normal hundred-resident world could not write an actual save")
	var epoch: int = game.frame.epoch
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch, 5000), "Normal hundred-resident save could not actually reload")
	check(game.frame.ids.size() == 100 and game.frame.player.inventory.is_empty(), "Reload respawned developer gifts or lost residents")
	await capture("settlement-normal-restored")
	game.queue_free(); await process_frame; await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://settlement-ui-controls.cfg", "user://settlement-ui-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("SETTLEMENT_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
