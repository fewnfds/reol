extends "res://tests/society_judgment_smoke.gd"

func explicit_player_response() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	w.objects.records[int(f.target)].owner = 3
	w.knowledge.created(w, 3, int(f.target), 0)
	var delivered: Dictionary = contact(w, 3, {"kind": "request_help", "target": 1, "task_target": int(f.target)})
	var id: int = int(delivered.facts.request)
	check(w.execute_operation(1, {"kind": "respond_request", "target": 3, "request": id}) == "response_required", "Player's silence was interpreted as an answer")
	check(w.execute_operation(4, {"kind": "respond_request", "target": 3, "request": id, "decision": "accept"}) == "invalid_response", "A third party answered the player's request")
	check(w.execute_operation(1, {"kind": "respond_request", "target": 3, "request": id, "decision": "accept"}) == "accepted", "Explicit player answer did not enter the shared host")
	w.settle_action(1, w.elapsed_ms)
	var state: Dictionary = Persistence.capture(w)
	check(Persistence.candidate(state, 0) != null, "In-progress explicit response failed recovery")
	var bad: Dictionary = state.duplicate(true)
	bad.domains.world.actions[1].decision = "invented"
	check(Persistence.candidate(bad, 0) == null, "Invalid in-progress response decision restored")
	advance(w, w.elapsed_ms + 1100)
	check(latest(w, 1).reason == "accepted_share" and w.society.requests[id].state == "accepted" and not w.objects.records[1].autonomous, "Player acceptance did not preserve control and create the ordinary Share")
	check(w.describe(1).requests[0].state == "accepted" and not w.describe(3).has("requests"), "Normal presentation leaked another person's request history")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Player's accepted response failed recovery")

func defer_eat_then_return(recover: bool) -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	resident(w, 3, [1, int(f.target)])
	healthy(w, 3)
	w.pages[0].hunger[2] = 2800
	w.objects.add(3, "meal", 2)
	w.objects.records[3].autonomous = true
	var id: int = send_help(w, int(f.target))
	check(w.society.judge_request(w, 3, id, 0).reason == "deferred_need", "Temporary need did not defer the actual delivered request")
	w.decisions.resume(w, 3, 0)
	w.decisions.prepare(w, 0)
	advance(w, 6000)
	check(w.society.requests[id].accepted_ms < 0, "AI answered before its deferred review time")
	check(w.activity_results.view(3).any(func(result: Dictionary): return result.operation == "eat" and result.status == "completed"), "AI did not actually eat before returning to its deferred social purpose")
	if recover:
		var loaded: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
		check(loaded != null, "Deferred request after a real meal could not recover")
		if loaded == null: return
		w = loaded
	advance(w, 24000)
	check(w.society.requests[id].accepted_ms >= 10000 and w.society.requests[id].state == "fulfilled" and w.objects.records[int(f.target)].kind == "wall", "Deferred AI did not return, answer and perform the real work: " + str({"request": w.society.requests[id], "life": w.livelihood.describe(3), "task": w.decisions.describe(3)}))
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Completed deferred response and work failed recovery")

func hidden_third_party_completion() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	var id: int = send_help(w, int(f.target))
	w.society.respond(w, 3, id, "defer", 0)
	w.decisions.suspend(w, 3)
	var far: Vector2 = w.Terrain.center(w.terrain.nearest_open(w.Terrain.index(Vector2i(180, 180))))
	move_actor(w, 1, far); move_actor(w, 3, far + Vector2(0.2, 0.0))
	w.objects.records[int(f.target)].owner = 0
	move_actor(w, 4, Vector2(126.5, 122.5))
	check(w.execute_operation(4, {"kind": "construct", "target": int(f.target)}) == "accepted", "Third-party work fixture could not start")
	advance(w, 2500)
	check(w.society.requests[id].reason == "task_satisfied" and w.society.requests[id].closed_by == 4, "Closure lost its actual submitter")
	var clock: int = w.society.requests[id].cooldown_until_ms
	contact(w, 1, {"kind": "talk", "target": 3})
	check(w.society.Requests.views(w.society, 1, w.elapsed_ms)[0].state == "deferred" and w.knowledge.view(1, int(f.target), w.elapsed_ms).kind == "blueprint", "A remote conversation disclosed a completion neither party knew")
	var result: Dictionary = contact(w, 3, {"kind": "respond_request", "target": 1, "request": id, "decision": "accept"})
	check(result.reason == "request_unavailable" and w.society.requests[id].reply.reason == "request_unavailable" and w.society.requests[id].reason == "task_satisfied" and w.society.requests[id].cooldown_until_ms == clock, "Response failed to end the stale proposal without revealing its hidden cause or restarting cooldown: " + str({"result": result, "request": w.society.requests[id], "clock": clock}))
	check(not w.livelihood.Planner.Contacts.responding(w.livelihood._self_view(w, 3), w.elapsed_ms), "Closed personal message kept generating response work")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Generic unavailable message could not recover")

