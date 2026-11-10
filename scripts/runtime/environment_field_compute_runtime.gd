class_name EnvironmentFieldComputeRuntime
extends RefCounted
## Optional one-request scheduler for a disposable field cache or the guarded
## projection of original ground objects. The ground cache remains the owner
## of the projection and validates every snapshot and publication.
## All service methods are called on the cache's owner thread.
## The worker receives only an immutable snapshot; it never touches the cache,
## this service, an entity, a scene or the shared world clock.
##
## The owner must retain this service while busy and poll until it returns a
## terminal result, including after cancellation, then close it when retired.
## The worker/device persist between requests. close() only accepts idle state;
## it wakes and joins that idle worker for resource teardown, never in-flight math.

const Cache = preload("res://scripts/sim/environment_field_cache.gd")
const GroundCache = preload("res://scripts/sim/environment_ground_cache.gd")
const AUTO_GPU_MIN_CELLS: int = 4096 # Candidate crossover; not a measured universal threshold.
const AUTO_SOURCE_GPU_MIN_CELLS: int = 256 # Warm, clean source candidates; see ordinary-world measurements.
const MAX_GPU_AREA_AXIS: int = 512 # Larger requests remain on the bounded CPU path.
const MAX_TICKET: int = 9007199254740991
const MODES: Array[String] = ["auto", "cpu", "gpu"]

var _cache: RefCounted
var _ground: RefCounted
var _mode: String = "auto"
var _state: String = "idle"
var _ticket_counter: int = 0
var _ticket: int = 0
var _area := Rect2i()
var _tile_columns: int = 0
var _tile_count: int = 0
var _scan_index: int = 0
var _scan_revision: int = 0
var _cancelled: bool = false
var _fallback_reason: String = ""
var _worker: GPUWorker
var _job: Dictionary = {}
var _terminal_reason: String = ""
var _request_main_usec: int = 0
var _snapshot_main_usec: int = 0
var _publish_main_usec: int = 0
var _preparation_main_usec: int = 0
var _purpose: String = "cache"
var _candidate_requests: int = 0
var _candidate_completed: int = 0
var _candidate_adopted: int = 0
var _candidate_failures: int = 0
var _candidate_snapshot_usec: int = 0
var _candidate_compute_ms: float = 0.0


func configure(cache: RefCounted, mode: String = "auto") -> bool:
	if _cache != null or _state != "idle" or mode not in MODES or not is_instance_valid(cache):
		return false
	var is_ground: bool = is_instance_of(cache, GroundCache)
	if not is_instance_of(cache, Cache) and not is_ground:
		return false
	var info: Dictionary = cache.diagnostics()
	if int(info.get("capacity", 0)) <= 0:
		return false
	# Only one scheduler may own the ground projection's rebuild queue. Its
	# ordinary advance() continues to sync sources but skips target rebuilding
	# while this lease is held. No runtime dependency is added to the sim layer.
	if is_ground and not bool(cache.acquire_compute_backend(self)):
		return false
	_cache = cache
	_ground = cache if is_ground else null
	_mode = mode
	return true


func set_mode(mode: String) -> bool:
	if _cache == null or _state != "idle" or mode not in MODES or not _owns_ground():
		return false
	_mode = mode
	return true


