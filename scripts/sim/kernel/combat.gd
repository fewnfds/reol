extends RefCounted
## Active combat only. The world owns effects; Godot supplies geometric queries.
## Impacts and strikes commit at a 50ms boundary, never by worker finish order.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const STATE_FIELDS: Array = ["orders", "bolts", "next_bolt", "shots", "hits", "resumed"]
var orders: Dictionary = {}
var bolts: Dictionary = {}
var next_bolt: int = 1
var shots: int = 0
var hits: int = 0
var resumed: int = 0
var repaths: int = 0
var queries: int = 0
var work_usec: int = 0
var buckets: Dictionary = {}
var previous: Array[PackedVector2Array] = []


func before_motion(world: RefCounted) -> void:
	previous.clear()
	if bolts.is_empty():
		return
	for page: RefCounted in world.pages:
		previous.append(page.positions.duplicate())


func position(world: RefCounted, id: int) -> Vector2:
	if world.actor_slots.has(id):
		var slot: int = world.actor_slots[id]
		return world.pages[slot / 256].positions[slot % 256]
	return Terrain.center(int(world.objects.records.get(id, {}).get("tile", -1)))


func alive(world: RefCounted, id: int) -> bool:
	if not world.objects.records.has(id):
		return false
	if world.actor_slots.has(id):
		var slot: int = world.actor_slots[id]
		return world.pages[slot / 256].health[slot % 256] > 0
	return int(world.objects.records[id].get("hp", 0)) > 0


func begin(world: RefCounted, actor: int, kind: String, target: int = 0, destination: int = -1, ranged: bool = false) -> String:
	if target > 0 and (target == actor or not alive(world, target)):
		return "invalid_target"
	var automatic: bool = world.objects.records[actor].get("autonomous", false)
	world.release(actor)
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	page.modes[slot % 256] = Units.Mode.IDLE
	orders[actor] = {"kind": kind, "target": target, "destination": destination, "anchor": position(world, actor),
		"ranged": ranged, "scan_ms": world.elapsed_ms, "repath_ms": 0,
		"resume": automatic, "last_tile": -1}
	return "accepted"


func finish(world: RefCounted, actor: int, at: int) -> void:
	var resume: bool = orders.get(actor, {}).get("resume", false)
	orders.erase(actor)
	if world.actor_slots.has(actor):
		var slot: int = world.actor_slots[actor]
		world.pages[slot / 256].modes[slot % 256] = Units.Mode.IDLE
		if resume and alive(world, actor):
			resumed += 1
			world.livelihood.after_action(world, actor, at)


func _bucket(point: Vector2) -> Vector2i:
	return Vector2i((point / 8.0).floor())


func _index(world: RefCounted) -> void:
	buckets.clear()
	for page: RefCounted in world.pages:
		for row: int in page.ids.size():
			if page.ids[row] <= 0 or page.health[row] <= 0:
				continue
			var key: Vector2i = _bucket(page.positions[row])
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(page.ids[row])


func candidates(low: Vector2, high: Vector2) -> Array[int]:
	queries += 1
	var result: Array[int] = []
	var first: Vector2i = _bucket(low)
	var last: Vector2i = _bucket(high)
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			result.append_array(buckets.get(Vector2i(x, y), []))
	return result


func _seek(world: RefCounted, actor: int, radius: float) -> int:
	var origin: Vector2 = position(world, actor)
	var side: int = int(world.objects.records[actor].get("side", 0))
	var best: float = radius * radius
	var chosen: int = 0
	for target: int in candidates(origin - Vector2.ONE * radius, origin + Vector2.ONE * radius):
		if target == actor or int(world.objects.records[target].get("side", 0)) == side:
			continue
		var distance: float = origin.distance_squared_to(position(world, target))
		if distance < best and wall_fraction(world, origin, position(world, target)) < 0:
			best = distance
			chosen = target
	return chosen


