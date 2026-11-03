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
	var tint := DayNight.new()
	var just_before: Color = tint._color_for_hour(6.999)
	var just_after: Color = tint._color_for_hour(7.001)
	runner.assert_true(absf(just_before.g - just_after.g) < 0.001, "dawn tint does not abruptly snap to full daylight at seven")
	runner.assert_eq(tint._color_for_hour(9.0), DayNight.DAY, "daylight tint is reached after the dawn transition")
	tint.free()


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
