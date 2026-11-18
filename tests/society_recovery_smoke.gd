extends "res://tests/society_state_smoke.gd"

func late_closure(kind: String) -> void:
	var f: Dictionary = private_fixture() if kind != "matter" else commission_fixture()
	var w: RefCounted = f.w if kind != "matter" else f.world
	var id: int = 0
	var matter: int = 0
	if kind == "matter":
		matter = w.institutions.create_matter(w, 1, delivery_spec(f, 2, 1))
		var delivered: Dictionary = w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 3, "matter": matter}, 0)
		check(delivered.status == "completed", "Late cancellation fixture failed")
		if delivered.status != "completed": return
		id = int(delivered.facts.request)
	else: id = send_help(w, int(f.target))
	if id == 0: return
	check(w.society.respond(w, 3, id, "defer", 0).reason == "request_deferred", "Late deferral fixture failed")
	advance(w, 100000)
	check(w.society.requests[id].state == "deferred" and not w.society.Requests.protects(w.society, 1, 3, w.elapsed_ms), "An elapsed request still protected an incidental contact")
	var view: Dictionary = w.society.Requests.views(w.society, 1, w.elapsed_ms)[0]
	check(view.state == "expired" and view.review_ms == -1 and not view.has("share") and not view.has("reply") and not view.has("cooldown_until_ms"), "Personal projection retained an expired review or objective bookkeeping")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Untouched elapsed deferral did not restore")
	if kind == "matter": check(w.institutions.cancel_matter(w, 1, matter), "Late matter cancellation refused")
	elif kind == "death": w.kill(3, w.elapsed_ms)
	else:
		move_actor(w, 1, Vector2(126.5, 122.5))
		check(w.execute_operation(1, {"kind": "construct", "target": int(f.target)}) == "accepted", "Late third-party construction refused")
		advance(w, w.elapsed_ms + 2000)
	check(w.society.requests[id].state == "expired" and w.society.requests[id].changed_ms == 60000 and w.society.requests[id].cooldown_until_ms == 90000, "A late closure restarted an already elapsed cooldown")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Late closure failed restoration")

func removed_obligor_then_completion() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	var id: int = send_help(w, int(f.target))
	if id == 0: return
	w.society.respond(w, 3, id, "accept", 0)
	var share: int = int(w.society.requests[id].share)
	check(w.remove_actor(3, 0) and w.institutions.shares[share].state == "accepted", "Removing the obligor erased the unresolved allocation")
	move_actor(w, 1, Vector2(126.5, 122.5))
	check(w.execute_operation(1, {"kind": "construct", "target": int(f.target)}) == "accepted", "Completion after obligor removal refused")
	advance(w, 2000)
	check(w.institutions.shares[share].state == "released" and w.institutions.shares[share].fulfilled == 0 and w.society.requests[id].state == "cancelled", "Third-party completion credited a removed obligor or reopened its request")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Removed obligor and later satisfaction did not restore")

func accepted_response_window() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	var id: int = send_help(w, int(f.target))
	if id == 0: return
	w.society.respond(w, 3, id, "accept", 0)
	w.decisions.suspend(w, 3)
	advance(w, 60001)
	w.society.Requests.expire_for(w.society, 3, w.elapsed_ms)
	check(w.society.requests[id].state == "accepted" and w.institutions.shares[int(w.society.requests[id].share)].state == "accepted", "Waiting-for-reply expiry revoked an already accepted obligation")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Paused accepted obligation after response window did not restore")

