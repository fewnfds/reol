extends "res://tests/settlement_ui_smoke.gd"
## The actual product opening, native resource gathering and contact workflow.
## No state injection, shortened work or imposed NPC acceptance.

func open_messages() -> void:
	game.controls._select(1, -1)
	check(await until(func(): return game.ui._target.get("id", 0) == 1), "Normal player inspection did not replace the previous selected frame")
	if game.ui._drawer_name != "character": game.controls.action("character", {})
	check(await until(func(): return game.ui.character != null and game.ui.character.subject_id == 1), "Normal player messages did not open")
	var tabs: TabContainer = game.ui.character._tabs
	for index: int in tabs.get_tab_count():
		if tabs.get_tab_title(index) == "约定": tabs.current_tab = index
	await process_frame; await process_frame

func message_button(label_text: String) -> Button:
	if game.ui.character == null: return null
	for row: Node in game.ui.character._requests.get_children():
		for child: Node in row.get_children():
			if child is Button and child.text == label_text: return child
	return null

func _run() -> void:
	game = Game.new()
	game.controls.bindings.config_path = "user://settlement-participation-controls.cfg"
	game.feedback.config_path = "user://settlement-participation-feedback.cfg"
	game.paused = true; game.runner.control(true, 1)
	root.add_child(game); current_scene = game; root.grab_focus()
	check(await until(func(): return game.frame != null, 8000), "Product opening failed")
	if game.frame == null: game.queue_free(); quit(1); return
	game.controls.action("context", {})
	game.controls.action("place_build", {"definition": "wood_floor"})
	game.controls._confirm_tool(Vector2(132.5, 122.5))
	check(game.ui._receipt.text.contains("材料") and game.controls.tool == "build", "Missing building material was silently ignored")
	game.controls.cancel_tool()
	var source: int = 0
	for id: int in game.frame.objects:
		var record: Dictionary = game.frame.objects[id]
		if record.definition == "spirit_bamboo" and record.tile == game.controls.Terrain.index(Vector2i(134, 118)): source = id
	check(source > 0, "Actual nearby finite timber source was absent")
	if source == 0: game.queue_free(); quit(1); return
	await select_and_press(source, "拔除")
	await resume()
	check(await until(func(): return game.frame.player.inventory.get("wood", 0) == 8 and game.frame.player.action.is_empty(), 12000), "Normal player never acquired real timber by felling the plant")
	await pause()
	check(game.frame.player.inventory.get("wood", 0) == 8, "Normal resource access was replaced by a gift")
	game.controls.action("place_build", {"definition": "wood_floor"})
	game.controls._confirm_tool(Vector2(132.5, 122.5))
	check(await until(func(): return game.ui._target.get("kind") == "blueprint"), "Native placement did not select its actual prepaid work site")
	var site: int = int(game.ui._target.get("id", 0))
	check(game.frame.player.inventory.get("wood", 0) == 7, "Native work site did not consume its real material exactly once")
	var button: Button = command_button("协作")
	check(button != null and not button.disabled, "Normal work site had no collaboration entrance")
	if button != null: await click(button)
	check(game.controls.tool == "worker", "Native collaboration button did not enter fellow-member selection")
	var helper: int = 24
	var point: Vector2 = game.view.project(game._displayed(helper) * game.TILE - Vector2(0, 16), false)
	check(game.controls.pick(game.controls.pointer_world(point)).has(helper), "Normal helper's visible sprite could not be picked")
	await capture("normal-collaboration-select")
	await mouse(MOUSE_BUTTON_LEFT, true, point); await mouse(MOUSE_BUTTON_LEFT, false, point)
	check(await until(func(): return game.frame.player.action.get("kind") == "request_help"), "Native collaboration selection did not submit the shared contact action")
	await resume()
	check(await until(func(): return not game.frame.player.get("requests", []).is_empty(), 10000), "Normal player never delivered the collaboration request")
	check(await until(func(): return game.frame.player.requests[0].state != "pending", 10000), "Autonomous fellow member never answered the delivered request")
	await pause()
	print("NORMAL_COLLABORATION_REPLY ", game.frame.player.requests)
	check(game.frame.player.requests[0].state == "accepted", "Healthy normal fellow member chose not to accept this available short task")
	await open_messages()
	check(await until(func(): return message_button("当面核对") != null), "Native request view lost its contact progress check")
	await capture("normal-collaboration-accepted")
	game.controls.action("close_drawer", {})
	await resume()
	check(await until(func(): return game.frame.objects.get(site, {}).get("kind", "blueprint") != "blueprint", 7000), "Autonomous helper promised but never actually completed the work")
	await pause()
	await open_messages()
	check(await until(func(): return message_button("当面核对") != null), "The completed work's native contact button never refreshed")
	button = message_button("当面核对")
	if button != null:
		game.ui.character._requests.get_parent().ensure_control_visible(button)
		await process_frame; await process_frame
		await click(button)
	await resume()
	check(await until(func(): return game.frame.player.requests[0].state == "fulfilled", 7000), "Actual completion never became a delivered contact answer")
	await pause()
	await open_messages()
	await capture("normal-collaboration-fulfilled")
	game.controls._select(helper, -1)
	check(await until(func(): return game.frame.inspected.get("id", 0) == helper), "Completed helper could not be inspected")
	check(game.frame.inspected.autonomous and not game.frame.inspected.decision.get("manual", false) and game.frame.inspected.responsibilities.is_empty(), "Collaboration stole the helper's controller or left a ghost responsibility")
	var before: int = game.frame.world_ms
	await resume()
	check(await until(func(): return game.frame.world_ms >= before + 1500, 4000), "Normal world did not continue after cooperation")
	check(game.frame.player.inventory.get("wood", 0) == 7, "Completion or contact duplicated or charged construction material again")
	game.queue_free(); await process_frame; await process_frame
	for path: String in ["user://settlement-participation-controls.cfg", "user://settlement-participation-feedback.cfg"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("SETTLEMENT_PARTICIPATION_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
