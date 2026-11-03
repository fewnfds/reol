extends RefCounted
## Real observation/atlas/streaming boundaries, rather than another nature
## generator test. Observing must not change any serialized world fact.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const Visuals = preload("res://scripts/world/terrain_visuals.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_observation(runner)
	_pointer_input(runner)
	_atlases(runner)
	_streaming_and_rebinding(runner)
	_focus_change_during_painting(runner)
	_synchronous_tool_replaces_partial(runner)
	print("SCENARIO natural view: read-only local senses, hidden/soul boundaries, all surface/plant atlas tiles, complete budgeted painting and stale-view cleanup")


func _observation(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	var observation: NaturalWorldRuntime = adapter.natural_adapter
	var cell: Vector2i = adapter.controlled_cell()
	var before: String = _canonical(adapter)
	runner.assert_true(observation.observe(cell), "embodied player can observe the ground currently within sight")
	runner.assert_true(observation.panel.visible and observation.selected_cell == cell, "successful observation opens its panel at the actual selected cell")
	var description: String = observation.describe(cell)
	runner.assert_true(description.contains(str(adapter.world_sim.map_data.natural_cell(cell).label)), "observation describes the same real substrate used by the map view")
	runner.assert_true(description.contains("尚未辨明"), "ordinary visual observation does not grant elemental appraisal")
	for hidden: String in ["fertility", "mineralization", "elements", "亲和度", "灵力储量"]:
		runner.assert_true(not description.contains(hidden), "normal observation does not reveal hidden fields: " + hidden)
	observation.refresh()
	observation.describe(cell)
	runner.assert_eq(_canonical(adapter), before, "observing/redrawing ground changes no time, body, finite source, inventory or relationship")
	adapter.current_region = ""
	runner.assert_true(not observation.describe(cell).is_empty(), "visible ground weather uses geography while the observer is between settlements")
	adapter.current_region = "home"
	runner.assert_true(not observation.observe(Vector2i(-1, 0)), "observation cannot select outside the finite world")
	runner.assert_true(not observation.observe(cell + Vector2i(20, 0)), "fallback senses do not reveal distant natural cells without fog data")
	runner.assert_eq(observation.cell_at_point(TileGrid.cell_to_world(cell)), cell, "elevation-aware pointer lookup preserves the exact flat-map cell center")
	var fog := FogOfWar.new()
	fog.setup(fixture.world, cell)
	var notifications: Dictionary = {"count": 0}
	fog.visibility_updated.connect(func() -> void: notifications.count += 1)
	fog.update_now()
	runner.assert_eq(notifications.count, 1, "one visibility recomputation emits one redraw notification even while the simulation is paused")
	fog._process(FogOfWar.UPDATE_INTERVAL)
	runner.assert_eq(notifications.count, 1, "unchanged visibility does not send a per-frame redraw notification")
	fixture.home._fog = fog
	runner.assert_true(observation.visible_cell(cell), "observation respects the real active fog's current visibility")
	var distant := Vector2i(80, 80)
	runner.assert_true(not observation.visible_cell(distant) and not observation.observe(distant), "hidden fog blocks natural inspection even when map data exists")
	fog.set_focus(distant)
	fog.update_now()
	observation.refresh()
	runner.assert_true(fog.is_explored(cell) and not fog.is_cell_visible(cell), "sight fixture retains explored memory after leaving the selected cell")
	runner.assert_eq(observation.describe(cell), "此处已离开视野，眼下的情形无法确认。", "explored ground does not provide live vegetation or source information")
	runner.assert_true(observation._description.text.contains("离开视野"), "an open panel stops showing live detail after visibility changes")
	fog.set_focus(cell)
	fog.update_now()
	adapter.avatar_subject = "subject:soul:yan_heng"
	adapter.avatar_changed.emit()
	runner.assert_true(not observation.panel.visible, "changing to a disembodied observer closes the previous body's natural observation")
	runner.assert_true(not observation.observe(cell), "soul cannot acquire physical sight by right-clicking former visible ground")
	runner.assert_true(not observation.visible_cell(cell), "public visibility projection also respects the active soul's limited senses")
	runner.assert_true(not observation.describe(cell).contains(str(adapter.world_sim.map_data.natural_cell(cell).label)), "direct description cannot bypass the soul's lack of physical sight")
	adapter.avatar_subject = "subject:player"
	adapter.avatar_changed.emit()
	runner.assert_true(observation.observe(cell), "returning to the original body restores its own observation")
	adapter.region_changed.emit("river")
	runner.assert_true(not observation.panel.visible and observation.selected_cell == Vector2i(-1, -1), "changing region clears the previous region's selection")
	fixture.home._fog = null
	fog.free()
	_fixtures._dispose(fixture)


func _pointer_input(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var observation: NaturalWorldRuntime = main._continuity.natural_adapter
	var target: Vector2i = main.player.cell
	var point: Vector2 = TileGrid.cell_to_world(target)
	point.y -= main.world.get_elevation(target) * ReolWorld.ELEVATION_PX
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = observation.get_canvas_transform() * point
	var before: String = _canonical(main._continuity)
	observation._unhandled_input(click)
	runner.assert_eq(observation.selected_cell, target, "right-click observes the event's transformed position without moving the physical mouse")
	runner.assert_true(observation.panel.visible, "right-click opens observation in the ordinary scene")
	runner.assert_eq(_canonical(main._continuity), before, "pointer observation changes no serialized world fact")
	observation.reset_observation()
	click.pressed = false
	observation._unhandled_input(click)
	runner.assert_true(not observation.panel.visible, "releasing the right button does not reopen observation")
	main.free()
	GameClock.restore_state(saved_clock)


func _atlases(runner: Object) -> void:
	var map := WorldMapData.new()
	var nature := NaturalEnvironment.new(WorldMapData.WORLD_SEED)
	var surfaces: Dictionary = map.natural_surface_definitions()
	var plants: Dictionary = nature.flora_definitions()
	var ground: Image = Visuals.build_natural_image(TileGrid.TILE_SIZE, surfaces)
	var cover: Image = Visuals.build_flora_image(TileGrid.TILE_SIZE, plants)
	runner.assert_eq(ground.get_size(), Vector2i(NaturalEnvironment.SURFACES.size() * TileGrid.TILE_SIZE, Visuals.VARIANTS * TileGrid.TILE_SIZE), "ground atlas contains every natural surface and all deterministic variants")
	runner.assert_eq(cover.get_size(), Vector2i(plants.size() * TileGrid.TILE_SIZE, Visuals.VARIANTS * TileGrid.TILE_SIZE), "plant atlas has an independent complete column for every configured species")
	var ground_hashes: Dictionary = {}
	var empty_plants: int = 0
	var opaque_corners: int = 0
	for index: int in NaturalEnvironment.SURFACES.size():
		var tile: Image = ground.get_region(Rect2i(index * TileGrid.TILE_SIZE, 0, TileGrid.TILE_SIZE, TileGrid.TILE_SIZE))
		ground_hashes[hash(tile.get_data())] = true
	for index: int in plants.size():
		for variant: int in Visuals.VARIANTS:
			var tile: Image = cover.get_region(Rect2i(index * TileGrid.TILE_SIZE, variant * TileGrid.TILE_SIZE, TileGrid.TILE_SIZE, TileGrid.TILE_SIZE))
			if not tile.get_used_rect().has_area():
				empty_plants += 1
			if tile.get_pixel(0, 0).a > 0.0 or tile.get_pixel(TileGrid.TILE_SIZE - 1, TileGrid.TILE_SIZE - 1).a > 0.0:
				opaque_corners += 1
	runner.assert_eq(ground_hashes.size(), NaturalEnvironment.SURFACES.size(), "all actual ground images are visually distinct")
	runner.assert_eq(empty_plants, 0, "all plant species and variants have actual visible code-generated pixels")
	runner.assert_eq(opaque_corners, 0, "vegetation remains a transparent overlay instead of hiding the whole underlying soil")


func _streaming_and_rebinding(runner: Object) -> void:
	var world := ReolWorld.new()
	world.initialize()
	var chunk := Vector2i(3, 3)
	world.set_focus(chunk * ReolWorld.CHUNK_SIZE)
	world._pending_load.clear()
	world._pending_load.append(chunk)
	var before: Dictionary = GameClock.to_dict()
	world._process(0.016)
	runner.assert_eq(_ground_count(world), ReolWorld.PAINT_CELLS_PER_FRAME, "normal streaming paints only one configured batch on its first frame")
	runner.assert_eq(world.loaded_chunk_count(), 0, "partially painted chunk is not falsely reported as complete")
	runner.assert_eq(world._painting_chunk, chunk, "streaming retains the exact partial chunk between frames")
	for _step: int in range(15):
		world._process(0.016)
	runner.assert_eq(world.loaded_chunk_count(), 1, "all sixteen 256-cell batches complete one 64x64 chunk")
	runner.assert_eq(_ground_count(world), ReolWorld.CHUNK_SIZE * ReolWorld.CHUNK_SIZE, "budgeted streaming does not omit or duplicate ground cells")
	runner.assert_true(world._painting_chunk.x < 0 and world._painting_offset == 0, "completed chunk releases its in-progress cursor")
	var errors: int = 0
	var expected_plants: int = 0
	var actual_plants: int = 0
	var source: TileSetAtlasSource = world._tile_set.get_source(0)
	var flora_source: TileSetAtlasSource = world._tile_set.get_source(1)
	for y: int in ReolWorld.CHUNK_SIZE:
		for x: int in ReolWorld.CHUNK_SIZE:
			var cell: Vector2i = chunk * ReolWorld.CHUNK_SIZE + Vector2i(x, y)
			var natural: Dictionary = world.map_data().natural_cell(cell)
			var elevation: int = world.get_elevation(cell)
			var atlas := Vector2i(NaturalEnvironment.SURFACES.find(str(natural.surface_id)), Visuals.variant_for(cell))
			if world._layers[elevation].get_cell_atlas_coords(cell) != atlas or not source.has_tile(atlas):
				errors += 1
			if not natural.flora.is_empty():
				expected_plants += 1
				var plant := Vector2i(world._flora_ids.find(natural.flora.id), int(natural.flora.variant))
				if world._flora_layers[elevation].get_cell_atlas_coords(cell) != plant or not flora_source.has_tile(plant):
					errors += 1
	for layer: TileMapLayer in world._flora_layers:
		actual_plants += layer.get_used_cells().size()
	runner.assert_eq(errors, 0, "all 4096 cells and their plant overlays use the actual surface/species atlas and original height")
	runner.assert_eq(actual_plants, expected_plants, "visible vegetation count agrees with the same deterministic cover projection")
	runner.assert_eq(GameClock.to_dict(), before, "painting terrain or plants never advances the shared game time")
	world._pending_load.append(chunk + Vector2i.RIGHT)
	world._process(0.016)
	runner.assert_true(world._painting_offset > 0, "map replacement fixture contains a real partially painted second chunk")
	world.bind_map_data(world.map_data().independent_copy())
	runner.assert_eq(_ground_count(world), 0, "accepted replacement clears every old ground elevation including partial cells")
	runner.assert_eq(_flora_count(world), 0, "accepted replacement clears every old vegetation elevation including partial cover")
	runner.assert_true(world._loaded.is_empty() and world._cliff_nodes.is_empty(), "replacement discards old completed chunk and cliff indexes")
	runner.assert_true(world._painting_chunk.x < 0 and world._painting_offset == 0, "replacement resets its in-progress batch cursor")
	world.free()


func _focus_change_during_painting(runner: Object) -> void:
	var world := ReolWorld.new()
	world.initialize()
	world.set_focus(Vector2i.ZERO)
	world._process(0.016)
	runner.assert_true(_count_in_chunk(world, Vector2i.ZERO) > 0, "focus-change fixture has genuinely painted some cells in the departing chunk")
	world.set_focus(Vector2i(511, 511))
	for _step: int in range(17):
		world._process(0.016)
	runner.assert_true(not world._loaded.has(Vector2i.ZERO), "an abandoned partial chunk cannot become a permanently retained far-away loaded chunk")
	runner.assert_eq(_count_in_chunk(world, Vector2i.ZERO), 0, "changing focus beyond retention radius cleans both ground and cover from the previous partial view")
	world.free()


func _synchronous_tool_replaces_partial(runner: Object) -> void:
	var world := ReolWorld.new()
	world.initialize()
	world.set_focus(Vector2i.ZERO)
	world._process(0.016)
	world._load_chunk(Vector2i(1, 1))
	runner.assert_true(world._loaded.has(Vector2i(1, 1)), "explicit synchronous tool entry still completes its requested chunk")
	runner.assert_eq(_count_in_chunk(world, Vector2i.ZERO), 0, "synchronous entry cleans an overridden partial chunk rather than orphaning its untracked tiles")
	world.free()


func _ground_count(world: ReolWorld) -> int:
	var count: int = 0
	for layer: TileMapLayer in world._layers:
		count += layer.get_used_cells().size()
	return count


func _flora_count(world: ReolWorld) -> int:
	var count: int = 0
	for layer: TileMapLayer in world._flora_layers:
		count += layer.get_used_cells().size()
	return count


func _count_in_chunk(world: ReolWorld, chunk: Vector2i) -> int:
	var count: int = 0
	var bounds := Rect2i(chunk * ReolWorld.CHUNK_SIZE, Vector2i.ONE * ReolWorld.CHUNK_SIZE)
	var layers: Array[TileMapLayer] = []
	layers.append_array(world._layers)
	layers.append_array(world._flora_layers)
	for layer: TileMapLayer in layers:
		for cell: Vector2i in layer.get_used_cells():
			if bounds.has_point(cell):
				count += 1
	return count


func _canonical(adapter: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(adapter)), "", true, true)
