extends RefCounted
## Real unique-object custody and movement, with no second light/energy balance.

const RegionalFixtures = preload("res://tests/sim/test_regional_simulation.gd")
const EntityFixtures = preload("res://tests/sim/test_entity_query.gd")
const DeviceFixtures = preload("res://tests/sim/test_thermal_devices.gd")
const RoomsFixtures = preload("res://tests/sim/test_rooms_and_rest.gd")
const ARTIFACTS_PATH: String = "res://data/definitions/artifacts.json"
const CONTINUITY_PATH: String = "res://data/scenarios/world_continuity.json"
const PEARL: String = "pearl"
const SHARD: String = "shard"
const FIRE: String = "fire_stone"
var _regional := RegionalFixtures.new()
var _entity := EntityFixtures.new()
var _devices := DeviceFixtures.new()
var _rooms := RoomsFixtures.new()


class FlatMap extends WorldMapData:
	func get_terrain(cell: Vector2i) -> int:
		return TERRAIN_GRASS if in_bounds(cell) else -1

	func terrain_is_walkable(cell: Vector2i) -> bool:
		return in_bounds(cell)

	func get_elevation(cell: Vector2i) -> int:
		return 0 if in_bounds(cell) else -1

	func independent_copy() -> WorldMapData:
		return FlatMap.new()


func run(runner: Object) -> void:
	var content: ReolContentDB = _content(runner)
	if content == null:
		return
	_definition_contract(runner, content)
	_composed_weapon(runner, content)
	_custody_and_queries(runner, content)
	_stale_and_pending(runner, content)
	_source_budget(runner, content)
	_grouped_projection(runner, content)
	_real_door(runner, content)
	_motion_and_restore(runner, content)
	print("SCENARIO intrinsic light: two independent unique definitions, real custody and route, bounded additive geometry, stale/pending rejection, read-only indices and independent in-flight JSON future")


func _content(runner: Object) -> ReolContentDB:
	var disk := ReolContentDB.new()
	if not disk.load_all():
		runner.assert_true(false, "intrinsic-light fixture loads the complete source content bundle")
		return null
	var original: Dictionary = disk.content_bundle()
	var original_json: String = _json(original)
	var documents: Dictionary = original.documents.duplicate(true)
	var definitions: Dictionary = documents[ARTIFACTS_PATH]
	# Author complete definitions in the isolated candidate bundle. The fixture
	# never relies on whether the ordinary opening includes any glowing items.
	var pearl: Dictionary = definitions.types.wooden_sword.duplicate(true)
	pearl.name = "琥珀珠"
	pearl.unknown_name = "微光圆珠"
	pearl.appearance = "一颗发着柔光的圆珠。"
	pearl.method = "圆珠自身持续发光。"
	pearl.material_cue = "珠面透出微光。"
	pearl.capabilities = ["intrinsic_light"]
	pearl.storage_place = "kitchen"
	pearl["lighting"] = {"version": 1, "peak_relative": 6000, "radius_cells": 4}
	var shard: Dictionary = pearl.duplicate(true)
	shard.name = "微光碎片"
	shard.unknown_name = "浅色碎片"
	shard["lighting"] = {"version": 1, "peak_relative": 3000, "radius_cells": 2}
	definitions.types["fixture_amber_pearl"] = pearl
	definitions.types["fixture_glow_shard"] = shard
	# Bind both actual objects to the ordinary, nonthermal crystal material in
	# the same archived bundle before the current source participant is built.
	var bindings: Dictionary = documents[ReolContentDB.ENVIRONMENT_SOURCES_PATH].bindings.artifacts
	bindings["fixture_amber_pearl"] = "ordinary_crystal"
	bindings["fixture_glow_shard"] = "ordinary_crystal"
	var bundle: Dictionary = ReolContentBundle.from_documents(documents)
	var candidate := ReolContentDB.new()
	var accepted: bool = candidate.load_bundle(bundle)
	runner.assert_true(accepted, "two independently authored light types pass complete bundle and cross-domain validation")
	runner.assert_eq(_json(original), original_json, "building isolated definitions never changes the source bundle")
	if not accepted:
		return null
	runner.assert_true(str(candidate.content_bundle().digest) != str(original.digest), "the real archived bundle contains the two authored light definitions")
	runner.assert_true(candidate.artifacts.types.fixture_amber_pearl.lighting != candidate.artifacts.types.fixture_glow_shard.lighting, "two physical definitions retain independent declared emission profiles")
	return candidate


