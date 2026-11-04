extends RefCounted
## Sparse flat terrain is authoritative without granting a live edit permission.

const Nature = preload("res://scripts/sim/natural_environment.gd")


func run(runner: Object) -> void:
	_patches_and_independent_copy(runner)
	_restore_validation(runner)
	_natural_water_dependencies(runner)
	_affected_edges(runner)
	_legacy_is_immutable(runner)
	print("SCENARIO flat terrain overrides: atomic patches, independent candidates, nature cache and saved values")


func _new_map() -> WorldMapData:
	return WorldMapData.from_descriptor(WorldMapData.flat_descriptor(42))


func _other_terrain(terrain: int) -> int:
	return (terrain + 1) % 3


func _patches_and_independent_copy(runner: Object) -> void:
	var map: WorldMapData = _new_map()
	runner.assert_not_null(map, "flat map is available for terrain overrides")
	if map == null:
		return
	var first := Vector2i(40, 11)
	var second := Vector2i(8, 10)
	var third := Vector2i(3, 11)
	var first_base: int = map.get_terrain(first)
	var second_base: int = map.get_terrain(second)
	var third_base: int = map.get_terrain(third)
	var first_next: int = _other_terrain(first_base)
	var second_next: int = _other_terrain(second_base)
	var third_next: int = _other_terrain(third_base)
	var notifications: Array = []
	map.terrain_changed.connect(func(cells: Array[Vector2i]) -> void:
		notifications.append(cells.duplicate())
		# A subscriber cannot mutate the value returned by the patch.
		cells.clear()
	)
	var result: Dictionary = map.apply_terrain_patch([
		[first.x, first.y, first_next], [second.x, second.y, second_next], [third.x, third.y, third_next]])
	runner.assert_true(bool(result.ok), "a flat batch applies after every row validates")
	runner.assert_eq(result.changed_cells, [second, third, first], "changed coordinates have stable row-major order")
	runner.assert_eq(notifications.size(), 1, "one successful batch emits one notification")
	if notifications.size() == 1:
		runner.assert_eq(notifications[0], result.affected_cells, "notification carries the same affected coordinates without exposing the result array")
	runner.assert_eq(map.terrain_overrides(), [[second.x, second.y, second_next], [third.x, third.y, third_next], [first.x, first.y, first_next]], "serialized overrides are sorted independently of input order")
	for cell: Vector2i in [first, second, third]:
		runner.assert_eq(map.get_elevation(cell), 0, "terrain patches do not create height in a flat world")
		runner.assert_eq(map.terrain_is_walkable(cell), map.get_terrain(cell) == WorldMapData.TERRAIN_GRASS, "walkability reads the changed authoritative terrain")
	var exported: Array = map.terrain_overrides()
	exported[0][2] = -1
	exported.clear()
	runner.assert_eq(map.get_terrain(second), second_next, "editing exported data cannot modify the authoritative map")
	var before_copy: Dictionary = map.natural_cell(first)
	var copy: WorldMapData = map.independent_copy()
	runner.assert_true(copy != null and copy != map, "independent map copy exists")
	if copy == null:
		return
	runner.assert_eq(copy.terrain_overrides(), map.terrain_overrides(), "copy includes actual sparse terrain state")
	runner.assert_eq(copy.natural_cell(first), before_copy, "copy derives the same natural state from its own map")
	var reset: Dictionary = map.apply_terrain_patch([[first.x, first.y, first_base]])
	runner.assert_true(bool(reset.ok), "a patch may restore the generated base terrain")
	runner.assert_eq(map.get_terrain(first), first_base, "restoring the base changes the authoritative terrain")
	runner.assert_eq(copy.get_terrain(first), first_next, "editing the original does not change its independent copy")
	runner.assert_eq(map.terrain_overrides().size(), 2, "returning to base removes the redundant override")
	runner.assert_eq(copy.terrain_overrides().size(), 3, "copy retains its own original overrides")
	var events_before: int = notifications.size()
	var same: Dictionary = map.apply_terrain_patch([[first.x, first.y, first_base]])
	runner.assert_true(bool(same.ok), "a valid no-op patch succeeds")
	runner.assert_true(same.changed_cells.is_empty() and same.affected_cells.is_empty(), "a no-op patch reports no changed or affected cells")
	runner.assert_eq(notifications.size(), events_before, "a no-op patch emits no notification")


