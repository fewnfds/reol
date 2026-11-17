extends "res://tests/production_ui_smoke.gd"

func capture(name_key: String) -> void:
	var directory: String = "res://logs/institution-ui/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + name_key + ".png")

func _run() -> void:
	var w := World.new()
	w.initialize(4, 0)
	for actor: int in w.actor_slots:
		w.release(actor); w.objects.records[actor].autonomous = false; w.objects.records[actor].side = 0
		w.pages[0].modes[actor - 1] = w.Units.Mode.IDLE
	var org: int = w.institutions.create("青禾宗")
	w.institutions.admit(w, org, 1, ["rest"]); w.institutions.admit(w, org, 4, ["rest"])
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(124, 124)))
	var bed: int = w.facilities.create_completed(w, "wood_bed", w.Terrain.index(Vector2i(124, 127)))
	for target: int in [chest, bed]: w.objects.records[target].organization = org
	w.objects.add(chest, "grain", 2, w.objects.Stock.right(0, org))
	w.institutions.appoint(w, org, 1, "kitchen_craft", [chest])
	w.institutions.arrange_service(w, bed, "rest", [4])
	w.pages[0].positions[0] = Vector2(123.5, 124.5)
	w.flush_topology(); w.perception.update(w, 0, true)
	var path: String = "user://institution-ui-fixture.reol"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var({"format": SessionIO.FORMAT, "state": Persistence.capture(w)}, false); file.close()
	game = Game.new(); game._opening = "development"; game._actors = 4
	game.controls.bindings.config_path = "user://institution-ui-controls.cfg"
	game.feedback.config_path = "user://institution-ui-feedback.cfg"
	game.paused = true; game.runner.control(true, 1)
	root.add_child(game); current_scene = game
	check(await until(func(): return game.frame != null), "Institution GUI initial frame absent")
	var epoch: int = game.frame.epoch
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "Real role/service file failed to load")
	game.controls._select(chest, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == chest), "Scoped chest not inspected")
	game.controls.action("take", {"target": chest})
	check(await until(func(): return game.ui.inventory.visible), "Scoped inventory workspace missing")
	var panel: Control = game.ui.inventory
	var selected: int = -1
	for index: int in panel._purpose.item_count:
		if panel._purpose.get_item_metadata(index).get("purpose", "") == "cook": selected = index
	check(selected > 0, "Scoped kitchen authority was missing from the native purpose selector")
	if selected > 0: panel._purpose.select(selected)
	panel.container.select("grain"); panel.amount.value = 2
	await process_frame; await process_frame
	check(not panel._take.disabled, "Scoped grain choice was disabled: " + str(panel._subject))
	await click(panel._take)
	check(await until(func(): return game.frame.player.action.get("purpose", "") == "cook"), "Native scoped issue lost its selected purpose")
	await resume()
	check(await until(func(): return game.frame.player.action.is_empty()), "Scoped native issue did not finish")
	await pause()
	panel.bag.select("grain")
	check(await until(func(): return panel._choice.text.contains("受托 2")), "Native scoped pickup did not receive actual entrusted grain")
	await capture("scoped-issue")
	panel.hide(); game.controls._select(bed, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == bed and command_button("休息") != null), "Assigned bed operation was not shown")
	var button: Button = command_button("休息")
	check(button != null and button.disabled, "Ordinary UI allowed an unassigned member to sleep in the assigned bed")
	await capture("assigned-bed")
	var sequence: int = game.runner.send({"kind": "save", "path": path})
	check(await until(func(): return game._last_receipt.contains("save #%d " % sequence) and game._last_receipt.ends_with(": saved")), "Real role/service save failed")
	epoch = game.frame.epoch; game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "Role/service candidate did not return through normal I/O")
	game.queue_free(); await process_frame; await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://institution-ui-controls.cfg", "user://institution-ui-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("INSTITUTION_ACCESS_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
