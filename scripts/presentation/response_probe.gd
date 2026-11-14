extends RefCounted
## Opt-in synthetic move requests through the real Runner and display sampler.
## Measures CPU preparation, never physical input or presentation to the monitor.

const Units = preload("res://scripts/sim/kernel/units.gd")
const Art = preload("res://scripts/presentation/art.gd")
const MAX_SAMPLES: int = 128
const TIMEOUT_USEC: int = 2000000
const EPSILON_SQUARED: float = 0.000001
const METRICS: Array[String] = ["request_to_received_ms", "request_to_applied_ms",
	"request_to_receipt_published_ms", "request_to_motion_committed_ms", "request_to_display_prepared_ms"]
var samples: Array[Dictionary] = []
var failures: Array[Dictionary] = []
var pending: Dictionary = {}
var _next_request_usec: int = 0
var _attempts: int = 0
var _last_pose: RefCounted
var _publish_intervals_ms := PackedFloat64Array()
var _last_published_usec: int = 0


func accept(receipt: Dictionary, collected_usec: int) -> void:
	if pending.is_empty() or receipt.seq != pending.seq:
		return
	if not receipt.ok:
		failures.append({"seq": receipt.seq, "reason": receipt.reason})
		pending = {}
		return
	if receipt.has("trace"):
		pending.trace = receipt.trace
		pending.accepted_world_ms = receipt.at_ms
		pending.receipt_collected_usec = collected_usec


func tick(host: Node2D, now: int) -> void:
	var frame: RefCounted = host.frame
	if frame == null or frame.paused or not frame.actor_slots.has(1):
		return
	var pose: RefCounted = frame.history.back()
	if pose != _last_pose:
		if _last_published_usec > 0:
			_publish_intervals_ms.append((frame.published_usec - _last_published_usec) / 1000.0)
		_last_published_usec = frame.published_usec
		_last_pose = pose
	var slot: int = frame.actor_slots[1]
	if not pending.is_empty():
		if frame.epoch != pending.epoch or now - int(pending.request_usec) > TIMEOUT_USEC:
			failures.append({"seq": pending.seq, "reason": "session_changed" if frame.epoch != pending.epoch else "timeout"})
			pending = {}
			return
		if pending.has("trace") and not pending.has("motion_committed_usec"):
			if frame.history[0].world_ms > int(pending.accepted_world_ms):
				failures.append({"seq": pending.seq, "reason": "motion_history_window_missed"})
				pending = {}
				return
			# Search retained poses: a display poll may skip the very first commit.
			for candidate: RefCounted in frame.history:
				if candidate.world_ms <= int(pending.accepted_world_ms):
					continue
				var index: int = candidate.ids.find(1)
				if index >= 0 and candidate.positions[index].distance_squared_to(pending.before_position) > EPSILON_SQUARED:
					pending.motion_committed_usec = candidate.completed_usec
					pending.motion_world_ms = candidate.world_ms
					break
		var display_threshold: float = 0.5 / (Art.TILE * host.camera.zoom.x)
		if not pending.has("display_prepared_usec") and host._displayed(1).distance_squared_to(pending.before_display) >= display_threshold * display_threshold:
			pending.display_prepared_usec = Time.get_ticks_usec()
			pending.display_world_ms = host.render_ms
		if pending.has("trace") and pending.has("motion_committed_usec") and pending.has("display_prepared_usec"):
			_finish()
		return
	if now < _next_request_usec or _attempts >= MAX_SAMPLES:
		return
	# Finish each previous route before measuring another request. No supersession.
	if frame.modes[slot] != Units.Mode.IDLE:
		return
	var origin: Vector2 = frame.positions[slot]
	var target := Vector2(-1, -1)
	var direction: Vector2 = Vector2.RIGHT if _attempts % 2 == 0 else Vector2.LEFT
	for offset: Vector2 in [direction, direction.rotated(PI * 0.5), -direction, direction.rotated(-PI * 0.5)]:
		var point: Vector2 = origin + offset * 0.5
		if frame.terrain.segment_clear(origin, point, frame.radii[slot], frame.flight[slot] > 0):
			target = point
			break
	if target.x < 0:
		failures.append({"reason": "no_clear_probe_segment"})
		_attempts += 1
		_next_request_usec = now + 500000
		return
	var request_usec: int = Time.get_ticks_usec()
	var seq: int = host.runner.send({"kind": "move", "actor": 1, "position": target,
		"epoch": frame.epoch, "_trace": {"request_usec": request_usec}})
	_attempts += 1
	# Vary phase relative to both 50ms simulation and 60FPS display boundaries.
	_next_request_usec = request_usec + 350000 + (_attempts * 37123) % 200000
	if seq == 0:
		failures.append({"reason": "not_admitted"})
		return
	pending = {"seq": seq, "epoch": frame.epoch, "request_usec": request_usec,
		"before_position": origin, "before_display": host._displayed(1)}


func _finish() -> void:
	var trace: Dictionary = pending.trace
	var request: int = pending.request_usec
	var row: Dictionary = {"seq": pending.seq, "accepted_world_ms": pending.accepted_world_ms,
		"motion_world_ms": pending.motion_world_ms, "display_world_ms": pending.display_world_ms,
		"receipt_frame_sequence": trace.frame_sequence,
		"request_to_received_ms": (int(trace.received_usec) - request) / 1000.0,
		"request_to_applied_ms": (int(trace.applied_usec) - request) / 1000.0,
		"request_to_receipt_published_ms": (int(trace.published_usec) - request) / 1000.0,
		"request_to_motion_committed_ms": (int(pending.motion_committed_usec) - request) / 1000.0,
		"request_to_display_prepared_ms": (int(pending.display_prepared_usec) - request) / 1000.0}
	samples.append(row)
	pending = {}


func report(summarize: Callable) -> Dictionary:
	var result: Dictionary = {"scenario": "synthetic-move-response-v1", "attempts": _attempts,
		"sample_count": samples.size(), "failures": failures, "pending_at_end": not pending.is_empty(),
		"display_threshold_pixels": 0.5,
		"scope": "synthetic request to CPU display preparation; not physical input or monitor presentation",
		"samples": samples, "observed_pose_publish_interval_ms": summarize.call(_publish_intervals_ms)}
	for metric: String in METRICS:
		var values := PackedFloat64Array()
		for row: Dictionary in samples:
			values.append(row[metric])
		result[metric] = summarize.call(values)
	return result
