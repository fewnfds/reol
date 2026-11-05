class_name ReolGameClock
extends Node
## One integer timeline; minute domains are coarse projections of the same time.

signal tick(tick_index: int)
signal time_advanced(from_ms: int, to_ms: int)
signal wait_changed(waiting: bool)
signal hour_changed(hour: int)
signal day_changed(day: int)
signal speed_changed(speed: float)
signal paused_changed(paused_state: bool)

const MINUTES_PER_HOUR: int = 60
const MINUTES_PER_DAY: int = 1440
const MS_PER_MINUTE: int = 60000
const STEP_EPSILON_RATIO: float = 1.0e-9
const MAX_MINUTES_PER_FRAME: int = 8
const MAX_EXPLICIT_INTERVALS: int = 4096
const MAX_EXACT_INTEGER: int = 9007199254740991
const SUPPORTED_SPEEDS: Array[float] = [1.0, 2.0, 4.0]
const RULES_PATH: String = "res://data/definitions/local_actions.json"
const PENDING_NONE: int = 0
const PENDING_FRAME: int = 1
const PENDING_EXPLICIT: int = 2
const PENDING_WAIT: int = 3

@export var start_minutes: int = 480
var speed: float = 1.0
var paused: bool = false
var tick_index: int = 0
var total_minutes: int = 0
var elapsed_ms: int = 0
var wait_target_ms: int = 0
var _accumulator: float = 0.0
var _rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
var _wait_guard: Callable
var _has_wait_guard: bool = false
var _interval_executor: Callable
var _has_interval_executor: bool = false
var _executor_required: bool = false
var _advancing: bool = false
var _pending_kind: int = PENDING_NONE
var _pending_end_ms: int = 0
var _frame_end_ms: int = 0
var _explicit_target_ms: int = 0
var _explicit_allow_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if total_minutes == 0:
		total_minutes = start_minutes


func _process(delta: float) -> void:
	if _advancing or not is_finite(delta) or delta < 0.0:
		return
	# An explicitly requested advance can start while paused. A new pause after
	# it started, however, stops its continuation until the user resumes.
	if paused and not (_explicit_target_ms > elapsed_ms and _explicit_allow_paused):
		return
	if not paused and wait_target_ms <= elapsed_ms:
		# Debt uses world milliseconds and retains fractional frame conversion.
		var incoming: float = delta * speed * 1000.0
		var future: int = maxi(elapsed_ms, maxi(_explicit_target_ms, maxi(_pending_end_ms, _frame_end_ms)))
		var reserved: int = future - elapsed_ms
		if _frame_end_ms > elapsed_ms:
			reserved = maxi(0, reserved - (_frame_end_ms - elapsed_ms))
		if not is_finite(incoming) or incoming > float(MAX_EXACT_INTEGER - elapsed_ms - reserved) - _accumulator:
			return
		_accumulator += incoming
	_advancing = true
	_process_pending()
	_advancing = false


func _process_pending() -> void:
	# Finish the exact interval previously offered to the executor before
	# starting a different request, even if a wait was cancelled in the meantime.
	if _pending_kind != PENDING_NONE:
		if not _commit_pending() or _finish_wait_if_due():
			return
		if paused and not _explicit_allow_paused:
			return
	if _frame_end_ms > elapsed_ms and not _finish_frame_step(_explicit_allow_paused):
		return
	if _explicit_target_ms > elapsed_ms:
		_drain_explicit(MAX_MINUTES_PER_FRAME)
		if _explicit_target_ms > elapsed_ms or paused:
			return
	if paused:
		return
	if wait_target_ms > elapsed_ms:
		var minute_budget: int = MAX_MINUTES_PER_FRAME
		while wait_target_ms > elapsed_ms and minute_budget > 0 and not paused:
			_pending_kind = PENDING_WAIT
			_pending_end_ms = mini(wait_target_ms, (tick_index + 1) * MS_PER_MINUTE)
			minute_budget -= 1
			if not _commit_pending() or _finish_wait_if_due():
				return
		return
	var step: float = float(_rules.clock.fixed_step_ms)
	var epsilon: float = step * STEP_EPSILON_RATIO
	var budget: int = int(_rules.clock.steps_per_frame)
	while _accumulator + epsilon >= step and budget > 0 and not paused:
		budget -= 1
		_frame_end_ms = elapsed_ms + int(step)
		if not _finish_frame_step(false):
			return
	# Budgeting never discards debt, including a callback interruption.


func _finish_frame_step(allow_paused: bool) -> bool:
	while _frame_end_ms > elapsed_ms:
		if paused and not allow_paused:
			return false
		_pending_kind = PENDING_FRAME
		_pending_end_ms = mini(_frame_end_ms, (tick_index + 1) * MS_PER_MINUTE)
		if not _commit_pending() or _finish_wait_if_due():
			return false
	_frame_end_ms = 0
	return true


func advance_ticks(count: int) -> void:
	# Explicit synchronous simulation commands preserve the old minute API.
	@warning_ignore("integer_division")
	if count < 0 or count > MAX_EXACT_INTEGER / MS_PER_MINUTE:
		return
	advance_msec(count * MS_PER_MINUTE)


