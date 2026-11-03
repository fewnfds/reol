extends RefCounted
## Actual manual life, shared-clock locomotion and travel across existing body
## owners. Saving never needs to freeze a legal walk or migrate the traveller.

const Fixtures = preload("res://tests/runtime/test_conflict_runtime.gd")
const Replay = preload("res://tests/runtime/helpers/conflict_replay.gd")
const Space = preload("res://scripts/sim/conflict_space.gd")


func run(runner: Object) -> void:
	_walk_sidestep_cast(runner)
	_actual_foreign_visit(runner)
	print("SCENARIO conflict mobility: actual human walking and sidestep/cast exclusion, ordinary moving saves, real river travel/selection/learning/conflict and same joint future across original body owners")


func _scene(runner: Object) -> Dictionary:
	var fixture: Dictionary = Fixtures.new()._scene(runner)
	if fixture.is_empty():
		return fixture
	var chosen: bool = fixture.runtime.avatar_adapter.choose("subject:player")
	runner.assert_true(chosen and fixture.main.player.avatar_active, "ordinary opening chooses the actual manual human before locomotion is tested")
	GameClock.set_paused(true)
	if not chosen:
		Fixtures.new()._dispose(fixture)
		return {}
	return fixture


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime)))


func _saved_future(runner: Object, fixture: Dictionary, delta_ms: int, label: String) -> bool:
	var runtime: WorldContinuityRuntime = fixture.runtime
	var path: String = "user://tests/conflict_mobility_%d.json" % Time.get_ticks_usec()
	var present: String = _canonical(runtime)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var stage: Dictionary = WorldSessionSnapshot.stage(runtime, snapshot)
	runner.assert_true(not stage.is_empty(), label + " independently stages the actual whole scene")
	if stage.is_empty():
		return false
	var saved: Error = runtime.save_game(path)
	runner.assert_eq(saved, OK, label + " saves through the original atomic store")
	if saved != OK:
		return false
	# A saved movement velocity/action is fact; future keyboard intent is not.
	# Both branches release the key before continuing, just as a load does.
	fixture.main.player._intent = Vector2.ZERO
	GameClock.advance_msec(delta_ms)
	var future: String = _canonical(runtime)
	var loaded: Error = runtime.load_game(path)
	runner.assert_eq(loaded, OK, label + " reloads the ordinary complete candidate")
	if loaded == OK:
		runner.assert_eq(_canonical(runtime), present, label + " preserves exact saved position, velocity/phase, cost and both original owners")
		GameClock.advance_msec(delta_ms)
		runner.assert_eq(_canonical(runtime), future, label + " reaches exactly the same complete world future")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	return loaded == OK


