extends RefCounted
## Focused boundary contract test with a deliberately multi-step guard. The
## production environment integration has its own end-to-end assertions.

const Fixture = preload("res://tests/sim/test_object_lifecycle.gd")
var _fixture := Fixture.new()
var _motion_calls: int = 0
var _existing_guard_calls: int = 0


func run(runner: Object) -> void:
	_direct_pending_and_cancel(runner)
	_timed_boundary_resume(runner)
	_timed_boundary_cancel(runner)
	_legacy_transfer_guard_composition(runner)
	print("SCENARIO environment event boundary: direct pending, timed deadline, cancellation and no repeated movement")


func _opening(runner: Object, id: String) -> RegionalSimulation:
	var world: RegionalSimulation = _fixture._world(runner)
	if world == null:
		return null
	var created: Dictionary = world.object_lifecycle.execute(_fixture._spawn("create_" + id, id, "plain_slate", [40, 40]))
	runner.assert_true(bool(created.get("ok", false)), "boundary fixture has a real ground original")
	if not bool(created.get("ok", false)):
		return null
	if not world.synchronize_regions():
		runner.assert_true(false, "boundary fixture synchronizes before projection")
		return null
	return world


func _direct_pending_and_cancel(runner: Object) -> void:
	var world: RegionalSimulation = _opening(runner, "direct_object")
	if world == null:
		return
	var guard := SlowGuard.new(world)
	runner.assert_true(world.bind_environment_boundary_guard(guard), "acceptance session binds its guard")
	var request: Dictionary = _fixture._move("direct_move", "direct_object", _fixture._location("ground:create_direct_object"), _fixture._ground(41, 40))
	var result: Dictionary = world.object_lifecycle.execute(request)
	runner.assert_true(bool(result.get("pending", false)), "a direct transaction can wait without moving the original")
	if not bool(result.get("pending", false)):
		return
	runner.assert_eq(world.artifacts.objects.direct_object.container, "ground:create_direct_object", "pending leaves the physical object at its old owner")
	runner.assert_true(world.to_dict().is_empty(), "ordinary world save refuses an unfinished candidate")
	runner.assert_true(not world.advance_to_ms(1), "time cannot pass an unfinished direct transaction")
	var cancelled: Dictionary = world.object_lifecycle.cancel_environment_change(result.handle)
	runner.assert_true(bool(cancelled.get("ok", false)), "a direct pending candidate can be cancelled")
	runner.assert_true(not world.object_lifecycle.receipts.has("direct_move"), "cancellation does not fabricate a successful receipt")
	runner.assert_eq(world.artifacts.objects.direct_object.container, "ground:create_direct_object", "cancel preserves the original position")
	runner.assert_true(not world.to_dict().is_empty(), "save is available again after cancellation")
	result = world.object_lifecycle.execute(request)
	runner.assert_true(bool(result.get("pending", false)), "cancelled command can be prepared again")
	if not bool(result.get("pending", false)):
		return
	var handle: Variant = result.handle
	result = world.object_lifecycle.resume_environment_change(handle)
	runner.assert_true(bool(result.get("pending", false)), "resume preserves pending until the guard is ready")
	result = world.object_lifecycle.resume_environment_change(handle)
	runner.assert_true(bool(result.get("ok", false)) and not bool(result.get("pending", false)), "ready direct transaction publishes once")
	runner.assert_eq(world.artifacts.objects.direct_object.container, "ground:direct_move", "completed transaction moves the original")
	runner.assert_eq(guard.commits, 1, "only the completed transaction commits the environment")
	runner.assert_eq(world.object_lifecycle.execute(request), result, "retry returns the single original receipt")


func _timed_boundary_resume(runner: Object) -> void:
	var world: RegionalSimulation = _opening(runner, "timed_object")
	if world == null:
		return
	var guard := SlowGuard.new(world)
	if not world.bind_environment_boundary_guard(guard):
		runner.assert_true(false, "timed guard binds")
		return
	_motion_calls = 0
	world.set_manual_motion_executor(_count_motion)
	var request: Dictionary = _fixture._move("timed_move", "timed_object", _fixture._location("ground:create_timed_object"), _fixture._ground(41, 40))
	var scheduled: Dictionary = world.object_lifecycle.schedule(request, "player", 100)
	runner.assert_true(bool(scheduled.get("ok", false)), "original timed move is scheduled")
	if not bool(scheduled.get("ok", false)):
		return
	runner.assert_true(not world.advance_to_ms(1000), "the real world stops at the pending event")
	runner.assert_eq(world.elapsed_ms, 100, "event uses its game-time deadline")
	runner.assert_eq(world.target_ms, 1000, "requested time debt is retained")
	runner.assert_eq(world.object_lifecycle.actions.timed_move.status, "active", "pending is not failure")
	runner.assert_eq(int(world.object_lifecycle.actions.timed_move.due_ms), 100, "the deadline is not rewritten")
	runner.assert_true(world.environment_boundary_active() and world.to_dict().is_empty(), "half-boundary rejects an ordinary snapshot")
	runner.assert_true(world.environment_event_valid(guard.context), "guard received the current identity credential")
	var motion_before: int = _motion_calls
	runner.assert_true(not world.advance_to_ms(100), "small guard budget stays pending")
	runner.assert_eq(_motion_calls, motion_before, "resuming does not rerun earlier interval movement")
	runner.assert_true(world.advance_to_ms(100), "the original boundary can complete after preparation")
	runner.assert_eq(_motion_calls, motion_before, "successful resume still does not repeat prior motion")
	runner.assert_eq(world.object_lifecycle.actions.timed_move.status, "completed", "the original action completes once")
	runner.assert_true(not world.environment_event_valid(guard.context), "event credential expires at boundary completion")
	runner.assert_eq(world.target_ms, 1000, "completing the event does not discard later requested time")
	runner.assert_eq(guard.commits, 1, "the source and object publish once")


