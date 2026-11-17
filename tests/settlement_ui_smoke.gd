extends "res://tests/cultivation_ui_smoke.gd"

func capture(name_key: String) -> void:
	var directory: String = "res://logs/settlement-ui/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + name_key + ".png")

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
	check(await until(func(): return game.ui.character._header.text.contains("传功弟子")), "Normal NPC detail view never refreshed")
	check(game.ui.character._header.text.contains("传功弟子") and game.ui.character._overview.text.contains("青禾宗") and game.ui.character._overview.text.contains("床榻"), "Normal fellow member lost their identity, institutional membership or assigned rest place")
	check(not game.ui.character._bag.visible and not game.ui.character._stats.text.contains("HP") and game.ui.character.events.text == "暂无可知记录。", "Normal observation opened another person's private bag, exact vitals or personal journal")
	var bar: TabBar = game.ui.character._tabs.get_tab_bar()
	await process_frame; await process_frame
	var point: Vector2 = bar.get_global_transform_with_canvas() * bar.get_tab_rect(1).get_center()
	await mouse(MOUSE_BUTTON_LEFT, true, point); await mouse(MOUSE_BUTTON_LEFT, false, point)
	check(game.ui.character._practice.text.contains("木息法"), "Normal initial mentor was not an actual practitioner")
	check(not game.ui.character._practice.text.contains("灵力") and not game.ui.character._practice.text.contains("理解"), "Public instruction revealed the mentor's private cultivation values")
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
	game.controls._select(1, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == 1), "Player inspection did not replace the old NPC frame")
	game.controls.action("character", {})
	check(await until(func(): return game.ui.character != null and game.ui.character.subject_id == 1), "The player's normal overview did not reopen after file load")
	check(await until(func(): return game.ui.character._overview.text.contains("青禾宗")), "The player's normal overview never refreshed")
	check(game.ui.character._overview.text.contains("青禾宗") and game.ui.character._overview.text.contains("床榻") and game.ui.character._activity.text.contains("亲自操作"), "The player could not identify their membership, residence or current control mode")
	root.size = Vector2i(1280, 720); game.ui.apply_scale(125, false)
	await process_frame; await process_frame
	check(game.ui.character._tabs.get_tab_bar().get_global_transform_with_canvas().origin.y < root.size.y and game.ui.character._tabs.get_child(0) is ScrollContainer, "Scaled normal character view lost accessible tabs or scrolling")
	await capture("settlement-normal-restored")
	game.queue_free(); await process_frame; await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://settlement-ui-controls.cfg", "user://settlement-ui-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("SETTLEMENT_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
