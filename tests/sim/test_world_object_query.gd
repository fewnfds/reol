extends RefCounted
## Integration checks use the original world owners. The facade exposes an
## authority-only projection and an explicitly scoped, detached spatial view.

const RoomsFixture = preload("res://tests/sim/test_rooms_and_rest.gd")
const EntityFixture = preload("res://tests/sim/test_entity_query.gd")
const CENTERS: Dictionary = {"home": Vector2i(100, 100), "river": Vector2i(150, 100)}

# Navigation and placement use Callables bound to these RefCounted fixtures.
# Keep them alive for the complete test, including independent restoration.
var _rooms := RoomsFixture.new()
var _entity := EntityFixture.new()


class FlatMap extends WorldMapData:
	func get_terrain(cell: Vector2i) -> int:
		return TERRAIN_GRASS if in_bounds(cell) else -1

	func get_elevation(cell: Vector2i) -> int:
		return 0 if in_bounds(cell) else -1


class CountingInventory extends SimInventory:
	var availability_calls: int = 0
	var custody_calls: int = 0

	func available(container: String, item: String) -> int:
		availability_calls += 1
		return super.available(container, item)

	func entrusted(container: String, item: String) -> int:
		custody_calls += 1
		return super.entrusted(container, item)


func run(runner: Object) -> void:
	_real_sources_snapshot_and_restore(runner)
	_nonrectangular_workplace(runner)
	_stock_does_not_scan_custody(runner)
	_stale_backlog_and_rejections(runner)
	print("SCENARIO world object query: original body, stock, resource, structure and item owners; scoped geometry, source clocks and JSON restoration")


func _world(runner: Object) -> Dictionary:
	var world: RegionalSimulation = _rooms._world(runner)
	if world == null:
		return {}
	var bird_opening: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/avian_life.json"))
	if not bird_opening is Dictionary or not world.avian_life.spawn_opening(bird_opening, CENTERS):
		runner.assert_true(false, "avian domain assembles the original bird bodies")
		return {}
	world.large_bodies.set_geometry(
		func(cell: Vector2i) -> bool: return cell.x > 0 and cell.y > 0 and cell.x < 200 and cell.y < 200,
		func(_cell: Vector2i) -> int: return 0)
	if not world.large_bodies.add_body("test_beast", "巡坡山兽", "home", Vector2i(112, 114), Vector2i(117, 114)):
		runner.assert_true(false, "large body is created through its original owner")
		return {}
	# An additional definition has the same capability but another content ID.
	# Add it to this fixture's content and domain definitions before spawning;
	# neither object nor capability is fabricated in a query result.
	var variant: Dictionary = world._content.artifacts.types.wooden_sword.duplicate(true)
	variant.name = "第二种练习器"
	world._content.artifacts.types["test_other_weapon"] = variant.duplicate(true)
	world.artifacts.definitions.types["test_other_weapon"] = variant.duplicate(true)
	var opening: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))
	if not opening is Dictionary:
		runner.assert_true(false, "artifact opening fixture is valid")
		return {}
	opening.objects.append({"id": "player", "definition": "wooden_sword", "region": "home", "container": "actor:player"})
	opening.objects.append({"id": "other_weapon", "definition": "test_other_weapon", "region": "home", "container": "dorm"})
	if not world.artifacts.spawn_opening(opening):
		runner.assert_true(false, "unique artifacts are spawned by the original artifact owner")
		return {}
	var blueprint: String = _rooms._fixtures._place(runner, world, "wood_wall", Vector2i(109, 107))
	if blueprint.is_empty():
		return {}
	return {"world": world, "blueprint": blueprint}


func _stock(region: String, container: String, item: String) -> Dictionary:
	return {"kind": "stock", "domain": "village", "region": region, "container": container, "item": item}


