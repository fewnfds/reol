extends RefCounted
## Navigation must use the same elevation and diagonal rules as manual movement.


class NavigationWorld extends ReolWorld:
	var cells: Dictionary[Vector2i, int] = {}


	func _ready() -> void:
		pass


	func terrain_is_walkable(cell: Vector2i) -> bool:
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
