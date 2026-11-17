extends "res://tests/activities_smoke.gd"

func lesson_world() -> RefCounted:
	var w: RefCounted = peaceful()
	for actor: int in w.actor_slots:
		w.livelihood.forget(actor)
		w.objects.records[actor].erase("methods")
		w.pages[0].hunger[actor - 1] = 10000
		w.pages[0].energy[actor - 1] = 10000
		w.pages[0].body_heat[actor - 1] = 22.0
		w.pages[0].positions[actor - 1] = Vector2(120.5 + actor, 120.5)
		w.clear_navigation(actor)
	w.Growth.seed(w.objects.records[2], "wood_breath", 0)
	w.Growth.seed(w.objects.records[2], "cooking", 0)
	w.sight.sync(w)
	return w

func learner(w: RefCounted, actor: int, method: String = "wood_breath") -> int:
	return w.livelihood.add_goal(w, actor, "development", {"method": method})

func autonomous(w: RefCounted, actor: int, subjects: Array) -> void:
	w.objects.records[actor].autonomous = true
	for subject: int in subjects:
		if w.actor_slots.has(subject): w.knowledge.refresh(w, actor, subject, w.elapsed_ms)
		else: w.knowledge.seed(w, actor, w.operation_target(subject), w.elapsed_ms)
	w.decisions.resume(w, actor, w.elapsed_ms)

func lesson_results(w: RefCounted, actor: int) -> Array:
	return w.activity_results.view(actor).filter(func(value: Dictionary): return value.status == "completed" and value.facts.get("points_gained", 0) > 0 and value.facts.has("teacher"))

func no_distant_lock() -> void:
	var w: RefCounted = lesson_world()
	w.pages[0].positions[0] = Vector2(110.5, 120.5)
	check(w.execute_operation(1, {"kind": "learn", "target": 2}) == "accepted", "Distant learning could not approach")
	check(w.society.waits.is_empty() and not w.reservations.has(2), "Distant learning locked its teacher")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Teaching approach failed recovery")
	w.end_run(1, 0, "path_failed")
	check(w.activity_results.view(2).is_empty(), "Approach invented teacher attendance")

func symmetric_and_recovery() -> void:
	var w: RefCounted = lesson_world()
	learner(w, 3)
	var purpose: int = w.livelihood.add_goal(w, 2, "instruction", {"method": "wood_breath", "target": 3})
	check(w.execute_operation(2, {"kind": "teach_wood_breath", "target": 3}) == "accepted", "Teacher could not initiate instruction")
	w.settle_action(2, 0)
	check(w.society.waits.has(3) and w.actions[2].participants == [2, 3], "Teacher did not acquire a willing student on site")
	advance(w, 400)
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Actual shared teaching failed recovery")
	if restored == null: return
	advance(w, 1300); advance(restored, 1300)
	check(w.objects.records[3].methods == restored.objects.records[3].methods and w.activity_results.records == restored.activity_results.records, "Restoring teaching changed its single result")
	var result: Dictionary = latest(w, 3)
	check(result.actor == 2 and result.facts.teacher == 2 and result.facts.learner == 3 and result.facts.understood and result.participants == [2, 3], "Teaching swapped roles or lost attendance")
	check(w.objects.records[3].methods.wood_breath.source == "learn" and w.objects.records[3].methods.wood_breath.teacher == 2 and not w.Growth.mastered(w.objects.records[3], "wood_breath"), "Lesson granted mastery without practice or lost source")
	check(w.livelihood.records[2].goals[purpose].state == "completed" and int(w.livelihood.records[3].social_appraisals[2].support) == 1, "Same lesson did not support the teacher's purpose and learner's experience")
	check(w.knowledge.view(3, 2, 1300).get("teaches", {}).has("wood_breath") and not w.knowledge.view(2, 3, 1300).get("teaches", {}).has("wood_breath"), "Teacher-led lesson inverted private teaching knowledge")
	var count: int = w.activity_results.next_id
	w.end_run(2, 1300, "completed")
	check(w.activity_results.next_id == count, "Teaching published a second terminal result")

func complementary_and_player() -> void:
	var w: RefCounted = lesson_world()
	learner(w, 3)
	check(w.execute_operation(2, {"kind": "teach_wood_breath", "target": 3}) == "accepted" and w.execute_operation(3, {"kind": "learn", "target": 2}) == "accepted", "Complementary commands could not approach")
	w.settle_action(3, 0)
	advance(w, 1300)
	check(lesson_results(w, 3).size() == 1 and w.society.waits.is_empty() and not w.actions.has(2), "Complementary commands deadlocked or taught twice")
	var p: RefCounted = lesson_world()
	check(p.execute_operation(2, {"kind": "teach_wood_breath", "target": 1}) == "accepted", "NPC could not approach player to offer teaching")
	p.settle_action(2, 0)
	check(p.actions[2].get("join_reason") == "awaiting_participant" and p.gate.current(1).is_empty() and not p.actions[2].has("started_ms"), "NPC unilaterally enrolled the player")
	var data: Dictionary = Persistence.capture(p)
	check(Persistence.candidate(data, 0) != null, "A bounded join window failed recovery")
	var bad: Dictionary = data.duplicate(true)
	bad.domains.world.actions[2].join_until_ms = 1000000
	check(Persistence.candidate(bad, 0) == null, "Unbounded lesson wait was accepted")
	bad = data.duplicate(true)
	bad.domains.world.actions[2].partner_free = true
	check(Persistence.candidate(bad, 0) == null, "Unilateral lesson participation was accepted")
	check(p.execute_operation(1, {"kind": "learn", "target": 2}) == "accepted", "Player could not actively join the offered method")
	p.settle_action(1, 0)
	check(p.actions.has(1) and not p.actions.has(2) and p.society.waits.has(2), "Player's own host did not adopt explicit participation")
	advance(p, 1300)
	check(lesson_results(p, 1).size() == 1 and p.objects.records[1].methods.wood_breath.teacher == 2, "Explicit player participation did not learn")
	var timeout: RefCounted = lesson_world()
	timeout.execute_operation(2, {"kind": "teach_wood_breath", "target": 1})
	timeout.settle_action(2, 0)
	advance(timeout, 5500)
	check(not timeout.objects.records[1].has("methods") and latest(timeout, 2).reason == "awaiting_participant" and timeout.society.waits.is_empty(), "Unanswered offer taught the player or waited forever")

