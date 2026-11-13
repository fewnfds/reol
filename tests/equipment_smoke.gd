extends RefCounted
## Atomic location, actual effects, and rebuildable equipment state counterexamples.
const World = preload("res://scripts/sim/kernel/world.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")

static func run(check: Callable) -> void:
	var w := World.new()
	w.initialize(4, 0)
	var page: RefCounted = w.pages[0]
	for actor: int in range(1, 5):
		w.command({"kind":"stop", "actor":actor})
		page.positions[actor - 1] = Vector2(145.5 + actor, 145.5)
	var bag_size: int = w.objects.count_inventory(1)
	w.objects.records[1].capacity = bag_size
	check.call(w.command({"kind":"equip", "item":"iron_sword"}).ok, "Normal gear could not equip")
	check.call(w.command({"kind":"equip", "item":"iron_sword@2"}).ok, "Full-count-capacity swap was not atomic")
	check.call(w.objects.amount(1, "iron_sword") == 1 and w.objects.amount(1, "iron_sword@2") == 0 and page.melee_damage[0] == 38, "Swap duplicated location or did not cache quality stats")
	check.call(w.objects.total("iron_sword@2") == 1 and w.objects.audit_total("iron_sword@2") == 1, "Equipping broke material accounting")
	w.command({"kind":"attack", "target":2})
	check.call(page.health[1] == 62, "Actual attack ignored equipment damage")
	w.objects.add(1, "wood", 1)
	var before: Dictionary = w.objects.records[1].duplicate(true)
	check.call(not w.command({"kind":"unequip", "slot":"weapon"}).ok and w.objects.records[1].equipment == before.equipment and w.objects.records[1].inventory == before.inventory, "Failed full-bag unequip partially committed")
	w.objects.add(1, "wood", -1)
	check.call(w.command({"kind":"unequip", "slot":"weapon"}).ok and page.melee_damage[0] == 25, "Unequip left stale attack stats")
	check.call(w.command({"kind":"equip", "item":"cloth_robe"}).ok and page.max_health[0] == 120 and page.health[0] == 100, "HP gear healed on equip or ignored max HP")
	w.command({"kind":"heal"})
	check.call(page.health[0] == 120, "Potion did not honor gear max HP")
	w.combat.damage(w, 2, 1, 20, w.elapsed_ms)
	check.call(page.health[0] == 103, "Actual damage ignored cached armor")
	w.command({"kind":"unequip", "slot":"body"})
	check.call(page.health[0] == 100 and page.max_health[0] == 100, "Max HP removal was not clamped")
	w.command({"kind":"equip", "item":"travel_boots"})
	var origin: Vector2 = page.positions[0]
	w.command({"kind":"move", "position":origin + Vector2(8, 3)})
	w.step()
	check.call(absf(page.positions[0].distance_to(origin) - 0.3) < 0.001, "Gear speed did not change continuous motion")
	w.command({"kind":"equip", "item":"short_bow"})
	w.combat.launch(1, page.positions[0], page.positions[1], w.elapsed_ms, page.ranged_damage[0])
	w.command({"kind":"unequip", "slot":"weapon"})
	check.call(w.combat.bolts.values()[0].damage == 28, "In-flight projectile changed damage after unequip")
	var chest: int = w.depot_objects[0]
	check.call(w.objects.transfer(1, chest, "iron_sword@2", 1) == 1 and w.objects.amount(chest, "iron_sword@2") == 1, "Container transfer lost quality")
	check.call(not Items.valid("iron_sword@02") and not Items.valid("wood@2") and not Items.valid("iron_sword@1") and w.objects.transfer(chest,1,"unknown@2",1) == 0, "Noncanonical stack key accepted")
	w.objects.add(2, "cloth_robe@2", 1)
	w.command({"kind":"equip", "actor":2, "item":"cloth_robe@2"})
	var state: Dictionary = Persistence.capture(w)
	var loaded: RefCounted = Persistence.candidate(state, 0)
	check.call(loaded != null and loaded.pages[0].move_speed[0] == 6.0 and loaded.pages[0].armor[1] == 4 and loaded.objects.records[2].equipment.get("body", "") == "cloth_robe@2", "Restore did not rebuild gear-derived stats")
	if loaded != null:
		var robes: int = loaded.objects.audit_total("cloth_robe@2")
		check.call(loaded.remove_actor(2) and loaded.objects.audit_total("cloth_robe@2") == robes, "Actor removal discarded worn gear")
		var born: int = loaded.spawn_actor(145 * 512 + 147)
		var slot: int = loaded.actor_slots[born]
		check.call(loaded.pages[slot / 256].armor[slot % 256] == 0 and loaded.pages[slot / 256].max_health[slot % 256] == 100, "Reused body kept previous gear stats")
	state.domains.objects.records[1].equipment["feet"] = "iron_sword"
	check.call(Persistence.candidate(state, 0) == null and w.objects.records[1].equipment.get("feet", "") == "travel_boots", "Invalid worn slot damaged live world")
