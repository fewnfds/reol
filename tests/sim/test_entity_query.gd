extends RefCounted
## Real body and object domains exercise the read-only editor query.

const RegionalFixtures = preload("res://tests/sim/test_regional_simulation.gd")
const FieldFixtures = preload("res://tests/sim/test_field_opportunities.gd")
const QUERY = preload("res://scripts/sim/entity_query.gd")
const CENTERS: Dictionary = {"home": Vector2i(100, 100), "river": Vector2i(150, 100)}
## The region's navigation is a Callable to this fixture instance. Keep the
## instance alive for the whole scenario, including independent restoration.
var _regional_fixtures := RegionalFixtures.new()


func run(runner: Object) -> void:
	_test_lookup_and_rejection(runner)
	_test_invalid_source_and_pending_time(runner)
	_test_stale_remote_snapshot(runner)
	_test_carried_item_and_restored_motion(runner)
	_test_real_field_slot(runner)
	print("SCENARIO entity query: distinct domain identities, original continuous positions, held and field objects, stale remote time, unchanged facts, and in-flight restoration")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _regional_fixtures._make_world(runner, false, false, true, false)
	if world == null:
		return null
	var bird_scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/avian_life.json"))
	if not world.avian_life.spawn_opening(bird_scenario, CENTERS):
		runner.assert_true(false, "query fixture opens the real two-region bird domain")
		return null
	var objects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))
	# The actor and one real artifact intentionally share a bare ID. Their domain
	# qualifiers must keep these existing physical owners separate.
	objects.objects.append({"id": "player", "definition": "wooden_sword", "region": "home", "container": "dorm"})
	objects.objects.append({"id": "remote_sword", "definition": "wooden_sword", "region": "river", "container": "actor:river_player"})
	if not world.artifacts.spawn_opening(objects):
		runner.assert_true(false, "query fixture opens real unique objects")
		return null
	return world


