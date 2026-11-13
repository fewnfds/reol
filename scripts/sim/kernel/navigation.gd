extends RefCounted
## Lane-private native searches. Routes contain continuous points; terrain stays tiled.
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const LOOKAHEAD: int = 32
const PLANS_PER_STEP: int = 32 # Geometry/endpoint preparation also costs CPU on cache hits.
const SEARCHES_PER_STEP: int = 8 # Count budget; individual native searches are still measured.
var terrain: RefCounted
var graph: AStarGrid2D
var large_graph: AStarGrid2D
var paths: Dictionary = {} # Immutable node corridors, never a body's endpoints.
var searches: int = 0
var cache_hits: int = 0
var direct: int = 0
var geometry_usec: int = 0
var search_usec: int = 0
var deferred: bool = false
var remaining: int = SEARCHES_PER_STEP
var preparations: int = PLANS_PER_STEP
var waits: int = 0
var islands: Array[Dictionary] = [{}, {}] # Only fully visited components, version-scoped.
var next_island: int = 1


func _init(ground: RefCounted = null) -> void:
	terrain = ground
	if terrain != null:
		graph = _graph(false)


func _graph(large: bool) -> AStarGrid2D:
	var result := AStarGrid2D.new()
	result.region = Rect2i(0, 0, Terrain.SIZE, Terrain.SIZE)
	result.offset = Vector2.ZERO if large else Vector2(0.5, 0.5)
	result.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	result.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	result.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	result.update()
	if large:
		result.fill_solid_region(Rect2i(0, 0, Terrain.SIZE, 1))
		result.fill_solid_region(Rect2i(0, 0, 1, Terrain.SIZE))
	for tile: int in terrain.structures:
		if terrain.blocked[tile] != 0:
			if large:
				result.fill_solid_region(Rect2i(Terrain.cell(tile), Vector2i(2, 2)))
			else:
				result.set_point_solid(Terrain.cell(tile))
	return result


func begin_step() -> void:
	remaining = SEARCHES_PER_STEP
	preparations = PLANS_PER_STEP


func changed(tiles: PackedInt32Array) -> void:
	paths.clear()
	islands = [{}, {}]
	for tile: int in tiles:
		graph.set_point_solid(Terrain.cell(tile), terrain.blocked[tile] != 0)
		if large_graph == null:
			continue
		for y: int in 2:
			for x: int in 2:
				var node: Vector2i = Terrain.cell(tile) + Vector2i(x, y)
				if large_graph.is_in_boundsv(node):
					large_graph.set_point_solid(node, not terrain.can_stand(Vector2(node), 0.9))


func _anchor(point: Vector2, radius: float, native: AStarGrid2D) -> Vector2i:
	var base := Vector2i((point - native.offset).round())
	var candidates: Array[Vector2i] = []
	for y: int in range(-1, 2):
		for x: int in range(-1, 2):
			var node := base + Vector2i(x, y)
			if native.is_in_boundsv(node) and not native.is_point_solid(node):
				candidates.append(node)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i): return (Vector2(a) + native.offset).distance_squared_to(point) < (Vector2(b) + native.offset).distance_squared_to(point))
	for node: Vector2i in candidates:
		if terrain.segment_clear(point, Vector2(node) + native.offset, radius):
			return node
	return Vector2i(-1, -1)


func plan(from: Vector2, goal: Vector2, radius: float, flying: bool = false) -> PackedVector2Array:
	deferred = false
	if preparations <= 0:
		deferred = true
		waits += 1
		return PackedVector2Array()
	preparations -= 1
	var started: int = Time.get_ticks_usec()
	if terrain.segment_clear(from, goal, radius, flying):
		direct += 1
		geometry_usec += Time.get_ticks_usec() - started
		return PackedVector2Array([goal])
	if flying or not terrain.can_stand(from, radius) or not terrain.can_stand(goal, radius):
		geometry_usec += Time.get_ticks_usec() - started
		return PackedVector2Array()
	if radius > 0.5 and large_graph == null:
		large_graph = _graph(true)
	var native: AStarGrid2D = large_graph if radius > 0.5 else graph
	var a := _anchor(from, radius, native)
	var b := _anchor(goal, radius, native)
	geometry_usec += Time.get_ticks_usec() - started
	if a.x < 0 or b.x < 0:
		return PackedVector2Array()
	var labels: Dictionary = islands[int(radius > 0.5)]
	if (labels.has(a) or labels.has(b)) and labels.get(a, 0) != labels.get(b, 0):
		return PackedVector2Array()
	var key: int = Terrain.index(a) + Terrain.index(b) * 262144 + int(radius > 0.5) * 68719476736
	var corridor := PackedVector2Array()
	if paths.has(key):
		corridor = paths[key]
		cache_hits += 1
	else:
		if remaining <= 0:
			deferred = true
			waits += 1
			return PackedVector2Array()
		remaining -= 1
		started = Time.get_ticks_usec()
		# Small enclosed destinations fail cheaply from the destination side.
		corridor = native.get_point_path(b, a)
		corridor.reverse()
		search_usec += Time.get_ticks_usec() - started
		searches += 1
		if paths.size() >= 4096:
			paths.clear()
		paths[key] = corridor
	if corridor.is_empty():
		started = Time.get_ticks_usec()
		_label_island(a, native, labels)
		_label_island(b, native, labels)
		geometry_usec += Time.get_ticks_usec() - started
		return PackedVector2Array()
	started = Time.get_ticks_usec()
	var points := PackedVector2Array([from])
	points.append_array(corridor)
	points.append(goal)
	var route := PackedVector2Array()
	var cursor: int = 0
	while cursor < points.size() - 1:
		var ahead: int = mini(LOOKAHEAD, points.size() - cursor - 1)
		while ahead > 1 and not terrain.segment_clear(points[cursor], points[cursor + ahead], radius):
			ahead = maxi(1, ahead / 2)
		var next: Vector2 = points[cursor + ahead]
		if ahead == 1 and not terrain.segment_clear(points[cursor], next, radius):
			route.clear()
			break
		if not next.is_equal_approx(points[cursor]):
			route.append(next)
		cursor += ahead
	geometry_usec += Time.get_ticks_usec() - started
	return route


func _label_island(start: Vector2i, native: AStarGrid2D, labels: Dictionary) -> void:
	if labels.has(start): return
	# Classify small closed pockets only after a failed search. A bounded,
	# incomplete visit never becomes evidence that another point is unreachable.
	var visited: Dictionary = {start: true}
	var pending: Array[Vector2i] = [start]
	var cursor: int = 0
	while cursor < pending.size():
		var point: Vector2i = pending[cursor]
		cursor += 1
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := point + offset
			if not visited.has(next) and native.is_in_boundsv(next) and not native.is_point_solid(next):
				visited[next] = true
				pending.append(next)
				if pending.size() > 128: return
	# Four-connected components equal eight-connected components when diagonal
	# movement requires both orthogonal neighbours to be open.
	for point: Vector2i in visited: labels[point] = next_island
	next_island += 1
