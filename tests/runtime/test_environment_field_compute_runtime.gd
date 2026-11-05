extends RefCounted
## Synchronous headless contracts for the scheduler; native GPU execution is
## independently verified by the owner, without substituting a fake device.

const Cache = preload("res://scripts/sim/environment_field_cache.gd")
const Compute = preload("res://scripts/runtime/environment_field_compute_runtime.gd")


func run(runner: Object) -> void:
	_configuration_and_atomic_rejections(runner)
	_cpu_budgets_and_revision(runner)
	_cancel_retains_backlog(runner)
	_headless_fallback(runner)
	_oversized_gpu_area(runner)
	_clipped_map_edge(runner)
	print("SCENARIO environment field compute scheduler: bounded CPU work, revision-aware completion, cancellation retention and explicit GPU fallback")


func _configuration_and_atomic_rejections(runner: Object) -> void:
	var service := Compute.new()
	var unconfigured := Cache.new()
	runner.assert_true(not service.configure(unconfigured), "an unconfigured cache cannot be attached")
	runner.assert_true(not service.set_mode("cpu") and not bool(service.request(Rect2i(0, 0, 16, 16)).ok), "unconfigured service rejects mode changes and requests")
	var cache := Cache.new()
	runner.assert_true(cache.configure(Vector2i(35, 19), 3), "the validation cache configures")
	var baseline: Dictionary = cache.diagnostics().duplicate(true)
	runner.assert_true(not service.configure(cache, "invalid"), "an unsupported mode cannot configure a service")
	runner.assert_eq(cache.diagnostics(), baseline, "invalid mode never touches the cache")
	runner.assert_true(service.configure(cache, "cpu"), "an initialized cache and supported mode configure")
	runner.assert_true(not service.configure(cache, "auto") and not service.set_mode("GPU"), "reconfigure and unknown mode are rejected")
	var before: Dictionary = service.diagnostics().duplicate(true)
	for area: Rect2i in [Rect2i(), Rect2i(-16, 0, 16, 16), Rect2i(0, -16, 16, 16),
		Rect2i(1, 0, 16, 16), Rect2i(0, 1, 16, 16), Rect2i(0, 0, 17, 16),
		Rect2i(0, 0, 16, 17), Rect2i(32, 16, 4, 3), Rect2i(32, 16, 3, 4),
		Rect2i(2147483647, 0, 16, 16)]:
		var rejected: Dictionary = service.request(area)
		runner.assert_true(not bool(rejected.ok) and not str(rejected.get("reason", "")).is_empty(), "invalid or non-tile-aligned complete area is rejected: " + str(area))
		runner.assert_eq(cache.diagnostics(), baseline, "area preflight rejects before queuing any tiles")
		runner.assert_eq(service.diagnostics(), before, "area preflight leaves scheduler state and tickets unchanged")
	runner.assert_true(not bool(service.poll().ok) and not bool(service.cancel(1).ok), "an idle scheduler cannot poll or cancel a nonexistent ticket")
	runner.assert_true(service.close(), "closing an idle scheduler succeeds")
	runner.assert_true(not bool(service.request(Rect2i(0, 0, 16, 16)).ok), "a closed scheduler no longer holds the cache")