func advance_msec(amount: int) -> void:
	if _advancing or amount <= 0:
		return
	# Explicit commands add time after any already-requested interval. Its
	# remaining frame debt is consumed by that interval, not by this command.
	var base: int = maxi(elapsed_ms, maxi(_frame_end_ms, maxi(_pending_end_ms, _explicit_target_ms)))
	if amount > MAX_EXACT_INTEGER - base:
		return
	var target: int = base + amount
	var reserved_debt: float = _accumulator
	if _frame_end_ms > elapsed_ms:
		reserved_debt = maxf(0.0, reserved_debt - float(_frame_end_ms - elapsed_ms))
	if reserved_debt > float(MAX_EXACT_INTEGER - target):
		return
	if _explicit_target_ms <= elapsed_ms:
		_explicit_allow_paused = paused
	_explicit_target_ms = target
	_advancing = true
	_drain_explicit(MAX_EXPLICIT_INTERVALS)
	_advancing = false


func _drain_explicit(budget: int) -> void:
	if _pending_kind != PENDING_NONE:
		if not _commit_pending() or _finish_wait_if_due():
			return
		budget -= 1
	if _frame_end_ms > elapsed_ms and not _finish_frame_step(_explicit_allow_paused):
		return
	while _explicit_target_ms > elapsed_ms and budget > 0:
		if paused and not _explicit_allow_paused:
			return
		_pending_kind = PENDING_EXPLICIT
		_pending_end_ms = mini(_explicit_target_ms, (tick_index + 1) * MS_PER_MINUTE)
		if wait_target_ms > elapsed_ms:
			_pending_end_ms = mini(_pending_end_ms, wait_target_ms)
		budget -= 1
		if not _commit_pending() or _finish_wait_if_due():
			return
	if _explicit_target_ms <= elapsed_ms:
		_explicit_target_ms = 0
		_explicit_allow_paused = false


func _commit_pending() -> bool:
	var start: int = elapsed_ms
	var end: int = _pending_end_ms
	var committed: int = end
	if _has_interval_executor:
		if not _interval_executor.is_valid():
			return false
		var result: Variant = _interval_executor.call(start, end)
		if not result is int or int(result) < start or int(result) > end:
			return false
		committed = int(result)
	elif _executor_required:
		return false
	if committed == start:
		return false
	var previous_hour: int = get_hour()
	var previous_day: int = get_day()
	if _pending_kind == PENDING_FRAME:
		_accumulator = maxf(0.0, _accumulator - float(committed - start))
	elapsed_ms = committed
	var completed: bool = committed == end
	if completed:
		_pending_kind = PENDING_NONE
		_pending_end_ms = 0
		if _frame_end_ms == committed:
			_frame_end_ms = 0
	@warning_ignore("integer_division")
	var minute: int = elapsed_ms / MS_PER_MINUTE
	var advanced_minute: bool = minute > tick_index
	if minute > tick_index:
		total_minutes += minute - tick_index
		tick_index = minute
	time_advanced.emit(start, committed)
	if advanced_minute:
		tick.emit(tick_index)
	if get_hour() != previous_hour:
		hour_changed.emit(get_hour())
	if get_day() != previous_day:
		day_changed.emit(get_day())
	return completed


func _finish_wait_if_due() -> bool:
	if wait_target_ms == 0 or elapsed_ms < wait_target_ms:
		return false
	cancel_wait()
	_explicit_allow_paused = false
	set_paused(true)
	return true


func bind_interval_executor(provider: Callable) -> bool:
	if _advancing or not provider.is_valid():
		return false
	if _has_interval_executor:
		return provider == _interval_executor
	_interval_executor = provider
	_has_interval_executor = true
	_executor_required = false
	return true


func unbind_interval_executor(provider: Callable) -> bool:
	if _advancing or not _has_interval_executor or provider != _interval_executor:
		return false
	_executor_required = has_pending_advance()
	_interval_executor = Callable()
	_has_interval_executor = false
	return true


func has_pending_advance() -> bool:
	return _advancing or _pending_kind != PENDING_NONE or _frame_end_ms > elapsed_ms or _explicit_target_ms > elapsed_ms


func is_advancing() -> bool:
	# A session loader must refuse before replacing its world, not discover
	# the reentry only when it eventually tries to restore this clock.
	return _advancing


func bind_wait_guard(provider: Callable) -> void:
	if _advancing:
		return
	_wait_guard = provider
	_has_wait_guard = true


func request_wait(minutes: int = -1) -> bool:
	if _advancing:
		return false
	if _has_wait_guard and (not _wait_guard.is_valid() or not bool(_wait_guard.call())):
		return false
	if minutes == -1:
		minutes = int(_rules.clock.wait_minutes)
	@warning_ignore("integer_division")
	var base: int = maxi(elapsed_ms, maxi(_frame_end_ms, maxi(_pending_end_ms, _explicit_target_ms)))
	var maximum_minutes: int = (MAX_EXACT_INTEGER - base) / MS_PER_MINUTE
	if minutes < 1 or minutes > maximum_minutes:
		return false
	var reserved_debt: float = _accumulator
	if _frame_end_ms > elapsed_ms:
		reserved_debt = maxf(0.0, reserved_debt - float(_frame_end_ms - elapsed_ms))
	if reserved_debt > float(MAX_EXACT_INTEGER - base - minutes * MS_PER_MINUTE):
		return false
	wait_target_ms = base + minutes * MS_PER_MINUTE
	wait_changed.emit(true)
	set_paused(false)
	return true


