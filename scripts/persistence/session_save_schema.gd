class_name SessionSaveSchema
extends RefCounted
## Explicit migrations at the session boundary. No file I/O or live mutations.

const VERSION: int = 48


static func capture_world(fog: FogOfWar, focus: Vector2i, terrain: WorldMapData = null) -> Dictionary:
	var state: Dictionary = terrain.descriptor() if terrain != null else WorldMapData.generation_descriptor()
	state["terrain_overrides"] = terrain.terrain_overrides() if terrain != null else []
	if fog != null:
		fog.set_focus(focus)
		fog.update_now()
	state["exploration"] = FogOfWar.empty_exploration() if fog == null else fog.exploration_to_dict()
	return state


static func upgrade(source: Dictionary, _content: ReolContentDB = null, restore_map_factory: Callable = Callable()) -> Dictionary:
	# A pre-bundle archive cannot prove which external templates it originally
	# used. All legacy migrations use the recorded v42 compatibility baseline.
	# Modern archives must be complete; no missing-pack fallback is permitted.
	var version: Variant = source.get("schema_version")
	# Array membership distinguishes int/float in this engine; a JSON whole
	# number must follow the same version path as its in-memory integer value.
	if not ReolGameClock._integer(version) or int(version) < 1 or int(version) > VERSION:
		return {}
	if version == VERSION:
		return _upgrade(source, null)
	var old: Dictionary = {}
	if version == 47 or version == 46 or version == 45 or version == 44 or version == 43:
		old = _upgrade(source, null)
	else:
		if source.has("content_bundle") or source.has("assembly"):
			return {}
		var content: ReolContentDB = ReolContentDB.legacy_v42()
		if content == null:
			return {}
		old = _upgrade(source, content)
	# Load the importer only at the historical boundary: the importer builds
	# independent candidates and calls back into current envelope validation.
	return {} if old.is_empty() else load("res://scripts/persistence/thermal_import.gd").convert(old, restore_map_factory)


