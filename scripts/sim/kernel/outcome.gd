extends RefCounted
## Detached notification envelope. Source and affected subject are distinct;
## environmental outcomes may legitimately have no actor.
static func envelope(value: Dictionary, at: int) -> Dictionary:
	var result: Dictionary = value.duplicate()
	result["actor"] = int(value.get("actor", 0))
	result["target"] = int(value.get("target", 0))
	result["at_ms"] = int(value.get("at_ms", at))
	return result

static func subject(value: Dictionary) -> int:
	return int(value.get("target", 0)) if int(value.get("target", 0)) > 0 else int(value.get("actor", 0))
