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
	_settlement_continuation(runner)
	_continuous_canvas_publication(runner)
	_test_cancel_during_settlement(runner)
	_settlement_failure_recovery(runner)
	_construction_publication(runner)
	_queued_save(runner)
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
	GameClock.advance_frame(0.2)
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
	GameClock.advance_frame(0.2)
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
	GameClock.advance_frame(0.0)
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
	GameClock.advance_frame(0.0)
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


func _settlement_continuation(runner: Object) -> void:
	var original: Dictionary = _setup(runner)
	if original.is_empty():
		return
	var original_runtime: WorldContinuityRuntime = original.continuity
	if not _start_journey(runner, original):
		fixtures._dispose(original)
		return
	GameClock.advance_msec(25)
	var expected: Variant = _capture_future(original_runtime, original.player)
	fixtures._dispose(original)
	var fixture: Dictionary = _setup(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	if not _start_journey(runner, fixture):
		fixtures._dispose(fixture)
		return
	var world: RegionalSimulation = runtime.world_sim
	var initial: Dictionary = world.to_dict()
	var notifications: Array = []
	var region_notifications: Array = []
	var region_listener: Callable = func() -> void: region_notifications.append(GameClock.elapsed_ms)
	fixture.home.simulation_advanced.connect(region_listener)
	var listener: Callable = func(_from_ms: int, to_ms: int) -> void:
		notifications.append(to_ms == world.elapsed_ms and not world.settlement.is_pending() and fixture.player.global_position == _point(world.regions.home.actors.player))
	GameClock.time_advanced.connect(listener)
	runtime.settlement_work_budget = 1
	GameClock.advance_msec(25)
	runner.assert_true(world.settlement.is_pending() and GameClock.has_pending_advance(), "a one-work allowance retains the original domain-stage continuation")
	runner.assert_eq(GameClock.elapsed_ms, 0, "the public clock does not publish a half-settled first boundary")
	runner.assert_true(world.to_dict().is_empty() and not world.restore(initial), "partial phase state cannot be saved or replaced by a load")
	runner.assert_true(not world.actor_controls("player", "action") and world.describe_object({"kind": "actor", "id": "player"}).reason == "settlement_pending", "new commands and common object queries cannot consume a partial boundary")
	var held_position: Vector2 = fixture.player.global_position
	var held_progress: Dictionary = world.settlement.progress()
	GameClock._frame_deadline_usec = 1
	runner.assert_eq(runtime.advance_to_ms(25), 0, "an already exhausted host deadline cannot publish a pending world")
	runner.assert_eq(fixture.player.global_position, held_position, "deadline refusal keeps the last complete body projection")
	runner.assert_eq(world.settlement.progress(), held_progress, "deadline refusal does not restart or skip the held causal step")
	GameClock._frame_deadline_usec = 0
	for _attempt: int in 1000:
		if not GameClock.has_pending_advance():
			break
		GameClock.advance_frame(0.0)
	GameClock.time_advanced.disconnect(listener)
	fixture.home.simulation_advanced.disconnect(region_listener)
	if GameClock.has_pending_advance():
		print("SETTLEMENT continuation diagnostic ", world.settlement.progress(), " clock=", GameClock.elapsed_ms, " world=", world.elapsed_ms, " settled=", world.settled_ms(), " errors=", world.errors, " paused=", GameClock.paused)
	runner.assert_true(not GameClock.has_pending_advance() and not world.settlement.is_pending(), "bounded work drains the existing handle to its original target")
	runner.assert_true(not notifications.is_empty() and not notifications.has(false), "all time listeners observe complete world boundaries and the same body projection")
	runner.assert_true(not region_notifications.is_empty() and not fixture.home._clock_interval_had_events, "regional changes during an earlier continuation notify once the public interval commits and clear their debt")
	runner.assert_true(_capture_future(runtime, fixture.player) == expected, "per-stage continuation preserves the full original clock/body/route/world future")
	fixtures._dispose(fixture)


func _test_cancel_during_settlement(runner: Object) -> void:
	var fixture: Dictionary = _setup(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	var home: VillageSimulation = world.regions.home
	var started: bool = home.submit_action("player", "deliver_wood")
	runner.assert_true(started, "cancel barrier fixture starts original hauling with real material reservations")
	if not started:
		fixtures._dispose(fixture)
		return
	world.invalidate_region("home")
	runtime.settlement_work_budget = 1
	GameClock.advance_msec(25)
	runner.assert_true(world.settlement.is_pending(), "original hauling reaches a suspended world boundary")
	var held_action: Dictionary = home.actors.player.active.duplicate(true)
	var held_inventory: Dictionary = home.inventory.to_dict()
	runner.assert_true(not held_action.is_empty() and not held_action.reservations.is_empty(), "pending hauling still owns its original reservations")
	runner.assert_true(not runtime.stop_player_action(), "ordinary stop reports rejection while settlement is pending")
	fixture.home.cancel_player_action()
	var service_panel: SettlementServicesPanel = runtime.service_adapter.panel
	var held_details: Array[String] = [service_panel._activity.text, service_panel._details.text, service_panel._phase.text]
	var response: Dictionary = runtime.service_adapter.submit("cancel")
	runner.assert_true(not response.ok and "未受理" in str(response.line), "service UI reports the refused stop instead of claiming success")
	runner.assert_eq(service_panel._notice.text, response.line, "pending stop refusal is immediately visible in the actual service panel")
	runner.assert_eq([service_panel._activity.text, service_panel._details.text, service_panel._phase.text], held_details, "command feedback does not refresh partial activity or inventory facts")
	var spirit_details: String = runtime.spirit_adapter.panel._description.text
	var spirit_response: Dictionary = runtime.spirit_adapter._reply(false, "pending feedback probe")
	runner.assert_eq(runtime.spirit_adapter.panel._notice.text, spirit_response.line, "spirit-source feedback also crosses the projection guard immediately")
	runner.assert_eq(runtime.spirit_adapter.panel._description.text, spirit_details, "spirit-source command feedback leaves partial world facts alone")
	runner.assert_eq(home.actors.player.active, held_action, "ordinary and manual cancellation cannot change a partially settled native action")
	runner.assert_eq(home.inventory.to_dict(), held_inventory, "rejected cancellation cannot release or spend original material reservations")
	runtime.settlement_work_budget = 2147483647
	for _attempt: int in 100:
		if not GameClock.has_pending_advance():
			break
		GameClock.advance_frame(0.0)
	runner.assert_true(not GameClock.has_pending_advance(), "the same hauling boundary finishes before accepting a new stop")
	runner.assert_true(runtime.stop_player_action(), "a stop is accepted after the world boundary completes")
	runner.assert_true(home.actors.player.active.is_empty(), "accepted stop ends the original native action")
	for reservation: String in held_action.reservations:
		runner.assert_true(not home.inventory.reservations.has(reservation), "accepted stop releases its actual material reservation")
	# A checked owner failure is terminal, not another opportunity for UI
	# cancellation to mutate the incomplete world. No callback is retried.
	started = home.submit_action("player", "deliver_wood")
	runner.assert_true(started, "failed-boundary probe starts another real reserved action")
	if started:
		var kernel := SimSettlementKernel.new([&"failure"])
		kernel.add_step(&"rejected_owner", &"failure", func(_at_ms: int) -> bool: return false, SimSettlementKernel.CallMode.CHECKED)
		kernel.compile()
		world.settlement = kernel
		kernel.begin(world.elapsed_ms, world.elapsed_ms + 1)
		runner.assert_eq(kernel.resume(1), SimSettlementKernel.Status.FAILED, "failure probe reaches the actual terminal kernel state")
		held_action = home.actors.player.active.duplicate(true)
		held_inventory = home.inventory.to_dict()
		runner.assert_true(not runtime.stop_player_action(), "ordinary stop also rejects a failed incomplete boundary")
		fixture.home.cancel_player_action()
		response = runtime.service_adapter.submit("cancel")
		runner.assert_true(not response.ok, "failed-boundary UI cannot claim the stop succeeded")
		runner.assert_eq(service_panel._notice.text, response.line, "terminal failure cannot hide the actual stop refusal indefinitely")
		runner.assert_eq(home.actors.player.active, held_action, "failed-boundary stop preserves original action state")
		runner.assert_eq(home.inventory.to_dict(), held_inventory, "failed-boundary stop preserves original material reservations")
	fixtures._dispose(fixture)


func _continuous_canvas_publication(runner: Object) -> void:
	var fixture: Dictionary = _setup(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	if not _start_journey(runner, fixture):
		fixtures._dispose(fixture)
		return
	var world: RegionalSimulation = runtime.world_sim
	runtime.settlement_work_budget = 1
	var observed: Array[bool] = []
	var listener: Callable = func(_from: int, at: int) -> void:
		observed.append(runtime._canvas_at_ms == at and runtime.construction_adapter._canvas_at_ms == at and runtime.avian_adapter._canvas_at_ms == at and fixture.home._canvas_at_ms == at)
	GameClock.time_advanced.connect(listener)
	# Keep adding real wall time. Each completed old interval can immediately
	# start another suspended interval before a deferred _draw ever occurs.
	for _attempt: int in 500:
		GameClock.advance_frame(0.05)
		if observed.size() >= 2 and world.settlement.is_pending():
			break
	GameClock.time_advanced.disconnect(listener)
	runner.assert_true(observed.size() >= 2 and world.settlement.is_pending(), "continuous one-work frames publish multiple old intervals while the next interval is already pending")
	runner.assert_true(not observed.has(false), "every public clock boundary synchronously captures all representative canvases before the next interval")
	runner.assert_eq(runtime.construction_adapter._canvas_at_ms, GameClock.elapsed_ms, "pending draw playback uses the latest published boundary, never an arbitrarily old picture")
	fixtures._dispose(fixture)


func _settlement_failure_recovery(runner: Object) -> void:
	var fixture: Dictionary = _setup(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var path: String = "user://tests/clock_failure_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "failure recovery starts with a coherent complete session")
	var expected: Variant = _capture_future(runtime, fixture.player)
	var calls: Array[int] = [0]
	var kernel := SimSettlementKernel.new([&"test"])
	kernel.add_step(&"fails_once", &"test", func(_ms: int) -> bool:
		calls[0] += 1
		return false, SimSettlementKernel.CallMode.CHECKED)
	kernel.compile()
	runtime.world_sim.settlement = kernel
	GameClock.advance_msec(25)
	runner.assert_true(kernel.has_failed() and GameClock.paused, "a real checked callback failure becomes a paused terminal state")
	runner.assert_eq(calls[0], 1, "the failing owner was invoked only once")
	runner.assert_true("fails_once" in runtime._panel._notice.text and "读取" in runtime._panel._notice.text, "ordinary UI displays the failed step and a usable recovery route")
	for _attempt: int in 3:
		GameClock.set_paused(false)
		GameClock.advance_frame(0.0)
		runner.assert_true(GameClock.paused, "unpausing cannot restart terminal failed work")
	runner.assert_eq(calls[0], 1, "terminal state neither replays effects nor retries the owner")
	runner.assert_eq(GameClock.elapsed_ms, 0, "failure never publishes the unfinished clock")
	runner.assert_eq(runtime.save_game(path), ERR_BUSY, "failed partial state cannot overwrite the complete archive")
	var primary: String = FileAccess.get_file_as_string(path)
	var receipts: Array = []
	runtime.save_finished.connect(func(_path: String, result: Error) -> void: receipts.append(result))
	runner.assert_eq(runtime.request_save(path), OK, "ordinary saving returns a request receipt even in a failed world")
	runtime._process(0.0)
	runner.assert_eq(receipts, [ERR_INVALID_DATA], "failed settlement terminates the queued request without retrying the owner")
	runner.assert_eq(FileAccess.get_file_as_string(path), primary, "failed queued saving preserves the last complete archive")
	runner.assert_eq(runtime.load_game(path), OK, "a valid complete session replaces the failed world between frames")
	runner.assert_eq(_capture_future(runtime, fixture.player), expected, "recovery restores original owners, clock and complete world")
	GameClock.advance_msec(25)
	runner.assert_eq(GameClock.elapsed_ms, 25, "the restored session can advance normally")
	_remove_owned_save(path)
	fixtures._dispose(fixture)


func _construction_publication(runner: Object) -> void:
	var fixture: Dictionary = _setup(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	for region: VillageSimulation in world.regions.values():
		for actor: String in region.actors:
			region.actors[actor].autonomous = false
			region.cancel_action(actor, "publication_fixture")
	var view: ConstructionRuntime = runtime.construction_adapter
	var source: Vector2i = SimRouteTravel.cell(world.regions.home.places[world.construction.definitions.site.source].cell)
	world.regions.home.set_actor_cell("player", source)
	var origin: Vector2i = view.find_yard_origin()
	var registered: Dictionary = world.construction.register_site("player", origin)
	runner.assert_true(registered.ok, "publication probe registers a yard near the actual runtime store")
	var placed: Dictionary = {"ok": false}
	if registered.ok:
		for cell: Vector2i in SimConstruction.cells_in(world.construction.site_bounds(str(registered.site))):
			if SimMotionClearance.fixed_road_reserves(world, cell) or world.construction.occupied(cell):
				continue
			placed = world.construction.place("player", "wood_wall", cell)
			if placed.ok:
				break
	var project: String = str(placed.get("project", ""))
	var started: bool = bool(placed.ok) and bool(world.construction.begin("player", project).ok)
	runner.assert_true(started, "publication probe begins a real material-backed wall")
	if not started:
		fixtures._dispose(fixture)
		return
	# Reach a genuine work phase without changing the product work duration.
	for _attempt: int in 100:
		if world.construction.active.get("player", {}).get("phase") == "work":
			break
		var next: int = world.construction.next_boundary_ms()
		GameClock.advance_msec(next - GameClock.elapsed_ms)
	if world.construction.active.get("player", {}).get("phase") != "work":
		runner.assert_true(false, "publication probe reaches the original work phase")
		fixtures._dispose(fixture)
		return
	view.show_panel()
	view.refresh_choices(project)
	view.refresh()
	view.refresh_committed_canvas()
	var prior_details: String = view._details.text
	var prior_commands: Array[Callable] = view._canvas_commands.duplicate()
	var notices: Array[Dictionary] = []
	var listener: Callable = func(result: Dictionary) -> void: notices.append(result)
	world.action_finished.connect(listener)
	var due: int = int(world.construction.active.player.due_ms)
	# Only the completion boundary needs a one-work policy; do not spend a
	# permanent regression on thousands of unrelated three-minute continuations.
	GameClock.advance_msec(due - GameClock.elapsed_ms - 1)
	for _attempt: int in 1000:
		if not GameClock.has_pending_advance():
			break
		GameClock.advance_frame(0.0)
	runner.assert_eq(GameClock.elapsed_ms, due - 1, "publication probe reaches the last complete millisecond before real construction completion")
	prior_details = view._details.text
	view.refresh_committed_canvas()
	prior_commands = view._canvas_commands.duplicate()
	runtime.settlement_work_budget = 1
	GameClock.advance_msec(1)
	var held: bool = false
	for _attempt: int in 1000:
		if world.construction.projects[project].state == "built" and world.settlement.is_pending():
			held = true
			break
		if not GameClock.has_pending_advance():
			break
		prior_details = view._details.text
		prior_commands = view._canvas_commands.duplicate()
		GameClock.advance_frame(0.0)
	runner.assert_true(held, "the real wall commits inside its domain before the later world stages finish")
	if not held:
		print("PUBLICATION diagnostic ", world.construction.projects[project], " active=", world.construction.active, " stage=", world.settlement.progress(), " clock=", GameClock.elapsed_ms, " due=", due)
	if held:
		view.refresh()
		view.refresh_committed_canvas()
		runner.assert_eq(notices.size(), 0, "domain completion does not publish a partial world action result")
		runner.assert_eq(view._details.text, prior_details, "the open construction book retains its complete-state details")
		runner.assert_eq(view._canvas_commands, prior_commands, "a pending redraw retains the last complete construction drawing")
		runner.assert_true(not view._pending_sight_cells.is_empty(), "sight changes remain owed to the public projection")
	runtime.settlement_work_budget = 4096
	for _attempt: int in 1000:
		if not GameClock.has_pending_advance():
			break
		GameClock.advance_frame(0.0)
	world.action_finished.disconnect(listener)
	runner.assert_true(not GameClock.has_pending_advance(), "default work policy finishes the original request")
	runner.assert_eq(notices.size(), 1, "the completed world publishes the real action result once")
	runner.assert_true(view._pending_sight_cells.is_empty(), "completed clock publication flushes sight invalidation")
	runner.assert_true(view._details.text != prior_details and view._canvas_commands != prior_commands, "complete publication updates both details and cached drawing")
	fixtures._dispose(fixture)


func _queued_save(runner: Object) -> void:
	var fixture: Dictionary = _setup(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	runner.assert_true(runtime._panel.save_requested.is_connected(runtime._home.request_save), "ordinary save button shares the queued boundary coordinator")
	if not _start_journey(runner, fixture):
		fixtures._dispose(fixture)
		return
	var path: String = "user://tests/queued_world_%d.json" % Time.get_ticks_usec()
	runtime.settings.event_budget = 1
	runtime.settlement_work_budget = 1
	GameClock.advance_msec(25)
	runner.assert_true(GameClock.has_pending_advance() and runtime.world_sim.settlement.is_pending(), "a real multi-domain boundary is split before the save request")
	var receipts: Array = []
	runtime.save_finished.connect(func(_path: String, result: Error) -> void: receipts.append(result))
	runner.assert_eq(runtime.request_save(path), OK, "the ordinary runtime accepts saving without a complete boundary yet")
	runner.assert_true(receipts.is_empty() and not FileAccess.file_exists(path), "acceptance never reports a file as already written")
	GameClock.set_paused(true)
	for _frame: int in 4096:
		if not runtime._saves.pending():
			break
		GameClock.advance_frame(1.0)
		runtime._process(0.0)
	runner.assert_eq(receipts, [OK], "budget-one work completes with exactly one successful file receipt")
	runner.assert_true(not GameClock.has_pending_advance() and GameClock.elapsed_ms == 25 and GameClock.paused, "saving finishes accepted time without new frame admission or unpausing")
	if receipts == [OK]:
		var saved: Dictionary = SimSaveStore.load_file(path).data
		runner.assert_eq(saved.clock.elapsed_ms, 25.0, "the file has the complete original endpoint")
		runtime.settings.event_budget = 4096
		runtime.settlement_work_budget = 4096
		GameClock.advance_msec(250)
		var future: Variant = _capture_future(runtime, fixture.player)
		runner.assert_eq(runtime.load_game(path), OK, "the queued complete session passes the ordinary candidate loader")
		runtime.settings.event_budget = 4096
		GameClock.advance_msec(250)
		runner.assert_eq(_capture_future(runtime, fixture.player), future, "queued saving preserves the same original bodies, journey, owners and future")
	_remove_owned_save(path)
	fixtures._dispose(fixture)


func _remove_owned_save(path: String) -> void:
	# This unique path was checked absent before the test created it.
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
