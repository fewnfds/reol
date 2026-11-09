extends RefCounted
## Plant owner contract: habitats, processes, physical support, original stock,
## global triggers and candidate continuation. Main is covered separately.
const Fixtures = preload("res://tests/sim/test_regional_simulation.gd")
const ConstructionFixture = preload("res://tests/sim/test_construction.gd")
const RoomsFixture = preload("res://tests/sim/test_rooms_and_rest.gd")


func world_for(runner: Object) -> RegionalSimulation:
	var original := ReolContentDB.new()
	if not original.load_all():
		runner.assert_true(false, "plant fixture reads current complete content")
		return null
	var documents: Dictionary = original.content_bundle().documents
	var rules: Dictionary = documents["res://data/definitions/plants.json"]
	rules.sample_ms = 1000
	rules.action_ms = 100
	for rule: Dictionary in rules.types.values():
		rule.mature_ms = 1000
		rule.flower_ms = 2000
		rule.fruit_ms = 3000
		rule.lifespan_ms = 6000 if rule.life == "annual" else 31536000000
		rule.injury_ms = 1000
		rule.light_min = 0
		rule.temperature = [-1000, 1000, -2000, 2000]
		rule.seasons = ["春", "夏", "秋", "冬"]
		rule.product.period_ms = 1000
		if rule.substrates != ["water"]:
			rule.substrates = ["soil", "sand"]
		if rule.label != "骆驼刺":
			rule.water_min = 0
			rule.water_max = 100
	var dormant: Dictionary = rules.types.perennial_herb.duplicate(true)
	dormant.label = "冬生草"
	dormant.seasons = ["冬"]
	rules.types["winter_herb"] = dormant
	for sample: Dictionary in documents["res://data/scenarios/plants.json"].samples:
		if sample.has("growth_ms"):
			sample.growth_ms = mini(int(sample.growth_ms), int(rules.types[sample.definition].fruit_ms))
	var content := ReolContentDB.new()
	if not content.load_bundle(ReolContentBundle.from_documents(documents)):
		runner.assert_true(false, "accelerated plant fixture is a validated archived rule bundle")
		return null
	var fixtures := Fixtures.new()
	var regions: Dictionary = {}
	for region: String in ["home", "river"]:
		regions[region] = fixtures._make_village(content, region, false)
	var world := RegionalSimulation.new()
	if not world.initialize(JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/world_continuity.json")), regions, content):
		runner.assert_true(false, "plant fixture composes the existing world owners")
		return null
	var map: WorldMapData = WorldMapData.from_descriptor(WorldMapData.flat_descriptor(31573))
	map.configure_nature(content.natural_environment)
	var grass: Array = []
	for y: int in range(98, 118):
		for x: int in range(98, 164):
			grass.append([x, y, WorldMapData.TERRAIN_GRASS])
	map.apply_terrain_patch(grass)
	world.bind_map_data(map)
	_bind_navigation(world)
	world.regions.home.set_actor_cell("player", Vector2i(108, 104))
	world.regions.home.actors.player.autonomous = false
	world.invalidate_region("home")
	return world


func _bind_navigation(world: RegionalSimulation) -> void:
	var owner: WeakRef = weakref(world)
	for sim: VillageSimulation in world.regions.values():
		sim.set_navigation(func(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
			return RoomsFixture.new()._path(owner.get_ref().construction, from, to), func(from: Vector2i, step: Vector2i) -> bool:
			var current: RegionalSimulation = owner.get_ref()
			return current.map_data.terrain_can_step(from, step) and not current.construction.blocked(from + step) and not current.plants.blocked(from + step))


func run(runner: Object) -> void:
	_habitats_and_life(runner)
	_actions_and_stumps(runner)
	_support_and_transplant(runner)
	_event_identity_and_restore(runner)
	print("SCENARIO plants: real habitats/annual life, reservations/interruptions, stumps, supported original identity, global awakening and same saved future")


func _habitats_and_life(runner: Object) -> void:
	var world: RegionalSimulation = world_for(runner)
	if world == null:
		return
	runner.assert_true(world.plants.spawn("herb", "perennial_herb", "home", Vector2i(108, 110)), "ordinary terrestrial roots use actual substrate")
	world.map_data.apply_terrain_patch([[112, 110, WorldMapData.TERRAIN_WATER]])
	runner.assert_true(not world.plants.spawn("wrong", "perennial_herb", "home", Vector2i(112, 110)), "terrestrial roots do not inherit a universal water ban or permission")
	runner.assert_true(world.plants.spawn("lotus", "lotus", "home", Vector2i(112, 110)), "aquatic roots use local water even though terrain growth_factor is zero")
	runner.assert_true(not world.plants.spawn("thorn", "desert_thorn", "home", Vector2i(112, 110)), "a desert species cannot root in open water")
	runner.assert_true(world.plants.spawn("annual", "annual_grass", "home", Vector2i(114, 110)), "annual and perennial bodies share one framework")
	runner.assert_true(world.plants.spawn("winter", "winter_herb", "home", Vector2i(115, 110)), "a seasonal species uses the same data-driven owner")
	var subjects: int = world.embodiment._subjects.size()
	runner.assert_true(world.advance_to_ms(2000), "continuous life advances on the common clock")
	runner.assert_eq(world.plants.bodies.herb.stage, "flowering", "maturity and flowering have separate thresholds")
	runner.assert_true(world.plants.bodies.winter.dormant and world.plants.bodies.winter.hp > 0 and world.plants.bodies.winter.growth_ms == 0, "an unsuitable season pauses growth without killing a tolerant perennial")
	runner.assert_eq(world.embodiment._subjects.size(), subjects, "ordinary plants allocate no mind or identity carrier")
	runner.assert_true(world.advance_to_ms(4000), "growth continues into reproduction")
	runner.assert_eq(world.regions.home.inventory.quantity(world.plants.container_id("herb"), "herb"), 1, "new product is stock in the original regional inventory")
	var storage: Dictionary = SimStorageQuery.item(world, {"domain": "village", "region": "home", "container": world.plants.container_id("herb"), "item": "herb"})
	runner.assert_true(storage.ok and storage.quantity == 1 and storage.carrier == {"kind": "plant", "id": "herb"}, "plant stock resolves the original body's storage anchor")
	runner.assert_true(world.advance_to_ms(6000), "lifespan boundary continues while offscreen")
	runner.assert_eq(world.plants.bodies.annual.stage, "dead", "annual death follows lifetime, not year rollover")
	runner.assert_true(world.plants.bodies.herb.hp > 0, "a perennial does not share the annual terminal rule")
	runner.assert_true(world.describe_object({"kind": "plant", "id": "lotus"}).ok, "plants join the common authority object query")
	var query: Dictionary = world.query_space(Rect2i(112, 110, 1, 1), ["plant"])
	runner.assert_true(query.ok and query.references.has({"kind": "plant", "id": "lotus"}), "the live spatial index resolves the original aquatic body")
	var before: int = int(world.plants.bodies.herb.hp)
	runner.assert_true(world.plants.damage("herb", 3, "sample_damage"), "original plant bodies accept damage")
	runner.assert_true(world.plants.damage("herb", 3, "sample_damage"), "damage operation can be retried safely")
	runner.assert_eq(world.plants.bodies.herb.hp, before - 3, "the same damage cannot apply twice")
	runner.assert_true(world.plants.spawn("fire", "fire_herb", "home", Vector2i(118, 110)), "a new plant can enter an already active environment")
	var source: Dictionary = world.environment_fields._sources.get_source("plant:fire")
	runner.assert_true(source.channels[3] > 0 and source.channels[5] > 0, "fire affinity and thermal emission use separate shared profile channels")
	world.plants.damage("fire", 100000, "destroy_fire")
	runner.assert_true(world.environment_fields._sources.get_source("plant:fire").is_empty(), "death removes the actual source without erasing saved environmental response")


func _finish_plants(runner: Object, world: RegionalSimulation) -> void:
	for _step: int in 100:
		if world.plants.active.is_empty():
			return
		var due: int = world.plants.jobs.next_boundary_ms()
		if not world.advance_to_ms(maxi(world.elapsed_ms + 1, due)):
			runner.assert_true(false, "plant process reaches its actual next boundary: " + str(world.errors))
			return
	runner.assert_true(false, "plant process terminates within bounded route/work steps")


func _actions_and_stumps(runner: Object) -> void:
	var world: RegionalSimulation = world_for(runner)
	if world == null:
		return
	runner.assert_true(world.plants.spawn("crop", "perennial_herb", "home", Vector2i(108, 106), "", false, 3000, 3000), "an opening specimen has explicit preexisting maturity")
	world.advance_to_ms(1000)
	var stock: int = world.regions.home.inventory.quantity("actor:player", "herb")
	var started: Dictionary = world.plants.jobs.begin("player", "crop", "harvest", {}, "plant_action:harvest")
	runner.assert_true(started.ok, "harvest reserves an original product before approaching")
	runner.assert_true(not world.plants.jobs.begin("shi_tou", "crop", "harvest").ok, "competing actors cannot own the same plant process")
	runner.assert_true(world.plants.cancel("player"), "manual interruption uses the same action contract")
	runner.assert_true(not world.regions.home.inventory.reservations.has("plant_action:harvest"), "cancel releases the original stock reservation")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "herb"), stock, "cancel creates no product")
	started = world.plants.jobs.begin("player", "crop", "harvest", {}, "plant_action:second")
	runner.assert_true(started.ok, "a new harvest can start after cancellation")
	world.advance_to_ms(world.elapsed_ms + 1)
	var in_flight: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))
	var continued: RegionalSimulation = world_for(runner)
	runner.assert_true(continued.restore(in_flight), "an approaching harvest restores its original reservation and body")
	_bind_navigation(continued)
	_finish_plants(runner, world)
	_finish_plants(runner, continued)
	runner.assert_eq(_canonical(continued.to_dict()), _canonical(world.to_dict()), "in-flight harvest reaches the same complete future")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "herb"), stock + 1, "one completed harvest moves one actual product")
	runner.assert_true(world.plants.jobs.begin("player", "crop", "harvest", {}, "plant_action:second").ok, "a completed operation returns its receipt")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "herb"), stock + 1, "retry does not transfer another product")
	runner.assert_true(world.plants.spawn("tree", "old_tree", "home", Vector2i(110, 106), "", false, 3000, 3000), "a non-awakened tree is a physical plant body")
	runner.assert_true(world.plants.blocked(Vector2i(110, 106)), "standing wood has original movement occupancy")
	runner.assert_true(world.plants.jobs.begin("player", "tree", "cut").ok, "cutting owns the same exclusive process contract")
	_finish_plants(runner, world)
	runner.assert_eq(world.plants.bodies.tree.stage, "root", "cutting a regrowing species leaves a surviving stump")
	runner.assert_true(not world.plants.blocked(Vector2i(110, 106)), "a stump immediately removes the standing obstacle")
	runner.assert_true(world.plants.overrides_flora(Vector2i(110, 106)), "cutting cannot reveal the same decorative tree again")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "wood"), 8, "aboveground material is paid once to the original bag")


