extends "res://tests/teaching_smoke.gd"
const ActivityText = preload("res://scripts/presentation/ui/activity_text.gd")
const EventText = preload("res://scripts/presentation/ui/event_text.gd")
const ServicePositions = preload("res://scripts/sim/kernel/service_positions.gd")

func readable_outcomes() -> void:
	var w: RefCounted = lesson_world()
	w.objects.records[2]["name"] = "师兄"
	w.knowledge.refresh(w, 1, 2, 0)
	check(w.command({"kind": "learn", "target": 2}).ok, "Player learning was not admitted")
	w.settle_action(1, 0)
	check(w.actions.get(1, {}).has("started_ms"), "Willing lesson did not start")
	var own: Dictionary = w.describe(1)
	var partner: Dictionary = w.describe(2)
	check(own.activity.started_ms == 0 and partner.activity.phase == "acting" and partner.activity.started_ms == 0, "Zero-time lesson/partner lost its shared interval")
	var midpoint: float = float(own.activity.started_ms + own.activity.due_ms) / 2.0
	check(is_equal_approx(ActivityText.progress(own, midpoint), 0.5) and ActivityText.progress(own, midpoint) == ActivityText.progress(partner, midpoint), "Participants showed different real progress")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Started lesson with scalar history failed restore")
	advance(w, 1300)
	var ends: Array = w.person_events.view(1).filter(func(e: Dictionary): return e.kind == "activity_result" and e.get("action") == "learn")
	check(ends.size() == 1 and ends[0].status == "completed" and ends[0].role == "learner" and ends[0].target_label.contains("师兄"), "Player lesson did not have one correctly directed readable result")
	var teachers: Array = w.person_events.view(2).filter(func(e: Dictionary): return e.kind == "activity_result" and e.get("action") == "learn")
	check(teachers.size() == 1 and teachers[0].role == "teacher", "Partner result was missing or reversed")
	var first: String = EventText.line(ends[0])
	w.objects.records[2].name = "改名后"
	for index: int in 10:
		w.commit_activity(w.next_run, "wood_mend", 1, 1, [1], w.elapsed_ms, w.ActivityResults.completed())
		w.next_run += 1
	check(w.activity_results.view(1).all(func(e: Dictionary): return e.run_id != ends[0].run_id) and EventText.line(w.person_events.view(1).filter(func(e: Dictionary): return e.kind == "activity_result" and e.get("action") == "learn")[0]) == first, "Bounded result eviction or renaming erased the personal history snapshot")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Readable terminal facts did not survive candidate validation")
	check(EventText.line({"kind": "status_added"}).is_empty() and EventText.line({"kind": "unknown_internal"}).is_empty(), "Internal event was presented as a false failure")
	var refused: RefCounted = lesson_world()
	refused.objects.records[3]["name"] = "三师兄"
	refused.knowledge.records.erase(1)
	refused.pages[0].positions[0] = refused.pages[0].positions[2] + Vector2(0.8, 0)
	refused.command({"kind": "learn_cooking", "target": 3})
	refused.settle_action(1, 0)
	var result: Dictionary = refused.person_events.view(1).back()
	check(result.kind == "activity_result" and result.reason == "teacher_does_not_know" and EventText.line(result).contains("尚未掌握") and result.target_label.contains("三师兄"), "Real on-site refusal lost its acquired identity or reason")
	check(refused.knowledge.account_view(1, 3, 0).teaching_refusals.has("learn_cooking"), "Personal refusal was unavailable to the normal menu")
	var teaching: RefCounted = lesson_world()
	learner(teaching, 3)
	check(teaching.begin_interaction(2, {"kind": "teach_wood_breath", "target": 3}) == "accepted", "Teacher could not initiate the shared session")
	teaching.settle_action(2, 0)
	advance(teaching, 200)
	teaching.end_run(2, 200, "replaced")
	for person: int in [2, 3]:
		var history: Array = teaching.person_events.view(person).filter(func(e: Dictionary): return e.kind == "activity_result" and e.action == "teach_wood_breath")
		check(history.size() == 1 and history[0].role == ("teacher" if person == 2 else "learner") and history[0].reason == "replaced" and EventText.line(history[0]).contains("已中断"), "Teacher-initiated cancellation lost a participant's role or terminal fact: " + str(history))
	check(Persistence.candidate(Persistence.capture(teaching), 0) != null, "Interrupted bilateral history did not restore")

