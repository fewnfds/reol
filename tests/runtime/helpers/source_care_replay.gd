extends "res://tests/runtime/helpers/source_loan_replay.gd"
## Ordinary main-scene intentions, waiting for the real keeper's own work.
## No position, knowledge, inventory, health or NPC-policy injection.

const WARNING_SAVE: String = "res://logs/source_care_warning.json"
const WARNING_ARCHIVE: String = "res://tests/fixtures/session_v38.json"


func prepare_warning(runtime: WorldContinuityRuntime) -> Dictionary:
	var report: Dictionary = {"ordinary_commands": true, "steps": []}
	if runtime.avatar_adapter.opening.visible and not runtime.avatar_adapter.choose("subject:player"):
		return _failure("ordinary human opening refused", report)
	GameClock.cancel_wait()
	GameClock.set_speed(1.0)
	GameClock.set_paused(true)
	var world: RegionalSimulation = runtime.world_sim
	if world.source_care.arrangements.is_empty():
		return _failure("normal new main lacks explicit care", report)
	if not _travel(runtime, "home", world.artifacts.object_cell(STONE)):
		return _failure("ordinary walk to stone failed", report)
	for verb: String in ["take", "study"]:
		if not _object_action(runtime, verb):
			return _failure("ordinary stone action failed: " + verb, report)
	_note(report, "actual_stone_and_method", {"qi": int(world.regions.home.actors.player.qi)})
	var guard: String = _wait_keeper(runtime)
	if guard.is_empty():
		return _failure("no real keeper visit with enough time within the finite duty", report)
	_note(report, "actual_keeper_at_work", {"actor": guard, "action": world.conflicts.body(guard).active.duplicate(true)})
	if not runtime.spirit_adapter.select_source(SOURCE_ID):
		return _failure("source invisible at actual location", report)
	var begun: Dictionary = runtime.spirit_adapter.submit("begin")
	if not bool(begun.get("ok", false)) or not _advance(runtime, 1500):
		return _failure("ordinary no-note source use failed: " + str(begun), report)
	var alerts: Array[Dictionary] = world.source_care.alerts_for("player")
	if alerts.is_empty() or not world.conflicts.conflict_for("player").is_empty():
		return _failure("actual seen use did not produce a warning with grace", report)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	if WorldSessionSnapshot.stage(runtime, snapshot).is_empty():
		return _failure("actual warning cannot stage", report)
	if runtime.save_game(ProjectSettings.globalize_path(WARNING_SAVE)) != OK:
		return _failure("ordinary warning save failed", report)
	report.merge({"ok": true, "ms": GameClock.elapsed_ms, "archive": WARNING_SAVE, "sha256": FileAccess.get_sha256(WARNING_SAVE),
		"guard": guard, "alerts": alerts, "warnings": world.source_care.warnings.duplicate(true), "source": world.spirit_sources.active.player.duplicate(true),
		"candidate_valid": true, "paused": GameClock.paused, "wait_target_ms": GameClock.wait_target_ms})
	_write_json("res://logs/source_care_prepare.json", report)
	return report


func _wait_keeper(runtime: WorldContinuityRuntime) -> String:
	var world: RegionalSimulation = runtime.world_sim
	var deadline: int = GameClock.elapsed_ms + 5400000
	while GameClock.elapsed_ms < deadline:
		for arrangement: Dictionary in world.source_care.arrangements.values():
			if arrangement.status != "active": continue
			var person: Dictionary = world.conflicts.body(str(arrangement.guard))
			var action: Dictionary = person.active
			if not str(arrangement.visit_action).is_empty() and action.get("id") == arrangement.visit_action and action.get("phase") == "work" and int(action.get("due_ms", 0)) - GameClock.elapsed_ms > int(world.source_care.definitions.grace_ms) + 2000:
				return str(arrangement.guard)
		if not _advance(runtime, 1000): return ""
	return ""


