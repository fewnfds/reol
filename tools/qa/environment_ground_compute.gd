extends SceneTree
## Native real-object GPU integration. Use a real RenderingDevice and an
## external process guard. A deadline cancels and reaps before exit; the
## external guard remains responsible for a permanently stuck driver.

const Compute = preload("res://scripts/runtime/environment_field_compute_runtime.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const DEADLINE_MS: int = 60_000
const AREA := Rect2i(0, 0, 32, 32)

var _fixture: RefCounted
var _world: RegionalSimulation
var _ground: RefCounted
var _oracle: RefCounted
var _definitions: RefCounted
var _service: RefCounted
var _errors: Array[String] = []
var _cases: Array[Dictionary] = []
var _started_ms: int = 0
var _verified_cells: int = 0
var _adapter: String = ""
var _device: String = ""
var _clock_ms: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_started_ms = Time.get_ticks_msec()
	# This fixture also loads ordinary scene/runtime fixtures that refer to
	# autoloads. Resolve it after SceneTree initialization, as the test runner
	# does, rather than while this entry script is compiled before autoloads.
	_fixture = load("res://tests/runtime/test_environment_ground_compute.gd").new()
	if not _check(RenderingServer.get_rendering_device() != null, "native RenderingDevice unavailable; CPU fallback is not a GPU pass"):
		await _finish()
		return
	_adapter = RenderingServer.get_video_adapter_name()
	var adapter_type: int = int(RenderingServer.get_video_adapter_type())
	if not _check(not _adapter.is_empty() and adapter_type in [RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, RenderingDevice.DEVICE_TYPE_DISCRETE_GPU], "a hardware GPU is required: %s type=%d" % [_adapter, adapter_type]):
		await _finish()
		return
	var data: Dictionary = _fixture.setup(self)
	if not _check(not data.is_empty(), "the real source fixture was not constructed"):
		await _finish()
		return
	_world = data.world
	_ground = data.ground
	_oracle = data.query
	_definitions = data.definitions
	_clock_ms = _world.elapsed_ms
	_service = Compute.new()
	if not _check(_service.configure(_ground, "gpu"), "scheduler could not bind the real source cache"):
		await _finish()
		return
	if not await _initial_gpu():
		await _finish()
		return
	if not await _stack_gpu():
		await _finish()
		return
	if not await _stale_to_cpu():
		await _finish()
		return
	if not await _cancel_and_reuse():
		await _finish()
		return
	if not await _prepare_after_mutation():
		await _finish()
		return
	if not await _inventory_epoch():
		await _finish()
		return
	if not await _restore_epoch():
		await _finish()
		return
	if not await _rebind_different_world():
		await _finish()
		return
	_check(_world.elapsed_ms == _clock_ms and _world.target_ms == _clock_ms, "environment calculation advanced the real world clock")
	await _finish()


func _initial_gpu() -> bool:
	var start: Dictionary = _begin_gpu("mixed_real_sources")
	if start.is_empty():
		return false
	var finished: Dictionary = await _drain("gpu", false, false)
	if finished.is_empty() or not _compare(AREA):
		return false
	return _pass("mixed_real_sources", finished)


func _stack_gpu() -> bool:
	var before: Dictionary = _ground.read_base(Vector2i(14, 15))
	var operation: Dictionary = _fixture.fixture._transfer("gpu_qa_grow", _fixture.fixture._location("store"), _fixture.fixture._ground(14, 15), "wood", 9999)
	if not _check(bool(_world.object_lifecycle.execute(operation).get("ok", false)), "one wood item did not merge into a ten-thousand-item pile"):
		return false
	if not _check(_world.regions.home.inventory.quantity("ground:compute_hot", "wood") == 10000 and _ground.read_base(Vector2i(14, 15)) == before, "stack growth changed its field or original inventory quantity"):
		return false
	var start: Dictionary = _begin_gpu("same_stack_10000")
	if start.is_empty():
		return false
	var finished: Dictionary = await _drain("gpu", false, false)
	if finished.is_empty() or not _compare(AREA):
		return false
	return _pass("same_stack_10000", finished)


func _stale_to_cpu() -> bool:
	var start: Dictionary = _begin_gpu("move_while_gpu_active")
	if start.is_empty():
		return false
	# A worker may finish while the owner is not polling. Mutate first, then
	# poll, exercising the unsynchronized original-owner publication guard.
	await create_timer(0.25).timeout
	var hold: Dictionary = _fixture.fixture._move("gpu_qa_hold", "compute_edge_item", _fixture.fixture._location("ground:compute_edge"), _fixture.fixture._location("actor:player"))
	var pickup: Dictionary = _fixture.fixture._transfer("gpu_qa_hot_pickup", _fixture.fixture._location("ground:compute_hot"), _fixture.fixture._location("actor:player"), "wood", 10000)
	if not _check(bool(_world.object_lifecycle.execute(hold).get("ok", false)) and bool(_world.object_lifecycle.execute(pickup).get("ok", false)), "real artifact and full pile did not move"):
		return false
	for point: Vector2i in [Vector2i(1, 1), Vector2i(14, 15)]:
		var pending: Dictionary = _ground.read_base(point)
		if not _check(bool(pending.get("pending", false)) and not pending.has("elements"), "an old source value remained visible during mutation at " + str(point)):
			return false
	var finished: Dictionary = await _drain("cpu", true, false)
	if finished.is_empty() or not _compare(AREA):
		return false
	return _pass("move_while_gpu_active", finished)


func _cancel_and_reuse() -> bool:
	var start: Dictionary = _begin_gpu("gpu_cancel")
	if start.is_empty():
		return false
	if not _check(not _service.close(), "close abandoned an active GPU worker"):
		return false
	if not _check(bool(_service.cancel(int(start.ticket)).get("ok", false)), "GPU cancellation was refused"):
		return false
	var cancelled: Dictionary = await _drain("gpu", false, true)
	if cancelled.is_empty() or not _check(not bool(_service.diagnostics().get("busy", true)), "cancelled worker was not reaped"):
		return false
	if not _pass("gpu_cancel", cancelled):
		return false
	var next: Dictionary = _begin_gpu("gpu_after_cancel")
	if next.is_empty():
		return false
	var finished: Dictionary = await _drain("gpu", false, false)
	if finished.is_empty() or not _compare(AREA):
		return false
	return _pass("gpu_after_cancel", finished)


func _prepare_after_mutation() -> bool:
	var remove: Dictionary = {"command": "gpu_qa_remove", "op": "remove", "id": "compute_slab_item", "from": _fixture.fixture._location("ground:compute_slab")}
	if not _check(bool(_world.object_lifecycle.execute(remove).get("ok", false)), "real source removal failed before GPU preparation"):
		return false
	var start: Dictionary = _service.request(AREA)
	if not _check(bool(start.get("ok", false)) and bool(start.get("pending", false)) and str(start.get("backend", "")) == "preparing", "unsynchronized real sources did not start bounded GPU preparation: " + str(start)):
		return false
	var saw_gpu: bool = false
	while _within_deadline():
		var result: Dictionary = _service.poll(4, 100000)
		if not _check(bool(result.get("ok", false)), "source preparation failed: " + str(result)):
			return false
		if str(result.get("backend", "")) == "gpu":
			saw_gpu = true
		if not bool(result.get("pending", true)):
			if not _check(saw_gpu and str(result.get("backend", "")) == "gpu" and not str(result.get("gpu", {}).get("device", "")).is_empty(), "source preparation did not complete on a hardware GPU: " + str(result)):
				return false
			_device = str(result.gpu.device)
			if not _compare(AREA):
				return false
			return _pass("source_prepare_then_gpu", result)
		await process_frame
	return false


func _inventory_epoch() -> bool:
	var start: Dictionary = _begin_gpu("gpu_untracked_inventory")
	if start.is_empty():
		return false
	# Remove the remaining real grain through its ledger, bypassing lifecycle.
	if not _check(_world.regions.home.inventory.consume("gpu_qa_bypass", "ground:compute_cold", "grain", 1), "direct inventory epoch mutation failed"):
		return false
	var stale: Dictionary = _ground.read_base(Vector2i(16, 14))
	if not _check(not bool(stale.get("ok", true)) and not stale.has("elements"), "untracked inventory mutation exposed an old field"):
		return false
	var failed: Dictionary = await _drain_failure()
	if failed.is_empty() or not _pass("gpu_untracked_inventory", failed):
		return false
	# The direct operation intentionally leaves its ground slot inconsistent.
	# Restore the same original inventory state before explicitly reattaching.
	# A fresh world for the next cases avoids inventing a lifecycle repair.
	return _fresh_world()


func _restore_epoch() -> bool:
	var start: Dictionary = _begin_gpu("gpu_same_owner_restore")
	if start.is_empty():
		return false
	var snapshot: Dictionary = _world.artifacts.to_dict()
	if not _check(_world.artifacts.restore(snapshot), "same-owner artifact restoration failed"):
		return false
	var stale: Dictionary = _ground.read_base(Vector2i(15, 12))
	if not _check(not bool(stale.get("ok", true)) and not stale.has("elements"), "artifact restore exposed an old cache"):
		return false
	var failed: Dictionary = await _drain_failure()
	if failed.is_empty() or not _pass("gpu_same_owner_restore", failed):
		return false
	return _fresh_world()


func _rebind_different_world() -> bool:
	var start: Dictionary = _begin_gpu("gpu_world_rebind")
	if start.is_empty():
		return false
	if not _check(not _service.close(), "world rebind must retain a live worker owner"):
		return false
	_ground.close()
	var replacement: Dictionary = _fixture.setup(self)
	if not _check(not replacement.is_empty(), "independent replacement world could not be built"):
		return false
	# Move the same disposable cache object to a distinct original world. The
	# old runtime must not acquire its new binding or release a new owner's lease.
	var replacement_ground: RefCounted = replacement.ground
	replacement_ground.close()
	if not _check(_ground.configure(replacement.world, replacement.definitions), "cache object could not bind the replacement world"):
		return false
	var failed: Dictionary = await _drain_failure()
	if failed.is_empty() or not _check(str(failed.get("reason", "")) == "backend_detached", "old GPU request did not report its detached binding"):
		return false
	if not _pass("gpu_world_rebind", failed) or not _check(_service.close(), "reaped old runtime did not close"):
		return false
	_world = replacement.world
	_definitions = replacement.definitions
	_oracle = replacement.query
	_clock_ms = _world.elapsed_ms
	for _i: int in 10000:
		var progress: Dictionary = _ground.advance(65536, 100000)
		if not _check(bool(progress.get("ok", false)), "replacement source assembly failed"):
			return false
		if str(progress.get("state", "")) == "ready" and int(progress.get("pending_sources", -1)) == 0:
			break
	if not _check(str(_ground.diagnostics().get("state", "")) == "ready", "replacement source assembly did not complete"):
		return false
	_service = Compute.new()
	if not _check(_service.configure(_ground, "gpu"), "new runtime did not acquire the replacement world"):
		return false
	var next: Dictionary = _begin_gpu("gpu_rebound_world")
	if next.is_empty():
		return false
	var finished: Dictionary = await _drain("gpu", false, false)
	if finished.is_empty() or not _compare(AREA):
		return false
	return _pass("gpu_rebound_world", finished)


func _fresh_world() -> bool:
	if not _check(_world.elapsed_ms == _clock_ms and _world.target_ms == _clock_ms, "source and GPU operations changed the original world clock"):
		return false
	if not _check(_service.close(), "completed old runtime could not release its lease"):
		return false
	_ground.close()
	var data: Dictionary = _fixture.setup(self)
	if not _check(not data.is_empty(), "replacement original world could not be constructed"):
		return false
	_world = data.world
	_ground = data.ground
	_oracle = data.query
	_definitions = data.definitions
	_clock_ms = _world.elapsed_ms
	_service = Compute.new()
	return _check(_service.configure(_ground, "gpu"), "replacement original world could not attach its scheduler")


func _begin_gpu(label: String) -> Dictionary:
	if not _within_deadline():
		return {}
	var result: Dictionary = _service.request(AREA)
	if not _check(bool(result.get("ok", false)) and bool(result.get("pending", false)) and str(result.get("backend", "")) == "gpu" and int(result.get("ticket", 0)) > 0, label + " did not start on GPU: " + str(result)):
		return {}
	return result


func _drain(expected_backend: String, expect_fallback: bool, cancelled: bool) -> Dictionary:
	var saw_fallback: bool = false
	while _within_deadline():
		var result: Dictionary = _service.poll(4, 100000)
		if not _check(bool(result.get("ok", false)), "GPU/CPU polling failed: " + str(result)):
			return {}
		if str(result.get("status", "")) == "cpu_fallback_pending":
			saw_fallback = true
			if not _check(expect_fallback and str(result.get("fallback_reason", "")).begins_with("publish:"), "unexpected GPU fallback: " + str(result)):
				return {}
		if not bool(result.get("pending", true)):
			if not _check(str(result.get("backend", "")) == expected_backend and bool(result.get("cancelled", false)) == cancelled and (not expect_fallback or saw_fallback), "incorrect terminal result: " + str(result)):
				return {}
			if not cancelled and expected_backend == "gpu":
				var metrics: Dictionary = result.get("gpu", {})
				if not _check(not str(metrics.get("device", "")).is_empty(), "GPU completion did not identify its real device"):
					return {}
				_device = str(metrics.device)
			return result
		await process_frame
	return {}


func _drain_failure() -> Dictionary:
	while _within_deadline():
		var result: Dictionary = _service.poll(4, 100000)
		if not bool(result.get("ok", false)):
			if not _check(not bool(result.get("pending", true)) and not bool(_service.diagnostics().get("busy", true)), "failed ticket was not reaped: " + str(result)):
				return {}
			return result
		if not _check(bool(result.get("pending", false)), "obsolete GPU request unexpectedly succeeded: " + str(result)):
			return {}
		await process_frame
	return {}


func _compare(area: Rect2i) -> bool:
	# The public projection returns five elements and net thermal grade. Read
	# the detached packed cache only after that projection succeeds to check
	# the independent hot/cold extrema too, including exact channel order.
	var packed_cache: RefCounted = _ground.get("_cache")
	if not _check(packed_cache != null, "missing underlying cache for seven-channel developer validation"):
		return false
	for y: int in range(area.position.y, area.end.y):
		if not _within_deadline():
			return false
		for x: int in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			var actual: Dictionary = _ground.read_base(cell)
			var expected: Dictionary = _oracle.sample_base(cell)
			var raw: Dictionary = packed_cache.read_base(cell)
			if not _check(bool(actual.get("ok", false)) and not bool(actual.get("pending", true)) and bool(expected.get("ok", false)) and bool(raw.get("ok", false)) and not bool(raw.get("pending", true)), "field unavailable at " + str(cell)):
				return false
			if not _check(actual.get("elements") == expected.get("elements") and actual.get("thermal_grade") == expected.get("thermal_grade"), "public field differs from original-source oracle at " + str(cell)):
				return false
			var channels: PackedInt32Array = raw.channels
			var expected_channels: PackedInt32Array = Rules.source_to_packed_channels(expected.elements, int(expected.thermal_grade))
			expected_channels[Rules.PACKED_HOT_INDEX] = int(expected.hot_grade)
			expected_channels[Rules.PACKED_COLD_INDEX] = int(expected.cold_grade)
			if not _check(channels == expected_channels, "seven packed channels differ from original-source oracle at " + str(cell)):
				return false
			_verified_cells += 1
	return true


func _pass(name: String, result: Dictionary) -> bool:
	_cases.append({"name": name, "status": str(result.get("status", "failed")), "backend": str(result.get("backend", "")), "reason": str(result.get("reason", result.get("fallback_reason", "")))})
	return true


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	_errors.append(message)
	printerr("GROUND_GPU_QA_ERROR: ", message)
	return false


func assert_true(condition: bool, label: String) -> void:
	_check(condition, label)


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label + ": expected " + str(expected) + ", got " + str(actual))


func _within_deadline() -> bool:
	return _check(Time.get_ticks_msec() - _started_ms <= DEADLINE_MS, "60-second monotonic deadline exceeded")


func _finish() -> void:
	if _service != null:
		var cancel_requested: bool = false
		while bool(_service.diagnostics().get("busy", false)):
			if not cancel_requested:
				_service.cancel(int(_service.diagnostics().get("ticket", 0)))
				cancel_requested = true
			_service.poll(4, 100000)
			if bool(_service.diagnostics().get("busy", false)):
				await process_frame
		if not _service.close():
			_check(false, "reaped scheduler could not close")
	if _ground != null:
		_ground.close()
	var report: Dictionary = {"result": "passed" if _errors.is_empty() else "failed", "failed": _errors.size(),
		"cases": _cases, "verified_cells": _verified_cells, "verified_channels": _verified_cells * 7,
		"adapter": _adapter, "device": _device, "elapsed_ms": Time.get_ticks_msec() - _started_ms, "errors": _errors}
	print("GROUND_GPU_QA_JSON:", JSON.stringify(report, "", true, true))
	quit(0 if _errors.is_empty() else 1)