func _walk_sidestep_cast(runner: Object) -> void:
	var fixtures: RefCounted = Fixtures.new()
	var fixture: Dictionary = _scene(runner)
	if fixture.is_empty():
		return
	if not fixtures._learn(fixture, runner):
		fixtures._dispose(fixture)
		return
	fixtures._pair(fixture, "a_he")
	var runtime: WorldContinuityRuntime = fixture.runtime
	var player: PlayerCharacter = fixture.main.player
	var ui: ConflictRuntime = fixture.ui
	runner.assert_true(ui.engage_selected().ok, "learned manual human declares an actual encounter before walking")
	var before: Vector2 = player.motion.position
	player._intent = -(fixture.arena.axis as Vector2)
	GameClock.advance_msec(50)
	runner.assert_true(not player.motion.velocity.is_zero_approx() and not player.motion.position.is_equal_approx(before), "a real positive shared interval moves the original body during the encounter's action-free gap")
	runner.assert_true(not runtime.world_sim.conflicts.action_blocks("player"), "walking sample remains in an actual free conflict phase")
	runner.assert_true(not runtime.world_sim.owns_for_scope("player", &"stationary"), "an action-free encounter does not falsely demand a stationary saved body")
	if not _saved_future(runner, fixture, 137, "walking during the actual encounter"):
		fixtures._dispose(fixture)
		return
	GameClock.advance_msec(300)
	runner.assert_true(player.motion.velocity.is_zero_approx(), "released real movement settles before the independent sidestep")
	var stamina: int = int(runtime.world_sim.conflicts.body("player").stamina)
	runner.assert_true(player.request_sidestep(-(fixture.arena.axis as Vector2)), "the free conflict phase accepts the original sidestep input")
	runner.assert_eq(runtime.world_sim.conflicts.body("player").stamina, stamina - int(player.motion.rules.sidestep.stamina), "sidestep charges original stamina once")
	GameClock.advance_msec(50)
	runner.assert_true(not player.motion.action.is_empty(), "sidestep really remains in its timed preparation at save time")
	var qi: int = int(runtime.world_sim.conflicts.body("player").qi)
	var allocations: int = runtime.world_sim.conflicts.next_cost_id
	runner.assert_true(not runtime.world_sim.conflicts.cast("player", "qi_guard", fixture.arena.axis).ok, "active sidestep excludes a simultaneous original spell")
	runner.assert_eq(runtime.world_sim.conflicts.next_cost_id, allocations, "refused spell during sidestep allocates no cost")
	runner.assert_eq(runtime.world_sim.conflicts.body("player").qi, qi, "refused spell during sidestep spends no original qi")
	if not _saved_future(runner, fixture, 113, "actual sidestep during an action-free encounter"):
		fixtures._dispose(fixture)
		return
	var end: int = int(player.motion.action.started_ms) + int(player.motion.rules.sidestep.prepare_ms) + int(player.motion.rules.sidestep.travel_ms) + int(player.motion.rules.sidestep.recover_ms)
	GameClock.advance_msec(end - GameClock.elapsed_ms)
	runner.assert_true(player.motion.action.is_empty(), "shared time completes the original sidestep before spell input")
	runner.assert_true(ui.request_cast("qi_guard"), "released body can queue an actual known spell through the input adapter")
	ui._pending_direction = fixture.arena.axis
	GameClock.advance_msec(1)
	runner.assert_eq(runtime.world_sim.conflicts.phase("player", GameClock.elapsed_ms), "prepare", "next positive shared instant starts the requested spell")
	before = player.motion.position
	player._intent = -(fixture.arena.axis as Vector2)
	GameClock.advance_msec(50)
	runner.assert_true(player.motion.position.is_equal_approx(before) and player.motion.velocity.is_zero_approx(), "active spell preparation holds the same original body against new walking input")
	runner.assert_true(not player.request_sidestep(-(fixture.arena.axis as Vector2)), "active spell preparation excludes sidestep input")
	runner.assert_true(runtime.world_sim.owns_for_scope("player", &"stationary"), "active spell still requires a stationary body in candidate checks")
	var bad: Dictionary = WorldSessionSnapshot.capture(runtime)
	bad.player.motion.velocity = [10.0, 0.0]
	runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "phase-sensitive mobility does not accept forged walking during an actual spell")
	player._intent = Vector2.ZERO
	_saved_future(runner, fixture, 149, "stationary paid spell preparation")
	ui.yield_player()
	fixtures._dispose(fixture)


