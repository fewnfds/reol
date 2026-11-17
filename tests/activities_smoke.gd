extends "res://tests/abilities_smoke.gd"
const Results = preload("res://scripts/sim/kernel/activity_results.gd")

func peaceful() -> RefCounted:
	var w: RefCounted = fixture()
	for id: int in w.actor_slots: w.objects.records[id].side = 0
	w.activity_results = Results.new() # Exclude fixture setup's canceled starter work.
	return w

func latest(w: RefCounted, actor: int) -> Dictionary:
	var entries: Array = w.activity_results.view(actor)
	return entries.back() if not entries.is_empty() else {}

func transfers() -> void:
	var w: RefCounted = peaceful()
	var tile: int = w.Terrain.index(Vector2i(124, 124))
	var pile: int = w.objects.create("pile", "wood", tile)
	w.objects.add(pile, "wood", 5)
	w.objects.records[1].capacity = w.objects.count_inventory(1) + 2
	w.pages[0].positions[0] = Vector2(124.5, 124.5)
	check(w.begin_transfer(1, {"kind": "take", "target": pile, "item": "wood", "amount": 5}) == "accepted", "Partial transfer refused")
	advance(w, 1000)
	var outcome: Dictionary = latest(w, 1)
	check(outcome.get("status") == "completed" and outcome.facts.amount == 2 and outcome.facts.requested == 5 and w.objects.amount(pile, "wood") == 3, "Result reported requested rather than actual goods")
	w.objects.records[1].capacity = -1
	w.pages[0].positions[1] = Vector2(124.5, 124.5)
	check(w.begin_transfer(1, {"kind": "take", "target": pile, "item": "wood", "amount": 3}) == "accepted" and w.begin_transfer(2, {"kind": "take", "target": pile, "item": "wood", "amount": 3}) == "accepted", "Concurrent transfer fixture refused")
	var run_a: int = w.actions[1].run_id
	var run_b: int = w.actions[2].run_id
	advance(w, 2000)
	check(not w.objects.records.has(pile) and latest(w, 1).run_id == run_a and latest(w, 1).status == "completed" and latest(w, 2).run_id == run_b and latest(w, 2).reason == "target_gone", "Same-time deletion swallowed or duplicated actual outcomes")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Deleted historical target invalidated a legal save")

func construction_handoff() -> void:
	var w: RefCounted = peaceful()
	w.objects.claim(w.source_objects[0], 1, "wood", 4)
	var placement: Dictionary = w.facilities.blueprint(w, 1, "wood_wall", w.Terrain.index(Vector2i(126, 126)))
	check(placement.reason == "accepted", "Construction fixture failed")
	if placement.reason != "accepted": return
	var target: int = placement.target
	w.objects.records[target].remaining_ms = 2000
	w.pages[0].positions[0] = Vector2(125.5, 126.5)
	var wood: int = w.objects.audit_total("wood")
	check(w.begin_interaction(1, {"kind": "construct", "target": target}) == "accepted", "First builder refused")
	advance(w, 16)
	var started: int = w.actions[1].started_ms
	advance(w, started + 700)
	w.end_run(1, w.elapsed_ms, "preempted")
	var first: Dictionary = latest(w, 1)
	check(first.status == "interrupted" and first.facts.worked_ms == 700 and w.objects.records[target].remaining_ms == 1300, "Interrupted labor was lost, doubled or mislabeled complete")
	w.pages[0].positions[1] = Vector2(125.5, 126.5)
	check(w.begin_interaction(2, {"kind": "construct", "target": target}) == "accepted", "Replacement builder refused")
	advance(w, w.elapsed_ms + 350)
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "In-progress handoff rejected at restore")
	if restored == null: return
	var until: int = w.elapsed_ms + 2000
	advance(w, until)
	advance(restored, until)
	var second: Dictionary = latest(w, 2)
	check(w.objects.records[target].kind == "wall" and second.status == "completed" and second.facts.worked_ms == 1300 and second.facts.remaining_ms == 0, "Replacement repeated the old contribution")
	check(w.objects.audit_total("wood") == wood and restored.objects.audit_total("wood") == wood and restored.activity_results.records == w.activity_results.records, "Restore replayed materials or changed terminal evidence")
	var count: int = w.activity_results.next_id
	w.end_run(2, w.elapsed_ms, "completed")
	check(w.activity_results.next_id == count, "Second terminal callback published twice")

