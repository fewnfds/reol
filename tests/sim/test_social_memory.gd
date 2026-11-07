extends RefCounted
## Focused evidence, request-cache and snapshot tests. The main runner supplies
## assertion helpers so a failed check is reported without aborting the suite.

const Memory = preload("res://scripts/sim/social_memory.gd")


func run(runner: Object) -> void:
	_test_observation_and_sources(runner)
	_test_private_explanations(runner)
	_test_evidence_and_direction(runner)
	_test_reason_does_not_change_memory(runner)
	_test_cooperation_and_limits(runner)
	_test_cached_requests(runner)
	_test_snapshot_roundtrip(runner)
	_test_corrupt_snapshots_are_atomic(runner)
	_test_policy_and_invalid_input(runner)


func _memory() -> Memory:
	var memory := Memory.new()
	for actor_id: String in ["player", "a", "b", "c", "d"]:
		memory.register_actor(actor_id)
	return memory


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 781
	return rng


func _policy() -> Dictionary:
	return {
		"bias": -0.15, "accept_threshold": 0.0, "uncertainty_band": 0.1,
		"context_step": 0.05,
		"weights": {
			"energy": 0.3, "busy": -0.6, "distance": -0.1, "risk": -0.8,
			"duty": 0.6, "offer": 0.15, "benevolence": 0.3,
			"reliability": 0.1, "affinity": 0.1,
		},
	}


func _uncertain_policy() -> Dictionary:
	return {
		"bias": 0.0, "accept_threshold": 0.0,
		"uncertainty_band": 1.0, "weights": {},
	}


func _test_observation_and_sources(runner: Object) -> void:
	var memory := _memory()
	var witnesses: Array[String] = ["b", "b"]
	var event_id: String = memory.record("delivered", "a", "player", {
		"resource": "rice", "quantity": 2,
		"reason": "I secretly need political support", "secret_reason": "private ambition",
		"private": {"motive": "replace the steward"},
		"terms": {"payment": 2, "secret_reason": "hidden"},
	}, witnesses, 5)
	runner.assert_true(not event_id.is_empty(), "observed event recorded")
	runner.assert_eq(memory.known_events("player").size(), 1, "target knows the event")
	runner.assert_eq(memory.known_events("a").size(), 1, "actor knows the event")
	runner.assert_eq(memory.known_events("b").size(), 1, "witness knows the event once")
	runner.assert_eq(memory.known_events("c").size(), 0, "uninvolved actor is not omniscient")
	var observed: Dictionary = memory.known_events("b")[0]
	runner.assert_eq(observed["details"]["quantity"], 2, "surface quantities are visible")
	runner.assert_true(not observed["details"].has("reason"), "objective reason is not observable")
	runner.assert_true(not observed["details"].has("secret_reason"), "unlisted motive stays private")
	runner.assert_true(not observed["details"].has("private"), "private envelope stays private")
	runner.assert_true(not observed["details"]["terms"].has("secret_reason"), "nested motive is redacted")
	runner.assert_true(not memory.learn("c", event_id, "d"), "uninformed source cannot transmit")
	runner.assert_true(not memory.learn("c", event_id, "missing"), "unknown source cannot transmit")
	runner.assert_true(not memory.learn("c", "event_999", "b"), "nonexistent event cannot transmit")
	runner.assert_true(memory.learn("c", event_id, "b"), "informed source can transmit")
	runner.assert_eq(memory.known_events("c")[0]["source"], "b", "knowledge records its source")
	runner.assert_true(not memory.known_events("c")[0]["direct"], "hearsay is distinguished from observation")
	runner.assert_true(not memory.learn("c", event_id, "a"), "same information is not learned twice")
	runner.assert_true(memory.learn("d", event_id, "c"), "a second source hop is possible")
	observed["details"]["quantity"] = 900
	runner.assert_eq(memory.known_events("b")[0]["details"]["quantity"], 2, "visible snapshots are detached")
	var snapshot: Dictionary = memory.to_dict()
	runner.assert_eq(snapshot["events"][0]["details"]["reason"], "I secretly need political support", "objective log retains private cause")


