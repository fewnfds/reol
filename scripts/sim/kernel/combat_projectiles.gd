extends RefCounted
## Parameterized projectile delivery, independent from action names and SceneTree physics.
const Motion = preload("res://scripts/sim/kernel/motion.gd")
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")

static func acquire(combat: RefCounted, world: RefCounted, bolt: Dictionary) -> void:
	if not combat.alive(world, bolt.actor): return
	world.sight.sync(world)
	var origin: Vector2 = bolt.position
	var direction: Vector2 = Vector2(bolt.velocity).normalized()
	var best: float = 0.8
	for target: int in combat.scan.nearby(origin - Vector2.ONE * 12, origin + Vector2.ONE * 12):
		if not combat.eligible(world, bolt.actor, target, bolt.filter, bolt.side): continue
		var seen: Variant = world.sight.observed_position(world, bolt.actor, target)
		if seen == null: continue
		var angle: float = absf(direction.angle_to(origin.direction_to(seen)))
		if angle < best: best = angle; bolt.target = target

static func steer(combat: RefCounted, world: RefCounted, now: int) -> void:
	for bolt: Dictionary in combat.bolts.values():
		if float(bolt.get("turn", 0)) <= 0 or now < int(bolt.next_steer): continue
		var dt: float = (int(bolt.next_steer) - int(bolt.steered_ms)) / 1000.0
		bolt.steered_ms = bolt.next_steer
		bolt.next_steer += 50
		if int(bolt.target) == 0: acquire(combat, world, bolt)
		if not combat.alive(world, bolt.actor) or not combat.alive(world, bolt.target): continue
		world.sight.sync(world)
		var seen: Variant = world.sight.observed_position(world, bolt.actor, bolt.target)
		if seen == null: continue
		var desired: Vector2 = Vector2(bolt.position).direction_to(seen)
		if not desired.is_zero_approx(): bolt.velocity = Vector2(bolt.velocity).rotated(clampf(Vector2(bolt.velocity).angle_to(desired), -float(bolt.turn) * dt, float(bolt.turn) * dt))

