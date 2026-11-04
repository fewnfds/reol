extends RefCounted
## Evidence of shared artifact order, real inventory operations and restore.
## The fixture obtains the ring through its timed original action. Positions
## and willingness are controlled test conditions, not a product replay.

const ExchangeFixtures = preload("res://tests/sim/test_private_exchange.gd")
const RING: String = "stele_drawing_ring"
const BUYER: String = "player"
const CROSS_SELLER: String = "river_shi_tou"
const SAME_SELLER: String = "shi_tou"
var fixtures := ExchangeFixtures.new()


func run(runner: Object) -> void:
	_cancel_then_restart_same_millisecond(runner)
	_cancel_then_original_action_same_millisecond(runner)
	_completion_then_study_same_millisecond(runner)
	_proposal_cannot_follow_its_action(runner)
	_historical_occupations(runner)
	_payment_and_restored_future(runner, CROSS_SELLER)
	_payment_and_restored_future(runner, SAME_SELLER)
	print("SCENARIO private exchange order: same-millisecond release and custody, original wallet payment and restored future")


func _snapshot(world: RegionalSimulation) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(world.to_dict()))


func _candidate(runner: Object, seller: String) -> RegionalSimulation:
	return fixtures._world(runner, seller)


func _reject_unchanged(runner: Object, candidate: RegionalSimulation, bad: Dictionary, reason: String) -> void:
	var stable: String = _snapshot(candidate)
	runner.assert_true(not candidate.restore(bad), "candidate rejects " + reason)
	runner.assert_eq(_snapshot(candidate), stable, "rejected " + reason + " cannot replace the live world")


func _cancel_then_restart_same_millisecond(runner: Object) -> void:
	var world: RegionalSimulation = fixtures._world(runner)
	if world == null:
		return
	var first: String = fixtures._start(runner, world)
	if first.is_empty():
		return
	var moment: int = int(world.elapsed_ms)
	runner.assert_true(world.private_exchange.cancel(BUYER, "player_cancelled"), "buyer cancels the original bargain")
	var release: String = str(world.private_exchange.jobs[first].artifact_release)
	var second: String = fixtures._start(runner, world)
	if second.is_empty():
		return
	var second_action: String = str(world.private_exchange.jobs[second].artifact_action)
	runner.assert_eq(int(world.elapsed_ms), moment, "cancel and new present consent occur at one shared millisecond")
	runner.assert_true(SimArtifacts.Schema._serial_number(release, "release") < SimArtifacts.Schema._action_number(second_action), "the release precedes the second original action")
	var candidate: RegionalSimulation = _candidate(runner, CROSS_SELLER)
	if candidate == null:
		return
	var saved: Dictionary = JSON.parse_string(_snapshot(world))
	runner.assert_true(candidate.restore(saved), "a valid same-millisecond cancel and new agreement restores")
	var bad: Dictionary = saved.duplicate(true)
	var release_number: int = SimArtifacts.Schema._serial_number(release, "release")
	var action_number: int = SimArtifacts.Schema._action_number(second_action)
	bad.private_exchange.jobs[first].artifact_release = "artifact:release:%d" % action_number
	bad.private_exchange.jobs[second].artifact_action = "artifact:action:%d" % release_number
	_reject_unchanged(runner, candidate, bad, "a new bargain ordered before the earlier release")


func _cancel_then_original_action_same_millisecond(runner: Object) -> void:
	var world: RegionalSimulation = fixtures._world(runner)
	if world == null:
		return
	var id: String = fixtures._start(runner, world)
	if id.is_empty():
		return
	runner.assert_true(world.private_exchange.cancel(BUYER, "player_cancelled"), "cancel releases the original ring")
	var release: String = str(world.private_exchange.jobs[id].artifact_release)
	var reply: Dictionary = world.artifacts.begin(CROSS_SELLER, "study", RING)
	runner.assert_true(bool(reply.get("ok", false)), "the seller can study the released ring at that same millisecond")
	if not bool(reply.get("ok", false)):
		return
	var action: String = str(world.artifacts.active[CROSS_SELLER].id)
	runner.assert_true(SimArtifacts.Schema._serial_number(release, "release") < SimArtifacts.Schema._action_number(action), "the original artifact action is later than release")
	var candidate: RegionalSimulation = _candidate(runner, CROSS_SELLER)
	if candidate == null:
		return
	var saved: Dictionary = JSON.parse_string(_snapshot(world))
	runner.assert_true(candidate.restore(saved), "valid release followed by original artifact use restores")
	var bad: Dictionary = saved.duplicate(true)
	bad.private_exchange.jobs[id].artifact_release = "artifact:release:%d" % SimArtifacts.Schema._action_number(action)
	bad.artifacts.active[CROSS_SELLER].id = "artifact:action:%d" % SimArtifacts.Schema._serial_number(release, "release")
	_reject_unchanged(runner, candidate, bad, "artifact use ordered before the release")


