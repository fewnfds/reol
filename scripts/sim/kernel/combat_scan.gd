extends RefCounted
## One step's detached actor index and bounded perception batch. Workers read
## the same geometry/positions and own only their results; no World reference.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Batch = preload("res://scripts/sim/execution/batch_execution.gd")
const Equipment = preload("res://scripts/sim/kernel/equipment.gd")
const BUCKET: float = 8.0
const CHUNK_SIZE: int = 64
const PARALLEL_MIN: int = 128
const DISCOVERY_STEPS: int = 4 # 200 world ms, staggered over the 50ms base step.
const WIDTH: int = Terrain.SIZE / int(BUCKET)

class SideIndex extends RefCounted:
	var side: int
	var heads := PackedInt32Array()

	func _init(value: int) -> void:
		side = value
		heads.resize(WIDTH * WIDTH)
		heads.fill(-1)

class Chunk extends RefCounted:
	var data: RefCounted
	var sight: RefCounted
	var first: int
	var end: int
	var found := PackedInt32Array()
	var candidates: int = 0
	var queries: int = 0
	var thread_id: int = 0

	func run() -> void:
		thread_id = OS.get_thread_caller_id()
		found.resize(end - first)
		found.fill(-1)
		for index: int in range(first, end):
			var slot: int = data.watchers[index]
			var origin: Vector2 = data.positions[slot]
			var from: int = data.tiles[slot]
			var target: int = data.tracking[index]
			var radius: float = data.ranges[index]
			if target >= 0:
				queries += 1
				var visible: bool = sight.sees_tile(from, data.tiles[target], radius)
				if visible and data.stationary[index]:
					visible = origin.distance_squared_to(data.positions[target]) <= data.limits[index] * data.limits[index] and Terrain.blocking_fraction(data.blocked, origin, data.positions[target]) < 0
				if visible:
					found[index - first] = target
				continue
			var limit: float = minf(radius, data.limits[index])
			if limit <= 0:
				continue
			var low: Vector2i = data.bucket(origin - Vector2.ONE * limit)
			var high: Vector2i = data.bucket(origin + Vector2.ONE * limit)
			var side: int = data.sides[slot]
			var best: float = limit * limit
			var chosen: int = -1
			var excluded: Dictionary = data.exclusions[index]
			var excluding: bool = not excluded.is_empty()
			for group: RefCounted in data.groups:
				if group.side == side:
					continue
				for y: int in range(maxi(0, low.y), mini(WIDTH - 1, high.y) + 1):
					for x: int in range(maxi(0, low.x), mini(WIDTH - 1, high.x) + 1):
						var other: int = group.heads[y * WIDTH + x]
						while other >= 0:
							candidates += 1
							if excluding and excluded.get(data.ids[other], -1) == data.tiles[other]:
								other = data.links[other]
								continue
							var distance: float = origin.distance_squared_to(data.positions[other])
							if distance <= best:
								queries += 1
								var visible: bool = sight.sees_tile(from, data.tiles[other], radius)
								if visible and data.stationary[index]:
									visible = Terrain.blocking_fraction(data.blocked, origin, data.positions[other]) < 0
								if visible and (distance < best or chosen < 0 or data.ids[other] < data.ids[chosen]):
									best = distance
									chosen = other
							other = data.links[other]
			found[index - first] = chosen

var positions := PackedVector2Array()
var ids := PackedInt64Array()
var sides := PackedInt32Array()
var tiles := PackedInt32Array()
var side_groups: Dictionary = {} # Side -> dense bucket heads; allies skip as a group.
var groups: Array[RefCounted] = [] # Stable iteration view shared by query workers.
var links := PackedInt32Array()
var blocked := PackedByteArray() # Stable until the owner joins this batch.
var sides_present: Dictionary = {}
var watchers := PackedInt32Array()
var tracking := PackedInt32Array()
var ranges := PackedFloat32Array()
var limits := PackedFloat32Array()
var stationary := PackedByteArray()
var exclusions: Array[Dictionary] = []
var _empty_exclusion: Dictionary = {}
var contacts: Dictionary = {} # Observer identity -> observed target slot.
var candidates: int = 0
var queries: int = 0
var index_usec: int = 0
var batch_usec: int = 0
var parallel_batches: int = 0
var observer_count: int = 0
var thread_ids: Dictionary = {}


func bucket(point: Vector2) -> Vector2i:
	return Vector2i((point / BUCKET).floor())


