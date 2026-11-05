class_name SimArtifactTransfers
extends RefCounted
## Live transaction seam, not another object ledger or saved event history.
## Guards are synchronous rule preflights: no mutation, reentry or settlement.
## Observers run only after the owning domain has committed the whole action.

signal committed(change: Dictionary)

var _guard: Callable
## Optional independent guard for a closed environment acceptance session.
## It composes with the existing gameplay guard instead of replacing it.
var _ground_guard: WeakRef
var _checking: bool = false
var checking: bool:
	get: return _checking


func set_guard(guard: Callable) -> void:
	_guard = guard


func bind_ground_guard(guard: RefCounted) -> bool:
	if _checking:
		return false
	var previous: RefCounted = _ground_guard.get_ref() if _ground_guard != null else null
	if guard != null and (not guard.has_method("allows_artifact_transfer") or previous != null and previous != guard):
		return false
	_ground_guard = weakref(guard) if guard != null else null
	return true


func allows(change: Dictionary) -> bool:
	if _checking:
		return false
	_checking = true
	if _ground_guard != null:
		var guardian: RefCounted = _ground_guard.get_ref()
		# A dead weak reference is not permission to proceed. The session owner
		# must explicitly unbind the guard or replace the entire world seam.
		if guardian == null:
			_checking = false
			return false
		var ground_result: Variant = guardian.allows_artifact_transfer(change.duplicate(true))
		if not ground_result is bool or not ground_result:
			_checking = false
			return false
	var result: Variant = _guard.call(change.duplicate(true)) if _guard.is_valid() else _guard.is_null()
	_checking = false
	return result is bool and result


func publish(change: Dictionary) -> void:
	# Signals share their arguments across subscribers. Freeze every nested
	# reference as well so an early observer cannot corrupt later observers.
	var notice: Dictionary = change.duplicate(true)
	for key: String in ["entity", "from", "to"]:
		notice[key].make_read_only()
	notice.make_read_only()
	committed.emit(notice)


static func describe(id: String, item: Dictionary, region: String, container: String, at_ms: int, action: String, cause: String) -> Dictionary:
	return {"entity": {"kind": "artifact", "id": id},
		"from": {"region": str(item.region), "container": str(item.container)},
		"to": {"region": region, "container": container}, "at_ms": at_ms,
		"action": action, "cause": cause}