func _test_lookup_and_rejection(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var before: String = _facts(world)
	var actor_ref: Dictionary = {"kind": "actor", "id": "player"}
	var original_ref: Dictionary = actor_ref.duplicate(true)
	var actor: Dictionary = QUERY.locate(world, actor_ref)
	var artifact: Dictionary = QUERY.locate(world, {"kind": "artifact", "id": "player"})
	var bird: Dictionary = QUERY.locate(world, {"kind": "avian", "id": "moss_sparrow"})
	for row: Dictionary in [actor, artifact, bird]:
		runner.assert_true(bool(row.get("ok", false)), "an existing physical owner returns a location")
	if bool(actor.get("ok", false)) and bool(artifact.get("ok", false)) and bool(bird.get("ok", false)):
		runner.assert_eq(actor.state_owner, "village_simulation", "person location comes from the original village")
		runner.assert_eq(actor.position, world.regions.home.actor_position(world.regions.home.actors.player), "person position is its continuous original coordinate")
		runner.assert_eq(actor.cell, SimRouteTravel.cell(world.regions.home.actors.player.cell), "person cell is a projection of its body")
		runner.assert_eq(artifact.state_owner, "artifacts", "same bare ID names a separate artifact")
		runner.assert_eq(artifact.cell, SimRouteTravel.cell(world.regions.home.places.dorm.cell), "stored artifact resolves the real place")
		runner.assert_true(actor.position != artifact.position, "kind and ID never conflate physical objects")
		runner.assert_eq(bird.state_owner, "avian_life", "bird position comes from its independent original body")
		runner.assert_eq(bird.position, SimAvianLife.point(world.avian_life.birds.moss_sparrow), "bird uses continuous flight-space position")
		runner.assert_eq(bird.altitude, 1, "bird's existing flying altitude is retained")
		runner.assert_true(not actor.stale and not artifact.stale and not bird.stale, "initial committed owners are current")
		actor.position = Vector2.ZERO
		actor.record_region = "tampered"
		actor_ref.id = "different"
		var again: Dictionary = QUERY.locate(world, original_ref)
		runner.assert_eq(again.position, world.regions.home.actor_position(world.regions.home.actors.player), "mutating returned data and the previous input cannot alter a later query")
		runner.assert_eq(again.record_region, "home", "mutated result does not alter the original owner")
		runner.assert_eq(original_ref, {"kind": "actor", "id": "player"}, "the original reference remains independently owned")
	var invalids: Array = [null, {}, {"kind": "actor"}, {"kind": "actor", "id": ""}, {"kind": "actor", "id": 5}, {"kind": "actor", "id": "player", "region": "home"}, {"kind": &"actor", "id": "player"}]
	for bad: Variant in invalids:
		var failure: Dictionary = QUERY.locate(world, bad)
		runner.assert_eq(failure, {"ok": false, "reason": "invalid_reference"}, "malformed reference fails explicitly")
	runner.assert_eq(QUERY.locate(world, {"kind": "unknown", "id": "player"}), {"ok": false, "reason": "unsupported_kind"}, "unknown kind is not reinterpreted")
	for kind: String in ["actor", "avian", "artifact"]:
		runner.assert_eq(QUERY.locate(world, {"kind": kind, "id": "not_present"}), {"ok": false, "reason": "not_found"}, "missing " + kind + " has an explicit result")
	runner.assert_eq(QUERY.locate(null, original_ref), {"ok": false, "reason": "world_unavailable"}, "missing world is explicit")
	runner.assert_eq(_facts(world), before, "successful, rejected and output-mutating queries leave world facts and time unchanged")


func _test_invalid_source_and_pending_time(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var before: String = _facts(world)
	var ref: Dictionary = {"kind": "actor", "id": "player"}
	# Reject two independent physical owners for the same domain-qualified ID.
	world.regions.river.actors.player = world.regions.home.actors.player.duplicate(true)
	runner.assert_eq(QUERY.locate(world, ref), {"ok": false, "reason": "ambiguous_reference"}, "duplicate human IDs cannot silently select a region")
	world.regions.river.actors.erase("player")
	var saved_position: Array = world.regions.home.actors.player.position.duplicate()
	world.regions.home.actors.player.position = [saved_position[0] + TileGrid.TILE_SIZE * 2, saved_position[1]]
	runner.assert_eq(QUERY.locate(world, ref), {"ok": false, "reason": "invalid_location"}, "a cell and continuous position disagreement is not repaired by a query")
	world.regions.home.actors.player.position = saved_position
	var saved_elapsed: int = world.regions.home.elapsed_ms
	world.regions.home.elapsed_ms = world.elapsed_ms + 1
	runner.assert_eq(QUERY.locate(world, ref), {"ok": false, "reason": "invalid_time"}, "a source clock ahead of the committed world is rejected")
	world.regions.home.elapsed_ms = saved_elapsed
	# Standalone village records accept nonnegative coordinates independently
	# of the current bird/map fixture's 512-cell limit. A lookup cannot add its
	# own bird-only restriction to a valid village record.
	var saved_cell: Array = world.regions.home.actors.player.cell.duplicate()
	var saved_place: Array = world.regions.home.places.dorm.cell.duplicate()
	var extended := Vector2i(ReolWorld.WORLD_SIZE + 1, 100)
	world.regions.home.set_actor_cell("player", extended)
	world.regions.home.places.dorm.cell = [extended.x, extended.y]
	var extended_person: Dictionary = QUERY.locate(world, ref)
	var extended_item: Dictionary = QUERY.locate(world, {"kind": "artifact", "id": "player"})
	runner.assert_true(bool(extended_person.get("ok", false)) and bool(extended_item.get("ok", false)), "village body and place use their original coordinate contract")
	if bool(extended_person.get("ok", false)) and bool(extended_item.get("ok", false)):
		runner.assert_eq(extended_person.cell, extended, "human body is not constrained by the unrelated bird schema")
		runner.assert_eq(extended_item.cell, extended, "stored item's real village place is not constrained by the bird schema")
	world.regions.home.actors.player.cell = saved_cell
	world.regions.home.actors.player.position = saved_position
	world.regions.home.places.dorm.cell = saved_place
	runner.assert_eq(_facts(world), before, "inspection of inconsistent inputs does not change the restored owners or clocks")

	# Budget exhaustion sets a future target without committing any extra time.
	# A location current at the committed instant must not imply a current target.
	runner.assert_true(not world.advance_to_ms(10000, 0), "zero work budget retains an unprocessed target")
	var pending_before: String = _facts(world)
	var pending: Dictionary = QUERY.locate(world, ref)
	runner.assert_true(bool(pending.get("ok", false)), "the last committed body is queryable with a pending target")
	if bool(pending.get("ok", false)):
		runner.assert_true(not pending.stale and pending.world_has_backlog, "source freshness and the world's unprocessed future are distinct")
		runner.assert_eq(pending.world_time_ms, 0, "query does not project an uncommitted instant")
		runner.assert_eq(pending.target_time_ms, 10000, "the requested target stays visible")
	runner.assert_eq(_facts(world), pending_before, "a pending query does not consume budget or synchronize time")


func _test_stale_remote_snapshot(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	runner.assert_true(world.set_active_region("home"), "stale test keeps the home region active")
	runner.assert_true(world.advance_to_ms(1234), "world advances while a remote village may batch its work")
	var remote: VillageSimulation = world.regions.river
	runner.assert_true(remote.elapsed_ms < world.elapsed_ms, "real offscreen region is behind the committed world instant")
	if remote.elapsed_ms >= world.elapsed_ms:
		return
	var before: String = _facts(world)
	var person: Dictionary = QUERY.locate(world, {"kind": "actor", "id": "river_player"})
	var held: Dictionary = QUERY.locate(world, {"kind": "artifact", "id": "remote_sword"})
	runner.assert_true(bool(person.get("ok", false)) and bool(held.get("ok", false)), "lagging original body and held artifact remain findable")
	if bool(person.get("ok", false)) and bool(held.get("ok", false)):
		runner.assert_true(person.stale and held.stale, "both positions explicitly report the old regional snapshot")
		runner.assert_eq(person.owner_time_ms, remote.elapsed_ms, "actor reports its real owner time")
		runner.assert_eq(person.world_time_ms, world.elapsed_ms, "actor reports the committed world time")
		runner.assert_eq(held.owner_time_ms, world.elapsed_ms, "artifact state belongs to the regional world clock")
		runner.assert_eq(held.location_time_ms, remote.elapsed_ms, "held position retains the carrier's older time")
		runner.assert_eq(held.position, person.position, "stale held item references the same original body position")
		runner.assert_eq(held.record_region, "river", "saved container region is named as a record, not a geographic conclusion")
	runner.assert_eq(_facts(world), before, "reading a stale location never synchronizes it or advances any world state")


func _test_carried_item_and_restored_motion(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	runner.assert_true(world.set_active_region("home"), "the moving carrier's region advances at each committed boundary")
	var home: VillageSimulation = world.regions.home
	home.set_actor_cell("player", SimRouteTravel.cell(home.places.kitchen.cell))
	world.invalidate_region("home")
	var take: Dictionary = world.artifacts.begin("player", "take", "hearth_stone")
	runner.assert_true(bool(take.get("ok", false)), "player begins the existing timed transfer of the original artifact")
	if not bool(take.get("ok", false)):
		return
	var due: int = int(world.artifacts.active.player.due_ms)
	runner.assert_true(world.advance_to_ms(due), "the actual artifact transfer completes")
	runner.assert_eq(world.artifacts.objects.hearth_stone.container, "actor:player", "one original artifact is now carried by the player")
	runner.assert_true(not world.artifacts.owns_actor("player") and world.native_action_allowed("player"), "the finished transfer releases the original body's action channel")
	var destination: Vector2i = SimRouteTravel.cell(home.places.dorm.cell)
	runner.assert_true(home._navigation.is_valid() and not home.find_path(SimRouteTravel.cell(home.actors.player.cell), destination).is_empty(), "the original village has a live route to the real rest place")
	var began: bool = home.submit_action("player", "rest")
	runner.assert_true(began, "the original carrier starts a real route")
	if not began:
		return
	world.invalidate_region("home")
	var before_step: Vector2 = home.actor_position(home.actors.player)
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 100), "carrier moves for an actual partial segment")
	var person: Dictionary = QUERY.locate(world, {"kind": "actor", "id": "player"})
	var item: Dictionary = QUERY.locate(world, {"kind": "artifact", "id": "hearth_stone"})
	runner.assert_true(bool(person.get("ok", false)) and bool(item.get("ok", false)), "moving carrier and its original item are both queryable")
	if not bool(person.get("ok", false)) or not bool(item.get("ok", false)):
		return
	runner.assert_true(person.position != before_step, "the body actually advanced continuously")
	runner.assert_true(person.position != TileGrid.cell_to_world(person.cell), "the sample is between tile centers")
	runner.assert_eq(item.position, person.position, "held artifact follows the carrier's continuous point")
	runner.assert_eq(item.cell, person.cell, "held artifact and carrier project to the same tile")
	var before: String = _facts(world)
	QUERY.locate(world, {"kind": "actor", "id": "player"})
	QUERY.locate(world, {"kind": "artifact", "id": "hearth_stone"})
	runner.assert_eq(_facts(world), before, "looking at a real in-flight process neither advances nor cancels it")
	# Saving intentionally synchronizes the regions; query again only after that
	# real save boundary, then restore the saved process in an independent world.
	var archive: Dictionary = _round_trip(world.to_dict())
	var expected_person: Dictionary = QUERY.locate(world, {"kind": "actor", "id": "player"})
	var expected_item: Dictionary = QUERY.locate(world, {"kind": "artifact", "id": "hearth_stone"})
	var restored: RegionalSimulation = _world(runner)
	if restored == null:
		return
	var accepted: bool = restored.restore(archive)
	runner.assert_true(accepted, "actual in-flight world restores independently")
	if not accepted:
		return
	var restored_person: Dictionary = QUERY.locate(restored, {"kind": "actor", "id": "player"})
	var restored_item: Dictionary = QUERY.locate(restored, {"kind": "artifact", "id": "hearth_stone"})
	runner.assert_eq(restored_person, expected_person, "query finds the same original body position and time after restoration")
	runner.assert_eq(restored_item, expected_item, "query finds the same unique carried object after restoration")


func _test_real_field_slot(runner: Object) -> void:
	var fixture := FieldFixtures.new()
	var world: RegionalSimulation = fixture._world(runner)
	if world == null:
		return
	var before: String = _facts(world)
	var result: Dictionary = QUERY.locate(world, {"kind": "artifact", "id": "stele_drawing_ring"})
	runner.assert_true(bool(result.get("ok", false)), "the real field artifact slot can be located")
	if bool(result.get("ok", false)):
		var cell: Vector2i = fixture._site(world)
		runner.assert_eq(result.cell, cell, "field object uses the original slot's cell")
		runner.assert_eq(result.position, TileGrid.cell_to_world(cell), "field slot is projected at its actual tile center")
		runner.assert_eq(result.location_owner, "field_opportunities", "field slot remains owned by its original domain")
	runner.assert_eq(_facts(world), before, "looking up the slot does not create knowledge or advance the field")


func _facts(world: RegionalSimulation) -> String:
	# RegionalSimulation.to_dict() deliberately settles quiet regions, so it
	# cannot be used to check whether a query itself synchronized a stale world.
	var regions: Dictionary = {}
	for region: String in world.regions:
		regions[region] = world.regions[region].to_dict()
	var snapshot: Dictionary = {
		"elapsed_ms": world.elapsed_ms, "target_ms": world.target_ms,
		"active_region": world.active_region, "work": world.simulation_work.duplicate(true),
		"boundaries": world._region_boundaries.duplicate(true), "regions": regions,
		"avian": world.avian_life.to_dict(), "artifacts": world.artifacts.to_dict(),
		"embodiment": world.embodiment.to_dict(), "field": world.field_opportunities.to_dict(),
		"services": {} if world.services == null else world.services.to_dict(),
		"routes": world.routes.duplicate(true), "couriers": world.couriers.duplicate(true),
		"shipments": world.shipments.duplicate(true), "events": world.events.duplicate(true),
		"messages": world.messages.duplicate(true), "news": world.local_news.duplicate(true),
		"cargo": world.in_transit.to_dict(), "operations": world.operations.duplicate(true),
	}
	return SnapshotValues.canonical_json(SnapshotValues.normalized(snapshot))


func _round_trip(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value, "", true, true))
