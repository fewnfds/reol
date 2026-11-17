extends RefCounted
## Rules for canonical sparse Objects subrecords; no clock or second identity table.
const Defs = preload("res://scripts/sim/kernel/growth_defs.gd")
const Beings = preload("res://scripts/sim/kernel/being_defs.gd")
const SOURCES: Array[String] = ["scenario", "learn", "study", "practice"]
const APTITUDES: Array[String] = ["physique", "comprehension"]
static var SOURCE_QI_STEPS: Array = _source_qi_steps()

static func _source_qi_steps() -> Array:
	var result: Array = []
	for method: Dictionary in Defs.METHODS.values():
		var cost: int = int(method.source_qi_cost)
		if cost > 0 and cost not in result: result.append(cost)
	result.sort()
	result.make_read_only()
	return result

static func source_qi_band(amount: int) -> int:
	var result: int = 0
	for cost: int in SOURCE_QI_STEPS:
		if amount < cost: break
		result = cost
	return result

static func has_qi_method(record: Dictionary) -> bool:
	for method: String in record.get("methods", {}):
		if introduced(record, method) and int(Defs.METHODS[method].qi_gain) > 0: return true
	return false

static func practice_readiness(actor: Dictionary, method: String) -> String:
	var spec: Dictionary = Defs.METHODS[method]
	if not introduced(actor, method): return "method_not_known"
	if mastered(actor, method):
		if int(spec.qi_gain) <= 0: return "already_mastered"
		if int(actor.get("qi", 0)) >= preload("res://scripts/sim/kernel/resource_pools.gd").QI_MAXIMUM: return "qi_full"
	if actor.get("body_capabilities", {}).get("metabolism", false) and (int(actor.get("energy", 0)) < maxi(800, int(spec.energy_cost)) or int(actor.get("hunger", 0)) < maxi(800, int(spec.satiety_cost))): return "body_not_ready"
	if actor.get("body_capabilities", {}).get("environment", false) and (float(actor.get("temperature", 22.0)) < 0.0 or float(actor.get("temperature", 22.0)) > 50.0): return "body_not_ready"
	return ""

static func aptitude(record: Dictionary, key: String) -> int:
	return int(record.get("aptitudes", {}).get(key, 10))

static func mastered(record: Dictionary, method: String) -> bool:
	return Defs.METHODS.has(method) and int(record.get("methods", {}).get(method, {}).get("progress", -1)) >= int(Defs.METHODS[method].mastery_points)

static func introduced(record: Dictionary, method: String) -> bool:
	return Defs.METHODS.has(method) and (not Defs.METHODS[method].requires_introduction or int(record.get("methods", {}).get(method, {}).get("understanding", 0)) >= int(Defs.METHODS[method].introduction_points))

static func abilities(record: Dictionary) -> Dictionary:
	var result: Dictionary = record.get("abilities", {}).duplicate()
	for method: String in record.get("methods", {}):
		if mastered(record, method):
			for ability: String in Defs.METHODS[method].unlocks: result[ability] = true
	return result # Derived union; explicit scenario grants are independent sources.

static func seed(record: Dictionary, method: String, now: int, fully_mastered: bool = true) -> void:
	assert(Defs.METHODS.has(method))
	if not record.has("methods"): record["methods"] = {}
	assert(not record.methods.has(method))
	record.methods[method] = {"progress": int(Defs.METHODS[method].mastery_points) if fully_mastered else 0, "understanding": int(Defs.METHODS[method].introduction_points),
		"learned_ms": now, "source": "scenario", "teacher": 0, "source_item": ""}

static func advance(record: Dictionary, method: String, points: int, source: String, teacher: int, now: int, item: String = "") -> Dictionary:
	assert(Defs.METHODS.has(method) and points >= 0 and source in SOURCES)
	assert(source != "practice" or introduced(record, method))
	if not record.has("methods"): record["methods"] = {}
	if not record.methods.has(method):
		record.methods[method] = {"progress": 0, "understanding": 0, "learned_ms": now, "source": source, "teacher": teacher, "source_item": item}
	var entry: Dictionary = record.methods[method]
	var channel: String = "understanding" if source in ["learn", "study"] else "progress"
	var previous: int = entry[channel]
	var before: Dictionary = abilities(record)
	var scale: float = clampf(1.0 + (aptitude(record, "comprehension") - 10) * 0.05, 0.5, 1.5)
	for condition: String in record.get("conditions", {}):
		if condition_active(record, condition): scale *= float(Defs.CONDITIONS[condition].learning_scale)
	if channel == "progress" and not Defs.METHODS[method].requires_introduction and entry.understanding >= Defs.METHODS[method].introduction_points: scale *= 1.25
	var ceiling: int = Defs.METHODS[method].introduction_points if channel == "understanding" else Defs.METHODS[method].mastery_points
	entry[channel] = mini(ceiling, previous + roundi(points * scale))
	var unlocked: Array = []
	for ability: String in abilities(record):
		if not before.has(ability): unlocked.append(ability)
	return {"method": method, "channel": channel, "points_gained": entry[channel] - previous, "progress": entry.progress, "understanding": entry.understanding, "mastered": mastered(record, method), "unlocked": unlocked}

static func duration_ms(record: Dictionary, operation: Dictionary, duration: int) -> int:
	var method: String = operation.get("duration_method", "")
	if not method.is_empty() and mastered(record, method): duration = roundi(duration * float(Defs.METHODS[method].mastered_duration_scale))
	return maxi(1, duration)

