extends RefCounted
## Specific injury, private care, original materials and a continuous world.

const Fixtures = preload("res://tests/sim/test_settlement_services.gd")
var fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_sources_and_life(runner)
	_diagnosis_and_materials(runner)
	_consent_and_cross_region(runner)
	_interruptions(runner)
	_recovery_and_future(runner)
	_npc_and_privacy(runner)
	_bad_candidates(runner)
	print("SCENARIO health: actual backlash, continued ordinary life, two-body consent and care, private herbs, gradual rest, autonomous requests and joint continuation")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = fixtures._make_world(runner)
	if world == null:
		return null
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))
	runner.assert_true(world.artifacts.spawn_opening(opening), "health fixture has the actual finite hearth stone")
	fixtures._position(world, "home", "kitchen")
	return world


func _state(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _artifact(runner: Object, world: RegionalSimulation, actor: String, verb: String) -> void:
	var answer: Dictionary = world.artifacts.begin(actor, verb, "hearth_stone")
	runner.assert_true(answer.ok, "real risk source action starts: " + actor + "/" + verb + "/" + str(answer.line))
	if answer.ok:
		runner.assert_true(world.advance_to_ms(int(world.artifacts.active[actor].due_ms)), "original action reaches its actual effect")


func _injured(runner: Object, actor: String = "player") -> RegionalSimulation:
	var world: RegionalSimulation = _world(runner)
	if actor != "player":
		world.regions.home.set_actor_cell(actor, SimRouteTravel.cell(world.regions.home.places.kitchen.cell))
		world.invalidate_region("home")
	_artifact(runner, world, actor, "heat")
	runner.assert_true(not world.health.current_source(actor).is_empty(), "only the committed backlash creates a persistent specific injury")
	return world


func _doctor(world: RegionalSimulation, patient: String = "player", doctor: String = "su_zhi") -> void:
	var region: String = world.health.home(doctor)
	var person: Dictionary = world.regions[region].actors[doctor]
	person.autonomous = true
	person.retry_ms = world.elapsed_ms + 6000000
	person.energy = 85.0
	world.regions[region].set_actor_cell(doctor, SimRouteTravel.cell(world.regions[world.health.home(patient)].actors[patient].cell))
	world.invalidate_region(region)


func _care(runner: Object, world: RegionalSimulation, verb: String, patient: String = "player", doctor: String = "su_zhi") -> String:
	var answer: Dictionary = world.health.request(patient, doctor, verb)
	runner.assert_true(answer.ok, "actual care begins: " + verb + "/" + str(answer.line))
	if not answer.ok:
		return ""
	var id: String = str(answer.id)
	runner.assert_true(world.advance_to_ms(int(world.health.jobs[id].due_ms)), "both original bodies spend the complete care duration")
	runner.assert_eq(world.health.jobs[id].status, "completed", "completed care is recorded only at its actual deadline")
	return id


func _sources_and_life(runner: Object) -> void:
	var healthy: RegionalSimulation = _world(runner)
	_artifact(runner, healthy, "player", "inspect")
	runner.assert_true(healthy.health.wounds.is_empty(), "ordinary looking causes no imaginary injury")
	_artifact(runner, healthy, "player", "study")
	_artifact(runner, healthy, "player", "charge")
	runner.assert_true(healthy.health.wounds.is_empty(), "properly learned channeling causes no random illness")
	_artifact(runner, healthy, "player", "force")
	runner.assert_eq(healthy.artifacts.events.back().kind, "fractured", "the original unsafe stone actually fractures")
	runner.assert_true(not healthy.health.current_source("player").is_empty(), "fractured source leaves the same specific bodily consequence")
	var world: RegionalSimulation = _injured(runner)
	var source: String = world.health.current_source("player")
	var wound: Dictionary = world.health.wounds[source]
	runner.assert_eq(wound.type, "meridian_irritation", "first consequence concerns this body and flow, not universal HP")
	runner.assert_eq(wound.remaining, world.health.definitions.recovery.required, "risk commit does not instantly count earlier minutes as recovery")
	world.health.record_effect(world.artifacts.events.back())
	runner.assert_eq(world.health.wounds.size(), 1, "repeated source commit never duplicates the same injury")
	runner.assert_true(not world.artifacts.begin("player", "charge", "hearth_stone").ok, "affected meridians prevent renewed channeling")
	runner.assert_true(world.health.describe("player").contains("灼涩"), "the affected person feels a concrete qualitative limitation")
	world.regions.home.set_actor_cell("player", Vector2i(97, 99))
	runner.assert_eq(SimRouteTravel.cell(world.regions.home.actors.player.cell), Vector2i(97, 99), "ordinary relocation remains possible")
	runner.assert_true(world.regions.home.submit_action("player", "rest"), "ordinary rest remains possible with an injury")
	world.regions.home.cancel_action("player")
	fixtures._position(world, "home", "kitchen")
	_artifact(runner, world, "player", "study")
	runner.assert_true(not world.health.current_source("player").is_empty(), "learning does not erase a real bodily consequence")
	runner.assert_true(world.health.eligible("player") and not world.health.eligible("sparrow"), "human treatment is not silently applied to an unrelated body")


func _diagnosis_and_materials(runner: Object) -> void:
	var world: RegionalSimulation = _injured(runner)
	_doctor(world)
	_doctor(world, "player", "shi_tou")
	runner.assert_eq(world.health.request("player", "shi_tou", "diagnose").code, "incapable", "a willing ordinary coworker does not gain medical practice from a request")
	runner.assert_true(not world.health.request("player", "su_zhi", "treat").ok, "hearsay and supplies do not replace the doctor's actual examination")
	var answer: Dictionary = world.health.request("player", "su_zhi", "diagnose")
	runner.assert_true(answer.ok, "the nearby experienced person can consent to an actual examination")
	if not answer.ok:
		return
	var id: String = str(answer.id)
	runner.assert_true(world.health.owns_actor("player") and world.health.owns_actor("su_zhi"), "examination owns both original bodies")
	runner.assert_true(not world.regions.home.submit_action("player", "rest") and not world.regions.home.submit_action("su_zhi", "deliver_grain"), "neither patient nor doctor can simultaneously execute a native job")
	runner.assert_true(not world.services.begin("player", "home", "eat").ok, "a service cannot also own the examining patient")
	world.advance_to_ms(int(world.health.jobs[id].due_ms))
	var source: String = world.health.current_source("player")
	runner.assert_true(not world.health.owns_actor("player") and world.health.wounds[source].treated_ms == -1, "examination yields information without treating the injury")
	runner.assert_true(not world.health.request("player", "su_zhi", "treat").ok, "knowing what to do does not supply free medicine")
	var inventory: SimInventory = world.regions.home.inventory
	inventory.containers["actor:player"]["herb"] = 2
	runner.assert_true(inventory.entrust("health_test_public", "actor:player", "herb", 2, {"domain": "test", "owner": "sect"}), "test fixture entrusts original physical herbs")
	var before: int = inventory.quantity("actor:player", "herb")
	runner.assert_true(not world.health.request("player", "su_zhi", "treat").ok, "patient-carried public herbs remain protected from private use")
	runner.assert_eq(inventory.quantity("actor:player", "herb"), before, "refused unauthorized care consumes no material")
	inventory.custody.erase("health_test_public")
	runner.assert_true(inventory.reserve("health_test_reserved", "actor:player", "herb", 2, "other"), "another real action can reserve the same physical herbs")
	runner.assert_true(not world.health.request("player", "su_zhi", "treat").ok, "medicine reserved by another action is not silently stolen")
	inventory.release("health_test_reserved")
	answer = world.health.request("player", "su_zhi", "treat")
	runner.assert_true(answer.ok, "patient's own disposable herbs allow actual care")
	if not answer.ok:
		return
	id = str(answer.id)
	var before_recovery: int = int(world.health.wounds[source].remaining)
	runner.assert_eq(inventory.quantity("actor:player", "herb"), before - int(world.health.definitions.material_amount), "the original bag loses exactly the invested medicine at start")
	runner.assert_eq(world.health.wounds[source].treated_ms, -1, "investing material does not grant early treatment")
	world.advance_to_ms(int(world.health.jobs[id].due_ms))
	runner.assert_eq(world.health.wounds[source].treated_ms, world.elapsed_ms, "treatment starts affecting future recovery only when actual work finishes")
	var ordinary_pulses: int = floori(float(world.health.duration("treat")) / 60000.0)
	runner.assert_eq(world.health.wounds[source].remaining, before_recovery - ordinary_pulses * int(world.health.definitions.recovery.normal), "completed treatment does not retroactively improve the minutes spent preparing it")
	runner.assert_true(int(world.health.wounds[source].remaining) > 0, "completed care is not instant universal healing")
	runner.assert_true(not world.health.request("player", "su_zhi", "treat").ok, "reopening the same request cannot repeatedly apply completed care")
	var materials: int = inventory.quantity("actor:player", "herb")
	world.advance_to_ms(world.elapsed_ms)
	runner.assert_eq(inventory.quantity("actor:player", "herb"), materials, "repeated settlement consumes no second medicine")
	before_recovery = int(world.health.wounds[source].remaining)
	world.advance_to_ms(world.elapsed_ms + 60000)
	runner.assert_eq(world.health.wounds[source].remaining, before_recovery - int(world.health.definitions.recovery.treated), "one whole future minute receives the completed treatment's recovery condition")


func _interruptions(runner: Object) -> void:
	var world: RegionalSimulation = _injured(runner)
	_doctor(world)
	_care(runner, world, "diagnose")
	world.regions.home.inventory.containers["actor:player"]["herb"] = 2
	var answer: Dictionary = world.health.request("player", "su_zhi", "treat")
	runner.assert_true(answer.ok, "cancel fixture starts real invested care")
	if not answer.ok:
		return
	var source: String = world.health.current_source("player")
	world.advance_to_ms(world.elapsed_ms + 1000)
	runner.assert_true(world.health.cancel("su_zhi"), "either participant can stop actual care")
	runner.assert_true(not world.health.owns_actor("player") and not world.health.owns_actor("su_zhi"), "doctor cancellation releases both body owners")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "herb"), 1, "cancelled preparation does not regenerate invested herbs")
	runner.assert_eq(world.health.wounds[source].treated_ms, -1, "cancelled care grants no partial completed-treatment condition")
	runner.assert_true(world.regions.home.actors.su_zhi.autonomous and not world.regions.home.actors.player.autonomous, "each person regains exactly their prior autonomy")
	answer = world.health.request("player", "su_zhi", "treat")
	runner.assert_true(answer.ok, "a new physical preparation may start from remaining real herbs")
	if not answer.ok:
		return
	var body: String = world.embodiment.carrier_for_source("village_actor", "su_zhi")
	world.embodiment.release_control(world.embodiment.subject_for_actor("su_zhi"), body, "communication")
	world.advance_to_ms(world.elapsed_ms + 1)
	runner.assert_eq(world.health.jobs[answer.id].status, "failed", "loss of the doctor's communication/control interrupts the process")
	runner.assert_eq(world.health.wounds[source].treated_ms, -1, "interrupted control never finishes a treatment offscreen")


