extends RefCounted

const Fixtures = preload("res://tests/sim/test_regional_simulation.gd")
var _fixtures: RefCounted = Fixtures.new()


func run(runner: Object) -> void:
	_test_independent_subject_and_private_old_knowledge(runner)
	_test_kept_word_and_actual_practice(runner)
	_test_cancel_control_and_exclusive_body(runner)
	_test_custody_and_personal_promises(runner)
	_test_force_breaks_cooperation(runner)
	_test_sleep_damage_and_saved_future(runner)
	_test_bad_candidates_leave_world_intact(runner)


func _make(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _fixtures._make_world(runner)
	runner.assert_true(world.artifacts.spawn_opening(JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))), "soul fixture has the original physical warm stone")
	runner.assert_true(world.soul_vessels.spawn_opening(JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/soul_vessels.json"))), "soul fixture stages an actual ring and independent resident")
	world.regions.home.set_actor_cell("player", world.soul_vessels.vessel_cell("old_ring"))
	return world


func _do(world: RegionalSimulation, verb: String, runner: Object, target: String = "", recipient: String = "", destination: String = "", actor: String = "player") -> void:
	var result: Dictionary = world.soul_vessels.begin(actor, verb, "old_ring", target, recipient, destination)
	runner.assert_true(bool(result.ok), "soul interaction starts: %s %s" % [verb, str(result.line)])
	if bool(result.ok):
		runner.assert_true(world.advance_to_ms(world.elapsed_ms + int(world.soul_vessels.definitions.verbs[verb].ms)), "soul interaction reaches the shared completion time")


func _ready_lesson(world: RegionalSimulation, runner: Object) -> void:
	_do(world, "take", runner)
	_do(world, "wake", runner)
	_do(world, "promise", runner)
	runner.assert_true(bool(world.artifacts.begin("player", "take", "hearth_stone").ok), "pupil physically picks up the original warm stone")
	world.advance_to_ms(world.artifacts.active.player.due_ms)
	world.regions.home.set_actor_cell("player", SimRouteTravel.cell(world.regions.home.places.garden.cell))
	_do(world, "fulfill", runner)


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true)), "", true, true)


func _test_independent_subject_and_private_old_knowledge(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	var domain: SimSoulVessels = world.soul_vessels
	var subject: String = SimSoulVessels.subject_id("yan_heng")
	var carrier: String = SimSoulVessels.carrier_id("old_ring")
	runner.assert_true(world.embodiment.residence_of(subject) == carrier and world.embodiment.controls(subject, carrier, "communication"), "resident has an actual carrier and his own voice")
	runner.assert_true(not world.embodiment.grant_control("subject:player", carrier, "motion") and not world.embodiment.grant_control("subject:player", carrier, "communication"), "holding a ring cannot create legs or seize another mind's voice")
	var before: String = _canonical(world)
	var view: Dictionary = domain.describe("player", "old_ring")
	runner.assert_true(not view.met and not str(view.line).contains("晏衡") and not str(view.line).contains("三百"), "looking at the ring does not reveal an unintroduced soul or private old knowledge")
	domain.describe("player", "old_ring")
	runner.assert_eq(_canonical(world), before, "opening and sorting a perception do not learn or change the resident")
	_do(world, "take", runner)
	_do(world, "wake", runner)
	_do(world, "listen", runner)
	runner.assert_true(str(domain.describe("player", "old_ring").line).contains("三百年前"), "listening receives an explicitly dated personal account")
	world.regions.home.set_actor_cell("su_zhi", domain.vessel_cell("old_ring"))
	var other: Dictionary = domain.describe("su_zhi", "old_ring")
	runner.assert_true(not other.met and not str(other.line).contains("柳") and not str(other.line).contains("晏衡"), "a bystander cannot read a holder's private transmission")
	runner.assert_true(not bool(world.artifacts.describe("player", "hearth_stone").method), "hearing an old story does not copy a hand technique")


func _test_kept_word_and_actual_practice(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	var domain: SimSoulVessels = world.soul_vessels
	_do(world, "take", runner)
	_do(world, "wake", runner)
	var qi: int = int(world.regions.home.actors.player.qi)
	runner.assert_true(not bool(domain.begin("player", "guide", "old_ring", "hearth_stone").ok), "an unkept relationship can refuse even when the object is physically held")
	runner.assert_eq(world.regions.home.actors.player.qi, qi, "refused guidance does not charge for an action that never began")
	_do(world, "promise", runner)
	runner.assert_true(not bool(domain.begin("player", "fulfill", "old_ring").ok), "saying a promise cannot replace going to its actual destination")
	runner.assert_true(bool(world.artifacts.begin("player", "take", "hearth_stone").ok), "lesson materials use original custody actions")
	world.advance_to_ms(world.artifacts.active.player.due_ms)
	world.regions.home.set_actor_cell("player", SimRouteTravel.cell(world.regions.home.places.garden.cell))
	runner.assert_eq(domain.pacts.yan_heng.player.state, "pledged", "walking to the goal alone does not invent an unperformed conversation")
	_do(world, "fulfill", runner)
	var energy: int = int(domain.residents.yan_heng.energy)
	qi = int(world.regions.home.actors.player.qi)
	runner.assert_true(bool(domain.begin("player", "guide", "old_ring", "hearth_stone").ok), "kept word and applicable material allow a willing resident to guide")
	runner.assert_eq(world.regions.home.actors.player.qi, qi - 1, "practice pays the pupil's original qi exactly once")
	runner.assert_eq(domain.residents.yan_heng.energy, energy - 8, "a real independent teacher pays his own limited attention")
	world.advance_to_ms(world.elapsed_ms + 59999)
	runner.assert_true(not bool(world.artifacts.describe("player", "hearth_stone").method), "nearly complete instruction is not yet a learned practice")
	world.advance_to_ms(world.elapsed_ms + 1)
	runner.assert_true(bool(world.artifacts.describe("player", "hearth_stone").method), "full embodied practice creates usable knowledge with its teaching source")
	runner.assert_true(str(world.artifacts.describe("player", "hearth_stone").line).contains("受教记录"), "the learner can trace this hand technique to actual instruction")
	world.regions.home.set_actor_cell("shi_tou", domain.vessel_cell("old_ring"))
	runner.assert_true(not bool(world.artifacts.describe("shi_tou", "hearth_stone").method), "nearby people do not silently learn the private completed lesson")
	runner.assert_true(world.restore(JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))), "completed personal lesson and pact validate together")


