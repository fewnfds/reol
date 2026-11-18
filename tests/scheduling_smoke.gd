extends "res://tests/agency_food_smoke.gd"
## Deferred work is allowed to finish later; authoritative consequences are not.

class HeldSelection extends "res://scripts/sim/kernel/agency_selection.gd":
	var permit := Semaphore.new()
	func run() -> void:
		permit.wait()
		super.run()

class IgnoreContactDecisions extends "res://scripts/sim/kernel/decisions.gd":
	func policy(world: RefCounted, actor: int) -> Dictionary:
		# The authoring schema supports ignore; stock resident currently fights.
		# Substitute policy data, keeping the production coordination unchanged.
		var spec: Dictionary = super.policy(world, actor).duplicate()
		spec.response = "ignore"
		return spec

func independent_timers() -> void:
	var w: RefCounted = peaceful()
	w.objects.records[2].autonomous = true
	w.decisions.wake(w, 2, 0, "institution_review", 10000)
	check(not w.decisions.records[2].life_dirty, "Future appointment dirtied current planning")
	w.decisions.wake(w, 2, 0, "space_needed", 31)
	w.decisions.wake(w, 2, 0, "life_result", 500)
	check(w.decisions.next_boundary(0, 50) == 50, "Soft deadline split every body's motion")
	w.decisions.prepare(w, 31)
	check(w.decisions.wakeups[2].has("institution_review") and w.decisions.records[2].next_ms == 500, "Local wake erased unrelated future timers")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null and restored.decisions.wakeups[2].get("institution_review") == 10000, "Save lost a later timer hidden behind a nearer wake")
	var legacy: Dictionary = Persistence.capture(w)
	legacy.domains.decisions.wakeups[2] = "life_result"
	var old: RefCounted = Persistence.candidate(legacy, 0)
	check(old != null and old.decisions.wakeups[2].get("life_result") == 500, "Current v32 single-reason save no longer loads")
	var invalid: Dictionary = Persistence.capture(w)
	invalid.domains.decisions.wakeups[2].institution_review = -1
	check(Persistence.candidate(invalid, 0) == null, "Invalid calendar deadline was accepted")
	invalid = Persistence.capture(w)
	invalid.domains.decisions.records[2] = "invalid"
	check(Persistence.candidate(invalid, 0) == null, "Malformed actor record did not fail cleanly before calendar normalization")

func local_clearance() -> void:
	var w: RefCounted = peaceful()
	var life := preload("res://scripts/sim/kernel/livelihood.gd").new()
	w.livelihood = life
	move_actor(w, 2, Vector2(123.5, 120.5))
	move_actor(w, 3, Vector2(123.5, 120.5))
	w.objects.records[2].autonomous = true
	for actor: int in w.actor_slots: w.knowledge.record(actor).due_ms = 5000
	var observed: int = w.knowledge.observations
	w.decisions.wake(w, 2, 0, "space_needed", 31)
	w.step(31)
	w.decisions.prepare(w, 31)
	check(w.decisions.records[2].task.get("purpose") == "clearance" and w.work_runs.has(2), "Idle obstruction did not adopt a local clearance motion")
	check(life.decisions == 0, "Clearance entered whole-life planning")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "In-progress clearance could not be restored")
	advance(w, 1500)
	check(not w.work_runs.has(2) and life.decisions == 0 and w.knowledge.observations == observed, "Clearance arrival triggered full observation or planning")
	resident(w, 2, [])
	w.decisions.wake(w, 2, w.elapsed_ms, "needs_changed")
	w.decisions.prepare(w, w.elapsed_ms)
	decide(w, w.elapsed_ms)
	check(life.decisions == 1, "One no-host stimulus started duplicate personal proposals")

