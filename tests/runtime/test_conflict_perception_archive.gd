extends RefCounted
## Real walking through a door and behind a wall; no injected combat setup.

const ARCHIVE: String = "res://tests/fixtures/session_v36.json"
const SOURCE_SHA: String = "c26b67a75d5ad39d3579c2fda49496a2208b2b9c9c2b64e03a791f52ec8edd73"
const ENCOUNTER: String = "conflict:encounter:1"
const SOURCE_MS: int = 128050
const LAST_SIGHT_MS: int = 127750
const CONTACT_MS: int = 130400
const FUTURE_MS: int = 194050
const Perception = preload("res://scripts/sim/conflict_perception.gd")
const Space = preload("res://scripts/sim/conflict_space.gd")


func run(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	var bytes: String = FileAccess.get_file_as_string(ARCHIVE)
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SOURCE_SHA, "actual hidden-walk archive retains its independently frozen SHA")
	runner.assert_eq(bytes.to_utf8_buffer().size(), 186545, "actual hidden-walk archive retains all original UTF-8 bytes")
	var expected: String = ""
	for attempt: int in 2:
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var runtime: WorldContinuityRuntime = main._continuity
		if runtime == null or runtime.world_sim == null:
			runner.assert_true(false, "ordinary main initializes before replaying the real wall-side archive")
			main.free()
			continue
		var path: String = "user://tests/perception_archive_%d_%d.json" % [Time.get_ticks_usec(), attempt]
		var future: String = _replay(runtime, path, runner)
		runner.assert_true(not future.is_empty(), "real hidden-walk archive reaches the full ordinary continuation: %d" % attempt)
		if attempt == 0:
			expected = future
		else:
			runner.assert_eq(future, expected, "independent normal loaders reproduce the identical full world after actual search, diagonal contact and ordinary stop")
		_remove(path)
		main.free()
	runner.assert_eq(FileAccess.get_file_as_string(ARCHIVE), bytes, "ordinary replay and temporary re-saves never overwrite the real hidden-walk source")
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SOURCE_SHA, "actual modern source remains byte-identical after both independent continuations")
	GameClock.restore_state(clock)
	print("SCENARIO perception archive: real v36 wall-side walk, retained old spatial clue, natural pursuit/reacquisition, actual float32 diagonal contact, normal save/load and byte-identical independent full futures")


