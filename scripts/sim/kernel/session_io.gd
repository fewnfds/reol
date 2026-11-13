extends RefCounted
## One cold I/O job at a time. Receives detached values, never the live world.
## Only the simulation owner adopts a loaded candidate.

const FORMAT: String = "reol-world-7"
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")
const MAX_BYTES: int = 268435456
var _thread := Thread.new()
var _mutex := Mutex.new()
var _result: Dictionary = {}
var _notify: Callable
var busy: bool = false


func submit(command: Dictionary, state: Dictionary, notify: Callable, workers: int = -1) -> bool:
	if busy:
		return false
	busy = true
	_notify = notify
	var error: Error = _thread.start(_run.bind(command, state, workers))
	if error != OK:
		busy = false
		return false
	return true


func poll() -> Dictionary:
	_mutex.lock()
	var value: Dictionary = _result
	_result = {}
	_mutex.unlock()
	if not value.is_empty():
		if _thread.is_started():
			_thread.wait_to_finish()
		busy = false
	return value


func close() -> void:
	if _thread.is_started():
		_thread.wait_to_finish()
	busy = false


func _run(command: Dictionary, state: Dictionary, workers: int) -> void:
	var path: String = str(command.get("path", "user://quicksave.reol"))
	var result: Dictionary = {"command": command, "ok": false, "reason": "io_failed"}
	if command.kind == "save":
		var temporary: String = path + ".tmp"
		var file := FileAccess.open(temporary, FileAccess.WRITE)
		if file != null:
			var stored: bool = file.store_var({"format": FORMAT, "state": state}, false)
			file.flush()
			var error: Error = file.get_error()
			file.close()
			if stored and error == OK:
				var backup: String = path + ".bak"
				var moved: Error = OK
				if FileAccess.file_exists(path):
					moved = DirAccess.rename_absolute(path, backup)
				if moved == OK:
					moved = DirAccess.rename_absolute(temporary, path)
					if moved != OK and FileAccess.file_exists(backup):
						DirAccess.rename_absolute(backup, path)
				result.ok = moved == OK
				result.reason = "saved" if result.ok else "rename_failed"
	else:
		# Recover a crash between the two renames only when the primary is absent.
		# A present invalid primary is reported, never silently replaced by history.
		var source: String = path if FileAccess.file_exists(path) else path + ".bak"
		var file := FileAccess.open(source, FileAccess.READ)
		if file != null and file.get_length() > 0 and file.get_length() <= MAX_BYTES:
			var data: Variant = file.get_var(false)
			if data is Dictionary and data.get("format", "") == FORMAT and data.get("state") is Dictionary:
				var candidate: RefCounted = Persistence.candidate(data.state, workers)
				result["candidate"] = candidate
				result.ok = candidate != null
				result.reason = "read" if result.ok else "invalid_state"
			else:
				result.reason = "invalid_format"
		if file != null:
			file.close()
	_mutex.lock()
	_result = result
	_mutex.unlock()
	_notify.call()
