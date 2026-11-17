extends RefCounted
## Contact methods consume personal messages and last-known people only.
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Requests = preload("res://scripts/sim/kernel/society_requests.gd")
const FOLLOW_UP_MS: int = 30000

static func due(request: Dictionary, actor: int, responsibilities: Dictionary = {}) -> int:
	if request.get("peer_known_dead", false): return -1
	if request.state == "pending": return int(request.delivered_ms) if actor == request.recipient else -1
	if request.state == "deferred": return int(request.review_ms)
	if request.state == "accepted":
		if request.recipient == actor and responsibilities.values().any(func(share: Dictionary): return share.matter == request.matter): return -1
		return int(request.changed_ms) + FOLLOW_UP_MS
	return -1

static func next_due(actor: Dictionary, at: int) -> int:
	var result: int = -1
	for request: Dictionary in actor.get("requests", []):
		var time: int = due(request, int(actor.id), actor.get("responsibilities", {}))
		if time > at and (result < 0 or time < result): result = time
	return result

static func responding(actor: Dictionary, at: int) -> bool:
	return actor.get("requests", []).any(func(request: Dictionary): return due(request, int(actor.id), actor.get("responsibilities", {})) >= 0 and due(request, int(actor.id), actor.get("responsibilities", {})) <= at)

static func judgment_due(actor: Dictionary, at: int) -> bool:
	return actor.get("requests", []).any(func(request: Dictionary): return request.recipient == actor.id and request.state in ["pending", "deferred"] and int(request.get("peer_tile", -1)) >= 0 and due(request, int(actor.id)) >= 0 and due(request, int(actor.id)) <= at)

static func responses(p: RefCounted) -> Array:
	var result: Array = []
	var eligible: Array = p.actor.get("requests", []).filter(func(request: Dictionary): return due(request, int(p.actor.id), p.actor.get("responsibilities", {})) >= 0 and due(request, int(p.actor.id), p.actor.get("responsibilities", {})) <= p.at_ms)
	eligible = eligible.filter(func(request: Dictionary):
		var other: int = int(request.issuer) if request.recipient == p.actor.id else int(request.recipient)
		return int(p.known.get(other, {}).get("tile", -1)) >= 0 and not p._denied("respond_request", other) and int(p.actor.get("request_retries", {}).get(int(request.id), 0)) <= p.at_ms)
	if not eligible.is_empty():
		var offset: int = int(p.budget.cursor) % eligible.size()
		eligible = eligible.slice(offset) + eligible.slice(0, offset)
	# A received answer due now precedes optional checks of accepted promises.
	eligible = eligible.filter(func(request: Dictionary): return request.recipient == p.actor.id and request.state in ["pending", "deferred"]) + eligible.filter(func(request: Dictionary): return not (request.recipient == p.actor.id and request.state in ["pending", "deferred"]))
	for request: Dictionary in eligible:
		var time: int = due(request, int(p.actor.id), p.actor.get("responsibilities", {}))
		if time < 0 or time > p.at_ms: continue
		var other: int = int(request.issuer) if request.recipient == p.actor.id else int(request.recipient)
		var target: Dictionary = p.known.get(other, {})
		if int(target.get("tile", -1)) < 0: continue
		var step: Dictionary = p._resolve(Operations.OPERATIONS.respond_request, target, [], false, {"request": int(request.id)})
		if not step.is_empty():
			step["social"] = true
			result.append(p._option(step, "respond_request", other))
		if int(p.budget.work) >= p.slice_limit: break
	return result

static func seek_help(p: RefCounted, goal: Dictionary) -> Array:
	# First consumer: a known prepaid personal construction task that this
	# body cannot work on. We do not infer strangers' skills or job labels.
	if goal.params.operation != "construct" or p.actor.body_capabilities.work: return []
	var target: int = int(goal.params.target)
	var place: Dictionary = p.known.get(target, {})
	if place.get("kind") != "blueprint" or int(place.get("organization", 0)) > 0 or int(place.get("owner", 0)) not in [0, int(p.actor.id)]: return []
	if p.actor.get("requests", []).any(func(request: Dictionary): return request.issuer == p.actor.id and request.target == target and request.state in ["pending", "deferred", "accepted"]): return []
	if p.actor.get("requests", []).filter(func(request: Dictionary): return request.issuer == p.actor.id and request.state in ["pending", "deferred"]).size() >= Requests.PENDING_LIMIT: return []
	var result: Array = []
	for peer: int in p.actor.get("contacts", {}):
		if not p._spend(): break
		var clue: Dictionary = p.known.get(peer, {})
		if int(clue.get("tile", -1)) < 0 or clue.kind != "actor": continue
		var blocked: bool = false
		for request: Dictionary in p.actor.get("requests", []):
			if request.issuer != p.actor.id or request.recipient != peer or request.target != target: continue
			if request.state in ["pending", "deferred", "accepted"] or p.at_ms < int(request.changed_ms) + Requests.COOLDOWN_MS: blocked = true; break
		if blocked: continue
		var step: Dictionary = p._resolve(Operations.OPERATIONS.request_help, clue, [], false, {"help_target": target, "task_target": target})
		if not step.is_empty():
			step["social"] = true
			var experience: Dictionary = p.actor.get("social_appraisals", {}).get(peer, {})
			step.confidence = minf(1.0, 0.7 + int(experience.get("support", 0)) * 0.05 + int(experience.get("exchanges", 0)) * 0.02)
			result.append(p._option(step, "request_help", peer))
	return result