func _world(runner: Object, content: ReolContentDB, count: int = 2, remote: String = "none", with_fire: bool = false, kitchen: Vector2i = Vector2i(-1, -1)) -> RegionalSimulation:
	var regions: Dictionary = {}
	for region: String in ["home", "river"]:
		var simulation: VillageSimulation = _regional._make_village(content, region, false)
		if simulation == null:
			runner.assert_true(false, "intrinsic-light fixture builds the original " + region + " body and place owners")
			return null
		regions[region] = simulation
	if kitchen.x >= 0:
		regions.home.places.kitchen.cell = [kitchen.x, kitchen.y]
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONTINUITY_PATH))
	var world := RegionalSimulation.new()
	if not world.initialize(settings, regions, content) or not world.configure_services(content.settlement_services):
		runner.assert_true(false, "intrinsic-light fixture assembles the original regional domains: " + str(world.errors))
		return null
	world.services.set_navigation(Callable(_regional, "_path"))
	var map := FlatMap.new()
	if not map.configure_nature(content.natural_environment):
		runner.assert_true(false, "fixture terrain binds the candidate's original natural definitions")
		return null
	world.bind_map_data(map)
	world.set_active_region("")
	runner.assert_true(world.artifacts.intrinsic_light_ids().is_empty(), "the fresh unique-object authority has no issued light sources")
	var rows: Array[Dictionary] = []
	if count >= 1:
		rows.append({"id": PEARL, "definition": "fixture_amber_pearl", "region": "home", "container": "kitchen"})
	if count >= 2:
		rows.append({"id": SHARD, "definition": "fixture_glow_shard", "region": "river" if remote != "none" else "home", "container": "actor:river_player" if remote == "held" else "kitchen"})
	for index: int in range(2, count):
		rows.append({"id": "extra_%03d" % index, "definition": "fixture_amber_pearl", "region": "home", "container": "kitchen"})
	rows.append({"id": "ordinary_sword", "definition": "wooden_sword", "region": "home", "container": "kitchen"})
	if with_fire:
		rows.append({"id": FIRE, "definition": "fire_stone", "region": "home", "container": "kitchen"})
	var opening: Dictionary = {"version": 1, "experiences": {}, "objects": rows}
	if not world.artifacts.spawn_opening(opening):
		runner.assert_true(false, "opening assembler issues actual intrinsic light objects once")
		return null
	world.regions.home.set_actor_cell("player", SimRouteTravel.cell(world.regions.home.places.kitchen.cell))
	world.invalidate_region("home")
	if not world.environment_fields.activate_sources():
		runner.assert_true(false, "intrinsic-light fixture activates the actual environmental sources")
		return null
	return world


