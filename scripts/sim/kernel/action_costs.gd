extends RefCounted
## Normalize aliases before all checks; owner-thread payment is all-or-nothing.
const Beings = preload("res://scripts/sim/kernel/being_defs.gd")
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
	if not world.objects.records.has(actor): return -1
	return available_view(view(world, actor), key)

static func view(world: RefCounted, actor: int) -> Dictionary:
	var record: Dictionary = world.objects.records.get(actor, {})
	var result: Dictionary = {"inventory": record.get("inventory", {}), "qi": int(record.get("qi", 0)), "pools": world.pools.records.get(actor, {})}
	var slot: int = world.actor_slots.get(actor, -1)
	if slot >= 0:
		result["hp"] = world.pages[slot / 256].health[slot % 256]
		if Beings.has(record, "metabolism"): result["energy"] = world.pages[slot / 256].energy[slot % 256]
	return result # Owner-local only; detached callers supply their own copies.

static func available_view(actor: Dictionary, key: String) -> int:
	var kind: String = key.get_slice(":", 0)
	var name_key: String = key.get_slice(":", 1)
	match kind:
		"item": return int(actor.get("inventory", {}).get(name_key, 0))
		"pool": return int(actor.get("pools", {}).get(name_key, {}).get("current", 0))
		"health": return maxi(0, int(actor.hp) - 1) if actor.has("hp") else -1
		"energy": return int(actor.get("energy", -1)) if actor.get("body_capabilities", {"metabolism": true}).get("metabolism", false) else -1
		"qi": return int(actor.get("qi", 0))
	return -1

static func check(world: RefCounted, actor: int, costs: Array) -> String:
	if not world.objects.records.has(actor): return "invalid_actor"
	if costs.is_empty(): return ""
	return check_view(view(world, actor), costs)

static func check_view(actor: Dictionary, costs: Array) -> String:
	var totals: Dictionary = normalized(costs)
	for key: String in totals:
		if int(totals[key]) <= 0 or available_view(actor, key) < int(totals[key]): return "insufficient_resource"
	return ""

static func pay(world: RefCounted, actor: int, costs: Array) -> bool:
	if not check(world, actor, costs).is_empty(): return false
	var slot: int = world.actor_slots.get(actor, -1)
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
