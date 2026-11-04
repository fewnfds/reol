extends RefCounted
## Original construction and avian owners supply storage anchors, not a second ledger.

const Fixtures = preload("res://tests/sim/test_regional_simulation.gd")
const QUERY = preload("res://scripts/sim/storage_query.gd")
const CENTERS: Dictionary = {"home": Vector2i(100, 100), "river": Vector2i(150, 100)}
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_test_construction_material(runner)
	_test_avian_storage(runner)
	print("SCENARIO storage anchors: original construction cargo and avian containers follow their real owners")


func _world(runner: Object, birds: bool = false) -> RegionalSimulation:
	var world: RegionalSimulation = _fixtures._make_world(runner)
	if world == null:
		return null
	if birds:
		var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/avian_life.json"))
		if not world.avian_life.spawn_opening(scenario, CENTERS):
			runner.assert_true(false, "real avian bodies and sites spawn together")
			return null
	return world


func _test_construction_material(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var sim: VillageSimulation = world.regions.home
	var construction: SimConstruction = world.construction
	sim.set_actor_cell("player", Vector2i(108, 104))
	sim.set_actor_cell("shi_tou", Vector2i(107, 104))
	world.invalidate_region("home")
	var registered: Dictionary = construction.register_site("player", Vector2i(108, 106))
	runner.assert_true(bool(registered.get("ok", false)), "real public worksite is registered")
	if not bool(registered.get("ok", false)):
		return
	var placed: Dictionary = construction.place("player", "wood_wall", Vector2i(109, 107))
	runner.assert_true(bool(placed.get("ok", false)), "real blueprint creates its own inventory container")
	if not bool(placed.get("ok", false)):
		return
	var id: String = str(placed.project)
	var ref: Dictionary = {"domain": "village", "region": "home", "container": id, "item": "wood"}
	var empty: Dictionary = QUERY.item(world, ref)
	runner.assert_true(bool(empty.get("ok", false)), "empty project container retains its recorded anchor")
	if bool(empty.get("ok", false)):
		runner.assert_eq(empty.quantity, 0, "an empty anchor does not create materials")
		runner.assert_true(not empty.entry_present, "an absent item entry is distinct from a physical stack")
		runner.assert_eq(empty.cell, SimRouteTravel.cell(construction.projects[id].material_cell), "empty anchor uses the project's recorded material cell")
	var original_stock: int = sim.inventory.quantity("store", "wood")
	var original_bag: int = sim.inventory.quantity("actor:player", "wood")
	var begun: Dictionary = construction.begin("player", id)
	runner.assert_true(bool(begun.get("ok", false)), "actual construction claims its worker and stock")
	if not bool(begun.get("ok", false)):
		return
	for _index: int in 40:
		if not construction.active.has("player") or construction.projects[id].carrier == "player":
			break
		if not world.advance_to_ms(maxi(world.elapsed_ms + 1, construction.next_boundary_ms())):
			runner.assert_true(false, "construction advances to its real pickup boundary")
			return
	runner.assert_eq(construction.projects[id].carrier, "player", "worker picks up the actual batch")
	if construction.projects[id].carrier != "player":
		return
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 77), "carried material advances with the original body")
	var before_inventory: Dictionary = sim.inventory.to_dict()
	var before_construction: Dictionary = construction.to_dict()
	var held: Dictionary = QUERY.item(world, ref)
	runner.assert_true(bool(held.get("ok", false)), "carried project batch has a location")
	if bool(held.get("ok", false)):
		runner.assert_eq(held.quantity, 3, "material quantity is still in the project container")
		runner.assert_eq(held.available, 3, "unreserved project stock remains available")
		runner.assert_eq(held.entrusted, 0, "carrying creates no duplicate custody")
		runner.assert_true(held.entry_present, "picked-up wood is an actual ledger entry")
		runner.assert_eq(held.carrier, {"kind": "actor", "id": "player"}, "project references the real carrier")
		runner.assert_eq(held.position, SimRouteTravel.point(sim.actors.player), "carried position follows the continuous body")
		runner.assert_eq(held.location_owner, "village_simulation", "body supplies the carried location")
		runner.assert_eq(held.location_time_ms, sim.elapsed_ms, "body reports its source clock")
		runner.assert_true(not held.stale and not held.world_has_backlog, "settled carried material reports a current source and world")
	runner.assert_eq(sim.inventory.quantity("store", "wood"), original_stock - 3, "pickup debits the source exactly once")
	runner.assert_eq(sim.inventory.quantity("actor:player", "wood"), original_bag, "the player's separate bag does not receive a duplicate batch")
	runner.assert_eq(sim.inventory.to_dict(), before_inventory, "storage query does not mutate the inventory")
	runner.assert_eq(construction.to_dict(), before_construction, "storage query does not mutate the construction process")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true))
	var restored: RegionalSimulation = _world(runner)
	if restored != null:
		var loaded: bool = restored.restore(saved)
		runner.assert_true(loaded, "independent restore accepts the in-flight batch")
		if loaded:
			var restored_held: Dictionary = QUERY.item(restored, ref)
			runner.assert_true(bool(restored_held.get("ok", false)), "restored original carrier remains resolvable")
			if bool(restored_held.get("ok", false)) and bool(held.get("ok", false)):
				runner.assert_eq(restored_held.position, held.position, "restored batch keeps the original body position")
				runner.assert_eq(restored_held.quantity, held.quantity, "restored batch is not duplicated")
	runner.assert_true(construction.cancel("player"), "actual interruption drops the batch")
	var dropped: Dictionary = QUERY.item(world, ref)
	runner.assert_true(bool(dropped.get("ok", false)), "dropped project batch stays locatable")
	if bool(dropped.get("ok", false)):
		var material_cell: Vector2i = SimRouteTravel.cell(construction.projects[id].material_cell)
		runner.assert_eq(dropped.cell, material_cell, "dropped batch follows the recorded material cell")
		runner.assert_eq(dropped.position, TileGrid.cell_to_world(material_cell), "ground anchor uses the cell center")
		runner.assert_eq(dropped.carrier, {}, "interruption removes the body carrier")
		runner.assert_eq(dropped.quantity, 3, "interruption neither returns nor loses wood")
		runner.assert_eq(dropped.location_owner, "construction", "ground location belongs to the project")


