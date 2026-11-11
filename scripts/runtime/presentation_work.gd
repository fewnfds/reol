class_name ReolPresentationWork
extends Node
## Host-only, disposable projections. Never enqueue rule effects or exploration.
## One slot per domain job, not per entity. Callbacks do one bounded chunk and
## return false only when blocked (e.g. the world has no complete boundary).

enum Priority { VISIBLE, BACKGROUND }
const MAX_WORK_USEC: int = 1000
const MAX_ATTEMPTS: int = 8
var budget_provider: Callable
var host_time: Callable = Time.get_ticks_usec
var _pending: Dictionary[StringName, Work] = {}
var _running: bool = false
var _completed: int = 0
var _coalesced: int = 0
var _deferred_frames: int = 0
var _overdue_runs: int = 0
var _max_wait_usec: int = 0

class Work:
	var id: StringName
	var callback: Callable
	var priority: int
	var queued_usec: int
	var due_usec: int


func _ready() -> void:
	# Godot runs this after ordinary process callbacks, regardless of tree order.
	process_priority = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(not _pending.is_empty())


func request(id: StringName, callback: Callable, priority: int, max_delay_ms: int) -> void:
	assert(id != &"" and callback.is_valid() and max_delay_ms >= 0)
	var work := Work.new()
	work.id = id
	work.callback = callback
	work.priority = priority
	work.queued_usec = int(host_time.call())
	work.due_usec = work.queued_usec + max_delay_ms * 1000
	var previous: Work = _pending.get(id)
	if previous != null:
		# Repeated dirty marks replace the projection, never postpone its turn.
		work.queued_usec = previous.queued_usec
		work.due_usec = mini(work.due_usec, previous.due_usec)
		work.priority = mini(work.priority, previous.priority)
		_coalesced += 1
	_pending[id] = work
	set_process(true)


func cancel(id: StringName) -> void:
	_pending.erase(id)
	set_process(not _pending.is_empty())


func clear() -> void:
	_pending.clear()
	set_process(false)


func _process(_delta: float) -> void:
	run_pending(int(budget_provider.call()) if budget_provider.is_valid() else MAX_WORK_USEC)


func run_pending(budget_usec: int) -> void:
	if _running or _pending.is_empty():
		return
	_running = true
	var start: int = int(host_time.call())
	var deadline: int = start + clampi(budget_usec, 0, MAX_WORK_USEC)
	var work: Array[Work] = []
	work.assign(_pending.values())
	work.sort_custom(func(a: Work, b: Work) -> bool:
		var a_due: bool = a.due_usec <= start
		var b_due: bool = b.due_usec <= start
		if a_due != b_due: return a_due
		if not a_due and a.priority != b.priority: return a.priority < b.priority
		if a.due_usec != b.due_usec: return a.due_usec < b.due_usec
		return a.id < b.id)
	var attempts: int = 0
	var forced: bool = false
	for item: Work in work:
		if attempts >= MAX_ATTEMPTS or _pending.get(item.id) != item:
			continue
		if not item.callback.is_valid():
			_pending.erase(item.id)
			continue
		var now: int = int(host_time.call())
		var outside_budget: bool = now >= deadline
		if outside_budget and (forced or now < item.due_usec):
			continue
		attempts += 1
		var completed: bool = item.callback.call()
		if not completed:
			continue # A blocked view must not consume another view's overdue turn.
		_completed += 1
		_max_wait_usec = maxi(_max_wait_usec, now - item.queued_usec)
		if outside_budget:
			forced = true
			_overdue_runs += 1
		# Cancellation/replacement during the callback must survive this result.
		if _pending.get(item.id) == item:
			_pending.erase(item.id)
	if not _pending.is_empty():
		_deferred_frames += 1
	_running = false
	set_process(not _pending.is_empty())


func diagnostics() -> Dictionary:
	return {"scope": "since session adapter setup", "pending": _pending.size(),
		"completed": _completed, "coalesced": _coalesced, "deferred_frames": _deferred_frames,
		"overdue_runs": _overdue_runs, "max_completed_wait_ms": _max_wait_usec / 1000.0}
