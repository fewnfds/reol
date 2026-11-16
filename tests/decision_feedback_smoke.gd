extends "res://tests/abilities_smoke.gd"
## Execution feedback belongs to an actor/operation/subject, not a facility type.

func resident(w: RefCounted, targets: Array) -> void:
	for actor: int in w.actor_slots: w.objects.records[actor].side = 0
	w.pages[0].positions[1] = Vector2(120.5, 120.5)
	w.pages[0].hunger[1] = 10000
	w.pages[0].energy[1] = 10000
	w.objects.add(2, "wood", 1)
	w._sync_inventory(2)
	w.objects.records[2].autonomous = true
	w.objects.records[2].known = {}
	w.objects.records[2].observe_due = 60000
	for target: int in targets: w.livelihood.remember(w, 2, target, 0)
	w.decisions.resume(w, 2, 0)

func failure_for(w: RefCounted, actor: int, operation: String, target: int) -> Dictionary:
	for failure: Dictionary in w.decisions.records.get(actor, {}).get("feedback", []):
		if failure.operation == operation and failure.target == target: return failure
	return {}

func immediate_alternative() -> void:
	var w: RefCounted = fixture()
	var blocked: int = w.facilities.seed_fixture(w, "wood_chest", w.Terrain.index(Vector2i(124, 120)))
	var usable: int = w.facilities.seed_fixture(w, "wood_chest", w.Terrain.index(Vector2i(120, 126)))
	for y: int in range(119, 122):
		for x: int in range(123, 126):
			if x != 124 or y != 120: w.queue_structure(w.Terrain.index(Vector2i(x, y)), true, false)
	w.flush_topology()
	resident(w, [blocked, usable])
	w.decisions.prepare(w, 0)
	check(failure_for(w, 2, "put", blocked).get("reason") == "no_operation_place", "Immediate work rejection lost its operation/subject")
	check(not w.actions.has(2), "Rejected candidate left a host action")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Refusal feedback failed candidate restore")
	advance(w, 4000)
	check(w.objects.amount(usable, "wood") == 1 and w.objects.amount(2, "wood") == 0, "Resident repeatedly picked a blocked best target instead of completing the alternative")
	check(w.livelihood.decisions < 20, "Refusal retry turned into frame-by-frame planning")
	if restored != null:
		advance(restored, 4000)
		check(restored.objects.amount(usable, "wood") == 1 and restored.pages[0].positions == w.pages[0].positions, "Restored refusal changed the alternative or movement")

func asynchronous_remembered_goal() -> void:
	var w: RefCounted = fixture()
	var blocked: int = w.facilities.seed_fixture(w, "wood_chest", w.Terrain.index(Vector2i(124, 120)))
	var usable: int = w.facilities.seed_fixture(w, "wood_chest", w.Terrain.index(Vector2i(120, 126)))
	for y: int in range(118, 123):
		for x: int in range(122, 127):
			if x in [122, 126] or y in [118, 122]: w.queue_structure(w.Terrain.index(Vector2i(x, y)), true, false)
	w.flush_topology()
	resident(w, [blocked, usable])
	w.objects.records[2].sight_range = 2.0
	w.decisions.prepare(w, 0)
	var task: Dictionary = w.decisions.records[2].task
	check(task.get("operation") == "put" and task.get("target") == blocked and task.get("approach", false), "Remembered-goal exploration discarded the intended operation/subject")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Remembered-goal host metadata failed restore")
	advance(w, 50)
	check(failure_for(w, 2, "put", blocked).get("reason") == "path_failed", "Asynchronous navigation failure did not feed back to the remembered operation")
	check(w.decisions.records[2].next_ms >= 500 and not w.gate.current(2).has("run_id"), "Failed navigation retained execution ownership or skipped retry delay")
	if restored != null:
		advance(restored, 50)
		check(restored.decisions.records[2].feedback == w.decisions.records[2].feedback, "Restored failed navigation attributed another target")
	advance(w, 4500)
	check(w.objects.amount(usable, "wood") == 1, "Remembered inaccessible target prevented the reachable alternative")

