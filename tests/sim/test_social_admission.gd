extends RefCounted

const Fixtures = preload("res://tests/sim/test_settlement_services.gd")
var _fixtures: RefCounted = Fixtures.new()


func run(runner: Object) -> void:
	_test_belief_and_actual_collection(runner)
	_test_private_verification_and_receipt(runner)
	_test_interrupted_npc_and_json(runner)
	_test_real_pass(runner)


func _world(runner: Object) -> RegionalSimulation:
	return _fixtures._make_world(runner)


func _speak(world: RegionalSimulation, runner: Object, actor: String, receiver: String, method: String) -> void:
	var sim: VillageSimulation = world.regions.home
	sim.set_actor_cell(actor, SimRouteTravel.cell(sim.actors[receiver].cell))
	runner.assert_true(world.admissions.start(actor, receiver, method).ok, "actual nearby %s conversation starts" % method)
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + int(world.admissions.definitions.actions[method])), "conversation reaches its common-time completion")


func _state(world: RegionalSimulation) -> String:
	return _fixtures._state(world)


func _restore(world: RegionalSimulation, runner: Object) -> RegionalSimulation:
	var other: RegionalSimulation = _world(runner)
	runner.assert_true(other.restore(JSON.parse_string(_state(world))), "actual social/institutional/execution state restores as one candidate")
	return other


func _obtain_grant(world: RegionalSimulation, runner: Object) -> String:
	for receiver: String in ["shi_tou", "a_he", "su_zhi"]:
		_speak(world, runner, "player", receiver, "claim")
		var grant: String = world.admissions.available_grant("player", "home")
		if not grant.is_empty():
			return grant
	runner.assert_true(false, "at least one ordinary colleague in the seeded situation grants provisional access")
	return ""


func _test_belief_and_actual_collection(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var stock: int = world.regions.home.inventory.quantity("garden", "herb")
	var id: String = _obtain_grant(world, runner)
	runner.assert_eq(world.admissions.entries.back().status, "believed", "an ordinary colleague can believe an unsupported spoken claim")
	runner.assert_true(not world.services.has_access("player", "home", "gate"), "a person's belief never creates a formal institutional authorization")
	runner.assert_eq(world.regions.home.inventory.quantity("garden", "herb"), stock, "hearing a claim alone never transfers actual medicine")
	if id.is_empty():
		runner.assert_true(false, "accepted statement yields an explicit limited admission")
		return
	var expires: int = int(world.admissions.grants[id].expires_ms)
	var rng: String = str(world.admissions._rng.state)
	var count: int = world.admissions.entries.size()
	var receiver: String = world.admissions.grants[id].receiver
	_speak(world, runner, "player", receiver, "claim")
	runner.assert_eq(str(world.admissions._rng.state), rng, "same statement does not reroll because time or ambient hunger changed")
	runner.assert_eq(world.admissions.entries.size(), count, "cached statement does not create new consent evidence")
	runner.assert_eq(world.admissions.grants[id].expires_ms, expires, "repetition cannot extend a grant's lifetime")
	runner.assert_true(world.services.begin("player", "home", "collect_herb").ok, "temporary admission starts the original physical collection executor")
	runner.assert_true(not world.admissions.start("player", receiver, "claim").ok, "collection and conversation cannot own one body at once")
	var saved: RegionalSimulation = _restore(world, runner)
	_fixtures._finish(world, "player", runner)
	saved.advance_to_ms(world.elapsed_ms)
	runner.assert_eq(_state(saved), _state(world), "pending real collection under temporary admission survives complete JSON restore")
	runner.assert_eq(world.regions.home.inventory.quantity("garden", "herb"), stock - 1, "one actual medicine branch leaves the garden")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "herb"), 1, "same branch arrives in the original person's bag")
	runner.assert_true(not str(world.admissions.grants[id].used_by).is_empty(), "actual transfer consumes the single discretionary admission")
	_speak(world, runner, "player", receiver, "claim")
	runner.assert_true(not world.services.begin("player", "home", "collect_herb").ok, "repeating an already used statement cannot create unlimited medicine permissions")
	var before: String = _state(world)
	var bad: Dictionary = world.to_dict()
	bad.admissions.grants[id].used_by = ""
	runner.assert_true(not world.restore(bad), "erasing usage while retaining real delivery is rejected")
	runner.assert_eq(_state(world), before, "bad joint consent does not partly replace the live world")
	print("SCENARIO admission: unsupported speech can persuade a person; real one-use collection changes goods, never formal credit")


