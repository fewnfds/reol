extends "res://tests/society_followup_smoke.gd"

func organization_cancel_messages() -> void:
	for canceller: int in [1, 4]:
		var f: Dictionary = commission_fixture()
		var w: RefCounted = f.world
		w.institutions.admit(w, int(f.org), 4, Array(w.institutions.PURPOSES))
		var matter: int = w.institutions.create_matter(w, 1, delivery_spec(f))
		var delivered: Dictionary = w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 3, "matter": matter}, 0)
		var id: int = int(delivered.facts.request)
		w.society.respond(w, 3, id, "defer", 0)
		var far: Vector2 = w.Terrain.center(w.terrain.nearest_open(w.Terrain.index(Vector2i(180, 180))))
		move_actor(w, 1, far); move_actor(w, 3, far + Vector2(0.2, 0.0))
		check(w.institutions.cancel_matter(w, canceller, matter), "Authorized cancellation fixture failed")
		check(w.society.requests[id].reply.state == "deferred" and w.society.requests[id].closed_by == canceller, "Cancellation delivered a wireless message or lost its source")
		contact(w, 1, {"kind": "talk", "target": 3})
		if canceller == 1:
			check(w.society.requests[id].reply.reason == "matter_closed", "The actual cancelling party could not report their own action")
		else:
			check(w.society.requests[id].reply.state == "deferred", "Conversation disclosed an unseen third-party administrative decision")
			contact(w, 3, {"kind": "respond_request", "target": 1, "request": id, "decision": "accept"})
			check(w.society.requests[id].reply.reason == "request_unavailable", "Third-party cancellation exposed its administrative cause")
			w.kill(4, w.elapsed_ms)
		check(Persistence.candidate(Persistence.capture(w), 0) != null, "Cancelled request and historical closing actor failed recovery")

func release_and_confirm() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	var id: int = send_help(w, int(f.target))
	w.society.respond(w, 3, id, "accept", 0)
	var share: int = w.society.requests[id].share
	check(w.institutions.release_share(w, 3, share), "Recipient could not explicitly release their responsibility")
	check(w.society.requests[id].reply.state == "accepted", "Release falsely delivered an instant message")
	contact(w, 1, {"kind": "talk", "target": 3})
	check(w.society.requests[id].reply.state == "cancelled" and w.society.requests[id].reply.reason == "share_released", "Actual release could not be reported by its participant")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Delivered release failed recovery")

func budget_limited_pending() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	healthy(w, 3)
	w.objects.records[3].autonomous = true
	w.livelihood.record(w, 3).budget = {"window_ms": 0, "work": 128, "cursor": 0, "goal_cursor": 0}
	var id: int = send_help(w, int(f.target))
	check(w.society.judge_request(w, 3, id, 0).is_empty() and w.society.requests[id].state == "pending", "Budget exhaustion falsely answered a pending request")
	w.decisions.resume(w, 3, 0)
	w.decisions.prepare(w, 0)
	advance(w, 14000)
	check(w.society.requests[id].share > 0 and w.society.requests[id].state == "fulfilled", "Ordinary planning starved the pending judgment's reserved budget: " + str({"request": w.society.requests[id], "life": w.livelihood.describe(3)}))
	check(int(w.livelihood.records[3].budget.work) <= 128 and Persistence.candidate(Persistence.capture(w), 0) != null, "Response bypassed the common work budget or failed recovery")

func partial_budget_wake() -> void:
	for amount: int in [111, 115, 127]:
		var f: Dictionary = private_fixture()
		var w: RefCounted = f.w
		resident(w, 3, [1, int(f.target)]); healthy(w, 3)
		w.livelihood.record(w, 3).budget = {"window_ms": 0, "work": amount, "cursor": 0, "goal_cursor": 0}
		var id: int = send_help(w, int(f.target))
		w.society.judge_request(w, 3, id, 0)
		w.livelihood.after_action(w, 3, 0)
		w.decisions.prepare(w, 0); advance(w, 6000)
		check(w.society.requests[id].accepted_ms >= 0, "Earlier life wake erased the remaining request budget deadline: " + str(amount))