func _refs(blueprint: String) -> Array:
	return [
		{"kind": "actor", "id": "player"},
		{"kind": "artifact", "id": "player"},
		{"kind": "artifact", "id": "other_weapon"},
		{"kind": "avian", "id": "moss_sparrow"},
		{"kind": "large_body", "id": "test_beast"},
		{"kind": "resource", "region": "home", "id": "herb_slope"},
		_stock("home", "kitchen", "wood"),
		{"kind": "construction", "id": blueprint},
	]


func _real_sources_snapshot_and_restore(runner: Object) -> void:
	var fixture: Dictionary = _world(runner)
	if fixture.is_empty():
		return
	var world: RegionalSimulation = fixture.world
	var references: Array = _refs(fixture.blueprint)
	var before: String = _entity._facts(world)
	var rows: Array[Dictionary] = []
	for reference: Dictionary in references:
		var row: Dictionary = world.describe_object(reference)
		runner.assert_true(bool(row.get("ok", false)), "original object is resolved by its domain-qualified reference: " + str(reference))
		if not bool(row.get("ok", false)):
			return
		rows.append(row)
		runner.assert_eq(row.reference, reference, "description preserves the original reference")
		runner.assert_eq(row.visibility, "authority_only", "developer truth is not player knowledge")
		runner.assert_true(not row.stale and not row.world_has_backlog, "opening source and world clocks are current")
		runner.assert_eq(row.world_time_ms, world.elapsed_ms, "all owners report the committed common clock")
		runner.assert_true(not row.spatial.navigation_occupancy, "projection is not a navigation or placement permission")
	var person: Dictionary = rows[0]
	var held: Dictionary = rows[1]
	var variant: Dictionary = rows[2]
	var bird: Dictionary = rows[3]
	var beast: Dictionary = rows[4]
	var source: Dictionary = rows[5]
	var stock: Dictionary = rows[6]
	var paper: Dictionary = rows[7]
	runner.assert_eq(person.classification, "body", "a human resolves to the original body")
	runner.assert_eq(person.state_owner, "village_simulation", "human state has the village owner")
	runner.assert_eq(held.classification, "unique_item", "same bare ID still resolves a distinct object kind")
	runner.assert_eq(held.state_owner, "artifacts", "the unique item remains owned by artifacts")
	runner.assert_eq(held.spatial.cells, person.spatial.cells, "held item follows the original body anchor")
	runner.assert_eq(held.spatial.layer, "container", "a carried object is not a floor object")
	runner.assert_eq(held.spatial.relation, "contained", "item custody remains explicit")
	runner.assert_eq(bird.state_owner, "avian_life", "the flying body retains its original domain")
	runner.assert_eq(bird.spatial.layer, "air", "an airborne bird does not become ground occupancy")
	runner.assert_eq(beast.spatial.cells.size(), 9, "a three-by-three body projects every original footprint cell")
	runner.assert_eq(beast.spatial.cells, SimBodyGeometry.cells(Vector2i(112, 114), Vector2i(3, 3)), "large geometry derives from the real form and anchor")
	runner.assert_eq(source.classification, "resource_record", "the natural source stays a source record")
	runner.assert_true(not bool(source.attributes.independent_plant), "a resource patch is not invented as a plant instance")
	runner.assert_eq(source.attributes.quantity, world.regions.home.inventory.quantity("resource:herb_slope", "herb"), "resource quantity remains in the original inventory")
	runner.assert_eq(source.attributes.quantity_owner, "village_inventory", "source and stock ownership are distinct")
	runner.assert_eq(stock.classification, "stock_entry", "material quantity is an inventory entry")
	runner.assert_eq(stock.attributes.quantity, 0, "an existing zero quantity is distinguishable from absence")
	runner.assert_true(not bool(stock.attributes.independent_instance), "a stock entry is not a unique object")
	runner.assert_eq(world.describe_object(_stock("home", "kitchen", "missing_item")), {"ok": false, "reason": "not_found"}, "missing stock is not reported as an existing zero")
	runner.assert_eq(paper.attributes.state, "blueprint", "paper is projected from the real unbuilt project")
	runner.assert_eq(paper.spatial.layer, "planned", "blueprint is separate from physical ground objects")
	runner.assert_true(not bool(paper.attributes.movement_blocked) and not world.construction.blocked(Vector2i(109, 107)), "paper does not block the actual map")
	var walk: Dictionary = world.object_capability(references[0], "walk")
	var fly: Dictionary = world.object_capability(references[0], "fly")
	var weapon: Dictionary = world.object_capability(references[1], "weapon")
	var other_weapon: Dictionary = world.object_capability(references[2], "weapon")
	runner.assert_true(bool(walk.get("ok", false)) and bool(walk.get("declared", false)), "body capability is obtained from its form")
	runner.assert_true(bool(fly.get("ok", false)) and not bool(fly.get("declared", true)), "known bird capability is not automatically a human capability")
	runner.assert_true(bool(weapon.get("ok", false)) and bool(weapon.get("declared", false)) and bool(other_weapon.get("declared", false)), "same capability works for another data-defined item")
	runner.assert_eq(weapon.get("scope"), "declaration_only", "capability does not grant permission to use an object")
	runner.assert_eq(variant.attributes.definition_id, "test_other_weapon", "different definitions remain distinguishable")
	runner.assert_eq(world.object_capability(references[1], "unregistered_capability"), {"ok": false, "reason": "unsupported_capability"}, "an unknown capability is not a false declaration")
	var snapshot_result: Dictionary = world.capture_object_space(references)
	runner.assert_true(bool(snapshot_result.get("ok", false)), "one bounded snapshot captures multiple actual owners")
	if not bool(snapshot_result.get("ok", false)):
		return
	runner.assert_eq(snapshot_result.scope, "captured_references", "snapshot is not a world enumeration")
	runner.assert_true(not snapshot_result.live and snapshot_result.object_count == references.size(), "snapshot is detached and names its input scope")
	var snapshot: SimObjectSpatialSnapshot = snapshot_result.snapshot
	var same_cell: Rect2i = Rect2i(person.spatial.cells[0], Vector2i.ONE)
	var floor_result: Dictionary = snapshot.query(same_cell, "ground")
	var carried_result: Dictionary = snapshot.query(same_cell, "container")
	runner.assert_true(bool(floor_result.get("ok", false)) and bool(carried_result.get("ok", false)), "both layers of the captured cell can be queried")
	if bool(floor_result.get("ok", false)) and bool(carried_result.get("ok", false)):
		runner.assert_true(floor_result.references.has(references[0]) and not floor_result.references.has(references[1]), "ground query includes the body but excludes the held item")
		runner.assert_true(carried_result.references.has(references[1]) and not carried_result.references.has(references[0]), "container query includes the held object but excludes the body")
		runner.assert_true(floor_result.complete and floor_result.scope == "captured_references" and not floor_result.live, "query completeness covers only the captured set")
		if not carried_result.references.is_empty():
			carried_result.references[0].id = "mutated_result"
		var again: Dictionary = snapshot.query(same_cell, "container")
		runner.assert_true(again.references.has(references[1]), "mutating query output cannot mutate a sealed snapshot")
	var partial_capture: Dictionary = world.capture_object_space([references[1]])
	runner.assert_true(bool(partial_capture.get("ok", false)), "a caller may deliberately capture a subset of the world")
	if bool(partial_capture.get("ok", false)):
		var subset_ground: Dictionary = partial_capture.snapshot.query(same_cell, "ground")
		runner.assert_true(bool(subset_ground.get("ok", false)) and subset_ground.references.is_empty() and subset_ground.scope == "captured_references", "uncaptured real body is not silently included in the query scope")
	var exhausted: Dictionary = snapshot.query(same_cell, "", "", 1)
	runner.assert_true(not bool(exhausted.get("ok", true)) and exhausted.get("reason") == "budget_exhausted" and not exhausted.get("complete", true), "a spatial budget failure does not claim complete results")
	runner.assert_true(not exhausted.has("references"), "failed area query publishes no partial reference set")
	var paper_ground: Dictionary = snapshot.query(Rect2i(Vector2i(109, 107), Vector2i.ONE), "ground")
	var paper_plan: Dictionary = snapshot.query(Rect2i(Vector2i(109, 107), Vector2i.ONE), "planned")
	runner.assert_true(bool(paper_ground.get("ok", false)) and not paper_ground.references.has(references[7]), "blueprint is not returned as a built ground structure")
	runner.assert_true(bool(paper_plan.get("ok", false)) and paper_plan.references.has(references[7]), "the same original blueprint is returned on the planned layer")
	var beast_cell: Dictionary = snapshot.query(Rect2i(Vector2i(113, 115), Vector2i.ONE), "ground")
	runner.assert_true(bool(beast_cell.get("ok", false)) and beast_cell.references.has(references[4]), "a corner cell returns the one original multi-cell body")
	person.reference.id = "mutated"
	person.spatial.cells[0] = Vector2i.ZERO
	person.capabilities.clear()
	stock.attributes.quantity = 999999
	runner.assert_eq(_entity._facts(world), before, "query, capture and mutated outputs do not change original owners or time")
	runner.assert_eq(world.describe_object(references[0]).spatial.cells, [TileGrid.world_to_cell(world.regions.home.actor_position(world.regions.home.actors.player))], "fresh query is detached from prior output mutations")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))
	var saved_fact: String = SnapshotValues.canonical_json(SnapshotValues.normalized(saved))
	world.describe_object(references[5])
	world.capture_object_space(references)
	runner.assert_eq(SnapshotValues.canonical_json(SnapshotValues.normalized(world.to_dict())), saved_fact, "whole synchronized world is unchanged across queries")
	var restored_fixture: Dictionary = _world(runner)
	if restored_fixture.is_empty():
		return
	var restored: RegionalSimulation = restored_fixture.world
	var accepted: bool = restored.restore(saved)
	runner.assert_true(accepted, "the actual world round-trips through JSON into an independent candidate")
	if not accepted:
		return
	for reference: Dictionary in references:
		runner.assert_eq(restored.describe_object(reference), world.describe_object(reference), "JSON restoration finds the same owner, geometry and clock")
	var captured_again: Dictionary = restored.capture_object_space(references)
	runner.assert_true(bool(captured_again.get("ok", false)), "restored original owners can be captured again")
	if bool(captured_again.get("ok", false)):
		var restored_snapshot: SimObjectSpatialSnapshot = captured_again.snapshot
		runner.assert_eq(restored_snapshot.query(same_cell, "container"), snapshot.query(same_cell, "container"), "restored scoped query returns the same original held object")
	# After a real world mutation, the previously sealed capture remains history.
	var old_cell: Vector2i = same_cell.position
	var new_cell: Vector2i = old_cell + Vector2i.RIGHT
	world.regions.home.set_actor_cell("player", new_cell)
	world.invalidate_region("home")
	runner.assert_true(snapshot.query(same_cell, "ground").references.has(references[0]), "an old capture does not silently become a live index")
	var updated: Dictionary = world.capture_object_space([references[0]])
	if bool(updated.get("ok", false)):
		runner.assert_true(updated.snapshot.query(Rect2i(new_cell, Vector2i.ONE), "ground").references.has(references[0]), "a new capture observes the changed original body")
	else:
		runner.assert_true(false, "changed body can be captured again")


