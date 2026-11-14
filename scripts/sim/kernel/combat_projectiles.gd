extends RefCounted
## Parameterized projectile delivery, independent from action names and SceneTree physics.
const Motion = preload("res://scripts/sim/kernel/motion.gd")
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")

static func steer(combat: RefCounted, world: RefCounted, now: int) -> void:
	for bolt: Dictionary in combat.bolts.values():
		if float(bolt.get("turn", 0)) <= 0 or now < int(bolt.next_steer): continue
		var dt: float = (int(bolt.next_steer) - int(bolt.steered_ms)) / 1000.0
		bolt.steered_ms = bolt.next_steer
		bolt.next_steer += 50
		if not combat.alive(world, bolt.actor) or not combat.alive(world, bolt.target): continue
		world.sight.sync(world)
		var seen: Variant = world.sight.observed_position(world, bolt.actor, bolt.target)
		if seen == null: continue
		var desired: Vector2 = Vector2(bolt.position).direction_to(seen)
		if not desired.is_zero_approx(): bolt.velocity = Vector2(bolt.velocity).rotated(clampf(Vector2(bolt.velocity).angle_to(desired), -float(bolt.turn) * dt, float(bolt.turn) * dt))

static func collect(combat: RefCounted, world: RefCounted, start: int, now: int) -> Array[Dictionary]:
	var impacts: Array[Dictionary] = []
	for id: int in combat.bolts.keys():
		var bolt: Dictionary = combat.bolts[id]
		var from: Vector2 = bolt.position
		var until: int = mini(now, int(bolt.expire_ms))
		var to: Vector2 = from + Vector2(bolt.velocity) * maxf(0, until - start) / 1000.0
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
			var fraction: float = Motion.hit_fraction(from, to, before, page.positions[row], page.radii[row] + float(bolt.radius), page.motion.get(row, PackedVector3Array()))
			if fraction >= 0 and (first < 0 or fraction < first): contacts.append({"target": target, "fraction": fraction, "implement": 0, "position": Motion.at(before, page.positions[row], page.motion.get(row, PackedVector3Array()), fraction)})
		for value: Dictionary in world.implements.records.values():
			var segment: Dictionary = world.implements.segment_at(value.id, start)
			if segment.is_empty() or not combat.eligible(world, bolt.actor, value.owner, bolt.filter, bolt.side): continue
			if bolt.passed.has("implement:%d" % value.id): continue
			var before: Vector2 = segment.from
			var radius: float = float(Defs.ACTIONS[value.ability].delivery.radius)
			var fraction: float = Motion.hit_fraction(from, to, before, segment.to, radius + float(bolt.radius), segment.knots)
			if fraction >= 0 and start + roundi((now - start) * fraction) < int(segment.active_until) and (first < 0 or fraction < first): contacts.append({"target": 0, "fraction": fraction, "implement": value.id, "position": Motion.at(before, segment.to, segment.knots, fraction)})
		contacts.sort_custom(func(a: Dictionary, b: Dictionary):
			if a.fraction != b.fraction: return a.fraction < b.fraction
			return a.target < b.target if a.target != b.target else a.implement < b.implement)
		for order: int in contacts.size():
			var contact: Dictionary = contacts[order]
			var at: int = start + roundi((until - start) * float(contact.fraction))
			var payload: Dictionary = Defs.ACTIONS.get(bolt.ability, {})
			impacts.append({"actor": bolt.actor, "target": contact.target, "implement_target": contact.implement, "bolt_id": id, "contact_order": order,
				"damage": bolt.damage, "activation": bolt.activation, "at_ms": at, "incoming": -Vector2(bolt.velocity).normalized(),
				"stun": payload.get("stun", 0), "push": payload.get("push", 0.0), "payload": bolt.ability, "group_ms": payload.get("group_ms", 280),
				"position": contact.position, "action": bolt.ability if not bolt.ability.is_empty() else "bolt"})
		if first >= 0:
			var object_target: int = 0
			for object: int in world.objects.by_tile.get(wall.tile, []):
				if world.objects.records[object].kind in ["wall", "door"]:
					object_target = object
					break
			impacts.append({"actor": bolt.actor, "target": object_target, "bolt_id": id, "contact_order": contacts.size(), "bolt_wall": true, "damage": bolt.damage, "activation": bolt.activation, "at_ms": start + roundi((until - start) * first), "incoming": -Vector2(bolt.velocity).normalized(), "stun": 0, "push": 0.0, "position": from.lerp(to, first), "action": "bolt"})
		var at: int = start + roundi((until - start) * (first if first >= 0 else 1.0))
		combat.projectile_segments.append({"id": id, "actor": bolt.actor, "from": from, "to": from.lerp(to, first) if first >= 0 else to,
			"start_ms": start, "end_ms": at, "radius": bolt.radius, "ability": bolt.ability})
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
		if implement == 0 and Defs.evading(combat.states.get(impact.target, {}), impact.at_ms):
			world.emit({"kind": "evaded", "actor": bolt.actor, "target": impact.target, "activation": bolt.activation, "at_ms": impact.at_ms, "position": impact.position})
			return false
		if int(bolt.pierce) > 0: bolt.pierce -= 1; return true
	for index: int in range(combat.projectile_segments.size() - 1, -1, -1):
		var segment: Dictionary = combat.projectile_segments[index]
		if segment.id != id or impact.at_ms < int(segment.start_ms) or impact.at_ms > int(segment.end_ms): continue
		segment.to = Vector2(segment.from).lerp(segment.to, float(impact.at_ms - int(segment.start_ms)) / maxi(1, int(segment.end_ms) - int(segment.start_ms)))
		segment.end_ms = impact.at_ms
		break
	combat.bolts.erase(id)
	return true

static func finish(combat: RefCounted, now: int) -> void:
	for id: int in combat.bolts.keys():
		if now >= int(combat.bolts[id].expire_ms): combat.bolts.erase(id)