func _definition_contract(runner: Object, content: ReolContentDB) -> void:
	var definitions: Dictionary = content.artifacts.duplicate(true)
	runner.assert_true(SimArtifacts.valid_definitions(definitions), "separate intrinsic capabilities use the original strict artifact schema")
	var bads: Array[Dictionary] = []
	var bad: Dictionary = definitions.duplicate(true)
	bad.types.fixture_amber_pearl.erase("lighting")
	bads.append(bad)
	for field: String in ["version", "peak_relative", "radius_cells"]:
		for value: int in ([0, 2] if field == "version" else [0, 10001] if field == "peak_relative" else [0, 9]):
			bad = definitions.duplicate(true)
			bad.types.fixture_amber_pearl.lighting[field] = value
			bads.append(bad)
	bad = definitions.duplicate(true)
	bad.types.fixture_amber_pearl.lighting["light_balance"] = 1
	bads.append(bad)
	bad = definitions.duplicate(true)
	bad.types.fixture_amber_pearl["thermal"] = definitions.types.fire_stone.thermal.duplicate(true)
	bads.append(bad)
	bad = definitions.duplicate(true)
	bad.types.fixture_amber_pearl.capabilities = ["intrinsic_light", "intrinsic_light"]
	bads.append(bad)
	bad = definitions.duplicate(true)
	bad.types.fixture_amber_pearl.actions["enable"] = {"label": "启用", "minutes": 1, "qi": 1}
	bads.append(bad)
	bad = definitions.duplicate(true)
	bad.types.fixture_amber_pearl.actions.study.qi = 1
	bads.append(bad)
	for invalid: Dictionary in bads:
		var before: String = _json(invalid)
		runner.assert_true(not SimArtifacts.valid_definitions(invalid), "intrinsic light rejects missing, oversized or unauthorized physical/activation fields")
		runner.assert_eq(_json(invalid), before, "invalid definition checking does not repair or mutate caller content")


func _grouped_projection(runner: Object, content: ReolContentDB) -> void:
	var world: RegionalSimulation = _world(runner, content, 16)
	if world == null:
		return
	var center: Vector2i = world.artifacts.object_cell(PEARL)
	var cells: Array[Vector2i] = []
	for y: int in range(-4, 5):
		for x: int in range(-4, 5):
			cells.append(center + Vector2i(x, y))
	var sources: Dictionary = SimLocalLight._sources(world)
	var projected: Dictionary = SimLocalLight.local_patch(world, cells)
	runner.assert_true(sources.supported and projected.supported, "shared geometric projection accepts actual individually issued sources")
	if not sources.supported or not projected.supported:
		return
	var opaque: Callable = func(cell: Vector2i) -> bool: return not world.map_data.in_bounds(cell) or world.construction.blocks_sight(cell)
	for cell: Vector2i in cells:
		var sum: int = 0
		for source: Dictionary in sources.rows:
			sum += SimLightPropagation.contribution(source.cell, cell, int(source.radius), int(source.peak), opaque)
		runner.assert_eq(projected.values[cell], mini(SimLocalLight.MAX_RELATIVE, sum), "equal-source reuse preserves the individually rounded additive result, including radius tails and saturation")


func _composed_weapon(runner: Object, content: ReolContentDB) -> void:
	for capabilities: Array in [["weapon", "intrinsic_light"], ["intrinsic_light", "weapon"]]:
		var documents: Dictionary = content.content_bundle().documents
		var sword: Dictionary = documents[ARTIFACTS_PATH].types.wooden_sword
		sword.capabilities = capabilities.duplicate()
		sword["lighting"] = {"version": 1, "peak_relative": 3500, "radius_cells": 3}
		var candidate := ReolContentDB.new()
		var accepted: bool = candidate.load_bundle(ReolContentBundle.from_documents(documents))
		runner.assert_true(accepted, "a passive optical trait composes with a weapon in either order, preserving remote-draw target validation")
		if not accepted:
			continue
		var world: RegionalSimulation = _world(runner, candidate, 0)
		if world == null:
			continue
		runner.assert_true(world.artifacts.has_capability("ordinary_sword", "weapon") and world.artifacts.has_capability("ordinary_sword", "intrinsic_light"), "the same unique weapon also supplies its independent optical trait")
		runner.assert_eq(world.artifacts.intrinsic_light_ids(), ["ordinary_sword"], "composition adds the original weapon ID to the derived source index")
		var light: Dictionary = SimLocalLight.at_cell(world, world.artifacts.object_cell("ordinary_sword"))
		runner.assert_true(light.supported and int(light.artificial_relative) == 3500, "the original composite weapon emits its declared light without another object or balance")
		var invalid: Dictionary = candidate.artifacts.duplicate(true)
		invalid.types.wooden_sword.capabilities = ["thermal_exchange", "intrinsic_light"]
		runner.assert_true(not SimArtifacts.valid_definitions(invalid), "conflicting thermal-flow and intrinsic meanings cannot silently share one emission definition")