func request(area: Rect2i) -> Dictionary:
	if _cache == null:
		return _failure("not_configured")
	if _state != "idle":
		return _failure("busy")
	if not _owns_ground():
		return _failure("backend_detached")
	if _ticket_counter >= MAX_TICKET:
		return _failure("ticket_exhausted")
	# Unlike the underlying field cache, the public ground query accepts and
	# clips arbitrary rectangles. This scheduler uses whole tiles throughout;
	# reject before calling it so the request, snapshot and scan agree exactly.
	if _ground != null and not _valid_ground_area(area):
		return _failure("compute_area")
	var request_started: int = Time.get_ticks_usec()
	# request_area validates the complete bounds and tile alignment before it
	# queues any tile. It does not export or copy a full-map GPU snapshot.
	var requested: Dictionary = _cache.request_area(area)
	if not bool(requested.get("ok", false)):
		return requested
	_ticket_counter += 1
	_ticket = _ticket_counter
	_area = area
	@warning_ignore("integer_division")
	_tile_columns = (area.size.x + Cache.TILE_SIZE - 1) / Cache.TILE_SIZE
	_tile_count = int(requested.requested_tiles)
	_scan_index = 0
	_scan_revision = int(requested.revision)
	_cancelled = false
	_fallback_reason = ""
	_terminal_reason = ""
	_request_main_usec = 0
	_snapshot_main_usec = 0
	_publish_main_usec = 0
	_preparation_main_usec = 0
	_state = "cpu"
	var wants_gpu: bool = _mode == "gpu" or (_mode == "auto" and area.size.x * area.size.y >= AUTO_GPU_MIN_CELLS)
	if wants_gpu:
		if area.size.x > MAX_GPU_AREA_AXIS or area.size.y > MAX_GPU_AREA_AXIS:
			_fallback_reason = "gpu_area_budget"
		elif RenderingServer.get_rendering_device() == null:
			_fallback_reason = "rendering_device_unavailable"
		else:
			_start_gpu(true)
	_request_main_usec = Time.get_ticks_usec() - request_started
	return {"ok": true, "pending": true, "ticket": _ticket, "backend": _state,
		"status": _state + "_pending", "mode": _mode, "area": _area,
		"requested_tiles": _tile_count, "revision": _scan_revision, "fallback_reason": _fallback_reason,
		"request_main_usec": _request_main_usec, "snapshot_main_usec": _snapshot_main_usec,
		"preparation_main_usec": _preparation_main_usec}


func request_source_candidate(handle: RefCounted) -> Dictionary:
	if _cache == null or _ground != null or _state != "idle" or _mode == "cpu" or _ticket_counter >= MAX_TICKET:
		return _failure("candidate_backend_unavailable")
	if RenderingServer.get_rendering_device() == null:
		return _failure("rendering_device_unavailable")
	var area: Rect2i = _cache.source_compute_area(handle)
	if area.size.x <= 0 or area.size.y <= 0 or area.size.x > MAX_GPU_AREA_AXIS or area.size.y > MAX_GPU_AREA_AXIS:
		return _failure("gpu_area_budget")
	if _mode == "auto" and area.get_area() < AUTO_SOURCE_GPU_MIN_CELLS:
		return _failure("candidate_below_crossover")
	var started: int = Time.get_ticks_usec()
	var job: Dictionary = _cache.export_source_compute_job(handle)
	if not bool(job.get("ok", false)):
		return job
	if _worker == null:
		_worker = GPUWorker.new()
	var error: Error = _worker.submit(job)
	if error != OK:
		return _failure("thread_start:" + str(error))
	_ticket_counter += 1
	_ticket = _ticket_counter
	_job = job
	_area = area
	_scan_revision = int(job.revision)
	_purpose = "candidate"
	_state = "gpu"
	_candidate_requests += 1
	_snapshot_main_usec = Time.get_ticks_usec() - started
	_candidate_snapshot_usec += _snapshot_main_usec
	return {"ok": true, "pending": true, "ticket": _ticket}


func note_source_adoption() -> void:
	_candidate_adopted += 1


func warmup() -> bool:
	if _cache == null or _state != "idle" or _mode == "cpu" or RenderingServer.get_rendering_device() == null:
		return false
	if _worker == null:
		_worker = GPUWorker.new()
	if _worker.submit({"warmup": true}) != OK:
		return false
	_purpose = "warmup"
	_state = "gpu"
	return true


func maintain() -> void:
	# Only reap warmup or a cancelled request. A live candidate is exclusively
	# polled by its existing settlement cursor.
	if _state == "gpu" and (_purpose == "warmup" or _cancelled):
		poll()


func shutdown() -> void:
	# Application teardown only: no world can consume this service afterwards.
	# The immutable in-flight job may finish before the device is destroyed.
	if _worker != null:
		_worker.close_idle()
		_worker = null
	_reset_request()
	close()


