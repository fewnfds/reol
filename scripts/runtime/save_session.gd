class_name SimSaveSession
extends RefCounted
## Reusable session pipeline. The host supplies data capture, independent
## candidate staging and a validated, infallible adoption callback. File I/O
## stays in SimSaveStore; this service owns admission and completion receipts.

signal save_finished(path: String, result: Error)

const DRAIN_TIMEOUT_USEC: int = 30000000
var reason: String = ""
var _capture: Callable
var _stage: Callable
var _adopt: Callable
var _ready: Callable
var _failed: Callable
var _clock: Node
var _busy: bool = false
var _path: String = ""
var _started_usec: int = 0


func configure(capture: Callable, stage: Callable, adopt: Callable, ready: Callable,
	clock: Node, failed: Callable) -> void:
	_capture = capture
	_stage = stage
	_adopt = adopt
	_ready = ready
	_clock = clock
	_failed = failed


func pending() -> bool:
	return not _path.is_empty()


func save_now(path: String) -> Error:
	if _busy or pending() or _clock.is_advancing() or not bool(_ready.call()):
		return ERR_BUSY
	_busy = true
	var result: Error = _write(path)
	_busy = false
	return result


func request_save(path: String) -> Error:
	if path.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	if _busy or pending() or not _clock.begin_save_boundary(self):
		return ERR_BUSY
	_path = path
	_started_usec = Time.get_ticks_usec()
	reason = "waiting_for_boundary"
	return OK # Accepted only; success is reported by save_finished.


func process_save() -> void:
	if not pending() or _busy:
		return
	_busy = true
	if bool(_failed.call()):
		reason = "settlement_failed"
		_finish(ERR_INVALID_DATA)
		return
	if Time.get_ticks_usec() - _started_usec >= DRAIN_TIMEOUT_USEC:
		reason = "boundary_timeout"
		_finish(ERR_TIMEOUT)
		return
	_clock.drain_save_boundary(self)
	if bool(_failed.call()):
		reason = "settlement_failed"
		_finish(ERR_INVALID_DATA)
	elif bool(_ready.call()):
		_finish(_write(_path))
	else:
		_busy = false


func cancel_save() -> void:
	if pending() and not _busy:
		reason = "cancelled"
		_busy = true
		_finish(ERR_SKIP)


func load_now(path: String) -> Error:
	# Loading may recover a failed/partial world, but cannot replace it inside
	# its clock callback or while another save is waiting for publication.
	if _busy or pending() or _clock.is_advancing():
		return ERR_BUSY
	_busy = true
	var loaded: Dictionary = SimSaveStore.load_file(path)
	if not bool(loaded.get("ok", false)):
		reason = "unreadable"
		_busy = false
		return loaded.error
	var candidate: Dictionary = _stage.call(loaded.data)
	if candidate.is_empty() or candidate.has("rejection"):
		reason = str(candidate.get("rejection", "invalid_candidate"))
		_busy = false
		return ERR_INVALID_DATA
	_adopt.call(candidate)
	reason = ""
	_busy = false
	return OK


func _write(path: String) -> Error:
	var snapshot: Dictionary = _capture.call()
	if snapshot.is_empty():
		reason = "incomplete_snapshot"
		return ERR_BUSY
	var result: Error = SimSaveStore.save_file(path, snapshot)
	reason = "" if result == OK else "file_write_failed"
	return result


func _finish(result: Error) -> void:
	var path: String = _path
	_path = ""
	_clock.end_save_boundary(self)
	# Keep reentrant requests outside this operation, including completion UI.
	save_finished.emit(path, result)
	_busy = false
