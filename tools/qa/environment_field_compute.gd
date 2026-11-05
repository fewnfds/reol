extends SceneTree
## Native asynchronous integration QA. Run with a real RenderingDevice under
## an external 30-second process guard; headless/Compatibility is a failure.
## The 20-second in-process deadline cancels and polls any active ticket to
## completion before quitting. The external guard handles a stuck GPU driver.

const Cache = preload("res://scripts/sim/environment_field_cache.gd")
const Index = preload("res://scripts/sim/environment_field_index.gd")
const Compute = preload("res://scripts/runtime/environment_field_compute_runtime.gd")
const DEADLINE_MS: int = 20_000
const CHANNELS: int = 7

var _cache: RefCounted
var _oracle: RefCounted
var _service: RefCounted
var _started_ms: int = 0
var _cases: Array[Dictionary] = []
var _case_index: int = -1
var _errors: Array[String] = []
var _verified_cells: int = 0
var _last_ticket: int = 0
var _device: String = ""
var _adapter_type: int = -1
var _adapter_name: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_started_ms = Time.get_ticks_msec()
	if not _check(RenderingServer.get_rendering_device() != null, "native RenderingDevice unavailable; GPU QA cannot pass by falling back to CPU"):
		await _finish()
		return
	_adapter_type = int(RenderingServer.get_video_adapter_type())
	_adapter_name = RenderingServer.get_video_adapter_name()
	if not _check(_adapter_type in [RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, RenderingDevice.DEVICE_TYPE_DISCRETE_GPU] and not _adapter_name.is_empty(), "native hardware GPU unavailable: adapter=%s type=%d" % [_adapter_name, _adapter_type]):
		await _finish()
		return
	if not await _non_square():
		await _finish()
		return
	if not await _compact_windows():
		await _finish()
		return
	if not await _stale_request():
		await _finish()
		return
	if not await _cancel_request():
		await _finish()
		return
	if not await _automatic_and_reopen():
		await _finish()
		return
	_within_deadline()
	await _finish()


func _fixture(size: Vector2i, mode: String) -> bool:
	if not _within_deadline():
		return false
	if _service != null:
		if not _check(not bool(_service.diagnostics().busy) and _service.close(), "previous service did not close while idle"):
			return false
	_cache = Cache.new()
	_oracle = Index.new()
	_service = Compute.new()
	return _check(_cache.configure(size, 12) and _oracle.configure(size, 12) and _service.configure(_cache, mode), "fixture configuration failed")


func _source(slot: int, id: String, cell: Vector2i, radius: int, channels: Array) -> bool:
	var actual: Dictionary = _cache.set_source(slot, cell, radius, channels)
	if not _check(bool(actual.get("ok", false)), "cache source rejected: " + str(actual)):
		return false
	var expected: Dictionary = _oracle.set_source({"id": id, "cell": cell, "radius": radius, "channels": channels})
	return _check(bool(expected.get("ok", false)), "oracle source rejected: " + str(expected))


func _remove(slot: int, id: String) -> bool:
	var actual: Dictionary = _cache.remove_source(slot)
	if not _check(bool(actual.get("ok", false)), "cache source removal failed: " + str(actual)):
		return false
	var expected: Dictionary = _oracle.remove_source(id)
	return _check(bool(expected.get("ok", false)), "oracle source removal failed: " + str(expected))


func _non_square() -> bool:
	if not _fixture(Vector2i(35, 19), "gpu"):
		return false
	var rows: Array = [
		[0, "winner", Vector2i(16, 8), 8, [1_000_000_000, 0, 500_001, 0, 77, 1_000, 0]],
		[1, "second", Vector2i(16, 8), 4, [700_000_000, 123_456, 0, 0, 900_001, 0, 500]],
		[2, "corner", Vector2i(0, 0), 2, [33_333, 0, 0, 0, 0, 0, 999_999_999]],
		[3, "edge", Vector2i(34, 18), 1, [0, 0, 1_000_000_000, 0, 0, 0, 0]],
		[4, "moving_radius", Vector2i(32, 16), 8, [100, 200, 1_000_000, 0, 300, 400, 0]],
		[5, "zero", Vector2i(5, 18), 4, [0, 0, 0, 0, 0, 0, 0]],
	]
	for row: Array in rows:
		if not _source(int(row[0]), str(row[1]), row[2], int(row[3]), row[4]):
			return false
	var whole := Rect2i(0, 0, 35, 19)
	if not await _request_compare("non_square_full", whole, "gpu"):
		return false
	var center: Dictionary = _cache.read_base(Vector2i(16, 8))
	if not _check(not bool(center.get("pending", true)) and int(center.channels[0]) == 1_000_000_000 and int(center.channels[3]) == 0, "maximum strength or all-zero channel was not exercised"):
		return false
	if not await _request_compare("offset_clipped_gpu", Rect2i(32, 16, 3, 3), "gpu"):
		return false
	if not _remove(0, "winner"):
		return false
	if not await _request_compare("winner_removed", whole, "gpu"):
		return false
	var replaced: Dictionary = _cache.read_base(Vector2i(16, 8))
	if not _check(not bool(replaced.get("pending", true)) and int(replaced.channels[0]) == 700_000_000, "the colocated runner-up did not replace the removed winner"):
		return false
	if not _source(1, "second", Vector2i(30, 18), 4, [700_000_000, 123_456, 0, 0, 900_001, 0, 500]):
		return false
	if not _source(4, "moving_radius", Vector2i(32, 16), 2, [100, 200, 1_000_000, 0, 300, 400, 0]):
		return false
	return await _request_compare("moved_source_and_radius", whole, "gpu")


