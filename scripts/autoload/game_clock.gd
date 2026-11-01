class_name ReolGameClock
extends Node
## Global game clock: fixed 10 Hz simulation ticks, pause, and 1x/2x/4x speed.
##
## 1 tick = 1 game minute. A full day is 1440 ticks (144 s at 1x).

signal tick(tick_index: int)
signal hour_changed(hour: int)
signal day_changed(day: int)
signal speed_changed(speed: float)
signal paused_changed(paused_state: bool)

const MINUTES_PER_HOUR: int = 60
const MINUTES_PER_DAY: int = 1440

@export var ticks_per_second: int = 10
@export var minutes_per_tick: int = 1
@export var start_minutes: int = 480

var speed: float = 1.0
var paused: bool = false
var tick_index: int = 0
var total_minutes: int = 0

var _accumulator: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if total_minutes == 0:
		total_minutes = start_minutes


func _process(delta: float) -> void:
	if paused:
		return

	_accumulator += delta * speed
	var step: float = 1.0 / float(ticks_per_second)
	var budget: int = 8
	while _accumulator >= step and budget > 0:
		_accumulator -= step
		budget -= 1
		_advance_tick()
	if budget == 0:
		_accumulator = 0.0


func advance_ticks(count: int) -> void:
	for _index in range(count):
		_advance_tick()


func _advance_tick() -> void:
	var previous_hour: int = get_hour()
	var previous_day: int = get_day()
	tick_index += 1
	total_minutes += minutes_per_tick
	tick.emit(tick_index)
	if get_hour() != previous_hour:
		hour_changed.emit(get_hour())
	if get_day() != previous_day:
		day_changed.emit(get_day())


func set_speed(value: float) -> void:
	var next_speed: float = clampf(value, 1.0, 4.0)
	if is_equal_approx(speed, next_speed):
		return
	speed = next_speed
	speed_changed.emit(speed)


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
