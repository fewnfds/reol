extends SceneTree
const Game = preload("res://scripts/presentation/game.gd")
const Bindings = preload("res://scripts/presentation/ui/input_bindings.gd")
var errors: int = 0
var game: Node2D
const PROFILE: String = "user://p1-control-ui-smoke.cfg"

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok: errors += 1; push_error(message)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.shift_pressed = code == KEY_SHIFT and pressed
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func tap(code: Key) -> void:
	await key(code, true)
	await key(code, false)

func mouse(button: MouseButton, pressed: bool, at: Vector2) -> void:
	Input.warp_mouse(at)
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = at
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func click(button: Button) -> void:
	if button == null: check(false, "Expected modal button missing"); return
	var point: Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
	await mouse(MOUSE_BUTTON_LEFT, true, point)
	await mouse(MOUSE_BUTTON_LEFT, false, point)

func named_button(text: String) -> Button:
	for child: Node in game.ui._modal_body.find_children("*", "Button", true, false):
		if child.text == text: return child
	return null

func capture(name_key: String) -> void:
	var directory: String = "res://logs/control-ui/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + name_key + ".png")

func launch() -> void:
	game = Game.new(); game._opening = "development"
	game.controls.bindings.config_path = PROFILE
	root.add_child(game)
	current_scene = game
	await RenderingServer.frame_post_draw
	root.grab_focus()
	var focus_until: int = Time.get_ticks_usec()+700000
	while (not root.has_focus() or not game.controls._focused) and Time.get_ticks_usec()<focus_until: await process_frame
	check(root.has_focus() and game.controls._focused,"Control window did not acquire focus")
	var deadline: int = Time.get_ticks_usec() + 2000000
	while game.frame == null and Time.get_ticks_usec() < deadline: await process_frame
	check(game.frame != null, "Control game never ready")

func aim(direction: Vector2) -> void:
	game.camera.force_update_scroll()
	var screen: Vector2 = game.view.project((game._displayed(1) + direction * 3) * game.TILE, false)
	Input.warp_mouse(screen)
	await create_timer(0.08).timeout

func directions() -> void:
	game.ui.hide()
	game.following = false
	for zoom: float in [0.6, 1.25]:
		game.camera.zoom = Vector2.ONE * zoom
		game.camera.position = game._displayed(1) * game.TILE + Vector2(40, -20)
		await aim(Vector2.UP)
		check(game.controls._aim.dot(Vector2.UP) > 0.999, "Scaled/free-camera mouse aim diverged")
	game.camera.zoom = Vector2.ONE * 0.9
	game.following = true
	await process_frame
	await process_frame
	await aim(Vector2.UP)
	await key(KEY_S, true)
	var moved_until: int = Time.get_ticks_usec()+500000
	while game._display_move.dot(Vector2.DOWN)<0.99 and Time.get_ticks_usec()<moved_until: await process_frame
	check(game._display_move.dot(Vector2.DOWN) > 0.99 and game.controls._aim.dot(Vector2.UP) > 0.9, "Backpedal coupled movement and aim: move=%s aim=%s held=%s focused=%s" % [game._display_move,game.controls._aim,game.controls._held,game.controls._focused])
	await capture("backpedal")
	await key(KEY_S, false)
	await aim(Vector2.RIGHT)
	await key(KEY_W, true)
	await create_timer(0.12).timeout
	await capture("strafe")
	await key(KEY_W, false)
	await create_timer(0.04).timeout
	var before: Vector2 = game.controls._aim
	Input.warp_mouse(game.view.project(game._displayed(1) * game.TILE, false))
	await process_frame
	await process_frame
	check(game.controls._aim.dot(before) > 0.9999, "Center deadzone reset aim: %s -> %s" % [before, game.controls._aim])
	await key(KEY_D, true)
	await tap(KEY_R)
	await tap(KEY_Q)
	check(game.controls.move_vector().x > 0.9, "Q/R still cleared held movement")
	await key(KEY_D, false)
	game.ui.show()

