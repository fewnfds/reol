extends RefCounted


func run(runner: Object) -> void:
	var slow := ReolGameClock.new()
	var fine := ReolGameClock.new()
	slow.advance_frame(5.05)
	runner.assert_eq(slow.elapsed_ms, 250, "a long host stall admits only a bounded future horizon")
	# Unadmitted wall time is intentional slowdown, not hidden catch-up debt.
	slow.advance_frame(0.0)
	slow.advance_frame(0.0)
	for _index in 5:
		fine.advance_frame(0.05)
	runner.assert_eq(slow.to_dict(), fine.to_dict(), "recovery does not manufacture the unadmitted part of a host stall")
	runner.assert_true(is_equal_approx(slow._accumulator, fine._accumulator), "fractional frame remainder is retained")
	slow._accumulator = 5050.0
	slow.advance_frame(0.0)
	runner.assert_eq(slow.elapsed_ms, 4250, "already accepted debt still obeys the eighty-step work budget")
	slow.advance_frame(0.0)
	runner.assert_eq(slow.elapsed_ms, 5300, "accepted debt is preserved even when larger than the new admission horizon")
	slow.free()
	fine.free()
	var clock := ReolGameClock.new()
	clock.time_advanced.connect(func(_from: int, to: int) -> void:
		if to == 50:
			clock.set_paused(true)
	)
	clock.advance_frame(0.5)
	runner.assert_eq(clock.elapsed_ms, 50, "a fine callback can pause before another due step executes")
	clock.advance_frame(10.0)
	runner.assert_eq(clock.elapsed_ms, 50, "paused wall time neither advances nor becomes extra debt")
	clock.set_paused(false)
	clock.advance_frame(0.0)
	runner.assert_eq(clock.elapsed_ms, 250, "resume drains only time admitted before the interruption")
	clock.advance_frame(NAN)
	clock.advance_frame(INF)
	clock.advance_frame(-1.0)
	runner.assert_eq(clock.elapsed_ms, 250, "invalid frame durations cannot poison clock scheduling")
	for speed: float in [-100.0, 1.7, 3.0, 10.0, NAN, INF]:
		clock.set_speed(speed)
		runner.assert_true(ReolGameClock.is_valid_state(clock.to_dict()), "every accepted speed remains serializable: %s" % str(speed))
	var bad: Dictionary = clock.to_dict()
	bad.tick_index = 9007199254740992
	var before: Dictionary = clock.to_dict()
	runner.assert_true(not clock.restore_state(bad), "time beyond exact JSON integer precision is rejected")
	runner.assert_eq(clock.to_dict(), before, "rejected clock data does not mutate committed time")
	clock.free()

	_test_minute_boundaries_and_wait(runner)
	_test_partial_frame_and_explicit_request(runner)
	_test_wait_partial_and_cancellation(runner)
	_test_pause_and_explicit_budget(runner)
	_test_executor_guards_and_restore(runner)
	_test_frame_crosses_minute(runner)
	_test_initially_paused_interrupt(runner)


