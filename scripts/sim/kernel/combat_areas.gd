extends RefCounted
## Independent, committed area deliveries. No SceneTree timer or projectile fiction.
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const STATE_FIELDS: Array = ["records", "next_id"]
var records: Dictionary = {}
var next_id: int = 1

func create(actor: int, state: Dictionary, at: int, side: int) -> void:
	var delivery: Dictionary = Defs.ACTIONS[state.kind].delivery
	records[next_id] = {"id": next_id, "actor": actor, "activation": state.activation, "ability": state.kind,
		"position": state.point, "damage": state.damage, "side": side, "born_ms": at,
		"trigger_ms": at + int(delivery.delay), "next_ms": at + int(delivery.delay),
		"expire_ms": at + int(delivery.delay) + int(delivery.duration), "finished": false}
	next_id += 1

func next_boundary(now: int, end: int) -> int:
	for value: Dictionary in records.values():
		for at: int in [int(value.next_ms), int(value.expire_ms) + 1]:
			if at > now: end = mini(end, at)
	return end

func collect(world: RefCounted, now: int) -> Array[Dictionary]:
	var impacts: Array[Dictionary] = []
	for id: int in records.keys():
		var value: Dictionary = records[id]
		var def: Dictionary = Defs.ACTIONS[value.ability]
		var delivery: Dictionary = def.delivery
		if value.finished and now > int(value.expire_ms) + 160: records.erase(id); continue
		if value.finished or now < int(value.next_ms): continue
		var at: int = value.next_ms
		for target: int in world.combat.scan.nearby(value.position - Vector2.ONE * (float(delivery.radius) + 1), value.position + Vector2.ONE * (float(delivery.radius) + 1)):
			if not world.combat.eligible(world, value.actor, target, delivery.filter, value.side): continue
			var slot: int = world.actor_slots[target]
			var point: Vector2 = world.pages[slot / 256].positions[slot % 256]
			var radius: float = world.pages[slot / 256].radii[slot % 256]
			if point.distance_to(value.position) > float(delivery.radius) + radius: continue
			if delivery.walls and Terrain.blocking_fraction(world.terrain.blocked, value.position, point) >= 0: continue
			impacts.append({"actor": value.actor, "target": target, "activation": value.activation, "at_ms": at,
				"damage": value.damage, "stun": def.stun, "push": def.push, "incoming": (value.position - point).normalized(),
				"position": point, "action": value.ability, "payload": value.ability, "evadable": true,
				"group_ms": mini(int(def.group_ms), int(delivery.period)), "heavy_hit": def.heavy_hit, "punish_ms": def.punish_ms})
		world.emit({"kind": "area_trigger", "actor": value.actor, "activation": value.activation, "area": id, "action": value.ability, "position": value.position, "at_ms": at})
		value.next_ms += int(delivery.period)
		value.finished = int(delivery.duration) == 0 or int(value.next_ms) >= int(value.expire_ms)
	return impacts

func valid(world: RefCounted) -> bool:
	if next_id < 1: return false
	for id: Variant in records:
		var value: Variant = records[id]
		if not id is int or id < 1 or id >= next_id or not value is Dictionary or value.get("id") != id: return false
		if not Defs.ACTIONS.has(value.get("ability")) or Defs.ACTIONS[value.ability].delivery.kind != "area": return false
		for key: String in ["actor", "activation", "damage", "side", "born_ms", "trigger_ms", "next_ms", "expire_ms"]:
			if not value.get(key) is int: return false
		if value.actor < 1 or value.actor >= world.objects.next_id or value.activation < 1 or value.activation >= world.combat.next_activation or value.damage < 0: return false
		if not world.combat._point_valid(value.get("position")) or value.position.x < 0 or not value.get("finished") is bool: return false
		var delivery: Dictionary = Defs.ACTIONS[value.ability].delivery
		if value.born_ms < 0 or value.born_ms > world.elapsed_ms or value.trigger_ms != value.born_ms + int(delivery.delay) or value.expire_ms != value.trigger_ms + int(delivery.duration): return false
		if value.next_ms < value.trigger_ms or value.next_ms > value.expire_ms + int(delivery.period): return false
		if (value.next_ms - value.trigger_ms) % int(delivery.period) != 0: return false
		if not value.finished and (value.next_ms <= world.elapsed_ms or (delivery.duration > 0 and value.next_ms >= value.expire_ms)): return false
		if value.finished and (world.elapsed_ms < value.trigger_ms or (delivery.duration > 0 and value.next_ms < value.expire_ms)): return false
	return true
