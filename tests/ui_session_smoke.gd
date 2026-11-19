extends "res://tests/abilities_ui_smoke.gd"
const Actions = preload("res://scripts/presentation/ui/actions.gd")

func capture(name_key: String) -> void:
	var directory: String = "res://logs/ui-session/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + name_key + ".png")

func build_button(text: String) -> Button:
	for child: Node in game.ui.build_menu.find_children("*", "Button", true, false):
		if child.is_visible_in_tree() and child.text == text: return child
	return null

func open_build_group(text: String) -> bool:
	var button: Button = build_button(text + "  ›")
	check(button != null, "Build category missing: " + text)
	if button == null: return false
	await click(button)
	return true

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
	check(game.ui.inventory.bag.get_child_count() == 12 and game.ui.inventory.cargo.get_child_count() == 1, "Player bag did not present 12 personal slots and one hauling slot")
	await capture("personal-bag")
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
	check(game.ui.build_menu.visible and not game.ui.inventory.visible, "Narrow drawer stayed hidden behind inventory")
	game.ui.open_bag(1)
	check(game.ui._drawer_name.is_empty() and game.ui.inventory.visible, "Opening the narrow bag kept a hidden build menu active")
	game.ui.toggle_drawer("build")
	check(game.ui.build_menu.visible and not game.ui.inventory.visible, "Returning from the narrow bag took more than one action")
	await process_frame
	await process_frame
	var selected: int = game.selected
	var reached: bool = true
	for choice: String in ["建筑", "工作", "灶台"]:
		check(game.controls.tool.is_empty() and game.ui.build_menu._leaves.is_empty(), "Materials appeared before the item was selected")
		if not await open_build_group(choice): reached = false; break
	if reached:
		var leaf: Button = game.ui.build_menu._leaves.get("cook_stove")
		check(leaf != null and leaf.is_visible_in_tree() and leaf.text.begins_with("木\n木料"), "Stove did not offer an explicit wood choice")
		check(game.ui.build_menu._columns.size() == 4 and game.ui.build_menu._leaves.size() == 1, "Single-material object did not have exactly four levels")
		check(not game.ui.build_menu._columns[0].visible and not leaf.get_global_rect().intersects(game.ui._map_panel.get_global_rect()), "Expanded build columns overran the usable screen")
		check(game.selected == selected and game.controls.tool.is_empty(), "Category click reached the world or started a placement")
		await capture("narrow-drawer")
		await key(KEY_ESCAPE, true)
		await key(KEY_ESCAPE, false)
		check(build_button("灶台  ›") != null, "Escape closed the build menu instead of returning to its parent category")
		if await open_build_group("灶台"):
			await click(game.ui.build_menu._leaves.cook_stove)
			check(game.controls.tool == "build" and game.controls.definition == "cook_stove" and not game.ui.build_menu.visible, "Material choice did not enter the original placement tool")
	game.controls.cancel_tool()
	if game.ui.build_menu.visible: game.ui.toggle_drawer("build")
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
		check(await until(func(): return game.ui._target.get("id", 0) == chest and game.ui._target.get("kind") == "chest"), "Container inspection never arrived")
		game.ui.open_stock("take", chest)
		var panel: PanelContainer = game.ui.inventory
		check(panel.visible and panel._dual, "Wide container workspace failed to open in two columns")
		game.ui.apply_scale(200, false)
		root.content_scale_size = Vector2i(700, 720)
		root.size = Vector2i(700, 720)
		await process_frame
		await process_frame
		check(not panel._dual and panel._container_sheet.is_visible_in_tree() and not panel._bag_sheet.is_visible_in_tree(), "Narrow container workspace showed both pages at once")
		game.ui.apply_scale(100, false)
		root.content_scale_size = original_size
		root.size = original_window
		game.controls._select(2, -1)
		check(not game.ui.inventory.visible, "Selection replaced the inspection but left a stale container open")
	root.gui_release_focus()
	check(await until(func(): return game.ui._target.get("id", 0) == 2), "NPC inspection never arrived")
	var person: Button
	for child: Node in game.ui._toolbar.find_children("*", "Button", true, false):
		if child.text == "人物": person = child; break
	check(person != null, "The player character button is missing")
	if person != null:
		await click(person)
		check(game.selected == 2 and game.ui.character != null and game.ui.character.subject_id == 1, "The character button followed the NPC selection")
		game.controls._select(1, -1)
		check(game.ui._drawer_name == "character", "Selecting a world actor closed the player's character panel")
		game.controls.action("close_drawer", {})
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
