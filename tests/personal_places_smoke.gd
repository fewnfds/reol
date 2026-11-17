extends "res://tests/abilities_smoke.gd"
const Opening = preload("res://scripts/sim/scenarios/settlement_opening.gd")
const SETUP = preload("res://data/openings/qinghe_sect.tres")

func personal_place_retention() -> void:
	var w := World.new()
	check(w.initialize(100, 0, false, "empty") and Opening.assemble(w, SETUP).is_empty(), "Normal opening failed before personal-place checks")
	for resident: int in range(2, 101):
		var allocated: Array = w.institutions.Access.service_targets(w.institutions, resident).get("rest", [])
		check(allocated.size() == 1 and w.livelihood.protected_targets(w, resident).has(int(allocated[0])), "Normal resident did not start with acquired personal-place evidence: " + str(resident))
	var actor: int = 97
	var bed: int = int(w.institutions.Access.service_targets(w.institutions, actor).rest[0])
	var original: Dictionary = w.knowledge.records[actor].subjects[bed].duplicate(true)
	# The original scenario knew the bed; seeing it makes provenance more current.
	w.knowledge.records[actor].subjects[bed].merge({"origin": "seen", "observer": actor, "source": actor}, true)
	var targets: Array = w.objects.records.keys().filter(func(id: int): return int(w.objects.records[id].tile) >= 0 and w.objects.records[id].kind == "bed" and id != bed)
	for index: int in 40:
		var target: int = w.facilities.create_completed(w, "wood_bed", w.Terrain.index(Vector2i(250 + index % 10 * 3, 250 + index / 10 * 3)))
		w.objects.records[target].organization = 1
		targets.append(target)
	w.flush_topology()
	for target: int in targets:
		var value: Dictionary = w.knowledge._public_value(w.operation_target(target))
		w.knowledge._store(w, actor, value, "seen", actor, actor, 0, 0, 0)
	check(w.knowledge.records[actor].subjects.size() == 128 and not w.knowledge.view(actor, bed, 0).is_empty(), "Unrelated observed beds evicted the resident's acquired personal allocation")
	check(w.livelihood.protected_targets(w, actor).has(bed), "The known personal rest place was not protected while unrelated purposes were current")
	var subjects: Dictionary = w.knowledge.records[actor].subjects
	subjects.erase(bed)
	check(not w.livelihood.protected_targets(w, actor).has(bed) and w.knowledge.view(actor, bed, 0).is_empty(), "Assignment manufactured knowledge of an already forgotten bed")
	subjects[bed] = original.duplicate(true)
	subjects[bed].origin = "heard"
	check(not w.livelihood.protected_targets(w, actor).has(bed), "An unverified rumor acquired permanent personal-place priority")
	subjects[bed] = original.duplicate(true)
	subjects[bed].view.tile = -1
	check(not w.livelihood.protected_targets(w, actor).has(bed), "An observed absent place retained personal allocation priority")
	subjects[bed] = original.duplicate(true)
	var before: PackedByteArray = var_to_bytes(subjects[bed])
	check(w.institutions.clear_service(w, bed, "rest"), "Original service owner could not revoke a personal allocation")
	check(not w.livelihood.protected_targets(w, actor).has(bed) and var_to_bytes(subjects[bed]) == before, "Revoking an allocation either kept its priority or rewrote old personal evidence")
	check(w.institutions.arrange_service(w, bed, "rest", [], true), "Personal place could not become a communal service")
	check(not w.livelihood.protected_targets(w, actor).has(bed), "A communal facility was silently promoted to a personal allocation")
	check(w.institutions.arrange_service(w, bed, "rest", [actor]), "Personal allocation could not be restored")
	# Exceeding capacity still evicts oldest equal-priority evidence; retaining
	# allocations is a preference, not an unbounded second memory store.
	for target: int in targets:
		check(w.institutions.arrange_service(w, target, "rest", [actor]), "Personal-allocation stress setup failed")
		w.knowledge._store(w, actor, w.knowledge._public_value(w.operation_target(target)), "seen", actor, actor, 0, 0, 0)
	check(w.knowledge.records[actor].subjects.size() <= 128, "Personal allocations made acquired knowledge unbounded")
	# Start from the acquired bed again and let the real planner/host restore
	# energy, without directly invoking rest or changing the worker controller.
	w.knowledge.records[actor].subjects.clear()
	w.knowledge.records[actor].subjects[bed] = original.duplicate(true)
	w.livelihood.record(w, actor).intention = {}
	w.pages[0].energy[actor - 1] = 1000
	w.decisions.wake(w, actor, 0, "needs_changed")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Important acquired places failed actual recovery")
	if restored == null: return
	w = restored
	while w.elapsed_ms < 60000 and w.pages[0].energy[actor - 1] < 2000: w.step(250)
	check(w.pages[0].energy[actor - 1] >= 2000 and w.activity_results.view(actor).any(func(result: Dictionary): return result.operation == "rest" and result.status == "completed" and int(result.facts.get("energy_restored", 0)) > 0), "The normal autonomous resident did not actually return to its known bed and rest")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "The actual completed rest failed recovery")

func _run() -> void:
	personal_place_retention()
	print("PERSONAL_PLACES_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
