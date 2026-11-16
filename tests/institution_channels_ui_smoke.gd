extends "res://tests/institution_access_ui_smoke.gd"

func _run() -> void:
	var w := World.new()
	w.initialize(4, 0)
	for actor: int in w.actor_slots:
		w.release(actor); w.objects.records[actor].autonomous = false; w.objects.records[actor].side = 0
		w.pages[0].modes[actor - 1] = w.Units.Mode.IDLE
		w.pages[0].positions[actor - 1] = Vector2(123.5 + actor, 124.5)
		w.pages[0].energy[actor - 1] = 10000; w.pages[0].hunger[actor - 1] = 10000
	var org: int = w.institutions.create("青禾宗")
	w.institutions.admit(w, org, 1, Array(w.institutions.PURPOSES))
	w.institutions.admit(w, org, 3, [])
	var source: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(125, 120)))
	var destination: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(130, 120)))
	var board: int = w.facilities.create_completed(w, "notice_desk", w.Terrain.index(Vector2i(121, 124)))
	for target: int in [source, destination, board]: w.objects.records[target].organization = org
	w.objects.add(source, "meal", 6, w.objects.Stock.right(0, org))
	w.flush_topology()
	w.livelihood.records.erase(3); w.knowledge.records.erase(3)
	for target: int in [source, destination, board]: w.knowledge.seed(w, 3, w.operation_target(target), 0)
	w.set_capability_overrides(3, {"work": false})
	w.objects.records[3].autonomous = true
	check(w.institutions.appoint(w, org, 3, "meal_steward", [source, destination, board], {"target": destination, "sources": [source], "channel": board}) > 0, "Native record fixture duty appointment failed")
	w.decisions.resume(w, 3, 0)
	while w.elapsed_ms < 15000 and w.institutions.channels.get(board, {}).get("posts", {}).is_empty(): w.step(16)
	check(not w.institutions.channels.get(board, {}).get("posts", {}).is_empty(), "Autonomous steward did not actually publish the GUI fixture")
	if w.institutions.channels.get(board, {}).get("posts", {}).is_empty(): quit(1); return
	var matter: int = w.institutions.channels[board].posts.keys()[0]
	w.perception.update(w, w.elapsed_ms, true)
	var path: String = "user://institution-channels-ui-fixture.reol"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var({"format": SessionIO.FORMAT, "state": Persistence.capture(w)}, false); file.close()
	game = Game.new(); game._actors = 4; game.speed = 4
	game.controls.bindings.config_path = "user://institution-channels-ui-controls.cfg"
	game.feedback.config_path = "user://institution-channels-ui-feedback.cfg"
	game.paused = true; game.runner.control(true, 4)
	root.add_child(game); current_scene = game; root.grab_focus()
	check(await until(func(): return game.frame != null), "Records GUI initial frame absent")
	var epoch: int = game.frame.epoch
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "Actual published duty fixture failed normal file loading")
	await select_and_press(board, "查阅告示")
	await resume()
	check(await until(func(): return game.frame.player.get("known_channels", {}).get(board, {}).get("posts", {}).has(matter) and game.frame.player.action.is_empty()), "Native reading did not acquire the actual published terms")
	await pause(); await capture("read-duty-post")
	var label: String = "受理 #%d · 饭食×3" % matter
	await select_and_press(board, label)
	await resume()
	check(await until(func(): return not game.frame.player.get("responsibilities", {}).is_empty() and game.frame.player.action.is_empty()), "Native acceptance lost the selected matter payload")
	await pause()
	if game.frame.player.get("responsibilities", {}).is_empty(): game.queue_free(); await process_frame; quit(1); return
	game.controls._select(source, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == source), "Actual source chest was not inspected")
	game.controls.action("take", {"target": source})
	check(await until(func(): return game.ui.inventory.visible), "Native material workspace absent")
	var panel: Control = game.ui.inventory
	var purpose: int = -1
	for index: int in panel._purpose.item_count:
		if panel._purpose.get_item_metadata(index).get("purpose", "") == "supply": purpose = index
	check(purpose > 0, "A real accepted delivery did not expose its lawful issue purpose")
	if purpose > 0: panel._purpose.select(purpose)
	panel.container.select("meal"); panel.amount.value = 3
	await process_frame; await process_frame
	check(not panel._take.disabled, "Actual accepted-share material issue was disabled")
	await click(panel._take); await resume()
	check(await until(func(): return game.frame.player.inventory.get("meal", 0) == 3 and game.frame.player.action.is_empty()), "Native issue failed actual stock/custody transfer")
	await pause(); panel.hide()
	var sequence: int = game.runner.send({"kind": "save", "path": path})
	check(await until(func(): return game._last_receipt.contains("save #%d " % sequence) and game._last_receipt.ends_with(": saved")), "In-progress record/custody file save failed")
	epoch = game.frame.epoch; game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "In-progress record/custody candidate failed file restoration")
	game.controls._select(destination, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == destination), "Delivery destination was not inspectable after restoration")
	game.controls.action("put", {"target": destination})
	check(await until(func(): return panel.visible), "Restored delivery workspace absent")
	panel.bag.select("meal"); panel.amount.value = 3
	await process_frame; await process_frame
	check(not panel._put.disabled, "Actual delivery was unavailable after restoration")
	await click(panel._put); await resume()
	check(await until(func(): return game.frame.player.inventory.get("meal", 0) == 0 and game.frame.player.action.is_empty()), "Native actual delivery did not settle")
	await pause(); panel.hide()
	check(not game.frame.player.get("reports", []).is_empty(), "Actual delivery failed to create a pending personal report")
	await select_and_press(board, "回报 #%d · 已办3" % matter)
	check(await until(func(): return game.frame.player.action.get("kind") == "report_matter"), "Native report did not enter the original approach host")
	sequence = game.runner.send({"kind": "save", "path": path})
	check(await until(func(): return game._last_receipt.contains("save #%d " % sequence) and game._last_receipt.ends_with(": saved")), "Approaching report failed real file save")
	epoch = game.frame.epoch; game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch and game.frame.player.action.get("kind") == "report_matter"), "In-flight report did not restore through normal session adoption")
	await resume()
	check(await until(func(): return game.frame.player.get("reports", []).is_empty() and game.frame.player.action.is_empty()), "Native return/report failed to publish real fulfilled amount")
	await pause()
	check(game.frame.player.known_channels[board].posts[matter].reported == 3, "Native report did not update the physical record")
	check(game.frame.player.known_channels[board].posts[matter].unclaimed == 3, "One delivery incorrectly fulfilled another person's remaining allocation")
	game.controls._select(board, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == board), "Restored report's record desk was not inspectable")
	await capture("reported-duty-delivery")
	await select_and_press(board, "撤回告示 #%d" % matter)
	await resume()
	check(await until(func(): return game.frame.player.known_channels[board].posts[matter].state == "closed" and game.frame.player.action.is_empty()), "Native authorized withdrawal lost the selected matter or failed to close locally")
	await pause(); await capture("withdrawn-duty-post")
	game.queue_free(); await process_frame; await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://institution-channels-ui-controls.cfg", "user://institution-channels-ui-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("INSTITUTION_CHANNELS_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
