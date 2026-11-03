extends "res://tests/runtime/helpers/conflict_replay.gd"
## Real opening and original commands. No resource, body or NPC-policy writes.

const FIELD_EVIDENCE_ROOT: String = "res://" + "logs/"
const TRIP_ARCHIVE: String = FIELD_EVIDENCE_ROOT + "field_trip_inflight.json"
const NPC_ARCHIVE: String = FIELD_EVIDENCE_ROOT + "field_npc_inflight.json"
const RING: String = "stele_drawing_ring"


func prepare_trip(runtime: WorldContinuityRuntime, archive: String = TRIP_ARCHIVE) -> Dictionary:
	var report: Dictionary = {"ordinary_commands": true, "steps": []}
	if not _choose(runtime) or not _ask(runtime, report):
		return _failure("ordinary opening or actual face-to-face clue refused", report)
	if not runtime.travel_to_site("broken_stele") or not _advance(runtime, 750):
		return _failure("known-site original travel did not start", report)
	if runtime.player_journey.is_empty():
		return _failure("travel archive would not be genuinely in flight", report)
	return _archive(runtime, report, archive)


func replay_trip(runtime: WorldContinuityRuntime, suffix: String, archive: String = TRIP_ARCHIVE) -> Dictionary:
	var report: Dictionary = {"ordinary_commands": true, "steps": []}
	if not suffix.is_valid_identifier() or runtime.load_game(ProjectSettings.globalize_path(archive)) != OK:
		return _failure("ordinary in-flight field load refused", report)
	GameClock.set_paused(true)
	if not _finish_trip(runtime):
		return _failure("actual field journey failed", report)
	_note(report, "real_site_arrival", {"cell": runtime.world_sim.conflicts.body("player").cell.duplicate(), "known": runtime.world_sim.field_opportunities.known_sites("player")})
	if not runtime.object_adapter.select_object(RING):
		return _failure("original ring is not actually visible after arrival", report)
	var taken: Dictionary = runtime.object_adapter.submit("take")
	if not bool(taken.ok):
		return _failure("ordinary unique-object take refused: " + str(taken), report)
	var due: int = int(runtime.world_sim.artifacts.active.player.due_ms)
	if not _advance(runtime, due - GameClock.elapsed_ms):
		return _failure("taking original ring did not finish", report)
	if runtime.world_sim.artifacts.objects[RING].container != "actor:player":
		return _failure("original ring has not changed actual custody", report)
	_note(report, "same_ring_taken", runtime.world_sim.artifacts.objects[RING].duplicate(true))
	return _future(runtime, report, suffix)


func replay_take(runtime: WorldContinuityRuntime, suffix: String, archive: String) -> Dictionary:
	var report: Dictionary = {"ordinary_commands": true, "steps": []}
	if not suffix.is_valid_identifier() or runtime.load_game(ProjectSettings.globalize_path(archive)) != OK:
		return _failure("ordinary taking-ring archive load refused", report)
	GameClock.set_paused(true)
	var job: Dictionary = runtime.world_sim.artifacts.active.get("player", {})
	if job.get("object") != RING or job.get("verb") != "take" or not _advance(runtime, int(job.due_ms) - GameClock.elapsed_ms):
		return _failure("actual original in-flight ring take did not finish", report)
	if runtime.world_sim.artifacts.objects[RING].container != "actor:player":
		return _failure("original completed take did not transfer the same ring", report)
	return _future(runtime, report, suffix)


func prepare_npc(runtime: WorldContinuityRuntime, archive: String = NPC_ARCHIVE) -> Dictionary:
	var report: Dictionary = {"ordinary_commands": true, "steps": []}
	if not _choose(runtime):
		return _failure("ordinary opening refused", report)
	_note(report, "player_never_requested_the_opportunity", {"known_sites": runtime.world_sim.field_opportunities.known_sites("player")})
	var deadline: int = GameClock.elapsed_ms + 1800000
	while GameClock.elapsed_ms < deadline:
		if not runtime.world_sim.field_opportunities.route_projection("river_shi_tou").is_empty():
			if not _advance(runtime, 137):
				return _failure("NPC original route could not advance", report)
			return _archive(runtime, report, archive)
		if not _advance(runtime, 5000):
			return _failure("shared world could not reach an NPC decision", report)
	return _failure("NPC did not start an actual trip within bounded ordinary time", report)


