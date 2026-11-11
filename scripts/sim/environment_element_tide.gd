class_name SimEnvironmentElementTide
extends RefCounted
## Receiver-cell percentages, held for one game minute. Order matches source
## definitions: wood/fire/earth/metal/water. No global RNG or accumulated bonus.

const PERIOD_MS: int = 60000
const MAX_PERCENT: int = 5
const _MASK_32: int = 0xffffffff
const _MIX_FACTOR: int = 0x45d9f3b


static func percentages(seed: int, cell: Vector2i, at_ms: int) -> PackedInt32Array:
	@warning_ignore("integer_division")
	var minute: int = at_ms / PERIOD_MS
	var key: int = _mix32(seed & _MASK_32)
	key = _mix32(key ^ ((seed >> 32) & _MASK_32))
	key = _mix32(key ^ (cell.x & _MASK_32))
	key = _mix32(key ^ (cell.y & _MASK_32))
	key = _mix32(key ^ (minute & _MASK_32))
	key = _mix32(key ^ ((minute >> 32) & _MASK_32))
	var result := PackedInt32Array()
	for channel: int in 5:
		result.append(_mix32(key ^ _mix32(channel + 1)) % (MAX_PERCENT * 2 + 1) - MAX_PERCENT)
	return result


static func apply(base: PackedFloat64Array, percent: PackedInt32Array) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for channel: int in 5:
		result.append(roundi(base[channel] * float(100 + percent[channel]) / 100.0))
	return result


static func _mix32(value: int) -> int:
	var mixed: int = value & _MASK_32
	mixed = ((mixed ^ (mixed >> 16)) * _MIX_FACTOR) & _MASK_32
	mixed = ((mixed ^ (mixed >> 16)) * _MIX_FACTOR) & _MASK_32
	return (mixed ^ (mixed >> 16)) & _MASK_32
