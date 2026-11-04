extends SceneTree
## Two-process QA: write an edited opening, then read it in a fresh process.
## Run with -- --phase=write, then -- --phase=read. Outputs are ignored logs.

const SAVE: String = "res://logs/terrain_restart_save.json"
const EXPECTED: String = "res://logs/terrain_restart_state.json"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var writing: bool = OS.get_cmdline_user_args().has("--phase=write")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	if writing:
		var map: WorldMapData = WorldMapData.from_descriptor(WorldMapData.flat_descriptor(20261104))
		var rows: Array = []
		for y: int in range(260, 265):
			for x: int in range(268, 274):
				rows.append([x, y, WorldMapData.TERRAIN_WATER])
		for y: int in range(247, 252):
			rows.append([270, y, WorldMapData.TERRAIN_ROCK])
		if not bool(map.apply_terrain_patch(rows).ok) or not main.configure_opening_map(map.descriptor(), map.terrain_overrides()):
			_fail("opening draft rejected")
			return
	root.add_child(main)
	current_scene = main
	var runtime: Node = main._continuity
	if runtime == null or runtime.world_sim == null:
		_fail("world assembly failed")
		return
	if writing:
		if not runtime.select_starting_avatar("subject:player"):
			_fail("opening selection failed")
			return
	else:
		if runtime.load_game(ProjectSettings.globalize_path(SAVE)) != OK:
			_fail("ordinary loader rejected the saved terrain")
			return
	root.get_node("GameClock").set_paused(true)
	root.size = Vector2i(1600, 900)
	root.position = Vector2i.ZERO
	main.camera.global_position = main.player.global_position + Vector2(400, 0)
	# This QA view reveals layout without giving the selected character knowledge.
	main.fog.hide()
	for layer: Node in main.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	for frame: int in 64:
		await process_frame
	await RenderingServer.frame_post_draw
	# Load after autoload registration; this --script entry itself is compiled
	# before GameClock exists in the global singleton table.
	var codec: Variant = load("res://scripts/runtime/world_session_snapshot.gd")
	var state: Dictionary = codec.capture(runtime)
	var digest: String = SnapshotValues.canonical_json(SnapshotValues.normalized(state)).sha256_text()
	if writing:
		if runtime.save_game(ProjectSettings.globalize_path(SAVE)) != OK:
			_fail("ordinary saver failed")
			return
		var output: FileAccess = FileAccess.open(EXPECTED, FileAccess.WRITE)
		if output == null:
			_fail("expected-state output unavailable")
			return
		output.store_string(JSON.stringify({"digest": digest, "overrides": state.world.terrain_overrides}))
		output.close()
	else:
		var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED))
		if not expected is Dictionary or digest != expected.get("digest"):
			_fail("fresh-process complete world differs from the saved state")
			return
	var picture: Image = root.get_texture().get_image()
	var path: String = "res://logs/terrain_native_%s.png" % ("write" if writing else "read")
	if picture.save_png(path) != OK:
		_fail("native image could not be saved")
		return
	print("TERRAIN_NATIVE ", "write" if writing else "read", " digest=", digest,
		" overrides=", state.world.terrain_overrides.size(), " image=", picture.get_size())
	quit(0)


func _fail(message: String) -> void:
	printerr("TERRAIN_NATIVE_FAILED ", message)
	quit(1)
