extends RefCounted
## Active combat and sparse threat discovery. World owns effects; Godot geometry.
## Impacts and strikes commit at a 50ms boundary, never by worker finish order.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const Scan = preload("res://scripts/sim/kernel/combat_scan.gd")
const CONTACT_MEMORY_MS: int = 5000
const STATE_FIELDS: Array = ["orders", "bolts", "next_bolt", "shots", "hits", "resumed", "unreachable"]
var orders: Dictionary = {}
var unreachable: Dictionary = {} # Failed target positions, scoped to navigation/capability.
var bolts: Dictionary = {}
var next_bolt: int = 1
var shots: int = 0
var hits: int = 0
var resumed: int = 0
var repaths: int = 0
var work_usec: int = 0
var scan := Scan.new()
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


func begin(world: RefCounted, actor: int, kind: String, target: int = 0, destination: int = -1, ranged: bool = false, at: int = -1) -> String:
	if not alive(world, actor) or (target > 0 and (target == actor or not alive(world, target))):
		return "invalid_target"
	world.sight.sync(world)
	var observed: Variant = world.sight.observed_position(world, actor, target) if target > 0 else null
	if target > 0 and observed == null:
		return "target_not_visible"
	var now: int = at if at >= 0 else world.elapsed_ms
	var automatic: bool = world.objects.records[actor].get("autonomous", false)
	world.release(actor, now)
	world.objects.records[actor]["ranged"] = ranged
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	page.modes[slot % 256] = Units.Mode.IDLE
	orders[actor] = {"kind": kind, "target": target, "destination": destination, "anchor": position(world, actor),
		"ranged": ranged, "scan_ms": now + (actor % Scan.DISCOVERY_STEPS) * 50, "repath_ms": 0,
		"resume": automatic, "last_tile": -1, "search_tile": -1,
		"last_seen_pos": observed if observed != null else Vector2(-1, -1), "last_seen_ms": now if observed != null else -1}
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


func step(world: RefCounted, now: int) -> void:
	var started: int = Time.get_ticks_usec()
	world.sight.sync(world)
	scan.index(world)
	scan.observe(world, orders, now, unreachable)
	for actor: int in scan.contacts:
		if not orders.has(actor) and actor != 1 and alive(world, actor) and world.objects.records[actor].get("autonomous", false):
			begin(world, actor, "pursue", scan.ids[scan.contacts[actor]], -1, world.objects.records[actor].get("ranged", false), now)
	var impacts: Array[Dictionary] = []
	for bolt_id: int in bolts.keys():
		var bolt: Dictionary = bolts[bolt_id]
		var from: Vector2 = bolt.position
		var to: Vector2 = from + Vector2(bolt.velocity) * 0.05
		var first: float = Terrain.blocking_fraction(world.terrain.blocked, from, to)
		var hit: int = 0
		for target: int in scan.nearby(from.min(to) - Vector2.ONE * 1.5, from.max(to) + Vector2.ONE * 1.5):
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
				impacts.append({"actor": bolt.actor, "target": hit, "damage": bolt.damage, "order": bolt_id, "incoming": -Vector2(bolt.velocity).normalized()})
			bolts.erase(bolt_id)
		elif now >= int(bolt.expire_ms):
			bolts.erase(bolt_id)
		else:
			bolt.position = to
	for actor: int in orders.keys():
		if not orders.has(actor):
			continue
		if not alive(world, actor):
			orders.erase(actor)
			continue
		_advance_order(world, actor, now, impacts)
	impacts.sort_custom(func(a: Dictionary, b: Dictionary): return a.actor < b.actor if a.actor != b.actor else a.order < b.order)
	for impact: Dictionary in impacts:
		damage(world, impact.actor, impact.target, impact.damage, now, impact.get("incoming", Vector2.ZERO))
	work_usec += Time.get_ticks_usec() - started