func replay_npc(runtime: WorldContinuityRuntime, suffix: String, archive: String = NPC_ARCHIVE) -> Dictionary:
	var report: Dictionary = {"ordinary_commands": true, "steps": []}
	if not suffix.is_valid_identifier() or runtime.load_game(ProjectSettings.globalize_path(archive)) != OK:
		return _failure("ordinary NPC-route source load refused", report)
	GameClock.set_paused(true)
	var deadline: int = GameClock.elapsed_ms + 600000
	while runtime.world_sim.artifacts.objects[RING].container != "actor:river_shi_tou" and GameClock.elapsed_ms < deadline:
		if not _advance(runtime, 1000):
			return _failure("NPC original expedition could not continue", report)
	if runtime.world_sim.artifacts.objects[RING].container != "actor:river_shi_tou":
		return _failure("NPC did not physically take the same original ring", report)
	_note(report, "npc_took_original_ring", runtime.world_sim.artifacts.objects[RING].duplicate(true))
	if not _ask(runtime, report):
		return _failure("later face-to-face clue did not supply an actual destination", report)
	if not runtime.travel_to_site("broken_stele") or not _finish_trip(runtime):
		return _failure("ordinary late visit to personally known site refused", report)
	if not _advance(runtime, 120000):
		return _failure("later empty-site world could not continue", report)
	_note(report, "late_actual_visit", {"cell": runtime.world_sim.conflicts.body("player").cell.duplicate(), "ring_visible": runtime.world_sim.artifacts.can_see("player", RING)})
	return _future(runtime, report, suffix)


func _choose(runtime: WorldContinuityRuntime) -> bool:
	if runtime.avatar_adapter.opening.visible and not runtime.avatar_adapter.choose("subject:player"):
		return false
	GameClock.set_paused(true)
	GameClock.cancel_wait()
	GameClock.set_speed(1.0)
	return runtime.human_player_active()


func _ask(runtime: WorldContinuityRuntime, report: Dictionary) -> bool:
	var teacher: String = "chen_shouzhuo"
	for _attempt: int in 12:
		_senses(runtime)
		var body: Dictionary = runtime.world_sim.conflicts.body(teacher)
		if runtime.home_runtime()._fog != null and not runtime.home_runtime()._fog.is_cell_visible(SimRouteTravel.cell(body.cell)):
			return false
		if not _travel(runtime, "home", SimRouteTravel.cell(body.cell)):
			return false
		var reply: Dictionary = runtime.interaction_adapter.submit(runtime.world_sim.embodiment.subject_for_actor(teacher), "field_clue", {"kind": "field_question", "id": "nearby_ruins"})
		_note(report, "actual_face_to_face_answer", reply)
		if bool(reply.ok) and not runtime.world_sim.field_opportunities.destination("player", "broken_stele").is_empty():
			return true
		if not _advance(runtime, 15000):
			return false
	return false


func _finish_trip(runtime: WorldContinuityRuntime) -> bool:
	var deadline: int = GameClock.elapsed_ms + TRAVEL_LIMIT_MS
	while not runtime.player_journey.is_empty() and GameClock.elapsed_ms < deadline:
		if not _advance(runtime, mini(250, deadline - GameClock.elapsed_ms)):
			return false
	var destination: Dictionary = runtime.world_sim.field_opportunities.destination("player", "broken_stele")
	return not destination.is_empty() and runtime.player_journey.is_empty() and SimRouteTravel.cell(destination.cell) == SimRouteTravel.cell(runtime.world_sim.conflicts.body("player").cell)


func _archive(runtime: WorldContinuityRuntime, report: Dictionary, path: String) -> Dictionary:
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	if WorldSessionSnapshot.stage(runtime, snapshot).is_empty() or runtime.save_game(ProjectSettings.globalize_path(path)) != OK:
		return _failure("actual in-flight field snapshot failed independent validation", report)
	report.merge({"ok": true, "ms": GameClock.elapsed_ms, "archive": path, "sha256": FileAccess.get_sha256(path), "candidate_valid": true})
	_write_json(path + ".report.json", report)
	return report


func _future(runtime: WorldContinuityRuntime, report: Dictionary, suffix: String) -> Dictionary:
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var path: String = "res://logs/field_future_%s.json" % suffix
	if WorldSessionSnapshot.stage(runtime, snapshot).is_empty() or SimSaveStore.save_file(ProjectSettings.globalize_path(path), snapshot) != OK:
		return _failure("actual complete field future failed independent validation", report)
	report.merge({"ok": true, "ms": GameClock.elapsed_ms, "full_snapshot": path, "sha256": FileAccess.get_sha256(path), "candidate_valid": true})
	_write_json("res://logs/field_restart_%s.json" % suffix, report)
	return report
