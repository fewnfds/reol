class_name SimSocialMemory
extends RefCounted
## Objective events, attributed knowledge, directed memories and bounded requests.
## Event details are private by default. Surface fields below are observable;
## `public` explicitly addresses everyone present, `participants` only the two
## parties. `private`, reason and unlisted fields stay in the objective log.
## Learning copies the informant's snapshot, never the objective event.

const VERSION: int = 1
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
var knowledge: Dictionary = {}
var relationships: Dictionary = {}
var requests: Dictionary = {}

var _actors: Dictionary = {}
var _event_by_id: Dictionary = {}
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
	_actors[actor_id] = true
	knowledge[actor_id] = {}
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
	var audience: Array[String] = [actor]
	if not target.is_empty() and not audience.has(target):
		audience.append(target)
	var observed_by: Array[String] = []
	for witness: String in witnesses:
		if not _actors.has(witness):
			return ""
		if not observed_by.has(witness):
			observed_by.append(witness)
		if not audience.has(witness):
			audience.append(witness)
	var event_id: String = "event_%d" % _next_event_id
	_next_event_id += 1
	var event: Dictionary = {
		"id": event_id, "kind": kind, "actor": actor, "target": target,
		"details": details.duplicate(true), "witnesses": observed_by, "tick": tick,
	}
	events.append(event)
	_event_by_id[event_id] = event
	for observer: String in audience:
		knowledge[observer][event_id] = _observed_event(event, observer)
	return event_id


func learn(actor: String, event_id: String, source: String) -> bool:
	if not _actors.has(actor) or not _actors.has(source) or actor == source:
		return false
	if knowledge[actor].has(event_id) or not knowledge[source].has(event_id):
		return false
	var learned: Dictionary = knowledge[source][event_id].duplicate(true)
	learned["source"] = source
	learned["direct"] = false
	knowledge[actor][event_id] = learned
	return true


func known_events(actor: String) -> Array[Dictionary]:
	var visible: Array[Dictionary] = []
	if not knowledge.has(actor):
		return visible
	for event: Dictionary in events:
		if knowledge[actor].has(event["id"]):
			visible.append(knowledge[actor][event["id"]].duplicate(true))
	return visible


func remember_outcome(
	observer: String, other: String, outcome: String, event_id: String
) -> bool:
	if not _actors.has(observer) or not _actors.has(other) or observer == other:
		return false
	if not knowledge[observer].has(event_id) or not OUTCOME_EFFECTS.has(outcome):
		return false
	var known: Dictionary = knowledge[observer][event_id]
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
		"knowledge": knowledge.duplicate(true), "relationships": relationships.duplicate(true),
		"requests": requests.duplicate(true), "next_event_id": _next_event_id,
		"next_request_id": _next_request_id, "outcome_effects": _outcome_effects.duplicate(true),
	}


func restore(data: Dictionary) -> bool:
	# All validation and reconstruction happens off to the side.
	if not _serializable(data) or data.get("version") != VERSION:
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
		if number < 1 or staged._event_by_id.has(raw["id"]):
			return false
		largest_event = maxi(largest_event, number)
		var event: Dictionary = raw.duplicate(true)
		staged.events.append(event)
		staged._event_by_id[event["id"]] = event
	if int(data["next_event_id"]) <= largest_event:
		return false
	if not staged._restore_knowledge(data["knowledge"]):
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
	knowledge = staged.knowledge
	relationships = staged.relationships
	requests = staged.requests
	_actors = staged._actors
	_event_by_id = staged._event_by_id
	_next_event_id = int(data["next_event_id"])
	_next_request_id = int(data["next_request_id"])
	_outcome_effects = staged._outcome_effects
	return true


func _observed_event(event: Dictionary, observer: String) -> Dictionary:
	var details: Dictionary = event["details"]
	var visible: Dictionary = {}
	for field: String in SURFACE_FIELDS:
		if details.has(field):
			visible[field] = _redacted_surface(details[field])
	visible.merge(details.get("public", {}).duplicate(true), true)
	if observer == event["actor"] or observer == event["target"]:
		visible.merge(details.get("participants", {}).duplicate(true), true)
	return {
		"id": event["id"], "kind": event["kind"], "actor": event["actor"],
		"target": event["target"], "details": visible, "tick": event["tick"],
		"source": observer, "direct": true,
	}


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
	if saved.size() != _actors.size():
		return false
	for observer: String in saved:
		if not _actors.has(observer) or not saved[observer] is Dictionary:
			return false
		for event_id: String in saved[observer]:
			var known: Variant = saved[observer][event_id]
			if not known is Dictionary or not _event_by_id.has(event_id):
				return false
			if not _has_keys(known, ["id", "kind", "actor", "target", "details", "tick", "source", "direct"]):
				return false
			var event: Dictionary = _event_by_id[event_id]
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
				if _canonical(known) != _canonical(_observed_event(event, observer)):
					return false
	for observer: String in saved:
		for event_id: String in saved[observer]:
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
				var expected: Dictionary = saved[source][event_id].duplicate(true)
				expected["source"] = source
				expected["direct"] = false
				if _canonical(entry) != _canonical(expected):
					return false
				cursor = source
	for event: Dictionary in events:
		for observer: String in _actors:
			if _is_audience(event, observer):
				if not saved[observer].has(event["id"]) or not saved[observer][event["id"]]["direct"]:
					return false
	knowledge = saved.duplicate(true)
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
