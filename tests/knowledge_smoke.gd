extends "res://tests/activities_smoke.gd"
const Knowledge = preload("res://scripts/sim/kernel/knowledge.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")

func move_actor(w: RefCounted, actor: int, position: Vector2) -> void:
	var slot: int = w.actor_slots[actor]
	w.pages[slot / 256].positions[slot % 256] = position
	w.combat.scan.index(w)

func observation_and_rumor() -> void:
	var w: RefCounted = peaceful()
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(124, 124)))
	w.objects.add(chest, "meal", 2)
	w.flush_topology()
	w.knowledge.records.clear()
	move_actor(w, 2, Vector2(123.5, 124.5))
	check(w.knowledge.refresh(w, 2, chest, 0), "Visible static facility was not observed")
	move_actor(w, 3, Vector2(180.5, 180.5))
	check(w.knowledge.deliver(w, 3, 2, chest, 0), "Delivered actual observer clue did not reach recipient")
	var heard: Dictionary = w.knowledge.records[3].subjects[chest]
	check(heard.origin == "heard" and heard.observer == 2 and heard.source == 2 and heard.hops == 1 and heard.seen_ms == 0, "Rumor became false new firsthand knowledge")
	var private_view: Dictionary = w.knowledge.view(3, chest, w.elapsed_ms)
	private_view.inventory.meal = 99
	check(w.knowledge.view(3, chest, w.elapsed_ms).inventory.meal == 2 and w.objects.amount(chest, "meal") == 2, "Detached knowledge mutated world or personal evidence")
	check(not w.knowledge.deliver(w, 2, 3, chest, 0), "Rumor echoed back to original observer")
	w.objects.add(chest, "meal", -2)
	w.remove_static(chest)
	check(w.knowledge.view(3, chest, w.elapsed_ms).tile >= 0 and w.knowledge.view(3, chest, w.elapsed_ms).inventory.meal == 2, "Remote deletion instantly updated personal evidence")
	advance(w, 100)
	move_actor(w, 3, Vector2(123.5, 124.5))
	w.knowledge.refresh(w, 3, chest, 100)
	check(w.knowledge.view(3, chest, w.elapsed_ms).tile == -1 and w.knowledge.records[3].subjects[chest].absent_ms == 100, "Directly observed absence left a false location")
	move_actor(w, 3, Vector2(180.5, 180.5))
	check(not w.knowledge.deliver(w, 3, 2, chest, 100) and w.knowledge.view(3, chest, w.elapsed_ms).tile == -1, "Old rumor revived a disproved location")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Historical missing subject/source failed restore")

func mobile_and_privacy() -> void:
	var w: RefCounted = peaceful()
	w.knowledge.records.clear()
	move_actor(w, 2, Vector2(123.5, 120.5))
	move_actor(w, 3, Vector2(124.5, 120.5))
	w.knowledge.observe(w, 2, 0)
	var clue: Dictionary = w.knowledge.view(2, 3, w.elapsed_ms)
	check(clue.tile == w.Terrain.index(Vector2i(124, 120)) and clue.hp == 1 and not clue.has("inventory") and not clue.has("methods") and not clue.has("qi"), "Mobile observation lost last position or copied private properties")
	check(w.knowledge.view(2, 3, Knowledge.MOBILE_FRESH_MS + 1).tile == -1 and w.knowledge.view(2, 3, w.elapsed_ms).hp == 1, "Old mobile position remained usable or erased identity")
	move_actor(w, 3, Vector2(180.5, 180.5))
	w.knowledge.refresh(w, 2, 3, 0)
	check(w.knowledge.view(2, 3, w.elapsed_ms).tile == -1 and w.knowledge.view(2, 3, w.elapsed_ms).hp == 1, "Empty last location became a false death notice")
	move_actor(w, 3, Vector2(124.5, 120.5))
	w.knowledge.refresh(w, 2, 3, 0)
	move_actor(w, 2, Vector2(180.5, 180.5))
	w.kill(3, 0)
	check(w.knowledge.view(2, 3, w.elapsed_ms).hp == 1, "Remote death leaked into individual knowledge")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null and restored.knowledge.view(2, 3, restored.elapsed_ms).hp == 1, "Restore rewrote stale living evidence")
	move_actor(w, 2, Vector2(123.5, 120.5))
	w.knowledge.refresh(w, 2, 3, 0)
	check(w.knowledge.view(2, 3, w.elapsed_ms).hp == 0, "Visible corpse was still believed alive")
	move_actor(w, 2, Vector2(180.5, 180.5))
	w.remove_actor(3)
	check(Persistence.candidate(Persistence.capture(w), 0) != null and w.knowledge.view(2, 3, w.elapsed_ms).hp == 0, "Historical contact identity required a live body")
	var source: int = w.facilities.create_completed(w, "cook_stove", w.Terrain.index(Vector2i(124, 124)))
	w.knowledge.seed(w, 2, w.operation_target(source))
	w.knowledge.observe(w, 2, 0)
	var before: Dictionary = w.knowledge.records[2].subjects[source].duplicate(true)
	w.objects.add(source, "meal", 1)
	w.knowledge.observe(w, 2, 0)
	check(w.knowledge.records[2].subjects[source] == before, "Unseen stock changed a personal observation")

