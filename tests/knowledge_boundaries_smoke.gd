extends "res://tests/knowledge_smoke.gd"

func location_scoped_absence() -> void:
	var w: RefCounted = peaceful()
	w.knowledge.records.clear()
	# Isolate the two explicitly timed location accounts from the independent
	# periodic schedule. A second observation at the same timestamp is not newer.
	for actor: int in w.actor_slots: w.knowledge.record(actor).due_ms = 5000
	move_actor(w, 1, Vector2(123.5, 120.5))
	move_actor(w, 3, Vector2(124.5, 120.5))
	w.knowledge.refresh(w, 1, 3, 0)
	advance(w, 50)
	move_actor(w, 3, Vector2(180.5, 180.5))
	move_actor(w, 2, Vector2(181.5, 180.5))
	w.knowledge.refresh(w, 2, 3, 50)
	advance(w, 100)
	w.knowledge.refresh(w, 1, 3, 100)
	check(w.knowledge.records[1].subjects[3].absent_tile == w.Terrain.index(Vector2i(124, 120)), "Departure did not retain the particular empty location")
	check(w.knowledge.deliver(w, 1, 2, 3, 100) and w.knowledge.view(1, 3, 100).tile == w.Terrain.index(Vector2i(180, 180)), "Absence at one location disproved another location")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Location-scoped absence did not restore")

func interrupted_refusal_and_actual_contact() -> void:
	var w: RefCounted = peaceful()
	move_actor(w, 1, Vector2(123.5, 120.5))
	move_actor(w, 3, Vector2(124.5, 120.5))
	check(w.begin_interaction(1, {"kind": "learn", "target": 3}) == "accepted", "Refusal fixture not admitted")
	w.settle_action(1, 0)
	advance(w, 1100)
	check(not w.knowledge.can_attempt(1, "learn", 3, 1100), "Actual refusal was not remembered")
	check(w.begin_interaction(1, {"kind": "learn", "target": 3}) == "accepted", "Manual retry was incorrectly disallowed")
	w.end_run(1, 1100, "preempted")
	check(not w.knowledge.can_attempt(1, "learn", 3, 1100), "Cancelling a manual retry erased specific teaching refusal")
	var blind: RefCounted = peaceful()
	blind.knowledge.records.clear()
	move_actor(blind, 1, Vector2(123.5, 120.5))
	move_actor(blind, 2, Vector2(124.5, 120.5))
	blind.objects.records[1].sight_range = 0.0
	check(blind.begin_interaction(1, {"kind": "learn", "target": 2}) == "accepted", "Actual nonvisual contact was not admitted")
	advance(blind, 2200)
	check(latest(blind, 1).status == "completed" and blind.knowledge.view(1, 2, blind.elapsed_ms).get("teaches", {}).has("wood_breath"), "Real teaching result required unrelated visual sight")
	check(not blind.knowledge.view(1, 2, blind.elapsed_ms).has("inventory") and Persistence.candidate(Persistence.capture(blind), 0) != null, "Contact receipt exposed private belongings or broke restore")
	var proof: Dictionary = blind.knowledge.records[1].subjects[2].teachings.wood_breath.duplicate()
	move_actor(blind, 3, Vector2(123.5, 120.5))
	blind.knowledge.refresh(blind, 3, 2, blind.elapsed_ms)
	move_actor(blind, 1, Vector2(180.5, 180.5))
	blind.knowledge.deliver(blind, 1, 3, 2, blind.elapsed_ms)
	check(blind.knowledge.records[1].subjects[2].teachings.wood_breath == proof, "Newer location rumor erased or rejuvenated actual teaching evidence")
	check(blind.knowledge.view(1, 2, blind.elapsed_ms + Knowledge.MOBILE_FRESH_MS + 1).tile == -1 and blind.knowledge.view(1, 2, blind.elapsed_ms + Knowledge.MOBILE_FRESH_MS + 1).teaches.wood_breath == proof.seen_ms, "Position expiry destroyed independent teaching evidence")
	var dead: RefCounted = peaceful()
	dead.knowledge.records.clear()
	move_actor(dead, 2, Vector2(123.5, 120.5))
	move_actor(dead, 3, Vector2(124.5, 120.5))
	dead.kill(3, 0)
	dead.combat.scan.index(dead)
	dead.knowledge.observe(dead, 2, 0)
	check(dead.knowledge.view(2, 3, 0).get("hp", 1) == 0 and not dead.combat.scan.nearby(Vector2(120, 118), Vector2(127, 122)).has(3), "Newly discovered corpse was invisible to personal sight or became a combat target")

