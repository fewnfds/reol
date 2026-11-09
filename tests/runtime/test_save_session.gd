extends RefCounted
## Clock/file coordination uses a local clock and tiny candidate, without Main.
var clock: ReolGameClock
var session: SimSaveSession
var value: int = 1
var failed: bool = false
var limit_ms: int = 5
var receipts: Array = []
var reentry: Array = []


func run(runner: Object) -> void:
	clock = ReolGameClock.new()
	_reset(false)
	clock.bind_interval_executor(func(from_ms: int, to_ms: int) -> int: return mini(from_ms + limit_ms, to_ms))
	session = SimSaveSession.new()
	session.configure(_capture, _stage, _adopt, func() -> bool: return not clock.has_pending_advance(), clock, func() -> bool: return failed)
	session.save_finished.connect(func(path: String, result: Error) -> void:
		receipts.append(result)
		reentry.append(session.request_save(path))
		reentry.append(session.load_now(path))
	)
	var path: String = "user://tests/save_session_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(session.save_now(path), OK, "a strict complete save writes the primary")
	runner.assert_eq(session.save_now(path), OK, "a second strict save establishes a backup")
	var before: String = FileAccess.get_file_as_string(path)
	var backup: String = FileAccess.get_file_as_string(path + ".bak")
	clock.advance_frame(0.2)
	runner.assert_true(clock.has_pending_advance(), "a partial accepted frame interval remains pending")
	runner.assert_eq(session.save_now(path), ERR_BUSY, "strict callers still refuse partial work")
	runner.assert_eq(session.request_save(path), OK, "ordinary request acquires a future complete boundary")
	runner.assert_eq(FileAccess.get_file_as_string(path), before, "request acceptance is not a completed write")
	var pending_at: int = clock.elapsed_ms
	clock.advance_frame(10.0)
	clock.advance_msec(1000)
	runner.assert_true(clock.elapsed_ms == pending_at and not clock.request_wait(1), "the save hold admits no new realtime, explicit or wait request")
	session.process_save()
	clock.set_paused(true)
	_drain(runner)
	var saved: Dictionary = SimSaveStore.load_file(path).data
	runner.assert_eq([saved.clock.elapsed_ms, saved.clock.frame_debt_ms, saved.clock.paused], [50.0, 150.0, true], "save finishes the accepted interval and retains unstarted debt and the latest user pause")
	runner.assert_eq(receipts, [OK], "only the completed write emits success")
	runner.assert_eq(reentry, [ERR_BUSY, ERR_BUSY], "completion listeners cannot reenter the active transaction")
	runner.assert_true(clock.paused, "coordinator never unpauses the user's game")
	limit_ms = 10000
	_reset(false)
	runner.assert_true(clock.request_wait(2), "a future wait is an ordinary persistent intent")
	clock.advance_frame(0.0)
	session.request_save(path)
	_drain(runner)
	saved = SimSaveStore.load_file(path).data
	runner.assert_eq([saved.clock.elapsed_ms, saved.clock.wait_target_ms, saved.clock.paused], [60000.0, 120000.0, false], "only the accepted wait interval is drained, its future target is saved")
	_reset(true)
	clock.advance_msec(120020)
	clock.set_paused(true)
	session.request_save(path)
	_drain(runner)
	saved = SimSaveStore.load_file(path).data
	runner.assert_eq([saved.clock.elapsed_ms, saved.clock.paused], [120020.0, true], "nonpersistent explicit requests finish without changing user pause")
	runner.assert_true(not clock.has_pending_advance(), "no explicit endpoint is silently dropped from the archive")
	before = FileAccess.get_file_as_string(path)
	backup = FileAccess.get_file_as_string(path + ".bak")
	failed = true
	session.request_save(path)
	session.process_save()
	runner.assert_eq(receipts.back(), ERR_INVALID_DATA, "terminal settlement failure completes with a failure receipt")
	failed = false
	session.request_save(path)
	session._started_usec -= SimSaveSession.DRAIN_TIMEOUT_USEC
	session.process_save()
	runner.assert_eq(receipts.back(), ERR_TIMEOUT, "an unfinishable request times out and releases the hold")
	session.request_save(path)
	session.cancel_save()
	runner.assert_eq(receipts.back(), ERR_SKIP, "explicit disposal/cancellation completes and releases the hold")
	runner.assert_eq([FileAccess.get_file_as_string(path), FileAccess.get_file_as_string(path + ".bak")], [before, backup], "failure, timeout and cancellation preserve both files")
	value = 99
	runner.assert_eq(session.load_now(path), OK, "independent valid candidate is adopted")
	runner.assert_eq(value, 1, "load publishes the archived owner state")
	var invalid_path: String = path + ".invalid"
	SimSaveStore.save_file(invalid_path, {"value": "bad"})
	runner.assert_eq(session.load_now(invalid_path), ERR_INVALID_DATA, "malformed candidate is rejected")
	runner.assert_eq(value, 1, "failed loading leaves live state unchanged")
	_reset(false)
	clock.advance_frame(0.05)
	runner.assert_true(clock.elapsed_ms > 0, "all failure paths released admission for normal gameplay")
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp", ".invalid"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	session = null
	clock.free()
	print("SCENARIO save session: bounded drain, persistent debt/wait, explicit completion, pause, receipts and failure isolation")


func _reset(paused: bool) -> void:
	clock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": paused})


func _drain(runner: Object) -> void:
	for _frame: int in 32:
		if not session.pending():
			break
		session.process_save()
	runner.assert_true(not session.pending(), "accepted work drains within the fixture's bounded frames")


func _capture() -> Dictionary:
	return {"value": value, "clock": clock.to_dict()}


func _stage(data: Dictionary) -> Dictionary:
	return data if data.get("value") is float and data.get("clock") is Dictionary and ReolGameClock.is_valid_state(data.clock) else {}


func _adopt(data: Dictionary) -> void:
	value = int(data.value)
	clock.restore_state(data.clock)
