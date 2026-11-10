class_name ReolMotionPresentation
extends RefCounted
## One visible body's presentation segment. Endpoints are complete published
## positions; no velocity prediction, world lookup, physics or saved state.

var position: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _start: Vector2 = Vector2.ZERO
var _at_ms: int = -1
var _progress: float = 1.0
var _duration: float = 0.05


func capture(point: Vector2, at_ms: int, duration: float, snap: bool = false) -> void:
	if snap or _at_ms < 0 or at_ms < _at_ms or at_ms == _at_ms and point != _target:
		position = point
		_target = point
		_start = point
		_progress = 1.0
	elif point != _target:
		_start = position
		_target = point
		_progress = 0.0
	_duration = maxf(duration, 0.001)
	_at_ms = at_ms


func advance(seconds: float) -> bool:
	if _progress >= 1.0 or seconds <= 0.0:
		return false
	_progress = minf(1.0, _progress + seconds / _duration)
	position = _start.lerp(_target, _progress)
	return true


func initialized() -> bool:
	return _at_ms >= 0