func _cpu_budgets_and_revision(runner: Object) -> void:
	var cache := Cache.new()
	var service := Compute.new()
	runner.assert_true(cache.configure(Vector2i(32, 16), 2) and service.configure(cache, "cpu"), "the two-tile CPU fixture configures")
	runner.assert_true(bool(cache.set_source(0, Vector2i(4, 4), 1, [1000, 0, 0, 0, 0, 300, 0]).ok), "the first original projection is accepted")
	runner.assert_true(bool(cache.set_source(1, Vector2i(20, 4), 1, [2000, 0, 0, 0, 0, 0, 300]).ok), "the second original projection is accepted")
	var started: Dictionary = service.request(Rect2i(0, 0, 32, 16))
	runner.assert_true(bool(started.ok) and bool(started.pending) and str(started.backend) == "cpu", "CPU request queues the actual complete region")
	var first_ticket: int = int(started.ticket)
	var before_cache: Dictionary = cache.diagnostics().duplicate(true)
	var before_service: Dictionary = service.diagnostics().duplicate(true)
	runner.assert_true(not bool(service.request(Rect2i(0, 0, 16, 16)).ok), "a second request cannot replace an in-flight ticket")
	runner.assert_true(not service.set_mode("gpu") and not service.close(), "mode change and close cannot abandon active work")
	for invalid: Array in [[0, 1], [1, 0], [1, Cache.MAX_WORK + 1]]:
		var rejected: Dictionary = service.poll(int(invalid[0]), int(invalid[1]))
		runner.assert_true(not bool(rejected.ok), "invalid poll budgets reject explicitly")
	runner.assert_eq(cache.diagnostics(), before_cache, "busy and invalid poll operations cannot mutate queued cache work")
	runner.assert_eq(service.diagnostics(), before_service, "busy and invalid poll operations cannot mutate the active ticket")
	var tiny: Dictionary = service.poll(1, 1)
	runner.assert_true(bool(tiny.ok) and bool(tiny.pending) and int(tiny.work) <= 1 and int(tiny.completed) <= 1, "one work unit leaves real pending work and respects both budgets")
	var first: Dictionary = service.poll(1, 100000)
	runner.assert_true(bool(first.ok) and bool(first.pending) and int(first.completed) == 1 and int(first.checked_tiles) <= 1, "one completed tile cannot falsely finish a two-tile request")
	runner.assert_true(not bool(cache.read_base(Vector2i(4, 4)).pending), "the first requested tile was actually built")
	runner.assert_true(bool(cache.read_base(Vector2i(20, 4)).pending), "the second requested tile remains pending")
	var changed: Dictionary = cache.set_source(0, Vector2i(4, 4), 1, [7000, 0, 0, 0, 0, 800, 0])
	runner.assert_true(bool(changed.ok) and bool(changed.changed), "the original source can change while a request is in flight")
	var done: Dictionary = _drain(service, runner)
	runner.assert_true(bool(done.get("ok", false)) and not bool(done.get("pending", true)) and str(done.get("status", "")) == "complete", "CPU request finishes only after the changed revision is ready")
	runner.assert_eq(int(done.get("ticket", -1)), first_ticket, "completion retains the same request identity")
	runner.assert_eq(int(done.get("revision", -1)), int(changed.revision), "completion advertises the actual latest source revision")
	var changed_cell: Dictionary = cache.read_base(Vector2i(4, 4))
	var other_cell: Dictionary = cache.read_base(Vector2i(20, 4))
	runner.assert_true(not bool(changed_cell.pending) and not bool(other_cell.pending), "previously checked tiles are revisited after the source revision changes")
	if not bool(changed_cell.pending) and not bool(other_cell.pending):
		runner.assert_eq(changed_cell.channels[0], 7000, "the completed field contains the changed original strength")
		runner.assert_eq(other_cell.channels[0], 2000, "the unrelated requested tile retains its own source")
	runner.assert_true(service.set_mode("auto") and service.set_mode("cpu"), "idle service accepts a supported policy change")
	runner.assert_true(service.close(), "completed CPU work can be closed without blocking")


