extends RefCounted
## Rebuildable hot stats; inventory/equipment source facts belong to Objects.
## Called by the owner on spawn, equipment changes and restore, never per tick.
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const BASE: Dictionary = {"max_hp": 100.0, "melee": 25.0, "ranged": 20.0, "armor": 0.0, "speed": 5.0}

static func values(record: Dictionary) -> Dictionary:
	var result: Dictionary = BASE.duplicate()
	# Explicit base overrides are also useful for a disclosed pressure fixture.
	result.merge(record.get("base_stats", {}), true)
	for key: String in record.get("equipment", {}).values():
		var bonus: Dictionary = Items.bonuses(key)
		for stat: String in bonus: result[stat] += bonus[stat]
	for stat: String in ["max_hp", "melee", "ranged", "armor"]: result[stat] = roundi(result[stat])
	return result

static func valid_record(record: Dictionary) -> bool:
	if record.get("body_profile", "human") not in ["human", "companion"]: return false
	if record.has("ability_loadout") and not Defs.LOADOUTS.has(record.ability_loadout): return false
	if record.get("combat_style", "") not in ["", "trained"]: return false
	if record.get("practice_mode", "") not in ["", "light", "heavy", "mixed"]: return false
	var equipment: Variant = record.get("equipment")
	var base: Variant = record.get("base_stats", {})
	if not equipment is Dictionary or not base is Dictionary: return false
	for slot: Variant in equipment:
		var key: Variant = equipment[slot]
		if not slot is String or not Items.SLOTS.has(slot) or not key is String or not Items.valid(key) or Items.spec(key).get("slot", "") != slot: return false
	for stat: Variant in base:
		if not stat is String or not BASE.has(stat) or (not base[stat] is int and not base[stat] is float) or not is_finite(float(base[stat])): return false
		if float(base[stat]) < (0.1 if stat == "speed" else 0.0) or float(base[stat]) > (50.0 if stat == "speed" else 1000000.0): return false
	return float(base.get("max_hp", 100)) >= 1

static func rebuild(world: RefCounted, id: int, clamp_health: bool = true) -> void:
	var slot: int = world.actor_slots[id]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	page.resize_stats()
	page.needs_enabled[row] = 0 if world.objects.records[id].get("body_profile", "human") == "companion" else 1
	var stats: Dictionary = world.effects.modify(values(world.objects.records[id]), id, world.operation_time())
	if clamp_health: world.pools.configure(id, world.combat.profile(world, id).get("pools", []), world.operation_time())
	page.max_health[row] = stats.max_hp
	page.melee_damage[row] = stats.melee
	page.ranged_damage[row] = stats.ranged
	page.armor[row] = stats.armor
	page.move_speed[row] = stats.speed
	page.move_scales[row] = 1.0
	world.effects.invalidate_movement(id)
	if clamp_health: page.health[row] = mini(page.health[row], page.max_health[row])

static func view(page: RefCounted, row: int) -> Dictionary:
	return {"max_hp": page.max_health[row], "melee": page.melee_damage[row], "ranged": page.ranged_damage[row],
		"armor": page.armor[row], "speed": page.move_speed[row]}
