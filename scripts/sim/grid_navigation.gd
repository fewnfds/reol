class_name SimGridNavigation
extends RefCounted
## Native AStar2D searches a reusable, relative grid. Only geometry is cached;
## every edge reads the current owner's clearance. No bodies or paths live here.

static var _graphs: Dictionary = {}
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP,
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]


class Search extends AStar2D:
	var radius: int
	var width: int
	var origin: Vector2i
	var step: Callable
	var stand: Callable
	var budget: int
	var visited: Dictionary = {}
	var exhausted: bool = false
	var busy: bool = false

	func _init(extent: int, diagonal: bool) -> void:
		radius = extent
		width = extent * 2 + 1
		neighbor_filter_enabled = true
		reserve_space(width * width)
		for y: int in width:
			for x: int in width:
				add_point(y * width + x, Vector2(x, y))
		for y: int in width:
			for x: int in width:
				var cell := Vector2i(x, y)
				for direction: Vector2i in SimGridNavigation.DIRECTIONS.slice(0, 8 if diagonal else 4):
					var next: Vector2i = cell + direction
					if next.x >= 0 and next.y >= 0 and next.x < width and next.y < width:
						var id: int = next.y * width + next.x
						if id > y * width + x:
							connect_points(y * width + x, id)

	func cell(id: int) -> Vector2i:
		@warning_ignore("integer_division")
		return origin + Vector2i(id % width - radius, id / width - radius)

	func _filter_neighbor(from_id: int, neighbor_id: int) -> bool:
		if not visited.has(from_id):
			if visited.size() >= budget:
				exhausted = true
				return true
			visited[from_id] = true
		if exhausted:
			return true
		var from: Vector2i = cell(from_id)
		var to: Vector2i = cell(neighbor_id)
		return not bool(stand.call(to)) or not bool(step.call(from, to - from))


static func find_path(from: Vector2i, to: Vector2i, stand: Callable, step: Callable, radius: int, budget: int, diagonal: bool = true) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if radius < 0 or radius > 64 or budget < 1 or not stand.is_valid() or not step.is_valid() or maxi(absi(to.x - from.x), absi(to.y - from.y)) > radius:
		return result
	if not bool(stand.call(from)) or not bool(stand.call(to)):
		return result
	if from == to:
		result.append(from)
		return result
	var key: String = "%d:%s" % [radius, diagonal]
	# Calls are synchronous. A callback reentering navigation gets an isolated
	# native search, rather than replacing the outer search's filter context.
	var graph: Search = _graphs.get(key)
	if graph == null or graph.busy:
		graph = Search.new(radius, diagonal)
		if not _graphs.has(key):
			_graphs[key] = graph
	graph.busy = true
	graph.origin = from
	graph.stand = stand
	graph.step = step
	graph.budget = budget
	graph.exhausted = false
	graph.visited.clear()
	var start: int = radius * graph.width + radius
	var delta: Vector2i = to - from
	var target: int = (delta.y + radius) * graph.width + delta.x + radius
	var path: PackedInt64Array = graph.get_id_path(start, target)
	if not graph.exhausted and graph.visited.size() < budget:
		for id: int in path:
			result.append(graph.cell(id))
	# Do not retain scene instances, an old session or geometry Callables.
	graph.stand = Callable()
	graph.step = Callable()
	graph.visited.clear()
	graph.busy = false
	return result
