extends "res://tests/cultivation_ui_smoke.gd"

func capture(name_key: String) -> void:
	var directory: String = "res://logs/settlement-ui/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + name_key + ".png")

func gallery_preview() -> void:
	var gallery_button: Button
	for button: Button in game._debug_console.find_children("*", "Button", true, false):
		if button.text == "图鉴": gallery_button = button; break
	check(gallery_button != null, "Debug tools omitted the gallery entry")
	if gallery_button == null: return
	await click(gallery_button)
	var gallery: CanvasLayer = game.art_gallery
	check(gallery.is_open() and game.controls.locked(), "Debug tools did not open a modal gallery")
	if not gallery.is_open(): return
	var tabs: TabContainer = gallery._tabs
	var bar: TabBar = tabs.get_tab_bar()
	var female_point: Vector2 = bar.get_global_transform_with_canvas() * bar.get_tab_rect(1).get_center()
	await mouse(MOUSE_BUTTON_LEFT, true, female_point)
	await mouse(MOUSE_BUTTON_LEFT, false, female_point)
	check(tabs.current_tab == 1 and gallery._actor_tabs[1][0].texture.region.position.y >= 768, "Female tab failed to select the female atlas rows")
	await capture("settlement-gallery-female-%d" % game.ui.ui_percent)
	var atlas_point: Vector2 = bar.get_global_transform_with_canvas() * bar.get_tab_rect(tabs.get_tab_count() - 1).get_center()
	await mouse(MOUSE_BUTTON_LEFT, true, atlas_point)
	await mouse(MOUSE_BUTTON_LEFT, false, atlas_point)
	check(tabs.current_tab == tabs.get_tab_count() - 1 and tabs.get_current_tab_control().get_child(0).item_count == 3, "Gallery did not expose all three original atlases")
	await key(KEY_ESCAPE, true); await key(KEY_ESCAPE, false)
	check(not gallery.is_open() and not gallery.is_processing(), "Escape failed to close the gallery and stop its animation")
	await key(KEY_F8, true); await key(KEY_F8, false)
	check(gallery.is_open(), "F8 failed to reopen the gallery")
	var close_button: Button = gallery._panel.find_children("*", "Button", true, false)[0]
	await mouse(MOUSE_BUTTON_LEFT, true, close_button.get_global_rect().get_center())
	await mouse(MOUSE_BUTTON_LEFT, false, close_button.get_global_rect().get_center())
	check(not gallery.is_open(), "Clicking the gallery close button did not close it")


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
	await gallery_preview()
	game.controls.action("context", {})
	game.controls._select(8, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == 8 and game.ui._target.get("observed_other", false)), "Normal NPC could not be inspected")
	var resident: Dictionary = game.ui._target
	check(game.ui._inspect_title.text.begins_with(str(resident.get("name", "")) + " #8") and resident.get("resident_title") == "传功弟子", "Normal NPC inspection lost the resident's identity")
	check(resident.get("memberships", []).any(func(entry: Dictionary): return entry.get("name") == "青禾宗") and not resident.get("service_targets", {}).get("rest", []).is_empty(), "Normal fellow member lost their membership or assigned rest place")
	check(resident.get("teaches", {}).has("wood_breath") and not resident.has("methods") and not resident.has("inventory") and not resident.has("events"), "Normal NPC inspection lost public instruction or opened private data")
	await capture("settlement-normal-character")
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
	await gallery_preview()
	game.queue_free(); await process_frame; await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://settlement-ui-controls.cfg", "user://settlement-ui-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("SETTLEMENT_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