func known_dead_peer() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	var id: int = send_help(w, int(f.target))
	w.society.respond(w, 3, id, "accept", 0)
	w.decisions.suspend(w, 3)
	w.kill(3, 0)
	check(not w.describe(1).requests[0].peer_known_dead, "Unobserved death became local knowledge")
	check(w.knowledge.refresh(w, 1, 3, 0), "Visible corpse could not be observed")
	var view: Dictionary = w.describe(1).requests[0]
	check(view.peer_known_dead and view.state == "accepted" and not w.livelihood.Planner.Contacts.responding(w.livelihood._self_view(w, 1), 31000), "Locally confirmed death kept prompting impossible contact or overwrote the remote party's message")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Personal corpse observation and unchanged shared message failed recovery")

func nonautonomous_busy_review() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	healthy(w, 3)
	w.livelihood.record(w, 3).budget = {"window_ms": 0, "work": 128, "cursor": 0, "goal_cursor": 0}
	var id: int = send_help(w, int(f.target))
	w.society.judge_request(w, 3, id, 0)
	advance(w, 500)
	check(w.execute_operation(4, {"kind": "talk", "target": 3}) == "accepted", "Resident's intervening contact could not start")
	w.settle_action(4, w.elapsed_ms)
	advance(w, 6000)
	check(w.society.requests[id].accepted_ms >= 1500 and w.society.requests[id].state == "fulfilled", "A nonautonomous resident lost its pending review while participating in another contact: " + str({"request":w.society.requests[id], "life":w.livelihood.describe(3), "decision":w.decisions.describe(3), "waits":w.society.waits}))
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Resident's delayed review failed recovery")

func interrupted_local_review() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	w.knowledge.records.erase(3)
	healthy(w, 3)
	w.livelihood.record(w, 3).budget = {"window_ms": 0, "work": 128, "cursor": 0, "goal_cursor": 0}
	var id: int = send_help(w, int(f.target))
	check(int(w.society.request_views(w, 3, 0)[0].peer_tile) >= 0, "Actual delivery did not convey its present issuer's location")
	w.society.judge_request(w, 3, id, 0)
	advance(w, 200)
	move_actor(w, 1, Vector2(128.5, 120.5))
	w.decisions.wake(w, 3, w.elapsed_ms, "notice")
	w.decisions.prepare(w, w.elapsed_ms)
	advance(w, 400); move_actor(w, 1, Vector2(123.7, 120.5))
	advance(w, 6000)
	check(w.society.requests[id].state == "fulfilled", "An earlier local wake while the issuer stepped away lost the pending review")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Local review after a temporary absence failed recovery")

func one_construction_request() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	resident(w, 3, [4, int(f.target)])
	w.objects.records[int(f.target)].owner = 3
	w.objects.records[int(f.target)].remaining_ms = 20000
	w.knowledge.created(w, 3, int(f.target), 0)
	w.objects.records[3]["capability_overrides"] = {"work": false}
	var other: int = w.spawn_actor(w.Terrain.index(Vector2i(124, 120)))
	w.objects.records[other].side = 0
	for person: int in [4, other]:
		w.society.Contacts.acknowledge(w.society, w, 3, person, 0)
		w.knowledge.refresh(w, 3, person, 0)
	healthy(w, 3); healthy(w, 4)
	w.livelihood.add_goal(w, 3, "operation", {"operation": "construct", "target": int(f.target)})
	w.decisions.prepare(w, 0); advance(w, 6000)
	check(w.society.requests.size() == 1 and w.society.requests.values()[0].state == "accepted", "A known in-progress single-place task generated more requests")
	check(w.activity_results.view(3).filter(func(result: Dictionary): return result.operation == "request_help").size() == 1, "The same construction kept soliciting other acquaintances after acceptance")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Single allocated task and social follow-up state failed recovery")

