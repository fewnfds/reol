extends RefCounted
## Regressions for presentation bugs and redundant visibility work.

const ViewLayout = preload("res://scripts/entities/pawn_view_layout.gd")


class CountingWorld extends ReolWorld:
	var terrain_queries: int = 0


	func get_terrain(_cell: Vector2i) -> int:
		terrain_queries += 1
		return TERRAIN_GRASS


	func get_elevation(_cell: Vector2i) -> int:
		return 0


func run(runner: Object) -> void:
	_test_stationary_visibility(runner)
	_test_cliff_chunk_position(runner)
	_test_dawn_continuity(runner)
	_test_crowd_layout(runner)


func _test_stationary_visibility(runner: Object) -> void:
	var world := CountingWorld.new()
	var fog := FogOfWar.new()
	fog.setup(world, Vector2i(256, 256))
	var after_setup: int = world.terrain_queries
	for _index: int in 20:
		fog.set_focus(Vector2i(256, 256))
		fog._process(FogOfWar.UPDATE_INTERVAL)
	runner.assert_eq(world.terrain_queries, after_setup, "stationary visibility reuses known visibility without tracing terrain again")
	fog.invalidate_visibility()
	fog._process(FogOfWar.UPDATE_INTERVAL)
	runner.assert_true(world.terrain_queries > after_setup, "explicit occluder invalidation refreshes a stationary observer")
	fog.set_focus(Vector2i(288, 256))
	fog._process(FogOfWar.UPDATE_INTERVAL)
	runner.assert_true(fog.is_cell_visible(Vector2i(288, 256)), "moving focus recomputes current visibility")
	runner.assert_eq(fog.get_state(Vector2i(256, 256)), FogOfWar.STATE_EXPLORED, "leaving sight preserves explored state")
	var queries: int = world.terrain_queries
	fog.update_now()
	runner.assert_true(world.terrain_queries > queries, "explicit immediate refresh remains available after reading a snapshot")
	fog.free()
	world.free()


func _test_cliff_chunk_position(runner: Object) -> void:
	var world := ReolWorld.new()
	world.initialize()
	var chunk := Vector2i(4, 4)
	world._load_chunk(chunk)
	var cliff: CliffChunk = world._cliff_nodes[chunk]
	runner.assert_eq(cliff.position, Vector2(chunk * ReolWorld.CHUNK_SIZE * TileGrid.TILE_SIZE), "cliff local geometry is placed at its actual world chunk rather than at world origin")
	world.free()


func _test_dawn_continuity(runner: Object) -> void:
	var climate: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/climate.json"))
	var solar: Dictionary = SimSolarRules.migration_defaults()
	# At zero tilt on the equator, geometric sunrise/set are exactly local
	# 06/18. Test their physical instants rather than the removed hour table.
	solar.latitude_mdeg = 0
	solar.axial_tilt_mdeg = 0
	for hour: int in [6, 18]:
		var transition: int = SimWorldCalendar.DAY_MS + hour * 3600000 - int(climate.calendar.start_minutes) * 60000
		var before: Dictionary = SimSolarRules.sample(climate.calendar, solar, transition - 1000)
		var after: Dictionary = SimSolarRules.sample(climate.calendar, solar, transition + 1000)
		runner.assert_true(not before.is_empty() and not after.is_empty(), "the geometric horizon has valid before/after solar samples")
		if before.is_empty() or after.is_empty():
			continue
		before.supported = true
		after.supported = true
		var just_before: Color = DayNight.color_for_sky(before)
		var just_after: Color = DayNight.color_for_sky(after)
		for channel: String in ["r", "g", "b"]:
			runner.assert_true(absf(float(just_before[channel]) - float(just_after[channel])) < 0.001, "the solar horizon tint has no abrupt %s snap at %d" % [channel, hour])
	for pair: Array in [[12, DayNight.DAY], [0, DayNight.NIGHT]]:
		var instant: int = SimWorldCalendar.DAY_MS + int(pair[0]) * 3600000 - int(climate.calendar.start_minutes) * 60000
		var sky: Dictionary = SimSolarRules.sample(climate.calendar, solar, instant)
		sky.supported = true
		runner.assert_eq(DayNight.color_for_sky(sky), pair[1], "the actual equatorial noon/midnight reaches its declared tint")


func _test_crowd_layout(runner: Object) -> void:
	var actors: Dictionary = {
		"b": {"cell": [10, 10]}, "a": {"cell": [10, 10]},
		"player": {"cell": [10, 10]}, "alone": {"cell": [12, 10]},
	}
	var before: String = JSON.stringify(actors)
	var layout: Dictionary = ViewLayout.build(actors, "player")
	runner.assert_eq(layout.player.offset, Vector2.ZERO, "player remains at the real cell center when residents share the facility")
	runner.assert_true(layout.a.offset != layout.b.offset and layout.a.offset.length() <= 24.001, "shared-cell resident silhouettes receive distinct bounded visual offsets")
	runner.assert_true(not layout.a.caption_visible and not layout.b.caption_visible, "crowded unselected residents suppress overlapping nameplates")
	runner.assert_true(layout.alone.caption_visible and layout.alone.offset == Vector2.ZERO, "an isolated resident keeps its normal position and label")
	var reordered: Dictionary = {"alone": actors.alone, "player": actors.player, "a": actors.a, "b": actors.b}
	runner.assert_eq(ViewLayout.build(reordered, "player"), layout, "stable IDs give the same crowd placement regardless of dictionary insertion order")
	runner.assert_eq(JSON.stringify(actors), before, "crowd layout does not alter persistent cells or simulation data")
	var visitor: Dictionary = ViewLayout.build({"a": actors.a}, "", Vector2i(10, 10))
	runner.assert_true(visitor.a.offset != Vector2.ZERO and not visitor.a.caption_visible, "a visiting player reserves the center without creating another actor")
	var pawn := Pawn.new()
	pawn.global_position = Vector2(100, 100)
	pawn.set_view_layout(layout.a)
	runner.assert_eq(pawn.selection_center(), Vector2(100, 88) + layout.a.offset, "resident hit testing follows its drawn offset")
	pawn.free()
