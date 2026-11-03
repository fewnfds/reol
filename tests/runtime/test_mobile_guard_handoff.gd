extends RefCounted
## Scene locomotion consumes the actual regional intervals before effects.

const Fixtures = preload("res://tests/runtime/test_conflict_runtime.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_cast_and_save(runner)
	_arbitrary_cuts_and_original_sidestep(runner)
	_actual_strike_boundary(runner)
	print("SCENARIO mobile guard handoff: ordinary teaching and paid practice, cast-time capped movement, actual effect origin, separate action locks, strict moving candidates, re-bound in-flight load, exact sparse/fine future and sidestep/strike boundaries")


func _scene(runner: Object) -> Dictionary:
	var fixture: Dictionary = _fixtures._scene(runner)
	if fixture.is_empty():
		return fixture
	if not fixture.runtime.avatar_adapter.choose("subject:player") or not _fixtures._learn(fixture, runner):
		_fixtures._dispose(fixture)
		return {}
	var response: Dictionary = fixture.runtime.capability_adapter.begin_practice()
	runner.assert_true(response.ok, "actually taught original player starts the real paid walking practice")
	if not response.ok:
		_fixtures._dispose(fixture)
		return {}
	var done: int = int(fixture.runtime.world_sim.capability_practice.active.player.complete_ms)
	GameClock.advance_msec(done - GameClock.elapsed_ms)
	runner.assert_true(fixture.runtime.world_sim.capability_practice.learned("player"), "normal shared time completes all original paid practice stages")
	if not fixture.runtime.world_sim.capability_practice.learned("player"):
		_fixtures._dispose(fixture)
		return {}
	return fixture


func _begin_guard(fixture: Dictionary, runner: Object) -> Dictionary:
	_fixtures._pair(fixture, "a_he")
	var ui: ConflictRuntime = fixture.ui
	runner.assert_true(ui.engage_selected().ok, "the actually trained person declares a real encounter before guarding")
	var player: PlayerCharacter = fixture.main.player
	player._intent = fixture.arena.axis
	GameClock.advance_msec(137)
	runner.assert_true(player.motion.velocity.length() > player.motion.velocity_limit(0.45), "the original player was really moving faster before the slow cast")
	runner.assert_true(ui.request_cast("qi_guard"), "normal guard input queues the original paid technique")
	ui._pending_direction = fixture.arena.axis
	GameClock.advance_msec(1)
	var domain: SimConflicts = fixture.runtime.world_sim.conflicts
	var id: String = domain.conflict_for("player")
	var aid: String = str(domain.conflicts[id].people.player.action)
	runner.assert_true(not aid.is_empty() and domain.actions[aid].method == "qi_guard", "next positive shared instant commits the exact guard")
	runner.assert_true(player.motion.velocity.length() <= player.motion.velocity_limit(0.45) + 0.001, "guard commit immediately caps existing running velocity without deleting ordinary input")
	return domain.actions.get(aid, {})


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime)))


