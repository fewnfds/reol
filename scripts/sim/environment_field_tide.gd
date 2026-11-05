class_name SimEnvironmentFieldTide
extends RefCounted
## A pure receiver-side multiplier derived from the world's seed, cell and time.
## Interpolate the four raw, nonnegative corner phases first; the triangular
## cycle is applied once afterward, so every cell traverses the full amplitude.
## There is no stored clock, random generator, source state or secondary field.

const SCALE: int = 1000000
const MIN_MULTIPLIER: int = 980000
const DEFAULT_PERIOD_MS: int = 600000
const DEFAULT_SPACING: int = 64
const MAX_TIME: int = 9007199254740991

# This bound keeps each weighted phase sum below 2^51, even at spacing 1024.
const MAX_PERIOD_MS: int = 2000000000
const MAX_SPACING: int = 1024
const _MASK_32: int = 0xffffffff
const _MIX_FACTOR: int = 0x45d9f3b


static func sample(seed: int, cell: Vector2i, at_ms: int, period_ms: int = DEFAULT_PERIOD_MS, spacing: int = DEFAULT_SPACING) -> Dictionary:
	if at_ms < 0 or at_ms > MAX_TIME:
		return {"ok": false, "reason": "time_out_of_range"}
	if period_ms < 2 or period_ms > MAX_PERIOD_MS or period_ms % 2 != 0:
		return {"ok": false, "reason": "invalid_period"}
	if spacing < 1 or spacing > MAX_SPACING:
		return {"ok": false, "reason": "invalid_spacing"}

	# Remainders are nonnegative even west/north of zero. Subtracting them
	# before integer division implements floor rather than truncation to zero.
	# Vector2i's full 32-bit coordinate range and its neighboring corners fit
	# in a GDScript int, including the corner just past 2^31 - 1.
	var local_x: int = posmod(cell.x, spacing)
	var local_y: int = posmod(cell.y, spacing)
	var grid_x: int = (int(cell.x) - local_x) / spacing
	var grid_y: int = (int(cell.y) - local_y) / spacing
	var left: int = spacing - local_x
	var top: int = spacing - local_y
	var weighted_phase: int = (
		_corner_phase(seed, grid_x, grid_y, period_ms) * left * top
		+ _corner_phase(seed, grid_x + 1, grid_y, period_ms) * local_x * top
		+ _corner_phase(seed, grid_x, grid_y + 1, period_ms) * left * local_y
		+ _corner_phase(seed, grid_x + 1, grid_y + 1, period_ms) * local_x * local_y
	)
	var offset_ms: int = weighted_phase / (spacing * spacing)
	# Never cast the original timestamp to float or add it before reduction.
	var phase_ms: int = (at_ms % period_ms + offset_ms) % period_ms
	var half_period: int = period_ms / 2
	var rising_distance: int = mini(phase_ms, period_ms - phase_ms)
	var multiplier: int = MIN_MULTIPLIER + (SCALE - MIN_MULTIPLIER) * rising_distance / half_period
	var until_boundary: int = half_period - phase_ms % half_period
	if until_boundary > MAX_TIME - at_ms:
		return {"ok": true, "multiplier": multiplier, "phase_ms": phase_ms,
			"next_boundary_ms": -1, "next_boundary_known": false,
			"reason": "next_boundary_outside_supported_time"}
	return {"ok": true, "multiplier": multiplier, "phase_ms": phase_ms,
		"next_boundary_ms": at_ms + until_boundary, "next_boundary_known": true}


static func _corner_phase(seed: int, grid_x: int, grid_y: int, period_ms: int) -> int:
	# Mix every 32-bit word, including the sign/high words. Each multiply is
	# at most (2^32 - 1) * 0x45d9f3b, safely within signed 64-bit integers.
	# Unlike an RNG this depends only on the arguments, never query order.
	var mixed: int = _mix32(seed & _MASK_32)
	mixed = _mix32(mixed ^ ((seed >> 32) & _MASK_32))
	mixed = _mix32(mixed ^ (grid_x & _MASK_32))
	mixed = _mix32(mixed ^ ((grid_x >> 32) & _MASK_32))
	mixed = _mix32(mixed ^ (grid_y & _MASK_32))
	mixed = _mix32(mixed ^ ((grid_y >> 32) & _MASK_32))
	return mixed % period_ms


static func _mix32(value: int) -> int:
	var mixed: int = value & _MASK_32
	mixed = ((mixed ^ (mixed >> 16)) * _MIX_FACTOR) & _MASK_32
	mixed = ((mixed ^ (mixed >> 16)) * _MIX_FACTOR) & _MASK_32
	return (mixed ^ (mixed >> 16)) & _MASK_32
