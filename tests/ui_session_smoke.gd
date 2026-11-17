extends "res://tests/abilities_ui_smoke.gd"
const Actions = preload("res://scripts/presentation/ui/actions.gd")

func capture(name_key: String) -> void:
	var directory: String = "res://logs/ui-session/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + name_key + ".png")

func _run() -> void:
	game = Game.new(); game._opening = "development"
	game._fps = 60
	game.controls.bindings.config_path = "user://ui-session-controls.cfg"
	game.feedback.config_path = "user://ui-session-feedback.cfg"
	root.add_child(game)
	current_scene = game
	root.grab_focus()
	if not await until(func(): return game.frame != null): check(false, "UI session never ready"); quit(1); return
	game.ui.apply_scale(100, false)
	game.ui.context_menu({"id": 987654, "kind": "chest", "memory": true}, Vector2(600, 350), {"target": 987654})
	check(not game.ui._context_panel.visible, "A memory with no legal action opened an input-blocking empty menu")
	game.ui.close_context()
	await key(KEY_I, true)
	await key(KEY_I, false)
	check(game.ui.inventory.visible, "Inventory shortcut did not open its panel")
	await key(KEY_I, true)
	await key(KEY_I, false)
	check(not game.ui.inventory.visible, "Inventory shortcut could not close its own panel")
	game.ui.inventory.hide()
	root.gui_release_focus()
	game.following = true
	await key(KEY_RIGHT, true)
	await create_timer(0.08).timeout
	await key(KEY_RIGHT, false)
	check(not game.following, "Keyboard camera pan never disengaged follow")
	game.controls._held.clear()
	game.ui.apply_scale(200, false)
	var original_size: Vector2i = root.content_scale_size
	var original_window: Vector2i = root.size
	root.content_scale_size = Vector2i(960, 720)
	root.size = Vector2i(960, 720)
	await process_frame
	game.ui._layout()
	check(game.ui.size.x < 1100, "Narrow UI fixture did not use a narrow logical viewport")
	game.ui.open_bag(1)
	game.ui.toggle_drawer("build")
	await process_frame
	check(game.ui._drawer_panel.visible and not game.ui.inventory.visible, "Narrow drawer stayed hidden behind inventory")
	await capture("narrow-drawer")
	game.ui.inventory.hide()
	game.ui.toggle_drawer(game.ui._drawer_name)
	game.ui.apply_scale(100, false)
	root.content_scale_size = original_size
	root.size = original_window
	game.controls._select(987654, -1)
	game.controls._pending_context = {"target": 987654, "screen": Vector2(600, 350), "epoch": game.frame.epoch}
	await create_timer(0.15).timeout
	check(game.controls._pending_context.is_empty(), "Missing inspected target left a pending interaction indefinitely")
	game.controls.cancel_tool()
	game.controls._select(1, -1)
	check(await until(func(): return game.frame.inspected.get("id", 0) == 1), "Player selection never acknowledged")
	var chest: int = 0
	for id: int in game.frame.perception.memories:
		var data: Dictionary = game.frame.perception.memories[id]
		if data.kind == "chest" and game.controls._visible_object(data): chest = id; break
	check(chest > 0, "No visible chest in ordinary world fixture")
	if chest > 0:
		var admitted: int = game.controls._send({"kind": "take", "target": chest, "item": "grain", "amount": 1})
		check(admitted > 0, "Visible tool target was rejected because it was not inspected")
		game.runner.send({"kind": "interrupt"})
		game.controls._select(chest, -1)
		check(await until(func(): return game.ui._target.get("id", 0) == chest), "Container inspection never arrived")
		game.ui.open_stock("take", chest)
		check(game.ui.inventory.visible, "Container workspace failed to open")
		game.controls._select(2, -1)
		check(not game.ui.inventory.visible, "Selection replaced the inspection but left a stale container open")
	root.gui_release_focus()
	check(await until(func(): return game.ui._target.get("id", 0) == 2), "NPC inspection never arrived")
	game.ui.toggle_drawer("character")
	check(game.ui._character_id == 2, "Character drawer lost its selected subject")
	game.controls._select(1, -1)
	check(game.ui._drawer_name.is_empty(), "Selection left an NPC character panel without its inspection")
	game.controls.action("pause", {})
	check(await until(func(): return game.frame.paused), "Tool fixture pause failed")
	var floor_id: int = 0
	for id: int in game.frame.perception.memories:
		var data: Dictionary = game.frame.perception.memories[id]
		if data.kind == "floor" and Actions.visible(game.frame, id, true): floor_id = id; break
	check(floor_id > 0, "No visible floor for demolition fixture")
	if floor_id > 0:
		var tile: int = game.frame.perception.memories[floor_id].tile
		var point: Vector2 = game.controls.Terrain.center(tile)
		game.controls.action("demolish_tool", {})
		game.controls._confirm_tool(point)
		check(await until(func(): return game._last_receipt.contains("demolish #") and game._last_receipt.ends_with(": accepted")), "Demolition tool could not select a visible floor")
		game.runner.send({"kind": "interrupt"})
	game.controls.action("pause", {})
	check(await until(func(): return not game.frame.paused), "Tool fixture resume failed")
	game.controls.action("pause_menu", {})
	check(await until(func(): return game.frame.paused), "Menu pause failed")
	var path: String = "user://ui-session-edges.reol"
	var seq: int = game.runner.send({"kind": "save", "path": path})
	check(await until(func(): return game._last_receipt.contains("save #%d " % seq) and game._last_receipt.ends_with(": saved")), "Menu save failed")
	game.controls._select(2, -1)
	await until(func(): return game.frame.inspected.get("id", 0) == 2)
	var epoch: int = game.frame.epoch
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "Menu load failed")
	check(await until(func(): return not game.frame.paused and not game.paused, 500), "Menu load closed its modal but left the world paused")
	check(await until(func(): return game.frame.inspected.get("id", 0) == game.selected), "Session reset selected player but kept the old inspected NPC")
	await capture("ui-session-edges")
	game.queue_free()
	await process_frame
	await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://ui-session-controls.cfg", "user://ui-session-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("UI_SESSION_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