func _nonrectangular_workplace(runner: Object) -> void:
	var world: RegionalSimulation = _rooms._fixtures._world(runner)
	if world == null:
		return
	var home: VillageSimulation = world.regions.home
	if not SimWorkplaces.enable_opening(home.config, home.places, home.actors, FlatMap.new(), str(home.config.institution.id)):
		runner.assert_true(false, "opening workplace assembles from its original owner")
		return
	var wall_ref: Dictionary = {"kind": "workplace", "region": "home", "part": "walls"}
	var roof_ref: Dictionary = {"kind": "workplace", "region": "home", "part": "roof"}
	var walls: Dictionary = world.describe_object(wall_ref)
	var roof: Dictionary = world.describe_object(roof_ref)
	runner.assert_true(bool(walls.get("ok", false)) and bool(roof.get("ok", false)), "original multi-cell workplace components resolve")
	if not bool(walls.get("ok", false)) or not bool(roof.get("ok", false)):
		return
	var original_cells: Array[Vector2i] = []
	for raw: Array in home.places.records.workspace.walls:
		original_cells.append(SimRouteTravel.cell(raw))
	runner.assert_eq(walls.spatial.cells, original_cells, "one source component retains its exact saved cells")
	var min_cell: Vector2i = original_cells[0]
	var max_cell: Vector2i = original_cells[0]
	for cell: Vector2i in original_cells:
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
	var bounds: Rect2i = Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)
	runner.assert_true(original_cells.size() < bounds.size.x * bounds.size.y, "actual wall component is not its filled bounding rectangle")
	var hole := Vector2i(-1, -1)
	for y: int in range(min_cell.y, max_cell.y + 1):
		for x: int in range(min_cell.x, max_cell.x + 1):
			var cell := Vector2i(x, y)
			if not original_cells.has(cell):
				hole = cell
				break
		if hole.x >= 0:
			break
	var before: String = _entity._facts(world)
	var captured: Dictionary = world.capture_object_space([wall_ref, roof_ref])
	runner.assert_true(bool(captured.get("ok", false)), "multi-cell wall and roof are captured from the original workplace")
	if not bool(captured.get("ok", false)):
		return
	var snapshot: SimObjectSpatialSnapshot = captured.snapshot
	var ground: Dictionary = snapshot.query(bounds, "ground")
	var upper: Dictionary = snapshot.query(bounds, "roof")
	runner.assert_true(ground.ok and ground.references == [wall_ref], "many wall cells return their one component once")
	runner.assert_true(upper.ok and upper.references == [roof_ref], "upper roof remains a separate component and layer")
	if hole.x >= 0:
		var empty: Dictionary = snapshot.query(Rect2i(hole, Vector2i.ONE), "ground")
		runner.assert_true(empty.ok and empty.references.is_empty(), "the wall's bounding-box interior does not gain an invented wall")
	walls.spatial.cells.clear()
	roof.reference.part = "mutated"
	runner.assert_eq(_entity._facts(world), before, "multi-cell descriptions and capture do not change source layout or time")


