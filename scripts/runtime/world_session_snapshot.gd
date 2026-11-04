class_name WorldSessionSnapshot
extends RefCounted
## Joint session serialization and candidate validation, without mutating live state.
## Internal collaborator of WorldContinuityRuntime; file I/O remains SimSaveStore.


static func capture(adapter: Node) -> Dictionary:
	var home: VillageRuntime = adapter.home_runtime()
	var context: Dictionary = home.snapshot_context()
	var player: PlayerCharacter = context.player
	# Regional capture first settles all regions at one commit point, including
	# a quiet home region while the player is visiting elsewhere.
	var world_snapshot: Dictionary = adapter.world_sim.to_dict()
	return SnapshotValues.for_save({
		"schema_version": SessionSaveSchema.VERSION, "world_seed": ReolWorld.WORLD_SEED,
		"content_bundle": context.content.content_bundle(),
		"avatar_subject": adapter.avatar_subject,
		"world": SessionSaveSchema.capture_world(context.fog, adapter.controlled_cell()),
		"simulation": home.simulation.to_dict(), "clock": GameClock.to_dict(),
		"player": {"cell": [player.cell.x, player.cell.y],
			"position": [player.motion.position.x, player.motion.position.y], "altitude": player.altitude,
			"motion": player.motion.to_dict()},
		"continuity": {"world": world_snapshot, "centers": _encoded_centers(adapter.centers),
			"player_journey": adapter.player_journey.duplicate(true), "known_lines": adapter.known_lines()},
	})


