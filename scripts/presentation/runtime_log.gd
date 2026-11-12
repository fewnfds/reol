extends Logger
## Godot calls Logger from any thread. Store bounded, detached records only;
## scene/UI/file work happens later on the main thread.

const CAPACITY: int = 512
var _mutex := Mutex.new()
var _records: Array[Dictionary] = []
var _sequence: int = 0
var _errors: int = 0
var _warnings: int = 0


func _init() -> void:
	_records.resize(CAPACITY)


func _log_message(message: String, error: bool) -> void:
	_append("error" if error else "info", message)


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, script_backtraces: Array) -> void:
	var frames := PackedStringArray()
	for trace: RefCounted in script_backtraces:
		if trace == null or trace.get_frame_count() == 0:
			continue
		for index: int in mini(8, trace.get_frame_count()):
			frames.append("%s:%d @ %s" % [trace.get_frame_file(index), trace.get_frame_line(index), trace.get_frame_function(index)])
		break
	var location: String = "\n".join(frames) if not frames.is_empty() else "%s:%d @ %s" % [file, line, function]
	_append("warning" if error_type == 1 else "error", (rationale if not rationale.is_empty() else code) + "\n" + location)


func _append(level: String, message: String) -> void:
	var entry: Dictionary = {"level": level, "text": message.left(4096), "real_ms": Time.get_ticks_msec(), "thread": OS.get_thread_caller_id()}
	_mutex.lock()
	_sequence += 1
	entry.seq = _sequence
	_records[(_sequence - 1) % CAPACITY] = entry
	_errors += int(level == "error")
	_warnings += int(level == "warning")
	_mutex.unlock()


func summary() -> Dictionary:
	_mutex.lock()
	var result: Dictionary = {"sequence": _sequence, "errors": _errors, "warnings": _warnings, "retained": mini(_sequence, CAPACITY)}
	_mutex.unlock()
	return result


func snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_mutex.lock()
	for seq: int in range(maxi(1, _sequence - CAPACITY + 1), _sequence + 1):
		result.append(_records[(seq - 1) % CAPACITY].duplicate())
	_mutex.unlock()
	return result