func _advance_order(world: RefCounted, actor: int, now: int, impacts: Array[Dictionary]) -> void:
	var order: Dictionary = orders[actor]
	var origin: Vector2 = position(world, actor)
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	var observed: Variant = null
	if scan.contacts.has(actor):
		var target_slot: int = scan.contacts[actor]
		if order.target == 0 or order.target == scan.ids[target_slot]:
			order.target = scan.ids[target_slot]
			observed = scan.positions[target_slot]
	elif order.target > 0 and (not world.actor_slots.has(order.target) or not alive(world, order.target)):
		# A visible corpse may invalidate a contact. Hidden death/removal is not
		# a telepathic notification; the observer still follows its old clue.
		observed = world.sight.observed_position(world, actor, order.target)
	if order.target == 0:
		if order.destination >= 0:
			if origin.distance_to(Terrain.center(order.destination)) < 0.4:
				finish(world, actor, now)
			elif page.modes[row] != Units.Mode.COMBAT_MOVE:
				page.move_to(row, order.destination, Units.Mode.COMBAT_MOVE)
		return
	if observed != null:
		if not alive(world, order.target):
			_drop_contact(world, actor, now)
			return
		order.last_seen_pos = observed
		order.last_seen_ms = now
		order.search_tile = -1
	elif order.kind == "hold" or order.last_seen_ms < 0 or now - int(order.last_seen_ms) >= CONTACT_MEMORY_MS or origin.distance_to(order.last_seen_pos) < 0.6 or (order.search_tile >= 0 and origin.distance_to(Terrain.center(order.search_tile)) < 0.4):
		_drop_contact(world, actor, now)
		return
	var target_position: Vector2 = order.last_seen_pos
	var ignored := PackedInt32Array()
	if observed != null and not world.actor_slots.has(order.target):
		ignored = world.objects.records[order.target].get("cells", PackedInt32Array([world.objects.records[order.target].tile]))
	var range_cells: float = 9.0 if order.ranged else 1.7
	if observed != null and origin.distance_to(target_position) <= range_cells + page.radii[row] - 0.35 and Terrain.blocking_fraction(world.terrain.blocked, origin, target_position, ignored) < 0:
		page.modes[row] = Units.Mode.IDLE
		if now >= world.attack_due[slot]:
			world.attack_due[slot] = now + (900 if order.ranged else 600)
			if order.ranged:
				launch(actor, origin, target_position, now)
			else:
				impacts.append({"actor": actor, "target": order.target, "damage": 25, "order": 0, "incoming": (origin - target_position).normalized()})
	elif order.kind == "hold":
		_drop_contact(world, actor, now)
	elif now >= int(order.repath_ms):
		var clearance: int = int(page.radii[row] > 0.5 and page.flight[row] == 0)
		var tile: int = world.terrain.nearest_open(Terrain.index(Vector2i(target_position)), clearance)
		if observed != null and not world.actor_slots.has(order.target):
			tile = world.facilities.interaction_tile(world, order.target, origin)
			if tile >= 0 and clearance > 0:
				tile = world.terrain.nearest_open(tile, clearance)
		if tile < 0 or origin.distance_to(Terrain.center(tile)) < 0.4:
			blocked(world, actor, now)
			return
		if observed == null:
			order.search_tile = tile
		if tile != order.last_tile or page.modes[row] != Units.Mode.COMBAT_MOVE:
			page.move_to(row, tile, Units.Mode.COMBAT_MOVE)
			order.last_tile = tile
			repaths += 1
		order.repath_ms = now + 300


func _drop_contact(world: RefCounted, actor: int, now: int) -> void:
	var order: Dictionary = orders[actor]
	if order.kind == "pursue":
		finish(world, actor, now)
	else:
		order.target = 0
		order.last_tile = -1
		order.search_tile = -1
		order.scan_ms = now
		var slot: int = world.actor_slots[actor]
		world.pages[slot / 256].modes[slot % 256] = Units.Mode.IDLE


func blocked(world: RefCounted, actor: int, now: int) -> void:
	var order: Dictionary = orders[actor]
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	var memory: Dictionary = unreachable.get(actor, {})
	if memory.get("topology", -1) != world.terrain.revision or memory.get("flight", -1) != page.flight[row] or memory.get("large") != (page.radii[row] > 0.5):
		memory = {"topology": world.terrain.revision, "flight": page.flight[row], "large": page.radii[row] > 0.5, "targets": {}}
	if order.target > 0 and order.last_seen_ms >= 0:
		memory.targets[order.target] = Terrain.index(Vector2i(order.last_seen_pos))
	unreachable[actor] = memory
	world.objects.records[actor]["threat_scan_after"] = now + 2000
	_drop_contact(world, actor, now)


