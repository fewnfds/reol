class_name EnvironmentFieldComputeRuntime
extends RefCounted
## Optional one-request scheduler for the existing disposable field cache.
## All methods except GPUWorker.run are called on the cache's owner thread.
## The worker receives only an immutable snapshot; it never touches the cache,
## this service, an entity, a scene or the shared world clock.
##
## The owner must retain this service while busy and poll until it returns a
## terminal result, including after cancellation. close() never blocks or joins
## a live thread. Dropping the last reference without reaping is unsupported.

const Cache = preload("res://scripts/sim/environment_field_cache.gd")
const AUTO_GPU_MIN_CELLS: int = 4096 # Candidate crossover; not a measured universal threshold.
const MAX_GPU_AREA_AXIS: int = 512 # Larger requests remain on the bounded CPU path.
const MAX_TICKET: int = 9007199254740991
const MODES: Array[String] = ["auto", "cpu", "gpu"]

var _cache: RefCounted
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
var _thread: Thread
var _job: Dictionary = {}


func configure(cache: RefCounted, mode: String = "auto") -> bool:
	if _cache != null or _state != "idle" or mode not in MODES or not is_instance_valid(cache) or not is_instance_of(cache, Cache):
		return false
	var info: Dictionary = cache.diagnostics()
	if int(info.get("capacity", 0)) <= 0:
		return false
	_cache = cache
	_mode = mode
	return true


func set_mode(mode: String) -> bool:
	if _cache == null or _state != "idle" or mode not in MODES:
		return false
	_mode = mode
	return true


func request(area: Rect2i) -> Dictionary:
	if _cache == null:
		return _failure("not_configured")
	if _state != "idle":
		return _failure("busy")
	if _ticket_counter >= MAX_TICKET:
		return _failure("ticket_exhausted")
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
	_state = "cpu"
	var wants_gpu: bool = _mode == "gpu" or (_mode == "auto" and area.size.x * area.size.y >= AUTO_GPU_MIN_CELLS)
	if wants_gpu:
		if area.size.x > MAX_GPU_AREA_AXIS or area.size.y > MAX_GPU_AREA_AXIS:
			_fallback_reason = "gpu_area_budget"
		elif RenderingServer.get_rendering_device() == null:
			_fallback_reason = "rendering_device_unavailable"
		else:
			var job: Dictionary = _cache.export_compute_job(area, true)
			if not bool(job.get("ok", false)):
				_fallback_reason = "snapshot:" + str(job.get("reason", "unknown"))
			else:
				# The static nested-class Callable is bound only to the detached
				# job, never to self. Exclusive input transfer is respected: the
				# owner does not mutate the job while the worker is alive.
				var worker: Callable = GPUWorker.run.bind(job)
				var thread := Thread.new()
				var error: Error = thread.start(worker)
				if error != OK:
					_fallback_reason = "thread_start:" + str(error)
				else:
					_job = job
					_thread = thread
					_state = "gpu"
	return {"ok": true, "pending": true, "ticket": _ticket, "backend": _state,
		"status": _state + "_pending", "mode": _mode, "area": _area,
		"requested_tiles": _tile_count, "revision": _scan_revision, "fallback_reason": _fallback_reason}


func poll(max_tiles: int = 1, max_work: int = 4096) -> Dictionary:
	if _cache == null:
		return _failure("not_configured")
	if _state == "idle":
		return _failure("idle")
	if max_tiles < 1 or max_work < 1 or max_work > Cache.MAX_WORK:
		return _failure("work_budget")
	if _state == "gpu":
		# Never call wait_to_finish while alive. Cancellation invalidates the
		# ticket but still requires subsequent polling to reap the thread.
		if _thread.is_alive():
			return _pending("cancelling" if _cancelled else "gpu_pending", 0, 0, 0)
		var result: Variant = _thread.wait_to_finish()
		_thread = null
		if _cancelled:
			return _finish_cancelled()
		if not result is Dictionary or not bool(result.get("ok", false)):
			var reason: String = "worker_result" if not result is Dictionary else str(result.get("reason", "worker_error"))
			return _fallback("gpu:" + reason)
		var prepared: Dictionary = result.get("prepared", {})
		var published: Dictionary = _cache.publish_compute_result(_job, prepared)
		if not bool(published.get("ok", false)):
			# In particular compute_stale/compute_owner never expose the worker
			# buffer. Existing pending cache work is retained for later CPU polls.
			return _fallback("publish:" + str(published.get("reason", "unknown")))
		var completed: Dictionary = {"ok": true, "pending": false, "cancelled": false,
			"ticket": _ticket, "backend": "gpu", "status": "complete", "area": _area,
			"revision": int(published.revision), "published_tiles": int(published.published_tiles),
			"pending_tiles": int(published.pending_tiles), "work": 0, "completed": 0,
			"fallback_reason": "", "gpu": result.get("metrics", {})}
		_reset_request()
		return completed
	if _cancelled:
		return _finish_cancelled()
	var prior_revision: int = int(_cache.diagnostics().revision)
	if prior_revision != _scan_revision:
		_scan_revision = prior_revision
		_scan_index = 0
	var built: Dictionary = _cache.rebuild(max_tiles, max_work)
	if not bool(built.get("ok", false)):
		return built
	var revision: int = int(built.revision)
	if revision != _scan_revision:
		_scan_revision = revision
		_scan_index = 0
	# Only inspect up to max_tiles area tiles per poll. If an earlier tile is
	# still pending, keep its cursor until the real global queue catches up.
	var checked: int = 0
	while _scan_index < _tile_count and checked < max_tiles:
		@warning_ignore("integer_division")
		var cell: Vector2i = _area.position + Vector2i((_scan_index % _tile_columns) * Cache.TILE_SIZE, (_scan_index / _tile_columns) * Cache.TILE_SIZE)
		var value: Dictionary = _cache.read_base(cell)
		if not bool(value.get("ok", false)):
			return value
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
		"pending_tiles": int(built.pending_tiles), "fallback_reason": _fallback_reason}
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
		"fallback_reason": _fallback_reason, "scan_index": _scan_index}


func close() -> bool:
	if _state != "idle":
		return false
	_cache = null
	_mode = "auto"
	return true


func _pending(status: String, completed: int, work: int, checked: int) -> Dictionary:
	return {"ok": true, "pending": true, "cancelled": _cancelled, "ticket": _ticket,
		"backend": _state, "status": status, "area": _area, "revision": _scan_revision,
		"completed": completed, "work": work, "checked_tiles": checked,
		"requested_tiles": _tile_count, "fallback_reason": _fallback_reason}


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


func _reset_request() -> void:
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


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


class GPUWorker:
	# This class and method are static so the thread's Callable cannot retain
	# the scheduler instance or access a live cache through an instance field.
	const GPU = preload("res://scripts/runtime/environment_field_gpu.gd")
	const WorkerCache = preload("res://scripts/sim/environment_field_cache.gd")

	static func run(job: Dictionary) -> Dictionary:
		var device := GPU.new()
		var initialized: Dictionary = device.initialize()
		if not bool(initialized.get("ok", false)):
			device.close()
			return {"ok": false, "reason": "initialize:" + str(initialized.get("reason", "unknown"))}
		var computed: Dictionary = device.compute(job)
		device.close()
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
