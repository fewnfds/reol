extends RefCounted
## Canonical individual implements: identity, custody, durability and deployment.
## Bound samples are not ordinary stack inventory and do not duplicate an item on launch.
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")
const Motion = preload("res://scripts/sim/kernel/motion.gd")
const STATE_FIELDS: Array = ["records", "next_id"]
var records: Dictionary = {}
var next_id: int = 1
var segments: Array[Dictionary] = []

func owned(actor: int, ability: String = "") -> int:
	for id: int in records:
		if records[id].owner == actor and (ability.is_empty() or records[id].ability == ability): return id
	return 0

func segment_at(id: int, at: int) -> Dictionary:
	for index: int in range(segments.size() - 1, -1, -1):
		var segment: Dictionary = segments[index]
		if segment.id == id and at >= int(segment.start_ms) and at <= int(segment.end_ms): return segment
	return {}

func active_at(id: int, at: int) -> bool:
	if not records.has(id) or int(records[id].hp) <= 0 or at > int(records[id].get("stopped_ms", 9223372036854775807)): return false
	var segment: Dictionary = segment_at(id, at)
	return not segment.is_empty() and at < int(segment.active_until)

func _stop(value: Dictionary, at: int) -> void:
	var segment: Dictionary = segment_at(value.id, at)
	if not segment.is_empty(): value.position = Motion.at(segment.from, segment.to, segment.knots, clampf(float(at - int(segment.start_ms)) / maxi(1, int(segment.end_ms) - int(segment.start_ms)), 0, 1))
	value["stopped_ms"] = at

func accept_contact(id: int, target: int, at: int) -> bool:
	if not active_at(id, at): return false
	var value: Dictionary = records[id]
	if at < int(value.touch.get(target, 0)): return false
	value.touch[target] = at + int(Defs.ACTIONS[value.ability].delivery.contact_ms)
	return true

func commit(event: Dictionary) -> void:
	# Collection predicts a segment. Only the chronological owner may adopt its
	# endpoint/phase, after earlier damage/death has had a chance to stop it.
	var value: Dictionary = records.get(event.implement_id, {})
	if value.is_empty() or value.activation != event.activation or value.phase in ["broken", "dropped", "stowed"]: return
	if event.at_ms > int(value.get("stopped_ms", 9223372036854775807)): return
	value.position = event.position
	value.direction = event.direction
	if event.has("phase"):
		value.phase = event.phase
		if event.phase in ["dropped", "stowed"]: _stop(value, event.at_ms)

func dispatch(world: RefCounted, actor: int, state: Dictionary, at: int) -> void:
	var delivery: Dictionary = Defs.ACTIONS[state.kind].delivery
	var existing: Dictionary = {}
	for id: int in records:
		if records[id].owner == actor and records[id].ability == state.kind: existing[records[id].slot] = id
	if existing.values().any(func(id: int): return records[id].phase not in ["stowed", "broken"]): recall(world, actor, state.kind); return
	for index: int in int(delivery.instances):
		var id: int = existing.get(index, next_id)
		if not records.has(id):
			next_id += 1
			records[id] = {"id": id, "slot": index, "owner": actor, "ability": state.kind, "hp": int(delivery.durability), "phase": "stowed"}
		var value: Dictionary = records[id]
		if value.phase == "broken": continue
		value.erase("stopped_ms")
		value.merge({"phase": {"orbit": "orbiting", "hover": "hovering"}.get(delivery.deployment, "outbound"), "position": world.combat.position(world, actor), "direction": state.direction,
			"activation": state.activation, "damage": state.damage, "side": state.side, "power": state.power, "lineage": state.get("lineage", {}),
			"hover": (world.combat.position(world, actor) + Vector2(state.direction) * 2.5).clamp(Vector2.ONE * 0.35, Vector2.ONE * 511.65), "next_emit": at + int(delivery.emit_period), "depart_ms": at, "return_ms": at + int(delivery.life), "touch": {}}, true)