func _custody_and_queries(runner: Object, content: ReolContentDB) -> void:
	var world: RegionalSimulation = _world(runner, content)
	if world == null:
		return
	var domain: SimArtifacts = world.artifacts
	var index: Array[String] = domain.intrinsic_light_ids()
	runner.assert_eq(index, [PEARL, SHARD], "opening builds a stable sorted index of only original intrinsic sources")
	runner.assert_true(index.is_read_only(), "public derived source IDs cannot mutate the original index")
	runner.assert_true(not domain.to_dict().has("intrinsic_light_ids") and not domain.to_dict().has("_intrinsic_light_ids"), "derived light-source index is not saved as a second authority")
	for id: String in [PEARL, SHARD]:
		var object: Dictionary = domain.objects[id]
		runner.assert_eq(object.size(), 3, "an intrinsic object stores only its definition and unique location")
		runner.assert_true(not object.has("enabled") and not object.has("stored_q") and not object.has("charge"), "its light does not invent switch state or stored energy")
		runner.assert_true(domain.has_capability(id, "intrinsic_light") and not domain.has_capability(id, "thermal_exchange"), "the light capability does not become a thermal device")
		var verbs: Dictionary = domain.verbs_for(id)
		for verb: String in ["inspect", "take", "place", "study", "examine"]:
			runner.assert_true(verbs.has(verb), "the original general tool verb remains available: " + verb)
		runner.assert_eq(verbs.size(), 5, "self-glowing objects do not acquire enable, disable or combat verbs")
	var at: Vector2i = domain.object_cell(PEARL)
	runner.assert_eq(domain.object_cell(SHARD), at, "both separate issued sources occupy the real original place")
	var before: String = _facts(world)
	var point: Dictionary = SimLocalLight.local_patch(world, [at, at + Vector2i.RIGHT, at + Vector2i.RIGHT * 2, at + Vector2i.RIGHT * 4])
	runner.assert_true(bool(point.get("supported", false)), "original two-source local light query succeeds")
	if bool(point.get("supported", false)):
		runner.assert_eq(point.values[at], 9000, "distinct intrinsically luminous objects add their declared peaks")
		runner.assert_eq(point.values[at + Vector2i.RIGHT], 7875, "both independent radii use existing integer attenuation")
		runner.assert_eq(point.values[at + Vector2i.RIGHT * 2], 4500, "shorter-radius source falls off independently")
		runner.assert_eq(point.values[at + Vector2i.RIGHT * 4], 0, "the original radius boundary emits no light")
	var combined: Dictionary = SimLocalLight.at_cell(world, at)
	runner.assert_true(bool(combined.get("supported", false)), "local and natural light can be observed together")
	if bool(combined.get("supported", false)):
		@warning_ignore("integer_division")
		var expected: int = 9000 * int(combined.relative_scale) / SimLightPropagation.SCALE
		runner.assert_eq(int(combined.artificial_relative), expected, "combined observation reads the same two real sources")
	for _repeat: int in 5:
		SimLocalLight.at_cell(world, at)
		domain.intrinsic_light_ids()
	runner.assert_eq(_facts(world), before, "light and source-index observations do not change world, body, stock, heat, time or knowledge")
	for id: String in [PEARL, SHARD]:
		var source: Dictionary = world.environment_fields._sources.get_source("artifact:" + id)
		runner.assert_true(not source.is_empty(), "the actual luminous object has its authored crystal material source")
		if not source.is_empty():
			runner.assert_true(int(source.channels[5]) == 0 and int(source.channels[6]) == 0, "intrinsic light adds neither heating nor cooling to its material source")
	var projection: Dictionary = world.environment_fields.project_tenths(at, world.elapsed_ms)
	runner.assert_true(bool(projection.get("supported", false)) and int(projection.get("value", 0)) == 0, "self-light alone produces no local thermal offset")
	runner.assert_true(world.environment_fields.receipts.is_empty() and world.environment_fields.device_switches.is_empty(), "self-light creates neither a paid heat receipt nor a device switch")
	runner.assert_true(not bool(domain.begin("player", "enable", PEARL).ok), "a generic self-light cannot be switched through a thermal verb")
	runner.assert_eq(_facts(world), before, "a rejected fabricated enable changes no world state")
	var count: int = domain.objects.size()
	if not _devices._action(runner, world, "player", "take", PEARL):
		return
	runner.assert_eq(domain.objects[PEARL].container, "actor:player", "paid take transfers the original unique pearl to its real carrier")
	runner.assert_eq(domain.objects.size(), count, "taking does not clone or consume a unique object")
	runner.assert_eq(domain.intrinsic_light_ids(), index, "custody changes never create a separate source ID")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "fixture_amber_pearl"), 0, "the unique pearl is not duplicated as a quantity stack")
	var moved: Vector2i = at + Vector2i.RIGHT * 8
	world.regions.home.set_actor_cell("player", moved)
	world.invalidate_region("home")
	runner.assert_eq(domain.object_cell(PEARL), moved, "the carried original follows its body's accepted cell")
	runner.assert_eq(_light(world, at), 3000, "only the stationary shard continues illuminating the former cell")
	runner.assert_eq(_light(world, moved), 6000, "the carried pearl emits at its body's new cell")
	world.regions.home.set_actor_cell("player", at)
	world.invalidate_region("home")
	if not _devices._action(runner, world, "player", "place", PEARL):
		return
	runner.assert_eq(domain.objects[PEARL].container, "kitchen", "paid place returns the same pearl to its authored original place")
	runner.assert_eq(_light(world, at), 9000, "placing restores the two-source physical projection")
	runner.assert_eq(domain.objects.size(), count, "take, body movement and place keep one object per identity")