func _test_minute_boundaries_and_wait(runner: Object) -> void:
	var clock := ReolGameClock.new()
	var order: Array[String] = []
	clock.time_advanced.connect(func(_from: int, to: int) -> void:
		order.append("fine:%d" % to)
	)
	clock.tick.connect(func(minute: int) -> void:
		order.append("minute:%d" % minute)
	)
	clock.advance_msec(59950)
	runner.assert_eq(clock.tick_index, 0, "minute products cannot settle before the shared minute boundary")
	clock.advance_msec(50)
	runner.assert_eq(order, ["fine:59950", "fine:60000", "minute:1"], "fine displacement commits before minute work at the same boundary")
	clock.set_speed(2)
	clock.advance_frame(0.15)
	runner.assert_eq(clock.elapsed_ms, 60300, "2x advances the same physical timeline")
	clock._accumulator = 17.25
	var saved: Dictionary = JSON.parse_string(JSON.stringify(clock.to_dict()))
	var restored := ReolGameClock.new()
	runner.assert_true(restored.restore_state(saved), "fine phase and fractional frame debt survive JSON")
	clock.advance_frame(0.05)
	restored.advance_frame(0.05)
	runner.assert_eq(clock.to_dict(), restored.to_dict(), "restored phase/debt has the identical next frame")
	clock.free()
	restored.free()
	clock = ReolGameClock.new()
	clock.tick.connect(func(minute: int) -> void:
		if minute == 1:
			clock.set_paused(true)
	)
	runner.assert_true(clock.request_wait(3), "long wait is a bounded command on the shared timeline")
	clock.advance_frame(0)
	runner.assert_eq(clock.elapsed_ms, 60000, "callback danger/pause interrupts a wait before its next minute")
	runner.assert_eq(clock.wait_target_ms, 180000, "interrupted wait target is retained for save/resume")
	clock.set_paused(false)
	clock.advance_frame(0)
	runner.assert_eq(clock.elapsed_ms, 180000, "resumed wait reaches its target without a separate simulation")
	runner.assert_true(clock.paused and clock.wait_target_ms == 0, "finished wait clears its command and pauses")
	clock.free()


class TestExecutor:
	extends Node
	var clock: ReolGameClock
	var limit: int = 1000000000
	var mode: String = "normal"
	var calls: Array = []
	var world_ms: int = 0
	var try_reentry: bool = false
	var reentry_results: Array = []

	func execute(from_ms: int, end_ms: int) -> Variant:
		calls.append([from_ms, end_ms])
		if try_reentry:
			var executor: Callable = Callable(self, "execute")
			clock.advance_msec(1000)
			reentry_results.append(clock.restore_state(clock.to_dict()))
			reentry_results.append(clock.bind_interval_executor(executor))
			reentry_results.append(clock.unbind_interval_executor(executor))
			reentry_results.append(clock.has_pending_advance())
		match mode:
			"float": return float(from_ms + 1)
			"early": return from_ms - 1
			"late": return end_ms + 1
		var result: int = mini(end_ms, from_ms + limit)
		world_ms = result
		return result


func _test_partial_frame_and_explicit_request(runner: Object) -> void:
	var clock := ReolGameClock.new()
	var executor := TestExecutor.new()
	executor.clock = clock
	executor.limit = 20
	var events: Array = []
	clock.time_advanced.connect(func(from_ms: int, to_ms: int) -> void:
		events.append([from_ms, to_ms, executor.world_ms, clock.elapsed_ms, clock._accumulator, clock.has_pending_advance()])
	)
	runner.assert_true(clock.bind_interval_executor(Callable(executor, "execute")), "a valid world interval executor can be bound")
	clock.advance_frame(0.05)
	runner.assert_eq(clock.elapsed_ms, 20, "frame time publishes only the 20 ms actually completed by the world")
	runner.assert_true(is_equal_approx(clock._accumulator, 30.0), "partial frame consumes only its committed 20 ms of debt")
	runner.assert_true(clock.has_pending_advance(), "a partially committed frame remains pending")
	runner.assert_eq(events, [[0, 20, 20, 20, 30.0, true]], "the world and frame debt settle before the time notification")
	clock.advance_msec(100)
	runner.assert_eq(clock.elapsed_ms, 40, "a new explicit command first resumes the prior frame interval")
	runner.assert_true(is_equal_approx(clock._accumulator, 10.0), "a resumed frame consumes only its additional completed debt")
	for _index in 10:
		if not clock.has_pending_advance():
			break
		clock.advance_frame(0.0)
	runner.assert_eq(clock.elapsed_ms, 150, "the 100 ms command follows the completed 50 ms frame without double counting")
	runner.assert_true(is_zero_approx(clock._accumulator) and not clock.has_pending_advance(), "resumed frame and explicit command leave no hidden work")
	runner.assert_eq(executor.calls, [[0, 50], [20, 50], [40, 50], [50, 150], [70, 150], [90, 150], [110, 150], [130, 150]], "partial execution retains the original end boundary until it completes")
	executor.free()
	clock.free()