func _stock_does_not_scan_custody(runner: Object) -> void:
	var fixture: Dictionary = _world(runner)
	if fixture.is_empty():
		return
	var world: RegionalSimulation = fixture.world
	var sim: VillageSimulation = world.regions.home
	# Instrument the original ledger API without changing its records: the test
	# owner restores a detached copy through SimInventory.restore, then receives
	# valid reservations/custody using the same public operations.
	var inventory := CountingInventory.new()
	if not inventory.restore(sim.inventory.to_dict()):
		runner.assert_true(false, "instrumented inventory restores the actual ledger")
		return
	sim.inventory = inventory
	var original: int = inventory.quantity("store", "wood")
	runner.assert_true(inventory.reserve("query_reserve", "store", "wood", 2, "player"), "fixture creates a real reservation")
	runner.assert_true(inventory.entrust("query_custody", "store", "wood", 3, {"domain": "test"}), "fixture creates a real custody obligation")
	inventory.availability_calls = 0
	inventory.custody_calls = 0
	var reference: Dictionary = _stock("home", "store", "wood")
	var before: String = JSON.stringify(inventory.to_dict(), "", true, true)
	var row: Dictionary = world.describe_object(reference)
	var declared: Dictionary = world.object_capability(reference, "quantity_record")
	var captured: Dictionary = world.capture_object_space([reference])
	runner.assert_true(bool(row.get("ok", false)) and int(row.attributes.quantity) == original, "stock projection reads the actual total, not available quantity")
	runner.assert_true(bool(declared.get("ok", false)) and bool(declared.get("declared", false)) and bool(captured.get("ok", false)), "quantity capability and capture reuse the same ledger")
	runner.assert_eq(inventory.availability_calls, 0, "query does not perform a reservation scan")
	runner.assert_eq(inventory.custody_calls, 0, "query does not perform a custody scan")
	runner.assert_eq(JSON.stringify(inventory.to_dict(), "", true, true), before, "query does not release custody or reservations")
	runner.assert_eq(inventory.available("store", "wood"), original - 5, "ordinary availability still accounts for both obligations")


