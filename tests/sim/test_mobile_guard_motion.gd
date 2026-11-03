extends RefCounted
## Ordinary walking is a projection of one paid action, never a second action.

const Combat = preload("res://tests/sim/test_conflicts.gd")
var _combat := Combat.new()


class CountedMotion extends SimLocalMotion:
	var move_calls: int = 0


	func _move(displacement: Vector2, can_step: Callable, slide: bool = true) -> void:
		move_calls += 1
		super._move(displacement, can_step, slide)


func run(runner: Object) -> void:
	_local_clock_and_speed(runner)
	_paid_training_and_projection(runner)
	_npc_walking_uses_its_own_proof(runner)
	print("SCENARIO mobile guard motion: real completed practice, original cast/ready exclusion, capped old momentum and diagonal input, swept terrain, identical integer-time slices and NPC movement over the original body")


func _open(_from: Vector2i, _direction: Vector2i) -> bool:
	return true


func _local_clock_and_speed(runner: Object) -> void:
	var coarse := CountedMotion.new()
	var sliced := CountedMotion.new()
	coarse.velocity = Vector2.RIGHT * float(coarse.rules.motion.speed)
	sliced.velocity = coarse.velocity
	var fraction: float = 0.45
	var intent := Vector2(1, 1)
	coarse.advance(137, 637, intent, _open, true, fraction)
	var cursor: int = 137
	for end: int in [138, 149, 150, 187, 201, 286, 287, 401, 499, 500, 636, 637]:
		sliced.advance(cursor, end, intent, _open, true, fraction)
		cursor = end
	runner.assert_eq(sliced.position, coarse.position, "arbitrary outer millisecond cuts consume exactly the same body substeps")
	runner.assert_eq(sliced.to_dict(), coarse.to_dict(), "arbitrary cuts preserve exact heading, velocity and collision state")
	runner.assert_eq(coarse.move_calls, 500, "one complete cast consumes at most its five hundred local integer steps")
	runner.assert_true(coarse.velocity.length() <= coarse.velocity_limit(fraction) + 0.001, "diagonal input and old running momentum never exceed the guard speed cap")
	runner.assert_true(coarse.position.length() <= coarse.velocity_limit(fraction) * 0.5 + 0.001, "old full-speed velocity cannot sneak an extra running segment into the limited action")
	var immediate := SimLocalMotion.new()
	immediate.velocity = Vector2.RIGHT * float(immediate.rules.motion.speed)
	immediate.limit_walking_speed(fraction)
	runner.assert_true(immediate.velocity.length() <= immediate.velocity_limit(fraction) + 0.001, "the cast commit can cap old velocity before any positive interval or save")
	var stopped := CountedMotion.new()
	stopped.advance(0, 86400000, Vector2.ZERO, _open)
	runner.assert_eq(stopped.move_calls, 0, "one idle day performs no per-millisecond body steps")
	var wall := SimLocalMotion.new()
	wall.relocate(TileGrid.cell_to_world(Vector2i(10, 10)))
	var can_step: Callable = func(from: Vector2i, direction: Vector2i) -> bool: return from.x + direction.x <= 10
	wall.advance(0, 500, Vector2.RIGHT, can_step, true, fraction)
	runner.assert_eq(wall.cell(), Vector2i(10, 10), "limited walking still uses actual swept blocked-cell geometry")
	runner.assert_true(wall.blocked and wall.velocity.is_zero_approx(), "a solid wall stops the original body and its actual velocity")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _combat._world(runner)
	if world != null:
		world.bind_map_data(Combat.CoverMap.new())
	return world


func _train(world: RegionalSimulation, actor: String, runner: Object) -> bool:
	var response: Dictionary = world.capability_practice.begin(actor)
	runner.assert_true(response.ok, "original capable person starts a real paid practice: " + actor)
	if not response.ok:
		return false
	var end: int = int(world.capability_practice.active[actor].complete_ms)
	runner.assert_true(world.advance_to_ms(end - 1), "all real practice stages reach the final preceding millisecond")
	runner.assert_true(not world.capability_practice.learned(actor), "practice cannot grant walking before actual completion")
	runner.assert_true(world.advance_to_ms(end), "original body completes the final paid practice stage")
	runner.assert_true(world.capability_practice.learned(actor), "only the real completed proof grants the new movement use")
	return world.capability_practice.learned(actor)


