class_name ReolPlayerCommandBuffer
extends RefCounted
## Host input waiting for admission, not accepted simulation work or save data.
## At most one intent of each kind. Stop supersedes all older waiting intents.

signal finished(id: int, kind: String, result: Dictionary)

const LIFETIME_MS: Dictionary = {"sidestep": 300, "travel": 1500, "cancel": 1500}
var _items: Array[Dictionary] = []
var _serial: int = 0


func enqueue(kind: String, args: Dictionary, context: String, now_ms: int) -> int:
	if not LIFETIME_MS.has(kind):
		return 0
	supersede(kind)
	_serial += 1
	_items.append({"id": _serial, "kind": kind, "args": args.duplicate(true),
		"context": context, "expires_ms": now_ms + int(LIFETIME_MS[kind])})
	return _serial


func supersede(kind: String) -> void:
	for index: int in range(_items.size() - 1, -1, -1):
		if kind == "cancel" or _items[index].kind == kind:
			var previous: Dictionary = _items.pop_at(index)
			complete(previous, {"ok": false, "reason": "superseded"})


func expire(context: String, now_ms: int) -> void:
	for index: int in range(_items.size() - 1, -1, -1):
		var item: Dictionary = _items[index]
		var reason: String = "context_changed" if item.context != context else ("expired" if now_ms >= int(item.expires_ms) else "")
		if not reason.is_empty():
			_items.remove_at(index)
			complete(item, {"ok": false, "reason": reason})


func pending() -> bool:
	return not _items.is_empty()


func take() -> Dictionary:
	return {} if _items.is_empty() else _items.pop_front()


func complete(item: Dictionary, result: Dictionary) -> void:
	finished.emit(int(item.id), str(item.kind), result)


func clear(reason: String = "context_changed") -> void:
	var previous: Array[Dictionary] = _items
	_items = []
	for item: Dictionary in previous:
		complete(item, {"ok": false, "reason": reason})
