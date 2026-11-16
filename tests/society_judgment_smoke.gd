extends "res://tests/society_state_smoke.gd"

func healthy(w: RefCounted, actor: int) -> void:
	w.pages[0].hunger[actor - 1] = 10000
	w.pages[0].energy[actor - 1] = 10000

func contact(w: RefCounted, actor: int, input: Dictionary) -> Dictionary:
	check(w.execute_operation(actor, input) == "accepted", "Actual contact did not enter its original host: " + str(input))
	w.settle_action(actor, w.elapsed_ms)
	advance(w, w.elapsed_ms + 1700)
	var result: Dictionary = latest(w, actor)
	check(result.get("operation") == input.kind, "Contact did not publish its own result: " + str(result))
	return result

func actual_judgment_and_experience(remote: bool) -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	healthy(w, 3)
	w.objects.add(3, "wood", -w.objects.amount(3, "wood")) # Blueprint materials are prepaid, not supplied by its helper.
	var result: Dictionary = contact(w, 1, {"kind": "request_help", "target": 3, "task_target": int(f.target)})
	check(result.reason == "accepted_share" and result.facts.get("counterparty") == 3 and w.society.requests.size() == 1, "Ready helper failed its own stable judgment or counterparty: " + str(result))
	var impression: Dictionary = w.livelihood.records.get(1, {}).get("social_appraisals", {})
	check(not impression.has(3), "Accepting a promise was recorded as completed support")
	if remote: move_actor(w, 1, Vector2(180.5, 180.5))
	advance(w, 9000)
	check(w.objects.records[int(f.target)].kind == "wall", "A judged request failed to drive real construction")
	impression = w.livelihood.records.get(1, {}).get("social_appraisals", {})
	check((not impression.has(3)) if remote else (impression.get(3, {}).get("support") == 1), "Support ignored actual witnessing")
	if remote:
		move_actor(w, 1, Vector2(126.5, 120.5))
		w.knowledge.refresh(w, 1, int(f.target), w.elapsed_ms)
		check(not w.livelihood.records.get(1, {}).get("social_appraisals", {}).has(3), "Seeing an already completed wall invented its benefactor")
	else:
		var before: Dictionary = impression.duplicate(true)
		w.livelihood.social_outcome(w, latest(w, 3))
		check(w.livelihood.records[1].social_appraisals == before, "Replayed evidence counted support twice")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Real personal judgment and support could not restore")

func need_budget_and_manual() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	w.pages[0].hunger[2] = 1000
	var result: Dictionary = contact(w, 1, {"kind": "request_help", "target": 3, "task_target": int(f.target)})
	check(result.reason == "refused_need" and w.institutions.shares.is_empty(), "A starving helper took on a new private duty")
	check(w.livelihood.records.get(1, {}).get("social_appraisals", {}).is_empty() and w.livelihood.records[3].social_appraisals.is_empty(), "Objective refusal invented personal resentment")
	move_actor(w, 3, Vector2(124.6, 120.5))
	healthy(w, 3)
	check(w.society.deliver_request(w, 1, {"kind": "request_help", "target": 3, "task_target": int(f.target)}, w.elapsed_ms).reason == "request_on_cooldown", "Movement or recovery rerolled a recent refusal")
	f = private_fixture(); w = f.w; healthy(w, 3)
	w.livelihood.record(w, 3).budget = {"window_ms": 0, "work": 128, "cursor": 0, "goal_cursor": 0}
	var id: int = send_help(w, int(f.target))
	check(w.society.judge_request(w, 3, id, 0).is_empty() and w.society.requests[id].state == "pending", "Exhausted judgment budget was recorded as refusal")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Budget-limited pending request failed restoration")
	f = private_fixture(); w = f.w; healthy(w, 3)
	w.decisions.suspend(w, 3)
	result = contact(w, 1, {"kind": "request_help", "target": 3, "task_target": int(f.target)})
	check(result.reason == "request_delivered" and w.society.requests.values()[0].state == "pending" and w.decisions.records[3].manual and not w.objects.records[3].autonomous, "Manual recipient was rejected or lost control")
	f = private_fixture(); w = f.w
	w.objects.records[int(f.target)].owner = 3
	w.knowledge.created(w, 3, int(f.target), 0)
	result = contact(w, 3, {"kind": "request_help", "target": 1, "task_target": int(f.target)})
	check(result.reason == "request_delivered" and w.society.requests.values()[0].recipient == 1 and w.society.requests.values()[0].state == "pending", "Player could not receive a pending request without surrendering control")

