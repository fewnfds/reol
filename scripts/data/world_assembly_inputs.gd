class_name ReolWorldAssemblyInputs
extends RefCounted
## JSON inputs needed to assemble an independent world before restoring facts.
## These are not live simulation state and never create actors or resources.

const VERSION: int = 1


static func from_world(world: RegionalSimulation, centers: Variant) -> Dictionary:
	if world == null or not centers is Dictionary:
		return {}
	var configurations: Dictionary = {}
	for id: Variant in world.regions:
		if not _id(id):
			return {}
		configurations[id] = world.opening_config(id).duplicate(true)
	return _joint(configurations, world.settings, centers)


static func standalone(configuration: Variant) -> Dictionary:
	if not configuration is Dictionary:
		return {}
	var value: Dictionary = SnapshotValues.for_save({
		"version": VERSION, "region_configs": {"home": configuration.duplicate(true)},
		"settings": {}, "centers": {},
	})
	return value if is_valid(value, false) else {}


static func is_valid(value: Variant, joint: bool) -> bool:
	if not value is Dictionary or value.size() != 4 or not SimSchema._json_value(value):
		return false
	if not SimSchema._integer(value.get("version"), VERSION, VERSION):
		return false
	if not value.get("region_configs") is Dictionary or not value.get("settings") is Dictionary or not value.get("centers") is Dictionary:
		return false
	var configurations: Dictionary = value.region_configs
	var settings: Dictionary = value.settings
	var centers: Dictionary = value.centers
	if configurations.is_empty():
		return false
	for id: Variant in configurations:
		if not _id(id) or not SimSchema.validate_config(configurations[id]):
			return false
	if not joint:
		return configurations.size() == 1 and configurations.has("home") and settings.is_empty() and centers.is_empty()
	if not _valid_settings(settings, configurations) or centers.size() != configurations.size():
		return false
	for id: Variant in centers:
		if not _id(id) or not configurations.has(id):
			return false
		var cell: Variant = centers[id]
		if not cell is Array or cell.size() != 2:
			return false
		for coordinate: Variant in cell:
			if not SimSchema._integer(coordinate, 0, WorldMapData.WORLD_SIZE - 1):
				return false
	return true


static func _joint(configurations: Dictionary, settings: Dictionary, centers: Dictionary) -> Dictionary:
	var value: Dictionary = SnapshotValues.for_save({
		"version": VERSION, "region_configs": configurations.duplicate(true),
		"settings": settings.duplicate(true), "centers": centers.duplicate(true),
	})
	return value if is_valid(value, true) else {}


static func _valid_settings(settings: Dictionary, configurations: Dictionary) -> bool:
	# Detailed route and cross-entity checks belong to RegionalSimulation when
	# the independent candidate is assembled. Require its structural inputs here.
	if not SimSchema._integer(settings.get("schema_version"), RegionalSimulation.DEFINITIONS_VERSION, RegionalSimulation.DEFINITIONS_VERSION):
		return false
	if not settings.get("regions") is Dictionary or not settings.get("routes") is Dictionary or not settings.get("courier_needs") is Dictionary:
		return false
	if settings.regions.size() != configurations.size():
		return false
	for id: Variant in settings.regions:
		if not _id(id) or not configurations.has(id) or not settings.regions[id] is Dictionary or not settings.regions[id].get("label") is String:
			return false
	var active: Variant = settings.get("active_region", "")
	if not active is String or (not active.is_empty() and not configurations.has(active)):
		return false
	for id: Variant in settings.routes:
		if not _id(id) or not settings.routes[id] is Dictionary:
			return false
	return true


static func _id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value == value.strip_edges()