func _stale_backlog_and_rejections(runner: Object) -> void:
	var fixture: Dictionary = _world(runner)
	if fixture.is_empty():
		return
	var world: RegionalSimulation = fixture.world
	var person: Dictionary = {"kind": "actor", "id": "player"}
	var remote: Dictionary = {"kind": "actor", "id": "river_player"}
	var remote_source: Dictionary = {"kind": "resource", "region": "river", "id": "herb_slope"}
	runner.assert_eq(world.describe_object(null), {"ok": false, "reason": "invalid_reference"}, "malformed reference is rejected")
	runner.assert_eq(world.describe_object({"kind": "unknown", "id": "player"}), {"ok": false, "reason": "unsupported_kind"}, "unsupported type is not mistaken for absence")
	runner.assert_eq(world.describe_object({"kind": "actor", "id": "missing"}), {"ok": false, "reason": "not_found"}, "missing body has an explicit result")
	runner.assert_eq(world.object_capability(person, ""), {"ok": false, "reason": "invalid_capability"}, "empty capability is invalid")
	runner.assert_eq(world.capture_object_space([person], 0), {"ok": false, "reason": "invalid_budget"}, "zero capture budget is invalid")
	runner.assert_eq(world.capture_object_space([person, remote], 1), {"ok": false, "reason": "budget_exhausted"}, "capture does not return a partial result when its input budget is exhausted")
	runner.assert_eq(world.capture_object_space([person, person]), {"ok": false, "reason": "duplicate_reference"}, "one reference cannot be counted as two objects")
	runner.assert_true(world.set_active_region("home"), "home stays active while the remote village batches")
	runner.assert_true(world.advance_to_ms(1234), "the world advances to a real common boundary")
	if world.regions.river.elapsed_ms >= world.elapsed_ms:
		runner.assert_true(false, "fixture produces a genuinely stale remote owner")
		return
	var before: String = _entity._facts(world)
	var stale: Dictionary = world.describe_object(remote)
	var stale_source: Dictionary = world.describe_object(remote_source)
	var stale_capability: Dictionary = world.object_capability(remote, "walk")
	runner.assert_true(bool(stale.get("ok", false)) and stale.stale and not stale.world_has_backlog, "remote source staleness is distinct from world backlog")
	runner.assert_eq(stale.owner_time_ms, world.regions.river.elapsed_ms, "remote body reports its real source time")
	runner.assert_true(bool(stale_source.get("ok", false)) and stale_source.stale, "remote resource retains its older regional timestamp")
	runner.assert_true(bool(stale_capability.get("ok", false)) and stale_capability.stale, "capability declaration preserves source staleness")
	runner.assert_eq(world.capture_object_space([person, remote]), {"ok": false, "reason": "stale_source"}, "capture refuses stale sources rather than projecting a false current world")
	runner.assert_eq(_entity._facts(world), before, "stale lookup never synchronizes a region")
	var target: int = world.elapsed_ms + 10000
	runner.assert_true(not world.advance_to_ms(target, 0), "zero simulation budget retains actual pending time")
	before = _entity._facts(world)
	var pending: Dictionary = world.describe_object(person)
	runner.assert_true(bool(pending.get("ok", false)) and pending.world_has_backlog, "committed observation explicitly reports the pending target")
	runner.assert_eq(pending.target_time_ms, target, "pending future is not treated as committed")
	runner.assert_eq(world.capture_object_space([person]), {"ok": false, "reason": "world_has_backlog"}, "capture cannot publish a current snapshot while time is pending")
	runner.assert_eq(_entity._facts(world), before, "backlog queries neither consume budget nor advance the world")
