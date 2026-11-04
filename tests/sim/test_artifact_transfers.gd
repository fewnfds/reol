extends RefCounted
## Exercise the live seam through the original artifact and exchange owners.

const Stones = preload("res://tests/sim/test_artifacts.gd")
const Drawing = preload("res://tests/sim/test_artifact_drawing.gd")
const Exchange = preload("res://tests/sim/test_private_exchange.gd")
const STONE: String = "hearth_stone"
const RING: String = "stele_drawing_ring"
const SWORD: String = "training_sword"
const BUYER: String = "player"
const SELLER: String = "river_shi_tou"


class Observer:
	extends RefCounted
	var _owner: WeakRef
	var allowed: Variant = true
	var mutate_guard: bool = false
	var mutate_notice: bool = false
	var probe_artifact_cancel: bool = false
	var probe_exchange_cancel: bool = false
	var probe_other_begin: bool = false
	var exchange_id: String = ""
	var guards: Array[Dictionary] = []
	var notices: Array[Dictionary] = []
	var guard_states: Array[Dictionary] = []
	var notice_states: Array[Dictionary] = []
	var cancellation_results: Array[bool] = []
	var begin_results: Array[bool] = []

	func _init(world: RegionalSimulation) -> void:
		_owner = weakref(world)

	func preflight(change: Dictionary) -> Variant:
		guards.append(change.duplicate(true))
		guard_states.append(_state(change))
		var world: RegionalSimulation = _owner.get_ref()
		if probe_artifact_cancel:
			cancellation_results.append(world.artifacts.cancel("player"))
		if probe_exchange_cancel:
			cancellation_results.append(world.private_exchange.cancel("player"))
		if probe_other_begin:
			begin_results.append(bool(world.artifacts.begin("chen_shouzhuo", "take", "hearth_stone").ok))
		if mutate_guard:
			change.entity.id = "forged"
			change.from.region = "forged"
			change.to.container = "forged"
		return allowed

	func committed(change: Dictionary) -> void:
		notices.append(change.duplicate(true))
		notice_states.append(_state(change))
		if mutate_notice:
			change.entity.id = "forged"
			change.from.region = "forged"
			change.to.container = "forged"

	func _state(change: Dictionary) -> Dictionary:
		var world: RegionalSimulation = _owner.get_ref()
		var object_id: String = str(change.entity.id)
		var last: Dictionary = world.artifacts.events.back() if not world.artifacts.events.is_empty() else {}
		var result: Dictionary = {"item": world.artifacts.objects.get(object_id, {}).duplicate(true),
			"event_count": world.artifacts.events.size(), "last_action": str(last.get("action", "")),
			"last_kind": str(last.get("kind", "")), "active": world.artifacts.owns_actor("player"),
			"target_in_use": world.artifacts.target_in_use(object_id)}
		if not exchange_id.is_empty():
			var job: Dictionary = world.private_exchange.jobs[exchange_id]
			var buyer_ledger: SimInventory = world.regions[job.buyer_region].inventory
			var seller_ledger: SimInventory = world.regions[job.seller_region].inventory
			result.merge({"status": str(job.status), "receipt": str(job.receipt),
				"receipt_exists": world.private_exchange.transfers.has(str(job.receipt)),
				"reserved": buyer_ledger.reservations.has(str(job.reservation)),
				"buyer_coin": buyer_ledger.quantity("actor:" + str(job.buyer), "coin"),
				"seller_coin": seller_ledger.quantity("actor:" + str(job.seller), "coin"),
				"buyer_locked": world.private_exchange.owns_actor(str(job.buyer)),
				"seller_locked": world.private_exchange.owns_actor(str(job.seller))})
		return result


func run(runner: Object) -> void:
	_stone_moves_and_rejections(runner)
	_draw_and_inflight_restore(runner)
	_exchange(runner, true)
	_exchange(runner, false)
	print("SCENARIO artifact transfers: synchronous guarded original moves, full commit notices, rejection, reentry and in-flight continuation")