func _test_cancel_control_and_exclusive_body(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	_ready_lesson(world, runner)
	var domain: SimSoulVessels = world.soul_vessels
	var qi: int = int(world.regions.home.actors.player.qi)
	var energy: int = int(domain.residents.yan_heng.energy)
	runner.assert_true(bool(domain.begin("player", "guide", "old_ring", "hearth_stone").ok), "interruption fixture begins a real lesson")
	runner.assert_true(not world.regions.home.submit_action("player", "rest"), "practice cannot simultaneously reserve the same body's ordinary work")
	runner.assert_true(not bool(world.artifacts.begin("player", "study", "hearth_stone").ok), "the same body cannot study through two executors")
	world.advance_to_ms(world.elapsed_ms + 12345)
	var subject: String = SimSoulVessels.subject_id("yan_heng")
	world.embodiment.release_control(subject, SimSoulVessels.carrier_id("old_ring"), "communication")
	world.advance_to_ms(world.elapsed_ms + 1)
	runner.assert_true(domain.active.is_empty() and not domain.learned("player", "hearth_stone"), "losing the teacher's real voice interrupts without awarding a hand technique")
	runner.assert_eq(world.regions.home.actors.player.qi, qi - 1, "interruption does not refund qi already spent")
	runner.assert_eq(domain.residents.yan_heng.energy, energy - 8, "interruption does not refund the teacher's attention")
	runner.assert_true(world.regions.home.submit_action("player", "rest"), "interrupted practice releases the body's ordinary execution")
	world.regions.home.cancel_action("player")
	world.embodiment.grant_control(subject, SimSoulVessels.carrier_id("old_ring"), "communication")
	runner.assert_true(not bool(domain.begin("player", "guide", "old_ring", "hearth_stone").ok), "an exhausted teacher can refuse another attempt instead of an infinite free teaching loop")


func _test_custody_and_personal_promises(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	var domain: SimSoulVessels = world.soul_vessels
	_do(world, "take", runner)
	_do(world, "wake", runner)
	_do(world, "promise", runner)
	world.regions.home.set_actor_cell("su_zhi", domain.vessel_cell("old_ring"))
	var control: String = world.embodiment.subject_for_actor("su_zhi")
	var carrier: String = world.embodiment.carrier_for_source("village_actor", "su_zhi")
	world.embodiment.release_control(control, carrier, "communication")
	runner.assert_true(not bool(domain.begin("player", "give", "old_ring", "", "su_zhi").ok), "custody is not forced on a person who cannot agree")
	world.embodiment.grant_control(control, carrier, "communication")
	_do(world, "give", runner, "", "su_zhi")
	runner.assert_eq(domain.vessels.old_ring.container, "actor:su_zhi", "accepted handover moves the original unique ring once")
	runner.assert_eq(domain.pacts.yan_heng.player.state, "broken", "giving away a ring before fulfilling a promise leaves that person's broken word")
	runner.assert_true(not bool(domain.begin("player", "take", "old_ring").ok), "old holder cannot steal a carried ring back by selecting it")
	runner.assert_true(not domain.pacts.yan_heng.has("su_zhi"), "a new custodian does not inherit the former holder's relationship")
	runner.assert_true(not bool(domain.describe("su_zhi", "old_ring").met), "receiving custody does not copy private conversations")
	_do(world, "listen", runner, "", "", "", "su_zhi")
	runner.assert_true(str(domain.describe("su_zhi", "old_ring").line).contains("三百年前"), "new holder can make their own actual contact")
	runner.assert_true(world.restore(JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))), "handover, independent identity and broken promise remain a valid world")


