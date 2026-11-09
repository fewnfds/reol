class_name ReolSimulationPacing
extends RefCounted
## Host policy only. Samples affect admission of FUTURE world time, never the
## order, timestamps, random state or completion of already accepted work.

const FRAME_BUDGET_USEC: int = 6000
const TARGET_RENDER_HZ: float = 60.0
const HEADROOM: float = 0.85
const MAX_LEAD_SECONDS: float = 0.25
const MIN_RATE: float = 0.01
const RECOVERY_PER_SECOND: float = 0.25

var rate: float = 1.0
var last_work_usec: int = 0
var longest_work_usec: int = 0
var _cost_per_ms: float = 0.0
var _unpublished_work_usec: int = 0
var _frame_seconds: float = 1.0 / TARGET_RENDER_HZ


func admit_ms(real_seconds: float, requested_speed: float, owed_ms: float, blocked: bool) -> float:
	if blocked or not is_finite(real_seconds) or real_seconds <= 0.0:
		return 0.0
	var lead_ms: float = MAX_LEAD_SECONDS * requested_speed * 1000.0
	return minf(real_seconds * requested_speed * rate * 1000.0, maxf(0.0, lead_ms - owed_ms))


func observe(real_seconds: float, work_usec: int, advanced_ms: int, pending: bool, requested_speed: float) -> void:
	last_work_usec = maxi(0, work_usec)
	longest_work_usec = maxi(longest_work_usec, last_work_usec)
	_unpublished_work_usec += last_work_usec
	_frame_seconds = lerpf(_frame_seconds, clampf(real_seconds, 1.0 / TARGET_RENDER_HZ, MAX_LEAD_SECONDS), 0.1)
	if advanced_ms > 0:
		var cost: float = float(_unpublished_work_usec) / float(advanced_ms)
		# React immediately to expensive work; reclaim capacity conservatively.
		_cost_per_ms = cost if cost >= _cost_per_ms else lerpf(_cost_per_ms, cost, 0.1)
		_unpublished_work_usec = 0
	var target: float = 1.0
	if _cost_per_ms > 0.0:
		target = clampf(FRAME_BUDGET_USEC * HEADROOM / (_frame_seconds * _cost_per_ms * requested_speed * 1000.0), MIN_RATE, 1.0)
	if pending:
		# A single cooperative yield is not itself sustained overload. Existing
		# cost evidence can lower the rate; recovery waits until work catches up.
		rate = minf(target, rate)
	elif target < rate:
		rate = target
	else:
		rate = minf(target, rate + clampf(real_seconds, 0.0, MAX_LEAD_SECONDS) * RECOVERY_PER_SECOND)


func reset() -> void:
	rate = 1.0
	last_work_usec = 0
	longest_work_usec = 0
	_cost_per_ms = 0.0
	_unpublished_work_usec = 0
	_frame_seconds = 1.0 / TARGET_RENDER_HZ
