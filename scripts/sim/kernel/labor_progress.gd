extends RefCounted
## Standard labor credited by a canceled run; completion owns the final quantum.
static func credited(base_work: int, scheduled_ms: int, elapsed_ms: int) -> int:
	return mini(maxi(0, base_work - 1), maxi(0, elapsed_ms) * base_work / maxi(1, scheduled_ms))
