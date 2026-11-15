extends "res://tests/abilities_smoke.gd"
## World work and ACT use one admission boundary and chronological commit path.
func timed_transfer(hit_at: int, due: int) -> RefCounted:
	var w: RefCounted = fixture()
	var source: int = w.source_objects[0]
	w.pages[0].positions[0] = w.Terrain.center(w.objects.records[source].tile)
	check(w.begin_transfer(1, {"kind": "take", "target": source, "item": "wood", "amount": 1}) == "accepted", "Transfer not admitted")
	w.settle(1, 0)
	w.pages[0].due_ms[0] = due
	var origin: Vector2 = w.pages[0].positions[0] - Vector2(0.45 + 22.0 * hit_at / 1000, 0)
	w.combat.launch(2, origin, w.pages[0].positions[0], 0, 10000)
	return w

func chronological() -> void:
	var earlier: RefCounted = timed_transfer(20, 40)
	earlier.step(50)
	check(not earlier.combat.alive(earlier, 1) and earlier.objects.amount(1, "wood") == 0, "Earlier fatal contact allowed later work to finish")
	var later: RefCounted = timed_transfer(40, 20)
	later.step(50)
	check(not later.combat.alive(later, 1) and later.objects.amount(1, "wood") == 1, "Later death erased an earlier delivery")
	var newborn: RefCounted = fixture()
	var target: int = newborn.source_objects[0]
	newborn.pages[0].positions[0] = newborn.Terrain.center(newborn.objects.records[target].tile)
	newborn.begin_transfer(1, {"kind": "take", "target": target, "item": "wood", "amount": 1})
	newborn.step(400)
	check(newborn.objects.amount(1, "wood") == 1 and not newborn.actions.has(1), "Arrival-created process deadline missed its interval")

func tending() -> void:
	var w: RefCounted = fixture("tender")
	var target: int = w.nature.create(w, "perennial_herb", w.Terrain.index(Vector2i(122, 122)), false, true)
	check(target > 0, "Plant fixture failed")
	if target == 0: return
	w.objects.records[target].injury_ms = 90000
	w.pages[0].positions[0] = Vector2(121.5, 122.5)
	var water: int = w.objects.amount(1, "water")
	check(w.begin_interaction(1, {"kind": "tend", "target": target}) == "accepted", "Manual tending rejected")
	w.step(1900) # Enter the plant's own work cell before its 1500ms labour.
	check(w.objects.amount(1, "water") == water - 1 and w.objects.records[target].injury_ms < 35000, "Manual domain operation did not conserve water")
	w.objects.records[target].injury_ms = 90000
	check(w.combat.request(w, 1, "skill", Vector2.RIGHT, Vector2.ZERO, -1, Vector2(-1, -1), target) == "started", "Selected-plant ACT tending rejected")
	check(w.objects.amount(1, "water") == water - 1, "Water paid before effective domain commit")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "In-progress domain cast rejected on restore")
	w.step(500)
	if restored != null: restored.step(500)
	check(w.objects.amount(1, "water") == water - 2 and w.objects.records[target].injury_ms < 35000, "ACT did not share tending operation")
	check(restored != null and restored.objects.amount(1, "water") == w.objects.amount(1, "water"), "Restored cast paid zero or twice")

func _run() -> void:
	chronological()
	tending()
	print("ACTION_DOMAINS_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
