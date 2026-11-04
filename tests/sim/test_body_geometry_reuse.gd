extends RefCounted
## Stable geometry may be reused only within one path search.

const START := Vector2i(5, 10)
const GOAL := Vector2i(19, 10)
const SIZE := Vector2i(3, 3)
const RADIUS: int = 20
const FULL_BUDGET: int = 1000


class GeometrySpy extends RefCounted:
	var terrain: Dictionary = {}
	var walls: Dictionary = {}
	var heights: Dictionary = {}
	var walk_trace: Array[Vector2i] = []
	var height_trace: Array[Vector2i] = []

	func walkable(cell: Vector2i) -> bool:
		walk_trace.append(cell)
		return cell.x >= 0 and cell.x < 25 and cell.y >= 0 and cell.y < 21 and not terrain.has(cell) and not walls.has(cell)

	func elevation(cell: Vector2i) -> int:
		height_trace.append(cell)
		return int(heights.get(cell, 0))

	func clear_trace() -> void:
		walk_trace.clear()
		height_trace.clear()

	func make_gate() -> void:
		for y: int in range(21):
			if y < 9 or y > 11:
				walls[Vector2i(12, y)] = true


class StatefulGeometry extends RefCounted:
	var frequency: Dictionary = {}
	var trace: Array[Vector2i] = []
	var height_trace: Array[Vector2i] = []

	func walkable(cell: Vector2i) -> bool:
		trace.append(cell)
		var times: int = int(frequency.get(cell, 0)) + 1
		frequency[cell] = times
		return cell.x >= 0 and cell.x < 25 and cell.y >= 0 and cell.y < 21 and times % 3 != 0

	func elevation(cell: Vector2i) -> int:
		height_trace.append(cell)
		return 0

	func reset() -> void:
		frequency.clear()
		trace.clear()
		height_trace.clear()


func run(runner: Object) -> void:
	_budget_and_geometry(runner)
	_fresh_searches(runner)
	_invalid_callables(runner)
	_stateful_default(runner)
	print("SCENARIO body-geometry reuse: exact bounded routes, stable per-search queries, changed geometry and original custom callbacks")


func _budget_and_geometry(runner: Object) -> void:
	var geometry := GeometrySpy.new()
	geometry.make_gate()
	var reference: Array[Vector2i] = SimBodyGeometry.find_path(START, GOAL, SIZE, geometry.walkable, geometry.elevation, RADIUS, FULL_BUDGET)
	runner.assert_eq(reference.size(), 15, "a three-cell body takes the shortest straight route through a three-cell opening")
	if reference.is_empty():
		return
	runner.assert_eq(reference.front(), START, "the route includes the original start")
	runner.assert_eq(reference.back(), GOAL, "the route reaches the actual goal")
	geometry.clear_trace()

	# Binary search finds the original BFS budget threshold without assuming how
	# many queued anchors are visited before the goal is popped.
	var low: int = 1
	var high: int = FULL_BUDGET
	while low < high:
		var middle: int = floori(float(low + high) / 2.0)
		var probe: Array[Vector2i] = SimBodyGeometry.find_path(START, GOAL, SIZE, geometry.walkable, geometry.elevation, RADIUS, middle)
		geometry.clear_trace()
		if probe.is_empty():
			low = middle + 1
		else:
			high = middle
	runner.assert_true(low > 1 and low < FULL_BUDGET, "the fixture exercises a real intermediate BFS budget threshold")
	for budget: int in [low - 1, low, low + 1, FULL_BUDGET]:
		var plain: Array[Vector2i] = SimBodyGeometry.find_path(START, GOAL, SIZE, geometry.walkable, geometry.elevation, RADIUS, budget)
		geometry.clear_trace()
		var reused: Array[Vector2i] = SimBodyGeometry.find_path(START, GOAL, SIZE, geometry.walkable, geometry.elevation, RADIUS, budget, true)
		geometry.clear_trace()
		runner.assert_eq(reused, plain, "reuse preserves the complete ordered route at budget %d" % budget)
		runner.assert_eq(plain.is_empty(), budget < low, "bounded search fails precisely below its original threshold")

	geometry.clear_trace()
	var uncached: Array[Vector2i] = SimBodyGeometry.find_path(START, GOAL, SIZE, geometry.walkable, geometry.elevation, RADIUS, FULL_BUDGET)
	var original_walk_calls: int = geometry.walk_trace.size()
	var original_height_calls: int = geometry.height_trace.size()
	geometry.clear_trace()
	var cached: Array[Vector2i] = SimBodyGeometry.find_path(START, GOAL, SIZE, geometry.walkable, geometry.elevation, RADIUS, FULL_BUDGET, true)
	runner.assert_eq(cached, uncached, "stable per-cell reuse retains the complete route")
	runner.assert_true(_unique(geometry.walk_trace), "stable walkability is queried at most once per cell in a search")
	runner.assert_true(_unique(geometry.height_trace), "stable height is queried at most once per cell in a search")
	runner.assert_true(geometry.walk_trace.size() < original_walk_calls, "the real multi-cell search eliminates repeated walkability queries")
	runner.assert_true(geometry.height_trace.size() < original_height_calls, "the real multi-cell search eliminates repeated elevation queries")


