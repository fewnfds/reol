class_name SimSettlementKernel
extends RefCounted
## Compiled, deterministic execution over original domain owners. No entity
## values, world clock, business effects or saved action records live here.

enum Status { COMPLETE, PENDING, FAILED }
enum CallMode { TIMED, UNTIMED, CHECKED, CHECKED_UNTIMED, YIELDING, BUDGETED }
const MAX_STEPS: int = 4096
const MAX_TIME: int = 9007199254740991

class Step extends RefCounted:
	var id: StringName
	var phase: StringName
	var callback: Callable
	var mode: int
	var after: Array
	var before: Array

var error: String = ""
var last_work: int = 0
var from_ms: int = 0
var at_ms: int = 0
var _phases: Array[StringName] = []
var _steps: Dictionary = {}
var _plan: Array[Step] = []
var _boundaries: Dictionary = {}
var _boundary_order: Array[StringName] = []
var _frozen: bool = false
var _pending: bool = false
var _executing: bool = false
var _cursor: int = 0
var _failed: bool = false


func _init(phases: Array[StringName] = []) -> void:
	_phases = phases.duplicate()


func add_step(id: StringName, phase: StringName, callback: Callable, mode: int = CallMode.TIMED, after: Array = [], before: Array = []) -> bool:
	if _frozen or _steps.size() >= MAX_STEPS or String(id).is_empty() or _steps.has(id) or not _phases.has(phase) or not callback.is_valid() or mode < CallMode.TIMED or mode > CallMode.BUDGETED:
		return false
	var step := Step.new()
	step.id = id
	step.phase = phase
	step.callback = callback
	step.mode = mode
	step.after = after.duplicate()
	step.before = before.duplicate()
	_steps[id] = step
	return true


func add_boundary(id: StringName, callback: Callable, runtime: bool = false) -> bool:
	if _frozen or String(id).is_empty() or _boundaries.has(id) or not callback.is_valid() or _boundaries.size() >= MAX_STEPS:
		return false
	_boundaries[id] = {"callback": callback, "runtime": runtime}
	return true


func compile() -> bool:
	if _frozen or _phases.is_empty() or _steps.is_empty():
		return false
	var phase_numbers: Dictionary = {}
	for phase: StringName in _phases:
		if String(phase).is_empty() or phase_numbers.has(phase):
			return _invalid("invalid_phases")
		phase_numbers[phase] = phase_numbers.size()
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}
	for id: StringName in _steps:
		incoming[id] = {}
		outgoing[id] = {}
	for id: StringName in _steps:
		var step: Step = _steps[id]
		for dependency: Variant in step.after:
			if not _edge(dependency, id, phase_numbers, incoming, outgoing):
				return _invalid("invalid_dependency:" + String(id))
		for successor: Variant in step.before:
			if not _edge(id, successor, phase_numbers, incoming, outgoing):
				return _invalid("invalid_dependency:" + String(id))
	var candidate: Array[Step] = []
	for phase: StringName in _phases:
		var waiting: Array[StringName] = []
		for id: StringName in _steps:
			if _steps[id].phase == phase:
				waiting.append(id)
		while not waiting.is_empty():
			waiting.sort()
			var chosen: StringName = &""
			for id: StringName in waiting:
				if incoming[id].is_empty():
					chosen = id
					break
			if chosen == &"":
				return _invalid("dependency_cycle:" + String(phase))
			candidate.append(_steps[chosen])
			waiting.erase(chosen)
			for successor: StringName in outgoing[chosen]:
				incoming[successor].erase(chosen)
	_plan = candidate
	_boundary_order.assign(_boundaries.keys())
	_boundary_order.sort()
	_frozen = true
	error = ""
	return true


func _edge(prior: Variant, later: Variant, phases: Dictionary, incoming: Dictionary, outgoing: Dictionary) -> bool:
	if not (prior is String or prior is StringName) or not (later is String or later is StringName):
		return false
	var a := StringName(prior)
	var b := StringName(later)
	if a == b or not _steps.has(a) or not _steps.has(b) or int(phases[_steps[a].phase]) > int(phases[_steps[b].phase]):
		return false
	incoming[b][a] = true
	outgoing[a][b] = true
	return true


func begin(previous_ms: int, next_ms: int) -> bool:
	if not _frozen or _pending or _executing or previous_ms < 0 or next_ms <= previous_ms or next_ms > MAX_TIME:
		return false
	from_ms = previous_ms
	at_ms = next_ms
	_cursor = 0
	_pending = true
	_failed = false
	error = ""
	return true


func resume(work_budget: int) -> int:
	last_work = 0
	if _executing:
		return Status.FAILED
	if _failed:
		return Status.FAILED
	if not _pending:
		return Status.COMPLETE
	_executing = true
	while _cursor < _plan.size() and last_work < maxi(0, work_budget):
		var step: Step = _plan[_cursor]
		if not step.callback.is_valid():
			return _failure("owner_unavailable:" + String(step.id))
		var result: Variant
		match step.mode:
			CallMode.UNTIMED, CallMode.CHECKED_UNTIMED:
				result = step.callback.call()
			CallMode.BUDGETED:
				result = step.callback.call(at_ms, work_budget - last_work)
			_:
				result = step.callback.call(at_ms)
		last_work += 1
		if step.mode == CallMode.BUDGETED:
			# x is actual work (including this invocation), y is Status. A domain
			# retains its own entity cursor and effects; the kernel never replays it.
			if not result is Vector2i or result.x < 1 or result.x > work_budget - last_work + 1 or result.y not in [Status.COMPLETE, Status.PENDING, Status.FAILED]:
				return _failure("invalid_work_receipt:" + String(step.id))
			last_work += result.x - 1
			if result.y == Status.FAILED:
				return _failure("step_failed:" + String(step.id))
			if result.y == Status.PENDING:
				_executing = false
				return Status.PENDING
		elif step.mode >= CallMode.CHECKED and step.mode <= CallMode.YIELDING:
			if not result is bool:
				return _failure("invalid_step_result:" + String(step.id))
			if not result:
				if step.mode != CallMode.YIELDING:
					return _failure("step_failed:" + String(step.id))
				_executing = false
				return Status.PENDING
		_cursor += 1
	_executing = false
	_pending = _cursor < _plan.size()
	return Status.PENDING if _pending else Status.COMPLETE


func next_boundary_ms(limit_ms: int, runtime_only: bool = false) -> int:
	var result: int = limit_ms
	for id: StringName in _boundary_order:
		var entry: Dictionary = _boundaries[id]
		if not runtime_only or bool(entry.runtime):
			result = mini(result, int(entry.callback.call()))
	return result


func is_pending() -> bool:
	return _pending


func is_executing() -> bool:
	return _executing


func has_failed() -> bool:
	return _failed


func contract() -> Dictionary:
	var steps: Array[Dictionary] = []
	for step: Step in _plan:
		steps.append({"id": String(step.id), "phase": String(step.phase), "after": step.after.duplicate(), "before": step.before.duplicate(), "mode": step.mode})
	return {"phases": _phases.duplicate(), "steps": steps, "boundaries": _boundary_order.duplicate(), "compiled": _frozen}


func progress() -> Dictionary:
	return {"pending": _pending, "executing": _executing, "from_ms": from_ms, "at_ms": at_ms, "completed_steps": _cursor, "total_steps": _plan.size(), "step": String(_plan[_cursor].id) if _pending else "", "error": error}


func _invalid(reason: String) -> bool:
	error = reason
	return false


func _failure(reason: String) -> int:
	error = reason
	_failed = true
	_executing = false
	return Status.FAILED
