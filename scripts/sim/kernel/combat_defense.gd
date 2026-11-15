extends RefCounted
## Ordered shield balances and directional timed blocks. Neither is invulnerability.
const STATE_FIELDS: Array = ["shields", "guards", "next_id"]
var shields: Dictionary = {}
var guards: Dictionary = {}
var next_id: int = 1

func shield(world: RefCounted, actor: int, target: int, amount: int, until: int, at: int, context: Dictionary = {}) -> void:
	if amount <= 0 or not world.combat.alive(world, target): return
	shields[next_id] = {"id": next_id, "source": actor, "target": target, "amount": amount, "born_ms": at, "until_ms": until, "context": context.duplicate(true)}
	next_id += 1

func guard(world: RefCounted, actor: int, fraction: float, duration: int, at: int, direction: Vector2) -> void:
	guards[actor] = {"born_ms": at, "until_ms": at + duration, "fraction": fraction, "direction": direction, "half_angle": 1.15}
	world.emit({"kind": "guard_started", "actor": actor, "at_ms": at})

func prepare(world: RefCounted, now: int) -> void:
	for id: int in shields.keys():
		if now >= int(shields[id].until_ms) or not world.combat.alive(world, shields[id].target):
			world.emit({"kind": "shield_removed", "target": shields[id].target, "at_ms": now, "reason": "expired" if now >= int(shields[id].until_ms) else "death"})
			shields.erase(id)
	for actor: int in guards.keys():
		if now >= int(guards[actor].until_ms) or not world.combat.alive(world, actor): guards.erase(actor)

func next_boundary(now: int, end: int) -> int:
	for entry: Dictionary in shields.values() + guards.values():
		if entry.until_ms > now: end = mini(end, entry.until_ms)
	return end

func absorb(world: RefCounted, target: int, amount: int, incoming: Vector2, now: int) -> Dictionary:
	var result: Dictionary = {"remaining": amount, "guarded": false, "blocked": 0, "absorbed": 0, "broken": []}
	var block: Dictionary = guards.get(target, {})
	if not block.is_empty() and now >= int(block.born_ms) and now < int(block.until_ms) and not incoming.is_zero_approx() and absf(Vector2(block.direction).angle_to(incoming)) <= float(block.half_angle):
		result.guarded = float(block.fraction) > 0
		result.blocked = roundi(amount * float(block.fraction))
		result.remaining -= int(result.blocked)
	var ids: Array = shields.keys()
	ids.sort()
	for id: int in ids:
		var entry: Dictionary = shields[id]
		if entry.target != target or now < int(entry.born_ms) or now >= int(entry.until_ms): continue
		var used: int = mini(int(result.remaining), int(entry.amount))
		entry.amount -= used
		result.remaining -= used
		result.absorbed += used
		if entry.amount == 0:
			result.broken.append(entry.duplicate(true))
			shields.erase(id)
			world.emit({"kind": "shield_removed", "target": target, "at_ms": now, "reason": "broken"})
	return result

func total(target: int, at: int) -> int:
	var amount: int = 0
	for entry: Dictionary in shields.values():
		if entry.target == target and at >= int(entry.born_ms) and at < int(entry.until_ms): amount += int(entry.amount)
	return amount

func remove_target(target: int) -> void:
	guards.erase(target)
	for id: int in shields.keys():
		if shields[id].target == target: shields.erase(id)

func valid(world: RefCounted) -> bool:
	if next_id < 1: return false
	for id: Variant in shields:
		var entry: Variant = shields[id]
		if not id is int or id < 1 or id >= next_id or not entry is Dictionary or entry.get("id") != id: return false
		for field: String in ["source", "target", "amount", "born_ms", "until_ms"]:
			if not entry.get(field) is int: return false
		if not world.objects.records.has(entry.target) or entry.source < 1 or entry.source >= world.objects.next_id or entry.amount <= 0 or entry.amount > 1000000 or entry.born_ms < 0 or entry.born_ms > world.elapsed_ms or entry.until_ms <= entry.born_ms or entry.until_ms > world.elapsed_ms + 60000 or not entry.get("context") is Dictionary: return false
	for actor: Variant in guards:
		var entry: Variant = guards[actor]
		if not actor is int or not world.actor_slots.has(actor) or not entry is Dictionary: return false
		if not entry.get("born_ms") is int or not entry.get("until_ms") is int or entry.born_ms < 0 or entry.born_ms > world.elapsed_ms or entry.until_ms <= entry.born_ms or entry.until_ms > world.elapsed_ms + 60000: return false
		if not entry.get("fraction") is float or not is_finite(entry.fraction) or entry.fraction < 0 or entry.fraction > 1 or not entry.get("direction") is Vector2 or not entry.direction.is_finite() or absf(entry.direction.length() - 1) > 0.01 or not entry.get("half_angle") is float or not is_finite(entry.half_angle) or entry.half_angle <= 0 or entry.half_angle > PI: return false
	return true
