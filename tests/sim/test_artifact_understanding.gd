extends RefCounted

const Fixtures = preload("res://tests/sim/test_artifacts.gd")


func run(runner: Object) -> void:
	_test_different_practice(runner)
	_test_requested_check_and_hearing(runner)
	_test_actual_overload(runner)
	_test_candidates_and_resume(runner)
	print("SCENARIO understanding: material practice differs from control, attributed reports never grant technique and real overload persists")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = Fixtures.new()._world(runner)
	for sim: VillageSimulation in world.regions.values():
		for actor: Dictionary in sim.actors.values():
			actor.autonomous = false
	for actor: String in ["player", "su_zhi", "chen_shouzhuo"]:
		world.regions.home.set_actor_cell(actor, world.artifacts.object_cell("hearth_stone"))
	world.invalidate_region("home")
	return world


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _do(runner: Object, world: RegionalSimulation, actor: String, verb: String) -> void:
	var result: Dictionary = world.artifacts.begin(actor, verb, "hearth_stone")
	runner.assert_true(result.ok, "world-backed action accepted: " + actor + ":" + verb)
	if result.ok:
		runner.assert_true(world.advance_to_ms(world.elapsed_ms + int(world.artifacts.definitions.verbs[verb].minutes) * 60000), "world reaches actual action completion")


