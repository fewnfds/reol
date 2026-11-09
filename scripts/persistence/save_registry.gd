class_name SimSaveRegistry
extends RefCounted
## Explicit data participants; no scene scan, raw object graph or saved script
## path. A candidate owns staged objects until all checks pass and it is adopted.

class Entry extends RefCounted:
	var id: StringName
	var key: StringName
	var factory: Script
	var load_state: Callable
	var prepare: Callable
	var check: Callable
	var bind: Callable
	var scope: Callable
	var strict_scope: bool = false

var _entries: Array[Entry] = []
var error: String = ""


func add(id: StringName, key: StringName, factory: Script, loader: Callable,
	checker: Callable = Callable(), preparer: Callable = Callable(),
	binder: Callable = Callable(), scope: Callable = Callable(), strict_scope: bool = false) -> bool:
	if id == &"" or key == &"" or factory == null or not loader.is_valid():
		return _fail("invalid_participant")
	for entry: Entry in _entries:
		if entry.id == id or entry.key == key:
			return _fail("duplicate_participant:" + String(id))
	var entry := Entry.new()
	entry.id = id
	entry.key = key
	entry.factory = factory
	entry.load_state = loader
	entry.check = checker
	entry.prepare = preparer
	entry.bind = binder
	entry.scope = scope
	entry.strict_scope = strict_scope
	_entries.append(entry)
	return true


func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for entry: Entry in _entries:
		result.append(entry.id)
	return result


func valid_shape(saved: Dictionary) -> bool:
	error = ""
	for entry: Entry in _entries:
		if not saved.get(entry.key) is Dictionary:
			return _fail("missing_data:" + String(entry.key))
	return true


func capture(host: Object) -> Dictionary:
	error = ""
	var result: Dictionary = {}
	for entry: Entry in _entries:
		var owner: Variant = host.get(entry.id)
		if owner == null or not owner.has_method("to_dict"):
			_fail("missing_owner:" + String(entry.id))
			return {}
		var state: Variant = owner.to_dict()
		if not state is Dictionary or state.is_empty():
			_fail("invalid_capture:" + String(entry.id))
			return {}
		result[String(entry.key)] = state
	return result


func stage(saved: Dictionary, context: Dictionary) -> bool:
	context.erase("validated_registry")
	if not valid_shape(saved):
		return false
	var owners: Dictionary = {}
	for entry: Entry in _entries:
		owners[entry.id] = entry.factory.new()
	context["owners"] = owners
	for entry: Entry in _entries:
		if entry.prepare.is_valid() and entry.prepare.call(owners[entry.id], context) != true:
			return _fail("prepare_failed:" + String(entry.id))
	for entry: Entry in _entries:
		if entry.load_state.call(owners[entry.id], saved[entry.key], context) != true:
			return _fail("restore_failed:" + String(entry.id))
	for entry: Entry in _entries:
		if entry.check.is_valid() and entry.check.call(owners[entry.id], context) != true:
			return _fail("validation_failed:" + String(entry.id))
	context["validated_registry"] = self
	return true


func install(host: Object, context: Dictionary) -> bool:
	if context.get("validated_registry") != self:
		return _fail("unvalidated_candidate")
	# Caller has completed candidate/world validation. Install every owner before
	# rebinding so a rebuild never observes a mixture of old and new participants.
	for entry: Entry in _entries:
		host.set(entry.id, context.owners[entry.id])
	for entry: Entry in _entries:
		var owner: RefCounted = context.owners[entry.id]
		if entry.bind.is_valid():
			entry.bind.call(owner, host, context)
		elif owner.has_method("bind_world"):
			owner.bind_world(host)
	context.erase("validated_registry")
	return true


func inventory_scope(saved: Dictionary, region: String, content: RefCounted) -> Dictionary:
	error = ""
	var result: Dictionary = {"containers": {}, "operations": {}, "reservations": {}}
	var protected: Dictionary = {"containers": {}, "operations": {}, "reservations": {}}
	for entry: Entry in _entries:
		if not entry.scope.is_valid():
			continue
		var contribution: Variant = entry.scope.call(saved.get(entry.key), region, content)
		if not contribution is Dictionary:
			_fail("invalid_scope:" + String(entry.id))
			return {}
		for field: String in contribution:
			if field in ["containers", "operations", "reservations"]:
				for id: String in contribution[field]:
					if protected[field].has(id) or entry.strict_scope and result[field].has(id):
						_fail("scope_collision:" + field + ":" + id)
						return {}
					result[field][id] = contribution[field][id]
					if entry.strict_scope:
						protected[field][id] = true
			else:
				result[field] = contribution[field]
	return result


func _fail(reason: String) -> bool:
	error = reason
	return false
