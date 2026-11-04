extends RefCounted
## Joint migration validates both independent candidates before returning data.

const LEGACY_PATH: String = "res://tests/fixtures/session_v42_exchange.json"
const HEAT_PATH: String = "res://data/definitions/local_heat.json"
const VillageFixtures = preload("res://tests/sim/test_village_simulation.gd")
var _village_fixtures := VillageFixtures.new()


class MapFactory extends RefCounted:
	var calls: int = 0
	var reject: bool = false

	func create(descriptor: Dictionary) -> WorldMapData:
		calls += 1
		return null if reject else WorldMapData.from_descriptor(descriptor)


func run(runner: Object) -> void:
	var archived: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_PATH))
	var archived_before: String = _json(archived)
	var legacy_content: ReolContentDB = ReolContentDB.legacy_v42()
	runner.assert_true(legacy_content != null, "the immutable v42 bundle can still be loaded as legacy content")
	if legacy_content == null:
		return
	# Stop the existing historical chain at its real v47/v39 boundary. This is
	# still the genuine archive's domain data; no field is rewritten in place.
	var old: Dictionary = SessionSaveSchema._upgrade(archived, legacy_content)
	runner.assert_true(not old.is_empty(), "the archived v42 source reaches the original v47 envelope")
	if old.is_empty():
		return
	runner.assert_eq(int(old.schema_version), 47, "the old chain stops before fixed-reference migration")
	runner.assert_eq(int(old.continuity.world.version), 39, "the old candidate retains the original regional contract")
	var old_before: String = _json(old)
	var factory := MapFactory.new()
	var converted: Dictionary = SessionSaveSchema.upgrade(old, null, Callable(factory, "create"))
	runner.assert_true(not converted.is_empty(), "the actual historical world passes old and new independent candidates")
	if converted.is_empty():
		return
	runner.assert_true(factory.calls > 0, "old validation uses the supplied independent terrain factory")
	runner.assert_eq(int(converted.schema_version), 48, "the converted root explicitly records its new semantics")
	runner.assert_eq(int(converted.continuity.world.version), 40, "the regional writer records the fixed-reference field")
	runner.assert_eq(int(converted.continuity.world.local_heat.version), 2, "the new heat state has its own version")
	runner.assert_eq(int(converted.continuity.world.environment.version), 3, "human exposure retains its data under the signed format")
	var old_heat: Dictionary = old.continuity.world.local_heat
	var new_heat: Dictionary = converted.continuity.world.local_heat
	runner.assert_eq(int(new_heat.model_started_ms), int(old_heat.last_ms), "the fixed-reference model starts at the original saved instant")
	runner.assert_eq(new_heat.last_sample_mode, "legacy_excess", "the original historical sample keeps its old offset meaning")
	runner.assert_eq(_json(new_heat.last_sample_cells), _json(old_heat.last_sample_cells), "the historical heat slice is preserved without fabricated allocation")
	runner.assert_eq(int(new_heat.last_sample_input), int(old_heat.last_sample_input), "the historical source ledger is retained")
	runner.assert_eq(int(new_heat.last_sample_loss), int(old_heat.last_sample_loss), "the historical loss ledger is retained")
	runner.assert_eq(_json(new_heat.receipts), _json(old_heat.receipts), "the original unique heat receipts are retained")
	runner.assert_eq(int(new_heat.input_energy), int(old_heat.input_energy), "the original source input is retained")
	runner.assert_eq(int(new_heat.loss_energy), int(old_heat.loss_energy), "original loss remains an external outflow")
	runner.assert_eq(int(new_heat.ambient_in), 0, "an empty archived field creates no allocated background energy")
	var before_docs: Dictionary = old.content_bundle.documents.duplicate(true)
	var after_docs: Dictionary = converted.content_bundle.documents.duplicate(true)
	before_docs.erase(HEAT_PATH)
	after_docs.erase(HEAT_PATH)
	runner.assert_eq(_json(after_docs), _json(before_docs), "all other archived content documents remain unchanged")
	runner.assert_true(ReolContentBundle.is_valid(converted.content_bundle, ReolContentDB.DOCUMENT_PATHS), "the converted definition has a freshly verified digest")
	runner.assert_eq(int(converted.content_bundle.documents[HEAT_PATH].version), 2, "the original bound heat definition is explicitly converted")
	runner.assert_eq(_without_thermal_versions(converted), _without_thermal_versions(old), "all original nonthermal facts and sampled exposure remain unchanged")
	runner.assert_eq(_json(old), old_before, "successful migration leaves the old candidate untouched")
	runner.assert_eq(_json(archived), archived_before, "successful migration never rewrites the original historical fixture")
	_standalone(runner, old)
	_rejections(runner, old, old_before)
	print("SCENARIO thermal import: genuine archived world, bound content, original candidate validation, new independent candidate and atomic corruption rejection")