func bounded_queue() -> void:
	var queue := preload("res://scripts/sim/execution/deferred_work.gd").new()
	for actor: int in range(1, 41): queue.request("life", actor, 0, 1)
	queue.request("life", 1, 10, 0)
	check(queue.ready.size() == 40 and queue.ready[queue.key("life", 1)].first_ms == 0, "Repeated stimulus duplicated work or reset waiting age")
	var served: Dictionary = {}
	for item: int in 40:
		var entry: Dictionary = queue.take(600, {})
		check(not entry.is_empty() and not served.has(entry.actor), "Aged work was starved by duplicate high-priority requests")
		served[entry.actor] = true
	check(served.size() == 40 and queue.ready.is_empty(), "Queue failed to serve every waiting subject")
	for actor: int in range(1, 9): queue.request("life", actor, 0, 0)
	queue.request("observe", 1, 100, 2)
	var domains: Array[String] = []
	for piece: int in 2: domains.append(queue.take(600, {}).domain)
	check(domains.has("observe"), "An old planning backlog consumed the observation dependency's service turn")

func pending_is_not_a_stimulus() -> void:
	var w: RefCounted = peaceful()
	resident(w, 2, [])
	w.decisions.released(2)
	w.decisions.wake(w, 2, 0, "life_pending")
	w.deferred.request("life", 2, 0)
	var before: int = w.decisions.evaluations
	for at: int in range(0, 50): w.decisions.prepare(w, at)
	check(w.decisions.evaluations == before and w.deferred.ready.size() == 1, "Waiting for one proposal repeated whole decision coordination at every substep")
	w.decisions.wake(w, 2, 0, "space_needed")
	w.service_deferred()
	check(w.decisions.wakeups.get(2, {}).get("space_needed") == 0, "Starting/completing a proposal consumed an unrelated due event")

func clearance_preserves_review() -> void:
	var w: RefCounted = peaceful()
	resident(w, 2, [])
	w.decisions.released(2)
	move_actor(w, 2, Vector2(123.5, 120.5))
	move_actor(w, 3, Vector2(123.5, 120.5))
	w.pages[0].move_speed[1] = 0.5
	w.decisions.wake(w, 2, 0, "space_needed")
	w.decisions.prepare(w, 0)
	check(w.decisions.records[2].task.get("purpose") == "clearance", "Review fixture failed to start a real local clearance")
	w.decisions.wake(w, 2, 0, "life_result", 100)
	advance(w, 150)
	w.decisions.prepare(w, w.elapsed_ms)
	check(w.decisions.records[2].task.get("reconsider", false) or w.livelihood.decisions > 0, "Ordinary review due during clearance was silently forgotten")
	w.pages[0].move_speed[1] = 5.0
	advance(w, 1000)
	check(w.livelihood.decisions > 0 or w.decisions.wakeups.get(2, {}).has("life_pending"), "Clearance completed without resuming the owed ordinary review")

func local_scan_targets(w: RefCounted, start: Vector2i) -> Array[int]:
	# Leave work after the maximum number of slices a single observer can get
	# in one service call, even with no wall-clock budget in the serial checks.
	var targets: Array[int] = []
	for index: int in w.knowledge.SCAN_TARGETS * 4 + 1:
		var tile: int = w.Terrain.index(start + Vector2i(index % 10, index / 10))
		var target: int = w.objects.create("pile", "wood", tile)
		w.objects.add(target, "wood", 1)
		targets.append(target)
	return targets

func exploration_observation_resumes() -> void:
	var w: RefCounted = peaceful()
	resident(w, 2, [])
	w.decisions.released(2)
	move_actor(w, 2, Vector2(125.5, 125.5))
	w.pages[0].hunger[1] = 500
	w.objects.add(2, "meal", -w.objects.amount(2, "meal"))
	local_scan_targets(w, Vector2i(126, 126))
	var food: int = w.objects.create("pile", "meal", w.Terrain.index(Vector2i(125, 125)))
	w.objects.add(food, "meal", 1)
	w.adopt_motion(2, 0)
	w.pages[0].modes[1] = w.Units.Mode.EXPLORE
	w.settle(2, 0)
	w.decisions.prepare(w, 0)
	w.service_deferred()
	check(w.knowledge._scans.has(2) and w.decisions.wakeups.get(2, {}).has("exploration_observe"), "Exploration did not retain its unfinished observation dependency")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Exploration/observation dependency failed to restore")
	if restored == null: return
	advance(restored, 3000)
	check(restored.pages[0].hunger[1] > 3000 and restored.objects.amount(food, "meal") == 0, "Restored explorer failed to observe, select and consume actual discovered food")