func settings() -> void:
	await tap(KEY_ESCAPE)
	await click(named_button("设置"))
	await click(named_button("键位设置"))
	check(game.ui.modal_kind() == "bindings" and game.paused, "Bindings editor did not use pause context")
	var editor: Control = game.ui.binding_editor
	var sequence: int = game.runner._next_seq
	await click(editor._buttons.act_primary)
	await tap(KEY_K)
	check(game.controls.bindings.values.act_primary.code == KEY_K and game.runner._next_seq == sequence, "Captured attack key leaked into world or failed to bind")
	check(game.ui._weapon.text.contains("K") and game.ui._weapon.text.contains(preload("res://scripts/sim/kernel/action_defs.gd").ACTIONS[game.frame.loadout.primary].title), "HUD did not follow primary binding")
	await click(editor._buttons.act_step)
	await tap(KEY_SHIFT)
	check(game.controls.bindings.values.act_step.code == KEY_SHIFT, "UI could not bind standalone Shift")
	check(editor._guard.is_empty(), "Shift release left a stale capture guard")
	await click(editor._buttons.act_step)
	await tap(KEY_SHIFT)
	check(editor.capture_action.is_empty() and editor._guard.is_empty(), "Shift could not be captured again in the same screen")
	await click(editor._buttons.game_heal)
	await tap(KEY_I)
	check(editor._swap.is_empty() and game.controls.bindings.values.game_heal.code == KEY_R, "UI offered unsafe R/I third-party swap")
	await tap(KEY_ESCAPE)
	check(game.ui.modal_kind() == "bindings" and editor.capture_action.is_empty(), "Capture Escape closed the settings screen")
	await click(editor._buttons.act_primary)
	await tap(KEY_R)
	check(not editor._swap.is_empty() and game.controls.bindings.values.act_primary.code == KEY_K, "Safe swap applied without confirmation or was not offered")
	await click(named_button("确认交换"))
	check(game.controls.bindings.values.act_primary.code == KEY_R and game.controls.bindings.values.game_heal.code == KEY_K, "Confirmed swap did not apply atomically")
	await click(editor._buttons.act_primary)
	await tap(KEY_K)
	await click(named_button("确认交换"))
	await click(editor._buttons.game_interact)
	await mouse(MOUSE_BUTTON_XBUTTON1, true, Vector2(500, 260))
	await mouse(MOUSE_BUTTON_XBUTTON1, false, Vector2(500, 260))
	check(game.controls.bindings.values.game_interact.kind == "mouse", "Game action could not bind to mouse")
	await click(editor._buttons.game_heal)
	await mouse(MOUSE_BUTTON_XBUTTON2, true, Vector2(500, 260))
	await mouse(MOUSE_BUTTON_XBUTTON2, false, Vector2(500, 260))
	await capture("bindings")
	await click(editor._buttons.act_primary)
	game.controls._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	game.controls._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	check(editor.capture_action.is_empty() and editor._guard.is_empty(), "Focus loss retained key capture")
	game.ui.apply_scale(200, false)
	await process_frame
	await process_frame
	check(game.ui._modal_panel.get_global_rect().end.y <= root.size.y + 1, "Bindings panel overflowed at 200% UI scale")
	await capture("bindings-large")
	var window_size: Vector2i = root.size
	root.size = Vector2i(960, 540)
	await process_frame
	await process_frame
	var reset_button: Button = named_button("恢复默认")
	var footer_end: Vector2 = reset_button.get_global_transform_with_canvas() * reset_button.size
	check(footer_end.y <= root.get_visible_rect().size.y, "Bindings footer was clipped after shrinking the window")
	root.size = window_size
	game.ui.apply_scale(100, false)
	await tap(KEY_ESCAPE)
	check(game.ui.modal_kind() == "settings" and game.paused, "Bindings Escape skipped settings")
	await tap(KEY_ESCAPE)
	check(game.ui.modal_kind() == "pause" and game.paused, "Settings Escape skipped pause menu")
	await tap(KEY_ESCAPE)
	check(game.ui.modal_kind().is_empty() and not game.paused, "Pause Escape did not restore play")

func rebound_play() -> void:
	game.ui.hide()
	var selected: int = game.selected
	await mouse(MOUSE_BUTTON_LEFT, true, Vector2(810, 315))
	await mouse(MOUSE_BUTTON_LEFT, false, Vector2(810, 315))
	check(game.selected == selected and not game.frame.combat.has(1), "Unbound left click fell back to selection/attack")
	await aim(Vector2.RIGHT)
	await tap(KEY_K)
	await aim(Vector2.UP)
	check(game.frame.combat.get(1, {}).get("direction", Vector2.ZERO).dot(Vector2.RIGHT) > 0.99 and game.controls._aim.dot(Vector2.UP) > 0.99, "Free aim changed committed swing direction")
	await capture("locked-aim")
	await create_timer(0.3).timeout
	await tap(KEY_SHIFT)
	check(game.frame.cooldowns.get("step", 0) > game.frame.world_ms, "Rebound Shift did not execute step")
	await create_timer(0.25).timeout
	var seq: int = game.runner._next_seq
	await mouse(MOUSE_BUTTON_XBUTTON2, true, Vector2(810, 315))
	await mouse(MOUSE_BUTTON_XBUTTON2, false, Vector2(810, 315))
	check(game.runner._next_seq == seq + 1, "Rebound game action was still restricted to keyboard events")
	game.ui.show()

func _run() -> void:
	DirAccess.remove_absolute(PROFILE)
	await launch()
	if game.frame == null: quit(1); return
	await directions()
	await settings()
	await rebound_play()
	game.queue_free()
	await process_frame
	await launch()
	check(game.controls.bindings.values.act_primary.code == KEY_K and game.controls.bindings.values.act_step.code == KEY_SHIFT and game.controls.bindings.values.game_interact.kind == "mouse", "Game restart did not preserve key/mouse preferences")
	check(game.ui._weapon.text.contains("K") and game.ui._weapon.text.contains(preload("res://scripts/sim/kernel/action_defs.gd").ACTIONS[game.frame.loadout.primary].title), "Restarted HUD showed default keys")
	game.controls.action("pause_menu", {})
	game.controls.action("settings", {})
	game.controls.action("bindings", {})
	await process_frame
	await click(named_button("恢复默认"))
	check(game.controls.bindings.values == Bindings.defaults() and game.ui._weapon.text.contains("左键") and game.ui._weapon.text.contains(preload("res://scripts/sim/kernel/action_defs.gd").ACTIONS[game.frame.loadout.primary].title), "Restore defaults left stale inputs or HUD")
	await capture("defaults")
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(PROFILE)
	print("CONTROL_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
