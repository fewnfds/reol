extends SceneTree
## Native two-process evidence. Requires -- --world-editor --phase=write/read.
## Inputs use the actual modal tool; saves are isolated QA artifacts in logs.

const SAVE: String = "res://logs/terrain_editor_restart.json"
const EXPECTED: String = "res://logs/terrain_editor_expected.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var writing: bool = OS.get_cmdline_user_args().has("--phase=write")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	root.size = Vector2i(1600, 900)
	root.position = Vector2i.ZERO
	var runtime: Node = main._continuity
	if runtime == null or runtime.world_sim == null or main._terrain_editor == null:
		_fail("world/editor assembly failed")
		return
	if writing:
		if not runtime.select_starting_avatar("subject:player") or not runtime.travel_to("river"):
			_fail("real human journey failed")
			return
		root.get_node("GameClock").advance_msec(317)
	elif runtime.load_game(ProjectSettings.globalize_path(SAVE)) != OK:
		_fail("fresh ordinary loader rejected edited world")
		return
	root.get_node("GameClock").set_paused(true)
	# The tool remains visible; hide other development HUDs only for this shot.
	for layer: Node in main.find_children("*", "CanvasLayer", true, false):
		if not main._terrain_editor.is_ancestor_of(layer):
			layer.visible = false
	main.fog.hide()
	main.camera.global_position = main.player.global_position + Vector2(390, 0)
	for frame: int in 30:
		await process_frame
	var f8 := InputEventKey.new()
	f8.keycode = KEY_F8
	f8.pressed = true
	Input.parse_input_event(f8)
	await process_frame
	var editor: Node = main._terrain_editor
	if not editor.overlay.visible:
		_fail("actual F8 input did not open the prepared modal tool")
		return
	var cell := Vector2i(-1, -1)
	if writing:
		# Find a visible 3x3 patch clear of real fixed/active spatial references.
		var guard: Variant = load("res://scripts/sim/terrain_edits.gd")
		for y: int in range(main.player.cell.y - 3, main.player.cell.y + 5):
			for x: int in range(main.player.cell.x + 4, main.player.cell.x + 11):
				var rows: Array = []
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						rows.append([x + dx, y + dy, WorldMapData.TERRAIN_WATER])
				if guard.inspect(runtime.world_sim, rows, runtime.player_journey).ok:
					cell = Vector2i(x, y)
					break
			if cell.x >= 0:
				break
		if cell.x < 0:
			_fail("no safe visible brush patch")
			return
		editor.terrain_choice.select(1)
		editor.brush_choice.select(1)
		# parse_input_event enters before root stretch conversion, just like a
		# native window event. The GUI handler receives logical overlay points.
		var screen: Vector2 = root.get_final_transform() * main.get_canvas_transform() * TileGrid.cell_to_world(cell)
		var motion := InputEventMouseMotion.new()
		motion.position = screen
		Input.parse_input_event(motion)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = screen
		click.pressed = true
		Input.parse_input_event(click)
		await process_frame
		click = click.duplicate()
		click.pressed = false
		Input.parse_input_event(click)
		if runtime.world_sim.map_data.get_terrain(cell) != WorldMapData.TERRAIN_WATER or runtime.world_sim.map_data.terrain_overrides().is_empty():
			print("EDITOR_INPUT_DIAG screen=", screen, " viewport=", root.size, " overlay=", editor.overlay.size,
				" cell=", cell, " pointer=", TileGrid.world_to_cell(editor.get_global_mouse_position()), " reply=", editor._reply.text)
			_fail("actual canvas click did not commit the selected water brush")
			return
	for frame: int in 32:
		await process_frame
	await RenderingServer.frame_post_draw
	var codec: Variant = load("res://scripts/runtime/world_session_snapshot.gd")
	var state: Dictionary = codec.capture(runtime)
	var digest: String = SnapshotValues.canonical_json(SnapshotValues.normalized(state)).sha256_text()
	if writing:
		if runtime.save_game(ProjectSettings.globalize_path(SAVE)) != OK:
			_fail("ordinary edited saver failed")
			return
		var file: FileAccess = FileAccess.open(EXPECTED, FileAccess.WRITE)
		if file == null:
			_fail("expected-state output unavailable")
			return
		file.store_string(JSON.stringify({"digest": digest, "cell": [cell.x, cell.y]}))
		file.close()
	else:
		var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED))
		if not expected is Dictionary or digest != expected.get("digest"):
			_fail("fresh-process complete world differs from saved edited state")
			return
	var image: Image = root.get_texture().get_image()
	if image.save_png("res://logs/terrain_editor_%s.png" % ("write" if writing else "read")) != OK:
		_fail("native screenshot failed")
		return
	print("TERRAIN_EDITOR_NATIVE ", "write" if writing else "read", " digest=", digest, " overrides=", state.world.terrain_overrides.size(), " in_flight=", not runtime.player_journey.is_empty())
	quit(0)


func _fail(message: String) -> void:
	printerr("TERRAIN_EDITOR_NATIVE_FAILED ", message)
	quit(1)