static func collect(combat: RefCounted, world: RefCounted, start: int, now: int, only_ids: Array = []) -> Array[Dictionary]:
	var impacts: Array[Dictionary] = []
	for id: int in combat.bolts.keys():
		if not only_ids.is_empty() and not only_ids.has(id): continue
		var bolt: Dictionary = combat.bolts[id]
		var segment_start: int = maxi(start, int(bolt.born_ms))
		if segment_start > now: continue
		var from: Vector2 = bolt.position
		var until: int = mini(now, int(bolt.expire_ms))
		var to: Vector2 = from + Vector2(bolt.velocity) * maxf(0, until - segment_start) / 1000.0
		var wall: Dictionary = Motion.wall_hit(world.terrain, from, to, bolt.radius) if bolt.walls else {"fraction": -1.0, "tile": -1}
		var first: float = wall.fraction
		var contacts: Array[Dictionary] = []
		var pad: float = float(bolt.radius) + 1.0 + combat.scan.sweep_padding
		for target: int in combat.scan.nearby(from.min(to) - Vector2.ONE * pad, from.max(to) + Vector2.ONE * pad):
			if not combat.eligible(world, bolt.actor, target, bolt.filter, bolt.side) or bolt.passed.has(target): continue
			var slot: int = world.actor_slots[target]
			var page: RefCounted = world.pages[slot / 256]
			var row: int = slot % 256
			var before: Vector2 = combat.previous[slot / 256][row]
			var path: PackedVector3Array = page.motion.get(row, PackedVector3Array())
			var low: float = float(segment_start - start) / maxi(1, now - start)
			var high: float = float(until - start) / maxi(1, now - start)
			var clipped: PackedVector3Array = Motion.subpath(before, page.positions[row], path, low, high)
			var begin: Vector2 = Vector2(clipped[0].x, clipped[0].y)
			var finish: Vector2 = Vector2(clipped[-1].x, clipped[-1].y)
			var fraction: float = Motion.hit_fraction(from, to, begin, finish, page.radii[row] + float(bolt.radius), clipped)
			if fraction >= 0 and (first < 0 or fraction < first): contacts.append({"target": target, "fraction": fraction, "implement": 0, "position": Motion.at(begin, finish, clipped, fraction)})
		for target: int in combat.receivers(world, from.min(to) - Vector2.ONE, from.max(to) + Vector2.ONE, bolt.actor, bolt.filter, bolt.side):
			if bolt.passed.has(target): continue
			var point: Vector2 = combat.position(world, target)
			var fraction: float = Motion.hit_fraction(from, to, point, point, 0.4 + float(bolt.radius), PackedVector3Array())
			if fraction >= 0 and (first < 0 or fraction < first): contacts.append({"target": target, "fraction": fraction, "implement": 0, "position": point})
		for value: Dictionary in world.implements.records.values():
			var segment: Dictionary = world.implements.segment_at(value.id, start)
			if segment.is_empty() or not combat.eligible(world, bolt.actor, value.owner, bolt.filter, bolt.side): continue
			if bolt.passed.has("implement:%d" % value.id): continue
			var low: float = float(segment_start - start) / maxi(1, now - start)
			var high: float = float(until - start) / maxi(1, now - start)
			var clipped: PackedVector3Array = Motion.subpath(segment.from, segment.to, segment.knots, low, high)
			var before: Vector2 = Vector2(clipped[0].x, clipped[0].y)
			var finish: Vector2 = Vector2(clipped[-1].x, clipped[-1].y)
			var radius: float = float(Defs.ACTIONS[value.ability].delivery.radius)
			var fraction: float = Motion.hit_fraction(from, to, before, finish, radius + float(bolt.radius), clipped)
			if fraction >= 0 and segment_start + roundi((until - segment_start) * fraction) < int(segment.active_until) and (first < 0 or fraction < first): contacts.append({"target": 0, "fraction": fraction, "implement": value.id, "position": Motion.at(before, finish, clipped, fraction)})
		contacts.sort_custom(func(a: Dictionary, b: Dictionary):
			if a.fraction != b.fraction: return a.fraction < b.fraction
			return a.target < b.target if a.target != b.target else a.implement < b.implement)
		for order: int in contacts.size():
			var contact: Dictionary = contacts[order]
			var at: int = segment_start + roundi((until - segment_start) * float(contact.fraction))
			var payload: Dictionary = combat.Payload.summary(bolt.payload)
			impacts.append({"actor": bolt.actor, "target": contact.target, "implement_target": contact.implement, "bolt_id": id, "contact_order": order,
				"lineage": bolt.get("lineage", {}), "rules": bolt.get("rules", []), "damage": bolt.damage, "activation": bolt.activation, "at_ms": at, "incoming": -Vector2(bolt.velocity).normalized(), "side": bolt.side, "power": bolt.power,
				"stun": payload.get("stun", 0), "push": payload.get("push", 0.0), "payload": bolt.payload, "group_ms": bolt.group_ms, "heavy_hit": payload.heavy_hit, "punish_ms": payload.punish_ms,
				"position": contact.position, "delivery_position": from.lerp(to, float(contact.fraction)), "action": bolt.ability if not bolt.ability.is_empty() else "bolt"})
		if first >= 0:
			var object_target: int = 0
			for object: int in world.objects.by_tile.get(wall.tile, []):
				if world.objects.records[object].kind in ["wall", "door"]:
					object_target = object
					break
			impacts.append({"actor": bolt.actor, "target": object_target, "bolt_id": id, "contact_order": contacts.size(), "bolt_wall": true, "damage": bolt.damage, "activation": bolt.activation, "at_ms": segment_start + roundi((until - segment_start) * first), "incoming": -Vector2(bolt.velocity).normalized(), "stun": 0, "push": 0.0, "position": from.lerp(to, first), "action": "bolt", "side": bolt.side, "power": bolt.power})
		var at: int = segment_start + roundi((until - segment_start) * (first if first >= 0 else 1.0))
		combat.projectile_segments.append({"id": id, "actor": bolt.actor, "from": from, "to": from.lerp(to, first) if first >= 0 else to,
			"start_ms": segment_start, "end_ms": at, "radius": bolt.radius, "ability": bolt.ability})
		for rule: Dictionary in bolt.rules:
			var trigger: int = int(bolt.born_ms) + int(rule.delay_ms) if rule.event == "timer" else int(bolt.expire_ms)
			if rule.event not in ["timer", "expired"] or bolt.timers.has(rule.id) or trigger > now or trigger < segment_start: continue
			impacts.append({"event": "projectile_reaction", "actor": bolt.actor, "target": 0, "bolt_id": id, "at_ms": trigger,
				"activation": bolt.activation, "action": bolt.ability, "damage": bolt.damage, "position": from + Vector2(bolt.velocity) * (trigger - segment_start) / 1000.0, "direction": Vector2(bolt.velocity).normalized(), "lineage": bolt.lineage, "rule": rule, "side": bolt.side, "power": bolt.power})
		bolt.position = from.lerp(to, first) if first >= 0 else to
	return impacts

static func accept(combat: RefCounted, world: RefCounted, impact: Dictionary) -> bool:
	# Collecting a candidate must not spend a projectile on an already destroyed
	# implement. Consumption is committed in the shared chronological impact pass.
	var id: int = impact.bolt_id
	if not combat.bolts.has(id): return false
	var bolt: Dictionary = combat.bolts[id]
	if not impact.get("bolt_wall", false):
		var implement: int = impact.get("implement_target", 0)
		if implement > 0:
			if not world.implements.active_at(implement, impact.at_ms): return false
		elif not combat.alive(world, impact.target): return false
		var key: Variant = impact.target if implement == 0 else "implement:%d" % implement
		if bolt.passed.has(key): return false
		bolt.passed[key] = true
		if implement == 0 and Defs.evading(combat.action_snapshot(impact.target), impact.at_ms):
			world.emit({"kind": "evaded", "actor": bolt.actor, "target": impact.target, "activation": bolt.activation, "at_ms": impact.at_ms, "position": impact.position})
			return false
		if int(bolt.pierce) > 0: bolt.pierce -= 1; return true
	truncate(combat, id, impact.at_ms)
	combat.bolts.erase(id)
	return true

static func truncate(combat: RefCounted, id: int, at: int) -> void:
	for index: int in range(combat.projectile_segments.size() - 1, -1, -1):
		var segment: Dictionary = combat.projectile_segments[index]
		if segment.id != id or at < int(segment.start_ms) or at > int(segment.end_ms): continue
		segment.to = Vector2(segment.from).lerp(segment.to, float(at - int(segment.start_ms)) / maxi(1, int(segment.end_ms) - int(segment.start_ms)))
		segment.end_ms = at
		break

static func finish(combat: RefCounted, now: int) -> void:
	for id: int in combat.bolts.keys():
		if now >= int(combat.bolts[id].expire_ms): combat.bolts.erase(id)