func _test_private_explanations(runner: Object) -> void:
	var memory := _memory()
	var witnesses: Array[String] = ["b"]
	var event_id: String = memory.record("request_answered", "a", "player", {
		"status": "refused", "reason": "unspoken resentment",
		"participants": {"reason": "I must finish my shift"},
		"public": {"gesture": "bows politely"},
	}, witnesses, 8)
	runner.assert_eq(memory.known_events("player")[0]["details"]["reason"], "I must finish my shift", "parties receive the stated explanation")
	runner.assert_true(not memory.known_events("b")[0]["details"].has("reason"), "bystander does not hear private explanation")
	runner.assert_eq(memory.known_events("b")[0]["details"]["gesture"], "bows politely", "explicit public observation is shared")
	runner.assert_true(memory.learn("c", event_id, "b"), "bystander can report surface event")
	runner.assert_true(not memory.known_events("c")[0]["details"].has("reason"), "hearsay does not fetch hidden explanation")
	runner.assert_true(memory.learn("d", event_id, "player"), "participant can retell their conversation")
	runner.assert_eq(memory.known_events("d")[0]["details"]["reason"], "I must finish my shift", "retelling uses source's actual knowledge")


func _test_evidence_and_direction(runner: Object) -> void:
	var memory := _memory()
	var witnesses: Array[String] = ["b"]
	var event_id: String = memory.record("helped", "a", "player", {"quantity": 1}, witnesses, 1)
	runner.assert_true(not memory.remember_outcome("c", "a", "helped", event_id), "unknown evidence cannot change a relationship")
	runner.assert_true(not memory.remember_outcome("b", "d", "helped", event_id), "unrelated person cannot be credited")
	runner.assert_true(memory.remember_outcome("b", "a", "helped", event_id), "observed help changes local memory")
	runner.assert_true(memory.relation("b", "a")["reliability"] > 0.5, "observer considers helper more reliable")
	runner.assert_eq(memory.relation("a", "b")["reliability"], 0.5, "relationship is directed")
	var after: Dictionary = memory.relation("b", "a")
	runner.assert_true(not memory.remember_outcome("b", "a", "helped", event_id), "repeated evidence gives no repeated gain")
	runner.assert_true(not memory.remember_outcome("b", "a", "betrayed", event_id), "changing interpretation cannot reuse the same evidence")
	runner.assert_eq(memory.relation("b", "a"), after, "duplicate evidence leaves memory unchanged")
	after["reliability"] = 0.0
	after["history"].clear()
	runner.assert_true(memory.relation("b", "a")["reliability"] > 0.5, "relation returns a detached view")
	var refusal: String = memory.record("refused", "a", "player", {"status": "refused"}, witnesses, 2)
	var reliability_before: float = memory.relation("b", "a")["reliability"]
	runner.assert_true(memory.remember_outcome("b", "a", "refused", refusal), "refusal can be remembered")
	runner.assert_eq(memory.relation("b", "a")["reliability"], reliability_before, "refusal alone does not imply broken promises")


func _test_reason_does_not_change_memory(runner: Object) -> void:
	var generous := _memory()
	var scheming := _memory()
	var witnesses: Array[String] = ["b"]
	var good_id: String = generous.record("delivered", "a", "player", {
		"resource": "rice", "quantity": 1, "reason": "compassion",
	}, witnesses, 2)
	var bad_id: String = scheming.record("delivered", "a", "player", {
		"resource": "rice", "quantity": 1, "reason": "make someone dependent",
	}, witnesses, 2)
	generous.remember_outcome("b", "a", "completed", good_id)
	scheming.remember_outcome("b", "a", "completed", bad_id)
	runner.assert_eq(generous.known_events("b"), scheming.known_events("b"), "same observations hide different motives")
	runner.assert_eq(generous.relation("b", "a"), scheming.relation("b", "a"), "relationship projection never reads hidden reason")


