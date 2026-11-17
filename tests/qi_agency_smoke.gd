extends "res://tests/qi_sources_smoke.gd"

func practitioner(w: RefCounted, actor: int, subjects: Array, qi: int = 0) -> void:
	w.objects.records[actor].base_stats = {"max_hp": 100.0}
	w.Equipment.rebuild(w, actor)
	w.pages[0].health[actor - 1] = 100
	w.Growth.seed(w.objects.records[actor], "wood_breath", w.elapsed_ms)
	w.objects.records[actor]["qi"] = qi
	w.pages[0].positions[actor - 1] = Vector2(123.5, 124.5)
	autonomous(w, actor, subjects)

func practice_results(w: RefCounted, actor: int) -> Array:
	return w.activity_results.view(actor).filter(func(result: Dictionary): return result.operation == "practice" and result.status == "completed")

func reserve_treatment_and_replenishment() -> void:
	var w: RefCounted = lesson_world()
	var tree: int = qi_source(w, "old_tree", Vector2i(124, 124), 1000)
	practitioner(w, 3, [tree], 2940)
	var initial_source: int = source_total(w)
	w.decisions.prepare(w, 0); advance(w, 8000)
	check(w.objects.records[3].qi == 3000 and practice_results(w, 3).size() == 1 and not w.actions.has(3), "Mastered practitioner did not replenish to full and stop")
	var damage: Dictionary = w.combat.damage(w, 0, 3, 40, w.elapsed_ms, Vector2.ZERO, 0, 0, 0.0, {"periodic": true})
	check(int(damage.get("damage", 0)) > 0 and int(w.decisions.records[3].next_ms) <= w.elapsed_ms + 50, "Real damage did not wake an idle autonomous person")
	advance(w, 10000)
	check(w.pages[0].health[2] == 100 and w.objects.records[3].qi < 3000, "Actual injury did not cause real self-treatment before replenishment")
	var heals: Array = w.activity_results.view(3).filter(func(result: Dictionary): return result.operation == "wood_mend" and result.status == "completed")
	check(heals.size() == 2 and int(heals[1].at_ms) - int(heals[0].at_ms) >= 500, "Payment/healing notifications caused same-tick instant repetitions")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Treatment-to-source workflow failed mid-process restoration")
	if restored != null: w = restored
	advance(w, 18000)
	check(w.objects.records[3].qi == 3000 and practice_results(w, 3).size() == 2, "Real qi consumption did not restart the shared reserve goal")
	var spent: int = 0
	for result: Dictionary in practice_results(w, 3): spent += int(result.facts.target_qi_spent)
	check(source_total(w) + spent == initial_source + int(w.nature.generated_qi), "All real natural qi sources and practice consumption did not balance")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Full reserve/resting workflow did not restore")

func empty_sources_second_source_and_recovery() -> void:
	var w: RefCounted = lesson_world()
	var first: int = qi_source(w, "old_tree", Vector2i(124, 124), 0)
	var second: int = qi_source(w, "spirit_bamboo", Vector2i(127, 124), 100)
	practitioner(w, 3, [first, second])
	w.decisions.prepare(w, 0); advance(w, 10000)
	check(practice_results(w, 3).size() == 1 and practice_results(w, 3)[0].target == second, "An empty first source hid the usable second source")
	check(w.livelihood.records[3].explore_count == 0 and not w.actions.has(3), "Known exhausted sources caused random exploration or useless practice")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Exhausted source waiting could not restore")
	if restored != null: w = restored
	advance(w, 65000)
	check(practice_results(w, 3).size() >= 2 and w.livelihood.records[3].explore_count == 0, "Naturally recovered source did not revive actual practice without random searching")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Recovered source/variant workflow failed restoration")

