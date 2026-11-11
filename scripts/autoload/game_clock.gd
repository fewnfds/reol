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
signal pacing_changed(effective_speed: float)
signal input_boundary

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
var pacing := ReolSimulationPacing.new()
var _last_host_usec: int = -1
var _frame_deadline_usec: int = 0
var _view_delta_seconds: float = 0.0
var _pace_display_bucket: int = 20
var _save_boundary_owner: WeakRef
var _publication_cost_usec: int = 0
var _publication_deferred_at_ms: int = -1
var _publication_deferred_deadline: int = 0
var _input_boundary_requested: bool = false


func bind_rules(definitions: Dictionary) -> bool:
	if _advancing or not SimLocalMotion.valid_rules(definitions):
		return false
	_rules = definitions
	return true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_host_usec = Time.get_ticks_usec()
	if total_minutes == 0:
		total_minutes = start_minutes


func _process(_delta: float) -> void:
	# Engine delta may be scaled/clamped. Monotonic host time is measured here;
	# bounded admission deliberately slows the world after a long host stall.
	var now: int = Time.get_ticks_usec()
	var seconds: float = float(now - _last_host_usec) / 1000000.0 if _last_host_usec >= 0 else 0.0
	_last_host_usec = now
	if _save_boundary_held():
		_view_delta_seconds = 0.0
		return
	var before: int = elapsed_ms
	var running: bool = not paused or _explicit_allow_paused
	_frame_deadline_usec = now + pacing.frame_budget_usec()
	advance_frame(seconds)
	_frame_deadline_usec = 0
	if running:
		pacing.observe(seconds, Time.get_ticks_usec() - now, elapsed_ms - before, has_pending_advance(), speed, _accumulator)
		_publish_pacing()


func advance_frame(delta: float) -> void:
	# Explicit host-frame input for deterministic drivers/tests. Only _process
	# measures CPU time and supplies a wall deadline; no wall time enters rules.
	_view_delta_seconds = 0.0
	if _advancing or _save_boundary_held() or not is_finite(delta) or delta < 0.0:
		return
	# A paused host still collects the exact interval already offered to its
	# coordinator. Once complete it starts no new realtime/explicit work.
	if paused and _pending_kind == PENDING_NONE and not (_explicit_target_ms > elapsed_ms and _explicit_allow_paused):
		return
	# Interpolate only previously committed projections, even while a newer
	# boundary waits. This clock never extrapolates unfinished world facts.
	_view_delta_seconds = minf(delta, ReolSimulationPacing.MAX_LEAD_SECONDS) * effective_speed()
	if not paused and wait_target_ms <= elapsed_ms:
		# Unadmitted wall time is slowdown, not an ever-growing catch-up target.
		# Previously admitted debt (including an old save) is never truncated.
		var explicit_work: bool = _explicit_target_ms > elapsed_ms or _pending_kind in [PENDING_EXPLICIT, PENDING_WAIT]
		var incoming: float = pacing.admit_ms(delta, speed, _accumulator, explicit_work)
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
	_offer_input_boundary()


func request_input_boundary() -> void:
	# Finish the offered interval, then let host intents enter before admitting
	# another one. Busy frames cannot starve input by always starting more work.
	_input_boundary_requested = true


func _offer_input_boundary() -> void:
	if _input_boundary_requested and not has_pending_advance():
		_input_boundary_requested = false
		input_boundary.emit()


func frame_budget_exhausted() -> bool:
	return _frame_deadline_usec > 0 and Time.get_ticks_usec() >= _frame_deadline_usec


func frame_budget_has_room(work_usec: int) -> bool:
	return _frame_deadline_usec == 0 or Time.get_ticks_usec() + work_usec <= _frame_deadline_usec


func presentation_budget_usec() -> int:
	# Separate from rule continuation: late-frame disposable work gets at most
	# 1ms, within 2ms after the simulation slice. No new world time is admitted.
	if _last_host_usec < 0:
		return ReolPresentationWork.MAX_WORK_USEC
	return clampi(_last_host_usec + pacing.frame_budget_usec() + 2000 - Time.get_ticks_usec(),
		0, ReolPresentationWork.MAX_WORK_USEC)


func ready_for_publication(at_ms: int) -> bool:
	if _frame_deadline_usec == 0:
		return true # Explicit drivers have no host deadline.
	if _publication_deferred_at_ms == at_ms and _publication_deferred_deadline != _frame_deadline_usec:
		_publication_deferred_at_ms = -1
		return true # At most one frame of deferral, even if preflight alone is slow.
	if at_ms < _pending_end_ms and not frame_budget_exhausted():
		return true # Interior rule boundaries need no full clock/view publication.
	# Leave room for the measured clock observers. A fresh callback can always
	# publish even if observers alone exceed the soft budget; no deadlock/debt loss.
	var reserve: int = mini(_publication_cost_usec, roundi(pacing.frame_budget_usec() * ReolSimulationPacing.HEADROOM))
	if frame_budget_has_room(reserve):
		_publication_deferred_at_ms = -1
		return true
	_publication_deferred_at_ms = at_ms
	_publication_deferred_deadline = _frame_deadline_usec
	return false


func effective_speed() -> float:
	return 0.0 if paused else speed * pacing.rate


func view_delta_seconds() -> float:
	return 0.0 if paused else _view_delta_seconds


func pacing_status() -> Dictionary:
	return {"requested_speed": speed, "effective_speed": effective_speed(), "load_rate": pacing.rate,
		"admitted_debt_ms": _accumulator, "pending": has_pending_advance(),
		"frame_work_budget_usec": pacing.frame_budget_usec(),
		"last_work_usec": pacing.last_work_usec, "longest_work_usec": pacing.longest_work_usec}