func due_review_during_long_work() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	w.objects.add(1, "wood", 4)
	var site: Dictionary = w.facilities.blueprint(w, 1, "wood_wall", w.Terrain.index(Vector2i(126, 125)))
	check(site.reason == "accepted", "Long-work interruption fixture failed placement")
	if site.reason != "accepted": return
	w.objects.records[site.target].remaining_ms = 30000
	resident(w, 3, [1, int(f.target), int(site.target)]); healthy(w, 3)
	w.livelihood.set_dispositions(w, 3, {"dutifulness": 0.5})
	var matter: int = w.institutions.create_matter(w, 1, {"kind": "operation", "target": int(site.target), "operation": "construct"})
	check(w.institutions.accept_share(w, 3, matter) > 0, "Existing long responsibility failed acceptance")
	var id: int = send_help(w, int(f.target))
	check(w.society.judge_request(w, 3, id, 0).reason == "deferred_busy", "Existing duty did not produce an explicit bounded deferral")
	w.decisions.prepare(w, 0); advance(w, 18000)
	check(w.objects.records[site.target].kind == "blueprint" and w.society.requests[id].state == "refused", "Due review was swallowed by a long lower-scored host instead of actually answering: " + str({"request":w.society.requests[id], "life":w.livelihood.describe(3)}))
	check(w.activity_results.view(3).any(func(result: Dictionary): return result.operation == "respond_request" and result.status == "completed"), "The long-work test changed the request without actual contact")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Interrupted long work and actual response failed recovery")

func history_does_not_starve_response() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	for iteration: int in w.society.Requests.RECENT_LIMIT:
		var matter: int = w.institutions.create_matter(w, 1, delivery_spec(f, 1, 1))
		var delivered: Dictionary = w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 3, "matter": matter}, w.elapsed_ms)
		check(delivered.status == "completed", "Historical offer failed actual delivery")
		if delivered.status != "completed": return
		check(w.society.respond(w, 3, int(delivered.facts.request), "refuse", w.elapsed_ms).status == "completed", "Historical offer was not actually refused")
	advance(w, 30001)
	w.objects.add(f.source, "grain", 1, Stock.right(0, int(f.org)))
	resident(w, 3, [1, int(f.source), int(f.destination)])
	healthy(w, 3)
	var matter: int = w.institutions.create_matter(w, 1, delivery_spec(f, 1, 1))
	var delivered: Dictionary = w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 3, "matter": matter}, w.elapsed_ms)
	check(delivered.status == "completed" and w.society.requests.size() == 33, "New request did not follow the retained closed history")
	if delivered.status != "completed": return
	var id: int = int(delivered.facts.request)
	w.decisions.prepare(w, w.elapsed_ms); advance(w, 48000)
	check(w.society.requests[id].state == "fulfilled" and w.objects.amount(f.destination, "grain") == 1, "Closed history consumed every response scan before its later pending request: " + str(w.livelihood.describe(3)))
	check(w.activity_results.view(3).any(func(result: Dictionary): return result.operation == "respond_request" and result.status == "completed"), "New request bypassed actual follow-up contact")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Retained request history and actual new fulfilment failed recovery")

func exhausted_budget_keeps_need_review() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	resident(w, 3, [int(f.target)]); healthy(w, 3)
	w.objects.add(3, "meal", 1)
	w.objects.records[int(f.target)].remaining_ms = 30000
	w.livelihood.add_goal(w, 3, "operation", {"operation": "construct", "target": int(f.target)})
	w.decisions.prepare(w, 0); advance(w, 500)
	check(w.actions.get(3, {}).get("kind") == "construct", "Budget-need fixture did not enter long work")
	w.livelihood.records[3].budget.work = 98
	w.pages[0].hunger[2] = 1000
	w.decisions.wake(w, 3, w.elapsed_ms, "needs_changed")
	w.decisions.prepare(w, w.elapsed_ms)
	check(w.decisions.records[3].life_dirty and w.decisions.records[3].next_ms > w.elapsed_ms, "Unexamined emergency was dropped at the exhausted preemption budget")
	advance(w, 4500)
	check(w.activity_results.view(3).any(func(result: Dictionary): return result.operation == "eat" and result.status == "completed"), "The next budget window did not actually interrupt long work for food")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Deferred budget preemption failed recovery")

