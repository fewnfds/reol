extends RefCounted

const Fixtures = preload("res://tests/sim/test_settlement_services.gd")
var fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_actual_purpose(runner)
	_failure_and_priorities(runner)
	_information_and_time(runner)
	_promises_and_obstructions(runner)
	_continuation_and_candidates(runner)
	print("SCENARIO autonomous livelihood: personal portable food, attributed contact, original paid work/acceptance/trade, finite fallback and same offscreen future")


func _world(runner: Object, cash: int = 4) -> RegionalSimulation:
	var world: RegionalSimulation = fixtures._make_world(runner)
	var sim: VillageSimulation = world.regions.home
	sim.inventory.containers.records["coin"] = cash
	sim.set_actor_cell("shi_tou", SimRouteTravel.cell(sim.places.records.cell))
	sim.set_actor_cell("chen_shouzhuo", SimRouteTravel.cell(sim.places.garden.cell))
	sim.observe_current_surroundings("chen_shouzhuo")
	sim.actors.shi_tou.autonomous = true
	sim.actors.shi_tou.retry_ms = 1
	world.invalidate_region("home")
	return world


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _actual_purpose(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	var total: int = fixtures._total(world, "coin")
	runner.assert_true(world.advance_to_ms(7200000), "a personal goal runs through the common scheduler")
	var id: String = world.budgeted_labor.latest_for("shi_tou")
	runner.assert_true(not id.is_empty(), "NPC independently negotiates a funded job rather than receiving a scripted payout")
	if id.is_empty():
		print("LIVELIHOOD DEBUG ", world.autonomous_livelihood.to_dict(), " body ", sim.actors.shi_tou, " requests ", sim.social.requests)
		return
	var note: Dictionary = world.budgeted_labor.contracts[id]
	runner.assert_eq(note.status, "paid", "NPC actually delivers, requests acceptance and collects the original fund")
	runner.assert_eq(sim.inventory.available("actor:shi_tou", "meal"), 1, "income buys a real portable meal in the one bag")
	runner.assert_eq(sim.inventory.quantity("actor:shi_tou", "coin"), 0, "money is spent toward the purpose, not accumulated to a panel target")
	runner.assert_eq(fixtures._total(world, "coin"), total, "autonomous labor and consumption do not create coins")
	runner.assert_true(world.autonomous_livelihood._claims_payment(sim, "shi_tou", "chen_shouzhuo"), "contact follows the worker's own attributed conversation")
	runner.assert_true(not world.autonomous_livelihood.wants_decision("shi_tou", world.elapsed_ms), "with portable food already owned, ordinary duties resume")
	var attempt: Dictionary = note.attempts.back()
	var event: Dictionary = sim.social._event_by_id[attempt.event]
	runner.assert_eq(int(event.details.public.work_credit), 0, "funded original delivery still grants no duplicate contribution")
	for known: Dictionary in sim.social.knowledge.player.values():
		runner.assert_true(known.kind != SimCapabilityConversation.KIND or known.target == "player" or known.actor == "player", "player gains no private NPC introduction by being in the same world")
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "completed personal plan validates alongside original payment and purchase")


func _failure_and_priorities(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, 0)
	var sim: VillageSimulation = world.regions.home
	world.advance_to_ms(7200000)
	runner.assert_true(world.budgeted_labor.latest_for("shi_tou").is_empty(), "no public money means no empty wage promise")
	runner.assert_eq(sim.inventory.quantity("actor:shi_tou", "coin"), 0, "failed job search mints no money")
	var worked: bool = false
	for event: Dictionary in sim.social.events:
		if event.actor == "shi_tou" and event.kind == "completed" and event.details.get("task") == "deliver_water":
			worked = true
	runner.assert_true(worked, "rejected search falls back to the original useful daily work")
	world = _world(runner)
	sim = world.regions.home
	sim.actors.shi_tou.hunger = 20.0
	world.advance_to_ms(1)
	runner.assert_eq(sim.actors.shi_tou.active.get("action"), "eat", "urgent food comes before earning a portable reserve")
	world = _world(runner)
	sim = world.regions.home
	sim.actors.shi_tou.energy = 20.0
	world.advance_to_ms(1)
	runner.assert_eq(sim.actors.shi_tou.active.get("action"), "rest", "real recovery comes before job seeking")
	world = _world(runner)
	sim = world.regions.home
	sim.inventory.containers["actor:shi_tou"]["meal"] = 1
	world.advance_to_ms(1)
	runner.assert_true(sim.actors.shi_tou.active.get("action") not in world.autonomous_livelihood.definitions.search_actions, "an already supplied person does not needlessly seek cash")
	runner.assert_eq(world.autonomous_livelihood.plans.shi_tou.last_ms, -1, "satisfied need does not manufacture a thought history")


