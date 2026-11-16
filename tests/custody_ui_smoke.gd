extends "res://tests/abilities_ui_smoke.gd"
## Actual restored World, native stock form and real owner-side pickup.
const World = preload("res://scripts/sim/kernel/world.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")
const SessionIO = preload("res://scripts/sim/kernel/session_io.gd")

func _run() -> void:
	var w := World.new()
	w.initialize(4, 0)
	for actor: int in w.actor_slots:
		w.release(actor)
		w.objects.records[actor].autonomous = false
		w.pages[0].modes[actor - 1] = w.Units.Mode.IDLE
	var org: int = w.institutions.create("青禾宗")
	w.institutions.admit(w, org, 1, Array(w.institutions.PURPOSES))
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(124, 124)))
	var salvage: int = w.objects.create("pile", "salvage", w.Terrain.index(Vector2i(123, 124)))
	w.objects.add(salvage, "grain", 1, w.objects.Stock.right(0, org))
	w.objects.records[chest].organization = org
	w.objects.add(chest, "grain", 4, w.objects.Stock.right(0, org))
	for item: String in ["iron_sword@2", "potion"]:
		w.objects.consume(1, {item: w.objects.amount(1, item)}, w.objects.Stock.right(1))
		w.objects.add(chest, item, 1, w.objects.Stock.right(0, org))
		check(w.institutions.move_goods(w, 1, chest, item, 1, "take", {"purpose": "supply"}, 0).status == "completed", "Supply-only gear fixture refused")
	w.pages[0].positions[0] = Vector2(123.5, 124.5)
	w.flush_topology()
	w.perception.update(w, 0, true)
	var path: String = "user://custody-ui-fixture.reol"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var({"format": SessionIO.FORMAT, "state": Persistence.capture(w)}, false)
	file.close()
	game = Game.new()
	game.controls.bindings.config_path = "user://custody-ui-controls.cfg"
	game.feedback.config_path = "user://custody-ui-feedback.cfg"
	game.paused = true
	game.runner.control(true, 1)
	root.add_child(game)
	current_scene = game
	check(await until(func(): return game.frame != null), "Stock UI initial frame absent")
	var epoch: int = game.frame.epoch
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "Stock UI state did not restore")
	game.ui.apply_scale(125, false)
	game.controls._select(chest, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == chest and game.ui._target.get("organization", 0) == org), "Public chest not inspected")
	game.controls.action("take", {"target": chest})
	check(await until(func(): return game.ui.inventory.visible), "Public stock workspace absent")
	var panel: Control = game.ui.inventory
	check(await until(func(): return panel._purpose.visible and panel._donate.visible), "Public pickup had no purpose/donation controls: " + str(panel._target))
	panel.bag.select("iron_sword@2")
	check(panel._equip.disabled, "Supply-only weapon falsely offered equip")
	panel.bag.select("potion")
	check(panel._use.disabled, "Supply-only potion falsely offered personal use")
	var selected: int = -1
	for index: int in panel._purpose.item_count:
		if panel._purpose.get_item_metadata(index).get("purpose", "") == "cook": selected = index
	check(selected > 0, "Authorized cooking purpose missing")
	if selected > 0: panel._purpose.select(selected)
	panel.container.select("grain")
	panel.amount.value = 2
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs/custody-ui/"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://logs/custody-ui/before-pickup.png")
	await click(panel._take)
	check(await until(func(): return game.frame.player.action.get("purpose", "") == "cook"), "Stock form lost declared purpose in real command")
	game.controls.action("pause", {})
	check(await until(func(): return not game.frame.paused and game.frame.player.action.is_empty()), "Public pickup did not finish")
	game.controls.action("pause", {})
	panel.bag.select("grain")
	check(await until(func(): return panel._choice.text.contains("受托 2")), "Native bag failed to display mixed ownership quantities")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs/custody-ui/"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://logs/custody-ui/public-pickup.png")
	game.controls._select(salvage, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == salvage), "Ground salvage not inspected")
	game.controls.action("take", {"target": salvage})
	check(await until(func(): return panel._target.get("id", 0) == salvage and panel._purpose.visible), "Ground public goods hid the issue form")
	selected = -1
	for index: int in panel._purpose.item_count:
		if panel._purpose.get_item_metadata(index).get("purpose", "") == "cook": selected = index
	check(selected > 0, "Ground public material had no authorized issue choice")
	if selected > 0: panel._purpose.select(selected)
	panel.container.select("grain")
	panel.amount.value = 1
	await click(panel._take)
	check(await until(func(): return game.frame.player.action.get("source_organization", 0) == org), "Ground issue lost its explicit organization")
	game.controls.action("pause", {})
	check(await until(func(): return not game.frame.paused and game.frame.player.action.is_empty() and game.frame.player.inventory.grain == 11), "Ground public issue did not reach the same physical bag")
	game.queue_free()
	await process_frame
	await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://custody-ui-controls.cfg", "user://custody-ui-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("CUSTODY_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