func _standalone(runner: Object, joint: Dictionary) -> void:
	# A joint village may still own inventory operations and reservations from
	# other regional domains. Removing those domains cannot make it standalone.
	var detached: Dictionary = joint.duplicate(true)
	detached.erase("continuity")
	detached.assembly = ReolWorldAssemblyInputs.standalone(detached.simulation.config)
	runner.assert_true(detached.simulation.inventory.operations.has("artifact:action:5:heat"), "the real joint archive contains an external artifact operation")
	runner.assert_true(detached.simulation.inventory.reservations.has("private_exchange:action:2:coin"), "the real joint archive contains an external exchange reservation")
	_reject(runner, detached, "a joint village detached from its original external owners")

	# Build a genuine independent simulation with its own native in-flight work;
	# do not discard operations or transfer inventory out of the joint archive.
	var sim: VillageSimulation = _village_fixtures._make_simulation(runner)
	if sim == null:
		return
	var began: bool = sim.submit_action("player", "deliver_wood")
	runner.assert_true(began, "independent village begins a real native haul")
	if not began:
		return
	var advanced: bool = sim.advance_to_ms(50)
	runner.assert_true(advanced and not sim.actors.player.active.is_empty(), "native work remains in flight at its actual fractional time")
	if not advanced or sim.actors.player.active.is_empty():
		return
	var saved: Dictionary = sim.to_dict()
	var legacy_content: ReolContentDB = ReolContentDB.legacy_v42()
	var verified: bool = legacy_content != null and VillageSimulation.from_snapshot(legacy_content, saved) != null
	runner.assert_true(verified, "the independent state validates against the archived nonthermal definitions without external inventory scope")
	if not verified:
		return
	var old: Dictionary = joint.duplicate(true)
	old.erase("continuity")
	old.simulation = saved.duplicate(true)
	# The initialized standalone sample has zero local heat. In the old format
	# its same fields had v1 positive-offset semantics; change labels only.
	old.simulation.version = 6
	old.simulation.land_resources.version = 3
	for row: Dictionary in old.simulation.land_resources.sources.values():
		if not row.ecology.is_empty():
			runner.assert_eq(int(row.ecology.heat_tenths), 0, "the generated old ecology sample has no new negative-heat history")
			row.ecology.version = 1
	old.assembly = ReolWorldAssemblyInputs.standalone(old.simulation.config)
	old.clock = {"tick_index": int(sim.tick_index),
		"total_minutes": int(legacy_content.climate.calendar.start_minutes) + int(sim.tick_index),
		"speed": 1.0, "paused": true, "elapsed_ms": int(sim.elapsed_ms),
		"frame_debt_ms": 0.0, "wait_target_ms": 0}
	old.player.cell = sim.actors.player.cell.duplicate()
	old.player.position = sim.actors.player.position.duplicate()
	old.player.altitude = 0
	old.player.motion = SimLocalMotion.legacy_state()
	old.player.motion.facing = sim.actors.player.facing.duplicate()
	# Give this standalone fixture its own real terrain, including the native
	# action's recorded route, rather than borrowing the detached joint map.
	var terrain: WorldMapData = WorldMapData.from_descriptor(WorldMapData.flat_descriptor(20261101))
	if terrain == null or not terrain.configure_nature(legacy_content.natural_environment):
		runner.assert_true(false, "independent standalone terrain binds its archived nature definitions")
		return
	var required_cells: Dictionary = {}
	for actor: Dictionary in saved.actors.values():
		required_cells[SimRouteTravel.cell(actor.cell)] = true
		for step: Array in actor.active.get("path", []):
			required_cells[SimRouteTravel.cell(step)] = true
	for place: Dictionary in saved.places.values():
		required_cells[SimRouteTravel.cell(place.cell)] = true
	var patch: Array = []
	for point: Vector2i in required_cells:
		patch.append([point.x, point.y, WorldMapData.TERRAIN_GRASS])
	if not bool(terrain.apply_terrain_patch(patch).ok):
		runner.assert_true(false, "independent standalone terrain accepts its actual actors, workplaces and route")
		return
	old.world = SessionSaveSchema.capture_world(null, SimRouteTravel.cell(old.player.cell), terrain)
	old.world_seed = int(terrain.descriptor().seed)
	var before: String = _json(old)
	var converted: Dictionary = ThermalImport.convert(old)
	runner.assert_true(not converted.is_empty(), "an independently simulated old-format village imports without a regional weather or heat field")
	if converted.is_empty():
		return
	runner.assert_true(not converted.has("continuity"), "the imported standalone village remains standalone")
	runner.assert_eq(int(converted.simulation.version), 7, "the standalone village adopts the signed nested schema")
	runner.assert_eq(int(converted.simulation.land_resources.version), 4, "the original land state is relabeled only after validation")
	runner.assert_eq(_json(converted.simulation.inventory), _json(saved.inventory), "native goods and the in-flight reservation are retained exactly")
	runner.assert_eq(_json(converted.simulation.actors.player.active), _json(saved.actors.player.active), "the independent native action is neither restarted nor completed")
	runner.assert_eq(_json(converted.simulation), _json(saved), "every standalone body, account, source and action fact is preserved")
	runner.assert_eq(int(converted.clock.elapsed_ms), 50, "the standalone archive keeps its fractional shared time")
	runner.assert_eq(_json(old), before, "standalone conversion does not mutate the old source")
	var old_herb: String = _herb_id(old.simulation.land_resources.sources)
	if not old_herb.is_empty():
		runner.assert_eq(int(converted.simulation.land_resources.sources[old_herb].ecology.version), 2, "the saved ecology sample is retained under the new format")
	var bad: Dictionary = old.duplicate(true)
	bad.simulation.land_resources.version = 4
	_reject(runner, bad, "a new standalone nested format disguised as an old archive")


