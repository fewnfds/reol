extends RefCounted
## Bounded evidence of committed activity outcomes. Never advances or replays work.
const State = preload("res://scripts/sim/kernel/state.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const PER_PERSON: int = 8
const LIMIT: int = 2048
const STATE_FIELDS: Array = ["next_id", "records"]
const STATUSES: Array[String] = ["completed", "refused", "interrupted", "failed"]
var next_id: int = 1
var records: Dictionary = {}
var _by_person: Dictionary = {}
var _references: Dictionary = {}

static func completed(facts: Dictionary = {}, reason: String = "completed") -> Dictionary:
	return {"status": "completed", "reason": reason, "facts": facts}

static func refused(reason: String, facts: Dictionary = {}) -> Dictionary:
	return {"status": "refused", "reason": reason, "facts": facts}

static func interrupted(reason: String, facts: Dictionary = {}) -> Dictionary:
	var status: String = "failed" if reason in ["path_failed", "out_of_reach", "target_gone", "invalid_target", "unavailable", "capability_lost", "actor_dead", "actor_removed"] else "interrupted"
	return {"status": status, "reason": reason, "facts": facts}

func record(run_id: int, operation: String, actor: int, target: int, participants: Array, at: int, outcome: Dictionary) -> Dictionary:
	# Trusted domain producers must obey the same bounded contract as saves.
	# Validate before copying/serializing; an invalid producer is an invariant
	# error, never a silently persisted record that cannot be read back.
	if not _value_fields_valid(run_id, operation, actor, target, participants, at, outcome):
		push_error("Invalid activity result producer: " + operation)
		return {}
	var entry: Dictionary = {"id": next_id, "run_id": run_id, "operation": operation, "actor": actor, "target": target,
		"participants": participants.duplicate(), "at_ms": at, "status": outcome.status, "reason": outcome.reason, "facts": State.copy(outcome.facts)}
	next_id += 1
	records[entry.id] = entry
	_index(entry)
	while records.size() > LIMIT:
		var oldest: int = records.keys()[0]
		for person: int in records[oldest].participants:
			if _by_person.has(person):
				_by_person[person].erase(oldest)
				if _by_person[person].is_empty(): _by_person.erase(person)
		_references.erase(oldest)
		records.erase(oldest)
	return entry

func _index(entry: Dictionary) -> void:
	for person: int in entry.participants:
		if not _by_person.has(person): _by_person[person] = []
		_by_person[person].append(entry.id)
		_references[entry.id] = int(_references.get(entry.id, 0)) + 1
		if _by_person[person].size() > PER_PERSON:
			var old: int = _by_person[person].pop_front()
			_references[old] -= 1
			if _references[old] == 0:
				_references.erase(old)
				records.erase(old)

func view(person: int) -> Array:
	var result: Array = []
	for id: int in _by_person.get(person, []): result.append(State.copy(records[id]))
	return result

func rebuild(world: RefCounted) -> bool:
	if next_id < 1 or records.size() > LIMIT: return false
	_by_person.clear()
	_references.clear()
	var runs: Dictionary = {}
	var previous: int = 0
	for id: Variant in records:
		var entry: Variant = records[id]
		if not id is int or id <= previous or id >= next_id or not entry is Dictionary or entry.size() != 10 or entry.get("id") != id: return false
		previous = id
		if not entry.get("run_id") is int or entry.run_id < 1 or entry.run_id >= world.next_run or runs.has(entry.run_id): return false
		if not entry.get("operation") is String or not Operations.OPERATIONS.has(entry.operation): return false
		if not entry.get("actor") is int or entry.actor <= 0 or entry.actor >= world.objects.next_id or not entry.get("target") is int or entry.target < 0 or entry.target >= world.objects.next_id: return false
		if not entry.get("at_ms") is int or entry.at_ms < 0 or entry.at_ms > world.elapsed_ms or entry.get("status") not in STATUSES or not entry.get("reason") is String or entry.reason.length() > 80 or not entry.reason.is_valid_identifier(): return false
		if not entry.get("participants") is Array or entry.participants.is_empty() or entry.participants.size() > 16 or entry.participants[0] != entry.actor: return false
		var people: Dictionary = {}
		for person: Variant in entry.participants:
			if not person is int or person <= 0 or person >= world.objects.next_id or people.has(person): return false
			people[person] = true
		if not entry.get("facts") is Dictionary or not _facts_valid(entry.facts) or var_to_bytes(entry.facts).size() > 8192: return false
		runs[entry.run_id] = true
	# Active execution and its terminal evidence cannot coexist in a save.
	for actor: int in world.gate.bindings:
		var binding: Dictionary = world.gate.bindings[actor]
		if binding.domain != "combat" and runs.has(binding.run_id): return false
	# Derive retention indexes from immutable chronological records. Rebuilding
	# cannot prune a valid snapshot; stale/orphan records are malformed input.
	var count: int = records.size()
	for id: int in records.keys(): _index(records[id])
	return records.size() == count

static func _value_fields_valid(run_id: int, operation: String, actor: int, target: int, participants: Array, at: int, outcome: Dictionary) -> bool:
	if run_id < 1 or not Operations.OPERATIONS.has(operation) or actor <= 0 or target < 0 or at < 0: return false
	if outcome.get("status") not in STATUSES or not outcome.get("reason") is String or outcome.reason.length() > 80 or not outcome.reason.is_valid_identifier(): return false
	if participants.is_empty() or participants.size() > 16 or participants[0] != actor: return false
	var seen: Dictionary = {}
	for person: Variant in participants:
		if not person is int or person <= 0 or seen.has(person): return false
		seen[person] = true
	return outcome.get("facts") is Dictionary and _facts_valid(outcome.facts) and var_to_bytes(outcome.facts).size() <= 8192

static func _facts_valid(value: Variant) -> bool:
	return _walk_facts(value, 0, [512])

static func _walk_facts(value: Variant, depth: int, budget: Array) -> bool:
	budget[0] -= 1
	if budget[0] < 0: return false
	if depth > 5: return false
	if value is Dictionary:
		if value.size() > 64: return false
		for key: Variant in value:
			if not key is String or key.length() > 80 or not _walk_facts(value[key], depth + 1, budget): return false
		return true
	if value is Array:
		if value.size() > 64: return false
		for child: Variant in value:
			if not _walk_facts(child, depth + 1, budget): return false
		return true
	return (value is int or value is bool or (value is String and value.length() <= 256) or (value is float and is_finite(value)))
