class_name ThermalImport
extends RefCounted
## Finite import of a validated v47/v39 thermal archive. All objects below are
## independent candidates; neither the file nor the active world is changed.

const HEAT_PATH: String = "res://data/definitions/local_heat.json"
const Shape = preload("res://scripts/sim/avian_schema.gd")


static func convert(snapshot: Dictionary, restore_map_factory: Callable = Callable()) -> Dictionary:
	if not SessionSaveSchema._valid_world_fields(snapshot, 47) or not snapshot.get("clock") is Dictionary or not ReolGameClock.is_valid_state(snapshot.clock) or not snapshot.clock.has("elapsed_ms") or not snapshot.get("simulation") is Dictionary:
		return {}
	# The saved digest is checked before accessing any document. Old definitions
	# are loaded from that bundle, never from current disk templates.
	var old_content := ReolContentDB.new()
	if not old_content.load_bundle(snapshot.content_bundle, true) or not LegacyHeatV1.valid_definitions(old_content.local_heat):
		return {}
	if int(snapshot.clock.total_minutes) - int(snapshot.clock.tick_index) != int(old_content.climate.calendar.start_minutes):
		return {}
	var descriptor: Dictionary = snapshot.world.duplicate(true)
	descriptor.erase("exploration")
	descriptor.erase("terrain_overrides")
	var raw_map: Variant = restore_map_factory.call(descriptor.duplicate(true)) if restore_map_factory.is_valid() else WorldMapData.from_descriptor(descriptor)
	if not raw_map is WorldMapData or SnapshotValues.normalized(raw_map.descriptor()) != SnapshotValues.normalized(descriptor):
		return {}
	var terrain: WorldMapData = raw_map
	if not terrain.configure_nature(old_content.natural_environment) or not terrain.restore_terrain_overrides(snapshot.world.terrain_overrides):
		return {}
	var joint: bool = snapshot.has("continuity")
	var old_world: RegionalSimulation
	var old_standalone: Dictionary = {}
	if joint:
		var extra: Variant = snapshot.continuity
		if not extra is Dictionary or not extra.get("world") is Dictionary or not extra.world.get("regions") is Dictionary or not extra.world.regions.get("home") is Dictionary or not extra.get("centers") is Dictionary or not extra.get("player_journey") is Dictionary or not extra.get("known_lines") is Array:
			return {}
		for line: Variant in extra.known_lines:
			if not line is String:
				return {}
		if SnapshotValues.normalized(extra.centers) != SnapshotValues.normalized(snapshot.assembly.centers) or SnapshotValues.normalized(snapshot.simulation) != SnapshotValues.normalized(extra.world.regions.home):
			return {}
		if extra.world.get("elapsed_ms") != snapshot.clock.elapsed_ms or extra.world.get("current_time") != snapshot.clock.tick_index:
			return {}
		# The entire old candidate, including geometry, frozen slope, sources,
		# clothing, ecology and cross-domain references, must pass before Q exists.
		old_world = WorldRestoreFactory.restore(old_content, extra.world, snapshot.assembly, terrain, true)
		if old_world == null:
			return {}
	else:
		# No regional thermal or weather state exists in a standalone archive.
		# Validate its original ecology and village without fabricating either.
		old_standalone = _village_v2_copy(snapshot.simulation)
		if old_standalone.is_empty() or not snapshot.assembly.region_configs.has("home") or not SimLandResources.opening_matches(RegionalSimulation._base_workplace_config(old_standalone.config), RegionalSimulation._base_workplace_config(snapshot.assembly.region_configs.home)) or old_standalone.get("elapsed_ms") != snapshot.clock.elapsed_ms or old_standalone.get("tick_index") != snapshot.clock.tick_index:
			return {}
		if VillageSimulation.from_snapshot(old_content, old_standalone) == null:
			return {}
	# Only now convert the bound heat definition; all other documents are copied
	# byte-for-value and a new digest covers precisely the converted bundle.
	var new_rules: Dictionary = SimLocalHeat.upgrade_definitions_v1(old_content.local_heat)
	if new_rules.is_empty():
		return {}
	var documents: Dictionary = snapshot.content_bundle.documents.duplicate(true)
	documents[HEAT_PATH] = new_rules
	var bundle: Dictionary = ReolContentBundle.from_documents(documents)
	if bundle.is_empty() or not ReolContentBundle.is_valid(bundle, ReolContentDB.DOCUMENT_PATHS):
		return {}
	var new_content := ReolContentDB.new()
	if not new_content.load_bundle(bundle):
		return {}
	var result: Dictionary = snapshot.duplicate(true)
	result.schema_version = 48
	result.content_bundle = bundle
	if joint:
		var next_heat := SimLocalHeat.new()
		if not next_heat.initialize(old_world, new_rules):
			return {}
		next_heat.set_geometry(old_world.construction.thermal_roofed, old_world.construction.thermal_barrier)
		var converted_heat: Dictionary = next_heat.import_v1(old_world.local_heat, old_world)
		if converted_heat.is_empty():
			return {}
		var regional: Dictionary = result.continuity.world
		regional.version = 40
		regional.environment.version = 3
		regional.local_heat = converted_heat
		for id: String in regional.regions:
			var village: Dictionary = _village_v2_copy(regional.regions[id])
			if village.is_empty():
				return {}
			regional.regions[id] = village
		result.simulation = _village_v2_copy(result.simulation)
		if result.simulation.is_empty():
			return {}
		# Reconstruct and cross-check every domain a second time under the new
		# definitions; the temporary legacy candidate is never published.
		if WorldRestoreFactory.restore(new_content, regional, result.assembly, terrain) == null:
			return {}
	else:
		result.simulation = old_standalone
		if VillageSimulation.from_snapshot(new_content, result.simulation) == null:
			return {}
	return result if SessionSaveSchema.is_valid_world(result) else {}


static func _village_v2_copy(source: Variant) -> Dictionary:
	if not source is Dictionary or source.get("version") != 6 or not source.get("config") is Dictionary or not source.get("land_resources") is Dictionary or source.land_resources.get("version") != 3 or not source.land_resources.get("sources") is Dictionary:
		return {}
	for row: Variant in source.land_resources.sources.values():
		if not row is Dictionary or not row.get("ecology") is Dictionary:
			return {}
		var ecology: Dictionary = row.ecology
		if ecology.is_empty():
			continue
		if ecology.get("version") != 1 or not Shape.count(ecology.get("heat_tenths"), 0, SimInventory.MAX_COUNT - 10000) or not Shape.count(ecology.get("temperature_tenths"), -10000, SimInventory.MAX_COUNT):
			return {}
		var background: int = int(ecology.temperature_tenths) - int(ecology.heat_tenths)
		if background < -10000 or background > 10000:
			return {}
	var result: Dictionary = source.duplicate(true)
	result.version = 7
	result.land_resources.version = 4
	for row: Dictionary in result.land_resources.sources.values():
		if not row.ecology.is_empty():
			row.ecology.version = 2
	return result
