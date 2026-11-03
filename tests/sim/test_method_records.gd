extends RefCounted

const Fixtures = preload("res://tests/sim/test_heat_method_crafting.gd")


func run(runner: Object) -> void:
	_test_written_sources(runner)
	_test_interrupted_paid_work(runner)
	_test_cross_region_and_resume(runner)
	_test_autonomous_adoption_and_refusal(runner)
	_test_atomic_candidates(runner)
	print("SCENARIO written methods: actual wood, unique carriers, private reading distinct from embodied practice, voluntary physical transmission and joint continuation")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = Fixtures.new()._world(runner)
	runner.assert_true(world.configure_services(JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/settlement_services.json"))), "record fixture uses the existing shared social service for visitors")
	return world


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _write(runner: Object, world: RegionalSimulation) -> String:
	var draft: Dictionary = world.heat_methods.compose("chen_shouzhuo", "hearth_stone", "灶旁细火", 1, 1)
	runner.assert_true(draft.ok, "recorded recipe is an actual bounded original version")
	world.regions.home.inventory.containers["actor:chen_shouzhuo"].wood = 3
	var id: String = "method_record:%d" % world.method_records.next_id
	runner.assert_true(world.method_records.begin("chen_shouzhuo", "write", "", str(draft.method)).ok, "author starts real paid inscription")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:chen_shouzhuo", "wood"), 2, "one original unentrusted wood is committed at start")
	runner.assert_true(not world.method_records.objects.has(id), "started inscription is not yet a real readable carrier")
	world.advance_to_ms(world.elapsed_ms + 120000)
	runner.assert_true(world.method_records.objects.has(id), "full labor creates one unique record")
	return id


func _test_written_sources(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var id: String = _write(runner, world)
	var method: String = str(world.method_records.objects[id].method)
	runner.assert_true(world.heat_methods.visible_methods("player").is_empty(), "seeing another person's carrier reveals no executable directory")
	runner.assert_true(not world.method_records.begin("player", "read", id).ok, "another person's bag is not a public library")
	runner.assert_true(world.method_records.begin("chen_shouzhuo", "place", id, "", "home/kitchen").ok, "writer can put actual record on a nearby public work surface")
	world.advance_to_ms(world.elapsed_ms + 60000)
	runner.assert_true(world.method_records.begin("player", "take", id).ok, "novice picks up the unique public carrier")
	world.advance_to_ms(world.elapsed_ms + 60000)
	runner.assert_true(world.method_records.held("player", id) and not world.method_records.has_read("player", method), "possession does not grant reading")
	runner.assert_true(world.method_records.begin("player", "read", id).ok, "novice spends actual time reading")
	world.advance_to_ms(world.elapsed_ms + 12345)
	var mid: Dictionary = JSON.parse_string(_canonical(world))
	var restored: RegionalSimulation = _world(runner)
	runner.assert_true(restored.restore(mid), "ongoing reading restores one paid original world")
	var end: int = world.elapsed_ms + 70000
	world.advance_to_ms(end)
	restored.advance_to_ms(end)
	runner.assert_eq(_canonical(restored), _canonical(world), "read completion and every other domain have identical continuation")
	runner.assert_true(world.method_records.has_read("player", method) and not world.heat_methods.knows("player", method) and not world.artifacts.describe("player", "hearth_stone").method, "textual knowledge gives neither original foundation nor mastery")
	runner.assert_true(world.heat_methods.visible_methods("player").size() == 1 and not world.method_records.has_read("su_zhi", method), "only the actual reader sees that version")
	var before: String = _canonical(world)
	world.method_records.visible("player")
	world.method_records.status("player")
	world.heat_methods.visible_methods("player")
	runner.assert_eq(_canonical(world), before, "browsing known records neither leaks nor changes state")
	runner.assert_true(not world.heat_methods.start("player", "hearth_stone", method, "record").ok, "read instructions cannot bypass missing embodied foundation")
	runner.assert_true(world.artifacts.begin("player", "study", "hearth_stone").ok, "reader still studies the original real interface")
	world.advance_to_ms(world.elapsed_ms + 240000)
	runner.assert_true(world.heat_methods.start("player", "hearth_stone", method, "record").ok, "reader with actual foundation can attempt the steps")
	world.advance_to_ms(world.elapsed_ms + 15000)
	runner.assert_true(restored.restore(JSON.parse_string(_canonical(world))), "reading source validates a new unfinished original artifact trial")
	var ungrounded: Dictionary = JSON.parse_string(_canonical(world))
	ungrounded.artifacts.events = ungrounded.artifacts.events.filter(func(event: Dictionary) -> bool: return not (event.actor == "player" and event.kind == "studied"))
	before = _canonical(world)
	runner.assert_true(not world.restore(ungrounded) and _canonical(world) == before, "record-backed practice candidate still requires a real prior interface foundation")
	world.advance_to_ms(world.elapsed_ms + 45000)
	restored.advance_to_ms(restored.elapsed_ms + 45000)
	runner.assert_eq(_canonical(restored), _canonical(world), "record-backed practice pays once and resumes identically")
	runner.assert_true(world.heat_methods.knows("player", method), "only real successful output grants practiced version")
	var revision: Dictionary = world.heat_methods.compose("chen_shouzhuo", "hearth_stone", "未传的长火", 2, 2, method)
	runner.assert_true(revision.ok and world.method_records.objects[id].method == method and world.heat_methods.visible_methods("player").size() == 1, "new revision does not rewrite an old carrier or silently teach reader")
	world.regions.home.inventory.containers["actor:player"].wood = 1
	runner.assert_true(world.method_records.begin("player", "write", "", method).ok, "reader may make a paid exact copy rather than a new global recipe")
	world.advance_to_ms(world.elapsed_ms + 120000)
	var copy_id: String = str(world.method_records.events.back().object)
	runner.assert_eq(world.method_records.objects[copy_id].source, id, "copied physical record retains its actual reading source")
	runner.assert_true(restored.restore(JSON.parse_string(_canonical(world))), "copy provenance and old/new immutable methods validate together")


func _test_interrupted_paid_work(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var method: String = str(world.heat_methods.compose("chen_shouzhuo", "hearth_stone", "未刻完", 1, 1).method)
	var before: String = _canonical(world)
	runner.assert_true(not world.method_records.begin("chen_shouzhuo", "write", "", method).ok and _canonical(world) == before, "missing private material starts no fake work")
	world.regions.home.inventory.containers["actor:chen_shouzhuo"].wood = 1
	runner.assert_true(world.method_records.begin("chen_shouzhuo", "write", "", method).ok, "one original wood can be committed")
	runner.assert_true(not world.artifacts.begin("chen_shouzhuo", "study", "hearth_stone").ok and not world.regions.home.submit_action("chen_shouzhuo", "deliver_water"), "inscription cannot double-own body with old experiment or native work")
	runner.assert_true(world.method_records.cancel("chen_shouzhuo"), "even immediate cancellation has one recorded outcome")
	runner.assert_true(world.method_records.objects.is_empty() and world.regions.home.inventory.quantity("actor:chen_shouzhuo", "wood") == 0, "cancelled inscription refunds neither material nor a finished item")
	var restored: RegionalSimulation = _world(runner)
	runner.assert_true(restored.restore(JSON.parse_string(_canonical(world))), "same-time paid start/cancel validates and persists")
	var actor: Dictionary = world.regions.home.actors.chen_shouzhuo
	actor.autonomous = true
	actor.retry_ms = world.elapsed_ms + 300000
	world.regions.home.set_actor_cell("chen_shouzhuo", SimRouteTravel.cell(world.regions.home.places.store.cell))
	runner.assert_true(world.regions.home.submit_action("chen_shouzhuo", "deliver_wood"), "native public delivery draws an entrusted batch")
	world.invalidate_region("home")
	world.advance_to_ms(world.elapsed_ms + 100)
	world.regions.home.cancel_action("chen_shouzhuo", "fixture")
	runner.assert_true(world.regions.home.inventory.entrusted("actor:chen_shouzhuo", "wood") > 0 and not world.method_records.begin("chen_shouzhuo", "write", "", method).ok, "entrusted public wood cannot be silently converted into private scripture")


func _test_cross_region_and_resume(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var id: String = _write(runner, world)
	var method: String = str(world.method_records.objects[id].method)
	var receiver: String = "river_su_zhi"
	var remote: VillageSimulation = world.regions.river
	var destination: Vector2i = SimRouteTravel.cell(remote.actors[receiver].cell)
	runner.assert_true(not world.method_records.begin("chen_shouzhuo", "give", id, "", receiver).ok, "distant person cannot receive a remote transfer")
	world.regions.home.set_actor_cell("chen_shouzhuo", destination)
	remote.actors[receiver].autonomous = true
	remote.actors[receiver].retry_ms = world.elapsed_ms + 120000
	world.invalidate_region("river")
	runner.assert_true(world.method_records.begin("chen_shouzhuo", "give", id, "", receiver).ok, "same original person at the other settlement may propose a voluntary physical gift")
	world.advance_to_ms(world.elapsed_ms + 15000)
	var restored: RegionalSimulation = _world(runner)
	runner.assert_true(restored.restore(JSON.parse_string(_canonical(world))), "cross-region consent and unfinished custody change restore")
	runner.assert_true(not world.method_records.has_read(receiver, method), "accepted gift still teaches no method")
	var end: int = world.elapsed_ms + 300000
	world.set_active_region("home")
	restored.set_active_region("river")
	world.advance_to_ms(end)
	var cursor: int = restored.elapsed_ms
	while cursor < end:
		cursor = mini(end, cursor + 4217)
		restored.advance_to_ms(cursor)
	restored.set_active_region("home")
	runner.assert_eq(_canonical(restored), _canonical(world), "far/near and coarse/fine delivery/read yield the same entire world")
	runner.assert_true(world.method_records.held(receiver, id), "the exact same carrier arrives in recipient's original bag")
	runner.assert_true(world.method_records.has_read(receiver, method) and not world.heat_methods.knows(receiver, method), "recipient autonomously reads in spare time, without automatic mastery")
	runner.assert_true(not world.method_records.has_read("river_a_he", method) and world.heat_methods.visible_methods("river_a_he").is_empty(), "same settlement is not a global knowledge share")
	remote.actors[receiver].autonomous = false
	remote.set_actor_cell(receiver, SimRouteTravel.cell(remote.places.kitchen.cell))
	world.invalidate_region("river")
	runner.assert_true(world.method_records.begin(receiver, "place", id, "", "river/kitchen").ok, "recipient may place same carrier on the other settlement's actual surface")
	world.advance_to_ms(world.elapsed_ms + 60000)
	runner.assert_eq(world.method_records.objects[id].region, "river", "placement keeps remote facility location rather than using the donor's old region")
	runner.assert_true(restored.restore(JSON.parse_string(_canonical(world))), "cross-region gift and later local placement preserve one custody chain")
	world.regions.home.set_actor_cell("chen_shouzhuo", SimRouteTravel.cell(world.regions.home.places.kitchen.cell))
	runner.assert_true(world.method_records.visible("chen_shouzhuo").is_empty(), "past donor cannot inspect distant current carrier state")


func _test_atomic_candidates(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var id: String = _write(runner, world)
	var saved: Dictionary = JSON.parse_string(_canonical(world))
	for fault: String in ["missing", "teleport", "version", "free", "erase_history", "future", "source", "double"]:
		var bad: Dictionary = saved.duplicate(true)
		match fault:
			"missing": bad.erase("method_records")
			"teleport": bad.method_records.objects[id].container = "actor:player"
			"version": bad.method_records.objects[id].method = "heat_method:9999"
			"free": bad.regions.home.inventory.operations.erase("method_record:action:1:material")
			"erase_history": bad.method_records = SimMethodRecords.empty_state()
			"future": bad.method_records.events[0].finished_ms += 1
			"source": bad.method_records.events[0].source = id
			"double": bad.method_records.events.append(bad.method_records.events[0].duplicate(true))
		var before: String = _canonical(world)
		runner.assert_true(not world.restore(bad), "bad physical/knowledge candidate rejected: " + fault)
		runner.assert_eq(_canonical(world), before, "bad candidate preserves original world: " + fault)


func _test_autonomous_adoption_and_refusal(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var id: String = _write(runner, world)
	var method: String = str(world.method_records.objects[id].method)
	var sim: VillageSimulation = world.regions.home
	sim.set_actor_cell("shi_tou", world.artifacts.object_cell("hearth_stone"))
	sim.actors.shi_tou.autonomous = true
	sim.actors.shi_tou.energy = 0.0
	var answer: Dictionary = world.method_records.begin("chen_shouzhuo", "give", id, "", "shi_tou")
	runner.assert_true(not answer.ok and world.method_records.held("chen_shouzhuo", id), "exhausted person may refuse a gift; carrier remains with the donor")
	var before: String = _canonical(world)
	world.method_records.begin("chen_shouzhuo", "give", id, "", "shi_tou")
	runner.assert_eq(_canonical(world), before, "same refusal reuses original social decision without rerolling")
	sim.actors.shi_tou.autonomous = false
	sim.set_actor_cell("a_he", world.artifacts.object_cell("hearth_stone"))
	sim.actors.a_he.autonomous = true
	sim.actors.a_he.retry_ms = world.elapsed_ms + 120000
	sim.inventory.containers.kitchen.wood = 0
	sim.inventory.containers.kitchen.meal = 0
	sim.observe_current_surroundings("a_he")
	world.artifacts.objects.hearth_stone.charge = 0
	world.invalidate_region("home")
	runner.assert_true(world.method_records.begin("chen_shouzhuo", "give", id, "", "a_he").ok, "available cook may voluntarily take the same actual written plan")
	world.advance_to_ms(world.elapsed_ms + 15000)
	var copy: RegionalSimulation = _world(runner)
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "self-directed reading and practical life begin from a valid common snapshot")
	var end: int = world.elapsed_ms + 1800000
	world.advance_to_ms(end)
	copy.set_active_region("river")
	var cursor: int = copy.elapsed_ms
	while cursor < end:
		cursor = mini(end, cursor + 3989)
		copy.advance_to_ms(cursor)
	copy.set_active_region(world.active_region)
	runner.assert_eq(_canonical(copy), _canonical(world), "reading and actual useful adoption are independent of player presence and step size")
	var attempted: bool = false
	for event: Dictionary in world.artifacts.events:
		if event.actor == "a_he" and event.get("method", {}).get("id") == method and event.method.mode == "record":
			attempted = true
	runner.assert_true(world.method_records.has_read("a_he", method) and attempted and world.heat_methods.knows("a_he", method), "cook reads, gains real interface experience and actually practices the received useful steps")
	world = _world(runner)
	id = _write(runner, world)
	sim = world.regions.home
	sim.actors.su_zhi.autonomous = true
	sim.actors.su_zhi.retry_ms = world.elapsed_ms + 120000
	runner.assert_true(world.method_records.begin("chen_shouzhuo", "give", id, "", "su_zhi").ok, "interrupted gift fixture obtains actual consent first")
	sim.set_actor_cell("su_zhi", Vector2i(120, 120))
	world.invalidate_region("home")
	world.advance_to_ms(world.elapsed_ms + 1)
	runner.assert_true(world.method_records.held("chen_shouzhuo", id) and world.method_records.events.back().outcome == "failed", "recipient leaving interrupts handover without teleporting or deleting the object")
	runner.assert_true(copy.restore(JSON.parse_string(_canonical(world))), "failed consent-backed gift keeps a valid one-object world")
	world.regions.home.inventory.containers["actor:chen_shouzhuo"].wood = 1
	runner.assert_true(world.method_records.begin("chen_shouzhuo", "write", "", str(world.method_records.objects[id].method)).ok, "control interruption fixture commits one more real material")
	world.embodiment.release_control("subject:chen_shouzhuo", "body:chen_shouzhuo", "motion")
	world.advance_to_ms(world.elapsed_ms + 1)
	runner.assert_true(not world.method_records.owns_actor("chen_shouzhuo") and world.regions.home.inventory.quantity("actor:chen_shouzhuo", "wood") == 0 and world.method_records.objects.size() == 1, "losing control releases paid labor without refunding or creating a second document")