func _timed_boundary_cancel(runner: Object) -> void:
	var world: RegionalSimulation = _opening(runner, "cancel_object")
	if world == null:
		return
	var guard := SlowGuard.new(world)
	if not world.bind_environment_boundary_guard(guard):
		return
	var request: Dictionary = _fixture._move("timed_cancel", "cancel_object", _fixture._location("ground:create_cancel_object"), _fixture._ground(41, 40))
	var scheduled: Dictionary = world.object_lifecycle.schedule(request, "player", 100)
	if not bool(scheduled.get("ok", false)):
		runner.assert_true(false, "cancellation action schedules")
		return
	world.advance_to_ms(100)
	runner.assert_true(world.environment_boundary_active(), "cancellable event is pending")
	runner.assert_true(world.object_lifecycle.cancel("player"), "actor cancellation releases the pending candidate")
	runner.assert_true(world.advance_to_ms(100), "cancelled event finishes the remaining boundary")
	runner.assert_eq(world.object_lifecycle.actions.timed_cancel.status, "cancelled", "action is cancelled rather than completed")
	runner.assert_eq(world.artifacts.objects.cancel_object.container, "ground:create_cancel_object", "cancel never moves the original")
	runner.assert_true(not world.object_lifecycle.receipts.has("timed_cancel"), "cancel never writes a successful receipt")
	runner.assert_eq(guard.commits, 0, "cancel does not publish a field candidate")


func _count_motion(_start: int, _end: int) -> void:
	_motion_calls += 1


func _legacy_transfer_guard_composition(runner: Object) -> void:
	var seam := SimArtifactTransfers.new()
	var guardian := TransferGuard.new()
	_existing_guard_calls = 0
	seam.set_guard(_existing_guard)
	runner.assert_true(seam.bind_ground_guard(guardian), "acceptance guard composes with an existing legacy guard")
	var ground := {"entity": {"kind": "artifact", "id": "item"}, "from": {"region": "home", "container": "ground:old"},
		"to": {"region": "home", "container": "actor:player"}, "at_ms": 0, "action": "old", "cause": "take"}
	runner.assert_true(not seam.allows(ground), "legacy artifact transfer cannot bypass the ground owner")
	runner.assert_eq(_existing_guard_calls, 0, "the original guard is not invoked for already rejected work")
	var ordinary: Dictionary = ground.duplicate(true)
	ordinary.from.container = "dorm"
	runner.assert_true(seam.allows(ordinary), "non-ground transfers still consult the existing guard")
	runner.assert_eq(_existing_guard_calls, 1, "existing guard remains in place")
	guardian = null
	runner.assert_true(not seam.allows(ordinary), "a lost weak guard refuses rather than bypassing protection")
	runner.assert_true(seam.bind_ground_guard(null), "explicit unbind restores ordinary behavior")
	runner.assert_true(seam.allows(ordinary), "the original guard works after acceptance closes")
	runner.assert_eq(_existing_guard_calls, 2, "closing does not replace the original guard")


func _existing_guard(_change: Dictionary) -> bool:
	_existing_guard_calls += 1
	return true


class TransferGuard:
	extends RefCounted

	func allows_artifact_transfer(change: Dictionary) -> bool:
		return not str(change.from.container).begins_with("ground:") and not str(change.to.container).begins_with("ground:")


class SlowGuard:
	extends RefCounted
	var world: WeakRef
	var handle: RefCounted
	var proof: RefCounted
	var remaining: int = 0
	var commits: int = 0
	var context: Variant

	func _init(owner: RegionalSimulation) -> void:
		world = weakref(owner)

	func prepare_move(_plan: Dictionary, supplied_context: Variant) -> Dictionary:
		context = supplied_context
		handle = RefCounted.new()
		proof = RefCounted.new()
		remaining = 2
		return {"ok": true, "pending": true, "handle": handle}

	func resume_move(supplied_handle: Variant) -> Dictionary:
		if not is_same(handle, supplied_handle):
			return {"ok": false, "reason": "invalid_handle"}
		remaining -= 1
		return {"ok": true, "pending": true, "handle": handle} if remaining > 0 else {"ok": true, "pending": false, "handle": handle, "proof": proof}

	func can_commit_move(supplied_proof: Variant, _plan: Dictionary, supplied_context: Variant) -> Dictionary:
		if not is_same(proof, supplied_proof):
			return {"ok": false, "reason": "invalid_proof"}
		if supplied_context != null and not world.get_ref().environment_event_valid(supplied_context):
			return {"ok": false, "reason": "stale_event"}
		return {"ok": true}

	func commit_move(supplied_proof: Variant, _plan: Dictionary) -> Dictionary:
		if not is_same(proof, supplied_proof):
			return {"ok": false, "reason": "invalid_proof"}
		commits += 1
		handle = null
		return {"ok": true}

	func cancel_move(_handle: Variant) -> Dictionary:
		handle = null
		return {"ok": true}
