extends "res://tests/abilities_ui_smoke.gd"
## Real renderer and native input in a one-cell furniture passage.
const World = preload("res://scripts/sim/kernel/world.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")
const Session = preload("res://scripts/sim/kernel/session_io.gd")
const Art = preload("res://scripts/presentation/art.gd")

func capture(name_key: String) -> void:
	var directory: String = "res://logs/movement-ui/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + name_key + ".png")

func _run() -> void:
	var w := World.new()
	w.initialize(4, 0)
	for actor: int in w.actor_slots:
		w.release(actor)
		w.objects.records[actor].autonomous = false
		w.pages[0].modes[actor - 1] = w.Units.Mode.IDLE
		w.pages[0].positions[actor - 1] = Vector2(121.5 + actor * 2, 117.5)
	w.pages[0].positions[0] = Vector2(121.5, 121.5)
	w.objects.records[1]["ability_loadout"] = "sword"
	var chest: int = 0
	for x: int in range(118, 126):
		var id: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(x, 120)))
		if x == 121: chest = id
		w.facilities.create_completed(w, "wood_wall", w.Terrain.index(Vector2i(x, 122)))
	var pile: int = w.objects.create("pile", "wood", w.Terrain.index(Vector2i(121, 121)))
	w.objects.transfer(w.source_objects[0], pile, "wood", 2)
	w.objects.transfer(w.source_objects[0], 1, "wood", 20)
	w.facilities.blueprint(w, 1, "wood_floor", w.Terrain.index(Vector2i(122, 121)))
	w.flush_topology()
	w.perception.update(w, 0, true)
	var path: String = "user://movement-ui-fixture.reol"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var({"format": Session.FORMAT, "state": Persistence.capture(w)}, false)
	file.close()
	game = Game.new()
	game._actors = 4
	game._fps = 60
	game.paused = true
	game.controls.bindings.config_path = "user://movement-ui-controls.cfg"
	game.feedback.config_path = "user://movement-ui-feedback.cfg"
	root.add_child(game)
	current_scene = game
	if not await until(func(): return game.frame != null): check(false, "Movement GUI never ready"); quit(1); return
	var epoch: int = game.frame.epoch
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "Passage fixture could not restore")
	game.following = false
	game.camera.position = Vector2(122, 120.5) * Art.TILE
	game.camera.zoom = Vector2.ONE * 2.5
	game.camera.force_update_scroll()
	await RenderingServer.frame_post_draw
	root.grab_focus()
	check(await until(func(): return root.has_focus() and game.controls._focused, 700), "Movement window did not acquire native input focus")
	check(game._displayed(1).distance_to(game.frame.positions[0]) < 0.0001, "Drawn foot is displaced from the body's ground contact")
	check(absf(game.population._buffer[7] / Art.TILE - game.frame.positions[0].y) < 0.0001, "GPU body anchor differs from ground collision")
	# The fixture immediately north is painted before the player in the passage.
	var buffer: PackedFloat32Array = game.population.multimesh.buffer
	var body_index: int = -1
	var chest_index: int = -1
	var pile_index: int = -1
	var blueprint_index: int = -1
	var chest_foot: Vector2 = Art.footprint_foot(Rect2i(121, 120, 1, 1)) * Art.TILE
	var pile_foot: Vector2 = Art.footprint_foot(Rect2i(121, 121, 1, 1)) * Art.TILE
	var blueprint_foot: Vector2 = Art.footprint_foot(Rect2i(122, 121, 1, 1)) * Art.TILE
	for index: int in buffer.size() / 16:
		var offset: int = index * 16
		var point := Vector2(buffer[offset + 3], buffer[offset + 7])
		if int(buffer[offset + 15]) & 128:
			if point == chest_foot: chest_index = index
			if point == pile_foot: pile_index = index
			if point == blueprint_foot: blueprint_index = index
		elif point == game.frame.positions[0] * Art.TILE: body_index = index
	check(chest_index >= 0 and body_index > chest_index, "Furniture south-edge sorting hid a player standing in front")
	check(pile_index >= 0 and pile_index < body_index and blueprint_index >= 0 and blueprint_index < body_index, "Ground items or pending blueprints covered the character's feet")
	await capture("ground-foot-and-passage")
	game.controls.action("pause", {})
	check(await until(func(): return not game.frame.paused), "Movement GUI did not resume")
	for strike: int in 3:
		var point: Vector2 = game.view.project(Vector2(122.0,120.5)*Art.TILE)
		await mouse(MOUSE_BUTTON_LEFT, true, point)
		await mouse(MOUSE_BUTTON_LEFT, false, point)
		await create_timer(0.31).timeout
		check(game.frame.terrain.can_stand(game.frame.positions[0], game.frame.radii[0]), "Native wall-facing melee left an overlapping body")
	await capture("diagonal-wall-attacks")
	await until(func(): return not game.frame.combat.has(1), 500)
	var before: Vector2 = game.frame.positions[0]
	await key(KEY_D, true)
	await create_timer(0.50).timeout
	await key(KEY_D, false)
	check(game.frame.positions[0].x - before.x > 2.0 and game.frame.terrain.can_stand(game.frame.positions[0], game.frame.radii[0]), "Native movement could not leave contact and traverse the south passage")
	game.controls.action("pause", {})
	await until(func(): return game.frame.paused)
	game.controls._select(chest, -1)
	await capture("passed-below-furniture")
	game.queue_free()
	await process_frame
	await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://movement-ui-controls.cfg", "user://movement-ui-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("MOVEMENT_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