func _cancel_retains_backlog(runner: Object) -> void:
	var cache := Cache.new()
	var service := Compute.new()
	runner.assert_true(cache.configure(Vector2i(32, 16), 2) and service.configure(cache, "cpu"), "the cancellation fixture configures")
	cache.set_source(0, Vector2i(20, 4), 1, [1000, 0, 0, 0, 0, 0, 0])
	cache.read_base(Vector2i(0, 0)) # Independent previously queued tile.
	var started: Dictionary = service.request(Rect2i(16, 0, 16, 16))
	var ticket: int = int(started.ticket)
	var partial: Dictionary = service.poll(1, 7)
	runner.assert_true(bool(partial.ok) and bool(partial.pending) and int(partial.work) <= 7, "a real CPU draft remains in progress before cancellation")
	var before: Dictionary = cache.diagnostics().duplicate(true)
	runner.assert_true(not bool(service.cancel(ticket + 1).ok), "another ticket cannot cancel this request")
	runner.assert_eq(cache.diagnostics(), before, "a mismatched cancellation has no cache effect")
	var cancelled: Dictionary = service.cancel(ticket)
	runner.assert_true(bool(cancelled.ok) and bool(cancelled.pending) and bool(cancelled.cancelled), "cancellation invalidates the active ticket without pretending worker completion")
	runner.assert_true(not service.close() and not service.set_mode("auto") and not bool(service.request(Rect2i(0, 0, 16, 16)).ok), "a cancelled ticket stays busy until poll reaps it")
	var finished: Dictionary = service.poll(1, 7)
	runner.assert_true(bool(finished.ok) and not bool(finished.pending) and bool(finished.cancelled) and int(finished.ticket) == ticket, "poll explicitly completes the cancelled CPU ticket")
	runner.assert_eq(cache.diagnostics(), before, "reaping cancellation does not erase either pending tile or the partial draft")
	runner.assert_true(bool(cache.read_base(Vector2i(0, 0)).pending) and bool(cache.read_base(Vector2i(20, 4)).pending), "both unrelated and requested tiles still retain their pending work")
	var changed: Dictionary = cache.set_source(0, Vector2i(20, 4), 1, [9000, 0, 0, 0, 0, 0, 0])
	var next: Dictionary = service.request(Rect2i(16, 0, 16, 16))
	runner.assert_true(bool(next.ok) and int(next.ticket) > ticket, "a later request has a fresh identity")
	var finished_next: Dictionary = _drain(service, runner)
	runner.assert_true(bool(finished_next.get("ok", false)) and int(finished_next.get("revision", -1)) == int(changed.revision), "the next request completes against the current source revision")
	var final: Dictionary = cache.read_base(Vector2i(20, 4))
	runner.assert_true(not bool(final.pending), "the subsequent request publishes the later field")
	if not bool(final.pending):
		runner.assert_eq(final.channels[0], 9000, "cancelled work cannot publish the obsolete source value")
	runner.assert_true(service.close(), "the service is idle after the next completion")
	runner.assert_true(service.configure(cache, "cpu"), "a closed service may be explicitly configured again")
	var reopened: Dictionary = service.request(Rect2i(16, 0, 16, 16))
	runner.assert_true(int(reopened.ticket) > int(next.ticket), "reconfiguration does not recycle an earlier ticket")
	runner.assert_true(not bool(service.cancel(ticket).ok), "an old ticket cannot cancel a newly configured request")
	service.cancel(int(reopened.ticket))
	service.poll()
	runner.assert_true(service.close(), "the reconfigured service is also safely reaped")