func _compact_windows() -> bool:
	if not _fixture(Vector2i(80, 64), "gpu"):
		return false
	if not _source(0, "left", Vector2i(29, 20), 8, [800_000, 0, 0, 0, 0, 0, 0]):
		return false
	if not _source(1, "right", Vector2i(51, 20), 8, [0, 500_000, 0, 0, 0, 0, 0]):
		return false
	if not _source(2, "colocated", Vector2i(29, 20), 4, [0, 0, 300_000, 0, 0, 0, 0]):
		return false
	if not _source(3, "far", Vector2i(1, 60), 1, [1_000_000, 0, 0, 0, 0, 0, 0]):
		return false
	var window := Rect2i(32, 16, 16, 16)
	var snapshot: Dictionary = _cache.export_compute_job(window, true)
	if not _check(bool(snapshot.get("ok", false)), "compact snapshot failed: " + str(snapshot)):
		return false
	var params: PackedInt32Array = snapshot.compute_params
	if not _check(params.size() == 8 and params[0] < 80 and params[1] < 64 and params[2] < 12, "window did not use the compact source projection"):
		return false
	if not await _request_compare("compact_external_sources", window, "gpu"):
		return false
	var left: Dictionary = _cache.read_base(Vector2i(32, 20))
	var right: Dictionary = _cache.read_base(Vector2i(47, 20))
	if not _check(int(left.channels[0]) > 0 and int(right.channels[1]) > 0, "sources outside the compact output did not affect both edges"):
		return false
	var empty := Rect2i(64, 48, 16, 16)
	var empty_snapshot: Dictionary = _cache.export_compute_job(empty, true)
	if not _check(bool(empty_snapshot.get("ok", false)), "empty compact snapshot failed"):
		return false
	var empty_params: PackedInt32Array = empty_snapshot.compute_params
	if not _check(empty_params.size() == 8 and empty_params[2] == 1 and empty_params[3] == 0, "empty window did not use the inactive compact slot"):
		return false
	return await _request_compare("compact_empty_window", empty, "gpu")


func _stale_request() -> bool:
	if not _fixture(Vector2i(16, 16), "gpu"):
		return false
	if not _source(0, "changing", Vector2i(8, 8), 2, [10_000, 0, 0, 0, 0, 0, 0]):
		return false
	_begin_case("gpu_stale_to_cpu")
	var area := Rect2i(0, 0, 16, 16)
	var started: Dictionary = _service.request(area)
	if not _start_ok(started, "gpu"):
		return false
	var old_revision: int = int(started.revision)
	if not _source(0, "changing", Vector2i(8, 8), 2, [90_000, 0, 0, 0, 0, 0, 0]):
		return false
	var changed_revision: int = int(_cache.diagnostics().revision)
	var before: Dictionary = _cache.read_base(Vector2i(8, 8))
	if not _check(changed_revision > old_revision and bool(before.get("pending", false)), "source mutation did not invalidate the old GPU snapshot"):
		return false
	var finished: Dictionary = await _drain(int(started.ticket), "cpu", true, false, Vector2i(8, 8))
	if finished.is_empty():
		return false
	if not _check(int(finished.get("revision", -1)) == changed_revision and str(finished.get("fallback_reason", "")) == "publish:compute_stale", "CPU fallback did not publish the latest revision"):
		return false
	if not _compare(area):
		return false
	var after: Dictionary = _cache.read_base(Vector2i(8, 8))
	if not _check(not bool(after.get("pending", true)) and int(after.channels[0]) == 90_000, "fallback did not publish the enhanced source"):
		return false
	_cases[_case_index]["requested_backend"] = "gpu"
	_cases[_case_index]["fallback_reason"] = str(finished.fallback_reason)
	_cases[_case_index]["revision"] = changed_revision
	_pass_case("cpu", area)
	return true


