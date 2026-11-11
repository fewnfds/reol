class_name SimCadence
extends RefCounted
## Logical sampling schedules, independent of frames, device completion or RNG.
## Exact events retain their own timestamp; these periods only select samples.

const BASE_MS: int = 50
const THERMAL_MOTION_MS: int = 2 * BASE_MS
const FIELD_MOTION_MS: int = 8 * BASE_MS


static func source_motion_ms(channels: PackedInt32Array) -> int:
	# Temperature can affect health; a mixed source uses the faster schedule.
	# Strong heat/cold keeps exact crossing time instead of hiding a large
	# absolute temperature error behind a small percentage of its target.
	if maxi(channels[5], channels[6]) > 1000:
		return 1
	return THERMAL_MOTION_MS if channels[5] != 0 or channels[6] != 0 else FIELD_MOTION_MS


static func at_or_after(at_ms: int, period_ms: int, phase_ms: int = 0) -> int:
	return at_ms + posmod(phase_ms - at_ms, period_ms)


static func after(at_ms: int, period_ms: int, phase_ms: int = 0) -> int:
	return at_ms + period_ms - posmod(at_ms - phase_ms, period_ms)


static func phase(id: String, period_ms: int) -> int:
	# Explicit stable hash; no global random draws or registration-order offset.
	var value: int = 0
	for character: int in id.to_utf8_buffer():
		value = (value * 31 + character) % 2147483647
	return (value % maxi(1, period_ms / BASE_MS)) * BASE_MS
