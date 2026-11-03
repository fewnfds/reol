extends RefCounted
## Full original-map equivalence is required before adding persistent deltas.

const Legacy = preload("res://tests/sim/helpers/legacy_world_map_oracle.gd")
const STEPS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]


func run(runner: Object) -> void:
	var original: Legacy = Legacy.new()
	var map := WorldMapData.new()
	runner.assert_eq(WorldMapData.generation_descriptor(), Legacy.generation_descriptor(), "extracted map retains the genuine old generator descriptor without a migration")
	runner.assert_eq(WorldMapData.WORLD_SIZE, Legacy.WORLD_SIZE, "map size remains the original finite extent")
	runner.assert_eq(WorldMapData.WORLD_SEED, Legacy.WORLD_SEED, "map seed remains the original world")
	_full_map(runner, map, original)
	_boundaries(runner, map, original)
	_independent_copy(runner, map)
	print("SCENARIO map data: full 512x512 legacy terrain/elevation/walkability and eight directed static steps, boundary semantics and independent query copy")


func _full_map(runner: Object, map: WorldMapData, original: Legacy) -> void:
	var terrain_errors: int = 0
	var height_errors: int = 0
	var walking_errors: int = 0
	var step_errors: int = 0
	var first_terrain: String = ""
	var first_height: String = ""
	var first_walking: String = ""
	var first_step: String = ""
	for y: int in Legacy.WORLD_SIZE:
		for x: int in Legacy.WORLD_SIZE:
			var cell := Vector2i(x, y)
			var expected_terrain: int = original.get_terrain(cell)
			var actual_terrain: int = map.get_terrain(cell)
			if actual_terrain != expected_terrain:
				terrain_errors += 1
				if first_terrain.is_empty():
					first_terrain = "%s expected %d, got %d" % [cell, expected_terrain, actual_terrain]
			var expected_height: int = original.get_elevation(cell)
			var actual_height: int = map.get_elevation(cell)
			if actual_height != expected_height:
				height_errors += 1
				if first_height.is_empty():
					first_height = "%s expected %d, got %d" % [cell, expected_height, actual_height]
			var expected_walking: bool = original.terrain_is_walkable(cell)
			var actual_walking: bool = map.terrain_is_walkable(cell)
			if actual_walking != expected_walking:
				walking_errors += 1
				if first_walking.is_empty():
					first_walking = "%s expected %s, got %s" % [cell, expected_walking, actual_walking]
			for step: Vector2i in STEPS:
				var expected: bool = original.terrain_can_step(cell, step)
				var actual: bool = map.terrain_can_step(cell, step)
				if actual != expected:
					step_errors += 1
					if first_step.is_empty():
						first_step = "%s + %s expected %s, got %s" % [cell, step, expected, actual]
	# Four aggregated assertions retain full coverage without producing millions
	# of runner checks or an unbounded failure stream for one generator error.
	runner.assert_eq(terrain_errors, 0, "every original terrain cell is preserved; first mismatch: " + first_terrain)
	runner.assert_eq(height_errors, 0, "every original elevation cell is preserved; first mismatch: " + first_height)
	runner.assert_eq(walking_errors, 0, "every original terrain walkability result is preserved; first mismatch: " + first_walking)
	runner.assert_eq(step_errors, 0, "all 2097152 original directed neighbouring steps are preserved; first mismatch: " + first_step)


func _boundaries(runner: Object, map: WorldMapData, original: Legacy) -> void:
	var outside: Array[Vector2i] = [
		Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(0, -1),
		Vector2i(512, 0), Vector2i(0, 512), Vector2i(512, 511),
		Vector2i(511, 512), Vector2i(512, 512), Vector2i(-512, 1024),
	]
	for cell: Vector2i in outside:
		runner.assert_eq(map.get_terrain(cell), -1, "outside terrain stays unknown: " + str(cell))
		runner.assert_eq(map.get_elevation(cell), -1, "outside elevation stays unknown: " + str(cell))
		runner.assert_true(not map.terrain_is_walkable(cell), "outside cells do not acquire ground: " + str(cell))
		runner.assert_true(map.terrain_can_step(cell, Vector2i.ZERO), "old zero-step contract includes outside origins: " + str(cell))
		for step: Vector2i in STEPS:
			runner.assert_eq(map.terrain_can_step(cell, step), original.terrain_can_step(cell, step), "original boundary-origin step is preserved: %s + %s" % [cell, step])
	for cell: Vector2i in [Vector2i.ZERO, Vector2i(511, 0), Vector2i(0, 511), Vector2i(511, 511), Vector2i(256, 256)]:
		runner.assert_true(map.terrain_can_step(cell, Vector2i.ZERO), "zero step does not invent movement or require accessible source terrain: " + str(cell))


func _independent_copy(runner: Object, map: WorldMapData) -> void:
	var copied: WorldMapData = map.independent_copy()
	runner.assert_true(copied != null and copied != map, "map candidate copy has its own data object rather than the live owner")
	if copied == null:
		return
	var mismatches: int = 0
	var first: String = ""
	for y: int in range(0, Legacy.WORLD_SIZE, 17):
		for x: int in range(0, Legacy.WORLD_SIZE, 19):
			var cell := Vector2i(x, y)
			var same: bool = copied.get_terrain(cell) == map.get_terrain(cell) and copied.get_elevation(cell) == map.get_elevation(cell) and copied.terrain_is_walkable(cell) == map.terrain_is_walkable(cell)
			for step: Vector2i in STEPS:
				same = same and copied.terrain_can_step(cell, step) == map.terrain_can_step(cell, step)
			if not same:
				mismatches += 1
				if first.is_empty():
					first = str(cell)
	runner.assert_eq(mismatches, 0, "independent copy preserves static queries; first mismatch: " + first)
