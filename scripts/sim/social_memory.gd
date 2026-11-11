class_name SimSocialMemory
extends RefCounted
## Objective events, attributed knowledge, directed memories and bounded requests.
## Event details are private by default. Surface fields below are observable;
## `public` explicitly addresses everyone present, `participants` only the two
## parties. `private`, reason and unlisted fields stay in the objective log.
## Learning preserves the informant's disclosure scope, never revealing the objective event.

const VERSION: int = 2
const LEGACY_VERSION: int = 1
const SURFACE_FIELDS: Array[String] = [
	"item", "item_id", "resource", "amount", "quantity", "task", "status",
	"outcome", "request_id", "job_id", "location", "offer", "terms", "text",
	"from", "to", "duration", "action", "result", "promise_id",
]
const FACTOR_DEFAULTS: Dictionary = {
	"energy": 1.0, "busy": 0.0, "distance": 0.0, "risk": 0.0,
	"duty": 0.0, "offer": 0.0, "benevolence": 0.0,
	"reliability": 0.5, "affinity": 0.0,
}
const OUTCOME_EFFECTS: Dictionary = {
	"fulfilled": [0.05, 0.05], "completed": [0.05, 0.05],
	"helped": [0.05, 0.05], "kept_promise": [0.05, 0.05],
	"failed": [-0.05, 0.0], "broke_promise": [-0.05, -0.05],
	"betrayed": [-0.05, -0.05], "refused": [0.0, 0.0],
}

var events: Array[Dictionary] = []
var relationships: Dictionary = {}
var requests: Dictionary = {}

class Observer extends RefCounted:
	# Direct knowledge indexes the original event audience. Only retelling
	# needs extra facts: immediate source and the original disclosure scope.
	var direct := PackedInt32Array()
	var order := PackedInt32Array()
	var heard: Dictionary[int, Array] = {}

	func saw(index: int) -> bool:
		var at: int = direct.bsearch(index)
		return at < direct.size() and direct[at] == index

	func knows(index: int) -> bool:
		return heard.has(index) or saw(index)

	func add_direct(index: int) -> void:
		direct.append(index)
		order.append(index)


var _actors: Dictionary[String, Observer] = {}
var _event_indices: Dictionary[String, int] = {}
var _scopes: Dictionary[int, Array] = {}
var _next_event_id: int = 1
var _next_request_id: int = 1
var _outcome_effects: Dictionary = OUTCOME_EFFECTS.duplicate(true)


func configure(policy: Dictionary) -> void:
	# Policy definitions are fixed once memories exist: changing deltas later
	# would retroactively reinterpret the same saved evidence.
	for observer: String in relationships:
		if not relationships[observer].is_empty():
			return
	var effects: Variant = policy.get("outcome_effects", {})
	if effects is Dictionary:
		var configured: Dictionary = _validated_effects(effects)
		if not configured.is_empty():
			_outcome_effects = configured


func register_actor(actor_id: String) -> void:
	if actor_id.is_empty() or _actors.has(actor_id):
		return
	_actors[actor_id] = Observer.new()
	relationships[actor_id] = {}


func record(
	kind: String, actor: String, target: String, details: Dictionary,
	witnesses: Array[String], tick: int
) -> String:
	if kind.is_empty() or not _actors.has(actor) or tick < 0:
		return ""
	if not target.is_empty() and not _actors.has(target):
		return ""
	if not _valid_details(details):
		return ""
	var observed_by: Array[String] = []
	var unique: Dictionary[String, bool] = {}
	for witness: String in witnesses:
		if not _actors.has(witness):
			return ""
		if not unique.has(witness):
			unique[witness] = true
			observed_by.append(witness)
	var event_id: String = "event_%d" % _next_event_id
	_next_event_id += 1
	var event: Dictionary = {
		"id": event_id, "kind": kind, "actor": actor, "target": target,
		"details": details.duplicate(true), "witnesses": observed_by, "tick": tick,
	}
	var index: int = _append_event(event)
	_index_direct_observations(index)
	return event_id