func _remove(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _cast_and_save(runner: Object) -> void:
	var fixture: Dictionary = _scene(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.runtime
	var player: PlayerCharacter = fixture.main.player
	var action: Dictionary = _begin_guard(fixture, runner)
	if action.is_empty():
		_fixtures._dispose(fixture)
		return
	var start: Vector2 = player.motion.position
	var aid: String = str(action.id)
	var started: int = int(action.started_ms)
	var effect: int = int(action.effect_ms)
	GameClock.advance_msec(73)
	runner.assert_true(not player.motion.position.is_equal_approx(start), "the real original body can adjust position during guard preparation")
	runner.assert_true(runtime.world_sim.conflicts.action_blocks("player"), "moving guard retains its actual cast lock")
	runner.assert_true(not player.request_sidestep(fixture.arena.axis), "slow walking never unlocks a simultaneous sidestep")
	runner.assert_true(not runtime.world_sim.conflicts.cast("player", "qi_bolt", fixture.arena.axis).ok, "slow walking never unlocks a simultaneous spell")
	runner.assert_true(not runtime.travel_to("river") and not GameClock.request_wait(), "slow guard cannot begin a journey or skip its danger with wait")
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, snapshot).is_empty(), "the real limited nonzero movement is accepted by an independent complete candidate")
	var broken: Dictionary = snapshot.duplicate(true)
	broken.player.motion.velocity = [float(player.motion.rules.motion.speed), 0.0]
	runner.assert_true(WorldSessionSnapshot.stage(runtime, broken).is_empty(), "a learned guard cannot save forged full-speed momentum")
	var path: String = "user://tests/mobile_guard_handoff_%d.json" % Time.get_ticks_usec()
	var present: String = _canonical(runtime)
	runner.assert_eq(runtime.save_game(path), OK, "ordinary saver captures the actual moving paid preparation")
	player._intent = Vector2.ZERO
	GameClock.advance_msec(effect - GameClock.elapsed_ms)
	var emitted: Dictionary = runtime.world_sim.conflicts.actions[aid]
	runner.assert_eq(emitted.emission.at_ms, effect, "motion does not shift the original effect deadline")
	runner.assert_eq(emitted.emission.origin, runtime.world_sim.conflicts.body("player").position, "effect takes the already advanced original body position at its real millisecond")
	runner.assert_true(not SimConflicts._vector(emitted.emission.origin).is_equal_approx(start), "guard origin follows actual paid preparation movement instead of a frozen cast-start copy")
	GameClock.advance_msec(started + 900 - GameClock.elapsed_ms)
	var future: String = _canonical(runtime)
	runner.assert_eq(runtime.load_game(path), OK, "normal loader restores the moving guard and rebinds the regional body executor")
	runner.assert_eq(_canonical(runtime), present, "whole saved scene preserves the paid action, mastery proof and capped actual velocity")
	GameClock.advance_msec(started + 900 - GameClock.elapsed_ms)
	runner.assert_eq(_canonical(runtime), future, "restored moving guard reaches the identical whole future without replaying motion or spell cost")
	_remove(path)
	_fixtures._dispose(fixture)