func _restore_validation(runner: Object) -> void:
	var map: WorldMapData = _new_map()
	if map == null:
		runner.assert_true(false, "flat map exists for restore checks")
		return
	var a := Vector2i(151, 170)
	var b := Vector2i(153, 170)
	var a_base: int = map.get_terrain(a)
	var b_base: int = map.get_terrain(b)
	var a_next: int = _other_terrain(a_base)
	var b_next: int = _other_terrain(b_base)
	runner.assert_true(bool(map.apply_terrain_patch([[a.x, a.y, a_next]]).ok), "restore test starts with a real override")
	var original: Array = map.terrain_overrides()
	var events: Array = []
	map.terrain_changed.connect(func(cells: Array[Vector2i]) -> void: events.append(cells.duplicate()))
	var invalid_rows: Array = [
		null, true, {}, [null], [[a.x, a.y]], [[a.x, a.y, a_next, 0]],
		[[a.x, a.y, a_next], [a.x, a.y, b_next]], [[-1, a.y, a_next]],
		[[512, a.y, a_next]], [[a.x, 512, a_next]], [[a.x, a.y, 3]],
		[[a.x, a.y, -1]], [[a.x, a.y, true]], [[true, a.y, a_next]],
		[[1.5, a.y, a_next]], [[a.x, a.y, 1.5]], [[INF, a.y, a_next]],
		[[NAN, a.y, a_next]], [[a.x, a.y, a_base]],
	]
	for bad: Variant in invalid_rows:
		runner.assert_true(not map.restore_terrain_overrides(bad), "restore rejects malformed, out-of-range, duplicate or redundant rows")
		runner.assert_eq(map.terrain_overrides(), original, "bad restore leaves the previous overrides unchanged")
	runner.assert_true(events.is_empty(), "bad restore emits no change notification")
	runner.assert_true(not map.restore_terrain_overrides([[b.x, b.y, b_next], [a.x, a.y, a_base]]), "redundant second restore row rejects the whole replacement")
	runner.assert_eq(map.terrain_overrides(), original, "earlier valid replacement row was not partially committed")
	var invalid_patch: Array = [[a.x, a.y, a_base], [512, b.y, b_next]]
	var rejected: Dictionary = map.apply_terrain_patch(invalid_patch)
	runner.assert_true(not bool(rejected.ok), "invalid second patch row rejects the entire batch")
	runner.assert_true(rejected.changed_cells.is_empty() and rejected.affected_cells.is_empty(), "rejected patch reports no changes")
	runner.assert_eq(map.terrain_overrides(), original, "first patch row was not partially applied")
	runner.assert_true(events.is_empty(), "rejected patch emits no notification")
	runner.assert_true(not bool(map.apply_terrain_patch([[b.x, b.y, b_next], [b.x, b.y, b_base]]).ok), "duplicate patch coordinates are rejected")
	runner.assert_eq(map.terrain_overrides(), original, "duplicate patch cannot partially modify the map")
	var too_many: Array = []
	too_many.resize(WorldMapData.WORLD_SIZE * WorldMapData.WORLD_SIZE + 1)
	runner.assert_true(not bool(map.apply_terrain_patch(too_many).ok), "patch cannot exceed the finite map area")
	runner.assert_true(not map.restore_terrain_overrides(too_many), "restore cannot exceed the finite map area")
	runner.assert_eq(map.terrain_overrides(), original, "oversized input leaves the prior state intact")
	var json_rows: Variant = JSON.parse_string(JSON.stringify([[float(b.x), float(b.y), float(b_next)], [float(a.x), float(a.y), float(a_next)]]))
	runner.assert_true(map.restore_terrain_overrides(json_rows), "JSON whole-number floats are accepted at the persistence boundary")
	runner.assert_eq(map.terrain_overrides(), [[a.x, a.y, a_next], [b.x, b.y, b_next]], "restored values are canonical integers in stable order")
	runner.assert_eq(events.size(), 1, "restore publishes the effective change after accepting the complete candidate")
	runner.assert_true(map.restore_terrain_overrides([]), "an empty replacement removes all flat overrides")
	runner.assert_true(map.terrain_overrides().is_empty(), "empty replacement restores the generated base")
	runner.assert_eq(map.get_terrain(a), a_base, "first restored cell matches its base")
	runner.assert_eq(map.get_terrain(b), b_base, "second restored cell matches its base")