static func stage(adapter: Node, snapshot: Dictionary) -> Dictionary:
	var home_runtime: VillageRuntime = adapter.home_runtime()
	var context: Dictionary = home_runtime.snapshot_context()
	var player: PlayerCharacter = context.player
	snapshot = SessionSaveSchema.upgrade(snapshot)
	if not SessionSaveSchema.is_valid_world(snapshot) or not snapshot.get("continuity") is Dictionary:
		return {}
	var content := ReolContentDB.new()
	if not content.load_bundle(snapshot.content_bundle):
		return {}
	# Build the independent map before even the first saved-position check.
	# The factory preserves explicit test maps; no query uses the live view.
	var candidate_map: WorldMapData = adapter.world_sim.map_data.independent_copy()
	if not candidate_map.configure_nature(content.natural_environment):
		return {}
	if not home_runtime.valid_snapshot(snapshot, candidate_map):
		return {}
	if int(snapshot.clock.total_minutes) - int(snapshot.clock.tick_index) != int(content.climate.calendar.start_minutes):
		return {}
	var extra: Dictionary = snapshot.continuity
	if not extra.get("world") is Dictionary or not extra.get("centers") is Dictionary or not extra.get("player_journey") is Dictionary or not extra.get("known_lines") is Array:
		return {}
	if SnapshotValues.normalized(extra.centers) != SnapshotValues.normalized(_encoded_centers(adapter.centers)):
		return {}
	for line: Variant in extra.known_lines:
		if not line is String:
			return {}
	# Initialize the candidate using independent baseline instances, since live
	# far regions may intentionally be behind the committed world clock.
	var candidates: Dictionary = {}
	for id: String in adapter.world_sim.regions:
		var source: VillageSimulation = adapter.world_sim.regions[id]
		var cells: Dictionary = {}
		for actor_id: String in source.actors:
			cells[actor_id] = source.actors[actor_id].cell.duplicate()
		var candidate := VillageSimulation.new()
		# Preserve the immutable content baseline even after loading a world
		# from before natural sources existed. Only the optional room policy
		# follows its matching live layout; restore supplies the saved facts.
		var configuration: Dictionary = RegionalSimulation._base_workplace_config(adapter.world_sim.opening_config(id))
		if source.config.has("workplaces_version"):
			configuration["workplaces_version"] = source.config.workplaces_version
			configuration.actions["workspace_return"] = source.config.actions.workspace_return.duplicate(true)
		if not candidate.initialize(content, configuration, cells, source.places):
			return {}
		# Keep every baseline owner at its genuine opening time. Moving only
		# the village clock would leave newly initialized source processes at
		# zero, and could price their first cache against an invented history.
		# The full independent restore below supplies all real saved clocks.
		candidates[id] = candidate
	var restored := RegionalSimulation.new()
	if not restored.initialize(adapter.settings, candidates, content):
		return {}
	restored.bind_map_data(candidate_map)
	if adapter.world_sim.services != null and not restored.configure_services(content.settlement_services):
		return {}
	if not restored.restore(extra.world):
		return {}
	# Site destinations belong to this candidate's own received/observed
	# knowledge. The live session may have learnt a place after this archive.
	if not _valid_journey(adapter, extra.player_journey, _cell(snapshot.player.cell), int(snapshot.clock.elapsed_ms), candidate_map, restored):
		return {}
	if not restored.construction.space_valid():
		return {}
	if not restored.large_bodies.space_valid():
		return {}
	if not _valid_workplace_routes(restored, snapshot, extra, candidate_map):
		return {}
	for sim: VillageSimulation in restored.regions.values():
		for body: Dictionary in sim.actors.values():
			if bool(body.alive) and restored.large_bodies.blocked(SimRouteTravel.cell(body.cell)):
				return {}
	if not _valid_avatar(str(snapshot.avatar_subject), restored, snapshot, extra):
		return {}
	var travelling: bool = not extra.player_journey.is_empty()
	var manual_action: bool = not snapshot.player.motion.action.is_empty()
	var velocity := Vector2(float(snapshot.player.motion.velocity[0]), float(snapshot.player.motion.velocity[1]))
	var moving: bool = not velocity.is_zero_approx()
	if int(snapshot.player.altitude) != 0 and restored.conflicts.owns_actor("player"):
		return {}
	if (int(snapshot.player.altitude) != 0 or velocity != Vector2.ZERO) and restored.artifacts.active.get("player", {}).get("verb", "") in ["use_research", "draw"]:
		return {}
	if (int(snapshot.player.altitude) != 0 or velocity != Vector2.ZERO) and restored.private_exchange.owns_actor("player"):
		return {}
	if travelling and restored.owns_for_scope("player", &"journey"):
		return {}
	if manual_action and restored.owns_for_scope("player", &"manual_action"):
		return {}
	if moving and restored.owns_for_scope("player", &"stationary"):
		return {}
	var walking: Dictionary = restored.conflicts.walking_projection("player")
	var speed: float = velocity.length()
	if moving and speed > float(player.motion.rules.motion.speed) * float(walking.speed_fraction) + 0.001:
		return {}
	if int(snapshot.clock.wait_target_ms) != 0 and restored.owns_for_scope("player", &"wait"):
		return {}
	if not extra.player_journey.is_empty() and not restored.actor_controls("player", "motion"):
		return {}
	if not snapshot.player.motion.action.is_empty():
		if travelling or not restored.actor_controls("player", "action") or not restored.actor_controls("player", "motion") or int(snapshot.clock.wait_target_ms) != 0:
			return {}
	if int(snapshot.clock.wait_target_ms) != 0 and not Vector2(float(snapshot.player.motion.velocity[0]), float(snapshot.player.motion.velocity[1])).is_zero_approx():
		return {}
	var home: VillageSimulation = restored.regions.home
	if restored.elapsed_ms != int(snapshot.clock.elapsed_ms) or SnapshotValues.normalized(home.to_dict()) != SnapshotValues.normalized(snapshot.simulation):
		return {}
	if not home_runtime.matches_snapshot_world(home, candidate_map) or not _valid_remote_terrain(adapter, restored.regions.river, candidate_map):
		return {}
	for id: String in restored.avian_life.birds:
		if int(restored.avian_life.birds[id].altitude) == 0 and not candidate_map.terrain_is_walkable(restored.avian_life.body_cell(id)):
			return {}
		if int(restored.avian_life.birds[id].altitude) == 0 and restored.large_bodies.blocked(restored.avian_life.body_cell(id)):
			return {}
	if _cell(home.actors.player.cell) != _cell(snapshot.player.cell) or not home.actor_position(home.actors.player).is_equal_approx(Vector2(float(snapshot.player.position[0]), float(snapshot.player.position[1]))):
		return {}
	if not SimRouteTravel.facing(home.actors.player).is_equal_approx(Vector2(float(snapshot.player.motion.facing[0]), float(snapshot.player.motion.facing[1]))):
		return {}
	if not extra.player_journey.is_empty() and not SimRouteTravel.valid_segment(extra.player_journey, home.actors.player, restored.elapsed_ms, float(player.motion.rules.motion.speed)):
		return {}
	return {"world": restored, "map": candidate_map, "content": content, "snapshot": snapshot}