func cancel_wait() -> void:
	if wait_target_ms != 0:
		wait_target_ms = 0
		wait_changed.emit(false)


func view_transition_rate() -> float:
	# A short presentation blend after a coarse position commit, never a rule.
	return 1000.0 / float(_rules.clock.view_transition_ms)


func set_speed(value: float) -> void:
	if not is_finite(value):
		return
	value = clampf(value, SUPPORTED_SPEEDS[0], SUPPORTED_SPEEDS[-1])
	var next_speed: float = SUPPORTED_SPEEDS[0]
	for candidate: float in SUPPORTED_SPEEDS:
		if absf(candidate - value) < absf(next_speed - value):
			next_speed = candidate
	if is_equal_approx(speed, next_speed):
		return
	speed = next_speed
	speed_changed.emit(speed)


func to_dict() -> Dictionary:
	return {"tick_index": tick_index, "total_minutes": total_minutes, "speed": speed, "paused": paused,
		"elapsed_ms": elapsed_ms, "frame_debt_ms": _accumulator, "wait_target_ms": wait_target_ms}


static func upgrade_legacy(data: Dictionary) -> Dictionary:
	if data.size() != 4 or data.has("elapsed_ms") or not is_valid_state(data):
		return {}
	if float(data.tick_index) > floorf(float(MAX_EXACT_INTEGER) / MS_PER_MINUTE):
		return {}
	var result: Dictionary = data.duplicate(true)
	result["elapsed_ms"] = int(data.tick_index) * MS_PER_MINUTE
	result["frame_debt_ms"] = 0.0
	result["wait_target_ms"] = 0
	return result


static func is_valid_state(data: Dictionary) -> bool:
	for field: String in ["tick_index", "total_minutes"]:
		if not _integer(data.get(field)):
			return false
	var speed_value: Variant = data.get("speed")
	if not (speed_value is int or speed_value is float) or not float(speed_value) in SUPPORTED_SPEEDS or not data.get("paused") is bool:
		return false
	# Four-field values are explicit legacy/programmatic input. Session v5
	# additionally requires all modern fields at its own validation boundary.
	if data.size() == 4:
		return not data.has("elapsed_ms")
	if data.size() != 7 or not _integer(data.get("elapsed_ms")) or not _integer(data.get("wait_target_ms")):
		return false
	@warning_ignore("integer_division")
	var minute: int = int(data.elapsed_ms) / MS_PER_MINUTE
	var debt: Variant = data.get("frame_debt_ms")
	return minute == int(data.tick_index) and (int(data.wait_target_ms) == 0 or int(data.wait_target_ms) > int(data.elapsed_ms)) and (debt is int or debt is float) and is_finite(float(debt)) and float(debt) >= 0.0 and float(debt) <= MAX_EXACT_INTEGER - int(data.elapsed_ms)


static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= MAX_EXACT_INTEGER and float(value) == floorf(float(value))


func restore_state(data: Dictionary) -> bool:
	if _advancing or not is_valid_state(data):
		return false
	if data.size() == 4:
		data = upgrade_legacy(data)
		if data.is_empty():
			return false
	_advancing = true
	tick_index = int(data.tick_index)
	total_minutes = int(data.total_minutes)
	speed = float(data.speed)
	paused = data.paused
	elapsed_ms = int(data.elapsed_ms)
	_accumulator = float(data.frame_debt_ms)
	wait_target_ms = int(data.wait_target_ms)
	_pending_kind = PENDING_NONE
	_pending_end_ms = 0
	_frame_end_ms = 0
	_explicit_target_ms = 0
	_explicit_allow_paused = false
	_executor_required = false
	if is_inside_tree():
		get_tree().paused = paused
	speed_changed.emit(speed)
	paused_changed.emit(paused)
	wait_changed.emit(wait_target_ms > elapsed_ms)
	hour_changed.emit(get_hour())
	day_changed.emit(get_day())
	_advancing = false
	return true


func set_paused(value: bool) -> void:
	# A fresh pause request interrupts an explicit single-step even if it began
	# while already paused. Repeating true is still a real danger/user request.
	_explicit_allow_paused = false
	if paused == value:
		return
	paused = value
	if is_inside_tree():
		get_tree().paused = value
	paused_changed.emit(value)


func toggle_pause() -> void:
	set_paused(not paused)


func get_day() -> int:
	return floori(float(total_minutes) / float(MINUTES_PER_DAY))


func get_hour() -> int:
	return floori(float(total_minutes) / float(MINUTES_PER_HOUR)) % 24


func get_minute() -> int:
	return total_minutes % MINUTES_PER_HOUR


func format_time() -> String:
	return "第 %d 天 %02d:%02d" % [get_day() + 1, get_hour(), get_minute()]