func exploration_retires_inflight_plan() -> void:
	for workers: int in [0, 2]:
		var w: RefCounted = peaceful()
		w.configure_lanes(workers)
		resident(w, 2, [])
		w.decisions.released(2)
		move_actor(w, 2, Vector2(125.5, 125.5))
		w.pages[0].hunger[1] = 500
		w.objects.add(2, "meal", -w.objects.amount(2, "meal"))
		local_scan_targets(w, Vector2i(127, 126))
		w.adopt_motion(2, 0)
		w.pages[0].move_to(1, Vector2(126.5, 125.5), w.Units.Mode.EXPLORE)
		var original: RefCounted = w.livelihood.prepare_plan(w, 2, 0)
		check(original != null, "Explorer could not prepare its in-transit proposal")
		if original == null: continue
		var held: HeldSelection = null
		var job: RefCounted = original
		if workers != 0:
			held = HeldSelection.new()
			held.input = original.input
			job = held
		var identity: String = w.deferred.key("life", 2)
		w.deferred.request("life", 2, 0)
		w.deferred.start(identity, job, workers)
		if workers != 0: w.deferred.ready.erase(identity)
		w.decisions.wake(w, 2, 0, "life_pending")
		var food: int = w.objects.create("pile", "meal", w.Terrain.index(Vector2i(126, 125)))
		w.objects.add(food, "meal", 1)
		# Real motion reaches its endpoint while the old proposal is unfinished.
		# Observing that endpoint is a new prerequisite, not completion of the job.
		w.step(1000)
		check(w.gate.current(2).is_empty() and w.decisions.wakeups.get(2, {}).has("exploration_observe"), "Explorer did not arrive before its unfinished local scan")
		check(not w.deferred.jobs.has(identity) and not w.livelihood._reserved_work.has(2), "Observation prerequisite orphaned an in-flight proposal or its allowance: workers=" + str(workers))
		if held != null: held.permit.post()
		advance(w, 4000)
		check(w.pages[0].hunger[1] > 3000 and w.objects.amount(food, "meal") == 0, "Arrived explorer never resumed after retiring its old proposal: workers=" + str(workers))
		w.deferred.close()

func ignored_contact_preserves_review() -> void:
	var w: RefCounted = peaceful()
	var coordinator := IgnoreContactDecisions.new()
	coordinator.records = w.decisions.records
	coordinator.wakeups = w.decisions.wakeups
	coordinator.next_task = w.decisions.next_task
	w.decisions = coordinator
	resident(w, 2, [])
	w.pages[0].hunger[1] = 500
	w.objects.add(2, "meal", 1 - w.objects.amount(2, "meal"))
	w.livelihood._ensure_goals(w, 2)
	w.adopt_motion(2, 0)
	w.pages[0].move_to(1, Vector2(220.5, 120.5), w.Units.Mode.EXPLORE)
	w.decisions.prepare(w, 0)
	w.decisions.service(w, 2, 0)
	var identity: String = w.deferred.key("life", 2)
	check(w.deferred.jobs.has(identity) and not w.decisions.records[2].life_dirty, "Contact fixture did not start its owed replacement review")
	check(w.combat.remember_contact(w, 2, 0, Vector2(130.5, 120.5), false, 0) == "accepted", "Contact fixture failed to report an actual directional threat")
	w.service_deferred() # Contact arrived after prepare, before proposal adoption.
	check(not w.deferred.jobs.has(identity), "Pending threat retained an adoptable life proposal")
	w.decisions.prepare(w, 0) # This policy ignores the threat and keeps its old walk.
	check(not w.combat.engagements.has(2) and w.decisions.wakeups.get(2, {}).has("life_pending"), "Ignored contact erased the owed needs review of a still running host: " + JSON.stringify({"record": w.decisions.records[2], "timers": w.decisions.wakeups.get(2, {}), "gate": w.gate.current(2)}))
	advance(w, 2500)
	check(w.pages[0].hunger[1] > 3000 and w.objects.amount(2, "meal") == 0, "Ignored short contact left a hungry actor in its old long walk")

