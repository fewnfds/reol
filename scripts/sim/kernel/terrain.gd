extends RefCounted
## Authoritative tile facts. Navigation contexts are private to execution lanes.

const SIZE: int = 512
const STATE_FIELDS: Array = ["blocked", "enclosures", "rooms", "structures", "base", "cover", "flooring", "room_cells", "resources", "depots", "revision", "source_cells", "source_channels"]
var blocked := PackedByteArray()
var enclosures := PackedByteArray() # Doors divide rooms but remain walkable.
var rooms := PackedInt32Array()
var structures := PackedInt32Array()
enum Substrate { SOIL = 1, SAND, WATER }
enum Cover { NONE, GRASS }
var base := PackedByteArray() # Soil/sand/water remains underneath surface coverings.
var cover := PackedByteArray() # Decorative groundcover; never an object or a growth loop.
var flooring := PackedByteArray() # 0 bare, 1 wood; object records own paid materials.
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
	base.resize(SIZE * SIZE)
	cover.resize(SIZE * SIZE)
	flooring.resize(SIZE * SIZE)
	for tile: int in base.size():
		var point: Vector2i = cell(tile)
		base[tile] = Substrate.SAND if region(tile) == 2 or Rect2i(166, 181, 8, 8).has_point(point) else (Substrate.WATER if Rect2i(169, 175, 6, 4).has_point(point) else Substrate.SOIL)
		cover[tile] = Cover.GRASS if base[tile] == Substrate.SOIL and region(tile) == 0 else Cover.NONE
	for room: int in room_count:
		var origin := Vector2i(180 + (room % 8) * 9, 180 + (room / 8) * 9)
		var members := PackedInt32Array()
		for y: int in 5:
			for x: int in 5:
				var cell: int = index(origin + Vector2i(x, y))
				structures.append(cell)
				# Floor extends under the wall/door, not just to its upper foot.
				base[cell] = Substrate.SOIL
				cover[cell] = Cover.NONE
				flooring[cell] = 1
				var edge: bool = x == 0 or x == 4 or y == 0 or y == 4
				blocked[cell] = int(edge and not (x == 2 and y == 4))
				enclosures[cell] = int(edge)
				if not edge:
					rooms[cell] = room
					members.append(cell)
		room_cells.append(members)
	for id: int in 8:
		depots.append(index(Vector2i(180 + (id % 4) * 25, 194 + (id / 4) * 45)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1747
	var used: Dictionary = {}
	while resources.size() < resource_count:
		var point := Vector2i(rng.randi_range(169, 259), rng.randi_range(169, 259))
		var tile: int = index(point)
		if wild_site(tile, ["soil"]) and not used.has(tile) and not depots.has(tile) and point not in [Vector2i(176,182), Vector2i(176,183), Vector2i(174,185), Vector2i(175,185), Vector2i(176,186), Vector2i(173,182)]:
			used[tile] = true
			resources.append(tile)


static func index(cell: Vector2i) -> int:
	return cell.y * SIZE + cell.x


static func cell(id: int) -> Vector2i:
	return Vector2i(id % SIZE, id / SIZE)


static func center(id: int) -> Vector2:
	return Vector2(cell(id)) + Vector2(0.5, 0.5)


static func trace_cells(from: Vector2, to: Vector2) -> PackedInt32Array:
	var tile := Vector2i(from.floor())
	var finish := Vector2i(to.floor())
	var result := PackedInt32Array()
	var delta: Vector2 = to - from
	var direction := Vector2i(signi(int(signf(delta.x))), signi(int(signf(delta.y))))
	var stride := Vector2(absf(1.0 / delta.x) if delta.x != 0 else INF, absf(1.0 / delta.y) if delta.y != 0 else INF)
	var next := Vector2((tile.x + (1 if direction.x > 0 else 0) - from.x) / delta.x if delta.x != 0 else INF,
		(tile.y + (1 if direction.y > 0 else 0) - from.y) / delta.y if delta.y != 0 else INF)
	while tile.x >= 0 and tile.y >= 0 and tile.x < SIZE and tile.y < SIZE:
		result.append(index(tile))
		if tile == finish:
			break
		if is_equal_approx(next.x, next.y):
			for side: Vector2i in [tile + Vector2i(direction.x, 0), tile + Vector2i(0, direction.y)]:
				if side.x >= 0 and side.y >= 0 and side.x < SIZE and side.y < SIZE:
					result.append(index(side))
			tile += direction
			next += stride
		elif next.x < next.y:
			tile.x += direction.x
			next.x += stride.x
		else:
			tile.y += direction.y
			next.y += stride.y
	return result


func nearest_open(id: int, clearance: int = 0) -> int:
	if id >= 0 and id < blocked.size() and fits(cell(id), clearance):
		return id
	var point: Vector2i = cell(clampi(id, 0, blocked.size() - 1))
	for radius: int in range(1, 9):
		for y: int in range(maxi(0, point.y - radius), mini(SIZE, point.y + radius + 1)):
			for x: int in range(maxi(0, point.x - radius), mini(SIZE, point.x + radius + 1)):
				var next: int = y * SIZE + x
				if fits(Vector2i(x, y), clearance):
					return next
	return -1


func fits(point: Vector2i, clearance: int) -> bool:
	for y: int in range(point.y - clearance, point.y + clearance + 1):
		for x: int in range(point.x - clearance, point.x + clearance + 1):
			if x < 0 or y < 0 or x >= SIZE or y >= SIZE or blocked[y * SIZE + x] != 0:
				return false
	return true


func substrate(tile: int) -> String:
	return ["", "soil", "sand", "water"][base[tile]] if tile >= 0 and tile < base.size() else ""


func wild_site(tile: int, allowed: Array) -> bool:
	return tile >= 0 and tile < base.size() and blocked[tile] == 0 and enclosures[tile] == 0 and rooms[tile] < 0 and flooring[tile] == 0 and allowed.has(substrate(tile))


func set_floor(tile: int, present: bool) -> void:
	if flooring[tile] == int(present):
		return
	flooring[tile] = int(present)
	if present:
		base[tile] = Substrate.SOIL
		cover[tile] = Cover.NONE
	revision += 1


func surface_at(tile: int) -> int:
	# One observed byte: base appearance, floor bit, decorative grass bit.
	var surface: int = int(base[tile])
	if surface == Substrate.SOIL and region(tile) == 1:
		surface = 4
	return surface | (8 if flooring[tile] != 0 else 0) | (16 if cover[tile] == Cover.GRASS and flooring[tile] == 0 else 0)


static func region(tile: int) -> int:
	var point: Vector2i = cell(tile)
	if Rect2i(300, 170, 80, 80).has_point(point):
		return 1
	if Rect2i(300, 290, 80, 80).has_point(point):
		return 2
	return 0


func moisture(tile: int) -> int:
	match substrate(tile):
		"water": return 100
		"sand": return 15
	return 55


func navigation(clearance: int = 0) -> AStarGrid2D:
	var graph := AStarGrid2D.new()
	graph.region = Rect2i(0, 0, SIZE, SIZE)
	graph.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	graph.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	graph.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	graph.update()
	for id: int in structures:
		if blocked[id] != 0:
			for y: int in range(-clearance, clearance + 1):
				for x: int in range(-clearance, clearance + 1):
					var point: Vector2i = cell(id) + Vector2i(x, y)
					if graph.is_in_boundsv(point):
						graph.set_point_solid(point)
	return graph


func detached() -> RefCounted:
	var value: RefCounted = get_script().new()
	value.blocked = blocked.duplicate()
	value.enclosures = enclosures.duplicate()
	value.rooms = rooms.duplicate()
	for room: PackedInt32Array in room_cells:
		value.room_cells.append(room.duplicate())
	value.structures = structures.duplicate()
	value.base = base.duplicate()
	value.cover = cover.duplicate()
	value.flooring = flooring.duplicate()
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


static func blocking_fraction(blocked: PackedByteArray, from: Vector2, to: Vector2, ignore: PackedInt32Array = PackedInt32Array()) -> float:
	var result: float = -1.0
	for tile: int in trace_cells(from, to):
		if tile < 0 or tile >= blocked.size() or blocked[tile] == 0 or ignore.has(tile):
			continue
		var low: Vector2 = Vector2(cell(tile))
		if Rect2(low, Vector2.ONE).has_point(from):
			return 0.0
		for edge: Array in [[low, low + Vector2.RIGHT], [low, low + Vector2.DOWN], [low + Vector2.ONE, low + Vector2.RIGHT], [low + Vector2.ONE, low + Vector2.DOWN]]:
			var crossing: Variant = Geometry2D.segment_intersects_segment(from, to, edge[0], edge[1])
			if crossing != null:
				var fraction: float = from.distance_to(crossing) / maxf(0.000001, from.distance_to(to))
				if result < 0 or fraction < result:
					result = fraction
		if result >= 0:
			return result
	return -1.0
