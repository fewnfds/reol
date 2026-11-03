extends "res://tests/runtime/helpers/conflict_replay.gd"
## Ordinary movement out of the real records office; no injected walls, bodies,
## resources or NPC policies. This is a bounded QA command sequence, not AI.

const SOURCE: String = "res://tests/fixtures/session_v35.json"
const HIDDEN: String = "res://logs/perception_hidden.json"
const Perception = preload("res://scripts/sim/conflict_perception.gd")


func prepare_hidden(runtime: WorldContinuityRuntime) -> Dictionary:
	var report: Dictionary = {"ordinary_commands": true, "steps": []}
	var error: Error = runtime.load_game(ProjectSettings.globalize_path(SOURCE))
	if error != OK:
		return _failure("ordinary v35 load failed: " + str(error), report)
	GameClock.set_paused(true)
	var domain: SimConflicts = runtime.world_sim.conflicts
	var id: String = domain.conflict_for("player")
	if id.is_empty() or not _advance(runtime, 950):
		return _failure("original paid preparation could not continue", report)
	# Use the real opening room's door. These are movement destinations only;
	# original acceleration, collisions, time and hostile reactions still run.
	var office: Dictionary = runtime.world_sim.regions.home.places.records.workspace
	var door: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(office.door))
	var player: Node = runtime.home_runtime()._player
	var points: Array[Vector2] = [Vector2(door.x, player.motion.position.y), door + Vector2(0, TileGrid.TILE_SIZE), door + Vector2(-TileGrid.TILE_SIZE * 1.5, TileGrid.TILE_SIZE)]
	for point: Vector2 in points:
		if not _walk(runtime, point):
			return _failure("ordinary office-door walk failed", report)
		_note(report, "ordinary_walk", {"position": domain.body("player").position.duplicate()})
	var row: Dictionary = domain.conflicts[id]
	var cues: Dictionary = Perception.cues(domain, row, str(row.defender))
	var sight: Dictionary = row.people.chen_shouzhuo.sight
	if bool(cues.visible) or sight.is_empty() or int(row.ended_ms) != -1 or sight.position == domain.body("player").position:
		return _failure("normal route did not leave a genuinely hidden, remembered opponent", report)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	if WorldSessionSnapshot.stage(runtime, snapshot).is_empty():
		return _failure("genuine hidden-movement snapshot failed candidate verification", report)
	error = runtime.save_game(ProjectSettings.globalize_path(HIDDEN))
	if error != OK:
		return _failure("genuine hidden-movement save failed", report)
	report.merge({"ok": true, "source": SOURCE, "source_sha256": FileAccess.get_sha256(SOURCE), "archive": HIDDEN, "archive_sha256": FileAccess.get_sha256(HIDDEN), "ms": GameClock.elapsed_ms, "player": domain.body("player").position.duplicate(), "observer": domain.body("chen_shouzhuo").position.duplicate(), "last_sight": sight.duplicate(true), "goal": domain.body("chen_shouzhuo").goal, "candidate_valid": true})
	_write_json("res://logs/perception_hidden_prepare.json", report)
	return report


func replay_hidden(runtime: WorldContinuityRuntime, suffix: String) -> Dictionary:
	if not suffix.is_valid_identifier() or suffix.length() > 32:
		return {"ok": false, "error": "invalid output suffix"}
	var report: Dictionary = {"ordinary_commands": true, "steps": []}
	var error: Error = runtime.load_game(ProjectSettings.globalize_path(HIDDEN))
	if error != OK:
		return _failure("ordinary hidden archive load failed: " + str(error), report)
	GameClock.set_paused(true)
	var domain: SimConflicts = runtime.world_sim.conflicts
	var id: String = domain.conflict_for("player")
	if id.is_empty():
		return _failure("hidden archive lacks its genuine encounter", report)
	var before: Dictionary = domain.conflicts[id].people.chen_shouzhuo.sight.duplicate(true)
	report["source_ms"] = GameClock.elapsed_ms
	report["source_sight"] = before
	report["source_visible"] = Perception.cues(domain, domain.conflicts[id], str(domain.conflicts[id].defender)).visible
	if before.is_empty() or bool(report.source_visible) or not _advance(runtime, 6000):
		return _failure("hidden recollection failed to continue through real time", report)
	_note(report, "real_search_continued", {"encounter": domain.conflicts[id].duplicate(true), "observer": domain.body("chen_shouzhuo").position.duplicate(), "player": domain.body("player").position.duplicate()})
	runtime.conflict_adapter.yield_player()
	if not _advance(runtime, 60000):
		return _failure("real post-conflict life could not continue", report)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var path: String = "res://logs/perception_future_%s.json" % suffix
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure("cannot write joint future", report)
	var canonical: String = SnapshotValues.canonical_json(SnapshotValues.normalized(snapshot))
	file.store_string(canonical)
	file.close()
	var valid: bool = not WorldSessionSnapshot.stage(runtime, snapshot).is_empty()
	report.merge({"ok": valid, "candidate_valid": valid, "ms": GameClock.elapsed_ms, "archive_sha256": FileAccess.get_sha256(HIDDEN), "future": path, "bytes": canonical.to_utf8_buffer().size(), "sha256": FileAccess.get_sha256(path), "qi": int(domain.body("player").qi), "burden": runtime.world_sim.health.combat_burden("player")})
	_write_json("res://logs/perception_restart_%s.json" % suffix, report)
	return report


func _walk(runtime: WorldContinuityRuntime, target: Vector2) -> bool:
	var player: Node = runtime.home_runtime()._player
	var deadline: int = GameClock.elapsed_ms + 5000
	while player.motion.position.distance_to(target) > 9.0 and GameClock.elapsed_ms < deadline:
		player._intent = player.motion.position.direction_to(target)
		if not _advance(runtime, 25):
			player._intent = Vector2.ZERO
			return false
	player._intent = Vector2.ZERO
	return _advance(runtime, 100) and player.motion.position.distance_to(target) < 16.0
