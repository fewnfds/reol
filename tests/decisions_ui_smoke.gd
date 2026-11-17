extends "res://tests/abilities_ui_smoke.gd"
## Real renderer/input and disk restore of the shared decision implementation.
func capture(name_key: String) -> void:
	var directory: String = "res://logs/decisions-ui/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + name_key + ".png")

func acted(actor: int, kinds: Array) -> bool:
	return game.frame.combat.get(actor, {}).get("kind", "") in kinds

func native_input_ready() -> bool:
	# Startup/window activation is asynchronous; injected keys still obey native focus.
	await RenderingServer.frame_post_draw
	root.grab_focus()
	var ready: bool = await until(func(): return root.has_focus() and game.controls._focused, 700)
	check(ready, "Decision UI window did not acquire native input focus")
	return ready

func _run() -> void:
	game = Game.new(); game._opening = "development"
	game._combat_lab = true
	game._fps = 60
	game.controls.bindings.config_path = "user://p5-decisions-ui-controls.cfg"
	game.feedback.config_path = "user://p5-decisions-ui-feedback.cfg"
	root.add_child(game)
	current_scene = game
	if not await until(func(): return game.frame != null): check(false, "P5 lab never ready"); quit(1); return
	if not await native_input_ready(): quit(1); return
	await reset("light")
	check(await until(func(): return acted(24, ["slash_1", "slash_2", "slash_3"]), 3000), "Pressure policy never executed a real combination")
	check(game.frame.decision_trace.any(func(entry: Dictionary): return entry.actor == 24 and entry.result == "sequence"), "Pressure sequence not published in detached diagnostics")
	await capture("light-pressure")
	if not await native_input_ready(): quit(1); return
	await key(KEY_A, true)
	await key(KEY_SPACE, true)
	await key(KEY_SPACE, false)
	await key(KEY_A, false)
	check(await until(func(): return game.frame.cooldowns.has("step"), 500), "Native defensive input stopped working with NPC policies")
	await reset("heavy")
	check(await until(func(): return acted(23, ["enemy_heavy"]), 3000), "Heavy policy never started its real committed strike")
	await capture("heavy-commitment")
	await reset("mixed")
	check(await until(func(): return acted(22, ["enemy_shot", "enemy_fan"]), 3000), "Ranged policy never actually fired")
	await capture("mixed-ranged")
	game.controls._select(22, -1)
	check(await until(func(): return game.frame.inspected.get("decision", {}).get("policy", "") == "ranged"), "Selected actor strategy was not published")
	game.controls.action("pause", {})
	check(await until(func(): return game.frame.paused), "Pause failed")
	var saved: Dictionary = game.frame.inspected.decision.duplicate(true)
	var hp: PackedInt32Array = game.frame.health.duplicate()
	var world_ms: int = game.frame.world_ms
	var epoch: int = game.frame.epoch
	var path: String = "user://p5-decisions-ui.reol"
	var sequence: int = game.runner.send({"kind": "save", "path": path})
	check(await until(func(): return game._last_receipt.contains("save #%d " % sequence) and game._last_receipt.ends_with(": saved"), 4000), "P5 disk save failed")
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch, 4000), "P5 disk load failed")
	check(game.frame.world_ms == world_ms and game.frame.health == hp, "File restore advanced combat while paused")
	game.controls._select(22, -1)
	check(await until(func(): return game.frame.inspected.get("id", 0) == 22), "Restored NPC inspection was not acknowledged")
	var adopted: Dictionary = game.frame.inspected.get("decision", {}).duplicate(true)
	saved.erase("choice")
	adopted.erase("choice") # Diagnostic caches are intentionally rebuilt.
	check(adopted == saved, "File restore changed policy memory or task state")
	await capture("strategy-restored")
	await key(KEY_F12, true)
	await key(KEY_F12, false)
	var console: Node = game._debug_console
	check(console != null and console.is_open(), "F12 diagnostics did not open")
	if console != null:
		console._command.text = "decisions"
		await key(KEY_ENTER, true)
		await key(KEY_ENTER, false)
		check(console._output.text.contains("ranged") and console._output.text.contains("task"), "Decision command lost selected policy or task output")
		await capture("decision-diagnostics")
	await key(KEY_F12, true)
	await key(KEY_F12, false)
	game.controls.action("pause", {})
	if not await native_input_ready(): quit(1); return
	await key(KEY_A, true)
	await key(KEY_SPACE, true)
	await key(KEY_SPACE, false)
	var before: Vector2 = game.frame.positions[0]
	await create_timer(0.20).timeout
	await key(KEY_A, false)
	check(game.frame.positions[0].distance_to(before) > 0.2, "Manual movement lost control after restore")
	await until(func(): return not game.frame.combat.has(1), 600)
	await attack(MOUSE_BUTTON_LEFT, 24)
	check(await until(func(): return game.frame.player.get("events", []).any(func(event: Dictionary): return event.kind == "action_started" and event.get("actor") == 1 and event.at_ms >= world_ms), 400), "Native attack failed after restore")
	await capture("manual-control")
	game.queue_free()
	await process_frame
	await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://p5-decisions-ui-controls.cfg", "user://p5-decisions-ui-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("DECISIONS_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
