extends RefCounted
## Finite owner work, not a second clock or an arbitrary callback registry.
## Domains retain facts/timers; this rebuildable queue retains service order.
const AGE_MS: int = 500
const STEP_USEC: int = 3000
const STEP_PIECES: int = 24
const STEP_STARTS: int = 2
const MAX_READY: int = 1024
var ready: Dictionary = {}
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

static func key(domain: String, actor: int) -> String:
	return "%s:%d" % [domain, actor]

func request(domain: String, actor: int, at: int, priority: int = 1) -> bool:
	var identity: String = key(domain, actor)
	if jobs.has(identity): return true # Later stimuli stay with the domain, not a duplicate poll item.
	if ready.has(identity):
		ready[identity].due_ms = mini(int(ready[identity].due_ms), at)
		ready[identity].priority = mini(int(ready[identity].priority), priority)
		return true
	if ready.size() >= MAX_READY: return false # The domain's durable due remains.
	ready[identity] = {"key": identity, "domain": domain, "actor": actor, "first_ms": at, "due_ms": at, "priority": priority}
	submitted += 1
	return true

func take(now: int, served: Dictionary, paused_domains: Dictionary = {}) -> Dictionary:
	var candidates: Dictionary = {}
	for item: Dictionary in ready.values():
		if item.due_ms > now or int(served.get(item.key, 0)) >= 4: continue
		if retiring(item.key): continue
		if paused_domains.has(item.domain) and not jobs.has(item.key): continue
		var best: Dictionary = candidates.get(item.domain, {})
		var rank: int = 0 if now - int(item.first_ms) >= AGE_MS else int(item.priority) + 1
		var best_rank: int = 0 if not best.is_empty() and now - int(best.first_ms) >= AGE_MS else int(best.get("priority", 0)) + 1
		if best.is_empty() or rank < best_rank or (rank == best_rank and (item.first_ms < best.first_ms or (item.first_ms == best.first_ms and item.key < best.key))): candidates[item.domain] = item
	# Observation supplies inputs to planning. Neither domain may consume the
	# whole owner budget while its own dependency waits in the other domain.
	var best: Dictionary = candidates.get(next_domain, {})
	if best.is_empty() and not candidates.is_empty(): best = candidates.values()[0]
	if not best.is_empty():
		next_domain = "observe" if best.domain == "life" else "life"
		ready.erase(best.key)
		maximum_wait_ms = maxi(maximum_wait_ms, now - int(best.first_ms))
	return best

func retiring(identity: String) -> bool:
	return retired.any(func(handle: Dictionary): return handle.key == identity)

func again(item: Dictionary, due: int) -> void:
	if ready.has(item.key):
		var newer: Dictionary = ready[item.key]
		item.first_ms = mini(int(item.first_ms), int(newer.first_ms))
		item.priority = mini(int(item.priority), int(newer.priority))
		item.due_ms = mini(due, int(newer.due_ms))
	else: item.due_ms = due
	ready[item.key] = item

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
	ready.erase(identity)
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
