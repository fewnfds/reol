extends RefCounted

const Fixtures = preload("res://tests/sim/test_interaction_requests.gd")


func run(runner: Object) -> void:
	_descriptions_and_sources(runner)
	_medical_practice_and_history(runner)
	_reception_and_refusal(runner)
	_cross_region_and_candidates(runner)
	print("SCENARIO capability conversation: personally grounded private self-report, remembered provenance, no skill/mandate grant, same decisions and future")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = Fixtures.new()._world(runner)
	runner.assert_true(world.configure_services(JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/settlement_services.json"))), "conversation fixture binds original cross-region social ledger")
	var at: Vector2i = world.artifacts.object_cell("hearth_stone")
	for actor: String in ["player", "su_zhi", "chen_shouzhuo", "shi_tou", "a_he"]:
		world.regions.home.set_actor_cell(actor, at)
	return world


func _ask(world: RegionalSimulation, speaker: String, sender: String = "player", medium: String = "spoken") -> Dictionary:
	return SimInteractionRequests.submit(world, {"sender": world.embodiment.subject_for_actor(sender), "receiver": world.embodiment.subject_for_actor(speaker),
		"verb": "converse", "object": {"kind": "conversation_topic", "id": "ways"}, "medium": medium, "conditions": {}})


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _heard(world: RegionalSimulation, answer: Dictionary, listener: String = "player") -> String:
	return str(SimInteractionRequests.observe(world, world.embodiment.subject_for_actor(listener), answer.process).line)


func _descriptions_and_sources(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	var bad_rules: Dictionary = world._content.capability_conversation.duplicate(true)
	bad_rules.statements.material_check.rule = "run_arbitrary_text"
	runner.assert_true(not SimCapabilityConversation.valid_definitions(bad_rules), "content cannot invent an unimplemented capability inference rule")
	var inventory: String = JSON.stringify(sim.inventory.to_dict(), "", true, true)
	var novice: Dictionary = _ask(world, "shi_tou")
	runner.assert_true(novice.ok, "ordinary person can voluntarily answer the same public topic")
	if not novice.ok:
		return
	var line: String = _heard(world, novice)
	runner.assert_true(line.contains("搬运") and not line.contains("我练过温石") and not line.contains("代表公库"), "novice states ordinary embodied help without unknown magic or authority")
	var material: Dictionary = _ask(world, "su_zhi")
	runner.assert_true(material.ok, "material practitioner can answer")
	line = _heard(world, material)
	runner.assert_true(line.contains("石材接缝") and not line.contains("我练过温石"), "material experience does not turn into control experience")
	var cook: Dictionary = _ask(world, "a_he")
	runner.assert_true(cook.ok and _heard(world, cook).contains("米水下锅"), "person introduces actual daily cooking practice without disclosing stock")
	var official: Dictionary = _ask(world, "chen_shouzhuo")
	runner.assert_true(official.ok, "current official can introduce own practiced methods and office")
	line = _heard(world, official)
	runner.assert_true(line.contains("我练过温石") and line.contains("代表公库") and line.contains("核簿"), "report follows speaker's own background and appointments")
	runner.assert_true(not line.contains("钱8") and not line.contains("余额") and not line.contains("80"), "introduction discloses neither hidden cash nor warehouse quantities")
	runner.assert_eq(JSON.stringify(sim.inventory.to_dict(), "", true, true), inventory, "talking transfers no money or goods")
	runner.assert_true(not world.artifacts.describe("player", "hearth_stone").method, "hearing an expert say he understands grants no technique")
	runner.assert_true(not sim.institutions.has_permission("sect", "player", "pay"), "hearing an official grants no mandate")
	var before: String = _canonical(world)
	runner.assert_eq(_ask(world, "chen_shouzhuo").process, official.process, "unchanged repeated inquiry returns original attributed utterance")
	runner.assert_eq(_canonical(world), before, "repeat alters no events, decision counters or RNG")
	var private_event: String = str(official.process.id).get_slice(":", 1)
	runner.assert_true(not sim.social.knowledge.a_he.has(private_event), "nearby bystander receives no private introduction")
	runner.assert_eq(SimInteractionRequests.observe(world, "subject:a_he", official.process).status, "unconfirmed", "third party cannot recall another person's private answer")
	# Old speech persists after a real appointment changes; it never grants access.
	runner.assert_true(sim.institutions.appoint("sect", "registrar", "su_zhi"), "ordinary office appointment changes who represents public cash")
	var changed: Dictionary = _ask(world, "chen_shouzhuo")
	runner.assert_true(changed.ok and not _heard(world, changed).contains("代表公库"), "asking after a role change gets a new self-report")
	runner.assert_true(_heard(world, official).contains("代表公库"), "old private speech remains a historical claim rather than updating remotely")
	# A real successful study changes what the same novice can say next time.
	runner.assert_true(world.artifacts.begin("player", "study", "hearth_stone").ok, "novice can start original timed study")
	world.advance_to_ms(world.elapsed_ms + 240000)
	var learned: Dictionary = _ask(world, "player", "su_zhi")
	runner.assert_true(learned.ok and _heard(world, learned, "su_zhi").contains("我练过温石"), "NPC inquiry sees the player's actually acquired method without a fixed class")


func _medical_practice_and_history(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var rules: Dictionary = world._content.capability_conversation
	var old_rules: Dictionary = rules.duplicate(true)
	old_rules.statements.erase("herbal_meridian_care")
	runner.assert_true(SimCapabilityConversation.valid_definitions(rules) and SimCapabilityConversation.valid_definitions(old_rules), "medical statement is optional content within the implemented practice vocabulary")
	runner.assert_true(world.health.can_diagnose("su_zhi") and not world.health.can_diagnose("shi_tou") and not world.health.can_diagnose("player"), "the medical introduction starts from actual defined experience")
	var health_before: String = JSON.stringify(world.health.to_dict(), "", true, true)
	# Produce authentic speech with the previous vocabulary, then add the new
	# rule without changing what the original event, decision or listener kept.
	world._content.capability_conversation = old_rules
	var old_answer: Dictionary = _ask(world, "su_zhi")
	world._content.capability_conversation = rules
	runner.assert_true(old_answer.ok, "experienced person can give an introduction with the old vocabulary")
	if not old_answer.ok:
		return
	var old_line: String = _heard(world, old_answer)
	runner.assert_true(not old_line.contains("经脉灼涩"), "old recorded introduction contains no newly added medical words")
	runner.assert_true(SimCapabilityConversation.valid_history(world.regions.home.social, rules, world.current_time), "new statements preserve the historically recorded claim subset")
	var answer: Dictionary = _ask(world, "su_zhi")
	runner.assert_true(answer.ok and _heard(world, answer).contains("经脉灼涩") and _heard(world, answer).contains("你自己备药"), "new inquiry can report actual medical experience and the limits of offered care")
	var novice: Dictionary = _ask(world, "shi_tou")
	runner.assert_true(novice.ok and not _heard(world, novice).contains("经脉灼涩"), "ordinary knowledge and local affiliation do not become medical practice")
	runner.assert_true(not world.health.can_diagnose("player"), "hearing the practitioner's introduction grants no diagnostic ability")
	runner.assert_eq(JSON.stringify(world.health.to_dict(), "", true, true), health_before, "introductions diagnose nobody and create no treatment, injury or recovery")
	var snapshot: Dictionary = JSON.parse_string(_canonical(world))
	var restored: RegionalSimulation = _world(runner)
	runner.assert_true(restored.restore(snapshot), "old and new medical-capability speech coexist in one validated world")
	runner.assert_eq(_heard(restored, old_answer), old_line, "restoring after adding medical content preserves the exact old utterance")
	runner.assert_eq(_heard(restored, answer), _heard(world, answer), "the later medical statement retains its original speaker and wording")


func _reception_and_refusal(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var sim: VillageSimulation = world.regions.home
	var before: String = _canonical(world)
	runner.assert_eq(_ask(world, "su_zhi", "player", "gesture").status, "not_understood", "complex personal introduction is not automatically understood as gestures")
	runner.assert_eq(_canonical(world), before, "misunderstanding creates no hidden answer")
	sim.set_actor_cell("su_zhi", Vector2i(180, 180))
	runner.assert_eq(_ask(world, "su_zhi").status, "unheard", "remote person does not report private capabilities")
	sim.set_actor_cell("su_zhi", world.artifacts.object_cell("hearth_stone"))
	runner.assert_true(world.artifacts.begin("su_zhi", "examine", "hearth_stone").ok, "speaker starts original focused inspection")
	runner.assert_eq(_ask(world, "su_zhi").status, "unavailable", "focused task takes precedence over introduction")
	world.artifacts.cancel("su_zhi")
	sim.social.relationships.su_zhi.player = {"reliability": 0.0, "affinity": -1.0, "history": []}
	var refused: Dictionary = _ask(world, "su_zhi")
	runner.assert_eq(refused.status, "refused", "capability does not imply willingness to introduce oneself to an enemy")
	before = _canonical(world)
	runner.assert_eq(_ask(world, "su_zhi").status, "refused", "same refusal is cached")
	runner.assert_eq(_canonical(world), before, "repeated refused inquiry does not reroll")
	var bird: Dictionary = world.avian_life.birds.moss_sparrow
	var at: Vector2 = TileGrid.cell_to_world(world.artifacts.object_cell("hearth_stone"))
	bird.position = [at.x, at.y]
	var bird_ask: Dictionary = {"sender": "subject:player", "receiver": "subject:avian:moss_sparrow", "verb": "converse", "object": {"kind": "conversation_topic", "id": "ways"}, "medium": "spoken", "conditions": {}}
	runner.assert_eq(SimInteractionRequests.submit(world, bird_ask).status, "not_understood", "a low-intelligence bird is not a human service directory")


func _cross_region_and_candidates(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var remote: VillageSimulation = world.regions.river
	var speaker: String = str(remote.actors.keys()[0])
	world.regions.home.set_actor_cell("player", SimRouteTravel.cell(remote.actors[speaker].cell))
	var result: Dictionary = _ask(world, speaker)
	runner.assert_true(result.ok and str(result.process.id).begins_with("services:"), "visitor and local share existing cross-region social memory")
	if not result.ok:
		return
	var spoken: String = _heard(world, result)
	var snapshot: Dictionary = JSON.parse_string(_canonical(world))
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(snapshot), "attributed cross-region statement restores with all original domains")
	runner.assert_eq(_heard(copy, result), spoken, "same received statement survives world replacement")
	world.advance_to_ms(100123)
	var prior_region: String = str(copy.active_region)
	copy.active_region = "river"
	copy.advance_to_ms(100123)
	copy.active_region = prior_region
	runner.assert_eq(_canonical(copy), _canonical(world), "talking leaves both worlds with the identical subsequent future")
	var before: String = _canonical(copy)
	var bad: Dictionary = JSON.parse_string(before)
	bad.services.social.events.back().details.participants.text = "秘密仓库：无限灵石"
	runner.assert_true(not copy.restore(bad), "altered private text is rejected instead of becoming an all-knowing report")
	runner.assert_eq(_canonical(copy), before, "bad utterance candidate leaves live world unchanged")
	bad = JSON.parse_string(before)
	bad.services.social.events.back().details.private.decision = "request_99999"
	runner.assert_true(not copy.restore(bad), "statement must link to original voluntary decision")
	runner.assert_eq(_canonical(copy), before, "bad consent reference also leaves live world unchanged")
