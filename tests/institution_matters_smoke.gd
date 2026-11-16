extends "res://tests/institution_access_smoke.gd"

func commission_fixture() -> Dictionary:
	var w: RefCounted = peaceful()
	var org: int = w.institutions.create("青禾宗")
	w.institutions.admit(w, org, 1, Array(w.institutions.PURPOSES))
	for actor: int in [3, 4]:
		w.institutions.admit(w, org, actor, [])
		move_actor(w, actor, Vector2(123.5, 120.5))
		w.pages[0].energy[actor - 1] = 10000; w.pages[0].hunger[actor - 1] = 10000
	move_actor(w, 1, Vector2(123.5, 120.5))
	var source: int = workshop(w, org, "wood_chest", Vector2i(125, 120))
	var destination: int = workshop(w, org, "wood_chest", Vector2i(130, 120))
	var stove: int = workshop(w, org, "cook_stove", Vector2i(127, 122))
	w.flush_topology()
	for target: int in [source, destination, stove]: w.knowledge.seed(w, 1, w.operation_target(target), 0)
	return {"world": w, "org": org, "source": source, "destination": destination, "stove": stove}

func delivery_spec(f: Dictionary, total: int = 4, quota: int = 2) -> Dictionary:
	return {"kind": "delivery", "organization": f.org, "target": f.destination, "item": "grain", "sources": [f.source], "total": total, "quota": quota}

func manual_transfer(w: RefCounted, actor: int, target: int, item: String, amount: int, handler: String, context: Dictionary = {}) -> Dictionary:
	var request: Dictionary = {"kind": handler, "target": target, "item": item, "amount": amount}
	request.merge(context, true)
	var tile: int = w.objects.records[target].tile
	move_actor(w, actor, Vector2(w.Terrain.cell(tile)) + Vector2(-0.5, 0.5))
	check(w.execute_operation(actor, request) == "accepted", "Manual shared transfer was not admitted: " + str(request))
	w.settle_action(actor, w.elapsed_ms)
	advance(w, w.elapsed_ms + 550)
	return w.activity_results.view(actor).back()

func partial_multi_actor_and_restore() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	w.objects.add(f.source, "grain", 8, Stock.right(0, f.org))
	var matter: int = w.institutions.create_matter(w, 1, delivery_spec(f))
	check(matter > 0 and w.institutions.shares.is_empty(), "Creation assigned a wireless obligation")
	var first: int = w.institutions.accept_share(w, 3, matter, 2)
	var second: int = w.institutions.accept_share(w, 4, matter, 2)
	check(first > 0 and second > 0 and w.institutions.accept_share(w, 2, matter, 1) == 0, "Shares oversold the remaining delivery")
	check(w.institutions.create_matter(w, 3, delivery_spec(f)) == 0, "A delegated execution permission minted commissioning authority")
	manual_transfer(w, 3, f.source, "grain", 1, "take", {"purpose": "supply"})
	var result: Dictionary = manual_transfer(w, 3, f.destination, "grain", 1, "put")
	check(w.institutions.shares[first].fulfilled == 1 and w.institutions.shares[second].fulfilled == 0, "Actual partial manual delivery did not credit its obligor")
	w.institutions.outcome(w, result)
	check(w.institutions.shares[first].fulfilled == 1, "Replayed result credited the same delivery twice")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Partial multi-actor obligation could not restore")
	if restored == null: return
	w = restored
	check(w.institutions.revise_matter(w, 1, matter, 5, 1, w.elapsed_ms + 10000) and w.institutions.shares[first].quota == 2 and w.institutions.shares[first].deadline_ms == 0, "Revision silently changed previously accepted terms")
	manual_transfer(w, 3, f.source, "grain", 1, "take", {"purpose": "supply"})
	manual_transfer(w, 3, f.destination, "grain", 1, "put")
	manual_transfer(w, 4, f.source, "grain", 2, "take", {"purpose": "supply"})
	manual_transfer(w, 4, f.destination, "grain", 2, "put")
	check(w.institutions.shares[first].state == "completed" and w.institutions.shares[second].fulfilled == 2 and w.objects.amount(f.destination, "grain") == 4, "Two people failed exact cumulative fulfilment")
	var state: Dictionary = Persistence.capture(w)
	state.domains.institutions.shares[first].fulfilled = 3
	check(Persistence.candidate(state, 0) == null and Persistence.candidate(Persistence.capture(w), 0) != null, "Overfulfilled bad candidate did not reject atomically")

func direct_contact_autonomous_production() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	resident(w, 4, [])
	w.objects.add(f.source, "grain", 2, Stock.right(0, f.org)); w.objects.add(f.source, "water", 1, Stock.right(0, f.org))
	w.objects.add(f.stove, "meal", 2, Stock.right(0, f.org))
	var matter: int = w.institutions.create_matter(w, 1, {"kind": "produce", "organization": f.org, "target": f.stove, "operation": "cook", "item": "meal", "sources": [f.source], "total": 3, "quota": 3})
	check(matter > 0 and not w.operation_actor(4).responsibilities.has(matter), "Production was accepted before contact")
	check(w.execute_operation(1, {"kind": "offer_matter", "target": 4, "matter": matter}) == "accepted", "Actual matter offer did not enter the common contact host")
	w.settle_action(1, 0)
	advance(w, 1500)
	check(not w.institutions.shares.is_empty() and w.activity_results.view(1).back().reason == "accepted_share", "On-site interaction did not actually convey/accept the terms")
	advance(w, 16000)
	check(w.institutions.matters[matter].state == "completed" and w.objects.amount(f.stove, "meal") == 5 and w.objects.amount(f.source, "grain") == 0, "Accepted production fetched ready-made meals instead of actually cooking new output: " + str({"matter": w.institutions.matters[matter], "purpose": w.livelihood.describe(4), "pot": w.objects.records[f.stove]}))
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Completed contact/production references did not restore")

func declared_purpose_at_real_sources() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	var plant: int = w.nature.create(w, "annual_grass", w.Terrain.index(Vector2i(127, 119)), false, true)
	w.objects.records[plant].organization = f.org; w.objects.records[plant].stage = w.nature.Stage.MATURE
	w.objects.add(plant, "grain", 3, Stock.right(0, f.org))
	w.knowledge.seed(w, 1, w.operation_target(plant), 0)
	resident(w, 4, [plant, f.destination])
	var spec: Dictionary = delivery_spec(f, 2, 2); spec.sources = [plant]
	var matter: int = w.institutions.create_matter(w, 1, spec)
	check(matter > 0 and w.institutions.accept_share(w, 4, matter) > 0, "Real plant-source transport terms refused")
	w.decisions.prepare(w, 0); advance(w, 10000)
	check(w.institutions.matters[matter].state == "completed" and w.objects.amount(f.destination, "grain") == 2 and w.objects.amount(plant, "grain") == 1, "Gathering for delivery used an incompatible material mandate instead of the declared lawful purpose")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Declared-purpose source collection did not restore")

func _run() -> void:
	partial_multi_actor_and_restore()
	direct_contact_autonomous_production()
	declared_purpose_at_real_sources()
	print("INSTITUTION_MATTERS_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