func _append_event(event: Dictionary) -> int:
	var index: int = events.size()
	_event_indices[event.id] = index
	_freeze_details(event)
	events.append(event)
	return index


func _index_direct_observations(index: int) -> void:
	var event: Dictionary = events[index]
	_actors[event.actor].add_direct(index)
	if not event.target.is_empty() and event.target != event.actor:
		_actors[event.target].add_direct(index)
	for witness: String in event.witnesses:
		if witness != event.actor and witness != event.target:
			_actors[witness].add_direct(index)


func learn(actor: String, event_id: String, source: String) -> bool:
	if not _actors.has(actor) or not _actors.has(source) or actor == source:
		return false
	var index: int = _event_indices.get(event_id, -1)
	var from: Observer = _actors[source]
	var to: Observer = _actors[actor]
	if index < 0 or to.knows(index) or not from.knows(index):
		return false
	var participants: bool = bool(from.heard[index][1]) if from.heard.has(index) else _participant(events[index], source)
	to.heard[index] = [source, participants]
	to.order.append(index)
	return true


func has_actor(actor: String) -> bool:
	return _actors.has(actor)


func actor_count() -> int:
	return _actors.size()


func observation_count() -> int:
	var total: int = 0
	for observer: Observer in _actors.values():
		total += observer.order.size()
	return total


func knows(actor: String, event_id: String) -> bool:
	var observer: Observer = _actors.get(actor)
	var index: int = _event_indices.get(event_id, -1)
	return observer != null and index >= 0 and observer.knows(index)


func saw(actor: String, event_id: String) -> bool:
	var observer: Observer = _actors.get(actor)
	var index: int = _event_indices.get(event_id, -1)
	return observer != null and index >= 0 and observer.saw(index)


func objective_event(event_id: String) -> Dictionary:
	# For domain validation. Player-facing readers use observation() instead.
	var index: int = _event_indices.get(event_id, -1)
	return events[index] if index >= 0 else {}


func observation(actor: String, event_id: String) -> Dictionary:
	var observer: Observer = _actors.get(actor)
	var index: int = _event_indices.get(event_id, -1)
	return _known_at(actor, observer, index) if observer != null and index >= 0 and observer.knows(index) else {}


func known_events(actor: String, kind: String = "", in_acquisition_order: bool = false, limit: int = -1) -> Array[Dictionary]:
	var visible: Array[Dictionary] = []
	var observer: Observer = _actors.get(actor)
	if observer == null or limit == 0:
		return visible
	var indices: PackedInt32Array = observer.order if in_acquisition_order else observer.direct
	if not in_acquisition_order and not observer.heard.is_empty():
		indices = indices.duplicate()
		for index: int in observer.heard:
			indices.append(index)
		indices.sort()
	for offset: int in indices.size():
		var index: int = indices[offset if limit < 0 else indices.size() - 1 - offset]
		if kind.is_empty() or events[index].kind == kind:
			visible.append(_known_at(actor, observer, index).duplicate(true))
			if visible.size() == limit:
				break
	if limit >= 0:
		visible.reverse()
	return visible


func _known_at(actor: String, observer: Observer, index: int) -> Dictionary:
	var event: Dictionary = events[index]
	var received: Array = observer.heard.get(index, [])
	var direct: bool = received.is_empty()
	var participants: bool = _participant(event, actor) if direct else bool(received[1])
	return _observation(event, actor if direct else str(received[0]), _view(index, participants), direct)


func _view(index: int, participants: bool) -> Dictionary:
	if not _scopes.has(index):
		var details: Dictionary = events[index].details
		var public_view: Dictionary = _public_details(details)
		var participant_view: Dictionary = _participant_details(details, public_view)
		_freeze_details(public_view)
		if not is_same(public_view, participant_view):
			_freeze_details(participant_view)
		_scopes[index] = [public_view, participant_view]
	return _scopes[index][int(participants)]


