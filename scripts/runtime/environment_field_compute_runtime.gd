class_name EnvironmentFieldComputeRuntime
extends RefCounted
## One source-candidate CPU/GPU request over an immutable compact field job.
## The original field validates and adopts results, or resumes its CPU path.
## All service methods run on the owner thread; only GPUWorker owns the device.
## Retain a busy service until cancellation is reaped. Only application teardown
## may join an in-flight worker; normal close accepts an idle service only.

const Cache = preload("res://scripts/sim/environment_field_cache.gd")
const AUTO_SOURCE_GPU_MIN_CELLS: int = 256
const MAX_GPU_AREA_AXIS: int = 512
const MAX_TICKET: int = 9007199254740991
const MODES: Array[String] = ["auto", "cpu", "gpu"]

var _cache: RefCounted
var _mode: String = "auto"
var _state: String = "idle"
var _ticket_counter: int = 0
var _ticket: int = 0
var _cancelled: bool = false
var _worker: GPUWorker
var _cpu: SimFieldCompute
var cpu_workers: int = 4
var _cpu_work: Dictionary = {"batches": 0, "parallel_batches": 0, "worker_usec": 0, "elapsed_usec": 0, "prepare_result_usec": 0}
var _job: Dictionary = {}
var _purpose: String = "candidate"
var _candidate_requests: int = 0
var _candidate_completed: int = 0
var _candidate_adopted: int = 0
var _candidate_failures: int = 0
var _candidate_snapshot_usec: int = 0
var _candidate_compute_ms: float = 0.0


func configure(cache: RefCounted, mode: String = "auto") -> bool:
	if _cache != null or _state != "idle" or mode not in MODES or not is_instance_of(cache, Cache):
		return false
	if int(cache.diagnostics().get("capacity", 0)) <= 0:
		return false
	_cache = cache
	_mode = mode
	return true


func request_source_candidate(handle: RefCounted) -> Dictionary:
	if _cache == null or _state != "idle" or _ticket_counter >= MAX_TICKET:
		return _failure("candidate_backend_unavailable")
	var area: Rect2i = _cache.source_compute_area(handle)
	if area.size.x <= 0 or area.size.y <= 0 or area.size.x > MAX_GPU_AREA_AXIS or area.size.y > MAX_GPU_AREA_AXIS:
		return _failure("gpu_area_budget")
	if _mode == "auto" and area.get_area() < AUTO_SOURCE_GPU_MIN_CELLS:
		return _failure("candidate_below_crossover")
	var started: int = Time.get_ticks_usec()
	var job: Dictionary = _cache.export_source_compute_job(handle)
	if not bool(job.get("ok", false)):
		return job
	if _mode == "cpu" or RenderingServer.get_rendering_device() == null:
		_cpu = SimFieldCompute.new()
		_cpu.start(job, cpu_workers)
		_state = "cpu"
	else:
		if _worker == null:
			_worker = GPUWorker.new()
		var error: Error = _worker.submit(job)
		if error != OK:
			return _failure("thread_start:" + str(error))
		_state = "gpu"
	_ticket_counter += 1
	_ticket = _ticket_counter
	_job = job
	_purpose = "candidate"
	_candidate_requests += 1
	_candidate_snapshot_usec += Time.get_ticks_usec() - started
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
	# A live candidate is exclusively polled by its settlement cursor.
	if _state != "idle" and (_purpose == "warmup" or _cancelled):
		poll()


func wait_for_completion() -> bool:
	# Simulation coordinator only. The host never calls this; it continues
	# drawing the last publication. Wait on the actual dependency, not a timer.
	if _state == "cpu":
		_cpu.execution.finish(true)
		return true
	if _state == "gpu":
		_worker.wait_for_completion()
		return true
	return false


