extends RefCounted

const Fixtures = preload("res://tests/sim/test_artifact_understanding.gd")


func run(runner: Object) -> void:
	_test_reception_and_authority(runner)
	_test_real_inspection_and_resume(runner)
	_test_specific_bird_errand(runner)
	print("SCENARIO requests: same structured intent, different understanding/body/consent, original timed jobs and specific real cargo")


func _world(runner: Object, neighboring_crevices: bool = false) -> RegionalSimulation:
	var world: RegionalSimulation = Fixtures.new()._world(runner)
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/avian_life.json"))
	if neighboring_crevices:
		opening.regions.home.sites.second_crevice.offset = [-6, 2]
	runner.assert_true(world.avian_life.spawn_opening(opening, {"home": Vector2i(100, 100), "river": Vector2i(150, 100)}), "request fixture uses actual avian carriers")
	return world


func _intent(receiver: String = "subject:su_zhi", verb: String = "examine", object_id: String = "hearth_stone", sender: String = "subject:player", medium: String = "spoken") -> Dictionary:
	return {"sender": sender, "receiver": receiver, "verb": verb,
		"object": {"kind": "avian_site" if verb == "fetch_herb" else "artifact", "id": object_id}, "medium": medium, "conditions": {}}


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _test_reception_and_authority(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var before: String = _canonical(world)
	var malformed: Dictionary = _intent()
	malformed.conditions = {"secret_free_reward": true}
	runner.assert_eq(SimInteractionRequests.submit(world, malformed).status, "invalid", "unsupported conditions are rejected instead of ignored")
	malformed = _intent()
	malformed.extra = "arbitrary tool"
	runner.assert_eq(SimInteractionRequests.submit(world, malformed).status, "invalid", "unknown envelope fields do not silently invoke anything")
	malformed = _intent()
	malformed.object.id = "unseen_object"
	runner.assert_eq(SimInteractionRequests.submit(world, malformed).status, "unheard", "unknown object cannot be pointed out")
	runner.assert_eq(_canonical(world), before, "invalid intents alter no resources, knowledge, jobs or RNG")
	var bird: Dictionary = world.avian_life.birds.moss_sparrow
	var at: Vector2 = TileGrid.cell_to_world(world.artifacts.object_cell("hearth_stone"))
	bird.position = [at.x, at.y]
	before = _canonical(world)
	runner.assert_eq(SimInteractionRequests.submit(world, _intent("subject:avian:moss_sparrow")).status, "not_understood", "seeing a bird does not let it understand an identification request")
	runner.assert_eq(_canonical(world), before, "misunderstanding grants no inspection, method or new social dice")
	var crevice: String = "home:crevice"
	world.regions.home.set_actor_cell("player", SimRouteTravel.cell(world.avian_life.sites[crevice].cell))
	runner.assert_eq(SimInteractionRequests.submit(world, _intent("subject:chen_shouzhuo", "fetch_herb", crevice)).status, "incapable", "a willing human cannot reach a bird-sized crevice by authority alone")
	world.regions.home.set_actor_cell("player", world.artifacts.object_cell("hearth_stone"))
	world.regions.home.set_actor_cell("su_zhi", Vector2i(110, 110))
	runner.assert_eq(SimInteractionRequests.submit(world, _intent()).status, "unheard", "remote responder is not silently called")
	world.regions.home.set_actor_cell("su_zhi", world.artifacts.object_cell("hearth_stone"))
	world.embodiment.release_control("subject:player", "body:player", "communication")
	runner.assert_eq(SimInteractionRequests.submit(world, _intent()).status, "unheard", "lost communication control cannot be bypassed")
	world.embodiment.grant_control("subject:player", "body:player", "communication")
	world.regions.home.actors.su_zhi.energy = 0.0
	runner.assert_eq(SimInteractionRequests.submit(world, _intent()).status, "refused", "an exhausted person's refusal differs from misunderstanding")
	var rng: String = str(world.regions.home._rng.state)
	SimInteractionRequests.submit(world, _intent())
	runner.assert_eq(str(world.regions.home._rng.state), rng, "same social proposal reuses the original decision")


func _test_real_inspection_and_resume(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var answer: Dictionary = SimInteractionRequests.submit(world, _intent())
	runner.assert_eq(answer.status, "started", "generic intent starts the original material inspection")
	if not bool(answer.ok):
		return
	var action_id: String = str(world.artifacts.active.su_zhi.id)
	runner.assert_eq(answer.process.id, action_id, "receipt refers to the original process, not a second job")
	runner.assert_eq(SimInteractionRequests.observe(world, "subject:player", answer.process).status, "pending", "acceptance is not a completed result")
	var rng: String = str(world.regions.home._rng.state)
	runner.assert_eq(SimInteractionRequests.submit(world, _intent()).status, "unavailable", "pending work cannot be restarted with another envelope")
	runner.assert_eq(str(world.regions.home._rng.state), rng, "busy duplicate does not reroll")
	world.advance_to_ms(12345)
	var restored: RegionalSimulation = _world(runner)
	runner.assert_true(restored.restore(JSON.parse_string(_canonical(world))), "old domain snapshot alone resumes the generic request")
	runner.assert_eq(SimInteractionRequests.pending(restored, "subject:player"), [answer.process], "pending view rebuilds from original participant/consent")
	world.advance_to_ms(120000)
	var cursor: int = restored.elapsed_ms
	while cursor < 120000:
		cursor = mini(120000, cursor + 517)
		restored.advance_to_ms(cursor)
	runner.assert_eq(_canonical(restored), _canonical(world), "coarse/fine and JSON continuation preserve every original domain")
	var heard: Dictionary = SimInteractionRequests.observe(restored, "subject:player", answer.process)
	runner.assert_eq(heard.status, "completed", "actual nearby completion gives an attributed response")
	runner.assert_true(str(heard.line).contains("苏芷") and str(heard.line).contains("细裂"), "result uses the real examiner's material experience")
	runner.assert_true(not restored.artifacts.describe("player", "hearth_stone").method, "hearing a result grants no technique")
	runner.assert_eq(SimInteractionRequests.observe(restored, "subject:chen_shouzhuo", answer.process).status, "unconfirmed", "knowing another process ID grants no private conclusion")
	world = _world(runner)
	answer = SimInteractionRequests.submit(world, _intent())
	world.regions.home.set_actor_cell("player", Vector2i(120, 120))
	world.advance_to_ms(120000)
	runner.assert_eq(SimInteractionRequests.observe(world, "subject:player", answer.process).status, "unconfirmed", "leaving cannot be turned into omniscient completion via receipt")
	world = _world(runner)
	answer = SimInteractionRequests.submit(world, _intent("subject:su_zhi", "examine", "hearth_stone", "subject:chen_shouzhuo"))
	runner.assert_eq(answer.status, "started", "NPC subject can submit the very same protocol")
	world.advance_to_ms(120000)
	runner.assert_eq(SimInteractionRequests.observe(world, "subject:chen_shouzhuo", answer.process).status, "completed", "NPC receives only its own result")


func _test_specific_bird_errand(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, true)
	var domain: SimAvianLife = world.avian_life
	var body: Dictionary = domain.birds.moss_sparrow
	var start: Vector2i = SimRouteTravel.cell(domain.sites["home:seeds"].cell)
	world.regions.home.set_actor_cell("player", start)
	var point: Vector2 = TileGrid.cell_to_world(start)
	body.position = [point.x, point.y]
	body.energy = 90 * SimAvianLife.SCALE
	body.fullness = 80 * SimAvianLife.SCALE
	var proposal: Dictionary = _intent("subject:avian:moss_sparrow", "fetch_herb", "home:second_crevice", "subject:player", "gesture")
	runner.assert_eq(SimInteractionRequests.submit(world, proposal).status, "refused", "understanding a gesture does not create willingness")
	world.regions.home.inventory.containers["actor:player"]["meal"] = 1
	runner.assert_true(domain.offer_grain("player", "moss_sparrow").ok, "a real food gift changes this specific bird's experience")
	proposal.medium = "spoken"
	runner.assert_eq(SimInteractionRequests.submit(world, proposal).status, "not_understood", "same concrete request in an unknown medium is not executed")
	proposal.medium = "gesture"
	var amount: int = domain.inventory.quantity("home:second_crevice", "herb")
	var untouched: int = domain.inventory.quantity("home:crevice", "herb")
	var garden: int = world.regions.home.inventory.quantity("garden", "herb")
	var answer: Dictionary = SimInteractionRequests.submit(world, proposal)
	runner.assert_eq(answer.status, "started", "gesture plus actual prior experience starts existing errand")
	if not bool(answer.ok):
		return
	runner.assert_eq(body.errand.source, "home:second_crevice", "requested source is respected instead of using another nearest place")
	world.advance_to_ms(50)
	var restored: RegionalSimulation = _world(runner, true)
	runner.assert_true(restored.restore(JSON.parse_string(_canonical(world))), "specific herb target persists in the original in-flight bird errand")
	runner.assert_true(SimInteractionRequests.pending(restored, "subject:player").has(answer.process), "bird agreement also reconstructs the pending request")
	world.advance_to_ms(60000)
	restored.advance_to_ms(60000)
	runner.assert_eq(_canonical(restored), _canonical(world), "request adds no separate unsaved future")
	runner.assert_eq(domain.inventory.quantity("home:second_crevice", "herb"), amount - 1, "real herb is removed from the specifically requested crevice")
	runner.assert_eq(domain.inventory.quantity("home:crevice", "herb"), untouched, "other possible source was not substituted")
	runner.assert_eq(world.regions.home.inventory.quantity("garden", "herb"), garden + 1, "original inventory receives one physical delivery")
	runner.assert_eq(SimInteractionRequests.observe(world, "subject:player", answer.process).status, "unconfirmed", "backend delivery history is not free player knowledge")
	runner.assert_true(not SimInteractionRequests.submit(world, proposal).ok, "one past gift cannot fund unlimited errands")
	world.regions.home.set_actor_cell("player", start)
	domain.cancel("moss_sparrow")
	body.position = [point.x, point.y]
	body.energy = 90 * SimAvianLife.SCALE
	body.fullness = 80 * SimAvianLife.SCALE
	world.regions.home.inventory.containers["actor:player"]["meal"] = 1
	runner.assert_true(domain.offer_grain("player", "moss_sparrow").ok, "another real gift precedes a separate agreement")
	var later: Dictionary = SimInteractionRequests.submit(world, proposal)
	runner.assert_eq(later.status, "started", "same pair can agree to another distinct real errand")
	runner.assert_eq(SimInteractionRequests.observe(world, "subject:player", answer.process).status, "unconfirmed", "old receipt cannot borrow progress from the same bird's later agreement")
	runner.assert_eq(SimInteractionRequests.observe(world, "subject:player", later.process).status, "pending", "only the current agreement reports current progress")