func remember_outcome(
	observer: String, other: String, outcome: String, event_id: String
) -> bool:
	if not _actors.has(observer) or not _actors.has(other) or observer == other:
		return false
	var known: Dictionary = observation(observer, event_id)
	if known.is_empty() or not OUTCOME_EFFECTS.has(outcome):
		return false
	if known["actor"] != other and known["target"] != other:
		return false
	var memory: Dictionary = relation(observer, other)
	for entry: Dictionary in memory["history"]:
		if entry["event_id"] == event_id:
			return false
	var effect: Array = _outcome_effects[outcome]
	memory["reliability"] = clampf(float(memory["reliability"]) + effect[0], 0.0, 1.0)
	memory["affinity"] = clampf(float(memory["affinity"]) + effect[1], -1.0, 1.0)
	memory["history"].append({
		"event_id": event_id, "outcome": outcome, "source": known["source"],
	})
	relationships[observer][other] = memory
	return true


func relation(observer: String, other: String) -> Dictionary:
	if relationships.has(observer) and relationships[observer].has(other):
		return relationships[observer][other].duplicate(true)
	return {"reliability": 0.5, "affinity": 0.0, "history": []}


func evaluate_request(
	requester: String, responder: String, task: String, context: Dictionary,
	policy: Dictionary, rng: RandomNumberGenerator, tick: int
) -> Dictionary:
	if (
		not _actors.has(requester) or not _actors.has(responder)
		or requester == responder or task.is_empty() or tick < 0 or rng == null
	):
		return _invalid_request(requester, responder, task, "invalid_request")
	var rules: Dictionary = _normalized_policy(policy)
	if rules.is_empty():
		return _invalid_request(requester, responder, task, "invalid_policy")
	var factors: Dictionary = _normalized_context(context, float(rules["context_step"]))
	if factors.is_empty():
		return _invalid_request(requester, responder, task, "invalid_context")
	var cache_key: String = _request_key(requester, responder, task, factors, rules)
	if requests.has(cache_key):
		return requests[cache_key].duplicate(true)
	var score: float = _score(factors, rules)
	var margin: float = score - float(rules["accept_threshold"])
	var band: float = rules["uncertainty_band"]
	var uncertain: bool = band > 0.0 and absf(margin) < band
	var chance: float = clampf(0.5 + margin / (2.0 * band), 0.0, 1.0) if uncertain else (
		1.0 if margin >= 0.0 else 0.0
	)
	var roll: float = rng.randf() if uncertain else -1.0
	var accepted: bool = roll < chance if uncertain else margin >= 0.0
	var reasons: Array[String] = _reasons(factors, rules, accepted)
	var result: Dictionary = {
		"id": "request_%d" % _next_request_id,
		"requester": requester, "responder": responder, "task": task,
		"status": "accepted" if accepted else "refused", "reason": reasons[0],
		"reasons": reasons, "tick": tick, "context": factors, "policy": rules,
		"score": score, "chance": chance, "roll": roll, "uncertain": uncertain,
	}
	_next_request_id += 1
	requests[cache_key] = result
	return result.duplicate(true)


func to_dict() -> Dictionary:
	var actor_ids: Array = _actors.keys()
	actor_ids.sort()
	return {
		"version": VERSION, "actors": actor_ids, "events": events.duplicate(true),
		"knowledge": _snapshot_knowledge(), "relationships": relationships.duplicate(true),
		"requests": requests.duplicate(true), "next_event_id": _next_event_id,
		"next_request_id": _next_request_id, "outcome_effects": _outcome_effects.duplicate(true),
	}