func _cancel_request() -> bool:
	if not _fixture(Vector2i(16, 16), "gpu"):
		return false
	if not _source(0, "cancelled", Vector2i(8, 8), 2, [0, 50_000, 0, 0, 0, 0, 0]):
		return false
	_begin_case("gpu_cancel_and_reap")
	var area := Rect2i(0, 0, 16, 16)
	var started: Dictionary = _service.request(area)
	if not _start_ok(started, "gpu"):
		return false
	var queued: int = int(_cache.diagnostics().pending_tiles)
	var cancelled: Dictionary = _service.cancel(int(started.ticket))
	if not _check(bool(cancelled.get("ok", false)) and bool(cancelled.get("pending", false)) and bool(cancelled.get("cancelled", false)) and queued > 0, "immediate GPU cancellation was not accepted with pending work"):
		return false
	var result: Dictionary = await _drain(int(started.ticket), "gpu", false, true)
	if result.is_empty():
		return false
	var cell: Dictionary = _cache.read_base(Vector2i(8, 8))
	if not _check(int(_cache.diagnostics().pending_tiles) == queued and bool(cell.get("pending", false)) and not bool(_service.diagnostics().busy), "cancellation published GPU values, lost backlog, or failed to reap the worker"):
		return false
	_cases[_case_index]["retained_pending_tiles"] = queued
	_pass_case("gpu_cancelled", area)
	if not _check(_service.set_mode("cpu"), "idle service could not change mode after cancellation"):
		return false
	return await _request_compare("cpu_after_cancel", area, "cpu")


func _automatic_and_reopen() -> bool:
	if not _fixture(Vector2i(64, 64), "auto"):
		return false
	if not _source(0, "small", Vector2i(3, 4), 2, [1_000_000, 0, 0, 0, 0, 0, 0]):
		return false
	if not _source(1, "large", Vector2i(50, 50), 4, [0, 200_000, 0, 0, 0, 0, 0]):
		return false
	if not await _request_compare("auto_small_cpu", Rect2i(0, 0, 16, 16), "cpu"):
		return false
	if not await _request_compare("auto_large_gpu", Rect2i(0, 0, 64, 64), "gpu"):
		return false
	var prior_ticket: int = _last_ticket
	if not _check(_service.close() and _service.configure(_cache, "gpu"), "completed service could not close and reopen in explicit GPU mode"):
		return false
	if not await _request_compare("reopened_explicit_small_gpu", Rect2i(0, 0, 16, 16), "gpu"):
		return false
	return _check(_last_ticket > prior_ticket, "reopening recycled an earlier request ticket")


func _request_compare(name: String, area: Rect2i, backend: String) -> bool:
	_begin_case(name)
	if not _within_deadline():
		return false
	var started: Dictionary = _service.request(area)
	if not _start_ok(started, backend):
		return false
	var finished: Dictionary = await _drain(int(started.ticket), backend, false, false)
	if finished.is_empty() or not _compare(area):
		return false
	_pass_case(backend, area)
	return true


func _start_ok(started: Dictionary, backend: String) -> bool:
	if not _check(bool(started.get("ok", false)) and bool(started.get("pending", false)) and str(started.get("backend", "")) == backend and int(started.get("ticket", 0)) > 0 and str(started.get("fallback_reason", "")).is_empty(), "request did not start on " + backend + ": " + str(started)):
		return false
	_last_ticket = int(started.ticket)
	return true