static func _upgrade(source: Dictionary, content: ReolContentDB) -> Dictionary:
	var version: Variant = source.get("schema_version")
	if not (version is int or version is float) or not is_finite(float(version)):
		return {}
	if version == VERSION:
		# A current envelope must already contain current regional state. The
		# standalone regional loader also accepts legacy data, but invoking its
		# compatibility path here would let a damaged modern save erase history.
		if source.has("continuity"):
			if not source.continuity is Dictionary or not source.continuity.get("world") is Dictionary or source.continuity.world.get("version") != RegionalSimulation.SCHEMA_VERSION:
				return {}
		return source if is_valid_world(source) else {}
	if version == 47:
		# Historical migrations stop at their actual last regional version.
		# The thermal importer validates the old candidate before conversion.
		if source.has("continuity"):
			if not source.continuity is Dictionary or not source.continuity.get("world") is Dictionary or source.continuity.world.get("version") != 39:
				return {}
		return source if _valid_world_fields(source, 47) else {}
	if version == 46:
		if not _valid_world_fields(source, 46):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if source.has("continuity"):
			if not source.continuity is Dictionary or not source.continuity.get("world") is Dictionary:
				return {}
			updated.continuity.world = RegionalSimulation.upgrade_heat_amounts(source.continuity.world)
			if updated.continuity.world.is_empty():
				return {}
		updated.schema_version = 47
		return _upgrade(updated, null)
	if version == 45:
		# This format had no mutable substrate. Only a genuine old envelope may
		# gain an empty overlay; current archives must already carry the field.
		if not _valid_world_fields(source, 45):
			return {}
		if source.has("continuity") and (not source.continuity is Dictionary or not source.continuity.get("world") is Dictionary or source.continuity.world.get("version") != 38):
			return {}
		var updated: Dictionary = source.duplicate(true)
		updated.world["terrain_overrides"] = []
		updated.schema_version = 46
		return _upgrade(updated, null)
	if version == 44:
		# Older envelopes only knew the exact original generator. A new flat map
		# cannot masquerade as an older save by changing the root version tag.
		if not _valid_world_fields(source, 44):
			return {}
		if source.has("continuity") and (not source.continuity is Dictionary or not source.continuity.get("world") is Dictionary or source.continuity.world.get("version") != 38):
			return {}
		var updated: Dictionary = source.duplicate(true)
		updated.schema_version = 45
		return _upgrade(updated, null)
	if version == 43:
		# The saved bundle is already authoritative. Construct only from the
		# configurations, settings and centers recorded in this archive.
		if not _valid_world_fields(source, 43) or source.has("assembly"):
			return {}
		var assembly: Dictionary = {}
		if source.has("continuity"):
			if not source.continuity is Dictionary or not source.continuity.get("world") is Dictionary or source.continuity.world.get("version") != 38:
				return {}
			assembly = ReolWorldAssemblyInputs.from_saved(source.continuity.world, source.continuity.get("centers"))
		else:
			if not source.get("simulation") is Dictionary:
				return {}
			assembly = ReolWorldAssemblyInputs.standalone(source.simulation.get("config"))
		if assembly.is_empty():
			return {}
		var updated: Dictionary = source.duplicate(true)
		updated["assembly"] = assembly
		updated.schema_version = 44
		return _upgrade(updated, null)
	if version == 42:
		if not _valid_world_fields(source, 42) or source.has("content_bundle") or content == null:
			return {}
		if source.has("continuity") and (not source.continuity is Dictionary or not source.continuity.get("world") is Dictionary or source.continuity.world.get("version") != 38):
			return {}
		var updated: Dictionary = source.duplicate(true)
		updated["content_bundle"] = content.content_bundle()
		updated.schema_version = 43
		return _upgrade(updated, content)
	if version == 41:
		if not _valid_world_fields(source, 41):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
				return {}
			updated.continuity.world = RegionalSimulation.upgrade_private_exchange(updated.continuity.world)
			if updated.continuity.world.is_empty():
				return {}
		updated.schema_version = 42
		return _upgrade(updated, content)
	if version == 40:
		if not _valid_world_fields(source, 40):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
				return {}
			updated.continuity.world = RegionalSimulation.upgrade_ring_use(updated.continuity.world)
			if updated.continuity.world.is_empty():
				return {}
		updated.schema_version = 41
		return _upgrade(updated, content)
	if version == 39:
		if not _valid_world_fields(source, 39):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
				return {}
			updated.continuity.world = RegionalSimulation.upgrade_field_opportunities(updated.continuity.world)
			if updated.continuity.world.is_empty():
				return {}
		updated.schema_version = 40
		return _upgrade(updated, content)
	if version == 38:
		if not _valid_world_fields(source, 38):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
				return {}
			updated.continuity.world = RegionalSimulation.upgrade_capability_practice(updated.continuity.world)
			if updated.continuity.world.is_empty():
				return {}
		updated.schema_version = 39
		return _upgrade(updated, content)
	if version == 37:
		if not _valid_world_fields(source, 37):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
				return {}
			updated.continuity.world = RegionalSimulation.upgrade_source_care(updated.continuity.world)
			if updated.continuity.world.is_empty():
				return {}
		updated.schema_version = 38
		return _upgrade(updated, content)
	if version == 36:
		if not _valid_world_fields(source, 36):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
				return {}
			updated.continuity.world = RegionalSimulation.upgrade_site_affairs(updated.continuity.world)
			if updated.continuity.world.is_empty():
				return {}
		updated.schema_version = 37
		return _upgrade(updated, content)
	if version == 35:
		if not _valid_world_fields(source, 35):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
				return {}
			updated.continuity.world = RegionalSimulation.upgrade_conflict_perception(updated.continuity.world)
			if updated.continuity.world.is_empty():
				return {}
		updated.schema_version = 36
		return _upgrade(updated, content)
	if version == 34:
		if not _valid_world_fields(source, 34):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
				return {}
			updated.continuity.world = RegionalSimulation.upgrade_conflicts(updated.continuity.world)
			if updated.continuity.world.is_empty():
				return {}
		updated.schema_version = 35
		return _upgrade(updated, content)
	if version == 33:
		if not _valid_world_fields(source, 33) or content == null:
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
				return {}
			var regional: Dictionary = updated.continuity.world
			if regional.get("version") != 29 or regional.has("spirit_sources") or not regional.get("regions") is Dictionary or not ReolGameClock._integer(regional.get("elapsed_ms")):
				return {}
			var initial_sources: Dictionary = SimSpiritSources.empty_state(int(regional.elapsed_ms), content.spirit_sources, regional.regions).sources
			# Keep the historical v1 top-level shape independent of future live
			# source fields. No old checkpoints or source transactions existed.
			var legacy_sources: Dictionary = {"version": 1, "rules_version": int(content.spirit_sources.version),
				"activation_ms": int(regional.elapsed_ms), "last_ms": int(regional.elapsed_ms), "sources": initial_sources,
				"active": {}, "records": {}, "qi_baselines": {}, "charge_baselines": {}, "next_id": 1}
			regional["spirit_sources"] = legacy_sources
			regional.version = 30
		updated.schema_version = 34
		return _upgrade(updated, content)
	if version == 32:
		return _upgrade_herb_ecology(source, content)
	if version == 31:
		return _upgrade_local_heat(source, content)
	if version == 30:
		return _upgrade_body_facing(source, content)
	if version == 29:
		if not _valid_world_fields(source, 29):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
				return {}
			var regional: Dictionary = updated.continuity.world
			if regional.get("version") != 26 or regional.has("environment") or not ReolGameClock._integer(regional.get("elapsed_ms")):
				return {}
			# This historical step must keep its original v1 shape even after
			# the live environment's empty_state gains new local-heat fields.
			regional["environment"] = {"version": 1, "rules_version": 1,
				"activation_ms": int(regional.elapsed_ms), "last_pulse_ms": int(regional.elapsed_ms), "samples": {}}
			regional.version = 27
		updated.schema_version = 30
		return _upgrade(updated, content)
	if version == 28:
		if not _valid_world_fields(source, 28):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary or updated.continuity.world.get("version") != 25 or updated.continuity.world.has("health"):
				return {}
			var regional: Dictionary = updated.continuity.world
			if not regional.get("artifacts") is Dictionary or not SimInventory._valid_count(regional.artifacts.get("next_id"), false):
				return {}
			regional["health"] = {"version": 1, "source_floor": int(regional.artifacts.next_id), "next_id": 1, "wounds": {}, "jobs": {}}
			regional.version = 26
		updated.schema_version = 29
		return _upgrade(updated, content)
	if version == 27:
		if not _valid_world_fields(source, 27):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary or updated.continuity.world.get("version") != 24 or updated.continuity.world.has("clothing"):
				return {}
			updated.continuity.world["clothing"] = SimClothing.empty_state()
			updated.continuity.world.version = 25
		updated.schema_version = 28
		return _upgrade(updated, content)
	if version == 26:
		if not _valid_world_fields(source, 26) or content == null:
			return {}
		var updated: Dictionary = source.duplicate(true)
		if not updated.get("simulation") is Dictionary or not SimAutonomousLivelihood.install(updated.simulation.get("config"), content.autonomous_livelihood):
			return {}
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
				return {}
			var regional: Dictionary = updated.continuity.world
			if regional.get("version") != 23 or regional.has("autonomous_livelihood") or not regional.get("regions") is Dictionary:
				return {}
			for sim: Variant in regional.regions.values():
				if not sim is Dictionary or not SimAutonomousLivelihood.install(sim.get("config"), content.autonomous_livelihood):
					return {}
			regional["autonomous_livelihood"] = SimAutonomousLivelihood.empty_state()
			regional.version = 24
		updated.schema_version = 27
		return _upgrade(updated, content)
	if version == 25:
		if not _valid_world_fields(source, 25):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary or updated.continuity.world.get("version") != 22 or updated.continuity.world.has("budgeted_labor"):
				return {}
			var regional: Dictionary = updated.continuity.world
			regional["budgeted_labor"] = SimBudgetedLabor.empty_state()
			regional.version = 23
			if regional.has("services"):
				if not regional.services is Dictionary or regional.services.get("version") != 4:
					return {}
				regional.services.version = 5
		updated.schema_version = 26
		return _upgrade(updated, content)
	if version == 24:
		if not _valid_world_fields(source, 24) or content == null:
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
				return {}
			var regional: Dictionary = updated.continuity.world
			if regional.get("version") != 21 or regional.has("personal_production"):
				return {}
			regional["personal_production"] = SimPersonalProduction.empty_state()
			if regional.has("services"):
				var service: Variant = regional.services
				if not service is Dictionary or not service.get("definitions") is Dictionary or not service.definitions.get("trade") is Dictionary or not service.definitions.trade.get("offers") is Dictionary:
					return {}
				var offer: Variant = content.local_trade.offers.get("sell_dried_herb")
				if not offer is Dictionary or service.definitions.trade.offers.has("sell_dried_herb") and not SimPersonalProduction.Shape.same_record(service.definitions.trade.offers.sell_dried_herb, offer):
					return {}
				# A future procurement policy, never invented cash, goods or orders.
				service.definitions.trade.offers["sell_dried_herb"] = offer.duplicate(true)
			regional.version = 22
		updated.schema_version = 25
		return _upgrade(updated, content)
	if version == 23:
		if not _valid_world_fields(source, 23):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary or updated.continuity.world.get("version") != 20 or updated.continuity.world.has("large_bodies") or not ReolGameClock._integer(updated.continuity.world.get("elapsed_ms")):
				return {}
			updated.continuity.world["large_bodies"] = SimLargeBodies.empty_state(int(updated.continuity.world.elapsed_ms))
			updated.continuity.world.version = 21
		updated.schema_version = 24
		return _upgrade(updated, content)
	if version == 22:
		if not _valid_world_fields(source, 22):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary or updated.continuity.world.get("version") != 19 or updated.continuity.world.has("method_records"):
				return {}
			updated.continuity.world["method_records"] = SimMethodRecords.empty_state()
			updated.continuity.world.version = 20
		updated.schema_version = 23
		return _upgrade(updated, content)
	if version == 21:
		if not _valid_world_fields(source, 21):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary or updated.continuity.world.get("version") != 18 or updated.continuity.world.has("standing_work"):
				return {}
			updated.continuity.world["standing_work"] = SimStandingWork.empty_state()
			updated.continuity.world.version = 19
		updated.schema_version = 22
		return _upgrade(updated, content)
	if version == 20:
		return _upgrade_entrusted_goods(source, content)
	if version == 19:
		return _upgrade_personal_foraging(source, content)
	if version == 18:
		return _upgrade_trade(source, content)
	if version == 17:
		return _upgrade_weather(source, content)
	if version == 16:
		if not _valid_world_fields(source, 16):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary or updated.continuity.world.get("version") != 13 or updated.continuity.world.has("resting"):
				return {}
			updated.continuity.world["resting"] = SimResting.empty_state()
			updated.continuity.world["version"] = 14
		updated["schema_version"] = 17
		return _upgrade(updated, content)
	if version == 15:
		if not _valid_world_fields(source, 15):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary or updated.continuity.world.get("version") != 12 or updated.continuity.world.has("construction"):
				return {}
			updated.continuity.world["construction"] = SimConstruction.empty_state()
			updated.continuity.world.construction.version = 1
			updated.continuity.world["version"] = 13
		updated["schema_version"] = 16
		return _upgrade(updated, content)
	if version == 14:
		if not _valid_world_fields(source, 14):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary or updated.continuity.world.get("version") != 11 or updated.continuity.world.has("heat_methods") or not updated.continuity.world.get("artifacts") is Dictionary or updated.continuity.world.artifacts.get("version") != 3:
				return {}
			updated.continuity.world["heat_methods"] = SimHeatMethods.empty_state()
			updated.continuity.world["version"] = 12
			updated.continuity.world.artifacts["version"] = 4
		updated["schema_version"] = 15
		return _upgrade(updated, content)
	if version == 13:
		if not _valid_world_fields(source, 13) or content == null:
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary or updated.continuity.world.get("version") != 10 or updated.continuity.world.has("admissions"):
				return {}
			updated.continuity.world["version"] = 11
			updated.continuity.world["admissions"] = SimSocialAdmission.empty_state(int(content.social_admission.seed))
		updated["schema_version"] = 14
		return _upgrade(updated, content)
	if version == 12:
		if not _valid_world_fields(source, 12):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary or updated.continuity.world.get("version") != 9 or not updated.continuity.world.get("soul_vessels") is Dictionary:
				return {}
			var souls: Dictionary = updated.continuity.world.soul_vessels
			if souls.get("version") != 1 or souls.has("agency"):
				return {}
			souls["version"] = 2
			souls["agency"] = SimSoulAgency.empty_state()
			updated.continuity.world["version"] = 10
		updated["schema_version"] = 13
		return _upgrade(updated, content)
	if version == 11:
		if not _valid_world_fields(source, 11):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary or updated.continuity.world.get("version") != 8 or updated.continuity.world.has("soul_vessels") or not ReolGameClock._integer(updated.continuity.world.get("elapsed_ms")):
				return {}
			updated.continuity.world["version"] = 9
			updated.continuity.world["soul_vessels"] = SimSoulVessels.empty_state(int(updated.continuity.world.elapsed_ms))
			updated.continuity.world.soul_vessels.version = 1
			updated.continuity.world.soul_vessels.erase("agency")
		updated["schema_version"] = 12
		return _upgrade(updated, content)
	if version == 10:
		return _upgrade_resources(source, content)
	if version == 9:
		if not _valid_world_fields(source, 9):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary or updated.continuity.world.get("version") != 6 or not updated.continuity.world.get("artifacts") is Dictionary:
				return {}
			var artifacts: Dictionary = updated.continuity.world.artifacts
			if artifacts.get("version") != 2 or artifacts.has("experiences") or not artifacts.get("objects") is Dictionary or not artifacts.get("active") is Dictionary or not artifacts.get("events") is Array:
				return {}
			for item: Variant in artifacts.objects.values():
				if not item is Dictionary or item.has("damage"):
					return {}
				item["damage"] = 0
			for job: Variant in artifacts.active.values():
				if not job is Dictionary or job.has("recipient"):
					return {}
				job["recipient"] = ""
			for event: Variant in artifacts.events:
				if not event is Dictionary or event.has("recipient"):
					return {}
				event["recipient"] = ""
			artifacts["experiences"] = {}
			artifacts["version"] = 3
			updated.continuity.world["version"] = 7
		updated["schema_version"] = 10
		return _upgrade(updated, content)
	if version == 8:
		if not _valid_world_fields(source, 8) or source.has("avatar_subject"):
			return {}
		var updated: Dictionary = source.duplicate(true)
		updated["avatar_subject"] = "subject:player"
		updated["schema_version"] = 9
		return _upgrade(updated, content)
	if version == 7:
		if not _valid_world_fields(source, 7):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary or updated.continuity.world.get("version") != 5 or updated.continuity.world.has("avian_life") or not ReolGameClock._integer(updated.continuity.world.get("elapsed_ms")):
				return {}
			updated.continuity.world["version"] = 6
			updated.continuity.world["avian_life"] = SimAvianLife.empty_state(int(updated.continuity.world.elapsed_ms))
		updated["schema_version"] = 8
		return _upgrade(updated, content)
	if version == 6:
		if not _valid_world_fields(source, 6):
			return {}
		var updated: Dictionary = source.duplicate(true)
		if updated.has("continuity"):
			if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary or updated.continuity.world.get("version") != 4 or updated.continuity.world.has("sparring"):
				return {}
			updated.continuity.world["version"] = 5
			updated.continuity.world["sparring"] = SimSparring.empty_state()
		updated["schema_version"] = 7
		return _upgrade(updated, content)
	if version != 1 and version != 2 and version != 3 and version != 4 and version != 5:
		return {}
	var migrated: Dictionary = source.duplicate(true)
	if version == 1:
		if source.has("world") or source.get("world_seed") != WorldMapData.legacy_descriptor().seed:
			return {}
		var world: Dictionary = WorldMapData.legacy_descriptor()
		# Old saves never recorded footprints: do not infer a journey's exploration.
		world["exploration"] = FogOfWar.empty_exploration()
		migrated["world"] = world
		migrated["schema_version"] = 2
	if migrated.schema_version == 2:
		if not _valid_world_fields(migrated, 2):
			return {}
		# Modern damaged saves cannot bypass validation by changing only a version.
		if migrated.has("continuity"):
			if not migrated.continuity is Dictionary or not migrated.continuity.get("world") is Dictionary:
				return {}
			var regional: Dictionary = migrated.continuity.world
			if regional.get("version") != 1 or regional.has("embodiment") or not regional.get("regions") is Dictionary:
				return {}
			var actors: Array[String] = []
			for region: Variant in regional.regions.values():
				if not region is Dictionary or not region.get("actors") is Dictionary:
					return {}
				for actor: Variant in region.actors:
					if not actor is String or actor.is_empty() or actors.has(actor):
						return {}
					actors.append(actor)
			actors.sort()
			regional["embodiment"] = SimEmbodiment.legacy_state(actors)
			regional["version"] = 2
		migrated["schema_version"] = 3
	if migrated.schema_version == 3:
		if not _valid_world_fields(migrated, 3):
			return {}
		if migrated.has("continuity"):
			if not migrated.continuity is Dictionary or not migrated.continuity.get("world") is Dictionary:
				return {}
			var regional: Dictionary = migrated.continuity.world
			if regional.get("version") != 2 or regional.has("artifacts"):
				return {}
			# Old worlds had no object instances or investigations.
			# Fix the actual v1 shape here; a newer empty_state may gain fields.
			regional["artifacts"] = {"version": 1, "objects": {}, "active": {}, "events": [], "next_id": 1}
			regional["version"] = 3
		migrated["schema_version"] = 4
	if migrated.schema_version == 4:
		if not _valid_world_fields(migrated, 4) or not migrated.get("clock") is Dictionary or not migrated.get("player") is Dictionary or migrated.player.has("motion"):
			return {}
		var clock: Dictionary = ReolGameClock.upgrade_legacy(migrated.clock)
		if clock.is_empty():
			return {}
		migrated["clock"] = clock
		migrated.player["motion"] = SimLocalMotion.legacy_state()
		migrated["schema_version"] = 5
	if not _valid_world_fields(migrated, 5) or content == null or not migrated.get("simulation") is Dictionary or not migrated.get("clock") is Dictionary or not ReolGameClock.is_valid_state(migrated.clock):
		return {}
	var allowed: Dictionary = {}
	if migrated.has("continuity"):
		if not migrated.continuity is Dictionary or not migrated.continuity.get("world") is Dictionary:
			return {}
		var regional: Dictionary = migrated.continuity.world
		if regional.get("version") != 3 or regional.has("elapsed_ms") or regional.has("target_ms") or not regional.get("regions") is Dictionary:
			return {}
		if not regional.regions.has("home") or JSON.stringify(migrated.simulation, "", true, true) != JSON.stringify(regional.regions.home, "", true, true) or int(regional.current_time) != int(migrated.clock.tick_index):
			return {}
		for region: Variant in regional.regions.values():
			if not region is Dictionary or not region.get("actors") is Dictionary:
				return {}
			for id: String in region.actors:
				allowed[id] = true
		var now: int = int(migrated.clock.elapsed_ms)
		for id: String in regional.regions:
			var next: Dictionary = LifeTimeMigration.village(regional.regions[id], content, allowed)
			if next.is_empty():
				return {}
			# Legacy minute domains stopped at the start of this minute. Their
			# partial-minute future begins at the captured precise session time.
			next.elapsed_ms = now
			for actor: Dictionary in next.actors.values():
				if not actor.active.is_empty():
					var offset: int = now - int(regional.current_time) * 60000
					actor.active.segment_started_ms = int(actor.active.segment_started_ms) + offset
					actor.active.due_ms = int(actor.active.due_ms) + offset
			regional.regions[id] = next
		regional["version"] = 4
		regional["elapsed_ms"] = now
		regional["target_ms"] = maxi(now, int(regional.target_time) * 60000)
		migrated.simulation = regional.regions.home.duplicate(true)
	else:
		migrated.simulation = LifeTimeMigration.village(migrated.simulation, content)
		if migrated.simulation.is_empty():
			return {}
		# Single-settlement v5 saves also captured a precise clock above their
		# minute-native life domain. Anchor its unplayed partial minute once.
		var now: int = int(migrated.clock.elapsed_ms)
		var offset: int = now - int(migrated.simulation.elapsed_ms)
		migrated.simulation.elapsed_ms = now
		for actor: Dictionary in migrated.simulation.actors.values():
			if not actor.active.is_empty():
				actor.active.segment_started_ms = int(actor.active.segment_started_ms) + offset
				actor.active.due_ms = int(actor.active.due_ms) + offset
	if not migrated.get("player") is Dictionary or not migrated.player.get("position") is Array:
		return {}
	# Exact player position existed in old sessions but not in their actor body.
	# Preserve it; native legacy journeys started from cell centres by design.
	migrated.simulation.actors.player.position = migrated.player.position.duplicate()
	if not migrated.player.motion.action.is_empty():
		var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SimLocalMotion.RULES_PATH))
		migrated.simulation.actors.player.exertion_until_ms = int(migrated.player.motion.action.started_ms) + int(rules.sidestep.prepare_ms) + int(rules.sidestep.travel_ms) + int(rules.sidestep.recover_ms) + int(rules.recovery.delay_ms)
	if migrated.has("continuity"):
		migrated.continuity.world.regions.home.actors.player.position = migrated.player.position.duplicate()
		migrated.continuity.world.regions.home.actors.player.exertion_until_ms = migrated.simulation.actors.player.exertion_until_ms
		var regional: Dictionary = migrated.continuity.world
		var now: int = int(migrated.clock.elapsed_ms)
		if regional.get("services") is Dictionary:
			var services: Dictionary = regional.services
			if services.get("version") != 1:
				return {}
			services.version = 2
			services["last_ms"] = now
			for job: Dictionary in services.jobs.values():
				job["started_ms"] = int(job.started) * 60000
				var body: Dictionary = regional.regions[job.home].actors[job.actor]
				job["segment_started_ms"] = now
				job["segment_from"] = body.position.duplicate()
				job["due_ms"] = maxi(now + 1, int(job.next_at) * 60000)
				if job.status == "active" and job.phase == "travel":
					SimRouteTravel.begin_segment(job, body, now, float(_motion_rules().motion.speed))
				job.erase("next_at")
		if not regional.get("artifacts") is Dictionary or regional.artifacts.get("version") != 1:
			return {}
		regional.artifacts.version = 2
		for job: Dictionary in regional.artifacts.active.values():
			job["started_ms"] = int(job.started) * 60000
			job["due_ms"] = int(job.due) * 60000
			job.erase("started")
			job.erase("due")
		for event: Dictionary in regional.artifacts.events:
			event["started_ms"] = int(event.started) * 60000
			event["at_ms"] = int(event.at) * 60000
			event.erase("started")
		var journey: Dictionary = migrated.continuity.player_journey
		if not journey.is_empty():
			if not journey.has("remaining") or journey.has("due_ms"):
				return {}
			var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SimLocalMotion.RULES_PATH))
			SimRouteTravel.begin_segment(journey, regional.regions.home.actors.player, now, float(rules.motion.speed))
			journey.erase("remaining")
	migrated["schema_version"] = 6
	return _upgrade(migrated, content)