func _snapshot_knowledge() -> Dictionary:
	var result: Dictionary = {}
	for actor: String in _actors:
		var observer: Observer = _actors[actor]
		# Direct facts and their normal order are already in the event ledger.
		# Keep only what cannot be recovered from it: retelling and actual order.
		if observer.heard.is_empty() and observer.order == observer.direct:
			continue
		var heard: Dictionary = {}
		for index: int in observer.heard:
			heard[events[index].id] = observer.heard[index][0]
		var order: Array = []
		order.assign(observer.order)
		result[actor] = {"heard": heard, "order": order}
	return result


func restore(data: Dictionary) -> bool:
	# All validation and reconstruction happens off to the side.
	var version: Variant = data.get("version")
	if not _serializable(data) or (version != LEGACY_VERSION and version != VERSION):
		return false
	if (
		not data.get("actors") is Array or not data.get("events") is Array
		or not data.get("knowledge") is Dictionary
		or not data.get("relationships") is Dictionary or not data.get("requests") is Dictionary
		or not data.get("outcome_effects") is Dictionary
		or not _integer_at_least(data.get("next_event_id"), 1)
		or not _integer_at_least(data.get("next_request_id"), 1)
	):
		return false
	# Avoid requiring the editor's global class cache during headless preload.
	var staged: Variant = get_script().new()
	staged._outcome_effects = _validated_effects(data["outcome_effects"])
	if staged._outcome_effects.is_empty():
		return false
	if _canonical(staged._outcome_effects) != _canonical(data["outcome_effects"]):
		return false
	for actor_id: Variant in data["actors"]:
		if not actor_id is String or actor_id.is_empty() or staged._actors.has(actor_id):
			return false
		staged.register_actor(actor_id)
	var largest_event: int = 0
	for raw: Variant in data["events"]:
		if not raw is Dictionary or not staged._valid_event(raw):
			return false
		var number: int = _numbered_id(raw["id"], "event_")
		if number < 1 or staged._event_indices.has(raw["id"]):
			return false
		largest_event = maxi(largest_event, number)
		staged._append_event(raw.duplicate(true))
	if int(data["next_event_id"]) <= largest_event:
		return false
	var restored: bool = staged._restore_legacy_knowledge(data.knowledge) if version == LEGACY_VERSION else staged._restore_knowledge(data.knowledge)
	if not restored:
		return false
	if not staged._restore_relationships(data["relationships"]):
		return false
	var largest_request: int = 0
	var request_ids: Dictionary = {}
	for cache_key: String in data["requests"]:
		var request: Variant = data["requests"][cache_key]
		if not request is Dictionary or not staged._valid_request(cache_key, request):
			return false
		var number: int = _numbered_id(request["id"], "request_")
		if number < 1 or request_ids.has(request["id"]):
			return false
		largest_request = maxi(largest_request, number)
		request_ids[request["id"]] = true
		staged.requests[cache_key] = request.duplicate(true)
	if int(data["next_request_id"]) <= largest_request:
		return false
	events = staged.events
	relationships = staged.relationships
	requests = staged.requests
	_actors = staged._actors
	_event_indices = staged._event_indices
	_scopes = staged._scopes
	_next_event_id = int(data["next_event_id"])
	_next_request_id = int(data["next_request_id"])
	_outcome_effects = staged._outcome_effects
	return true


func _public_details(details: Dictionary) -> Dictionary:
	var visible: Dictionary = {}
	for field: String in SURFACE_FIELDS:
		if details.has(field):
			visible[field] = _redacted_surface(details[field])
	visible.merge(details.get("public", {}).duplicate(true), true)
	return visible


func _participant_details(details: Dictionary, public_view: Dictionary) -> Dictionary:
	var extra: Dictionary = details.get("participants", {})
	if extra.is_empty():
		return public_view
	var visible: Dictionary = public_view.duplicate()
	visible.merge(extra.duplicate(true), true)
	return visible