func social_participation() -> void:
	var w: RefCounted = peaceful()
	check(w.begin_interaction(1, {"kind": "learn", "target": 2}) == "accepted" and w.society.waits.has(2), "Invitation fixture refused")
	w.end_run(1, 0, "path_failed")
	check(latest(w, 1).participants == [1] and w.activity_results.view(2).is_empty(), "Distant invitation became attendance: " + str(w.activity_results.records))
	w.pages[0].positions[0] = Vector2(122.5, 120.5)
	check(w.begin_interaction(1, {"kind": "learn", "target": 2}) == "accepted", "Actual teaching fixture refused")
	advance(w, 16)
	check(w.actions[1].participants == [1, 2] and w.activity_view(1).phase == "acting", "In-place participation not adopted by the original host")
	w.kill(2, w.elapsed_ms)
	var outcome: Dictionary = latest(w, 1)
	check(outcome.reason == "target_gone" and outcome.participants == [1, 2] and latest(w, 2).id == outcome.id and w.society.waits.is_empty(), "Partner death published two results or lost actual participation")
	check(not w.objects.records[1].get("methods", {}).has("wood_breath"), "Interrupted teaching granted its final effect")
	var busy: RefCounted = peaceful()
	busy.pages[0].positions[0] = Vector2(122.5, 120.5)
	busy.decisions.suspend(busy, 2)
	busy.adopt_work(2, 0)
	busy.pages[0].modes[1] = busy.Units.Mode.REST
	busy.pages[0].due_ms[1] = 10000
	var stock: Dictionary = busy.objects.records[2].stock.duplicate(true)
	check(busy.begin_interaction(1, {"kind": "trade", "target": 2}) == "accepted", "Busy contact request was not accepted for on-site review")
	advance(busy, 1200)
	check(latest(busy, 1).reason == "target_busy" and latest(busy, 1).participants == [1] and busy.objects.records[2].stock == stock and busy.activity_results.view(2).is_empty(), "Busy partner was traded with unilaterally")
	var tree_world: RefCounted = peaceful()
	var tree: int = tree_world.nature.create(tree_world, "old_tree", tree_world.Terrain.index(Vector2i(124, 124)))
	check(tree > 0, "Static teacher fixture failed")
	if tree > 0:
		tree_world.objects.records[tree].stage = tree_world.nature.Stage.MATURE
		tree_world.objects.records[tree].sapient = true
		tree_world.Growth.seed(tree_world.objects.records[tree], "wood_breath", 0)
		tree_world.pages[0].positions[0] = Vector2(123.5, 124.5)
		check(tree_world.begin_interaction(1, {"kind": "learn", "target": tree}) == "accepted", "Static sapient teacher was mistaken for an unavailable body")
		advance(tree_world, 1300)
		check(tree_world.objects.records[1].get("methods", {}).has("wood_breath") and latest(tree_world, 1).facts.teacher == tree, "Static contact lost its actual learning outcome")

func clue_feedback_and_progress() -> void:
	var w: RefCounted = peaceful()
	w.pages[0].positions[2] = Vector2(123.5, 121.5)
	w.knowledge.record(2).subjects = {}
	w.knowledge.record(3).subjects = {}
	w.knowledge.seed(w, 2, w.operation_target(w.source_objects[0]), 0)
	w.objects.records[3].sight_range = 2.0
	w.objects.records[3].autonomous = true
	w.decisions.resume(w, 3, 0)
	check(w.begin_interaction(3, {"kind": "talk", "target": 2}) == "accepted", "Clue-sharing fixture failed")
	w.settle_action(3, 0)
	advance(w, 1000)
	var outcome: Dictionary = latest(w, 3)
	check(outcome.get("reason") == "shared_clue" and outcome.status == "completed" and outcome.facts.subject == w.source_objects[0] and w.decisions.retry_allowed(w, 3, "talk", 2, 1000), "Successful clue sharing became failure feedback")
	var natural: RefCounted = peaceful()
	var plant: int = natural.nature.create(natural, "annual_grass", natural.Terrain.index(Vector2i(124, 124)), true)
	natural.objects.add(plant, "grain", 1)
	natural.pages[0].positions[0] = Vector2(124.5, 124.5)
	check(natural.begin_interaction(1, {"kind": "sow", "target": plant}) == "accepted", "Seeding fixture refused")
	advance(natural, 2000)
	check(natural.objects.records[plant].stage == natural.nature.Stage.SPROUT and not natural.objects.records[plant].has("remaining_ms") and latest(natural, 1).facts.worked_ms == 1500, "Completed sowing was interrupted or charged twice")
	var source: int = natural.source_objects[0]
	natural.pages[0].positions[1] = natural.Terrain.center(natural.objects.records[source].tile)
	natural.pages[0].source_ids[1] = 0
	natural.adopt_work(2, natural.elapsed_ms)
	natural.pages[0].move_to(1, natural.pages[0].positions[1], natural.Units.Mode.RESOURCE)
	advance(natural, 2050)
	# Another consumer exhausts the real source during the harvest interval.
	natural.objects.add(source, "wood", -natural.objects.amount(source, "wood"))
	advance(natural, 3000)
	check(latest(natural, 2).get("reason") == "empty" and not natural.work_runs.has(2) and natural.pages[0].modes[1] != natural.Units.Mode.REST, "Harvest refusal lost its reason or created a fake resting host")

