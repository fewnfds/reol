extends "res://tests/institution_access_ui_smoke.gd"

func _run() -> void:
	var w := World.new()
	w.initialize(4, 0)
	for actor: int in w.actor_slots:
		w.release(actor); w.objects.records[actor].autonomous = false; w.objects.records[actor].side = 0
		w.pages[0].modes[actor - 1] = w.Units.Mode.IDLE
		w.pages[0].positions[actor - 1] = Vector2(122.5 + actor, 124.5)
		w.pages[0].energy[actor - 1] = 10000; w.pages[0].hunger[actor - 1] = 10000
	w.objects.add(1, "wood", 3)
	var site: Dictionary = w.facilities.blueprint(w, 1, "wood_wall", w.Terrain.index(Vector2i(127, 126)))
	check(site.reason == "accepted", "Formal help GUI fixture could not place real materials")
	if site.reason != "accepted": quit(1); return
	w.objects.records[site.target].remaining_ms = 5000
	w.flush_topology(); w.perception.update(w, 0, true)
	var path: String = "user://institution-matters-ui-fixture.reol"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var({"format": SessionIO.FORMAT, "state": Persistence.capture(w)}, false); file.close()
	game = Game.new(); game._actors = 4; game.speed = 4
	game.controls.bindings.config_path = "user://institution-matters-ui-controls.cfg"
	game.feedback.config_path = "user://institution-matters-ui-feedback.cfg"
	game.paused = true; game.runner.control(true, 4)
	root.add_child(game); current_scene = game; root.grab_focus()
	check(await until(func(): return game.frame != null), "Formal matter GUI had no initial frame")
	var epoch: int = game.frame.epoch
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "Actual formal help fixture did not load")
	await select_and_press(int(site.target), "协作")
	check(game.controls.tool == "worker", "Native help button did not request a recipient")
	game.camera.force_update_scroll()
	var point: Vector2 = game.view.project(game._displayed(2) * game.TILE + Vector2(0, -16), false)
	check(2 in game.controls.pick(game.controls.pointer_world(point), false), "Helper's visible torso was not pickable")
	await mouse(MOUSE_BUTTON_LEFT, true, point); await mouse(MOUSE_BUTTON_LEFT, false, point)
	check(await until(func(): return game.frame.player.action.get("kind") == "request_help"), "Real scene click did not send the chosen helper")
	await resume()
	game.controls._select(2, -1)
	check(await until(func(): return not game.frame.inspected.get("responsibilities", {}).is_empty()), "The native interaction never created the helper's real responsibility")
	await pause()
	check(game.frame.inspected.get("action", {}).get("kind", "") in ["", "construct"] and not game.frame.inspected.has("commitment"), "Normal inspection kept legacy duplicate promise state")
	await capture("accepted-formal-help")
	var sequence: int = game.runner.send({"kind": "save", "path": path})
	check(await until(func(): return game._last_receipt.contains("save #%d " % sequence) and game._last_receipt.ends_with(": saved")), "Formal obligation was not actually saved")
	epoch = game.frame.epoch; game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "Formal obligation failed normal file restoration")
	await resume()
	game.controls._select(int(site.target), -1)
	check(await until(func(): return game.frame.inspected.get("id", 0) == site.target and game.frame.inspected.get("kind") == "wall", 4500), "Restored helper did not finish the same construction through the live game")
	await pause(); await capture("completed-formal-help")
	game.queue_free(); await process_frame; await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://institution-matters-ui-controls.cfg", "user://institution-matters-ui-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("INSTITUTION_MATTERS_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