func _test_wait_partial_and_cancellation(runner: Object) -> void:
	var clock := ReolGameClock.new()
	var executor := TestExecutor.new()
	executor.clock = clock
	executor.limit = 0
	clock.bind_interval_executor(Callable(executor, "execute"))
	var notifications: Array = []
	clock.time_advanced.connect(func(from_ms: int, to_ms: int) -> void: notifications.append([from_ms, to_ms]))
	clock.request_wait(1)
	clock.advance_frame(0.0)
	runner.assert_eq(clock.elapsed_ms, 0, "a zero-progress wait does not publish or advance the clock")
	runner.assert_true(clock.has_pending_advance() and clock.wait_target_ms == 60000 and notifications.is_empty(), "zero progress retains the wait and its interval without a false completion")
	executor.limit = 20000
	clock.advance_frame(0.0)
	clock.advance_frame(0.0)
	runner.assert_eq(clock.elapsed_ms, 40000, "a wait may complete in several partial world commits")
	runner.assert_true(not clock.paused and clock.wait_target_ms == 60000, "the wait does not stop before its actual end")
	clock.advance_frame(0.0)
	runner.assert_true(clock.paused and clock.wait_target_ms == 0 and not clock.has_pending_advance(), "the wait clears and pauses only after the final world commit")
	runner.assert_eq(executor.calls, [[0, 60000], [0, 60000], [20000, 60000], [40000, 60000]], "zero and partial wait retries preserve the same interval end")
	executor.free()
	clock.free()

	clock = ReolGameClock.new()
	executor = TestExecutor.new()
	executor.clock = clock
	executor.limit = 20000
	clock.bind_interval_executor(Callable(executor, "execute"))
	clock.request_wait(2)
	clock.advance_frame(0.0)
	clock.cancel_wait()
	clock.advance_frame(0.0)
	runner.assert_eq(clock.elapsed_ms, 40000, "cancelling a wait retains its already requested unfinished interval")
	runner.assert_true(clock.wait_target_ms == 0 and clock.has_pending_advance(), "cancel removes later wait targets without discarding in-flight work")
	executor.limit = 1000000000
	clock.advance_msec(100)
	runner.assert_eq(clock.elapsed_ms, 60100, "a later explicit request follows the cancelled wait's outstanding interval")
	runner.assert_true(not clock.has_pending_advance(), "the cancelled wait leaves no further work after the requested interval")
	executor.free()
	clock.free()


func _test_pause_and_explicit_budget(runner: Object) -> void:
	var clock := ReolGameClock.new()
	clock.time_advanced.connect(func(_from_ms: int, to_ms: int) -> void:
		if to_ms == 60000:
			clock.set_paused(true)
	)
	clock.advance_msec(180000)
	runner.assert_true(clock.paused and clock.elapsed_ms == 60000 and clock.has_pending_advance(), "a danger pause stops a running explicit advance at the completed boundary")
	clock.advance_frame(10.0)
	runner.assert_eq(clock.elapsed_ms, 60000, "paused wall time does not continue the interrupted explicit advance")
	clock.set_paused(false)
	clock.advance_frame(0.0)
	runner.assert_true(clock.elapsed_ms == 180000 and not clock.has_pending_advance(), "resuming drains the retained explicit target")
	clock.free()

	clock = ReolGameClock.new()
	clock.set_paused(true)
	var executor := TestExecutor.new()
	executor.clock = clock
	executor.limit = 20
	clock.bind_interval_executor(Callable(executor, "execute"))
	clock.advance_msec(50)
	runner.assert_true(clock.paused and clock.elapsed_ms == 20, "an explicit simulation command still works when initially paused")
	clock.advance_frame(0.0)
	clock.advance_frame(0.0)
	runner.assert_true(clock.paused and clock.elapsed_ms == 50 and not clock.has_pending_advance(), "the explicit paused command can finish its partial work without wall-clock debt")
	executor.free()
	clock.free()

	clock = ReolGameClock.new()
	clock.advance_ticks(4100)
	runner.assert_eq(clock.tick_index, 4096, "a huge explicit request is capped rather than blocking indefinitely")
	runner.assert_true(clock.has_pending_advance(), "the bounded explicit request retains its remaining target")
	clock.advance_frame(0.0)
	runner.assert_true(clock.tick_index == 4100 and not clock.has_pending_advance(), "later frames drain the remaining explicit request")
	clock.free()


