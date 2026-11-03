extends RefCounted
## Immutable real paid preparation, replayed by the normal main-scene loader.

const ARCHIVE: String = "res://tests/fixtures/session_v35.json"
const SOURCE_SHA: String = "b0765c3a7147ce6789b6211fa4d1f222646a4086e2b47594fa8ab4d32e4dd37f"
const FUTURE_MS: int = 420000


func run(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	var original: String = FileAccess.get_file_as_string(ARCHIVE)
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SOURCE_SHA, "actual paid preparation archive retains its independently recorded SHA")
	runner.assert_eq(original.to_utf8_buffer().size(), 173445, "actual paid preparation archive keeps all original bytes")
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary main initializes before actual conflict archive replay")
		main.free()
		GameClock.restore_state(clock)
		return
	var path: String = "user://tests/conflict_archive_%d.json" % Time.get_ticks_usec()
	var bad_path: String = path + ".bad.json"
	var expected: String = ""
	for attempt: int in 2:
		var future: String = _replay(runtime, path, bad_path, runner)
		runner.assert_true(not future.is_empty(), "ordinary archive replay reaches its complete shared future: %d" % attempt)
		if attempt == 0:
			expected = future
		else:
			runner.assert_eq(future, expected, "reloading the original paid preparation reproduces the byte-identical complete world and player future")
	runner.assert_eq(FileAccess.get_file_as_string(ARCHIVE), original, "normal saves, loads and rejected candidates never overwrite the real preparation archive")
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SOURCE_SHA, "actual preparation fixture remains byte-identical after both replays")
	_remove(path)
	_remove(bad_path)
	main.free()
	GameClock.restore_state(clock)
	print("SCENARIO conflict archive: real paid preparation and first qi baseline, emitted flight, natural response, sourced injury, finite guard, held sword, yield, recovery, ordinary reload and atomic rejection")