func forged_replies_and_terms() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	var id: int = send_help(w, int(f.target))
	if id == 0: return
	var state: Dictionary = Persistence.capture(w)
	var bad: Dictionary = state.duplicate(true)
	bad.domains.society.requests[id].terms.deadline_ms = 0
	check(Persistence.candidate(bad, 0) == null, "A forged private-help deadline was accepted")
	w.society.respond(w, 3, id, "accept", 0)
	state = Persistence.capture(w)
	bad = state.duplicate(true)
	bad.domains.society.requests[id].recipient = 4
	check(Persistence.candidate(bad, 0) == null, "A request accepted another person's share")
	bad = state.duplicate(true)
	bad.domains.society.requests[id].merge({"state": "cancelled", "reason": "share_released", "cooldown_until_ms": 30000}, true)
	check(Persistence.candidate(bad, 0) == null, "A live accepted obligation was forged into a cancelled request")
	f = commission_fixture(); w = f.world
	var matter: int = w.institutions.create_matter(w, 1, {"kind": "delivery", "organization": int(f.org), "target": int(f.destination), "item": "grain", "sources": [int(f.source)], "total": 2, "quota": 1, "deadline_ms": 1000})
	var result: Dictionary = w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 3, "matter": matter}, 0)
	check(result.status == "completed", "Short-deadline fixture failed")
	if result.status != "completed": return
	id = int(result.facts.request)
	state = Persistence.capture(w)
	bad = state.duplicate(true)
	bad.domains.society.requests[id].expires_ms = 60000
	check(Persistence.candidate(bad, 0) == null, "A request response window extended beyond its delivered deadline")
	bad = state.duplicate(true)
	bad.domains.institutions.matters[matter].state = "cancelled"
	check(Persistence.candidate(bad, 0) == null, "A closed matter restored a live pending request")
	bad = state.duplicate(true)
	bad.domains.institutions.matters.erase(matter)
	check(Persistence.candidate(bad, 0) == null, "A missing matter restored a forged active offer")
	advance(w, 1001)
	w.society.Requests.expire_for(w.society, 3, w.elapsed_ms)
	state = Persistence.capture(w)
	bad = state.duplicate(true)
	bad.domains.society.requests[id].reply = {"state": "accepted", "reason": "accepted_share", "at_ms": 0}
	check(Persistence.candidate(bad, 0) == null and Persistence.candidate(state, 0) != null, "An unaccepted expired request restored a fabricated consent")

func strict_history() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	var id: int = send_help(w, int(f.target))
	if id == 0: return
	w.society.respond(w, 3, id, "defer", 0)
	var bad: Dictionary = Persistence.capture(w)
	bad.domains.society.requests[id].review_ms = 5000
	check(Persistence.candidate(bad, 0) == null, "A deferred request restored a forged review time")
	w.society.respond(w, 3, id, "accept", 0)
	var share: int = int(w.society.requests[id].share)
	check(w.institutions.release_share(w, 3, share), "Release fixture failed")
	var state: Dictionary = Persistence.capture(w)
	check(Persistence.candidate(state, 0) != null, "A genuinely released request did not restore")
	bad = state.duplicate(true)
	bad.domains.society.requests[id].reason = "participant_unavailable"
	check(Persistence.candidate(bad, 0) == null, "Two living participants restored fabricated unavailability")
	bad = state.duplicate(true)
	bad.domains.society.requests[id].reason = "unrecognized_closure"
	check(Persistence.candidate(bad, 0) == null, "A cancelled request restored an impossible closure reason")
	bad = state.duplicate(true)
	var duplicate: Dictionary = bad.domains.society.requests[id].duplicate(true)
	duplicate.id = bad.domains.society.next_request
	duplicate.issuer = 2
	bad.domains.society.requests[duplicate.id] = duplicate
	bad.domains.society.next_request += 1
	check(Persistence.candidate(bad, 0) == null, "Two closed requests restored the same original share")
	bad = state.duplicate(true)
	bad.domains.institutions.shares.erase(share)
	bad.domains.society.requests[id].merge({"matter": 0, "version": 0}, true)
	check(Persistence.candidate(bad, 0) == null, "A historical nonzero share restored without its matter identity")

func construction_allocation() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	var spec: Dictionary = {"kind": "operation", "target": int(f.target), "operation": "construct", "deadline_ms": 300000}
	var first: int = w.institutions.create_matter(w, 1, spec)
	var second: int = w.institutions.create_matter(w, 1, spec)
	check(first > 0 and second > first, "Parallel proposal fixture failed")
	check(not w.institutions.revise_matter(w, 1, first, 2, 1, 300000), "Construction revision created more than one physical task")
	var sent: Dictionary = w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 3, "matter": first}, 0)
	var later: Dictionary = w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 4, "matter": second}, 0)
	check(sent.status == "completed" and later.status == "completed", "Unallocated proposals could not be delivered")
	if sent.status != "completed" or later.status != "completed": return
	check(w.society.respond(w, 3, int(sent.facts.request), "accept", 0).reason == "accepted_share", "First construction proposal could not be accepted")
	check(w.society.respond(w, 4, int(later.facts.request), "accept", 0).reason == "already_assigned", "Another proposal double-allocated one physical construction")
	check(w.institutions.accept_share(w, 4, second) == 0, "Direct share acceptance bypassed physical construction allocation")
	check(w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 2, "matter": second}, 0).reason == "already_assigned", "An allocated construction accepted another offer")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Refusing a competing construction proposal damaged restoration")
	var source: Dictionary = w.institutions.shares[int(w.society.requests[int(sent.facts.request)].share)]
	var forged: Dictionary = source.duplicate(true)
	forged.id = w.institutions.next_share
	forged.matter = second
	forged.actor = 4
	w.institutions.next_share += 1
	w.institutions.shares[forged.id] = forged
	check(not w.institutions.Matters.valid(w.institutions, w), "The normative owner restored two allocated matters for one construction")

