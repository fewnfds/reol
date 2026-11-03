extends RefCounted
## Real carried artifact -> original charge -> one finite local heat receipt.

const EnvironmentFixture = preload("res://tests/sim/test_environment.gd")


func run(runner: Object) -> void:
	_permissions_and_cancel(runner)
	_health_permission(runner)
	_finite_original_charge(runner)
	_mid_action_resume(runner)
	_npc_uses_own_stone(runner)
	print("SCENARIO artifact warming: known held original stone, real shared duration, exclusive action, finite charge, no cancellation heat, joint continuation and ordinary cold NPC")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = EnvironmentFixture.new()._world(runner)
	if world == null:
		return null
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))
	if not world.artifacts.spawn_opening(opening):
		runner.assert_true(false, "warming uses the original finite opening stone")
		return null
	for sim: VillageSimulation in world.regions.values():
		for actor: Dictionary in sim.actors.values():
			actor.autonomous = false
	for actor: String in ["player", "chen_shouzhuo"]:
		world.regions.home.set_actor_cell(actor, world.artifacts.object_cell("hearth_stone"))
	world.invalidate_region("home")
	return world


func _do(runner: Object, world: RegionalSimulation, actor: String, verb: String) -> bool:
	var response: Dictionary = world.artifacts.begin(actor, verb, "hearth_stone")
	runner.assert_true(response.ok, "original timed action begins: " + actor + ":" + verb)
	if not response.ok:
		return false
	return _advance_to(runner, world, int(world.artifacts.active[actor].due_ms))


func _advance_to(runner: Object, world: RegionalSimulation, at_ms: int) -> bool:
	var ok: bool = world.advance_to_ms(at_ms)
	runner.assert_true(ok, "the original shared scheduler reaches the requested operation boundary")
	return ok


func _learn_and_hold(runner: Object, world: RegionalSimulation) -> bool:
	return _do(runner, world, "player", "study") and _do(runner, world, "player", "take")