func positions_and_clearance() -> void:
	var w: RefCounted = lesson_world()
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(130, 124)))
	w.flush_topology()
	w.pages[0].positions[0] = Vector2(128.5, 124.5)
	w.pages[0].positions[1] = Vector2(128.5, 123.5)
	w.objects.add(chest, "meal", 4)
	check(w.begin_interaction(1, {"kind": "eat", "target": chest}) == "accepted", "First service visitor was not admitted")
	check(w.begin_interaction(2, {"kind": "eat", "target": chest}) == "accepted", "Second service visitor could not use another legal point")
	check(w.pages[0].targets[0] != w.pages[0].targets[1], "Visitors claimed the same destination")
	var saved: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(saved != null and saved.pages[0].targets[0] != saved.pages[0].targets[1], "Derived destination occupancy did not survive restore")
	w.release(2); w.clear_navigation(2)
	w.pages[0].positions[1] = w.pages[0].targets[0]
	w.objects.records[2].autonomous = true
	w.decisions.records[2].manual = false
	var before: Vector2 = w.pages[0].positions[1]
	check(ServicePositions.step_aside(w, 2, 0), "Idle autonomous occupant did not make room")
	check(w.pages[0].positions[1] == before and w.pages[0].targets[1] != before, "Clearance teleported the body or retained the same destination")
	check(not ServicePositions.step_aside(w, 1, 0), "Clearance stole player control")
	w.end_run(2, 0); w.clear_navigation(2)
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Canceling a clearance move left an invalid claim")

func occupied_arrival() -> void:
	var w: RefCounted = lesson_world()
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(130, 124)))
	w.flush_topology(); w.objects.add(chest, "meal", 4)
	w.pages[0].positions[0] = Vector2(127.5, 124.5)
	check(w.begin_interaction(1, {"kind": "eat", "target": chest}) == "accepted", "Arrival fixture was not admitted")
	var first: Vector2 = w.pages[0].targets[0]
	w.pages[0].positions[0] = first
	w.pages[0].positions[2] = first # A later arrival occupies the admitted destination.
	w.settle_action(1, 0)
	check(not w.actions[1].has("started_ms") and w.pages[0].targets[0] != first, "New body obstruction was ignored at service arrival")
	w.pages[0].positions[0] = w.pages[0].targets[0]
	w.settle_action(1, 0)
	check(w.actions[1].has("started_ms"), "Service visitor could not begin at the alternate position")
	w.objects.records[1].autonomous = true
	check(not ServicePositions.step_aside(w, 1, 0), "An active worker was displaced")
	var single: RefCounted = lesson_world()
	var bed: int = single.nature.create(single, "annual_grass", single.Terrain.index(Vector2i(134, 124)), true)
	single.objects.add(bed, "grain", 1)
	single.pages[0].positions[0] = Vector2(134.5, 124.5)
	check(single.begin_interaction(2, {"kind": "sow", "target": bed}) == "target_busy", "Temporary sole-position obstruction was confused with invalid geometry")
	check(single.gate.current(2).is_empty() and not single.reservations.has(bed), "A refused occupied position leaked a host or lock")
	single.pages[0].positions[0] = Vector2(133.5, 123.5)
	check(single.begin_interaction(2, {"kind": "sow", "target": bed}) == "accepted", "Vacated sole position could not be retried")
	check(Persistence.candidate(Persistence.capture(single), 0) != null, "Occupied-position refusal/retry broke restore")

func edge_clearance_and_contact() -> void:
	var w: RefCounted = lesson_world()
	var plant: int = w.nature.create(w, "annual_grass", w.Terrain.index(Vector2i(134, 124)), true)
	w.objects.add(plant, "grain", 1)
	w.pages[0].positions[2] = Vector2(135.1, 124.5)
	w.objects.records[3].autonomous = true; w.decisions.records[3].manual = false
	check(w.begin_interaction(2, {"kind": "sow", "target": plant}) == "target_busy", "Edge body did not obstruct the actual service point")
	check(ServicePositions.step_aside(w, 3, 0), "Edge occupant could not yield because its centre was in a neighboring tile")
	w.pages[0].positions[2] = w.pages[0].targets[2]
	w.end_run(3, 0); w.clear_navigation(3)
	check(w.begin_interaction(2, {"kind": "sow", "target": plant}) == "accepted", "Edge clearance failed to reopen the actual point")
	var wall: int = w.facilities.create_completed(w, "wood_wall", w.Terrain.index(Vector2i(140, 124)))
	w.flush_topology()
	w.pages[0].positions[3] = Vector2(142.0, 124.5)
	var point: Vector2 = w.facilities.interaction_point(w, 4, Vector2(138.5, 124.5), 0.35, false, "talk", 1)
	check(wall > 0 and point.x >= 0 and w.terrain.can_stand(point, 0.35, false), "Contact point embedded the actor into an adjacent wall")
	w.objects.claim(w.source_objects[0], 1, "wood", 4)
	var blueprint: Dictionary = w.facilities.blueprint(w, 1, "wood_wall", w.Terrain.index(Vector2i(144, 124)))
	w.pages[0].positions[2] = Vector2(144.5, 124.5)
	check(blueprint.reason == "accepted" and w.facilities.start_construction(w, blueprint.target, 0) == "occupied", "Occupied blueprint acquired a solid footprint")
	check(ServicePositions.step_aside(w, 3, 0), "Idle body inside a future solid footprint could not yield")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Clearance/contact boundaries did not restore")

func _run() -> void:
	readable_outcomes()
	positions_and_clearance()
	occupied_arrival()
	edge_clearance_and_contact()
	print("SECT_FEEDBACK_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
