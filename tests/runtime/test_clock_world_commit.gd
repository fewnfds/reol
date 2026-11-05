extends RefCounted
## Real two-region runtime, original clock, player body and route. An event
## budget may split an interval, but the published clock must never lead it.

const RuntimeFixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
var fixtures := RuntimeFixtures.new()


func run(runner: Object) -> void:
	_published_after_world(runner)
	_budgeted_frame_and_save(runner)
	_budgeted_explicit(runner)
	_manual_override_before_projection(runner)
	_regional_requested_limit(runner)
	print("SCENARIO real clock/world commit: published boundary, budget debt, route override and retained regional target")


func _setup(runner: Object) -> Dictionary:
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return {}
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	# Keep original bodies and systems; only suppress unrelated autonomous
	# choices. Two real resident retry boundaries make a limited 50ms request
	# require multiple regional boundaries, rather than a fake executor.
	for region: String in world.regions:
		var sim: VillageSimulation = world.regions[region]
		for actor: Dictionary in sim.actors.values():
			actor.autonomous = false
		world.invalidate_region(region)
	var home: VillageSimulation = world.regions.home
	if not home.actors.has("chen_shouzhuo") or not home.actors.has("a_he"):
		runner.assert_true(false, "the real opening has both resident retry fixtures")
		fixtures._dispose(fixture)
		return {}
	home.actors.chen_shouzhuo.autonomous = true
	home.actors.chen_shouzhuo.retry_ms = 10
	home.actors.a_he.autonomous = true
	home.actors.a_he.retry_ms = 20
	world.invalidate_region("home")
	return fixture


func _start_journey(runner: Object, fixture: Dictionary) -> bool:
	var runtime: WorldContinuityRuntime = fixture.continuity
	var started: bool = runtime.travel_to("river") and not runtime.player_journey.is_empty()
	runner.assert_true(started, "the real runtime starts a two-settlement journey")
	if started:
		runner.assert_true(int(runtime.player_journey.due_ms) > 50, "the first real route segment spans the partial clock interval")
		started = int(runtime.player_journey.due_ms) > 50
	return started


func _point(body: Dictionary) -> Vector2:
	return Vector2(float(body.position[0]), float(body.position[1]))


func _expected_position(route: Dictionary, body: Dictionary, at_ms: int) -> Vector2:
	var projected: Dictionary = body.duplicate(true)
	SimRouteTravel.project(route.duplicate(true), projected, at_ms)
	return _point(projected)