func fresh_reviews_and_cancel_budget() -> void:
	var w: RefCounted = peaceful()
	move_actor(w, 1, Vector2(123.5, 120.5))
	move_actor(w, 2, Vector2(123.5, 120.5))
	resident(w, 2, [])
	w.decisions.released(2)
	var job: RefCounted = w.livelihood.prepare_plan(w, 2, 0)
	job.run()
	w.objects.claim(w.source_objects[0], 1, "wood", 4)
	var target: int = w.facilities.blueprint(w, 1, "wood_wall", w.Terrain.index(Vector2i(127, 122))).target
	var sent: Dictionary = w.society.deliver_request(w, 1, {"kind": "request_help", "target": 2, "task_target": target}, 0)
	check(sent.status == "completed", "Fresh review fixture failed to deliver its actual request")
	var request: int = int(sent.facts.get("request", 0))
	if request == 0: return
	w.society.respond(w, 2, request, "defer", 0)
	w.livelihood.complete_plan(w, 2, job, 0)
	check(w.decisions.wakeups.get(2, {}).get("request_review") == w.society.requests[request].review_ms, "Proposal completion scheduled reviews from its old request snapshot")
	var budgeted: RefCounted = w.livelihood.prepare_plan(w, 2, 0)
	check(budgeted != null, "Cancellation allowance fixture did not prepare")
	if budgeted == null: return
	var hold: int = w.livelihood._reserved_work[2].amount
	var consumed: int = w.livelihood.records[2].budget.work
	w.livelihood.cancel_plan(2)
	check(w.livelihood.records[2].budget.work == consumed + hold, "Cancel/restart refunded the entire same-window issued query allowance")

func background_completion_and_temporary_gate() -> void:
	var w: RefCounted = peaceful()
	w.configure_lanes(2)
	var held_jobs: Array = []
	for actor: int in [2, 3]:
		resident(w, actor, [])
		w.decisions.released(actor)
		w.objects.add(actor, "meal", 1)
		w.pages[0].hunger[actor - 1] = 500
		var held := HeldSelection.new()
		held.input = w.livelihood.prepare_plan(w, actor, 0).input
		held_jobs.append(held)
		w.deferred.start(w.deferred.key("life", actor), held, 2)
		w.decisions.wake(w, actor, 0, "life_pending")
	for actor: int in range(50, 58): w.deferred.request("life", actor, 0, 0)
	w.deferred.request("observe", 1, 0, 2)
	var status: Dictionary = w.combat._status(2)
	status.stun_until = 100
	w.step(50)
	check(w.elapsed_ms == 50 and w.deferred.jobs.size() == 2 and w.decisions.wakeups[2].has("life_pending"), "Temporary gate cancelled a still owed in-flight review or blocked the world")
	check(w.knowledge._scans.has(1) or w.knowledge.observations > 1, "Full background capacity starved ordinary observation")
	var restore: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restore != null, "Gated pending review failed current-format restore")
	for held: RefCounted in held_jobs: held.permit.post()
	var deadline: int = Time.get_ticks_usec() + 1000000
	while w.deferred.jobs.values().any(func(handle: Dictionary): return not WorkerThreadPool.is_task_completed(handle.task)) and Time.get_ticks_usec() < deadline: OS.delay_msec(1)
	w.combat.status.erase(2)
	w.service_deferred()
	check(not w.deferred.jobs.has(w.deferred.key("life", 2)) and not w.deferred.jobs.has(w.deferred.key("life", 3)), "Older blocked admissions starved already completed background results")
	if restore != null:
		advance(restore, 1500)
		check(restore.pages[0].hunger[1] > 3000, "Restored temporarily gated pending review failed to resume")