func _replay(runtime: WorldContinuityRuntime, path: String, bad_path: String, runner: Object) -> String:
	var loaded: Error = runtime.load_game(ProjectSettings.globalize_path(ARCHIVE))
	runner.assert_eq(loaded, OK, "ordinary main loader restores the actual earned paid preparation")
	if loaded != OK:
		return ""
	var world: RegionalSimulation = runtime.world_sim
	var domain: SimConflicts = world.conflicts
	var action: Dictionary = domain.actions.get("conflict:action:1", {})
	runner.assert_true(not action.is_empty(), "archive retains its actual stable first action identity")
	if action.is_empty():
		return ""
	runner.assert_eq(GameClock.elapsed_ms, 125200, "ordinary load resumes the actual fractional paid preparation instant")
	runner.assert_eq(int(domain.body("player").qi), 17, "original qi has already paid its actual three-point spell cost")
	runner.assert_eq(action.status, "active", "actual archived preparation remains active rather than restarting")
	runner.assert_eq(int(action.started_ms), 125000, "archive keeps its original spell start time")
	runner.assert_eq(int(action.effect_ms), 125500, "archive keeps its original emission boundary")
	runner.assert_eq(int(action.due_ms), 126000, "archive keeps its original recovery deadline")
	runner.assert_true(not bool(action.emitted) and domain.projectiles.is_empty(), "paid preparation has no prematurely created projectile")
	for method: String in ["sword", "qi_bolt", "qi_guard"]:
		runner.assert_true(domain.knows("player", method), "genuinely completed original teaching supplies personal knowledge: " + method)
	runner.assert_eq(domain.lessons["conflict:lesson:1"].status, "completed", "archive retains the actual completed paired demonstration")
	runner.assert_eq(world.artifacts.held_weapon("player"), "training_sword", "original player holds the same actually collected unique sword")
	runner.assert_eq(world.artifacts.objects.training_sword.container, "actor:player", "actual sword still has one canonical custody container")
	runner.assert_eq(int(world.spirit_sources.to_dict().version), SimSpiritSources.VERSION, "actual first-cast baseline uses the explicit joint cost schema")
	runner.assert_eq(_canonical(world.capability_practice.to_dict()), _canonical(SimCapabilityPractice.empty_state()), "real old paid cast gains no invented advanced practice or practice costs")
	var baseline: Dictionary = world.spirit_sources.qi_baselines.get("player", {})
	runner.assert_true(not baseline.is_empty(), "real first spell captures the original body's qi checkpoint")
	if not baseline.is_empty():
		runner.assert_eq(int(baseline.at_ms), 125000, "first-cast checkpoint retains its actual original instant")
		runner.assert_eq(int(baseline.qi), 20, "first-cast checkpoint proves original prepayment qi")
		runner.assert_eq(int(baseline.conflict_floor), 1, "checkpoint includes rather than skips the original spell cost")
		runner.assert_eq(int(baseline.practice_floor), 1, "old actual spell checkpoint skips no future original capability-practice cost")
	var forged: Dictionary = WorldSessionSnapshot.capture(runtime)
	forged.simulation.actors.player.qi = 18
	forged.continuity.world.regions.home.actors.player.qi = 18
	_reject(runtime, bad_path, forged, runner, "actual paid preparation cannot gain an unrecorded qi balance")
	forged = WorldSessionSnapshot.capture(runtime)
	forged.continuity.world.conflicts.conflicts["conflict:encounter:1"].people.player.action = ""
	_reject(runtime, bad_path, forged, runner, "active paid preparation cannot be detached from its actual encounter owner")
	_advance(runtime, 125499, runner)
	runner.assert_true(not bool(action.emitted) and domain.projectiles.is_empty(), "real preparation remains un-emitted one millisecond before its exact boundary")
	_advance(runtime, 125550, runner)
	runner.assert_eq(GameClock.elapsed_ms, 125550, "350ms from the source reaches actual projectile flight")
	runner.assert_true(bool(action.emitted) and domain.projectiles.has(action.id), "original paid action emits a genuinely travelling projectile")
	if not domain.projectiles.has(action.id):
		return ""
	runner.assert_eq(int(action.emission.at_ms), 125500, "travelling projectile records exact original emission")
	runner.assert_true(float(domain.projectiles[action.id].travelled) > 0.0, "saved flight has actual spatial progress after emission")
	runner.assert_eq(int(domain.body("player").qi), 17, "actual emission does not charge the original spell twice")
	if not _reload_current(runtime, path, runner, "real in-flight projectile"):
		return ""
	world = runtime.world_sim
	domain = world.conflicts
	action = domain.actions["conflict:action:1"]
	var limit: int = GameClock.elapsed_ms + 12000
	while world.health.combat_burden("player") == 0 and not domain.conflict_for("player").is_empty() and GameClock.elapsed_ms < limit:
		_advance(runtime, mini(limit, GameClock.elapsed_ms + 50), runner)
	runner.assert_eq(world.health.combat_burden("player"), 12, "original opponent's natural response produces a real sourced player contusion")
	var wound_id: String = world.health.source_of_type("player", "contusion")
	runner.assert_true(not wound_id.is_empty() and domain.hits.has(wound_id), "actual continuing injury refers to a committed conflict hit")
	if wound_id.is_empty() or domain.conflict_for("player").is_empty():
		return ""
	var initial_remaining: int = int(world.health.wounds[wound_id].remaining)
	forged = WorldSessionSnapshot.capture(runtime)
	forged.continuity.world.conflicts.hits[wound_id].impact = int(forged.continuity.world.conflicts.hits[wound_id].impact) + 1
	_reject(runtime, bad_path, forged, runner, "actual hit cannot inflate its sourced impact independently of the real method and wound")
	limit = GameClock.elapsed_ms + 4000
	while domain.action_blocks("player") and GameClock.elapsed_ms < limit:
		_advance(runtime, mini(limit, GameClock.elapsed_ms + 50), runner)
	var direction: Vector2 = SimRouteTravel.point(domain.body(domain.opponent("player"))) - SimRouteTravel.point(domain.body("player"))
	runner.assert_true(domain.cast("player", "qi_guard", direction).ok, "injured player uses a genuinely learned and paid guard in the same original encounter")
	var guard: Dictionary = _last_player_action(domain)
	if guard.is_empty() or guard.method != "qi_guard":
		return ""
	runtime.hold_player_motion(true)
	_advance(runtime, int(guard.effect_ms), runner)
	runner.assert_true(domain.barriers.has("player"), "actual guard preparation emits finite protection while the original injury remains")
	if domain.barriers.has("player"):
		runner.assert_eq(int(domain.barriers.player.remaining), 12, "actual emitted protection starts with its configured finite capacity")
		runner.assert_eq(int(domain.barriers.player.until_ms), int(guard.effect_ms) + 2400, "actual emitted protection keeps its original expiration instant")
	runner.assert_eq(int(domain.body("player").qi), 14, "new guard spends exactly one additional actual qi cost")
	if not _reload_current(runtime, path, runner, "active guard with existing real contusion"):
		return ""
	world = runtime.world_sim
	domain = world.conflicts
	guard = _last_player_action(domain)
	_advance(runtime, int(guard.due_ms), runner)
	direction = SimRouteTravel.point(domain.body(domain.opponent("player"))) - SimRouteTravel.point(domain.body("player"))
	runner.assert_true(domain.cast("player", "sword", direction).ok, "same actually held sword performs a personally learned strike")
	var sword: Dictionary = _last_player_action(domain)
	if sword.is_empty() or sword.method != "sword":
		return ""
	runtime.hold_player_motion(true)
	runner.assert_eq(sword.object, "training_sword", "actual strike provenance names the same unique collected sword")
	_advance(runtime, int(sword.due_ms), runner)
	var qi: int = int(domain.body("player").qi)
	runtime.conflict_adapter.yield_player()
	runner.assert_true(domain.conflict_for("player").is_empty(), "ordinary stop ends the actual encounter")
	runner.assert_eq(int(domain.body("player").qi), qi, "ordinary stop neither refunds nor repeats paid qi costs")
	runner.assert_true(not world.health.source_of_type("player", "contusion").is_empty(), "ordinary stop retains the existing sourced injury")
	_advance(runtime, 130000, runner)
	runner.assert_true(domain.projectiles.is_empty() and domain.barriers.is_empty(), "already emitted finite shots and protection finish through actual future time")
	_advance(runtime, FUTURE_MS, runner)
	runner.assert_true(int(world.health.wounds[wound_id].remaining) < initial_remaining, "old actual injury gradually recovers through later shared-minute pulses")
	runner.assert_true(not world.health.wounds[wound_id].recovery.is_empty(), "gradual recovery retains its real observed pulse history")
	runner.assert_eq(int(domain.body("player").qi), qi, "ordinary later life does not passively recreate spent qi")
	var first_payments: int = 0
	for payment: Dictionary in domain.qi_spending("player"):
		if int(payment.number) == 1 and int(payment.amount) == 3:
			first_payments += 1
	runner.assert_eq(first_payments, 1, "whole replay retains exactly one original paid-spell cost entry")
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, snapshot).is_empty(), "complete actual replay future stages independently with original injury and all unrelated life")
	return _canonical(snapshot)


