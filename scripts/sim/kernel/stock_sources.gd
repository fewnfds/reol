extends RefCounted
## Bounded natural replenishment into real stock; no terrain-volume simulation.
const Items = preload("res://scripts/sim/kernel/items.gd")
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")

static func spec(definition: Dictionary) -> Dictionary:
	return definition.get("capabilities", {}).get("stock_source", {})

static func errors(definition: Dictionary) -> PackedStringArray:
	var source: Dictionary = spec(definition)
	if source.is_empty(): return PackedStringArray()
	var result := PackedStringArray()
	if not Items.valid(str(source.get("item", ""))) or definition.get("kind") != "source": result.append("stock source: invalid item/kind")
	for field: String in ["capacity", "period_ms", "amount", "pickup_amount"]:
		var value: Variant = source.get(field)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floorf(float(value)) or float(value) <= 0 or float(value) > 1000000: result.append("stock source: invalid " + field)
	if result.is_empty() and (int(source.period_ms) % 1000 != 0 or int(source.amount) > int(source.capacity) or int(source.pickup_amount) > int(source.capacity)): result.append("stock source: inconsistent cadence/capacity")
	return result

static func install(world: RefCounted, id: int) -> void:
	var record: Dictionary = world.objects.records[id]
	var source: Dictionary = spec(world.facilities.definitions[record.definition])
	if source.is_empty(): return
	assert(errors(world.facilities.definitions[record.definition]).is_empty())
	record.capacity = int(source.capacity)
	if not record.has("source_due_ms"):
		record["source_due_ms"] = ((world.operation_time() + int(source.period_ms) + 999) / 1000) * 1000
		record["source_generated"] = 0
	if not world.facilities.sources.has(id): world.facilities.sources.append(id)

static func pulse(world: RefCounted, at: int) -> void:
	for id: int in world.facilities.sources:
		var record: Dictionary = world.objects.records[id]
		if at < int(record.source_due_ms): continue
		var source: Dictionary = spec(world.facilities.definitions[record.definition])
		var periods: int = 1 + (at - int(record.source_due_ms)) / int(source.period_ms)
		record.source_due_ms += periods * int(source.period_ms)
		var count: int = mini(periods * int(source.amount), int(source.capacity) - world.objects.amount(id, source.item))
		if count > 0:
			world.objects.add(id, source.item, count)
			record.source_generated += count

static func collect(world: RefCounted, actor: int, target: int, at: int, requested: int = 2147483647, purpose: String = "supply") -> Dictionary:
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor) or not world.objects.records.has(target): return world.ActivityResults.refused("dead_or_missing")
	var record: Dictionary = world.objects.records[target]
	var source: Dictionary = spec(world.facilities.definitions[record.definition])
	var view: Dictionary = world.operation_actor(actor)
	var place: Dictionary = world.operation_target(target)
	if source.is_empty() or purpose not in world.institutions.ISSUE_PURPOSES: return world.ActivityResults.refused("invalid_purpose")
	if not world.objects.Stock.access_reason(view, place, "collect_source", {"item": source.item}).is_empty() or not world.objects.Stock.permits_at(view, place, purpose, str(source.item)): return world.ActivityResults.refused("not_authorized")
	var moved: int = world.institutions.acquire_yield(world, actor, target, source.item, mini(int(source.pickup_amount), requested), at, purpose)
	world._sync_inventory(actor)
	return world.ActivityResults.completed({"item": source.item, "amount": moved, "source": target, "destination": actor}, "collected") if moved > 0 else world.ActivityResults.refused("empty_or_full")

static func rebuild(world: RefCounted) -> bool:
	world.facilities.sources.clear()
	for id: int in world.objects.records:
		var record: Dictionary = world.objects.records[id]
		var definition: Dictionary = world.facilities.definitions.get(record.definition, {})
		var source: Dictionary = spec(definition)
		if record.kind == "blueprint":
			if record.has("source_due_ms") or record.has("source_generated"): return false
			continue
		if source.is_empty():
			if record.has("source_due_ms") or record.has("source_generated"): return false
			continue
		if not errors(definition).is_empty() or record.kind != "source" or record.capacity != int(source.capacity): return false
		if not record.get("source_due_ms") is int or record.source_due_ms % 1000 != 0 or record.source_due_ms <= world.elapsed_ms or record.source_due_ms > world.elapsed_ms + int(source.period_ms) + 999: return false
		if not record.get("source_generated") is int or record.source_generated < 0 or record.source_generated > 1000000000000000: return false
		for item: String in record.stock:
			if item != source.item: return false
			for batch: Dictionary in record.stock[item]:
				if Stock.attribution(batch) != world.objects.default_right(id): return false
		world.facilities.sources.append(id)
	return true
