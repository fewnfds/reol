extends "res://tests/teaching_smoke.gd"

func moving_contact_boundary() -> void:
	var w: RefCounted = lesson_world()
	learner(w, 3)
	w.objects.records[3].autonomous = true
	w.decisions.resume(w, 3, 0)
	w.pages[0].positions[1] = Vector2(120.0, 120.5)
	w.pages[0].positions[2] = Vector2(121.48, 120.5)
	w.livelihood._walk_to_site(w, 3, w.Terrain.index(Vector2i(130, 120)), 0)
	w.execute_operation(2, {"kind": "teach_wood_breath", "target": 3})
	# Use the real motion/arrival path, not a direct call to settle_action.
	advance(w, 15000)
	check(lesson_results(w, 3).size() == 1, "Sub-interval contact adopted a partner's future position and failed the lesson: " + str(w.activity_results.view(2)))
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Moving contact boundary failed recovery")

func explicit_shared_qualifications() -> void:
	var w: RefCounted = lesson_world()
	w.Growth.seed(w.objects.records[1], "wood_breath", 0)
	w.objects.records[2].methods.erase("wood_breath")
	w.decisions.suspend(w, 2)
	w.execute_operation(1, {"kind": "teach_wood_breath", "target": 2})
	w.execute_operation(2, {"kind": "learn", "target": 1})
	# The learner understands elsewhere after admission but before meeting.
	w.Growth.seed(w.objects.records[2], "wood_breath", 0, false)
	w.settle_action(1, 0)
	check(not w.actions.has(1) and latest(w, 1).reason == "learner_already_understood" and latest(w, 1).facts.points_gained == 0, "Explicit commands skipped on-site understanding qualification")
	var urgent: RefCounted = lesson_world()
	urgent.decisions.suspend(urgent, 2)
	urgent.execute_operation(2, {"kind": "teach_wood_breath", "target": 1})
	urgent.execute_operation(1, {"kind": "learn", "target": 2})
	urgent.pages[0].hunger[1] = 500
	urgent.settle_action(1, 0)
	check(latest(urgent, 1).get("reason") == "refused_need" and urgent.society.waits.is_empty(), "Explicit participation bypassed an urgent bodily need")

func retained_book_without_old_site() -> void:
	var w: RefCounted = lesson_world()
	w.objects.records[2].methods.erase("wood_breath")
	var id: int = learner(w, 2)
	var entry: Dictionary = w.livelihood.records[2]
	var own: Dictionary = w.livelihood._self_view(w, 2)
	check(w.livelihood._preference(entry, own, {}, 0).retained.has("0:study:breath_manual"), "An active learning purpose without an old method immediately returned its book")
	entry.goals[id].method = {"approach": "develop", "operation": "learn", "anchor": 4, "selected_ms": 0}
	check(w.livelihood._preference(entry, own, {}, 0).retained.has("0:study:breath_manual"), "A missing old teacher prevented retaining a self-study prerequisite")

func known_dead_obligation() -> void:
	var w: RefCounted = lesson_world()
	var org: int = w.institutions.create("青禾宗")
	for actor: int in [1, 2, 3]: w.institutions.admit(w, org, actor, ["commission"] if actor == 1 else [])
	var matter: int = w.institutions.create_matter(w, 1, {"kind": "operation", "operation": "teach_wood_breath", "target": 3, "organization": org})
	var share: int = w.institutions.accept_share(w, 2, matter)
	w.kill(3, 0); w.knowledge.refresh(w, 2, 3, 0)
	autonomous(w, 2, [])
	advance(w, 8000)
	check(w.institutions.shares[share].state == "accepted" and w.livelihood.records[2].explore_count == 0 and w.gate.current(2).is_empty(), "Known dead student caused pointless searching or silently erased a formal obligation")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "A blocked historical obligation failed recovery")

func duplicate_student_host_reply() -> void:
	var w: RefCounted = lesson_world()
	var org: int = w.institutions.create("青禾宗")
	for actor: int in [1, 2, 3]: w.institutions.admit(w, org, actor, ["commission"] if actor == 1 else [])
	w.knowledge.refresh(w, 1, 3, 0)
	for i: int in 2:
		var matter: int = w.institutions.create_matter(w, 1, {"kind": "operation", "operation": "teach_wood_breath", "target": 3, "organization": org})
		var delivered: Dictionary = w.society.Requests.deliver(w.society, w, 1, {"kind": "offer_matter", "target": 2, "matter": matter}, 0)
		check(delivered.status == "completed", "Duplicate teaching offer failed actual contact")
		if delivered.status != "completed": return
		var id: int = delivered.facts.request
		check(w.society.Requests.respond(w.society, w, 2, id, "accept", "accepted_share", 0).status == "completed", "Duplicate teaching offer could not be accepted")
	w.objects.records[2].autonomous = false
	w.end_run(2, 0, "interrupted", {}, false); w.clear_navigation(2)
	# Issuer misses the lesson, then returns to speak to its actual teacher.
	w.pages[0].positions[0] = Vector2(160.5, 120.5); w.clear_navigation(1)
	w.execute_operation(3, {"kind": "learn", "target": 2}); w.settle_action(3, 0)
	advance(w, 1300)
	w.pages[0].positions[0] = Vector2(122, 120.5); w.clear_navigation(1)
	w.society.Requests.sync_contact(w.society, w, 1, 2, w.elapsed_ms)
	check(w.society.requests.values().all(func(request: Dictionary): return request.closed_by == 2 and request.reply.state == request.state), "Returning teacher could not convey a student-hosted duplicate resolution")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Duplicate resolution and delivered reply failed recovery")

func departing_participant_wait() -> void:
	var w: RefCounted = lesson_world()
	w.pages[0].positions[1] = Vector2(120.0, 120.5)
	w.pages[0].positions[0] = Vector2(121.0, 120.5)
	w.command({"kind": "move", "actor": 1, "position": Vector2(130.5, 120.5)})
	w.execute_operation(2, {"kind": "teach_wood_breath", "target": 1})
	advance(w, 50)
	check(w.actions.get(2, {}).get("waiting", false), "Departure fixture did not reach its actual participant wait")
	advance(w, 400)
	check(not w.actions.has(2) and latest(w, 2).get("reason") == "out_of_reach", "A departed participant restarted the bounded on-site join window")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Leaving a bounded join window failed recovery")

func _run() -> void:
	moving_contact_boundary()
	explicit_shared_qualifications()
	retained_book_without_old_site()
	known_dead_obligation()
	duplicate_student_host_reply()
	departing_participant_wait()
	print("TEACHING_REFINEMENT_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
