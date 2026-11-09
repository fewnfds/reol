extends RefCounted
## One owner-level fixture protects actual stock, cross-ledger handling,
## interrupted public custody and candidate continuation. No Main assembly.
const Fixture = preload("res://tests/sim/test_settlement_services.gd")
var _fixture: RefCounted = Fixture.new()


func run(runner: Object) -> void:
	_private_delivery_and_restore(runner)
	_public_interruption_and_resume(runner)
	_reservations_and_refusal(runner)
	_storage_capacity_and_damage(runner)
	print("SCENARIO stock hauling: original bags/ledgers, timed contact, custody, interruption, resumed handoff and candidate atomicity")


func _advance(world: RegionalSimulation, actor: String, runner: Object, stop_at_delivery: bool = false) -> void:
	for _index: int in 256:
		if not world.services.owns_actor(actor):
			return
		var job: Dictionary = world.services.jobs[world.services.active_jobs[actor]]
		if stop_at_delivery and job.stage == "delivery":
			return
		var next: int = maxi(world.elapsed_ms + 1, world.services.next_boundary_ms())
		if not world.advance_to_ms(next, 4096, 2147483647):
			runner.assert_true(false, "hauling advances through the original world kernel")
			return
	runner.assert_true(false, "hauling completes within a bounded fixture")


func _private_delivery_and_restore(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._make_world(runner)
	if world == null:
		return
	var inventory: SimInventory = world.regions.home.inventory
	inventory.containers["actor:player"]["wood"] = 7
	var source: Dictionary = {"region": "home", "container": "actor:player"}
	var target: Dictionary = {"region": "river", "container": "store"}
	var before: int = world.regions.river.inventory.quantity("store", "wood")
	var reply: Dictionary = world.services.begin_haul("player", source, target, "wood", 3)
	runner.assert_true(reply.ok, "an original pocket can deliver supported stock across regional ledgers")
	if not reply.ok:
		return
	runner.assert_eq(inventory.quantity("actor:player", "wood"), 7, "accepting an intent moves no stock")
	runner.assert_eq(inventory.available("actor:player", "wood"), 4, "the original ledger protects the requested cargo")
	_advance(world, "player", runner, true)
	var checkpoint: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))
	runner.assert_true(not checkpoint.is_empty(), "in-transit cargo saves with the shared registry")
	var resumed: RegionalSimulation = _fixture._make_world(runner)
	runner.assert_true(resumed.restore(checkpoint), "a candidate restores the original route, bag and stock reservation")
	_advance(world, "player", runner)
	_advance(resumed, "player", runner)
	if world.services.jobs[reply.id].status != "completed":
		print("HAUL FAILURE ", world.services.jobs[reply.id])
	runner.assert_eq(world.services.jobs[reply.id].status, "completed", "delivery finishes only at the real destination")
	runner.assert_eq(world.regions.river.inventory.quantity("store", "wood"), before + 3, "the target ledger receives one actual consignment")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "wood"), 4, "the original bag loses exactly the delivered amount")
	var actual: Dictionary = RegionalSimulation._normalized(resumed.to_dict())
	var expected: Dictionary = RegionalSimulation._normalized(world.to_dict())
	if actual != expected:
		print("HAUL FUTURE DIFFERENCE ", _difference(actual, expected))
	runner.assert_eq(SnapshotValues.canonical_json(actual).sha256_text(), SnapshotValues.canonical_json(expected).sha256_text(), "stopping during transport continues the same whole future")
	var terminal: Dictionary = world.services.jobs[reply.id].duplicate(true)
	world.services._hauling.settle(terminal, world.elapsed_ms)
	runner.assert_eq(world.regions.river.inventory.quantity("store", "wood"), before + 3, "a repeated terminal settlement cannot duplicate the delivery")
	var live: String = JSON.stringify(resumed.to_dict(), "", true, true)
	var remote: Dictionary = checkpoint.duplicate(true)
	var job: Dictionary = remote.services.jobs[reply.id]
	var body: Dictionary = remote.regions.home.actors.player
	job.phase = "work"
	job.path = []
	job.stand = body.cell.duplicate()
	job.segment_from = body.position.duplicate()
	job.segment_started_ms = remote.elapsed_ms
	job.due_ms = int(remote.elapsed_ms) + int(world._content.local_actions.hauling.handling_ms)
	runner.assert_true(not resumed.restore(remote), "a forged work position cannot turn a remote container into contact")
	runner.assert_eq(JSON.stringify(resumed.to_dict(), "", true, true).sha256_text(), live.sha256_text(), "forged contact cannot replace the live candidate")
	checkpoint.services.jobs[reply.id].options.amount = 4
	runner.assert_true(not resumed.restore(checkpoint), "a changed cargo amount cannot borrow the old reservation")
	runner.assert_eq(JSON.stringify(resumed.to_dict(), "", true, true), live, "bad cargo candidates leave the live world intact")


