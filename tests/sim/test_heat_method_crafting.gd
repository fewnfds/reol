extends RefCounted

const Fixtures = preload("res://tests/sim/test_artifact_understanding.gd")


func run(runner: Object) -> void:
	_test_drafts_and_real_effects(runner)
	_test_teaching_and_resume(runner)
	_test_interruptions_and_candidates(runner)
	_test_autonomous_use(runner)
	print("SCENARIO crafted methods: authored revisions, real flow/capacity/damage, embodied teaching and personally learned NPC use")


func _world(runner: Object) -> RegionalSimulation:
	return Fixtures.new()._world(runner)


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _tested(runner: Object, world: RegionalSimulation, actor: String = "chen_shouzhuo", flow: int = 1, pulses: int = 1) -> String:
	var draft: Dictionary = world.heat_methods.compose(actor, "hearth_stone", "留火小法", flow, pulses)
	runner.assert_true(draft.ok, "experienced operator can formulate bounded flow steps")
	if not draft.ok:
		return ""
	var response: Dictionary = world.heat_methods.start(actor, "hearth_stone", str(draft.method))
	runner.assert_true(response.ok, "trial occupies the original artifact process")
	if response.ok:
		world.advance_to_ms(world.elapsed_ms + int(world.heat_methods.terms(str(draft.method)).minutes) * 60000)
	return str(draft.method)


