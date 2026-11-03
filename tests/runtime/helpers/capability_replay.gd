extends "res://tests/runtime/helpers/conflict_replay.gd"
## Ordinary teaching, practice and input; no body, learning or resource edits.

const EVIDENCE_ROOT: String = "res://" + "logs/"
const PRACTICE_ARCHIVE: String = EVIDENCE_ROOT + "capability_practice_inflight.json"
const GUARD_ARCHIVE: String = EVIDENCE_ROOT + "capability_guard_inflight.json"


func prepare_practice(runtime: WorldContinuityRuntime) -> Dictionary:
	var report: Dictionary = {"ordinary_commands": true, "steps": []}
	if runtime.avatar_adapter.opening.visible and not runtime.avatar_adapter.choose("subject:player"):
		return _failure("ordinary human opening refused", report)
	GameClock.set_paused(true)
	GameClock.cancel_wait()
	GameClock.set_speed(1.0)
	var teacher: String = _find_teacher(runtime, report)
	if teacher.is_empty():
		return _failure("no actual teacher accepted", report)
	_note(report, "actual_lesson", {"teacher": teacher, "lessons": runtime.world_sim.conflicts.lessons.duplicate(true)})
	var reply: Dictionary = runtime.capability_adapter.begin_practice()
	if not bool(reply.ok):
		return _failure("ordinary practice refused: " + str(reply), report)
	if not _advance(runtime, 15000):
		return _failure("ordinary walking practice did not reach its real middle", report)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	if WorldSessionSnapshot.stage(runtime, snapshot).is_empty() or runtime.save_game(ProjectSettings.globalize_path(PRACTICE_ARCHIVE)) != OK:
		return _failure("actual practice archive invalid", report)
	report.merge({"ok": true, "ms": GameClock.elapsed_ms, "archive": PRACTICE_ARCHIVE, "sha256": FileAccess.get_sha256(PRACTICE_ARCHIVE), "qi": int(runtime.world_sim.conflicts.body("player").qi), "practice": runtime.world_sim.capability_practice.active.player.duplicate(true)})
	_write_json(EVIDENCE_ROOT + "capability_prepare.json", report)
	return report


func replay_practice(runtime: WorldContinuityRuntime, suffix: String, archive: String = PRACTICE_ARCHIVE) -> Dictionary:
	if not suffix.is_valid_identifier() or runtime.load_game(ProjectSettings.globalize_path(archive)) != OK:
		return {"ok": false, "error": "ordinary practice replay refused"}
	GameClock.set_paused(true)
	var report: Dictionary = {"ordinary_commands": true, "steps": []}
	var world: RegionalSimulation = runtime.world_sim
	var job: Dictionary = world.capability_practice.active.get("player", {})
	if job.is_empty() or not _advance(runtime, int(job.complete_ms) - GameClock.elapsed_ms):
		return _failure("actual practice could not finish", report)
	if not world.capability_practice.learned("player"):
		return _failure("paid steps failed to grant the actual use", report)
	_note(report, "actual_practice_completed", world.capability_practice.learned_record("player"))
	return _save_future(runtime, report, suffix)