static func _valid_workplace_routes(world: RegionalSimulation, snapshot: Dictionary, extra: Dictionary, terrain: WorldMapData) -> bool:
	var rooms: Array[Dictionary] = []
	for sim: VillageSimulation in world.regions.values():
		if not SimWorkplaces.valid_places(sim.places, sim.config, terrain):
			return false
		if sim.config.has("workplaces_version"):
			rooms.append(sim.places)
	if rooms.is_empty():
		return true
	var routes: Array = [extra.player_journey.get("path", [])]
	for sim: VillageSimulation in world.regions.values():
		for places: Dictionary in rooms:
			if not SimWorkplaces.actors_clear(places, sim.actors):
				return false
	if world.services != null:
		for actor: String in world.services.active_jobs:
			routes.append(world.services.jobs[world.services.active_jobs[actor]].get("path", []))
	for sim: VillageSimulation in world.regions.values():
		for actor: String in sim.actors:
			routes.append(world.field_opportunities.route_projection(actor).get("path", []))
	for path: Array in routes:
		for raw: Array in path:
			for places: Dictionary in rooms:
				if SimWorkplaces.blocked(places, SimRouteTravel.cell(raw)):
					return false
	for places: Dictionary in rooms:
		if SimWorkplaces.blocked(places, SimRouteTravel.cell(snapshot.player.cell)):
			return false
	return true


static func _valid_avatar(subject: String, world: RegionalSimulation, snapshot: Dictionary, extra: Dictionary) -> bool:
	# Exactly one opening life is manual. The former human's autonomous life is
	# part of this saved world, rather than another secretly controlled avatar.
	for id: String in world.avian_life.birds:
		if bool(world.avian_life.birds[id].autonomous) == (subject == SimAvianLife.subject_id(id)):
			return false
	var manual_soul: String = str(world.soul_vessels.agency.manual)
	var former_free: bool = world.activity_previous_autonomy("player") or bool(world.regions.home.actors.player.autonomous)
	if (not manual_soul.is_empty()) != subject.begins_with("subject:soul:"):
		return false
	if subject == world.embodiment.subject_for_actor("player"):
		# An occupied body is temporarily nonautonomous. Its saved owner must
		# also restore it as manual when this is the selected human life.
		return not former_free
	if subject.begins_with("subject:soul:"):
		var soul_id: String = subject.trim_prefix("subject:soul:")
		var soul_former_free: bool = former_free or bool(world.soul_vessels.agency.errands.get("player", {}).get("previous_autonomous", false))
		if manual_soul != soul_id or not world.soul_vessels.residents.has(soul_id) or not soul_former_free:
			return false
		return extra.player_journey.is_empty() and snapshot.player.motion.action.is_empty() and Vector2(float(snapshot.player.motion.velocity[0]), float(snapshot.player.motion.velocity[1])).is_zero_approx()
	if not subject.begins_with("subject:avian:"):
		return false
	var id: String = subject.trim_prefix("subject:avian:")
	if not world.avian_life.birds.has(id) or not former_free or world.embodiment.residence_of(subject) != SimAvianLife.carrier_id(id):
		return false
	return extra.player_journey.is_empty() and snapshot.player.motion.action.is_empty() and Vector2(float(snapshot.player.motion.velocity[0]), float(snapshot.player.motion.velocity[1])).is_zero_approx()


