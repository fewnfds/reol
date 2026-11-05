extends SceneTree
## Native asynchronous regression for the inspector covering overlapping icons.
## Run with --script res://tools/qa/object_inspection_cycle.gd. Custody assignments
## below arrange a presentation fixture, not a claim of gameplay transport.

const Codec = preload("res://scripts/persistence/snapshot_values.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(25.0, true, false, true).timeout.connect(func() -> void: _fail("timeout"))
	root.size = Vector2i(1600, 900)
	var clock: Node = root.get_node("GameClock")
	clock.set_paused(true)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	# Resolve runtime classes after autoloads exist; preloading their types in a
	# standalone SceneTree would compile GameClock users before registration.
	var runtime: Node = main._continuity
	if not runtime.select_starting_avatar("subject:player"):
		_fail("human opening refused")
		return
	clock.set_paused(true)
	var adapter: Node = runtime.object_adapter
	var domain: RefCounted = runtime.world_sim.artifacts
	domain.objects.training_sword.container = "actor:player"
	domain.objects.amber_pearl.container = "actor:player"
	var kitchen: Vector2i = domain.object_cell("hearth_stone")
	main.player.spawn_at(kitchen)
	main.player.global_position += Vector2(0, 16)
	runtime.prepare_player_command()
	main.fog.set_focus(kitchen)
	main.fog.update_now()
	main.camera.global_position = main.player.global_position + Vector2(91, -57)
	main.camera.zoom = Vector2(1.3, 1.3)
	main.camera.force_update_scroll()
	var collision: Vector2 = adapter._display_point("hearth_stone")
	if not collision.is_equal_approx(adapter._display_point("amber_pearl")):
		_fail("fixture did not overlap")
		return
	var before: String = Codec.canonical_json(Codec.normalized(runtime.world_sim.to_dict()))
	adapter.reset_observation()
	_click(adapter.get_canvas_transform() * collision)
	for frame: int in 4:
		await process_frame
	if adapter.selected_object != "amber_pearl" or not adapter.panel._cycle.is_visible_in_tree():
		_fail("viewport did not open the first object and cycle control")
		return
	var covered: Vector2 = adapter.panel.get_global_transform_with_canvas().affine_inverse() * (adapter.get_canvas_transform() * collision)
	if not Rect2(Vector2.ZERO, adapter.panel.size).has_point(covered):
		_fail("inspector does not cover the scene hit in this fixture")
		return
	for expected: String in ["hearth_stone", "amber_pearl", "hearth_stone"]:
		var button: Button = adapter.panel._cycle
		_click(button.get_global_transform_with_canvas() * (button.size * 0.5))
		for frame: int in 3:
			await process_frame
		if adapter.selected_object != expected:
			_fail("GUI cycle expected " + expected + ", got " + adapter.selected_object)
			return
	if Codec.canonical_json(Codec.normalized(runtime.world_sim.to_dict())) != before:
		_fail("inspection mutated world state")
		return
	print("OBJECT_INSPECTION_GUI passed: covered scene hit; actual button dispatch; unchanged world")
	quit(0)


func _click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.position = at
	press.global_position = at
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	root.push_input(press, true)
	var release := InputEventMouseButton.new()
	release.position = at
	release.global_position = at
	release.button_index = MOUSE_BUTTON_LEFT
	root.push_input(release, true)


func _fail(reason: String) -> void:
	printerr("OBJECT_INSPECTION_GUI failed: ", reason)
	quit(1)
