extends "res://tests/runtime/helpers/field_replay.gd"
## Continue genuine ordinary histories through original product commands only.

const RESEARCH_ARCHIVE: String = "res://logs/drawing_research_inflight.json"
const DRAW_ARCHIVE: String = "res://logs/drawing_inflight.json"
const V40_TAKE: String = "res://tests/fixtures/session_v40_take.json"


func prepare_research(runtime: WorldContinuityRuntime) -> Dictionary:
	var report: Dictionary = {"ordinary_commands": true, "source": V40_TAKE, "steps": []}
	if runtime.load_game(ProjectSettings.globalize_path(V40_TAKE)) != OK:
		return _failure("genuine earlier take archive refused", report)
	GameClock.set_paused(true)
	var domain: SimArtifacts = runtime.world_sim.artifacts
	if not _finish_artifact(runtime) or domain.objects[RING].container != "actor:player":
		return _failure("original ring take did not complete", report)
	if not runtime.object_adapter.select_object(RING) or not runtime.object_adapter.submit("study").ok or not _finish_artifact(runtime):
		return _failure("actual outer-form study did not complete", report)
	_note(report, "outer_form_only", {"method": domain.describe("player", RING).method, "qi": runtime.world_sim.conflicts.body("player").qi})
	var response: Dictionary = runtime.object_adapter.submit("use_research")
	if not response.ok or not _advance(runtime, 30000):
		return _failure("ordinary paid inner-pattern research did not begin", report)
	return _archive(runtime, report, RESEARCH_ARCHIVE)


func prepare_draw(runtime: WorldContinuityRuntime) -> Dictionary:
	var report: Dictionary = {"ordinary_commands": true, "source": RESEARCH_ARCHIVE, "steps": []}
	if runtime.load_game(ProjectSettings.globalize_path(RESEARCH_ARCHIVE)) != OK:
		return _failure("genuine research archive refused", report)
	GameClock.set_paused(true)
	if not _finish_artifact(runtime) or not _to_drawing_position(runtime, report):
		return _failure("original research or actual return and short approach failed", report)
	if not runtime.object_adapter.select_object(RING):
		return _failure("held original ring cannot be inspected", report)
	var response: Dictionary = runtime.object_adapter.submit_draw("training_sword")
	_note(report, "actual_draw_command", response)
	if not response.ok or not _advance(runtime, 1000):
		return _failure("paid short-distance draw did not reach its real middle", report)
	return _archive(runtime, report, DRAW_ARCHIVE)


func replay_research(runtime: WorldContinuityRuntime, suffix: String, archive: String = RESEARCH_ARCHIVE) -> Dictionary:
	var report: Dictionary = {"ordinary_commands": true, "source": archive, "steps": []}
	if runtime.load_game(ProjectSettings.globalize_path(archive)) != OK:
		return _failure("research source load refused", report)
	GameClock.set_paused(true)
	if not _finish_artifact(runtime) or not _to_drawing_position(runtime, report):
		return _failure("paid research or original travel did not continue", report)
	runtime.object_adapter.select_object(RING)
	if not runtime.object_adapter.submit_draw("training_sword").ok or not _finish_artifact(runtime):
		return _failure("original trained ring did not draw the original sword", report)
	return _drawing_future(runtime, report, suffix)


func replay_draw(runtime: WorldContinuityRuntime, suffix: String, cancel: bool = false, archive: String = DRAW_ARCHIVE) -> Dictionary:
	var report: Dictionary = {"ordinary_commands": true, "source": archive, "cancelled": cancel, "steps": []}
	if runtime.load_game(ProjectSettings.globalize_path(archive)) != OK:
		return _failure("genuine middle-of-draw source refused", report)
	GameClock.set_paused(true)
	if cancel:
		runtime.stop_player_action()
	elif not _finish_artifact(runtime):
		return _failure("original paid draw did not finish", report)
	return _drawing_future(runtime, report, suffix)


func _finish_artifact(runtime: WorldContinuityRuntime) -> bool:
	var job: Dictionary = runtime.world_sim.artifacts.active.get("player", {})
	return not job.is_empty() and _advance(runtime, int(job.due_ms) - GameClock.elapsed_ms)


func _to_drawing_position(runtime: WorldContinuityRuntime, report: Dictionary) -> bool:
	var domain: SimArtifacts = runtime.world_sim.artifacts
	var sword: Dictionary = domain.objects.get("training_sword", {})
	if sword.is_empty() or sword.container != "dorm" or not _travel(runtime, "home", domain.object_cell("training_sword")):
		return false
	var target: Vector2i = domain.object_cell("training_sword")
	var cells: Array[Vector2i] = VillageRuntime.find_reachable_cells(runtime.home_runtime()._world, target, 5, 1024)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x if a.x != b.x else a.y < b.y)
	for cell: Vector2i in cells:
		var gap: float = cell.distance_to(target)
		if gap < 3.0 or gap > 4.5:
			continue
		var from: Vector2 = TileGrid.cell_to_world(cell)
		var to: Vector2 = TileGrid.cell_to_world(target)
		if Space.level(runtime.world_sim, from) != Space.level(runtime.world_sim, to) or not Space.clear_segment(runtime.world_sim, from, to, Space.level(runtime.world_sim, from)):
			continue
		if not _travel(runtime, "home", cell):
			continue
		runtime.object_adapter.select_object(RING)
		for choice: Dictionary in runtime.object_adapter.draw_targets():
			if choice.id == "training_sword":
				_note(report, "actual_short_walk", {"player_cell": [cell.x, cell.y], "target": [target.x, target.y], "gap_cells": gap})
				return true
	return false


func _drawing_future(runtime: WorldContinuityRuntime, report: Dictionary, suffix: String) -> Dictionary:
	if not suffix.is_valid_identifier():
		return _failure("invalid evidence suffix", report)
	_note(report, "same_original_target", runtime.world_sim.artifacts.objects.training_sword.duplicate(true))
	if not _travel(runtime, "river") or not _advance(runtime, 120000):
		return _failure("actual later cross-settlement journey failed", report)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var path: String = "res://logs/drawing_future_%s.json" % suffix
	if WorldSessionSnapshot.stage(runtime, snapshot).is_empty() or SimSaveStore.save_file(ProjectSettings.globalize_path(path), snapshot) != OK:
		return _failure("full original drawing future failed candidate validation", report)
	report.merge({"ok": true, "ms": GameClock.elapsed_ms, "full_snapshot": path, "sha256": FileAccess.get_sha256(path), "candidate_valid": true,
		"qi": int(runtime.world_sim.conflicts.body("player").qi), "target": runtime.world_sim.artifacts.objects.training_sword.duplicate(true)})
	_write_json("res://logs/drawing_restart_%s.json" % suffix, report)
	return report
