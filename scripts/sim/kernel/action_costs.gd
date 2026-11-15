extends RefCounted
## Start costs are committed once, after successful joint admission.
static func from_action(definition: Dictionary) -> Array:
	return [{"kind": "item", "id": definition.cost_item, "amount": definition.cost_amount}] if int(definition.cost_amount) > 0 else []

static func normalized(costs: Array) -> Dictionary:
	var totals: Dictionary = {}
	for cost: Dictionary in costs:
		var key: String = str(cost.kind) + ":" + str(cost.id)
		totals[key] = int(totals.get(key, 0)) + int(cost.amount)
	return totals

static func check(world: RefCounted, actor: int, costs: Array) -> String:
	for key: String in normalized(costs):
		if not key.begins_with("item:"): return "invalid_cost"
		if world.objects.amount(actor, key.trim_prefix("item:")) < int(normalized(costs)[key]): return "insufficient_resource"
	return ""

static func pay(world: RefCounted, actor: int, costs: Array) -> bool:
	if not check(world, actor, costs).is_empty(): return false
	var totals: Dictionary = normalized(costs)
	for key: String in totals: world.objects.add(actor, key.trim_prefix("item:"), -int(totals[key]))
	world._sync_inventory(actor)
	return true