func bounded_propagation() -> void:
	var w: RefCounted = peaceful()
	w.knowledge.records.clear()
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(124, 124)))
	w.flush_topology()
	move_actor(w, 2, Vector2(123.5, 124.5))
	w.knowledge.refresh(w, 2, chest, 0)
	move_actor(w, 1, Vector2(180.5, 180.5))
	move_actor(w, 3, Vector2(181.5, 180.5))
	move_actor(w, 4, Vector2(182.5, 180.5))
	check(w.knowledge.deliver(w, 3, 2, chest, 0) and w.knowledge.deliver(w, 4, 3, chest, 0), "Two legal clue hops were refused")
	check(not w.knowledge.deliver(w, 1, 4, chest, 0) and not w.knowledge.deliver(w, 3, 2, chest, 0), "Hop cap or unchanged clue deduplication failed")
	var revision: int = w.knowledge.records[4].subjects[chest].revision
	w.knowledge.deliver(w, 4, 2, chest, 0)
	check(w.knowledge.records[4].subjects[chest].hops == 1 and w.knowledge.records[4].subjects[chest].revision == revision and w.knowledge.deliver(w, 1, 4, chest, 0), "Better provenance failed to improve propagation without inventing changed evidence")
	w.remove_actor(2)
	check(w.knowledge.records[3].subjects[chest].observer == 2 and Persistence.candidate(Persistence.capture(w), 0) != null, "Removing origin invalidated other people's evidence")

func actual_talk_changes_life() -> void:
	var w: RefCounted = peaceful()
	w.knowledge.records.clear()
	var stove: int = w.facilities.create_completed(w, "cook_stove", w.Terrain.index(Vector2i(136, 120)))
	w.objects.add(stove, "meal", 1)
	w.flush_topology()
	move_actor(w, 2, Vector2(123.5, 120.5))
	move_actor(w, 3, Vector2(123.5, 121.5))
	w.objects.records[3].sight_range = 3.0
	check(w.knowledge.refresh(w, 2, stove, 0), "Speaker did not observe real remote meal")
	check(w.begin_interaction(3, {"kind": "talk", "target": 2}) == "accepted", "Actual conversation not accepted")
	w.settle_action(3, 0)
	advance(w, 1100)
	check(latest(w, 3).reason == "shared_clue" and w.knowledge.records[3].subjects[stove].origin == "heard", "Conversation did not transfer speaker knowledge")
	w.pages[0].hunger[2] = 3000
	w.objects.records[3].autonomous = true
	w.knowledge.record(3).due_ms = w.elapsed_ms + 3000
	w.decisions.resume(w, 3, w.elapsed_ms)
	w.decisions.prepare(w, w.elapsed_ms)
	check(w.pages[0].modes[2] == w.Units.Mode.EXPLORE and w.decisions.records[3].task.get("target") == stove, "New heard food location did not change real autonomous movement")
	advance(w, 6500)
	check(w.objects.amount(stove, "meal") == 0 and w.pages[0].hunger[2] > 5000, "Heard location did not lead to real meal consumption")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Real conversation/life consumer corrupted restore")

