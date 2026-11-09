class_name SimEventQueue
extends RefCounted
## Persistent, deterministic discrete work. Trusted rules own effects; this
## queue owns requests/receipts and rebuildable deadline/topic indexes only.
## No script paths, Callables, engine timers or observer knowledge enter saves.

enum Condition { READY, WAIT, INVALID }
enum Effect { APPLIED, RETRY, INVALID, FAILED }
const VERSION: int = 1
const NEVER: int = SimInventory.MAX_COUNT
const Shape = preload("res://scripts/sim/avian_schema.gd")
const LIVE: Array[String] = ["pending", "waiting"]
const TERMINAL: Array[String] = ["completed", "cancelled", "invalid", "expired", "failed"]

var clock_ms: int = 0
var records: Dictionary = {}
var _rules: Dictionary = {}
var _index := SimParticipationIndex.new()
var _topics: Dictionary = {}
var _dispatching: bool = false
var _dispatch_ms: int = -1


func register_rule(id: String, condition: Callable, effect: Callable, validate: Callable) -> bool:
	if _dispatching or id.is_empty() or _rules.has(id) or not condition.is_valid() or not effect.is_valid() or not validate.is_valid():
		return false
	_rules[id] = {"condition": condition, "effect": effect, "validate": validate}
	return true


func enqueue(id: String, rule: String, due_ms: int, payload: Dictionary = {}, options: Dictionary = {}) -> bool:
	for field: String in options:
		if field not in ["repeat_ms", "retry_ms", "expires_ms", "topics"]:
			return false
	if not options.get("topics", []) is Array:
		return false
	var request: Dictionary = {"rule": rule, "due_ms": due_ms, "payload": payload.duplicate(true),
		"repeat_ms": options.get("repeat_ms", 0), "retry_ms": options.get("retry_ms", 1),
		"expires_ms": options.get("expires_ms", NEVER), "topics": options.get("topics", []).duplicate()}
	if not _valid_request(request) or id.is_empty():
		return false
	if records.has(id):
		return Shape.same_record(records[id].request, request)
	if due_ms < clock_ms or _dispatching and due_ms <= _dispatch_ms:
		return false # A handler cannot recursively create same-time work.
	var row: Dictionary = {"request": request, "status": "pending", "next_ms": due_ms,
		"count": 0, "last_ms": -1, "reason": ""}
	records[id] = row
	_track(id, row)
	return true


func cancel(id: String, reason: String = "cancelled") -> bool:
	if not records.has(id) or _dispatching:
		return false
	if records[id].status == "cancelled":
		return true
	if records[id].status not in LIVE:
		return false
	_finish(id, "cancelled", reason)
	return true


func notify(topic: String, at_ms: int) -> bool:
	if topic.is_empty() or at_ms < clock_ms or at_ms >= NEVER:
		return false
	# A notification is a wake-up, not a synchronous call into another rule.
	var wake_ms: int = maxi(at_ms, _dispatch_ms + 1) if _dispatching else at_ms
	for id: String in _topics.get(topic, {}):
		var row: Dictionary = records[id]
		if row.status != "waiting":
			continue
		row.status = "pending"
		row.next_ms = mini(wake_ms, int(row.request.expires_ms))
		_index.set_due(&"events", id, int(row.next_ms))
	return true


func receipt(id: String) -> Dictionary:
	return records.get(id, {}).duplicate(true)


func next_boundary_ms() -> int:
	return _index.next_due_ms(&"events", NEVER)