static func _upgrade_resources(source: Dictionary, content: ReolContentDB) -> Dictionary:
	if content == null or not _valid_world_fields(source, 10) or not source.get("simulation") is Dictionary:
		return {}
	var updated: Dictionary = source.duplicate(true)
	var allowed: Dictionary = {}
	if updated.has("continuity"):
		if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
			return {}
		var regional: Dictionary = updated.continuity.world
		if regional.get("version") != 7 or not regional.get("regions") is Dictionary or not regional.regions.has("home"):
			return {}
		if JSON.stringify(updated.simulation, "", true, true) != JSON.stringify(regional.regions.home, "", true, true):
			return {}
		for region: Variant in regional.regions.values():
			if not region is Dictionary or not region.get("actors") is Dictionary:
				return {}
			for id: String in region.actors:
				allowed[id] = true
		for region: Dictionary in regional.regions.values():
			if not SimSnapshotSchema.validate(region, content, allowed, false, true):
				return {}
			region["version"] = 3
			region["land_resources"] = {"version": 1, "sources": {}}
		regional["version"] = 8
		updated.simulation = regional.regions.home.duplicate(true)
	else:
		if not SimSnapshotSchema.validate(updated.simulation, content, {}, false, true):
			return {}
		updated.simulation["version"] = 3
		updated.simulation["land_resources"] = {"version": 1, "sources": {}}
	updated["schema_version"] = 11
	return _upgrade(updated, content)


