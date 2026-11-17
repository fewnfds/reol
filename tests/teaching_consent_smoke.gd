extends "res://tests/teaching_smoke.gd"

func contact_before_discovery() -> void:
	var w: RefCounted = lesson_world()
	w.Growth.seed(w.objects.records[1], "wood_breath", 0, false)
	var contacts: Dictionary = w.society.contacts.duplicate(true)
	w.execute_operation(2, {"kind": "teach_wood_breath", "target": 1}); w.settle_action(2, 0)
	check(w.actions.get(2, {}).get("join_reason") == "awaiting_participant" and w.society.contacts == contacts, "An unattended player disclosed private mastery before agreeing to contact")
	var busy: RefCounted = lesson_world()
	busy.Growth.seed(busy.objects.records[3], "wood_breath", 0, false)
	busy.execute_operation(3, {"kind": "talk", "target": 4}); busy.settle_action(3, 0)
	busy.execute_operation(2, {"kind": "teach_wood_breath", "target": 3}); busy.settle_action(2, 0)
	check(busy.actions[2].get("join_reason") == "target_busy" and latest(busy, 2).is_empty(), "A busy student's knowledge bypassed the shared participation gate")
	var blind: RefCounted = lesson_world()
	blind.objects.records[3].sight_range = 0.0
	blind.execute_operation(3, {"kind": "learn", "target": 4}); blind.settle_action(3, 0)
	check(latest(blind, 3).reason == "teacher_does_not_know" and not blind.knowledge.can_attempt(3, "learn", 4, 1000) and not blind.knowledge.view(3, 4, 0).is_empty(), "A real nonvisual refusal lost its contact receipt or learning experience")
	check(Persistence.candidate(Persistence.capture(blind), 0) != null, "Nonvisual refusal failed recovery")

func meaningful_opportunity_during_search() -> void:
	var w: RefCounted = lesson_world()
	learner(w, 3)
	w.objects.records[3].autonomous = true
	w.decisions.resume(w, 3, 0)
	w.livelihood._walk_to_site(w, 3, w.Terrain.index(Vector2i(137, 120)), 0)
	w.execute_operation(2, {"kind": "teach_wood_breath", "target": 3}); w.settle_action(2, 0)
	check(w.society.waits.has(3) and w.pages[0].modes[2] == w.Units.Mode.IDLE, "An interested searching learner walked past an actual teaching opportunity")
	advance(w, 1300)
	check(w.objects.records[3].get("methods", {}).get("wood_breath", {}).get("teacher") == 2, "Stopping a willing search did not lead to an actual lesson")

func dormant_duty_is_not_occupation() -> void:
	var w: RefCounted = lesson_world()
	var org: int = w.institutions.create("青禾宗")
	w.institutions.admit(w, org, 2, [])
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(125, 122)))
	var stove: int = w.facilities.create_completed(w, "cook_stove", w.Terrain.index(Vector2i(128, 122)))
	var board: int = w.facilities.create_completed(w, "notice_desk", w.Terrain.index(Vector2i(126, 125)))
	for target: int in [chest, stove, board]: w.objects.records[target].organization = org
	w.objects.add(chest, "meal", 12, w.objects.Stock.right(0, org))
	w.flush_topology()
	var duty: int = w.institutions.appoint(w, org, 2, "meal_steward", [chest, stove, board], {"target": chest, "sources": [stove], "channel": board})
	check(duty > 0, "Dormant duty could not be authored")
	w.pages[0].positions[1] = Vector2(125.5, 125.5); w.clear_navigation(2)
	w.knowledge.observe(w, 2, 0)
	w.execute_operation(2, {"kind": "read_channel", "target": board}); w.settle_action(2, 0)
	advance(w, 1300)
	w.pages[0].positions[0] = Vector2(124.5, 125.5); w.clear_navigation(1)
	check(not w.livelihood.Planner.Institutions.review_due(w.livelihood._self_view(w, 2), w.operation_actor(2).duties[duty], w.elapsed_ms), "Duty fixture was actually due for inspection")
	w.execute_operation(1, {"kind": "learn", "target": 2}); w.settle_action(1, w.elapsed_ms)
	check(w.society.waits.has(2), "A satisfied, recently checked duty permanently vetoed a free teacher's brief help")
	advance(w, 2600)
	check(w.objects.records[1].get("methods", {}).has("wood_breath") and w.institutions.appointments[duty].active, "A free teaching opportunity removed or bypassed the original duty")

func duplicate_obligations() -> void:
	var w: RefCounted = lesson_world()
	var org: int = w.institutions.create("青禾宗")
	for actor: int in [1, 2, 3]: w.institutions.admit(w, org, actor, ["commission"] if actor == 1 else [])
	var first: int = w.institutions.create_matter(w, 1, {"kind": "operation", "operation": "teach_wood_breath", "target": 3, "organization": org})
	var second: int = w.institutions.create_matter(w, 1, {"kind": "operation", "operation": "teach_wood_breath", "target": 3, "organization": org})
	check(first > 0 and second > 0, "Duplicate need fixture could not be authored")
	if first <= 0 or second <= 0: return
	var one: int = w.institutions.accept_share(w, 2, first)
	var two: int = w.institutions.accept_share(w, 2, second)
	learner(w, 3)
	w.execute_operation(2, {"kind": "teach_wood_breath", "target": 3}); w.settle_action(2, 0)
	advance(w, 1300)
	check(w.institutions.shares[one].fulfilled + w.institutions.shares[two].fulfilled == 1 and w.institutions.matters[first].state == "completed" and w.institutions.matters[second].state == "satisfied", "One actual lesson paid twice or left an already witnessed satisfied need active")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Duplicate need resolution failed recovery")

func _run() -> void:
	if "--duty" in OS.get_cmdline_user_args(): dormant_duty_is_not_occupation()
	elif "--search" in OS.get_cmdline_user_args(): meaningful_opportunity_during_search()
	elif "--duplicate" in OS.get_cmdline_user_args(): duplicate_obligations()
	else: contact_before_discovery()
	print("TEACHING_CONSENT_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