func _consent_and_cross_region(runner: Object) -> void:
	var world: RegionalSimulation = _injured(runner)
	_doctor(world)
	world.regions.home.actors.su_zhi.energy = 0.0
	var answer: Dictionary = world.health.request("player", "su_zhi", "diagnose")
	runner.assert_eq(answer.code, "refused", "actual experience does not oblige a depleted doctor to agree")
	var decisions: int = world.regions.home.social.requests.size()
	var rng: int = world.regions.home._rng.state
	answer = world.health.request("player", "su_zhi", "diagnose")
	runner.assert_eq(answer.code, "refused", "the same unfavorable request is still refused")
	runner.assert_eq(world.regions.home.social.requests.size(), decisions, "repeated identical care requests reuse the original social decision")
	runner.assert_eq(world.regions.home._rng.state, rng, "reopening the menu does not reroll consent")
	runner.assert_true(world.health.jobs.is_empty(), "social refusal creates no body task or material cost")
	world = _injured(runner)
	runner.assert_eq(world.health.request("player", "river_su_zhi", "diagnose").code, "unheard", "knowledge of a far away medical background is not remote treatment")
	_doctor(world, "player", "river_su_zhi")
	_care(runner, world, "diagnose", "player", "river_su_zhi")
	world.regions.home.inventory.containers["actor:player"]["herb"] = 1
	answer = world.health.request("player", "river_su_zhi", "treat")
	runner.assert_true(answer.ok, "physically present visitor and patient can agree across their original home identities")
	if not answer.ok:
		return
	world.advance_to_ms(world.elapsed_ms + 713)
	var resumed: RegionalSimulation = _world(runner)
	runner.assert_true(resumed.restore(JSON.parse_string(_state(world))), "cross-region care validates the service social memory and original patient's material operation")
	var finish: int = int(world.health.jobs[answer.id].due_ms)
	world.advance_to_ms(finish)
	resumed.advance_to_ms(finish)
	runner.assert_eq(_state(resumed), _state(world), "the visiting doctor is never duplicated or lost by joint continuation")