func prepare(world: RefCounted, now: int) -> void:
	var indexed: bool = false
	for value: Dictionary in records.values():
		if value.phase not in ["orbiting", "hovering"] or now < int(value.next_emit) or not world.combat.alive(world, value.owner): continue
		var delivery: Dictionary = Defs.ACTIONS[value.ability].delivery
		value.next_emit += int(delivery.emit_period)
		if str(delivery.emitter).is_empty(): continue
		if not indexed:
			world.combat.scan.index(world)
			indexed = true
		world.sight.sync(world)
		var target: int = 0
		var distance: float = 8.0
		for other: int in world.combat.scan.nearby(value.position - Vector2.ONE * 8, value.position + Vector2.ONE * 8):
			if not world.combat.eligible(world, value.owner, other, "hostile", value.side): continue
			var seen: Variant = world.sight.observed_position(world, value.owner, other)
			if seen == null or Terrain_los(world, value.position, seen): continue
			var span: float = Vector2(value.position).distance_to(seen)
			if span < distance: distance = span; target = other
		if target == 0: continue
		var lineage: Dictionary = world.reactions.root(value.owner, value.activation)
		world.combat.spawn_template(world, value.owner, delivery.emitter, value.position, Vector2(value.position).direction_to(world.combat.position(world, target)), now, 1.0, lineage)

func Terrain_los(world: RefCounted, from: Vector2, to: Vector2) -> bool:
	return preload("res://scripts/sim/kernel/terrain.gd").blocking_fraction(world.terrain.blocked, from, to) >= 0

func recall(world: RefCounted, actor: int, ability: String = "") -> void:
	for value: Dictionary in records.values():
		if not ability.is_empty() and value.ability != ability: continue
		if value.owner != actor or value.phase in ["broken", "stowed"] or not world.combat.alive(world, actor): continue
		value.erase("stopped_ms")
		var radius: float = float(Defs.ACTIONS[value.ability].delivery.radius)
		if Vector2(value.position).distance_to(world.combat.position(world, actor)) <= 0.8 and Motion.wall_hit(world.terrain, value.position, world.combat.position(world, actor), radius).fraction < 0:
			value.phase = "stowed"
		else: value.phase = "returning"

func drop_owner(world: RefCounted, actor: int, at: int) -> void:
	for value: Dictionary in records.values():
		if value.owner != actor or value.phase in ["broken", "dropped"]: continue
		var segment: Dictionary = segment_at(value.id, at)
		if value.phase == "stowed": value.position = world.combat.position(world, actor)
		elif not segment.is_empty(): _stop(value, at)
		value.phase = "dropped"
		value["stopped_ms"] = at

func readiness(actor: int, ability: String) -> String:
	var total: int = 0
	var broken: int = 0
	for entry: Dictionary in records.values():
		if entry.owner != actor or entry.ability != ability: continue
		total += 1
		if entry.phase == "broken": broken += 1
	if total > 0 and broken == total: return "implement_broken"
	return ""

func next_boundary(now: int, end: int) -> int:
	for value: Dictionary in records.values():
		if value.phase == "outbound" and int(value.return_ms) > now: end = mini(end, int(value.return_ms))
		if value.phase in ["orbiting", "hovering"] and int(value.next_emit) > now: end = mini(end, int(value.next_emit))
	return end

