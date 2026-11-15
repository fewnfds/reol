extends RefCounted
const LOGIC_VERSION: String = "owned_marks:2:activation-two-to-eight-targets"
## Trusted, host-owned extension example. State is a versioned plain value.
static func initial_state() -> Dictionary:
	return {"version": 1, "detonations": 0}

static func valid(state: Dictionary) -> bool:
	return state.size() == 2 and state.get("version") is int and state.version == 1 and state.get("detonations") is int and state.detonations >= 0

static func candidates(world: RefCounted, event: Dictionary) -> Array[int]:
	var result: Array[int] = []
	# This activation's marks only; no global cross-player or old-cast detonation.
	for id: int in world.effects.records.keys():
		var entry: Dictionary = world.effects.records[id]
		if entry.source != event.actor or entry.activation != event.activation or entry.kind != "mark" or result.has(entry.target): continue
		if result.size() >= 8: break
		result.append(entry.target)
	return result

static func targets(world: RefCounted, event: Dictionary, state: Dictionary) -> Array[int]:
	var result: Array[int] = candidates(world, event)
	if result.size() < 2: return []
	for id: int in world.effects.records.keys():
		var entry: Dictionary = world.effects.records[id]
		if entry.source != event.actor or entry.activation != event.activation or entry.kind != "mark" or not result.has(entry.target): continue
		world.effects.remove(world, id, "consumed", event.at_ms)
	state.detonations += 1
	return result
