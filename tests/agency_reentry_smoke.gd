extends "res://tests/agency_food_smoke.gd"
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")

func unknown_store_return() -> void:
	var w: RefCounted = peaceful()
	var org: int = w.institutions.create("青禾宗")
	w.institutions.admit(w, org, 4, ["take", "put", "supply"])
	move_actor(w, 4, Vector2(123.5, 120.5))
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(125, 120)))
	w.objects.records[chest].organization = org
	w.objects.add(chest, "wood", 1, Stock.right(0, org))
	check(w.institutions.move_goods(w, 4, chest, "wood", 1, "take", {"purpose": "supply"}, 0).status == "completed", "Unknown-return fixture issue refused")
	w.institutions.admit(w, org, 4, [])
	resident(w, 4, [])
	var clue: Dictionary = w.operation_target(chest)
	clue.erase("inventory"); clue.erase("contents")
	w.knowledge.seed(w, 4, clue, 0)
	w.pages[0].hunger[3] = 10000; w.pages[0].energy[3] = 10000
	w.flush_topology(); w.decisions.prepare(w, 0)
	advance(w, 4500)
	check(w.knowledge.view(4, chest, w.elapsed_ms).has("inventory"), "Visible inspection waited for the periodic observation")
	check(w.objects.amount(chest, "wood") == 1 and w.institutions.returns(w, 4).is_empty(), "Unknown return store did not inspect and return actual stock")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Inspection/return left invalid goal or task reference")

func private_book_in_public_custody() -> void:
	var w: RefCounted = peaceful()
	var org: int = w.institutions.create("青禾宗")
	w.institutions.admit(w, org, 4, ["take", "put"])
	move_actor(w, 4, Vector2(123.5, 120.5))
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(125, 120)))
	w.objects.records[chest].organization = org
	w.objects.add(chest, "breath_manual", 1, Stock.right(4))
	w.flush_topology(); resident(w, 4, [chest])
	w.pages[0].hunger[3] = 10000; w.pages[0].energy[3] = 10000
	w.livelihood.add_goal(w, 4, "development", {"method": "wood_breath"})
	w.decisions.prepare(w, 0)
	advance(w, 6000)
	check(w.objects.amount(4, "breath_manual", Stock.right(4)) == 1 and w.objects.records[4].get("methods", {}).get("wood_breath", {}).get("understanding", 0) >= 200, "A private deposited book was incorrectly issued as public study material")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Private deposited learning lost restoration")

func competing_material_purposes() -> void:
	var w: RefCounted = peaceful()
	var org: int = w.institutions.create("青禾宗")
	w.institutions.admit(w, org, 4, Array(w.institutions.PURPOSES))
	move_actor(w, 4, Vector2(123.5, 120.5))
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(125, 120)))
	var stove: int = w.facilities.create_completed(w, "cook_stove", w.Terrain.index(Vector2i(127, 122)))
	for target: int in [chest, stove]: w.objects.records[target].organization = org
	w.objects.add(chest, "grain", 2, Stock.right(0, org))
	w.flush_topology(); resident(w, 4, [chest, stove])
	w.pages[0].hunger[3] = 1500; w.pages[0].energy[3] = 10000
	var transfers: int = w.objects.transfers
	w.livelihood.add_goal(w, 4, "delivery", {"item": "grain", "amount": 2, "organization": org})
	w.decisions.prepare(w, 0)
	advance(w, 14000)
	check(w.objects.transfers - transfers <= 1 and w.objects.amount(4, "grain") == 2, "Missing water made another goal return and reissue cooking grain: transfers=%d held=%d goals=%s" % [w.objects.transfers - transfers, w.objects.amount(4, "grain"), w.livelihood.describe(4)])
	check(w.facilities.completed.get("cook", 0) == 0 and Persistence.candidate(Persistence.capture(w), 0) != null, "Missing second ingredient was fabricated or corrupted state")

func _run() -> void:
	unknown_store_return()
	private_book_in_public_custody()
	competing_material_purposes()
	print("AGENCY_REENTRY_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
