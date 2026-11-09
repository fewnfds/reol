extends RefCounted
## Public discrete-work contract; a tiny owner proves semantics without Main.
var applied: Array[String] = []
var ready: bool = false
var queue: SimEventQueue
var recursive_rejected: bool = false


func _queue() -> SimEventQueue:
	var result := SimEventQueue.new()
	result.register_rule("sample", _condition, _effect, func(payload: Dictionary) -> bool: return payload.size() == 1 and payload.get("mode") in ["ready", "wait", "retry", "invalid", "recursive"])
	return result


func _condition(payload: Dictionary, _context: Dictionary) -> int:
	if payload.mode == "invalid":
		return SimEventQueue.Condition.INVALID
	return SimEventQueue.Condition.WAIT if payload.mode == "wait" and not ready else SimEventQueue.Condition.READY


func _effect(payload: Dictionary, context: Dictionary) -> int:
	if payload.mode == "retry" and context.at_ms < 30:
		return SimEventQueue.Effect.RETRY
	if payload.mode == "recursive":
		recursive_rejected = not queue.enqueue("recursive_child", "sample", int(context.at_ms), {"mode": "ready"})
	applied.append(str(context.id) + ":" + str(context.occurrence))
	return SimEventQueue.Effect.APPLIED


func run(runner: Object) -> void:
	queue = _queue()
	runner.assert_true(queue.enqueue("b", "sample", 10, {"mode": "ready"}), "a trusted rule accepts discrete work")
	runner.assert_true(queue.enqueue("a", "sample", 10, {"mode": "ready"}), "caller IDs break simultaneous ties")
	runner.assert_true(queue.enqueue("early", "sample", 5, {"mode": "ready"}), "earlier due time dominates the tie-break")
	runner.assert_true(queue.enqueue("a", "sample", 10, {"mode": "ready"}), "the exact request is idempotent")
	runner.assert_true(not queue.enqueue("a", "sample", 11, {"mode": "ready"}), "an operation ID cannot be reused for different work")
	runner.assert_true(not queue.enqueue("bad", "unknown", 5), "saved data cannot choose a script or unregistered handler")
	var result: Vector2i = queue.settle_budgeted(10, 1)
	runner.assert_eq(result.y, SimSettlementKernel.Status.PENDING, "bounded work preserves remaining simultaneous events")
	runner.assert_eq(applied, ["early:0"], "one bounded step applies the earliest event")
	queue.settle_budgeted(10, 1)
	queue.settle_budgeted(10, 1)
	runner.assert_eq(applied, ["early:0", "a:0", "b:0"], "resumption preserves deterministic total order")
	queue.settle_budgeted(10, 10)
	runner.assert_eq(applied.size(), 3, "revisiting a boundary never repeats effects")
	runner.assert_true(queue.enqueue("waiting", "sample", 11, {"mode": "wait"}, {"topics": ["target:one"], "expires_ms": 100}), "a conditional request declares its wake topic and deadline")
	queue.settle_budgeted(11, 10)
	runner.assert_eq(queue.receipt("waiting").status, "waiting", "false conditions wait without per-frame rechecking")
	runner.assert_eq(queue.next_boundary_ms(), 100, "a waiting condition retains its expiry only")
	queue.notify("unrelated", 12)
	runner.assert_eq(queue.next_boundary_ms(), 100, "unrelated changes cannot wake this request")
	ready = true
	queue.notify("target:one", 12)
	queue.settle_budgeted(12, 10)
	runner.assert_eq(queue.receipt("waiting").status, "completed", "the targeted notification wakes and rechecks the condition")
	queue.enqueue("repeat", "sample", 20, {"mode": "ready"}, {"repeat_ms": 10})
	queue.enqueue("retry", "sample", 20, {"mode": "retry"}, {"retry_ms": 10})
	queue.settle_budgeted(20, 10)
	runner.assert_eq(queue.receipt("retry").count, 0, "explicit retry does not claim successful application")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(queue.to_dict()))
	var restored: SimEventQueue = _queue()
	runner.assert_true(restored.restore(saved), "deadlines, receipts and recurrence survive JSON independently")
	queue.settle_budgeted(30, 10)
	var expected: Dictionary = queue.to_dict()
	restored.settle_budgeted(30, 10)
	runner.assert_eq(restored.to_dict(), expected, "restore continues the same future without replaying completed work")
	runner.assert_true(queue.cancel("repeat"), "ongoing periodic work can be cancelled explicitly")
	queue.settle_budgeted(40, 10)
	runner.assert_eq(queue.receipt("repeat").count, 2, "cancelled work cannot produce another occurrence")
	ready = false
	queue.enqueue("expires", "sample", 41, {"mode": "wait"}, {"topics": ["never"], "expires_ms": 45})
	queue.enqueue("lost", "sample", 41, {"mode": "invalid"})
	queue.settle_budgeted(41, 10)
	queue.settle_budgeted(45, 10)
	runner.assert_eq([queue.receipt("expires").status, queue.receipt("lost").status], ["expired", "invalid"], "deadline and vanished-target outcomes are distinct")
	queue.enqueue("recursive", "sample", 46, {"mode": "recursive"})
	queue.settle_budgeted(46, 10)
	runner.assert_true(recursive_rejected, "effects cannot recursively enqueue same-time work")
	var before: Dictionary = queue.to_dict()
	var bad: Dictionary = before.duplicate(true)
	bad.records.a.request.rule = "load_untrusted_script"
	runner.assert_true(not queue.restore(bad), "unknown saved rules are rejected")
	runner.assert_eq(queue.to_dict(), before, "a bad candidate leaves all live requests unchanged")
	var malformed := SimEventQueue.new()
	malformed.register_rule("broken", func(_payload: Dictionary, _context: Dictionary) -> Variant: return "not_a_condition", func(_payload: Dictionary, _context: Dictionary) -> int: return SimEventQueue.Effect.APPLIED, func(_payload: Dictionary) -> bool: return true)
	malformed.enqueue("broken", "broken", 0)
	runner.assert_eq(malformed.settle_budgeted(0, 1).y, SimSettlementKernel.Status.FAILED, "a malformed trusted handler fails the settlement step")
	runner.assert_eq(malformed.receipt("broken").status, "failed", "the failed handler retains a terminal receipt without claiming an effect")
	queue = null
	print("SCENARIO events: stable due order, bounded resume, targeted wake, expiry/cancel, recurring receipts and independent restore")
