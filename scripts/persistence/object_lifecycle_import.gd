class_name ObjectLifecycleImport
extends RefCounted
## Import a genuine root50/region41 into root51/region42. A legacy archive did
## not record free ground slots or lifecycle operations; never invent them.


static func convert(snapshot: Dictionary, restore_map_factory: Callable = Callable()) -> Dictionary:
	if not SessionSaveSchema._valid_solar_envelope(snapshot, 50):
		return {}
	if not snapshot.get("clock") is Dictionary or not ReolGameClock.is_valid_state(snapshot.clock) or not snapshot.clock.has("elapsed_ms") or not snapshot.get("simulation") is Dictionary:
		return {}
	var content := ReolContentDB.new()
	if not content.load_bundle(snapshot.content_bundle):
		return {}
	if int(snapshot.clock.total_minutes) - int(snapshot.clock.tick_index) != int(content.climate.calendar.start_minutes):
		return {}
	var descriptor: Dictionary = snapshot.world.duplicate(true)
	descriptor.erase("exploration")
	descriptor.erase("terrain_overrides")
	var raw_map: Variant = restore_map_factory.call(descriptor.duplicate(true)) if restore_map_factory.is_valid() else WorldMapData.from_descriptor(descriptor)
	if not raw_map is WorldMapData or SnapshotValues.normalized(raw_map.descriptor()) != SnapshotValues.normalized(descriptor):
		return {}
	var terrain: WorldMapData = raw_map
	if not terrain.configure_nature(content.natural_environment) or not terrain.restore_terrain_overrides(snapshot.world.terrain_overrides):
		return {}
	if not _player_shape(snapshot, terrain):
		return {}
	var joint: bool = snapshot.has("continuity")
	if joint:
		var extra: Dictionary = snapshot.continuity
		var regional: Dictionary = extra.world
		if not regional.get("regions") is Dictionary or not regional.regions.get("home") is Dictionary or not extra.get("centers") is Dictionary or not extra.get("player_journey") is Dictionary or not extra.get("known_lines") is Array:
			return {}
		for line: Variant in extra.known_lines:
			if not line is String:
				return {}
		if SnapshotValues.normalized(extra.centers) != SnapshotValues.normalized(snapshot.assembly.centers) or SnapshotValues.normalized(snapshot.simulation) != SnapshotValues.normalized(regional.regions.home):
			return {}
		if regional.get("elapsed_ms") != snapshot.clock.elapsed_ms or regional.get("current_time") != snapshot.clock.tick_index:
			return {}
		# Region41 is independently restored through its explicit empty-domain
		# compatibility path. The input remains the actual old archive.
		if WorldRestoreFactory.restore(content, regional, snapshot.assembly, terrain) == null:
			return {}
	else:
		if not snapshot.simulation.get("config") is Dictionary or not snapshot.assembly.region_configs.has("home") or not SimLandResources.opening_matches(RegionalSimulation._base_workplace_config(snapshot.simulation.config), RegionalSimulation._base_workplace_config(snapshot.assembly.region_configs.home)) or snapshot.simulation.get("elapsed_ms") != snapshot.clock.elapsed_ms or snapshot.simulation.get("tick_index") != snapshot.clock.tick_index:
			return {}
		if VillageSimulation.from_snapshot(content, snapshot.simulation) == null:
			return {}
	var result: Dictionary = snapshot.duplicate(true)
	result.schema_version = 51
	if joint:
		result.continuity.world["object_lifecycle"] = {"version": 1, "ground": {"version": 1, "slots": {}}, "receipts": {}, "created": {}, "actions": {}}
		result.continuity.world.version = 42
		# The preceding independent region41 restore already converts exactly
		# these two fields and validates the resulting empty lifecycle candidate.
		# Do not restore that identical candidate a second time in every legacy
		# import. No other world fact changed here, and nothing is installed.
	return result if SessionSaveSchema.is_valid_world(result) else {}


static func _player_shape(snapshot: Dictionary, terrain: WorldMapData) -> bool:
	var player: Variant = snapshot.get("player")
	var simulation: Dictionary = snapshot.simulation
	if not player is Dictionary or not SimAvianLife.Schema.cell_valid(player.get("cell")) or not SnapshotValues.number_pair(player.get("position")) or not SnapshotValues.valid_integer(player.get("altitude"), 0) or float(player.altitude) > 2.0:
		return false
	if simulation.get("controlled_actor") != "player" or not simulation.get("actors") is Dictionary or not simulation.actors.get("player") is Dictionary:
		return false
	var body: Dictionary = simulation.actors.player
	if not SimLocalMotion._vector(body.get("facing")) or not body.get("active") is Dictionary:
		return false
	var motion := SimLocalMotion.new()
	if not motion.valid_state(player.get("motion"), int(snapshot.clock.elapsed_ms)):
		return false
	var facing := Vector2(float(player.motion.facing[0]), float(player.motion.facing[1]))
	if not facing.is_equal_approx(SimRouteTravel.facing(body)) or not player.motion.action.is_empty() and not body.active.is_empty():
		return false
	var cell := Vector2i(int(player.cell[0]), int(player.cell[1]))
	var point := Vector2(float(player.position[0]), float(player.position[1]))
	var body_point: Variant = SimStorageQuery.actor_position(body)
	return body_point is Vector2 and point.is_equal_approx(body_point) and terrain.terrain_is_walkable(cell) and TileGrid.world_to_cell(point) == cell
