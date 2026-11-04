extends RefCounted
## Exercise the ordinary streamed tile projection against actual map edits.


func run(runner: Object) -> void:
	_repaint_source_and_shore(runner)
	_partial_cleanup_and_rebind(runner)
	_stationary_fog(runner)
	print("SCENARIO terrain view: budgeted water/shore repaint, streamed ownership and stationary sight invalidation")


func _fixture(runner: Object) -> Dictionary:
	var map: WorldMapData = WorldMapData.from_descriptor(WorldMapData.flat_descriptor(42))
	var rules: Variant = JSON.parse_string(FileAccess.get_file_as_string(NaturalEnvironment.DEFAULT_PATH))
	if map == null or not rules is Dictionary or not map.configure_nature(rules):
		runner.assert_true(false, "flat map with its natural definitions is available")
		return {}
	# A water tile must have no incidental lotus so this case specifically
	# observes removal of existing terrestrial vegetation in the rendered layer.
	var test_rules: Dictionary = rules.duplicate(true)
	test_rules.surfaces.water.density = 0
	for id: String in ["shore", "wetland", "woodland", "gravel", "meadow", "grassland"]:
		test_rules.surfaces[id].density = 100
	if not map.configure_nature(test_rules):
		runner.assert_true(false, "valid no-lotus water definition is available")
		return {}
	var world := ReolWorld.new()
	world.bind_map_data(map)
	world.initialize()
	return {"map": map, "world": world, "rules": test_rules}