func real_motives_and_cancellation() -> void:
	var w: RefCounted = lesson_world()
	learner(w, 3)
	w.pages[0].hunger[2] = 500
	check(w.execute_operation(2, {"kind": "teach_wood_breath", "target": 3}) == "accepted", "Teacher could not approach hungry learner")
	w.settle_action(2, 0)
	check(latest(w, 2).reason == "refused_need" and not w.objects.records[3].has("methods") and w.society.waits.is_empty(), "A lesson overrode the learner's urgent need")
	var unwilling: RefCounted = lesson_world()
	unwilling.execute_operation(2, {"kind": "teach_wood_breath", "target": 3})
	unwilling.settle_action(2, 0)
	check(latest(unwilling, 2).reason == "not_interested", "A learner with no relevant purpose was forced to learn")
	var interrupted: RefCounted = lesson_world()
	learner(interrupted, 3)
	interrupted.execute_operation(2, {"kind": "teach_wood_breath", "target": 3})
	interrupted.settle_action(2, 0)
	advance(interrupted, 400)
	interrupted.end_run(3, 400, "replaced")
	check(not interrupted.objects.records[3].has("methods") and interrupted.actions.is_empty() and interrupted.society.waits.is_empty() and latest(interrupted, 2).reason == "partner_left", "Leaving teaching granted effects or leaked occupation")
	check(Persistence.candidate(Persistence.capture(interrupted), 0) != null, "Interrupted teaching could not recover")

func organizational_teaching(student_host: bool, already: bool = false) -> void:
	var w: RefCounted = lesson_world()
	var org: int = w.institutions.create("青禾宗")
	w.institutions.admit(w, org, 1, ["commission"])
	w.institutions.admit(w, org, 2, [])
	w.institutions.admit(w, org, 3, [])
	w.knowledge.seed(w, 1, w.operation_target(3), 0)
	var matter: int = w.institutions.create_matter(w, 1, {"kind": "operation", "operation": "teach_wood_breath", "organization": org, "target": 3})
	check(matter > 0, "A member could not be the subject of authorized instruction")
	if matter == 0: return
	var share: int = w.institutions.accept_share(w, 2, matter)
	check(share > 0 and w.institutions.Matters.grants(w.institutions, w, 2).is_empty(), "Teaching granted stock rights over a member or failed acceptance")
	check(w.institutions.create_matter(w, 2, {"kind": "operation", "operation": "teach_wood_breath", "organization": org, "target": 3}) == 0, "Membership or an accepted teaching task minted commission authority")
	var purpose: int = w.livelihood.add_goal(w, 2, "instruction", {"method": "wood_breath", "target": 3})
	if already:
		w.Growth.seed(w.objects.records[3], "wood_breath", 0, false)
		w.execute_operation(2, {"kind": "teach_wood_breath", "target": 3})
		w.settle_action(2, 0)
	else:
		learner(w, 3)
		var actor: int = 3 if student_host else 2
		w.execute_operation(actor, {"kind": "learn" if student_host else "teach_wood_breath", "target": 2 if student_host else 3})
		w.settle_action(actor, 0)
		advance(w, 1300)
	var result: Dictionary = latest(w, 2)
	check(w.institutions.shares[share].state == ("released" if already else "completed") and w.institutions.shares[share].fulfilled == (0 if already else 1), "Teaching obligation credited the wrong participant or invented a lesson")
	check(w.institutions.matters[matter].state == ("satisfied" if already else "completed") and w.livelihood.records[2].goals[purpose].state == "completed", "Same lesson/discovery did not resolve its relevant purposes")
	w.institutions.outcome(w, result)
	check(w.institutions.shares[share].fulfilled == (0 if already else 1) and Persistence.candidate(Persistence.capture(w), 0) != null, "Teaching replay or restoration duplicated fulfillment")

func _run() -> void:
	no_distant_lock()
	symmetric_and_recovery()
	complementary_and_player()
	real_motives_and_cancellation()
	organizational_teaching(false)
	organizational_teaching(true)
	organizational_teaching(false, true)
	print("TEACHING_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