static func rest_scale(record: Dictionary) -> float:
	return clampf(1.0 + (aptitude(record, "physique") - 10) * 0.05, 0.5, 1.5)

static func condition_active(record: Dictionary, condition: String) -> bool:
	return record.get("conditions", {}).has(condition) and Defs.CONDITIONS.has(condition) and Beings.has(record, Defs.CONDITIONS[condition].required_capability)

static func needs_rest(record: Dictionary) -> bool:
	for condition: String in record.get("conditions", {}):
		if condition_active(record, condition): return true
	return false

static func modify_stats(record: Dictionary, stats: Dictionary) -> Dictionary:
	stats.max_hp = maxf(1, float(stats.max_hp) + (aptitude(record, "physique") - 10) * 5)
	for condition: String in record.get("conditions", {}):
		if condition_active(record, condition): stats.speed *= float(Defs.CONDITIONS[condition].speed_scale)
	return stats

static func apply_condition(record: Dictionary, condition: String, cause: String, now: int) -> bool:
	if not Defs.CONDITIONS.has(condition) or cause not in Defs.CONDITIONS[condition].causes or not Beings.has(record, Defs.CONDITIONS[condition].required_capability): return false
	if not record.has("conditions"): record["conditions"] = {}
	if record.conditions.has(condition):
		record.conditions[condition].recovery = 0 # Renewed actual injury undoes recovery.
		record.conditions[condition].cause = cause # Most recent injury; since_ms preserves onset.
		return false # No derived magnitude changed.
	record.conditions[condition] = {"since_ms": now, "cause": cause, "recovery": 0}
	return true

static func recover_rest(record: Dictionary) -> Dictionary:
	var facts: Dictionary = {}
	for condition: String in record.get("conditions", {}).keys():
		if not condition_active(record, condition): continue
		var entry: Dictionary = record.conditions[condition]
		var spec: Dictionary = Defs.CONDITIONS[condition]
		var recovered: int = mini(int(spec.recovery_needed) - int(entry.recovery), roundi(int(spec.rest_recovery) * rest_scale(record)))
		entry.recovery += recovered
		facts[condition] = recovered
		if entry.recovery >= spec.recovery_needed: record.conditions.erase(condition)
	return facts

static func valid_record(record: Dictionary, next_id: int, now: int) -> bool:
	if not Defs.ERRORS.is_empty() or record.has("practice"): return false
	if record.has("qi_carry") and record.kind != "plant": return false
	if record.has("qi"):
		if record.kind not in ["actor", "plant"] or not record.qi is int or record.qi < 0: return false
		# Nature owns each species' reservoir capacity and fractional state.
		if record.kind == "actor" and record.qi > preload("res://scripts/sim/kernel/resource_pools.gd").QI_MAXIMUM: return false
	if record.has("aptitudes"):
		if record.kind != "actor" or not record.aptitudes is Dictionary: return false
		for key: Variant in record.aptitudes:
			if key not in APTITUDES or not record.aptitudes[key] is int or record.aptitudes[key] < 1 or record.aptitudes[key] > 30: return false
	var methods: Variant = record.get("methods", {})
	if not methods is Dictionary or methods.size() > Defs.METHODS.size(): return false
	for method: Variant in methods:
		var entry: Variant = methods[method]
		if not method is String or not Defs.METHODS.has(method) or not entry is Dictionary or entry.size() != 6: return false
		if not entry.get("progress") is int or entry.progress < 0 or entry.progress > Defs.METHODS[method].mastery_points: return false
		if not entry.get("understanding") is int or entry.understanding < 0 or entry.understanding > Defs.METHODS[method].introduction_points: return false
		if entry.progress > 0 and Defs.METHODS[method].requires_introduction and entry.understanding < Defs.METHODS[method].introduction_points: return false
		if not entry.get("learned_ms") is int or entry.learned_ms < 0 or entry.learned_ms > now or entry.get("source") not in SOURCES: return false
		if Defs.METHODS[method].requires_introduction and entry.source == "practice": return false
		if not entry.get("teacher") is int or entry.teacher < 0 or entry.teacher >= next_id or entry.teacher == record.id: return false
		if not entry.get("source_item") is String or (entry.source_item != "" and not preload("res://scripts/sim/kernel/items.gd").valid(entry.source_item)): return false
		if (entry.source == "learn") != (entry.teacher > 0) or (entry.source == "study") != (entry.source_item != ""): return false
		if entry.source == "study" and entry.source_item != Defs.METHODS[method].study_item: return false
	var grants: Variant = record.get("abilities", {})
	if not grants is Dictionary or grants.size() > 64: return false
	for ability: Variant in grants:
		if not ability is String or not ability.is_valid_identifier() or not grants[ability] is bool or not grants[ability]: return false
	var conditions: Variant = record.get("conditions", {})
	if not conditions is Dictionary or conditions.size() > Defs.CONDITIONS.size() or (not conditions.is_empty() and record.kind != "actor"): return false
	for condition: Variant in conditions:
		var entry: Variant = conditions[condition]
		if not condition is String or not Defs.CONDITIONS.has(condition) or not entry is Dictionary or entry.size() != 3: return false
		if not entry.get("since_ms") is int or entry.since_ms < 0 or entry.since_ms > now or entry.get("cause") not in Defs.CONDITIONS[condition].causes: return false
		if not entry.get("recovery") is int or entry.recovery < 0 or entry.recovery >= Defs.CONDITIONS[condition].recovery_needed: return false
	return true
