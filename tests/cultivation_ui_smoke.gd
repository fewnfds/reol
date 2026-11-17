extends "res://tests/production_ui_smoke.gd"

func capture(name_key: String) -> void:
	var directory: String = "res://logs/cultivation-ui/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + name_key + ".png")

func _run() -> void:
	var w := World.new()
	w.initialize(4, 0)
	for actor: int in w.actor_slots:
		w.release(actor); w.objects.records[actor].autonomous = false; w.objects.records[actor].side = 0
		w.pages[0].modes[actor - 1] = w.Units.Mode.IDLE
		w.pages[0].positions[actor - 1] = Vector2(123.5 + actor, 126.5)
	var bed: int = w.facilities.create_completed(w, "cultivation_bed", w.Terrain.index(Vector2i(124, 124)))
	w.facilities.create_completed(w, "granary", w.Terrain.index(Vector2i(128, 124)))
	w.pages[0].positions[0] = Vector2(123.5, 124.5)
	w.flush_topology(); w.perception.update(w, 0, true)
	var path: String = "user://cultivation-ui-fixture.reol"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var({"format": SessionIO.FORMAT, "state": Persistence.capture(w)}, false); file.close()
	game = Game.new(); game._actors = 4; game.speed = 1
	game.controls.bindings.config_path = "user://cultivation-ui-controls.cfg"
	game.feedback.config_path = "user://cultivation-ui-feedback.cfg"
	game.paused = true; game.runner.control(true, 1)
	root.add_child(game); current_scene = game; root.grab_focus()
	check(await until(func(): return game.frame != null), "Cultivation normal frame absent")
	var epoch: int = game.frame.epoch
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "Actual cultivation file failed to load")
	var grain_before: int = int(game.frame.player.inventory.get("grain", 0))
	game.controls.action("context", {})
	await process_frame; await process_frame
	for cell: Vector2 in [Vector2(124.5, 124.5), Vector2(125.5, 124.5), Vector2(124.5, 125.5), Vector2(125.5, 125.5)]:
		var screen: Vector2 = game.view.project(cell * game.TILE, false)
		await mouse(MOUSE_BUTTON_LEFT, true, screen); await mouse(MOUSE_BUTTON_LEFT, false, screen)
		check(await until(func(): return game.ui._target.get("id", 0) == bed), "Native non-anchor bed click did not select the visible footprint: " + str(cell))
	await select_and_press(bed, "栽种灵稻")
	await resume()
	check(await until(func(): return game.frame.player.action.get("kind") == "sow_grain"), "Native planting button failed to enter the common operation")
	await pause()
	check(game.ui._inspect_values.text.contains("栽培水分"), "The cultivation host had no normal water feedback")
	await capture("sowing")
	var sequence: int = game.runner.send({"kind": "save", "path": path})
	check(await until(func(): return game._last_receipt.contains("save #%d " % sequence) and game._last_receipt.ends_with(": saved")), "Actual in-progress sowing file could not save")
	epoch = game.frame.epoch; game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch and game.frame.player.action.get("kind") == "sow_grain"), "Actual sowing host did not resume")
	game.controls._select(bed, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == bed), "Restored cultivation host could not be inspected")
	await resume()
	check(await until(func(): return game.frame.player.action.is_empty() and int(game.ui._target.get("occupant", 0)) > 0, 3000), "Restored planting did not actually create the crop")
	await pause()
	var plant: int = int(game.ui._target.get("occupant", 0))
	check(plant > 0 and int(game.frame.player.inventory.get("grain", 0)) == grain_before - 1, "Native planting did not consume exactly one seed")
	if plant > 0:
		await select_and_press(plant, "照料")
		var water: int = int(game.frame.player.inventory.get("water", 0))
		await resume()
		check(await until(func(): return game.frame.player.action.is_empty() and int(game.frame.player.inventory.get("water", 0)) == water - 1, 3000), "Native care did not spend actual water")
		await pause()
		check(command_button("照料") != null and command_button("照料").disabled and command_button("照料").tooltip_text.contains("无需补水"), "Full healthy plant care did not explain why it is disabled")
		check(game.ui._inspect_values.text.contains("适水已足"), "Native crop inspection did not show actual soil condition")
		await capture("watered-crop")
	game.queue_free(); await process_frame; await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://cultivation-ui-controls.cfg", "user://cultivation-ui-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("CULTIVATION_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