func partner_resumes_owed_review() -> void:
	var w: RefCounted = peaceful()
	move_actor(w, 2, Vector2(124.5, 120.5))
	move_actor(w, 3, Vector2(124.5, 120.5))
	resident(w, 2, [])
	w.decisions.released(2)
	check(w.begin_interaction(3, {"kind": "talk", "target": 2}) == "accepted", "Partner resume fixture could not start a conversation")
	w.settle_action(3, 0)
	check(w.gate.current(2).get("domain") == "partner", "Partner resume fixture never bound the actual participant")
	# Deferred planning may see the participant already bound to this contact.
	w.decisions.track_host(w, 2)
	check(w.decisions.records[2].task.get("binding") == w.gate.current(2), "Fixture failed to track the active partner run")
	w.end_run(3, 0, "interrupted")
	check(w.gate.current(2).is_empty() and w.decisions.records[2].task.is_empty(), "Ending a contact left the participant tracking a released run")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Ended contact made the current world unloadable")
	check(w.begin_interaction(3, {"kind": "talk", "target": 2}) == "accepted", "A new contact could not acquire the released participant")
	w.settle_action(3, 0)
	w.objects.add(2, "meal", 1 - w.objects.amount(2, "meal"))
	w.pages[0].hunger[1] = 500
	w.decisions.wake(w, 2, 0, "life_result", 100)
	advance(w, 3000)
	check(w.pages[0].hunger[1] > 3000 and w.objects.amount(2, "meal") == 0, "Review due while participating was lost when the shared activity ended: " + JSON.stringify({"binding":w.gate.current(2), "record":w.decisions.records[2], "timers":w.decisions.wakeups.get(2,{}), "action":w.actions.get(2,{}), "hunger":w.pages[0].hunger[1]}))

func incremental_observation() -> void:
	var w: RefCounted = peaceful()
	move_actor(w, 2, Vector2(123.5, 120.5))
	var targets: Array[int] = local_scan_targets(w, Vector2i(124, 122))
	w.knowledge.records.erase(2)
	w.deferred.request("observe", 2, 0, 2)
	w.service_deferred()
	check(int(w.knowledge._scans.get(2, {}).get("cursor", 0)) > 0 and int(w.knowledge.records[2].due_ms) == 0, "Ordinary scan did not retain a partially processed cursor")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null and restored.knowledge._scans.is_empty() and restored.knowledge.records[2].due_ms == 0, "In-progress scan was serialized as fact or lost its due request")
	var seen: Dictionary = w.knowledge.known(2, w.elapsed_ms)
	move_actor(w, 2, Vector2(180.5, 180.5))
	for attempt: int in 50:
		w.service_deferred()
		if not w.knowledge._scans.has(2): break
	check(not w.knowledge._scans.has(2), "Deferred observation failed to drain after movement")
	for target: int in targets:
		check(w.knowledge.view(2, target, w.elapsed_ms) == seen.get(target, {}), "Deferred scan learned hidden changes after moving away")

func asynchronous_lifecycle() -> void:
	var w: RefCounted = peaceful()
	w.configure_lanes(2)
	resident(w, 2, [])
	w.objects.add(2, "meal", 1)
	w.pages[0].hunger[1] = 1000
	var original: RefCounted = w.livelihood.prepare_plan(w, 2, 0)
	check(original != null, "Async fixture could not prepare detached input")
	if original == null: return
	var held := HeldSelection.new()
	held.input = original.input
	var identity: String = w.deferred.key("life", 2)
	w.deferred.start(identity, held, 2)
	w.decisions.wake(w, 2, 0, "life_pending")
	w.deferred.request("life", 2, 0)
	var saved: Dictionary = Persistence.capture(w)
	check(saved.domains.livelihood.records[2].budget.work == 0, "Unfinished worker reserved queries in saved consumed budget")
	var restored: RefCounted = Persistence.candidate(saved, 0)
	check(restored != null and restored.deferred.jobs.is_empty() and restored.decisions.wakeups[2].has("life_pending"), "Save waited for or persisted a worker instead of a recoverable request")
	w.step(17) # The worker is deliberately blocked; a join here hangs this test.
	check(w.elapsed_ms == 17 and not w.deferred.jobs.is_empty(), "World did not advance independently of a blocked soft worker")
	w.command({"kind": "interrupt", "actor": 2})
	check(w.deferred.jobs.is_empty() and w.decisions.records[2].manual, "Manual takeover retained an adoptable old proposal")
	held.permit.post()
	w.deferred.close() # Explicit teardown may wait and must collect cancelled work.
	check(w.actions.get(2, {}).is_empty() and w.decisions.records[2].manual, "Cancelled result restarted autonomous work")
	if restored != null:
		advance(restored, 1000)
		check(restored.actions.get(2, {}).get("kind") == "eat" or restored.pages[0].hunger[1] > 1000, "Restored pending proposal failed to resume through ordinary owner rules")

