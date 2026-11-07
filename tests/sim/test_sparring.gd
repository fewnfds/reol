extends RefCounted

const Fixtures = preload("res://tests/sim/test_regional_simulation.gd")
var _fixtures: RefCounted = Fixtures.new()


func run(runner: Object) -> void:
	_test_stages_and_once(runner)
	_test_geometry_and_mutual_hits(runner)
	_test_ai_approaches_before_blocked_strike(runner)
	_test_hit_does_not_shorten_pause(runner)
	_test_sparse_restore(runner)
	_test_consent_ownership_and_loss(runner)
	_test_bad_state_atomic(runner)


func _make(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _fixtures._make_world(runner)
	var sim: VillageSimulation = world.regions.home
	var origin: Vector2 = sim.actor_position(sim.actors.player)
	sim.set_actor_position("shi_tou", origin + Vector2(80, 0))
	world.invalidate_region("home")
	return world


func _begin(world: RegionalSimulation, runner: Object) -> void:
	runner.assert_true(bool(world.sparring.invite("player", "shi_tou").ok), "rested nearby residents voluntarily agree to practice")


func _state(world: RegionalSimulation) -> int:
	return JSON.stringify(JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true)), "", true, true).hash()


func _test_stages_and_once(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	_begin(world, runner)
	var domain: SimSparring = world.sparring
	var player: Dictionary = world.regions.home.actors.player
	runner.assert_true(domain.strike("player", Vector2.RIGHT), "practice strike is accepted through original action ownership")
	runner.assert_eq(player.stamina, 95, "strike immediately pays from the original body")
	runner.assert_true(not domain.strike("player", Vector2.RIGHT), "repeated input cannot overlap an accepted main action")
	world.advance_to_ms(299)
	runner.assert_eq(domain.phase("player", world.elapsed_ms), "prepare", "one millisecond before contact remains preparation")
	runner.assert_eq(domain.bout.people.player.hits, 0, "preparation never inflicts hidden early hits")
	var stamina: int = int(world.regions.home.actors.shi_tou.stamina)
	world.advance_to_ms(300)
	runner.assert_eq(domain.bout.people.player.hits, 1, "geometric contact begins at the precise preparation boundary")
	runner.assert_eq(world.regions.home.actors.shi_tou.stamina, stamina - 14, "contact strains the target's original persistent stamina")
	world.advance_to_ms(400)
	runner.assert_eq(domain.phase("player", world.elapsed_ms), "recover", "contact interval ends at its declared boundary")
	runner.assert_eq(domain.bout.people.player.hits, 1, "the same contact window cannot pay a second hit")
	world.advance_to_ms(750)
	runner.assert_true(domain.bout.people.player.action.is_empty(), "recovery ends after the complete original duration")
	domain.stop()
	runner.assert_true(not domain.owns_actor("player"), "voluntary stop releases the original actor")
	runner.assert_eq(player.stamina, 95, "stopping does not refund exertion")
	runner.assert_true(not bool(player.autonomous), "practice cannot turn the player into an autonomous pawn")


func _test_geometry_and_mutual_hits(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	_begin(world, runner)
	world.sparring.strike("player", Vector2.LEFT)
	world.advance_to_ms(300)
	runner.assert_eq(world.sparring.bout.people.player.hits, 0, "an opponent outside the declared fan cannot be hit")
	world = _make(runner)
	_begin(world, runner)
	world.sparring.strike("player", Vector2.RIGHT)
	world.sparring.strike("shi_tou", Vector2.LEFT)
	world.advance_to_ms(300)
	runner.assert_eq(world.regions.home.actors.player.stamina, 81, "same-time contact still hits the first actor after its own attack cost")
	runner.assert_eq(world.regions.home.actors.shi_tou.stamina, 121, "same-time contact also hits the second actor independent of key ordering")
	runner.assert_eq(world.sparring.bout.people.player.hits, 1, "first simultaneous strike is recorded once")
	runner.assert_eq(world.sparring.bout.people.shi_tou.hits, 1, "second simultaneous strike is recorded once")
	world = _make(runner)
	_begin(world, runner)
	world.sparring.strike("player", Vector2.RIGHT)
	world.advance_to_ms(250)
	world.regions.home.set_actor_position("shi_tou", world.regions.home.actor_position(world.regions.home.actors.player) + Vector2(250, 0))
	world.advance_to_ms(300)
	runner.assert_eq(world.sparring.bout.people.player.hits, 0, "leaving the actual reach before contact avoids the strike without an evasion die")
	world = _make(runner)
	world.sparring.set_geometry(func(_from: Vector2, _to: Vector2) -> bool: return false, Callable())
	_begin(world, runner)
	world.sparring.strike("player", Vector2.RIGHT)
	world.advance_to_ms(300)
	runner.assert_eq(world.sparring.bout.people.player.hits, 0, "terrain or height guard prevents contact through a barrier")


func _test_sparse_restore(runner: Object) -> void:
	var fine: RegionalSimulation = _make(runner)
	var sparse: RegionalSimulation = _make(runner)
	for world: RegionalSimulation in [fine, sparse]:
		_begin(world, runner)
		world.sparring.strike("player", Vector2.RIGHT)
		world.sparring.strike("shi_tou", Vector2.LEFT)
	fine.advance_to_ms(123)
	sparse.advance_to_ms(123)
	var restored: RegionalSimulation = _make(runner)
	runner.assert_true(restored.restore(JSON.parse_string(JSON.stringify(sparse.to_dict(), "", true, true))), "in-flight practice survives the full regional candidate validator")
	restored.set_active_region("home")
	for target: int in [299, 300, 777, 2345, 8000]:
		while fine.elapsed_ms < target:
			fine.advance_to_ms(mini(target, fine.elapsed_ms + 17))
		runner.assert_true(sparse.advance_to_ms(target), "absent practice reaches a sparse target")
		restored.advance_to_ms(target)
		restored.set_active_region("")
		runner.assert_eq(_state(sparse), _state(fine), "fine and absent practice have the same actions/resources at %dms" % target)
		runner.assert_eq(_state(restored), _state(fine), "restored practice has identical consequences across precision changes at %dms" % target)
	print("SCENARIO sparring: precise fan contact, mutual hits, original bodies, sparse/fine and in-flight continuation")


func _test_hit_does_not_shorten_pause(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	_begin(world, runner)
	world.sparring.bout.people.shi_tou.ready_ms = 700
	world.sparring.strike("player", Vector2.RIGHT)
	world.advance_to_ms(300)
	runner.assert_eq(world.sparring.bout.people.shi_tou.ready_ms, 700, "receiving a hit cannot shorten an existing recovery or AI pause")


func _test_ai_approaches_before_blocked_strike(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	world.sparring.set_geometry(func(from: Vector2, to: Vector2) -> bool: return from.distance_to(to) < 40.0, Callable())
	_begin(world, runner)
	world.advance_to_ms(100)
	runner.assert_true(world.sparring.bout.people.shi_tou.action.is_empty(), "NPC does not prepare a strike when terrain prevents actual contact")
	runner.assert_true(world.regions.home.actor_position(world.regions.home.actors.shi_tou).distance_to(world.regions.home.actor_position(world.regions.home.actors.player)) < 80, "NPC keeps approaching instead of repeatedly striking across a ledge")
	world.advance_to_ms(500)
	runner.assert_true(not world.sparring.bout.people.shi_tou.action.is_empty(), "NPC starts the same phased strike once it reaches valid contact geometry")


func _test_consent_ownership_and_loss(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	world.regions.home.actors.shi_tou.energy = 10
	runner.assert_true(not bool(world.sparring.invite("player", "shi_tou").ok), "exhausted NPC can refuse a player request")
	world.regions.home.actors.shi_tou.energy = 90
	runner.assert_true(world.configure_services(JSON.parse_string(FileAccess.get_file_as_string(SettlementServicesRuntime.DEFINITIONS_PATH))), "practice fixture has real visitor services")
	world.regions.home.actors.shi_tou.autonomous = true
	_begin(world, runner)
	runner.assert_true(not world.regions.home.submit_action("player", "check_kitchen"), "native labor cannot share the practice body")
	runner.assert_true(not bool(world.services.begin("player", "home", "rest").ok), "visitor work cannot share the practice body")
	var carrier: String = world.embodiment.carrier_for_source("village_actor", "shi_tou")
	world.embodiment.release_control("subject:shi_tou", carrier, "motion")
	world.advance_to_ms(50)
	runner.assert_true(world.sparring.bout.is_empty(), "loss of real motion control safely ends practice")
	runner.assert_true(bool(world.regions.home.actors.shi_tou.autonomous), "ending practice restores the NPC's previous autonomous life")
	runner.assert_eq(world.sparring.last_result.reason, "control_lost", "control loss is distinguished from a voluntary stop")


func _test_bad_state_atomic(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	_begin(world, runner)
	world.sparring.strike("player", Vector2.RIGHT)
	world.advance_to_ms(123)
	var saved: Dictionary = world.to_dict()
	var before: int = _state(world)
	for corruption: String in ["direction", "double_owner", "missing", "early_hit"]:
		var bad: Dictionary = saved.duplicate(true)
		match corruption:
			"direction": bad.sparring.bout.people.player.action.direction = [2, 0]
			"double_owner": bad.regions.home.actors.shi_tou.autonomous = true
			"missing": bad.erase("sparring")
			"early_hit": bad.sparring.bout.people.player.action.hit = true
		runner.assert_true(not world.restore(bad), "bad practice snapshot is rejected: " + corruption)
		runner.assert_eq(_state(world), before, "bad practice cannot partly replace bodies/world: " + corruption)
