extends RefCounted
## Navigation must use the same elevation and diagonal rules as manual movement.


class NavigationWorld extends ReolWorld:
	var cells: Dictionary[Vector2i, int] = {}
	var terrain_queries: int = 0


	func _ready() -> void:
		pass


	func terrain_is_walkable(cell: Vector2i) -> bool:
		terrain_queries += 1
		return cells.has(cell)


	func get_elevation(cell: Vector2i) -> int:
		return int(cells.get(cell, -100))


	func can_move(from_cell: Vector2i, to_cell: Vector2i) -> bool:
		return (
			is_walkable(from_cell) and is_walkable(to_cell)
			and ReolWorld.elevation_step_allowed(get_elevation(from_cell), get_elevation(to_cell))
		)


func run_tests(runner: Object) -> void:
	_test_detour(runner)
	_test_unreachable(runner)
	_test_limits(runner)
	_test_same_cell(runner)
	_test_elevation(runner)
	_test_diagonal(runner)
	_test_revisioned_reuse(runner)
	_test_opaque_geometry(runner)
	_test_owner_isolation(runner)


func _test_revisioned_reuse(runner: Object) -> void:
	var world := NavigationWorld.new()
	for x: int in 6:
		world.cells[Vector2i(x, 0)] = 0
	var state: Dictionary = {"revision": 0, "blocked": {}}
	world.set_obstacle_provider(func(cell: Vector2i) -> bool: return state.blocked.has(cell),
		func() -> int: return int(state.revision))
	var path: Array[Vector2i] = VillageRuntime.find_grid_path(world, Vector2i.ZERO, Vector2i(5, 0), 6, 64)
	runner.assert_true(not path.is_empty(), "observable geometry produces an original legal route")
	var queries: int = world.terrain_queries
	var repeated: Array[Vector2i] = VillageRuntime.find_grid_path(world, Vector2i.ZERO, Vector2i(5, 0), 6, 64)
	runner.assert_eq(repeated, path, "same-version route reuse preserves the original native path")
	runner.assert_eq(world.terrain_queries, queries, "repeated same-version route does not query terrain again")
	repeated.clear()
	runner.assert_eq(VillageRuntime.find_grid_path(world, Vector2i.ZERO, Vector2i(5, 0), 6, 64), path, "caller mutation cannot consume a cached shared route")
	runner.assert_true(VillageRuntime.find_grid_path(world, Vector2i.ZERO, Vector2i(5, 0), 6, 1).is_empty(), "a cached successful route does not bypass a later search budget")
	state.blocked[Vector2i(2, 0)] = true
	state.revision += 1
	runner.assert_true(VillageRuntime.find_grid_path(world, Vector2i.ZERO, Vector2i(5, 0), 6, 64).is_empty(), "revision-only obstacle change invalidates cached routes and clearance")
	state.blocked.clear()
	state.revision += 1
	runner.assert_eq(VillageRuntime.find_grid_path(world, Vector2i.ZERO, Vector2i(5, 0), 6, 64), path, "opening the route invalidates the cached failure")
	world.is_walkable(Vector2i(5, 0))
	state.blocked[Vector2i(2, 0)] = true
	var previous_revision: int = int(state.revision)
	state.revision += 1
	world.invalidate_navigation([Vector2i(2, 0)], previous_revision)
	queries = world.terrain_queries
	runner.assert_true(world.is_walkable(Vector2i(5, 0)), "unaffected local clearance remains valid")
	runner.assert_eq(world.terrain_queries, queries, "local topology invalidation retains unrelated point queries")
	runner.assert_true(not world.is_walkable(Vector2i(2, 0)), "local invalidation refreshes its changed obstacle")
	runner.assert_true(VillageRuntime.find_grid_path(world, Vector2i.ZERO, Vector2i(5, 0), 6, 64).is_empty(), "local obstacle change still invalidates complete routes")
	state.blocked[Vector2i(5, 0)] = true
	state.revision += 1 # A separate dependency changed without a local notice.
	previous_revision = int(state.revision)
	state.revision += 1
	world.invalidate_navigation([Vector2i(2, 0)], previous_revision)
	runner.assert_true(not world.is_walkable(Vector2i(5, 0)), "a later local notice cannot hide an older unobserved dependency revision")
	world.free()


func _test_opaque_geometry(runner: Object) -> void:
	var world := NavigationWorld.new()
	for x: int in 3:
		world.cells[Vector2i(x, 0)] = 0
	var blocked: Dictionary = {}
	world.set_obstacle_provider(func(cell: Vector2i) -> bool: return blocked.has(cell))
	runner.assert_true(not VillageRuntime.find_grid_path(world, Vector2i.ZERO, Vector2i(2, 0), 3, 32).is_empty(), "opaque geometry initially allows its current route")
	blocked[Vector2i(1, 0)] = true
	runner.assert_true(VillageRuntime.find_grid_path(world, Vector2i.ZERO, Vector2i(2, 0), 3, 32).is_empty(), "unobservable callback changes are checked live instead of cached")
	blocked.clear()
	runner.assert_true(not VillageRuntime.find_grid_path(world, Vector2i.ZERO, Vector2i(2, 0), 3, 32).is_empty(), "opaque reopening does not retain a cached failure")
	world.free()