func _completion_then_study_same_millisecond(runner: Object) -> void:
	var world: RegionalSimulation = fixtures._world(runner)
	if world == null:
		return
	var id: String = fixtures._start(runner, world)
	if id.is_empty():
		return
	var due: int = int(world.private_exchange.jobs[id].due_ms)
	runner.assert_true(world.advance_to_ms(due), "the original transfer reaches its exact completion boundary")
	if world.private_exchange.jobs[id].status != "completed":
		return
	var event: String = str(world.private_exchange.jobs[id].artifact_event)
	var reply: Dictionary = world.artifacts.begin(BUYER, "study", RING)
	runner.assert_true(bool(reply.get("ok", false)), "buyer can start their own study immediately after the handover")
	if not bool(reply.get("ok", false)):
		return
	var action: String = str(world.artifacts.active[BUYER].id)
	runner.assert_eq(int(world.elapsed_ms), due, "study begins at the handover millisecond")
	runner.assert_true(SimArtifacts.Schema._serial_number(event, "event") < SimArtifacts.Schema._action_number(action), "completed custody precedes the new study")
	var candidate: RegionalSimulation = _candidate(runner, CROSS_SELLER)
	if candidate == null:
		return
	var saved: Dictionary = JSON.parse_string(_snapshot(world))
	runner.assert_true(candidate.restore(saved), "real completion followed by immediate personal study restores")
	var bad: Dictionary = saved.duplicate(true)
	var event_number: int = SimArtifacts.Schema._serial_number(event, "event")
	var action_number: int = SimArtifacts.Schema._action_number(action)
	var forged_event: String = "artifact:event:%d" % action_number
	bad.private_exchange.jobs[id].artifact_event = forged_event
	bad.private_exchange.transfers[str(bad.private_exchange.jobs[id].receipt)].artifact_event = forged_event
	for row: Dictionary in bad.artifacts.events:
		if row.id == event:
			row.id = forged_event
	bad.artifacts.active[BUYER].id = "artifact:action:%d" % event_number
	_reject_unchanged(runner, candidate, bad, "study ordered before the completed transfer event")


func _proposal_cannot_follow_its_action(runner: Object) -> void:
	var world: RegionalSimulation = fixtures._world(runner)
	if world == null:
		return
	var id: String = fixtures._start(runner, world)
	if id.is_empty():
		return
	var candidate: RegionalSimulation = _candidate(runner, CROSS_SELLER)
	if candidate == null:
		return
	var saved: Dictionary = JSON.parse_string(_snapshot(world))
	runner.assert_true(candidate.restore(saved), "a genuine same-millisecond proposal and action restore")
	var bad: Dictionary = saved.duplicate(true)
	var job: Dictionary = bad.private_exchange.jobs[id]
	var proposal: Dictionary = bad.private_exchange.proposals[job.proposal]
	var action_number: int = SimArtifacts.Schema._action_number(str(job.artifact_action))
	var forged_floor: int = action_number + 1
	proposal.artifact_floor = forged_floor
	var requests: Dictionary = bad.services.social.requests
	var original_key: String = ""
	var decision: Dictionary = {}
	for key: String in requests:
		if requests[key].id == proposal.decision:
			original_key = key
			decision = requests[key].duplicate(true)
			break
	runner.assert_true(not original_key.is_empty(), "the original attributed decision exists")
	if original_key.is_empty():
		return
	decision.context.terms.artifact_floor = forged_floor
	requests.erase(original_key)
	var forged_key: String = world.services.social._request_key(str(decision.requester), str(decision.responder), str(decision.task), decision.context, decision.policy)
	requests[forged_key] = decision
	var isolated_social := SimSocialMemory.new()
	runner.assert_true(isolated_social.restore(bad.services.social), "forged decision retains a self-consistent social cache key")
	runner.assert_true(SimArtifacts.Schema.serial_floor_valid(world.artifacts, forged_floor, int(proposal.at_ms)), "same-millisecond floor passes the generic time bounds")
	_reject_unchanged(runner, candidate, bad, "a proposal floor after its own action")


