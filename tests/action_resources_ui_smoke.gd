extends "res://tests/abilities_ui_smoke.gd"
func _run() -> void:
	game = Game.new(); game._opening = "development"
	game._combat_lab = true
	game._fps = 60
	game.controls.bindings.config_path = "user://p4-resources-ui-controls.cfg"
	game.feedback.config_path = "user://p4-resources-ui-feedback.cfg"
	root.add_child(game)
	current_scene = game
	root.grab_focus()
	if not await until(func(): return game.frame != null): check(false, "World never ready"); quit(1); return
	await choose("guardian")
	await create_timer(0.25).timeout
	var point: Vector2 = await aim(1)
	point += Vector2(35, 0)
	await capture("p4-guardian-before")
	await mouse(MOUSE_BUTTON_RIGHT, true, point)
	await mouse(MOUSE_BUTTON_RIGHT, false, point)
	check(await until(func(): return not game.frame.shields.is_empty() and not game.frame.guards.is_empty()), "Real right click did not produce defense")
	check(game.frame.pools.get("mana", {}).get("current", 100) < 100 and game.ui._weapon.text.contains("蓝"), "Pool cost/HUD not visible")
	await capture("p4-guardian-shield")
	await save_lifetime("p4-guardian-shield")
	await choose("binder")
	await create_timer(0.20).timeout
	await attack(MOUSE_BUTTON_RIGHT, 24)
	check(await until(func(): return not game.frame.areas.is_empty()), "Point control telegraph missing")
	await capture("p4-frostbind-warning")
	check(await until(func(): return game.frame.effects.values().any(func(value: Dictionary): return value.kind == "root")), "Control lifetime not published")
	await capture("p4-frostbind-root")
	game.queue_free()
	await process_frame
	await process_frame
	for path: String in ["user://p4-resources-ui-controls.cfg", "user://p4-resources-ui-feedback.cfg"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("ACTION_RESOURCES_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
