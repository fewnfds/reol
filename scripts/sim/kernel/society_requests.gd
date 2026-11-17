extends RefCounted
## Delivered requests only. Institutions alone owns obligations and fulfilment.
const State = preload("res://scripts/sim/kernel/state.gd")
const Results = preload("res://scripts/sim/kernel/activity_results.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const LIMIT: int = 4096
const PENDING_LIMIT: int = 8
const RECENT_LIMIT: int = 32
const RESPONSE_MS: int = 60000
const COOLDOWN_MS: int = 30000
const DEFER_MS: int = 10000
const STATES: Array[String] = ["pending", "deferred", "accepted", "fulfilled", "refused", "expired", "cancelled"]

static func key(request: Dictionary) -> String:
	var task: bool = request.kind == "request_help" or (request.terms.kind == "operation" and request.terms.operation == "construct")
	return "%d:%d:%s:%d" % [request.issuer, request.recipient, "construct" if task else "matter", int(request.target) if task else int(request.matter)]

static func effective_state(request: Dictionary, now: int) -> String:
	return "expired" if request.state in ["pending", "deferred"] and now >= request.expires_ms else str(request.state)

static func _cooldown(request: Dictionary, now: int) -> int:
	return int(request.expires_ms) + COOLDOWN_MS if effective_state(request, now) == "expired" else int(request.cooldown_until_ms)

static func blocks(request: Dictionary, now: int) -> bool:
	return effective_state(request, now) in ["pending", "deferred", "accepted"] or now < _cooldown(request, now)

static func _index(owner: RefCounted, request: Dictionary) -> void:
	owner._requests_by_key[key(request)] = request.id
	for actor: int in [request.issuer, request.recipient]:
		if not owner._requests_by_actor.has(actor): owner._requests_by_actor[actor] = []
		owner._requests_by_actor[actor].append(request.id)
	if request.state == "accepted": owner._request_by_share[int(request.share)] = request.id

static func _erase(owner: RefCounted, id: int) -> void:
	var request: Dictionary = owner.requests[id]
	owner._requests_by_key.erase(key(request))
	owner._request_by_share.erase(int(request.share))
	for actor: int in [request.issuer, request.recipient]:
		owner._requests_by_actor.get(actor, []).erase(id)
		if owner._requests_by_actor.get(actor, []).is_empty(): owner._requests_by_actor.erase(actor)
	owner.requests.erase(id)

static func protects(owner: RefCounted, a: int, b: int, now: int) -> bool:
	for id: int in owner._requests_by_actor.get(a, []):
		var request: Dictionary = owner.requests[id]
		if effective_state(request, now) in ["pending", "deferred", "accepted"] and b in [request.issuer, request.recipient]: return true
	return false

static func _close(owner: RefCounted, request: Dictionary, state: String, reason: String, at: int, actor: int = 0) -> void:
	owner._request_by_share.erase(int(request.share))
	request.merge({"state": state, "reason": reason, "changed_ms": at, "review_ms": -1, "cooldown_until_ms": at + COOLDOWN_MS, "closed_by": actor}, true)
	# Do not change reply: a remote outcome is not a delivered message.

static func expire_for(owner: RefCounted, actor: int, now: int) -> void:
	for id: int in owner._requests_by_actor.get(actor, []):
		_expire(owner, owner.requests[id], now)

static func _expire(owner: RefCounted, request: Dictionary, now: int) -> bool:
	if request.state not in ["pending", "deferred"] or now < request.expires_ms: return false
	_close(owner, request, "expired", "request_expired", int(request.expires_ms))
	return true

static func compact(owner: RefCounted, now: int) -> void:
	for request: Dictionary in owner.requests.values():
		_expire(owner, request, now)
	for id: int in owner.requests.keys():
		if not blocks(owner.requests[id], now): _erase(owner, id)

static func _terms(matter: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for field: String in ["kind", "organization", "operation", "item", "sources", "deadline_ms"]: result[field] = State.copy(matter[field])
	return result

static func deliver(owner: RefCounted, world: RefCounted, issuer: int, action: Dictionary, now: int) -> Dictionary:
	if not action.get("target") is int or not action.get("kind") is String: return Results.refused("invalid_request")
	var recipient: int = int(action.get("target", 0))
	if not world.actor_slots.has(issuer) or not world.actor_slots.has(recipient) or not owner.in_contact(world, issuer, recipient, now): return Results.refused("contact_not_completed")
	var kind: String = str(action.get("kind", ""))
	if kind not in ["request_help", "offer_matter"]: return Results.refused("invalid_request")
	var target: int = 0
	var matter: Dictionary = {}
	var terms: Dictionary = {"kind": "operation", "organization": 0, "operation": "construct", "item": "", "sources": [], "deadline_ms": now + 300000}
	var quota: int = 1
	if kind == "offer_matter":
		if not action.get("matter") is int or (action.has("quota") and (not action.quota is int or action.quota < 0)): return Results.refused("invalid_matter_offer")
		matter = world.institutions.matters.get(int(action.matter), {})
		if matter.is_empty() or matter.state != "active" or not world.institutions.Matters._can_manage(world.institutions, world, issuer, matter, true): return Results.refused("cannot_commission")
		terms = _terms(matter)
		target = int(matter.target)
		quota = int(action.get("quota", 0))
		if quota == 0: quota = mini(int(matter.quota), int(matter.total) - world.institutions.Matters.occupied(world.institutions, matter))
		if quota <= 0 or quota > int(matter.total) - world.institutions.Matters.occupied(world.institutions, matter): return Results.refused("cannot_accept_share")
	else:
		if not action.get("task_target") is int or action.task_target <= 0: return Results.refused("invalid_task")
		target = int(action.task_target)
		world.knowledge.refresh(world, issuer, target, now)
		var clue: Dictionary = world.knowledge.view(issuer, target, now)
		if clue.is_empty(): return Results.refused("unknown_task")
		if clue.get("kind") != "blueprint" or int(clue.get("tile", -1)) < 0: return Results.refused("invalid_task")
		if int(clue.get("owner", 0)) not in [0, issuer]: return Results.refused("cannot_commission")
		terms.organization = int(clue.get("organization", 0))
		# Public/private construction uses the same one-place allocation contract.
		if terms.organization > 0: return Results.refused("use_matter_offer")
		for entry: Dictionary in world.institutions.matters.values():
			if entry.target != target or entry.state != "active" or entry.operation != "construct": continue
			if world.institutions.Matters.occupied(world.institutions, entry) > 0: return Results.refused("already_assigned")
			if entry.issuer != issuer or (entry.deadline_ms > 0 and entry.deadline_ms <= now): continue
			if not world.institutions.Matters._can_manage(world.institutions, world, issuer, entry, true): continue
			matter = entry
			terms = _terms(entry)
			break
	if terms.operation == "construct" and world.institutions.Matters.construction_assigned(world.institutions, target): return Results.refused("already_assigned")
	if terms.deadline_ms > 0 and terms.deadline_ms <= now: return Results.refused("matter_expired")
	for subject: int in [target] + terms.sources:
		if int(world.knowledge.view(issuer, subject, now).get("tile", -1)) < 0: return Results.refused("unknown_task")
	var request: Dictionary = {"id": owner.next_request, "issuer": issuer, "recipient": recipient, "kind": kind, "target": target,
		"matter": int(matter.get("id", 0)), "version": int(matter.get("version", 0)), "quota": quota, "terms": terms,
		"delivered_ms": now, "expires_ms": mini(now + RESPONSE_MS, int(terms.deadline_ms)) if terms.deadline_ms > 0 else now + RESPONSE_MS,
		"state": "pending", "changed_ms": now, "review_ms": -1, "cooldown_until_ms": -1, "reason": "request_delivered", "share": 0,
		"accepted_ms": -1, "closed_by": -1,
		"reply": {"state": "pending", "reason": "request_delivered", "at_ms": now}}
	var previous: int = int(owner._requests_by_key.get(key(request), 0))
	if previous > 0 and blocks(owner.requests[previous], now): return Results.refused("already_requested" if owner.requests[previous].reply.state in ["pending", "deferred", "accepted"] and (owner.requests[previous].share > 0 or now < owner.requests[previous].expires_ms) else "request_on_cooldown")
	for person: int in [issuer, recipient]:
		expire_for(owner, person, now)
		var incoming: int = 0
		var outgoing: int = 0
		var recent: int = 0
		for id: int in owner._requests_by_actor.get(person, []):
			var entry: Dictionary = owner.requests[id]
			if entry.state in ["pending", "deferred", "accepted"] and entry.recipient == person: incoming += 1
			if entry.state in ["pending", "deferred"] and entry.issuer == person: outgoing += 1
			if entry.issuer == person and entry.state not in ["pending", "deferred", "accepted"] and blocks(entry, now): recent += 1
		if (person == recipient and incoming >= PENDING_LIMIT) or (person == issuer and (outgoing >= PENDING_LIMIT or recent >= RECENT_LIMIT)): return Results.refused("too_many_requests")
	if owner.requests.size() >= LIMIT: compact(owner, now)
	if owner.requests.size() >= LIMIT: return Results.refused("too_many_requests")
	# Replacing cooled history preserves one canonical key without growing forever.
	if previous > 0 and owner.requests.has(previous): _erase(owner, previous)
	for subject: int in [target] + terms.sources: world.knowledge.deliver(world, recipient, issuer, subject, now, true)
	owner.next_request += 1
	owner.requests[request.id] = request
	_index(owner, request)
	owner.Contacts.acknowledge(owner, world, issuer, recipient, now)
	return Results.completed({"request": int(request.id), "counterparty": recipient}, "request_delivered")

static func response_input_valid(owner: RefCounted, actor: int, input: Dictionary, historical: bool = false) -> bool:
	if not input.get("request") is int or input.request < 1 or input.request >= owner.next_request or not input.get("target") is int: return false
	if input.has("decision") and (input.decision not in ["accept", "refuse", "defer"]): return false
	var request: Dictionary = owner.requests.get(int(input.request), {})
	# A cooled request may be compacted while an admitted contact is travelling.
	if request.is_empty(): return historical
	return actor in [request.issuer, request.recipient] and input.target == (request.issuer if actor == request.recipient else request.recipient) and (not input.has("decision") or actor == request.recipient)

static func sync_contact(owner: RefCounted, world: RefCounted, a: int, b: int, now: int) -> void:
	if not owner.in_contact(world, a, b, now): return
	for id: int in owner._requests_by_actor.get(a, []):
		var request: Dictionary = owner.requests[id]
		if b not in [request.issuer, request.recipient] or request.state not in ["fulfilled", "cancelled"] or (request.reply.state == request.state and request.reply.reason == request.reason): continue
		var evidence: bool = int(request.closed_by) in [a, b]
		if not evidence and request.reason == "task_satisfied":
			for witness: int in [a, b]:
				var clue: Dictionary = world.knowledge.view(witness, int(request.target), now)
				if not clue.is_empty() and int(clue.get("tile", -1)) >= 0 and clue.kind != "blueprint":
					evidence = true
					world.knowledge.deliver(world, b if witness == a else a, witness, int(request.target), now)
					break
		if evidence: request.reply = {"state": str(request.state), "reason": str(request.reason), "at_ms": now}

static func follow_up(owner: RefCounted, world: RefCounted, actor: int, other: int, id: int, now: int) -> Dictionary:
	if not owner.in_contact(world, actor, other, now): return Results.refused("contact_not_completed")
	var request: Dictionary = owner.requests.get(id, {})
	if request.is_empty() or actor not in [request.issuer, request.recipient] or other not in [request.issuer, request.recipient] or actor == other: return Results.refused("request_unavailable")
	expire_for(owner, actor, now)
	sync_contact(owner, world, actor, other, now)
	if request.state in ["fulfilled", "cancelled"]:
		# A real attempt can discover that this contract is unavailable. It cannot
		# discover who changed it elsewhere or whether an unseen site is finished.
		if request.reply.state not in ["fulfilled", "cancelled"]: request.reply = {"state": "cancelled", "reason": "request_unavailable", "at_ms": now}
		return Results.completed({"request": id, "counterparty": other}, str(request.reply.reason))
	if request.state in ["expired", "refused"]: return Results.completed({"request": id, "counterparty": other}, "request_expired" if request.state == "expired" else str(request.reply.reason))
	if request.state == "accepted":
		request.reply = {"state": "accepted", "reason": "accepted_share", "at_ms": now}
		return Results.completed({"request": id, "counterparty": other}, "accepted_share")
	return {}

static func respond(owner: RefCounted, world: RefCounted, actor: int, id: int, decision: String, reason: String, now: int) -> Dictionary:
	var request: Dictionary = owner.requests.get(id, {})
	if request.is_empty() or request.recipient != actor or not reason.is_valid_identifier() or reason.length() > 80: return Results.refused("invalid_request")
	if not owner.in_contact(world, actor, int(request.issuer), now): return Results.refused("contact_not_completed")
	expire_for(owner, actor, now)
	if decision not in ["accept", "defer", "refuse"]: return Results.refused("invalid_response")
	if request.state not in ["pending", "deferred"]:
		var follow: Dictionary = follow_up(owner, world, actor, int(request.issuer), id, now)
		return follow if not follow.is_empty() else Results.refused("request_unavailable")
	if decision == "defer":
		if now + 1 >= request.expires_ms: return Results.refused("request_expiring")
		request.merge({"state": "deferred", "reason": reason, "changed_ms": now, "review_ms": mini(now + DEFER_MS, int(request.expires_ms) - 1)}, true)
	elif decision == "refuse": _close(owner, request, "refused", reason, now, actor)
	elif decision == "accept":
		var rejection: String = _accept(owner, world, request, now)
		if not rejection.is_empty():
			_close(owner, request, "refused", rejection, now, actor)
		else: request.merge({"state": "accepted", "reason": "accepted_share", "changed_ms": now, "accepted_ms": now, "review_ms": -1}, true)
	else: return Results.refused("invalid_response")
	request.reply = {"state": str(request.state), "reason": str(request.reason), "at_ms": now}
	var facts: Dictionary = {"request": id, "counterparty": int(request.issuer)}
	if request.matter > 0: facts["matter"] = int(request.matter)
	if request.share > 0: facts["share"] = int(request.share)
	return Results.completed(facts, str(request.reason))

static func _accept(owner: RefCounted, world: RefCounted, request: Dictionary, now: int) -> String:
	var actor: int = request.recipient
	var terms: Dictionary = request.terms
	var required: String = "put" if terms.kind == "delivery" else str(terms.operation)
	if not Operations.capability_reason(world.objects.records[actor], required).is_empty(): return "refused_capability"
	for target: int in [request.target] + terms.sources:
		if int(world.knowledge.view(actor, target, now).get("tile", -1)) < 0: return "task_not_understood"
	if terms.operation == "construct" and world.institutions.Matters.construction_assigned(world.institutions, int(request.target)): return "already_assigned"
	var matter: Dictionary = world.institutions.matters.get(int(request.matter), {})
	var created: bool = false
	if world.institutions.Matters.shares_for(world.institutions, actor).size() >= world.institutions.Matters.PERSON_LIMIT: return "refused_capacity"
	if request.kind == "request_help" and request.matter == 0:
		if matter.is_empty():
			var id: int = world.institutions.create_matter(world, int(request.issuer), {"kind": "operation", "target": int(request.target), "operation": "construct", "deadline_ms": int(terms.deadline_ms)})
			if id == 0: return "cannot_commission"
			matter = world.institutions.matters[id]
			created = true
	else:
		if matter.is_empty() or matter.state != "active" or matter.version != request.version or not world.institutions.Matters._can_manage(world.institutions, world, int(request.issuer), matter, true): return "terms_changed"
	for existing: Dictionary in world.institutions.Matters.shares_for(world.institutions, actor):
		if existing.matter == matter.id: return "already_accepted"
	# Player/manual acceptance creates a responsibility without taking control.
	var temporary: bool = actor != 1 and not world.decisions.records.get(actor, {}).get("manual", false)
	var share: int = world.institutions.accept_share(world, actor, int(matter.id), int(request.quota), temporary)
	if share == 0:
		if created: world.institutions.cancel_matter(world, int(request.issuer), int(matter.id))
		return "cannot_accept_share"
	request.matter = int(matter.id)
	request.version = int(matter.version)
	request.share = share
	owner._request_by_share[share] = request.id
	return ""

static func share_closed(owner: RefCounted, share: Dictionary, completed: bool, now: int, actor: int = 0) -> void:
	var request: Dictionary = owner.requests.get(int(owner._request_by_share.get(int(share.id), 0)), {})
	if request.is_empty() or request.state != "accepted": return
	_close(owner, request, "fulfilled" if completed else "cancelled", "share_completed" if completed else "share_released", now, actor)

static func matter_closed(owner: RefCounted, matter: int, now: int, actor: int = 0) -> void:
	for request: Dictionary in owner.requests.values():
		if request.matter == matter and request.state in ["pending", "deferred"] and not _expire(owner, request, now): _close(owner, request, "cancelled", "matter_closed", now, actor)

static func construction_completed(owner: RefCounted, target: int, now: int, actor: int = 0) -> void:
	for request: Dictionary in owner.requests.values():
		if request.target == target and request.kind == "request_help" and request.state in ["pending", "deferred"] and not _expire(owner, request, now): _close(owner, request, "cancelled", "task_satisfied", now, actor)

static func actor_removed(owner: RefCounted, actor: int, now: int) -> void:
	for id: int in owner._requests_by_actor.get(actor, []):
		var request: Dictionary = owner.requests[id]
		if request.state in ["pending", "deferred", "accepted"] and not _expire(owner, request, now): _close(owner, request, "cancelled", "participant_unavailable", now)

static func views(owner: RefCounted, actor: int, now: int) -> Array:
	var result: Array = []
	for id: int in owner._requests_by_actor.get(actor, []):
		var request: Dictionary = owner.requests[id]
		var view: Dictionary = {}
		for field: String in ["id", "issuer", "recipient", "kind", "target", "matter", "version", "quota", "terms", "delivered_ms", "expires_ms", "accepted_ms"]: view[field] = State.copy(request[field])
		view.state = str(request.reply.state)
		view.reason = str(request.reply.reason)
		view.changed_ms = int(request.reply.at_ms)
		view.review_ms = mini(int(request.reply.at_ms) + DEFER_MS, int(request.expires_ms) - 1) if view.state == "deferred" else -1
		if view.state in ["pending", "deferred"] and now >= request.expires_ms: view.state = "expired"; view.reason = "request_expired"; view.changed_ms = int(request.expires_ms); view.review_ms = -1
		result.append(view)
	return result

static func _terms_valid(terms: Variant, world: RefCounted) -> bool:
	if not terms is Dictionary or terms.size() != 6 or terms.get("kind") not in ["delivery", "produce", "operation"]: return false
	if not terms.get("organization") is int or terms.organization < 0 or (terms.organization > 0 and not world.institutions.organizations.has(terms.organization)): return false
	if not terms.get("operation") is String or not terms.get("item") is String or not terms.get("sources") is Array or terms.sources.size() > world.institutions.Matters.SOURCE_LIMIT or not terms.get("deadline_ms") is int or terms.deadline_ms < 0: return false
	if terms.kind == "delivery":
		if terms.organization == 0 or terms.sources.is_empty() or not terms.operation.is_empty() or not Items.valid(terms.item): return false
	elif not Operations.OPERATIONS.has(terms.operation): return false
	elif terms.kind == "produce":
		if terms.organization == 0 or Operations.OPERATIONS[terms.operation].recipe.is_empty() or not Operations.OPERATIONS[terms.operation].recipe.outputs.has(terms.item): return false
	elif not terms.item.is_empty() or not Operations.OPERATIONS[terms.operation].recipe.is_empty(): return false
	if terms.organization == 0 and (terms.operation != "construct" or not terms.sources.is_empty()): return false
	var seen: Dictionary = {}
	for source: Variant in terms.sources:
		if not source is int or source < 1 or source >= world.objects.next_id or seen.has(source): return false
		seen[source] = true
	return true

static func valid(owner: RefCounted, world: RefCounted) -> bool:
	if owner.next_request < 1 or owner.next_request > 999999999999 or owner.requests.size() > LIMIT: return false
	owner._requests_by_key.clear(); owner._requests_by_actor.clear(); owner._request_by_share.clear()
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}
	var seen_shares: Dictionary = {}
	var archived_requests: Dictionary = {}
	var previous: int = 0
	for id: Variant in owner.requests:
		var request: Variant = owner.requests[id]
		if not id is int or id <= previous or id >= owner.next_request or not request is Dictionary or request.size() != 20: return false
		previous = id
		for field: String in ["id", "issuer", "recipient", "target", "matter", "version", "quota", "delivered_ms", "expires_ms", "changed_ms", "review_ms", "cooldown_until_ms", "share", "accepted_ms", "closed_by"]:
			if not request.get(field) is int: return false
		if request.closed_by < -1 or request.closed_by >= world.objects.next_id or ((request.get("state") in ["pending", "deferred", "accepted"]) != (request.closed_by == -1)): return false
		if request.closed_by > 0 and world.objects.records.has(request.closed_by) and world.objects.records[request.closed_by].kind != "actor": return false
		if request.id != id or request.issuer < 1 or request.recipient < 1 or request.issuer == request.recipient or request.issuer >= world.objects.next_id or request.recipient >= world.objects.next_id or request.target < 1 or request.target >= world.objects.next_id: return false
		for actor: int in [request.issuer, request.recipient]:
			if world.objects.records.has(actor) and world.objects.records[actor].kind != "actor": return false
		if request.get("kind") not in ["request_help", "offer_matter"] or request.get("state") not in STATES or not request.get("reason") is String or not request.reason.is_valid_identifier() or request.reason.length() > 80 or not _terms_valid(request.get("terms"), world): return false
		if request.state == "refused" and request.closed_by != request.recipient: return false
		if (request.state == "expired" or request.reason == "participant_unavailable") and request.closed_by != 0: return false
		if request.state == "fulfilled" and request.closed_by <= 0: return false
		if request.delivered_ms < 0 or request.changed_ms < request.delivered_ms or request.changed_ms > world.operation_time() or request.expires_ms <= request.delivered_ms or request.expires_ms > request.delivered_ms + RESPONSE_MS or request.review_ms < -1 or request.cooldown_until_ms < -1: return false
		if request.matter < 0 or request.matter >= world.institutions.next_matter or request.version < 0 or (request.matter == 0) != (request.version == 0) or request.share < 0 or request.share >= world.institutions.next_share or request.quota < 1 or request.quota > 1000000: return false
		if (request.share > 0) != (request.accepted_ms >= 0) or request.accepted_ms < -1: return false
		if request.share > 0 and (request.accepted_ms < request.delivered_ms or request.accepted_ms >= request.expires_ms or request.accepted_ms > request.changed_ms): return false
		if request.terms.deadline_ms > 0 and request.terms.deadline_ms <= request.delivered_ms: return false
		if request.expires_ms != (mini(int(request.delivered_ms) + RESPONSE_MS, int(request.terms.deadline_ms)) if request.terms.deadline_ms > 0 else int(request.delivered_ms) + RESPONSE_MS): return false
		if request.terms.kind == "delivery" and request.target in request.terms.sources: return false
		if request.matter > 0 and not world.institutions.matters.has(int(request.matter)) and not world.institutions.matter_ledger.has(int(request.terms.organization)): return false
		if request.state in ["pending", "deferred"] and request.matter > 0 and (not world.institutions.matters.has(int(request.matter)) or world.institutions.matters[int(request.matter)].state != "active"): return false
		if request.matter > 0 and world.institutions.matters.has(int(request.matter)):
			var matter: Dictionary = world.institutions.matters[int(request.matter)]
			if matter.target != request.target or request.version > matter.version: return false
			for field: String in ["kind", "organization", "operation", "item", "sources"]:
				if request.terms[field] != matter[field]: return false
			if request.version == matter.version and request.terms.deadline_ms != matter.deadline_ms: return false
		if request.kind == "offer_matter" and request.matter == 0: return false
		if request.kind == "request_help" and (request.quota != 1 or request.terms.kind != "operation" or request.terms.operation != "construct" or request.terms.organization != 0 or not request.terms.sources.is_empty()): return false
		if request.kind == "request_help" and request.matter == 0 and request.terms.deadline_ms != int(request.delivered_ms) + 300000: return false
		var reply: Variant = request.get("reply")
		if not _reply_valid(request, world.operation_time()): return false
		if int(world.institutions.matters.get(int(request.matter), {}).get("created_ms", 0)) > (int(request.accepted_ms) if request.share > 0 and request.kind == "request_help" else int(request.delivered_ms)): return false
		if request.kind == "request_help" and int(world.institutions.matters.get(int(request.matter), {}).get("created_ms", 0)) > request.delivered_ms:
			if request.share == 0 or world.institutions.matters[int(request.matter)].created_ms != request.accepted_ms or request.terms.deadline_ms != int(request.delivered_ms) + 300000: return false
		if (request.state == "deferred") != (request.review_ms >= 0) or (request.state == "deferred" and request.review_ms != mini(int(request.changed_ms) + DEFER_MS, int(request.expires_ms) - 1)): return false
		if request.state == "pending" and (request.reason != "request_delivered" or request.changed_ms != request.delivered_ms or reply.reason != request.reason): return false
		if request.state == "refused" and (reply.state != "refused" or reply.at_ms != request.changed_ms or reply.reason != request.reason): return false
		if request.state == "deferred" and (reply.at_ms != request.changed_ms or reply.reason != request.reason): return false
		if request.state in ["deferred", "accepted", "refused"] and request.changed_ms >= request.expires_ms: return false
		if request.state == "expired" and (request.reason != "request_expired" or reply.state not in ["pending", "deferred"]): return false
		if request.state == "cancelled" and (reply.state == "refused" or (request.share == 0 and request.changed_ms >= request.expires_ms)): return false
		if request.state == "cancelled":
			if request.reason not in (["share_released", "participant_unavailable"] if request.share > 0 else ["matter_closed", "task_satisfied", "participant_unavailable"]): return false
			if request.reason == "participant_unavailable" and world.combat.alive(world, int(request.issuer)) and world.combat.alive(world, int(request.recipient)): return false
			if request.reason == "task_satisfied" and (request.kind != "request_help" or world.objects.records.get(int(request.target), {}).get("kind") == "blueprint"): return false
			if request.reason == "matter_closed" and (request.matter == 0 or world.institutions.matters.get(int(request.matter), {}).get("state") == "active"): return false
		if reply.state == "deferred" and reply.at_ms + 1 >= request.expires_ms: return false
		if reply.state == "pending" and (reply.reason != "request_delivered" or reply.at_ms != request.delivered_ms): return false
		if reply.state == "accepted" and reply.reason != "accepted_share": return false
		if request.state == "accepted" and request.reason != "accepted_share": return false
		if request.state == "fulfilled" and request.reason != "share_completed": return false
		if request.state in ["pending", "deferred", "accepted"]:
			if request.cooldown_until_ms != -1 or request.reply.state != request.state: return false
			for actor: int in [request.issuer, request.recipient]:
				if not world.actor_slots.has(actor) or not world.combat.alive(world, actor): return false
		elif request.cooldown_until_ms != request.changed_ms + COOLDOWN_MS: return false
		if request.state == "expired" and request.changed_ms != request.expires_ms: return false
		if request.state in ["accepted", "fulfilled"]:
			if request.share == 0 or (request.state == "accepted" and request.reply.state != "accepted"): return false
		elif request.state != "cancelled" and request.share != 0: return false
		if request.share > 0:
			if request.matter == 0 or seen_shares.has(request.share): return false
			seen_shares[request.share] = true
		if request.state == "accepted":
			var share: Dictionary = world.institutions.shares.get(int(request.share), {})
			if share.get("actor") != request.recipient or share.get("matter") != request.matter or share.get("state") != "accepted" or share.get("quota") != request.quota or owner._request_by_share.has(request.share): return false
		if request.share > 0 and world.institutions.shares.has(int(request.share)):
			var share: Dictionary = world.institutions.shares[int(request.share)]
			if share.actor != request.recipient or share.matter != request.matter or share.quota != request.quota or share.created_ms != request.accepted_ms or share.deadline_ms != request.terms.deadline_ms: return false
			if request.state == "fulfilled" and share.state != "completed": return false
			if request.state == "cancelled" and share.state != "released" and (request.reason != "participant_unavailable" or (world.combat.alive(world, int(request.issuer)) and world.combat.alive(world, int(request.recipient)))): return false
		elif request.state == "fulfilled":
			var matter: Dictionary = world.institutions.matters.get(int(request.matter), {})
			var archive_key: String = "matter:%d" % request.matter if not matter.is_empty() else "%d:%s" % [request.terms.organization, request.terms.kind]
			archived_requests[archive_key] = int(archived_requests.get(archive_key, 0)) + int(request.quota)
			var amount: int = int(matter.archived) if not matter.is_empty() else int(world.institutions.matter_ledger.get(int(request.terms.organization), {}).get(str(request.terms.kind), 0))
			if int(archived_requests[archive_key]) > amount: return false
		if owner._requests_by_key.has(key(request)): return false
		_index(owner, request)
		if request.state in ["pending", "deferred", "accepted"]: incoming[int(request.recipient)] = int(incoming.get(int(request.recipient), 0)) + 1
		if request.state in ["pending", "deferred"]: outgoing[int(request.issuer)] = int(outgoing.get(int(request.issuer), 0)) + 1
	for count: int in incoming.values() + outgoing.values():
		if count > PENDING_LIMIT: return false
	return true

static func _reply_valid(request: Dictionary, now: int) -> bool:
	var reply: Variant = request.get("reply")
	if not reply is Dictionary or reply.size() != 3 or reply.get("state") not in ["pending", "deferred", "accepted", "refused", "fulfilled", "cancelled"] or not reply.get("reason") is String or not reply.reason.is_valid_identifier() or reply.reason.length() > 80 or not reply.get("at_ms") is int or reply.at_ms < request.delivered_ms or reply.at_ms > now: return false
	match reply.state:
		"pending":
			if reply.at_ms != request.delivered_ms or reply.reason != "request_delivered" or request.share > 0 or request.state not in ["pending", "expired", "cancelled"]: return false
		"deferred":
			if reply.at_ms >= request.expires_ms - 1 or reply.at_ms > request.changed_ms or request.share > 0 or request.state not in ["deferred", "expired", "cancelled"]: return false
		"accepted":
			if request.share <= 0 or reply.reason != "accepted_share" or reply.at_ms < request.accepted_ms or request.state not in ["accepted", "fulfilled", "cancelled"]: return false
			if request.state != "accepted" and reply.at_ms > request.changed_ms: return false
		"refused":
			if request.state != "refused" or reply.at_ms != request.changed_ms or reply.reason != request.reason: return false
		"fulfilled":
			if request.state != "fulfilled" or reply.reason != "share_completed" or reply.at_ms < request.changed_ms: return false
		"cancelled":
			if request.state not in ["cancelled", "fulfilled"] or reply.at_ms < request.changed_ms: return false
			if reply.reason != "request_unavailable" and (request.state != "cancelled" or reply.reason != request.reason): return false
	return true
