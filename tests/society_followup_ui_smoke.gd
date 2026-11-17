extends "res://tests/institution_access_ui_smoke.gd"

func capture(name_key: String) -> void:
	var directory: String = "res://logs/society-ui/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + name_key + ".png")

func message_button(label_text: String) -> Button:
	if game.ui.character == null: return null
	for row: Node in game.ui.character._requests.get_children():
		for child: Node in row.get_children():
			if child is Button and child.text == label_text: return child
	return null

func message_shows(text: String) -> bool:
	return game.ui.character._requests.get_children().any(func(child: Node): return child is Label and child.text.contains(text))

func open_messages() -> void:
	if game.ui._drawer_name != "character": game.controls.action("character", {})
	check(await until(func(): return game.ui.character != null), "Player character drawer did not open")
	var tabs: TabContainer = game.ui.character._tabs
	for index: int in tabs.get_tab_count():
		if tabs.get_tab_title(index) == "约定": tabs.current_tab = index
	await process_frame; await process_frame

func _run() -> void:
	var w := World.new()
	w.initialize(4, 0)
	for actor: int in w.actor_slots:
		w.release(actor); w.objects.records[actor].autonomous = false; w.objects.records[actor].side = 0
		w.pages[0].modes[actor - 1] = w.Units.Mode.IDLE
		w.pages[0].positions[actor - 1] = Vector2(123.5 + actor * 0.2, 124.5)
		w.pages[0].energy[actor - 1] = 10000; w.pages[0].hunger[actor - 1] = 10000
	w.objects.add(3, "wood", 4)
	var site: Dictionary = w.facilities.blueprint(w, 3, "wood_wall", w.Terrain.index(Vector2i(127, 126)))
	check(site.reason == "accepted", "GUI social fixture could not place prepaid blueprint")
	if site.reason != "accepted": quit(1); return
	check(w.execute_operation(3, {"kind": "request_help", "target": 1, "task_target": int(site.target)}) == "accepted", "Incoming request did not use the actual contact host")
	while w.elapsed_ms < 1300: w.step(mini(16, 1300 - w.elapsed_ms))
	check(w.society.requests.size() == 1 and w.society.requests.values()[0].state == "pending", "Real contact did not leave the player's answer open")
	w.flush_topology(); w.perception.update(w, w.elapsed_ms, true)
	var path: String = "user://society-followup-ui-fixture.reol"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var({"format": SessionIO.FORMAT, "state": Persistence.capture(w)}, false); file.close()
	game = Game.new(); game._actors = 4; game.speed = 1
	game.controls.bindings.config_path = "user://society-followup-ui-controls.cfg"
	game.feedback.config_path = "user://society-followup-ui-feedback.cfg"
	game.paused = true; game.runner.control(true, 1)
	root.add_child(game); current_scene = game; root.grab_focus()
	check(await until(func(): return game.frame != null), "Social GUI had no initial frame")
	var epoch: int = game.frame.epoch
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "Social GUI fixture failed normal file load")
	await open_messages()
	check(await until(func(): return message_button("稍后答复") != null), "Native player request buttons were missing")
	await capture("incoming-request")
	var button: Button = message_button("稍后答复")
	if button != null: await click(button)
	check(await until(func(): return game.frame.player.action.get("kind") == "respond_request"), "Native reply did not create the shared contact action")
	var sequence: int = game.runner.send({"kind": "save", "path": path})
	check(await until(func(): return game._last_receipt.contains("save #%d " % sequence) and game._last_receipt.ends_with(": saved")), "In-flight native response did not save")
	epoch = game.frame.epoch; game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "In-flight native response did not restore")
	await resume()
	check(await until(func(): return game.frame.player.requests[0].state == "deferred"), "Restored native response did not actually deliver the deferral")
	await pause()
	await open_messages()
	check(await until(func(): return message_shows("暂缓答复")), "Delivered deferral did not refresh its visible native message")
	await capture("delivered-deferral")
	check(await until(func(): return message_button("接受") != null), "Reloaded personal message did not expose its native accept button")
	button = message_button("接受")
	if button != null: await click(button)
	await resume()
	check(await until(func(): return not game.frame.player.responsibilities.is_empty()), "Explicit player acceptance did not create the ordinary responsibility")
	await pause()
	check(game.frame.player.requests[0].state == "accepted" and not game.frame.player.autonomous and game.frame.player.action.is_empty(), "Native player acceptance took control or failed to complete contact")
	check(await until(func(): return message_shows("已接受") and message_button("接受") == null), "Native message kept stale reply buttons after acceptance")
	await capture("accepted-player-request")
	game.queue_free(); await process_frame; await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://society-followup-ui-controls.cfg", "user://society-followup-ui-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("SOCIETY_FOLLOWUP_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