func _stale_and_pending(runner: Object, content: ReolContentDB) -> void:
	var pending: RegionalSimulation = _world(runner, content)
	if pending == null:
		return
	var at: Vector2i = pending.artifacts.object_cell(PEARL)
	runner.assert_true(not pending.advance_to_ms(pending.elapsed_ms + 10000, 0), "an exhausted work budget retains its actual pending world time")
	var pending_before: String = _facts(pending)
	for result: Dictionary in [SimLocalLight.local_patch(pending, [at]), SimLocalLight.at_cell(pending, at)]:
		runner.assert_true(not bool(result.get("supported", false)) and result.get("reason") == "pending_time" and not result.has("values") and not result.has("total_relative"), "pending world time yields explicit unknown rather than fabricated darkness")
	runner.assert_eq(_facts(pending), pending_before, "pending-time light queries never settle the owed work")
	var world: RegionalSimulation = _world(runner, content, 2, "held")
	if world == null:
		return
	runner.assert_true(world.set_active_region("home") and world.advance_to_ms(world.elapsed_ms + 1234), "home time advances while a far carrier is lazily scheduled")
	var remote: VillageSimulation = world.regions.river
	runner.assert_true(remote.elapsed_ms < world.elapsed_ms, "the real distant carrier has a stale committed position")
	if remote.elapsed_ms >= world.elapsed_ms:
		return
	var reference: Dictionary = SimEntityQuery.locate(world, {"kind": "artifact", "id": SHARD})
	runner.assert_true(bool(reference.get("ok", false)) and bool(reference.get("stale", false)), "the actual held shard inherits its carrier's older location timestamp")
	var before: String = _facts(world)
	var failure: Dictionary = SimLocalLight.local_patch(world, [world.artifacts.object_cell(PEARL)])
	runner.assert_true(not bool(failure.get("supported", false)) and failure.get("reason") == "unsettled_location" and not failure.has("values"), "stale carried light fails explicitly instead of projecting an old or partial position")
	runner.assert_eq(_facts(world), before, "stale-source inspection does not wake or advance the remote carrier")
	runner.assert_true(world.synchronize_region("river"), "an explicit world operation can settle the far carrier")
	runner.assert_true(bool(SimLocalLight.local_patch(world, [world.artifacts.object_cell(PEARL)]).get("supported", false)), "the same source becomes queryable after actual synchronization")
	var fixed: RegionalSimulation = _world(runner, content, 2, "fixed")
	if fixed == null:
		return
	runner.assert_true(fixed.set_active_region("home") and fixed.advance_to_ms(fixed.elapsed_ms + 1234), "a distant fixed place may also have an older village clock")
	runner.assert_true(fixed.regions.river.elapsed_ms < fixed.elapsed_ms, "the fixed-place example is actually offscreen and stale")
	var fixed_before: String = _facts(fixed)
	var fixed_at: Vector2i = fixed.artifacts.object_cell(SHARD)
	runner.assert_eq(_light(fixed, fixed_at), 3000, "an immutable placed source remains at its accepted fixed location without waking its village")
	runner.assert_eq(_facts(fixed), fixed_before, "reading a fixed far source does not synchronize its village")


