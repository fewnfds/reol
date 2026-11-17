extends "res://tests/teaching_smoke.gd"

func autonomous_transmission() -> void:
	var w: RefCounted = lesson_world()
	var tree: int = w.nature.create(w, "old_tree", w.Terrain.index(Vector2i(128, 123)))
	w.objects.records[tree].stage = w.nature.Stage.MATURE; w.objects.records[tree].growth_ms = int(w.nature.definitions[w.objects.records[tree].definition].mature_ms)
	w.objects.records[tree].qi = 3000
	w.nature._sync(w, tree); w.flush_topology()
	learner(w, 3); learner(w, 4)
	var first: int = w.livelihood.add_goal(w, 2, "instruction", {"method": "wood_breath", "target": 3})
	var next: int = w.livelihood.add_goal(w, 3, "instruction", {"method": "wood_breath", "target": 4})
	autonomous(w, 2, [3])
	autonomous(w, 3, [2, 4, tree])
	w.decisions.prepare(w, 0)
	advance(w, 400)
	check(w.actions.get(2, {}).get("kind") == "teach_wood_breath" or w.society.waits.has(2), "A teacher with a personal purpose did not independently approach their named student: " + str(w.livelihood.describe(2)))
	advance(w, 7500)
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "An autonomous learning/practice chain failed recovery")
	if restored == null: return
	advance(w, 35000); advance(restored, 35000)
	check(w.Growth.mastered(w.objects.records[3], "wood_breath") and w.objects.records[4].get("methods", {}).get("wood_breath", {}).get("teacher") == 3, "The student did not actually practice and transmit to another person: " + str({"three":w.describe(3), "four":w.describe(4), "goals":w.livelihood.describe(3)}))
	check(w.livelihood.records[2].goals[first].state == "completed" and w.livelihood.records[3].goals[next].state == "completed" and not w.Growth.mastered(w.objects.records[4], "wood_breath"), "Transmission did not resolve its purposes or gave the third person unearned mastery")
	check(int(w.objects.records[tree].qi) < 3000 and w.pages[0].energy[2] < 9500 and w.objects.records[3].qi > 0, "Independent practice did not use the actual source and body resources")
	check(w.objects.records[3].methods == restored.objects.records[3].methods and w.objects.records[4].methods == restored.objects.records[4].methods and w.activity_results.records == restored.activity_results.records, "Restoration changed the autonomous teaching/practice continuation")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Final transmission failed recovery")

func busy_window_and_teacher_need() -> void:
	var w: RefCounted = lesson_world()
	learner(w, 3)
	w.adopt_work(3, 0); w.pages[0].modes[2] = w.Units.Mode.REST; w.pages[0].due_ms[2] = 10000
	w.pages[0].energy[2] = 1000
	w.execute_operation(2, {"kind": "teach_wood_breath", "target": 3}); w.settle_action(2, 0)
	check(latest(w, 2).reason == "refused_need" and w.work_runs.has(3), "A teacher repeatedly pulled a needy person out of rest")
	var teacher: RefCounted = lesson_world()
	teacher.pages[0].energy[1] = 1000
	teacher.execute_operation(1, {"kind": "learn", "target": 2}); teacher.settle_action(1, 0)
	check(latest(teacher, 1).reason == "refused_need" and not teacher.society.waits.has(2), "Learning ignored the teacher's urgent need")
	var busy: RefCounted = lesson_world()
	learner(busy, 3)
	busy.execute_operation(3, {"kind": "talk", "target": 4}); busy.settle_action(3, 0)
	busy.execute_operation(2, {"kind": "teach_wood_breath", "target": 3}); busy.settle_action(2, 0)
	check(busy.actions[2].get("join_reason") == "target_busy" and busy.actions.has(3) and not busy.society.waits.has(3), "Teaching seized a busy learner")
	advance(busy, 400)
	check(Persistence.candidate(Persistence.capture(busy), 0) != null, "A busy participant's rendezvous failed recovery")
	advance(busy, 2800)
	check(lesson_results(busy, 3).size() == 1, "A free and willing participant did not join within the bounded window: " + str({"actions":busy.actions, "results":busy.activity_results.records}))

func partial_understanding() -> void:
	var w: RefCounted = lesson_world()
	w.objects.records[3]["aptitudes"] = {"comprehension": 1}
	learner(w, 3)
	var org: int = w.institutions.create("青禾宗")
	for actor: int in [1, 2, 3]: w.institutions.admit(w, org, actor, ["commission"] if actor == 1 else [])
	var matter: int = w.institutions.create_matter(w, 1, {"kind": "operation", "organization": org, "target": 3, "operation": "teach_wood_breath"})
	check(matter > 0, "Partial teaching matter could not be created")
	if matter <= 0: return
	var share: int = w.institutions.accept_share(w, 2, matter)
	var purpose: int = w.livelihood.add_goal(w, 2, "instruction", {"method": "wood_breath", "target": 3})
	w.execute_operation(2, {"kind": "teach_wood_breath", "target": 3}); w.settle_action(2, 0)
	advance(w, 1300)
	check(int(w.objects.records[3].methods.wood_breath.understanding) == 110 and w.institutions.shares[share].fulfilled == 0 and w.livelihood.records[2].goals[purpose].state == "active", "Partial understanding falsely fulfilled a teaching purpose or obligation")
	var first: Dictionary = latest(w, 2)
	w.institutions.outcome(w, first)
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Partial understanding with an unfulfilled obligation failed recovery")
	if restored == null: return
	w = restored
	w.execute_operation(3, {"kind": "learn", "target": 2}); w.settle_action(3, w.elapsed_ms)
	advance(w, 2600)
	check(w.objects.records[3].methods.wood_breath.understanding == 200 and latest(w, 2).facts.points_gained == 90 and w.institutions.shares[share].fulfilled == 1 and w.livelihood.records[2].goals[purpose].state == "completed", "A second real lesson failed to finish the remaining understanding exactly once")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Finished partial lessons failed recovery")

func _run() -> void:
	if "--busy" in OS.get_cmdline_user_args(): busy_window_and_teacher_need()
	elif "--partial" in OS.get_cmdline_user_args(): partial_understanding()
	else: autonomous_transmission()
	print("TEACHING_AGENCY_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
