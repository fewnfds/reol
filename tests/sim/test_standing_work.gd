extends RefCounted

const Fixtures = preload("res://tests/sim/test_settlement_services.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_test_agreement_and_original_labor(runner)
	_test_needs_refusals_and_withdrawal(runner)
	_test_absence_expiration_and_candidates(runner)
	print("SCENARIO standing work: attributed consent, original autonomous life/labor/custody, finite term and communication-limited withdrawal")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _fixtures._make_world(runner)
	var sim: VillageSimulation = world.regions.home
	_fixtures._position(world, "home", "kitchen")
	sim.set_actor_cell("shi_tou", SimRouteTravel.cell(sim.places.kitchen.cell))
	sim.actors.shi_tou.autonomous = true
	sim.inventory.containers.kitchen.wood = 1
	world.invalidate_region("home")
	return world


func _ask(world: RegionalSimulation) -> Dictionary:
	return SimInteractionRequests.submit(world, {"sender": world.embodiment.subject_for_actor("player"), "receiver": world.embodiment.subject_for_actor("shi_tou"), "verb": "watch_supply", "object": {"kind": "work_plan", "id": "kitchen_wood"}, "medium": "spoken", "conditions": {}})


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _test_agreement_and_original_labor(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	var duties: Dictionary = sim.config.actor_profiles.duplicate(true)
	var reply: Dictionary = _ask(world)
	runner.assert_true(reply.ok, "a free companion may agree to a finite cooperative intention")
	if not reply.ok:
		return
	var id: String = str(reply.process.id)
	var until: int = int(world.standing_work.entries[id].until_ms)
	sim.actors.shi_tou.goal = "private_method_conclusion"
	runner.assert_true(not str(world.standing_work.describe("player", id).line).contains("private_method_conclusion"), "nearby agreement query does not read an idle actor's private goal or learning conclusion")
	var baseline: String = _canonical(world)
	var repeated: Dictionary = _ask(world)
	runner.assert_true(repeated.process == reply.process and _canonical(world) == baseline, "repeated same proposal neither rerolls nor extends the existing agreement")
	runner.assert_true(sim.actors.shi_tou.active.is_empty(), "consent is not immediate labor or delivery")
	world.advance_to_ms(1500000)
	runner.assert_true(sim.inventory.quantity("kitchen", "wood") > 1, "companion actually collects and carries public wood through the original executor")
	runner.assert_true(sim.actors.shi_tou.receipts.size() > 0 or sim.institutions.balance("sect", "shi_tou") > 0, "actual worker retains original public-work evidence or official recognition")
	runner.assert_true(sim.actors.player.receipts.is_empty() and sim.institutions.balance("sect", "player") == 0, "asking someone never transfers their labor credit to the player")
	runner.assert_eq(sim.config.actor_profiles, duties, "temporary promise does not rewrite the original permanent roles")
	runner.assert_true(sim.actors.shi_tou.autonomous, "cooperative promise never turns off autonomy")
	runner.assert_eq(int(world.standing_work.entries[id].until_ms), until, "ordinary work does not renew the agreed end time")
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "real work, social consent and original inventory validate together")


func _test_needs_refusals_and_withdrawal(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	sim.actors.shi_tou.hunger = 10.0
	var reply: Dictionary = _ask(world)
	runner.assert_true(reply.ok, "promise to watch later can coexist with an immediate personal food need")
	world.advance_to_ms(100)
	runner.assert_eq(sim.actors.shi_tou.active.get("action"), "eat", "original personal hunger outranks an agreed public intention")
	var denied: Dictionary = world.standing_work.ask("home", "chen_shouzhuo", "shi_tou", "kitchen_water")
	runner.assert_true(not denied.ok, "another request cannot displace an existing social promise")
	sim.set_actor_cell("player", Vector2i(200, 200))
	world.invalidate_region("home")
	var id: String = str(reply.process.id)
	runner.assert_true(not world.standing_work.withdraw(id, "player").ok, "distant requester cannot clear another person's intention by remote command")
	runner.assert_eq(world.standing_work.describe("player", id).code, "unconfirmed", "absent requester cannot inspect hidden work or current withdrawal facts")
	runner.assert_true(world.standing_work.withdraw(id, "shi_tou").ok, "companion can independently withdraw their own promise")
	runner.assert_eq(world.standing_work.describe("player", id).code, "unconfirmed", "private withdrawal is not instantly transmitted to the distant requester")
	runner.assert_true(SimInteractionRequests.pending(world, world.embodiment.subject_for_actor("player")).has(reply.process), "reconstructing request UI cannot reveal a remote private withdrawal by hiding its receipt")
	runner.assert_eq(sim.actors.shi_tou.active.get("action"), "eat", "withdrawal does not cancel ongoing real bodily actions")
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "private withdrawal and continuing hunger action remain a valid world")
	world = _world(runner)
	sim = world.regions.home
	sim.actors.shi_tou.energy = 0.0
	var first: Dictionary = _ask(world)
	var saved: String = _canonical(world)
	var second: Dictionary = _ask(world)
	runner.assert_true(not first.ok and not second.ok and first.process == second.process and _canonical(world) == saved, "same exhausted circumstances reuse the original refusal without new random rolls")
	sim.actors.shi_tou.autonomous = false
	runner.assert_true(not _ask(world).ok, "manual actor is never silently made to accept cooperative duties")


func _test_absence_expiration_and_candidates(runner: Object) -> void:
	var near: RegionalSimulation = _world(runner)
	var reply: Dictionary = _ask(near)
	if not reply.ok:
		runner.assert_true(false, "expiry fixture has an actual original promise")
		return
	var id: String = str(reply.process.id)
	var initial: String = _canonical(near)
	var far: RegionalSimulation = _world(runner)
	runner.assert_true(far.restore(JSON.parse_string(initial)), "independent absent world restores same promise")
	near.set_active_region("home")
	far.set_active_region("river")
	near.advance_to_ms(1800000)
	far.advance_to_ms(1800000)
	var left: Dictionary = JSON.parse_string(_canonical(near))
	var right: Dictionary = JSON.parse_string(_canonical(far))
	left.active_region = ""
	right.active_region = ""
	runner.assert_true(left == right, "absence preserves the same original social/labor/material future")
	var saved: Dictionary = JSON.parse_string(_canonical(near))
	for fault: String in ["consent", "term", "participant", "duplicate", "erase", "missing"]:
		var bad: Dictionary = saved.duplicate(true)
		var note: Dictionary = bad.standing_work.entries[id]
		match fault:
			"consent": note.decision = "request_99999"
			"term": note.until_ms += 1
			"participant": note.responder = "player"
			"duplicate": bad.standing_work.entries["fake"] = note.duplicate(true)
			"erase": bad.standing_work.entries.erase(id)
			"missing": bad.erase("standing_work")
		var before: String = _canonical(near)
		runner.assert_true(not near.restore(bad), "bad cooperative candidate rejected: " + fault)
		runner.assert_true(_canonical(near) == before, "bad promise cannot partly replace the live world: " + fault)
	var until: int = int(near.standing_work.entries[id].until_ms)
	near.advance_to_ms(until - 1000)
	var sim: VillageSimulation = near.regions.home
	# Start an ordinary real duty before expiry; it must finish with its real cargo.
	sim.cancel_action("shi_tou", "fixture_timing")
	sim.set_actor_cell("shi_tou", SimRouteTravel.cell(sim.places.store.cell))
	runner.assert_true(sim.submit_action("shi_tou", "deliver_wood"), "expiry fixture starts a real last in-flight public delivery")
	near.invalidate_region("home")
	near.advance_to_ms(until + 1)
	runner.assert_eq(near.standing_work.entries[id].status, "expired", "fixed deadline ends new work intention")
	runner.assert_true(not sim.actors.shi_tou.active.is_empty() and sim.inventory.entrusted("actor:shi_tou", "wood") > 0, "expiry preserves the same ongoing duty and its real entrusted cargo")
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(near))), "expired promise plus unfinished public cargo restore consistently")