func _test_sleep_damage_and_saved_future(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	_do(world, "take", runner)
	_do(world, "wake", runner)
	_do(world, "sleep", runner)
	world.advance_to_ms(world.elapsed_ms + 17617)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))
	var until: int = world.elapsed_ms + 1000000
	world.advance_to_ms(until)
	var expected: String = _canonical(world)
	runner.assert_eq(world.soul_vessels.residents.yan_heng.energy, 24, "sleep recovers bounded real attention instead of unlimited stored time")
	runner.assert_true(world.restore(saved), "sleeping resident restores fractional recovery")
	while world.elapsed_ms < until:
		world.advance_to_ms(mini(until, world.elapsed_ms + 517))
	runner.assert_eq(_canonical(world), expected, "coarse absent sleep and detailed advancement have identical physical and social futures")
	for _index in range(3):
		_do(world, "force", runner)
		if world.soul_vessels.residents.yan_heng.awake:
			_do(world, "sleep", runner)
	runner.assert_eq(world.soul_vessels.vessels.old_ring.damage, 4, "forcing transmission actually breaks the same vessel's seal")
	runner.assert_true(not bool(world.soul_vessels.begin("player", "wake", "old_ring").ok), "broken seal is not repaired by clicking a gentle wake command")
	runner.assert_true(world.restore(JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))), "damaged carrier restores without repairing it or resetting old knowledge")


func _test_force_breaks_cooperation(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	_ready_lesson(world, runner)
	_do(world, "sleep", runner)
	_do(world, "force", runner)
	var domain: SimSoulVessels = world.soul_vessels
	runner.assert_eq(domain.pacts.yan_heng.player.state, "broken", "damaging a person's carrier breaks this holder's cooperation even after an earlier kept word")
	runner.assert_true(not bool(domain.begin("player", "guide", "old_ring", "hearth_stone").ok), "old goodwill does not compel a damaged resident to keep teaching")
	runner.assert_true(world.restore(JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))), "force-caused loss of cooperation and the same old mind persist together")
	_do(world, "promise", runner)
	_do(world, "fulfill", runner)
	runner.assert_eq(world.soul_vessels.pacts.yan_heng.player.state, "fulfilled", "actual renewed fulfillment can restore cooperation without repairing material damage")
	runner.assert_eq(world.soul_vessels.vessels.old_ring.damage, 2, "social repair does not silently repair a cracked carrier")


func _test_bad_candidates_leave_world_intact(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	_ready_lesson(world, runner)
	runner.assert_true(bool(world.soul_vessels.begin("player", "guide", "old_ring", "hearth_stone").ok), "bad-state fixture starts a legal lesson")
	world.advance_to_ms(world.elapsed_ms + 12345)
	var original: Dictionary = world.to_dict()
	var before: String = _canonical(world)
	for corruption: String in ["missing", "source", "energy", "time", "payment", "target", "pact", "knowledge", "double_body", "unknown_actor"]:
		var bad: Dictionary = original.duplicate(true)
		match corruption:
			"missing": bad.erase("soul_vessels")
			"source": bad.embodiment.carriers["vessel:old_ring"].source.id = "imaginary_ring"
			"energy": bad.soul_vessels.residents.yan_heng.energy = 25
			"time": bad.soul_vessels.active.player.due_ms = bad.elapsed_ms
			"payment": bad.soul_vessels.active.player.qi_spent = true
			"target": bad.soul_vessels.active.player.target = "imaginary_stone"
			"pact": bad.soul_vessels.events = []
			"knowledge": bad.soul_vessels.residents.yan_heng.knowledge.append("omniscience")
			"double_body": bad.regions.home.actors.player.autonomous = true
			"unknown_actor":
				bad.soul_vessels.active.player.actor = "nobody"
				bad.soul_vessels.active.player.region = ""
		runner.assert_true(not world.restore(bad), "invalid soul candidate rejected: " + corruption)
		runner.assert_eq(_canonical(world), before, "rejection preserves all live domains: " + corruption)
	var until: int = world.elapsed_ms + 100000
	world.advance_to_ms(until)
	var expected: String = _canonical(world)
	runner.assert_true(world.restore(JSON.parse_string(JSON.stringify(original))), "a real in-progress lesson remains restorable after rejected loads")
	world.advance_to_ms(until)
	runner.assert_eq(_canonical(world), expected, "restored in-progress guidance has the same future and pays once")