func _test_executor_guards_and_restore(runner: Object) -> void:
	var clock := ReolGameClock.new()
	var executor := TestExecutor.new()
	executor.clock = clock
	var provider: Callable = Callable(executor, "execute")
	var other := TestExecutor.new()
	other.clock = clock
	var replacement: Callable = Callable(other, "execute")
	runner.assert_true(clock.bind_interval_executor(provider) and clock.bind_interval_executor(provider), "the same valid executor can bind idempotently")
	runner.assert_true(not clock.bind_interval_executor(replacement) and not clock.unbind_interval_executor(replacement), "another executor cannot replace or unbind the owner")
	executor.mode = "float"
	clock.advance_msec(50)
	runner.assert_true(clock.elapsed_ms == 0 and clock.has_pending_advance(), "a floating-point executor result is rejected even when integral")
	for invalid_mode: String in ["early", "late"]:
		executor.mode = invalid_mode
		clock.advance_frame(0.0)
		runner.assert_true(clock.elapsed_ms == 0 and clock.has_pending_advance(), "out-of-range executor result preserves pending work: " + invalid_mode)
	runner.assert_true(clock.unbind_interval_executor(provider), "only the original owner can unbind")
	clock.advance_frame(0.0)
	runner.assert_true(clock.elapsed_ms == 0 and clock.has_pending_advance(), "unbinding cannot falsely complete an existing world interval")
	runner.assert_true(clock.bind_interval_executor(replacement), "a replacement can explicitly take over after unbinding")
	clock.advance_frame(0.0)
	runner.assert_true(clock.elapsed_ms == 50 and not clock.has_pending_advance(), "the new owner completes the original outstanding request")
	clock.unbind_interval_executor(replacement)
	executor.mode = "normal"
	executor.try_reentry = true
	clock.bind_interval_executor(provider)
	var notifications: Array = []
	clock.time_advanced.connect(func(_from_ms: int, _to_ms: int) -> void:
		clock.advance_msec(1000)
		notifications.append(clock.restore_state(clock.to_dict()))
		notifications.append(clock.unbind_interval_executor(provider))
		notifications.append(clock.has_pending_advance())
	)
	clock.advance_msec(10)
	runner.assert_eq(executor.reentry_results, [false, false, false, true], "executor callbacks cannot reenter advance, restore or binding changes")
	runner.assert_eq(notifications, [false, false, true], "time notifications are guarded and report the active transaction")
	runner.assert_eq(clock.elapsed_ms, 60, "reentrant advance attempts do not add time")
	executor.try_reentry = false
	executor.limit = 0
	clock.advance_msec(10)
	var saved: Dictionary = {"tick_index": 0, "total_minutes": 0, "speed": 1.0, "paused": false, "elapsed_ms": 10, "frame_debt_ms": 0.0, "wait_target_ms": 0}
	runner.assert_true(clock.restore_state(saved) and not clock.has_pending_advance(), "a successful restore clears temporary advance cursors")
	executor.limit = 1000000000
	clock.advance_msec(10)
	runner.assert_eq(clock.elapsed_ms, 20, "restore retains the bound executor for the restored timeline")
	clock.unbind_interval_executor(provider)
	executor.free()
	other.free()
	clock.free()

	clock = ReolGameClock.new()
	executor = TestExecutor.new()
	executor.clock = clock
	provider = Callable(executor, "execute")
	clock.bind_interval_executor(provider)
	executor.free()
	other = TestExecutor.new()
	other.clock = clock
	replacement = Callable(other, "execute")
	runner.assert_true(not clock.bind_interval_executor(replacement), "an invalidated owner cannot be silently replaced")
	clock.advance_msec(50)
	runner.assert_true(clock.elapsed_ms == 0 and clock.has_pending_advance(), "a freed executor cannot make the clock advance by itself")
	runner.assert_true(clock.unbind_interval_executor(provider) and clock.bind_interval_executor(replacement), "the original callable can explicitly release an invalidated binding")
	clock.advance_frame(0.0)
	runner.assert_eq(clock.elapsed_ms, 50, "a replacement completes the pending interval")
	other.free()
	clock.free()


