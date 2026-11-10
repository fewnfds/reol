class_name RegionalSimulation
extends RefCounted
signal action_finished(outcome: Dictionary)
signal boundary_settled(at_ms: int)
## One timeline owns regional execution, transport and delayed institutional news.
## Scene adapters may disappear; these instances and their pending work remain.

const DEFINITIONS_VERSION: int = 1
const SCHEMA_VERSION: int = 47
const MINUTE_MS: int = 60000
const MAX_COUNT: int = SimInventory.MAX_COUNT
const Services = preload("res://scripts/sim/services/settlement_services.gd")

# Profiles describe existing call-site contracts, not a second lock registry.
# Every query reads the actual domain-owned process, including multi-person jobs.
enum ActivityScope {
	LOCAL = 1, BODY = 2, PLAYER_ACTION = 4, AUTOMATIC_MOTION = 8,
	JOURNEY = 16, MANUAL_ACTION = 32, STATIONARY = 64, WAIT = 128,
	RETURN_AUTONOMY = 256,
}
const ACTIVITY_PROFILES: Dictionary = {
	&"local": ActivityScope.LOCAL, &"body": ActivityScope.BODY,
	&"player_action": ActivityScope.PLAYER_ACTION, &"automatic_motion": ActivityScope.AUTOMATIC_MOTION,
	&"journey": ActivityScope.JOURNEY, &"manual_action": ActivityScope.MANUAL_ACTION,
	&"stationary": ActivityScope.STATIONARY, &"wait": ActivityScope.WAIT,
}
const ACTIVITY_DOMAINS: Dictionary = {
	&"plants": ActivityScope.LOCAL | ActivityScope.BODY | ActivityScope.PLAYER_ACTION | ActivityScope.AUTOMATIC_MOTION | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION | ActivityScope.STATIONARY | ActivityScope.WAIT | ActivityScope.RETURN_AUTONOMY,
	&"object_lifecycle": ActivityScope.LOCAL | ActivityScope.BODY | ActivityScope.PLAYER_ACTION | ActivityScope.AUTOMATIC_MOTION | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION | ActivityScope.STATIONARY | ActivityScope.WAIT | ActivityScope.RETURN_AUTONOMY,
	&"private_exchange": ActivityScope.LOCAL | ActivityScope.BODY | ActivityScope.PLAYER_ACTION | ActivityScope.AUTOMATIC_MOTION | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION | ActivityScope.STATIONARY | ActivityScope.RETURN_AUTONOMY,
	&"field_opportunities": ActivityScope.LOCAL | ActivityScope.BODY | ActivityScope.PLAYER_ACTION | ActivityScope.AUTOMATIC_MOTION | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION | ActivityScope.STATIONARY | ActivityScope.RETURN_AUTONOMY,
	&"capability_practice": ActivityScope.LOCAL | ActivityScope.BODY | ActivityScope.PLAYER_ACTION | ActivityScope.AUTOMATIC_MOTION | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION | ActivityScope.STATIONARY | ActivityScope.RETURN_AUTONOMY,
	&"conflicts": ActivityScope.LOCAL | ActivityScope.BODY | ActivityScope.PLAYER_ACTION | ActivityScope.AUTOMATIC_MOTION | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION | ActivityScope.STATIONARY | ActivityScope.WAIT | ActivityScope.RETURN_AUTONOMY,
	&"spirit_sources": ActivityScope.LOCAL | ActivityScope.BODY | ActivityScope.PLAYER_ACTION | ActivityScope.AUTOMATIC_MOTION | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION | ActivityScope.STATIONARY | ActivityScope.RETURN_AUTONOMY,
	&"health": ActivityScope.LOCAL | ActivityScope.BODY | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION | ActivityScope.STATIONARY | ActivityScope.RETURN_AUTONOMY,
	&"clothing": ActivityScope.LOCAL | ActivityScope.BODY | ActivityScope.PLAYER_ACTION | ActivityScope.AUTOMATIC_MOTION | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION | ActivityScope.STATIONARY | ActivityScope.RETURN_AUTONOMY,
	&"personal_production": ActivityScope.LOCAL | ActivityScope.BODY | ActivityScope.PLAYER_ACTION | ActivityScope.AUTOMATIC_MOTION | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION | ActivityScope.STATIONARY | ActivityScope.RETURN_AUTONOMY,
	&"method_records": ActivityScope.LOCAL | ActivityScope.BODY | ActivityScope.PLAYER_ACTION | ActivityScope.AUTOMATIC_MOTION | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION | ActivityScope.STATIONARY | ActivityScope.RETURN_AUTONOMY,
	&"resting": ActivityScope.LOCAL | ActivityScope.BODY | ActivityScope.PLAYER_ACTION | ActivityScope.AUTOMATIC_MOTION | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION | ActivityScope.STATIONARY | ActivityScope.RETURN_AUTONOMY,
	&"facility_use": ActivityScope.LOCAL | ActivityScope.BODY | ActivityScope.PLAYER_ACTION | ActivityScope.AUTOMATIC_MOTION | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION | ActivityScope.STATIONARY | ActivityScope.WAIT | ActivityScope.RETURN_AUTONOMY,
	&"construction": ActivityScope.LOCAL | ActivityScope.BODY | ActivityScope.PLAYER_ACTION | ActivityScope.AUTOMATIC_MOTION | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION | ActivityScope.RETURN_AUTONOMY,
	&"admissions": ActivityScope.LOCAL | ActivityScope.BODY | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION | ActivityScope.RETURN_AUTONOMY,
	&"soul_vessels": ActivityScope.LOCAL | ActivityScope.BODY | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION,
	&"sparring": ActivityScope.LOCAL | ActivityScope.BODY | ActivityScope.PLAYER_ACTION | ActivityScope.AUTOMATIC_MOTION | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION | ActivityScope.WAIT,
	&"artifacts": ActivityScope.BODY | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION | ActivityScope.RETURN_AUTONOMY,
	&"services": ActivityScope.BODY | ActivityScope.AUTOMATIC_MOTION | ActivityScope.JOURNEY | ActivityScope.MANUAL_ACTION,
}
const SPARRING_PHASE_SCOPES: int = ActivityScope.PLAYER_ACTION | ActivityScope.AUTOMATIC_MOTION | ActivityScope.MANUAL_ACTION
const SaveDomains = preload("res://scripts/sim/world_save_domains.gd")
# Keep query order stable too: a future derived cache must not silently turn
# next-boundary collection into an unordered set of domain callbacks.
const BOUNDARY_DOMAINS: Array[StringName] = [
	&"world_events", &"plants",
	&"object_lifecycle",
	&"artifacts", &"sparring", &"avian_life", &"soul_vessels", &"admissions",
	&"construction", &"facility_use", &"resting", &"weather", &"standing_work", &"large_bodies",
	&"method_records", &"personal_production", &"budgeted_labor", &"clothing",
	&"health", &"environment", &"environment_fields", &"spirit_sources", &"conflicts", &"source_care", &"capability_practice", &"field_opportunities", &"private_exchange",
]
# The runtime adapter historically used this ordered subset to choose an outer
# interval before its heat preflight and player-journey checks. Other world,
# regional, route and message boundaries are still handled inside advance_to_ms.
const RUNTIME_BOUNDARY_DOMAINS: Array[StringName] = [
	&"world_events", &"plants",
	&"construction", &"facility_use", &"resting", &"weather", &"clothing", &"health",
	&"spirit_sources", &"conflicts", &"source_care", &"field_opportunities",
	&"private_exchange", &"capability_practice", &"environment", &"environment_fields",
	&"large_bodies", &"personal_production",
]
# Describes the existing world-level order; it is not an automatic callback
# registry. In particular, interrupted object settlement resumes at that phase.
const ADVANCE_PHASES: Array[StringName] = [
	&"manual_motion_and_regional_advance", &"settle_previous_interval",
	&"advance_journeys_and_arrivals", &"prepare_environment_event",
	&"settle_current_processes", &"sample_herb_conditions", &"consider_future_actions",
	&"process_messages", &"discrete_events", &"dispatch_routes",
]

var regions: Dictionary = {}
var _finished_notices: Array[Dictionary] = []
var _publishing_boundary: bool = false
var _opening_configs: Dictionary = {}
var elapsed_ms: int = 0
var target_ms: int = 0
var current_time: int:
	get:
		return floori(float(elapsed_ms) / MINUTE_MS)
	set(value):
		elapsed_ms = value * MINUTE_MS
var target_time: int:
	get:
		return floori(float(target_ms) / MINUTE_MS)
	set(value):
		target_ms = value * MINUTE_MS
var active_region: String = ""
var settings: Dictionary = {}
var routes: Dictionary = {}
var shipments: Dictionary = {}
var couriers: Dictionary = {}
var events: Array = []
var messages: Array = []
var local_news: Dictionary = {}
var operations: Dictionary = {}
var in_transit: SimInventory = SimInventory.new()
var errors: Array[String] = []
var simulation_work: Dictionary = {"boundaries": 0, "deliveries": 0, "messages": 0}
var services: RefCounted
var embodiment: SimEmbodiment:
	set(value):
		if embodiment != null:
			embodiment.set_control_change_guard(Callable())
		embodiment = value
		if embodiment != null:
			var owner: WeakRef = weakref(self)
			embodiment.set_control_change_guard(func(source: Dictionary) -> bool:
				var authority: RegionalSimulation = owner.get_ref()
				return authority != null and authority._prepare_control_change(source))