func _headless_fallback(runner: Object) -> void:
	if RenderingServer.get_rendering_device() != null:
		print("SKIP compute no-device fallback: a real rendering device is active; native worker is validated separately")
		return
	for mode: String in ["cpu", "auto", "gpu"]:
		var cache := Cache.new()
		var service := Compute.new()
		runner.assert_true(cache.configure(Vector2i(64, 64), 1) and service.configure(cache, mode), "headless mode fixture configures: " + mode)
		cache.set_source(0, Vector2i(3, 4), 1, [1234, 0, 0, 0, 0, 2000, 0])
		var started: Dictionary = service.request(Rect2i(0, 0, 64, 64))
		runner.assert_true(bool(started.ok) and str(started.backend) == "cpu", "headless request uses the existing CPU cache path: " + mode)
		var expected_reason: String = "" if mode == "cpu" else "rendering_device_unavailable"
		runner.assert_eq(str(started.fallback_reason), expected_reason, "explicit and automatic GPU requests report why fallback was necessary")
		var result: Dictionary = _drain(service, runner)
		runner.assert_true(bool(result.get("ok", false)) and not bool(result.get("pending", true)), "fallback drains through bounded CPU work: " + mode)
		runner.assert_eq(str(result.get("fallback_reason", "")), expected_reason, "completion retains the fallback reason")
		var value: Dictionary = cache.read_base(Vector2i(3, 4))
		runner.assert_true(not bool(value.pending), "the actual source cell is published after fallback")
		if not bool(value.pending):
			runner.assert_eq(value.channels[0], 1234, "fallback preserves the same original source strength")
		runner.assert_true(service.close(), "headless fallback leaves no worker to abandon")
	var small_cache := Cache.new()
	var automatic := Compute.new()
	small_cache.configure(Vector2i(16, 16), 1)
	automatic.configure(small_cache, "auto")
	var small: Dictionary = automatic.request(Rect2i(0, 0, 16, 16))
	runner.assert_true(str(small.backend) == "cpu" and str(small.fallback_reason).is_empty(), "auto selects CPU directly below its candidate threshold")
	automatic.cancel(int(small.ticket))
	automatic.poll()
	runner.assert_true(automatic.close(), "small automatic request is reaped")


func _oversized_gpu_area(runner: Object) -> void:
	for mode: String in ["auto", "gpu"]:
		var cache := Cache.new()
		var service := Compute.new()
		runner.assert_true(cache.configure(Vector2i(528, 16), 1) and service.configure(cache, mode), "the wider-than-GPU-budget fixture configures")
		var started: Dictionary = service.request(Rect2i(0, 0, 528, 16))
		runner.assert_true(bool(started.ok) and str(started.backend) == "cpu", "a request wider than 512 cells uses CPU regardless of device availability")
		runner.assert_eq(str(started.fallback_reason), "gpu_area_budget", "GPU area limit is explicit before any device or shader work")
		runner.assert_eq(int(cache.diagnostics().pending_tiles), 33, "the whole oversized area remains queued for the CPU")
		var before: Dictionary = cache.diagnostics().duplicate(true)
		service.cancel(int(started.ticket))
		service.poll()
		runner.assert_eq(cache.diagnostics(), before, "cancelling an oversized request preserves the entire queued area")
		runner.assert_true(service.close(), "the oversized cancellation is reaped without a GPU worker")


func _clipped_map_edge(runner: Object) -> void:
	var cache := Cache.new()
	var service := Compute.new()
	runner.assert_true(cache.configure(Vector2i(35, 19), 1) and service.configure(cache, "cpu"), "a map with partial edge tiles configures")
	cache.set_source(0, Vector2i(34, 18), 1, [0, 0, 0, 0, 3100, 0, 0])
	var started: Dictionary = service.request(Rect2i(32, 16, 3, 3))
	runner.assert_true(bool(started.ok) and int(started.requested_tiles) == 1, "the clipped final map tile is a valid complete request")
	var finished: Dictionary = _drain(service, runner)
	runner.assert_true(bool(finished.get("ok", false)), "the clipped tile can finish")
	var edge: Dictionary = cache.read_base(Vector2i(34, 18))
	runner.assert_true(not bool(edge.pending), "the last map cell is published")
	if not bool(edge.pending):
		runner.assert_eq(edge.channels[4], 3100, "the actual edge source retains its strength")
	runner.assert_true(service.close(), "the edge request leaves the service idle")


func _drain(service: RefCounted, runner: Object) -> Dictionary:
	for _attempt: int in 1000:
		var result: Dictionary = service.poll(1, 10000)
		if not bool(result.get("ok", false)):
			runner.assert_true(false, "bounded polling failed: " + str(result))
			return result
		runner.assert_true(int(result.get("work", 0)) <= 10000 and int(result.get("completed", 0)) <= 1 and int(result.get("checked_tiles", 0)) <= 1, "every CPU poll respects its work and tile budgets")
		if not bool(result.pending):
			return result
	runner.assert_true(false, "bounded scheduler polling failed to finish in its declared test limit")
	return {}