func player_participation_is_explicit() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	check(w.execute_operation(3, {"kind": "talk", "target": 1}) == "accepted", "NPC-to-player conversation refused")
	w.settle_action(3, 0)
	var state: Dictionary = Persistence.capture(w)
	check(state.domains.world.actions[3].get("partner_free", false) and Persistence.candidate(state, 0) != null, "NPC-to-player explicit free participation failed")
	var bad: Dictionary = state.duplicate(true)
	bad.domains.world.actions[3].erase("partner_free")
	check(Persistence.candidate(bad, 0) == null, "Player-targeted contact restored without a participation mode")
	bad = state.duplicate(true)
	bad.domains.world.actions[3].kind = "study"
	bad.domains.world.actions[3].erase("partner_free")
	check(Persistence.candidate(bad, 0) == null, "A solo study restored with invented two-person attendance")

func unknown_followups_do_not_starve_incoming() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	w.institutions.admit(w, int(f.org), 3, Array(w.institutions.PURPOSES))
	for target: int in [int(f.source), int(f.destination)]: w.knowledge.seed(w, 3, w.operation_target(target), 0)
	var matter: int = w.institutions.create_matter(w, 3, delivery_spec(f, 16, 1))
	for iteration: int in 16:
		var helper: int = 4 if iteration == 0 else w.spawn_actor(w.Terrain.index(Vector2i(124, 120)))
		w.objects.records[helper].side = 0
		w.institutions.admit(w, int(f.org), helper, [])
		move_actor(w, helper, Vector2(123.8, 120.5))
		var delivered: Dictionary = w.society.deliver_request(w, 3, {"kind": "offer_matter", "target": helper, "matter": matter}, 0)
		check(delivered.status == "completed", "Actual old follow-up could not be delivered")
		if delivered.status != "completed": return
		check(w.society.respond(w, helper, int(delivered.facts.request), "accept", 0).reason == "accepted_share", "Actual old follow-up could not be accepted")
		w.decisions.suspend(w, helper)
		move_actor(w, helper, w.Terrain.center(w.terrain.nearest_open(w.Terrain.index(Vector2i(180, 180)))))
	advance(w, 61001)
	w.objects.add(1, "wood", 4)
	var site: Dictionary = w.facilities.blueprint(w, 1, "wood_wall", w.Terrain.index(Vector2i(129, 122)))
	w.objects.records[site.target].remaining_ms = 1200
	var incoming: int = send_help(w, int(site.target))
	resident(w, 3, [1, int(site.target)]); healthy(w, 3)
	w.livelihood._ensure_goals(w, 3)
	for target: int in w.objects.records:
		if w.livelihood.records[3].goals.size() >= 16: break
		if w.objects.records[target].kind == "resource": w.livelihood.add_goal(w, 3, "operation", {"operation": "talk", "target": target})
	w.livelihood.records[3].budget.work = 110
	w.livelihood.records[3].budget.cursor = 0
	w.decisions.prepare(w, w.elapsed_ms); advance(w, w.elapsed_ms + 7000)
	check(w.society.requests[incoming].state == "refused" and w.society.requests[incoming].reason == "refused_capacity" and w.activity_results.view(3).any(func(result: Dictionary): return result.operation == "respond_request" and result.status == "completed"), "Sixteen unseen accepted follow-ups and a full purpose catalog starved a fresh incoming answer")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Many outstanding contacts and an actual capacity refusal failed recovery")

