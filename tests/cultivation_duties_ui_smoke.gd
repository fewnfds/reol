extends "res://tests/cultivation_ui_smoke.gd"

func _run() -> void:
	var w := World.new()
	w.initialize(4, 0)
	for actor: int in w.actor_slots:
		w.release(actor); w.objects.records[actor].autonomous = false; w.objects.records[actor].side = 0
		w.livelihood.forget(actor)
		w.pages[0].modes[actor - 1] = w.Units.Mode.IDLE
		w.pages[0].positions[actor - 1] = Vector2(123.5 + actor % 2, 124.5 + actor / 2)
	var org: int = w.institutions.create("青禾宗")
	w.institutions.admit(w, org, 1, [])
	w.institutions.admit(w, org, 3, [])
	var bed: int = w.facilities.create_completed(w, "cultivation_bed", w.Terrain.index(Vector2i(125, 124)))
	var store: int = w.facilities.create_completed(w, "granary", w.Terrain.index(Vector2i(122, 124)))
	var well: int = w.facilities.create_completed(w, "water_well", w.Terrain.index(Vector2i(122, 127)))
	for target: int in [bed, store, well]: w.objects.records[target].organization = org
	w.objects.add(store, "grain", 1, w.objects.Stock.right(0, org))
	w.flush_topology()
	w.objects.records[3].autonomous = true
	for target: int in [bed, store, well]: w.knowledge.seed(w, 3, w.operation_target(target), 0)
	check(w.institutions.appoint(w, org, 3, "field_cultivator", [bed, store, well], {"sites": [bed], "sources": [store, well], "destination": store}) > 0, "Native field fixture role refused")
	w.decisions.resume(w, 3, 0); w.decisions.prepare(w, 0)
	while w.elapsed_ms < 10000:
		w.step(16)
		if w.actions.get(3, {}).get("kind") == "sow_grain" and int(w.actions[3].get("started_ms", 0)) > 0: break
	check(w.actions.get(3, {}).get("kind") == "sow_grain" and w.objects.records[bed].guest == 0, "NPC did not actually source and begin planting before GUI load")
	w.perception.update(w, w.elapsed_ms, true)
	var path: String = "user://cultivation-duties-ui-fixture.reol"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var({"format": SessionIO.FORMAT, "state": Persistence.capture(w)}, false); file.close()
	game = Game.new(); game._opening = "development"; game._actors = 4; game.speed = 1
	game.controls.bindings.config_path = "user://cultivation-duties-ui-controls.cfg"
	game.feedback.config_path = "user://cultivation-duties-ui-feedback.cfg"
	game.paused = true; game.runner.control(true, 1)
	root.add_child(game); current_scene = game; root.grab_focus()
	check(await until(func(): return game.frame != null), "Field GUI initial frame absent")
	var epoch: int = game.frame.epoch
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "Actual field appointment/in-progress host file could not load")
	game.controls._select(3, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == 3), "Native NPC inspection failed")
	check(await until(func(): return game.ui._inspect_panel.visible and game.ui._inspect_values.text.contains("栽种灵稻")), "Normal NPC inspection did not describe autonomous field work")
	check(await until(func(): return game.ui._inspect_values.text.contains("灵田照管")), "Normal NPC inspection did not explain the source of field responsibility")
	await capture("autonomous-field-role")
	var sequence: int = game.runner.send({"kind": "save", "path": path})
	check(await until(func(): return game._last_receipt.contains("save #%d " % sequence) and game._last_receipt.ends_with(": saved")), "Native field host could not save")
	epoch = game.frame.epoch; game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "Native field host could not restore")
	game.controls._select(bed, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == bed), "Native field bed inspection failed")
	await resume()
	check(await until(func(): return int(game.ui._target.get("occupant", 0)) > 0, 5000), "NPC did not resume and finish planting after actual file load")
	await pause()
	await capture("autonomous-field-completed")
	check(game.frame.player.action.is_empty(), "NPC field work seized the player's action host")
	game.queue_free(); await process_frame; await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://cultivation-duties-ui-controls.cfg", "user://cultivation-duties-ui-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("CULTIVATION_DUTIES_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
