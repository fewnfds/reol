extends "res://tests/runtime/helpers/source_loan_replay.gd"
## Separate-process continuation of the genuine issuer-owned inspection trip.

const INSPECTION: String = "res://tests/fixtures/session_v37_inspection.json"


func continue_inspection(runtime: WorldContinuityRuntime, suffix: String) -> Dictionary:
	if not suffix.is_valid_identifier() or suffix.length() > 24:
		return {"ok": false, "error": "invalid evidence suffix"}
	var report: Dictionary = {"ordinary_commands": true, "steps": []}
	var error: Error = runtime.load_game(ProjectSettings.globalize_path(INSPECTION))
	if error != OK:
		return _failure("ordinary inspector archive load failed: " + str(error), report)
	GameClock.set_paused(true)
	var world: RegionalSimulation = runtime.world_sim
	var note: Dictionary = world.site_affairs.notes.values().back()
	var check: Dictionary = world.site_affairs.checks.values().back()
	var job: Dictionary = world.services.jobs[check.job]
	if check.status != "active" or job.actor == "player" or not check.observation.is_empty():
		return _failure("archive is not an original unobserved issuer-owned trip", report)
	report["source_ms"] = GameClock.elapsed_ms
	report["original_job"] = job.duplicate(true)
	if not _finish_visitor(runtime, str(job.actor)) or note.closed_ms == -1:
		return _failure("original inspector did not complete the actual round trip", report)
	var process: Dictionary = {"domain": "site_affairs", "id": check.job, "performer": world.embodiment.subject_for_actor(str(job.actor))}
	var unknown: Dictionary = SimInteractionRequests.observe(world, "subject:player", process)
	if unknown.status != "pending":
		return _failure("unheard result leaked after ordinary restore", report)
	var heard: Dictionary = _ask_at_desk(runtime, "verify_return", str(note.id), report)
	if heard.get("status") != "completed" or not _travel(runtime, "river") or not _advance(runtime, 60000):
		return _failure("ordinary follow-up and departure failed", report)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var canonical: String = SnapshotValues.canonical_json(SnapshotValues.normalized(snapshot))
	var path: String = "res://logs/source_loan_inspection_future_%s.json" % suffix
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure("cannot write inspector's complete joint future", report)
	file.store_string(canonical)
	file.close()
	var valid: bool = not WorldSessionSnapshot.stage(runtime, snapshot).is_empty()
	report.merge({"ok": valid, "candidate_valid": valid, "archive_sha256": FileAccess.get_sha256(INSPECTION), "ms": GameClock.elapsed_ms,
		"bytes": canonical.to_utf8_buffer().size(), "sha256": FileAccess.get_sha256(path), "future": path,
		"check": check.duplicate(true), "note": note.duplicate(true), "remote_poll": unknown, "heard": heard})
	_write_json("res://logs/source_loan_inspection_restart_%s.json" % suffix, report)
	return report
