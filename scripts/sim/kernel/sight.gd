extends RefCounted
## Shared, read-only geometry during queries. No player map or personal memory.
## Tile centres define sight; physical movement and weapon clearance are separate.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const DEFAULT_RANGE: float = 24.0
const PREPARED: int = 24 # Common-case table size, not a gameplay range limit.
const STRIDE: int = PREPARED * 2 + 1
var loss := PackedByteArray()
var revision: int = 0
var layout_seen: int = -1
var sync_usec: int = 0
var rebuilds: int = 0
var _rays: Array[PackedInt32Array] = []
var _distances := PackedFloat32Array()


func _init() -> void:
	loss.resize(Terrain.SIZE * Terrain.SIZE)
	_rays.resize((PREPARED + 1) * STRIDE)
	_distances.resize(_rays.size())
	for y: int in range(PREPARED + 1):
		for x: int in range(-PREPARED, PREPARED + 1):
			var key: int = y * STRIDE + x + PREPARED
			var offsets := PackedInt32Array()
			var length: int = maxi(absi(x), y)
			for step: int in range(1, length):
				offsets.append(floori(float(y * step) / length + 0.5) * Terrain.SIZE + floori(float(x * step) / length + 0.5))
			_rays[key] = offsets
			_distances[key] = sqrt(float(x * x + y * y))


func sync(world: RefCounted) -> void:
	if layout_seen == world.objects.layout_revision:
		return
	var started: int = Time.get_ticks_usec()
	var value := PackedByteArray()
	value.resize(loss.size())
	for rec: Dictionary in world.objects.records.values():
		if rec.tile < 0 or rec.kind == "blueprint":
			continue
		var cost: int = int(world.facilities.definitions.get(rec.definition, {}).get("perception_cost", 0))
		if rec.kind == "plant":
			cost = 2 if rec.definition == "old_tree" and rec.stage == 2 else 0
		if cost == 0:
			continue
		for tile: int in rec.get("cells", PackedInt32Array([rec.tile])):
			value[tile] = maxi(value[tile], cost)
	if value != loss:
		loss = value
		revision += 1
	layout_seen = world.objects.layout_revision
	rebuilds += 1
	sync_usec += Time.get_ticks_usec() - started


func range_for(world: RefCounted, actor: int) -> float:
	return float(world.objects.records.get(actor, {}).get("sight_range", 0.0))


func sees_tile(a: int, b: int, sight_range: float) -> bool:
	if sight_range <= 0 or a < 0 or b < 0 or a >= loss.size() or b >= loss.size():
		return false
	# Canonical direction preserves symmetry, including rounding at diagonals.
	var low: int = mini(a, b)
	var high: int = maxi(a, b)
	var dx: int = high % Terrain.SIZE - low % Terrain.SIZE
	var dy: int = high / Terrain.SIZE - low / Terrain.SIZE
	var distance_sq: int = dx * dx + dy * dy
	if distance_sq > sight_range * sight_range:
		return false
	if absi(dx) <= PREPARED and dy <= PREPARED:
		var key: int = dy * STRIDE + dx + PREPARED
		# Small epsilon compensates float32 distance-table rounding at the rim.
		var budget: float = sight_range - _distances[key] + 0.00001
		var amount: int = 0
		for offset: int in _rays[key]:
			amount += loss[low + offset]
			if amount > budget:
				return false
		return true
	# Rare long sight uses the same discrete line, without growing an O(R^3) table.
	var budget: float = sight_range - sqrt(float(distance_sq)) + 0.00001
	var amount: int = 0
	var length: int = maxi(absi(dx), dy)
	for step: int in range(1, length):
		var offset: int = floori(float(dy * step) / length + 0.5) * Terrain.SIZE + floori(float(dx * step) / length + 0.5)
		amount += loss[low + offset]
		if amount > budget:
			return false
	return true


func sees(origin: Vector2, tile: int, sight_range: float) -> bool:
	return sees_tile(Terrain.index(Vector2i(origin.floor())), tile, sight_range)


func sees_object(origin: Vector2, rec: Dictionary, sight_range: float) -> bool:
	if sees(origin, rec.tile, sight_range):
		return true
	for tile: int in rec.get("cells", PackedInt32Array()):
		if sees(origin, tile, sight_range):
			return true
	return false


func observed_position(world: RefCounted, observer: int, target: int) -> Variant:
	if not world.objects.records.has(target):
		return null
	var origin: Vector2 = world.combat.position(world, observer)
	var sight_range: float = range_for(world, observer)
	if world.actor_slots.has(target):
		var point: Vector2 = world.combat.position(world, target)
		return point if sees(origin, Terrain.index(Vector2i(point.floor())), sight_range) else null
	# A visible cell is a usable aim point; do not aim through an unseen footprint.
	var rec: Dictionary = world.objects.records[target]
	var best: float = INF
	var observed: Variant = null
	for tile: int in rec.get("cells", PackedInt32Array([rec.tile])):
		var point: Vector2 = Terrain.center(tile)
		if origin.distance_squared_to(point) < best and sees(origin, tile, sight_range):
			best = origin.distance_squared_to(point)
			observed = point
	return observed