func _published_after_world(runner: Object) -> void:
	var fixture: Dictionary = _setup(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	var player: PlayerCharacter = fixture.player
	if not _start_journey(runner, fixture):
		fixtures._dispose(fixture)
		return
	var body: Dictionary = world.regions.home.actors.player
	var original_body: Dictionary = body.duplicate(true)
	var original_route: Dictionary = runtime.player_journey.duplicate(true)
	var observed: Array[Dictionary] = []
	var listener: Callable = func(from_ms: int, to_ms: int) -> void:
		observed.append({"from": from_ms, "to": to_ms, "clock": GameClock.elapsed_ms,
			"world": world.elapsed_ms, "home": world.regions.home.elapsed_ms,
			"body": _point(body), "view": player.global_position,
			"boundaries": int(world.simulation_work.boundaries)})
	GameClock.time_advanced.connect(listener)
	GameClock.advance_msec(25)
	GameClock.time_advanced.disconnect(listener)
	runner.assert_eq(observed.size(), 1, "one completed explicit interval produces one time notification")
	if observed.size() == 1:
		var event: Dictionary = observed[0]
		runner.assert_eq([event.from, event.to, event.clock, event.world, event.home], [0, 25, 25, 25, 25], "the listener sees clock, actual world and active region at the published instant")
		runner.assert_eq(event.body, _expected_position(original_route, original_body, 25), "the original travelling body has reached only the published instant")
		runner.assert_eq(event.view, event.body, "the player view has projected the same committed body before later listeners")
		runner.assert_true(int(event.boundaries) >= 2, "real resident events were settled before notification")
		runner.assert_eq(int(world.simulation_work.boundaries), int(event.boundaries), "notification does not settle the world a second time")
	runner.assert_eq(GameClock.elapsed_ms, 25, "the real shared clock completes the requested interval")
	fixtures._dispose(fixture)


func _capture_future(runtime: WorldContinuityRuntime, player: PlayerCharacter) -> Variant:
	return SnapshotValues.normalized({"world": runtime.world_sim.to_dict(),
		"journey": runtime.player_journey.duplicate(true), "motion": player.motion.to_dict(),
		"position": [player.motion.position.x, player.motion.position.y],
		"clock": GameClock.to_dict()})


func _frame_reference(runner: Object) -> Variant:
	var fixture: Dictionary = _setup(runner)
	if fixture.is_empty():
		return null
	if not _start_journey(runner, fixture):
		fixtures._dispose(fixture)
		return null
	GameClock._process(0.2)
	runner.assert_eq(GameClock.elapsed_ms, 200, "unlimited real frame reaches the comparison instant")
	var result: Variant = _capture_future(fixture.continuity, fixture.player)
	fixtures._dispose(fixture)
	return result


func _budgeted_frame_and_save(runner: Object) -> void:
	var reference: Variant = _frame_reference(runner)
	if reference == null:
		return
	var fixture: Dictionary = _setup(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	var player: PlayerCharacter = fixture.player
	if not _start_journey(runner, fixture):
		fixtures._dispose(fixture)
		return
	var path: String = "user://tests/clock_world_commit_%d.json" % Time.get_ticks_usec()
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			runner.assert_true(false, "the isolated save path must not overwrite an existing file")
			fixtures._dispose(fixture)
			return
	var first: Error = runtime.save_game(path)
	var second: Error = runtime.save_game(path)
	runner.assert_true(first == OK and second == OK, "two real accepted saves establish primary and backup")
	if first != OK or second != OK:
		_remove_owned_save(path)
		fixtures._dispose(fixture)
		return
	var primary: String = FileAccess.get_file_as_string(path)
	var backup: String = FileAccess.get_file_as_string(path + ".bak")
	runner.assert_true(not primary.is_empty() and not backup.is_empty(), "both original files exist before pending-work rejection")
	var body: Dictionary = world.regions.home.actors.player
	var original_body: Dictionary = body.duplicate(true)
	var original_route: Dictionary = runtime.player_journey.duplicate(true)
	var notifications: Array[Dictionary] = []
	var reentry_results: Array = []
	var listener: Callable = func(from_ms: int, to_ms: int) -> void:
		notifications.append({"from": from_ms, "to": to_ms, "clock": GameClock.elapsed_ms,
			"world": world.elapsed_ms, "body": _point(body), "view": player.global_position})
		if reentry_results.is_empty():
			reentry_results.append(runtime.load_game(path))
			reentry_results.append(runtime.save_game(path))
	GameClock.time_advanced.connect(listener)
	runtime.settings.event_budget = 1
	GameClock._process(0.2)
	var actual: int = int(world.elapsed_ms)
	runner.assert_true(actual > 0 and actual < 50, "one actual regional event leaves the first fixed frame step partially complete")
	runner.assert_eq(GameClock.elapsed_ms, actual, "the clock publishes only the partial time actually settled")
	runner.assert_true(world.target_ms > actual and GameClock.has_pending_advance(), "both the world request and clock continuation remain pending")
	runner.assert_true(is_equal_approx(GameClock._accumulator, 200.0 - float(actual)), "completed milliseconds alone are removed from frame debt")
	runner.assert_eq(_point(body), _expected_position(original_route, original_body, actual), "a partial event budget never projects the journey to the requested future")
	runner.assert_eq(player.global_position, _point(body), "the visible player follows the partially committed original body")
	runner.assert_eq(notifications.size(), 1, "the partial commit emits one real interval, not the uncompleted endpoint")
	runner.assert_eq(reentry_results, [ERR_BUSY, ERR_BUSY], "a time listener cannot replace the world or save during its active commit")
	runner.assert_true(is_same(runtime.world_sim, world), "reentrant loading is refused before replacing the original world")
	if notifications.size() == 1:
		var event: Dictionary = notifications[0]
		runner.assert_eq([event.from, event.to, event.clock, event.world], [0, actual, actual, actual], "partial listeners see one common completed instant")
		runner.assert_eq(event.body, event.view, "the listener sees the actual partially committed body")
	runner.assert_eq(runtime.save_game(path), ERR_BUSY, "a joint save is refused while a requested interval is pending")
	runner.assert_eq(FileAccess.get_file_as_string(path), primary, "a refused save preserves the original primary bytes")
	runner.assert_eq(FileAccess.get_file_as_string(path + ".bak"), backup, "a refused save preserves the original backup bytes")
	runner.assert_true(not FileAccess.file_exists(path + ".tmp") and not FileAccess.file_exists(path + ".bak.tmp"), "a refused save creates no intermediate file")
	runtime.settings.event_budget = 4096
	GameClock._process(0.0)
	GameClock.time_advanced.disconnect(listener)
	runner.assert_eq(GameClock.elapsed_ms, 200, "restored event budget drains the exact original frame request")
	runner.assert_eq(world.elapsed_ms, 200, "the actual regional world reaches that same final instant")
	runner.assert_true(is_zero_approx(GameClock._accumulator) and not GameClock.has_pending_advance(), "frame debt and its partial cursor are exhausted once")
	runner.assert_eq(_capture_future(runtime, player), reference, "partial and uninterrupted real frames have the same world, journey, body and clock future")
	_remove_owned_save(path)
	fixtures._dispose(fixture)


func _explicit_reference(runner: Object) -> Variant:
	var fixture: Dictionary = _setup(runner)
	if fixture.is_empty():
		return null
	if not _start_journey(runner, fixture):
		fixtures._dispose(fixture)
		return null
	GameClock.advance_msec(200)
	runner.assert_eq(GameClock.elapsed_ms, 200, "unlimited explicit request reaches the comparison instant")
	var result: Variant = _capture_future(fixture.continuity, fixture.player)
	fixtures._dispose(fixture)
	return result


func _budgeted_explicit(runner: Object) -> void:
	var reference: Variant = _explicit_reference(runner)
	if reference == null:
		return
	var fixture: Dictionary = _setup(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	if not _start_journey(runner, fixture):
		fixtures._dispose(fixture)
		return
	runtime.settings.event_budget = 1
	GameClock.advance_msec(200)
	runner.assert_true(world.elapsed_ms > 0 and world.elapsed_ms < 200, "a limited explicit request stops at its actual first regional boundary")
	runner.assert_eq(GameClock.elapsed_ms, world.elapsed_ms, "an explicit partial result also keeps one committed time")
	runner.assert_true(GameClock.has_pending_advance(), "the original explicit endpoint remains pending")
	runtime.settings.event_budget = 4096
	GameClock._process(0.0)
	runner.assert_eq(GameClock.elapsed_ms, 200, "zero new wall time resumes the original explicit endpoint")
	runner.assert_eq(world.elapsed_ms, 200, "the resumed actual world reaches the same endpoint")
	runner.assert_true(not GameClock.has_pending_advance(), "completed explicit work is not replayed")
	runner.assert_eq(_capture_future(runtime, fixture.player), reference, "partial and uninterrupted explicit advances preserve the same future")
	fixtures._dispose(fixture)


func _manual_override_before_projection(runner: Object) -> void:
	var fixture: Dictionary = _setup(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	var player: PlayerCharacter = fixture.player
	if not _start_journey(runner, fixture):
		fixtures._dispose(fixture)
		return
	var body: Dictionary = world.regions.home.actors.player
	var origin: Vector2 = _point(body)
	var next_cell: Vector2i = SimRouteTravel.cell(runtime.player_journey.path[0])
	var journey_direction: Vector2 = (TileGrid.cell_to_world(next_cell) - origin).normalized()
	var intent: Vector2 = Vector2.ZERO
	for candidate: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if Vector2(candidate).dot(journey_direction) <= 0.0 and fixture.world.can_step(player.cell, candidate):
			intent = Vector2(candidate)
			break
	runner.assert_true(not intent.is_zero_approx(), "the real opening offers a walkable direction away from the automatic journey")
	if intent.is_zero_approx():
		fixtures._dispose(fixture)
		return
	player._intent = intent
	runtime.settings.event_budget = 1
	GameClock.advance_msec(50)
	var actual: int = int(world.elapsed_ms)
	var moved: Vector2 = _point(body) - origin
	runner.assert_true(actual > 0 and actual < 50, "the manual takeover is observed at a genuinely partial regional boundary")
	runner.assert_eq(GameClock.elapsed_ms, actual, "manual takeover publishes only the completed boundary")
	runner.assert_true(runtime.player_journey.is_empty(), "sampled manual input cancels the actual automatic journey")
	runner.assert_true(moved.dot(intent) > 0.0, "manual movement begins in the selected walkable direction")
	runner.assert_true(moved.dot(journey_direction) <= 0.00001, "the cancelled route never first projects the body toward the future destination")
	runner.assert_eq(player.global_position, _point(body), "manual takeover projects the same original body")
	player._intent = Vector2.ZERO
	fixtures._dispose(fixture)


func _regional_requested_limit(runner: Object) -> void:
	var fixture: Dictionary = _setup(runner)
	if fixture.is_empty():
		return
	var world: RegionalSimulation = fixture.continuity.world_sim
	var completed: bool = world.advance_to_ms(200, 1)
	var partial: int = int(world.elapsed_ms)
	runner.assert_true(not completed and partial > 0 and partial < 195, "the real regional executor retains a larger budget-limited request")
	runner.assert_eq(world.target_ms, 200, "the uncompleted original regional target remains owed")
	if completed or partial <= 0 or partial >= 195:
		fixtures._dispose(fixture)
		return
	var smaller: int = partial + 5
	runner.assert_true(world.advance_to_ms(smaller, 4096), "a later smaller requested slice can be settled")
	runner.assert_eq(world.elapsed_ms, smaller, "the retained larger target cannot make this call overshoot its requested end")
	runner.assert_eq(world.target_ms, 200, "settling a smaller slice does not discard the larger target")
	runner.assert_true(world.advance_to_ms(200, 4096), "the retained target can subsequently complete")
	runner.assert_eq([world.elapsed_ms, world.target_ms], [200, 200], "the original target and actual world reunite")
	fixtures._dispose(fixture)


func _remove_owned_save(path: String) -> void:
	# This unique path was checked absent before the test created it.
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