func _last_player_action(domain: SimConflicts) -> Dictionary:
	var result: Dictionary = {}
	for action: Dictionary in domain.actions.values():
		if action.actor == "player" and (result.is_empty() or int(action.number) > int(result.number)):
			result = action
	return result


func _advance(runtime: WorldContinuityRuntime, target_ms: int, runner: Object) -> void:
	if target_ms < GameClock.elapsed_ms:
		runner.assert_true(false, "ordinary archive replay never rewinds the shared clock by advancing time")
		return
	GameClock.advance_msec(target_ms - GameClock.elapsed_ms)
	var home: VillageRuntime = runtime.home_runtime()
	home._sync_actor_views(true)
	if home._fog != null:
		home._fog.set_focus(runtime.controlled_cell())
		home._fog.update_now()
	runtime.conflict_adapter.refresh()
	runner.assert_true(runtime.world_sim.elapsed_ms == target_ms and GameClock.elapsed_ms == target_ms, "ordinary runtime and original regional processes reach the same requested instant")


func _reload_current(runtime: WorldContinuityRuntime, path: String, runner: Object, label: String) -> bool:
	var before: String = _canonical(WorldSessionSnapshot.capture(runtime))
	runner.assert_eq(runtime.save_game(path), OK, label + " saves through the ordinary joint serializer")
	var loaded: Error = runtime.load_game(path)
	runner.assert_eq(loaded, OK, label + " loads through the ordinary candidate boundary")
	if loaded != OK:
		return false
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(runtime)), before, label + " preserves every present world, body, resource and action fact")
	return true


func _reject(runtime: WorldContinuityRuntime, path: String, forged: Dictionary, runner: Object, label: String) -> void:
	var before: String = _canonical(WorldSessionSnapshot.capture(runtime))
	var live: RegionalSimulation = runtime.world_sim
	var terrain: WorldMapData = live.map_data
	runner.assert_eq(SimSaveStore.save_file(path, forged), OK, label + " is an ordinary readable JSON candidate")
	runner.assert_true(runtime.load_game(path) != OK, label + " is rejected by the normal loader")
	runner.assert_true(runtime.world_sim == live and runtime.world_sim.map_data == terrain, label + " leaves original live owners intact")
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(runtime)), before, label + " leaves original qi, injury, activity, clock and all other facts unchanged")


func _canonical(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _remove(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