func _public_interruption_and_resume(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._make_world(runner)
	if world == null:
		return
	var source: Dictionary = {"region": "home", "container": "store"}
	var target: Dictionary = {"region": "river", "container": "store"}
	var inventory: SimInventory = world.regions.home.inventory
	var before: int = inventory.quantity("store", "wood")
	var reply: Dictionary = world.services.begin_haul("player", source, target, "wood", 2)
	runner.assert_true(reply.ok, "authorized home supplies use the same handling lifecycle")
	if not reply.ok:
		return
	_advance(world, "player", runner, true)
	runner.assert_eq(inventory.quantity("store", "wood"), before - 2, "pickup changes the original public ledger once")
	runner.assert_eq(inventory.entrusted("actor:player", "wood"), 2, "public cargo retains a real custody basis")
	world.interrupt_occupation("player", "struck_by_conflict")
	runner.assert_true(not world.services.owns_actor("player"), "hostile interruption releases the body's work")
	runner.assert_true(not inventory.consume("test:steal", "actor:player", "wood", 2), "cancelled public cargo cannot become disposable private stock")
	var checkpoint: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))
	runner.assert_true(world.restore(checkpoint), "cancelled public custody remains a valid persistent fact")
	var resume: Dictionary = world.services.begin_haul("player", source, target, "wood", 2)
	runner.assert_true(resume.ok, "the same intended delivery resumes its actual held consignment")
	if not resume.ok:
		return
	runner.assert_eq(world.services.jobs[resume.id].stage, "delivery", "resumption does not withdraw another batch")
	_advance(world, "player", runner)
	runner.assert_eq(world.regions.home.inventory.quantity("store", "wood"), before - 2, "resuming does not pay pickup a second time")
	runner.assert_eq(world.regions.home.inventory.entrusted("actor:player", "wood"), 0, "actual delivery settles the original public custody")
	runner.assert_true(world.restore(JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))), "the completed original pickup/resumed delivery chain validates together")


func _reservations_and_refusal(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._make_world(runner)
	if world == null:
		return
	var source: Dictionary = {"region": "home", "container": "store"}
	var target: Dictionary = {"region": "home", "container": "kitchen"}
	world.regions.home.inventory.containers.store.wood = 2
	var first: Dictionary = world.services.begin_haul("player", source, target, "wood", 2)
	runner.assert_true(first.ok, "one worker reserves actual source stock")
	var second: Dictionary = world.services.begin_haul("shi_tou", source, target, "wood", 2)
	runner.assert_true(not second.ok, "a second worker cannot reserve the same two units")
	world.services.cancel("player")
	runner.assert_eq(world.regions.home.inventory.available("store", "wood"), 2, "cancelling before pickup releases the original stock")
	var unchanged: Dictionary = world.regions.home.inventory.to_dict()
	runner.assert_true(not world.services.begin_haul("player", {"region": "river", "container": "records"}, target, "coin", 1).ok, "a locatable foreign cash box grants no withdrawal right")
	runner.assert_true(not world.services.begin_haul("player", source, target, "wood", 25).ok, "the declared per-load capacity is enforced before reservation")
	runner.assert_eq(world.regions.home.inventory.to_dict(), unchanged, "refused loads do not change any original material state")
	var remote: Dictionary = {"region": "river", "container": "store"}
	var destination: Dictionary = {"region": "home", "container": "store"}
	var foreign: Dictionary = world.services.begin_haul("player", remote, destination, "grain", 2)
	runner.assert_true(foreign.ok, "the existing public freight policy permits a foreign supply pickup")
	if foreign.ok:
		var saved: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))
		runner.assert_true(world.restore(saved), "a foreign ledger retains a validated reservation by the one original visiting actor")
		for field: String in ["label", "stage", "stand", "anchor", "reservation"]:
			var malformed: Dictionary = saved.duplicate(true)
			malformed.services.jobs[foreign.id].erase(field)
			runner.assert_true(not world.restore(malformed), "missing hauling field is a clean candidate rejection: " + field)
		var bad: Dictionary = saved.duplicate(true)
		bad.regions.river.inventory.reservations[str(foreign.id) + ":stock"].owner_id = "nobody"
		runner.assert_true(not world.restore(bad), "foreign reservation scope cannot invent a body owner")


