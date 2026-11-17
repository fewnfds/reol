extends "res://tests/institution_access_ui_smoke.gd"

func capture(name_key: String) -> void:
	var directory: String = "res://logs/teaching-ui/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + name_key + ".png")

func _run() -> void:
	var w := World.new()
	w.initialize(4, 0)
	for actor: int in w.actor_slots:
		w.release(actor); w.objects.records[actor].autonomous = false; w.objects.records[actor].side = 0
		w.livelihood.forget(actor)
		w.pages[0].positions[actor - 1] = Vector2(123.5 + actor, 124.5)
		w.clear_navigation(actor)
		w.pages[0].energy[actor - 1] = 10000; w.pages[0].hunger[actor - 1] = 10000
	w.objects.records[2].autonomous = true
	w.knowledge.refresh(w, 2, 1, 0)
	w.livelihood.add_goal(w, 2, "instruction", {"method": "wood_breath", "target": 1})
	w.decisions.resume(w, 2, 0); w.decisions.prepare(w, 0)
	while w.elapsed_ms < 300: w.step(mini(16, 300 - w.elapsed_ms))
	check(w.actions.get(2, {}).get("join_reason") == "awaiting_participant" and not w.actions.has(1), "Autonomous instructor did not offer a lesson without seizing player input")
	w.perception.update(w, w.elapsed_ms, true)
	var path: String = "user://teaching-ui-fixture.reol"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var({"format": SessionIO.FORMAT, "state": Persistence.capture(w)}, false); file.close()
	game = Game.new(); game._opening = "development"; game._actors = 4; game.speed = 1
	game.controls.bindings.config_path = "user://teaching-ui-controls.cfg"
	game.feedback.config_path = "user://teaching-ui-feedback.cfg"
	game.paused = true; game.runner.control(true, 1)
	root.add_child(game); current_scene = game; root.grab_focus()
	check(await until(func(): return game.frame != null), "Teaching GUI initial frame absent")
	var epoch: int = game.frame.epoch
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch), "Actual teaching invitation file failed to load")
	await select_and_press(2, "请教")
	check(await until(func(): return game.frame.player.action.get("kind") == "learn"), "Native learning button failed to express the player's participation")
	await resume()
	check(await until(func(): return game.frame.player.get("activity", {}).get("role") == "learner"), "Player's explicit action did not merge the NPC's offer")
	await pause()
	game.controls.action("character", {})
	check(await until(func(): return game.ui.character != null and game.ui.character.subject_id == 2 and game.ui.character._activity.text.contains("传授中")), "Actual teacher role was absent from the normal character panel")
	await capture("shared-lesson")
	var at: int = game.frame.world_ms
	var sequence: int = game.runner.send({"kind": "save", "path": path})
	check(await until(func(): return game._last_receipt.contains("save #%d " % sequence) and game._last_receipt.ends_with(": saved")), "Actual shared lesson could not be saved")
	epoch = game.frame.epoch; game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch and game.frame.world_ms == at), "Actual shared lesson did not restore its boundary")
	check(game.frame.player.activity.get("role") == "learner" and game.frame.player.action.kind == "learn", "Restored teaching lost the player's own host")
	await resume()
	check(await until(func(): return game.frame.player.get("methods", {}).get("wood_breath", {}).get("understanding", 0) >= 200, 2500), "Restored shared lesson did not actually teach the player")
	await pause()
	game.controls._select(1, -1)
	game.controls.action("character", {})
	check(await until(func(): return game.ui.character != null and game.ui.character.subject_id == 1), "Player's learned method panel did not open")
	game.ui.character._tabs.current_tab = 1
	await process_frame; await process_frame
	check(game.ui.character._practice.text.contains("木息法") and game.ui.character._practice.text.contains("实践 0/1000"), "Normal UI confused understanding with practical mastery")
	await capture("player-learned")
	game.queue_free(); await process_frame; await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://teaching-ui-controls.cfg", "user://teaching-ui-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("TEACHING_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
