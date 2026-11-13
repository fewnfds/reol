extends RefCounted
## A page owns its hot columns; only its assigned lane writes them during a step.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Equipment = preload("res://scripts/sim/kernel/equipment.gd")
const PAGE_SIZE: int = 256
const WALK_SPEED: float = Equipment.BASE.speed
const MAX_TOLERANCE: float = 100.0
const THERMAL_DAMAGE_PER_SECOND: float = 1.0
const TOLERANCE_REGEN_PER_SECOND: float = 1.0
enum Mode { RESOURCE, HARVEST, REST, MANUAL, IDLE, DEAD, APPROACH, ACTION, FREE, EXPLORE, COMBAT_MOVE }

const STATE_FIELDS: Array = ["ids", "positions", "targets", "modes", "health", "energy", "hunger", "body_heat",
	"exposure", "elements", "due_ms", "route_cursors", "routes", "source_ids", "tolerance", "thermal_carry",
	"flight", "radii", "moved_distance", "path_failures"]

var ids := PackedInt64Array()
var positions := PackedVector2Array()
var targets := PackedVector2Array()
var modes := PackedByteArray()
var flight := PackedByteArray()
var radii := PackedFloat32Array()
var health := PackedInt32Array()
var max_health := PackedInt32Array() # Derived stats, rebuilt rather than saved.
var melee_damage := PackedInt32Array()
var ranged_damage := PackedInt32Array()
var armor := PackedInt32Array()
var move_speed := PackedFloat32Array()
var tolerance := PackedFloat32Array()
var thermal_carry := PackedFloat32Array()
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
var routes: Array[PackedVector2Array] = []
var motion: Dictionary = {} # Sparse timed knots for this step, shared by collision/display.
var ready := PackedInt64Array() # local row, exact arrival/due time
var failures := PackedInt32Array()
var environmental_deaths := PackedInt32Array()
var environmental_events: Array[Dictionary] = []
var moved_distance: float = 0.0
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
	targets.append(Terrain.center(terrain.resources[source]))
	modes.append(Mode.RESOURCE)
	health.append(int(Equipment.BASE.max_hp))
	max_health.append(int(Equipment.BASE.max_hp))
	melee_damage.append(int(Equipment.BASE.melee))
	ranged_damage.append(int(Equipment.BASE.ranged))
	armor.append(int(Equipment.BASE.armor))
	move_speed.append(WALK_SPEED)
	tolerance.append(MAX_TOLERANCE)
	thermal_carry.append(0.0)
	flight.append(0)
	radii.append(0.35)
	energy.append(10000)
	hunger.append(10000)
	body_heat.append(22.0)
	potions.append(0)
	cargo.append(0)
	due_ms.append(0)
	route_cursors.append(0)
	routes.append(PackedVector2Array())
	exposure.resize(ids.size() * 7)
	elements.resize(ids.size() * 5)
	return row


func resize_stats() -> void:
	for field: String in ["max_health", "melee_damage", "ranged_damage", "armor", "move_speed"]:
		if get(field).size() != ids.size():
			var column: Variant = get(field)
			column.resize(ids.size())
			set(field, column)


func move_to(row: int, target: Vector2, mode: int) -> void:
	targets[row] = target
	modes[row] = mode
	routes[row] = PackedVector2Array()
	route_cursors[row] = 0


func advance(navigation: RefCounted) -> void:
	ready.clear()
	failures.clear()
	motion = {}
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
		var route: PackedVector2Array = routes[row]
		if route.is_empty():
			route = navigation.plan(positions[row], targets[row], radii[row], flight[row] > 0)
			routes[row] = route
			route_cursors[row] = 0
			if route.is_empty():
				if navigation.deferred: continue
				path_failures += 1
				failures.append(row)
				continue
		var point: Vector2 = positions[row]
		var speed: float = move_speed[row]
		var available: float = speed * 0.05
		var cursor: int = route_cursors[row]
		var knots := PackedVector3Array()
		while available > 0.00001 and cursor < route.size():
			var next: Vector2 = route[cursor]
			var distance: float = point.distance_to(next)
			if distance <= available:
				point = next
				available -= distance
				cursor += 1
				if available > 0.00001 and distance > 0.00001:
					knots.append(Vector3(point.x, point.y, 1.0 - available / (speed * 0.05)))
			else:
				point = point.move_toward(next, available)
				available = 0.0
		if not knots.is_empty():
			var path := PackedVector3Array([Vector3(positions[row].x, positions[row].y, 0.0)])
			path.append_array(knots)
			path.append(Vector3(point.x, point.y, 1.0))
			motion[row] = path
		moved_distance += speed * 0.05 - available
		positions[row] = point
		route_cursors[row] = cursor
		if cursor >= route.size():
			ready.append(row)
			ready.append(end_ms - roundi(available / speed * 1000.0))


func sample_environment(seconds: float = 1.0) -> void:
	environmental_deaths.clear()
	environmental_events.clear()
	var alpha: float = 1.0 - exp(-seconds / 30.0)
	for row: int in positions.size():
		if modes[row] == Mode.DEAD or modes[row] == Mode.FREE:
			continue
		var tile: int = Terrain.index(Vector2i(positions[row]))
		environment.sample_raw(tile, exposure, row * 7)
		var ambient: float = environment.temperature_at(tile, exposure, row * 7)
		body_heat[row] = lerpf(body_heat[row], ambient, alpha)
		for channel: int in 5:
			elements[row * 5 + channel] = environment.element(tile, exposure, row * 7, channel)
		hunger[row] = maxi(0, hunger[row] - roundi(2 * seconds))
		energy[row] = maxi(0, energy[row] - roundi((3 + absf(body_heat[row] - 22.0)) * seconds))
		if seconds > 0.0 and (body_heat[row] > 80.0 or body_heat[row] < 0.0):
			var before: float = tolerance[row]
			var absorbed: float = minf(tolerance[row], seconds * THERMAL_DAMAGE_PER_SECOND)
			tolerance[row] = maxf(0.0, tolerance[row] - absorbed)
			var residual: float = maxf(0.0, seconds * THERMAL_DAMAGE_PER_SECOND - absorbed) + thermal_carry[row]
			var damage: int = mini(health[row], int(floor(residual + 0.000001)))
			thermal_carry[row] = maxf(0.0, residual - floor(residual + 0.000001))
			health[row] -= damage
			environmental_events.append({"kind": "thermal_hit", "actor": ids[row], "at_ms": end_ms,
				"cause": "cold" if body_heat[row] < 0.0 else "heat", "absorbed": absorbed, "damage": damage,
				"tolerance": tolerance[row], "hp": health[row], "temperature": body_heat[row]})
			if before > 0.0 and tolerance[row] <= 0.0:
				environmental_events.append({"kind": "tolerance_exhausted", "actor": ids[row], "at_ms": end_ms})
		elif seconds > 0.0 and body_heat[row] >= 5.0 and body_heat[row] <= 75.0 and ambient >= 0.0 and ambient <= 80.0:
			var before: float = tolerance[row]
			tolerance[row] = minf(MAX_TOLERANCE, before + seconds * TOLERANCE_REGEN_PER_SECOND)
			if before < MAX_TOLERANCE and tolerance[row] == MAX_TOLERANCE:
				environmental_events.append({"kind": "tolerance_restored", "actor": ids[row], "at_ms": end_ms})
		if health[row] <= 0:
			environmental_deaths.append(row)
