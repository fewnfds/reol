extends "res://tests/abilities_ui_smoke.gd"
func _run() -> void:
	game = Game.new(); game._opening = "development"
	game._combat_lab = true
	game._fps = 60
	game.controls.bindings.config_path = "user://p4-domain-ui-controls.cfg"
	game.feedback.config_path = "user://p4-domain-ui-feedback.cfg"
	root.add_child(game)
	current_scene = game
	root.grab_focus()
	if not await until(func(): return game.frame != null): check(false, "World never ready"); quit(1); return
	await choose("tender")
	await create_timer(0.2).timeout
	root.grab_focus()
	var plant: int = 0
	for record: Dictionary in game.frame.objects.values():
		if record.kind == "plant" and record.tile == 152 * 512 + 145: plant = record.id; break
	check(plant > 0, "Selected object sample missing")
	if plant > 0:
		game.selected = plant
		var point: Vector2 = await aim(1)
		point += Vector2(35, 0)
		print("DOMAIN_UI state ",game.controls.direct," ",game.controls.locked()," ",game.controls._focused," ",point)
		await capture("p4-tending-before")
		await mouse(MOUSE_BUTTON_RIGHT, true, point)
		await mouse(MOUSE_BUTTON_RIGHT, false, point)
		check(await until(func(): return game.frame.cooldowns.has("water_tend")), "Actual right click did not admit domain cast")
		check(await until(func(): return not game.frame.combat.has(1), 1100), "Domain cast did not finish")
		game.controls.action("character", {})
		await capture("p4-tending")
	game.queue_free()
	await process_frame
	await process_frame
	for path: String in ["user://p4-domain-ui-controls.cfg", "user://p4-domain-ui-feedback.cfg"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("ACTION_DOMAINS_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