func _publish_pacing() -> void:
	var bucket: int = floori(pacing.rate * 20.0)
	if bucket != _pace_display_bucket:
		_pace_display_bucket = bucket
		pacing_changed.emit(effective_speed())


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
	if _input_boundary_requested and _explicit_target_ms <= elapsed_ms:
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
			if _input_boundary_requested:
				return
		return
	var step: float = float(_rules.clock.fixed_step_ms)
	var epsilon: float = step * STEP_EPSILON_RATIO
	var budget: int = int(_rules.clock.steps_per_frame)
	while _accumulator + epsilon >= step and budget > 0 and not paused and not frame_budget_exhausted():
		budget -= 1
		_frame_end_ms = elapsed_ms + int(step)
		if not _finish_frame_step(false):
			return
		if _input_boundary_requested:
			return
	# Budgeting never discards debt, including a callback interruption.


func _finish_frame_step(allow_paused: bool) -> bool:
	while _frame_end_ms > elapsed_ms:
		if paused and not allow_paused or frame_budget_exhausted():
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
	if _advancing or _save_boundary_held() or amount <= 0:
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
	_offer_input_boundary()


func _drain_explicit(budget: int) -> void:
	if _pending_kind != PENDING_NONE:
		if not _commit_pending() or _finish_wait_if_due():
			return
		budget -= 1
	if _frame_end_ms > elapsed_ms and not _finish_frame_step(_explicit_allow_paused):
		return
	while _explicit_target_ms > elapsed_ms and budget > 0 and not frame_budget_exhausted():
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
	if frame_budget_exhausted():
		return false
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
	var publication_started: int = Time.get_ticks_usec()
	time_advanced.emit(start, committed)
	if advanced_minute:
		tick.emit(tick_index)
	if get_hour() != previous_hour:
		hour_changed.emit(get_hour())
	if get_day() != previous_day:
		day_changed.emit(get_day())
	if _frame_deadline_usec > 0:
		var cost: int = Time.get_ticks_usec() - publication_started
		_publication_cost_usec = cost if _publication_cost_usec == 0 else roundi(lerpf(float(_publication_cost_usec), float(cost), 0.25))
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


func begin_save_boundary(owner: RefCounted) -> bool:
	if owner == null or _advancing or _save_boundary_held():
		return false
	_save_boundary_owner = weakref(owner)
	_view_delta_seconds = 0.0
	return true


func drain_save_boundary(owner: RefCounted) -> void:
	if not _owns_save_boundary(owner) or _advancing:
		return
	# Complete accepted work even if paused; do not start another realtime
	# step or wait interval. Unstarted debt and the future wait target are
	# already persistent. Explicit commands must finish: they are not saved.
	var previous_deadline: int = _frame_deadline_usec
	_frame_deadline_usec = Time.get_ticks_usec() + ReolSimulationPacing.FRAME_BUDGET_USEC
	_advancing = true
	_drain_save_work()
	_advancing = false
	_frame_deadline_usec = previous_deadline


func _drain_save_work() -> void:
	if _pending_kind != PENDING_NONE:
		if not _commit_pending():
			return
		_finish_wait_if_due()
	if _frame_end_ms > elapsed_ms and not _finish_frame_step(true):
		return
	var budget: int = MAX_MINUTES_PER_FRAME
	while _explicit_target_ms > elapsed_ms and budget > 0 and not frame_budget_exhausted():
		budget -= 1
		_pending_kind = PENDING_EXPLICIT
		_pending_end_ms = mini(_explicit_target_ms, (tick_index + 1) * MS_PER_MINUTE)
		if wait_target_ms > elapsed_ms:
			_pending_end_ms = mini(_pending_end_ms, wait_target_ms)
		if not _commit_pending():
			return
		_finish_wait_if_due()
	if _explicit_target_ms <= elapsed_ms:
		_explicit_target_ms = 0
		_explicit_allow_paused = false


func end_save_boundary(owner: RefCounted) -> void:
	if _owns_save_boundary(owner):
		_save_boundary_owner = null
		_last_host_usec = Time.get_ticks_usec()
		_view_delta_seconds = 0.0


func _owns_save_boundary(owner: RefCounted) -> bool:
	return _save_boundary_held() and _save_boundary_owner.get_ref() == owner


func _save_boundary_held() -> bool:
	return _save_boundary_owner != null and _save_boundary_owner.get_ref() != null


func bind_wait_guard(provider: Callable) -> void:
	if _advancing:
		return
	_wait_guard = provider
	_has_wait_guard = true


func request_wait(minutes: int = -1) -> bool:
	if _advancing or _save_boundary_held():
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
	# Published-body interpolation follows the simulation step. The historical
	# 150ms cosmetic blend would add unnecessary input/follow lag at a 50ms step.
	return 1000.0 / float(_rules.clock.fixed_step_ms)


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


static func is_valid_state(data: Dictionary) -> bool:
	for field: String in ["tick_index", "total_minutes"]:
		if not _integer(data.get(field)):
			return false
	var speed_value: Variant = data.get("speed")
	if not (speed_value is int or speed_value is float) or not float(speed_value) in SUPPORTED_SPEEDS or not data.get("paused") is bool:
		return false
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
	_input_boundary_requested = false
	pacing.reset()
	_publication_cost_usec = 0
	_publication_deferred_at_ms = -1
	_publication_deferred_deadline = 0
	_last_host_usec = Time.get_ticks_usec()
	_view_delta_seconds = 0.0
	_publish_pacing()
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
	_last_host_usec = Time.get_ticks_usec()
	_view_delta_seconds = 0.0
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
