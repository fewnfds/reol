extends RefCounted
## A page owns its hot columns; only its assigned lane writes them during a step.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const PAGE_SIZE: int = 256
const WALK_SPEED: float = 5.0
enum Mode { RESOURCE, HARVEST, REST, MANUAL, IDLE, DEAD, APPROACH, ACTION, FREE, EXPLORE }

const STATE_FIELDS: Array = ["ids", "positions", "targets", "modes", "health", "energy", "hunger", "body_heat",
	"exposure", "elements", "due_ms", "route_cursors", "routes", "source_ids",
	"moved_distance", "path_requests", "path_failures"]

var ids := PackedInt64Array()
var positions := PackedVector2Array()
var targets := PackedInt32Array()
var modes := PackedByteArray()
var health := PackedInt32Array()
var energy := PackedInt32Array()
var hunger := PackedInt32Array()
var body_heat := PackedFloat32Array()
var exposure := PackedInt32Array()
var elements := PackedInt32Array()
var potions := PackedInt32Array()
var cargo := PackedInt32Array()
var source_ids := PackedInt32Array()
var due_ms := PackedInt64Array()
var route_cursors := PackedInt32Array()
var routes: Array[PackedInt32Array] = []
var ready := PackedInt64Array() # local row, exact arrival/due time
var failures := PackedInt32Array()
var environmental_deaths := PackedInt32Array()
var moved_distance: float = 0.0
var path_requests: int = 0
var path_failures: int = 0
var environment: RefCounted
var terrain: RefCounted
var end_ms: int


func initialize(first: int, count: int, ground: RefCounted) -> void:
	terrain = ground
	for row: int in count:
		var id: int = first + row
		var start: int = terrain.nearest_open(Terrain.index(Vector2i(171 + posmod(id * 7, 91), 171 + posmod(id * 13, 91))))
		add_row(id, start)
	if first == 1:
		modes[0] = Mode.IDLE


func add_row(id: int, tile: int) -> int:
	var row: int = ids.size()
	ids.append(id)
	positions.append(Terrain.center(tile))
	var source: int = posmod(id * 37, terrain.resources.size())
	source_ids.append(source)
	targets.append(terrain.resources[source])
	modes.append(Mode.RESOURCE)
	health.append(100)
	energy.append(10000)
	hunger.append(10000)
	body_heat.append(22.0)
	potions.append(0)
	cargo.append(0)
	due_ms.append(0)
	route_cursors.append(0)
	routes.append(PackedInt32Array())
	exposure.resize(ids.size() * 7)
	elements.resize(ids.size() * 5)
	return row


func move_to(row: int, target: int, mode: int) -> void:
	targets[row] = target
	modes[row] = mode
	routes[row] = PackedInt32Array()
	route_cursors[row] = 0


func advance(graph: AStarGrid2D, path_cache: Dictionary) -> void:
	ready.clear()
	failures.clear()
	for row: int in positions.size():
		var mode: int = modes[row]
		if mode == Mode.DEAD or mode == Mode.FREE:
			continue
		if mode == Mode.HARVEST or mode == Mode.REST or mode == Mode.ACTION:
			if due_ms[row] <= end_ms:
				ready.append(row)
				ready.append(due_ms[row])
			continue
		if mode == Mode.IDLE:
			continue
		var route: PackedInt32Array = routes[row]
		if route.is_empty():
			var start: int = Terrain.index(Vector2i(positions[row]))
			var key: int = start + targets[row] * Terrain.SIZE * Terrain.SIZE
			if path_cache.has(key):
				route = path_cache[key]
			else:
				path_requests += 1
				route = PackedInt32Array() # A cached empty route is also immutable.
				for tile: Vector2i in graph.get_id_path(Terrain.cell(start), Terrain.cell(targets[row])):
					route.append(Terrain.index(tile))
				if path_cache.size() >= 4096:
					path_cache.clear()
				path_cache[key] = route
			routes[row] = route
			route_cursors[row] = 0
			if route.size() > 1:
				var first: Vector2 = Terrain.center(route[0])
				var direction: Vector2 = Terrain.center(route[1]) - first
				var offset: Vector2 = positions[row] - first
				if is_zero_approx(offset.cross(direction)) and offset.dot(direction) > 0.0:
					route_cursors[row] = 1
			if route.is_empty():
				path_failures += 1
				failures.append(row)
				continue
		var point: Vector2 = positions[row]
		var available: float = WALK_SPEED * 0.05
		var cursor: int = route_cursors[row]
		while available > 0.00001 and cursor < route.size():
			var next: Vector2 = Terrain.center(route[cursor])
			var distance: float = point.distance_to(next)
			if distance <= available:
				point = next
				available -= distance
				cursor += 1
			else:
				point = point.move_toward(next, available)
				available = 0.0
		moved_distance += positions[row].distance_to(point)
		positions[row] = point
		route_cursors[row] = cursor
		if cursor >= route.size():
			ready.append(row)
			ready.append(end_ms - roundi(available / WALK_SPEED * 1000.0))


func sample_environment(seconds: float = 1.0) -> void:
	environmental_deaths.clear()
	var alpha: float = 1.0 - exp(-seconds / 30.0)
	for row: int in positions.size():
		if modes[row] == Mode.DEAD or modes[row] == Mode.FREE:
			continue
		var tile: int = Terrain.index(Vector2i(positions[row]))
		environment.sample_raw(tile, exposure, row * 7)
		body_heat[row] = lerpf(body_heat[row], environment.temperature_at(tile, exposure, row * 7), alpha)
		for channel: int in 5:
			elements[row * 5 + channel] = environment.element(tile, exposure, row * 7, channel)
		hunger[row] = maxi(0, hunger[row] - roundi(2 * seconds))
		energy[row] = maxi(0, energy[row] - roundi((3 + absf(body_heat[row] - 22.0)) * seconds))
		if seconds > 0.0 and (body_heat[row] > 80.0 or body_heat[row] < 0.0):
			health[row] = maxi(0, health[row] - 1)
		if health[row] <= 0:
			environmental_deaths.append(row)