func bounded_evidence() -> void:
	var w: RefCounted = peaceful()
	var ledger: RefCounted = w.activity_results
	ledger.record(w.next_run, "learn", 1, 2, [1, 2], 0, Results.completed({"method": "wood_breath"}))
	w.next_run += 1
	for actor: int in [1, 2]:
		for index: int in 10:
			ledger.record(w.next_run, "study", actor, actor, [actor], 0, Results.completed())
			w.next_run += 1
		if actor == 1:
			check(ledger.records.has(1) and ledger.view(1).size() == Results.PER_PERSON, "One participant's rollover discarded another's evidence")
			check(Persistence.candidate(Persistence.capture(w), 0) != null, "Shared retention rebuilt different participant windows")
	check(not ledger.records.has(1) and ledger.records.size() == 16 and Persistence.candidate(Persistence.capture(w), 0) != null, "Bounded result retention could not rebuild")
	var source: int = w.source_objects[0]
	w.begin_transfer(1, {"kind": "take", "target": source, "item": "wood", "amount": 1})
	ledger.record(w.actions[1].run_id, "take", 1, source, [1], 0, Results.completed())
	check(Persistence.candidate(Persistence.capture(w), 0) == null, "A live run and its terminal evidence restored together")
	var capped: RefCounted = Results.new()
	w.objects.next_id += Results.LIMIT + 1 # Historical allocated-and-removed identities.
	w.end_run(1, 0, "replaced")
	for index: int in Results.LIMIT + 1:
		var actor: int = index + 1
		capped.record(w.next_run, "study", actor, actor, [actor], 0, Results.completed())
		w.next_run += 1
	check(capped.records.size() == Results.LIMIT and capped.view(1).is_empty() and capped.rebuild(w), "Population turnover bypassed the global evidence bound")

func placed_without_dispatch() -> void:
	var w: RefCounted = peaceful()
	var cell := Vector2i(126, 126)
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		w.facilities.create_completed(w, "wood_wall", w.Terrain.index(cell + offset))
	w.flush_topology()
	w.objects.claim(w.source_objects[0], 1, "wood", 4)
	var before: int = w.objects.amount(1, "wood")
	var receipt: Dictionary = w.command({"kind": "construct", "definition": "wood_wall", "tile": w.Terrain.index(cell)})
	check(receipt.ok and receipt.get("placed", false) and receipt.reason == "placed_waiting" and receipt.dispatch_reason == "no_operation_place" and w.objects.records[receipt.target].kind == "blueprint" and w.objects.amount(1, "wood") == before - 3 and w.objects.amount(receipt.target, "wood") == 3, "Committed placement was reported as complete failure or refunded: " + str(receipt))

func busy_player_and_partner_handoff() -> void:
	var w: RefCounted = peaceful()
	w.pages[0].positions[0] = Vector2(122.5, 120.5)
	w.adopt_motion(1, 0)
	w.pages[0].move_to(0, Vector2(124.5, 120.5), w.Units.Mode.MANUAL)
	var stock: Dictionary = w.objects.records[1].stock.duplicate(true)
	check(w.begin_interaction(2, {"kind": "trade", "target": 1}) == "accepted", "Player contact fixture refused")
	advance(w, 600)
	check(latest(w, 2).get("reason") == "target_busy" and latest(w, 2).participants == [2] and stock == w.objects.records[1].stock, "Busy player was an involuntary participant")
	w.release(1)
	w.pages[0].positions[0] = Vector2(122.5, 120.5)
	w.objects.records[2].autonomous = true
	w.decisions.resume(w, 2, w.elapsed_ms)
	check(w.begin_interaction(1, {"kind": "learn", "target": 2}) == "accepted", "Partner command fixture refused")
	check(w.command({"kind": "interrupt", "actor": 2}).ok, "Partner stop failed")
	check(not w.decisions.wakeups.has(2) and w.decisions.records[2].manual and w.society.waits.is_empty() and latest(w, 1).reason == "partner_left", "Old partner wake survived explicit manual takeover")

