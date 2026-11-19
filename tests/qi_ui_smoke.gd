extends "res://tests/cultivation_ui_smoke.gd"

func practice_tab() -> void:
	await process_frame; await process_frame
	var bar: TabBar = game.ui.character._tabs.get_tab_bar()
	var point: Vector2 = bar.get_global_transform_with_canvas() * bar.get_tab_rect(1).get_center()
	await mouse(MOUSE_BUTTON_LEFT, true, point); await mouse(MOUSE_BUTTON_LEFT, false, point)
	check(game.ui.character._tabs.current_tab == 1, "Native practice tab did not open")

func _run() -> void:
	var w := World.new()
	w.initialize(4, 0)
	for actor: int in w.actor_slots:
		w.release(actor); w.objects.records[actor].autonomous = false; w.objects.records[actor].side = 0
		w.livelihood.forget(actor); w.objects.records[actor].erase("methods")
		w.pages[0].modes[actor - 1] = w.Units.Mode.IDLE
		w.pages[0].hunger[actor - 1] = 10000; w.pages[0].energy[actor - 1] = 10000
		w.pages[0].positions[actor - 1] = Vector2(122.5 + actor % 2, 124.5 + actor / 2)
	var source: int = w.nature.create(w, "spirit_bamboo", w.Terrain.index(Vector2i(125, 124)))
	w.objects.records[source].stage = w.nature.Stage.MATURE
	w.objects.records[source].growth_ms = int(w.nature.definitions.spirit_bamboo.mature_ms)
	w.objects.records[source].qi = 1000; w.nature._sync(w, source)
	w.Growth.seed(w.objects.records[1], "wood_breath", 0)
	w.Growth.seed(w.objects.records[3], "wood_breath", 0)
	w.objects.records[1].qi = 3000; w.objects.records[3].qi = 2940
	w.objects.records[3].autonomous = true
	w.knowledge.seed(w, 3, w.operation_target(source), 0)
	w.flush_topology(); w.decisions.resume(w, 3, 0); w.decisions.prepare(w, 0)
	while w.elapsed_ms < 1500:
		w.step(16)
		if int(w.actions.get(3, {}).get("started_ms", 0)) > 0: break
	check(w.actions.get(3, {}).get("kind") == "practice", "Reserve goal did not enter a real practice host")
	w.perception.update(w, w.elapsed_ms, true)
	var path: String = "user://qi-ui-fixture.reol"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var({"format": SessionIO.FORMAT, "state": Persistence.capture(w)}, false); file.close()
	game = Game.new(); game._opening = "development"; game._actors = 4; game.speed = 1
	game.controls.bindings.config_path = "user://qi-ui-controls.cfg"
	game.feedback.config_path = "user://qi-ui-feedback.cfg"
	game.paused = true; game.runner.control(true, 1)
	root.add_child(game); current_scene = game; root.grab_focus()
	check(await until(func(): return game.frame != null), "Qi GUI initial frame absent")
	var epoch: int = game.frame.epoch
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "Actual in-progress practice file failed to load")
	game.controls._select(3, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == 3), "Practitioner could not be inspected")
	check(await until(func(): return game.ui._inspect_values.text.contains("修行") and game.frame.inspected.get("qi", 0) == 2940), "Ordinary inspection did not reflect the ongoing practice")
	await capture("qi-practicing")
	game.controls.action("character", {})
	await practice_tab()
	check(game.ui.character.subject_id == 1 and game.ui.character._practice.text.contains("3000 / 3000"), "The player practice tab did not show the player's reserve")
	game.controls.action("close_drawer", {})
	var sequence: int = game.runner.send({"kind": "save", "path": path})
	check(await until(func(): return game._last_receipt.contains("save #%d " % sequence) and game._last_receipt.ends_with(": saved")), "Native practice could not save")
	epoch = game.frame.epoch; game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "Native practice could not restore")
	game.controls._select(3, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == 3), "Restored practitioner could not be reinspected")
	await resume()
	var stopped: bool = await until(func(): return game.frame.inspected.get("qi", 0) == 3000 and game.ui._inspect_values.text.contains("闲暇"), 5000)
	if not stopped: await capture("qi-stop-failure")
	check(stopped, "Practitioner did not complete the restored host and stop at full reserve: " + str({"qi": game.frame.inspected.get("qi"), "activity": game.ui._inspect_values.text, "world_ms": game.frame.world_ms}))
	await pause(); await capture("qi-full-stopped")
	game.controls._select(source, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == source and command_button("修行") != null), "New natural source did not expose the shared player operation")
	check(command_button("修行").disabled, "Full mastered player was offered useless practice")
	await capture("qi-source-player")
	game.queue_free(); await process_frame; await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://qi-ui-controls.cfg", "user://qi-ui-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("QI_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
