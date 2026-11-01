extends SceneTree
## Minimal headless test runner for Reol.
##
## Run with:
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Convention: every method named `test_*` with no arguments is a test.
## Do not use bare `assert()`: a failed assert can stop before quit() and hang CI.
## Use the helpers below, which record failures and keep going.

var passed: int = 0
var failed: int = 0


func _initialize() -> void:
	print("Reol tests - Godot %s" % Engine.get_version_info()["string"])

	var names: Array[String] = []
	for method in get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_") and method["args"].is_empty():
			names.append(method_name)
	names.sort()

	for test_name in names:
		var before := failed
		print("RUN  %s" % test_name)
		call(test_name)
		if failed == before:
			passed += 1
			print("PASS %s" % test_name)

	print("")
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	failed += 1
	printerr("FAIL %s" % label)


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	failed += 1
	printerr("FAIL %s: expected %s, got %s" % [label, str(expected), str(actual)])


func assert_not_null(value: Variant, label: String) -> void:
	if value != null:
		return
	failed += 1
	printerr("FAIL %s: value is null" % label)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


func test_project_name() -> void:
	var project_name := str(ProjectSettings.get_setting("application/config/name", ""))
	assert_true(not project_name.is_empty(), "project name is set")


func test_project_features() -> void:
	var features: PackedStringArray = ProjectSettings.get_setting(
		"application/config/features", PackedStringArray()
	)
	assert_true(features.has("4.7"), "project targets Godot 4.7")


func test_main_scene_configured() -> void:
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	assert_eq(main_scene, "res://scenes/main.tscn", "main scene path")
	assert_true(ResourceLoader.exists(main_scene), "main scene exists")


func test_boot_scene_instantiates() -> void:
	var packed: PackedScene = load("res://scenes/boot.tscn") as PackedScene
	assert_not_null(packed, "boot.tscn loads as PackedScene")
	if packed == null:
		return
	var node: Node = packed.instantiate()
	assert_eq(String(node.name), "Boot", "boot root name")
	node.free()


func test_tile_grid_roundtrip() -> void:
	var cells: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(1, 1),
		Vector2i(10, 20),
		Vector2i(511, 511),
	]
	for cell in cells:
		var world_position: Vector2 = TileGrid.cell_to_world(cell)
		assert_eq(
			TileGrid.world_to_cell(world_position),
			cell,
			"grid roundtrip %s" % str(cell)
		)


func test_tile_grid_offsets() -> void:
	assert_eq(TileGrid.cell_to_world(Vector2i(0, 0)), Vector2(32.0, 32.0), "origin center")
	assert_eq(TileGrid.cell_to_world(Vector2i(1, 0)), Vector2(96.0, 32.0), "east offset")
	assert_eq(TileGrid.cell_to_world(Vector2i(0, 1)), Vector2(32.0, 96.0), "south offset")
	assert_eq(TileGrid.cell_to_world(Vector2i(1, 1)), Vector2(96.0, 96.0), "south-east offset")
	assert_eq(TileGrid.world_to_cell(Vector2(0.0, 0.0)), Vector2i(0, 0), "top-left corner")
	assert_eq(TileGrid.world_to_cell(Vector2(63.9, 63.9)), Vector2i(0, 0), "inside tile")
	assert_eq(TileGrid.world_to_cell(Vector2(64.0, 64.0)), Vector2i(1, 1), "next tile")


func test_input_actions_exist() -> void:
	var actions: Array[String] = [
		"move_left",
		"move_right",
		"move_up",
		"move_down",
		"camera_left",
		"camera_right",
		"camera_up",
		"camera_down",
		"center_camera",
		"zoom_in",
		"zoom_out",
	]
	for action in actions:
		assert_true(InputMap.has_action(action), "input action exists: %s" % action)


func test_world_terrain_and_elevation() -> void:
	var world := ReolWorld.new()
	world.initialize()
	var cells: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(256, 256),
		Vector2i(511, 511),
	]
	for cell in cells:
		var terrain: int = world.get_terrain(cell)
		assert_true(
			terrain >= ReolWorld.TERRAIN_WATER and terrain <= ReolWorld.TERRAIN_ROCK,
			"terrain range at %s" % str(cell)
		)
		var elevation: int = world.get_elevation(cell)
		assert_true(
			elevation >= 0 and elevation < ReolWorld.ELEVATION_LEVELS,
			"elevation range at %s" % str(cell)
		)
	assert_eq(
		world.world_rect().size,
		Vector2(32768.0, 32768.0),
		"world rect covers 512x512 tiles"
	)
	assert_true(
		not world.can_move(Vector2i(0, 0), Vector2i(-1, 0)),
		"cannot move out of bounds"
	)
	world.free()


func test_fog_visibility_states() -> void:
	var world := ReolWorld.new()
	world.initialize()
	var fog := FogOfWar.new()
	fog.setup(world, Vector2i(256, 256))

	var center := Vector2i(256, 256)
	assert_true(fog.is_cell_visible(center), "spawn cell is visible")
	assert_true(fog.is_explored(center), "spawn cell is explored")

	var far := Vector2i(306, 256)
	assert_eq(
		fog.get_state(far),
		FogOfWar.STATE_HIDDEN,
		"far cell starts hidden"
	)

	fog.set_focus(far)
	fog.update_now()
	assert_eq(
		fog.get_state(center),
		FogOfWar.STATE_EXPLORED,
		"old visible cell becomes explored"
	)
	assert_true(fog.is_cell_visible(far), "new focus cell is visible")

	fog.free()
	world.free()


func test_scripts_parse() -> void:
	var files: Array[String] = []
	_collect_gd_files("res://scripts", files)
	_collect_gd_files("res://tests", files)

	for path in files:
		if path == "res://tests/run_tests.gd":
			continue
		var resource: Resource = load(path)
		assert_not_null(resource, "parse %s" % path)


func test_required_directories() -> void:
	for path in ["res://scenes", "res://scripts", "res://tests", "res://assets"]:
		var dir := DirAccess.open(path)
		assert_not_null(dir, "directory exists: %s" % path)
		if dir != null:
			dir.list_dir_end()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _collect_gd_files(path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := path.path_join(entry)
		if dir.current_is_dir():
			_collect_gd_files(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
