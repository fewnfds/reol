class_name SimArtifactTransfers
extends RefCounted
## Live transaction seam, not another object ledger or saved event history.
## Guards are synchronous rule preflights: no mutation, reentry or settlement.
## Observers run only after the owning domain has committed the whole action.

signal committed(change: Dictionary)

var _guard: Callable
var _checking: bool = false
var checking: bool:
	get: return _checking


func set_guard(guard: Callable) -> void:
	_guard = guard


func allows(change: Dictionary) -> bool:
	if _checking:
		return false
	if not _guard.is_valid():
		return _guard.is_null()
	_checking = true
	var result: Variant = _guard.call(change.duplicate(true))
	_checking = false
	return result is bool and result


func publish(change: Dictionary) -> void:
	committed.emit(change.duplicate(true))


static func describe(id: String, item: Dictionary, region: String, container: String, at_ms: int, action: String, cause: String) -> Dictionary:
	return {"entity": {"kind": "artifact", "id": id},
		"from": {"region": str(item.region), "container": str(item.container)},
		"to": {"region": region, "container": container}, "at_ms": at_ms,
		"action": action, "cause": cause}