func _historical_occupations(runner: Object) -> void:
	var world: RegionalSimulation = fixtures._world(runner)
	if world == null:
		return
	var id: String = fixtures._start(runner, world)
	if id.is_empty():
		return
	var job: Dictionary = world.private_exchange.jobs[id]
	var start: int = int(job.started_ms)
	runner.assert_true(world.advance_to_ms(start + 2), "exchange continues while checking existing occupation history")
	# These isolated records exercise this domain's cross-check only; they are
	# not complete health/travel snapshots and are removed before serialization.
	world.health.jobs["probe"] = {"patient": BUYER, "doctor": "su_zhi", "status": "completed", "started_ms": start, "finished_ms": start + 1}
	runner.assert_true(not SimPrivateExchange.Schema.cross_valid(world.private_exchange), "a proven historical care interval cannot share either trading body")
	world.health.jobs.probe.finished_ms = start
	world.health.jobs.probe.started_ms = start - 1
	runner.assert_true(SimPrivateExchange.Schema.cross_valid(world.private_exchange), "adjacent care and handover boundaries are allowed")
	world.health.jobs.erase("probe")
	world.field_opportunities.trips["probe"] = {"actor": CROSS_SELLER, "status": "completed", "started_ms": start, "finished_ms": start + 1}
	runner.assert_true(not SimPrivateExchange.Schema.cross_valid(world.private_exchange), "a proven historical field trip cannot share a trading body")
	world.field_opportunities.trips.probe.finished_ms = start
	world.field_opportunities.trips.probe.started_ms = start - 1
	runner.assert_true(SimPrivateExchange.Schema.cross_valid(world.private_exchange), "adjacent field travel and handover are allowed")
	world.field_opportunities.trips.erase("probe")


func _payment_and_restored_future(runner: Object, seller: String) -> void:
	var world: RegionalSimulation = fixtures._world(runner, seller)
	if world == null:
		return
	var id: String = fixtures._start(runner, world, seller)
	if id.is_empty():
		return
	var job: Dictionary = world.private_exchange.jobs[id]
	var deadline: int = int(job.due_ms)
	runner.assert_true(world.advance_to_ms(deadline - 1), "original exchange reaches the last incomplete millisecond")
	var candidate: RegionalSimulation = _candidate(runner, seller)
	if candidate == null:
		return
	var in_progress: Dictionary = JSON.parse_string(_snapshot(world))
	runner.assert_true(candidate.restore(in_progress), "independent candidate restores the original pending payment")
	runner.assert_true(world.advance_to_ms(deadline) and candidate.advance_to_ms(deadline), "original and restored worlds reach the same deadline")
	runner.assert_eq(_snapshot(candidate), _snapshot(world), "restored and original worlds commit the same full future")
	if job.status != "completed":
		return
	var payment: String = str(job.receipt)
	var buyer_region: String = str(job.buyer_region)
	var expected_kind: String = "transfer" if job.buyer_region == job.seller_region else "consume"
	var operation: Dictionary = world.regions[buyer_region].inventory.operations.get(payment, {})
	runner.assert_eq(operation.get("kind"), expected_kind, "real source ledger records the appropriate same/cross-region payment")
	runner.assert_true(world.advance_to_ms(deadline + 1000) and candidate.advance_to_ms(deadline + 1000), "both worlds continue after the payment")
	runner.assert_eq(_snapshot(candidate), _snapshot(world), "payment remains identical after the next shared interval")
	var saved: Dictionary = JSON.parse_string(_snapshot(world))
	# Generic ledger operations belong to their own domains. This check owns
	# only the private_exchange namespace and must not validate all banking.
	var unrelated_id: String = "other_system:operation"
	world.regions[buyer_region].inventory.operations[unrelated_id] = operation.duplicate(true)
	runner.assert_true(SimPrivateExchange.Schema.cross_valid(world.private_exchange), "unrelated inventory operations are outside private exchange ownership")
	world.regions[buyer_region].inventory.operations.erase(unrelated_id)
	for fault: String in ["missing", "wrong_amount", "wrong_source", "wrong_kind", "orphan", "seller_prior_autonomy"]:
		var bad: Dictionary = saved.duplicate(true)
		var ops: Dictionary = bad.regions[buyer_region].inventory.operations
		match fault:
			"missing": ops.erase(payment)
			"wrong_amount": ops[payment].amount += 1
			"wrong_source":
				if expected_kind == "transfer":
					ops[payment].source = "actor:" + seller
				else:
					ops[payment].container = "actor:" + seller
			"wrong_kind": ops[payment].kind = "unknown"
			"orphan": ops["private_exchange:action:999999:payment"] = ops[payment].duplicate(true)
			"seller_prior_autonomy": bad.private_exchange.jobs[id].seller_autonomous = false
		_reject_unchanged(runner, candidate, bad, "%s %s inventory payment" % [expected_kind, fault])