func _expected(id: String, from_region: String, from_container: String, to_region: String, to_container: String, at_ms: int, action: String, cause: String) -> Dictionary:
	return {"entity": {"kind": "artifact", "id": id}, "from": {"region": from_region, "container": from_container},
		"to": {"region": to_region, "container": to_container}, "at_ms": at_ms, "action": action, "cause": cause}


func _stone_action(runner: Object, world: RegionalSimulation, verb: String) -> Dictionary:
	var reply: Dictionary = world.artifacts.begin(BUYER, verb, STONE)
	runner.assert_true(bool(reply.ok), "real stone operation starts: " + verb)
	return world.artifacts.active[BUYER].duplicate(true) if bool(reply.ok) else {}


func _stone_moves_and_rejections(runner: Object) -> void:
	var fixture := Stones.new()
	var world: RegionalSimulation = fixture._world(runner)
	if world == null:
		return
	var observer := Observer.new(world)
	observer.mutate_guard = true
	observer.mutate_notice = true
	observer.probe_artifact_cancel = true
	world.artifacts.transfers.set_guard(observer.preflight)
	world.artifacts.transfers.committed.connect(observer.committed)
	var original: Dictionary = world.artifacts.objects[STONE].duplicate(true)
	var initial_events: int = world.artifacts.events.size()
	var take: Dictionary = _stone_action(runner, world, "take")
	if take.is_empty():
		return
	var expected: Dictionary = _expected(STONE, "home", "kitchen", "home", "actor:player", int(take.due_ms), str(take.id), "take")
	runner.assert_true(world.advance_to_ms(int(take.due_ms) - 1), "the last incomplete stone millisecond is reachable")
	runner.assert_true(observer.guards.is_empty() and observer.notices.is_empty(), "neither preflight nor notice runs before the actual move")
	runner.assert_true(world.advance_to_ms(int(take.due_ms)), "the original clock settles the stone take")
	runner.assert_eq(observer.guards, [expected], "take preflight sees the exact canonical source, destination and action")
	runner.assert_eq(observer.notices, [expected], "mutating the guard's copy cannot corrupt the committed change")
	if not observer.guard_states.is_empty():
		var before: Dictionary = observer.guard_states[0]
		runner.assert_eq(before.item, original, "preflight runs while the real stone remains at its source")
		runner.assert_true(bool(before.active) and bool(before.target_in_use), "preflight runs while the original process owns the object")
		runner.assert_eq(int(before.event_count), initial_events, "preflight precedes the original success record")
	runner.assert_eq(observer.cancellation_results, [false], "a guard cannot cancel the process that is being checked")
	if not observer.notice_states.is_empty():
		var after: Dictionary = observer.notice_states[0]
		runner.assert_eq(after.item.container, "actor:player", "the listener sees the real stone already held")
		runner.assert_true(not bool(after.active) and not bool(after.target_in_use), "the listener sees the process and object lock released")
		runner.assert_eq(after.last_action, str(take.id), "the original action record exists before notification")
		runner.assert_eq(after.last_kind, "taken", "the original success is recorded before notification")
	runner.assert_eq(world.artifacts.objects[STONE].container, "actor:player", "mutating the listener's copy cannot alter original custody")
	world.artifacts.settle_at_ms(world.elapsed_ms)
	runner.assert_eq(observer.notices.size(), 1, "repeating settlement never republishes the take")

	observer.probe_artifact_cancel = false
	var place: Dictionary = _stone_action(runner, world, "place")
	if place.is_empty():
		return
	expected = _expected(STONE, "home", "actor:player", "home", "kitchen", int(place.due_ms), str(place.id), "place")
	runner.assert_true(world.advance_to_ms(int(place.due_ms)), "the original clock settles the placement")
	runner.assert_eq(observer.guards.size(), 2, "placement has exactly one preflight")
	runner.assert_eq(observer.notices.size(), 2, "placement publishes exactly once")
	if observer.guards.size() >= 2 and observer.notices.size() >= 2:
		runner.assert_eq(observer.guards[1], expected, "placement preflight describes the original holder and workplace")
		runner.assert_eq(observer.notices[1], expected, "placement notification preserves the original change")
		runner.assert_eq(observer.notice_states[1].last_kind, "placed", "placement success is recorded before its notice")
		runner.assert_true(not bool(observer.notice_states[1].active), "placement releases its process before notification")
	runner.assert_eq(world.artifacts.objects[STONE].container, "kitchen", "listener mutation cannot move the placed stone")
	world.artifacts.describe(BUYER, STONE)
	runner.assert_true(not bool(world.artifacts.begin(BUYER, "place", STONE).ok), "an already placed stone cannot be placed again")
	var cancelled: Dictionary = _stone_action(runner, world, "take")
	if cancelled.is_empty():
		return
	runner.assert_true(world.artifacts.cancel(BUYER), "an actual unfinished take can be cancelled")
	runner.assert_eq(observer.guards.size(), 2, "queries, failed starts and cancellation do not preflight a move")
	runner.assert_eq(observer.notices.size(), 2, "queries, failed starts and cancellation emit no move")

	for verdict: Variant in [false, 1]:
		observer.allowed = verdict
		var blocked: Dictionary = _stone_action(runner, world, "take")
		if blocked.is_empty():
			return
		runner.assert_true(world.advance_to_ms(int(blocked.due_ms)), "rejected take still spends its full operation time")
		runner.assert_eq(int(world.elapsed_ms), int(blocked.due_ms), "rejection does not roll the world clock back")
		runner.assert_eq(world.artifacts.objects[STONE], original, "false or non-bool guard keeps the same original stone at its source")
		runner.assert_eq(world.artifacts.events.back().kind, "failed", "rejected transfer finishes as a real failed action")
		runner.assert_true(not world.artifacts.owns_actor(BUYER), "a rejected action releases its original actor")
	runner.assert_eq(observer.guards.size(), 4, "each rejected take calls the synchronous guard once")
	runner.assert_eq(observer.notices.size(), 2, "rejected transfers emit no successful notice")
	world.artifacts.transfers.set_guard(Callable())
	var unguarded: Dictionary = _stone_action(runner, world, "take")
	if unguarded.is_empty():
		return
	runner.assert_true(world.advance_to_ms(int(unguarded.due_ms)), "an empty callable restores the default allowing behavior")
	runner.assert_eq(world.artifacts.objects[STONE].container, "actor:player", "unguarded default moves the original stone")
	runner.assert_eq(observer.guards.size(), 4, "clearing the guard makes no stale preflight call")
	runner.assert_eq(observer.notices.size(), 3, "the later successful action publishes exactly once")


