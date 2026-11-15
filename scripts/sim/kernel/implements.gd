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
	if not records.has(id) or at > int(records[id].get("stopped_ms", 9223372036854775807)): return false
	var segment: Dictionary = segment_at(id, at)
	return not segment.is_empty() and at < int(segment.active_until)

func _stop(value: Dictionary, at: int) -> void:
	var segment: Dictionary = segment_at(value.id, at)
	if not segment.is_empty(): value.position = Motion.at(segment.from, segment.to, segment.knots, clampf(float(at - int(segment.start_ms)) / maxi(1, int(segment.end_ms) - int(segment.start_ms)), 0, 1))
	value["stopped_ms"] = at

func dispatch(world: RefCounted, actor: int, state: Dictionary, at: int) -> void:
	var id: int = owned(actor, state.kind)
	if id > 0 and records[id].phase != "stowed": recall(world, actor); return
	var delivery: Dictionary = Defs.ACTIONS[state.kind].delivery
	if id == 0:
		id = next_id
		next_id += 1
		records[id] = {"id": id, "owner": actor, "ability": state.kind, "hp": int(delivery.durability), "phase": "stowed"}
	var value: Dictionary = records[id]
	value.erase("stopped_ms")
	value.merge({"phase": "outbound", "position": world.combat.position(world, actor), "direction": state.direction,
		"activation": state.activation, "damage": state.damage, "side": int(world.objects.records[actor].get("side", 0)),
		"depart_ms": at, "return_ms": at + int(delivery.life), "touch": {}}, true)

func recall(world: RefCounted, actor: int) -> void:
	for value: Dictionary in records.values():
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
		if not segment.is_empty() and at < int(segment.active_until): _stop(value, at)
		elif value.phase == "stowed": value.position = world.combat.position(world, actor)
		value.phase = "dropped"
		value["stopped_ms"] = at

func readiness(actor: int, ability: String) -> String:
	var id: int = owned(actor, ability)
	if id > 0 and records[id].phase == "broken": return "implement_broken"
	return ""

func next_boundary(now: int, end: int) -> int:
	for value: Dictionary in records.values():
		if value.phase == "outbound" and int(value.return_ms) > now: end = mini(end, int(value.return_ms))
	return end