func step(world: RefCounted, now: int) -> void:
	if orders.is_empty() and bolts.is_empty():
		return
	var started: int = Time.get_ticks_usec()
	_index(world)
	var impacts: Array[Dictionary] = []
	for bolt_id: int in bolts.keys():
		var bolt: Dictionary = bolts[bolt_id]
		var from: Vector2 = bolt.position
		var to: Vector2 = from + Vector2(bolt.velocity) * 0.05
		var first: float = wall_fraction(world, from, to)
		var hit: int = 0
		for target: int in candidates(from.min(to) - Vector2.ONE * 1.5, from.max(to) + Vector2.ONE * 1.5):
			if target == bolt.actor:
				continue
			var slot: int = world.actor_slots[target]
			var current: Vector2 = position(world, target)
			var before: Vector2 = previous[slot / 256][slot % 256] if not previous.is_empty() else current
			var radius: float = world.pages[slot / 256].radii[slot % 256] + 0.08
			var fraction: float = 0.0 if (from - before).length_squared() <= radius * radius else Geometry2D.segment_intersects_circle(from - before, to - current, Vector2.ZERO, radius)
			if fraction >= 0 and (first < 0 or fraction < first):
				first = fraction
				hit = target
		if first >= 0:
			if hit == 0:
				var tile: int = Terrain.index(Vector2i(from.lerp(to, minf(1.0, first + 0.001))))
				for object: int in world.objects.by_tile.get(tile, []):
					if world.objects.records[object].kind in ["wall", "door"]:
						hit = object
						break
			if hit > 0:
				impacts.append({"actor": bolt.actor, "target": hit, "damage": bolt.damage, "order": bolt_id})
			bolts.erase(bolt_id)
		elif now >= int(bolt.expire_ms):
			bolts.erase(bolt_id)
		else:
			bolt.position = to
	for actor: int in orders.keys():
		if not alive(world, actor):
			orders.erase(actor)
			continue
		var order: Dictionary = orders[actor]
		var origin: Vector2 = position(world, actor)
		var range_cells: float = 9.0 if order.ranged else 1.7
		if order.target > 0 and not alive(world, order.target):
			if order.kind == "pursue":
				finish(world, actor, now)
				continue
			order.target = 0
		if order.target == 0 and now >= int(order.scan_ms):
			order.target = _seek(world, actor, range_cells if order.kind == "hold" else 12.0)
			order.scan_ms = now + 200 + (actor % 4) * 50
		var slot: int = world.actor_slots[actor]
		var page: RefCounted = world.pages[slot / 256]
		var row: int = slot % 256
		if order.target == 0:
			if order.destination >= 0:
				if origin.distance_to(Terrain.center(order.destination)) < 0.4:
					finish(world, actor, now)
				elif page.modes[row] != Units.Mode.COMBAT_MOVE:
					page.move_to(row, order.destination, Units.Mode.COMBAT_MOVE)
			continue
		var target_position: Vector2 = position(world, order.target)
		var ignored := PackedInt32Array()
		if not world.actor_slots.has(order.target):
			ignored = world.objects.records[order.target].get("cells", PackedInt32Array([world.objects.records[order.target].tile]))
			for tile: int in ignored:
				if origin.distance_squared_to(Terrain.center(tile)) < origin.distance_squared_to(target_position):
					target_position = Terrain.center(tile)
		if order.kind == "hold" and target_position.distance_squared_to(order.anchor) > 18.0 * 18.0:
			order.target = 0
			continue
		var visible: bool = wall_fraction(world, origin, target_position, ignored) < 0
		if origin.distance_to(target_position) <= range_cells + page.radii[row] - 0.35 and visible:
			page.modes[row] = Units.Mode.IDLE
			if now >= world.attack_due[slot]:
				world.attack_due[slot] = now + (900 if order.ranged else 600)
				if order.ranged:
					launch(actor, origin, target_position, now)
				else:
					impacts.append({"actor": actor, "target": order.target, "damage": 25, "order": 0})
		elif order.kind != "hold" and now >= int(order.repath_ms):
			var clearance: int = int(page.radii[row] > 0.5 and page.flight[row] == 0)
			var tile: int = world.terrain.nearest_open(Terrain.index(Vector2i(target_position)), clearance)
			if not world.actor_slots.has(order.target):
				tile = world.facilities.interaction_tile(world, order.target, origin)
				if tile >= 0 and clearance > 0:
					tile = world.terrain.nearest_open(tile, clearance)
			if tile >= 0 and (tile != order.last_tile or page.modes[row] != Units.Mode.COMBAT_MOVE):
				page.move_to(row, tile, Units.Mode.COMBAT_MOVE)
				order.last_tile = tile
				repaths += 1
			order.repath_ms = now + 300
	impacts.sort_custom(func(a: Dictionary, b: Dictionary): return a.actor < b.actor if a.actor != b.actor else a.order < b.order)
	for impact: Dictionary in impacts:
		damage(world, impact.actor, impact.target, impact.damage, now)
	work_usec += Time.get_ticks_usec() - started


func launch(actor: int, origin: Vector2, destination: Vector2, now: int) -> void:
	bolts[next_bolt] = {"actor": actor, "position": origin, "velocity": origin.direction_to(destination) * 22.0,
		"damage": 20, "expire_ms": now + 2000}
	next_bolt += 1
	shots += 1


func damage(world: RefCounted, actor: int, target: int, amount: int, now: int) -> void:
	if not alive(world, target):
		return
	hits += 1
	var rec: Dictionary = world.objects.records[target]
	if world.actor_slots.has(target):
		var slot: int = world.actor_slots[target]
		var page: RefCounted = world.pages[slot / 256]
		var row: int = slot % 256
		page.health[row] = maxi(0, page.health[row] - maxi(1, amount - int(rec.get("armor", 0))))
		world.attacks += 1
		if page.health[row] <= 0:
			world.kill(target, now)
		elif not orders.has(target) and alive(world, actor) and target != 1:
			begin(world, target, "pursue", actor)
	else:
		rec.hp = maxi(0, int(rec.hp) - maxi(1, amount - int(world.facilities.definitions.get(rec.definition, {}).get("armor", 0))))
		if rec.hp <= 0:
			world.facilities.demolish(world, target)
	world.outcomes.append({"kind": "hit", "actor": actor, "target": target, "damage": amount, "at_ms": now})


func wall_fraction(world: RefCounted, from: Vector2, to: Vector2, ignore: PackedInt32Array = PackedInt32Array()) -> float:
	var result: float = -1.0
	for tile: int in Terrain.trace_cells(from, to):
		if tile < 0 or tile >= world.terrain.blocked.size() or world.terrain.blocked[tile] == 0 or ignore.has(tile):
			continue
		var low: Vector2 = Vector2(Terrain.cell(tile))
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


func valid(world: RefCounted) -> bool:
	for id: Variant in orders:
		if not id is int or not world.actor_slots.has(id) or not orders[id] is Dictionary:
			return false
		var rec: Dictionary = orders[id]
		if not rec.get("target") is int or not rec.get("anchor") is Vector2 or not rec.anchor.is_finite() or not rec.get("kind") is String or rec.kind not in ["pursue", "hold", "attack_move"]:
			return false
	for id: Variant in bolts:
		if not id is int or not bolts[id] is Dictionary:
			return false
		var bolt: Dictionary = bolts[id]
		if not bolt.get("position") is Vector2 or not bolt.position.is_finite() or not bolt.get("velocity") is Vector2 or not bolt.velocity.is_finite() or not bolt.get("expire_ms") is int or not bolt.get("damage") is int or not bolt.get("actor") is int:
			return false
	return true