func prepare_guard(runtime: WorldContinuityRuntime) -> Dictionary:
	var report: Dictionary = {"ordinary_commands": true, "steps": []}
	var world: RegionalSimulation = runtime.world_sim
	if not world.capability_practice.learned("player"):
		return _failure("guard setup requires actual completed practice", report)
	var teacher: String = ""
	for lesson: Dictionary in world.conflicts.lessons.values():
		if lesson.pupil == "player" and lesson.status == "completed":
			teacher = str(lesson.teacher)
	if teacher.is_empty() or not _travel(runtime, "home", SimRouteTravel.cell(world.conflicts.body(teacher).cell)) or not _separate(runtime, teacher):
		return _failure("ordinary return to original teacher failed", report)
	_senses(runtime)
	runtime.home_runtime().select_actor(teacher)
	var reply: Dictionary = runtime.conflict_adapter.engage_selected()
	if not bool(reply.ok):
		return _failure("ordinary hostile intention refused: " + str(reply), report)
	var movement: String = ""
	var origin: Vector2 = SimRouteTravel.point(world.conflicts.body("player"))
	for action_name: String in ["move_up", "move_down", "move_left", "move_right"]:
		var direction: Vector2 = {"move_up": Vector2.UP, "move_down": Vector2.DOWN, "move_left": Vector2.LEFT, "move_right": Vector2.RIGHT}[action_name]
		if Space.clear_segment(world, origin, origin + direction * 64, Space.level(world, origin)):
			movement = action_name
			break
	if movement.is_empty() or not runtime.conflict_adapter.request_cast("qi_guard"):
		return _failure("no actual clear walking direction or guard request", report)
	Input.action_press(movement)
	runtime.home_runtime()._player._physics_process(0.0)
	if not _advance(runtime, 1):
		_release(runtime, movement)
		return _failure("actual guard did not commit", report)
	var aid: String = str(world.conflicts.conflicts[world.conflicts.conflict_for("player")].people.player.action)
	if aid.is_empty() or not _advance(runtime, 250):
		_release(runtime, movement)
		return _failure("actual moving guard did not reach in-flight time", report)
	var moved: float = origin.distance_to(SimRouteTravel.point(world.conflicts.body("player")))
	_release(runtime, movement)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	if moved < 10.0 or not world.conflicts.action_blocks("player") or WorldSessionSnapshot.stage(runtime, snapshot).is_empty():
		return _failure("real cast-time walking did not produce a valid visible displacement", report)
	if runtime.save_game(ProjectSettings.globalize_path(GUARD_ARCHIVE)) != OK:
		return _failure("actual moving guard save failed", report)
	report.merge({"ok": true, "ms": GameClock.elapsed_ms, "archive": GUARD_ARCHIVE, "sha256": FileAccess.get_sha256(GUARD_ARCHIVE), "movement": movement, "displacement_px": moved, "action": world.conflicts.actions[aid].duplicate(true), "qi": int(world.conflicts.body("player").qi)})
	_write_json(EVIDENCE_ROOT + "capability_guard_prepare.json", report)
	return report


func replay_guard(runtime: WorldContinuityRuntime, suffix: String, archive: String = GUARD_ARCHIVE) -> Dictionary:
	if not suffix.is_valid_identifier() or runtime.load_game(ProjectSettings.globalize_path(archive)) != OK:
		return {"ok": false, "error": "ordinary moving guard replay refused"}
	GameClock.set_paused(true)
	var report: Dictionary = {"ordinary_commands": true, "steps": []}
	if not _advance(runtime, 3000):
		return _failure("actual ongoing guard could not continue", report)
	_note(report, "ongoing_original_conflict", {"actions": runtime.world_sim.conflicts.actions.duplicate(true), "hits": runtime.world_sim.conflicts.hits.duplicate(true)})
	runtime.conflict_adapter.yield_player()
	if not _advance(runtime, 15000):
		return _failure("actual retreat failed", report)
	return _save_future(runtime, report, suffix)


func _release(runtime: WorldContinuityRuntime, action_name: String) -> void:
	Input.action_release(action_name)
	runtime.home_runtime()._player._physics_process(0.0)


func _save_future(runtime: WorldContinuityRuntime, report: Dictionary, suffix: String) -> Dictionary:
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var path: String = "res://logs/capability_future_%s.json" % suffix
	if WorldSessionSnapshot.stage(runtime, snapshot).is_empty() or SimSaveStore.save_file(ProjectSettings.globalize_path(path), snapshot) != OK:
		return _failure("complete actual future failed independent validation", report)
	report.merge({"ok": true, "ms": GameClock.elapsed_ms, "full_snapshot": path, "sha256": FileAccess.get_sha256(path), "candidate_valid": true, "qi": int(runtime.world_sim.conflicts.body("player").qi)})
	_write_json("res://logs/capability_restart_%s.json" % suffix, report)
	return report