func _arbitrary_cuts_and_original_sidestep(runner: Object) -> void:
	var fixture: Dictionary = _scene(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.runtime
	var player: PlayerCharacter = fixture.main.player
	var action: Dictionary = _begin_guard(fixture, runner)
	if action.is_empty():
		_fixtures._dispose(fixture)
		return
	var path: String = "user://tests/mobile_guard_cuts_%d.json" % Time.get_ticks_usec()
	var started: int = int(action.started_ms)
	runner.assert_eq(runtime.save_game(path), OK, "arbitrary-millisecond guard saves through the ordinary store before the comparison")
	player._intent = fixture.arena.axis
	GameClock.advance_msec(500)
	var coarse: String = _canonical(runtime)
	runner.assert_eq(runtime.load_game(path), OK, "fine comparison starts from the same actual paid snapshot")
	player._intent = fixture.arena.axis
	for offset: int in [1, 17, 49, 50, 113, 149, 150, 151, 199, 200, 201, 287, 351, 449, 499, 500]:
		GameClock.advance_msec(started + offset - GameClock.elapsed_ms)
	runner.assert_eq(_canonical(runtime), coarse, "arbitrary outer slices preserve the entire world/body/clock/fog snapshot across effect and cast completion")
	player._intent = Vector2.ZERO
	GameClock.advance_msec(300)
	runner.assert_true(player.request_sidestep(fixture.arena.axis), "original sidestep remains available in the now free encounter gap")
	var step_started: int = int(player.motion.action.get("started_ms", -1))
	runner.assert_eq(runtime.save_game(path), OK, "original paid sidestep is saved before multiple regional boundaries")
	GameClock.advance_msec(550)
	var step_future: String = _canonical(runtime)
	runner.assert_true(player.motion.action.is_empty() and player.motion.last_outcome in ["finished", "blocked"], "one large shared step completes the real sidestep instead of rejecting its in-flight backlog")
	runner.assert_eq(runtime.load_game(path), OK, "original in-flight sidestep restores after the new executor handoff")
	for offset: int in [1, 49, 50, 99, 100, 127, 299, 300, 301, 549, 550]:
		GameClock.advance_msec(step_started + offset - GameClock.elapsed_ms)
	var step_sliced: String = _canonical(runtime)
	if step_sliced != step_future:
		_dump("mobile_guard_sidestep_coarse", step_future)
		_dump("mobile_guard_sidestep_sliced", step_sliced)
	runner.assert_eq(step_sliced, step_future, "original sidestep has the exact same whole future over many arbitrary regional cuts")
	_remove(path)
	_fixtures._dispose(fixture)


func _dump(name: String, json: String) -> void:
	var file: FileAccess = FileAccess.open("res://logs/" + name + ".json", FileAccess.WRITE)
	if file != null:
		file.store_string(json)


func _actual_strike_boundary(runner: Object) -> void:
	var fixture: Dictionary = _scene(runner)
	if fixture.is_empty():
		return
	_fixtures._pair(fixture, "chen_shouzhuo")
	var runtime: WorldContinuityRuntime = fixture.runtime
	var player: PlayerCharacter = fixture.main.player
	var domain: SimConflicts = runtime.world_sim.conflicts
	runner.assert_true(fixture.ui.engage_selected().ok, "original trained player declares the actual strike timing scenario")
	runner.assert_true(domain.cast("player", "qi_guard", fixture.arena.axis).ok, "actual guard begins before the opponent's real bolt")
	GameClock.advance_msec(int(domain.rules.methods.qi_guard.prepare_ms) + int(domain.rules.methods.qi_guard.duration_ms) + 50)
	runner.assert_true(not domain.barriers.has("player"), "finite original protection genuinely expires before the injury timing comparison")
	var direction: Vector2 = SimRouteTravel.point(domain.body("player")) - SimRouteTravel.point(domain.body("chen_shouzhuo"))
	runner.assert_true(domain.cast("chen_shouzhuo", "qi_bolt", direction).ok, "actual ready opponent commits a real projectile using its original qi")
	GameClock.advance_msec(int(domain.rules.methods.qi_bolt.prepare_ms))
	runner.assert_eq(domain.projectiles.size(), 1, "the original projectile is actually in flight before body movement begins")
	# Move away only after emission, so the real incoming ray still catches the
	# moving original body. The resulting stagger governs later intervals only.
	var path: String = "user://tests/mobile_guard_strike_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "real projectile preparation has an independent complete saved start")
	var start: int = GameClock.elapsed_ms
	player._intent = -(fixture.arena.axis as Vector2)
	GameClock.advance_msec(1000)
	var struck: bool = false
	var hit_ms: int = SimInventory.MAX_COUNT
	for hit: Dictionary in runtime.world_sim.conflicts.hits.values():
		if hit.actor == "player" and int(hit.impact) > 0 and int(hit.absorbed) == 0:
			struck = true
			hit_ms = mini(hit_ms, int(hit.at_ms))
	runner.assert_true(struck, "the actually emitted ray hits the original moving body and produces real stagger rather than a cosmetic shield contact")
	var coarse: String = _canonical(runtime)
	runner.assert_eq(runtime.load_game(path), OK, "strike timing comparison restores the actual original shot preparation")
	player._intent = -(fixture.arena.axis as Vector2)
	for offset: int in range(17, 1001, 17):
		GameClock.advance_msec(start + offset - GameClock.elapsed_ms)
	GameClock.advance_msec(start + 1000 - GameClock.elapsed_ms)
	runner.assert_eq(_canonical(runtime), coarse, "movement and actual projectile contact use the same shared milliseconds across arbitrary presentation slices")
	if struck:
		runner.assert_eq(runtime.load_game(path), OK, "exact impact candidate replays from the actual independently saved emitted shot")
		player._intent = -(fixture.arena.axis as Vector2)
		GameClock.advance_msec(hit_ms - GameClock.elapsed_ms)
		runner.assert_true(runtime.world_sim.conflicts.action_blocks("player"), "the exact original impact millisecond has its real independent stagger lock")
		runner.assert_true(player.motion.velocity.is_zero_approx(), "impact boundary projects the new movement lock immediately without undoing prior displacement")
		runner.assert_true(not WorldSessionSnapshot.stage(runtime, WorldSessionSnapshot.capture(runtime)).is_empty(), "the player's real exact-impact whole snapshot is a valid independently staged candidate")
	_remove(path)
	_fixtures._dispose(fixture)