var artifacts: SimArtifacts
## Session hooks survive an in-place restore; candidates have separate hooks.
var artifact_transfers := SimArtifactTransfers.new()
var object_lifecycle: SimObjectLifecycle
var heat_methods: SimHeatMethods
var sparring: SimSparring
var avian_life: SimAvianLife
var soul_vessels: SimSoulVessels
var admissions: SimSocialAdmission
var construction: SimConstruction
var facility_use: SimFacilityUse
var resting: SimResting
var weather: SimWeather
var standing_work: SimStandingWork
var method_records: SimMethodRecords
var large_bodies: SimLargeBodies
var personal_production: SimPersonalProduction
var budgeted_labor: SimBudgetedLabor
var autonomous_livelihood: SimAutonomousLivelihood
var clothing: SimClothing
var health: SimHealth
var environment: SimEnvironment
var environment_fields: RefCounted
var spirit_sources: SimSpiritSources
var conflicts: SimConflicts
var site_affairs: RefCounted
var source_care: RefCounted
var capability_practice: RefCounted
var field_opportunities: RefCounted
var private_exchange: RefCounted
var plants: SimPlants
var world_events: SimWorldEvents
var map_data: WorldMapData
## Rebuildable spatial links only; never serialized as another world state.
var space: SimWorldSpace

var _content: ReolContentDB
var _next_id: int = 1
var _region_boundaries: Dictionary = {}
var _dirty_region_boundaries: Dictionary = {}
var _local_action_owner: Callable
var _manual_motion_executor: Callable
## Opt-in exclusive acceptance-session guard. These credentials do not make
## arbitrary raw access to this public simulation an isolated transaction.
var _environment_guard: WeakRef
var _environment_boundary_waiting: bool = false
var _environment_event: EnvironmentEventContext
var _environment_response: EnvironmentEventContext
## Derived execution links/cursor; partial boundaries cannot be saved. Domain
## state and accepted target time remain in their original owners.
var settlement: SimSettlementKernel
var _settlement_adapter: SimWorldSettlement
var settlement_work: int = 0
var _settled_ms: int = 0
## Region selection for the kernel's native_interval step. Manual input runs
## before begin(); the existing kernel retains all subsequent continuation.
var _native_regions: Array[String] = []
var _native_region_cursor: int = 0
var _native_committing: bool = false


static func schedule_contract() -> Dictionary:
	# Return copies: callers may inspect the existing schedule, not mutate it.
	# Services are optional; regions, routes, messages and ecology sampling also
	# provide boundaries outside the fixed domain list.
	return {
		"snapshot_domains": SaveDomains.ids(),
		"boundary_domains": BOUNDARY_DOMAINS.duplicate(),
		"runtime_boundary_domains": RUNTIME_BOUNDARY_DOMAINS.duplicate(),
		"advance_phases": ADVANCE_PHASES.duplicate(),
	}


func describe_object(reference: Variant) -> Dictionary:
	# Authority/editor API. Observation and permission are separate contracts.
	return SimWorldObjectQuery.describe(self, reference)


func object_capability(reference: Variant, capability: String) -> Dictionary:
	return SimWorldObjectQuery.capability(self, reference, capability)


func capture_object_space(references: Array, budget: int = 4096) -> Dictionary:
	return SimWorldObjectQuery.capture(self, references, budget)


func query_space(area: Rect2i, kinds: Array = [], layer: String = "", budget: int = 4096) -> Dictionary:
	if space == null:
		return {"ok": false, "complete": false, "reason": "world_unavailable", "references": []}
	return space.query(area, kinds, layer, budget)


func describe_actor_action(actor: String) -> Dictionary:
	return SimActionContract.describe(self, actor)


func _replace_space() -> void:
	var previous: SimWorldSpace = space
	space = SimWorldSpace.new(self)
	if previous != null:
		previous.reset("world_replaced")
		previous.detach()


func retire_space() -> void:
	# A runtime adopts a fully validated independent world. Retained handles to
	# the previous live projection must fail even if another diagnostic keeps
	# that original simulation alive.
	var previous: SimWorldSpace = space
	space = null
	if previous != null:
		previous.reset("world_replaced")
		previous.detach()


func bind_environment_boundary_guard(guard: RefCounted) -> bool:
	if guard != null and environment_fields is SimWorldEnvironmentFields:
		return false # Ordinary fields are the sole transaction participant.
	if object_lifecycle == null or _environment_boundary_waiting or _environment_event != null or object_lifecycle.environment_change_pending():
		return false
	var previous: RefCounted = _environment_guard.get_ref() if _environment_guard != null else null
	if guard != null and previous != null and previous != guard:
		return false
	if not object_lifecycle.bind_environment_boundary_guard(guard):
		return false
	_environment_guard = weakref(guard) if guard != null else null
	_environment_response = null
	return true


func environment_boundary_active() -> bool:
	return _environment_event != null or _environment_boundary_waiting or not accepts_commands()


func environment_event_context() -> Variant:
	return _environment_event if environment_event_valid(_environment_event) else null


func environment_response_context(guard: RefCounted) -> Variant:
	var bound: RefCounted = _environment_guard.get_ref() if _environment_guard != null else null
	if guard == null or guard != bound or object_lifecycle == null or environment_boundary_active() or object_lifecycle.environment_change_pending() or not _environment_regions_synchronized():
		return null
	_environment_response = EnvironmentEventContext.new(self, guard, elapsed_ms, false)
	return _environment_response


func environment_event_valid(context: Variant) -> bool:
	if not context is EnvironmentEventContext:
		return false
	var bound: RefCounted = _environment_guard.get_ref() if _environment_guard != null else null
	if bound == null or context.owner.get_ref() != self or context.guard.get_ref() != bound or context.at_ms != elapsed_ms:
		return false
	if context.event:
		if not is_same(context, _environment_event):
			return false
	elif not is_same(context, _environment_response) or object_lifecycle == null or environment_boundary_active() or object_lifecycle.environment_change_pending():
		return false
	return _environment_regions_synchronized()


func _environment_regions_synchronized() -> bool:
	for region: VillageSimulation in regions.values():
		if region.elapsed_ms != elapsed_ms:
			return false
	return true


func bind_map_data(data: WorldMapData) -> void:
	map_data = data
	if data == null:
		return
	if plants != null:
		plants.bind_world(self)
	if construction != null:
		construction.set_terrain(data.terrain_is_walkable, data.get_elevation)
	if large_bodies != null:
		large_bodies.set_geometry(data.terrain_is_walkable, data.get_elevation, large_bodies._incoming, true)


func initialize(definitions: Dictionary, instances: Dictionary, content: ReolContentDB = null) -> bool:
	errors.clear()
	if not _valid_settings(definitions, instances):
		errors.append("Invalid regional definitions, containers or clocks")
		return false
	var next_embodiment := SimEmbodiment.new()
	if content == null or not next_embodiment.configure(content.body_forms) or not next_embodiment.restore(SimEmbodiment.legacy_state(_actor_ids(instances))):
		errors.append("Invalid body forms or subject references")
		return false
	_content = content
	embodiment = next_embodiment
	settings = definitions.duplicate(true)
	regions = instances.duplicate()
	object_lifecycle = SimObjectLifecycle.new()
	if not object_lifecycle.initialize(self):
		return false
	artifacts = SimArtifacts.new()
	if not artifacts.initialize(self, content.artifacts):
		errors.append("Invalid artifact definitions")
		return false
	heat_methods = SimHeatMethods.new()
	if not heat_methods.initialize(self, content.heat_methods):
		errors.append("Invalid heat method definitions")
		return false
	method_records = SimMethodRecords.new()
	if not method_records.initialize(self, content.method_records):
		errors.append("Invalid method record definitions")
		return false
	sparring = SimSparring.new()
	if not sparring.initialize(self):
		errors.append("Invalid sparring definitions")
		return false
	elapsed_ms = int((regions.values()[0] as VillageSimulation).elapsed_ms)
	target_ms = elapsed_ms
	large_bodies = SimLargeBodies.new()
	if not large_bodies.initialize(self, content.large_bodies):
		errors.append("Invalid large body definitions")
		return false
	soul_vessels = SimSoulVessels.new()
	if not soul_vessels.initialize(self, content.soul_vessels):
		errors.append("Invalid soul vessel definitions")
		return false
	avian_life = SimAvianLife.new()
	if not avian_life.initialize(self, content.avian_life):
		errors.append("Invalid avian life definitions")
		return false
	admissions = SimSocialAdmission.new()
	if not admissions.initialize(self, content.social_admission):
		errors.append("Invalid social admission definitions")
		return false
	construction = SimConstruction.new()
	if not construction.initialize(self, content.construction):
		errors.append("Invalid construction definitions")
		return false
	facility_use = SimFacilityUse.new()
	facility_use.bind_world(self)
	resting = SimResting.new()
	if not resting.initialize(self, content.resting):
		errors.append("Invalid resting definitions")
		return false
	weather = SimWeather.new()
	if not weather.initialize(self, content.weather):
		errors.append("Invalid weather definitions")
		return false
	standing_work = SimStandingWork.new()
	if not standing_work.initialize(self, content.standing_work):
		errors.append("Invalid standing work definitions")
		return false
	personal_production = SimPersonalProduction.new()
	if not personal_production.initialize(self, content.personal_production):
		errors.append("Invalid personal production definitions")
		return false
	active_region = str(settings.get("active_region", ""))
	budgeted_labor = SimBudgetedLabor.new()
	if not budgeted_labor.initialize(self, content.budgeted_labor):
		errors.append("Invalid budgeted labor definitions")
		return false
	autonomous_livelihood = SimAutonomousLivelihood.new()
	if not autonomous_livelihood.initialize(self, content.autonomous_livelihood):
		errors.append("Invalid autonomous livelihood definitions")
		return false
	clothing = SimClothing.new()
	if not clothing.initialize(self, content.clothing):
		errors.append("Invalid clothing definitions")
		return false
	conflicts = SimConflicts.new()
	if not conflicts.initialize(self, content.conflicts):
		errors.append("Invalid conflict definitions")
		return false
	health = SimHealth.new()
	if not health.initialize(self, content.health):
		errors.append("Invalid health definitions")
		return false
	health.source_floor = artifacts.next_id
	capability_practice = SimCapabilityPractice.new()
	if not capability_practice.initialize(self, content.capability_practice):
		errors.append("Invalid bounded capability practice definitions")
		return false
	field_opportunities = SimFieldOpportunities.new()
	if not field_opportunities.initialize(self, content.field_opportunities):
		errors.append("Invalid bounded field-site definitions")
		return false
	private_exchange = SimPrivateExchange.new()
	if not private_exchange.initialize(self, content.private_exchange):
		errors.append("Invalid bounded private exchange rules")
		return false
	spirit_sources = SimSpiritSources.new()
	if not spirit_sources.initialize(self, content.spirit_sources):
		errors.append("Invalid finite spiritual source definitions")
		return false
	environment_fields = SimWorldEnvironmentFields.new()
	if not environment_fields.initialize(self, content.local_heat):
		errors.append("Invalid current environmental field definitions")
		return false
	environment = SimEnvironment.new()
	if not environment.initialize(self, content.climate):
		errors.append("Invalid local environment definitions")
		return false
	if not _sample_herb_conditions(true):
		errors.append("Invalid opening plant environment")
		return false
	site_affairs = SimSiteAffairs.new()
	if not site_affairs.initialize(self, content.site_affairs):
		errors.append("Invalid bounded source-loan rules")
		return false
	source_care = SimSourceCare.new()
	if not source_care.initialize(self, content.source_care):
		errors.append("Invalid bounded source-care rules")
		return false
	routes = {}
	shipments = {}
	couriers = {}
	events = []
	messages = []
	local_news = {}
	operations = {}
	in_transit = SimInventory.new()
	_next_id = 1
	simulation_work = {"boundaries": 0, "deliveries": 0, "messages": 0}
	_region_boundaries = {}
	_dirty_region_boundaries.clear()
	for region_id: String in regions:
		local_news[region_id] = []
		_region_boundaries[region_id] = regions[region_id].next_boundary_ms()
	for route_id: String in settings.routes:
		var definition: Dictionary = settings.routes[route_id]
		routes[route_id] = {
			"blocked": false,
			"demand": 0, "request_time": -1,
		}
		var courier_id: String = definition.courier
		couriers[courier_id] = {
			"id": courier_id, "route": route_id, "name": definition.courier_name,
			"phase": "idle", "shipment": "", "progress": 0,
			"energy": 100.0, "rest_remaining": 0,
		}
	plants = SimPlants.new()
	if not plants.initialize(self, content.plants):
		return false
	plants.bind_world(self)
	world_events = SimWorldEvents.new()
	if not world_events.initialize(self) or not world_events.seed_routes():
		return false
	_opening_configs = {}
	for id: String in regions:
		_opening_configs[id] = regions[id].config.duplicate(true)
	_bind_service_guards()
	_replace_space()
	return _bind_settlement()