func collect(world: RefCounted, start: int, now: int, melee: Array[int]) -> Array[Dictionary]:
	var impacts: Array[Dictionary] = []
	for id: int in records:
		var value: Dictionary = records[id]
		if not world.combat.alive(world, value.owner):
			if value.phase not in ["broken", "dropped"]: drop_owner(world, value.owner, start)
			continue
		if value.phase not in ["outbound", "returning"]: continue
		var def: Dictionary = Defs.ACTIONS[value.ability].merged(world.combat.Payload.summary(Defs.ACTIONS[value.ability].payload), true)
		var delivery: Dictionary = def.delivery
		if start >= int(value.return_ms): value.phase = "returning"
		var from: Vector2 = value.position
		var home: Vector2 = world.combat.position(world, value.owner)
		var owner_slot: int = world.actor_slots[value.owner]
		var owner_page: RefCounted = world.pages[owner_slot / 256]
		var home_before: Vector2 = world.combat.previous[owner_slot / 256][owner_slot % 256]
		var direction: Vector2 = from.direction_to(home) if value.phase == "returning" else value.direction
		if direction.is_zero_approx(): direction = value.direction
		var distance: float = float(delivery.speed) * (now - start) / 1000.0
		var to: Vector2 = from + direction * distance
		var wall: Dictionary = Motion.wall_hit(world.terrain, from, to, float(delivery.radius))
		var caught: bool = false
		var halt: float = 1.0
		var active_until: int = now + 1
		if value.phase == "returning":
			var catch_fraction: float = Motion.hit_fraction(from, to, home_before, home, 0.45, owner_page.motion.get(owner_slot % 256, PackedVector3Array()))
			if catch_fraction >= 0 and (wall.fraction < 0 or catch_fraction < float(wall.fraction)):
				halt = catch_fraction
				caught = true
				active_until = start + roundi((now - start) * halt)
		if not caught and wall.fraction >= 0:
			halt = maxf(0, float(wall.fraction) - 0.002 / maxf(0.001, distance))
			if value.phase == "returning": active_until = start + roundi((now - start) * halt)
			value.phase = "dropped" if value.phase == "returning" else "returning"
		to = from.lerp(to, halt)
		var path := PackedVector3Array()
		if halt < 1:
			path = PackedVector3Array([Vector3(from.x, from.y, 0), Vector3(to.x, to.y, halt), Vector3(to.x, to.y, 1)])
		value.position = to
		value.direction = direction
		segments.append({"id": id, "from": from, "to": to, "knots": path, "start_ms": start, "end_ms": now, "active_until": active_until})
		for target: int in world.combat.scan.nearby(from.min(to) - Vector2.ONE * 2, from.max(to) + Vector2.ONE * 2):
			if not world.combat.eligible(world, value.owner, target, delivery.filter, value.side): continue
			var slot: int = world.actor_slots[target]
			var page: RefCounted = world.pages[slot / 256]
			var row: int = slot % 256
			var before: Vector2 = world.combat.previous[slot / 256][row]
			var fraction: float = Motion.circles_hit(from, to, path, before, page.positions[row], page.motion.get(row, PackedVector3Array()), page.radii[row] + float(delivery.radius))
			var at: int = start + roundi((now - start) * fraction)
			if fraction < 0 or at >= active_until or at < int(value.touch.get(target, 0)): continue
			value.touch[target] = at + int(delivery.contact_ms)
			impacts.append({"actor": value.owner, "target": target, "activation": value.activation, "source_implement": id,
				"at_ms": at, "damage": value.damage, "incoming": -direction, "stun": def.stun, "push": def.push,
				"group_ms": 0, "evadable": true, "position": Motion.at(from, to, path, fraction), "action": value.ability, "payload": def.payload})
		# Enemy attacks use the same swept target, but never give this object a villager AI.
		for attacker: int in melee:
			var action: Dictionary = world.combat.states[attacker]
			var other: Dictionary = Defs.ACTIONS[action.kind]
			if not world.combat.eligible(world, attacker, value.owner, other.delivery.filter, int(world.objects.records[attacker].get("side", 0))): continue
			if action.hit.get("implement:%d" % id, false): continue
			var slot: int = world.actor_slots[attacker]
			var page: RefCounted = world.pages[slot / 256]
			var fraction: float = Motion.shape_hit(world.combat.previous[slot / 256][slot % 256], page.positions[slot % 256], page.motion.get(slot % 256, PackedVector3Array()), from, to, path, Defs.sector(other, action.direction), float(delivery.radius))
			if fraction < 0 or start + roundi((now - start) * fraction) >= active_until: continue
			var contact: Vector2 = Motion.at(from, to, path, fraction)
			if Motion.wall_hit(world.terrain, world.combat.position(world, attacker), contact, 0.0).fraction >= 0: continue
			impacts.append({"actor": attacker, "target": 0, "implement_target": id, "damage": action.damage,
				"activation": action.activation, "at_ms": start + roundi((now - start) * fraction), "melee": true})
		if caught: value.phase = "stowed"
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
		if not value.get("owner") is int or value.owner < 1 or value.owner >= world.objects.next_id or not Defs.ACTIONS.has(value.get("ability")): return false
		var delivery: Dictionary = Defs.ACTIONS[value.ability].delivery
		if delivery.kind != "implement" or not value.get("hp") is int or value.hp < 0 or value.hp > delivery.durability: return false
		if value.get("phase") not in ["stowed", "outbound", "returning", "dropped", "broken"] or (value.hp == 0) != (value.phase == "broken"): return false
		var key: String = "%s:%s" % [value.owner, value.ability]
		if unique.has(key): return false
		unique[key] = true
		if not world.combat._point_valid(value.get("position")) or value.position.x < 0 or not world.combat._direction_valid(value.get("direction")): return false
		for field: String in ["activation", "damage", "depart_ms", "return_ms", "side"]:
			if not value.get(field) is int: return false
		if value.activation < 1 or value.activation >= world.combat.next_activation or value.damage < 0 or value.depart_ms < 0 or value.depart_ms > world.elapsed_ms or value.return_ms != value.depart_ms + int(delivery.life): return false
		if not value.get("touch") is Dictionary: return false
		if value.has("stopped_ms") and (not value.stopped_ms is int or value.stopped_ms < 0 or value.stopped_ms > world.elapsed_ms): return false
		for target: Variant in value.touch:
			if not target is int or target < 1 or target >= world.objects.next_id or not value.touch[target] is int or value.touch[target] < 0 or value.touch[target] > world.elapsed_ms + int(delivery.contact_ms): return false
	return true