static func _valid_journey(adapter: Node, journey: Dictionary, start: Vector2i, now: int, terrain: WorldMapData, candidate: RegionalSimulation = null) -> bool:
	if journey.is_empty():
		return true
	if not journey.get("destination") is String or not journey.get("path") is Array:
		return false
	var destination: String = str(journey.destination)
	var site: Dictionary = {}
	if destination.begins_with("site:"):
		if candidate == null or not SimEmbodiment._keys(journey, ["destination", "path", "due_ms", "segment_started_ms", "segment_from"]):
			return false
		site = candidate.field_opportunities.destination("player", destination.trim_prefix("site:"))
		if site.is_empty():
			return false
	elif not adapter.centers.has(destination):
		return false
	if not SnapshotValues.valid_integer(journey.get("due_ms"), 1) or not SnapshotValues.valid_integer(journey.get("segment_started_ms"), 0) or not SnapshotValues.number_pair(journey.get("segment_from")) or int(journey.due_ms) <= now or int(journey.segment_started_ms) > now:
		return false
	var current: Vector2i = start
	for raw: Variant in journey.path:
		if not SnapshotValues.number_pair(raw, true):
			return false
		var next: Vector2i = _cell(raw)
		var delta: Vector2i = next - current
		if absi(delta.x) > 1 or absi(delta.y) > 1 or not terrain.terrain_can_step(current, delta):
			return false
		current = next
	if journey.has("target"):
		if not SnapshotValues.number_pair(journey.target, true):
			return false
		return current == _cell(journey.target) and terrain.terrain_is_walkable(current)
	return current == _cell(site.cell) and terrain.terrain_is_walkable(current) if not site.is_empty() else current == adapter.centers[destination]


static func _valid_remote_terrain(adapter: Node, sim: VillageSimulation, terrain: WorldMapData) -> bool:
	var expected: VillageSimulation = adapter.world_sim.regions.river
	if sim.actors.size() != expected.actors.size() or sim.places.size() != expected.places.size():
		return false
	for id: String in expected.actors:
		if not sim.actors.has(id) or sim.actors[id].definition_id != expected.actors[id].definition_id:
			return false
	for id: String in expected.places:
		# Saved places own their geometry. A new opening may choose a different
		# office footprint; pricing an old archive against it rejects valid saves.
		if not sim.places.has(id) or not sim.places[id].get("label") is String:
			return false
	for actor: Dictionary in sim.actors.values():
		var current: Vector2i = _cell(actor.cell)
		if not terrain.terrain_is_walkable(current):
			return false
		var action: Dictionary = actor.active
		for raw: Array in action.get("path", []):
			var next: Vector2i = _cell(raw)
			var direction: Vector2i = next - current
			if absi(direction.x) > 1 or absi(direction.y) > 1 or not terrain.terrain_can_step(current, direction):
				return false
			current = next
		if not action.is_empty() and current != _cell(sim.places[action.destination].cell):
			return false
	for place: Dictionary in sim.places.values():
		if not terrain.terrain_is_walkable(_cell(place.cell)) or _cell(place.cell).distance_to(adapter.centers.river) > float(sim.config.navigation_radius):
			return false
	if not SimWorkplaces.valid_places(sim.places, sim.config, terrain):
		return false
	return true


static func _encoded_centers(centers: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in centers:
		var cell: Vector2i = centers[id]
		result[id] = [cell.x, cell.y]
	return result


static func _cell(raw: Array) -> Vector2i:
	return Vector2i(int(raw[0]), int(raw[1]))
