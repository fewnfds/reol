extends "res://tests/runtime/helpers/source_care_replay.gd"
## Editor entry for the same ordinary keeper/source intentions as regression.


func replay_explained(runtime: WorldContinuityRuntime, suffix: String) -> Dictionary:
	var archive: String = "res://tests/fixtures/session_v38_explained.json"
	var report: Dictionary = {"ordinary_commands": true, "steps": []}
	if runtime.load_game(ProjectSettings.globalize_path(archive)) != OK:
		return _failure("ordinary explained-channel load failed", report)
	GameClock.set_paused(true)
	var world: RegionalSimulation = runtime.world_sim
	var original: Dictionary = world.spirit_sources.active.get("player", {})
	if original.is_empty(): return _failure("explained archive lacks actual channel", report)
	var note: Dictionary = world.site_affairs.notes.values().front()
	if not _advance(runtime, int(original.due_ms) - GameClock.elapsed_ms) or note.used != original.id or not world.source_care.warnings.is_empty() or not _object_action(runtime, "place"):
		return _failure("explained channel and actual original-stone placement failed", report)
	var returned: Dictionary = _ask_at_desk(runtime, "verify_return", str(note.id), report)
	if not bool(returned.get("ok", false)) or not _finish_visitor(runtime, str(note.issuer)):
		return _failure("original issuer did not verify the actual peaceful return", report)
	var received: Dictionary = _ask_at_desk(runtime, "verify_return", str(note.id), report)
	if received.get("status") != "completed" or not _travel(runtime, "river") or not _advance(runtime, 60000):
		return _failure("actual received answer and departure failed", report)
	return _future(runtime, suffix, archive, report)


func replay_conflict(runtime: WorldContinuityRuntime, suffix: String) -> Dictionary:
	var archive: String = "res://tests/fixtures/session_v38_conflict.json"
	var report: Dictionary = {"ordinary_commands": true, "steps": []}
	if runtime.load_game(ProjectSettings.globalize_path(archive)) != OK:
		return _failure("ordinary paid-keeper-action load failed", report)
	GameClock.set_paused(true)
	if not _advance(runtime, 550): return _failure("original keeper action did not emit", report)
	runtime.conflict_adapter.yield_player()
	if not _advance(runtime, 5000) or not _travel(runtime, "river") or not _advance(runtime, 60000):
		return _failure("actual paid action, voluntary withdrawal and departure failed", report)
	return _future(runtime, suffix, archive, report)


func _future(runtime: WorldContinuityRuntime, suffix: String, archive: String, report: Dictionary) -> Dictionary:
	if not suffix.is_valid_identifier() or suffix.length() > 24: return _failure("invalid replay suffix", report)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var canonical: String = SnapshotValues.canonical_json(SnapshotValues.normalized(snapshot))
	var path: String = "res://logs/source_care_future_%s.json" % suffix
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return _failure("cannot save full care continuation", report)
	file.store_string(canonical)
	file.close()
	var valid: bool = not WorldSessionSnapshot.stage(runtime, snapshot).is_empty()
	report.merge({"ok": valid, "candidate_valid": valid, "archive": archive, "archive_sha256": FileAccess.get_sha256(archive), "future": path, "bytes": canonical.to_utf8_buffer().size(), "sha256": FileAccess.get_sha256(path), "ms": GameClock.elapsed_ms, "region": runtime.current_region})
	_write_json("res://logs/source_care_restart_%s.json" % suffix, report)
	return report