func occupied_completion_and_cancellation() -> void:
	for cancel: bool in [false, true]:
		var w: RefCounted = peaceful()
		w.objects.claim(w.source_objects[0], 1, "wood", 4)
		var target: int = w.facilities.blueprint(w, 1, "wood_wall", w.Terrain.index(Vector2i(126, 126))).target
		w.objects.records[target].remaining_ms = 2000
		w.pages[0].positions[0] = Vector2(125.5, 126.5)
		w.begin_interaction(1, {"kind": "construct", "target": target})
		advance(w, 16)
		var started: int = w.actions[1].started_ms
		# Simulate an occupancy conflict at the commit boundary, independently
		# from navigation's prevention of entering an already acquired footprint.
		w.pages[0].positions[1] = Vector2(126.5, 126.5)
		advance(w, started + 2000)
		check(w.actions[1].get("waiting", false) and w.objects.records[target].remaining_ms == 1 and not w.actions[1].has("started_ms"), "Occupied completion did not preserve the final quantum")
		check(Persistence.candidate(Persistence.capture(w), 0) != null, "Occupied wait could not restore")
		if cancel:
			w.end_run(1, w.elapsed_ms, "preempted")
			check(latest(w, 1).facts == {"worked_ms": 1999, "remaining_ms": 1}, "Canceled wait lost remaining work or counted waiting as labor")
			w.pages[0].positions[1] = Vector2(125.5, 126.5)
			w.begin_interaction(2, {"kind": "construct", "target": target})
		else:
			w.pages[0].positions[1] = Vector2(128.5, 126.5)
		advance(w, w.elapsed_ms + 500)
		var outcome: Dictionary = latest(w, 2 if cancel else 1)
		check(w.objects.records[target].kind == "wall" and outcome.status == "completed" and outcome.facts.worked_ms == (1 if cancel else 2000), "Waiting or replacement labor was counted twice")

func restore_boundaries_and_death() -> void:
	var w: RefCounted = peaceful()
	w.objects.claim(w.source_objects[0], 1, "wood", 4)
	var target: int = w.facilities.blueprint(w, 1, "wood_wall", w.Terrain.index(Vector2i(126, 126))).target
	w.begin_interaction(1, {"kind": "construct", "target": target})
	var bad: Dictionary = Persistence.capture(w)
	bad.domains.world.actions[1]["started_ms"] = 0
	check(Persistence.candidate(bad, 0) == null, "An approaching builder restored fabricated labor")
	w.objects.records[1]["abilities"] = {"wood_mend": true}
	w.objects.records[1]["qi"] = 100
	w.pages[0].health[0] = 1000
	var binding: Dictionary = w.gate.current(1)
	check(w.execute_operation(1, {"kind": "wood_mend", "target": 1}) == "completed" and w.gate.current(1) == binding and Persistence.candidate(Persistence.capture(w), 0) != null, "Instant result collided with ongoing construction on restore")
	w.kill(1, 0)
	check(latest(w, 1).reason == "actor_dead" and latest(w, 1).status == "failed", "Actor death lost its terminal cause")
	var plant: int = w.nature.create(w, "annual_grass", w.Terrain.index(Vector2i(124, 124)), true)
	bad = Persistence.capture(w)
	bad.domains.objects.records[plant].remaining_ms = -1
	check(Persistence.candidate(bad, 0) == null, "Invalid seeding labor restored")
	check(not Results._facts_valid({"tree": [[range(64), range(64), range(64), range(64), range(64), range(64), range(64), range(64)]]}), "Facts traversal had no total node budget")

func _run() -> void:
	transfers()
	construction_handoff()
	social_participation()
	clue_feedback_and_progress()
	bounded_evidence()
	placed_without_dispatch()
	busy_player_and_partner_handoff()
	occupied_completion_and_cancellation()
	restore_boundaries_and_death()
	print("ACTIVITIES_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