func unmet_body_and_no_magic() -> void:
	var w: RefCounted = lesson_world()
	var tree: int = qi_source(w, "spirit_bamboo", Vector2i(124, 124), 1000)
	autonomous(w, 3, [tree])
	w.decisions.prepare(w, 0); advance(w, 4000)
	check(not w.Growth.introduced(w.objects.records[3], "wood_breath") and practice_results(w, 3).is_empty() and w.livelihood.records[3].explore_count == 0, "Unintroduced person invented a qi desire or stole a method")
	w.Growth.seed(w.objects.records[3], "wood_breath", w.elapsed_ms)
	w.pages[0].hunger[2] = 3000
	w.decisions.wake(w, 3, w.elapsed_ms, "needs_changed")
	advance(w, 8000)
	check(practice_results(w, 3).is_empty(), "Reserve desire consumed scarce satiety before sustenance")
	# No magical method does not imply sleeping restores ordinary HP.
	var p: RefCounted = lesson_world()
	p.pages[0].health[2] -= 20
	autonomous(p, 3, [])
	p.decisions.prepare(p, 0); advance(p, 4000)
	check(not p.actions.has(3) and p.livelihood.records[3].explore_count == 0, "Unhealable HP loss created pointless sleep or random exploration")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Unready reserve goal failed restoration")

func small_deficits_and_unfinished_source_review() -> void:
	for amount: int in [2990, 2999]:
		var w: RefCounted = lesson_world()
		var tree: int = qi_source(w, "old_tree", Vector2i(124, 124), 1000)
		practitioner(w, 3, [tree], amount)
		w.decisions.prepare(w, 0); advance(w, 8000)
		check(w.objects.records[3].qi == 3000 and practice_results(w, 3).size() == 1, "Small positive reserve deficit was silently discarded: " + str(amount))
	var w: RefCounted = lesson_world()
	var tree: int = qi_source(w, "spirit_bamboo", Vector2i(124, 124), 0)
	w.Growth.seed(w.objects.records[3], "wood_breath", 0, false)
	w.objects.records[3].qi = 3000
	learner(w, 3)
	autonomous(w, 3, [tree])
	w.pages[0].positions[2] = Vector2(110.5, 124.5)
	w.sight.sync(w)
	var actor: Dictionary = w.livelihood._self_view(w, 3)
	check(w.livelihood.Planner.source_review_due(actor, w.knowledge.known(3, 0), 0) == 60000, "Full reserve hid unfinished mastery's source review")
	w.decisions.prepare(w, 0); advance(w, 10000)
	check(practice_results(w, 3).is_empty() and w.livelihood.records[3].explore_count == 0, "Empty remote source caused useless practice or random searching")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "A remote-source review could not restore")
	if restored != null: w = restored
	advance(w, 80000)
	check(practice_results(w, 3).size() > 0 and w.objects.records[3].methods.wood_breath.progress > 0, "Unfinished full-qi practitioner did not revisit an actually recovered remote source")

func source_loss_and_manual_interruption() -> void:
	var w: RefCounted = lesson_world()
	var tree: int = qi_source(w, "spirit_bamboo", Vector2i(124, 124), 1000)
	practitioner(w, 3, [tree], 2940)
	w.decisions.prepare(w, 0); advance(w, 700)
	check(w.actions.get(3, {}).get("kind") == "practice", "Source-loss fixture did not start actual practice")
	w.nature.remove(w, tree); w.flush_topology()
	advance(w, 8000)
	check(w.objects.records[3].qi == 2940 and practice_results(w, 3).is_empty() and not w.actions.has(3), "Disappeared source paid practice or stranded its host")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Deleted source history could not restore")
	var other: int = qi_source(w, "spirit_bamboo", Vector2i(124, 124), 1000)
	w.knowledge.seed(w, 3, w.operation_target(other), w.elapsed_ms)
	w.decisions.wake(w, 3, w.elapsed_ms, "needs_changed")
	advance(w, 8700)
	check(w.actions.get(3, {}).get("kind") == "practice", "Manual-interruption fixture did not begin practice")
	w.release(3); w.decisions.suspend(w, 3)
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Manually interrupted reserve workflow could not restore")
	if restored != null: w = restored
	advance(w, 14000)
	check(w.objects.records[3].qi == 2940 and practice_results(w, 3).is_empty() and not w.actions.has(3), "Reserve review seized manual control after interruption or restoration")
	w.decisions.resume(w, 3, w.elapsed_ms); advance(w, 22000)
	check(w.objects.records[3].qi == 3000 and practice_results(w, 3).size() == 1, "Resuming autonomy did not re-enter real practice exactly once")

func _run() -> void:
	reserve_treatment_and_replenishment()
	empty_sources_second_source_and_recovery()
	unmet_body_and_no_magic()
	small_deficits_and_unfinished_source_review()
	source_loss_and_manual_interruption()
	print("QI_AGENCY_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