func _storage_capacity_and_damage(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._make_world(runner)
	if world == null: return
	var building = load("res://tests/sim/test_building_framework.gd").new()
	world.bind_map_data(load("res://tests/sim/test_structure_query.gd").FlatMap.new())
	world.regions.home.set_navigation(building._path.bind(weakref(world)))
	world.services.set_navigation(building._path.bind(weakref(world)))
	world.regions.home.set_actor_cell("player", Vector2i(108, 104))
	building.fixture._site(runner, world)
	var chest: String = building._build(runner, world, "wood_chest", Vector2i(112, 109))
	if chest.is_empty(): return
	var inventory: SimInventory = world.regions.home.inventory
	inventory.containers[chest + ":contents"]["wood"] = 20
	inventory.containers["actor:player"]["wood"] = 4
	inventory.containers["actor:shi_tou"]["wood"] = 1
	var source: Dictionary = {"region": "home", "container": "actor:player"}
	var target: Dictionary = {"region": "home", "container": chest + ":contents"}
	var laundering: Dictionary = world.services.begin_haul("player", {"region": "home", "container": "store"}, target, "wood", 2)
	runner.assert_true(not laundering.ok, "public cargo cannot be delivered into storage that has no continuing disposition owner")
	if laundering.ok: world.services.cancel("player")
	var reply: Dictionary = world.services.begin_haul("player", source, target, "wood", 4)
	runner.assert_true(reply.ok, "hauling reserves the remaining real storage capacity: " + str(reply.line))
	if not reply.ok: return
	runner.assert_true(not world.facility_use.begin("shi_tou", chest, "front", "deposit", "wood", 1).ok, "the original furniture owner respects a hauling destination claim")
	_advance(world, "player", runner)
	runner.assert_eq(inventory.quantity(chest + ":contents", "wood"), 24, "one original ledger receives the actual full consignment")
	reply = world.services.begin_haul("player", target, source, "wood", 4)
	runner.assert_true(reply.ok, "the same storage interface supports authorized withdrawal")
	if not reply.ok: return
	_advance(world, "player", runner, true)
	runner.assert_eq(inventory.quantity("actor:player", "wood"), 4, "withdrawal physically enters the original pocket")
	world.construction.damage(chest, 100000)
	runner.assert_true(not world.services.owns_actor("player") and inventory.quantity("actor:player", "wood") == 4 and inventory.reservations.is_empty(), "facility loss releases the related job without swallowing carried material")


func _difference(actual: Variant, expected: Variant, path: String = "") -> String:
	if actual is Dictionary and expected is Dictionary:
		for key: Variant in expected:
			if not actual.has(key):
				return path + "." + str(key) + " missing"
			var found: String = _difference(actual[key], expected[key], path + "." + str(key))
			if not found.is_empty():
				return found
		return "" if actual.size() == expected.size() else path + " extra keys"
	if actual is Array and expected is Array:
		if actual.size() != expected.size():
			return path + " different lengths"
		for index: int in actual.size():
			var found: String = _difference(actual[index], expected[index], path + "[%d]" % index)
			if not found.is_empty():
				return found
		return ""
	return "" if actual == expected else "%s: %s != %s" % [path, str(actual).left(120), str(expected).left(120)]