func _bind_settlement() -> bool:
	var adapter := SimWorldSettlement.new()
	if not adapter.initialize(self):
		errors.append("Invalid settlement dependencies")
		return false
	_settlement_adapter = adapter
	settlement = adapter.kernel
	_settled_ms = elapsed_ms
	_environment_boundary_waiting = false
	_finished_notices.clear()
	return true


func settled_ms() -> int:
	return _settled_ms if has_pending_boundary() else elapsed_ms


func has_pending_boundary() -> bool:
	return settlement != null and settlement.is_pending()


func pending_boundary_ms() -> int:
	return settlement.at_ms if has_pending_boundary() else elapsed_ms


func accepts_commands() -> bool:
	return not _publishing_boundary and (services == null or not services._handling_stock) and (settlement == null or not settlement.is_pending() or settlement.is_executing())


func publish_action_finished(outcome: Dictionary) -> void:
	if has_pending_boundary():
		_finished_notices.append(outcome)
	else:
		action_finished.emit(outcome)


func opening_config(region_id: String) -> Dictionary:
	return _opening_configs.get(region_id, regions[region_id].config)


func set_manual_motion_executor(executor: Callable) -> void:
	_manual_motion_executor = executor


func interrupt_occupation(actor: String, reason: String, preserve_sparring: bool = false) -> void:
	if not accepts_commands():
		return
	# Hostile contact interrupts actual jobs, retaining already paid costs and
	# entrusted goods. A command never erases an unrelated promise or contract.
	if conflicts != null:
		conflicts.interrupt_lesson(actor)
	if services != null:
		services.cancel(actor, reason)
	if capability_practice != null:
		capability_practice.cancel(actor, reason)
	if field_opportunities != null:
		field_opportunities.cancel(actor, reason)
	if private_exchange != null:
		private_exchange.cancel(actor, reason)
	for domain: RefCounted in [plants, object_lifecycle, artifacts, soul_vessels, admissions, construction, facility_use, resting, clothing, health, spirit_sources, method_records, personal_production]:
		if domain != null:
			domain.cancel(actor)
	if not preserve_sparring and sparring != null and sparring.owns_actor(actor):
		sparring.stop("finished")
	for sim: VillageSimulation in regions.values():
		if sim.has_actor(actor):
			sim.cancel_action(actor, reason)
	if source_care != null:
		source_care.occupation_interrupted(actor)
	if field_opportunities != null:
		field_opportunities.occupation_interrupted(actor)


static func _base_workplace_config(source: Dictionary) -> Dictionary:
	# Optional saved rooms change no source recipe or accumulated history.
	var result: Dictionary = source.duplicate(true)
	if result.has("workplaces_version"):
		result.erase("workplaces_version")
		if result.get("actions") is Dictionary:
			result.actions.erase("workspace_return")
	return result


func configure_services(definitions: Dictionary) -> bool:
	if services != null:
		return false
	var candidate := Services.new()
	if not candidate.initialize(self, definitions):
		return false
	services = candidate
	_bind_service_guards()
	return true


func _bind_service_guards() -> void:
	var owner: WeakRef = weakref(self)
	for simulation: VillageSimulation in regions.values():
		var native_owner: WeakRef = weakref(simulation)
		simulation.set_control_guard(func(actor_id: String, channel: String) -> bool:
			var authority: RefCounted = owner.get_ref()
			return authority != null and authority.actor_controls(actor_id, channel))
		simulation.set_action_guard(func(actor_id: String) -> bool:
			var authority: RefCounted = owner.get_ref()
			return authority != null and authority.native_action_allowed(actor_id))
		simulation.set_rest_recovery(func(actor_id: String) -> int:
			var authority: RefCounted = owner.get_ref()
			return 0 if authority == null else authority.resting.recovery_for(actor_id))
		simulation.set_external_labor(func(actor_id: String) -> bool:
			var authority: RefCounted = owner.get_ref()
			return authority != null and (authority.personal_production.owns_actor(actor_id) or authority.clothing.owns_actor(actor_id) or (authority.field_opportunities != null and authority.field_opportunities.owns_actor(actor_id))))
		simulation.set_exposure_rate(func(actor_id: String) -> int:
			var authority: RefCounted = owner.get_ref()
			return 0 if authority == null else authority.clothing.energy_rate(actor_id) + authority.environment.energy_rate(actor_id))
		simulation.set_duty_provider(func(actor_id: String, at_ms: int) -> String:
			var authority: RefCounted = owner.get_ref()
			return "" if authority == null else authority.standing_work.duty_for(actor_id, at_ms))
		simulation.set_labor_observer(func(stage: String, actor_id: String, action: Dictionary, event: String) -> String:
			var authority: RefCounted = owner.get_ref()
			var native: VillageSimulation = native_owner.get_ref()
			if authority == null or native == null:
				return ""
			var result: String = authority.budgeted_labor.native_event(stage, actor_id, action, event)
			if stage in ["finish", "fail"]:
				SimActionContract.job_finished(authority, "native", action, actor_id, "completed" if stage == "finish" else "cancelled", stage, native.elapsed_ms)
			return result)
		simulation.set_initiative_provider(func(actor_id: String, at_ms: int) -> bool:
			var authority: RefCounted = owner.get_ref()
			return authority != null and authority._wants_initiative(actor_id, at_ms))


func _wants_initiative(actor: String, at_ms: int) -> bool:
	if health.wants_decision(actor, at_ms) or clothing.wants_decision(actor, at_ms):
		return true
	if artifacts.wants_warming_decision(actor, at_ms):
		# Record only an actual native-to-artifact handoff, never a UI preview.
		# Same-timestamp effects may change conditions before final execution.
		artifacts.note_warming_decision(actor, at_ms)
		return true
	if spirit_sources.wants_decision(actor, at_ms):
		spirit_sources.note_decision(actor, at_ms)
		return true
	if autonomous_livelihood.wants_decision(actor, at_ms):
		return true
	if source_care != null and source_care.wants_decision(actor, at_ms):
		source_care.note_decision(actor, at_ms)
		return true
	if field_opportunities != null and field_opportunities.wants_decision(actor, at_ms):
		field_opportunities.note_decision(actor, at_ms)
		return true
	return false


func autonomous_decision(actor: String) -> bool:
	if services == null:
		return false
	var region: String = services.actor_home(actor)
	if region.is_empty():
		return false
	var sim: VillageSimulation = regions[region]
	if not sim.actor_is_autonomous(actor) or sim.actor_has_action(actor):
		return false
	var person: Dictionary = sim.synchronize_actor(actor)
	return sim.elapsed_ms == elapsed_ms and bool(person.autonomous) and person.active.is_empty() and int(person.retry_ms) - int(sim.config.decision_interval) * MINUTE_MS == elapsed_ms and person.hunger > sim.config.needs.eat_below and person.energy > sim.config.needs.rest_below and native_action_allowed(actor)


func native_action_allowed(actor_id: String) -> bool:
	return actor_controls(actor_id, "action") and not body_action_owns(actor_id) and (construction == null or construction.duty_for(actor_id).is_empty()) and (resting == null or resting.duty_for(actor_id).is_empty())


func set_local_action_owner(provider: Callable) -> void:
	_local_action_owner = provider


func local_action_owns(actor_id: String) -> bool:
	return owns_for_scope(actor_id, &"local")


