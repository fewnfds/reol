extends RefCounted
## Persistent timed effects. Definitions are immutable; every active lifetime is a value.
## HP is still committed by Combat. Movement scales are rebuildable body data.
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")
const STATE_FIELDS: Array = ["records", "next_id"]
var records: Dictionary = {}
var next_id: int = 1

func apply(world: RefCounted, target: int, source: int, activation: int, ability: String, now: int, amount: int) -> void:
	apply_bundle(world, target, source, activation, ability, Defs.ACTIONS[ability].payload, now, amount)

func apply_bundle(world: RefCounted, target: int, source: int, activation: int, ability: String, bundle: Array, now: int, amount: int) -> void:
	for spec: Dictionary in bundle:
		if spec.kind == "domain":
			world.DomainOps.commit(world, source, target, spec.operation, now)
			continue
		if not world.combat.alive(world, target) or not world.actor_slots.has(target): continue
		if spec.kind not in ["slow", "dot"]: continue
		var found: int = 0
		for id: int in records:
			var old: Dictionary = records[id]
			if now < int(old.until_ms) and old.target == target and old.kind == spec.kind and old.status_id == spec.id and (spec.kind == "slow" or old.source == source): found = id; break
		var magnitude: float = float(spec.magnitude)
		var damage: int = maxi(0, roundi(amount * magnitude)) if spec.kind == "dot" else 0
		if found > 0:
			var old: Dictionary = records[found]
			old.until_ms = maxi(int(old.until_ms), now + int(spec.duration_ms))
			old.magnitude = minf(float(old.magnitude), magnitude) if spec.kind == "slow" else magnitude
			old.damage = maxi(int(old.damage), damage)
			continue # Refresh never resets the next periodic tick.
		records[next_id] = {"source": source, "target": target, "activation": activation, "ability": ability,
			"kind": spec.kind, "status_id": spec.id, "born_ms": now, "until_ms": now + int(spec.duration_ms),
			"next_ms": now + int(spec.period_ms), "period_ms": int(spec.period_ms), "magnitude": magnitude, "damage": damage}
		next_id += 1

func next_boundary(now: int, end: int) -> int:
	for value: Dictionary in records.values():
		for boundary: int in [int(value.until_ms), int(value.next_ms) if value.kind == "dot" else 0]:
			if boundary > now: end = mini(end, boundary)
	return end

func prepare(world: RefCounted, now: int) -> void:
	for page: RefCounted in world.pages: page.move_scales.fill(1.0)
	var scales: Dictionary = {}
	for id: int in records.keys():
		var value: Dictionary = records[id]
		if now >= int(value.until_ms) or not world.combat.alive(world, value.target): records.erase(id); continue
		if value.kind == "slow": scales[value.target] = float(scales.get(value.target, 1.0)) * float(value.magnitude)
	for actor: int in scales:
		var slot: int = world.actor_slots[actor]
		world.pages[slot / 256].move_scales[slot % 256] = maxf(0.15, float(scales[actor]))

func collect(world: RefCounted, now: int) -> Array[Dictionary]:
	var impacts: Array[Dictionary] = []
	for value: Dictionary in records.values():
		if value.kind != "dot": continue
		while int(value.next_ms) <= now and int(value.next_ms) < int(value.until_ms):
			impacts.append({"actor": value.source, "target": value.target, "activation": value.activation,
				"at_ms": value.next_ms, "damage": value.damage, "incoming": Vector2.ZERO, "stun": 0, "push": 0.0,
				"group_ms": 0, "periodic": true, "position": world.combat.position(world, value.target), "action": value.ability})
			value.next_ms += int(value.period_ms)
	return impacts

func remove_target(actor: int) -> void:
	for id: int in records.keys():
		if records[id].target == actor: records.erase(id)

func valid(world: RefCounted) -> bool:
	if next_id < 1: return false
	for id: Variant in records:
		var value: Variant = records[id]
		if not id is int or id < 1 or id >= next_id or not value is Dictionary: return false
		for key: String in ["source", "target", "activation", "born_ms", "until_ms", "next_ms", "period_ms", "damage"]:
			if not value.get(key) is int: return false
		if not world.actor_slots.has(value.target) or value.source < 1 or value.source >= world.objects.next_id or not Defs.ACTIONS.has(value.get("ability")): return false
		if value.get("kind") not in ["slow", "dot"] or not value.get("status_id") is String or value.status_id.is_empty(): return false
		if not value.get("magnitude") is float or not is_finite(value.magnitude): return false
		if value.born_ms < 0 or value.born_ms > world.elapsed_ms or value.until_ms <= value.born_ms or value.until_ms > world.elapsed_ms + 60000: return false
		if value.activation == 0 or value.activation >= world.combat.next_activation or value.damage < 0 or value.damage > 10000000: return false
		if value.kind == "dot" and (value.period_ms < 50 or value.period_ms > 10000 or value.next_ms < value.born_ms + value.period_ms or (value.next_ms <= world.elapsed_ms and value.next_ms < value.until_ms) or value.next_ms > world.elapsed_ms + value.period_ms or value.magnitude < 0 or value.magnitude > 20): return false
		if value.kind == "slow" and (value.magnitude <= 0 or value.magnitude > 1): return false
	return true
