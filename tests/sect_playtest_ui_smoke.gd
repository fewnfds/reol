extends "res://tests/cultivation_ui_smoke.gd"

func tap(code: Key) -> void:
	await key(code, true)
	await key(code, false)

func capture(name_key: String) -> void:
	var directory: String = "res://logs/sect-playtest-ui/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + name_key + ".png")

func _run() -> void:
	game = Game.new()
	game.controls.bindings.config_path = "user://sect-playtest-controls.cfg"
	game.feedback.config_path = "user://sect-playtest-feedback.cfg"
	game.paused = true; game.runner.control(true, 1)
	root.add_child(game); current_scene = game; root.grab_focus()
	check(await until(func(): return game.frame != null, 8000), "Normal sect did not publish")
	if game.frame == null: quit(1); return
	await process_frame; await process_frame
	check(not game.controls.combat_stance and game.frame.ids.size() == 100, "Normal sect did not default to daily play")
	var target: int = 8
	var point: Vector2 = game.view.project(game.frame.positions[target - 1] * game.TILE + Vector2(0, -12), false)
	await mouse(MOUSE_BUTTON_LEFT, true, point); await mouse(MOUSE_BUTTON_LEFT, false, point)
	check(await until(func(): return game.ui._target.get("id", 0) == target and not game.ui._target.get("pending", false)), "Daily left click failed to inspect NPC")
	check(game.ui._inspect_values.text.contains("闲暇") and not game.ui._inspect_values.text.contains("视距 0.0"), "Selected NPC did not explain its actual activity")
	await capture("daily-selected")
	await resume()
	var attacks: int = game.frame.counters.attacks
	var origin: Vector2 = game.frame.positions[0]
	await key(KEY_D, true)
	check(await until(func(): return game.frame.positions[0].distance_to(origin) > 0.2, 2000), "WASD was unavailable in daily play")
	await key(KEY_D, false)
	point = game.view.project(game._displayed(target) * game.TILE + Vector2(0, -12), false)
	await mouse(MOUSE_BUTTON_RIGHT, true, point); await mouse(MOUSE_BUTTON_RIGHT, false, point)
	check(await until(func(): return game.ui._context_panel.visible), "Daily right click did not open object menu")
	check(game.frame.counters.attacks == attacks and not game.frame.combat.has(1), "Daily mouse commands accidentally attacked")
	game.ui.close_context()
	await tap(KEY_TAB)
	check(game.controls.combat_stance and game.ui._weapon.text.contains("战斗"), "Explicit combat switch did not reach HUD")
	var aim: Vector2 = game.view.project((game._displayed(1) + Vector2(3, 0)) * game.TILE, false)
	await mouse(MOUSE_BUTTON_LEFT, true, aim)
	check(await until(func(): return game.frame.combat.has(1), 2000), "Combat mouse press did not start an action")
	await tap(KEY_TAB)
	check(not game.controls.combat_stance and not game.controls._primary_down, "Switching to daily retained held attack")
	await mouse(MOUSE_BUTTON_LEFT, false, aim)
	check(await until(func(): return not game.frame.combat.has(1), 2000), "Committed action never completed after switching stance")
	await capture("daily-after-combat")
	await tap(KEY_TAB)
	await tap(KEY_F)
	check(await until(func(): return game.ui._context_panel.visible), "Nearby interaction did not open from combat stance")
	await capture("combat-nearby")
	game.ui.close_context()
	game.controls._select(target, -1)
	check(await until(func(): return game.ui._target.get("id") == target and not game.ui._target.get("pending", false)), "Context selection never resolved")
	await select_and_press(target, "交谈")
	check(not game.controls.combat_stance and not game.controls._primary_down, "Explicit daily interaction retained combat aiming/input")
	game.controls.action("place_build", {"definition": "wood_wall"})
	check(not game.controls.combat_stance and game.controls.tool == "build", "Build tool did not take safe input priority")
	game.controls.cancel_tool()
	game.controls.action("context", {})
	game.controls.action("continue_build", {"target": 1})
	check(not game.controls.combat_stance, "Existing construction adapter bypassed the daily operation boundary")
	game.controls._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(game.controls._held.is_empty() and not game.controls._primary_down, "Focus loss retained continuous input")
	game.controls._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	game.controls._session_request = 999
	var next_seq: int = game.runner._next_seq
	game.controls.action("work", {}); game.controls.action("load", {})
	check(game.runner._next_seq == next_seq and game.controls._session_request == 999, "UI signals bypassed the pending session boundary")
	game.controls.accept_receipt({"seq": 999, "reason": "accepted"})
	check(game.controls._session_request == 999, "Intermediate receipt released the session boundary")
	game.controls.accept_receipt({"seq": 999, "reason": "load_failed"})
	check(game.controls._session_request == 0, "Failed terminal receipt left input locked")
	await pause()
	var path: String = "user://sect-playtest-fixture.reol"
	var sequence: int = game.runner.send({"kind": "save", "path": path})
	check(await until(func(): return game._last_receipt.contains("save #%d " % sequence) and game._last_receipt.ends_with(": saved")), "Normal GUI could not save")
	var epoch: int = game.frame.epoch
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch, 5000), "Normal GUI could not load")
	check(not game.controls.combat_stance, "Normal load did not return to daily stance")
	game.queue_free(); await process_frame; await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://sect-playtest-controls.cfg", "user://sect-playtest-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("SECT_PLAYTEST_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