func _source_budget(runner: Object, content: ReolContentDB) -> void:
	# Each fire stone is actually activated and owns one original heat flow.
	# This exercises the shared limit, not only an isolated all-intrinsic case.
	for count: int in [127, 128]:
		var world: RegionalSimulation = _world(runner, content, count, "none", true)
		if world == null:
			return
		var at: Vector2i = world.artifacts.object_cell(PEARL)
		runner.assert_eq(world.artifacts.intrinsic_light_ids().size(), count, "each unique issued luminous object occupies one derived source slot")
		if not _devices._action(runner, world, "player", "study", FIRE) or not _devices._action(runner, world, "player", "enable", FIRE):
			return
		var rates: Dictionary = world.environment_fields.device_emission_rates(world.elapsed_ms)
		runner.assert_true(bool(rates.get("supported", false)) and rates.rates.has(FIRE), "the additional thermal source is an actual active original flow")
		var before: String = _facts(world)
		var result: Dictionary = SimLocalLight.local_patch(world, [at])
		if count == 127:
			runner.assert_true(bool(result.get("supported", false)), "127 intrinsic objects plus one real thermal source fit the 128-source budget")
			if bool(result.get("supported", false)):
				runner.assert_eq(int(result.values[at]), SimLocalLight.MAX_RELATIVE, "real additive sources saturate at the declared relative-light limit")
		else:
			runner.assert_true(not bool(result.get("supported", false)) and result.get("reason") == "source_budget" and not result.has("values"), "128 intrinsic objects plus one thermal source refuse a partial result")
		runner.assert_eq(_facts(world), before, "bounded light inspection does not debit or advance any of its sources")


func _real_door(runner: Object, content: ReolContentDB) -> void:
	var world: RegionalSimulation = _world(runner, content, 2, "none", false, Vector2i(107, 108))
	if world == null:
		return
	_rooms._bind_navigation(world)
	var at: Vector2i = world.artifacts.object_cell(PEARL)
	var registration: Dictionary = world.construction.register_site("player", Vector2i(108, 106))
	runner.assert_true(bool(registration.get("ok", false)), "a real build site can border the actual luminous objects")
	if not bool(registration.get("ok", false)):
		return
	var wall: Vector2i = at + Vector2i.RIGHT
	var behind: Vector2i = at + Vector2i.RIGHT * 2
	var planned: Dictionary = world.construction.place("player", "wood_door", wall)
	runner.assert_true(bool(planned.get("ok", false)), "a neighboring real door blueprint can be placed")
	if not bool(planned.get("ok", false)):
		return
	var door: String = str(planned.project)
	var started: Dictionary = world.construction.begin("player", door)
	runner.assert_true(bool(started.get("ok", false)), "the original body begins paid door construction")
	if not bool(started.get("ok", false)):
		return
	_rooms._fixtures._finish(runner, world)
	runner.assert_true(world.construction.blocks_sight(wall), "completed closed door is the original opaque structure")
	runner.assert_true(_light(world, wall) > 0, "the door's facing surface receives real intrinsic light")
	runner.assert_eq(_light(world, behind), 0, "the same closed door blocks light behind it")
	for verb: String in ["open", "close", "demolish"]:
		var response: Dictionary = world.construction.begin("player", door, verb)
		runner.assert_true(bool(response.get("ok", false)), "door action begins through the real structure owner: " + verb)
		if not bool(response.get("ok", false)):
			return
		_rooms._fixtures._finish(runner, world)
		runner.assert_eq(_light(world, behind) > 0, verb != "close", "committed door geometry immediately changes the same intrinsic light: " + verb)


