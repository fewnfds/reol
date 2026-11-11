class_name ReolSimulationPacing
extends RefCounted
## Host policy only. Samples affect admission of FUTURE world time, never the
## order, timestamps, random state or completion of already accepted work.

const FRAME_BUDGET_USEC: int = 6000
const MAX_FRAME_BUDGET_USEC: int = 10000
const FRAME_WORK_SHARE: float = 0.60
const TARGET_RENDER_HZ: float = 60.0
const HEADROOM: float = 0.85
const MAX_LEAD_SECONDS: float = 0.25
const MIN_RATE: float = 0.01
const RECOVERY_PER_SECOND: float = 0.25
const THROUGHPUT_WINDOW_SECONDS: float = 0.5
const PRESSURE_HOLD_SECONDS: float = 0.25
const PRESSURE_LEAD_SECONDS: float = 0.15
const HEALTHY_LEAD_SECONDS: float = 0.10

var rate: float = 1.0
var last_work_usec: int = 0
var longest_work_usec: int = 0
var _frame_seconds: float = 1.0 / TARGET_RENDER_HZ
var _sample_seconds: float = 0.0
var _sample_world_ms: float = 0.0
var _pressure_seconds: float = 0.0


func frame_budget_usec() -> int:
	# The soft execution slice and admission feedback are independent. Keep
	# the existing 6ms slice at high refresh; at 60Hz allow up to 10ms rather
	# than silently halving work capacity. A host stall cannot grow this cap.
	return clampi(roundi(_frame_seconds * FRAME_WORK_SHARE * 1000000.0), FRAME_BUDGET_USEC, MAX_FRAME_BUDGET_USEC)


func admit_ms(real_seconds: float, requested_speed: float, owed_ms: float, blocked: bool) -> float:
	if blocked or not is_finite(real_seconds) or real_seconds <= 0.0:
		return 0.0
	var lead_ms: float = MAX_LEAD_SECONDS * requested_speed * 1000.0
	return minf(real_seconds * requested_speed * rate * 1000.0, maxf(0.0, lead_ms - owed_ms))


func observe(real_seconds: float, work_usec: int, advanced_ms: int, _pending: bool, requested_speed: float, owed_ms: float = 0.0) -> void:
	last_work_usec = maxi(0, work_usec)
	longest_work_usec = maxi(longest_work_usec, last_work_usec)
	if not is_finite(real_seconds) or real_seconds <= 0.0 or requested_speed <= 0.0:
		return
	var seconds: float = minf(real_seconds, MAX_LEAD_SECONDS)
	_frame_seconds = lerpf(_frame_seconds, clampf(seconds, 0.001, 1.0 / TARGET_RENDER_HZ), 0.1)
	var retained: float = exp(-seconds / THROUGHPUT_WINDOW_SECONDS)
	_sample_seconds = _sample_seconds * retained + seconds
	_sample_world_ms = _sample_world_ms * retained + float(maxi(0, advanced_ms))
	var lead: float = maxf(0.0, owed_ms) / (requested_speed * 1000.0)
	if lead > PRESSURE_LEAD_SECONDS:
		_pressure_seconds += seconds
		if _pressure_seconds >= PRESSURE_HOLD_SECONDS:
			# Measure completed throughput only when work is persistently backed
			# up. Cheap idle frames, one expensive boundary and GPU polling are
			# not independently evidence of overload. The debt cap stays in admit.
			var capacity: float = _sample_world_ms / (_sample_seconds * requested_speed * 1000.0)
			rate = minf(rate, clampf(capacity * HEADROOM, MIN_RATE, 1.0))
	else:
		_pressure_seconds = 0.0
		if lead < HEALTHY_LEAD_SECONDS:
			rate = minf(1.0, rate + seconds * RECOVERY_PER_SECOND)


func reset() -> void:
	rate = 1.0
	last_work_usec = 0
	longest_work_usec = 0
	_sample_seconds = 0.0
	_sample_world_ms = 0.0
	_pressure_seconds = 0.0
	_frame_seconds = 1.0 / TARGET_RENDER_HZ