func collect(world: RefCounted, start: int, now: int, melee: Array[int]) -> Array[Dictionary]:
	var impacts: Array[Dictionary] = []
	for id: int in records:
		var value: Dictionary = records[id]
		if not world.combat.alive(world, value.owner):
			if value.phase not in ["broken", "dropped"]: drop_owner(world, value.owner, start)
			continue
		if value.phase not in ["outbound", "returning", "orbiting", "hovering"]: continue
		var def: Dictionary = Defs.ACTIONS[value.ability].merged(world.combat.Payload.summary(Defs.ACTIONS[value.ability].payload), true)
		var delivery: Dictionary = def.delivery
		var phase: String = "returning" if value.phase == "outbound" and start >= int(value.return_ms) else str(value.phase)
		var from: Vector2 = value.position
		var home: Vector2 = world.combat.position(world, value.owner)
		var owner_slot: int = world.actor_slots[value.owner]
		var owner_page: RefCounted = world.pages[owner_slot / 256]
		var home_before: Vector2 = world.combat.previous[owner_slot / 256][owner_slot % 256]
		var direction: Vector2 = from.direction_to(home) if phase == "returning" else value.direction
		if direction.is_zero_approx(): direction = value.direction
		var distance: float = float(delivery.speed) * (now - start) / 1000.0
		var to: Vector2 = from + direction * distance
		if phase in ["orbiting", "hovering"]:
			var angle: float = float(now - int(value.depart_ms)) / 1000.0 * 2.2 + float(value.slot) * TAU / int(delivery.instances)
			var desired: Vector2 = home + Vector2.from_angle(angle) * float(delivery.orbit_radius) if phase == "orbiting" else Vector2(value.hover)
			to = from.move_toward(desired, distance)
			if not from.is_equal_approx(to): direction = from.direction_to(to)
		var wall: Dictionary = Motion.wall_hit(world.terrain, from, to, float(delivery.radius))
		var caught: bool = false
		var halt: float = 1.0
		var active_until: int = now + 1
		var transition: String = ""
		if phase == "returning":
			var catch_fraction: float = Motion.hit_fraction(from, to, home_before, home, 0.45, owner_page.motion.get(owner_slot % 256, PackedVector3Array()))
			if catch_fraction >= 0 and (wall.fraction < 0 or catch_fraction < float(wall.fraction)):
				halt = catch_fraction
				caught = true
				transition = "stowed"
				active_until = start + roundi((now - start) * halt)
		if not caught and wall.fraction >= 0:
			halt = maxf(0, float(wall.fraction) - 0.002 / maxf(0.001, distance))
			if phase == "returning": active_until = start + roundi((now - start) * halt)
			transition = "dropped" if phase == "returning" else "returning"
		to = from.lerp(to, halt)
		var path := PackedVector3Array()
		if halt < 1:
			path = PackedVector3Array([Vector3(from.x, from.y, 0), Vector3(to.x, to.y, halt), Vector3(to.x, to.y, 1)])
		segments.append({"id": id, "from": from, "to": to, "knots": path, "start_ms": start, "end_ms": now, "active_until": active_until})
		impacts.append({"event": "implement_motion", "actor": value.owner, "implement_id": id, "activation": value.activation, "position": to, "direction": direction, "at_ms": now})
		if not transition.is_empty():
			impacts.append({"event": "implement_transition", "actor": value.owner, "implement_id": id, "activation": value.activation, "position": to, "direction": direction, "phase": transition, "at_ms": start + roundi((now - start) * halt)})
		elif phase != value.phase:
			impacts.append({"event": "implement_transition", "actor": value.owner, "implement_id": id, "activation": value.activation, "position": from, "direction": direction, "phase": phase, "at_ms": start})
		for target: int in world.combat.scan.nearby(from.min(to) - Vector2.ONE * (2 + world.combat.scan.sweep_padding), from.max(to) + Vector2.ONE * (2 + world.combat.scan.sweep_padding)):
			if not world.combat.eligible(world, value.owner, target, delivery.filter, value.side): continue
			var slot: int = world.actor_slots[target]
			var page: RefCounted = world.pages[slot / 256]
			var row: int = slot % 256
			var before: Vector2 = world.combat.previous[slot / 256][row]
			var fraction: float = Motion.circles_hit(from, to, path, before, page.positions[row], page.motion.get(row, PackedVector3Array()), page.radii[row] + float(delivery.radius))
			var at: int = start + roundi((now - start) * fraction)
			if fraction < 0 or at >= active_until or at < int(value.touch.get(target, 0)): continue
			impacts.append({"actor": value.owner, "target": target, "activation": value.activation, "source_implement": id,
				"at_ms": at, "damage": value.damage, "incoming": -direction, "stun": def.stun, "push": def.push, "side": value.side, "power": value.power,
				"group_ms": 0, "evadable": true, "position": Motion.at(from, to, path, fraction), "action": value.ability, "payload": def.payload, "lineage": value.lineage, "rules": def.reactions})
		# Enemy attacks use the same swept target, but never give this object a villager AI.
		var receiver_pad: Vector2 = Vector2.ONE * (float(delivery.radius) + 0.4)
		for target: int in world.combat.receivers(world, from.min(to) - receiver_pad, from.max(to) + receiver_pad, value.owner, delivery.filter, value.side):
			var point: Vector2 = world.combat.position(world, target)
			var fraction: float = Motion.circles_hit(from, to, path, point, point, PackedVector3Array(), 0.4 + float(delivery.radius))
			var at: int = start + roundi((now - start) * fraction)
			if fraction < 0 or at >= active_until or at < int(value.touch.get(target, 0)): continue
			impacts.append({"actor": value.owner, "target": target, "activation": value.activation, "source_implement": id, "at_ms": at, "damage": value.damage,
				"incoming": -direction, "stun": def.stun, "push": def.push, "group_ms": 0, "position": point, "action": value.ability, "payload": def.payload, "lineage": value.lineage, "rules": def.reactions, "side": value.side, "power": value.power})
		for attacker: int in melee:
			var action: Dictionary = world.combat.states[attacker]
			var other: Dictionary = Defs.ACTIONS[action.kind]
			if not world.combat.eligible(world, attacker, value.owner, other.delivery.filter, action.side): continue
			if action.hit.get("implement:%d" % id, false): continue
			var slot: int = world.actor_slots[attacker]
			var page: RefCounted = world.pages[slot / 256]
			var fraction: float = Motion.shape_hit(world.combat.previous[slot / 256][slot % 256], page.positions[slot % 256], page.motion.get(slot % 256, PackedVector3Array()), from, to, path, Defs.sector(other, action.direction), float(delivery.radius))
			if fraction < 0 or start + roundi((now - start) * fraction) >= active_until: continue
			var contact: Vector2 = Motion.at(from, to, path, fraction)
			if Motion.wall_hit(world.terrain, world.combat.position(world, attacker), contact, 0.0).fraction >= 0: continue
			impacts.append({"actor": attacker, "target": 0, "implement_target": id, "damage": action.damage,
				"activation": action.activation, "at_ms": start + roundi((now - start) * fraction), "melee": true})
	return impacts

