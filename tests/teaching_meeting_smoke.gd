extends "res://tests/teaching_smoke.gd"

func distant_complementary() -> void:
	var w: RefCounted = lesson_world()
	w.pages[0].positions[1] = Vector2(110.5, 120.5); w.clear_navigation(2)
	w.pages[0].positions[2] = Vector2(130.5, 120.5); w.clear_navigation(3)
	learner(w, 3)
	check(w.execute_operation(2, {"kind": "teach_wood_breath", "target": 3}) == "accepted" and w.execute_operation(3, {"kind": "learn", "target": 2}) == "accepted", "Distant complementary approaches could not start")
	advance(w, 15000)
	check(lesson_results(w, 3).size() == 1, "Distant complementary participants passed each other without meeting: " + str({"two":w.combat.position(w, 2), "three":w.combat.position(w, 3), "actions":w.actions, "results":w.activity_results.records}))

func explicit_manual_pair() -> void:
	var w: RefCounted = lesson_world()
	w.decisions.suspend(w, 2)
	w.execute_operation(2, {"kind": "teach_wood_breath", "target": 1})
	w.settle_action(2, 0)
	w.execute_operation(1, {"kind": "learn", "target": 2})
	w.settle_action(1, 0)
	advance(w, 6500)
	check(lesson_results(w, 1).size() == 1 and w.decisions.records[2].manual, "Explicit complementary manual participants waited forever or lost control ownership")

func known_dead_purpose() -> void:
	var w: RefCounted = lesson_world()
	var goal: int = w.livelihood.add_goal(w, 2, "instruction", {"method": "wood_breath", "target": 3})
	w.knowledge.refresh(w, 2, 3, 0)
	w.kill(3, 0)
	w.knowledge.refresh(w, 2, 3, 0)
	autonomous(w, 2, [])
	advance(w, 8000)
	check(w.livelihood.records[2].goals[goal].state == "cancelled" and w.gate.current(2).is_empty(), "A teacher kept searching for an actually observed dead student")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Resolved personal purpose with historical student failed recovery")

func _run() -> void:
	if "--manual" in OS.get_cmdline_user_args(): explicit_manual_pair()
	elif "--dead" in OS.get_cmdline_user_args(): known_dead_purpose()
	else: distant_complementary()
	print("TEACHING_MEETING_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
