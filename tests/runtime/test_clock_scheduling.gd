extends RefCounted


func run(runner: Object) -> void:
	var slow := ReolGameClock.new()
	var fine := ReolGameClock.new()
	slow._process(5.05)
	runner.assert_eq(slow.elapsed_ms, 4000, "one stalled frame is bounded to eighty fine world steps")
	# No additional real time: drain only the unfinished original frame.
	slow._process(0.0)
	slow._process(0.0)
	for _index in 101:
		fine._process(0.05)
	runner.assert_eq(slow.to_dict(), fine.to_dict(), "frame budget preserves the same world time as small frames")
	runner.assert_true(is_equal_approx(slow._accumulator, fine._accumulator), "fractional frame remainder is retained")
	slow.free()
	fine.free()
	var clock := ReolGameClock.new()
	clock.time_advanced.connect(func(_from: int, to: int) -> void:
		if to == 50:
			clock.set_paused(true)
	)
	clock._process(0.5)
	runner.assert_eq(clock.elapsed_ms, 50, "a fine callback can pause before another due step executes")
	clock._process(10.0)
	runner.assert_eq(clock.elapsed_ms, 50, "paused wall time neither advances nor becomes extra debt")
	clock.set_paused(false)
	clock._process(0.0)
	runner.assert_eq(clock.elapsed_ms, 500, "resume drains only time already pending before the interruption")
	clock._process(NAN)
	clock._process(INF)
	clock._process(-1.0)
	runner.assert_eq(clock.elapsed_ms, 500, "invalid frame durations cannot poison clock scheduling")
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
	clock._process(0.15)
	runner.assert_eq(clock.elapsed_ms, 60300, "2x advances the same physical timeline")
	clock._accumulator = 17.25
	var saved: Dictionary = JSON.parse_string(JSON.stringify(clock.to_dict()))
	var restored := ReolGameClock.new()
	runner.assert_true(restored.restore_state(saved), "fine phase and fractional frame debt survive JSON")
	clock._process(0.05)
	restored._process(0.05)
	runner.assert_eq(clock.to_dict(), restored.to_dict(), "restored phase/debt has the identical next frame")
	clock.free()
	restored.free()
	clock = ReolGameClock.new()
	clock.tick.connect(func(minute: int) -> void:
		if minute == 1:
			clock.set_paused(true)
	)
	runner.assert_true(clock.request_wait(3), "long wait is a bounded command on the shared timeline")
	clock._process(0)
	runner.assert_eq(clock.elapsed_ms, 60000, "callback danger/pause interrupts a wait before its next minute")
	runner.assert_eq(clock.wait_target_ms, 180000, "interrupted wait target is retained for save/resume")
	clock.set_paused(false)
	clock._process(0)
	runner.assert_eq(clock.elapsed_ms, 180000, "resumed wait reaches its target without a separate simulation")
	runner.assert_true(clock.paused and clock.wait_target_ms == 0, "finished wait clears its command and pauses")
	clock.free()