func hit(world: RefCounted, id: int, amount: int, at: int) -> void:
	if not records.has(id) or records[id].hp <= 0 or amount <= 0: return
	var value: Dictionary = records[id]
	value.hp = maxi(0, int(value.hp) - maxi(1, amount))
	if value.hp == 0: value.phase = "broken"; _stop(value, at)
	world.emit({"kind": "implement_hit", "actor": value.owner, "implement": id, "at_ms": at, "position": value.position})

func valid(world: RefCounted) -> bool:
	if next_id < 1: return false
	var unique: Dictionary = {}
	for id: Variant in records:
		var value: Variant = records[id]
		if not id is int or id < 1 or id >= next_id or not value is Dictionary or value.get("id") != id: return false
		if not world.combat.valid_source(value): return false
		if not value.get("owner") is int or value.owner < 1 or value.owner >= world.objects.next_id or not Defs.ACTIONS.has(value.get("ability")): return false
		var delivery: Dictionary = Defs.ACTIONS[value.ability].delivery
		if delivery.kind != "implement" or not value.get("hp") is int or value.hp < 0 or value.hp > delivery.durability: return false
		if value.get("phase") not in ["stowed", "outbound", "returning", "dropped", "broken", "orbiting", "hovering"] or (value.hp == 0) != (value.phase == "broken"): return false
		if value.phase not in ["dropped", "broken"] and not world.actor_slots.has(value.owner): return false
		var key: String = "%s:%s:%s" % [value.owner, value.ability, value.get("slot", 0)]
		if unique.has(key): return false
		unique[key] = true
		if not world.combat._point_valid(value.get("position")) or value.position.x < 0 or not world.combat._direction_valid(value.get("direction")): return false
		for field: String in ["activation", "damage", "depart_ms", "return_ms", "side"]:
			if not value.get(field) is int: return false
		if value.activation < 1 or value.activation >= world.combat.next_activation or value.damage < 0 or value.depart_ms < 0 or value.depart_ms > world.elapsed_ms or value.return_ms != value.depart_ms + int(delivery.life): return false
		if not value.get("slot") is int or value.slot < 0 or value.slot >= int(delivery.instances) or not value.get("next_emit") is int or value.next_emit < value.depart_ms or not world.combat._point_valid(value.get("hover")): return false
		if not value.get("touch") is Dictionary: return false
		if value.has("stopped_ms") and (not value.stopped_ms is int or value.stopped_ms < 0 or value.stopped_ms > world.elapsed_ms): return false
		for target: Variant in value.touch:
			if not target is int or target < 1 or target >= world.objects.next_id or not value.touch[target] is int or value.touch[target] < 0 or value.touch[target] > world.elapsed_ms + int(delivery.contact_ms): return false
	return true