func _recovery_and_future(runner: Object) -> void:
	var active: RegionalSimulation = _injured(runner)
	var resting: RegionalSimulation = _world(runner)
	runner.assert_true(resting.restore(JSON.parse_string(_state(active))), "a specific ongoing injury survives joint JSON")
	fixtures._position(resting, "home", "dorm")
	runner.assert_true(resting.regions.home.submit_action("player", "rest"), "the original dorm rest is used for recovery")
	active.advance_to_ms(active.elapsed_ms + 600000)
	resting.advance_to_ms(resting.elapsed_ms + 600000)
	var source: String = active.health.current_source("player")
	runner.assert_true(int(resting.health.wounds[source].remaining) < int(active.health.wounds[source].remaining), "actual resting improves recovery faster than continuing ordinary life")
	var world: RegionalSimulation = _injured(runner)
	_doctor(world)
	_care(runner, world, "diagnose")
	world.regions.home.inventory.containers["actor:player"]["herb"] = 1
	var answer: Dictionary = world.health.request("player", "su_zhi", "treat")
	runner.assert_true(answer.ok, "continuation fixture is in actual treatment")
	if not answer.ok:
		return
	world.advance_to_ms(world.elapsed_ms + 31000)
	var saved: String = _state(world)
	var fine: RegionalSimulation = _world(runner)
	runner.assert_true(fine.restore(JSON.parse_string(saved)), "both bodies, spent medicine and unfinished treatment validate together")
	var horizon: int = world.elapsed_ms + 5400000
	world.set_active_region("river")
	fine.set_active_region("home")
	runner.assert_true(world.advance_to_ms(horizon), "absent-region patient continues recovery on the original timeline")
	while fine.elapsed_ms < horizon:
		if not fine.advance_to_ms(mini(horizon, fine.elapsed_ms + 7937)):
			runner.assert_true(false, "fine recovery can reach the common horizon")
			break
	var a: Dictionary = JSON.parse_string(_state(world))
	var b: Dictionary = JSON.parse_string(_state(fine))
	a.active_region = ""
	b.active_region = ""
	runner.assert_eq(JSON.stringify(a), JSON.stringify(b), "coarse absent care and fine present care have the identical complete future")
	runner.assert_true(world.health.current_source("player").is_empty(), "time and actual completed treatment eventually allow normal channeling again")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "herb"), 0, "continuation never duplicates or refunds medicine")


