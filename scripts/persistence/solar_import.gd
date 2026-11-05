class_name SolarImport
extends RefCounted
## Root49's original climate and complete simulation are proved before the
## immutable v1 content is converted to the single current solar contract.

const CLIMATE_PATH: String = "res://data/definitions/climate.json"


static func convert(snapshot: Dictionary, restore_map_factory: Callable = Callable()) -> Dictionary:
	if not SessionSaveSchema._valid_world_fields(snapshot, 49) or not snapshot.get("clock") is Dictionary or not ReolGameClock.is_valid_state(snapshot.clock) or not snapshot.clock.has("elapsed_ms") or not snapshot.get("simulation") is Dictionary:
		return {}
	# Validate the archived digest and exact old climate, rather than replacing
	# its definitions with the current files. The legacy flag exists solely for
	# this independent candidate and requires climate v1, not either version.
	var old_content := ReolContentDB.new()
	if not old_content.load_bundle(snapshot.content_bundle, false, false, true):
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
	if joint:
		var extra: Variant = snapshot.continuity
		if not extra is Dictionary or not extra.get("world") is Dictionary or extra.world.get("version") != 41 or not extra.world.get("environment") is Dictionary or extra.world.environment.get("version") != 3 or extra.world.environment.get("rules_version") != 1 or not extra.world.get("regions") is Dictionary or not extra.world.regions.get("home") is Dictionary or not extra.get("centers") is Dictionary or not extra.get("player_journey") is Dictionary or not extra.get("known_lines") is Array:
			return {}
		for line: Variant in extra.known_lines:
			if not line is String:
				return {}
		if SnapshotValues.normalized(extra.centers) != SnapshotValues.normalized(snapshot.assembly.centers) or SnapshotValues.normalized(snapshot.simulation) != SnapshotValues.normalized(extra.world.regions.home):
			return {}
		if extra.world.get("elapsed_ms") != snapshot.clock.elapsed_ms or extra.world.get("current_time") != snapshot.clock.tick_index:
			return {}
		# This restores the original current-heat state against v1 climate, with
		# all original ledgers, sampled exposures and domain references intact.
		if WorldRestoreFactory.restore(old_content, extra.world, snapshot.assembly, terrain) == null:
			return {}
	else:
		if not snapshot.simulation.get("config") is Dictionary or not snapshot.assembly.region_configs.has("home") or not SimLandResources.opening_matches(RegionalSimulation._base_workplace_config(snapshot.simulation.config), RegionalSimulation._base_workplace_config(snapshot.assembly.region_configs.home)) or snapshot.simulation.get("elapsed_ms") != snapshot.clock.elapsed_ms or snapshot.simulation.get("tick_index") != snapshot.clock.tick_index:
			return {}
		if VillageSimulation.from_snapshot(old_content, snapshot.simulation) == null:
			return {}
	# New solar is a fixed import rule, not information inferred from an old
	# save or read from current disk. Temperature rules and every other document
	# retain their archived values. Only the digest of this new bundle changes.
	var climate: Dictionary = old_content.climate.duplicate(true)
	climate.version = 2
	climate["solar"] = SimSolarRules.migration_defaults()
	if not SimClimateRules.valid_definitions(climate):
		return {}
	var documents: Dictionary = snapshot.content_bundle.documents.duplicate(true)
	documents[CLIMATE_PATH] = climate
	var bundle: Dictionary = ReolContentBundle.from_documents(documents)
	var new_content := ReolContentDB.new()
	if bundle.is_empty() or not new_content.load_bundle(bundle):
		return {}
	var result: Dictionary = snapshot.duplicate(true)
	result.schema_version = 50
	result.content_bundle = bundle
	if joint:
		result.continuity.world.environment.rules_version = 2
		# Revalidate a fresh independent world; no previous simulation or live
		# owner is ever committed by this conversion.
		if WorldRestoreFactory.restore(new_content, result.continuity.world, result.assembly, terrain) == null:
			return {}
	elif VillageSimulation.from_snapshot(new_content, result.simulation) == null:
		return {}
	# Solar's historical output is root50; the session entry point applies the
	# separate root50 -> root51 lifecycle import only after this proof succeeds.
	return result if SessionSaveSchema._valid_solar_envelope(result, 50) else {}
