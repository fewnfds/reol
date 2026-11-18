extends RefCounted
## One read-only boundary for ordinary inspection. Complete Frame details stay
## available to developer diagnostics; no UI cache becomes personal knowledge.
const State = preload("res://scripts/sim/kernel/state.gd")

static func visible(frame: RefCounted, id: int, use_fog: bool) -> bool:
	if id == 1: return true
	if frame.actor_slots.has(id): return not use_fog or frame.visible[frame.actor_slots[id]] != 0
	if not use_fog: return frame.objects.has(id)
	for tile: int in frame.perception.get("memories", {}).get(id, {}).get("cells", PackedInt32Array()):
		if frame.perception.tiles[tile] != 0: return true
	return false

static func observed(frame: RefCounted, id: int, use_fog: bool) -> Dictionary:
	if id == 0: return {}
	if id == 1: return frame.player
	if frame.actor_slots.has(id) and frame.inspected_id != id: return {"id": id, "kind": "actor", "pending": true}
	var clue: Dictionary = frame.inspected_clue
	if int(clue.get("view", {}).get("id", 0)) != id: clue = {}
	if visible(frame, id, use_fog):
		var raw: Dictionary = frame.inspected
		if int(raw.get("id", 0)) != id:
			return {"id": id, "kind": "actor" if frame.actor_slots.has(id) else "", "pending": true}
		if raw.get("kind") != "actor": return raw
		return _person(frame, raw, clue, use_fog)
	var old: Dictionary = clue.get("view", {}) if clue.get("view", {}).get("kind") == "actor" else frame.perception.get("memories", {}).get(id, {})
	if old.is_empty(): return {}
	var result: Dictionary = {}
	if old.kind == "actor":
		for field: String in ["id", "kind", "definition", "name", "tile", "hp", "teaches"]:
			if old.has(field): result[field] = State.copy(old[field])
	else: result = State.copy(old)
	result["memory"] = true
	result["seen_ms"] = int(clue.get("seen_ms", 0))
	return result

static func _person(frame: RefCounted, raw: Dictionary, clue: Dictionary, use_fog: bool) -> Dictionary:
	var result: Dictionary = {"observed_other": true}
	for field: String in ["id", "kind", "definition", "name", "sex", "resident_title", "sapient", "position", "equipment", "tile", "at_ms"]:
		if raw.has(field): result[field] = State.copy(raw[field])
	result["hp"] = 1 if int(raw.get("hp", 0)) > 0 else 0
	result["appearance"] = appearance(raw)
	if frame.actor_labels.has(int(raw.id)) and result.hp > 0:
		result["name_relation"] = frame.actor_labels[int(raw.id)].relation
	result["teaches"] = State.copy(clue.get("view", {}).get("teaches", {}))
	result["teaching_refusals"] = State.copy(clue.get("teaching_refusals", {}))
	result["activity"] = _activity(frame, raw, use_fog)
	if int(frame.inspected_social.get("id", 0)) == int(raw.id): result.merge(State.copy(frame.inspected_social))
	# A visible corpse can be searched through the original goods operation.
	if result.hp == 0:
		for field: String in ["inventory", "capacity", "stock_organizations"]:
			if raw.has(field): result[field] = State.copy(raw[field])
	return result

static func _activity(frame: RefCounted, raw: Dictionary, use_fog: bool) -> Dictionary:
	if int(raw.get("hp", 0)) <= 0: return {"phase": "dead"}
	var activity: Dictionary = raw.get("activity", {})
	var phase: String = str(activity.get("phase", ""))
	if phase.is_empty(): return {}
	if phase in ["approaching", "traveling", "exploring"]: return {"phase": phase}
	var result: Dictionary = {"phase": phase}
	var target: int = int(activity.get("target", 0))
	if target == 0 or target == raw.id or visible(frame, target, use_fog):
		for field: String in ["operation", "target", "target_label", "role", "started_ms", "due_ms"]:
			if activity.has(field): result[field] = activity[field]
		if activity.get("reason") in ["awaiting_participant", "target_busy", "occupied"]: result["reason"] = activity.reason
	return result

static func appearance(raw: Dictionary) -> String:
	if int(raw.get("hp", 0)) <= 0: return "已亡故"
	var words := PackedStringArray()
	if int(raw.get("hp", 0)) < int(raw.get("stats", {}).get("max_hp", raw.get("hp", 0))): words.append("带伤")
	if int(raw.get("energy", 10000)) < 3000: words.append("神色疲惫")
	if int(raw.get("hunger", 10000)) < 3000: words.append("显露饥态")
	if float(raw.get("temperature", 22)) < 5 or float(raw.get("temperature", 22)) > 40: words.append("寒热不适")
	return " · ".join(words) if not words.is_empty() else "气色平常"
