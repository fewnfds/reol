extends "res://tests/abilities_ui_smoke.gd"
## Native input, selectors, multi-slot HUD and real file restore for P4.
func tap(code: Key) -> void:
	await key(code, true)
	await key(code, false)

func point_slot(action_id: String, point: Vector2) -> void:
	# Native keyboard slots are covered in melee_route. For point-cast checks,
	# use a temporary supported mouse binding: synthetic motion cannot move
	# the OS cursor that a Window polls when handling a keyboard edge.
	var bindings: RefCounted = game.controls.bindings
	var previous: Dictionary = bindings.values.duplicate(true)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_XBUTTON2
	event.position = point
	event.pressed = true
	var proposal: Dictionary = bindings.propose(action_id, event)
	check(proposal.get("ok", false), "Point-cast binding could not be proposed")
	if not proposal.get("ok", false): return
	check(bindings.commit(proposal.candidate, false) == OK, "Point-cast binding could not be installed")
	Input.parse_input_event(event)
	await process_frame
	await process_frame
	var release: InputEventMouseButton = event.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	check(bindings.commit(previous, false) == OK, "Point-cast binding was not restored")

func save_p4(label: String) -> void:
	game.controls.action("pause", {})
	check(await until(func(): return game.frame.paused), label + ": pause missing")
	var saved: Dictionary = {}
	for field: String in ["health", "pools", "shields", "guards", "effects", "areas", "implements", "entities"]: saved[field] = game.frame.get(field).duplicate(true) if game.frame.get(field) is Dictionary else game.frame.get(field).duplicate()
	var epoch: int = game.frame.epoch
	var path: String = "user://p4-combinations-ui.reol"
	var seq: int = game.runner.send({"kind": "save", "path": path})
	check(await until(func(): return game._last_receipt.contains("save #%d " % seq) and game._last_receipt.ends_with(": saved"), 4000), label + ": file save failed")
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch, 4000), label + ": file load failed")
	for field: String in saved: check(game.frame.get(field) == saved[field], label + ": restore changed " + field)
	await capture("p4-" + label + "-restored")
	game.controls.action("pause", {})
	await until(func(): return not game.frame.paused)
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func melee_route() -> void:
	if game.frame.loadout.id != "bloodblade": await choose("bloodblade")
	check(game.ui._skill_slots.skill2.panel.visible and game.ui._skill_slots.skill3.panel.visible, "Extra action slots not visible")
	check(await until(func(): return game.frame.positions[0].distance_to(game.frame.positions[23]) < 1.6, 3000), "Melee approach missing")
	for strike: int in 3:
		await attack(MOUSE_BUTTON_LEFT, 24)
		await create_timer(0.40).timeout
	check(game.frame.pools.get("rage", {}).get("current", 0) >= 21, "Real melee contacts did not accumulate rage")
	await create_timer(0.20).timeout
	await tap(KEY_E)
	check(await until(func(): return game.frame.cooldowns.has(Defs.ACTIONS.blood_burst.cd_group), 500), "E did not activate rage finisher")
	await create_timer(0.55).timeout
	await attack(MOUSE_BUTTON_RIGHT, 24)
	check(await until(func(): return not game.frame.shields.is_empty(), 500), "Guard input did not create shield")
	await capture("p4-bloodblade-loop")
	await save_p4("bloodblade")
	await until(func(): return not game.frame.combat.has(1), 600)
	await tap(KEY_C)
	check(await until(func(): return game.frame.cooldowns.has("renewal"), 500), "C did not activate recovery slot")

func ranged_route() -> void:
	await choose("barrage")
	var point: Vector2 = await aim(24)
	await mouse(MOUSE_BUTTON_LEFT, true, point)
	await create_timer(0.50).timeout
	await mouse(MOUSE_BUTTON_LEFT, false, point)
	check(game.frame.health[23] < 120, "Held star barrage did not damage")
	await create_timer(0.25).timeout
	await attack(MOUSE_BUTTON_RIGHT, 24)
	check(await until(func(): return not game.frame.areas.is_empty(), 1200), "Ember contact did not produce field")
	await capture("p4-barrage-ember")
	await create_timer(0.25).timeout
	await point_slot("act_skill2", await aim(24))
	check(await until(func(): return game.frame.cooldowns.has("frost_bind"), 500), "Point-bound slot did not activate area control")
	await create_timer(0.40).timeout
	await aim(1)
	var position: Vector2 = game.frame.positions[0]
	var screen: Vector2 = game.get_canvas_transform() * ((game._displayed(1) + Vector2(0, 2)) * game.TILE + game.camera.offset)
	await point_slot("act_skill3", screen)
	check(await until(func(): return game.frame.positions[0].distance_to(position) > 1, 500), "Point-bound slot did not blink to cursor")
	await capture("p4-barrage-control-blink")
	await save_p4("barrage")

func mechanisms() -> void:
	for id: String in ["stars", "plague", "sequence"]:
		await choose(id)
		var point: Vector2 = await aim(24)
		await mouse(MOUSE_BUTTON_LEFT, true, point)
		await create_timer(0.55).timeout
		await mouse(MOUSE_BUTTON_LEFT, false, point)
		check(game.frame.health[23] < 120, id + ": authored projectile did not contact")
		await capture("p4-" + id)
	await choose("companions")
	await attack(MOUSE_BUTTON_RIGHT, 24)
	check(await until(func(): return not game.frame.entities.is_empty(), 600), "Summon body not published")
	await create_timer(0.40).timeout
	await point_slot("act_skill2", await aim(1))
	check(await until(func(): return game.frame.entities.size() == 2, 600), "Totem slot not published")
	await create_timer(0.60).timeout
	await capture("p4-wolf-totem-aura")
	await save_p4("entities-aura")
	await choose("sword_array")
	await attack(MOUSE_BUTTON_LEFT, 24)
	check(await until(func(): return game.frame.implements.size() == 2, 600), "Two implement slots not published")
	await create_timer(0.60).timeout
	await capture("p4-sword-array")
	await save_p4("sword-array")

func stale_selection() -> void:
	await choose("barrage")
	game.controls._select(2, -1)
	var observed: Dictionary = game.controls.Actions.observed(game.frame, 2, true)
	check(observed.is_empty() or observed.get("memory", false), "Stale selection fixture is still visible")
	await tap(KEY_SPACE)
	check(await until(func(): return game.frame.cooldowns.has("step"), 500), "Unseen old selection blocked a directional action")
	game.controls._select(1, -1)

func _run() -> void:
	game = Game.new()
	game._combat_lab = true
	game._fps = 60
	game.controls.bindings.config_path = "user://p4-combinations-ui-controls.cfg"
	game.feedback.config_path = "user://p4-combinations-ui-feedback.cfg"
	root.add_child(game)
	current_scene = game
	root.grab_focus()
	if not await until(func(): return game.frame != null): check(false, "P4 lab never ready"); quit(1); return
	game.runner.send({"kind": "combat_practice", "mode": "light", "loadout": "bloodblade"})
	await until(func(): return game.frame.practice_mode == "light")
	await melee_route()
	await ranged_route()
	await mechanisms()
	await stale_selection()
	game.queue_free()
	await process_frame
	await process_frame
	for path: String in ["user://p4-combinations-ui-controls.cfg", "user://p4-combinations-ui-feedback.cfg"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("ACTION_COMBINATIONS_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