func unassigned_proposals() -> void:
	for after_delivery: bool in [false, true]:
		var f: Dictionary = private_fixture()
		var w: RefCounted = f.w
		w.objects.records[int(f.target)].owner = 0
		for actor: int in [1, 2]: w.knowledge.refresh(w, actor, int(f.target), 0)
		var request: int = send_help(w, int(f.target)) if after_delivery else 0
		var other: int = w.institutions.create_matter(w, 2, {"kind": "operation", "target": int(f.target), "operation": "construct"})
		check(other > 0, "Other issuer's unallocated proposal fixture failed")
		if not after_delivery: request = send_help(w, int(f.target))
		check(request > 0 and w.society.respond(w, 3, request, "accept", 0).reason == "accepted_share", "An unrelated unallocated proposal blocked legal help on an unowned blueprint")
		check(Persistence.candidate(Persistence.capture(w), 0) != null, "Coexisting unallocated proposal and real allocation failed restoration")
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	w.institutions.create_matter(w, 1, {"kind": "operation", "target": int(f.target), "operation": "construct", "deadline_ms": 1000})
	advance(w, 1001)
	var valid_matter: int = w.institutions.create_matter(w, 1, {"kind": "operation", "target": int(f.target), "operation": "construct"})
	var request: int = send_help(w, int(f.target))
	check(request > 0 and w.society.requests[request].matter == valid_matter, "An expired unallocated proposal hid a valid current proposal")

func request_origins() -> void:
	var f: Dictionary = private_fixture()
	var w: RefCounted = f.w
	var request: int = send_help(w, int(f.target))
	var bad: Dictionary = Persistence.capture(w)
	bad.domains.society.requests[request].merge({"state": "cancelled", "reason": "matter_closed", "cooldown_until_ms": 30000}, true)
	check(Persistence.candidate(bad, 0) == null, "An unbound private request fabricated a matter closure")
	f = commission_fixture(); w = f.world
	var matter: int = w.institutions.create_matter(w, 1, delivery_spec(f, 2, 1))
	check(w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 3, "matter": matter, "quota": 1000001}, 0).status == "refused" and w.society.requests.is_empty(), "An impossible offered quota created an unrestorable request")
	request = int(w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 3, "matter": matter}, 0).facts.request)
	for reason: String in ["matter_closed", "task_satisfied"]:
		bad = Persistence.capture(w)
		bad.domains.society.requests[request].merge({"state": "cancelled", "reason": reason, "cooldown_until_ms": 30000}, true)
		check(Persistence.candidate(bad, 0) == null, "A live delivery proposal fabricated a closure: " + reason)
	advance(w, 100)
	w.society.respond(w, 3, request, "accept", w.elapsed_ms)
	w.decisions.suspend(w, 3)
	advance(w, 200)
	bad = Persistence.capture(w)
	bad.domains.society.requests[request].changed_ms = 150
	bad.domains.society.requests[request].reply.at_ms = 150
	check(Persistence.candidate(bad, 0) == null, "A request adopted a share created at a different acceptance time")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Genuine acceptance timestamps failed restoration")

