extends RefCounted
## Development lookup of original large bodies, not a second entity registry.

const RegionalFixtures = preload("res://tests/sim/test_regional_simulation.gd")
const QUERY = preload("res://scripts/sim/entity_query.gd")
const BODY_ID: String = "test_beast"
const REFERENCE: Dictionary = {"kind": "large_body", "id": BODY_ID}
## Village navigation calls this fixture. Keep it alive through each world and
## independent restore; no Callable or closure captures a world back into itself.
var _regional_fixtures := RegionalFixtures.new()


func run(runner: Object) -> void:
	_stationary_and_identity(runner)
	_moving_and_restore(runner)
	_pending_and_source_time(runner)
	_invalid_sources(runner)
	_invalid_current_leg(runner)
	print("SCENARIO large-body query: original positions and owner clocks, continuous presentation extent versus reserved sweep, independent motion restore, retained backlog and detached read-only results")


func _world(runner: Object) -> RegionalSimulation:
	# Same real add_body fixture/layout as test_large_bodies._world. Retaining
	# its RegionalFixtures owner avoids dangling village navigation Callables.
	var world: RegionalSimulation = _regional_fixtures._make_world(runner)
	if world == null:
		return null
	world.large_bodies.set_geometry(_fixture_open_ground, _fixture_elevation)
	var added: bool = world.large_bodies.add_body(BODY_ID, "巡坡山兽", "home", Vector2i(112, 114), Vector2i(117, 114))
	runner.assert_true(added, "query fixture creates the original large body and its real carrier")
	return world if added else null


static func _fixture_open_ground(cell: Vector2i) -> bool:
	return cell.x > 0 and cell.y > 0 and cell.x < 200 and cell.y < 200


static func _fixture_elevation(_cell: Vector2i) -> int:
	return 0


