extends RefCounted
## Controlled arena, actual learning/payment/input: does the new walk matter?
## Initial placement is a fixture. No resource, learning or outcome is injected.

const Fixtures = preload("res://tests/runtime/test_conflict_runtime.gd")
const Handoff = preload("res://tests/runtime/test_mobile_guard_handoff.gd")
const Space = preload("res://scripts/sim/conflict_space.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_same_committed_ray_different_choices(runner)
	_untrained_guard_keeps_the_original_lock(runner)
	print("SCENARIO mobile guard tactics: same genuinely committed ray and before-choice save, stationary guard spends its actual capacity while learned slow sidestep avoids the ray during the same paid five-hundred-millisecond cast; untrained walking remains locked")


func _scene(runner: Object, trained: bool) -> Dictionary:
	var fixture: Dictionary = Handoff.new()._scene(runner) if trained else _fixtures._scene(runner)
	if fixture.is_empty():
		return fixture
	if not trained and (not fixture.runtime.avatar_adapter.choose("subject:player") or not _fixtures._learn(fixture, runner)):
		_fixtures._dispose(fixture)
		return {}
	var arena: Dictionary = _arena(fixture)
	runner.assert_true(not arena.is_empty(), "actual generated map has a level ray lane and a perpendicular walkable margin")
	if arena.is_empty():
		_fixtures._dispose(fixture)
		return {}
	fixture["tactics"] = arena
	var main: Node = fixture.main
	var runtime: WorldContinuityRuntime = fixture.runtime
	# This is controlled initial arena placement, before hostile commitment.
	# All later motion, emissions, costs, hits and protection use product rules.
	main.player.motion.relocate(arena.point)
	main.player._project_motion()
	runtime.world_sim.regions.home.set_actor_position("chen_shouzhuo", arena.shooter)
	runtime.world_sim.invalidate_region("home")
	runtime.home_runtime()._sync_actor_views(true)
	main.fog.set_focus(main.player.cell)
	main.fog.update_now()
	main._process(0.0)
	runtime.home_runtime().select_actor("chen_shouzhuo")
	var response: Dictionary = fixture.ui.engage_selected()
	runner.assert_true(response.ok, "normal selected-target UI commits the actual encounter over the two original bodies")
	if not response.ok:
		_fixtures._dispose(fixture)
		return {}
	var domain: SimConflicts = runtime.world_sim.conflicts
	GameClock.advance_msec(int(domain.rules.reaction_ms))
	response = domain.cast("chen_shouzhuo", "qi_bolt", arena.axis)
	runner.assert_true(response.ok, "the original ready teacher really commits and pays for the aimed bolt")
	if not response.ok:
		_fixtures._dispose(fixture)
		return {}
	var row: Dictionary = domain.conflicts[domain.conflict_for("chen_shouzhuo")]
	var shot_action: String = str(row.people.chen_shouzhuo.action)
	GameClock.advance_msec(int(domain.rules.methods.qi_bolt.prepare_ms))
	runner.assert_true(domain.projectiles.has(shot_action), "the comparison begins only after the actual ray has emitted with immutable original direction")
	if not domain.projectiles.has(shot_action):
		_fixtures._dispose(fixture)
		return {}
	fixture["shot"] = shot_action
	fixture["choice_ms"] = GameClock.elapsed_ms
	return fixture


func _arena(fixture: Dictionary) -> Dictionary:
	var main: Node = fixture.main
	var world: RegionalSimulation = fixture.runtime.world_sim
	var cells: Array[Vector2i] = VillageRuntime.find_reachable_cells(main.world, main.player.cell, 24, 4096)
	for cell: Vector2i in cells:
		var point: Vector2 = TileGrid.cell_to_world(cell) + Vector2(3.25, -2.5)
		var level: int = Space.level(world, point)
		for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
			# At 440 px/s, this committed ray reaches the target on its real
			# 400ms sample: after guard onset (151ms) and before cast end (501ms).
			var shooter: Vector2 = point - axis * 176.0
			var ray_end: Vector2 = point + axis * 88.0
			if not main.world.is_walkable(TileGrid.world_to_cell(shooter)) or Space.level(world, shooter) != level or not Space.clear_segment(world, shooter, ray_end, level):
				continue
			var occupied: bool = false
			for sim: VillageSimulation in world.regions.values():
				for actor: String in sim.actors:
					if actor not in ["player", "chen_shouzhuo"] and Space.segment_distance(shooter, ray_end, SimRouteTravel.point(sim.actors[actor])) <= 32.0:
						occupied = true
			if occupied:
				continue
			for side: Vector2 in [Vector2(-axis.y, axis.x), Vector2(axis.y, -axis.x)]:
				var margin: Vector2 = point + side * 64.0
				if not main.world.is_walkable(TileGrid.world_to_cell(margin)) or Space.level(world, margin) != level or not Space.clear_segment(world, point, margin, level):
					continue
				var walkable: bool = true
				var cursor: Vector2 = point
				for index: int in range(1, 9):
					var next: Vector2 = point + side * float(index) * 8.0
					if not Space.can_step(world, TileGrid.world_to_cell(cursor), TileGrid.world_to_cell(next)):
						walkable = false
						break
					cursor = next
				if walkable:
					return {"point": point, "shooter": shooter, "axis": axis, "side": side}
	return {}


func _guard(fixture: Dictionary, intent: Vector2, runner: Object) -> String:
	var player: PlayerCharacter = fixture.main.player
	player._intent = Vector2.ZERO
	var ui: ConflictRuntime = fixture.ui
	runner.assert_true(ui.request_cast("qi_guard"), "ordinary guard input queues the existing personally learned protective technique")
	ui._pending_direction = -(fixture.tactics.axis as Vector2)
	GameClock.advance_msec(1)
	var domain: SimConflicts = fixture.runtime.world_sim.conflicts
	var row: Dictionary = domain.conflicts[domain.conflict_for("player")]
	var aid: String = str(row.people.player.action)
	runner.assert_true(not aid.is_empty() and domain.actions[aid].method == "qi_guard", "the next actual millisecond starts a paid original guard, not a new special attack")
	if aid.is_empty():
		return ""
	player._intent = intent
	return aid


func _player_hit(domain: SimConflicts, shot: String) -> Dictionary:
	for hit: Dictionary in domain.hits.values():
		if hit.actor == "player" and hit.action == shot:
			return hit
	return {}


func _same_committed_ray_different_choices(runner: Object) -> void:
	var fixture: Dictionary = _scene(runner, true)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.runtime
	var player: PlayerCharacter = fixture.main.player
	var path: String = "user://tests/mobile_guard_tactics_%d.json" % Time.get_ticks_usec()
	var choice_ms: int = int(fixture.choice_ms)
	var shot: String = str(fixture.shot)
	var original_shot: Dictionary = runtime.world_sim.conflicts.projectiles[shot].duplicate(true)
	var original_qi: int = int(runtime.world_sim.conflicts.body("player").qi)
	var original_stamina: int = int(runtime.world_sim.conflicts.body("player").stamina)
	var save_error: Error = runtime.save_game(path)
	runner.assert_eq(save_error, OK, "one actual before-choice save contains the fully emitted ray and original paid learning")
	if save_error != OK:
		_fixtures._dispose(fixture)
		return
	var aid: String = _guard(fixture, Vector2.ZERO, runner)
	if aid.is_empty():
		_remove(path)
		_fixtures._dispose(fixture)
		return
	GameClock.advance_msec(choice_ms + 450 - GameClock.elapsed_ms)
	var stationary: SimConflicts = runtime.world_sim.conflicts
	var hit: Dictionary = _player_hit(stationary, shot)
	runner.assert_true(not hit.is_empty(), "standing protective choice really receives the same emitted ray")
	if not hit.is_empty():
		runner.assert_eq(int(hit.absorbed), int(stationary.rules.methods.qi_guard.capacity), "stationary choice actually spends finite original shield capacity")
		runner.assert_eq(int(hit.impact), 0, "original guard protects the stationary body rather than inventing a dodge")
		runner.assert_true(int(hit.at_ms) < int(stationary.actions[aid].due_ms), "stationary contact occurs inside the original five-hundred-millisecond cast")
	runner.assert_true(not stationary.barriers.has("player"), "the stationary guard's fully used capacity is genuinely gone")
	var stationary_qi: int = int(stationary.body("player").qi)
	var stationary_stamina: int = int(stationary.body("player").stamina)
	var stationary_cost: Dictionary = {"qi": stationary.actions[aid].qi_spent, "stamina": stationary.actions[aid].stamina_spent, "duration": int(stationary.actions[aid].due_ms) - int(stationary.actions[aid].started_ms)}
	runner.assert_true(stationary.action_blocks("player"), "stationary cast remains active at the tactical comparison instant")
	var loaded: Error = runtime.load_game(path)
	runner.assert_eq(loaded, OK, "sideways choice restores that same actual before-choice ray rather than generating a favorable second shot")
	if loaded != OK:
		_remove(path)
		_fixtures._dispose(fixture)
		return
	runner.assert_eq(SnapshotValues.normalized(runtime.world_sim.conflicts.projectiles[shot]), SnapshotValues.normalized(original_shot), "the second choice has exactly the same original ray origin, direction, emission and advance state")
	aid = _guard(fixture, fixture.tactics.side, runner)
	if aid.is_empty():
		_remove(path)
		_fixtures._dispose(fixture)
		return
	GameClock.advance_msec(choice_ms + 450 - GameClock.elapsed_ms)
	var moving: SimConflicts = runtime.world_sim.conflicts
	runner.assert_true(_player_hit(moving, shot).is_empty(), "real learned slow walking leaves the already committed ray clear of the original player")
	runner.assert_true(moving.barriers.has("player"), "the moving choice retains its real protective barrier")
	if moving.barriers.has("player"):
		runner.assert_eq(moving.barriers.player.remaining, moving.rules.methods.qi_guard.capacity, "avoiding the ray preserves all original paid guard capacity")
	runner.assert_true((player.motion.position - (fixture.tactics.point as Vector2)).dot(fixture.tactics.side) > float(moving.rules.projectile_radius), "the actual original body has moved laterally outside the committed hit radius")
	runner.assert_eq(moving.body("player").qi, stationary_qi, "the two meaningful outcomes pay the same actual original qi")
	runner.assert_eq(moving.body("player").stamina, stationary_stamina, "the two meaningful outcomes pay the same actual original stamina")
	runner.assert_eq(moving.body("player").qi, original_qi - int(moving.rules.methods.qi_guard.qi), "the tactical use spends exactly one original protective cost")
	runner.assert_eq(moving.body("player").stamina, original_stamina - int(moving.rules.methods.qi_guard.stamina), "ordinary lateral walking does not duplicate the action's stamina expense")
	var moving_cost: Dictionary = {"qi": moving.actions[aid].qi_spent, "stamina": moving.actions[aid].stamina_spent, "duration": int(moving.actions[aid].due_ms) - int(moving.actions[aid].started_ms)}
	runner.assert_eq(moving_cost, stationary_cost, "the actual original action timing and resource commitment are identical across both choices")
	runner.assert_eq(int(moving_cost.duration), 500, "the useful adjustment fits inside the unchanged original five-hundred-millisecond guard cast")
	runner.assert_true(moving.action_blocks("player"), "a successful tactical miss never releases the original ongoing cast lock")
	runner.assert_true(not player.request_sidestep(fixture.tactics.side), "the useful walk is still ordinary walking, not an extra simultaneous evasive action")
	player._intent = Vector2.ZERO
	_remove(path)
	_fixtures._dispose(fixture)


func _untrained_guard_keeps_the_original_lock(runner: Object) -> void:
	var fixture: Dictionary = _scene(runner, false)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.runtime
	var player: PlayerCharacter = fixture.main.player
	runner.assert_true(runtime.world_sim.conflicts.knows("player", "qi_guard") and not runtime.world_sim.capability_practice.learned("player"), "control body actually knows the original guard but has never completed the new practice")
	var start: Vector2 = player.motion.position
	var aid: String = _guard(fixture, fixture.tactics.side, runner)
	if not aid.is_empty():
		GameClock.advance_msec(int(fixture.choice_ms) + 450 - GameClock.elapsed_ms)
		var domain: SimConflicts = runtime.world_sim.conflicts
		runner.assert_eq(player.motion.position, start, "the same ordinary sideways input cannot move an untrained protective caster")
		runner.assert_true(player.motion.velocity.is_zero_approx() and domain.action_blocks("player"), "old guard retains both real velocity stop and original cast commitment")
		runner.assert_true(not _player_hit(domain, str(fixture.shot)).is_empty(), "the untrained body still actually receives the committed ray")
		runner.assert_true(not domain.barriers.has("player"), "the untrained stationary guard really spends its finite capacity instead of receiving the new use for free")
	player._intent = Vector2.ZERO
	_fixtures._dispose(fixture)


func _remove(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