func _paid_training_and_projection(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	_combat._pair(world, "chen_shouzhuo", "player", Vector2(300, 0))
	if not _train(world, "chen_shouzhuo", runner):
		return
	# The actual learned person is the responder. A role must not bypass the
	# independent reaction delay simply because the skill itself is known.
	_combat._pair(world, "shi_tou", "chen_shouzhuo", Vector2(300, 0))
	var response: Dictionary = world.conflicts.begin("shi_tou", "chen_shouzhuo")
	runner.assert_true(response.ok, "original person with a real offensive background may declare intent toward the actually trained original body")
	if not response.ok:
		return
	runner.assert_true(not world.conflicts.walking_projection("chen_shouzhuo").allowed, "a learned defender still obeys the original ready delay")
	runner.assert_true(not world.conflicts.cast("chen_shouzhuo", "qi_guard", Vector2.LEFT).ok, "knowing mobile guard cannot waive the reaction delay for casting either")
	world.advance_to_ms(world.elapsed_ms + int(world.conflicts.rules.reaction_ms))
	var qi: int = int(world.conflicts.body("chen_shouzhuo").qi)
	response = world.conflicts.cast("chen_shouzhuo", "qi_guard", Vector2.LEFT)
	runner.assert_true(response.ok, "the real ready person pays for the original guard")
	if not response.ok:
		return
	var aid: String = str(world.conflicts.conflicts[world.conflicts.conflict_for("chen_shouzhuo")].people.chen_shouzhuo.action)
	var action: Dictionary = world.conflicts.actions[aid]
	var walking: Dictionary = world.conflicts.walking_projection("chen_shouzhuo")
	runner.assert_true(walking.allowed and walking.reason == "mobile_guard" and walking.action == aid, "walking cites this exact original action and the actual prior learning")
	runner.assert_eq(walking.speed_fraction, world.capability_practice.rules.nodes.mobile_guard.speed_fraction, "walking uses the original data rule rather than a second UI constant")
	runner.assert_true(world.conflicts.action_blocks("chen_shouzhuo"), "walking permission leaves the original action lock in force")
	runner.assert_true(not world.conflicts.cast("chen_shouzhuo", "qi_bolt", Vector2.LEFT).ok, "limited walking cannot start a simultaneous original attack")
	runner.assert_true(world.owns_for_scope("chen_shouzhuo", &"manual_action") and world.owns_for_scope("chen_shouzhuo", &"player_action"), "sidestep and new player actions keep their independent phase exclusion")
	runner.assert_true(not world.owns_for_scope("chen_shouzhuo", &"automatic_motion") and not world.owns_for_scope("chen_shouzhuo", &"stationary"), "only ordinary walking and its stationary projection are relaxed")
	runner.assert_eq(world.conflicts.body("chen_shouzhuo").qi, qi - int(world.conflicts.rules.methods.qi_guard.qi), "one original guard is the only spell expense")
	var actual_start: int = int(action.started_ms)
	action.started_ms = world.capability_practice.learned_at("chen_shouzhuo") - 1
	runner.assert_true(not world.conflicts.walking_projection("chen_shouzhuo").allowed, "adversarial past action cannot borrow a practice completed after its start")
	action.started_ms = actual_start
	world.advance_to_ms(int(action.due_ms))
	runner.assert_true(world.conflicts.barriers.has("chen_shouzhuo"), "the original remaining barrier survives cast completion")
	runner.assert_eq(world.conflicts.walking_projection("chen_shouzhuo").speed_fraction, 1.0, "remaining protection does not impose the cast-only slow walk on a free manual body")
	runner.assert_true(world.conflicts.walking_projection("chen_shouzhuo").allowed, "cast completion restores the original ordinary walking gap")


func _npc_walking_uses_its_own_proof(runner: Object) -> void:
	for trained: bool in [false, true]:
		var world: RegionalSimulation = _world(runner)
		if world == null:
			return
		var actor: String = "river_chen_shouzhuo"
		_combat._pair(world, actor, "player", Vector2(300, 0))
		if trained and not _train(world, actor, runner):
			return
		world.conflicts.body(actor).autonomous = true
		world.invalidate_region("river")
		runner.assert_true(world.conflicts.begin(actor, "player").ok, "original foreign-owned NPC commits an encounter using its own policy")
		runner.assert_true(world.conflicts.cast(actor, "qi_guard", Vector2.RIGHT).ok, "original foreign-owned NPC pays for its own protective action")
		var before: Vector2 = SimRouteTravel.point(world.conflicts.body(actor))
		world.advance_to_ms(world.elapsed_ms + int(world.conflicts.rules.step_ms))
		var distance: float = before.distance_to(SimRouteTravel.point(world.conflicts.body(actor)))
		if trained:
			var limit: float = float(world.regions.river.motion_rules.motion.speed) * float(world.conflicts.rules.ai_speed_fraction) * float(world.capability_practice.rules.nodes.mobile_guard.speed_fraction) * float(world.conflicts.rules.step_ms) / 1000.0
			runner.assert_true(distance > 0.0 and distance <= limit + 0.001, "trained NPC walks its original body with both original AI and learned guard speed fractions")
		else:
			runner.assert_eq(distance, 0.0, "untrained NPC cannot walk during the exact same original guard action")
		runner.assert_eq(world.conflicts.actions.size(), 1, "slow walking never creates a second autonomous cast")
		runner.assert_eq(world.conflicts.home(actor), "river", "local combat movement never migrates the NPC's persistent original body owner")