func _draw_and_inflight_restore(runner: Object) -> void:
	var fixture := Drawing.new()
	var world: RegionalSimulation = fixture._world(runner)
	if world == null or not fixture._learn(runner, world):
		return
	fixture._at_sword(world, BUYER)
	fixture._put(world, "chen_shouzhuo", world.artifacts.object_cell(STONE))
	var observer := Observer.new(world)
	observer.allowed = false
	observer.probe_other_begin = true
	world.artifacts.transfers.set_guard(observer.preflight)
	world.artifacts.transfers.committed.connect(observer.committed)
	var source: Dictionary = world.artifacts.objects[SWORD].duplicate(true)
	var qi: int = int(world.regions.home.actors.player.qi)
	var started: int = int(world.elapsed_ms)
	var reply: Dictionary = world.artifacts.begin_draw(BUYER, RING, SWORD)
	runner.assert_true(bool(reply.ok), "a learned ring holder starts a real paid draw")
	if not bool(reply.ok):
		return
	var blocked: Dictionary = world.artifacts.active[BUYER].duplicate(true)
	runner.assert_eq(int(blocked.due_ms), started + 2000, "the rejected draw still has its actual two-second duration")
	runner.assert_true(world.advance_to_ms(int(blocked.due_ms)), "rejected draw reaches the real deadline")
	runner.assert_eq(int(world.elapsed_ms), started + 2000, "guard refusal does not refund elapsed draw time")
	runner.assert_eq(int(world.regions.home.actors.player.qi), qi - 2, "guard refusal does not refund paid qi")
	runner.assert_eq(world.artifacts.objects[SWORD], source, "guard refusal leaves the unique sword at its source")
	runner.assert_eq(world.artifacts.events.back().kind, "failed", "the refused draw is recorded as failure")
	runner.assert_true(observer.notices.is_empty(), "a refused draw emits no successful transfer")
	runner.assert_eq(observer.begin_results, [false], "preflight cannot start a second actor on an otherwise separate object")
	if not observer.guards.is_empty():
		runner.assert_eq(observer.guards[0].entity.id, SWORD, "draw preflight identifies the sword, not the ring")

	observer.allowed = true
	reply = world.artifacts.begin_draw(BUYER, RING, SWORD)
	runner.assert_true(bool(reply.ok), "the same original sword can be drawn after clearing the refusal")
	if not bool(reply.ok):
		return
	var job: Dictionary = world.artifacts.active[BUYER].duplicate(true)
	var saved: String = SnapshotValues.canonical_json(SnapshotValues.normalized(world.to_dict()))
	var candidate: RegionalSimulation = fixture._world(runner)
	if candidate == null:
		return
	candidate.bind_map_data(world.map_data.independent_copy())
	var candidate_observer := Observer.new(candidate)
	var seam: SimArtifactTransfers = candidate.artifacts.transfers
	seam.set_guard(candidate_observer.preflight)
	seam.committed.connect(candidate_observer.committed)
	var old_domain: SimArtifacts = candidate.artifacts
	var restored: bool = candidate.restore(JSON.parse_string(saved))
	runner.assert_true(restored, "an independent candidate restores the actual in-flight draw")
	if not restored:
		return
	runner.assert_true(candidate.artifacts != old_domain and candidate.artifacts.transfers == seam, "same-world restore replaces the domain while preserving live hooks")
	runner.assert_true(candidate_observer.guards.is_empty() and candidate_observer.notices.is_empty(), "restore itself neither checks nor publishes a transfer")
	runner.assert_eq(SnapshotValues.canonical_json(SnapshotValues.normalized(candidate.to_dict())), saved, "in-flight JSON preserves the complete original world")
	var expected: Dictionary = _expected(SWORD, str(source.region), str(source.container), "home", "actor:player", int(job.due_ms), str(job.id), "draw")
	runner.assert_true(world.advance_to_ms(int(job.due_ms)), "original in-flight draw reaches its deadline")
	runner.assert_true(candidate.advance_to_ms(int(job.due_ms)), "restored in-flight draw reaches the same deadline")
	runner.assert_eq(observer.notices, [expected], "the original draw publishes the actual sword exactly once")
	runner.assert_eq(candidate_observer.guards, [expected], "the retained candidate guard runs once on the real sword")
	runner.assert_eq(candidate_observer.notices, [expected], "the retained candidate listener receives one complete draw")
	if not candidate_observer.notice_states.is_empty():
		runner.assert_eq(candidate_observer.notice_states[0].last_kind, "drawn", "draw event exists before listeners run")
		runner.assert_true(not bool(candidate_observer.notice_states[0].active), "draw releases its actor before listeners run")
	runner.assert_eq(SnapshotValues.canonical_json(SnapshotValues.normalized(candidate.to_dict())), SnapshotValues.canonical_json(SnapshotValues.normalized(world.to_dict())), "restored and original worlds have identical complete futures")
	candidate.artifacts.settle_at_ms(candidate.elapsed_ms)
	runner.assert_eq(candidate_observer.notices.size(), 1, "restored draw cannot publish again on repeated settlement")