func _npc_and_privacy(runner: Object) -> void:
	var world: RegionalSimulation = _injured(runner, "shi_tou")
	_doctor(world, "shi_tou")
	var body: Dictionary = world.regions.home.actors.shi_tou
	body.autonomous = true
	body.hunger = 80.0
	body.energy = 80.0
	body.retry_ms = world.elapsed_ms + int(world.regions.home.config.decision_interval) * 60000
	world.invalidate_region("home")
	world.set_active_region("river")
	runner.assert_true(world.advance_to_ms(int(body.retry_ms)), "offscreen NPC reaches their ordinary personal decision")
	runner.assert_true(world.health.owns_actor("shi_tou") and world.health.owns_actor("su_zhi"), "an injured ordinary NPC can ask a nearby experienced person through the same actual care API")
	if world.health.jobs.is_empty():
		return
	var job: Dictionary = world.health.jobs.values()[0]
	var process: Dictionary = {"domain": "health", "id": str(job.id), "performer": world.embodiment.subject_for_actor("su_zhi")}
	runner.assert_eq(world.health.observe("player", process).status, "unconfirmed", "being elsewhere does not disclose another patient's private diagnosis")
	world.advance_to_ms(int(job.due_ms))
	runner.assert_eq(world.health.observe("shi_tou", process).status, "completed", "the actual patient receives the completed diagnosis")
	runner.assert_true(not world.health.current_source("shi_tou").is_empty(), "NPC examination alone does not erase injury")