func body_action_owns(actor_id: String, except_domain: StringName = &"") -> bool:
	return owns_for_scope(actor_id, &"body", except_domain)


func owns_for_scope(actor_id: String, scope: StringName, except_domain: StringName = &"") -> bool:
	# Fail closed for a misspelled internal profile. Actor existence/control and
	# native actor.active remain separate checks at the corresponding entry point.
	if not ACTIVITY_PROFILES.has(scope):
		return true
	var mask: int = int(ACTIVITY_PROFILES[scope])
	for name: StringName in ACTIVITY_DOMAINS:
		if name == except_domain or (int(ACTIVITY_DOMAINS[name]) & mask) == 0:
			continue
		var domain: Variant = get(name)
		if domain == null:
			continue
		if name == &"conflicts" and (mask & (ActivityScope.AUTOMATIC_MOTION | ActivityScope.STATIONARY)) != 0:
			if not bool(domain.walking_projection(actor_id).allowed):
				return true
		elif (name in [&"sparring", &"conflicts"] and (mask & SPARRING_PHASE_SCOPES) != 0):
			if domain.action_blocks(actor_id):
				return true
		elif domain.owns_actor(actor_id):
			return true
	return (mask & (ActivityScope.LOCAL | ActivityScope.BODY)) != 0 and except_domain != &"local_motion" and _local_action_owner.is_valid() and bool(_local_action_owner.call(actor_id))


func activity_previous_autonomy(actor_id: String) -> bool:
	# Mirrors the saved former-human policy. Current native autonomy and soul
	# errands have distinct meanings and are checked by the avatar validator.
	for name: StringName in ACTIVITY_DOMAINS:
		if (int(ACTIVITY_DOMAINS[name]) & ActivityScope.RETURN_AUTONOMY) == 0:
			continue
		var domain: Variant = get(name)
		if domain == null:
			continue
		if domain.has_method("previous_autonomy"):
			if domain.previous_autonomy(actor_id):
				return true
		elif bool(domain.active.get(actor_id, {}).get("previous_autonomous", false)):
			return true
	return false


func actor_controls(actor_id: String, channel: String) -> bool:
	if not accepts_commands():
		return false
	if embodiment == null or not embodiment.self_controls_actor(actor_id, channel):
		return false
	for simulation: VillageSimulation in regions.values():
		if simulation.has_actor(actor_id):
			return simulation.actor_is_alive(actor_id)
	return false


func _prepare_control_change(source: Dictionary) -> bool:
	if source.kind != "village_actor":
		return true
	if not accepts_commands():
		return false
	for region: String in regions:
		if regions[region].has_actor(str(source.id)):
			return synchronize_region(region)
	return false