func poll(max_tiles: int = 1, max_work: int = 4096) -> Dictionary:
	if _cache == null:
		return _failure("not_configured")
	if _state == "idle":
		return _failure("idle")
	if max_tiles < 1 or max_work < 1 or max_work > Cache.MAX_WORK:
		return _failure("work_budget")
	# The same ground-cache object may be closed and rebound to a different
	# world. Its old lease must not migrate with it. A live worker still owns
	# its immutable snapshot and must be reaped before reporting terminal failure.
	if not _owns_ground():
		_terminal_reason = "backend_detached"
	if _state == "gpu":
		# The same worker remains alive between requests. Read only a completed
		# mailbox result; GPU synchronization stays on that worker.
		if not _worker.ready():
			var status: String = "gpu_pending"
			if not _terminal_reason.is_empty():
				status = "discarding_detached_backend"
			elif _cancelled:
				status = "cancelling"
			return _pending(status, 0, 0, 0)
		var result: Dictionary = _worker.take_result()
		if not _terminal_reason.is_empty():
			return _finish_failed(_terminal_reason)
		if _cancelled:
			return _finish_cancelled()
		if _purpose == "warmup":
			_reset_request()
			return {"ok": bool(result.get("ok", false)), "pending": false}
		if _purpose == "candidate":
			var candidate_result: Dictionary = {"ok": bool(result.get("ok", false)), "pending": false,
				"ticket": _ticket, "job": _job, "prepared": result.get("prepared", {}),
				"gpu": result.get("metrics", {}), "reason": result.get("reason", "")}
			if bool(candidate_result.ok):
				_candidate_completed += 1
				_candidate_compute_ms += float(candidate_result.gpu.get("compute_ms", 0.0))
			else:
				_candidate_failures += 1
			_reset_request()
			return candidate_result
		if not result is Dictionary or not bool(result.get("ok", false)):
			var reason: String = "worker_result" if not result is Dictionary else str(result.get("reason", "worker_error"))
			return _fallback("gpu:" + reason)
		var prepared: Dictionary = result.get("prepared", {})
		var publish_started: int = Time.get_ticks_usec()
		var published: Dictionary = _cache.publish_compute_result(_job, prepared)
		_publish_main_usec = Time.get_ticks_usec() - publish_started
		if not bool(published.get("ok", false)):
			# In particular compute_stale/compute_owner never expose the worker
			# buffer. Existing pending cache work is retained for later CPU polls.
			return _fallback("publish:" + str(published.get("reason", "unknown")))
		var completed: Dictionary = {"ok": true, "pending": false, "cancelled": false,
			"ticket": _ticket, "backend": "gpu", "status": "complete", "area": _area,
			"revision": int(published.revision), "published_tiles": int(published.published_tiles),
			"pending_tiles": int(published.pending_tiles), "work": 0, "completed": 0,
			"fallback_reason": "", "gpu": result.get("metrics", {}),
			"request_main_usec": _request_main_usec, "snapshot_main_usec": _snapshot_main_usec,
			"publish_main_usec": _publish_main_usec, "preparation_main_usec": _preparation_main_usec}
		_reset_request()
		return completed
	if not _terminal_reason.is_empty():
		return _finish_failed(_terminal_reason)
	if _cancelled:
		return _finish_cancelled()
	if _state == "preparing":
		# A previous attempt saw unsynchronized source projections. A leased
		# ground advance updates only sources, within the normal work/time
		# budget. Never fall through to CPU rebuilding in the same call.
		var preparation_started: int = Time.get_ticks_usec()
		var synced: Dictionary = _ground.advance(max_work, 2000)
		_preparation_main_usec += Time.get_ticks_usec() - preparation_started
		if not bool(synced.get("ok", false)):
			var reason: String = str(synced.get("reason", "source_sync_failed"))
			if reason in ["stale_source", "world_has_backlog"]:
				return _pending("preparing_pending", 0, 0, 0)
			return _finish_failed(reason)
		var work: int = int(synced.get("work_used", 0))
		_scan_revision = int(synced.get("revision", _scan_revision))
		if str(synced.get("state", "")) != "ready" or int(synced.get("pending_sources", 0)) != 0:
			return _pending("preparing_pending", 0, work, 0)
		if not _owns_ground():
			return _finish_failed("backend_detached")
		# One final attempt checks the real owner/context inside export. A new
		# source_pending or any other refusal falls back; it cannot loop here.
		_start_gpu(false)
		if _state == "gpu":
			return _pending("gpu_pending", 0, work, 0)
		return _pending("cpu_fallback_pending", 0, work, 0)
	var prior_revision: int = int(_cache.diagnostics().revision)
	if prior_revision != _scan_revision:
		_scan_revision = prior_revision
		_scan_index = 0
	var built: Dictionary = _cache.rebuild(max_tiles, max_work)
	if not bool(built.get("ok", false)):
		var reason: String = str(built.get("reason", "rebuild_failed"))
		if _ground != null and reason in ["stale_source", "world_has_backlog"]:
			return _pending("source_sync_pending", 0, 0, 0)
		return _finish_failed(reason)
	var revision: int = int(built.revision)
	if revision != _scan_revision:
		_scan_revision = revision
		_scan_index = 0
	# A ground rebuild may need multiple bounded calls to project all pending
	# original changes. Do not scan even previously clean tiles until that
	# queue is synchronized: a late change can invalidate an earlier tile.
	if _ground != null and bool(built.get("pending", false)):
		return _pending("source_sync_pending", int(built.get("completed", 0)), int(built.get("work", 0)), 0)
	# Only inspect up to max_tiles area tiles per poll. If an earlier tile is
	# still pending, keep its cursor until the real global queue catches up.
	var checked: int = 0
	while _scan_index < _tile_count and checked < max_tiles:
		@warning_ignore("integer_division")
		var cell: Vector2i = _area.position + Vector2i((_scan_index % _tile_columns) * Cache.TILE_SIZE, (_scan_index / _tile_columns) * Cache.TILE_SIZE)
		var value: Dictionary = _cache.read_base(cell)
		if not bool(value.get("ok", false)):
			var reason: String = str(value.get("reason", "read_failed"))
			if _ground != null and reason in ["stale_source", "world_has_backlog"]:
				return _pending("source_sync_pending", int(built.completed), int(built.work), checked)
			return _finish_failed(reason)
		checked += 1
		if bool(value.pending):
			break
		_scan_index += 1
	if _scan_index < _tile_count:
		return _pending("cpu_pending", int(built.completed), int(built.work), checked)
	var completed: Dictionary = {"ok": true, "pending": false, "cancelled": false,
		"ticket": _ticket, "backend": "cpu", "status": "complete", "area": _area,
		"revision": revision, "completed": int(built.completed), "work": int(built.work),
		"checked_tiles": checked, "requested_tiles": _tile_count,
		"pending_tiles": int(built.pending_tiles), "fallback_reason": _fallback_reason,
		"request_main_usec": _request_main_usec, "snapshot_main_usec": _snapshot_main_usec,
		"publish_main_usec": _publish_main_usec, "preparation_main_usec": _preparation_main_usec}
	_reset_request()
	return completed