func exchanges_and_bad_state() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	var result: Dictionary = contact(w, 1, {"kind": "talk", "target": 3})
	check(w.livelihood.records[1].social_appraisals[3].exchanges == 1 and w.livelihood.records[3].social_appraisals[1].exchanges == 1, "A real conversation did not affect both participants' experiences")
	var state: Dictionary = Persistence.capture(w)
	w.livelihood.social_outcome(w, result)
	check(w.livelihood.records[1].social_appraisals[3].exchanges == 1, "Replayed conversation counted twice")
	for field: String in ["exchanges", "support", "last_result", "at_ms"]:
		var bad: Dictionary = state.duplicate(true)
		bad.domains.livelihood.records[1].social_appraisals[3][field] = {"exchanges": 17, "support": 2, "last_result": w.activity_results.next_id, "at_ms": w.elapsed_ms + 1}[field]
		check(Persistence.candidate(bad, 0) == null, "Malformed personal impression restored: " + field)
	var bad: Dictionary = state.duplicate(true)
	bad.domains.livelihood.records[1].social_appraisals[1] = bad.domains.livelihood.records[1].social_appraisals[3].duplicate(true)
	check(Persistence.candidate(bad, 0) == null, "A person restored an impression of themselves as another party")
	bad = state.duplicate(true)
	bad.domains.livelihood.records[1].social_appraisals[3]["invented_feeling"] = 1
	check(Persistence.candidate(bad, 0) == null, "An unsupported extra personal state field restored")
	move_actor(w, 3, Vector2(180.5, 180.5)); w.kill(3, w.elapsed_ms)
	check(w.livelihood.records[1].social_appraisals[3] == state.domains.livelihood.records[1].social_appraisals[3] and Persistence.candidate(Persistence.capture(w), 0) != null, "Remote death erased another person's experience")

func experience_changes_a_real_request() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	healthy(w, 3)
	w.livelihood.set_dispositions(w, 3, {"persistence": 2.0, "dutifulness": 2.0})
	var id: int = send_help(w, int(f.target))
	var view: Dictionary = w.society.Requests.views(w.society, 3, 0)[0]
	var before: Dictionary = w.livelihood.evaluate_request(w, 3, view, 0)
	check(before.decision == "refuse" and before.reason == "refused_busy", "Occupied stranger fixture did not express its own purpose cost: " + str(before))
	for iteration: int in 3: contact(w, 1, {"kind": "talk", "target": 3})
	view = w.society.Requests.views(w.society, 3, w.elapsed_ms)[0]
	var after: Dictionary = w.livelihood.evaluate_request(w, 3, view, w.elapsed_ms)
	check(after.decision == "accept" and after.diagnostic.willingness > before.diagnostic.willingness, "Actual shared experiences did not affect judgment of the same delivered request: " + str(after))
	check(w.society.judge_request(w, 3, id, w.elapsed_ms).reason == "accepted_share", "Personal judgment was not consumed by the actual responsibility entry")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Experience-influenced responsibility could not restore")

func organization_scope_and_estimate() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	w.objects.add(f.source, "grain", 2, Stock.right(0, int(f.org))); w.objects.add(f.source, "water", 1, Stock.right(0, int(f.org)))
	var matter: int = w.institutions.create_matter(w, 1, {"kind": "produce", "organization": int(f.org), "target": int(f.stove), "operation": "cook", "item": "meal", "sources": [int(f.source)], "total": 3, "quota": 3})
	var id: int = int(w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 3, "matter": matter}, 0).facts.request)
	var before: Dictionary = w.operation_actor(3)
	var evaluation: Dictionary = w.livelihood.evaluate_request(w, 3, w.society.Requests.views(w.society, 3, 0)[0], 0)
	check(evaluation.decision == "accept" and evaluation.estimate_ms >= 4000 and evaluation.estimate_ms < 8000, "One recipe batch was miscounted or narrow execution rights were ignored: " + str(evaluation))
	check(w.operation_actor(3).scope_grants == before.scope_grants and w.operation_actor(3).permissions == before.permissions and w.operation_actor(3).responsibilities.is_empty(), "A prospective judgment wrote real authorization or responsibility")
	check(w.society.judge_request(w, 3, id, 0).reason == "accepted_share" and w.institutions.permits(3, int(f.org), "commission") == false, "Actual narrow acceptance granted delegation rights")
	f = commission_fixture(); w = f.world
	matter = w.institutions.create_matter(w, 1, delivery_spec(f, 2, 1))
	id = int(w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 2, "matter": matter}, 0).facts.request)
	check(w.society.judge_request(w, 2, id, 0).reason == "not_organization_member" and w.institutions.shares.is_empty(), "A nonmember was granted an organization's implicit membership")
	f = commission_fixture(); w = f.world
	w.objects.add(f.source, "grain", 2, Stock.right(0, int(f.org))); w.objects.add(f.source, "water", 1, Stock.right(0, int(f.org)))
	matter = w.institutions.create_matter(w, 1, {"kind": "produce", "organization": int(f.org), "target": int(f.stove), "operation": "cook", "item": "meal", "sources": [int(f.source)], "total": 3, "quota": 3, "deadline_ms": 1000})
	id = int(w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 3, "matter": matter}, 0).facts.request)
	check(w.society.judge_request(w, 3, id, 0).reason == "refused_deadline", "A recipe's real work duration disappeared from personal deadline estimates")

