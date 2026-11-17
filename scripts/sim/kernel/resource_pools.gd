extends RefCounted
## Optional actor pools. Health, body energy, qi and inventory keep existing owners.
const STATE_FIELDS: Array = ["records"]
const QI_MAXIMUM: int = 3000
var records: Dictionary = {}

func configure(actor: int, specs: Array, now: int) -> void:
	if specs.is_empty(): return
	if not records.has(actor): records[actor] = {}
	for spec: Dictionary in specs:
		if not records[actor].has(spec.id): records[actor][spec.id] = {"current": int(spec.initial), "maximum": int(spec.maximum), "regen": int(spec.regen), "carry": 0, "at_ms": now}
		else:
			var pool: Dictionary = records[actor][spec.id]
			pool.maximum = int(spec.maximum)
			pool.regen = int(spec.regen)
			pool.current = mini(int(pool.current), int(pool.maximum))

func prepare(world: RefCounted, now: int) -> void:
	for actor: int in records:
		for pool: Dictionary in records[actor].values():
			var elapsed: int = maxi(0, now - int(pool.at_ms))
			pool.at_ms = now
			if not world.combat.alive(world, actor): continue
			pool.carry += elapsed * int(pool.regen)
			pool.current = mini(int(pool.maximum), int(pool.current) + int(pool.carry) / 1000)
			pool.carry = int(pool.carry) % 1000 if pool.current < pool.maximum else 0

func amount(actor: int, key: String) -> int:
	return int(records.get(actor, {}).get(key, {}).get("current", 0))

func change(actor: int, key: String, delta: int) -> int:
	if not records.get(actor, {}).has(key): return 0
	var pool: Dictionary = records[actor][key]
	var before: int = pool.current
	pool.current = clampi(before + delta, 0, int(pool.maximum))
	return int(pool.current) - before

func gain(world: RefCounted, actor: int, key: String, amount: int, at: int) -> int:
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor): return 0
	var slot: int = world.actor_slots[actor]
	if key in ["hp", "health", "life"]: return int(world.combat.heal(world, actor, actor, amount, at).amount)
	if key == "energy":
		var before: int = world.pages[slot / 256].energy[slot % 256]
		world.pages[slot / 256].energy[slot % 256] = clampi(before + amount, 0, 10000)
		world.livelihood.resource_changed(world, actor, key, before, world.pages[slot / 256].energy[slot % 256], at)
		return world.pages[slot / 256].energy[slot % 256] - before
	if key == "qi":
		var before: int = int(world.objects.records[actor].get("qi", 0))
		world.objects.records[actor]["qi"] = clampi(before + amount, 0, QI_MAXIMUM)
		world.livelihood.resource_changed(world, actor, key, before, int(world.objects.records[actor].qi), at)
		return int(world.objects.records[actor].qi) - before
	return change(actor, key, amount)

func valid(world: RefCounted) -> bool:
	for actor: Variant in records:
		if not actor is int or not world.actor_slots.has(actor) or not records[actor] is Dictionary or records[actor].size() > 8: return false
		for key: Variant in records[actor]:
			var pool: Variant = records[actor][key]
			if not key is String or not key.is_valid_identifier() or not pool is Dictionary: return false
			for field: String in ["current", "maximum", "regen", "carry", "at_ms"]:
				if not pool.get(field) is int: return false
			if pool.current < 0 or pool.current > pool.maximum or pool.maximum < 1 or pool.maximum > 100000 or pool.regen < 0 or pool.regen > 1000 or pool.carry < 0 or pool.carry >= 1000 or pool.at_ms < 0 or pool.at_ms > world.elapsed_ms: return false
	return true