func _test_private_verification_and_receipt(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var grant: String = _obtain_grant(world, runner)
	if grant.is_empty():
		return
	var receiver: String = world.admissions.grants[grant].receiver
	_speak(world, runner, "player", "chen_shouzhuo", "claim")
	runner.assert_eq(world.admissions.entries.back().status, "requires_check", "registrar distinguishes a spoken assertion from a record he can check")
	_speak(world, runner, "player", "chen_shouzhuo", "verify")
	var audit: Dictionary = world.admissions.latest_audit("player")
	runner.assert_eq(audit.status, "unconfirmed", "actual verification finds the missing local registration")
	runner.assert_true(not world.regions.home.social.knowledge[receiver].has(audit.social_event), "earlier listener does not magically hear the registrar's private verification")
	runner.assert_true(world.admissions.valid_grant(grant, "player", "home"), "ignorant colleague's earlier admission is not revoked by a global truth flag")
	_speak(world, runner, "player", receiver, "receipt")
	runner.assert_true(not world.admissions.valid_grant(grant, "player", "home"), "showing the actual receipt lets the colleague revoke his own admission")
	_speak(world, runner, "player", receiver, "claim")
	runner.assert_eq(world.admissions.entries.back().status, "requires_check", "same person now uses the new evidence he actually received")
	var known: Dictionary = world.regions.home.social.knowledge.lao_zhou
	runner.assert_true(not known.has(audit.social_event), "uninvolved people keep their original knowledge")
	var other: RegionalSimulation = _restore(world, runner)
	runner.assert_eq(_state(other), _state(world), "private receipts, changed knowledge and revocation roundtrip together")
	var bad: Dictionary = world.to_dict()
	bad.admissions.entries[2].evidence = "invented_signature"
	runner.assert_true(not other.restore(bad), "unbacked historical verification cannot be forged into real evidence")
	print("SCENARIO verification: local record, private result and physically presented receipt change different people's decisions at different times")


func _test_interrupted_npc_and_json(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	sim.set_actor_cell("su_zhi", SimRouteTravel.cell(sim.actors.shi_tou.cell))
	sim.actors.su_zhi.autonomous = true
	runner.assert_true(world.admissions.start("su_zhi", "shi_tou", "claim").ok, "NPC uses the same finite interaction API without a player exemption")
	world.advance_to_ms(2000)
	var restored: RegionalSimulation = _restore(world, runner)
	world.advance_to_ms(5000)
	for at_ms: int in range(2050, 5001, 50):
		restored.advance_to_ms(at_ms)
	runner.assert_eq(_state(restored), _state(world), "fine and distant completion agree for the same NPC's unfinished conversation")
	runner.assert_true(world.regions.home.actors.su_zhi.autonomous, "NPC returns to his own life after speaking")
	world = _world(runner)
	sim = world.regions.home
	sim.set_actor_cell("player", SimRouteTravel.cell(sim.actors.shi_tou.cell))
	runner.assert_true(world.admissions.start("player", "shi_tou", "claim").ok, "another actual conversation starts")
	world.advance_to_ms(2000)
	runner.assert_true(world.admissions.cancel("player"), "conversation can be cancelled before delivery")
	runner.assert_true(world.admissions.grants.is_empty() and world.elapsed_ms == 2000, "cancel does not manufacture consent or roll back elapsed world time")
	var id: String = _obtain_grant(world, runner)
	if id.is_empty():
		return
	world.advance_to_ms(int(world.admissions.grants[id].expires_ms))
	runner.assert_true(not world.admissions.valid_grant(id, "player", "home"), "temporary permission expires on the common clock without an on-screen countdown dependency")


func _test_real_pass(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	_fixtures._position(world, "river", "store")
	runner.assert_true(world.services.begin("player", "river", "haul_grain").ok, "positive evidence fixture takes a real resource-backed delivery")
	_fixtures._finish(world, "player", runner)
	runner.assert_true(world.services.report_work("player", "home").ok, "real delivery is separately reported to the institution")
	_fixtures._finish(world, "player", runner)
	runner.assert_true(world.services.request_access("player", "home", "gate").ok, "earned local contribution starts real authorization")
	_fixtures._finish(world, "player", runner)
	_speak(world, runner, "player", "chen_shouzhuo", "verify")
	runner.assert_eq(world.admissions.latest_audit("player").status, "confirmed", "same verification protocol confirms an actually registered person")
	_speak(world, runner, "player", "shi_tou", "show_pass")
	runner.assert_eq(world.admissions.entries.back().status, "pass_seen", "actual signed evidence works through the same nearby interaction")
	var saved: RegionalSimulation = _restore(world, runner)
	runner.assert_eq(_state(saved), _state(world), "earned credentials and positive verification preserve all their original sources")