func defer_once() -> void:
	for recover: bool in [false, true]:
		var f: Dictionary = private_fixture()
		var w: RefCounted = f.w
		healthy(w, 3); w.pages[0].hunger[2] = 2800
		w.objects.records[3].autonomous = true
		var id: int = send_help(w, int(f.target))
		check(w.society.judge_request(w, 3, id, 0).reason == "deferred_need" and w.society.requests[id].review_ms == 10000, "A temporary personal need did not cause an explicit bounded deferral")
		check(Persistence.candidate(Persistence.capture(w), 0) != null, "Deferred personal judgment could not restore")
		w.decisions.suspend(w, 3)
		advance(w, 10000)
		if recover: healthy(w, 3)
		w.decisions.resume(w, 3, w.elapsed_ms)
		var response: Dictionary = w.society.judge_request(w, 3, id, w.elapsed_ms)
		check(response.reason == ("accepted_share" if recover else "refused_need"), "An unchanged need deferred indefinitely or a resolved need failed acceptance: " + str(response))

func trading_and_learning() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	w.objects.add(1, "potion", 1)
	contact(w, 1, {"kind": "trade", "target": 2})
	check(w.livelihood.records[1].social_appraisals[2].support == 0 and w.livelihood.records[2].social_appraisals[1].support == 0, "A paid exchange invented one-sided support")
	w.objects.records[1].get("methods", {}).erase("wood_breath")
	var result: Dictionary = contact(w, 1, {"kind": "learn", "target": 2})
	check(result.facts.get("points_gained", 0) > 0 and w.livelihood.records[1].social_appraisals[2].support == 1 and w.livelihood.records[2].social_appraisals[1].support == 0, "Actual learning failed to preserve asymmetric personal benefit")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Actual trade and learning experience could not restore")

func bounded_real_contacts() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	w.objects.records[1].get("methods", {}).erase("wood_breath")
	contact(w, 1, {"kind": "learn", "target": 2})
	var first: int = 0
	var old: Dictionary = {}
	for index: int in 25:
		var peer: int = w.spawn_actor(w.Terrain.index(Vector2i(124, 120)))
		w.objects.records[peer].side = 0
		contact(w, 1, {"kind": "talk", "target": peer})
		if index == 0:
			first = peer
			old = w.livelihood.records[1].social_appraisals[peer].duplicate(true)
	var accounts: Dictionary = w.livelihood.records[1].social_appraisals
	check(accounts.size() == 24 and accounts.has(2) and accounts[2].support == 1 and not accounts.has(first), "Incidental conversation overflow erased meaningful support or grew an unbounded memory")
	var state: Dictionary = Persistence.capture(w)
	check(Persistence.candidate(state, 0) != null, "A real crowded acquaintance journal could not restore")
	state.domains.livelihood.records[1].social_appraisals[first] = old
	check(Persistence.candidate(state, 0) == null, "A personal impression table beyond its budget restored")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--memory" in args: bounded_real_contacts()
	elif "--scope" in args: organization_scope_and_estimate()
	elif "--defer" in args: defer_once()
	elif "--teaching" in args: trading_and_learning()
	elif "--influence" in args: experience_changes_a_real_request()
	elif "--needs" in args: need_budget_and_manual()
	elif "--exchanges" in args: exchanges_and_bad_state()
	else: actual_judgment_and_experience("--remote" in args)
	print("SOCIETY_JUDGMENT_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