static func _upgrade_herb_ecology(source: Dictionary, content: ReolContentDB) -> Dictionary:
	if not _valid_world_fields(source, 32) or content == null:
		return {}
	var updated: Dictionary = source.duplicate(true)
	if updated.has("continuity"):
		if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
			return {}
		var regional: Dictionary = updated.continuity.world
		if regional.get("version") != 28 or not regional.get("regions") is Dictionary or not regional.regions.has("home") or not ReolGameClock._integer(regional.get("elapsed_ms")):
			return {}
		if JSON.stringify(updated.get("simulation"), "", true, true) != JSON.stringify(regional.regions.home, "", true, true):
			return {}
		if not regional.get("weather") is Dictionary or not regional.get("local_heat") is Dictionary or not regional.local_heat.get("cells") is Dictionary:
			return {}
		for sim: Variant in regional.regions.values():
			if not _activate_herb_ecology(sim, content, regional.weather, regional.local_heat):
				return {}
		regional.version = 29
		updated.simulation = regional.regions.home.duplicate(true)
	else:
		# Very old standalone villages have no new sources to activate. Do not
		# invent a weather history, water or a herb garden in those worlds.
		if not _activate_herb_ecology(updated.get("simulation"), content, {}, {}):
			return {}
	updated.schema_version = 33
	return _upgrade(updated, content)