func _bad_candidates(runner: Object) -> void:
	var world: RegionalSimulation = _injured(runner)
	_doctor(world)
	_care(runner, world, "diagnose")
	world.regions.home.inventory.containers["actor:player"]["herb"] = 1
	var answer: Dictionary = world.health.request("player", "su_zhi", "treat")
	runner.assert_true(answer.ok, "bad-candidate fixture contains ongoing two-body treatment")
	if not answer.ok:
		return
	world.advance_to_ms(world.elapsed_ms + 1)
	var stable: String = _state(world)
	var source: String = world.health.current_source("player")
	var id: String = str(answer.id)
	for kind: String in ["missing", "deleted_injury", "source_actor", "early_treatment", "fake_remaining", "missing_material", "wrong_material", "orphan_material", "consent", "doctor", "parallel", "position", "diagnosis"]:
		var broken: Dictionary = JSON.parse_string(stable)
		match kind:
			"missing": broken.erase("health")
			"deleted_injury": broken.health.wounds.erase(source)
			"source_actor": broken.health.wounds[source].actor = "shi_tou"
			"early_treatment": broken.health.wounds[source].treated_ms = broken.elapsed_ms
			"fake_remaining": broken.health.wounds[source].remaining -= 1
			"missing_material": broken.regions.home.inventory.operations.erase(id + ":material")
			"wrong_material": broken.regions.home.inventory.operations[id + ":material"].item = "wood"
			"orphan_material": broken.regions.home.inventory.operations["health:action:999:material"] = broken.regions.home.inventory.operations[id + ":material"].duplicate(true)
			"consent": broken.health.jobs[id].consent = "request_999999"
			"doctor": broken.health.jobs[id].doctor = "shi_tou"
			"parallel": broken.regions.home.actors.su_zhi.autonomous = true
			"position": broken.health.jobs[id].patient_position[0] += 0.25
			"diagnosis": broken.health.jobs[id].diagnosis = "health:action:999"
		runner.assert_true(not world.restore(broken), "joint candidate rejects health corruption: " + kind)
		runner.assert_eq(_state(world), stable, "bad health candidate leaves every live domain unchanged: " + kind)
