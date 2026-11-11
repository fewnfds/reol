class_name ReolSimulationProfile
extends RefCounted
## Optional diagnostic callbacks can run on the simulation thread. Never wrap
## a worker callback in a Node method. The host drains only these locked totals.
var _mutex := Mutex.new()
var _scopes: Dictionary = {}
var _frame: Dictionary = {}
var _frame_usec: int = 0
var _kernel: WeakRef
var _originals: Dictionary = {}
var _wrappers: Dictionary = {}
var _navigation: Array[Dictionary] = []
var _nav_calls: int = 0
var _nav_usec: int = 0
var _nav_max: int = 0
var _queries: Array = []


func bind_kernel(kernel: SimSettlementKernel) -> void:
	if _kernel != null and _kernel.get_ref() == kernel:
		return
	unwrap_kernel()
	_kernel = weakref(kernel)
	for step: SimSettlementKernel.Step in kernel._plan:
		var id: String = String(step.id)
		_originals[id] = step.callback
		var wrapper: Callable
		match step.mode:
			SimSettlementKernel.CallMode.UNTIMED, SimSettlementKernel.CallMode.CHECKED_UNTIMED:
				wrapper = _untimed.bind(step.callback, id)
			SimSettlementKernel.CallMode.BUDGETED:
				wrapper = _budgeted.bind(step.callback, id)
			_:
				wrapper = _timed.bind(step.callback, id)
		_wrappers[id] = wrapper
		step.callback = wrapper


func unwrap_kernel() -> void:
	var kernel: SimSettlementKernel = _kernel.get_ref() if _kernel != null else null
	if kernel != null:
		for step: SimSettlementKernel.Step in kernel._plan:
			var id: String = String(step.id)
			if _wrappers.has(id) and step.callback == _wrappers[id]:
				step.callback = _originals[id]
	_originals.clear()
	_wrappers.clear()
	_kernel = null


func bind_navigation(owner: RefCounted) -> void:
	var original: Callable = owner.get("_navigation")
	if not original.is_valid():
		return
	var wrapper: Callable = _navigate.bind(original)
	_navigation.append({"owner": weakref(owner), "original": original, "wrapper": wrapper})
	owner.set("_navigation", wrapper)


func unwrap_navigation() -> void:
	for row: Dictionary in _navigation:
		var owner: RefCounted = row.owner.get_ref()
		if owner != null and owner.get("_navigation") == row.wrapper:
			owner.set("_navigation", row.original)
	_navigation.clear()


func drain() -> Dictionary:
	_mutex.lock()
	var result: Dictionary = {"frame": _frame, "frame_usec": _frame_usec}
	_frame = {}
	_frame_usec = 0
	_mutex.unlock()
	return result


func totals() -> Dictionary:
	_mutex.lock()
	var result: Dictionary = {"scopes": _scopes.duplicate(true), "calls": _nav_calls,
		"usec": _nav_usec, "max_usec": _nav_max, "queries": _queries.duplicate()}
	_mutex.unlock()
	return result


func _navigate(from: Vector2i, to: Vector2i, original: Callable) -> Array[Vector2i]:
	var started: int = Time.get_ticks_usec()
	var result: Array[Vector2i] = original.call(from, to)
	var usec: int = Time.get_ticks_usec() - started
	_mutex.lock()
	_nav_calls += 1
	_nav_usec += usec
	_nav_max = maxi(_nav_max, usec)
	if _queries.size() < 4096:
		_queries.append([from.x, from.y, to.x, to.y])
	_mutex.unlock()
	return result


func _timed(at_ms: int, callback: Callable, id: String) -> Variant:
	var started: int = Time.get_ticks_usec()
	var result: Variant = callback.call(at_ms)
	_record(id, Time.get_ticks_usec() - started)
	return result


func _untimed(callback: Callable, id: String) -> Variant:
	var started: int = Time.get_ticks_usec()
	var result: Variant = callback.call()
	_record(id, Time.get_ticks_usec() - started)
	return result


func _budgeted(at_ms: int, budget: int, callback: Callable, id: String) -> Variant:
	var started: int = Time.get_ticks_usec()
	var result: Variant = callback.call(at_ms, budget)
	_record(id, Time.get_ticks_usec() - started)
	return result


func _record(id: String, usec: int) -> void:
	var kernel: SimSettlementKernel = _kernel.get_ref()
	var at_ms: int = kernel.at_ms
	_mutex.lock()
	var row: Dictionary = _scopes.get(id, {"calls": 0, "logical_boundaries": 0, "last_at_ms": -1, "total_usec": 0, "max_usec": 0})
	row.calls += 1
	if int(row.last_at_ms) != at_ms:
		row.logical_boundaries += 1
		row.last_at_ms = at_ms
	row.total_usec += usec
	row.max_usec = maxi(row.max_usec, usec)
	_scopes[id] = row
	_frame[id] = int(_frame.get(id, 0)) + usec
	_frame_usec += usec
	_mutex.unlock()