func launch(actor: int, origin: Vector2, destination: Vector2, now: int) -> void:
	bolts[next_bolt] = {"actor": actor, "position": origin, "velocity": origin.direction_to(destination) * 22.0,
		"damage": 20, "expire_ms": now + 2000}
	next_bolt += 1
	shots += 1


func damage(world: RefCounted, actor: int, target: int, amount: int, now: int, incoming: Vector2 = Vector2.ZERO) -> void:
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
		elif not orders.has(target) and target != 1:
			world.sight.sync(world)
			var ranged: bool = world.objects.records[target].get("ranged", false)
			if alive(world, actor) and world.sight.observed_position(world, target, actor) != null:
				begin(world, target, "pursue", actor, -1, ranged, now)
			elif not incoming.is_zero_approx():
				# The actual incoming trajectory is a direction clue, not the
				# hidden shooter's identity, current position or launch location.
				var hint: Vector2 = position(world, target) + incoming * 6.0
				hint = hint.clamp(Vector2.ZERO, Vector2.ONE * (Terrain.SIZE - 0.001))
				var tile: int = world.terrain.nearest_open(Terrain.index(Vector2i(hint)), int(page.radii[row] > 0.5 and page.flight[row] == 0))
				if tile >= 0:
					begin(world, target, "attack_move", 0, tile, ranged, now)
	else:
		rec.hp = maxi(0, int(rec.hp) - maxi(1, amount - int(world.facilities.definitions.get(rec.definition, {}).get("armor", 0))))
		if rec.hp <= 0:
			world.facilities.demolish(world, target, now)
	world.outcomes.append({"kind": "hit", "actor": actor, "target": target, "damage": amount, "at_ms": now})


func valid(world: RefCounted) -> bool:
	for id: Variant in orders:
		if not id is int or not world.actor_slots.has(id) or not orders[id] is Dictionary:
			return false
		var rec: Dictionary = orders[id]
		if not rec.get("target") is int or rec.target < 0 or not rec.get("anchor") is Vector2 or not rec.anchor.is_finite() or not rec.get("last_seen_pos") is Vector2 or not rec.last_seen_pos.is_finite() or not rec.get("last_seen_ms") is int or not rec.get("kind") is String or rec.kind not in ["pursue", "hold", "attack_move"]:
			return false
		for field: String in ["scan_ms", "repath_ms", "destination", "last_tile", "search_tile"]:
			if not rec.get(field) is int:
				return false
		if not rec.get("ranged") is bool or not rec.get("resume") is bool or rec.last_seen_ms < -1 or rec.last_seen_ms > world.elapsed_ms or rec.scan_ms < 0 or rec.repath_ms < 0:
			return false
		for tile: int in [rec.destination, rec.last_tile, rec.search_tile]:
			if tile < -1 or tile >= world.terrain.blocked.size():
				return false
	for actor: Variant in unreachable:
		var memory: Variant = unreachable[actor]
		if not actor is int or not world.actor_slots.has(actor) or not memory is Dictionary or not memory.get("targets") is Dictionary or not memory.get("topology") is int or not memory.get("flight") is int or not memory.get("large") is bool:
			return false
		for target: Variant in memory.targets:
			if not target is int or not memory.targets[target] is int or memory.targets[target] < 0 or memory.targets[target] >= world.terrain.blocked.size():
				return false
	for id: Variant in bolts:
		if not id is int or not bolts[id] is Dictionary:
			return false
		var bolt: Dictionary = bolts[id]
		if not bolt.get("position") is Vector2 or not bolt.position.is_finite() or not bolt.get("velocity") is Vector2 or not bolt.velocity.is_finite() or not bolt.get("expire_ms") is int or not bolt.get("damage") is int or not bolt.get("actor") is int:
			return false
	return true
