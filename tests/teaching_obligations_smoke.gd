extends "res://tests/teaching_smoke.gd"

func preparation_uses_own_rights(borrowed: bool = false) -> void:
	var w: RefCounted = lesson_world()
	var org: int = w.institutions.create("青禾宗")
	for actor: int in [1, 2, 3]: w.institutions.admit(w, org, actor, ["commission"] if actor == 1 else (["take", "study"] if actor == 2 and borrowed else []))
	w.objects.records[2].methods.erase("wood_breath")
	w.objects.add(2, "breath_manual", -w.objects.amount(2, "breath_manual"))
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(125, 122)))
	w.objects.records[chest].owner = 0 if borrowed else 2
	w.objects.records[chest].organization = org if borrowed else 0
	w.objects.add(chest, "breath_manual", 1, w.objects.Stock.right(0, org) if borrowed else w.objects.Stock.right(2))
	var tree: int = w.nature.create(w, "old_tree", w.Terrain.index(Vector2i(128, 123)))
	w.objects.records[tree].stage = w.nature.Stage.MATURE; w.objects.records[tree].qi = 3000
	w.nature._sync(w, tree); w.flush_topology()
	# The future teacher is willing to learn because they themselves want to
	# teach a fourth person, without a duplicated standalone development goal.
	w.livelihood.add_goal(w, 3, "instruction", {"method": "wood_breath", "target": 4})
	var matter: int = w.institutions.create_matter(w, 1, {"kind": "operation", "operation": "teach_wood_breath", "target": 3, "organization": org})
	check(matter > 0, "Preparation test could not commission instruction")
	if matter <= 0: return
	var share: int = w.institutions.accept_share(w, 2, matter)
	autonomous(w, 2, [3, chest, tree])
	w.decisions.prepare(w, 0)
	advance(w, 6500)
	if borrowed: check(w.objects.amount(2, "breath_manual") == 1 or w.Growth.introduced(w.objects.records[2], "wood_breath"), "Custody returned the borrowed study prerequisite before actual introduction finished")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Preparing oneself for an obligation failed recovery")
	if restored == null: return
	advance(w, 35000); advance(restored, 35000)
	check(w.Growth.mastered(w.objects.records[2], "wood_breath") and w.objects.records[3].get("methods", {}).get("wood_breath", {}).get("teacher") == 2, "An empty job source list prevented legal independent study/practice or an interested future teacher refused learning: " + str(w.livelihood.describe(2)))
	check(w.objects.amount(chest, "breath_manual") + w.objects.amount(2, "breath_manual") == 1 and w.objects.records[tree].qi < 3000 and w.institutions.shares[share].fulfilled == 1, "Preparation or teaching bypassed actual goods, source costs or final fulfillment")
	check(w.objects.records[2].methods == restored.objects.records[2].methods and w.activity_results.records == restored.activity_results.records, "Restoration changed the prerequisite-to-teaching continuation")

func witnessed_student_host() -> void:
	var w: RefCounted = lesson_world()
	var org: int = w.institutions.create("青禾宗")
	for actor: int in [1, 2, 3]: w.institutions.admit(w, org, actor, ["commission"] if actor == 1 else [])
	var matter: int = w.institutions.create_matter(w, 1, {"kind": "operation", "operation": "teach_wood_breath", "target": 3, "organization": org})
	check(matter > 0, "Actual teaching offer could not be commissioned")
	if matter <= 0: return
	w.objects.records[2].sight_range = 24.0
	w.execute_operation(1, {"kind": "offer_matter", "target": 2, "matter": matter})
	w.settle_action(1, 0); advance(w, 1700)
	check(w.society.requests.size() == 1 and w.society.requests.values()[0].state == "accepted", "Actual offered teaching responsibility was not accepted")
	if w.society.requests.is_empty() or w.society.requests.values()[0].state != "accepted": return
	# Keep the accepted obligation but leave the recipient resident for an
	# independently chosen student-hosted lesson.
	w.objects.records[2].autonomous = false
	w.end_run(2, w.elapsed_ms, "interrupted", {}, false); w.clear_navigation(2)
	w.pages[0].positions[0] = Vector2(121.5, 120.5); w.clear_navigation(1)
	w.pages[0].positions[1] = Vector2(122.5, 120.5); w.clear_navigation(2)
	w.pages[0].positions[2] = Vector2(123.5, 120.5); w.clear_navigation(3)
	w.execute_operation(3, {"kind": "learn", "target": 2}); w.settle_action(3, w.elapsed_ms)
	advance(w, w.elapsed_ms + 1300)
	var request: Dictionary = w.society.requests.values()[0]
	check(request.state == "fulfilled" and request.closed_by == 2 and latest(w, 2).actor == 3, "Student-hosted teaching lost its teacher's fulfillment knowledge")
	check(int(w.livelihood.records[1].social_appraisals.get(2, {}).get("support", 0)) == 1, "Present issuer did not witness the actual teacher's fulfilled obligation")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Witnessed student-hosted fulfillment failed recovery")

func _run() -> void:
	if "--witness" in OS.get_cmdline_user_args(): witnessed_student_host()
	elif "--borrowed" in OS.get_cmdline_user_args(): preparation_uses_own_rights(true)
	else: preparation_uses_own_rights()
	print("TEACHING_OBLIGATIONS_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