func help_delivery_and_remote_failure() -> void:
	var w: RefCounted = peaceful()
	move_actor(w, 3, w.combat.position(w, 1) + Vector2(1, 0))
	w.objects.claim(w.source_objects[0], 1, "wood", 8)
	var target: int = w.facilities.blueprint(w, 1, "wood_wall", w.Terrain.index(Vector2i(160, 120))).target
	w.knowledge.records.clear()
	w.knowledge.seed(w, 2, w.operation_target(target))
	check(w.knowledge.deliver(w, 4, 2, target, 0) and w.knowledge.deliver(w, 1, 4, target, 0), "Two-hop request fixture failed")
	var refusal: Dictionary = w.society.commit(w, 1, {"kind": "request_help", "target": 3, "task_target": target}, 0)
	check(refusal.reason == "task_not_understood" and w.institutions.Matters.shares_for(w.institutions, 3).is_empty(), "Unreceived task produced a ghost responsibility")
	check(not w.objects.records[1].autonomous and w.institutions.Matters.shares_for(w.institutions, 1).is_empty(), "A request created a player responsibility without explicit response")
	advance(w, 30001) # A new explanation cannot bypass the first real refusal.
	w.livelihood.records.erase(3)
	w.pages[0].energy[2] = 10000; w.pages[0].hunger[2] = 10000
	w.knowledge.created(w, 1, target, w.elapsed_ms)
	for y: int in range(118, 123):
		for x: int in range(158, 163):
			if x in [158, 162] or y in [118, 122]: w.queue_structure(w.Terrain.index(Vector2i(x, y)), true, false)
	w.flush_topology()
	w.objects.records[3].sight_range = 2.0
	check(w.society.commit(w, 1, {"kind": "request_help", "target": 3, "task_target": target}, w.elapsed_ms).reason == "accepted_share", "Direct task explanation failed")
	var began: int = w.elapsed_ms
	w.decisions.resume(w, 3, began)
	w.decisions.prepare(w, began)
	advance(w, began + 3000)
	var failures: Array = w.decisions.records[3].feedback
	check(failures.size() == 1 and failures[0].reason == "path_failed" and failures[0].at_ms < began + 100, "Remote construction promise bypassed path retry delay")
	check(not w.institutions.Matters.shares_for(w.institutions, 3).is_empty() and not w.actions.has(3), "Temporary path failure erased a responsibility or retained an action")

func protected_evidence_and_history() -> void:
	var w: RefCounted = peaceful()
	w.knowledge.records.clear()
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(124, 124)))
	w.flush_topology()
	move_actor(w, 2, Vector2(123.5, 124.5))
	w.knowledge.refresh(w, 2, chest, 0)
	move_actor(w, 3, Vector2(180.5, 180.5))
	move_actor(w, 4, Vector2(181.5, 180.5))
	w.knowledge.deliver(w, 3, 2, chest, 0)
	w.knowledge.deliver(w, 4, 3, chest, 0)
	w.remove_actor(3)
	w.remove_static(chest)
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Deleted immediate source and target invalidated two-hop history")
	move_actor(w, 4, Vector2(123.5, 124.5))
	w.knowledge.refresh(w, 4, chest, 0)
	var teacher: Dictionary = w.operation_target(2)
	teacher.tile = w.Terrain.index(Vector2i(123, 124))
	teacher["teaches"] = {"wood_breath": 0}
	w.knowledge.seed(w, 4, teacher)
	for index: int in 150:
		var pile: int = w.objects.create("pile", "grain", w.Terrain.index(Vector2i(130 + index % 10, 130 + index / 10)))
		w.objects.add(pile, "grain", 1)
		w.knowledge.seed(w, 4, w.operation_target(pile))
	check(w.knowledge.records[4].subjects.size() == Knowledge.SUBJECT_LIMIT and w.knowledge.records[4].subjects.has(chest) and w.knowledge.view(4, 2, 0).teaches.has("wood_breath"), "Incidental clues immediately evicted recent disproof or teaching evidence")
	check(not w.knowledge.view(4, 2, 0).has("inventory") and Persistence.candidate(Persistence.capture(w), 0) != null, "Scenario actor knowledge leaked private state or failed restore")

func observation_during_activity() -> void:
	var w: RefCounted = peaceful()
	w.knowledge.records.clear()
	move_actor(w, 2, Vector2(123.5, 120.5))
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(124, 123)))
	w.flush_topology()
	w.knowledge.record(2).due_ms = 1000
	check(w.command({"kind": "move", "actor": 2, "position": Vector2(140.5, 120.5)}).ok, "Travel observation fixture refused")
	advance(w, 1000)
	check(not w.gate.current(2).is_empty() and w.knowledge.view(2, chest, 1000).get("tile", -1) >= 0, "Busy manual traveller only observed after its activity ended")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "In-activity observation corrupted the running host")

func full_memory_and_identity_only_delivery() -> void:
	var w: RefCounted = peaceful()
	w.knowledge.records.clear()
	move_actor(w, 4, Vector2(180.5, 180.5))
	for index: int in 128:
		var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(130 + index % 16, 130 + index / 16)))
		w.knowledge.seed(w, 4, w.operation_target(chest))
	var teacher: Dictionary = w.operation_target(3)
	teacher["teaches"] = {"wood_breath": 0}
	w.knowledge.seed(w, 2, teacher) # Explicit name/capability, without a position.
	check(w.knowledge.deliver(w, 4, 2, 3, 0), "Full memory discarded incoming capability before its priority was known")
	var heard: Dictionary = w.knowledge.view(4, 3, 0)
	check(heard.tile == -1 and not heard.has("hp") and heard.teaches.wood_breath == 0 and w.knowledge.record(4).subjects.size() == Knowledge.SUBJECT_LIMIT, "Identity-only capability message invented a current location/body or grew without bound")
	w.objects.claim(w.source_objects[0], 1, "wood", 4)
	var target: int = w.facilities.blueprint(w, 1, "wood_wall", w.Terrain.index(Vector2i(160, 120))).target
	move_actor(w, 4, w.combat.position(w, 1) + Vector2(1, 0))
	w.livelihood.records.erase(4)
	w.pages[0].energy[3] = 10000; w.pages[0].hunger[3] = 10000
	var response: Dictionary = w.society.commit(w, 1, {"kind": "request_help", "target": 4, "task_target": target}, 0)
	check(response.reason == "accepted_share" and w.operation_actor(4).task_access.has(target), "Full memory rejected an explicitly discussed task before obligation protection applied: " + str(response))
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Atomic knowledge admission failed restore")

func _run() -> void:
	location_scoped_absence()
	interrupted_refusal_and_actual_contact()
	help_delivery_and_remote_failure()
	protected_evidence_and_history()
	observation_during_activity()
	full_memory_and_identity_only_delivery()
	print("KNOWLEDGE_BOUNDARIES_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
