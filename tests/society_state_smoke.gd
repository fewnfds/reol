extends "res://tests/institution_matters_smoke.gd"

func private_fixture() -> Dictionary:
	var w: RefCounted = peaceful()
	for actor: int in [1, 2, 3, 4]: move_actor(w, actor, Vector2(123.5 + actor * 0.2, 120.5))
	w.objects.claim(w.source_objects[0], 1, "wood", 12)
	var target: int = w.facilities.blueprint(w, 1, "wood_wall", w.Terrain.index(Vector2i(127, 122))).target
	w.objects.records[target].remaining_ms = 1200
	return {"w": w, "target": target}

func send_help(w: RefCounted, target: int, recipient: int = 3) -> int:
	var result: Dictionary = w.society.deliver_request(w, 1, {"kind": "request_help", "target": recipient, "task_target": target}, w.elapsed_ms)
	check(result.status == "completed", "On-site request failed: " + str(result))
	return int(result.facts.get("request", 0))

func contacts_and_delivery() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	w.knowledge.records.clear()
	check(w.begin_interaction(1, {"kind": "talk", "target": 3}) == "accepted", "Conversation fixture refused")
	w.settle_action(1, 0)
	advance(w, 1100)
	check(w.society.Contacts.known(w.society, 1, 3) and w.society.Contacts.known(w.society, 3, 1), "Real conversation without a novel clue lost acquaintance")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Acquaintance could not restore")
	w.knowledge.created(w, 1, int(f.target), w.elapsed_ms)
	move_actor(w, 3, Vector2(180.5, 180.5))
	var before: Dictionary = w.knowledge.records.get(3, {}).duplicate(true)
	check(w.society.deliver_request(w, 1, {"kind": "request_help", "target": 3, "task_target": int(f.target)}, w.elapsed_ms).reason == "contact_not_completed" and w.society.requests.is_empty() and w.knowledge.records.get(3, {}) == before, "Undelivered request changed its remote recipient")
	move_actor(w, 3, Vector2(124.5, 120.5))
	var id: int = send_help(w, int(f.target))
	if id == 0: return
	check(w.society.requests[id].state == "pending" and w.institutions.shares.is_empty() and int(w.knowledge.view(3, int(f.target), w.elapsed_ms).get("tile", -1)) >= 0, "Delivery created a duty or failed to convey the actual clue")
	check(w.society.deliver_request(w, 1, {"kind": "request_help", "target": 3, "task_target": int(f.target)}, w.elapsed_ms).reason == "already_requested", "Pending duplicate was recreated")
	check(w.society.respond(w, 4, id, "accept", w.elapsed_ms).reason == "invalid_request", "A third person answered another person's request")
	check(w.society.respond(w, 3, id, "refuse", w.elapsed_ms).reason == "request_refused", "Explicit refusal failed")
	var matter: int = w.institutions.create_matter(w, 1, {"kind": "operation", "target": int(f.target), "operation": "construct"})
	check(matter > 0 and w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 3, "matter": matter}, w.elapsed_ms).reason == "request_on_cooldown", "Changing the request channel bypassed the same construction refusal")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Refusal and cross-channel cooldown did not restore")

func expiry_and_bad_state() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	var id: int = send_help(w, int(f.target))
	if id == 0: return
	check(w.society.requests[id].delivered_ms == 0 and Persistence.candidate(Persistence.capture(w), 0) != null, "Valid delivery at simulation time zero was rejected")
	check(w.society.respond(w, 3, id, "defer", 0).reason == "request_deferred", "Deferral failed")
	var state: Dictionary = Persistence.capture(w)
	for field: String in ["issuer", "state", "review_ms", "expires_ms", "terms", "reply"]:
		var bad: Dictionary = state.duplicate(true)
		bad.domains.society.requests[id][field] = {"issuer": 3, "state": "invented", "review_ms": 70000, "expires_ms": -1, "terms": {"kind": "operation"}, "reply": {"state": "pending", "reason": "pending", "at_ms": 1}}[field]
		check(Persistence.candidate(bad, 0) == null, "Malformed social request restored: " + field)
	advance(w, 60001)
	var untouched: Dictionary = w.society.requests[id].duplicate(true)
	check(w.society.Requests.views(w.society, 1, w.elapsed_ms)[0].state == "expired" and w.society.requests[id] == untouched, "Reading elapsed request advanced its truth")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Unvisited overdue request made a valid save unreadable")
	w.society.Requests.expire_for(w.society, 3, w.elapsed_ms)
	check(w.society.requests[id].state == "expired" and w.society.requests[id].changed_ms == 60000 and w.society.requests[id].cooldown_until_ms == 90000, "Lazy expiry anchored its cooldown to the observer's visit time")
	advance(w, 90001)
	w.society.Requests.compact(w.society, w.elapsed_ms)
	check(w.society.requests.is_empty(), "Cooled expired history permanently blocked request capacity")