func cancel(ticket: int) -> Dictionary:
	if _cache == null:
		return _failure("not_configured")
	if _state == "idle":
		return _failure("idle")
	if ticket != _ticket:
		return _failure("ticket_mismatch")
	_cancelled = true
	# Neither queued cache tiles nor an in-progress CPU draft are discarded.
	# A running GPU worker is allowed to finish and its result is only dropped.
	return {"ok": true, "ticket": _ticket, "pending": true, "cancelled": true, "status": "cancelling"}


func diagnostics() -> Dictionary:
	return {"configured": _cache != null, "mode": _mode, "busy": _state != "idle",
		"backend": _state, "ticket": _ticket, "cancelled": _cancelled,
		"fallback_reason": _fallback_reason, "scan_index": _scan_index,
		"ground_bound": _ground != null, "ground_lease_valid": _owns_ground(),
		"terminal_reason": _terminal_reason, "request_main_usec": _request_main_usec,
		"snapshot_main_usec": _snapshot_main_usec, "publish_main_usec": _publish_main_usec,
		"preparation_main_usec": _preparation_main_usec, "purpose": _purpose,
		"candidate_requests": _candidate_requests, "candidate_completed": _candidate_completed,
		"candidate_adopted": _candidate_adopted,
		"candidate_failures": _candidate_failures, "candidate_snapshot_usec": _candidate_snapshot_usec,
		"candidate_compute_ms": _candidate_compute_ms}