func _test_cooperation_and_limits(runner: Object) -> void:
	var memory := _memory()
	var rng := _rng()
	var initial_rng: int = rng.state
	var duty: Dictionary = memory.evaluate_request("player", "a", "bring_rice", {
		"duty": 1.0, "offer": 0.0, "affinity": 0.0,
	}, _policy(), rng, 1)
	runner.assert_eq(duty["status"], "accepted", "low-cost duty can motivate unpaid help for a stranger")
	runner.assert_eq(rng.state, initial_rng, "clear acceptance uses no dice")
	var kindness: Dictionary = memory.evaluate_request("player", "b", "bring_rice", {
		"benevolence": 1.0, "offer": 0.0, "affinity": 0.0,
	}, _policy(), rng, 1)
	runner.assert_eq(kindness["status"], "accepted", "benevolence can motivate help without debt or payment")
	var exhausted: Dictionary = memory.evaluate_request("player", "c", "bring_rice", {
		"energy": 0.1, "busy": 1.0, "risk": 1.0,
	}, _policy(), rng, 1)
	runner.assert_eq(exhausted["status"], "refused", "fatigue, workload and risk can justify refusal")
	runner.assert_eq(exhausted["reason"], "risk", "request reports strongest known opposing factor")
	runner.assert_eq(rng.state, initial_rng, "clear refusal uses no dice")
	var unknown_secret: Dictionary = memory.evaluate_request("player", "a", "bring_rice", {
		"duty": 1.0, "secret_reason": "hates the old leader", "objective_allegiance": 1.0,
	}, _policy(), rng, 2)
	runner.assert_eq(unknown_secret["id"], duty["id"], "unknown motives do not affect decisions or request identity")


func _test_cached_requests(runner: Object) -> void:
	var memory := _memory()
	var rng := _rng()
	var context: Dictionary = {"risk": 0.2, "terms": {"reward": 1, "resource": "rice"}}
	var initial_rng: int = rng.state
	var first: Dictionary = memory.evaluate_request("player", "a", "fetch", context, _uncertain_policy(), rng, 1)
	runner.assert_true(first["uncertain"], "a genuinely close decision uses bounded randomness")
	runner.assert_true(rng.state != initial_rng, "first uncertain request consumes randomness")
	var after_first: int = rng.state
	var repeat_context: Dictionary = {
		"request_id": "new_button_click", "tick": 1000, "risk": 0.201,
		"terms": {"resource": "rice", "reward": 1},
	}
	var repeated: Dictionary = memory.evaluate_request("player", "a", "fetch", repeat_context, _uncertain_policy(), rng, 1000)
	runner.assert_eq(repeated, first, "same semantic request reuses its answer despite new tick and key order")
	runner.assert_eq(rng.state, after_first, "repeated pressure never rerolls")
	first["context"]["terms"]["reward"] = 999
	var unaffected: Dictionary = memory.evaluate_request("player", "a", "fetch", context, _uncertain_policy(), rng, 1001)
	runner.assert_eq(unaffected["context"]["terms"]["reward"], 1, "caller cannot mutate cached request through returned value")
	var changed_context: Dictionary = context.duplicate(true)
	changed_context["risk"] = 0.8
	var changed: Dictionary = memory.evaluate_request("player", "a", "fetch", changed_context, _uncertain_policy(), rng, 1002)
	runner.assert_true(changed["id"] != repeated["id"], "substantial situation change permits reevaluation")
	var new_terms: Dictionary = context.duplicate(true)
	new_terms["terms"]["reward"] = 2
	var renegotiated: Dictionary = memory.evaluate_request("player", "a", "fetch", new_terms, _uncertain_policy(), rng, 1003)
	runner.assert_true(renegotiated["id"] != repeated["id"], "different substantive terms make a new request")