func _test_drafts_and_real_effects(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var before: String = _canonical(world)
	runner.assert_true(not world.heat_methods.compose("player", "hearth_stone", "凭名字成仙", 1, 1).ok, "no foundation means no executable recipe by naming alone")
	runner.assert_eq(_canonical(world), before, "failed draft does not create knowledge or pay fake costs")
	var draft: Dictionary = world.heat_methods.compose("chen_shouzhuo", "hearth_stone", "细火", 1, 1)
	var id: String = str(draft.method)
	runner.assert_true(draft.ok and not world.heat_methods.knows("chen_shouzhuo", id), "a valid draft is not a verified technique")
	runner.assert_eq(world.heat_methods.compose("chen_shouzhuo", "hearth_stone", "换个名字", 1, 1).method, id, "renaming identical steps reuses the actual recipe")
	runner.assert_eq(world.heat_methods.methods.size(), 1, "same steps do not multiply ability entries")
	before = _canonical(world)
	world.heat_methods.visible_methods("player")
	world.heat_methods.visible_methods("chen_shouzhuo")
	runner.assert_eq(_canonical(world), before, "looking at authorized notes never teaches or mutates")
	var qi: int = int(world.regions.home.actors.chen_shouzhuo.qi)
	var heat: int = int(world.artifacts.objects.hearth_stone.charge)
	runner.assert_true(world.heat_methods.start("chen_shouzhuo", "hearth_stone", id).ok, "one-qi low-flow trial begins")
	runner.assert_eq(world.regions.home.actors.chen_shouzhuo.qi, qi - 1, "trial consumes the original person's actual qi")
	runner.assert_true(not world.heat_methods.knows("chen_shouzhuo", id), "input alone does not prove a future outcome")
	world.advance_to_ms(world.elapsed_ms + 60000)
	runner.assert_eq(world.artifacts.objects.hearth_stone.charge, heat + 1, "completed gentle input stores real heat in the same stone")
	runner.assert_true(world.heat_methods.knows("chen_shouzhuo", id) and not world.heat_methods.knows("player", id), "completed trial belongs to its operator, not every witness")
	var revision: Dictionary = world.heat_methods.compose("chen_shouzhuo", "hearth_stone", "细火长养", 1, 2, id)
	runner.assert_true(revision.ok and revision.method != id, "changing duration produces a separate immutable revision")
	runner.assert_eq(world.heat_methods.methods[revision.method].revision, 2, "new version records actual parent and revision")
	runner.assert_true(not world.heat_methods.knows("chen_shouzhuo", str(revision.method)), "old practice does not silently teach the revision")
	world.artifacts.objects.hearth_stone.charge = 12
	runner.assert_true(world.heat_methods.start("chen_shouzhuo", "hearth_stone", str(revision.method)).ok, "full capacity is not omnisciently revealed as a rejected command")
	world.advance_to_ms(world.elapsed_ms + 120000)
	runner.assert_true(not world.heat_methods.knows("chen_shouzhuo", str(revision.method)), "unobservable extra storage at capacity does not validate the draft")
	world = _world(runner)
	draft = world.heat_methods.compose("chen_shouzhuo", "hearth_stone", "急灌", 3, 1)
	runner.assert_true(world.heat_methods.start("chen_shouzhuo", "hearth_stone", str(draft.method)).ok, "known foundation can try a risky high-flow plan")
	world.advance_to_ms(60000)
	runner.assert_eq(world.artifacts.objects.hearth_stone.damage, 4, "high instantaneous flow opens the actual existing crack")
	runner.assert_eq(world.artifacts.objects.hearth_stone.charge, 0, "fracture loses real stored heat")
	runner.assert_true(not world.heat_methods.knows("chen_shouzhuo", str(draft.method)), "destruction is not awarded as mastery")


func _test_teaching_and_resume(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var id: String = _tested(runner, world)
	var teacher_qi: int = int(world.regions.home.actors.chen_shouzhuo.qi)
	var learner_qi: int = int(world.regions.home.actors.player.qi)
	var response: Dictionary = world.heat_methods.teach("chen_shouzhuo", "player", "hearth_stone", id)
	runner.assert_true(response.ok, "an available willing learner accepts actual hands-on instruction")
	if not response.ok:
		return
	runner.assert_true(world.artifacts.owns_actor("chen_shouzhuo") and world.artifacts.owns_actor("player"), "one original job owns both participants")
	runner.assert_eq(world.regions.home.actors.player.qi, learner_qi - 1, "learner supplies real trial energy")
	runner.assert_eq(world.regions.home.actors.chen_shouzhuo.qi, teacher_qi - 1, "guide also pays the actual attention cost")
	runner.assert_true(not world.heat_methods.knows("player", id) and not world.artifacts.describe("player", "hearth_stone").method, "acceptance does not grant either recipe or foundation")
	world.advance_to_ms(world.elapsed_ms + 12345)
	var saved: Dictionary = JSON.parse_string(_canonical(world))
	var restored: RegionalSimulation = _world(runner)
	runner.assert_true(restored.restore(saved), "ongoing two-person practice restores its original paid inputs and consent")
	var end: int = world.elapsed_ms + 70000
	world.advance_to_ms(end)
	var cursor: int = restored.elapsed_ms
	while cursor < end:
		cursor = mini(end, cursor + 493)
		restored.advance_to_ms(cursor)
	runner.assert_eq(_canonical(restored), _canonical(world), "fine/remote and JSON practice resume the same entire future")
	runner.assert_true(world.heat_methods.knows("player", id) and world.artifacts.describe("player", "hearth_stone").method, "only completed personal practice establishes the learned version and foundation")
	runner.assert_true(not world.heat_methods.knows("su_zhi", id), "nearby third party gets no free technique")
	var revision: Dictionary = world.heat_methods.compose("chen_shouzhuo", "hearth_stone", "后修", 2, 1, id)
	runner.assert_true(revision.ok and not world.heat_methods.knows("player", str(revision.method)), "student does not inherit a later revision")
	runner.assert_true(not world.heat_methods.teach("chen_shouzhuo", "player", "hearth_stone", id).ok, "already learned version cannot be replayed as another reward")
	var meals: int = world.regions.home.inventory.quantity("kitchen", "meal")
	runner.assert_true(world.artifacts.begin("player", "heat", "hearth_stone").ok, "new learner can apply the real learned foundation to an existing life use")
	world.advance_to_ms(world.elapsed_ms + 180000)
	runner.assert_eq(world.regions.home.inventory.quantity("kitchen", "meal"), meals + 6, "stored heat still cooks actual grain/water into food")


func _test_interruptions_and_candidates(runner: Object) -> void:
	for reason: String in ["teacher_cancel", "learner_cancel", "teacher_left", "communication_lost"]:
		var world: RegionalSimulation = _world(runner)
		var id: String = _tested(runner, world)
		runner.assert_true(world.heat_methods.teach("chen_shouzhuo", "player", "hearth_stone", id).ok, "interruption fixture begins real practice: " + reason)
		var qi: int = int(world.regions.home.actors.player.qi)
		match reason:
			"teacher_cancel": world.artifacts.cancel("chen_shouzhuo")
			"learner_cancel": world.artifacts.cancel("player")
			"teacher_left": world.regions.home.set_actor_cell("chen_shouzhuo", Vector2i(120, 120))
			"communication_lost": world.embodiment.release_control("subject:chen_shouzhuo", "body:chen_shouzhuo", "communication")
		world.advance_to_ms(world.elapsed_ms + 60000)
		runner.assert_true(not world.heat_methods.knows("player", id), "interrupted lesson awards no knowledge: " + reason)
		runner.assert_eq(world.regions.home.actors.player.qi, qi, "already spent energy is not refunded: " + reason)
		runner.assert_true(not world.artifacts.owns_actor("player") and not world.artifacts.owns_actor("chen_shouzhuo"), "both roles release together: " + reason)
	var world: RegionalSimulation = _world(runner)
	var id: String = _tested(runner, world)
	world.heat_methods.teach("chen_shouzhuo", "player", "hearth_stone", id)
	world.advance_to_ms(world.elapsed_ms + 10000)
	var saved: Dictionary = JSON.parse_string(_canonical(world))
	var before: String = _canonical(world)
	for fault: String in ["directory_missing", "method_missing", "free_guide", "fake_consent", "duration", "cycle"]:
		var bad: Dictionary = saved.duplicate(true)
		match fault:
			"directory_missing": bad.erase("heat_methods")
			"method_missing": bad.artifacts.active.player.method.id = "heat_method:9999"
			"free_guide": bad.artifacts.active.player.method.guide_qi = 0
			"fake_consent": bad.artifacts.active.player.method.consent = "request_9999"
			"duration": bad.artifacts.active.player.due_ms += 1
			"cycle": bad.heat_methods.methods[id].parent = id
		runner.assert_true(not world.restore(bad), "bad method/coordination candidate rejected: " + fault)
		runner.assert_eq(_canonical(world), before, "failed restore leaves all original live domains intact: " + fault)


func _test_autonomous_use(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var id: String = _tested(runner, world)
	var sim: VillageSimulation = world.regions.home
	sim.set_actor_cell("a_he", world.artifacts.object_cell("hearth_stone"))
	runner.assert_true(world.heat_methods.teach("chen_shouzhuo", "a_he", "hearth_stone", id).ok, "cook is free to agree to the same hands-on method")
	world.advance_to_ms(world.elapsed_ms + 60000)
	runner.assert_true(world.heat_methods.knows("a_he", id), "cook now has personal practice, not global recipe access")
	world.artifacts.objects.hearth_stone.charge = 0
	sim.inventory.containers.kitchen.meal = 0
	sim.inventory.containers.kitchen.wood = 0
	sim.observe_current_surroundings("a_he")
	sim.actors.a_he.autonomous = true
	sim.actors.a_he.retry_ms = world.elapsed_ms + 1
	world.invalidate_region("home")
	var restored: RegionalSimulation = _world(runner)
	runner.assert_true(restored.restore(JSON.parse_string(_canonical(world))), "personally learned NPC plan restores before autonomous adoption")
	runner.assert_true(restored.set_active_region("river"), "same cook continues while the player is in the other settlement")
	var end: int = world.elapsed_ms + 1000000
	world.advance_to_ms(end)
	var cursor: int = restored.elapsed_ms
	while cursor < end:
		cursor = mini(end, cursor + 4217)
		restored.advance_to_ms(cursor)
	restored.set_active_region(world.active_region)
	runner.assert_eq(_canonical(restored), _canonical(world), "learned autonomous method has the same whole-world future near/far and coarse/fine")
	var adopted: bool = false
	for event: Dictionary in world.artifacts.events:
		if event.actor == "a_he" and event.get("method", {}).get("id") == id and event.method.mode == "use":
			adopted = true
	runner.assert_true(adopted, "autonomous cook actually uses its personally learned recharge version after experiencing depletion")