func _actual_foreign_visit(runner: Object) -> void:
	var fixture: Dictionary = _scene(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.runtime
	var ui: ConflictRuntime = fixture.ui
	var travel: RefCounted = Replay.new()
	var teacher: String = "river_chen_shouzhuo"
	runner.assert_true(not runtime.world_sim.conflicts.knows("player", "qi_bolt"), "visiting life starts without the foreign teacher's martial knowledge")
	var arrived: bool = travel._travel(runtime, "river")
	runner.assert_true(arrived, "ordinary travel actually reaches the river settlement without relocating a fixture body")
	if not arrived:
		Fixtures.new()._dispose(fixture)
		return
	var adjacent: Vector2i = _teacher_neighbor(fixture, teacher)
	runner.assert_true(adjacent != Vector2i(-1, -1), "real foreign teacher has an accessible same-height neighboring place for demonstration")
	if adjacent == Vector2i(-1, -1) or not travel._travel(runtime, "river", adjacent):
		runner.assert_true(false, "ordinary travel actually approaches the foreign teacher")
		Fixtures.new()._dispose(fixture)
		return
	travel._senses(runtime)
	var view: Pawn = runtime._remote_views.get(teacher)
	runner.assert_true(view != null and runtime.select_remote_at(view.selection_center()), "ordinary remote selection resolves the visible foreign teacher after real arrival")
	runner.assert_eq(ui.selected_target(), teacher, "technique UI resolves the actual selected river resident")
	runner.assert_eq(runtime.world_sim.conflicts.home("player"), "home", "ordinary travel preserves the player's unique original body owner")
	runner.assert_eq(runtime.world_sim.conflicts.home(teacher), "river", "ordinary travel preserves the teacher's different original body owner")
	var taught: Dictionary = ui.teach_selected()
	runner.assert_true(taught.ok, "foreign teacher can actually accept a visiting pupil at their real shared location")
	if not taught.ok:
		Fixtures.new()._dispose(fixture)
		return
	var lesson_id: String = "conflict:lesson:1"
	runner.assert_eq(runtime.world_sim.conflicts.lessons[lesson_id].region, "river", "cross-owner lesson context belongs to its existing teacher owner")
	if not _saved_future(runner, fixture, 113, "foreign teacher and home-owned pupil in an actual lesson"):
		Fixtures.new()._dispose(fixture)
		return
	var due: int = int(runtime.world_sim.conflicts.lessons[lesson_id].due_ms)
	GameClock.advance_msec(due - GameClock.elapsed_ms)
	runner.assert_true(runtime.world_sim.conflicts.knows("player", "qi_bolt"), "completed foreign demonstration grants a real personally learned method")
	travel._senses(runtime)
	view = runtime._remote_views.get(teacher)
	runner.assert_true(view != null and runtime.select_remote_at(view.selection_center()), "foreign teacher remains an actual selectable person after saved demonstration")
	var began: Dictionary = ui.engage_selected()
	runner.assert_true(began.ok, "ordinary U control declares a same-place encounter across original body owners")
	if not began.ok:
		Fixtures.new()._dispose(fixture)
		return
	var id: String = runtime.world_sim.conflicts.conflict_for("player")
	runner.assert_eq(runtime.world_sim.conflicts.conflicts[id].region, "river", "foreign encounter uses defender context while original bodies stay put")
	var warned: Dictionary = {}
	for event: Dictionary in runtime.world_sim.services.social.events:
		if event.kind == "conflict_warned" and event.actor == "player" and event.target == teacher:
			warned = event
	runner.assert_true(not warned.is_empty(), "foreign encounter records its actual participants in the existing shared personal-memory book")
	if not warned.is_empty():
		var memory: SimSocialMemory = runtime.world_sim.services.social
		runner.assert_true(memory.knowledge.player.has(warned.id) and memory.knowledge[teacher].has(warned.id), "both actual cross-owner participants personally retain the encounter warning")
		runner.assert_true(not warned.witnesses.has("chen_shouzhuo") and not memory.knowledge.chen_shouzhuo.has(warned.id), "distant home teacher does not gain remote warning knowledge or witness status")
		for witness: String in warned.witnesses:
			runner.assert_true(bool(memory.knowledge[witness][warned.id].direct), "actual nearby witness personally observes the foreign warning: " + witness)
	runner.assert_true(ui.request_cast("qi_bolt"), "visiting body can request its actually learned projectile through the ordinary adapter")
	var direction: Vector2 = SimRouteTravel.point(runtime.world_sim.conflicts.body(teacher)) - fixture.main.player.motion.position
	ui._pending_direction = direction.normalized()
	GameClock.advance_msec(1)
	GameClock.advance_msec(int(runtime.world_sim.conflicts.rules.methods.qi_bolt.prepare_ms))
	runner.assert_true(not runtime.world_sim.conflicts.projectiles.is_empty(), "actual foreign encounter creates a genuinely emitted paid projectile before saving")
	_saved_future(runner, fixture, 2000, "cross-owner encounter with an actual emitted projectile")
	runner.assert_eq(runtime.world_sim.conflicts.home("player"), "home", "cross-owner contact and save never migrate the visitor's body")
	runner.assert_true(not runtime.world_sim.regions.river.actors.has("player"), "cross-owner conflict creates no duplicate local player body")
	ui.yield_player()
	Fixtures.new()._dispose(fixture)


func _teacher_neighbor(fixture: Dictionary, teacher: String) -> Vector2i:
	var runtime: WorldContinuityRuntime = fixture.runtime
	var world: RegionalSimulation = runtime.world_sim
	var origin: Vector2 = SimRouteTravel.point(world.conflicts.body(teacher))
	var cell: Vector2i = TileGrid.world_to_cell(origin)
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var next: Vector2i = cell + offset
		var point: Vector2 = TileGrid.cell_to_world(next)
		if fixture.main.world.is_walkable(next) and Space.level(world, origin) == Space.level(world, point) and Space.clear_segment(world, origin, point, Space.level(world, origin)):
			return next
	return Vector2i(-1, -1)