func _drain(ticket: int, backend: String, expect_stale: bool, cancelled: bool, watched_cell: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var saw_stale: bool = false
	while _within_deadline():
		var result: Dictionary = _service.poll(4, 100_000)
		if not _check(bool(result.get("ok", false)) and int(result.get("ticket", -1)) == ticket, "ticket polling failed: " + str(result)):
			return {}
		var status: String = str(result.get("status", ""))
		if status == "cpu_fallback_pending":
			if not _check(expect_stale and str(result.get("fallback_reason", "")) == "publish:compute_stale" and str(result.get("backend", "")) == "cpu", "GPU fell back unexpectedly: " + str(result)):
				return {}
			var watched: Dictionary = _cache.read_base(watched_cell)
			if not _check(bool(watched.get("pending", false)), "stale worker output became visible before CPU fallback"):
				return {}
			saw_stale = true
		if not bool(result.get("pending", true)):
			if not _check(str(result.get("backend", "")) == backend and bool(result.get("cancelled", false)) == cancelled and status == ("cancelled" if cancelled else "complete"), "unexpected terminal backend or status: " + str(result)):
				return {}
			if not _check(not expect_stale or saw_stale, "stale GPU publication was not rejected before CPU completion"):
				return {}
			if not cancelled and backend == "gpu":
				var metrics: Variant = result.get("gpu")
				if not _check(metrics is Dictionary and metrics.has("device") and not str(metrics.device).is_empty() and str(result.get("fallback_reason", "")).is_empty(), "GPU completion did not report its real worker result"):
					return {}
				_device = str(metrics.device)
				_cases[_case_index]["device"] = _device
			return result
		if not expect_stale and not cancelled and str(result.get("backend", "")) != backend:
			_check(false, "worker switched to an unexpected backend: " + str(result))
			return {}
		# GPU completion and cancellation are always polled after yielding a
		# frame; no call waits for a live worker thread.
		await process_frame
	return {}


func _compare(area: Rect2i) -> bool:
	for y: int in range(area.position.y, area.end.y):
		if not _within_deadline():
			return false
		for x: int in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			var actual: Dictionary = _cache.read_base(cell)
			var expected: Dictionary = _oracle.sample_base(cell)
			if not _check(bool(actual.get("ok", false)) and not bool(actual.get("pending", true)) and bool(expected.get("ok", false)) and actual.get("channels") is PackedInt32Array and expected.get("channels") is PackedInt64Array, "field unavailable at " + str(cell)):
				return false
			var a: PackedInt32Array = actual.channels
			var b: PackedInt64Array = expected.channels
			if not _check(a.size() == CHANNELS and b.size() == CHANNELS, "unexpected channel count at " + str(cell)):
				return false
			for channel: int in CHANNELS:
				if a[channel] != b[channel]:
					_check(false, "field mismatch at %s channel %d: %d != %d" % [str(cell), channel, a[channel], b[channel]])
					return false
			_verified_cells += 1
	return true


func _begin_case(name: String) -> void:
	_cases.append({"name": name, "result": "running", "verified_before": _verified_cells})
	_case_index = _cases.size() - 1


func _pass_case(backend: String, area: Rect2i) -> void:
	var row: Dictionary = _cases[_case_index]
	row.result = "passed"
	row["backend"] = backend
	row["area"] = [area.position.x, area.position.y, area.size.x, area.size.y]
	row["verified_cells"] = _verified_cells - int(row.verified_before)
	row.erase("verified_before")


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	var name: String = str(_cases[_case_index].name) if _case_index >= 0 else "setup"
	var detail: String = name + ": " + message
	_errors.append(detail)
	if _case_index >= 0:
		_cases[_case_index].result = "failed"
	printerr("FIELD_COMPUTE_QA_ERROR: ", detail)
	return false


func _within_deadline() -> bool:
	return _check(Time.get_ticks_msec() - _started_ms <= DEADLINE_MS, "20-second monotonic deadline exceeded")


func _finish() -> void:
	# Keep the service alive through a complete cancellation/reap. Once the
	# in-process deadline has fired, continue yielding and polling; an external
	# 30-second guard is responsible for a permanently stuck driver.
	if _service != null:
		var cancellation_requested: bool = false
		while bool(_service.diagnostics().busy):
			var info: Dictionary = _service.diagnostics()
			if not cancellation_requested and not bool(info.get("cancelled", false)):
				_service.cancel(int(info.ticket))
				cancellation_requested = true
			_service.poll(4, 100_000)
			if bool(_service.diagnostics().busy):
				await process_frame
		if not _service.close():
			_check(false, "reaped service could not close")
	var passed: int = 0
	for row: Dictionary in _cases:
		if str(row.result) == "passed":
			passed += 1
	var report: Dictionary = {"result": "passed" if _errors.is_empty() else "failed",
		"case_count": _cases.size(), "cases_passed": passed, "failed": _errors.size(),
		"verified_cells": _verified_cells, "verified_channels": _verified_cells * CHANNELS,
		"device": _device, "adapter": _adapter_name, "adapter_type": _adapter_type,
		"elapsed_ms": Time.get_ticks_msec() - _started_ms,
		"cases": _cases, "errors": _errors}
	print("FIELD_COMPUTE_QA_JSON:", JSON.stringify(report, "", true, true))
	quit(0 if _errors.is_empty() else 1)