static func _activate_herb_ecology(sim: Variant, content: ReolContentDB, weather: Dictionary, heat: Dictionary) -> bool:
	if not sim is Dictionary or sim.get("version") != 5 or not sim.get("config") is Dictionary or not sim.config.get("actions") is Dictionary or not sim.get("places") is Dictionary or not SimInventory._valid_count(sim.get("elapsed_ms")):
		return false
	if sim.config.actions.has("irrigate_herb"):
		return false
	var conditions: Dictionary = {}
	for id: String in sim.config.get("resource_sources", {}):
		var source: Variant = sim.config.resource_sources[id]
		if not source is Dictionary or source.get("definition") != "wild_herbs":
			continue
		if id != "herb_slope" or not sim.places.get(source.get("place")) is Dictionary or not SimLocalMotion._vector(sim.places[source.place].get("cell")) or weather.is_empty():
			return false
		var raw: Array = sim.places[source.place].cell
		var point := Vector2i(int(raw[0]), int(raw[1]))
		var key: String = "%d,%d" % [point.x, point.y]
		var warmth: int = 0
		if heat.cells.has(key):
			if not heat.cells[key] is Dictionary or not SimInventory._valid_count(heat.cells[key].get("energy")):
				return false
			@warning_ignore("integer_division")
			warmth = int(heat.cells[key].energy) / int(content.local_heat.capacity_per_tenth)
		conditions[id] = RegionalSimulation.herb_conditions_for(content, weather, point, int(sim.elapsed_ms), warmth)
		if conditions[id].is_empty():
			return false
	var land: Dictionary = SimLandResources.upgrade_state(sim.get("land_resources", {}), sim.config, content.land_resources, int(sim.elapsed_ms), conditions)
	if land.is_empty():
		return false
	# This historical addition predates signed ecology v2. Current factories
	# must not silently stamp future nested versions into a v33 candidate.
	land.version = 3
	for source: Dictionary in land.sources.values():
		if not source.ecology.is_empty():
			source.ecology.version = 1
	if not conditions.is_empty():
		# This is the historical v33 addition, not a replacement with today's
		# whole scenario. All existing settings and work remain untouched.
		sim.config.actions["irrigate_herb"] = {"label": "浇灌野药", "kind": "irrigate", "target": "garden",
			"resource": "herb_slope", "item": "water", "amount": 1, "minutes": 2, "contribution": 0}
	sim.land_resources = land
	sim.version = 6
	return true