static func _observation(event: Dictionary, source: String, visible: Dictionary, direct: bool) -> Dictionary:
	return {
		"id": event["id"], "kind": event["kind"], "actor": event["actor"],
		"target": event["target"], "details": visible, "tick": event["tick"],
		"source": source, "direct": direct,
	}


static func _participant(event: Dictionary, observer: String) -> bool:
	return event.actor == observer or event.target == observer


static func _freeze_details(value: Variant) -> void:
	if value is Dictionary and not value.is_read_only():
		for entry: Variant in value.values():
			_freeze_details(entry)
		value.make_read_only()
	elif value is Array and not value.is_read_only():
		for entry: Variant in value:
			_freeze_details(entry)
		value.make_read_only()


func _redacted_surface(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: String in value:
			if (
				key in ["reason", "motive", "motivation", "private", "secret", "internal"]
				or key.begins_with("secret_") or key.begins_with("private_")
				or key.begins_with("internal_")
			):
				continue
			result[key] = _redacted_surface(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry: Variant in value:
			result.append(_redacted_surface(entry))
		return result
	return value


func _normalized_policy(policy: Dictionary) -> Dictionary:
	if not policy.get("weights", {}) is Dictionary:
		return {}
	var result: Dictionary = {
		"bias": policy.get("bias", 0.0),
		"accept_threshold": policy.get("accept_threshold", 0.0),
		"uncertainty_band": policy.get("uncertainty_band", 0.0),
		"context_step": policy.get("context_step", 0.05), "weights": {},
	}
	for key: String in ["bias", "accept_threshold", "uncertainty_band", "context_step"]:
		if not _finite_number(result[key]):
			return {}
		result[key] = float(result[key])
	if result["uncertainty_band"] < 0.0 or result["context_step"] <= 0.0 or result["context_step"] > 1.0:
		return {}
	for factor: String in FACTOR_DEFAULTS:
		var weight: Variant = policy.get("weights", {}).get(factor, 0.0)
		if not _finite_number(weight):
			return {}
		result["weights"][factor] = float(weight)
	return result


func _validated_effects(overrides: Dictionary) -> Dictionary:
	var result: Dictionary = OUTCOME_EFFECTS.duplicate(true)
	for outcome: Variant in overrides:
		if not outcome is String or not OUTCOME_EFFECTS.has(outcome):
			return {}
		var effect: Variant = overrides[outcome]
		if not effect is Array or effect.size() != 2:
			return {}
		for change: Variant in effect:
			if not _finite_number(change) or absf(float(change)) > 1.0:
				return {}
		result[outcome] = [float(effect[0]), float(effect[1])]
	return result


func _normalized_context(context: Dictionary, step: float) -> Dictionary:
	var result: Dictionary = {}
	for factor: String in FACTOR_DEFAULTS:
		var value: Variant = context.get(factor, FACTOR_DEFAULTS[factor])
		if not _finite_number(value):
			return {}
		var minimum: float = -1.0 if factor == "affinity" else 0.0
		result[factor] = clampf(snappedf(clampf(float(value), minimum, 1.0), step), minimum, 1.0)
	var terms: Variant = context.get("terms", {})
	if not _serializable(terms):
		return {}
	result["terms"] = terms.duplicate(true) if terms is Dictionary or terms is Array else terms
	return result


func _score(context: Dictionary, policy: Dictionary) -> float:
	var score: float = policy["bias"]
	for factor: String in FACTOR_DEFAULTS:
		score += float(context[factor]) * float(policy["weights"][factor])
	return score


func _reasons(context: Dictionary, policy: Dictionary, accepted: bool) -> Array[String]:
	var candidates: Array[Dictionary] = []
	for factor: String in FACTOR_DEFAULTS:
		var contribution: float = float(context[factor]) * float(policy["weights"][factor])
		if (accepted and contribution > 0.0) or (not accepted and contribution < 0.0):
			candidates.append({"factor": factor, "impact": absf(contribution)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(a["impact"], b["impact"]):
			return a["factor"] < b["factor"]
		return a["impact"] > b["impact"]
	)
	var result: Array[String] = []
	for candidate: Dictionary in candidates:
		if result.size() == 3:
			break
		result.append(candidate["factor"])
	if result.is_empty():
		result.append("willing" if accepted else "unwilling")
	return result


func _request_key(
	requester: String, responder: String, task: String, context: Dictionary, policy: Dictionary
) -> String:
	return _canonical({
		"requester": requester, "responder": responder, "task": task,
		"context": context, "policy": policy,
	})


func _invalid_request(requester: String, responder: String, task: String, reason: String) -> Dictionary:
	return {
		"id": "", "status": "refused", "reason": reason,
		"requester": requester, "responder": responder, "task": task,
	}


func _valid_details(details: Dictionary) -> bool:
	if not _serializable(details):
		return false
	for envelope: String in ["public", "participants", "private"]:
		if details.has(envelope) and not details[envelope] is Dictionary:
			return false
	return true


func _valid_event(event: Dictionary) -> bool:
	if not _has_keys(event, ["id", "kind", "actor", "target", "details", "witnesses", "tick"]):
		return false
	if (
		not event["id"] is String or not event["kind"] is String or event["kind"].is_empty()
		or not event["actor"] is String or not _actors.has(event["actor"])
		or not event["target"] is String or not event["details"] is Dictionary
		or not event["witnesses"] is Array or not _integer_at_least(event["tick"], 0)
	):
		return false
	if not event["target"].is_empty() and not _actors.has(event["target"]):
		return false
	if not _valid_details(event["details"]):
		return false
	var unique: Dictionary = {}
	for witness: Variant in event["witnesses"]:
		if not witness is String or not _actors.has(witness) or unique.has(witness):
			return false
		unique[witness] = true
	return true


func _restore_knowledge(saved: Dictionary) -> bool:
	for index: int in events.size():
		_index_direct_observations(index)
	for actor: Variant in saved:
		var row: Variant = saved[actor]
		if not actor is String or not _actors.has(actor) or not row is Dictionary or not _has_keys(row, ["heard", "order"]) or not row.heard is Dictionary or not row.order is Array:
			return false
		var observer: Observer = _actors[actor]
		for event_id: Variant in row.heard:
			var source: Variant = row.heard[event_id]
			if not event_id is String or not source is String or source == actor or not _actors.has(source):
				return false
			var index: int = _event_indices.get(event_id, -1)
			if index < 0 or observer.saw(index):
				return false
			observer.heard[index] = [source, -1] # Scope is derived from the verified source chain.
		if row.order.size() != observer.direct.size() + observer.heard.size():
			return false
		var included: Dictionary[int, bool] = {}
		var order := PackedInt32Array()
		for raw: Variant in row.order:
			if not _integer_at_least(raw, 0) or raw >= events.size():
				return false
			var index: int = int(raw)
			if included.has(index) or not observer.knows(index):
				return false
			included[index] = true
			order.append(index)
		observer.order = order
	for actor: String in saved:
		for index: int in _actors[actor].heard:
			if not _restore_heard_scope(actor, index):
				return false
	return true


func _restore_heard_scope(actor: String, index: int) -> bool:
	var chain: Array[String] = []
	var visited: Dictionary[String, bool] = {}
	var cursor: String = actor
	var scope: int = -1
	while scope < 0:
		if visited.has(cursor):
			return false
		visited[cursor] = true
		var observer: Observer = _actors[cursor]
		if observer.saw(index):
			scope = int(_participant(events[index], cursor))
			break
		if not observer.heard.has(index):
			return false
		var source: Array = observer.heard[index]
		if int(source[1]) >= 0:
			scope = int(source[1])
			break
		chain.append(cursor)
		cursor = str(source[0])
	for observer_id: String in chain:
		_actors[observer_id].heard[index][1] = scope
	return true


func _restore_legacy_knowledge(saved: Dictionary) -> bool:
	if saved.size() != _actors.size():
		return false
	for observer: String in saved:
		if not _actors.has(observer) or not saved[observer] is Dictionary:
			return false
		for event_id: String in saved[observer]:
			var known: Variant = saved[observer][event_id]
			var index: int = _event_indices.get(event_id, -1)
			if not known is Dictionary or index < 0:
				return false
			if not _has_keys(known, ["id", "kind", "actor", "target", "details", "tick", "source", "direct"]):
				return false
			var event: Dictionary = events[index]
			if (
				known["id"] != event_id or known["kind"] != event["kind"]
				or known["actor"] != event["actor"] or known["target"] != event["target"]
				or known["tick"] != event["tick"] or not known["details"] is Dictionary
				or not known["source"] is String or not _actors.has(known["source"])
				or not known["direct"] is bool
			):
				return false
			if known["direct"]:
				if known["source"] != observer or not _is_audience(event, observer):
					return false
				if _canonical(known.details) != _canonical(_view(index, _participant(event, observer))):
					return false
			_actors[observer].order.append(index)
	for observer: String in saved:
		for event_id: String in saved[observer]:
			var first: Dictionary = saved[observer][event_id]
			if first.direct:
				continue
			var visited: Dictionary = {}
			var cursor: String = observer
			while true:
				if visited.has(cursor) or not saved[cursor].has(event_id):
					return false
				visited[cursor] = true
				var entry: Dictionary = saved[cursor][event_id]
				if entry["direct"]:
					break
				var source: String = entry["source"]
				if not saved[source].has(event_id):
					return false
				if _canonical(entry.details) != _canonical(saved[source][event_id].details):
					return false
				cursor = source
			var index: int = _event_indices[event_id]
			_actors[observer].heard[index] = [first.source, _participant(events[index], cursor)]
	# Direct membership is rebuilt in event order from actual audiences only.
	for index: int in events.size():
		var event: Dictionary = events[index]
		if not _restore_direct(saved, event.actor, event.id, index):
			return false
		if not event.target.is_empty() and event.target != event.actor and not _restore_direct(saved, event.target, event.id, index):
			return false
		for witness: String in event.witnesses:
			if witness != event.actor and witness != event.target and not _restore_direct(saved, witness, event.id, index):
				return false
	return true


func _restore_direct(saved: Dictionary, observer: String, id: String, index: int) -> bool:
	if not bool(saved[observer].get(id, {}).get("direct", false)):
		return false
	_actors[observer].direct.append(index)
	return true


func _restore_relationships(saved: Dictionary) -> bool:
	if saved.size() != _actors.size():
		return false
	for observer: String in saved:
		if not _actors.has(observer) or not saved[observer] is Dictionary:
			return false
		for other: String in saved[observer]:
			var memory: Variant = saved[observer][other]
			if not _actors.has(other) or not memory is Dictionary:
				return false
			if not _has_keys(memory, ["reliability", "affinity", "history"]):
				return false
			if not _finite_number(memory["reliability"]) or not _finite_number(memory["affinity"]):
				return false
			if not memory["history"] is Array:
				return false
			for entry: Variant in memory["history"]:
				if not entry is Dictionary or not _has_keys(entry, ["event_id", "outcome", "source"]):
					return false
				if not entry["event_id"] is String or not entry["outcome"] is String:
					return false
				if not remember_outcome(observer, other, entry["outcome"], entry["event_id"]):
					return false
			var rebuilt: Dictionary = relation(observer, other)
			if not is_equal_approx(float(memory["reliability"]), rebuilt["reliability"]):
				return false
			if not is_equal_approx(float(memory["affinity"]), rebuilt["affinity"]):
				return false
			if _canonical(memory["history"]) != _canonical(rebuilt["history"]):
				return false
	return true


func _valid_request(cache_key: String, request: Dictionary) -> bool:
	if not _has_keys(request, [
		"id", "requester", "responder", "task", "status", "reason", "reasons", "tick",
		"context", "policy", "score", "chance", "roll", "uncertain",
	]):
		return false
	if (
		not request["id"] is String or not request["requester"] is String
		or not request["responder"] is String or not request["task"] is String
		or request["task"].is_empty() or not _actors.has(request["requester"])
		or not _actors.has(request["responder"]) or request["requester"] == request["responder"]
		or not request["context"] is Dictionary or not request["policy"] is Dictionary
		or not _integer_at_least(request["tick"], 0) or not request["uncertain"] is bool
	):
		return false
	for key: String in ["score", "chance", "roll"]:
		if not _finite_number(request[key]):
			return false
	var rules: Dictionary = _normalized_policy(request["policy"])
	if rules.is_empty() or _canonical(rules) != _canonical(request["policy"]):
		return false
	var factors: Dictionary = _normalized_context(request["context"], rules["context_step"])
	if factors.is_empty() or _canonical(factors) != _canonical(request["context"]):
		return false
	if cache_key != _request_key(request["requester"], request["responder"], request["task"], factors, rules):
		return false
	var score: float = _score(factors, rules)
	var margin: float = score - float(rules["accept_threshold"])
	var band: float = rules["uncertainty_band"]
	var uncertain: bool = band > 0.0 and absf(margin) < band
	var chance: float = clampf(0.5 + margin / (2.0 * band), 0.0, 1.0) if uncertain else (
		1.0 if margin >= 0.0 else 0.0
	)
	if not is_equal_approx(request["score"], score) or not is_equal_approx(request["chance"], chance):
		return false
	if request["uncertain"] != uncertain:
		return false
	var roll: float = request["roll"]
	if (uncertain and (roll < 0.0 or roll > 1.0)) or (not uncertain and roll != -1.0):
		return false
	var accepted: bool = roll < chance if uncertain else margin >= 0.0
	var expected_reasons: Array[String] = _reasons(factors, rules, accepted)
	return (
		request["status"] == ("accepted" if accepted else "refused")
		and request["reason"] == expected_reasons[0]
		and _canonical(request["reasons"]) == _canonical(expected_reasons)
	)


func _is_audience(event: Dictionary, observer: String) -> bool:
	return event["actor"] == observer or event["target"] == observer or event["witnesses"].has(observer)


func _has_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key: String in keys:
		if not value.has(key):
			return false
	return true


func _numbered_id(value: String, prefix: String) -> int:
	if not value.begins_with(prefix):
		return -1
	var suffix: String = value.trim_prefix(prefix)
	if not suffix.is_valid_int() or str(int(suffix)) != suffix:
		return -1
	return int(suffix)


func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _integer_at_least(value: Variant, minimum: int) -> bool:
	return _finite_number(value) and float(value) == floorf(float(value)) and float(value) >= minimum


func _serializable(value: Variant, depth: int = 0) -> bool:
	if depth > 32:
		return false
	if value == null or value is String or value is bool:
		return true
	if value is int or value is float:
		return is_finite(float(value))
	if value is Array:
		for entry: Variant in value:
			if not _serializable(entry, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _serializable(value[key], depth + 1):
				return false
		return true
	return false


func _canonical(value: Variant) -> String:
	# JSON parses all numbers as floats. Integral terms must keep their request
	# identity after save/load (reward=1 and reward=1.0 are the same offer).
	if value is float and value == floorf(value) and absf(value) < 9007199254740992.0:
		return str(int(value))
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var parts: PackedStringArray = []
		for key: String in keys:
			parts.append(JSON.stringify(key) + ":" + _canonical(value[key]))
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var parts: PackedStringArray = []
		for entry: Variant in value:
			parts.append(_canonical(entry))
		return "[" + ",".join(parts) + "]"
	return JSON.stringify(value)
