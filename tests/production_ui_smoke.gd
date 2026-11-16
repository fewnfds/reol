extends "res://tests/abilities_ui_smoke.gd"
const World = preload("res://scripts/sim/kernel/world.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")
const SessionIO = preload("res://scripts/sim/kernel/session_io.gd")

func capture(name_key: String) -> void:
	var directory: String = "res://logs/production-ui/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + name_key + ".png")

func command_button(text: String) -> Button:
	for child: Node in game.ui._commands.get_children():
		if child is Button and child.text == text: return child
	return null

func select_and_press(target: int, text: String) -> void:
	game.controls._select(target, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == target), "Production UI target not inspected")
	check(await until(func(): return command_button(text) != null and not command_button(text).disabled), "Native operation unavailable: " + text)
	await process_frame
	await process_frame
	var button: Button = command_button(text)
	if button != null:
		game.ui._inspect_scroll.ensure_control_visible(button)
		await process_frame
		await process_frame
	if text == "请教煎药": await capture("teacher-menu")
	if button != null and not button.disabled: await click(button)

func pause() -> void:
	game.controls.action("pause", {})
	check(await until(func(): return game.frame.paused), "Production UI pause missing")

func resume() -> void:
	game.controls.action("pause", {})
	check(await until(func(): return not game.frame.paused), "Production UI resume missing")

func _run() -> void:
	var w := World.new()
	w.initialize(4, 0)
	for actor: int in w.actor_slots:
		w.release(actor)
		w.objects.records[actor].autonomous = false
		w.pages[0].modes[actor - 1] = w.Units.Mode.IDLE
		w.pages[0].positions[actor - 1] = Vector2(122.5 + actor, 126.5)
		w.objects.records[actor].side = 0
	var stove: int = w.facilities.create_completed(w, "cook_stove", w.Terrain.index(Vector2i(124, 124)))
	var well: int = w.facilities.create_completed(w, "water_well", w.Terrain.index(Vector2i(122, 124)))
	w.objects.add(1, "herb", 2)
	w.flush_topology()
	while w.elapsed_ms < 15000: w.step(16)
	w.pages[0].positions[0] = Vector2(123.5, 125.5)
	w.pages[0].positions[1] = Vector2(123.5, 126.5)
	w.perception.update(w, w.elapsed_ms, true)
	var path: String = "user://production-ui-fixture.reol"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var({"format": SessionIO.FORMAT, "state": Persistence.capture(w)}, false)
	file.close()
	game = Game.new()
	game.controls.bindings.config_path = "user://production-ui-controls.cfg"
	game.feedback.config_path = "user://production-ui-feedback.cfg"
	game.paused = true
	game.runner.control(true, 1)
	root.add_child(game)
	current_scene = game
	root.grab_focus()
	check(await until(func(): return game.frame != null), "Production UI initial frame absent")
	var epoch: int = game.frame.epoch
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "Production fixture did not load")
	game.ui.apply_scale(125, false)
	game.controls.action("context", {})
	await select_and_press(2, "请教煎药")
	await resume()
	check(await until(func(): return game.frame.player.get("methods", {}).has("herbalism") and game.frame.player.action.is_empty(), 2500), "Native teaching did not introduce real herbalism")
	await pause()
	await select_and_press(stove, "煎制伤药")
	await resume()
	check(await until(func(): return game.ui._target.get("process", {}).get("stage", "") == "passive", 4000), "Native brew did not reach passive phase")
	await pause()
	check(game.frame.player.action.is_empty() and game.ui._inspect_values.text.contains("静置") and game.ui._inspect_values.text.contains("在制原料"), "Passive work left actor occupied or hid real WIP")
	check(command_button("煎制伤药").disabled and command_button("煎制伤药").tooltip_text.contains("静置"), "Passive disabled operation did not explain waiting")
	await capture("passive-batch")
	var saved_at: int = game.frame.world_ms
	epoch = game.frame.epoch
	var seq: int = game.runner.send({"kind": "save", "path": path})
	check(await until(func(): return game._last_receipt.contains("save #%d " % seq) and game._last_receipt.ends_with(": saved")), "Actual production file save failed")
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "Actual production file load failed")
	check(game.frame.world_ms == saved_at, "Passive file restore moved world time")
	game.controls._select(stove, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == stove and game.ui._target.get("process", {}).get("stage", "") == "passive"), "Saved passive batch not inspectable after restore")
	await resume()
	check(await until(func(): return command_button("煎制伤药") != null and not command_button("煎制伤药").disabled, 5000), "Mature batch did not permit collection")
	check(game.ui._inspect_values.text.contains("可收取") and command_button("煎制伤药").tooltip_text.contains("无需重新投料"), "Mature operation did not explain collection")
	await pause()
	await select_and_press(stove, "煎制伤药")
	await resume()
	check(await until(func(): return game.ui._target.get("inventory", {}).get("potion", 0) == 1 and game.ui._target.get("process", {}).is_empty(), 2500), "Native collection did not make one actual potion")
	await pause()
	await capture("collected-potion")
	var water_before: int = int(game.frame.player.inventory.get("water", 0))
	await select_and_press(well, "汲水")
	await resume()
	check(await until(func(): return game.frame.player.action.is_empty() and game.frame.player.inventory.get("water", 0) == water_before + 1 and game.ui._target.get("inventory", {}).get("water", 0) == 0, 2500), "Native water collection did not exhaust finite source")
	await pause()
	await capture("depleted-source")
	game.queue_free()
	await process_frame
	await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://production-ui-controls.cfg", "user://production-ui-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("PRODUCTION_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