func poll() -> Dictionary:
	if _cache == null:
		return _failure("not_configured")
	if _state == "idle":
		return _failure("idle")
	if _state == "cpu":
		var result: Dictionary = _cpu.collect()
		if bool(result.get("pending", false)):
			return {"ok": true, "pending": true, "ticket": _ticket}
		_cpu_work.batches += 1
		_cpu_work.parallel_batches += int(_cpu.work.parallel)
		for key: String in ["worker_usec", "elapsed_usec", "prepare_result_usec"]:
			_cpu_work[key] += int(_cpu.work[key])
		var completed: Dictionary = {"ok": bool(result.ok), "pending": false, "ticket": _ticket,
			"cancelled": _cancelled, "job": _job, "prepared": result.prepared, "cpu": result.metrics}
		if not _cancelled:
			_candidate_completed += int(result.ok)
			_candidate_failures += int(not bool(result.ok))
		_reset_request()
		return completed
	if not _worker.ready():
		return {"ok": true, "pending": true, "ticket": _ticket,
			"status": "cancelling" if _cancelled else "gpu_pending"}
	var result: Dictionary = _worker.take_result()
	if _cancelled:
		var cancelled: Dictionary = {"ok": true, "pending": false, "cancelled": true, "ticket": _ticket}
		_reset_request()
		return cancelled
	if _purpose == "warmup":
		_reset_request()
		return {"ok": bool(result.get("ok", false)), "pending": false}
	var completed: Dictionary = {"ok": bool(result.get("ok", false)), "pending": false,
		"ticket": _ticket, "job": _job, "prepared": result.get("prepared", {}),
		"gpu": result.get("metrics", {}), "reason": result.get("reason", "")}
	if bool(completed.ok):
		_candidate_completed += 1
		_candidate_compute_ms += float(completed.gpu.get("compute_ms", 0.0))
	else:
		_candidate_failures += 1
	_reset_request()
	return completed


func cancel(ticket: int) -> Dictionary:
	if _cache == null:
		return _failure("not_configured")
	if _state == "idle":
		return _failure("idle")
	if ticket != _ticket:
		return _failure("ticket_mismatch")
	# Finish the immutable worker input, then discard its result. World state
	# and the field's pending CPU work are never cancelled by this service.
	_cancelled = true
	return {"ok": true, "ticket": _ticket, "pending": true, "cancelled": true, "status": "cancelling"}


func diagnostics() -> Dictionary:
	return {"configured": _cache != null, "mode": _mode, "busy": _state != "idle",
		"backend": _state, "ticket": _ticket, "cancelled": _cancelled, "purpose": _purpose,
		"candidate_requests": _candidate_requests, "candidate_completed": _candidate_completed,
		"candidate_adopted": _candidate_adopted, "candidate_failures": _candidate_failures,
		"candidate_snapshot_usec": _candidate_snapshot_usec, "candidate_compute_ms": _candidate_compute_ms,
		"cpu": _cpu_work.duplicate()}


func close() -> bool:
	if _state != "idle":
		return false
	if _worker != null:
		_worker.close_idle()
		_worker = null
	_cache = null
	_mode = "auto"
	return true


func shutdown() -> void:
	# Application teardown only: no world can consume this service afterwards.
	if _cpu != null:
		_cpu.execution.cancel()
		_cpu.execution.finish(true)
	if _worker != null:
		_worker.close_idle()
		_worker = null
	_reset_request()
	close()


func _reset_request() -> void:
	_cpu = null
	_purpose = "candidate"
	_state = "idle"
	_ticket = 0
	_cancelled = false
	_job = {}


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


class GPUWorker:
	extends RefCounted
	const GPU = preload("res://scripts/runtime/environment_field_gpu.gd")
	const WorkerCache = preload("res://scripts/sim/environment_field_cache.gd")
	var _thread: Thread
	var _mutex := Mutex.new()
	var _wake := Semaphore.new()
	var _done := Semaphore.new()
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
		_done.try_wait()
		if result.is_empty():
			# A script error can end the thread before a normal reply. Reap it,
			# let the caller fall back, and allow a later request to restart.
			if _thread != null and not _thread.is_alive():
				_thread.wait_to_finish()
				_thread = null
			return {"ok": false, "reason": "worker_ended_without_result"}
		return result


	func wait_for_completion() -> void:
		if not ready():
			_done.wait()

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
			_done.post()
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