func settle_budgeted(at_ms: int, budget: int) -> Vector2i:
	if _dispatching or at_ms < clock_ms or at_ms >= NEVER or budget < 1:
		return Vector2i(0, SimSettlementKernel.Status.FAILED)
	_dispatching = true
	_dispatch_ms = at_ms
	var used: int = 0
	var failed: bool = false
	while used < budget:
		var due: Array[String] = _index.due_ids(&"events", at_ms, 1)
		if due.is_empty():
			break
		var id: String = due[0]
		var row: Dictionary = records[id]
		_index.cancel_due(&"events", id)
		used += 1
		var request: Dictionary = row.request
		if at_ms > int(request.expires_ms) or row.status == "waiting":
			_finish(id, "expired", "deadline")
			continue
		var context: Dictionary = {"id": id, "at_ms": at_ms, "due_ms": int(row.next_ms), "occurrence": int(row.count)}
		var checked: Variant = _rules[request.rule].condition.call(request.payload.duplicate(true), context.duplicate())
		if not checked is int or checked not in [Condition.READY, Condition.WAIT, Condition.INVALID]:
			_finish(id, "failed", "invalid_condition_result")
			failed = true
			break
		var condition: int = int(checked)
		if condition == Condition.INVALID:
			_finish(id, "invalid", "target_or_condition")
			continue
		if condition == Condition.WAIT:
			if at_ms >= int(request.expires_ms):
				_finish(id, "expired", "deadline")
			else:
				row.status = "waiting"
				row.next_ms = int(request.expires_ms)
				if int(row.next_ms) < NEVER:
					_index.set_due(&"events", id, int(row.next_ms))
			continue
		var effected: Variant = _rules[request.rule].effect.call(request.payload.duplicate(true), context.duplicate())
		var result: int = int(effected) if effected is int else Effect.FAILED
		if result == Effect.APPLIED:
			row.count = int(row.count) + 1
			row.last_ms = at_ms
			if int(request.repeat_ms) > 0 and int(row.next_ms) <= NEVER - int(request.repeat_ms):
				row.next_ms = int(row.next_ms) + int(request.repeat_ms)
				if int(row.next_ms) <= int(request.expires_ms) and int(row.next_ms) < NEVER:
					_index.set_due(&"events", id, int(row.next_ms))
					continue
			_finish(id, "completed", "applied")
		elif result == Effect.RETRY and at_ms < int(request.expires_ms) and at_ms < NEVER - int(request.retry_ms):
			row.next_ms = mini(at_ms + int(request.retry_ms), int(request.expires_ms))
			_index.set_due(&"events", id, int(row.next_ms))
		else:
			_finish(id, "invalid" if result == Effect.INVALID else "expired" if result == Effect.RETRY else "failed", "effect_result")
			if result not in [Effect.INVALID, Effect.RETRY]:
				failed = true
				break
	clock_ms = at_ms
	_dispatching = false
	_dispatch_ms = -1
	return Vector2i(maxi(1, used), SimSettlementKernel.Status.FAILED if failed else SimSettlementKernel.Status.PENDING if next_boundary_ms() <= at_ms else SimSettlementKernel.Status.COMPLETE)


func _finish(id: String, status: String, reason: String) -> void:
	records[id].status = status
	records[id].reason = reason
	_index.set_member(&"events", id, false)
	for topic: String in records[id].request.topics:
		if _topics.has(topic):
			_topics[topic].erase(id)
			if _topics[topic].is_empty():
				_topics.erase(topic)


func _track(id: String, row: Dictionary) -> void:
	if row.status not in LIVE:
		return
	_index.set_member(&"events", id)
	if int(row.next_ms) < NEVER:
		_index.set_due(&"events", id, int(row.next_ms))
	for topic: String in row.request.topics:
		if not _topics.has(topic):
			_topics[topic] = {}
		_topics[topic][id] = true


func _valid_request(value: Variant) -> bool:
	if not Shape.keys(value, ["rule", "due_ms", "payload", "repeat_ms", "retry_ms", "expires_ms", "topics"]) or not _rules.has(value.rule):
		return false
	if not Shape.count(value.due_ms, 0, NEVER - 1) or not Shape.count(value.repeat_ms) or not Shape.count(value.retry_ms, 1) or not Shape.count(value.expires_ms, int(value.due_ms)):
		return false
	if not value.payload is Dictionary or not ReolContentBundle._json_value(value.payload) or not value.topics is Array:
		return false
	var seen: Dictionary = {}
	for topic: Variant in value.topics:
		if not topic is String or topic.is_empty() or seen.has(topic):
			return false
		seen[topic] = true
	return _rules[value.rule].validate.call(value.payload) == true


func to_dict() -> Dictionary:
	return {} if _dispatching else {"version": VERSION, "clock_ms": clock_ms, "records": records.duplicate(true)}


func restore(data: Dictionary) -> bool:
	if _dispatching or not Shape.keys(data, ["version", "clock_ms", "records"]) or data.version != VERSION or not Shape.count(data.clock_ms) or not data.records is Dictionary:
		return false
	for id: Variant in data.records:
		var row: Variant = data.records[id]
		if not id is String or id.is_empty() or not Shape.keys(row, ["request", "status", "next_ms", "count", "last_ms", "reason"]) or not _valid_request(row.request):
			return false
		if row.status not in LIVE and row.status not in TERMINAL or not Shape.count(row.next_ms) or not Shape.count(row.count) or not Shape.count(row.last_ms, -1, int(data.clock_ms)) or not row.reason is String:
			return false
		if (int(row.count) == 0) != (int(row.last_ms) == -1) or int(row.next_ms) < int(row.request.due_ms):
			return false
		if row.status in LIVE and (int(row.next_ms) < int(data.clock_ms) or int(row.next_ms) > int(row.request.expires_ms)):
			return false
		if row.status == "completed" and int(row.count) == 0 or row.status == "waiting" and (int(row.next_ms) != int(row.request.expires_ms) or int(row.count) > 0 and int(row.request.repeat_ms) == 0):
			return false
	clock_ms = int(data.clock_ms)
	records = data.records.duplicate(true)
	for row: Dictionary in records.values():
		for field: String in ["next_ms", "count", "last_ms"]:
			row[field] = int(row[field])
		for field: String in ["due_ms", "repeat_ms", "retry_ms", "expires_ms"]:
			row.request[field] = int(row.request[field])
	_index = SimParticipationIndex.new()
	_topics = {}
	for id: String in records:
		_track(id, records[id])
	return true