func close() -> bool:
	if _state != "idle":
		return false
	# A close/rebind may already have invalidated the old lease. In that case
	# never release another scheduler's lease on the newly bound ground cache.
	if _ground != null and _owns_ground() and not bool(_ground.release_compute_backend(self)):
		return false
	if _worker != null:
		_worker.close_idle()
		_worker = null
	_cache = null
	_ground = null
	_mode = "auto"
	return true


func _pending(status: String, completed: int, work: int, checked: int) -> Dictionary:
	return {"ok": true, "pending": true, "cancelled": _cancelled, "ticket": _ticket,
		"backend": _state, "status": status, "area": _area, "revision": _scan_revision,
		"completed": completed, "work": work, "checked_tiles": checked,
		"requested_tiles": _tile_count, "fallback_reason": _fallback_reason,
		"request_main_usec": _request_main_usec, "snapshot_main_usec": _snapshot_main_usec,
		"publish_main_usec": _publish_main_usec, "preparation_main_usec": _preparation_main_usec}


func _start_gpu(allow_preparing: bool) -> void:
	# This runs only on the owner thread. A ground export checks the world,
	# binding and source epochs before it hands out a detached projection.
	var snapshot_started: int = Time.get_ticks_usec()
	var job: Dictionary = _cache.export_compute_job(_area, true)
	_snapshot_main_usec += Time.get_ticks_usec() - snapshot_started
	if not bool(job.get("ok", false)):
		var reason: String = str(job.get("reason", "unknown"))
		if _ground != null and allow_preparing and reason == "source_pending":
			_state = "preparing"
			return
		_fallback_reason = "snapshot:" + reason
		_state = "cpu"
		return
	# A private mailbox carries only detached jobs/results. Its worker owns the
	# persistent device and never retains this service or any world authority.
	if _worker == null:
		_worker = GPUWorker.new()
	var error: Error = _worker.submit(job)
	if error != OK:
		_fallback_reason = "thread_start:" + str(error)
		_state = "cpu"
		return
	_job = job
	_state = "gpu"


func _fallback(reason: String) -> Dictionary:
	_fallback_reason = reason
	_job = {}
	_state = "cpu"
	_scan_index = 0
	_scan_revision = int(_cache.diagnostics().revision)
	# No CPU rebuild or success is reported in the same poll that rejected GPU
	# output; a subsequent poll must do the bounded work against the live cache.
	return _pending("cpu_fallback_pending", 0, 0, 0)


func _finish_cancelled() -> Dictionary:
	var result: Dictionary = {"ok": true, "pending": false, "cancelled": true,
		"ticket": _ticket, "backend": _state, "status": "cancelled",
		"area": _area, "fallback_reason": _fallback_reason}
	_reset_request()
	return result


func _finish_failed(reason: String) -> Dictionary:
	# A failure is terminal only after any GPU worker has been reaped. The
	# original cache's invalidation and pending work are not discarded here.
	var result: Dictionary = {"ok": false, "pending": false, "cancelled": false,
		"ticket": _ticket, "backend": _state, "status": "failed", "area": _area,
		"reason": reason, "fallback_reason": _fallback_reason,
		"request_main_usec": _request_main_usec, "snapshot_main_usec": _snapshot_main_usec,
		"publish_main_usec": _publish_main_usec, "preparation_main_usec": _preparation_main_usec}
	_reset_request()
	return result


func _reset_request() -> void:
	_purpose = "cache"
	_state = "idle"
	_ticket = 0
	_area = Rect2i()
	_tile_columns = 0
	_tile_count = 0
	_scan_index = 0
	_scan_revision = 0
	_cancelled = false
	_fallback_reason = ""
	_job = {}
	_terminal_reason = ""
	_request_main_usec = 0
	_snapshot_main_usec = 0
	_publish_main_usec = 0
	_preparation_main_usec = 0


func _owns_ground() -> bool:
	return _ground == null or (is_instance_valid(_ground) and bool(_ground.owns_compute_backend(self)))


