extends "res://tests/abilities_ui_smoke.gd"
## Real atlas, station display and file restore. Isolated fixture, no user save.
const World = preload("res://scripts/sim/kernel/world.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")
const SessionIO = preload("res://scripts/sim/kernel/session_io.gd")
const Art = preload("res://scripts/presentation/art.gd")

func capture(name_key: String) -> void:
	var directory: String = "res://logs/work-positions-ui/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + name_key + ".png")

func _run() -> void:
	var w := World.new()
	w.initialize(24, 0)
	for actor: int in w.actor_slots:
		w.release(actor)
		w.objects.records[actor].autonomous = false
		w.pages[0].modes[actor - 1] = w.Units.Mode.IDLE
	w.pages[0].positions[0] = Vector2(120.5, 119.5)
	w.objects.claim(w.source_objects[0], 1, "wood", 40)
	var sites: Array[int] = []
	for entry: Array in [["wood_wall", 118, 120, 0], ["wood_table", 121, 120, 0], ["long_bed", 125, 120, 0], ["wood_table", 128, 120, 1]]:
		var site: Dictionary = w.facilities.blueprint(w, 1, entry[0], w.Terrain.index(Vector2i(entry[1], entry[2])), entry[3])
		check(site.reason == "accepted", "GUI construction fixture failed")
		if site.reason == "accepted":
			sites.append(site.target)
			w.objects.records[site.target].remaining_ms = 1000
			check(w.facilities.start_construction(w, site.target, 0) == "started", "GUI site could not start")
	var stove: int = w.facilities.seed_fixture(w, "cook_stove", w.Terrain.index(Vector2i(122, 123)))
	w.flush_topology()
	w.perception.update(w, 0, true)
	var path: String = "user://work-positions-ui.reol"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var({"format": SessionIO.FORMAT, "state": Persistence.capture(w)}, false)
	file.close()
	game = Game.new()
	game._fps = 60
	game.controls.bindings.config_path = "user://work-positions-ui-controls.cfg"
	game.feedback.config_path = "user://work-positions-ui-feedback.cfg"
	game.paused = true
	game.runner.control(true, 1)
	root.add_child(game)
	current_scene = game
	root.grab_focus()
	if not await until(func(): return game.frame != null): check(false, "Work UI never ready"); quit(1); return
	game.ui.apply_scale(150, false)
	game.controls.action("context", {})
	var epoch: int = game.frame.epoch
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "Work UI file did not load")
	game.following = false
	game.camera.position = Vector2(123.5, 121.5) * 32
	game.camera.zoom = Vector2.ONE * 1.5
	game.camera.force_update_scroll()
	game.controls._select(stove, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == stove), "Cooking station detail not published")
	check(game.ui._target.work_cells.craft.size() == 1, "Single cooking cell absent from detached UI")
	check(Art.catalog().entries.has("construction_0") and Art.catalog().entries.has("construction_15"), "Joined unfinished sprites missing from runtime atlas")
	for site: int in sites:
		check(game.frame.perception.memories.get(site, {}).get("construction_started", false), "Observed unfinished stage lost during file restore")
	await capture("unfinished-and-station")
	game.controls._select(sites[1], -1)
	check(await until(func(): return game.ui._target.get("id", 0) == sites[1]), "Unfinished detail not published")
	check(game.ui._inspect_values.text.contains("施工中"), "Unfinished site still described as a placement preview")
	var action: Button
	for child: Node in game.ui._commands.get_children():
		if child is Button and child.text == "施工": action = child
	check(action != null, "Continue construction button missing")
	if action != null: await click(action)
	game.controls.action("pause", {})
	check(await until(func(): return not game.frame.paused), "Construction GUI failed to resume")
	check(await until(func(): return game.object_canvas.objects.get(sites[1], {}).get("kind", "") == "table", 4000), "Native continuation did not complete the actual site")
	check(await until(func(): return game.ui._target.get("kind", "") == "table"), "Completed detail stayed at the unfinished stage")
	await capture("continued-complete")
	game.queue_free()
	await process_frame
	await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://work-positions-ui-controls.cfg", "user://work-positions-ui-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("WORK_POSITIONS_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