func _test_frame_crosses_minute(runner: Object) -> void:
	var clock := ReolGameClock.new()
	clock.advance_msec(59975)
	var executor := TestExecutor.new()
	executor.clock = clock
	executor.world_ms = 59975
	clock.bind_interval_executor(Callable(executor, "execute"))
	var order: Array = []
	clock.time_advanced.connect(func(_from_ms: int, to_ms: int) -> void: order.append("fine:%d" % to_ms))
	clock.tick.connect(func(minute: int) -> void: order.append("minute:%d" % minute))
	clock.advance_frame(0.05)
	runner.assert_eq(executor.calls, [[59975, 60000], [60000, 60025]], "one frame step is split at the shared minute boundary")
	runner.assert_eq(order, ["fine:60000", "minute:1", "fine:60025"], "the minute tick occurs before the remainder of the frame step")
	runner.assert_true(clock.elapsed_ms == 60025 and is_zero_approx(clock._accumulator), "both frame segments consume exactly the original frame debt")
	executor.free()
	clock.free()


func _test_initially_paused_interrupt(runner: Object) -> void:
	var clock := ReolGameClock.new()
	clock.set_paused(true)
	var executor := TestExecutor.new()
	executor.clock = clock
	clock.bind_interval_executor(Callable(executor, "execute"))
	clock.tick.connect(func(minute: int) -> void:
		if minute == 1:
			clock.set_paused(true)
	)
	clock.advance_ticks(3)
	runner.assert_eq([clock.elapsed_ms, executor.world_ms], [60000, 60000], "a fresh pause interrupts an explicit command that began paused")
	runner.assert_true(clock.paused and clock.has_pending_advance(), "the interrupted explicit endpoint is preserved without continuing")
	clock.advance_frame(1.0)
	runner.assert_eq(clock.elapsed_ms, 60000, "paused frames neither continue that command nor accumulate new wall time")
	runner.assert_true(is_zero_approx(clock._accumulator), "the interrupted explicit command creates no extra frame debt")
	clock.set_paused(false)
	clock.advance_frame(0.0)
	runner.assert_eq([clock.elapsed_ms, executor.world_ms], [180000, 180000], "resume completes only the original explicit target")
	runner.assert_true(not clock.has_pending_advance(), "resumed explicit work is consumed exactly once")
	executor.free()
	clock.free()

	clock = ReolGameClock.new()
	clock.advance_msec(59975)
	clock.tick.connect(func(minute: int) -> void:
		if minute == 1:
			clock.set_paused(true)
	)
	clock.advance_frame(0.05)
	runner.assert_true(clock.elapsed_ms == 60000 and clock.has_pending_advance(), "a minute-boundary pause retains the remaining half of a frame step")
	runner.assert_true(is_equal_approx(clock._accumulator, 25.0), "only the completed half of the frame debt is consumed at the boundary")
	clock.set_paused(false)
	clock.advance_frame(0.0)
	runner.assert_true(clock.elapsed_ms == 60025 and not clock.has_pending_advance(), "the remaining half-step resumes even when debt is below a full step")
	clock.free()
