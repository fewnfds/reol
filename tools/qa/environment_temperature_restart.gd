extends SceneTree
## Two independent headless processes verify the isolated temperature state,
## not a Main save. Run -- write, then -- read under the external process guard.
## The owned QA artifact is confined to the ignored workspace logs directory.

const Temperature = preload("res://scripts/sim/environment_temperature_state.gd")
const Codec = preload("res://scripts/persistence/snapshot_values.gd")
const PATH: String = "res://logs/environment_temperature_restart.json"
const CELLS: Array[Vector2i] = [Vector2i(2, 2), Vector2i(5, 2), Vector2i(3, 4)]
const TIMES: Array[int] = [5000, 5237, 12347, 60000]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] not in ["write", "read"]:
		_fail("expected write or read")
		return
	var state := Temperature.new()
	if args[0] == "write":
		if not state.configure(Vector2i(8, 8), 16, 0):
			_fail("configure")
			return
		var changes: Array[Dictionary] = [
			{"cell": CELLS[0], "initial_c": 20.0, "target_c": 200.0, "target_per_ms": 0.0, "until_ms": 60000, "tau_ms": 10000},
			{"cell": CELLS[1], "initial_c": 20.0, "target_c": 20.0, "target_per_ms": 0.0, "until_ms": 60000, "tau_ms": 10000}]
		if not bool(state.commit(state.prepare_targets(changes, 0, 2)).ok):
			_fail("initial target commit")
			return
		changes = [
			{"cell": CELLS[0], "target_c": 20.0, "target_per_ms": 0.0, "until_ms": 60000, "tau_ms": 10000},
			{"cell": CELLS[1], "target_c": 200.0, "target_per_ms": 0.0, "until_ms": 60000, "tau_ms": 10000},
			{"cell": CELLS[2], "initial_c": 10.0, "target_c": 10.0, "target_per_ms": 0.001, "until_ms": 60000, "tau_ms": 7000}]
		if not bool(state.commit(state.prepare_targets(changes, 5000, 3)).ok):
			_fail("move target commit")
			return
		var snapshot: Dictionary = state.snapshot()
		var checkpoint: String = _hash(snapshot)
		var future: Dictionary = _future(state)
		if future.is_empty():
			return
		var document: Dictionary = {"version": 1, "state": snapshot, "checkpoint_hash": checkpoint, "future_hash": _hash(future)}
		var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
		if file == null:
			_fail("open QA artifact")
			return
		file.store_string(JSON.stringify(document, "", true, true))
		file.close()
		print("TEMPERATURE_RESTART_JSON:", JSON.stringify({"phase": "write", "checkpoint": checkpoint, "future": document.future_hash, "cells": 3, "samples": 12}))
	else:
		var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if not document is Dictionary or document.get("version") != 1 or not state.restore(document.get("state")):
			_fail("restore independent candidate")
			return
		var checkpoint: String = _hash(state.snapshot())
		var future: Dictionary = _future(state)
		if future.is_empty():
			return
		var future_hash: String = _hash(future)
		if checkpoint != document.get("checkpoint_hash") or future_hash != document.get("future_hash"):
			_fail("independent checkpoint or future differs")
			return
		print("TEMPERATURE_RESTART_JSON:", JSON.stringify({"phase": "read", "checkpoint": checkpoint, "future": future_hash, "cells": 3, "samples": 12}))
	quit(0)


func _future(state: RefCounted) -> Dictionary:
	var samples: Array[Dictionary] = []
	for at_ms: int in TIMES:
		for cell: Vector2i in CELLS:
			var sample: Dictionary = state.actual_at(cell, at_ms)
			if not bool(sample.get("ok", false)):
				_fail("future sample: " + str(sample))
				return {}
			samples.append(sample)
	return {"anchor": state.snapshot(), "samples": samples}


func _hash(value: Dictionary) -> String:
	return Codec.canonical_json(Codec.normalized(value)).sha256_text()


func _fail(reason: String) -> void:
	printerr("TEMPERATURE_RESTART_ERROR: ", reason)
	quit(1)
