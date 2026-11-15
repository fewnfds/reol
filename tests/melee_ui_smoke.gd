extends SceneTree
const Game = preload("res://scripts/presentation/game.gd")
const Settings = preload("res://scripts/presentation/feedback_settings.gd")
const Sound = preload("res://scripts/presentation/combat_audio.gd")
var game: Node2D
var errors: int = 0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok: errors += 1; push_error(message)

func until(test: Callable, milliseconds: int = 2500) -> bool:
	var deadline: int = Time.get_ticks_msec() + milliseconds
	while not test.call() and Time.get_ticks_msec() < deadline: await process_frame
	return test.call()

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func aim(id: int) -> Vector2:
	game.camera.force_update_scroll()
	var point: Vector2 = game.get_canvas_transform() * (game._displayed(id) * game.TILE + game.camera.offset)
	Input.warp_mouse(point)
	await process_frame
	return point

func mouse(button: MouseButton, pressed: bool, point: Vector2) -> void:
	Input.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await process_frame
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func attack(button: MouseButton, id: int) -> void:
	var point: Vector2 = await aim(id)
	await mouse(button, true, point)
	await mouse(button, false, point)

func click(button: Button) -> void:
	var point: Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
	await mouse(MOUSE_BUTTON_LEFT, true, point)
	await mouse(MOUSE_BUTTON_LEFT, false, point)

func capture(name_key: String) -> void:
	var directory: String = "res://logs/melee-ui/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + name_key + ".png")

func reset(mode: String) -> void:
	var epoch: int = game.frame.epoch
	for child: Node in game.ui._practice_bar.get_children():
		if child is Button and child.text.begins_with({"light": "轻敌", "heavy": "重敌", "mixed": "混战"}[mode]): await click(child); break
	check(await until(func(): return game.frame.epoch > epoch and game.frame.practice_mode == mode), "Practice selection did not replace the session")

func light_fight() -> void:
	check(await until(func(): return game.frame.positions[0].distance_to(game.frame.positions[23]) < 1.5, 3000), "Light enemy never approached")
	await attack(MOUSE_BUTTON_LEFT, 24)
	check(await until(func(): return game.frame.health[23] < 120, 600), "First real sword input missed light enemy")
	await create_timer(0.10).timeout
	await attack(MOUSE_BUTTON_LEFT, 24)
	check(await until(func(): return game.frame.combat.get(1, {}).get("kind") == "slash_2", 500), "Second sword input did not chain")
	check(await until(func(): return game.frame.health[23] < 80, 500), "Second sword hit was not committed")
	await capture("light-two-hits")
	await create_timer(0.09).timeout
	await attack(MOUSE_BUTTON_LEFT, 24)
	check(await until(func(): return game.frame.combat.get(1, {}).get("kind") == "slash_3", 500), "Third sword input did not chain")
	check(await until(func(): return game.frame.health[23] <= 0, 700), "Complete sword combo failed to finish light enemy")
	await capture("light-finisher")
	check(game.combat_audio.played.get("hit", 0) > 0, "Light contact voice never played")

func heavy_fight() -> void:
	await reset("heavy")
	check(await until(func(): return game.frame.combat.get(23, {}).get("kind") == "enemy_heavy", 3000), "Heavy enemy did not telegraph")
	await capture("heavy-warning")
	await key(KEY_D, true)
	check(await until(func(): return game.frame.positions[0].distance_to(game.frame.positions[22]) < 1.45, 350), "Could not step into sword range during the heavy opening")
	await key(KEY_D, false)
	await attack(MOUSE_BUTTON_LEFT, 23)
	check(await until(func(): return game.frame.health[22] < 220, 600), "Sword did not contact heavy enemy")
	check(game.frame.combat.get(23, {}).get("kind") == "enemy_heavy", "Light contact interrupted the steady heavy opening")
	await capture("heavy-steady-contact")
	var opening: Dictionary = game.frame.combat.get(23, {})
	if not opening.is_empty():
		await until(func(): return game.frame.world_ms >= int(opening.active_ms) - 100, 700)
	await key(KEY_D, true)
	await key(KEY_SPACE, true)
	await key(KEY_SPACE, false)
	await key(KEY_D, false)
	await create_timer(0.23).timeout
	await capture("heavy-recovery-window")
	await aim(23)
	await attack(MOUSE_BUTTON_RIGHT, 23)
	check(await until(func(): return game.frame.reactions.get(23, {}).get("punished", false), 700), "Recovery heavy strike did not cause off balance")
	await capture("heavy-recovery-punish")
	check(game.frame.player.hp == 100, "Timed dash or punish caused an unavoidable trade")
	await create_timer(0.06).timeout
	check(game.combat_audio.played.get("armor", 0) > 0 and game.combat_audio.played.get("break", 0) > 0, "Steady and off-balance voices were not distinct")

func settings_and_reset() -> void:
	game.controls.action("pause_menu", {})
	game.controls.action("settings", {})
	await process_frame
	var slider: HSlider = game.ui._modal_body.find_child("feedback_shake", true, false)
	check(slider != null, "Feedback settings slider missing")
	if slider != null:
		slider.value = 0
		var loaded := Settings.new()
		loaded.config_path = game.feedback.config_path
		loaded.load_settings()
		check(loaded.shake == 0, "Feedback preference did not persist")
	await capture("settings")
	game.controls.action("close_settings", {})
	game.controls.action("resume", {})
	await process_frame
	game.ui.apply_scale(200, false)
	await process_frame
	await capture("hud-200")
	game.ui.apply_scale(100, false)
	await reset("mixed")
	check(await until(func(): return game.frame.combat.values().any(func(state: Dictionary): return state.kind == "enemy_shot"), 2500), "Mixed fight did not include readable archer")
	await capture("mixed")
	var shot: Dictionary = game.frame.combat.get(22, {})
	if not shot.is_empty():
		await until(func(): return game.render_ms >= int(shot.recovery_ms) + 60)
		await capture("archer-recovery")
	game.camera.offset = Vector2.ZERO
	game.camera.force_update_scroll()
	var screen := Vector2(650, 330)
	var before: Vector2 = game.controls.pointer_world(screen)
	game.camera.offset = Vector2(8, -6)
	game.camera.force_update_scroll()
	check(before.distance_to(game.controls.pointer_world(screen)) < 0.0001, "Camera shake contaminated aim")
	game.camera.offset = Vector2.ZERO
	check(game.frame.player.hp == 100, "Practice reset retained damage")