func _support_and_transplant(runner: Object) -> void:
	var world: RegionalSimulation = world_for(runner)
	if world == null:
		return
	var construction := ConstructionFixture.new()
	construction._site(runner, world)
	var placed: Dictionary = world.construction.place("player", "planter", Vector2i(109, 107))
	runner.assert_true(placed.ok, "a planter uses the normal furniture blueprint")
	if not placed.ok:
		return
	var id: String = str(placed.project)
	runner.assert_true(world.construction.begin("player", id).ok, "planter construction uses original public materials")
	construction._finish(runner, world)
	runner.assert_true(world.construction.has_capability(id, "cultivation"), "completed furniture grants cultivation support")
	runner.assert_true(world.plants.spawn("potted", "perennial_herb", "home", Vector2i(109, 107), id), "a plant can root in original furniture support")
	var born: int = int(world.plants.bodies.potted.born_ms)
	runner.assert_true(world.plants.bodies.potted.location.cell.is_empty(), "a supported plant owns no duplicate furniture position")
	runner.assert_true(world.plants.jobs.begin("player", "potted", "transplant", {"cell": [110, 107], "support": ""}).ok, "an adjacent reachable transplant retains the original body")
	_finish_plants(runner, world)
	runner.assert_eq(world.plants.bodies.potted.born_ms, born, "transplant preserves original age and identity")
	runner.assert_eq(world.plants.cell_of("potted"), Vector2i(110, 107), "original location changes exactly once")
	runner.assert_eq(world.construction.cultivation[id].plant, "", "transplant releases the original support relation")
	runner.assert_true(world.plants.spawn("removed_potted", "perennial_herb", "home", Vector2i(109, 107), id), "an empty support can accept another original body")
	runner.assert_true(world.plants.jobs.begin("player", "removed_potted", "uproot").ok, "uprooting can remove a plant directly from its support")
	_finish_plants(runner, world)
	runner.assert_true(world.construction.cultivation[id].plant.is_empty() and world.plants.bodies.removed_potted.location.support.is_empty(), "removal releases both sides of the physical support relation")
	var removal_world: RegionalSimulation = world_for(runner)
	runner.assert_true(removal_world.restore(JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))), "a removed potted body and empty support restore as one candidate")
	runner.assert_true(world.plants.jobs.begin("player", "potted", "transplant", {"cell": [109, 107], "support": id}).ok, "the same body can return to the planter")
	_finish_plants(runner, world)
	var hp: int = int(world.plants.bodies.potted.hp)
	runner.assert_true(world.construction.damage(id, 100000).ok, "furniture damage follows its existing physical contract")
	runner.assert_true(world.plants.bodies.potted.location.support.is_empty(), "a destroyed support detaches its original plant")
	runner.assert_true(world.plants.bodies.potted.hp < hp, "support loss leaves an explicit damaged body")
	var after_damage: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))
	var restored: RegionalSimulation = world_for(runner)
	runner.assert_true(restored.restore(after_damage), "a destroyed planter and its detached original plant restore together")