func _motion_and_restore(runner: Object, content: ReolContentDB) -> void:
	var world: RegionalSimulation = _world(runner, content)
	if world == null:
		return
	runner.assert_true(world.set_active_region("home"), "the original moving carrier's region receives each shared-time boundary")
	if not _devices._action(runner, world, "player", "take", PEARL):
		return
	var home: VillageSimulation = world.regions.home
	var origin: Vector2i = world.artifacts.object_cell(SHARD)
	var original_position: Vector2 = home.actor_position(home.actors.player)
	var began: bool = home.submit_action("player", "rest")
	runner.assert_true(began, "the real carrier starts an ordinary route using its original body")
	if not began:
		return
	world.invalidate_region("home")
	var sampled: bool = world.advance_to_ms(world.elapsed_ms + 100)
	runner.assert_true(sampled, "real shared time advances into the first continuous walking segment")
	if not sampled:
		return
	var person: Dictionary = SimEntityQuery.locate(world, {"kind": "actor", "id": "player"})
	var source: Dictionary = SimEntityQuery.locate(world, {"kind": "artifact", "id": PEARL})
	runner.assert_true(bool(person.get("ok", false)) and bool(source.get("ok", false)) and person.position != original_position, "the body has actually moved between tile centers")
	if not bool(person.get("ok", false)) or not bool(source.get("ok", false)):
		return
	runner.assert_eq(source.position, person.position, "the luminous original follows the same continuous carrier position")
	runner.assert_eq(source.cell, person.cell, "current lighting uses the actual carried source's projected cell")
	var checkpoint: Dictionary = JSON.parse_string(_json(world.to_dict()))
	var checkpoint_state: String = _json(checkpoint)
	var current_light: Dictionary = SimLocalLight.local_patch(world, [source.cell, origin])
	runner.assert_true(bool(current_light.get("supported", false)), "in-flight source has a supported current light projection")
	runner.assert_true(not checkpoint.artifacts.has("intrinsic_light_ids") and not checkpoint.artifacts.has("_intrinsic_light_ids"), "the actual save keeps only the unique source objects, not a derived ID index")
	var new_content := ReolContentDB.new()
	if not new_content.load_bundle(content.content_bundle()):
		runner.assert_true(false, "restore loads the archived, independently authored definitions")
		return
	var map := FlatMap.new()
	if not map.configure_nature(new_content.natural_environment):
		runner.assert_true(false, "independent restored terrain accepts archived definitions")
		return
	var assembly: Dictionary = ReolWorldAssemblyInputs.from_world(world, {"home": [100, 100], "river": [150, 100]})
	var restored: RegionalSimulation = WorldRestoreFactory.restore(new_content, checkpoint, assembly, map)
	runner.assert_true(restored != null, "independent candidate restores the original carried source in the middle of real travel")
	runner.assert_eq(_json(checkpoint), checkpoint_state, "candidate staging leaves the archived facts unchanged")
	if restored == null:
		return
	runner.assert_true(restored != world and restored.artifacts != world.artifacts and restored.map_data != world.map_data and restored._content != world._content, "restored source, body, map and definitions have independent owners")
	runner.assert_eq(_json(restored.to_dict()), checkpoint_state, "independent restore reproduces the complete saved world")
	runner.assert_eq(restored.artifacts.intrinsic_light_ids(), world.artifacts.intrinsic_light_ids(), "restore derives the same light-source IDs from original objects")
	runner.assert_true(restored.artifacts.intrinsic_light_ids().is_read_only(), "the restored source index is read-only too")
	runner.assert_eq(SimLocalLight.local_patch(restored, [source.cell, origin]), current_light, "restored light reads the same carried and fixed objects")
	for sim: VillageSimulation in restored.regions.values():
		sim.set_navigation(Callable(_regional, "_path"))
	if restored.services != null:
		restored.services.set_navigation(Callable(_regional, "_path"))
	var broken: Dictionary = checkpoint.duplicate(true)
	broken.artifacts.objects[PEARL]["stored_q"] = 1
	var bad_map := FlatMap.new()
	bad_map.configure_nature(new_content.natural_environment)
	var rejected: RegionalSimulation = WorldRestoreFactory.restore(new_content, broken, assembly, bad_map)
	runner.assert_true(rejected == null, "a fabricated light energy account cannot be restored as a valid source")
	runner.assert_eq(_json(world.to_dict()), checkpoint_state, "rejecting the independent invalid candidate does not alter the living source world")
	var action: Dictionary = home.actors.player.active
	if action.is_empty() or action.phase != "travel":
		runner.assert_true(false, "the checkpoint retains its actual in-flight route")
		return
	var crossing: int = SimRouteTravel.crossing_ms(action, home.actors.player, world.elapsed_ms)
	runner.assert_true(crossing > world.elapsed_ms, "the original next cell crossing lies ahead of the checkpoint")
	if crossing <= world.elapsed_ms:
		return
	runner.assert_true(world.advance_to_ms(crossing) and restored.advance_to_ms(crossing - 1) and restored.advance_to_ms(crossing), "original and independent candidate cross the real tile boundary in different slices")
	var after: Dictionary = SimEntityQuery.locate(world, {"kind": "artifact", "id": PEARL})
	runner.assert_true(bool(after.get("ok", false)) and after.cell != origin, "the actual source cell changes when its carrier crosses a tile boundary")
	if bool(after.get("ok", false)) and after.cell != origin:
		runner.assert_eq(_light(world, after.cell), 8250, "moving source peak and the stationary shard's one-cell falloff combine at the new cell")
		runner.assert_eq(_light(restored, after.cell), _light(world, after.cell), "restored source follows the same real crossing")
	var future: int = crossing + 5000
	runner.assert_true(world.advance_to_ms(future) and restored.advance_to_ms(crossing + 1234) and restored.advance_to_ms(future), "whole and sliced worlds continue their existing shared-time processes")
	runner.assert_eq(_json(restored.to_dict()), _json(world.to_dict()), "independent in-flight restore and different slices have the same complete future")


