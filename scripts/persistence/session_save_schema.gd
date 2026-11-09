class_name SessionSaveSchema
extends RefCounted
## Version and shape validation at the session boundary. No live mutations.

const VERSION: int = 56
const REJECTION_LEGACY_BUILDINGS: String = "legacy_buildings"
const REJECTION_LEGACY_ENVIRONMENT: String = "legacy_environment"
const REJECTION_LEGACY_EVENTS: String = "legacy_events"
const REJECTION_LEGACY_ACTIONS: String = "legacy_actions"
const REJECTION_UNSUPPORTED_VERSION: String = "unsupported_version"


static func capture_world(fog: FogOfWar, focus: Vector2i, terrain: WorldMapData = null) -> Dictionary:
	var state: Dictionary = terrain.descriptor() if terrain != null else WorldMapData.generation_descriptor()
	state["terrain_overrides"] = terrain.terrain_overrides() if terrain != null else []
	if fog != null:
		fog.set_focus(focus)
		fog.update_now()
	state["exploration"] = FogOfWar.empty_exploration() if fog == null else fog.exploration_to_dict()
	return state


static func rejection_reason(version: Variant) -> String:
	# JSON may parse an integral version as a float. Zero, fractional values,
	# non-numbers, out-of-range numbers and future versions are not old saves.
	if not ReolGameClock._integer(version) or int(version) < 1:
		return REJECTION_UNSUPPORTED_VERSION
	if int(version) == 52:
		return REJECTION_LEGACY_BUILDINGS
	if int(version) == 53:
		return REJECTION_LEGACY_EVENTS
	if int(version) == 55:
		return REJECTION_LEGACY_ACTIONS
	if int(version) < VERSION:
		return REJECTION_LEGACY_ENVIRONMENT
	if int(version) > VERSION:
		return REJECTION_UNSUPPORTED_VERSION
	return ""


static func supports_version(version: Variant) -> bool:
	return rejection_reason(version).is_empty()


static func upgrade(source: Dictionary, _content: ReolContentDB = null, _restore_map_factory: Callable = Callable()) -> Dictionary:
	# Earlier roots lack authoritative field-response history. Do not synthesize
	# it from disk content or route an old save into a historical importer.
	if not supports_version(source.get("schema_version")):
		return {}
	return source if is_valid_world(source) else {}


static func _upgrade(source: Dictionary, _content: ReolContentDB) -> Dictionary:
	# Historical test callers retain this spelling while their cases are split.
	# It has the same current-only boundary as the ordinary entry.
	return upgrade(source)


static func is_valid_world(snapshot: Dictionary) -> bool:
	return _valid_solar_envelope(snapshot, VERSION)


static func _valid_solar_envelope(snapshot: Dictionary, expected_version: int) -> bool:
	# Root 50 remains a shape validator for the isolated historical importer;
	# validating that envelope does not admit it through upgrade().
	if not expected_version in [50, VERSION] or not _valid_world_fields(snapshot, expected_version):
		return false
	var climate: Variant = snapshot.content_bundle.documents.get("res://data/definitions/climate.json")
	if not SimClimateRules.valid_definitions(climate):
		return false
	if snapshot.has("continuity"):
		var continuity: Variant = snapshot.continuity
		if not continuity is Dictionary or not continuity.get("world") is Dictionary:
			return false
		var regional: Dictionary = continuity.world
		if expected_version == 50:
			if regional.get("version") != 41 or regional.has("object_lifecycle"):
				return false
		elif regional.get("version") != RegionalSimulation.SCHEMA_VERSION or not regional.get("object_lifecycle") is Dictionary:
			return false
		var environment: Variant = continuity.world.get("environment")
		if not environment is Dictionary or environment.get("version") != SimEnvironment.VERSION or environment.get("rules_version") != 2:
			return false
	return true


static func _valid_world_fields(snapshot: Dictionary, expected_version: int) -> bool:
	# The old importers still refer to these validators; ordinary loading accepts
	# only VERSION above and never invokes them as a migration chain.
	if expected_version not in [47, 48, 49, 50, VERSION] or snapshot.get("schema_version") != expected_version:
		return false
	if not ReolWorldAssemblyInputs.is_valid(snapshot.get("assembly"), snapshot.has("continuity")):
		return false
	if not ReolContentBundle.is_valid(snapshot.get("content_bundle"), ReolContentDB.DOCUMENT_PATHS):
		return false
	if not SimInventory._nonempty(snapshot.get("avatar_subject")):
		return false
	if not snapshot.get("world") is Dictionary:
		return false
	var world: Dictionary = snapshot.world
	if not FogOfWar.is_valid_exploration(world.get("exploration")):
		return false
	var descriptor: Dictionary = world.duplicate()
	descriptor.erase("exploration")
	if not world.get("terrain_overrides") is Array:
		return false
	descriptor.erase("terrain_overrides")
	if not WorldMapData.valid_descriptor(descriptor) or snapshot.get("world_seed") != descriptor.seed:
		return false
	var candidate: WorldMapData = WorldMapData.from_descriptor(descriptor)
	return candidate != null and candidate.valid_terrain_overrides(world.terrain_overrides)