func _test_different_practice(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var domain: SimArtifacts = world.artifacts
	runner.assert_true(domain.describe("chen_shouzhuo", "hearth_stone").method, "past practical experience lets its owner operate this type")
	runner.assert_true(not domain.describe("su_zhi", "hearth_stone").method and not domain.describe("player", "hearth_stone").method, "material familiarity and novice sight do not grant control technique")
	var before: String = _canonical(world)
	for _index: int in 5:
		for actor: String in ["player", "su_zhi", "chen_shouzhuo"]:
			var view: Dictionary = domain.describe(actor, "hearth_stone")
			runner.assert_true(not view.has("damage") and not view.has("charge") and not str(view.line).contains("细裂"), "browsing cannot read hidden material state even with relevant practice")
	runner.assert_eq(_canonical(world), before, "description queries change no knowledge, object or random state")
	_do(runner, world, "su_zhi", "examine")
	runner.assert_true(str(domain.describe("su_zhi", "hearth_stone").line).contains("细裂"), "paid material check interprets the actual weak seam")
	_do(runner, world, "chen_shouzhuo", "examine")
	runner.assert_true(str(domain.describe("chen_shouzhuo", "hearth_stone").line).contains("辨不清"), "experienced operator remains uncertain in an unfamiliar material field")
	_do(runner, world, "player", "examine")
	runner.assert_true(not domain.describe("player", "hearth_stone").method, "looking closely is not the same action as learning to channel heat")
	var observed: String = domain.describe("su_zhi", "hearth_stone").line
	domain.objects.hearth_stone.damage = 0
	runner.assert_eq(domain.describe("su_zhi", "hearth_stone").line, observed, "stored assessment does not silently update when hidden truth changes")
	var rank: String = world.regions.home.actors.chen_shouzhuo.rank_id
	world.regions.home.actors.chen_shouzhuo.rank_id = "servant"
	runner.assert_true(domain.describe("chen_shouzhuo", "hearth_stone").method, "social rank is not the source of learned control")
	world.regions.home.actors.chen_shouzhuo.rank_id = rank


func _test_requested_check_and_hearing(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var domain: SimArtifacts = world.artifacts
	var sim: VillageSimulation = world.regions.home
	runner.assert_true(domain.request_check("player", "su_zhi", "examine", "hearth_stone").ok, "nearby well-rested artisan accepts a specific inspection")
	runner.assert_true(not domain.request_check("player", "su_zhi", "examine", "hearth_stone").ok, "another request cannot restart a committed inspection")
	runner.assert_true(not str(domain.describe("player", "hearth_stone").line).contains("细裂"), "pending inspection grants no result early")
	world.advance_to_ms(120000)
	var report: Dictionary = domain.describe("player", "hearth_stone")
	runner.assert_true(str(report.line).contains("苏芷曾告诉你") and str(report.line).contains("细裂"), "real nearby result is an attributed statement")
	runner.assert_true(not report.method, "hearing material advice does not copy a technique")
	runner.assert_true(domain.request_check("player", "chen_shouzhuo", "study", "hearth_stone").ok, "a different person can examine the control path with their own qi")
	var qi: int = sim.actors.chen_shouzhuo.qi
	world.advance_to_ms(360000)
	runner.assert_true(str(domain.describe("player", "hearth_stone").line).contains("陈守拙曾告诉你"), "method explanation retains its speaker")
	runner.assert_true(not domain.describe("player", "hearth_stone").method and sim.actors.chen_shouzhuo.qi == qi, "explanation is not free recipient mastery or another qi payment")
	var resumed: RegionalSimulation = _world(runner)
	runner.assert_true(resumed.restore(JSON.parse_string(_canonical(world))), "inspection decisions, speaker and listener sources validate with the shared world")
	world = _world(runner)
	domain = world.artifacts
	sim = world.regions.home
	runner.assert_true(domain.request_check("player", "su_zhi", "examine", "hearth_stone").ok, "second world has the same inspection opportunity")
	sim.set_actor_cell("player", Vector2i(120, 120))
	world.invalidate_region("home")
	world.advance_to_ms(120000)
	runner.assert_eq(domain.events.back().recipient, "", "leaving before the explanation prevents receiving it")
	runner.assert_true(not sim.actor_status("su_zhi").contains("细裂"), "public activity label cannot leak the private material conclusion")
	sim.set_actor_cell("player", domain.object_cell("hearth_stone"))
	runner.assert_true(not str(domain.describe("player", "hearth_stone").line).contains("细裂"), "returning cannot retroactively hear a missed private explanation")
	sim.actors.su_zhi.energy = 0.0
	var accepted: bool = domain.request_check("player", "su_zhi", "examine", "hearth_stone").ok
	runner.assert_true(not accepted, "exhausted person can refuse unpaid help")
	var requests: int = sim.social.requests.size()
	var rng: String = str(sim._rng.state)
	for _index: int in 5:
		domain.request_check("player", "su_zhi", "examine", "hearth_stone")
	runner.assert_eq(sim.social.requests.size(), requests, "unchanged repeated requests reuse the same social consideration")
	runner.assert_eq(str(sim._rng.state), rng, "repeated clicks cannot obtain fresh social dice")


func _test_actual_overload(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var domain: SimArtifacts = world.artifacts
	var item: Dictionary = domain.objects.hearth_stone
	var food: int = world.regions.home.inventory.quantity("kitchen", "meal")
	_do(runner, world, "player", "study")
	_do(runner, world, "player", "heat")
	runner.assert_eq(world.regions.home.inventory.quantity("kitchen", "meal"), food + 6, "ordinary load cooks actual food through the original shared transaction")
	runner.assert_eq(item.damage, 1, "gentle operating method does not magically repair or worsen a weak seam")
	var charge: int = int(item.charge)
	var qi: int = world.regions.home.actors.player.qi
	runner.assert_true(domain.begin("player", "force", "hearth_stone").ok, "unknown structural risk does not prohibit a real attempt")
	runner.assert_eq(world.regions.home.actors.player.qi, qi - 6, "overload spends real qi when committed")
	world.advance_to_ms(world.elapsed_ms + 50)
	domain.cancel("player")
	runner.assert_eq(item.charge, charge, "interrupted overload produces no stored heat")
	runner.assert_eq(item.damage, 1, "interrupted overload does not apply its later completion fracture")
	runner.assert_eq(world.regions.home.actors.player.qi, qi - 6, "cancel does not refund committed qi")
	_do(runner, world, "chen_shouzhuo", "force")
	runner.assert_eq(item.damage, domain.definitions.types.warm_stone.damage_max, "the same weak seam actually fractures under a knowledgeable operator")
	runner.assert_eq(item.charge, 0, "fracture dissipates existing finite stored heat")
	runner.assert_eq(domain.events.back().kind, "fractured", "failure leaves a real event rather than an invisible flag")
	runner.assert_true(not domain.begin("chen_shouzhuo", "heat", "hearth_stone").ok, "fracture also requires the original operator to recover before trying again")
	# The earlier 50 ms cancellation makes this fracture fall between minute
	# boundaries. Its first whole recovery interval ends at a later pulse.
	var recovery_minute: int = ceili(float(world.elapsed_ms) / 60000.0) + int(world.health.definitions.recovery.required)
	runner.assert_true(world.advance_to_ms(recovery_minute * 60000), "fractional injury reaches its full natural-recovery horizon")
	runner.assert_true(not world.health.blocks_channeling("chen_shouzhuo"), "the actual operator recovers before the broken-object check")
	food = world.regions.home.inventory.quantity("kitchen", "meal")
	_do(runner, world, "chen_shouzhuo", "heat")
	runner.assert_eq(world.regions.home.inventory.quantity("kitchen", "meal"), food, "knowing the method cannot make a broken object cook")
	var sound: RegionalSimulation = _world(runner)
	sound.artifacts.objects.hearth_stone.damage = 0
	_do(runner, sound, "chen_shouzhuo", "force")
	runner.assert_eq(sound.artifacts.events.back().kind, "overcharged", "intact material can take a first overload with actual wear")
	runner.assert_true(int(sound.artifacts.objects.hearth_stone.damage) > 0, "successful overload is not endless free capacity")
	_do(runner, sound, "chen_shouzhuo", "force")
	runner.assert_eq(sound.artifacts.events.back().kind, "fractured", "a later overload obeys accumulated material change")


func _test_candidates_and_resume(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	runner.assert_true(world.artifacts.request_check("player", "su_zhi", "examine", "hearth_stone").ok, "pending explanation fixture begins")
	world.advance_to_ms(447)
	var source: Dictionary = JSON.parse_string(_canonical(world))
	var coarse: RegionalSimulation = _world(runner)
	runner.assert_true(coarse.restore(source), "ongoing inspection and intended listener survive JSON")
	world.advance_to_ms(240123)
	for at: int in range(497, 240123, 50):
		coarse.advance_to_ms(at)
	coarse.advance_to_ms(240123)
	runner.assert_true(_canonical(coarse) == _canonical(world), "near/far inspection completion and explanations have the same future")
	var negatives: Array[Dictionary] = []
	var bad: Dictionary = source.duplicate(true)
	bad.artifacts.experiences["subject:su_zhi"] = ["invented_omniscience"]
	negatives.append(bad)
	bad = source.duplicate(true)
	bad.artifacts.experiences["subject:missing"] = ["kiln_repair"]
	negatives.append(bad)
	bad = source.duplicate(true)
	bad.artifacts.objects.hearth_stone.damage = true
	negatives.append(bad)
	bad = source.duplicate(true)
	bad.artifacts.objects.hearth_stone.damage = 999
	negatives.append(bad)
	bad = source.duplicate(true)
	bad.artifacts.active.su_zhi.recipient = "missing_person"
	negatives.append(bad)
	for invalid: Dictionary in negatives:
		var before: String = _canonical(world)
		runner.assert_true(not world.restore(invalid), "bad experience, damage or listener reference is rejected")
		runner.assert_eq(_canonical(world), before, "candidate rejection preserves every live domain")