func archives_and_shared_source() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	var matter: int = w.institutions.create_matter(w, 1, {"kind": "produce", "organization": int(f.org), "target": int(f.stove), "operation": "cook", "item": "meal", "sources": [int(f.stove)], "total": 3, "quota": 3})
	var result: Dictionary = w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 3, "matter": matter}, 0)
	check(matter > 0 and result.status == "completed" and Persistence.candidate(Persistence.capture(w), 0) != null, "Legal production using stock at its own workbench could not restore")
	w.institutions.cancel_matter(w, 1, matter)
	var bad: Dictionary = Persistence.capture(w)
	bad.domains.institutions.matters.erase(matter)
	check(Persistence.candidate(bad, 0) == null, "A request restored a missing matter without any closed-history ledger")
	matter = w.institutions.create_matter(w, 1, delivery_spec(f, 1, 1))
	w.objects.add(f.source, "grain", 1, Stock.right(0, int(f.org)))
	result = w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 3, "matter": matter}, 0)
	if result.status != "completed": check(false, "Archived fulfilment fixture could not deliver"); return
	var id: int = int(result.facts.request)
	w.society.respond(w, 3, id, "accept", 0)
	w.decisions.suspend(w, 3)
	manual_transfer(w, 3, int(f.source), "grain", 1, "take", {"purpose": "supply"})
	manual_transfer(w, 3, int(f.destination), "grain", 1, "put")
	check(w.society.requests[id].state == "fulfilled", "Actual archive fixture never fulfilled its request")
	for index: int in 512:
		var historical: int = w.institutions.create_matter(w, 1, delivery_spec(f, 1, 1))
		check(historical > 0 and w.institutions.cancel_matter(w, 1, historical), "Real archive pressure could not close an old matter")
	check(not w.institutions.matters.has(matter) and Persistence.candidate(Persistence.capture(w), 0) != null, "Real compressed fulfilment history was rejected")
	f = private_fixture(); w = f.w
	id = send_help(w, int(f.target))
	advance(w, 60001)
	w.society.Requests.expire_for(w.society, 3, w.elapsed_ms)
	bad = Persistence.capture(w)
	bad.domains.society.requests[id].reply = {"state": "deferred", "reason": "request_deferred", "at_ms": 59999}
	check(Persistence.candidate(bad, 0) == null, "An impossible last-millisecond deferral restored")

func delayed_labor_after_death() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	w.objects.add(f.source, "grain", 2, Stock.right(0, int(f.org)))
	w.objects.add(f.source, "water", 1, Stock.right(0, int(f.org)))
	var matter: int = w.institutions.create_matter(w, 1, {"kind": "produce", "organization": int(f.org), "target": int(f.stove), "operation": "cook", "item": "meal", "sources": [int(f.source)], "total": 3, "quota": 3})
	var result: Dictionary = w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 3, "matter": matter}, 0)
	if result.status != "completed": check(false, "Delayed labor fixture could not deliver"); return
	var id: int = int(result.facts.request)
	w.society.respond(w, 3, id, "accept", 0)
	var share: int = int(w.society.requests[id].share)
	w.decisions.suspend(w, 3)
	manual_transfer(w, 3, int(f.source), "grain", 2, "take", {"purpose": "cook"})
	manual_transfer(w, 3, int(f.source), "water", 1, "take", {"purpose": "cook"})
	manual_transfer(w, 3, int(f.stove), "grain", 2, "put", {"purpose": "cook"})
	manual_transfer(w, 3, int(f.stove), "water", 1, "put", {"purpose": "cook"})
	var work_point: Vector2 = w.facilities.interaction_point(w, int(f.stove), w.combat.position(w, 3), 0.35, false, "craft", 3)
	move_actor(w, 3, work_point)
	check(w.execute_operation(3, {"kind": "cook", "target": int(f.stove)}) == "accepted", "Actual first worker could not enter production")
	w.settle_action(3, w.elapsed_ms)
	advance(w, w.elapsed_ms + 1000)
	w.kill(3, w.elapsed_ms)
	check(w.objects.records[int(f.stove)].has("process") and w.society.requests[id].state == "cancelled" and w.institutions.shares[share].state == "accepted", "Worker death erased the unfinished pot or original responsibility")
	w.institutions.admit(w, int(f.org), 4, Array(w.institutions.PURPOSES))
	move_actor(w, 4, work_point)
	check(w.execute_operation(4, {"kind": "cook", "target": int(f.stove)}) == "accepted", "Replacement worker could not continue the same pot")
	w.settle_action(4, w.elapsed_ms)
	advance(w, w.elapsed_ms + 4000)
	check(w.institutions.shares[share].state == "completed" and w.society.requests[id].state == "cancelled" and w.society.requests[id].reason == "participant_unavailable", "Delayed real labor reopened the dead participant's request or lost its credit")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Later credit for a dead participant's actual labor failed restoration")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--labor" in args: delayed_labor_after_death()
	elif "--archives" in args: archives_and_shared_source()
	elif "--proposals" in args: unassigned_proposals()
	elif "--origins" in args: request_origins()
	elif "--strict" in args: strict_history()
	elif "--allocation" in args: construction_allocation()
	elif "--bad" in args: forged_replies_and_terms()
	elif "--removed" in args: removed_obligor_then_completion()
	elif "--accepted" in args: accepted_response_window()
	else: late_closure("death" if "--death" in args else ("construction" if "--construction" in args else "matter"))
	print("SOCIETY_RECOVERY_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