func _repaint_source_and_shore(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	if fixture.is_empty():
		return
	var map: WorldMapData = fixture.map
	var world: ReolWorld = fixture.world
	var center := Vector2i(256, 256)
	# Clear the immediate probe cross so changing only center to water must turn
	# each adjacent grass cell into the actual near-water shore surface.
	var rows: Array = []
	for y: int in range(-3, 4):
		for x: int in range(-3, 4):
			rows.append([center.x + x, center.y + y, WorldMapData.TERRAIN_GRASS])
	runner.assert_true(bool(map.apply_terrain_patch(rows).ok), "preparation creates a finite terrestrial patch")
	var target := Vector2i(-1, -1)
	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			var candidate: Vector2i = center + Vector2i(x, y)
			if map.get_terrain(candidate) == WorldMapData.TERRAIN_GRASS and not map.natural_cell(candidate).flora.is_empty():
				target = candidate
				break
		if target.x >= 0:
			break
	runner.assert_true(target.x >= 0, "the deterministic terrestrial patch contains an actual vegetation tile")
	if target.x < 0:
		world.free()
		return
	var neighbor: Vector2i = target + Vector2i.RIGHT
	var old_neighbor: String = map.natural_surface(neighbor)
	runner.assert_true(old_neighbor != "shore", "neighbor begins without immediate water")
	world.set_focus(target)
	var view := Rect2i(target - Vector2i(7, 7), Vector2i(15, 15))
	world.prioritize_view(view)
	world._process(0.016)
	runner.assert_true(world.is_view_ready(view), "normal priority painting draws the entire local view")
	runner.assert_true(world._flora_layers[0].get_cell_source_id(target) >= 0, "terrestrial cover is actually present before editing")
	var old_neighbor_atlas: Vector2i = world._layers[0].get_cell_atlas_coords(neighbor)
	var changed: Dictionary = map.apply_terrain_patch([[target.x, target.y, WorldMapData.TERRAIN_WATER]])
	runner.assert_true(bool(changed.ok), "the terrain edit is accepted")
	runner.assert_true(not world.terrain_is_walkable(target), "water blocks movement immediately before another rendering frame")
	runner.assert_eq(map.natural_surface(neighbor), "shore", "the nearby cell's natural result changes from real water adjacency")
	runner.assert_true(world._flora_layers[0].get_cell_source_id(target) >= 0, "the already drawn plant awaits the normal repaint budget")
	world._process(0.016)
	runner.assert_eq(world._layers[0].get_cell_atlas_coords(target).x, NaturalEnvironment.SURFACES.find("water"), "budgeted repaint changes the actual ground atlas to water")
	runner.assert_eq(world._flora_layers[0].get_cell_source_id(target), -1, "budgeted repaint removes the stale terrestrial cover")
	runner.assert_eq(world._layers[0].get_cell_atlas_coords(neighbor).x, NaturalEnvironment.SURFACES.find("shore"), "actual water adjacency repaints neighboring ground as shore")
	runner.assert_true(world._layers[0].get_cell_atlas_coords(neighbor) != old_neighbor_atlas, "the neighboring rendered tile really changes")
	world.free()


func _partial_cleanup_and_rebind(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	if fixture.is_empty():
		return
	var map: WorldMapData = fixture.map
	var world: ReolWorld = fixture.world
	var cell := Vector2i(309, 309)
	var view := Rect2i(cell - Vector2i(1, 1), Vector2i(3, 3))
	world.set_focus(cell)
	world.prioritize_view(view)
	world._process(0.016)
	var chunk := Vector2i(4, 4)
	runner.assert_true(world.is_view_ready(view) and not world._loaded.has(chunk), "priority view is drawn while its chunk is still partial")
	runner.assert_true(world._preview_chunks.has(chunk) and world._preview_chunks[chunk].has(cell), "priority cell belongs to its partial chunk")
	var terrain_before: int = map.get_terrain(cell)
	var replacement: int = WorldMapData.TERRAIN_WATER if terrain_before != WorldMapData.TERRAIN_WATER else WorldMapData.TERRAIN_GRASS
	runner.assert_true(bool(map.apply_terrain_patch([[cell.x, cell.y, replacement]]).ok), "partial tile can receive an edit")
	world._process(0.016)
	runner.assert_true(world._preview_chunks.has(chunk) and world._preview_chunks[chunk].has(cell), "repainting retains partial chunk ownership")
	world.set_focus(Vector2i.ZERO) # Chunk (4,4) lies beyond the unload radius 3.
	runner.assert_eq(_cell_count(world, cell), 0, "moving focus away clears the repainted partial tile")
	# A second edit while the dirty preview is already gone must not resurrect it.
	replacement = WorldMapData.TERRAIN_ROCK if map.get_terrain(cell) != WorldMapData.TERRAIN_ROCK else WorldMapData.TERRAIN_GRASS
	runner.assert_true(bool(map.apply_terrain_patch([[cell.x, cell.y, replacement]]).ok), "offscreen terrain can change without a view")
	world._process(0.016)
	runner.assert_eq(_cell_count(world, cell), 0, "an offscreen edit does not recreate an unloaded tile")
	world.set_focus(cell)
	world.prioritize_view(view)
	world._process(0.016)
	runner.assert_true(world.is_view_ready(view), "returning to the area streams the current terrain")
	var last_state: int = map.get_terrain(cell)
	var queued_change: int = WorldMapData.TERRAIN_WATER if last_state != WorldMapData.TERRAIN_WATER else WorldMapData.TERRAIN_GRASS
	runner.assert_true(bool(map.apply_terrain_patch([[cell.x, cell.y, queued_change]]).ok), "a fresh edit queues another preview repaint")
	# Leave before consuming that queue: queued dirty cells cannot resurrect a
	# cleared partial preview when the rendering frame eventually runs.
	world.set_focus(Vector2i.ZERO)
	runner.assert_eq(_cell_count(world, cell), 0, "leaving clears the queued dirty preview")
	world._process(0.016)
	runner.assert_eq(_cell_count(world, cell), 0, "pending repaint does not recreate a preview after unloading")
	world.set_focus(cell)
	world.prioritize_view(view)
	world._process(0.016)
	runner.assert_true(world.is_view_ready(view), "re-entering after dirty cleanup draws the latest terrain")
	var current_atlas: Vector2i = world._layers[0].get_cell_atlas_coords(cell)
	var current_surface: String = map.natural_surface(cell)
	runner.assert_eq(current_atlas.x, NaturalEnvironment.SURFACES.find(current_surface), "the restored view reflects the offscreen edit")
	var changed_map: WorldMapData = map.independent_copy()
	runner.assert_true(changed_map != null and changed_map != map, "replacement map is independent")
	if changed_map != null:
		world.bind_map_data(changed_map)
		world.prioritize_view(view)
		world._process(0.016)
		runner.assert_true(world.is_view_ready(view), "view is restored for the new map")
		var before_atlas: Vector2i = world._layers[0].get_cell_atlas_coords(cell)
		var before_plant: int = world._flora_layers[0].get_cell_source_id(cell)
		var old_new_value: int = WorldMapData.TERRAIN_WATER if map.get_terrain(cell) != WorldMapData.TERRAIN_WATER else WorldMapData.TERRAIN_GRASS
		var rebind_notifications: Array = []
		world.terrain_changed.connect(func(changed: Array[Vector2i]) -> void: rebind_notifications.append(changed))
		runner.assert_true(bool(map.apply_terrain_patch([[cell.x, cell.y, old_new_value]]).ok), "the former map can still change independently")
		runner.assert_true(rebind_notifications.is_empty(), "former map no longer publishes terrain changes to the rebound view")
		world._process(0.016)
		runner.assert_true(world.map_data() == changed_map and world.map_data().get_terrain(cell) != map.get_terrain(cell), "the view retains the replacement's independent terrain")
		runner.assert_eq(world._layers[0].get_cell_atlas_coords(cell), before_atlas, "former map signal cannot repaint the replacement ground")
		runner.assert_eq(world._flora_layers[0].get_cell_source_id(cell), before_plant, "former map signal cannot change replacement vegetation")
	world.free()


func _stationary_fog(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	if fixture.is_empty():
		return
	var map: WorldMapData = fixture.map
	var world: ReolWorld = fixture.world
	var eye := Vector2i(250, 250)
	var blocker: Vector2i = eye + Vector2i.RIGHT
	var seen: Vector2i = eye + Vector2i.RIGHT * 2
	runner.assert_true(bool(map.apply_terrain_patch([[eye.x, eye.y, WorldMapData.TERRAIN_GRASS],
		[blocker.x, blocker.y, WorldMapData.TERRAIN_GRASS], [seen.x, seen.y, WorldMapData.TERRAIN_GRASS]]).ok), "sight test starts with a clear three-cell line")
	var fog := FogOfWar.new()
	fog.setup(world, eye)
	runner.assert_true(fog.is_cell_visible(seen), "stationary observer sees the clear line")
	runner.assert_true(bool(map.apply_terrain_patch([[blocker.x, blocker.y, WorldMapData.TERRAIN_ROCK]]).ok), "a real rock edit blocks the line")
	fog._process(FogOfWar.UPDATE_INTERVAL)
	runner.assert_true(not fog.is_cell_visible(seen) and fog.is_explored(seen), "terrain notification updates stationary visibility while retaining explored memory")
	runner.assert_true(bool(map.apply_terrain_patch([[blocker.x, blocker.y, WorldMapData.TERRAIN_GRASS]]).ok), "removing the rock restores the open line")
	fog._process(FogOfWar.UPDATE_INTERVAL)
	runner.assert_true(fog.is_cell_visible(seen), "stationary observer sees the reopened line on the next visibility update")
	fog.free()
	world.free()


func _cell_count(world: ReolWorld, cell: Vector2i) -> int:
	var count: int = 0
	for layer: TileMapLayer in world._layers:
		if layer.get_cell_source_id(cell) >= 0:
			count += 1
	for layer: TileMapLayer in world._flora_layers:
		if layer.get_cell_source_id(cell) >= 0:
			count += 1
	return count