func _test_owner_isolation(runner: Object) -> void:
	var first := NavigationWorld.new()
	var second := NavigationWorld.new()
	for x: int in 3:
		first.cells[Vector2i(x, 0)] = 0
	for world: NavigationWorld in [first, second]:
		world.set_obstacle_provider(func(_cell: Vector2i) -> bool: return false, func() -> int: return 1)
	runner.assert_true(not VillageRuntime.find_grid_path(first, Vector2i.ZERO, Vector2i(2, 0), 3, 32).is_empty(), "first owner accepts its actual terrain")
	runner.assert_true(VillageRuntime.find_grid_path(second, Vector2i.ZERO, Vector2i(2, 0), 3, 32).is_empty(), "same revision in another world cannot reuse the first owner's route")
	first.set_obstacle_provider(func(_cell: Vector2i) -> bool: return true, func() -> int: return 1)
	runner.assert_true(VillageRuntime.find_grid_path(first, Vector2i.ZERO, Vector2i(2, 0), 3, 32).is_empty(), "replacing a provider invalidates same-number revision queries")
	first.free()
	second.free()


func _test_detour(runner: Object) -> void:
	var world := NavigationWorld.new()
	for cell: Vector2i in [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1),
		Vector2i(2, 2), Vector2i(1, 2), Vector2i(0, 2),
	]:
		world.cells[cell] = 0
	var path: Array[Vector2i] = VillageRuntime.find_grid_path(
		world, Vector2i.ZERO, Vector2i(0, 2), 4, 32
	)
	runner.call("assert_true", path.size() >= 5, "navigation walks around blocked cells")
	_assert_legal(runner, world, path, Vector2i.ZERO, Vector2i(0, 2))
	world.free()


func _test_unreachable(runner: Object) -> void:
	var world := NavigationWorld.new()
	world.cells[Vector2i.ZERO] = 0
	world.cells[Vector2i(2, 0)] = 0
	var path: Array[Vector2i] = VillageRuntime.find_grid_path(
		world, Vector2i.ZERO, Vector2i(2, 0), 4, 32
	)
	runner.call("assert_true", path.is_empty(), "unreachable navigation returns no path")
	world.free()


func _test_limits(runner: Object) -> void:
	var world := NavigationWorld.new()
	for x: int in range(5):
		world.cells[Vector2i(x, 0)] = 0
	runner.call("assert_true", VillageRuntime.find_grid_path(
		world, Vector2i.ZERO, Vector2i(4, 0), 3, 32
	).is_empty(), "navigation radius is enforced")
	runner.call("assert_true", VillageRuntime.find_grid_path(
		world, Vector2i.ZERO, Vector2i(2, 0), 4, 2
	).is_empty(), "navigation node budget is enforced")
	var enough_budget: Array[Vector2i] = VillageRuntime.find_grid_path(
		world, Vector2i.ZERO, Vector2i(2, 0), 4, 3
	)
	_assert_legal(runner, world, enough_budget, Vector2i.ZERO, Vector2i(2, 0))
	world.free()


func _test_same_cell(runner: Object) -> void:
	var world := NavigationWorld.new()
	world.cells[Vector2i.ZERO] = 0
	var path: Array[Vector2i] = VillageRuntime.find_grid_path(
		world, Vector2i.ZERO, Vector2i.ZERO, 0, 1
	)
	runner.call("assert_eq", path, [Vector2i.ZERO], "standing at a destination needs no move")
	runner.call("assert_true", VillageRuntime.find_grid_path(
		world, Vector2i(5, 5), Vector2i(5, 5), 1, 1
	).is_empty(), "blocked start and destination are rejected")
	runner.call("assert_true", VillageRuntime.find_grid_path(
		world, Vector2i.ZERO, Vector2i.ZERO, 1, 0
	).is_empty(), "zero navigation budget is rejected")
	world.free()


func _test_elevation(runner: Object) -> void:
	var world := NavigationWorld.new()
	world.cells[Vector2i.ZERO] = 0
	world.cells[Vector2i(1, 0)] = 2
	runner.call("assert_true", VillageRuntime.find_grid_path(
		world, Vector2i.ZERO, Vector2i(1, 0), 3, 32
	).is_empty(), "navigation cannot climb a two-level cliff")
	world.cells[Vector2i(0, 1)] = 1
	world.cells[Vector2i(1, 1)] = 2
	var path: Array[Vector2i] = VillageRuntime.find_grid_path(
		world, Vector2i.ZERO, Vector2i(1, 0), 3, 32
	)
	runner.call("assert_true", path.size() >= 3, "navigation uses a gradual height route")
	_assert_legal(runner, world, path, Vector2i.ZERO, Vector2i(1, 0))
	world.free()


func _test_diagonal(runner: Object) -> void:
	var world := NavigationWorld.new()
	world.cells[Vector2i.ZERO] = 0
	world.cells[Vector2i.ONE] = 0
	runner.call("assert_true", VillageRuntime.find_grid_path(
		world, Vector2i.ZERO, Vector2i.ONE, 2, 32
	).is_empty(), "navigation cannot squeeze through two closed diagonal corners")
	world.cells[Vector2i(1, 0)] = 0
	var path: Array[Vector2i] = VillageRuntime.find_grid_path(
		world, Vector2i.ZERO, Vector2i.ONE, 2, 32
	)
	runner.call("assert_eq", path.size(), 2, "one open side allows the existing diagonal rule")
	_assert_legal(runner, world, path, Vector2i.ZERO, Vector2i.ONE)
	world.free()


func _assert_legal(
	runner: Object,
	world: NavigationWorld,
	path: Array[Vector2i],
	start: Vector2i,
	finish: Vector2i
) -> void:
	runner.call("assert_true", not path.is_empty(), "reachable navigation produces a path")
	if path.is_empty():
		return
	runner.call("assert_eq", path[0], start, "navigation path begins at the actor")
	runner.call("assert_eq", path[-1], finish, "navigation path ends at the destination")
	for index: int in range(1, path.size()):
		var step: Vector2i = path[index] - path[index - 1]
		runner.call("assert_true", maxi(absi(step.x), absi(step.y)) == 1, "navigation advances one cell at a time")
		runner.call("assert_true", world.can_step(path[index - 1], step), "navigation obeys world.can_step")