static func _valid_ground_area(area: Rect2i) -> bool:
	if area.position.x < 0 or area.position.y < 0 or area.size.x <= 0 or area.size.y <= 0:
		return false
	if area.size.x > GroundCache.SIZE or area.size.y > GroundCache.SIZE:
		return false
	if area.position.x > GroundCache.SIZE - area.size.x or area.position.y > GroundCache.SIZE - area.size.y:
		return false
	return area.position.x % Cache.TILE_SIZE == 0 and area.position.y % Cache.TILE_SIZE == 0 \
		and area.size.x % Cache.TILE_SIZE == 0 and area.size.y % Cache.TILE_SIZE == 0


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


class GPUWorker:
	extends RefCounted
	const GPU = preload("res://scripts/runtime/environment_field_gpu.gd")
	const WorkerCache = preload("res://scripts/sim/environment_field_cache.gd")
	var _thread: Thread
	var _mutex := Mutex.new()
	var _wake := Semaphore.new()
	var _job: Dictionary = {}
	var _result: Dictionary = {}
	var _in_flight: bool = false
	var _closing: bool = false

	func submit(job: Dictionary) -> Error:
		_mutex.lock()
		if _in_flight or _closing:
			_mutex.unlock()
			return ERR_BUSY
		_job = job
		_in_flight = true
		_mutex.unlock()
		if _thread == null:
			_thread = Thread.new()
			var error: Error = _thread.start(_run)
			if error != OK:
				_thread = null
				_mutex.lock()
				_job = {}
				_in_flight = false
				_mutex.unlock()
				return error
		_wake.post()
		return OK

	func ready() -> bool:
		_mutex.lock()
		var completed: bool = not _result.is_empty()
		_mutex.unlock()
		return completed or _thread != null and not _thread.is_alive()

	func take_result() -> Dictionary:
		_mutex.lock()
		var result: Dictionary = _result
		_result = {}
		_in_flight = false
		_mutex.unlock()
		if result.is_empty():
			# A script error can end the thread before a normal reply. Reap it,
			# let the caller fall back, and allow a later request to restart.
			if _thread != null and not _thread.is_alive():
				_thread.wait_to_finish()
				_thread = null
			return {"ok": false, "reason": "worker_ended_without_result"}
		return result

	func close_idle() -> void:
		_mutex.lock()
		_closing = true
		_mutex.unlock()
		if _thread != null:
			_wake.post()
			_thread.wait_to_finish()
			_thread = null

	func _run() -> void:
		var device := GPU.new()
		while true:
			_wake.wait()
			_mutex.lock()
			if _closing:
				_mutex.unlock()
				break
			var job: Dictionary = _job
			_job = {}
			_mutex.unlock()
			var result: Dictionary = _compute(device, job)
			_mutex.lock()
			_result = result
			_mutex.unlock()
		device.close()

	static func _compute(device: RefCounted, job: Dictionary) -> Dictionary:
		var initialized: Dictionary = device.initialize()
		if not bool(initialized.get("ok", false)):
			return {"ok": false, "reason": "initialize:" + str(initialized.get("reason", "unknown"))}
		if bool(job.get("warmup", false)):
			return initialized
		var computed: Dictionary = device.compute(job)
		if not bool(computed.get("ok", false)):
			return {"ok": false, "reason": "compute:" + str(computed.get("reason", "unknown"))}
		if not computed.get("values") is PackedInt32Array:
			return {"ok": false, "reason": "compute_values"}
		var prepared: Dictionary = WorkerCache.prepare_compute_result(job, computed.values)
		if not bool(prepared.get("ok", false)):
			return {"ok": false, "reason": "prepare:" + str(prepared.get("reason", "unknown"))}
		return {"ok": true, "prepared": prepared, "metrics": {
			"device": str(computed.get("device", "")), "setup_ms": float(initialized.get("setup_ms", 0.0)),
			"compute_ms": float(computed.get("total_ms", 0.0)), "upload_ms": float(computed.get("upload_ms", 0.0)),
			"readback_ms": float(computed.get("readback_ms", 0.0))}}
