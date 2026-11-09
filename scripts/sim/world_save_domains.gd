class_name SimWorldSaveDomains
extends RefCounted
## Saved-domain catalogue. Each entry declares its data adapter once; the
## shared registry captures, stages, validates and rebinds it without a switch.
## These are current model adapters, not a second simulation or a migration.
const Registry = preload("res://scripts/persistence/save_registry.gd")
const KEYS: Dictionary = {&"environment_fields": &"local_heat"}


static func registry(with_services: bool = false) -> SimSaveRegistry:
	var result := Registry.new()
	result.add(&"plants", &"plants", preload("res://scripts/sim/plants.gd"),
		func(owner: RefCounted, data: Dictionary, _context: Dictionary) -> bool: return owner.restore(data), _domain_check, _prepare_plants, Callable(), SimPlants.Codec.inventory_scope)
	_standard(result, &"world_events", preload("res://scripts/sim/world_events.gd"), &"", _domain_check)
	result.add(&"embodiment", &"embodiment", preload("res://scripts/sim/embodiment.gd"), _embodiment)
	_standard(result, &"object_lifecycle", preload("res://scripts/sim/object_lifecycle.gd"), &"", _domain_check,
		func(data: Variant, region: String, _content: RefCounted) -> Dictionary: return SimObjectLifecycle.inventory_scope(data, region), true)
	_standard(result, &"site_affairs", preload("res://scripts/sim/site_affairs.gd"), &"site_affairs", _domain_check)
	_standard(result, &"source_care", preload("res://scripts/sim/source_care.gd"), &"source_care", _domain_check)
	_standard(result, &"capability_practice", preload("res://scripts/sim/capability_practice.gd"), &"capability_practice", _domain_check)
	_standard(result, &"field_opportunities", preload("res://scripts/sim/field_opportunities.gd"), &"field_opportunities", _domain_check)
	_standard(result, &"private_exchange", preload("res://scripts/sim/private_exchange.gd"), &"private_exchange",
		_schema_check.bind(SimPrivateExchange.Schema),
		func(data: Variant, region: String, _content: RefCounted) -> Dictionary: return SimPrivateExchange.Schema.inventory_scope(data, region))
	if with_services:
		result.add(&"services", &"services", preload("res://scripts/sim/services/settlement_services.gd"), _services)
	_standard(result, &"heat_methods", preload("res://scripts/sim/heat_methods.gd"), &"heat_methods")
	result.add(&"method_records", &"method_records", preload("res://scripts/sim/method_records.gd"), _records, _schema_check.bind(SimMethodRecords.Schema))
	_standard(result, &"artifacts", preload("res://scripts/sim/artifacts.gd"), &"artifacts", _artifacts_check)
	_standard(result, &"soul_vessels", preload("res://scripts/sim/soul_vessels.gd"), &"soul_vessels")
	result.add(&"large_bodies", &"large_bodies", preload("res://scripts/sim/large_bodies.gd"), _large, _large_check, Callable(), _bind_large)
	result.add(&"avian_life", &"avian_life", preload("res://scripts/sim/avian_life.gd"), _avian, Callable(), Callable(), _bind_avian)
	_standard(result, &"sparring", preload("res://scripts/sim/sparring.gd"), &"")
	_standard(result, &"admissions", preload("res://scripts/sim/social_admission.gd"), &"social_admission")
	result.add(&"construction", &"construction", preload("res://scripts/sim/construction.gd"), _construction,
		func(owner: RefCounted, _context: Dictionary) -> bool: return owner.space_valid(), Callable(), _bind_construction,
		func(data: Variant, region: String, content: RefCounted) -> Dictionary: return SimConstruction.Schema.inventory_scope(data, region, content.construction))
	_standard(result, &"resting", preload("res://scripts/sim/resting.gd"), &"resting")
	_standard(result, &"weather", preload("res://scripts/sim/weather.gd"), &"weather")
	_standard(result, &"standing_work", preload("res://scripts/sim/standing_work.gd"), &"standing_work")
	_standard(result, &"personal_production", preload("res://scripts/sim/personal_production.gd"), &"personal_production", Callable(),
		func(data: Variant, region: String, content: RefCounted) -> Dictionary: return SimPersonalProduction.Schema.inventory_scope(data, region, content.personal_production))
	_standard(result, &"budgeted_labor", preload("res://scripts/sim/budgeted_labor.gd"), &"budgeted_labor", Callable(),
		func(data: Variant, region: String, _content: RefCounted) -> Dictionary: return SimBudgetedLabor.Schema.inventory_scope(data, region))
	_standard(result, &"autonomous_livelihood", preload("res://scripts/sim/autonomous_livelihood.gd"), &"autonomous_livelihood")
	_standard(result, &"clothing", preload("res://scripts/sim/clothing.gd"), &"clothing")
	_standard(result, &"conflicts", preload("res://scripts/sim/conflicts.gd"), &"conflicts", _schema_check.bind(SimConflicts.Schema))
	_standard(result, &"health", preload("res://scripts/sim/health.gd"), &"health", Callable(),
		func(data: Variant, region: String, content: RefCounted) -> Dictionary: return SimHealth.Schema.inventory_scope(data, region, content.health))
	# Sources must exist while artifact state is staged, but their response is
	# restored only after weather, original objects and bodily consequences.
	result.add(&"environment_fields", &"local_heat", preload("res://scripts/sim/world_environment_fields.gd"),
		func(owner: RefCounted, data: Dictionary, _context: Dictionary) -> bool: return owner.restore(data), Callable(), _prepare_fields)
	_standard(result, &"environment", preload("res://scripts/sim/environment.gd"), &"climate",
		func(_owner: RefCounted, context: Dictionary) -> bool: return context.world._valid_herb_conditions())
	_standard(result, &"spirit_sources", preload("res://scripts/sim/spirit_sources.gd"), &"spirit_sources")
	result.add(&"facility_use", &"facility_use", preload("res://scripts/sim/facility_use.gd"), _facility, Callable(), Callable(), Callable(),
		func(data: Variant, region: String, content: RefCounted) -> Dictionary: return SimFacilityUse.inventory_scope(data, region, content.construction))
	return result