func _test_snapshot_roundtrip(runner: Object) -> void:
	var memory := _memory()
	memory.configure({"outcome_effects": {"helped": [0.02, 0.03]}})
	var witnesses: Array[String] = ["b"]
	var event_id: String = memory.record("helped", "a", "player", {"resource": "rice"}, witnesses, 3)
	memory.learn("c", event_id, "b")
	memory.learn("d", event_id, "c")
	memory.remember_outcome("c", "a", "helped", event_id)
	var rng := _rng()
	var context: Dictionary = {"terms": {"reward": 1, "resource": "rice"}}
	var first: Dictionary = memory.evaluate_request("player", "a", "fetch", context, _uncertain_policy(), rng, 4)
	var saved: Dictionary = memory.to_dict()
	var encoded: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var restored := Memory.new()
	runner.assert_true(restored.restore(encoded), "snapshot survives a JSON roundtrip")
	# JSON normalizes integer Variants to floats; compare the serialized meaning.
	var restored_json: Dictionary = JSON.parse_string(JSON.stringify(restored.to_dict(), "", true, true))
	runner.assert_eq(restored_json, encoded, "all knowledge, policy, histories, counters and requests survive")
	runner.assert_eq(restored.known_events("d")[0]["source"], "c", "multi-hop source remains attributed after restore")
	runner.assert_true(not restored.remember_outcome("c", "a", "helped", event_id), "restored evidence remains deduplicated")
	var before_repeat: int = rng.state
	var cached: Dictionary = restored.evaluate_request("player", "a", "fetch", context, _uncertain_policy(), rng, 100)
	runner.assert_eq(cached["id"], first["id"], "request cache persists across reload")
	runner.assert_eq(rng.state, before_repeat, "loading does not grant another roll")
	var next_event: String = restored.record("helped", "a", "player", {}, witnesses, 101)
	runner.assert_eq(next_event, "event_2", "event ID counter continues after reload")
	var next_request: Dictionary = restored.evaluate_request("player", "a", "different_task", {}, _uncertain_policy(), rng, 102)
	runner.assert_eq(next_request["id"], "request_2", "request ID counter continues after reload")
	saved["knowledge"]["b"][event_id]["details"]["resource"] = "stone"
	runner.assert_eq(memory.known_events("b")[0]["details"]["resource"], "rice", "serialized state is a detached copy")


func _test_corrupt_snapshots_are_atomic(runner: Object) -> void:
	var memory := _memory()
	var witnesses: Array[String] = ["b"]
	var event_id: String = memory.record("helped", "a", "player", {"quantity": 1}, witnesses, 1)
	memory.learn("c", event_id, "b")
	memory.learn("d", event_id, "c")
	memory.remember_outcome("c", "a", "helped", event_id)
	memory.evaluate_request("player", "a", "fetch", {}, _uncertain_policy(), _rng(), 2)
	var baseline: Dictionary = memory.to_dict()
	var orphan: Dictionary = baseline.duplicate(true)
	orphan["knowledge"]["c"]["event_404"] = orphan["knowledge"]["c"][event_id].duplicate(true)
	orphan["knowledge"]["c"]["event_404"]["id"] = "event_404"
	_assert_rejected(runner, memory, orphan, baseline, "orphan knowledge event")
	var source: Dictionary = baseline.duplicate(true)
	source["knowledge"]["b"].clear()
	_assert_rejected(runner, memory, source, baseline, "missing source knowledge")
	var cycle: Dictionary = baseline.duplicate(true)
	cycle["knowledge"]["c"][event_id]["source"] = "d"
	_assert_rejected(runner, memory, cycle, baseline, "circular hearsay with no observation root")
	var leaked: Dictionary = baseline.duplicate(true)
	leaked["knowledge"]["b"][event_id]["details"]["reason"] = "objective secret"
	_assert_rejected(runner, memory, leaked, baseline, "fabricated observer knowledge")
	var history: Dictionary = baseline.duplicate(true)
	history["relationships"]["c"]["a"]["history"][0]["event_id"] = "event_404"
	_assert_rejected(runner, memory, history, baseline, "orphan relationship evidence")
	var forged_source: Dictionary = baseline.duplicate(true)
	forged_source["relationships"]["c"]["a"]["history"][0]["source"] = "a"
	_assert_rejected(runner, memory, forged_source, baseline, "false memory provenance")
	var altered_value: Dictionary = baseline.duplicate(true)
	altered_value["relationships"]["c"]["a"]["reliability"] = 0.99
	_assert_rejected(runner, memory, altered_value, baseline, "relationship score inconsistent with evidence")
	var request: Dictionary = baseline.duplicate(true)
	var cache_key: String = request["requests"].keys()[0]
	request["requests"][cache_key]["responder"] = "missing"
	_assert_rejected(runner, memory, request, baseline, "request with orphan actor")
	var invalid_result: Dictionary = baseline.duplicate(true)
	invalid_result["requests"][cache_key]["chance"] = 0.99
	_assert_rejected(runner, memory, invalid_result, baseline, "request result inconsistent with policy")
	var reused_counter: Dictionary = baseline.duplicate(true)
	reused_counter["next_event_id"] = 1
	_assert_rejected(runner, memory, reused_counter, baseline, "reused event ID counter")
	var wrong_version: Dictionary = baseline.duplicate(true)
	wrong_version["version"] = 999
	_assert_rejected(runner, memory, wrong_version, baseline, "unknown snapshot version")


