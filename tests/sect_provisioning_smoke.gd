extends "res://tests/cultivation_duties_smoke.gd"
## A small World consumer of the production workflow, not a separate scene or
## simulation. Time and movement still use World's ordinary boundaries.
var adopted: Dictionary = {}
var consumed: Dictionary = {}
var last_result: int = 0

func account(w: RefCounted) -> void:
	for id: int in w.activity_results.records:
		if id <= last_result: continue
		var result: Dictionary = w.activity_results.records[id]
		if result.status != "completed": continue
		adopted[result.operation] = int(adopted.get(result.operation, 0)) + 1
		for item: String in result.facts.get("consumed", {}): consumed[item] = int(consumed.get(item, 0)) + int(result.facts.consumed[item])
	last_result = w.activity_results.next_id - 1

func settlement() -> Dictionary:
	var w := World.new()
	w.initialize(8, 0)
	for actor: int in w.actor_slots:
		w.release(actor)
		w.objects.records[actor].autonomous = false
		w.objects.records[actor].side = 0
		w.pages[0].modes[actor - 1] = w.Units.Mode.IDLE
		w.pages[0].hunger[actor - 1] = 8000
		w.pages[0].energy[actor - 1] = 8000
		move_actor(w, actor, Vector2(122.5 + actor % 4, 120.5 + actor / 4))
		for right: Dictionary in w.objects.groups(actor):
			if int(right.owner) != actor: continue
			for item: String in ["grain", "water", "meal"]:
				var amount: int = w.objects.amount(actor, item, right)
				if amount > 0: w.objects.consume(actor, {item: amount}, right)
	w.livelihood.records.clear()
	w.knowledge.records.clear()
	w.activity_results = Results.new()
	var org: int = w.institutions.create("青禾宗")
	for actor: int in w.actor_slots: check(w.institutions.admit(w, org, actor, ["eat", "rest"]), "Resident admission failed")
	var store: int = workshop(w, org, "granary", Vector2i(122, 123))
	var well: int = workshop(w, org, "water_well", Vector2i(120, 125))
	var stove: int = workshop(w, org, "cook_stove", Vector2i(124, 123))
	var meals: int = workshop(w, org, "wood_chest", Vector2i(126, 123))
	var board: int = workshop(w, org, "notice_desk", Vector2i(122, 120))
	check(w.institutions.arrange_service(w, meals, "eat", [], true), "Public food service failed")
	var sites: Array = []
	for index: int in 6: sites.append(workshop(w, org, "cultivation_bed", Vector2i(123 + index % 3 * 3, 127 + index / 3 * 3)))
	var places: Array = sites + [store, well, stove, meals, board]
	for actor: int in range(2, 9):
		var bed: int = workshop(w, org, "wood_bed", Vector2i(116, 118 + actor * 2))
		check(w.institutions.arrange_service(w, bed, "rest", [actor]), "Resident bed arrangement failed")
		places.append(bed)
	w.objects.add(store, "grain", 6, Stock.right(0, org)) # Exactly the six initial seeds.
	w.objects.add(meals, "meal", 12, Stock.right(0, org)) # Finite transition meals; no recurring injection.
	w.flush_topology()
	for actor: int in range(2, 9): resident(w, actor, places)
	for actor: int in [2, 3]:
		var fields: Array = sites.slice(0, 3) if actor == 2 else sites.slice(3, 6)
		check(w.institutions.appoint(w, org, actor, "field_cultivator", fields + [store, well], {"sites": fields, "sources": [store, well], "destination": store}) > 0, "Field assignment failed")
	check(w.institutions.appoint(w, org, 4, "kitchen_steward", [store, well, stove, board], {"target": stove, "sources": [store, well], "channel": board}) > 0, "Kitchen stewardship failed")
	check(w.institutions.appoint(w, org, 4, "meal_steward", [stove, meals, board], {"target": meals, "sources": [stove], "channel": board}) > 0, "Food service stewardship failed")
	Growth.seed(w.objects.records[5], "cooking", 0, false)
	Growth.seed(w.objects.records[6], "cooking", 0, false)
	return {"world": w, "org": org, "store": store, "well": well, "stove": stove, "meals": meals, "board": board, "sites": sites}

func cycle() -> void:
	var f: Dictionary = settlement()
	var w: RefCounted = f.world
	var initial: Dictionary = {}
	for item: String in ["grain", "water", "meal"]: initial[item] = w.objects.audit_total(item)
	w.decisions.prepare(w, 0)
	var start: int = Time.get_ticks_msec()
	var end: int = w.environment.DAY_MS * 3
	var resumed: bool = false
	while w.elapsed_ms < end:
		w.step(mini(250, end - w.elapsed_ms))
		account(w)
		if not resumed and w.elapsed_ms >= w.environment.DAY_MS + 17000:
			var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
			check(restored != null, "Actual field/food society did not restore after its first day")
			if restored != null: w = restored; f.world = restored
			resumed = true
		if w.elapsed_ms % w.environment.DAY_MS == 0:
			print("SECT_CYCLE ", {"day": w.elapsed_ms / w.environment.DAY_MS, "generated": w.nature.generated_items, "store": w.objects.inventory_summary(f.store), "food": w.objects.amount(f.meals, "meal"), "adopted": adopted, "hunger": w.pages[0].hunger})
	var generated_water: int = 0
	for source: int in w.facilities.sources: generated_water += int(w.objects.records[source].source_generated)
	check(w.objects.audit_total("grain") + int(consumed.get("grain", 0)) == int(initial.grain) + int(w.nature.generated_items.get("grain", 0)), "Real grain source/conversion audit did not balance")
	check(w.objects.audit_total("water") + int(consumed.get("water", 0)) == int(initial.water) + generated_water, "Real water source/conversion audit did not balance")
	check(w.objects.audit_total("meal") + int(consumed.get("meal", 0)) == int(initial.meal) + int(adopted.get("cook", 0)) * 3, "Cooking and eating did not balance")
	for operation: String in ["sow_grain", "draw_water", "tend", "gather", "put", "cook", "eat", "rest"]: check(int(adopted.get(operation, 0)) > 0, "Autonomous three-day workflow missed actual operation: " + operation)
	check(int(w.nature.generated_items.get("grain", 0)) > 6 and int(adopted.get("cook", 0)) > 1, "Settlement never repeated actual renewable supply and processing")
	for actor: int in range(2, 9): check(w.combat.alive(w, actor) and w.pages[0].hunger[actor - 1] > 1800, "An autonomous resident ended hungry/dead: " + str(actor) + " " + str(w.livelihood.describe(actor)))
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Final field/food workflows did not restore")
	print("SECT_PROVISIONING_SMOKE errors=", errors, " wall_ms=", Time.get_ticks_msec() - start, " adopted=", adopted, " consumed=", consumed)

func _run() -> void:
	cycle()
	quit(0 if errors == 0 else 1)