func _test_avian_storage(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, true)
	if world == null:
		return
	var domain: SimAvianLife = world.avian_life
	var bird_ref: Dictionary = {"domain": "avian", "region": "home", "container": "bird:moss_sparrow", "item": "herb"}
	var site_ref: Dictionary = {"domain": "avian", "region": "home", "container": "home:seeds", "item": "seed"}
	var site: Dictionary = QUERY.item(world, site_ref)
	runner.assert_true(bool(site.get("ok", false)), "real habitat inventory has a site anchor")
	if bool(site.get("ok", false)):
		runner.assert_eq(site.cell, SimRouteTravel.cell(domain.sites["home:seeds"].cell), "site resolves its original cell")
		runner.assert_eq(site.quantity, domain.inventory.quantity("home:seeds", "seed"), "site quantity comes from the avian ledger")
		runner.assert_true(site.entry_present and site.quantity > 0, "finite seed stock exists in the original site")
	var at: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(domain.sites["home:seeds"].cell))
	SimRouteTravel.put(world.regions.home.actors.player, at)
	domain.birds.moss_sparrow.position = [at.x, at.y]
	domain.birds.moss_sparrow.altitude = 0
	domain.birds.moss_sparrow.fullness = 75 * SimAvianLife.SCALE
	domain.birds.moss_sparrow.energy = 80 * SimAvianLife.SCALE
	world.regions.home.inventory.containers["actor:player"]["grain"] = 1
	world.invalidate_region("home")
	var offered: Dictionary = domain.offer_grain("player", "moss_sparrow")
	var requested: Dictionary = domain.ask_herb("player", "moss_sparrow") if bool(offered.get("ok", false)) else {}
	runner.assert_true(bool(requested.get("ok", false)), "a real bird accepts and performs the herb request")
	if not bool(requested.get("ok", false)):
		return
	for _index: int in 40:
		if domain.inventory.quantity("bird:moss_sparrow", "herb") > 0:
			break
		if not world.advance_to_ms(domain.next_boundary_ms()):
			runner.assert_true(false, "bird advances to its real pickup boundary")
			return
	runner.assert_eq(domain.inventory.quantity("bird:moss_sparrow", "herb"), 1, "bird picks up one original herb")
	if domain.inventory.quantity("bird:moss_sparrow", "herb") != 1:
		return
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 100), "bird begins its actual delivery flight")
	var before: Dictionary = domain.to_dict()
	var held: Dictionary = QUERY.item(world, bird_ref)
	runner.assert_true(bool(held.get("ok", false)), "bird's real carried herb is locatable")
	if bool(held.get("ok", false)):
		runner.assert_eq(held.quantity, 1, "bird quantity comes from its original inventory")
		runner.assert_eq(held.available, 1, "the original carried herb remains available")
		runner.assert_eq(held.entrusted, 0, "bird carrying does not invent entrusted goods")
		runner.assert_true(held.entry_present, "the carried herb is a real ledger entry")
		runner.assert_eq(held.position, SimAvianLife.point(domain.birds.moss_sparrow), "herb follows the bird's continuous original position")
		runner.assert_eq(held.altitude, domain.birds.moss_sparrow.altitude, "bird altitude remains explicit")
		runner.assert_eq(held.carrier, {"kind": "avian", "id": "moss_sparrow"}, "bird body is the carrier")
		runner.assert_eq(held.owner_time_ms, domain.elapsed_ms, "bird inventory reports its own clock")
		runner.assert_true(not held.stale and not held.world_has_backlog, "bird query reports the settled committed instant")
	runner.assert_eq(domain.to_dict(), before, "bird storage lookup is read-only")
	var wrong_region: Dictionary = {"domain": "avian", "region": "river", "container": "bird:moss_sparrow"}
	runner.assert_eq(QUERY.locate(world, wrong_region), {"ok": false, "reason": "invalid_location"}, "a bird cannot be resolved under another region")
	var missing: Dictionary = {"domain": "avian", "region": "home", "container": "bird:missing"}
	runner.assert_eq(QUERY.locate(world, missing), {"ok": false, "reason": "not_found"}, "a missing container never becomes an origin location")
	var body: Dictionary = domain.birds.moss_sparrow
	domain.birds.erase("moss_sparrow")
	runner.assert_eq(QUERY.item(world, bird_ref), {"ok": false, "reason": "invalid_location"}, "a real container without its body fails explicitly")
	domain.birds["moss_sparrow"] = body
	var saved: Dictionary = JSON.parse_string(JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true))
	var restored: RegionalSimulation = _world(runner, true)
	if restored != null:
		var loaded: bool = restored.restore(saved)
		runner.assert_true(loaded, "independent restore retains the bird's actual carried herb")
		if loaded:
			var restored_held: Dictionary = QUERY.item(restored, bird_ref)
			runner.assert_true(bool(restored_held.get("ok", false)), "restored bird and original inventory still resolve")
			if bool(restored_held.get("ok", false)) and bool(held.get("ok", false)):
				runner.assert_eq(restored_held.position, held.position, "restored flight keeps its original position")
				runner.assert_eq(restored_held.quantity, held.quantity, "restored bird keeps the one carried herb")