static func _actor_ids(instances: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for simulation: VillageSimulation in instances.values():
		for actor_id: String in simulation.actor_ids():
			result.append(actor_id)
	result.sort()
	return result


func next_runtime_boundary_ms(limit_ms: int) -> int:
	# This read-only outer boundary intentionally preserves the adapter's former
	# subset and has no elapsed_ms clamp. advance_to_ms handles all other world
	# boundaries; the adapter separately handles its player journey.
	return settlement.next_boundary_ms(limit_ms, true)


func advance_to(requested_time: int, max_events: int = 4096) -> bool:
	@warning_ignore("integer_division")
	var maximum_minute: int = MAX_COUNT / MINUTE_MS
	if requested_time < 0 or requested_time > maximum_minute:
		return false
	return advance_to_ms(requested_time * MINUTE_MS, max_events)


func advance_to_ms(requested_ms: int, max_events: int = 4096, work_budget: int = MAX_COUNT, should_yield: Callable = Callable()) -> bool:
	if settlement == null or settlement.is_executing() or _native_committing or _publishing_boundary:
		return false
	settlement_work = 0
	if construction != null and construction._changing:
		return false
	if object_lifecycle != null and object_lifecycle._committing:
		return false
	if environment_fields is SimWorldEnvironmentFields and not environment_fields.activate_sources():
		errors.append("Environmental sources could not activate before advancing")
		return false
	if environment_fields is SimWorldEnvironmentFields and not has_pending_boundary() and not environment_fields.flush_sources(elapsed_ms):
		return false
	if requested_ms < elapsed_ms or requested_ms > MAX_COUNT or regions.is_empty():
		return false
	if object_lifecycle.environment_change_pending() and not has_pending_boundary():
		return false
	_environment_response = null
	target_ms = maxi(target_ms, requested_ms)
	var processed: int = 0
	if settlement.is_pending():
		if requested_ms < settlement.at_ms:
			return false
		if processed >= maxi(0, max_events) or not _complete_boundary(work_budget, should_yield):
			return false
		processed += 1
	# A retained larger request is debt, not permission to overshoot this
	# invocation's accepted interval (the shared clock may be resuming a slice).
	while elapsed_ms < requested_ms:
		if processed >= maxi(0, max_events) or settlement_work >= maxi(0, work_budget) or should_yield.is_valid() and bool(should_yield.call()):
			return false
		var next_ms: int = mini(requested_ms, _next_boundary(requested_ms))
		for region_id: String in regions:
			if region_id == active_region or _dirty_region_boundaries.has(region_id) or regions[region_id].boundary_dependencies_changed():
				_region_boundaries[region_id] = regions[region_id].next_world_boundary_ms()
				_dirty_region_boundaries.erase(region_id)
			next_ms = mini(next_ms, int(_region_boundaries[region_id]))
		# Numeric/ledger exhaustion must leave all original clocks and bodies at
		# the last accepted boundary. Keep target_ms as explicit owed work.
		if not environment_fields.can_settle_at_ms(next_ms):
			errors.append("Environment fields exceed their declared numerical budget")
			return false
		var old_ms: int = elapsed_ms
		# Manual override must be accepted before the kernel closes external
		# commands. It executes exactly once for this newly admitted interval.
		_native_committing = true
		if _manual_motion_executor.is_valid():
			_manual_motion_executor.call(elapsed_ms, next_ms)
		_native_committing = false
		_native_regions.clear()
		_native_region_cursor = 0
		for region_id: String in _sorted_keys(regions):
			if region_id == active_region or int(_region_boundaries[region_id]) <= next_ms or regions[region_id].next_boundary_ms() <= next_ms:
				_native_regions.append(region_id)
		if not settlement.begin(old_ms, next_ms):
			errors.append("Settlement boundary could not begin")
			return false
		if not _complete_boundary(work_budget - settlement_work, should_yield):
			return false
		processed += 1
	return true


func _settle_native_interval(next_ms: int, _budget: int) -> Vector2i:
	# Submit all independent regions before checking their completion. The
	# shared logical boundary stays unpublished until every original owner ends.
	for region_id: String in _native_regions:
		regions[region_id].prepare_actor_advance(next_ms)
	var ready: bool = true
	for region_id: String in _native_regions:
		if not regions[region_id].actor_advance_ready():
			ready = false
	if not ready:
		return Vector2i(1, SimSettlementKernel.Status.PENDING)
	while _native_region_cursor < _native_regions.size():
		var region_id: String = _native_regions[_native_region_cursor]
		var simulation: VillageSimulation = regions[region_id]
		if not simulation.advance_to_ms(next_ms, 4096, settlement.should_yield_work):
			if simulation.has_pending_actor_interval():
				return Vector2i(1, SimSettlementKernel.Status.PENDING)
			errors.append("Regional executor could not reach its next boundary")
			return Vector2i(1, SimSettlementKernel.Status.FAILED)
		_region_boundaries[region_id] = simulation.next_world_boundary_ms()
		_dirty_region_boundaries.erase(region_id)
		_native_region_cursor += 1
	_native_regions.clear()
	elapsed_ms = next_ms
	return Vector2i(1, SimSettlementKernel.Status.COMPLETE)


func close_actor_execution() -> void:
	for simulation: VillageSimulation in regions.values():
		simulation.close_actor_execution()


func _complete_boundary(work_budget: int, should_yield: Callable = Callable()) -> bool:
	var status: int = settlement.resume(work_budget, should_yield)
	settlement_work += settlement.last_work
	_environment_boundary_waiting = settlement.is_pending() and settlement.progress().step == "object_lifecycle"
	if status != SimSettlementKernel.Status.COMPLETE:
		if status == SimSettlementKernel.Status.FAILED and (errors.is_empty() or errors[-1] != settlement.error):
			errors.append(settlement.error)
		return false
	if environment_fields is SimWorldEnvironmentFields and not environment_fields.flush_sources(elapsed_ms):
		errors.append("Environmental source dependencies could not publish")
		return false
	_environment_event = null
	_settled_ms = elapsed_ms
	simulation_work.boundaries = int(simulation_work.boundaries) + 1
	# Internal indexes were updated synchronously by their owners. Public
	# results wait for all domains; observers cannot reenter this publication.
	_publishing_boundary = true
	var notices: Array[Dictionary] = _finished_notices
	_finished_notices = []
	for notice: Dictionary in notices:
		action_finished.emit(notice)
	boundary_settled.emit(elapsed_ms)
	_publishing_boundary = false
	return true


func set_active_region(region_id: String) -> bool:
	if not accepts_commands() or (not region_id.is_empty() and not regions.has(region_id)) or elapsed_ms != target_ms:
		return false
	if not region_id.is_empty() and not synchronize_region(region_id):
		return false
	invalidate_region(active_region)
	# Ownership is changed in place. No actor is initialized, cancelled or rerolled.
	active_region = region_id
	return true


func synchronize_region(region_id: String, actor_id: String = "") -> bool:
	if not regions.has(region_id):
		return false
	var simulation: VillageSimulation = regions[region_id]
	# Synchronization only catches up elapsed time. Multiple domains may need
	# the same region at one boundary; do not rerun its full deadline scan or
	# emit another empty advance for each actor/job. Mutations still call
	# invalidate_region, including when the region is already current.
	if simulation.elapsed_ms == elapsed_ms:
		if actor_id.is_empty():
			simulation.synchronize_actors()
		else:
			simulation.synchronize_actor(actor_id)
		return true
	if not simulation.advance_to_ms(elapsed_ms):
		return false
	_region_boundaries[region_id] = simulation.next_world_boundary_ms()
	_dirty_region_boundaries.erase(region_id)
	if actor_id.is_empty():
		simulation.synchronize_actors()
	else:
		simulation.synchronize_actor(actor_id)
	return true


func invalidate_region(region_id: String, actor_id: String = "") -> void:
	# Original owners invalidate after changing a region. Coalesce repeated
	# mutations at one boundary; recompute before the next scheduling decision.
	if regions.has(region_id):
		_dirty_region_boundaries[region_id] = true
		if actor_id.is_empty():
			regions[region_id].invalidate_boundary_cache()
		else:
			regions[region_id].invalidate_actor_boundary(actor_id)


func _next_herb_sample_ms() -> int:
	var next: int = MAX_COUNT
	for sim: VillageSimulation in regions.values():
		next = mini(next, sim.land_resources.next_ecology_sample_ms())
	return next


static func herb_conditions_for(content: ReolContentDB, weather_state: Dictionary, point: Vector2i, at_ms: int, heat_tenths: int = 0) -> Dictionary:
	# A pure projection shared by live sampling and the explicit old-save
	# activation. Plant conditions never inherit human clothes or comfort.
	if content == null or not SimInventory._valid_count(at_ms) or not SimInventory._valid_count(weather_state.get("epoch_ms")):
		return {}
	var background: Dictionary = SimClimateRules.background_at(content.climate, content.weather, int(weather_state.epoch_ms), point, at_ms)
	if background.is_empty():
		return {}
	return {"temperature_tenths": int(background.temperature_tenths) + heat_tenths,
		"heat_tenths": heat_tenths, "rain": background.kind == "rain"}


func _sample_herb_conditions(opening: bool = false) -> bool:
	if not opening and posmod(elapsed_ms, MINUTE_MS) != 0:
		# MAX_COUNT is a scheduling sentinel, never a fabricated final sample.
		return true
	for region: String in _sorted_keys(regions):
		var sim: VillageSimulation = regions[region]
		if not opening and sim.land_resources.next_ecology_sample_ms() > elapsed_ms:
			continue
		# Sources integrate their old cached law before the parent samples the
		# new one. A quiet far village is still synchronized at this boundary.
		if not synchronize_region(region):
			return false
		for id: String in _sorted_keys(sim.land_resources.sources):
			if sim.land_resources.sources[id].ecology.is_empty():
				continue
			var place: String = str(sim.config.resource_sources[id].place)
			var point: Vector2i = _cell(sim.places[place].cell)
			var projected: Dictionary = environment_fields.project_tenths(point, elapsed_ms)
			if not bool(projected.supported):
				return false
			var heat: int = int(projected.value)
			var conditions: Dictionary = herb_conditions_for(_content, weather.to_dict(), point, elapsed_ms, heat)
			if conditions.is_empty() or not sim.land_resources.set_ecology_conditions(id, elapsed_ms,
				int(conditions.temperature_tenths), bool(conditions.rain), int(conditions.heat_tenths)):
				return false
		invalidate_region(region)
	return true


func _valid_herb_conditions() -> bool:
	for sim: VillageSimulation in regions.values():
		for id: String in sim.land_resources.sources:
			var ecology: Dictionary = sim.land_resources.sources[id].ecology
			if ecology.is_empty():
				continue
			if int(ecology.activation_ms) < weather.epoch_ms:
				return false
			var point: Vector2i = _cell(sim.places[sim.config.resource_sources[id].place].cell)
			var at_ms: int = int(ecology.sample_ms)
			var heat: int = int(ecology.heat_tenths)
			if at_ms == environment_fields.last_sample_ms:
				if environment_fields is SimWorldEnvironmentFields and not bool(environment_fields.sample_result(point, at_ms).get("supported", false)):
					return false
				if environment_fields.sample_tenths(point, at_ms) != heat:
					return false
			elif at_ms == elapsed_ms:
				var projected: Dictionary = environment_fields.project_tenths(point, at_ms)
				if not bool(projected.supported) or int(projected.value) != heat:
					return false
			elif at_ms != int(ecology.activation_ms):
				return false
			elif environment_fields is SimWorldEnvironmentFields:
				# The response field begins at the committed climate background.
				# Only that actual activation sample is known to be neutral; an
				# older sample cannot be reconstructed from today's field.
				if at_ms != int(environment_fields.activation_ms) or heat != 0:
					return false
			else:
				# A migrated source can retain its activation sample across the
				# first partial minute. That older heat slice is no longer stored
				# by the heat field: check its finite source/space upper bound,
				# without pretending to replay an unavailable thermal history.
				var key: String = "%d,%d" % [point.x, point.y]
				@warning_ignore("integer_division")
				if environment_fields is LegacyHeatV1:
					var maximum: int = mini(int(environment_fields.definitions.max_cell_energy), int(environment_fields.input_energy)) / int(environment_fields.definitions.capacity_per_tenth)
					if heat < 0 or heat > maximum or heat > 0 and not environment_fields.cells.has(key):
						return false
				elif at_ms < int(environment_fields.model_started_ms):
					var limits: Dictionary = environment_fields.legacy_limits
					var maximum: int = mini(int(environment_fields.definitions.max_cell_energy) - 13000 * int(environment_fields.definitions.capacity_per_tenth), int(limits.get("input_energy", 0))) / int(environment_fields.definitions.capacity_per_tenth)
					if limits.is_empty() or heat < 0 or heat > maximum or heat > 0 and not limits.cells.has(key):
						return false
				elif heat < environment_fields.minimum_offset_tenths() or heat > environment_fields.maximum_offset_tenths() or heat != 0 and not environment_fields.has_cell(point):
					return false
			var expected: Dictionary = herb_conditions_for(_content, weather.to_dict(), point, at_ms, heat)
			if expected.is_empty() or int(ecology.temperature_tenths) != int(expected.temperature_tenths) or bool(ecology.rain) != bool(expected.rain):
				return false
			var rules: Dictionary = sim.land_resources.terms_for(id).ecology
			var first_sample: int = SimHerbEcologyRules.next_sample_ms({"sample_ms": ecology.activation_ms, "activation_ms": ecology.activation_ms}, rules)
			var latest: int = sim.elapsed_ms - posmod(sim.elapsed_ms, int(rules.sample_ms))
			var expected_sample: int = int(ecology.activation_ms) if latest - int(ecology.activation_ms) < int(rules.sample_ms) else latest
			if at_ms != expected_sample:
				return false
			var rain_ms: int = _herb_rain_duration(_content.weather, weather.to_dict(), SimClimateRules.region_at(_content.climate, point), int(ecology.activation_ms), sim.elapsed_ms, first_sample)
			if not SimHerbEcologyRules._within_rate(int(ecology.rain_input), int(rules.rain_per_ms), rain_ms):
				return false
	return true


static func _herb_rain_duration(rules: Dictionary, weather_state: Dictionary, region: String, activation: int, now: int, first_sample: int) -> int:
	# Integrate the same held minute samples as the live process. This is an
	# upper bound on accepted atmospheric water, computed in O(weather phases)
	# even for old worlds; it does not invent a minute-by-minute event history.
	var epoch: int = int(weather_state.epoch_ms)
	var duration: int = mini(now, first_sample) - activation if SimWeather.kind_at(rules, region, epoch, activation) == "rain" else 0
	if now <= first_sample:
		return duration
	var last: int = now - posmod(now, MINUTE_MS)
	var shift: int = int(rules.regions[region].offset_ms) - epoch
	var cycle: int = 0
	for phase: Dictionary in rules.phases:
		cycle += int(phase.duration_ms)
	var start: int = 0
	if last > first_sample:
		for phase: Dictionary in rules.phases:
			var end: int = start + int(phase.duration_ms)
			if phase.kind == "rain":
				duration += (SimWeather._pulse_prefix(last - MINUTE_MS + shift, cycle, start, end) - SimWeather._pulse_prefix(first_sample - MINUTE_MS + shift, cycle, start, end)) * MINUTE_MS
			start = end
	if last >= first_sample and SimWeather.kind_at(rules, region, epoch, last) == "rain":
		duration += now - last
	return duration


func synchronize_regions() -> bool:
	for region_id: String in _sorted_keys(regions):
		if not synchronize_region(region_id):
			return false
	return true


func set_route_blocked(route_id: String, blocked: bool) -> bool:
	if not routes.has(route_id) or elapsed_ms != target_ms:
		return false
	if bool(routes[route_id].blocked) == blocked:
		return true
	routes[route_id].blocked = blocked
	var definition: Dictionary = settings.routes[route_id]
	var courier: Dictionary = couriers[definition.courier]
	var shipment_id: String = courier.shipment
	if courier.phase == "outbound" and shipments.has(shipment_id):
		shipments[shipment_id].status = "blocked" if blocked else "outbound"
	_record(
		"road_blocked" if blocked else "road_reopened", definition.from, route_id,
		"山路受阻，行旅暂候。" if blocked else "山路恢复通行，行旅继续。"
	)
	return true


func request_delivery(route_id: String) -> bool:
	if not routes.has(route_id):
		return false
	var definition: Dictionary = settings.routes[route_id]
	var demand: int = delivery_need(route_id)
	# Warehouse keepers send a stock report. The supplier acts on this delivered
	# report, not on direct access to another settlement's current inventory.
	_queue_message("stock_request", definition.to, definition.from, route_id, {
		"amount": demand, "observed_at": current_time,
		"line": "%s来信：%s。" % [_label(definition.to), "请求补粮" if demand > 0 else "暂不缺粮"],
	})
	return true


## Destination-side assessment shared by work offers and stock reports.
## The source still dispatches only against reports that have reached it.
func delivery_need(route_id: String) -> int:
	if not routes.has(route_id):
		return 0
	var definition: Dictionary = settings.routes[route_id]
	if not synchronize_region(definition.to):
		return 0
	var expected: int = regions[definition.to].inventory.quantity(definition.target, definition.item)
	for shipment: Dictionary in shipments.values():
		var other: Dictionary = settings.routes[shipment.route]
		if other.to == definition.to and other.target == definition.target and other.item == definition.item and shipment.status in ["outbound", "blocked"]:
			expected += int(shipment.amount)
	if services != null:
		expected += services.expected_deliveries(definition.to, definition.target, definition.item)
	return maxi(0, int(definition.stock_below) - expected)


## An accepted contract or dispatched cargo claims reports already sent.
## This adjusts known commitments, not knowledge of current remote stock.
func reserve_delivery(route_id: String, amount: int) -> void:
	if not routes.has(route_id) or amount <= 0 or amount > MAX_COUNT:
		return
	var definition: Dictionary = settings.routes[route_id]
	for other_id: String in routes:
		var other: Dictionary = settings.routes[other_id]
		if other.to != definition.to or other.target != definition.target or other.item != definition.item:
			continue
		routes[other_id].demand = maxi(0, int(routes[other_id].demand) - amount)
		for message: Dictionary in messages:
			if message.kind == "stock_request" and message.route == other_id:
				message.details.amount = maxi(0, int(message.details.amount) - amount)
				message.details.line = "%s来信：%s。" % [_label(other.to), "请求补粮" if int(message.details.amount) > 0 else "暂不缺粮"]


func courier_cell(courier_id: String) -> Vector2:
	if not couriers.has(courier_id):
		return Vector2.ZERO
	var courier: Dictionary = couriers[courier_id]
	var definition: Dictionary = settings.routes[courier.route]
	var origin: Array = regions[definition.from].places[definition.source].cell
	var destination: Array = regions[definition.to].places[definition.target].cell
	var fraction: float = float(courier.progress) / float(definition.travel_minutes)
	if courier.phase == "returning":
		fraction = 1.0 - fraction
	elif courier.phase in ["idle", "resting"]:
		fraction = 0.0
	var path: Array = definition.get("path", [])
	if path.size() >= 2:
		var offset: float = clampf(fraction, 0.0, 1.0) * float(path.size() - 1)
		var index: int = mini(int(offset), path.size() - 2)
		return _cell(path[index]).lerp(_cell(path[index + 1]), offset - float(index))
	return _cell(origin).lerp(_cell(destination), clampf(fraction, 0.0, 1.0))


func known_event_lines(region_id: String, limit: int = 3) -> Array[String]:
	var result: Array[String] = []
	var known: Array = local_news.get(region_id, [])
	for index in range(maxi(0, known.size() - maxi(0, limit)), known.size()):
		result.append(str(known[index].line))
	return result


func to_dict() -> Dictionary:
	if services != null and services._handling_stock:
		return {}
	if _publishing_boundary or has_pending_boundary() or construction != null and construction._changing or environment_boundary_active() or (object_lifecycle != null and (object_lifecycle._committing or object_lifecycle.environment_change_pending())):
		return {}
	if not synchronize_regions() or not environment_fields.settle_at_ms(elapsed_ms):
		return {}
	var regional_states: Dictionary = {}
	for region_id: String in _sorted_keys(regions):
		regional_states[region_id] = regions[region_id].to_dict()
	var snapshot: Dictionary = {
		"version": SCHEMA_VERSION, "settings": settings.duplicate(true),
		"current_time": current_time, "target_time": target_time, "elapsed_ms": elapsed_ms, "target_ms": target_ms,
		"active_region": active_region, "regions": regional_states,
		"routes": routes.duplicate(true), "shipments": shipments.duplicate(true),
		"couriers": couriers.duplicate(true), "events": events.duplicate(true),
		"messages": messages.duplicate(true), "local_news": local_news.duplicate(true),
		"operations": operations.duplicate(true), "in_transit": in_transit.to_dict(),
		"next_id": _next_id,
	}
	var domains := SaveDomains.registry(services != null)
	var captured: Dictionary = domains.capture(self)
	if captured.is_empty():
		return {}
	snapshot.merge(captured)
	return _json_keys(snapshot)


func restore(data: Dictionary, legacy_heat_v1: bool = false, legacy_heat_v2: bool = false) -> bool:
	if _publishing_boundary or has_pending_boundary() or object_lifecycle != null and object_lifecycle._committing:
		return false
	# The current model cannot reconstruct causal field residuals from a Q
	# archive. Historical importers remain evidence, not a second running engine.
	if legacy_heat_v1 or legacy_heat_v2 or data.get("version") != SCHEMA_VERSION:
		return false
	if construction != null and construction._changing or environment_boundary_active() or (object_lifecycle != null and object_lifecycle.environment_change_pending()) or (_environment_guard != null and _environment_guard.get_ref() != null):
		return false
	# Validation constructs an entirely separate world. Failed loads preserve
	# existing regional objects, inventory and pending deliveries.
	# Earlier regional and thermal versions are rejected before validation.
	if _content == null or not _valid_world_shape(data):
		return false
	if (services != null) != data.has("services"):
		return false
	var allowed_subjects: Dictionary = {}
	for saved_region: Variant in data.regions.values():
		if not saved_region is Dictionary or not saved_region.get("actors") is Dictionary:
			return false
		for actor_id: Variant in saved_region.actors:
			if not actor_id is String or allowed_subjects.has(actor_id):
				return false
			allowed_subjects[actor_id] = true
	var domains := SaveDomains.registry(services != null)
	var next_regions: Dictionary = {}
	var subject_scope: Dictionary = allowed_subjects if services != null else {}
	for region_id: String in _sorted_keys(regions):
		var saved: Dictionary = data.regions[region_id]
		if not saved.get("actors") is Dictionary or not saved.get("places") is Dictionary or not saved.get("config") is Dictionary:
			return false
		if not SimLandResources.opening_matches(_base_workplace_config(saved.config), _base_workplace_config(opening_config(region_id))):
			return false
		var inventory_scope: Dictionary = domains.inventory_scope(data, region_id, _content)
		if inventory_scope.is_empty():
			return false
		inventory_scope["service_custody"] = services != null
		inventory_scope["rainfall_limit"] = SimWeather.rain_budget(data.weather, _content.weather, region_id, int(data.elapsed_ms))
		var simulation: VillageSimulation = VillageSimulation.from_snapshot(_content, saved, subject_scope, inventory_scope)
		if simulation == null:
			return false
		if simulation.elapsed_ms != int(data.elapsed_ms):
			return false
		# Navigation is an adapter, never serialized. Keep the caller's provider.
		simulation.set_navigation(regions[region_id]._navigation, regions[region_id]._step_validator)
		next_regions[region_id] = simulation
	# A restore-only factory has no initialized opening instances to validate.
	# Check actual restored owners, route endpoints and clocks before any commit.
	if not _valid_settings(settings, next_regions):
		return false
	var next_transit := SimInventory.new()
	if not next_transit.restore(data.in_transit) or not _valid_cross_state(data, next_regions, next_transit):
		return false
	var candidate_world := RegionalSimulation.new()
	candidate_world.map_data = map_data
	candidate_world.regions = next_regions
	candidate_world.settings = settings
	candidate_world.elapsed_ms = int(data.elapsed_ms)
	candidate_world.target_ms = int(data.target_ms)
	candidate_world.routes = data.routes.duplicate(true)
	candidate_world.shipments = data.shipments.duplicate(true)
	candidate_world.couriers = data.couriers.duplicate(true)
	candidate_world.operations = data.operations.duplicate(true)
	candidate_world.in_transit = next_transit
	candidate_world._content = _content
	var context: Dictionary = {"world": candidate_world, "source": self, "content": _content, "data": data}
	if not domains.stage(data, context):
		return false
	# Candidate checks use only candidate geometry. Reattach live adapter
	# callbacks after every domain has passed validation, before old owners go.
	if map_data != null:
		if large_bodies != null:
			context["large_incoming"] = large_bodies._incoming
		if construction != null:
			context["construction_incoming"] = construction._incoming
		if avian_life != null:
			context["avian_landing"] = avian_life._landing
	regions = next_regions
	elapsed_ms = int(data.elapsed_ms)
	target_ms = int(data.target_ms)
	active_region = data.active_region
	routes = data.routes.duplicate(true)
	shipments = data.shipments.duplicate(true)
	couriers = data.couriers.duplicate(true)
	events = data.events.duplicate(true)
	messages = data.messages.duplicate(true)
	local_news = data.local_news.duplicate(true)
	operations = data.operations.duplicate(true)
	in_transit = next_transit
	_next_id = int(data.next_id)
	if plants != null:
		plants.retire_bindings()
	var installed: bool = domains.install(self, context)
	assert(installed, "validated saved-world participants must install")
	_bind_service_guards()
	_region_boundaries = {}
	_dirty_region_boundaries.clear()
	for region_id: String in regions:
		_region_boundaries[region_id] = regions[region_id].next_boundary_ms()
	_replace_space()
	return _bind_settlement()


func _next_boundary(limit_ms: int) -> int:
	var boundary: int = settlement.next_boundary_ms(limit_ms)
	boundary = mini(boundary, _next_herb_sample_ms())
	if services != null:
		boundary = mini(boundary, services.next_boundary_ms())
	for route_id: String in routes:
		var courier: Dictionary = couriers[settings.routes[route_id].courier]
		if courier.phase in ["outbound", "returning"] and not bool(routes[route_id].blocked):
			boundary = mini(boundary, (current_time + int(settings.routes[route_id].travel_minutes) - int(courier.progress)) * MINUTE_MS)
		elif courier.phase == "waiting_delivery":
			boundary = mini(boundary, int(courier.retry_at) * MINUTE_MS)
		elif courier.phase == "resting":
			boundary = mini(boundary, (current_time + int(courier.rest_remaining)) * MINUTE_MS)
	for message: Dictionary in messages:
		boundary = mini(boundary, int(message.due) * MINUTE_MS)
	return maxi(elapsed_ms + 1, boundary)


func _advance_journeys(elapsed: int) -> void:
	for courier: Dictionary in couriers.values():
		if courier.phase in ["outbound", "returning"] and not bool(routes[courier.route].blocked):
			courier.progress = int(courier.progress) + elapsed
			courier.energy = snappedf(maxf(0.0, float(courier.energy) - float(settings.courier_needs.energy_per_travel_minute) * elapsed), 0.000001)
		elif courier.phase == "resting":
			courier.rest_remaining = maxi(0, int(courier.rest_remaining) - elapsed)


func _process_arrivals() -> void:
	for courier_id: String in _sorted_keys(couriers):
		var courier: Dictionary = couriers[courier_id]
		var definition: Dictionary = settings.routes[courier.route]
		if courier.phase == "resting" and int(courier.rest_remaining) <= 0:
			courier.energy = minf(100.0, float(courier.energy) + float(settings.courier_needs.rest_gain))
			courier.phase = "idle"
		elif courier.phase == "waiting_delivery" and int(courier.retry_at) <= current_time:
			_deliver(courier_id)
		elif courier.phase in ["outbound", "returning"] and int(courier.progress) >= int(definition.travel_minutes):
			if courier.phase == "outbound":
				_deliver(courier_id)
			else:
				courier.phase = "idle"
				courier.progress = 0
				courier.shipment = ""
				_record("returned", definition.from, courier.route, "%s已空车返回。" % courier.name)


func _process_messages() -> void:
	var pending: Array = []
	for message: Dictionary in messages:
		if int(message.due) > current_time:
			pending.append(message)
			continue
		if message.kind == "stock_request":
			var route: Dictionary = routes[message.route]
			if int(message.details.observed_at) >= int(route.request_time):
				route.demand = int(message.details.amount)
				route.request_time = int(message.details.observed_at)
		local_news[message.to].append({
			"id": message.id, "source": message.from, "heard_at": current_time,
			"occurred_at": message.sent_at, "line": message.details.line,
		})
		simulation_work.messages = int(simulation_work.messages) + 1
	messages = pending


func _try_dispatch(route_id: String, force_service: bool = false) -> void:
	var route: Dictionary = routes[route_id]
	var definition: Dictionary = settings.routes[route_id]
	var courier: Dictionary = couriers[definition.courier]
	if not force_service and services != null and services.courier_claimed(str(definition.courier)):
		return
	if courier.phase != "idle" or bool(route.blocked) or int(route.demand) <= 0:
		return
	if float(courier.energy) < float(settings.courier_needs.rest_below):
		courier.phase = "resting"
		courier.rest_remaining = int(settings.courier_needs.rest_minutes)
		_record("resting", definition.from, route_id, "%s精力不足，先休息再赶路。" % courier.name)
		return
	var source: VillageSimulation = regions[definition.from]
	var surplus: int = source.inventory.available(definition.source, definition.item) - int(definition.reserve_floor)
	# The timeline has already processed every earlier inventory event. A zero
	# surplus in a quiet region therefore cannot change before its cached event.
	if surplus <= 0 or not synchronize_region(definition.from):
		return
	surplus = source.inventory.available(definition.source, definition.item) - int(definition.reserve_floor)
	var amount: int = mini(int(definition.amount), mini(int(route.demand), surplus))
	if amount <= 0:
		return
	var shipment_id: String = _allocate("shipment")
	var container: String = "cargo:" + shipment_id
	in_transit.create_container(container, {})
	if not _move_goods(shipment_id + ":pickup", source.inventory, definition.source, in_transit, container, definition.item, amount, definition.from, "transit"):
		return
	shipments[shipment_id] = {
		"id": shipment_id, "route": route_id, "item": definition.item, "amount": amount,
		"status": "outbound", "departed_at": current_time, "delivered_at": -1,
		"container": container,
	}
	courier.phase = "outbound"
	courier.shipment = shipment_id
	courier.progress = 0
	reserve_delivery(route_id, amount)
	_record("departed", definition.from, route_id, "%s带着%d份粮食出发了。" % [courier.name, amount])
	invalidate_region(definition.from)


func _deliver(courier_id: String) -> void:
	var courier: Dictionary = couriers[courier_id]
	var definition: Dictionary = settings.routes[courier.route]
	var shipment: Dictionary = shipments[courier.shipment]
	var destination: VillageSimulation = regions[definition.to]
	if not synchronize_region(definition.to):
		return
	if not _move_goods(shipment.id + ":delivery", in_transit, shipment.container, destination.inventory, definition.target, shipment.item, int(shipment.amount), "transit", definition.to):
		# A full destination keeps its cargo in custody and retries after the next
		# assessment. It does not silently lose or refund the transported goods.
		courier.phase = "waiting_delivery"
		courier.progress = int(definition.travel_minutes)
		courier.retry_at = current_time + int(definition.assessment_minutes)
		return
	shipment.status = "delivered"
	shipment.delivered_at = current_time
	courier.phase = "returning"
	courier.progress = 0
	for actor: Dictionary in destination.synchronize_actors().values():
		if actor.active.is_empty():
			actor.retry_ms = mini(int(actor.retry_ms), elapsed_ms)
	simulation_work.deliveries = int(simulation_work.deliveries) + 1
	_record("delivered", definition.to, courier.route, "%s送到%d份粮食，已经入库。" % [courier.name, int(shipment.amount)])
	invalidate_region(definition.to)


func _move_goods(
	operation_id: String, source: SimInventory, source_container: String,
	destination: SimInventory, destination_container: String, item: String,
	amount: int, source_region: String, destination_region: String
) -> bool:
	var signature: Dictionary = {
		"from": source_region, "to": destination_region, "source": source_container,
		"target": destination_container, "item": item, "amount": amount,
	}
	if operations.has(operation_id):
		return _valid_transfer_receipt(operations[operation_id], source_region, destination_region, source_container, destination_container, item, amount)
	# Routes use configured workplaces and transit storage, never lifecycle
	# ground piles. Reject direct ledger writes that would bypass their indexes.
	if source_container.begins_with("ground:") or destination_container.begins_with("ground:"):
		return false
	if amount <= 0 or not source.containers.has(source_container) or not destination.containers.has(destination_container):
		return false
	if source.available(source_container, item) < amount or amount > MAX_COUNT - destination.quantity(destination_container, item):
		return false
	# Both ledgers and the operation receipt commit synchronously after every
	# precondition has passed. There is no callback or save boundary in between.
	source.containers[source_container][item] = source.quantity(source_container, item) - amount
	destination.containers[destination_container][item] = destination.quantity(destination_container, item) + amount
	operations[operation_id] = signature
	source.contents_changed.emit(source_container)
	destination.contents_changed.emit(destination_container)
	return true


func _record(kind: String, origin: String, route_id: String, line: String) -> void:
	var event_id: String = _allocate("event")
	events.append({"id": event_id, "kind": kind, "region": origin, "route": route_id, "at": current_time, "line": line})
	local_news[origin].append({"id": event_id, "source": origin, "heard_at": current_time, "occurred_at": current_time, "line": line})
	var definition: Dictionary = settings.routes[route_id]
	var other: String = definition.to if origin == definition.from else definition.from
	_queue_message("news", origin, other, route_id, {"line": "%s传来消息：%s" % [_label(origin), line]})


func _queue_message(kind: String, origin: String, destination: String, route_id: String, details: Dictionary) -> void:
	messages.append({
		"id": _allocate("message"), "kind": kind, "from": origin, "to": destination,
		"route": route_id, "sent_at": current_time,
		"due": current_time + int(settings.routes[route_id].message_minutes),
		"details": details.duplicate(true),
	})


func _allocate(prefix: String) -> String:
	var id: String = "world:%s:%d" % [prefix, _next_id]
	_next_id += 1
	return id


func _label(region_id: String) -> String:
	return str(settings.regions[region_id].label)


func _valid_settings(definitions: Dictionary, instances: Dictionary) -> bool:
	if definitions.get("schema_version") != DEFINITIONS_VERSION or not definitions.get("regions") is Dictionary or not definitions.get("routes") is Dictionary:
		return false
	if instances.is_empty() or not _string_keys(instances) or not _string_keys(definitions.regions) or not _string_keys(definitions.routes) or _sorted_keys(instances) != _sorted_keys(definitions.regions):
		return false
	if not definitions.get("active_region", "") is String or (not str(definitions.get("active_region", "")).is_empty() and not instances.has(definitions.active_region)):
		return false
	if not definitions.get("courier_needs") is Dictionary:
		return false
	var needs: Dictionary = definitions.courier_needs
	if not _number(needs.get("energy_per_travel_minute"), 0.0) or not _number(needs.get("rest_below"), 0.0, 100.0) or not _integer(needs.get("rest_minutes"), 1) or not _number(needs.get("rest_gain"), 1.0, 100.0):
		return false
	var time: int = -1
	var owners: Dictionary = {}
	var actor_ids: Dictionary = {}
	for region_id: Variant in instances:
		if not region_id is String or not instances[region_id] is VillageSimulation or not definitions.regions[region_id] is Dictionary:
			return false
		var simulation: VillageSimulation = instances[region_id]
		if owners.has(simulation.get_instance_id()):
			return false
		owners[simulation.get_instance_id()] = true
		for actor_id: String in simulation.synchronize_actors():
			if actor_ids.has(actor_id):
				return false
			actor_ids[actor_id] = true
		if simulation.synchronize_actors().is_empty() or (time >= 0 and time != simulation.elapsed_ms):
			return false
		time = simulation.elapsed_ms
		if not definitions.regions[region_id].get("label") is String:
			return false
	var used_couriers: Dictionary = {}
	for route_id: Variant in definitions.routes:
		if not route_id is String or not definitions.routes[route_id] is Dictionary:
			return false
		var route: Dictionary = definitions.routes[route_id]
		for field: String in ["from", "to", "source", "target", "item", "courier", "courier_name"]:
			if not route.get(field) is String or str(route[field]).is_empty():
				return false
		if not instances.has(route.from) or not instances.has(route.to) or route.from == route.to or used_couriers.has(route.courier) or actor_ids.has(route.courier):
			return false
		used_couriers[route.courier] = true
		var source: VillageSimulation = instances[route.from]
		var target: VillageSimulation = instances[route.to]
		if not source.inventory.containers.has(route.source) or not source.places.has(route.source) or not target.inventory.containers.has(route.target) or not target.places.has(route.target):
			return false
		for field: String in ["amount", "stock_below", "travel_minutes", "assessment_minutes", "message_minutes"]:
			if not _integer(route.get(field), 1):
				return false
		if not _integer(route.get("reserve_floor"), 0):
			return false
		if route.has("path"):
			if not route.path is Array or route.path.size() < 2:
				return false
			for point: Variant in route.path:
				if not _valid_cell(point):
					return false
	return true


func _valid_world_shape(data: Dictionary) -> bool:
	if data.get("version") != SCHEMA_VERSION or _normalized(data.get("settings")) != _normalized(settings):
		return false
	for field: String in ["regions", "routes", "shipments", "couriers", "local_news", "operations", "in_transit"]:
		if not data.get(field) is Dictionary:
			return false
	if not SaveDomains.registry(services != null).valid_shape(data):
		return false
	if data.spirit_sources.get("version") != SimSpiritSources.VERSION:
		return false
	for field: String in ["events", "messages"]:
		if not data.get(field) is Array:
			return false
	if not _integer(data.get("current_time"), 0) or not _integer(data.get("target_time"), int(data.current_time)) or not _integer(data.get("next_id"), 1):
		return false
	if not _integer(data.get("elapsed_ms"), 0) or not _integer(data.get("target_ms"), int(data.elapsed_ms)):
		return false
	if int(data.current_time) != floori(float(data.elapsed_ms) / MINUTE_MS) or int(data.target_time) != floori(float(data.target_ms) / MINUTE_MS):
		return false
	if not data.get("active_region") is String or (not str(data.active_region).is_empty() and not regions.has(data.active_region)):
		return false
	return _sorted_keys(data.regions) == _sorted_keys(regions) and _sorted_keys(data.routes) == _sorted_keys(routes) and _sorted_keys(data.couriers) == _sorted_keys(couriers) and _sorted_keys(data.local_news) == _sorted_keys(regions)


func _valid_cross_state(data: Dictionary, candidates: Dictionary, cargo: SimInventory) -> bool:
	var time: int = int(data.current_time)
	var ids: Dictionary = {}
	for route_id: String in data.routes:
		var route: Variant = data.routes[route_id]
		if not route is Dictionary or route.has("next_assessment") or not route.get("blocked") is bool or not _integer(route.get("demand"), 0) or not _integer(route.get("request_time"), -1, time):
			return false
	for shipment_id: Variant in data.shipments:
		var shipment: Variant = data.shipments[shipment_id]
		if not shipment_id is String or not shipment is Dictionary or shipment.get("id") != shipment_id or not _unique_id(shipment_id, ids, int(data.next_id)):
			return false
		if not data.routes.has(shipment.get("route")) or not shipment.get("status") in ["outbound", "blocked", "delivered"] or not _integer(shipment.get("amount"), 1) or not _integer(shipment.get("departed_at"), 0, time):
			return false
		var definition: Dictionary = settings.routes[shipment.route]
		if shipment.get("item") != definition.item or shipment.get("container") != "cargo:" + String(shipment_id) or not cargo.containers.has(shipment.container):
			return false
		var delivered: bool = shipment.status == "delivered"
		if not _integer(shipment.get("delivered_at"), int(shipment.departed_at) if delivered else -1, time if delivered else -1):
			return false
		if cargo.containers[shipment.container].size() != 1 or cargo.quantity(shipment.container, shipment.item) != (0 if delivered else int(shipment.amount)):
			return false
		if not _valid_transfer_receipt(data.operations.get(shipment_id + ":pickup"), definition.from, "transit", definition.source, shipment.container, shipment.item, int(shipment.amount)):
			return false
		if delivered and not _valid_transfer_receipt(data.operations.get(shipment_id + ":delivery"), "transit", definition.to, shipment.container, definition.target, shipment.item, int(shipment.amount)):
			return false
		if not delivered and data.operations.has(shipment_id + ":delivery"):
			return false
	for courier_id: String in data.couriers:
		var courier: Variant = data.couriers[courier_id]
		if not courier is Dictionary or courier.get("id") != courier_id or not data.routes.has(courier.get("route")):
			return false
		var definition: Dictionary = settings.routes[courier.route]
		if definition.courier != courier_id or courier.get("name") != definition.courier_name or not courier.get("phase") in ["idle", "outbound", "returning", "resting", "waiting_delivery"]:
			return false
		var maximum_progress: int = int(definition.travel_minutes) if courier.phase == "waiting_delivery" else int(definition.travel_minutes) - 1
		if not _number(courier.get("energy"), 0.0, 100.0) or not _integer(courier.get("progress"), 0, maximum_progress) or not _integer(courier.get("rest_remaining"), 0, int(settings.courier_needs.rest_minutes)) or not courier.get("shipment") is String:
			return false
		if courier.phase in ["outbound", "returning", "waiting_delivery"]:
			if not data.shipments.has(courier.shipment) or data.shipments[courier.shipment].route != courier.route:
				return false
			if (courier.phase == "returning") != (data.shipments[courier.shipment].status == "delivered"):
				return false
			if courier.phase == "outbound" and ((data.shipments[courier.shipment].status == "blocked") != bool(data.routes[courier.route].blocked)):
				return false
			if courier.phase == "waiting_delivery" and (not _integer(courier.get("retry_at"), time + 1) or int(courier.progress) != int(definition.travel_minutes)):
				return false
		elif courier.shipment != "" or int(courier.progress) != 0:
			return false
	for shipment: Dictionary in data.shipments.values():
		if shipment.status != "delivered" and data.couriers[settings.routes[shipment.route].courier].shipment != shipment.id:
			return false
	if not cargo.reservations.is_empty() or not cargo.operations.is_empty() or not cargo.custody.is_empty() or cargo.containers.size() != data.shipments.size():
		return false
	for region_id: String in data.local_news:
		if not data.local_news[region_id] is Array:
			return false
		for news: Variant in data.local_news[region_id]:
			if not news is Dictionary or not news.get("id") is String or not candidates.has(news.get("source")) or not news.get("line") is String or not _integer(news.get("occurred_at"), 0, time) or not _integer(news.get("heard_at"), int(news.occurred_at), time):
				return false
	for event: Variant in data.events:
		if not event is Dictionary or not event.get("kind") is String or not event.get("line") is String or not candidates.has(event.get("region")) or not data.routes.has(event.get("route")) or not _integer(event.get("at"), 0, time) or not _unique_id(event.get("id"), ids, int(data.next_id)):
			return false
	for message: Variant in data.messages:
		if not message is Dictionary or not message.get("kind") in ["stock_request", "news"] or not candidates.has(message.get("from")) or not candidates.has(message.get("to")) or message.from == message.to or not data.routes.has(message.get("route")):
			return false
		if not _integer(message.get("sent_at"), 0, time) or not _integer(message.get("due"), time + 1) or not message.get("details") is Dictionary or not message.details.get("line") is String or not _unique_id(message.get("id"), ids, int(data.next_id)):
			return false
		if message.kind == "stock_request" and (not _integer(message.details.get("amount"), 0) or not _integer(message.details.get("observed_at"), 0, int(message.sent_at))):
			return false
	var expected_operations: int = 0
	for shipment: Dictionary in data.shipments.values():
		expected_operations += 2 if shipment.status == "delivered" else 1
	return data.operations.size() == expected_operations


static func _valid_transfer_receipt(record: Variant, origin: String, destination: String, source: String, target: String, item: String, amount: int) -> bool:
	return (
		record is Dictionary and record.size() == 6
		and record.get("from") == origin and record.get("to") == destination
		and record.get("source") == source and record.get("target") == target
		and record.get("item") == item and _integer(record.get("amount"), amount, amount)
	)


static func _unique_id(value: Variant, used: Dictionary, next_id: int) -> bool:
	if not value is String or not String(value).begins_with("world:") or used.has(value):
		return false
	var tail: String = String(value).get_slice(":", 2)
	if not tail.is_valid_int() or int(tail) < 1 or int(tail) >= next_id:
		return false
	used[value] = true
	return true


static func _sorted_keys(value: Dictionary) -> Array:
	var keys: Array = value.keys()
	keys.sort()
	return keys


static func _string_keys(value: Dictionary) -> bool:
	for key: Variant in value:
		if not key is String or String(key).strip_edges().is_empty():
			return false
	return true


static func _number(value: Variant, minimum: float, maximum: float = float(MAX_COUNT)) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum


static func _integer(value: Variant, minimum: int, maximum: int = MAX_COUNT) -> bool:
	return _number(value, float(minimum), float(maximum)) and float(value) == floorf(float(value))


static func _valid_cell(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0], 0) and _integer(value[1], 0)


static func _cell(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


static func _normalized(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true, true))


static func _json_keys(value: Variant) -> Variant:
	if value is StringName:
		return String(value)
	if value is Array:
		var array: Array = []
		for child: Variant in value:
			array.append(_json_keys(child))
		return array
	if value is Dictionary:
		var record: Dictionary = {}
		for key: Variant in value:
			record[String(key) if key is StringName else key] = _json_keys(value[key])
		return record
	return value


class EnvironmentEventContext:
	extends RefCounted
	var owner: WeakRef
	var guard: WeakRef
	var at_ms: int
	var event: bool

	func _init(bound_owner: RefCounted, bound_guard: RefCounted, time_ms: int, is_event: bool) -> void:
		owner = weakref(bound_owner)
		guard = weakref(bound_guard)
		at_ms = time_ms
		event = is_event