func stale_replacement_and_conflict() -> void:
	var w: RefCounted = peaceful()
	move_actor(w, 2, Vector2(123.5, 120.5))
	var food: int = w.objects.create("pile", "meal", w.Terrain.index(Vector2i(124, 120)))
	w.objects.add(food, "meal", 1)
	resident(w, 2, [food])
	w.objects.add(2, "meal", -w.objects.amount(2, "meal"))
	w.pages[0].hunger[1] = 500
	w.adopt_motion(2, 0)
	w.pages[0].move_to(1, Vector2(220.5, 120.5), w.Units.Mode.EXPLORE)
	var original: Dictionary = w.gate.current(2)
	var job: RefCounted = w.livelihood.prepare_plan(w, 2, 0)
	check(job != null, "Working actor could not prepare an urgent replacement")
	if job == null: return
	job.run()
	w.objects.add(food, "meal", -1)
	w.livelihood.complete_plan(w, 2, job, 0)
	check(w.gate.current(2) == original and w.pages[0].modes[1] == w.Units.Mode.EXPLORE, "Rejected stale replacement cancelled healthy current work")
	var replacement_food: int = w.objects.create("pile", "meal", w.Terrain.index(Vector2i(124, 121)))
	w.objects.add(replacement_food, "meal", 1)
	w.knowledge.seed(w, 2, w.operation_target(replacement_food), 0)
	advance(w, 3000)
	check(w.pages[0].hunger[1] > 3000 and w.objects.amount(replacement_food, "meal") == 0, "Refused busy preemption lost its scheduled retry against another available meal")
	var other: RefCounted = peaceful()
	var pile: int = other.objects.create("pile", "meal", other.Terrain.index(Vector2i(124, 122)))
	other.objects.add(pile, "meal", 1)
	var proposals: Array = []
	for actor: int in [2, 3]:
		move_actor(other, actor, Vector2(124.5, 122.5))
		other.objects.add(actor, "meal", -other.objects.amount(actor, "meal"))
		other.pages[0].hunger[actor - 1] = 500
		resident(other, actor, [pile])
		var proposal: RefCounted = other.livelihood.prepare_plan(other, actor, 0)
		proposal.run()
		proposals.append(proposal)
	for index: int in 2: other.livelihood.complete_plan(other, index + 2, proposals[index], 0)
	advance(other, 1300)
	check(other.objects.amount(pile, "meal") == 0 and other.facilities.completed.get("eat", 0) == 1, "Concurrent old proposals duplicated a single actual meal")
	check(Persistence.candidate(Persistence.capture(other), 0) != null, "Conflict resolution left invalid ownership or pending work")

func _run() -> void:
	independent_timers()
	local_clearance()
	bounded_queue()
	pending_is_not_a_stimulus()
	clearance_preserves_review()
	exploration_observation_resumes()
	exploration_retires_inflight_plan()
	ignored_contact_preserves_review()
	fresh_reviews_and_cancel_budget()
	background_completion_and_temporary_gate()
	partner_resumes_owed_review()
	incremental_observation()
	asynchronous_lifecycle()
	stale_replacement_and_conflict()
	print("SCHEDULING_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