func _light(world: RegionalSimulation, cell: Vector2i) -> int:
	var result: Dictionary = SimLocalLight.local_patch(world, [cell])
	return int(result.values[cell]) if bool(result.get("supported", false)) else -1


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _facts(world: RegionalSimulation) -> String:
	# Read the actual response anchors directly. RegionalSimulation.to_dict()
	# would synchronize a stale far carrier and invalidate the query check.
	var heat: SimWorldEnvironmentFields = world.environment_fields
	var field: Dictionary = {"diagnostics": heat.diagnostics(), "activation_ms": heat.activation_ms,
		"last_ms": heat.last_ms, "last_sample_ms": heat.last_sample_ms,
		"receipts": heat.receipts, "device_switches": heat.device_switches,
		"samples": heat._samples, "transient": heat._transient}
	if heat._active:
		var sources: Dictionary = {}
		for key: String in heat._sources._records:
			var source: Dictionary = heat._sources.get_source(key)
			var cell: Vector2i = source.cell
			sources[key] = {"cell": [cell.x, cell.y], "radius": source.radius,
				"channels": Array(source.channels)}
		field["sources"] = sources
		field["index"] = heat._field.diagnostics()
		field["background"] = heat._background.snapshot()
		field["temperature"] = heat._temperature.snapshot()
		field["phases"] = heat._phases.snapshot()
	return _json({"regional": _entity._facts(world), "construction": world.construction.to_dict(),
		"weather": world.weather.to_dict(), "environment": world.environment.to_dict(), "field": field})
