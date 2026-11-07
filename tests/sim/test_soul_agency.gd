extends RefCounted

const Fixtures = preload("res://tests/sim/test_soul_vessels.gd")
var _fixtures: RefCounted = Fixtures.new()


func run(runner: Object) -> void:
	_test_self_sense_and_actual_cooperation(runner)
	_test_body_refusal_and_cancel_keeps_custody(runner)
	_test_saved_route_and_bad_candidates(runner)


func _make(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _fixtures._make(runner)
	var d: SimSoulVessels = world.soul_vessels
	world.regions.home.set_actor_cell("su_zhi", d.vessel_cell("old_ring") + Vector2i.RIGHT)
	runner.assert_true(d.agency.activate("yan_heng"), "same actual resident can begin one manual life at time zero")
	return world


func _state(world: RegionalSimulation) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true)), "", true, true)


func _test_self_sense_and_actual_cooperation(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	var d: SimSoulVessels = world.soul_vessels
	var agency: SimSoulAgency = d.agency
	var before: String = _state(world)
	var view: Dictionary = agency.perceive("yan_heng")
	runner.assert_true(not view.has("inventory") and not view.has("energy") and not view.has("qi"), "self perception never exposes human or hidden material ledgers")
	for signal_row: Dictionary in view.signals:
		runner.assert_eq(signal_row.label, "一道呼吸的气息", "unintroduced sensed people have no automatically known proper names")
	runner.assert_eq(_state(world), before, "passive self sensing changes neither person nor world")
	var helper_start: Array = world.regions.home.actors.su_zhi.position.duplicate()
	runner.assert_true(agency.command("yan_heng", "call", "su_zhi").ok, "resident can transmit a concrete request to someone actually sensed")
	runner.assert_eq(d.residents.yan_heng.energy, 14, "transmission spends the same resident's original attention")
	world.advance_to_ms(4999)
	runner.assert_true(agency.errands.is_empty(), "a half-heard request does not prematurely move a human")
	world.advance_to_ms(5000)
	runner.assert_true(agency.errands.has("su_zhi"), "available willing person independently accepts the actual request")
	runner.assert_eq(world.regions.home.actors.su_zhi.position, helper_start, "acceptance itself never teleports a helper")
	runner.assert_eq(d.vessels.old_ring.container, "kitchen", "accepted promise does not teleport the ring into an inventory")
	runner.assert_true(not world.regions.home.submit_action("su_zhi", "rest"), "accepted carry occupies the helper's original body")
	var deadline: int = world.elapsed_ms + 120000
	while not agency.errands.is_empty() and world.elapsed_ms < deadline:
		world.advance_to_ms(agency.next_boundary_ms())
	runner.assert_true(agency.errands.is_empty(), "real approach, pickup and carry reach a terminal outcome")
	runner.assert_eq(d.vessels.old_ring.container, "actor:su_zhi", "the one ring physically ends in the helper's custody")
	runner.assert_eq(world.regions.home.actors.su_zhi.cell, world.regions.home.places.garden.cell, "the original human actually walks to the requested garden")
	runner.assert_true(agency.command("yan_heng", "observe").ok, "resident can personally observe after actual arrival")
	world.advance_to_ms(world.elapsed_ms + 10000)
	runner.assert_true(str(agency.perceive("yan_heng").latest).contains("药木"), "arrival permits an actual new personal experience rather than a remote omniscient fact")
	runner.assert_true(world.restore(JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))), "manual soul, consent, human body and current observation persist together")


func _test_body_refusal_and_cancel_keeps_custody(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	var d: SimSoulVessels = world.soul_vessels
	var agency: SimSoulAgency = d.agency
	world.regions.home.actors.su_zhi.energy = 0.0
	runner.assert_true(agency.command("yan_heng", "call", "su_zhi").ok, "request may be sent without knowing another person's hidden fatigue")
	world.advance_to_ms(5000)
	runner.assert_true(agency.errands.is_empty() and agency.events.back().kind == "refused", "an exhausted actual person can refuse the resident's wish")
	runner.assert_eq(d.vessels.old_ring.container, "kitchen", "refusal preserves actual custody")
	world.regions.home.actors.su_zhi.energy = 100.0
	runner.assert_true(agency.command("yan_heng", "call", "su_zhi").ok, "changed actual circumstances can support a new agreement")
	world.advance_to_ms(10000)
	while not agency.errands.is_empty() and not agency.errands.su_zhi.picked:
		world.advance_to_ms(agency.next_boundary_ms())
	runner.assert_true(agency.errands.has("su_zhi") and agency.errands.su_zhi.picked, "cancellation fixture has already physically taken the ring")
	var point: Array = world.regions.home.actors.su_zhi.position.duplicate()
	agency.command("yan_heng", "cancel")
	runner.assert_true(agency.errands.is_empty(), "resident can withdraw a pending carry request")
	runner.assert_eq(d.vessels.old_ring.container, "actor:su_zhi", "cancel never refunds or teleports an already carried ring")
	runner.assert_eq(world.regions.home.actors.su_zhi.position, point, "cancel never teleports the helper back to the request origin")
	runner.assert_true(agency.command("yan_heng", "sleep").ok, "resident can choose to withdraw their own consciousness")
	world.advance_to_ms(world.elapsed_ms + 605000)
	runner.assert_true(agency.perceive("yan_heng").signals.is_empty(), "sleeping does not silently reveal people who passed nearby")
	runner.assert_true(agency.command("yan_heng", "wake").ok, "resident always has a self-waking path without requiring a human controller")
	world.advance_to_ms(world.elapsed_ms + 1000)
	runner.assert_true(d.residents.yan_heng.awake, "same resident reawakens in the same carried ring")


func _test_saved_route_and_bad_candidates(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	world.soul_vessels.agency.command("yan_heng", "call", "su_zhi")
	world.advance_to_ms(5000)
	world.advance_to_ms(5100)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))
	var before: String = _state(world)
	for kind: String in ["consent", "double", "phase", "time", "manual", "point"]:
		var bad: Dictionary = saved.duplicate(true)
		match kind:
			"consent": bad.soul_vessels.agency.social.requests = {}
			"double": bad.regions.home.actors.su_zhi.autonomous = true
			"phase": bad.soul_vessels.agency.errands.su_zhi.phase = "teleport"
			"time": bad.soul_vessels.agency.errands.su_zhi.due_ms = 5100
			"manual": bad.soul_vessels.agency.manual = "unknown_soul"
			"point": bad.regions.home.actors.su_zhi.position[0] += 2.0
		runner.assert_true(not world.restore(bad), "invalid soul intention rejected: " + kind)
		runner.assert_eq(_state(world), before, "bad soul intention leaves all live state intact: " + kind)
	world.advance_to_ms(120000)
	var expected: String = _state(world)
	runner.assert_true(world.restore(saved), "unfinished actual human carry can be restored")
	while world.elapsed_ms < 120000:
		world.advance_to_ms(mini(120000, world.elapsed_ms + 97))
	runner.assert_eq(_state(world), expected, "sparse absent carry and detailed resumed carry have the same whole-world future")