func actual_fulfilment_and_death() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	var id: int = send_help(w, int(f.target))
	if id == 0: return
	var accepted: Dictionary = w.society.respond(w, 3, id, "accept", 0)
	check(accepted.reason == "accepted_share" and w.society.requests[id].share > 0, "Consent failed to create the original formal responsibility")
	var state: Dictionary = Persistence.capture(w)
	var bad: Dictionary = state.duplicate(true)
	bad.domains.society.requests[id].share = w.institutions.next_share
	check(Persistence.candidate(bad, 0) == null and Persistence.candidate(state, 0) != null, "Accepted request did not validate its real share")
	w.decisions.resume(w, 3, 0); w.decisions.prepare(w, 0)
	advance(w, 8000)
	check(w.objects.records[int(f.target)].kind == "wall" and w.society.requests[id].state == "fulfilled", "Actual accepted work did not close the social request")
	check(w.society.Requests.views(w.society, 1, w.elapsed_ms)[0].state == "accepted", "Remote completion leaked into the issuer's delivered reply")
	w.society.on_share_closed(w, w.institutions.shares[int(w.society.requests[id].share)], true)
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Repeated closure corrupted the completed request")
	var death: Dictionary = private_fixture()
	w = death.w
	id = send_help(w, int(death.target))
	if id == 0: return
	w.society.respond(w, 3, id, "accept", 0)
	var share: int = int(w.society.requests[id].share)
	move_actor(w, 1, Vector2(180.5, 180.5))
	w.knowledge.refresh(w, 1, 3, 0)
	var knowledge: Dictionary = w.knowledge.records[1].duplicate(true)
	w.kill(3, 0)
	check(w.society.requests[id].state == "cancelled" and w.institutions.shares[share].state == "accepted" and w.knowledge.records[1] == knowledge, "Participant death erased a responsibility or delivered remote knowledge")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Dead participant with an unresolved formal obligation could not restore")

func third_party_and_matter_closure() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	var pending: int = send_help(w, int(f.target), 4)
	var id: int = send_help(w, int(f.target), 3)
	if pending == 0 or id == 0: return
	w.society.respond(w, 3, id, "accept", 0)
	w.decisions.suspend(w, 3)
	move_actor(w, 1, Vector2(126.5, 122.5))
	check(w.execute_operation(1, {"kind": "construct", "target": int(f.target)}) == "accepted", "Third-party construction refused")
	advance(w, 2000)
	check(w.society.requests[id].state == "cancelled" and w.society.requests[pending].state == "cancelled", "Satisfied work failed to close accepted and not-yet-accepted requests")
	check(w.institutions.shares[int(w.society.requests[id].share)].fulfilled == 0 and Persistence.candidate(Persistence.capture(w), 0) != null, "Third-party work was falsely credited to the absent obligor")
	f = commission_fixture(); w = f.world
	var matter: int = w.institutions.create_matter(w, 1, {"kind": "delivery", "organization": int(f.org), "target": int(f.destination), "item": "grain", "sources": [int(f.source)], "total": 3, "quota": 2})
	var result: Dictionary = w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 4, "matter": matter}, 0)
	check(result.status == "completed", "Matter delivery fixture failed: " + str(result))
	if result.status != "completed": return
	id = int(result.facts.request)
	check(w.institutions.cancel_matter(w, 1, matter) and w.society.requests[id].state == "cancelled" and Persistence.candidate(Persistence.capture(w), 0) != null, "Unaccepted offer remained live after matter cancellation")

func _run() -> void:
	var lifecycle: bool = "--lifecycle" in OS.get_cmdline_user_args()
	if lifecycle:
		actual_fulfilment_and_death()
		third_party_and_matter_closure()
	else:
		contacts_and_delivery()
		expiry_and_bad_state()
	print("SOCIETY_STATE_SMOKE lifecycle=", lifecycle, " errors=", errors)
	quit(0 if errors == 0 else 1)