func _natural_water_dependencies(runner: Object) -> void:
	var map: WorldMapData = _new_map()
	if map == null:
		runner.assert_true(false, "flat map exists for nature-cache checks")
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(Nature.DEFAULT_PATH))
	if not raw is Dictionary:
		runner.assert_true(false, "natural rules load for terrain test")
		return
	var rules: Dictionary = raw
	rules.land.water_probe_distances = [2, 4]
	rules.cache_cells = 3
	runner.assert_true(map.configure_nature(rules), "test installs independent valid water probe distances")
	var center := Vector2i(200, 200)
	var dry: Array = []
	for y: int in range(center.y - 8, center.y + 9):
		for x: int in range(center.x - 8, center.x + 9):
			dry.append([x, y, WorldMapData.TERRAIN_GRASS])
	runner.assert_true(bool(map.apply_terrain_patch(dry).ok), "isolated test substrate is made dry without changing height")
	var near: Vector2i = center + Vector2i.RIGHT * 2
	var far: Vector2i = center + Vector2i.RIGHT * 4
	var unaffected: Vector2i = center + Vector2i.RIGHT
	var before_near: Dictionary = map.natural_cell(near)
	var before_far: Dictionary = map.natural_cell(far)
	var before_unaffected: Dictionary = map.natural_cell(unaffected)
	runner.assert_eq(int(before_near.water_nearby), 0, "near cell begins with no actual nearby map water")
	runner.assert_eq(int(before_far.water_nearby), 0, "far cell begins with no actual nearby map water")
	# Force ring-cache eviction before changing a source, then revisit those keys.
	for x: int in range(12):
		map.natural_cell(center + Vector2i(x - 6, 3))
	var before_copy: WorldMapData = map.independent_copy()
	if before_copy == null:
		runner.assert_true(false, "independent dry candidate exists")
		return
	var changed: Dictionary = map.apply_terrain_patch([[center.x, center.y, WorldMapData.TERRAIN_WATER]])
	var expected: Array[Vector2i] = [center]
	for distance: int in [2, 4]:
		for direction: Vector2i in Nature.DIRECTIONS:
			expected.append(center + direction * distance)
	expected.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	runner.assert_eq(changed.changed_cells, [center], "only the source's substrate changes")
	runner.assert_eq(changed.affected_cells, expected, "affected cells use the bound session's actual probe distances")
	runner.assert_eq(int(map.natural_cell(near).water_nearby), int(rules.land.water_probe_bonus[0]), "cached nearby substrate observes the new water")
	runner.assert_eq(int(map.natural_cell(far).water_nearby), int(rules.land.water_probe_bonus[1]), "cached farther substrate observes the new water")
	runner.assert_eq(map.natural_cell(unaffected), before_unaffected, "a cell outside the water probes keeps its derived natural state")
	runner.assert_eq(map.natural_surface(center), "water", "the changed source has a water surface")
	runner.assert_eq(before_copy.natural_cell(near), before_near, "another map does not inherit source or cache changes")
	runner.assert_eq(before_copy.natural_cell(far), before_far, "another map retains its independent farther substrate")
	var second: Vector2i = center + Vector2i.RIGHT * 6
	runner.assert_true(bool(map.apply_terrain_patch([[second.x, second.y, WorldMapData.TERRAIN_WATER]]).ok), "second water source is added")
	runner.assert_eq(int(map.natural_cell(far).water_nearby), int(rules.land.water_probe_bonus[0]), "nearer source takes precedence over farther source")
	runner.assert_true(bool(map.apply_terrain_patch([[center.x, center.y, WorldMapData.TERRAIN_GRASS]]).ok), "first source can be removed")
	runner.assert_eq(int(map.natural_cell(far).water_nearby), int(rules.land.water_probe_bonus[0]), "removing one source does not erase another source's influence")
	runner.assert_eq(int(map.natural_cell(center).water_nearby), 0, "removed source no longer claims water at its old cell")


func _affected_edges(runner: Object) -> void:
	var map: WorldMapData = _new_map()
	if map == null:
		runner.assert_true(false, "flat map exists for bounded affected-cell checks")
		return
	var center := Vector2i.ZERO
	map.apply_terrain_patch([[0, 0, WorldMapData.TERRAIN_GRASS]])
	var rock: Dictionary = map.apply_terrain_patch([[0, 0, WorldMapData.TERRAIN_ROCK]])
	runner.assert_eq(rock.affected_cells, [center], "non-water terrain changes affect only their own derived cell")
	var water: Dictionary = map.apply_terrain_patch([[0, 0, WorldMapData.TERRAIN_WATER]])
	var expected: Array[Vector2i] = [center, Vector2i(1, 0), Vector2i(3, 0), Vector2i(0, 1), Vector2i(0, 3)]
	expected.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	runner.assert_eq(water.affected_cells, expected, "affected water probes are clipped to world bounds")


func _legacy_is_immutable(runner: Object) -> void:
	var map: WorldMapData = WorldMapData.from_descriptor(WorldMapData.legacy_descriptor())
	if map == null:
		runner.assert_true(false, "historical map still constructs")
		return
	var cell := Vector2i(200, 200)
	var terrain: int = map.get_terrain(cell)
	var elevation: int = map.get_elevation(cell)
	var events: Array = []
	map.terrain_changed.connect(func(cells: Array[Vector2i]) -> void: events.append(cells.duplicate()))
	runner.assert_true(map.restore_terrain_overrides([]), "a historical map accepts an empty saved override set")
	runner.assert_true(not map.restore_terrain_overrides([[cell.x, cell.y, _other_terrain(terrain)]]), "a historical map rejects nonempty override data")
	runner.assert_true(not bool(map.apply_terrain_patch([[cell.x, cell.y, _other_terrain(terrain)]]).ok), "a historical map rejects terrain edits")
	runner.assert_true(not bool(map.apply_terrain_patch([]).ok), "even an empty edit request is not accepted by a historical map")
	runner.assert_eq(map.get_terrain(cell), terrain, "historical terrain stays unchanged")
	runner.assert_eq(map.get_elevation(cell), elevation, "historical elevation stays unchanged")
	runner.assert_true(map.terrain_overrides().is_empty() and events.is_empty(), "historical map stores and emits no terrain modifications")
