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
	_priority_view_and_streaming(runner)
	_priority_boundaries_and_cleanup(runner)
	_priority_after_ordinary_batch(runner)
	_focus_change_during_painting(runner)
	_synchronous_tool_replaces_partial(runner)
	print("SCENARIO natural view: read-only local senses, hidden/soul boundaries, budgeted priority and streaming, correct atlases and stale-view cleanup")


func _observation(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	var observation: NaturalWorldRuntime = adapter.natural_adapter
	var cell: Vector2i = adapter.controlled_cell()
	var before: String = _canonical(adapter)
	var world: ReolWorld = fixture.world
	world.initialize()
	world.set_focus(cell)
	var view := Rect2i(cell - Vector2i(3, 3), Vector2i(7, 7))
	world.prioritize_view(view)
	world._process(0.016)
	runner.assert_true(world.is_view_ready(view), "a small local priority view completes in one budgeted frame")
	runner.assert_eq(_canonical(adapter), before, "prioritizing and painting a view changes no serialized world, body or clock state")
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


func _priority_view_and_streaming(runner: Object) -> void:
	var world := ReolWorld.new()
	world.initialize()
	var focus := Vector2i(256, 228)
	var view := Rect2i(Vector2i(244, 219), Vector2i(25, 19))
	var chunks: Array[Vector2i] = [Vector2i(3, 3), Vector2i(4, 3)]
	world.set_focus(focus)
	var before: Dictionary = GameClock.to_dict()
	world.prioritize_view(view)
	runner.assert_true(not world.is_view_ready(view), "an unpainted view is not ready merely because it was requested")
	world._process(0.016)
	runner.assert_eq(_ground_count(world), ReolWorld.PAINT_CELLS_PER_FRAME, "priority and ordinary painting share the first frame's cell budget")
	runner.assert_true(_ground_at(world, focus), "the focus near the center of a cross-chunk view is painted in its first frame")
	runner.assert_true(not world.is_view_ready(view), "a 475-cell view remains incomplete after a 256-cell frame")
	for chunk: Vector2i in chunks:
		runner.assert_eq(_cliff_mask_errors(world, chunk), 0, "partial cliff coverage matches only the ground painted in each priority chunk")
	world.prioritize_view(view)
	var previous: int = _ground_count(world)
	world._process(0.016)
	runner.assert_true(_ground_count(world) - previous <= ReolWorld.PAINT_CELLS_PER_FRAME, "the second frame also respects the combined painting budget")
	runner.assert_true(world.is_view_ready(view), "repeating the same request does not restart the priority queue")
	runner.assert_eq(_projection_errors(world, view), 0, "every prioritized ground and plant cell matches its natural atlas and elevation")
	for chunk: Vector2i in chunks:
		runner.assert_eq(_cliff_mask_errors(world, chunk), 0, "partial cliff coverage follows both priority and ordinary painted cells")

	# Complete these same chunks through the normal queue, including cells
	# already drawn out of order for the priority view.
	world._pending_load.clear()
	for chunk: Vector2i in chunks:
		if not world._loaded.has(chunk) and world._painting_chunk != chunk:
			world._pending_load.append(chunk)
	for _step: int in range(40):
		if world._loaded.has(chunks[0]) and world._loaded.has(chunks[1]):
			break
		world.prioritize_view(view)
		previous = _ground_count(world)
		world._process(0.016)
		runner.assert_true(_ground_count(world) - previous <= ReolWorld.PAINT_CELLS_PER_FRAME, "ordinary continuation remains within the shared cell budget")
	runner.assert_true(world._loaded.has(chunks[0]) and world._loaded.has(chunks[1]), "ordinary streaming completes both chunks containing priority cells")
	for chunk: Vector2i in chunks:
		runner.assert_true(world._cliff_nodes.has(chunk) and world._cliff_nodes[chunk].complete, "a fully painted chunk promotes its cliff view to complete")
	var chunk_rect := Rect2i(Vector2i(3, 3) * ReolWorld.CHUNK_SIZE, Vector2i(ReolWorld.CHUNK_SIZE * 2, ReolWorld.CHUNK_SIZE))
	runner.assert_eq(_ground_count(world), ReolWorld.CHUNK_SIZE * ReolWorld.CHUNK_SIZE * 2, "continuation leaves exactly one ground cell per location in the two chunks")
	runner.assert_eq(_projection_errors(world, chunk_rect), 0, "completed chunks preserve all actual ground and vegetation without wrong-height remnants")
	runner.assert_eq(GameClock.to_dict(), before, "priority and ordinary painting do not advance shared time")
	world.bind_map_data(world.map_data().independent_copy())
	runner.assert_eq(_ground_count(world), 0, "rebinding clears priority and ordinary ground cells")
	runner.assert_eq(_flora_count(world), 0, "rebinding clears priority and ordinary vegetation")
	runner.assert_true(world._cliff_nodes.is_empty(), "rebinding clears priority and ordinary cliff ownership")
	runner.assert_true(not world.is_view_ready(view), "rebinding invalidates the previously completed view")
	world.prioritize_view(view)
	world._process(0.016)
	world.prioritize_view(view)
	world._process(0.016)
	runner.assert_true(world.is_view_ready(view), "the same view can be requested again after rebinding")
	runner.assert_eq(_projection_errors(world, view), 0, "the rebound map restores the correct priority projection")
	world.free()


func _priority_boundaries_and_cleanup(runner: Object) -> void:
	var world := ReolWorld.new()
	world.initialize()
	world.set_focus(Vector2i.ZERO)
	world._pending_load.clear()
	var upper_left := Rect2i(Vector2i(-2, -2), Vector2i(5, 5))
	world.prioritize_view(upper_left)
	world._process(0.016)
	runner.assert_true(world.is_view_ready(upper_left), "a view overlapping the upper-left boundary completes its in-world portion")
	runner.assert_eq(_ground_count(world), 9, "the upper-left view is clipped to its nine in-world cells")
	runner.assert_eq(_projection_errors(world, Rect2i(Vector2i.ZERO, Vector2i(3, 3))), 0, "upper-left clipped cells have their actual atlas and elevation")
	runner.assert_true(not world.is_view_ready(Rect2i(Vector2i(-4, -4), Vector2i(2, 2))), "a view with no in-world area is not ready")
	var focus_edge := Rect2i(Vector2i(190, 0), Vector2i(4, 2))
	world.prioritize_view(focus_edge)
	world._process(0.016)
	runner.assert_true(not world.is_view_ready(focus_edge), "a view is not ready when some in-world cells lie outside the focus loading radius")
	runner.assert_eq(_ground_count(world), 13, "priority painting clips to the focus loading radius")
	runner.assert_eq(_projection_errors(world, Rect2i(Vector2i(190, 0), Vector2i(2, 2))), 0, "the in-range portion of a partly out-of-focus view is still painted correctly")
	runner.assert_true(not _ground_at(world, Vector2i(192, 0)), "priority does not paint cells outside the focus loading radius")
	runner.assert_true(not world.is_view_ready(Rect2i(Vector2i(192, 0), Vector2i(2, 2))), "a view entirely outside the focus loading radius is not ready")
	world.set_focus(Vector2i(192, 0))
	world._pending_load.clear()
	world.prioritize_view(focus_edge)
	world._process(0.016)
	runner.assert_true(world.is_view_ready(focus_edge), "moving focus into range allows the full in-world view to become ready")
	runner.assert_eq(_projection_errors(world, focus_edge), 0, "the newly reachable edge cells use the correct ground and vegetation")
	var last := Vector2i(ReolWorld.WORLD_SIZE - 1, ReolWorld.WORLD_SIZE - 1)
	var lower_right := Rect2i(last - Vector2i(2, 2), Vector2i(5, 5))
	world.set_focus(last)
	world._pending_load.clear()
	world.prioritize_view(lower_right)
	for _step: int in range(20):
		world._process(0.016)
	runner.assert_true(world.is_view_ready(lower_right), "a view overlapping the lower-right boundary completes its in-world portion")
	runner.assert_eq(_projection_errors(world, Rect2i(last - Vector2i(2, 2), Vector2i(3, 3))), 0, "lower-right clipped cells have their actual atlas and elevation")
	runner.assert_eq(_outside_world_count(world), 0, "clipped priority requests never paint outside the finite world")
	runner.assert_eq(_count_in_chunk(world, Vector2i.ZERO), 0, "far focus changes discard old priority ground and vegetation")
	runner.assert_eq(_count_in_chunk(world, Vector2i(2, 0)), 0, "far focus changes also discard old priority cells in neighboring chunks")
	runner.assert_eq(_count_in_chunk(world, Vector2i(3, 0)), 0, "far focus changes discard the newly reachable priority cells too")
	world.free()

	# Abandon an incomplete cross-chunk priority queue, not just a completed
	# small view, to catch orphaned out-of-order cells on a rapid jump.
	world = ReolWorld.new()
	world.initialize()
	var focus := Vector2i(256, 228)
	var view := Rect2i(Vector2i(244, 219), Vector2i(25, 19))
	world.set_focus(focus)
	world.prioritize_view(view)
	world._process(0.016)
	runner.assert_true(_count_in_chunk(world, Vector2i(3, 3)) > 0 and _count_in_chunk(world, Vector2i(4, 3)) > 0, "incomplete priority fixture contains cells on both sides of a chunk boundary")
	runner.assert_true(world._cliff_nodes.has(Vector2i(3, 3)) and world._cliff_nodes.has(Vector2i(4, 3)), "incomplete priority chunks also own their cliff views")
	world.bind_map_data(world.map_data().independent_copy())
	runner.assert_eq(_ground_count(world), 0, "rebinding while priority is incomplete clears its out-of-order ground cells")
	runner.assert_eq(_flora_count(world), 0, "rebinding while priority is incomplete clears its out-of-order vegetation")
	runner.assert_true(world._cliff_nodes.is_empty() and not world.is_view_ready(view), "rebinding invalidates partial cliff views and readiness")
	world.prioritize_view(view)
	world._process(0.016)
	runner.assert_true(_count_in_chunk(world, Vector2i(3, 3)) > 0 and _count_in_chunk(world, Vector2i(4, 3)) > 0, "the same incomplete view can be prioritized again after rebinding")
	world.set_focus(last)
	world.prioritize_view(lower_right)
	for _step: int in range(20):
		world._process(0.016)
	runner.assert_true(world.is_view_ready(lower_right), "a rapid far jump prioritizes the new destination view")
	runner.assert_eq(_count_in_chunk(world, Vector2i(3, 3)), 0, "rapid far jump clears the first abandoned partial chunk")
	runner.assert_eq(_count_in_chunk(world, Vector2i(4, 3)), 0, "rapid far jump clears the second abandoned partial chunk")
	runner.assert_true(not world._cliff_nodes.has(Vector2i(3, 3)) and not world._cliff_nodes.has(Vector2i(4, 3)), "rapid far jump releases both abandoned partial cliff views")
	runner.assert_eq(_outside_world_count(world), 0, "far-jump destination painting remains inside the world")
	world.free()


func _priority_after_ordinary_batch(runner: Object) -> void:
	var world := ReolWorld.new()
	world.initialize()
	world.set_focus(Vector2i.ZERO)
	world._pending_load.clear()
	world._pending_load.append(Vector2i.ZERO)
	world._process(0.016)
	runner.assert_eq(_ground_count(world), ReolWorld.PAINT_CELLS_PER_FRAME, "the priority-after-streaming fixture begins with an ordinary partial chunk")
	var before_clock: Dictionary = GameClock.to_dict()
	var before_ground: int = _ground_count(world)
	var before_flora: int = _flora_count(world)
	var already_painted := Rect2i(Vector2i(2, 1), Vector2i(5, 2))
	runner.assert_true(world.is_view_ready(already_painted), "the small view lies entirely in the ordinary first four painted rows")
	runner.assert_true(not world._cliff_nodes.has(Vector2i.ZERO), "ordinary partial painting has not yet created a cliff view")
	world.prioritize_view(already_painted)
	runner.assert_true(world._cliff_nodes.has(Vector2i.ZERO), "an already painted priority view creates the partial cliff view")
	runner.assert_eq(_cliff_mask_errors(world, Vector2i.ZERO), 0, "the partial cliff mask matches all and only ground painted by ordinary streaming")
	runner.assert_eq(_projection_errors(world, already_painted), 0, "prioritizing already painted cells keeps their actual terrain and vegetation projection")
	runner.assert_eq(_ground_count(world), before_ground, "an already painted priority view does not add ground cells")
	runner.assert_eq(_flora_count(world), before_flora, "an already painted priority view does not add vegetation cells")
	runner.assert_eq(GameClock.to_dict(), before_clock, "creating the partial cliff view does not advance shared time")
	var view := Rect2i(Vector2i(30, 30), Vector2i(5, 5))
	world.prioritize_view(view)
	world._process(0.016)
	runner.assert_true(world.is_view_ready(view), "a priority view can be added to an already active ordinary chunk")
	runner.assert_eq(_cliff_mask_errors(world, Vector2i.ZERO), 0, "partial cliff coverage includes ordinary cells painted before the first priority request")
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
	var view := Rect2i(Vector2i(20, 20), Vector2i(7, 7))
	world.prioritize_view(view)
	world._process(0.016)
	runner.assert_true(world.is_view_ready(view), "synchronous replacement fixture has a completed priority view inside a partial chunk")
	world._load_chunk(Vector2i(1, 1))
	runner.assert_true(world._loaded.has(Vector2i(1, 1)), "explicit synchronous tool entry still completes its requested chunk")
	runner.assert_eq(_count_in_chunk(world, Vector2i.ZERO), 0, "synchronous entry cleans an overridden partial chunk rather than orphaning its untracked tiles")
	world.prioritize_view(view)
	world._process(0.016)
	runner.assert_true(world.is_view_ready(view), "the same priority view can be restored after its partial chunk was cancelled")
	runner.assert_eq(_projection_errors(world, view), 0, "re-prioritizing after cancellation restores the correct ground and vegetation")
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


func _ground_at(world: ReolWorld, cell: Vector2i) -> bool:
	for layer: TileMapLayer in world._layers:
		if layer.get_cell_source_id(cell) != -1:
			return true
	return false


func _projection_errors(world: ReolWorld, bounds: Rect2i) -> int:
	var errors: int = 0
	var ground_source: TileSetAtlasSource = world._tile_set.get_source(0)
	var flora_source: TileSetAtlasSource = world._tile_set.get_source(1)
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			var natural: Dictionary = world.map_data().natural_cell(cell)
			var elevation: int = world.get_elevation(cell)
			var ground := Vector2i(NaturalEnvironment.SURFACES.find(str(natural.surface_id)), Visuals.variant_for(cell))
			var flora: Dictionary = natural.get("flora", {})
			var plant := Vector2i(-1, -1)
			if not flora.is_empty():
				plant = Vector2i(world._flora_ids.find(flora.id), int(flora.variant))
			for level: int in ReolWorld.ELEVATION_LEVELS:
				var ground_id: int = world._layers[level].get_cell_source_id(cell)
				var plant_id: int = world._flora_layers[level].get_cell_source_id(cell)
				if level == elevation:
					if ground_id != 0 or world._layers[level].get_cell_atlas_coords(cell) != ground or not ground_source.has_tile(ground):
						errors += 1
					if flora.is_empty():
						if plant_id != -1:
							errors += 1
					elif plant_id != 1 or world._flora_layers[level].get_cell_atlas_coords(cell) != plant or not flora_source.has_tile(plant):
						errors += 1
				elif ground_id != -1 or plant_id != -1:
					errors += 1
	return errors


func _outside_world_count(world: ReolWorld) -> int:
	var count: int = 0
	var bounds := Rect2i(Vector2i.ZERO, Vector2i.ONE * ReolWorld.WORLD_SIZE)
	var layers: Array[TileMapLayer] = []
	layers.append_array(world._layers)
	layers.append_array(world._flora_layers)
	for layer: TileMapLayer in layers:
		for cell: Vector2i in layer.get_used_cells():
			if not bounds.has_point(cell):
				count += 1
	return count


func _cliff_mask_errors(world: ReolWorld, chunk: Vector2i) -> int:
	var cliff: CliffChunk = world._cliff_nodes.get(chunk)
	if cliff == null or cliff.complete:
		return 1
	var errors: int = 0
	var bounds := Rect2i(chunk * ReolWorld.CHUNK_SIZE, Vector2i.ONE * ReolWorld.CHUNK_SIZE)
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			if cliff.partial_cells.has(cell) != _ground_at(world, cell):
				errors += 1
	for cell: Vector2i in cliff.partial_cells:
		if not bounds.has_point(cell):
			errors += 1
	return errors


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
