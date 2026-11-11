class_name ReolSimulationSignalBridge
extends RefCounted
## During a world ownership loan, external Node observers become mailbox
## records. Domain-to-domain signals stay synchronous on the simulation owner.
## Restore original connections before replay, so normal UI rebinds still work.
var _sources: Array[WeakRef] = []
var _connections: Array[Dictionary] = []
var _notices: Array[Dictionary] = []
var _mutex := Mutex.new()

class Relay extends RefCounted:
	var owner: ReolSimulationSignalBridge
	var index: int
	func zero() -> void:
		owner._record(index, [])
	func one(a: Variant) -> void:
		owner._record(index, [a])
	func two(a: Variant, b: Variant) -> void:
		owner._record(index, [a, b])
	func three(a: Variant, b: Variant, c: Variant) -> void:
		owner._record(index, [a, b, c])


func discover(root: RefCounted) -> void:
	_sources.clear()
	var seen: Dictionary = {}
	var queue: Array[Object] = [root]
	while not queue.is_empty():
		var object: Object = queue.pop_back()
		if not is_instance_valid(object) or object is Node or object is WeakRef or seen.has(object.get_instance_id()):
			continue
		seen[object.get_instance_id()] = true
		if object.get_script() == null:
			continue
		for info: Dictionary in object.get_signal_list():
			# Object's editor notifications occur on every Resource/definition;
			# they are not world events and must not grow each handoff's scan.
			if String(info.name) not in ["script_changed", "property_list_changed"]:
				_sources.append(weakref(object))
				break
		for property: Dictionary in object.get_property_list():
			if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
				continue
			var value: Variant = object.get(property.name)
			if value is RefCounted:
				queue.append(value)
			elif value is Dictionary or value is Array:
				var entries: Array = value.values() if value is Dictionary else value
				for entry: Variant in entries:
					if entry is RefCounted:
						queue.append(entry)


func lend() -> void:
	assert(_connections.is_empty())
	for reference: WeakRef in _sources:
		var source: Object = reference.get_ref()
		if source == null:
			continue
		for signal_info: Dictionary in source.get_signal_list():
			var name: StringName = signal_info.name
			for connection: Dictionary in source.get_signal_connection_list(name):
				var target: Callable = connection.callable
				if not target.get_object() is Node:
					continue
				var index: int = _connections.size()
				var receiver := Relay.new()
				receiver.owner = self
				receiver.index = index
				var relay: Callable
				match signal_info.args.size():
					0: relay = receiver.zero
					1: relay = receiver.one
					2: relay = receiver.two
					3: relay = receiver.three
					_: assert(false, "Add this signal arity to the ownership bridge")
				_connections.append({"source": reference, "signal": name, "target": target, "relay": relay, "receiver": receiver, "flags": int(connection.flags)})
				source.disconnect(name, target)
				# Only the final Node call is deferred to the host. The small relay
				# itself must record synchronously before the owner releases world.
				source.connect(name, relay, int(connection.flags) & ~CONNECT_DEFERRED)


func reclaim(deliver: bool = true) -> void:
	# Called only after the coordinator has released ownership (or joined).
	for row: Dictionary in _connections:
		var source: Object = row.source.get_ref()
		if source == null:
			continue
		var attached: bool = source.is_connected(row.signal, row.relay)
		if attached:
			source.disconnect(row.signal, row.relay)
		if row.target.is_valid() and (attached or (int(row.flags) & CONNECT_ONE_SHOT) == 0) and not source.is_connected(row.signal, row.target):
			source.connect(row.signal, row.target, row.flags)
	_mutex.lock()
	var notices: Array[Dictionary] = _notices
	_notices = []
	_mutex.unlock()
	if deliver:
		for notice: Dictionary in notices:
			var target: Callable = _connections[int(notice.index)].target
			if target.is_valid():
				target.callv(notice.args)
	_connections.clear()


func _record(index: int, args: Array) -> void:
	_mutex.lock()
	_notices.append({"index": index, "args": args.duplicate(true)})
	_mutex.unlock()