static func _upgrade_local_heat(source: Dictionary, content: ReolContentDB) -> Dictionary:
	if not _valid_world_fields(source, 31):
		return {}
	var updated: Dictionary = source.duplicate(true)
	if updated.has("continuity"):
		if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
			return {}
		var regional: Dictionary = updated.continuity.world
		if regional.get("version") != 27 or regional.has("local_heat") or not ReolGameClock._integer(regional.get("elapsed_ms")):
			return {}
		var exposure: Variant = regional.get("environment")
		if not LegacyHeatV1.Shape.keys(exposure, ["version", "rules_version", "activation_ms", "last_pulse_ms", "samples"]) or exposure.version != 1 or not exposure.samples is Dictionary:
			return {}
		# Preserve all real prior exposure, including a sample followed by a
		# partially completed dressing action. Only the new heat term is zero:
		# no old source existed, and no past interval is sampled or repriced.
		for sample: Variant in exposure.samples.values():
			if not LegacyHeatV1.Shape.keys(sample, ["at_ms", "cell", "region", "temperature_tenths", "garments", "insulation_tenths", "energy_rate"]):
				return {}
			sample["heat_tenths"] = 0
		exposure.version = 2
		var at_ms: int = int(regional.elapsed_ms)
		regional["local_heat"] = {"version": 1, "rules_version": 1, "activation_ms": at_ms, "last_ms": at_ms,
			"segment_started_ms": at_ms, "cells": {}, "flows": [], "input_energy": 0,
			"loss_energy": 0, "receipts": {}, "last_sample_ms": at_ms,
			"last_sample_cells": {}, "last_sample_input": 0, "last_sample_loss": 0}
		regional.version = 28
	updated.schema_version = 32
	return _upgrade(updated, content)


