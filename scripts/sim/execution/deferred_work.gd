extends RefCounted
## Finite owner work, not a second clock or an arbitrary callback registry.
## Domains retain facts/timers; this rebuildable queue retains service order.
const MinTimeQueue = preload("res://scripts/sim/execution/min_time_queue.gd")
const AGE_MS: int = 500
const STEP_USEC: int = 3000
const STEP_PIECES: int = 24
const STEP_STARTS: int = 2
var ready: Dictionary = {} # One item per domain and actor. Mutate through this owner.
var jobs: Dictionary = {}
var retired: Array[Dictionary] = []
var submitted: int = 0
var finished: int = 0
var cancelled: int = 0
var background_started: int = 0
var background_finished: int = 0
var maximum_wait_ms: int = 0
var maximum_piece_usec: int = 0
var work_usec: int = 0
var worker_usec: int = 0
var worker_ids: Dictionary = {}
var starts_in_step: int = 0
var next_domain: String = "life"
var _now: int = 0 # Only advances within this live world.
var _future := MinTimeQueue.new()
var _due: Dictionary = {"life": {}, "observe": {}} # Domain -> priority -> earliest original request.

static func key(domain: String, actor: int) -> String:
	return "%s:%d" % [domain, actor]

func request(domain: String, actor: int, at: int, priority: int = 1) -> bool:
	var identity: String = key(domain, actor)
	if jobs.has(identity): return true # Later stimuli stay with the domain, not a duplicate poll item.
	if ready.has(identity):
		var item: Dictionary = ready[identity]
		if at >= int(item.due_ms) and priority >= int(item.priority): return true
		_remove_ready(identity)
		item.due_ms = mini(int(item.due_ms), at)
		item.priority = mini(int(item.priority), priority)
		_enqueue(item)
		return true
	_enqueue({"key": identity, "domain": domain, "actor": actor, "first_ms": at, "due_ms": at, "priority": priority})
	submitted += 1
	return true

func _enqueue(item: Dictionary) -> void:
	ready[item.key] = item
	if int(item.due_ms) > _now:
		_future.set_time(item.key, item.due_ms)
	else:
		_activate(item)

func _activate(item: Dictionary) -> void:
	var priorities: Dictionary = _due[item.domain]
	if not priorities.has(item.priority): priorities[item.priority] = MinTimeQueue.new()
	priorities[item.priority].set_time(item.key, item.first_ms)

func _remove_ready(identity: String) -> void:
	if not ready.has(identity): return
	var item: Dictionary = ready[identity]
	if _future.has(identity): _future.erase(identity)
	else: _due[item.domain][item.priority].erase(identity)
	ready.erase(identity)

func take(now: int, served: Dictionary, paused_domains: Dictionary = {}) -> Dictionary:
	_now = now
	var first: String = _future.first_through(now)
	while not first.is_empty():
		_future.erase(first)
		_activate(ready[first])
		first = _future.first_through(now)
	# Observation supplies inputs to planning. Neither domain may consume the
	# whole owner budget while its own dependency waits in the other domain.
	var other: String = "observe" if next_domain == "life" else "life"
	var best: Dictionary = _best(next_domain, served, paused_domains.has(next_domain))
	if best.is_empty(): best = _best(other, served, paused_domains.has(other))
	if not best.is_empty():
		next_domain = "observe" if best.domain == "life" else "life"
		_remove_ready(best.key)
		maximum_wait_ms = maxi(maximum_wait_ms, now - int(best.first_ms))
	return best

func _best(domain: String, served: Dictionary, paused: bool) -> Dictionary:
	var best: Dictionary = {}
	if paused:
		# Continuations may run while fresh jobs are paused. Only admitted jobs
		# belong to this set and its size is bounded by the worker limit.
		for identity: String in jobs:
			var item: Dictionary = ready.get(identity, {})
			if not item.is_empty() and item.domain == domain and int(item.due_ms) <= _now and _can_take(identity, served) and _before(item, best): best = item
		return best
	for queue: RefCounted in _due[domain].values():
		var first: String = queue.first()
		var skipped: Array[String] = []
		while not first.is_empty() and not _can_take(first, served):
			skipped.append(first)
			queue.erase(first)
			first = queue.first()
		if not first.is_empty() and _before(ready[first], best): best = ready[first]
		for identity: String in skipped: queue.set_time(identity, ready[identity].first_ms)
	return best