func _information_and_time(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	runner.assert_eq(world.autonomous_livelihood._speaker("shi_tou", sim), "", "distant real office holder is not an omniscient contact")
	runner.assert_true(world.budgeted_labor.contracts.is_empty(), "knowing an institution exists does not remotely sign work")
	world.target_ms = 1000000
	runner.assert_true(not world.budgeted_labor.accept("shi_tou", "home", "chen_shouzhuo", "deliver_wood").ok, "external commands still cannot bypass outstanding world time")
	runner.assert_true(not world.budgeted_labor.accept_autonomous("shi_tou", "home", "chen_shouzhuo", "deliver_wood").ok, "autonomous entry requires a current personal decision stamp")
	runner.assert_eq(SimCapabilityConversation.ask(world, "shi_tou", "chen_shouzhuo", "ways").status, "invalid", "external conversation retains the same time gate")
	world.target_ms = 0
	world.advance_to_ms(1)
	runner.assert_eq(sim.actors.shi_tou.active.get("action"), "seek_records", "seeking begins with actual travel to a public place")
	runner.assert_true(world.budgeted_labor.contracts.is_empty(), "first search does not resolve a distant employer")
	world = _world(runner)
	sim = world.regions.home
	sim.set_actor_cell("shi_tou", SimRouteTravel.cell(sim.places.garden.cell))
	for i: int in 8:
		sim.observe("meeting", "shi_tou", "chen_shouzhuo", {})
	SimCapabilityConversation.ask(world, "shi_tou", "chen_shouzhuo", "ways")
	runner.assert_true(world.autonomous_livelihood._claims_payment(sim, "shi_tou", "chen_shouzhuo"), "an actual personal introduction supplies a fallible contact")
	sim.institutions.appoint("sect", "registrar", "a_he")
	runner.assert_true(world.autonomous_livelihood._claims_payment(sim, "shi_tou", "chen_shouzhuo"), "changing offices does not rewrite the listener's old words")
	var cash: int = sim.inventory.quantity("records", "coin")
	runner.assert_true(not world.budgeted_labor.accept("shi_tou", "home", "chen_shouzhuo", "deliver_wood").ok, "old testimony does not bypass the real current payment authority")
	runner.assert_eq(sim.inventory.quantity("records", "coin"), cash, "stale contact neither spends the fund nor grants a job")
	SimCapabilityConversation.ask(world, "shi_tou", "chen_shouzhuo", "ways")
	runner.assert_true(not world.autonomous_livelihood._claims_payment(sim, "shi_tou", "chen_shouzhuo"), "later self-report replaces older contact knowledge even within one minute")
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "same-minute attributed statements survive candidate validation")
	runner.assert_true(not copy.autonomous_livelihood._claims_payment(copy.regions.home, "shi_tou", "chen_shouzhuo"), "JSON dictionary ordering cannot revive the older payment claim")


func _promises_and_obstructions(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	sim.set_actor_cell("player", SimRouteTravel.cell(sim.actors.shi_tou.cell))
	var promise: Dictionary = world.standing_work.ask("home", "player", "shi_tou", "kitchen_wood")
	runner.assert_true(promise.ok, "a personal preparation purpose can coexist with an earlier social promise")
	world.advance_to_ms(1)
	runner.assert_eq(world.autonomous_livelihood.plans.shi_tou.last_ms, -1, "existing voluntary promise is not displaced by a private cash goal")
	runner.assert_true(sim.actors.shi_tou.active.get("action") not in world.autonomous_livelihood.definitions.search_actions, "earlier promise retains the ordinary bodily executor")
	world = _world(runner)
	sim = world.regions.home
	sim.set_actor_cell("shi_tou", SimRouteTravel.cell(sim.places.dorm.cell))
	sim.set_navigation(_blocked_path)
	world.advance_to_ms(1)
	runner.assert_eq(world.autonomous_livelihood.plans.shi_tou.last_result, "unreachable", "blocked public approach fails without teleporting to an official")
	var attempted: int = int(world.autonomous_livelihood.plans.shi_tou.last_ms)
	world.advance_to_ms(1800000)
	runner.assert_eq(world.autonomous_livelihood.plans.shi_tou.last_ms, attempted, "rejected search observes backoff instead of retrying every frame or batch")
	runner.assert_true(world.budgeted_labor.contracts.is_empty(), "unreachable worker cannot sign or receive distant work")


func _blocked_path(_from: Vector2i, _to: Vector2i) -> Array[Vector2i]:
	return []


func _continuation_and_candidates(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	world.advance_to_ms(12345)
	var saved: Dictionary = JSON.parse_string(_canonical(world))
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(saved), "searching and its original native body restore jointly")
	copy.active_region = "river"
	var stop: int = 7200000
	world.advance_to_ms(stop)
	while copy.elapsed_ms < stop:
		copy.advance_to_ms(mini(stop, copy.elapsed_ms + 17321))
	copy.set_active_region(world.active_region)
	runner.assert_eq(_canonical(copy), _canonical(world), "coarse/fine and absent/present execution produce the same entire future")
	var before: String = _canonical(copy)
	for kind: String in ["region", "stop_index", "search_count", "last_ms", "retry_ms", "last_result"]:
		var bad: Dictionary = JSON.parse_string(before)
		var plan: Dictionary = bad.autonomous_livelihood.plans.shi_tou
		match kind:
			"region": plan.region = "river"
			"stop_index": plan.stop_index = 999
			"search_count": plan.search_count = -1
			"last_ms": plan.last_ms = stop + 1
			"retry_ms": plan.retry_ms = SimInventory.MAX_COUNT
			"last_result": plan.last_result = "magically_paid"
		runner.assert_true(not copy.restore(bad), "invalid personal search state is rejected: " + kind)
		runner.assert_eq(_canonical(copy), before, "bad candidate does not partly replace the living world: " + kind)