func _stationary_and_identity(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var before: String = _facts_digest(world)
	var reference: Dictionary = REFERENCE.duplicate(true)
	var row: Dictionary = QUERY.locate(world, reference)
	runner.assert_true(bool(row.get("ok", false)), "stationary original large body can be located")
	if not bool(row.get("ok", false)):
		return
	runner.assert_eq(row.kind, "large_body", "large body identity remains domain-qualified")
	runner.assert_eq(row.id, BODY_ID, "query keeps the original source ID")
	runner.assert_eq(row.position, world.large_bodies.point(BODY_ID), "query reads the unique source's continuous position")
	runner.assert_eq(row.cell, Vector2i(112, 114), "cell projects the original source position")
	runner.assert_eq(row.state_owner, "large_bodies", "large body state belongs to its original domain")
	runner.assert_eq(row.location_owner, "large_bodies", "location also belongs to the original large-body domain")
	runner.assert_eq(row.record_region, "home", "record region is the saved association")
	runner.assert_eq(row.owner_time_ms, world.large_bodies.elapsed_ms, "owner time reads the actual domain clock")
	runner.assert_eq(row.location_time_ms, world.large_bodies.elapsed_ms, "location reports the same original domain clock")
	runner.assert_true(not row.stale and not row.world_has_backlog, "fresh source and fully committed target are explicit")
	runner.assert_eq(row.footprint, Vector2i(3, 3), "footprint has the original form's cell dimensions")
	runner.assert_eq(row.swept_bounds_cells, Rect2i(111, 113, 3, 3), "resting reservation is the original nine-cell footprint")
	runner.assert_eq(row.swept_bounds_cells, world.large_bodies.swept_bounds(BODY_ID), "query reuses the original conservative occupancy")
	runner.assert_eq(row.physical_bounds_px, Rect2(Vector2(111, 113) * TileGrid.TILE_SIZE, Vector2(3, 3) * TileGrid.TILE_SIZE), "resting presentation rectangle is expressed in pixels")
	for private_field: String in ["waypoints", "path", "destination", "step", "facing", "body", "knowledge", "intent"]:
		runner.assert_true(not row.has(private_field), "query does not expose private route or intent field " + private_field)
	row.position = Vector2.ZERO
	row.footprint = Vector2i.ONE
	row.physical_bounds_px = Rect2()
	row.swept_bounds_cells = Rect2i()
	row.record_region = "changed"
	reference.id = "changed"
	var again: Dictionary = QUERY.locate(world, REFERENCE)
	runner.assert_true(bool(again.get("ok", false)) and again.cell == Vector2i(112, 114) and again.footprint == Vector2i(3, 3) and again.record_region == "home", "input/output mutation does not reach the source")
	runner.assert_eq(_facts_digest(world), before, "stationary queries and detached output mutation preserve all inspected facts")

	# Bare IDs may be shared by different domains. A record association does not
	# assert containment: this home-owned body is physically beside the river.
	var added: bool = world.large_bodies.add_body("player", "同名兽身", "home", Vector2i(160, 114), Vector2i(165, 114))
	runner.assert_true(added, "real large-body source may share a person's bare ID")
	if not added:
		return
	var body: Dictionary = QUERY.locate(world, {"kind": "large_body", "id": "player"})
	var person: Dictionary = QUERY.locate(world, {"kind": "actor", "id": "player"})
	runner.assert_true(bool(body.get("ok", false)) and bool(person.get("ok", false)), "both distinct original owners remain independently queryable")
	if bool(body.get("ok", false)) and bool(person.get("ok", false)):
		runner.assert_eq(body.position, TileGrid.cell_to_world(Vector2i(160, 114)), "large-body qualifier resolves its actual source")
		runner.assert_eq(person.position, world.regions.home.actor_position(world.regions.home.actors.player), "actor qualifier still resolves the original human body")
		runner.assert_true(body.position != person.position and body.state_owner != person.state_owner, "same bare ID never merges two physical owners")
		runner.assert_eq(body.record_region, "home", "location query does not invent a geographic region from the position")
		runner.assert_true(not body.has("spatial_region") and not body.has("current_region"), "saved ownership is not presented as geographic containment")


func _moving_and_restore(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var start: Vector2 = world.large_bodies.point(BODY_ID)
	runner.assert_true(world.advance_to_ms(15400), "common world time actually advances into the original large-body step")
	var row: Dictionary = QUERY.locate(world, REFERENCE)
	runner.assert_true(bool(row.get("ok", false)) and not world.large_bodies.bodies[BODY_ID].step.is_empty(), "real in-flight source remains queryable")
	if not bool(row.get("ok", false)):
		return
	runner.assert_eq(row.position, start + Vector2(TileGrid.TILE_SIZE * 0.25, 0), "400 of 1600 milliseconds produces the original quarter-step position")
	runner.assert_true(row.position != TileGrid.cell_to_world(row.cell), "query does not snap an in-flight body to its grid anchor")
	runner.assert_eq(row.swept_bounds_cells, Rect2i(111, 113, 4, 3), "active reservation retains both full endpoint footprints")
	runner.assert_eq(row.swept_bounds_cells, world.large_bodies.swept_bounds(BODY_ID), "active conservative bounds remain the original domain's query")
	runner.assert_eq(row.physical_bounds_px.position, Vector2(111, 113) * TileGrid.TILE_SIZE + Vector2(TileGrid.TILE_SIZE * 0.25, 0), "continuous presentation extent follows the original intermediate point")
	runner.assert_eq(row.physical_bounds_px.size, Vector2(3, 3) * TileGrid.TILE_SIZE, "movement does not inflate the physical body to its reservation")
	runner.assert_true(row.swept_bounds_cells.size.x * TileGrid.TILE_SIZE > row.physical_bounds_px.size.x, "conservative sweep and continuous presentation extent are visibly distinct contracts")
	var before: String = _facts_digest(world)
	for repeat: int in 4:
		QUERY.locate(world, REFERENCE)
	runner.assert_eq(_facts_digest(world), before, "repeated in-flight lookups do not advance, synchronize or register another source")

	# Saving deliberately settles regions. Compare queries only after that real
	# boundary, then restore its actual source/process into an independent world.
	var archive: Dictionary = JSON.parse_string(JSON.stringify(world.to_dict(), "", true, true))
	var expected: Dictionary = QUERY.locate(world, REFERENCE)
	var restored: RegionalSimulation = _world(runner)
	if restored == null:
		return
	var accepted: bool = restored.restore(archive)
	runner.assert_true(accepted, "independent world restores the real partially completed large-body step")
	if not accepted:
		return
	runner.assert_eq(QUERY.locate(restored, REFERENCE), expected, "restored source has the same detached location, geometry and clocks")
	runner.assert_true(restored.large_bodies != world.large_bodies and restored.large_bodies.world == restored, "restored query is bound to a separate actual source owner")
	var restored_before: String = _facts_digest(restored)
	QUERY.locate(restored, REFERENCE)
	runner.assert_eq(_facts_digest(restored), restored_before, "restored lookup remains read-only")
	runner.assert_true(world.advance_to_ms(18000), "original world continues its actual motion")
	var advanced: bool = restored.advance_to_ms(16000) and restored.advance_to_ms(17000) and restored.advance_to_ms(18000)
	runner.assert_true(advanced, "restored source continues through real fine-grained common-time steps")
	runner.assert_eq(QUERY.locate(restored, REFERENCE), QUERY.locate(world, REFERENCE), "fine and coarse resumed motion expose the same original source geometry and time")


func _pending_and_source_time(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	runner.assert_true(world.set_active_region("home") and world.advance_to_ms(1234), "time scenario advances a real common instant with an inactive remote village")
	var remote_ms: int = world.regions.river.elapsed_ms
	runner.assert_true(remote_ms < world.elapsed_ms, "remote original village is genuinely allowed to lag")
	runner.assert_true(not world.advance_to_ms(10000, 0), "zero work budget retains a requested uncommitted target")
	var before: String = _facts_digest(world)
	var row: Dictionary = QUERY.locate(world, REFERENCE)
	runner.assert_true(bool(row.get("ok", false)), "last committed large-body source remains queryable with backlog")
	if not bool(row.get("ok", false)):
		return
	runner.assert_true(row.world_has_backlog and not row.stale, "current source time does not imply that the requested future was committed")
	runner.assert_eq(row.owner_time_ms, 1234, "backlogged source is reported at its original committed clock")
	runner.assert_eq(row.world_time_ms, 1234, "lookup does not advance the common committed instant")
	runner.assert_eq(row.target_time_ms, 10000, "unprocessed target remains explicit")
	runner.assert_eq(world.regions.river.elapsed_ms, remote_ms, "query does not synchronize a quiet record region")
	runner.assert_eq(_facts_digest(world), before, "query preserves pending work, original regions, clocks and inventory")
	var elapsed: int = world.large_bodies.elapsed_ms
	world.large_bodies.elapsed_ms = 0
	var stale_before: String = _facts_digest(world)
	var stale: Dictionary = QUERY.locate(world, REFERENCE)
	runner.assert_true(bool(stale.get("ok", false)) and stale.stale and stale.world_has_backlog, "older source clock and retained world backlog are distinct diagnostics")
	if bool(stale.get("ok", false)):
		runner.assert_eq(stale.location_time_ms, 0, "query reports the original older source instant without repairing it")
	runner.assert_eq(_facts_digest(world), stale_before, "older source lookup does not silently synchronize its domain")
	world.large_bodies.elapsed_ms = elapsed
	for bad_time: int in [-1, world.elapsed_ms + 1]:
		world.large_bodies.elapsed_ms = bad_time
		_expect_failure(runner, world, "invalid_time", "negative or future original owner clock is explicit")
	world.large_bodies.elapsed_ms = elapsed
	var target: int = world.target_ms
	world.target_ms = world.elapsed_ms - 1
	_expect_failure(runner, world, "invalid_time", "target before the committed instant is invalid")
	world.target_ms = target
	runner.assert_eq(_facts_digest(world), before, "invalid time inspections leave all restored facts unchanged")


func _invalid_sources(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var before: String = _facts_digest(world)
	runner.assert_eq(QUERY.locate(world, {"kind": "large_body", "id": "absent"}), {"ok": false, "reason": "not_found"}, "missing large-body ID is explicit")
	for bad_reference: Variant in [{"kind": "large_body", "id": ""}, {"kind": "large_body", "id": 1}, {"kind": "large_body", "id": BODY_ID, "region": "home"}]:
		runner.assert_eq(QUERY.locate(world, bad_reference), {"ok": false, "reason": "invalid_reference"}, "malformed large-body references cannot bypass domain qualification")
	var domain: SimLargeBodies = world.large_bodies
	world.large_bodies = null
	_expect_failure(runner, world, "domain_unavailable", "absent original domain is explicit")
	world.large_bodies = SimLargeBodies.new()
	_expect_failure(runner, world, "invalid_world", "unbound source domain is rejected")
	var other: RegionalSimulation = _world(runner)
	if other == null:
		world.large_bodies = domain
		return
	world.large_bodies = other.large_bodies
	_expect_failure(runner, world, "invalid_world", "another world's source cannot be borrowed")
	world.large_bodies = domain
	var body: Dictionary = domain.bodies[BODY_ID]
	domain.bodies[BODY_ID] = null
	_expect_failure(runner, world, "invalid_location", "invalid original body record is explicit")
	domain.bodies[BODY_ID] = body
	var region: String = body.region
	body.region = "not_a_saved_region"
	_expect_failure(runner, world, "invalid_location", "missing record region is not inferred from the physical position")
	body.region = region
	var position: Array = body.position.duplicate()
	var invalid_positions: Array = [null, [], [0], [true, position[1]], [NAN, position[1]], [INF, position[1]], [-1, position[1]], [ReolWorld.WORLD_SIZE * TileGrid.TILE_SIZE, position[1]], [position[0] + 1.0, position[1]]]
	for invalid: Variant in invalid_positions:
		body.position = invalid
		_expect_failure(runner, world, "invalid_location", "invalid or off-center resting source position is not repaired")
	body.position = position
	body.step = []
	_expect_failure(runner, world, "invalid_location", "malformed current reservation is not reinterpreted")
	body.step = {}
	var form: String = domain.definitions.form
	domain.definitions.form = "missing_form"
	_expect_failure(runner, world, "invalid_location", "missing original footprint source fails before direct dereference")
	domain.definitions.form = form
	var footprint: Array = world._content.body_forms.forms[form].footprint
	world._content.body_forms.forms[form].footprint = [2, 3]
	_expect_failure(runner, world, "invalid_location", "an invalid original footprint cannot produce a query rectangle")
	world._content.body_forms.forms[form].footprint = footprint
	runner.assert_eq(_facts_digest(world), before, "rejected source inspections do not mutate or register physical facts")


func _invalid_current_leg(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	runner.assert_true(world.advance_to_ms(15400), "invalid-leg scenario first creates real partial movement")
	var body: Dictionary = world.large_bodies.bodies[BODY_ID]
	if body.step.is_empty():
		runner.assert_true(false, "real source must have an active step for invalid-leg inspection")
		return
	var before: String = _facts_digest(world)
	var step: Dictionary = body.step.duplicate(true)
	for field: String in ["started_ms", "due_ms", "duration"]:
		body.step = step.duplicate(true)
		if field == "started_ms":
			body.step.started_ms = world.elapsed_ms + 1
		elif field == "due_ms":
			body.step.due_ms = world.elapsed_ms
		else:
			body.step.due_ms += 1
		_expect_failure(runner, world, "invalid_time", "active leg rejects inconsistent original " + field)
	body.step = step.duplicate(true)
	body.step.from = [-1, 114]
	_expect_failure(runner, world, "invalid_location", "invalid active origin cannot define a sweep")
	body.step = step.duplicate(true)
	body.step.to = [114, 114]
	_expect_failure(runner, world, "invalid_location", "a non-adjacent active target cannot define an original one-step sweep")
	body.step = step.duplicate(true)
	body.step.erase("to")
	_expect_failure(runner, world, "invalid_location", "missing active target is explicit")
	body.step = step
	var position: Array = body.position.duplicate()
	body.position = [position[0] + 8.0, position[1]]
	_expect_failure(runner, world, "invalid_location", "a point inconsistent with its original committed leg is not projected or repaired")
	body.position = position
	runner.assert_eq(_facts_digest(world), before, "rejected active-leg lookups preserve the original step and all other inspected state")


func _expect_failure(runner: Object, world: RegionalSimulation, reason: String, label: String) -> void:
	runner.assert_eq(QUERY.locate(world, REFERENCE), {"ok": false, "reason": reason}, label)


func _facts_digest(world: RegionalSimulation) -> String:
	# World.to_dict intentionally settles quiet regions. Read their original
	# snapshots directly, and compare compact digests rather than dumping worlds.
	var regions: Dictionary = {}
	for region: String in world.regions:
		regions[region] = world.regions[region].to_dict()
	var snapshot: Dictionary = {
		"elapsed_ms": world.elapsed_ms, "target_ms": world.target_ms,
		"active_region": world.active_region, "work": world.simulation_work.duplicate(true),
		"boundaries": world._region_boundaries.duplicate(true), "settings": world.settings.duplicate(true),
		"regions": regions, "large_bodies": world.large_bodies.to_dict(),
		"body_forms": world._content.body_forms.duplicate(true), "body_rules": world.large_bodies.definitions.duplicate(true),
		"avian": world.avian_life.to_dict(), "artifacts": world.artifacts.to_dict(),
		"embodiment": world.embodiment.to_dict(), "field": world.field_opportunities.to_dict(),
		"construction": world.construction.to_dict(), "weather": world.weather.to_dict(),
		"services": {} if world.services == null else world.services.to_dict(),
		"routes": world.routes.duplicate(true), "couriers": world.couriers.duplicate(true),
		"shipments": world.shipments.duplicate(true), "events": world.events.duplicate(true),
		"messages": world.messages.duplicate(true), "news": world.local_news.duplicate(true),
		"cargo": world.in_transit.to_dict(), "operations": world.operations.duplicate(true),
	}
	return SnapshotValues.canonical_json(SnapshotValues.normalized(snapshot)).sha256_text()