func death_and_reset() -> void:
	check(await until(func(): return game.frame.player.hp <= 0, 12000), "Mixed fight could not reach a real player death")
	await reset("light")
	check(game.frame.player.hp == 100, "A dead player could not restart practice")

func save_and_restore() -> void:
	game.controls.action("pause", {})
	check(await until(func(): return game.frame.paused), "Combat save never paused")
	var saved_ms: int = game.frame.world_ms
	var health: PackedInt32Array = game.frame.health.duplicate()
	var cooldowns: Dictionary = game.frame.cooldowns.duplicate(true)
	var epoch: int = game.frame.epoch
	var path: String = "user://p2-melee-ui-session.reol"
	var seq: int = game.runner.send({"kind": "save", "path": path})
	check(await until(func(): return game._last_receipt.contains("save #%d " % seq) and game._last_receipt.ends_with(": saved"), 4000), "Actual combat session did not save")
	game.controls.clear_direct()
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch, 4000), "Actual combat session did not restore")
	check(game.frame.world_ms == saved_ms and game.frame.health == health and game.frame.cooldowns == cooldowns and game.frame.combat.get(1, {}).get("kind") == "cleave", "Paused combat restore changed damage, cooldown or committed action")
	await capture("restored-combat")
	game.controls.action("pause", {})
	check(await until(func(): return game.frame.world_ms >= saved_ms + 400), "Restored action failed to finish")
	check(game.frame.health == health, "Restored active slash repeated a committed hit")
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func feedback_layers() -> void:
	var probe := Sound.new()
	root.add_child(probe)
	var at: int = game.frame.world_ms
	var contacts: Array = []
	for row: Array in [[22, true, false], [23, false, true], [24, false, false]]:
		contacts.append({"kind": "hit", "actor": 1, "target": row[0], "activation": 500, "at_ms": at, "epoch": game.frame.epoch, "armored": row[1], "off_balance": row[2]})
	probe.adopt(game.frame, contacts, false)
	probe.advance(at)
	check(probe.played.get("break", 0) == 1 and probe.played.get("armor", 0) == 0 and probe.played.get("hit", 0) == 0, "A multi-target slash stacked contact accents")
	probe.adopt(game.frame, contacts, false)
	probe.advance(at + 16)
	check(probe.played.get("break", 0) == 1, "Repeated frame adoption replayed a contact")
	probe.adopt(game.frame, [{"kind": "action_started", "action": "enemy_heavy", "actor": 23, "activation": 501, "at_ms": at}, {"kind": "hit", "actor": 23, "target": 1, "activation": 501, "at_ms": at}], false)
	probe.advance(at + 17)
	check(probe._voices[6].playing and probe._voices[7].playing, "Warning and player injury did not retain reserved voices")
	probe.adopt(game.frame, [{"kind": "hit", "actor": 23, "target": 24, "activation": 502, "at_ms": at + 50, "armored": true}], false)
	probe.advance(at + 50)
	probe.adopt(game.frame, [{"kind": "hit", "actor": 23, "target": 1, "activation": 502, "at_ms": at + 70}], false)
	probe.advance(at + 70)
	check(probe.played.get("hurt", 0) == 2, "An earlier bystander contact swallowed later player injury")
	probe.adopt(game.frame, [{"kind": "hit", "actor": 1, "target": 24, "activation": 503, "at_ms": at + 110}], false)
	probe.advance(at + 110)
	var voice: AudioStreamPlayer = probe._accents["1:503:contact"].voice
	probe.adopt(game.frame, [{"kind": "hit", "actor": 1, "target": 23, "activation": 503, "at_ms": at + 160, "off_balance": true}], false)
	probe.advance(at + 160)
	check(probe.played.get("break", 0) == 2 and probe._accents["1:503:contact"].voice == voice, "A later break did not replace the earlier accent on the same voice")
	probe.queue_free()

func _run() -> void:
	game = Game.new()
	game._combat_lab = true
	game._fps = 60
	game.controls.bindings.config_path = "user://p2-melee-ui-controls.cfg"
	game.feedback.config_path = "user://p2-melee-ui-feedback.cfg"
	root.add_child(game)
	current_scene = game
	root.grab_focus()
	if not await until(func(): return game.frame != null): check(false, "Melee game never ready"); quit(1); return
	game.runner.send({"kind": "combat_practice", "mode": "light", "loadout": "sword"})
	check(await until(func(): return game.frame.loadout.id == "sword" and game.frame.practice_mode == "light"), "Sword fixture unavailable")
	await capture("start")
	await light_fight()
	await heavy_fight()
	await save_and_restore()
	await settings_and_reset()
	feedback_layers()
	await death_and_reset()
	game.queue_free()
	await process_frame
	await process_frame
	for path: String in ["user://p2-melee-ui-controls.cfg", "user://p2-melee-ui-feedback.cfg"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("MELEE_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