func late_fulfilment_message() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	var id: int = send_help(w, int(f.target))
	w.society.respond(w, 3, id, "accept", 0)
	w.decisions.suspend(w, 3)
	var far: Vector2 = w.Terrain.center(w.terrain.nearest_open(w.Terrain.index(Vector2i(180, 180))))
	move_actor(w, 1, far)
	advance(w, 61000)
	move_actor(w, 3, Vector2(126.5, 122.5))
	check(w.execute_operation(3, {"kind": "construct", "target": int(f.target)}) == "accepted", "Late real fulfilment could not start")
	advance(w, 64000)
	check(w.society.requests[id].state == "fulfilled" and w.society.requests[id].reply.state == "accepted", "Distant late fulfilment was not kept separate from delivered reply")
	move_actor(w, 3, far + Vector2(0.2, 0.0))
	contact(w, 1, {"kind": "talk", "target": 3})
	check(w.society.requests[id].reply.state == "fulfilled" and w.society.requests[id].reply.at_ms > w.society.requests[id].expires_ms and w.society.requests[id].accepted_ms == 0, "Face-to-face outcome overwrote acceptance or remained stuck behind the response window")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Late delivered fulfilment could not recover")

func clock_based_contact_retry() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	w.livelihood.record(w, 3)
	w.knowledge.refresh(w, 3, 1, 0)
	w.livelihood._appraise(w, 3, "respond_request", 1, "refused", "target_busy", 0)
	w.decisions.result(w, 3, "respond_request", 1, "target_busy", 0)
	move_actor(w, 1, Vector2(123.5, 120.7)); w.knowledge.refresh(w, 3, 1, 0)
	check(w.livelihood._blocked(w, 3, w.livelihood.records[3], 0).has("respond_request:1") and not w.decisions.retry_allowed(w, 3, "respond_request", 1, 0), "Peer movement erased the contact refusal's clock-based backoff")
	advance(w, 2000)
	check(w.decisions.retry_allowed(w, 3, "respond_request", 1, w.elapsed_ms), "Contact failure never became retryable")

func autonomous_request_for_known_help() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	resident(w, 3, [4, int(f.target)])
	w.objects.records[int(f.target)].owner = 3
	w.knowledge.created(w, 3, int(f.target), 0)
	w.objects.records[3]["capability_overrides"] = {"work": false}
	w.society.Contacts.acknowledge(w.society, w, 3, 4, 0)
	w.knowledge.refresh(w, 3, 4, 0)
	healthy(w, 3); healthy(w, 4)
	w.livelihood.add_goal(w, 3, "operation", {"operation": "construct", "target": int(f.target)})
	w.objects.records[3].autonomous = true
	w.decisions.resume(w, 3, 0); w.decisions.prepare(w, 0)
	advance(w, 18000)
	check(w.society.requests.size() == 1 and w.society.requests.values()[0].issuer == 3 and w.society.requests.values()[0].recipient == 4 and w.objects.records[int(f.target)].kind == "wall", "A body unable to work did not ask a known person through real contact: " + str({"requests": w.society.requests, "life": w.livelihood.describe(3)}))
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Autonomous request and fulfilment could not recover")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--player" in args: explicit_player_response()
	elif "--defer" in args: defer_eat_then_return("--recover" in args)
	elif "--hidden" in args: hidden_third_party_completion()
	elif "--late" in args: late_fulfilment_message()
	elif "--seek" in args: autonomous_request_for_known_help()
	else: clock_based_contact_retry()
	print("SOCIETY_FOLLOWUP_SMOKE mode=", args, " errors=", errors)
	quit(0 if errors == 0 else 1)