static func _upgrade_body_facing(source: Dictionary, content: ReolContentDB) -> Dictionary:
	if not _valid_world_fields(source, 30) or not source.get("player") is Dictionary or not source.player.get("motion") is Dictionary:
		return {}
	var raw: Variant = source.player.motion.get("facing")
	if not SimLocalMotion._vector(raw):
		return {}
	var heading := Vector2(float(raw[0]), float(raw[1]))
	if absf(heading.length() - 1.0) > 0.001:
		return {}
	var updated: Dictionary = source.duplicate(true)
	if updated.has("continuity"):
		if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
			return {}
		var regional: Dictionary = updated.continuity.world
		if regional.get("version") != 27 or not regional.get("regions") is Dictionary or not regional.regions.has("home"):
			return {}
		# Both copies describe the same home body. Never conceal a damaged
		# original snapshot by overwriting one from the other during migration.
		if JSON.stringify(updated.get("simulation"), "", true, true) != JSON.stringify(regional.regions.home, "", true, true):
			return {}
		for sim: Variant in regional.regions.values():
			if not _add_body_facing(sim):
				return {}
		if not regional.regions.home.actors.has("player"):
			return {}
		regional.regions.home.actors.player.facing = raw.duplicate()
		updated.simulation = regional.regions.home.duplicate(true)
	else:
		if not _add_body_facing(updated.get("simulation")) or not updated.simulation.actors.has("player"):
			return {}
		updated.simulation.actors.player.facing = raw.duplicate()
	updated.schema_version = 31
	return _upgrade(updated, content)


static func _add_body_facing(sim: Variant) -> bool:
	if not sim is Dictionary or sim.get("version") != 4 or not sim.get("actors") is Dictionary:
		return false
	for body: Variant in sim.actors.values():
		if not body is Dictionary or body.has("facing"):
			return false
		# There is no record of an old idle NPC's last heading. Give it a
		# deterministic initial orientation rather than inventing a past walk.
		body["facing"] = [0.0, 1.0]
	sim.version = 5
	return true


static func is_valid_world(snapshot: Dictionary) -> bool:
	return _valid_world_fields(snapshot, VERSION)


static func _upgrade_weather(source: Dictionary, content: ReolContentDB) -> Dictionary:
	if not _valid_world_fields(source, 17) or content == null:
		return {}
	var updated: Dictionary = source.duplicate(true)
	if not _upgrade_rain_source(updated.get("simulation")):
		return {}
	if updated.has("continuity"):
		if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
			return {}
		var regional: Dictionary = updated.continuity.world
		if regional.get("version") != 14 or regional.has("weather") or not regional.get("construction") is Dictionary or regional.construction.get("version") != 1 or not regional.get("regions") is Dictionary or not ReolGameClock._integer(regional.get("elapsed_ms")):
			return {}
		regional.construction.version = 2
		regional["weather"] = SimWeather.empty_state(int(regional.elapsed_ms))
		regional.version = 15
		for region: Variant in regional.regions.values():
			if not _upgrade_rain_source(region):
				return {}
	updated.schema_version = 18
	return _upgrade(updated, content)


static func _upgrade_trade(source: Dictionary, content: ReolContentDB) -> Dictionary:
	if not _valid_world_fields(source, 18) or content == null:
		return {}
	var updated: Dictionary = source.duplicate(true)
	if updated.has("continuity"):
		if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
			return {}
		var regional: Dictionary = updated.continuity.world
		if regional.get("version") != 15:
			return {}
		if regional.has("services"):
			var service: Variant = regional.services
			if not service is Dictionary or service.get("version") != 2 or not service.get("definitions") is Dictionary or service.definitions.has("trade"):
				return {}
			service.definitions["trade"] = content.local_trade.duplicate(true)
			service.version = 3
		regional.version = 16
	updated.schema_version = 19
	return _upgrade(updated, content)