func _assert_rejected(
	runner: Object, memory: Memory, corrupt: Dictionary, baseline: Dictionary, label: String
) -> void:
	runner.assert_true(not memory.restore(corrupt), "%s is rejected" % label)
	runner.assert_eq(memory.to_dict(), baseline, "%s leaves live state untouched" % label)


func _test_policy_and_invalid_input(runner: Object) -> void:
	var memory := _memory()
	memory.configure({"outcome_effects": {"helped": [0.02, 0.03]}})
	var witnesses: Array[String] = ["b"]
	var event_id: String = memory.record("helped", "a", "player", {}, witnesses, 1)
	memory.remember_outcome("b", "a", "helped", event_id)
	runner.assert_true(is_equal_approx(memory.relation("b", "a")["reliability"], 0.52), "relationship effect is configurable")
	runner.assert_true(is_equal_approx(memory.relation("b", "a")["affinity"], 0.03), "affinity effect is configurable")
	memory.configure({"outcome_effects": {"helped": [0.9, 0.9]}})
	var restored := Memory.new()
	runner.assert_true(restored.restore(memory.to_dict()), "reconfiguring cannot reinterpret existing memories")
	var rng := _rng()
	var before_rng: int = rng.state
	var bad: Dictionary = memory.evaluate_request("player", "missing", "fetch", {}, _policy(), rng, 1)
	runner.assert_eq(bad["reason"], "invalid_request", "unknown responder is rejected safely")
	var invalid_context: Dictionary = memory.evaluate_request("player", "a", "fetch", {"risk": NAN}, _policy(), rng, 1)
	runner.assert_eq(invalid_context["reason"], "invalid_context", "non-finite context is rejected")
	var invalid_policy: Dictionary = memory.evaluate_request("player", "a", "fetch", {}, {"weights": {"risk": INF}}, rng, 1)
	runner.assert_eq(invalid_policy["reason"], "invalid_policy", "non-finite policy is rejected")
	runner.assert_eq(rng.state, before_rng, "invalid inputs consume no randomness")
	var invalid_witnesses: Array[String] = ["missing"]
	var count_before: int = memory.events.size()
	runner.assert_eq(memory.record("helped", "a", "player", {}, invalid_witnesses, 1), "", "unknown event witness is rejected")
	runner.assert_eq(memory.events.size(), count_before, "invalid event is not partially recorded")