func _can_take(identity: String, served: Dictionary) -> bool:
	return int(served.get(identity, 0)) < 4 and not retiring(identity)

func _before(item: Dictionary, best: Dictionary) -> bool:
	if best.is_empty(): return true
	var rank: int = 0 if _now - int(item.first_ms) >= AGE_MS else int(item.priority) + 1
	var best_rank: int = 0 if _now - int(best.first_ms) >= AGE_MS else int(best.priority) + 1
	if rank != best_rank: return rank < best_rank
	if item.first_ms != best.first_ms: return item.first_ms < best.first_ms
	return item.key < best.key

func retiring(identity: String) -> bool:
	for handle: Dictionary in retired:
		if handle.key == identity: return true
	return false

func again(item: Dictionary, due: int) -> void:
	if ready.has(item.key):
		var newer: Dictionary = ready[item.key]
		_remove_ready(item.key)
		item.first_ms = mini(int(item.first_ms), int(newer.first_ms))
		item.priority = mini(int(item.priority), int(newer.priority))
		item.due_ms = mini(due, int(newer.due_ms))
	else: item.due_ms = due
	_enqueue(item)

func capacity(requested: int) -> bool:
	var limit: int = 16 if requested == 0 else maxi(1, mini(2, requested if requested > 0 else OS.get_processor_count() - 2))
	return jobs.size() + retired.size() < limit

func start(identity: String, job: RefCounted, requested: int) -> void:
	assert(not jobs.has(identity) and capacity(requested))
	assert(not retiring(identity))
	var task: int = -1
	if requested != 0:
		# The callable owns only detached job data, never the live World/queue.
		task = WorkerThreadPool.add_task(job.run, false, "Reol personal planning")
		background_started += 1
	jobs[identity] = {"job": job, "task": task, "key": identity, "actor": int(identity.get_slice(":", 1))}
	starts_in_step += 1

func poll(identity: String) -> RefCounted:
	var handle: Dictionary = jobs[identity]
	if handle.task >= 0:
		if not WorkerThreadPool.is_task_completed(handle.task): return null
		WorkerThreadPool.wait_for_task_completion(handle.task)
		background_finished += 1
	else:
		if not handle.job.advance(): return null
	var job: RefCounted = handle.job
	worker_usec += job.work_usec
	worker_ids[job.thread_id] = true
	jobs.erase(identity)
	return job

func cancel(domain: String, actor: int) -> void:
	var identity: String = key(domain, actor)
	_remove_ready(identity)
	if not jobs.has(identity): return
	var handle: Dictionary = jobs[identity]
	jobs.erase(identity)
	if handle.task >= 0: retired.append(handle)
	cancelled += 1

func cancel_actor(actor: int) -> void:
	for domain: String in ["life", "observe"]: cancel(domain, actor)

func collect_retired() -> void:
	for index: int in range(retired.size() - 1, -1, -1):
		var handle: Dictionary = retired[index]
		if not WorkerThreadPool.is_task_completed(handle.task): continue
		WorkerThreadPool.wait_for_task_completion(handle.task)
		background_finished += 1
		retired.remove_at(index)

func close() -> void:
	# Only session teardown waits. Save/publish never waits for a soft proposal.
	for handle: Dictionary in jobs.values():
		if handle.task >= 0: WorkerThreadPool.wait_for_task_completion(handle.task)
	for handle: Dictionary in retired: WorkerThreadPool.wait_for_task_completion(handle.task)
	jobs.clear()
	retired.clear()
	ready.clear()
	_future.clear()
	for priorities: Dictionary in _due.values(): priorities.clear()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# GDScript self-method dispatch is unavailable during RefCounted teardown.
		for handle: Dictionary in jobs.values():
			if handle.task >= 0: WorkerThreadPool.wait_for_task_completion(handle.task)
		for handle: Dictionary in retired: WorkerThreadPool.wait_for_task_completion(handle.task)

func describe() -> Dictionary:
	return {"ready": ready.size(), "running": jobs.size(), "retired": retired.size(), "submitted": submitted, "finished": finished, "cancelled": cancelled,
		"background_started": background_started, "background_finished": background_finished, "maximum_wait_ms": maximum_wait_ms,
		"maximum_piece_usec": maximum_piece_usec, "work_usec": work_usec, "worker_usec": worker_usec, "worker_ids": worker_ids.keys()}
