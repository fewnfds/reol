extends "res://tests/runtime/helpers/conflict_replay.gd"
## Bounded ordinary intentions in the real main scene. No body, stock, skill,
## office or autonomy injection; the original clock advances every actual job.

const LOAN_ARCHIVE: String = "res://tests/fixtures/session_v37.json"
const PREPARED_LOAN: String = "res://logs/source_loan_inflight.json"
const STONE: String = "hearth_stone"
const SOURCE_ID: String = "hearth_seam"
const CASE_ID: String = "hearth_loan"
const OFFER: String = "source_once_body"


func prepare_loan(runtime: WorldContinuityRuntime) -> Dictionary:
	var report: Dictionary = {"ordinary_commands": true, "steps": []}
	if runtime.avatar_adapter.opening.visible and not runtime.avatar_adapter.choose("subject:player"):
		return _failure("ordinary human opening refused", report)
	GameClock.cancel_wait()
	GameClock.set_speed(1.0)
	GameClock.set_paused(true)
	var world: RegionalSimulation = runtime.world_sim
	if not world.site_affairs.cases.has(CASE_ID):
		return _failure("ordinary new main has no explicit local arrangement", report)
	if not _travel(runtime, "home", world.artifacts.object_cell(STONE)):
		return _failure("ordinary walk to the original stone failed", report)
	for verb: String in ["take", "study"]:
		if not _object_action(runtime, verb):
			return _failure("ordinary original stone action failed: " + verb, report)
	_note(report, "actual_stone_and_method", {"container": world.artifacts.objects[STONE].container, "method": world.artifacts.describe("player", STONE).method})
	var loan: Dictionary = _ask_at_desk(runtime, "borrow_source", OFFER, report)
	if not bool(loan.get("ok", false)):
		return _failure("ordinary loan request not accepted: " + str(loan), report)
	if not _finish_visitor(runtime, "player") or world.site_affairs.notes.is_empty():
		return _failure("ordinary signature did not produce an actual note", report)
	var note: Dictionary = world.site_affairs.notes.values().back()
	_note(report, "actual_signature", {"note": note.duplicate(true)})
	if runtime.save_game(ProjectSettings.globalize_path("res://logs/source_loan_signed.json")) != OK:
		return _failure("ordinary signed-note save failed", report)
	if not _travel(runtime, "home", world.spirit_sources.source_cell(SOURCE_ID)):
		return _failure("ordinary return to the physical source failed", report)
	if not runtime.spirit_adapter.select_source(SOURCE_ID):
		return _failure("source cannot be seen after ordinary arrival", report)
	var source_reply: Dictionary = runtime.spirit_adapter.submit("begin")
	if not bool(source_reply.get("ok", false)):
		return _failure("ordinary body-channel request refused: " + str(source_reply), report)
	if not _advance(runtime, 30000) or str(note.bound).is_empty():
		return _failure("original in-progress source has no matching actual note binding", report)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	if WorldSessionSnapshot.stage(runtime, snapshot).is_empty():
		return _failure("ordinary in-progress loan cannot stage", report)
	if runtime.save_game(ProjectSettings.globalize_path(PREPARED_LOAN)) != OK:
		return _failure("ordinary in-progress loan save failed", report)
	report.merge({"ok": true, "archive": PREPARED_LOAN, "sha256": FileAccess.get_sha256(PREPARED_LOAN), "ms": GameClock.elapsed_ms,
		"candidate_valid": true, "note": note.duplicate(true), "qi": int(world.regions.home.actors.player.qi), "source": world.spirit_sources.active.player.duplicate(true)})
	_write_json("res://logs/source_loan_prepare.json", report)
	return report


