extends "res://tests/qi_agency_smoke.gd"

func small_food_retains_public_inputs() -> void:
	var w: RefCounted = lesson_world()
	var org: int = w.institutions.create("青禾宗")
	check(w.institutions.admit(w, org, 3, ["take", "put", "cook", "eat"]), "Small-need cooking membership failed")
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(122, 124)))
	var stove: int = w.facilities.create_completed(w, "cook_stove", w.Terrain.index(Vector2i(126, 124)))
	for target: int in [chest, stove]: w.objects.records[target].organization = org
	check(w.institutions.arrange_service(w, stove, "eat", [], true), "Cooked food was not available as a real member service")
	w.objects.add(chest, "grain", 2, w.objects.Stock.right(0, org))
	w.objects.add(chest, "water", 1, w.objects.Stock.right(0, org))
	w.pages[0].positions[2] = Vector2(123.5, 124.5)
	w.pages[0].hunger[2] = 6990
	w.flush_topology(); autonomous(w, 3, [chest, stove]); w.decisions.prepare(w, 0)
	advance(w, 20000)
	check(int(w.facilities.completed.get("cook", 0)) == 1 and w.pages[0].hunger[2] >= 7000, "Small food need failed to retain public cooking inputs: " + str({"results": w.activity_results.view(3), "decision": w.livelihood.latest.get(3), "carried": w.objects.inventory_summary(3), "hunger": w.pages[0].hunger[2]}))
	var returns: Array = w.activity_results.view(3).filter(func(result: Dictionary): return result.operation == "put" and result.status == "completed")
	check(returns.is_empty(), "Small food need repeatedly returned its needed ingredients")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Small-need public cooking could not restore")

func ordinary_learning_still_explores() -> void:
	var w: RefCounted = lesson_world()
	var tree: int = qi_source(w, "spirit_bamboo", Vector2i(124, 124), 0)
	w.Growth.seed(w.objects.records[3], "cooking", 0, false)
	learner(w, 3, "cooking"); autonomous(w, 3, [tree])
	w.decisions.prepare(w, 0); advance(w, 800)
	check(w.livelihood.records[3].explore_count > 0, "Knowing a qi source suppressed ordinary cooking exploration")

func external_activity_resumes_autonomy() -> void:
	var w: RefCounted = lesson_world()
	var tree: int = qi_source(w, "old_tree", Vector2i(124, 124), 1000)
	practitioner(w, 3, [tree])
	w.pages[0].health[2] = 60
	check(w.command({"actor": 3, "kind": "practice", "target": tree}).ok, "External one-off practice command was refused")
	advance(w, 9000)
	check(w.pages[0].health[2] == 100, "One-off practice completed without returning to the person's own treatment goal")
	var practice: Array = practice_results(w, 3)
	var healed: Array = w.activity_results.view(3).filter(func(result: Dictionary): return result.operation == "wood_mend" and result.status == "completed")
	check(not practice.is_empty() and not healed.is_empty() and int(healed[0].at_ms) - int(practice[0].at_ms) >= 500, "Externally initiated activity bypassed the shared after-action pacing")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Externally initiated then autonomous workflow failed recovery")

func qi_schema_ownership() -> void:
	var w: RefCounted = lesson_world()
	var tree: int = qi_source(w, "spirit_bamboo", Vector2i(124, 124), 1000)
	var saved: Dictionary = Persistence.capture(w)
	var bad: Dictionary = saved.duplicate(true)
	bad.domains.objects.records[3]["qi_carry"] = 10
	check(Persistence.candidate(bad, 0) == null, "Source-only qi carry was accepted on a person")
	bad = saved.duplicate(true)
	bad.domains.objects.records[w.depot_objects[0]]["qi"] = 100
	check(Persistence.candidate(bad, 0) == null, "A building was accepted as a natural qi reservoir")
	# Growth validates a plant's method history; the Nature owner validates its
	# configured capacity. The actor ceiling cannot reject a larger reservoir.
	var detached: Dictionary = w.objects.records[tree].duplicate(true)
	detached.qi = 3500
	check(w.Growth.valid_record(detached, w.objects.next_id, w.elapsed_ms), "The actor qi ceiling leaked into the plant's growth validator")
	bad = saved.duplicate(true); bad.domains.objects.records[tree].qi = 3500
	check(Persistence.candidate(bad, 0) == null, "Nature did not enforce this actual species' lower reservoir capacity")

func partner_cancel_and_manual_wake() -> void:
	var w: RefCounted = lesson_world()
	learner(w, 3)
	w.livelihood.add_goal(w, 2, "instruction", {"method": "wood_breath", "target": 3})
	w.objects.records[2].autonomous = true
	w.decisions.resume(w, 2, 0)
	check(w.execute_operation(3, {"kind": "learn", "target": 2}) == "accepted", "Partner cancellation fixture could not approach")
	w.settle_action(3, 0)
	check(w.society.waits.has(2), "Actual lesson did not hold its teacher partner")
	w.release(3)
	check(not w.society.waits.has(2) and w.gate.current(2).is_empty() and w.decisions.records[2].next_ms >= 0, "Host cancellation failed to release and wake the autonomous partner")
	w.decisions.suspend(w, 2)
	w.livelihood.think(w, 2, 0); w.livelihood.after_action(w, 2, 0)
	check(w.decisions.records[2].next_ms == -1 and not w.decisions.wakeups.has(2), "Life entry points added a useless wake to a suspended controller")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Cancelled partnership/manual controller could not restore")

func _run() -> void:
	small_food_retains_public_inputs()
	ordinary_learning_still_explores()
	external_activity_resumes_autonomy()
	qi_schema_ownership()
	partner_cancel_and_manual_wake()
	print("QI_REFINEMENT_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