func _fresh_searches(runner: Object) -> void:
	var geometry := GeometrySpy.new()
	geometry.make_gate()
	var open: Array[Vector2i] = SimBodyGeometry.find_path(START, GOAL, SIZE, geometry.walkable, geometry.elevation, RADIUS, FULL_BUDGET, true)
	runner.assert_true(not open.is_empty(), "the original narrow opening is traversable")
	geometry.clear_trace()
	var gate := Vector2i(12, 10)
	geometry.walls[gate] = true
	_compare_closed(runner, geometry, "new wall closes the only opening")
	geometry.walls.erase(gate)
	var reopened: Array[Vector2i] = SimBodyGeometry.find_path(START, GOAL, SIZE, geometry.walkable, geometry.elevation, RADIUS, FULL_BUDGET, true)
	runner.assert_eq(reopened, open, "removing a wall affects the next search and restores the same route")
	geometry.clear_trace()
	geometry.terrain[gate] = true
	_compare_closed(runner, geometry, "new impassable terrain closes the only opening")
	geometry.terrain.erase(gate)
	for y: int in range(9, 12):
		geometry.heights[Vector2i(12, y)] = 3
	_compare_closed(runner, geometry, "a cliff in the opening prevents a body straddling the elevation change")
	geometry.heights.clear()
	var leveled: Array[Vector2i] = SimBodyGeometry.find_path(START, GOAL, SIZE, geometry.walkable, geometry.elevation, RADIUS, FULL_BUDGET, true)
	runner.assert_eq(leveled, open, "a later search reads the leveled terrain afresh")


func _compare_closed(runner: Object, geometry: GeometrySpy, label: String) -> void:
	var plain: Array[Vector2i] = SimBodyGeometry.find_path(START, GOAL, SIZE, geometry.walkable, geometry.elevation, RADIUS, FULL_BUDGET)
	geometry.clear_trace()
	var reused: Array[Vector2i] = SimBodyGeometry.find_path(START, GOAL, SIZE, geometry.walkable, geometry.elevation, RADIUS, FULL_BUDGET, true)
	geometry.clear_trace()
	runner.assert_true(plain.is_empty(), label)
	runner.assert_eq(reused, plain, label + " with reused geometry")


func _invalid_callables(runner: Object) -> void:
	var geometry := GeometrySpy.new()
	var invalid := Callable()
	var no_walk: Array[Vector2i] = SimBodyGeometry.find_path(START, GOAL, SIZE, invalid, geometry.elevation, RADIUS, FULL_BUDGET, true)
	var no_height: Array[Vector2i] = SimBodyGeometry.find_path(START, GOAL, SIZE, geometry.walkable, invalid, RADIUS, FULL_BUDGET, true)
	runner.assert_true(no_walk.is_empty(), "an invalid walkability callback is rejected even when reuse is requested")
	runner.assert_true(no_height.is_empty(), "an invalid elevation callback is rejected even when reuse is requested")


func _stateful_default(runner: Object) -> void:
	var geometry := StatefulGeometry.new()
	var implicit: Array[Vector2i] = SimBodyGeometry.find_path(START, GOAL, SIZE, geometry.walkable, geometry.elevation, RADIUS, FULL_BUDGET)
	var implicit_walk: Array[Vector2i] = geometry.trace.duplicate()
	var implicit_height: Array[Vector2i] = geometry.height_trace.duplicate()
	geometry.reset()
	var explicit: Array[Vector2i] = SimBodyGeometry.find_path(START, GOAL, SIZE, geometry.walkable, geometry.elevation, RADIUS, FULL_BUDGET, false)
	runner.assert_true(not _unique(implicit_walk), "the default search actually revisits a stateful cell callback")
	runner.assert_eq(geometry.trace, implicit_walk, "the default preserves the custom walkability callback order and count")
	runner.assert_eq(geometry.height_trace, implicit_height, "the default preserves the custom elevation callback order and count")
	runner.assert_eq(explicit, implicit, "explicitly disabling reuse gives the same stateful result")


func _unique(trace: Array[Vector2i]) -> bool:
	var seen: Dictionary = {}
	for cell: Vector2i in trace:
		if seen.has(cell):
			return false
		seen[cell] = true
	return true
