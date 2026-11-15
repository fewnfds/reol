extends RefCounted
## Normalize aliases before all checks; owner-thread payment is all-or-nothing.
static func from_action(definition: Dictionary) -> Array:
	return definition.costs

static func normalized(costs: Array) -> Dictionary:
	var totals: Dictionary = {}
	for cost: Dictionary in costs:
		var kind: String = str(cost.kind)
		var name_key: String = str(cost.id)
		if kind == "pool" and name_key in ["hp", "health", "life"]: kind = "health"
		if kind == "pool" and name_key in ["energy", "qi"]: kind = name_key
		var key: String = kind + ":" + (name_key if kind in ["item", "pool"] else "")
		totals[key] = int(totals.get(key, 0)) + int(cost.amount)
	return totals

static func available(world: RefCounted, actor: int, key: String) -> int:
	var kind: String = key.get_slice(":", 0)
	var name_key: String = key.get_slice(":", 1)
	var slot: int = world.actor_slots[actor]
	match kind:
		"item": return world.objects.amount(actor, name_key)
		"pool": return world.pools.amount(actor, name_key)
		"health": return maxi(0, world.pages[slot / 256].health[slot % 256] - 1)
		"energy": return world.pages[slot / 256].energy[slot % 256]
		"qi": return int(world.objects.records[actor].get("qi", 0))
	return -1

static func check(world: RefCounted, actor: int, costs: Array) -> String:
	var totals: Dictionary = normalized(costs)
	for key: String in totals:
		if int(totals[key]) <= 0 or available(world, actor, key) < int(totals[key]): return "insufficient_resource"
	return ""

static func pay(world: RefCounted, actor: int, costs: Array) -> bool:
	if not check(world, actor, costs).is_empty(): return false
	var slot: int = world.actor_slots[actor]
	var totals: Dictionary = normalized(costs)
	for key: String in totals:
		var amount: int = totals[key]
		match key.get_slice(":", 0):
			"item": world.objects.add(actor, key.get_slice(":", 1), -amount)
			"pool": world.pools.change(actor, key.get_slice(":", 1), -amount)
			"health": world.pages[slot / 256].health[slot % 256] -= amount
			"energy": world.pages[slot / 256].energy[slot % 256] -= amount
			"qi": world.objects.records[actor].qi -= amount
	world._sync_inventory(actor)
	return true