func waiting_for_one_reply_is_local() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	w.livelihood.record(w, 3)
	w.objects.records[int(f.target)].owner = 3
	w.knowledge.created(w, 3, int(f.target), 0)
	var delivered: Dictionary = contact(w, 3, {"kind": "request_help", "target": 1, "task_target": int(f.target)})
	var first: int = int(delivered.facts.request)
	w.society.respond(w, 1, first, "defer", w.elapsed_ms)
	var answer: Dictionary = contact(w, 3, {"kind": "respond_request", "target": 1, "request": first})
	check(answer.reason == "awaiting_response", "Player's deferred request was not kept pending")
	check(w.livelihood.records[3].appraisals.has("respond_request:1:%d" % first) and Persistence.candidate(Persistence.capture(w), 0) != null, "Awaiting a specific reply did not save its own bounded retry")
	w.objects.add(1, "wood", 4)
	var site: Dictionary = w.facilities.blueprint(w, 1, "wood_wall", w.Terrain.index(Vector2i(129, 122)))
	w.objects.records[site.target].remaining_ms = 1200
	var second: int = send_help(w, int(site.target))
	w.objects.records[3].autonomous = true
	w.knowledge.refresh(w, 3, 1, w.elapsed_ms)
	w.knowledge.seed(w, 3, w.operation_target(int(site.target)), w.elapsed_ms)
	w.decisions.resume(w, 3, w.elapsed_ms); healthy(w, 3)
	w.decisions.prepare(w, w.elapsed_ms); advance(w, w.elapsed_ms + 10000)
	check(w.society.requests[second].state == "fulfilled", "Waiting for a manual reply blocked a different incoming request from the same peer")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Per-request awaiting-response backoff failed recovery")

func absent_issuer() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	resident(w, 3, [1, int(f.target)])
	healthy(w, 3)
	var id: int = send_help(w, int(f.target))
	w.society.respond(w, 3, id, "defer", 0)
	move_actor(w, 1, w.Terrain.center(w.terrain.nearest_open(w.Terrain.index(Vector2i(180, 180)))))
	w.decisions.prepare(w, 0)
	advance(w, 30000)
	check(w.society.requests[id].share == 0 and not w.activity_results.view(3).any(func(result: Dictionary): return result.operation == "respond_request" and result.status == "completed"), "AI replied to an absent person from their remote current position")
	check(w.knowledge.view(3, 1, w.elapsed_ms).get("tile", -1) < 0, "AI kept chasing an absent peer's live location")
	w.kill(1, w.elapsed_ms)
	check(w.society.Requests.views(w.society, 3, w.elapsed_ms)[0].state == "deferred", "Remote death instantly entered the helper's personal messages")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Absent/dead issuer with an undelivered outcome failed recovery")

func free_participant_recovery() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	w.decisions.suspend(w, 3)
	check(w.execute_operation(1, {"kind": "talk", "target": 3}) == "accepted", "Manual participant contact could not start")
	w.settle_action(1, 0)
	check(w.actions[1].participants == [1, 3] and not w.society.waits.has(3), "Manual participant was seized into a partner host")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Actual unlocked manual participation could not recover")
	var bad: Dictionary = Persistence.capture(w)
	bad.domains.world.actions[1].erase("partner_free")
	check(Persistence.candidate(bad, 0) == null, "Unaccounted unlocked participation restored")
	bad.domains.world.actions[1].participants = [1]
	check(Persistence.candidate(bad, 0) == null, "A started contact restored with only its initiator")
	w.decisions.resume(w, 3, 0)
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Changing manual control erased the historical participation contract")
	advance(w, 1100)
	check(latest(w, 1).status == "completed", "An idle participant lost a valid conversation solely by resuming control")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--release" in args: release_and_confirm()
	elif "--budget" in args: budget_limited_pending()
	elif "--absent" in args: absent_issuer()
	elif "--unbound" in args: free_participant_recovery()
	elif "--partial-budget" in args: partial_budget_wake()
	elif "--known-dead" in args: known_dead_peer()
	elif "--resident-busy" in args: nonautonomous_busy_review()
	elif "--local-review" in args: interrupted_local_review()
	elif "--single-request" in args: one_construction_request()
	elif "--long-work" in args: due_review_during_long_work()
	elif "--history" in args: history_does_not_starve_response()
	elif "--need-budget" in args: exhausted_budget_keeps_need_review()
	elif "--player-participation" in args: player_participation_is_explicit()
	elif "--unseen-followups" in args: unknown_followups_do_not_starve_incoming()
	elif "--reply-scope" in args: waiting_for_one_reply_is_local()
	else: organization_cancel_messages()
	print("SOCIETY_FOLLOWUP_BOUNDARIES_SMOKE mode=", args, " errors=", errors)
	quit(0 if errors == 0 else 1)