func replay_loan(runtime: WorldContinuityRuntime, suffix: String) -> Dictionary:
	if not suffix.is_valid_identifier() or suffix.length() > 24:
		return {"ok": false, "error": "invalid evidence suffix"}
	var report: Dictionary = {"ordinary_commands": true, "steps": []}
	var error: Error = runtime.load_game(ProjectSettings.globalize_path(LOAN_ARCHIVE))
	if error != OK:
		return _failure("ordinary source-loan loader failed: " + str(error), report)
	GameClock.set_paused(true)
	var world: RegionalSimulation = runtime.world_sim
	var original: Dictionary = world.spirit_sources.active.get("player", {}).duplicate(true)
	if original.is_empty():
		return _failure("archive lacks original in-progress source", report)
	var note: Dictionary = world.site_affairs.notes.values().back()
	report["source_ms"] = GameClock.elapsed_ms
	report["before_qi"] = int(world.regions.home.actors.player.qi)
	if not _advance(runtime, int(original.due_ms) - GameClock.elapsed_ms) or note.used != original.id:
		return _failure("actual source completion failed to consume its own signed note", report)
	_note(report, "original_source_completed", {"note": note.duplicate(true), "qi": int(world.regions.home.actors.player.qi), "record": world.spirit_sources.records[original.id].duplicate(true)})
	if not _object_action(runtime, "place"):
		return _failure("ordinary original stone placement failed", report)
	var returned: Dictionary = _ask_at_desk(runtime, "verify_return", str(note.id), report)
	if not bool(returned.get("ok", false)):
		return _failure("ordinary return request refused: " + str(returned), report)
	var job_id: String = str(returned.process.id)
	if not world.services.jobs.has(job_id):
		return _failure("accepted return has no original service job", report)
	var job: Dictionary = world.services.jobs[job_id]
	if job.actor == "player" or world.services.owns_actor("player") or not _advance(runtime, 250):
		return _failure("return does not use the issuer's own original body", report)
	var during: Dictionary = WorldSessionSnapshot.capture(runtime)
	if WorldSessionSnapshot.stage(runtime, during).is_empty() or runtime.save_game(ProjectSettings.globalize_path("res://logs/source_loan_inspection_%s.json" % suffix)) != OK:
		return _failure("actual inspection trip cannot save and stage", report)
	_note(report, "actual_inspector_departed", {"job": job.duplicate(true), "check": world.site_affairs.checks[job_id].duplicate(true), "player_free": not world.body_action_owns("player")})
	if not _finish_visitor(runtime, str(job.actor)) or note.closed_ms == -1:
		return _failure("actual inspection and return to desk did not register", report)
	var check: Dictionary = world.site_affairs.checks[job_id]
	var before: Dictionary = SimInteractionRequests.observe(world, "subject:player", returned.process)
	if before.status != "pending":
		return _failure("remote poll leaked the unreceived return result", report)
	_note(report, "actual_return_registered", {"check": check.duplicate(true), "note": note.duplicate(true), "remote_poll": before})
	var received: Dictionary = _ask_at_desk(runtime, "verify_return", str(note.id), report)
	if received.get("status") != "completed":
		return _failure("ordinary face-to-face receipt failed: " + str(received), report)
	if not _travel(runtime, "river") or not _advance(runtime, 60000):
		return _failure("ordinary departure and continuing life failed", report)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var canonical: String = SnapshotValues.canonical_json(SnapshotValues.normalized(snapshot))
	var path: String = "res://logs/source_loan_future_%s.json" % suffix
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure("cannot write complete joint loan future", report)
	file.store_string(canonical)
	file.close()
	var valid: bool = not WorldSessionSnapshot.stage(runtime, snapshot).is_empty()
	report.merge({"ok": valid, "candidate_valid": valid, "ms": GameClock.elapsed_ms, "region": runtime.current_region,
		"archive_sha256": FileAccess.get_sha256(LOAN_ARCHIVE), "future": path, "bytes": canonical.to_utf8_buffer().size(), "sha256": FileAccess.get_sha256(path),
		"qi": int(world.regions.home.actors.player.qi), "container": world.artifacts.objects[STONE].container, "received": received})
	_write_json("res://logs/source_loan_restart_%s.json" % suffix, report)
	return report


func _ask_at_desk(runtime: WorldContinuityRuntime, verb: String, object_id: String, report: Dictionary) -> Dictionary:
	var world: RegionalSimulation = runtime.world_sim
	var row: Dictionary = world.site_affairs.cases[CASE_ID]
	var sim: VillageSimulation = world.regions[row.region]
	if not _travel(runtime, str(row.region), SimRouteTravel.cell(sim.places[row.record_place].cell)):
		return {"ok": false, "error": "ordinary office walk failed"}
	var deadline: int = GameClock.elapsed_ms + 1800000
	var last: Dictionary = {}
	while GameClock.elapsed_ms < deadline:
		var issuer: String = str(sim.institutions.institutions[row.institution].offices[row.office].holder)
		var receiver: String = world.embodiment.subject_for_actor(issuer)
		var introduction: Dictionary = runtime.interaction_adapter.submit(receiver, "site_arrangement", {"kind": "site_case", "id": CASE_ID})
		if bool(introduction.get("ok", false)):
			last = runtime.interaction_adapter.submit(receiver, verb, {"kind": "source_offer" if verb == "borrow_source" else "source_note", "id": object_id})
			if bool(last.get("ok", false)): return last
		else:
			last = introduction
		if not _advance(runtime, 10000): break
	_note(report, "bounded_office_wait_failed", {"last": last})
	return last


func _finish_visitor(runtime: WorldContinuityRuntime, actor: String) -> bool:
	var deadline: int = GameClock.elapsed_ms + 1800000
	while runtime.world_sim.services.owns_actor(actor) and GameClock.elapsed_ms < deadline:
		if not _advance(runtime, 1000): return false
	return not runtime.world_sim.services.owns_actor(actor)


func _object_action(runtime: WorldContinuityRuntime, verb: String) -> bool:
	var domain: SimArtifacts = runtime.world_sim.artifacts
	var deadline: int = GameClock.elapsed_ms + 1800000
	while GameClock.elapsed_ms < deadline:
		if not runtime.object_adapter.select_object(STONE): return false
		var reply: Dictionary = runtime.object_adapter.submit(verb)
		if bool(reply.get("ok", false)):
			if not _advance(runtime, int(domain.active.player.due_ms) - GameClock.elapsed_ms) or domain.owns_actor("player"): return false
			return domain.objects[STONE].container == ("kitchen" if verb == "place" else "actor:player") and (verb != "study" or bool(domain.describe("player", STONE).method))
		# A real NPC can already be handling the sole public object. Wait for
		# ordinary life; neither cancel their work nor make a second stone.
		if not _advance(runtime, 1000): return false
	return false