func _event_identity_and_restore(runner: Object) -> void:
	var world: RegionalSimulation = world_for(runner)
	if world == null:
		return
	runner.assert_true(world.plants.spawn("spirit_tree", "old_tree", "home", Vector2i(109, 106)), "awakening starts with an ordinary original plant")
	runner.assert_true(world.world_events.enqueue("test_awakening", "plant_awakening", 500, {"plant": "spirit_tree"}, {"topics": ["plant:spirit_tree"]}), "a plant uses the same global queue as route assessments")
	world.advance_to_ms(500)
	runner.assert_eq(world.world_events.receipt("test_awakening").status, "waiting", "an unmet event condition sleeps until a relevant change")
	world.advance_to_ms(1000)
	runner.assert_eq(world.world_events.receipt("test_awakening").status, "completed", "maturity wakes the exact pending trigger")
	runner.assert_eq(world.plants.bodies.spirit_tree.subject, "subject:plant:spirit_tree", "awakening attaches one subject to the same body")
	runner.assert_eq(world.plants.bodies.spirit_tree.contacts, {}, "awakening does not invent earlier observations or relationships")
	var identity: int = world.embodiment._subjects.size()
	var answer: Dictionary = SimInteractionRequests.submit(world, {"sender": "subject:player", "receiver": "subject:plant:spirit_tree", "verb": "ask_harvest", "object": {"kind": "plant", "id": "spirit_tree"}, "medium": "spoken", "conditions": {}})
	runner.assert_true(answer.ok, "a stationary awakened tree participates in the common interaction boundary")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))
	var restored: RegionalSimulation = world_for(runner)
	runner.assert_true(restored.restore(saved), "the registry independently restores events, plants, source responses and identities")
	if not restored.plants.bodies.has("spirit_tree"):
		return
	_bind_navigation(restored)
	world.advance_to_ms(5000)
	restored.advance_to_ms(5000)
	runner.assert_eq(_canonical(restored.to_dict()), _canonical(world.to_dict()), "restored and uninterrupted worlds reach the same future")
	runner.assert_eq(restored.embodiment._subjects.size(), identity, "continued events never awaken a second subject")
	var before: String = _canonical(restored.to_dict())
	var bad: Dictionary = restored.to_dict()
	bad.plants.bodies.spirit_tree.location.support = "missing_planter"
	bad.plants.bodies.spirit_tree.location.cell = []
	runner.assert_true(not restored.restore(bad), "a broken original support reference rejects the complete candidate")
	runner.assert_eq(_canonical(restored.to_dict()), before, "bad plant data cannot partially replace the live world")


func _canonical(value: Dictionary) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