func index(world: RefCounted) -> void:
	var started: int = Time.get_ticks_usec()
	positions.clear()
	ids.clear()
	for group: RefCounted in side_groups.values():
		group.heads.fill(-1)
	sides_present.clear()
	for page: RefCounted in world.pages:
		positions.append_array(page.positions)
		ids.append_array(page.ids)
	sides.resize(ids.size())
	tiles.resize(ids.size())
	links.resize(ids.size())
	blocked = world.terrain.blocked
	var base: int = 0
	for page: RefCounted in world.pages:
		for row: int in page.ids.size():
			var slot: int = base + row
			var id: int = ids[slot]
			if id <= 0 or page.health[row] <= 0:
				ids[slot] = 0
				continue
			var side: int = int(world.objects.records[id].get("side", 0))
			sides[slot] = side
			sides_present[side] = true
			tiles[slot] = Terrain.index(Vector2i(positions[slot].floor()))
			var key: Vector2i = bucket(positions[slot])
			if not side_groups.has(side):
				side_groups[side] = SideIndex.new(side)
			var group: RefCounted = side_groups[side]
			var cell: int = key.y * WIDTH + key.x
			links[slot] = group.heads[cell]
			group.heads[cell] = slot
		base += page.ids.size()
	groups.assign(side_groups.values())
	index_usec += Time.get_ticks_usec() - started


func nearby(low: Vector2, high: Vector2) -> Array[int]:
	var result: Array[int] = []
	var first: Vector2i = bucket(low)
	var last: Vector2i = bucket(high)
	for group: RefCounted in groups:
		for y: int in range(maxi(0, first.y), mini(WIDTH - 1, last.y) + 1):
			for x: int in range(maxi(0, first.x), mini(WIDTH - 1, last.x) + 1):
				var slot: int = group.heads[y * WIDTH + x]
				while slot >= 0:
					result.append(ids[slot])
					slot = links[slot]
	return result


func observe(world: RefCounted, orders: Dictionary, now: int, unreachable: Dictionary = {}) -> void:
	watchers.clear()
	tracking.clear()
	ranges.clear()
	limits.clear()
	stationary.clear()
	exclusions.clear()
	contacts.clear()
	var phase: int = (now / 50) % DISCOVERY_STEPS
	for slot: int in ids.size():
		var id: int = ids[slot]
		if id == 0:
			continue
		var order: Dictionary = orders.get(id, {})
		var target: int = -1
		var limit: float = 0.0
		var hold: bool = not order.is_empty() and order.kind == "hold"
		if hold:
			limit = Equipment.RANGED_RANGE if order.ranged else Equipment.MELEE_RANGE
		if not order.is_empty():
			if order.target > 0:
				# Static targets are checked by the owner through their footprint.
				if not world.actor_slots.has(order.target):
					continue
				target = world.actor_slots[order.target]
				if ids[target] == 0:
					continue
			elif now >= int(order.scan_ms):
				limit = (Equipment.RANGED_RANGE if order.ranged else Equipment.MELEE_RANGE) if order.kind == "hold" else float(world.objects.records[id].get("alert_range", 12.0))
				order.scan_ms = now + DISCOVERY_STEPS * 50
			else:
				continue
		elif sides_present.size() > 1 and slot % DISCOVERY_STEPS == phase and id != 1 and world.objects.records[id].get("autonomous", false) and now >= int(world.objects.records[id].get("threat_scan_after", 0)):
			limit = float(world.objects.records[id].get("alert_range", 12.0))
		else:
			continue
		watchers.append(slot)
		tracking.append(target)
		ranges.append(world.sight.range_for(world, id))
		limits.append(limit)
		stationary.append(int(hold))
		var memory: Dictionary = unreachable.get(id, {})
		var page: RefCounted = world.pages[slot / 256]
		if target < 0 and memory.get("topology", -1) == world.terrain.revision and memory.get("flight", -1) == page.flight[slot % 256] and memory.get("large") == (page.radii[slot % 256] > 0.5):
			exclusions.append(memory.targets) # Owner does not mutate clues until join.
		else:
			exclusions.append(_empty_exclusion)
	if watchers.is_empty():
		return
	var started: int = Time.get_ticks_usec()
	var chunks: Array[RefCounted] = []
	for first: int in range(0, watchers.size(), CHUNK_SIZE):
		var chunk := Chunk.new()
		chunk.data = self
		chunk.sight = world.sight
		chunk.first = first
		chunk.end = mini(watchers.size(), first + CHUNK_SIZE)
		chunks.append(chunk)
	var batch := Batch.new()
	batch.start(chunks, world.requested_workers if watchers.size() >= PARALLEL_MIN else 0)
	batch.finish(true)
	parallel_batches += int(batch.parallel)
	observer_count += watchers.size()
	for chunk: RefCounted in chunks:
		thread_ids[chunk.thread_id] = true
		candidates += chunk.candidates
		queries += chunk.queries
		for offset: int in chunk.found.size():
			if chunk.found[offset] >= 0:
				contacts[ids[watchers[chunk.first + offset]]] = chunk.found[offset]
	batch_usec += Time.get_ticks_usec() - started
