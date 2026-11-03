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
const MAX_EXACT_INTEGER: int = 9007199254740991
const SUPPORTED_SPEEDS: Array[float] = [1.0, 2.0, 4.0]
const RULES_PATH: String = "res://data/definitions/local_actions.json"

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if total_minutes == 0:
		total_minutes = start_minutes


func _process(delta: float) -> void:
	if paused or not is_finite(delta) or delta < 0.0:
		return
	if wait_target_ms > elapsed_ms:
		var minute_budget: int = MAX_MINUTES_PER_FRAME
		while wait_target_ms > elapsed_ms and minute_budget > 0 and not paused:
			_commit_interval(mini(wait_target_ms, (tick_index + 1) * MS_PER_MINUTE))
			minute_budget -= 1
		if elapsed_ms == wait_target_ms:
			cancel_wait()
			set_paused(true)
		return
	# Debt uses world milliseconds and retains fractional frame conversion.
	var incoming: float = delta * speed * 1000.0
	if not is_finite(incoming) or incoming > MAX_EXACT_INTEGER - elapsed_ms - _accumulator:
		return
	_accumulator += incoming
	var step: float = float(_rules.clock.fixed_step_ms)
	var epsilon: float = step * STEP_EPSILON_RATIO
	var budget: int = int(_rules.clock.steps_per_frame)
	while _accumulator + epsilon >= step and budget > 0 and not paused:
		_accumulator = maxf(0.0, _accumulator - step)
		budget -= 1
		advance_msec(int(step))
	# Budgeting never discards debt, including a callback interruption.


func advance_ticks(count: int) -> void:
	# Explicit synchronous simulation commands preserve the old minute API.
	for _index in range(count):
		advance_msec(MS_PER_MINUTE)


func advance_msec(amount: int) -> void:
	if amount < 0 or amount > MAX_EXACT_INTEGER - elapsed_ms:
		return
	var target: int = elapsed_ms + amount
	while elapsed_ms < target:
		_commit_interval(mini(target, (tick_index + 1) * MS_PER_MINUTE))


func _commit_interval(end: int) -> void:
	var previous_hour: int = get_hour()
	var previous_day: int = get_day()
	var start: int = elapsed_ms
	elapsed_ms = end
	time_advanced.emit(start, end)
	@warning_ignore("integer_division")
	var minute: int = elapsed_ms / MS_PER_MINUTE
	if minute > tick_index:
		total_minutes += minute - tick_index
		tick_index = minute
		tick.emit(tick_index)
	if get_hour() != previous_hour:
		hour_changed.emit(get_hour())
	if get_day() != previous_day:
		day_changed.emit(get_day())


func bind_wait_guard(provider: Callable) -> void:
	_wait_guard = provider
	_has_wait_guard = true


func request_wait(minutes: int = -1) -> bool:
	if _has_wait_guard and (not _wait_guard.is_valid() or not bool(_wait_guard.call())):
		return false
	if minutes == -1:
		minutes = int(_rules.clock.wait_minutes)
	@warning_ignore("integer_division")
	var maximum_minutes: int = (MAX_EXACT_INTEGER - elapsed_ms) / MS_PER_MINUTE
	if minutes < 1 or minutes > maximum_minutes:
		return false
	wait_target_ms = elapsed_ms + minutes * MS_PER_MINUTE
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
	if not is_valid_state(data):
		return false
	if data.size() == 4:
		data = upgrade_legacy(data)
		if data.is_empty():
			return false
	tick_index = int(data.tick_index)
	total_minutes = int(data.total_minutes)
	speed = float(data.speed)
	paused = data.paused
	elapsed_ms = int(data.elapsed_ms)
	_accumulator = float(data.frame_debt_ms)
	wait_target_ms = int(data.wait_target_ms)
	if is_inside_tree():
		get_tree().paused = paused
	speed_changed.emit(speed)
	paused_changed.emit(paused)
	wait_changed.emit(wait_target_ms > elapsed_ms)
	hour_changed.emit(get_hour())
	day_changed.emit(get_day())
	return true


func set_paused(value: bool) -> void:
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