func _rejections(runner: Object, old: Dictionary, before: String) -> void:
	var bad: Dictionary = old.duplicate(true)
	bad.content_bundle.digest = "invalid"
	_reject(runner, bad, "a damaged original content digest")
	bad = old.duplicate(true)
	bad.content_bundle.documents[HEAT_PATH].conductance.open = 1000
	bad.content_bundle = ReolContentBundle.from_documents(bad.content_bundle.documents)
	_reject(runner, bad, "invalid original rules with a recomputed digest")
	bad = old.duplicate(true)
	bad.continuity.world.local_heat.version = 2
	_reject(runner, bad, "a new heat state disguised as an old region")
	bad = old.duplicate(true)
	bad.continuity.world.local_heat.input_energy = 1
	_reject(runner, bad, "an unconserved original heat ledger")
	bad = old.duplicate(true)
	bad.continuity.world.local_heat.cells["1,1"] = {"cell": [1, 1], "energy": 0}
	_reject(runner, bad, "an unreceipted old source patch")
	bad = old.duplicate(true)
	var sample_id: Variant = bad.continuity.world.environment.samples.keys()[0]
	bad.continuity.world.environment.samples[sample_id].heat_tenths = -1
	_reject(runner, bad, "a negative heat value disguised as a v1 human sample")
	bad = old.duplicate(true)
	var herb: String = _herb_id(bad.continuity.world.regions.home.land_resources.sources)
	if not herb.is_empty():
		bad.continuity.world.regions.home.land_resources.sources[herb].ecology.heat_tenths = -1
		bad.simulation = bad.continuity.world.regions.home.duplicate(true)
		_reject(runner, bad, "a negative heat value disguised as a v1 ecology sample")
	else:
		runner.assert_true(false, "the historical fixture has a real home herb sample")
	bad = old.duplicate(true)
	bad.simulation.elapsed_ms = int(bad.simulation.elapsed_ms) + 1
	_reject(runner, bad, "mismatching copies of the original home simulation")
	bad = old.duplicate(true)
	bad.continuity.world.environment.version = 3
	_reject(runner, bad, "a new human format disguised as an old region")
	bad = old.duplicate(true)
	bad.continuity.world.regions.home.land_resources.version = 4
	bad.simulation = bad.continuity.world.regions.home.duplicate(true)
	_reject(runner, bad, "a current land format disguised as an old region")
	bad = old.duplicate(true)
	bad.schema_version = 48
	_reject(runner, bad, "a current root sent through the old migration entrance")
	bad = old.duplicate(true)
	bad.schema_version = 49
	runner.assert_true(SessionSaveSchema.upgrade(bad).is_empty(), "an unknown future root is rejected before consulting legacy templates")
	var factory := MapFactory.new()
	factory.reject = true
	runner.assert_true(SessionSaveSchema.upgrade(old, null, Callable(factory, "create")).is_empty(), "a failing independent terrain factory rejects the entire import")
	runner.assert_true(factory.calls > 0, "the refusal comes from the requested candidate factory")
	runner.assert_eq(_json(old), before, "every failed import leaves the original candidate untouched")


func _herb_id(sources: Dictionary) -> String:
	for id: String in sources:
		if not sources[id].ecology.is_empty():
			return id
	return ""


func _reject(runner: Object, candidate: Dictionary, label: String) -> void:
	var before: String = _json(candidate)
	runner.assert_true(ThermalImport.convert(candidate).is_empty(), "migration rejects " + label)
	runner.assert_eq(_json(candidate), before, "rejection never changes the supplied old archive")


func _without_thermal_versions(snapshot: Dictionary) -> String:
	var copy: Dictionary = snapshot.duplicate(true)
	copy.erase("schema_version")
	copy.erase("content_bundle")
	var world: Dictionary = copy.continuity.world
	world.erase("version")
	world.erase("local_heat")
	world.environment.erase("version")
	for village: Dictionary in world.regions.values():
		_strip_village_versions(village)
	_strip_village_versions(copy.simulation)
	return _json(copy)


func _strip_village_versions(village: Dictionary) -> void:
	village.erase("version")
	village.land_resources.erase("version")
	for row: Dictionary in village.land_resources.sources.values():
		if not row.ecology.is_empty():
			row.ecology.erase("version")


func _json(value: Dictionary) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
