extends RefCounted
## Authoritative tile facts. Navigation contexts are private to execution lanes.

const SIZE: int = 512
var blocked := PackedByteArray()
var enclosures := PackedByteArray() # Doors divide rooms but remain walkable.
var rooms := PackedInt32Array()
var structures := PackedInt32Array()
var room_cells: Array[PackedInt32Array] = []
var resources := PackedInt32Array()
var depots := PackedInt32Array()
var revision: int = 1
var source_cells := PackedInt32Array()
var source_channels := PackedInt32Array()


func initialize(room_count: int = 50, resource_count: int = 200) -> void:
	blocked.resize(SIZE * SIZE)
	enclosures.resize(SIZE * SIZE)
	rooms.resize(SIZE * SIZE)
	rooms.fill(-1)
	for room: int in room_count:
		var origin := Vector2i(180 + (room % 8) * 9, 180 + (room / 8) * 9)
		var members := PackedInt32Array()
		for y: int in 5:
			for x: int in 5:
				var cell: int = index(origin + Vector2i(x, y))
				structures.append(cell)
				var edge: bool = x == 0 or x == 4 or y == 0 or y == 4
				blocked[cell] = int(edge and not (x == 2 and y == 4))
				enclosures[cell] = int(edge)
				if not edge:
					rooms[cell] = room
					members.append(cell)
		room_cells.append(members)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1747
	var used: Dictionary = {}
	while resources.size() < resource_count:
		var point := Vector2i(rng.randi_range(169, 259), rng.randi_range(169, 259))
		var tile: int = nearest_open(index(point))
		if not used.has(tile):
			used[tile] = true
			resources.append(tile)
	for id: int in 8:
		depots.append(index(Vector2i(177 + id * 11, 269)))


static func index(cell: Vector2i) -> int:
	return cell.y * SIZE + cell.x


static func cell(id: int) -> Vector2i:
	return Vector2i(id % SIZE, id / SIZE)


static func center(id: int) -> Vector2:
	return Vector2(cell(id)) + Vector2(0.5, 0.5)


func nearest_open(id: int) -> int:
	if id >= 0 and id < blocked.size() and blocked[id] == 0:
		return id
	var point: Vector2i = cell(clampi(id, 0, blocked.size() - 1))
	for radius: int in range(1, 9):
		for y: int in range(maxi(0, point.y - radius), mini(SIZE, point.y + radius + 1)):
			for x: int in range(maxi(0, point.x - radius), mini(SIZE, point.x + radius + 1)):
				var next: int = y * SIZE + x
				if blocked[next] == 0:
					return next
	return -1


func navigation() -> AStarGrid2D:
	var graph := AStarGrid2D.new()
	graph.region = Rect2i(0, 0, SIZE, SIZE)
	graph.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	graph.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	graph.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	graph.update()
	for id: int in structures:
		if blocked[id] != 0:
			graph.set_point_solid(cell(id))
	return graph


func detached() -> RefCounted:
	var value: RefCounted = get_script().new()
	value.blocked = blocked.duplicate()
	value.enclosures = enclosures.duplicate()
	value.rooms = rooms.duplicate()
	for room: PackedInt32Array in room_cells:
		value.room_cells.append(room.duplicate())
	value.structures = structures.duplicate()
	value.resources = resources.duplicate()
	value.depots = depots.duplicate()
	value.revision = revision
	value.source_cells = source_cells.duplicate()
	value.source_channels = source_channels.duplicate()
	return value


func change_structure(tile: int, kind: int) -> void:
	blocked[tile] = int(kind == 1)
	enclosures[tile] = int(kind == 1 or kind == 2)
	var existing: int = structures.find(tile)
	if kind == 0 and existing >= 0:
		structures.remove_at(existing)
	elif kind != 0 and existing < 0:
		structures.append(tile)
	rebuild_rooms()
	revision += 1


func rebuild_rooms() -> void:
	rooms.fill(-1)
	room_cells.clear()
	if structures.is_empty():
		return
	var low := Vector2i(SIZE - 1, SIZE - 1)
	var high := Vector2i.ZERO
	for tile: int in structures:
		low = low.min(cell(tile))
		high = high.max(cell(tile))
	low = (low - Vector2i.ONE).max(Vector2i.ZERO)
	high = (high + Vector2i.ONE).min(Vector2i(SIZE - 1, SIZE - 1))
	var seen := PackedByteArray()
	seen.resize(SIZE * SIZE)
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var start: int = y * SIZE + x
			if enclosures[start] != 0 or seen[start] != 0:
				continue
			var pending := PackedInt32Array([start])
			seen[start] = 1
			var cursor: int = 0
			var outside: bool = false
			while cursor < pending.size():
				var tile: int = pending[cursor]
				cursor += 1
				var point: Vector2i = cell(tile)
				if point.x == low.x or point.y == low.y or point.x == high.x or point.y == high.y:
					outside = true
				for delta: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var next: Vector2i = point + delta
					if next.x < low.x or next.y < low.y or next.x > high.x or next.y > high.y:
						continue
					var next_id: int = index(next)
					if seen[next_id] == 0 and enclosures[next_id] == 0:
						seen[next_id] = 1
						pending.append(next_id)
			if not outside:
				for tile: int in pending:
					rooms[tile] = room_cells.size()
				room_cells.append(pending)
