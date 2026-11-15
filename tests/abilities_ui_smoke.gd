extends "res://tests/melee_ui_smoke.gd"
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")

func capture(name_key: String) -> void:
	var directory: String = "res://logs/abilities-ui/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + name_key + ".png")

func choose(id: String) -> void:
	var epoch: int = game.frame.epoch
	var choice: OptionButton = game.ui._loadout_choice
	await click(choice)
	var popup: PopupMenu = choice.get_popup()
	check(popup.visible, "Native loadout selector did not open")
	popup.set_focused_item(game.ui._loadout_ids.find(id))
	await key(KEY_ENTER, true)
	await key(KEY_ENTER, false)
	check(await until(func(): return game.frame.epoch > epoch and game.frame.loadout.id == id), "Native selection did not adopt " + id)

func save_lifetime(label: String) -> void:
	game.controls.action("pause", {})
	check(await until(func(): return game.frame.paused), label + ": pause missing")
	var areas: Dictionary = game.frame.areas.duplicate(true)
	var implements: Dictionary = game.frame.implements.duplicate(true)
	var effects: Dictionary = game.frame.effects.duplicate(true)
	var hp: PackedInt32Array = game.frame.health.duplicate()
	var at: int = game.frame.world_ms
	var epoch: int = game.frame.epoch
	var path: String = "user://p3-abilities-ui-session.reol"
	var seq: int = game.runner.send({"kind": "save", "path": path})
	check(await until(func(): return game._last_receipt.contains("save #%d " % seq) and game._last_receipt.ends_with(": saved"), 4000), label + ": save missing")
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch, 4000), label + ": load missing")
	check(game.frame.world_ms == at and game.frame.health == hp and game.frame.areas == areas and game.frame.implements == implements and game.frame.effects == effects, label + ": changed saved lifetime")
	await capture(label + "-restored")
	game.controls.action("pause", {})
	check(await until(func(): return not game.frame.paused), label + ": resume missing")
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func sample(id: String) -> void:
	await choose(id)
	var primary: Dictionary = Defs.ACTIONS[game.frame.loadout.primary]
	if primary.delivery.kind == "melee":
		check(await until(func(): return game.frame.positions[0].distance_to(game.frame.positions[23]) < 1.8, 3000), id + ": enemy did not approach")
	var point: Vector2 = await aim(24)
	if id == "thunder": point -= Vector2(50, 0) * game.camera.zoom.x
	await mouse(MOUSE_BUTTON_LEFT, true, point)
	if primary.delivery.kind == "projectile":
		check(await until(func(): return game.frame.projectiles.size() > 0, 500), id + ": projectile not published")
		await capture(id + "-primary")
		await create_timer(0.26).timeout
	elif id == "thunder":
		check(await until(func(): return not game.frame.areas.is_empty(), 500), "Point area not published")
		await capture("thunder-warning")
		await mouse(MOUSE_BUTTON_LEFT, false, point)
		await save_lifetime("thunder-pending")
	elif id == "flying_sword":
		check(await until(func(): return not game.frame.implements.is_empty(), 500), "Sword not published")
		await create_timer(0.15).timeout
		await capture("sword-outbound")
	else: await create_timer(0.10).timeout
	await mouse(MOUSE_BUTTON_LEFT, false, point)
	check(await until(func(): return game.frame.health[23] < 120, 1300), id + ": primary never damaged enemy")
	if id == "fire" or id == "frost" or id == "venom":
		check(not game.frame.effects.is_empty(), id + ": status indicator missing")
	await capture(id + "-contact")
	await until(func(): return not game.frame.combat.has(1), 700)
	await attack(MOUSE_BUTTON_RIGHT, 24)
	var skill: String = game.frame.loadout.skill
	if id == "flying_sword":
		check(await until(func(): return game.frame.implements.values().any(func(value: Dictionary): return value.phase == "returning"), 500), "Sword did not recall")
		await save_lifetime("sword-returning")
		check(await until(func(): return game.frame.implements.values().any(func(value: Dictionary): return value.phase == "stowed"), 1500), "Sword did not return")
	else:
		check(await until(func(): return game.frame.cooldowns.has(Defs.ACTIONS[skill].cd_group), 700), id + ": skill cooldown missing")
		await create_timer(0.20).timeout
	await capture(id + "-skill")

func _run() -> void:
	game = Game.new()
	game._combat_lab = true
	game._fps = 60
	game.controls.bindings.config_path = "user://p3-abilities-ui-controls.cfg"
	game.feedback.config_path = "user://p3-abilities-ui-feedback.cfg"
	root.add_child(game)
	current_scene = game
	root.grab_focus()
	if not await until(func(): return game.frame != null): check(false, "Ability lab never ready"); quit(1); return
	game.runner.send({"kind": "combat_practice", "mode": "light", "loadout": "fire"})
	await until(func(): return game.frame.practice_mode == "light")
	for id: String in ["sword", "bow", "spear", "fire", "frost", "thunder", "venom", "flying_sword"]: await sample(id)
	game.queue_free()
	await process_frame
	await process_frame
	for path: String in ["user://p3-abilities-ui-controls.cfg", "user://p3-abilities-ui-feedback.cfg"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("ABILITIES_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