func replay_warning(runtime: WorldContinuityRuntime, suffix: String, mode: String = "drive", archive: String = WARNING_ARCHIVE) -> Dictionary:
	if not suffix.is_valid_identifier() or suffix.length() > 24 or mode not in ["stop", "drive"]:
		return {"ok": false, "error": "invalid care replay mode or suffix"}
	var report: Dictionary = {"ordinary_commands": true, "mode": mode, "steps": []}
	if runtime.load_game(ProjectSettings.globalize_path(archive)) != OK:
		return _failure("ordinary received-warning loader refused", report)
	GameClock.set_paused(true)
	var world: RegionalSimulation = runtime.world_sim
	var alerts: Array[Dictionary] = world.source_care.alerts_for("player")
	if alerts.size() != 1:
		return _failure("archive does not contain one actually received live warning", report)
	var warning: Dictionary = world.source_care.warnings[alerts[0].id]
	var original: String = str(warning.source_job)
	var spent: int = int(world.spirit_sources.sources[SOURCE_ID].spent)
	var qi: int = int(world.conflicts.body("player").qi)
	if mode == "stop":
		var reply: Dictionary = runtime.spirit_adapter.submit("cancel")
		if not bool(reply.get("ok", false)) or not _advance(runtime, int(warning.due_ms) - GameClock.elapsed_ms + 1000):
			return _failure("ordinary voluntary stop failed", report)
	else:
		if not _advance(runtime, int(warning.due_ms) - GameClock.elapsed_ms + 700):
			return _failure("ordinary continuation through the finite grace failed", report)
		var encounter: Dictionary = world.conflicts.conflicts.get(warning.conflict, {})
		if warning.status != "escalated" or encounter.get("initiator") != "shi_tou" or encounter.get("defender") != "player" or world.conflicts.actions.is_empty():
			return _failure("real original keeper did not start and pay for its own action", report)
		_note(report, "actual_keeper_action", {"warning": warning.duplicate(true), "encounter": encounter.duplicate(true), "actions": world.conflicts.actions.duplicate(true), "hits": world.conflicts.hits.duplicate(true)})
		runtime.conflict_adapter.yield_player()
	if not _advance(runtime, 5000):
		return _failure("ordinary post-warning bodies could not settle", report)
	var record: Dictionary = world.spirit_sources.records.get(original, {})
	if record.get("result") != "cancelled" or int(record.get("output", -1)) != 0 or int(world.spirit_sources.sources[SOURCE_ID].spent) != spent or int(world.conflicts.body("player").qi) != qi:
		return _failure("interrupted original source changed its unearned output or actual source balance", report)
	if not world.conflicts.conflict_for("player").is_empty() or not _travel(runtime, "river") or not _advance(runtime, 60000):
		return _failure("ordinary departure after warning could not complete", report)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var canonical: String = SnapshotValues.canonical_json(SnapshotValues.normalized(snapshot))
	var path: String = "res://logs/source_care_future_%s.json" % suffix
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure("cannot write complete joint care future", report)
	file.store_string(canonical)
	file.close()
	var valid: bool = not WorldSessionSnapshot.stage(runtime, snapshot).is_empty()
	report.merge({"ok": valid, "candidate_valid": valid, "ms": GameClock.elapsed_ms, "region": runtime.current_region,
		"archive": archive, "archive_sha256": FileAccess.get_sha256(archive), "future": path, "bytes": canonical.to_utf8_buffer().size(), "sha256": FileAccess.get_sha256(path),
		"warning": warning.duplicate(true), "record": record.duplicate(true), "health": world.health.to_dict()})
	_write_json("res://logs/source_care_restart_%s.json" % suffix, report)
	return report


func prepare_peace(runtime: WorldContinuityRuntime) -> Dictionary:
	var report: Dictionary = {"ordinary_commands": true, "steps": []}
	if runtime.avatar_adapter.opening.visible and not runtime.avatar_adapter.choose("subject:player"):
		return _failure("ordinary human opening refused", report)
	GameClock.cancel_wait()
	GameClock.set_speed(1.0)
	GameClock.set_paused(true)
	var world: RegionalSimulation = runtime.world_sim
	if not _travel(runtime, "home", world.artifacts.object_cell(STONE)):
		return _failure("ordinary walk to public stone failed", report)
	for verb: String in ["take", "study"]:
		if not _object_action(runtime, verb):
			return _failure("ordinary original stone action failed: " + verb, report)
	var loan: Dictionary = _ask_at_desk(runtime, "borrow_source", OFFER, report)
	if not bool(loan.get("ok", false)) or not _finish_visitor(runtime, "player") or world.site_affairs.notes.is_empty():
		return _failure("ordinary issuer did not actually sign the original borrowing", report)
	var note: Dictionary = world.site_affairs.notes.values().back()
	if not _travel(runtime, "home", world.spirit_sources.source_cell(SOURCE_ID)):
		return _failure("ordinary source return failed", report)
	var guard: String = _wait_keeper(runtime)
	if guard.is_empty():
		return _failure("actual finite keeper did not arrive before use", report)
	var explained: Dictionary = runtime.interaction_adapter.submit(world.embodiment.subject_for_actor(guard), "explain_source", {"kind": "care_basis", "id": str(note.id)})
	if explained.get("status") != "completed":
		return _failure("ordinary remembered borrowing explanation not accepted: " + str(explained), report)
	if not runtime.spirit_adapter.select_source(SOURCE_ID) or not bool(runtime.spirit_adapter.submit("begin").get("ok", false)):
		return _failure("ordinary explained physical source use refused", report)
	var original: String = str(world.spirit_sources.active.player.id)
	if not _advance(runtime, 30000):
		return _failure("explained original channel could not advance", report)
	var state: Dictionary = WorldSessionSnapshot.capture(runtime)
	if not world.source_care.warnings.is_empty() or WorldSessionSnapshot.stage(runtime, state).is_empty() or runtime.save_game(ProjectSettings.globalize_path("res://logs/source_care_explained.json")) != OK:
		return _failure("actual explained partial source cannot stage without a fabricated warning", report)
	if not _advance(runtime, int(world.spirit_sources.active.player.due_ms) - GameClock.elapsed_ms) or note.used != original or not _object_action(runtime, "place"):
		return _failure("actual peaceful use and original-stone return failed", report)
	var returned: Dictionary = _ask_at_desk(runtime, "verify_return", str(note.id), report)
	if not bool(returned.get("ok", false)) or not _finish_visitor(runtime, str(note.issuer)):
		return _failure("original issuer did not actually inspect and register peaceful return", report)
	var received: Dictionary = _ask_at_desk(runtime, "verify_return", str(note.id), report)
	var valid: bool = received.get("status") == "completed" and not WorldSessionSnapshot.stage(runtime, WorldSessionSnapshot.capture(runtime)).is_empty()
	report.merge({"ok": valid, "candidate_valid": valid, "ms": GameClock.elapsed_ms, "explanation": explained, "note": note.duplicate(true), "source": world.spirit_sources.records[original].duplicate(true), "warnings": world.source_care.warnings.duplicate(true), "received": received})
	_write_json("res://logs/source_care_peace.json", report)
	return report
