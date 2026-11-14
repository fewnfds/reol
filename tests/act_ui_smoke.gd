extends SceneTree
const Game = preload("res://scripts/presentation/game.gd")
var errors: int = 0
var game: Node2D

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok: errors += 1; push_error(message)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func mouse(button: MouseButton, pressed: bool, at: Vector2) -> void:
	Input.warp_mouse(at)
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = at
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func capture(name_key: String) -> void:
	var directory: String = "res://logs/act-ui/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + name_key + ".png")

func player_shots() -> int:
	return game.frame.player.get("events", []).filter(func(event: Dictionary): return event.kind == "action_active" and event.get("action") == "shot").size()

func _run() -> void:
	game = Game.new()
	root.add_child(game)
	current_scene = game
	var deadline: int = Time.get_ticks_usec() + 2000000
	while game.frame == null and Time.get_ticks_usec() < deadline: await process_frame
	if game.frame == null: check(false, "ACT game never ready"); quit(1); return
	game.ui.hide()
	await key(KEY_D, true)
	var start: Vector2 = game.frame.positions[0]
	await create_timer(0.25).timeout
	await key(KEY_D, false)
	check(game.frame.positions[0].x > start.x + 0.5, "D did not move right")
	await create_timer(0.08).timeout
	var stopped: Vector2 = game.frame.positions[0]
	await create_timer(0.1).timeout
	check(game.frame.positions[0].is_equal_approx(stopped), "D release did not stop")
	await key(KEY_A, true)
	check(game.controls.tool.is_empty() and game.controls.move_vector().x < 0, "A still selected an RTS attack tool")
	await key(KEY_A, false)
	await key(KEY_H, true)
	await key(KEY_H, false)
	check(not game.runner.poll().receipts.any(func(receipt: Dictionary): return receipt.kind == "hold"), "H still issued guard")
	await key(KEY_S, true)
	check(game.controls.move_vector().y > 0, "S still issued stop instead of moving down")
	game.controls._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await create_timer(0.06).timeout
	check(game.controls.move_vector() == Vector2.ZERO, "Focus loss retained held movement")
	await key(KEY_S, false)
	game.ui.show()
	await key(KEY_TAB, true)
	await key(KEY_TAB, false)
	check(not game.controls.direct, "Tab did not enter interaction context")
	await key(KEY_A, true)
	check(game.controls.move_vector().is_zero_approx() and game.controls.tool.is_empty(), "Interaction mode leaked movement or old attack tool")
	await key(KEY_A, false)
	await key(KEY_TAB, true)
	await key(KEY_TAB, false)
	check(game.controls.direct, "Tab did not return to ACT")
	for action: String in ["attack_move", "stop", "hold", "move_tool"]:
		check(not game.ui._player_buttons.has(action), "Old RTS button remains: " + action)
	await key(KEY_F, true)
	await key(KEY_F, false)
	await create_timer(0.08).timeout
	check(game.ui._context_panel.visible and game.selected > 1, "F did not inspect a nearby visible interaction target")
	await key(KEY_ESCAPE, true)
	await key(KEY_ESCAPE, false)
	await capture("controls")
	game.ui.hide()
	var point := Vector2(820, 320)
	await mouse(MOUSE_BUTTON_LEFT, true, point)
	await mouse(MOUSE_BUTTON_LEFT, false, point)
	check(game.frame.combat.get(1, {}).get("kind") == "slash_1", "Left mouse did not start sword action")
	deadline = Time.get_ticks_usec() + 300000
	while not game.combat_audio._voices.any(func(voice: AudioStreamPlayer): return voice.playing) and Time.get_ticks_usec() < deadline: await process_frame
	check(game.combat_audio._voices.any(func(voice: AudioStreamPlayer): return voice.playing), "Active attack did not trigger its audio voice")
	await capture("slash")
	await create_timer(0.15).timeout
	await mouse(MOUSE_BUTTON_RIGHT, true, point)
	await mouse(MOUSE_BUTTON_RIGHT, false, point)
	check(game.frame.combat.get(1, {}).get("kind") == "cleave" and game.frame.cooldowns.get("skill", 0) > game.frame.world_ms, "Right mouse did not start a cooldown weapon skill")
	await create_timer(0.6).timeout
	await key(KEY_2, true)
	await key(KEY_2, false)
	await create_timer(0.06).timeout
	check(game.frame.player.equipment.get("weapon") == "short_bow", "2 did not equip the real bow")
	var shots: int = player_shots()
	await mouse(MOUSE_BUTTON_LEFT, true, point)
	await create_timer(0.6).timeout
	await capture("bow")
	await mouse(MOUSE_BUTTON_LEFT, false, point)
	check(player_shots() >= shots + 2, "Holding left mouse did not repeat bow shots")
	shots = player_shots()
	await create_timer(0.45).timeout
	check(player_shots() == shots, "Mouse release kept shooting")
	var before_step: Vector2 = game.frame.positions[0]
	await key(KEY_SPACE, true)
	await key(KEY_SPACE, false)
	await create_timer(0.24).timeout
	check(game.frame.positions[0].distance_to(before_step) > 1.8, "Space did not execute a neutral backstep")
	game.ui.show()
	await key(KEY_D, true)
	game.controls.action("inventory", {})
	await create_timer(0.05).timeout
	check(game.controls.move_vector().is_zero_approx() and not game.controls._primary_down, "Opening inventory retained continuous intent")
	game.ui.inventory.hide()
	var echo_event := InputEventKey.new()
	echo_event.physical_keycode = KEY_D
	echo_event.pressed = true
	echo_event.echo = true
	Input.parse_input_event(echo_event)
	await process_frame
	check(game.controls.move_vector().is_zero_approx(), "Key repeat resumed movement without a fresh press")
	await key(KEY_D, false)
	await key(KEY_D, true)
	game.controls.action("pause", {})
	await create_timer(0.05).timeout
	check(game.controls.move_vector().is_zero_approx(), "Pause retained held movement")
	await key(KEY_SPACE, true)
	await key(KEY_SPACE, false)
	var paused_position: Vector2 = game.frame.positions[0]
	game.controls.action("pause", {})
	await create_timer(0.12).timeout
	check(game.frame.positions[0].is_equal_approx(paused_position), "Resume replayed held movement or queued a paused attack")
	await key(KEY_D, false)
	await key(KEY_B, true)
	await key(KEY_B, false)
	check(not game.controls.direct and game.ui._drawer_name == "build", "B did not enter construction context from ACT")
	game.controls.action("place_build", {"definition": "long_bed"})
	var facing: int = game.controls.facing
	await key(KEY_R, true)
	await key(KEY_R, false)
	check(game.controls.facing == (facing + 1) % 4, "Construction R was consumed as the ACT potion key")
	await key(KEY_ESCAPE, true)
	await key(KEY_ESCAPE, false)
	await key(KEY_TAB, true)
	await key(KEY_TAB, false)
	print("ACT_UI_SMOKE errors=", errors)
	game.queue_free()
	await process_frame
	quit(0 if errors == 0 else 1)