func evidence_and_bounds() -> void:
	var w: RefCounted = fixture()
	var target: int = w.facilities.seed_fixture(w, "wood_chest", w.Terrain.index(Vector2i(124, 120)))
	w.flush_topology()
	w.livelihood.remember(w, 2, target, 0)
	w.decisions.result(w, 2, "forge", target, "path_failed", 0)
	check(not w.decisions.retry_allowed(w, 2, "forge", target, 0), "Generic operation failure was not retained")
	check(w.decisions.retry_allowed(w, 3, "forge", target, 0) and w.decisions.retry_allowed(w, 2, "inspect", target, 0), "Failure leaked between actors or operations")
	w.livelihood.remember(w, 2, target, 10)
	check(not w.decisions.retry_allowed(w, 2, "forge", target, 10), "Unchanged observation timestamp erased structural failure")
	w.objects.add(target, "wood", 1)
	w.terrain.revision += 1
	check(not w.decisions.retry_allowed(w, 2, "forge", target, 20), "Hidden inventory or global terrain revision cleared personal failure")
	w.livelihood.remember(w, 2, target, 20)
	check(w.decisions.retry_allowed(w, 2, "forge", target, 20), "Meaningful newly observed evidence did not reopen the target")
	w.decisions.result(w, 2, "forge", target, "path_failed", 0)
	check(not w.decisions.retry_allowed(w, 2, "forge", target, 4999) and w.decisions.retry_allowed(w, 2, "forge", target, 5000), "Structural failure became a permanent blacklist or expired too early")
	for index: int in 20:
		var subject: int = w.objects.create("pile", "probe", w.Terrain.index(Vector2i(140 + index, 120)))
		w.decisions.result(w, 2, "inspect", subject, "unavailable", 0)
	check(w.decisions.records[2].feedback.size() == w.decisions.FEEDBACK_LIMIT, "Per-actor feedback was not bounded")
	var snapshot: Dictionary = Persistence.capture(w)
	check(Persistence.candidate(snapshot, 0) != null, "Bounded feedback failed restore")
	var bad: Dictionary = snapshot.duplicate(true)
	bad.domains.decisions.records[2].feedback[0].until_ms = 999999
	check(Persistence.candidate(bad, 0) == null, "Unbounded refusal duration was adopted")
	bad = snapshot.duplicate(true)
	bad.domains.decisions.records[2].feedback[0].evidence = {"hidden_global_revision": 1}
	check(Persistence.candidate(bad, 0) == null, "Unexpected evidence fields were adopted")
	bad = snapshot.duplicate(true)
	bad.domains.decisions.records[2].feedback.append(bad.domains.decisions.records[2].feedback[0].duplicate(true))
	check(Persistence.candidate(bad, 0) == null, "Oversized feedback was adopted")

func manual_success_and_cancellation() -> void:
	var w: RefCounted = fixture()
	var target: int = w.objects.create("pile", "grain", w.Terrain.index(Vector2i(120, 120)))
	w.objects.add(target, "grain", 2)
	w.decisions.result(w, 1, "take", target, "path_failed", 0)
	check(w.begin_transfer(1, {"kind": "take", "target": target, "item": "grain", "amount": 1}) == "accepted", "Manual input was blocked by autonomous refusal feedback")
	advance(w, 400)
	check(w.objects.amount(1, "grain") > 0 and failure_for(w, 1, "take", target).is_empty(), "Real manual success failed to clear the matching refusal")
	w.decisions.result(w, 1, "inspect", target, "path_failed", w.elapsed_ms)
	w.decisions.result(w, 1, "inspect", target, "interrupted", w.elapsed_ms)
	check(not failure_for(w, 1, "inspect", target).is_empty(), "Cancellation incorrectly cleared a prior failure")
	w.decisions.result(w, 1, "inspect", target, "completed", w.elapsed_ms)
	check(failure_for(w, 1, "inspect", target).is_empty(), "Matching success did not clear the refusal")

func commitment_and_disproved_memory() -> void:
	var w: RefCounted = fixture()
	w.objects.claim(w.source_objects[0], 1, "wood", 10)
	var target: int = w.facilities.blueprint(w, 1, "wood_wall", w.Terrain.index(Vector2i(124, 120))).target
	for y: int in range(119, 122):
		for x: int in range(123, 126):
			if x != 124 or y != 120: w.queue_structure(w.Terrain.index(Vector2i(x, y)), true, false)
	w.flush_topology()
	resident(w, [target])
	check(w.society.finish(w, 1, {"kind": "request_help", "target": 2, "task_target": target}, 0) == "completed", "Construction commitment fixture failed")
	w.decisions.prepare(w, 0)
	advance(w, 4000)
	check(failure_for(w, 2, "construct", target).get("at_ms") == 0 and not w.actions.has(2), "Commitment bypassed structural refusal and repeatedly planned the same blocked site")
	check(w.objects.records[2].get("commitment", {}).get("target") == target, "Temporary inability silently cancelled a construction promise")
	w.objects.records[2].known[target].seen_ms = 4000
	w.decisions.result(w, 2, "construct", target, "accepted", 4000)
	check(not failure_for(w, 2, "construct", target).is_empty(), "Admission cleared failure before any work completed")
	var memory: RefCounted = fixture()
	var missing: int = memory.objects.create("pile", "meal", memory.Terrain.index(Vector2i(124, 120)))
	memory.objects.add(missing, "meal", 1)
	resident(memory, [missing])
	memory.pages[0].hunger[1] = 3000
	memory.livelihood.remember(memory, 3, missing, 0)
	memory.pages[0].positions[2] = Vector2(180.5, 180.5)
	memory.objects.transfer(missing, 1, "meal", 1)
	memory.objects.remove_empty(missing)
	memory.decisions.prepare(memory, 0)
	check(not memory.objects.records[2].known.has(missing), "Visible absence left a disproved personal clue until the next observation sweep")
	check(memory.objects.records[3].known.has(missing), "Another actor learned a remote disappearance without observation")
	check(memory.decisions.records[2].task.get("target", 0) != missing, "Disproved clue still produced a remembered-goal exploration task")

func _run() -> void:
	immediate_alternative()
	asynchronous_remembered_goal()
	evidence_and_bounds()
	manual_success_and_cancellation()
	commitment_and_disproved_memory()
	print("DECISION_FEEDBACK_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