func _state(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _permissions_and_cancel(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var domain: SimArtifacts = world.artifacts
	runner.assert_true(not domain.begin("chen_shouzhuo", "warm", "hearth_stone").ok, "experienced operator must first take the real stone in hand")
	if not _do(runner, world, "player", "take"):
		return
	runner.assert_true(not domain.begin("player", "warm", "hearth_stone").ok, "holding an object does not grant a usable channeling method")
	runner.assert_true(not domain.begin("chen_shouzhuo", "warm", "hearth_stone").ok, "another person's stone cannot supply this actor's warmth")
	if not _do(runner, world, "player", "study"):
		return
	var charge: int = int(domain.objects.hearth_stone.charge)
	var qi: int = int(world.regions.home.actors.player.qi)
	var cell: Vector2i = domain.object_cell("hearth_stone")
	var now: int = world.elapsed_ms
	var response: Dictionary = domain.begin("player", "warm", "hearth_stone")
	runner.assert_true(response.ok, "knowledgeable holder can choose finite local warmth")
	if not response.ok:
		return
	runner.assert_eq(domain.active.player.due_ms, now + 60000, "warming reserves one minute on the original clock")
	runner.assert_eq(domain.objects.hearth_stone.charge, charge, "accepting a request spends no stored heat before completion")
	runner.assert_eq(world.regions.home.actors.player.qi, qi, "warming spends existing stored heat, with no extra qi payment")
	runner.assert_true(not domain.begin("player", "charge", "hearth_stone").ok and not world.native_action_allowed("player"), "the real warming job excludes a second artifact or native task")
	runner.assert_true(world.advance_to_ms(now + 237), "a partial interval has genuinely elapsed before cancellation")
	runner.assert_eq(world.local_heat.local_tenths(cell), 0, "a pending operation produces no early local warmth")
	runner.assert_true(domain.cancel("player"), "the ordinary cancellation path interrupts warming")
	runner.assert_eq(domain.objects.hearth_stone.charge, charge, "cancellation never debits the original storage")
	runner.assert_eq(world.local_heat.local_tenths(cell), 0, "cancellation leaves no invisible thermal effect")
	runner.assert_eq(domain.events.back().kind, "cancelled", "interruption records an unfinished operation rather than a warmed source")
	var view: Dictionary = domain.describe("player", "hearth_stone")
	runner.assert_true(not view.has("charge") and not view.has("amount") and not view.has("pulse_energy"), "the holder receives limited descriptions instead of the thermal ledger")


func _health_permission(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _do(runner, world, "player", "take") or not _do(runner, world, "player", "heat"):
		return
	runner.assert_true(world.health.blocks_channeling("player"), "an actual mistaken original heat operation irritates the operator's channels")
	if not _do(runner, world, "player", "study"):
		return
	var charge: int = int(world.artifacts.objects.hearth_stone.charge)
	var response: Dictionary = world.artifacts.begin("player", "warm", "hearth_stone")
	runner.assert_true(not response.ok and str(response.line).contains("引流不顺"), "understanding a method cannot bypass the original injury permission")
	runner.assert_eq(world.artifacts.objects.hearth_stone.charge, charge, "health refusal consumes none of the original stored charge")


func _finite_original_charge(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _learn_and_hold(runner, world):
		return
	var domain: SimArtifacts = world.artifacts
	var opening: int = int(domain.objects.hearth_stone.charge)
	var cost: int = int(domain.definitions.types.warm_stone.warming_charge)
	var qi: int = int(world.regions.home.actors.player.qi)
	var origin: Vector2i = domain.object_cell("hearth_stone")
	var pulses: int = floori(float(opening) / float(cost))
	for index: int in pulses:
		var cell: Vector2i = origin + Vector2i(index * 3, 0)
		world.regions.home.set_actor_cell("player", cell)
		world.invalidate_region("home")
		if not _do(runner, world, "player", "warm"):
			return
		var event: Dictionary = domain.events.back()
		runner.assert_eq(event.kind, "warmed", "only the completed action supplies a real warmed source")
		runner.assert_eq(event.cell, [cell.x, cell.y], "the source remains fixed at the holder's actual completion cell")
		runner.assert_eq(event.at_ms, world.elapsed_ms, "thermal source time is the actual original completion millisecond")
		runner.assert_eq(domain.objects.hearth_stone.charge, opening - (index + 1) * cost, "each local pulse debits exactly the original artifact charge once")
		runner.assert_true(world.local_heat.local_tenths(cell) > 0, "the successful source creates actual local warmth")
		runner.assert_eq(world.regions.home.actors.player.qi, qi, "repeated warming does not secretly charge another resource")
	runner.assert_eq(domain.objects.hearth_stone.charge, 0, "the finite opening storage is truly exhausted")
	runner.assert_true(not domain.begin("player", "warm", "hearth_stone").ok, "a depleted stone cannot provide another free pulse")
	var finished: Dictionary = domain.events.back()
	var heat_before: Dictionary = world.local_heat.to_dict()
	var duplicate: Dictionary = {"action": finished.action, "actor": finished.actor, "object": finished.object,
		"at_ms": finished.at_ms, "cell": finished.cell.duplicate(), "amount": int(world.local_heat.definitions.pulse_energy)}
	runner.assert_true(not world.local_heat.deposit(duplicate), "replaying the same artifact action cannot supply a second pulse")
	runner.assert_eq(world.local_heat.to_dict(), heat_before, "a repeated source leaves the original thermal authority unchanged")
	var moved: Vector2i = origin + Vector2i(25, 0)
	world.regions.home.set_actor_cell("player", moved)
	world.invalidate_region("home")
	runner.assert_eq(world.local_heat.local_tenths(moved), 0, "leaving a spent source does not carry its local warmth with the body")


func _mid_action_resume(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _learn_and_hold(runner, world):
		return
	if not world.artifacts.begin("player", "warm", "hearth_stone").ok:
		runner.assert_true(false, "continuation scenario starts the real warming operation")
		return
	var due: int = int(world.artifacts.active.player.due_ms)
	world.advance_to_ms(world.elapsed_ms + 17431)
	var saved: Dictionary = JSON.parse_string(_state(world))
	var fine: RegionalSimulation = _world(runner)
	var bounded: RegionalSimulation = _world(runner)
	if fine == null or bounded == null:
		return
	runner.assert_true(fine.restore(saved), "active warming, original charge and no premature source survive joint JSON loading")
	runner.assert_true(bounded.restore(saved), "another candidate restores the same unfinished physical operation")
	runner.assert_true(world.advance_to_ms(due + 120123), "coarse continuation settles the original source and subsequent dissipation")
	while fine.elapsed_ms < due + 120123:
		fine.advance_to_ms(mini(fine.elapsed_ms + 1301, due + 120123))
	var attempts: int = 0
	while not bounded.advance_to_ms(due + 120123, 1) and attempts < 2000:
		attempts += 1
	runner.assert_true(attempts < 2000, "bounded work makes progress without losing the warming receipt")
	runner.assert_eq(_state(fine), _state(world), "many local intervals produce the same complete source and future as coarse execution")
	runner.assert_eq(_state(bounded), _state(world), "budgeted continuation preserves original charge and one thermal receipt exactly")
	var copied: RegionalSimulation = _world(runner)
	if copied != null:
		runner.assert_true(copied.restore(JSON.parse_string(_state(world))), "a completed warmed event and matching thermal source restore together")


func _npc_uses_own_stone(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _do(runner, world, "chen_shouzhuo", "take"):
		return
	var person: Dictionary = world.regions.home.actors.chen_shouzhuo
	person.autonomous = true
	person.hunger = 85.0
	person.energy = 85.0
	person.retry_ms = world.elapsed_ms + 1
	world.invalidate_region("home")
	runner.assert_true(world.artifacts.wants_warming_decision("chen_shouzhuo", world.elapsed_ms), "an ordinary cold NPC considers its own held stone and existing practical knowledge")
	runner.assert_true(not world.artifacts.wants_warming_decision("su_zhi", world.elapsed_ms), "a nearby character does not use another holder's private storage")
	world.advance_to_ms(world.elapsed_ms + 2)
	runner.assert_true(world.artifacts.owns_actor("chen_shouzhuo"), "the original native initiative path begins the NPC's actual warming job")
	if not world.artifacts.active.has("chen_shouzhuo"):
		return
	runner.assert_eq(world.artifacts.active.chen_shouzhuo.verb, "warm", "the decision uses the same ordinary warm verb as the player")
	var charge: int = int(world.artifacts.objects.hearth_stone.charge)
	world.advance_to_ms(int(world.artifacts.active.chen_shouzhuo.due_ms))
	runner.assert_eq(world.artifacts.objects.hearth_stone.charge, charge - 1, "the NPC pays from the same original finite artifact rather than a free comfort effect")