func constrained_learning_feedback() -> void:
	var w: RefCounted = peaceful()
	w.knowledge.records.clear()
	move_actor(w, 1, Vector2(123.5, 120.5))
	move_actor(w, 3, Vector2(124.5, 120.5))
	check(w.begin_interaction(1, {"kind": "learn", "target": 3}) == "accepted", "Failed teaching fixture did not start")
	w.settle_action(1, 0)
	advance(w, 1100)
	check(latest(w, 1).reason == "teacher_does_not_know" and not w.knowledge.can_attempt(1, "learn", 3, w.elapsed_ms) and w.knowledge.can_attempt(1, "talk", 3, w.elapsed_ms) and w.knowledge.can_attempt(1, "learn_cooking", 3, w.elapsed_ms), "Teacher refusal became either repeated harassment or a global blacklist")
	var clue: Dictionary = w.knowledge.view(1, 3, w.elapsed_ms)
	check(not clue.has("methods") and not clue.has("inventory"), "Teaching refusal exposed unrelated private state")
	w.objects.add(3, "wood", 1)
	w.knowledge.refresh(w, 1, 3, w.elapsed_ms)
	check(not w.knowledge.can_attempt(1, "learn", 3, w.elapsed_ms), "Unrelated new observation cleared specific teaching refusal")
	Growth.seed(w.objects.records[3], "wood_breath", w.elapsed_ms)
	move_actor(w, 4, Vector2(123.5, 120.5))
	# The evidence case needs an agreed lesson. Mastery alone no longer obliges
	# a teacher to accept another person's unsolicited request (T10 consent).
	check(w.begin_interaction(3, {"kind": "teach_wood_breath", "target": 4}) == "accepted", "Teacher could not express agreement to the evidence lesson")
	check(w.begin_interaction(4, {"kind": "learn", "target": 3}) == "accepted", "Later positive teaching evidence fixture refused")
	w.settle_action(4, w.elapsed_ms)
	advance(w, 2200)
	check(w.knowledge.view(4, 3, w.elapsed_ms).get("teaches", {}).get("wood_breath", -1) > 1100, "Actual teaching success produced no limited capability evidence")
	check(w.knowledge.deliver(w, 2, 4, 3, w.elapsed_ms), "Visible body prevented hearing independent teaching evidence")
	w.knowledge.refresh(w, 2, 3, w.elapsed_ms)
	check(w.knowledge.records[2].subjects[3].teachings.wood_breath.hops == 1, "Seeing a teacher reset the teaching account's provenance")
	check(w.knowledge.deliver(w, 1, 2, 3, w.elapsed_ms) and w.knowledge.can_attempt(1, "learn", 3, w.elapsed_ms), "New specific teaching account did not allow a fresh attempt")
	check(w.knowledge.records[1].subjects[3].teachings.wood_breath.hops == 2 and not w.knowledge.deliver(w, 4, 1, 3, w.elapsed_ms), "Teaching account echoed despite its independent hop cap")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Specific negative/positive evidence did not restore")
	var bad: Dictionary = Persistence.capture(w)
	bad.domains.knowledge.records[1].subjects[3].teachings.wood_breath.hops = 3
	check(Persistence.candidate(bad, 0) == null, "Unbounded teaching provenance restored")

func bounded_and_recovery() -> void:
	var w: RefCounted = peaceful()
	w.knowledge.records.clear()
	for index: int in 150:
		var target: int = w.objects.create("pile", "grain", w.Terrain.index(Vector2i(120 + index % 10, 120 + index / 10)))
		w.objects.add(target, "grain", 1)
		w.knowledge.seed(w, 2, w.operation_target(target))
	check(w.knowledge.record(2).subjects.size() == Knowledge.SUBJECT_LIMIT, "Personal knowledge grew without a bound")
	var state: Dictionary = Persistence.capture(w)
	check(Persistence.candidate(state, 0) != null, "Bounded personal knowledge did not restore")
	var target: int = w.knowledge.records[2].subjects.keys()[0]
	for field: String in ["hops", "seen_ms", "source", "revision", "absent_ms"]:
		var bad: Dictionary = state.duplicate(true)
		bad.domains.knowledge.records[2].subjects[target][field] = {"hops": 99, "seen_ms": 1, "source": w.objects.next_id, "revision": -1, "absent_ms": 2}[field]
		check(Persistence.candidate(bad, 0) == null, "Malformed knowledge restored: " + field)
	var bad: Dictionary = state.duplicate(true)
	bad.domains.knowledge.records[2].subjects[target].view["methods"] = {}
	check(Persistence.candidate(bad, 0) == null, "Private/unknown knowledge field was accepted")
	bad = state.duplicate(true)
	bad.domains.objects.records[2]["known"] = {}
	check(Persistence.candidate(bad, 0) == null, "Duplicate legacy knowledge truth restored")

func _run() -> void:
	observation_and_rumor()
	mobile_and_privacy()
	bounded_propagation()
	actual_talk_changes_life()
	constrained_learning_feedback()
	bounded_and_recovery()
	print("KNOWLEDGE_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