static func _upgrade_personal_foraging(source: Dictionary, content: ReolContentDB) -> Dictionary:
	if not _valid_world_fields(source, 19) or content == null:
		return {}
	var updated: Dictionary = source.duplicate(true)
	if not updated.get("simulation") is Dictionary or not SimPersonalForaging.install(updated.simulation.get("config"), content.personal_foraging):
		return {}
	if updated.has("continuity"):
		if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
			return {}
		var regional: Dictionary = updated.continuity.world
		if regional.get("version") != 16 or not regional.get("regions") is Dictionary:
			return {}
		for sim: Variant in regional.regions.values():
			if not sim is Dictionary or not SimPersonalForaging.install(sim.get("config"), content.personal_foraging):
				return {}
		regional.version = 17
	updated.schema_version = 20
	return _upgrade(updated, content)


static func _upgrade_entrusted_goods(source: Dictionary, content: ReolContentDB) -> Dictionary:
	if not _valid_world_fields(source, 20) or content == null:
		return {}
	var updated: Dictionary = source.duplicate(true)
	if not updated.get("simulation") is Dictionary or not SimEntrustedGoods.migrate_native(updated.simulation):
		return {}
	if updated.has("continuity"):
		if not updated.continuity is Dictionary or not updated.continuity.get("world") is Dictionary:
			return {}
		var regional: Dictionary = updated.continuity.world
		if regional.get("version") != 17 or not regional.get("regions") is Dictionary or not SimEntrustedGoods.Shape.same_record(source.simulation, regional.regions.get("home")):
			return {}
		for sim: Variant in regional.regions.values():
			if not sim is Dictionary or not SimEntrustedGoods.migrate_native(sim):
				return {}
		if regional.has("services"):
			var service: Variant = regional.services
			if not service is Dictionary or service.get("version") != 3 or not service.get("definitions") is Dictionary or service.definitions.has("returns") or not service.get("jobs") is Dictionary:
				return {}
			service.version = 4
			service.definitions["returns"] = content.entrusted_returns.duplicate(true)
			for job: Variant in service.jobs.values():
				if not job is Dictionary or not job.get("kind") is String or not job.get("status") is String:
					return {}
				if job.kind != "haul_grain":
					continue
				job["custody_required"] = job.status == "active"
				if job.status != "active":
					continue
				if not SimInventory._nonempty(job.get("id")) or not job.get("carrying") is bool or not regional.regions.has(job.get("home")) or not regional.regions[job.home].actors.has(job.get("actor")) or not regional.settings.routes.has(job.get("route")):
					return {}
				job.options = {"custody": ("legacy:" + str(job.id)) if job.carrying else str(job.id) + ":pickup"}
				if not job.carrying:
					continue
				var route: Dictionary = regional.settings.routes[job.route]
				var basis: Dictionary = {"domain": "service", "purpose": "haul_grain", "origin": job.id,
					"institution": regional.regions[route.from].config.institution.id,
					"source_region": route.from, "source": route.source, "return_region": route.from, "return_place": route.source,
					"target_region": route.to, "target": route.target, "legacy": true}
				regional.regions[job.home].inventory.custody[job.options.custody] = {"container": "actor:" + str(job.actor), "item": route.item, "amount": int(job.amount), "basis": basis, "settled_by": {}}
		# The root village is the same original home, not another copy of goods.
		updated.simulation.inventory = regional.regions.home.inventory.duplicate(true)
		regional.version = 18
	updated.schema_version = 21
	return _upgrade(updated, content)


static func _upgrade_rain_source(sim: Variant) -> bool:
	if not sim is Dictionary or not sim.get("land_resources") is Dictionary:
		return false
	var land: Dictionary = sim.land_resources
	if land.get("version") != 1 or not land.get("sources") is Dictionary:
		return false
	for row: Variant in land.sources.values():
		if not row is Dictionary or row.size() != 3 or not row.has("next_growth_ms") or not row.has("produced") or not row.has("extracted"):
			return false
		row["rainfall"] = 0
	land.version = 2
	return true


static func _valid_world_fields(snapshot: Dictionary, expected_version: int) -> bool:
	if snapshot.get("schema_version") != expected_version:
		return false
	if expected_version <= 43 and snapshot.has("assembly"):
		return false
	if expected_version >= 44 and not ReolWorldAssemblyInputs.is_valid(snapshot.get("assembly"), snapshot.has("continuity")):
		return false
	if expected_version >= 43 and not ReolContentBundle.is_valid(snapshot.get("content_bundle"), ReolContentDB.DOCUMENT_PATHS):
		return false
	if expected_version >= 9 and not SimInventory._nonempty(snapshot.get("avatar_subject")):
		return false
	if not snapshot.get("world") is Dictionary:
		return false
	var world: Dictionary = snapshot.world
	if not FogOfWar.is_valid_exploration(world.get("exploration")):
		return false
	var descriptor: Dictionary = world.duplicate()
	descriptor.erase("exploration")
	if expected_version >= 46:
		if not world.get("terrain_overrides") is Array:
			return false
		descriptor.erase("terrain_overrides")
	if not WorldMapData.valid_descriptor(descriptor) or snapshot.get("world_seed") != descriptor.seed:
		return false
	if expected_version >= 46:
		var candidate: WorldMapData = WorldMapData.from_descriptor(descriptor)
		if candidate == null or not candidate.valid_terrain_overrides(world.terrain_overrides):
			return false
	# Freeze old envelopes independently from any future default map profile.
	return expected_version >= 45 or SnapshotValues.normalized(descriptor) == SnapshotValues.normalized(WorldMapData.legacy_descriptor())


static func _motion_rules() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SimLocalMotion.RULES_PATH))