func _exchange(runner: Object, accept: bool) -> void:
	var fixture := Exchange.new()
	var world: RegionalSimulation = fixture._world(runner)
	if world == null:
		return
	var buyer_coin: int = fixture._coin(world, BUYER)
	var seller_coin: int = fixture._coin(world, SELLER)
	var total: int = fixture._total(world)
	var price: int = int(world.private_exchange.definitions.price)
	var original: Dictionary = world.artifacts.objects[RING].duplicate(true)
	var event_count: int = world.artifacts.events.size()
	var id: String = fixture._start(runner, world)
	if id.is_empty():
		return
	var job: Dictionary = world.private_exchange.jobs[id]
	var observer := Observer.new(world)
	observer.allowed = accept
	observer.exchange_id = id
	observer.probe_exchange_cancel = true
	observer.mutate_guard = true
	observer.mutate_notice = true
	world.artifacts.transfers.set_guard(observer.preflight)
	world.artifacts.transfers.committed.connect(observer.committed)
	var expected: Dictionary = _expected(RING, str(original.region), str(original.container), str(job.buyer_region), "actor:" + BUYER, int(job.due_ms), str(job.artifact_action), "private_exchange")
	runner.assert_true(world.advance_to_ms(int(job.due_ms) - 1), "the bargain remains in flight through the last incomplete millisecond")
	runner.assert_true(observer.guards.is_empty() and observer.notices.is_empty(), "agreement and waiting publish no physical exchange")
	runner.assert_true(world.advance_to_ms(int(job.due_ms)), "the original clock reaches the private delivery deadline")
	runner.assert_eq(observer.guards, [expected], "private handover preflight identifies the real ring and artifact action")
	runner.assert_eq(observer.cancellation_results, [false], "a guard cannot cancel its own pending private delivery")
	if not observer.guard_states.is_empty():
		var before: Dictionary = observer.guard_states[0]
		runner.assert_eq(before.item, original, "private preflight sees the original ring still held by seller")
		runner.assert_eq(int(before.buyer_coin), buyer_coin, "private preflight precedes the buyer debit")
		runner.assert_eq(int(before.seller_coin), seller_coin, "private preflight precedes the seller credit")
		runner.assert_true(bool(before.reserved) and bool(before.buyer_locked) and bool(before.seller_locked) and bool(before.target_in_use), "private preflight sees the live reservation and locks")
		runner.assert_true(before.status == "active" and not bool(before.receipt_exists), "private preflight precedes completion and receipt")
		runner.assert_eq(int(before.event_count), event_count, "private preflight precedes original artifact history")
	if accept:
		runner.assert_eq(observer.notices, [expected], "completed exchange publishes the entire original ring handover once")
		if not observer.notice_states.is_empty():
			var after: Dictionary = observer.notice_states[0]
			runner.assert_eq(after.item.container, "actor:player", "listener sees the real ring with the buyer")
			runner.assert_eq(int(after.buyer_coin), buyer_coin - price, "listener sees the final buyer balance")
			runner.assert_eq(int(after.seller_coin), seller_coin + price, "listener sees the final seller balance")
			runner.assert_true(after.status == "completed" and not str(after.receipt).is_empty() and bool(after.receipt_exists), "listener sees completed job and the original money receipt")
			runner.assert_true(not bool(after.reserved) and not bool(after.buyer_locked) and not bool(after.seller_locked) and not bool(after.target_in_use), "listener sees both actor locks and the reservation released")
			runner.assert_eq(after.last_action, str(job.artifact_action), "listener sees original artifact event tied to the action")
			runner.assert_eq(after.last_kind, "exchanged", "listener runs after the original exchange record")
		runner.assert_eq(world.artifacts.objects[RING].container, "actor:player", "mutating listener data cannot alter the ring")
		runner.assert_eq(fixture._total(world), total, "a completed delivery conserves original money")
		world.private_exchange.settle_at_ms(world.elapsed_ms)
		runner.assert_eq(observer.notices.size(), 1, "repeated exchange settlement cannot republish")
	else:
		runner.assert_true(observer.notices.is_empty(), "guard rejection publishes no completed exchange")
		runner.assert_eq(job.status, "failed", "a rejected exchange terminates as failed")
		runner.assert_eq(world.artifacts.objects[RING], original, "failed exchange keeps the single ring with the seller")
		runner.assert_eq(fixture._coin(world, BUYER), buyer_coin, "failed exchange leaves buyer coins unchanged")
		runner.assert_eq(fixture._coin(world, SELLER), seller_coin, "failed exchange leaves seller coins unchanged")
		runner.assert_eq(world.artifacts.events.size(), event_count, "failed exchange records no physical artifact delivery")
		runner.assert_true(not world.regions[job.buyer_region].inventory.reservations.has(str(job.reservation)), "failed exchange releases the original coin reservation")
		runner.assert_true(not world.private_exchange.owns_actor(BUYER) and not world.private_exchange.owns_actor(SELLER) and not world.artifacts.target_in_use(RING), "failed exchange releases both actors and the ring")