func _replay(runtime: WorldContinuityRuntime, path: String, runner: Object) -> String:
	var loaded: Error = runtime.load_game(ProjectSettings.globalize_path(ARCHIVE))
	runner.assert_eq(loaded, OK, "ordinary loader restores the real modern wall-side walk")
	if loaded != OK:
		return ""
	var world: RegionalSimulation = runtime.world_sim
	var domain: SimConflicts = world.conflicts
	var row: Dictionary = domain.conflicts.get(ENCOUNTER, {})
	runner.assert_true(not row.is_empty(), "real wall-side save retains the same original encounter")
	if row.is_empty():
		return ""
	runner.assert_eq(GameClock.elapsed_ms, SOURCE_MS, "ordinary load returns to the actual hidden-walk millisecond")
	var sight: Dictionary = row.people.chen_shouzhuo.sight.duplicate(true)
	runner.assert_eq(int(sight.at_ms), LAST_SIGHT_MS, "observer retains the actual last visible moment before the player passed behind the wall")
	runner.assert_eq(sight.position, [16439.12109375, 16288.93359375], "old clue preserves the player's genuinely seen door-side position")
	var player_point: Vector2 = SimRouteTravel.point(domain.body("player"))
	runner.assert_eq(domain.body("player").position, [16385.62109375, 16288.02734375], "original player remains at its actually walked hidden position")
	runner.assert_true(player_point.distance_to(Vector2(float(sight.position[0]), float(sight.position[1]))) > 50.0, "retained evidence is observably different from the hidden present")
	runner.assert_true(not Perception.can_see(domain, "chen_shouzhuo", player_point, Space.level(world, player_point)), "original current wall genuinely blocks the observer's sight of the player")
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, WorldSessionSnapshot.capture(runtime)).is_empty(), "actual hidden present stages independently without replacing old sight with hidden coordinates")
	runner.assert_eq(int(domain.body("player").qi), 17, "original player's already-paid spell has no extra payment during its actual walk")
	_advance(runtime, 128550, runner)
	runner.assert_eq(row.people.chen_shouzhuo.sight, sight, "finishing an already emitted action does not grant vision through the actual wall")
	# This real future originally exposed a float32 origin/segment proof bug.
	# Keep the real natural path and geometry proof. The shared-boundary motion
	# handoff now reacquires/contacts at 130400; the immutable source stays intact.
	_advance(runtime, CONTACT_MS, runner)
	var hit: Dictionary = domain.hits.get("conflict:hit:3", {})
	runner.assert_true(not hit.is_empty(), "natural pursuit and reacquisition produce the actual third committed hit")
	if hit.is_empty():
		return ""
	runner.assert_eq(int(hit.at_ms), CONTACT_MS, "actual diagonal contact follows the current shared-boundary scheduler")
	runner.assert_eq(hit.actor, "player", "actual diagonal contact concerns the original player body")
	runner.assert_eq(hit.action, "conflict:action:5", "real contact retains the actual new NPC action identity")
	runner.assert_true(float(hit.segment_from[0]) != float(hit.segment_to[0]) and float(hit.segment_from[1]) != float(hit.segment_to[1]), "regression genuinely exercises a diagonal projectile segment at large world coordinates")
	runner.assert_eq(int(row.people.chen_shouzhuo.sight.at_ms), CONTACT_MS, "observer reacquires the player only after physically approaching the old clue")
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, WorldSessionSnapshot.capture(runtime)).is_empty(), "actual diagonal contact is a valid independently staged joint candidate")
	if not _reload_current(runtime, path, runner):
		return ""
	world = runtime.world_sim
	domain = world.conflicts
	_advance(runtime, SOURCE_MS + 6000, runner)
	var before_qi: int = int(domain.body("player").qi)
	runtime.conflict_adapter.yield_player()
	runner.assert_true(domain.conflict_for("player").is_empty(), "ordinary stop leaves the actual already-ended exchange stopped")
	runner.assert_eq(int(domain.body("player").qi), before_qi, "ordinary stop neither refunds nor repeats original paid energy")
	_advance(runtime, FUTURE_MS, runner)
	runner.assert_eq(int(domain.body("player").qi), 17, "later ordinary life keeps the same original paid energy balance")
	runner.assert_eq(domain.hits.size(), 3, "one natural continuation retains three real contacts without duplication")
	runner.assert_eq(world.health.combat_burden("player"), 24, "real stopped world retains both actual player contusions")
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, snapshot).is_empty(), "complete real hidden-walk future validates independently with original costs, injury, sight and all unrelated life")
	return _canonical(snapshot)


func _advance(runtime: WorldContinuityRuntime, target_ms: int, runner: Object) -> void:
	if target_ms < GameClock.elapsed_ms:
		runner.assert_true(false, "actual hidden-walk replay never rewinds the common clock")
		return
	GameClock.advance_msec(target_ms - GameClock.elapsed_ms)
	var home: VillageRuntime = runtime.home_runtime()
	home._sync_actor_views(true)
	if home._fog != null:
		home._fog.set_focus(runtime.controlled_cell())
		home._fog.update_now()
	runtime.conflict_adapter.refresh()
	runner.assert_true(runtime.world_sim.elapsed_ms == target_ms and GameClock.elapsed_ms == target_ms, "real hidden-walk runtime and original simulation reach the same requested instant")


func _reload_current(runtime: WorldContinuityRuntime, path: String, runner: Object) -> bool:
	var before: String = _canonical(WorldSessionSnapshot.capture(runtime))
	runner.assert_eq(runtime.save_game(path), OK, "real diagonal-contact present saves through the ordinary joint serializer")
	var loaded: Error = runtime.load_game(path)
	runner.assert_eq(loaded, OK, "real diagonal-contact present loads through the ordinary independent candidate")
	if loaded != OK:
		return false
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(runtime)), before, "ordinary re-save/load preserves all actual diagonal-contact and memory facts")
	return true


func _canonical(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _remove(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