static func ids() -> Array[StringName]:
	return registry().ids()


static func _standard(registry: SimSaveRegistry, id: StringName, script: Script, rules: StringName,
	check: Callable = Callable(), scope: Callable = Callable(), strict: bool = false) -> void:
	var added: bool = registry.add(id, KEYS.get(id, id), script, _load.bind(id, rules), check, Callable(), Callable(), scope, strict)
	assert(added, "duplicate saved-world participant")


static func _load(owner: RefCounted, data: Dictionary, context: Dictionary, id: StringName, rules: StringName) -> bool:
	var world: RefCounted = context.world
	if id in [&"artifacts", &"conflicts", &"spirit_sources"]:
		world.set(id, owner)
	var initialized: Variant = owner.call("initialize", world) if rules == &"" else owner.call("initialize", world, context.content.get(rules))
	if initialized != true or not owner.restore(data):
		return false
	world.set(id, owner)
	return true


static func _embodiment(owner: RefCounted, data: Dictionary, context: Dictionary) -> bool:
	if not owner.configure(context.content.body_forms) or not owner.restore(data):
		return false
	for region: VillageSimulation in context.world.regions.values():
		for id: String in region.actors:
			if not region.actors[id].active.is_empty() and (not owner.self_controls_actor(id, "action") or not owner.self_controls_actor(id, "motion")):
				return false
	context.world.embodiment = owner
	return true


static func _services(owner: RefCounted, data: Dictionary, context: Dictionary) -> bool:
	if not owner.initialize(context.world, context.source.services.definitions):
		return false
	context.world.services = owner
	owner.set_navigation(context.source.services._navigation, context.source.services._can_step)
	if not owner.restore(data):
		return false
	for id: String in owner.active_jobs:
		if not context.world.actor_controls(id, "action") or not context.world.actor_controls(id, "motion"):
			return false
	return true


static func _records(owner: RefCounted, data: Dictionary, context: Dictionary) -> bool:
	if not context.data.artifacts.get("events") is Array or not owner.initialize(context.world, context.content.method_records) or not owner.restore(data, context.data.artifacts.events):
		return false
	context.world.method_records = owner
	return true


static func _prepare_fields(owner: RefCounted, context: Dictionary) -> bool:
	if not owner.initialize(context.world, context.content.local_heat):
		return false
	context.world.environment_fields = owner
	return true


static func _large(owner: RefCounted, data: Dictionary, context: Dictionary) -> bool:
	if not _load(owner, data, context, &"large_bodies", &"large_bodies"):
		return false
	if context.world.map_data != null:
		owner.set_geometry(context.world.map_data.terrain_is_walkable, context.world.map_data.get_elevation, Callable(), true)
	else:
		owner.set_geometry(context.source.large_bodies._terrain, context.source.large_bodies._elevation, context.source.large_bodies._incoming)
	return true


static func _large_check(owner: RefCounted, _context: Dictionary) -> bool:
	return not owner._terrain.is_valid() or owner.space_valid()


static func _avian(owner: RefCounted, data: Dictionary, context: Dictionary) -> bool:
	if not _load(owner, data, context, &"avian_life", &"avian_life"):
		return false
	owner.set_landing_check(context.world.map_data.terrain_is_walkable if context.world.map_data != null else context.source.avian_life._landing)
	return true


static func _construction(owner: RefCounted, data: Dictionary, context: Dictionary) -> bool:
	if not _load(owner, data, context, &"construction", &"construction"):
		return false
	if context.world.map_data != null:
		owner.set_terrain(context.world.map_data.terrain_is_walkable, context.world.map_data.get_elevation)
	else:
		owner.set_terrain(context.source.construction._terrain, context.source.construction._elevation)
		owner.set_incoming_occupancy(context.source.construction._incoming)
	return true


static func _facility(owner: RefCounted, data: Dictionary, context: Dictionary) -> bool:
	owner.bind_world(context.world)
	context.world.facility_use = owner
	return owner.restore(data)


static func _domain_check(owner: RefCounted, _context: Dictionary) -> bool:
	return owner.cross_valid()


static func _schema_check(owner: RefCounted, _context: Dictionary, schema: Script) -> bool:
	return schema.cross_valid(owner)


static func _artifacts_check(owner: RefCounted, _context: Dictionary) -> bool:
	for actor: String in owner.active:
		var job: Dictionary = owner.active[actor]
		if job.verb == "warm" and not owner._warming_readiness(actor, str(job.object)).ok:
			return false
	return SimArtifacts.Schema.cross_valid(owner)


static func _bind_large(owner: RefCounted, host: RefCounted, context: Dictionary) -> void:
	if context.has("large_incoming"):
		owner._incoming = context.large_incoming
	owner.bind_world(host)


static func _bind_construction(owner: RefCounted, host: RefCounted, context: Dictionary) -> void:
	if context.has("construction_incoming"):
		owner.set_incoming_occupancy(context.construction_incoming)
	owner.bind_world(host)


static func _bind_avian(owner: RefCounted, host: RefCounted, context: Dictionary) -> void:
	if context.has("avian_landing"):
		owner.set_landing_check(context.avian_landing)
	owner.bind_world(host)


static func _prepare_plants(owner: RefCounted, context: Dictionary) -> bool:
	if not owner.initialize(context.world, context.content.plants):
		return false
	context.world.plants = owner
	return true
