class_name VillageSimulation
extends RefCounted
## Shared-millisecond world state; minute social timestamps are projections. Scene adapters provide navigation and presentation.

signal changed
signal body_space_changed(id: String)
signal body_cell_crossed(id: String, cell: Vector2i, at_ms: int)
signal space_reset

const SCHEMA_VERSION: int = 7
const MINUTE_MS: int = 60000
const NEED_SCALE: int = 1000000
const SnapshotSchema = preload("res://scripts/sim/snapshot_schema.gd")
const Workplaces = preload("res://scripts/sim/workplaces.gd")

enum NativePhase { START, INTEGRATE, PROJECT, SETTLE, CHOOSE, OBSERVE }

class NativeAdvance extends RefCounted:
	var target_ms: int
	var initial_minute: int
	var events_left: int
	var phase: int = NativePhase.START
	var sparse: bool
	var at_boundary: bool
	var projecting: Array = []
	var due: Array = []
	var observing: Array = []
	var cursor: int = 0
	var batch: SimActorAdvance
	var work_started: bool = false
	var candidates: Array = []
	var included: Dictionary = {}
	var work_cursor: int = 0

var _native_advance: NativeAdvance
var _actors: Dictionary = {}
var actors: Dictionary:
	get:
		# Identity/state lookup is pure. Execution and capture use explicit barriers.
		return _actors
	set(value):
		synchronize_actors()
		_actors = value
		_reset_actor_projections()
var _actor_projection_ms: Dictionary[String, int] = {}
var _projecting_actors: Dictionary[String, bool] = {}
var _materializing_actors: bool = false
var _all_projected_ms: int = -1
var _sparse_actor_projection: bool = false
var actor_execution_enabled: bool = false
var actor_execution_workers: int = 4
var actor_execution_minimum: int = SimActorAdvance.PARALLEL_MINIMUM
## Unsaved measurements; preparation/publication remain on the owner thread.
var actor_execution_work: Dictionary = {"batches": 0, "parallel_batches": 0, "rows": 0, "adopted": 0, "motion_adopted": 0, "discarded": 0, "prepare_usec": 0, "dispatch_usec": 0, "worker_usec": 0, "worker_wall_usec": 0, "queue_usec": 0, "collection_delay_usec": 0, "publish_usec": 0, "pending_returns": 0, "threads": {}}
var _prepared_actor_advance: SimActorAdvance
var _retired_actor_advances: Array[SimActorAdvance] = []
var _preparing_actor_advance: bool = false
var _actor_advance_generation: int = 0
var _workplace_blocks: Dictionary[Vector2i, bool] = {}
var _stock_places_at_cell: Dictionary = {}
var _stock_contents: Dictionary = {}
var _stock_observations: Dictionary = {}
var _stock_epoch: int = 0
var _stock_observed_epoch: int = -1
var _stock_observed_minute: int = -1
var _stock_dirty_actors: Dictionary[String, bool] = {}
var places: Dictionary = {}:
	set(value):
		places = value
		# The accepted workplace layout is replaced on opening/restore. Runtime
		# edits belong to SimConstruction, with its own original spatial index.
		rebuild_workplace_geometry()
var config: Dictionary = {}
var situations: Dictionary = {}
var authorizations: Dictionary = {}
var interaction_results: Dictionary = {}
var inventory: SimInventory = SimInventory.new()
var land_resources: SimLandResources
var social: SimSocialMemory = SimSocialMemory.new()
var institutions: SimInstitutionBook = SimInstitutionBook.new()
var elapsed_ms: int = 0
var tick_index: int:
	get:
		@warning_ignore("integer_division")
		var minute: int = elapsed_ms / MINUTE_MS
		return minute
	set(value):
		elapsed_ms = value * MINUTE_MS
var motion_rules: Dictionary = {}
var controlled_actor: String = "player"
var errors: Array[String] = []
## Diagnostics only. These counters do not affect decisions or persisted state.
var simulation_work: Dictionary = {"step_count": 0, "boundary_count": 0, "batched_minutes": 0, "quiet_batch_calls": 0, "actor_settle_checks": 0, "actor_decision_checks": 0, "actor_merge_checks": 0}

var _content: ReolContentDB
var _boundary_revision_provider: Callable
var _boundary_revision: int = -1
var _actor_boundaries: Dictionary[String, int] = {}
var _route_continuations: Dictionary[String, bool] = {}
var native_route_events_enabled: bool = false
var _route_completions: Dictionary[String, Dictionary] = {}
var _route_geometry_revision_provider: Callable
var _native_crossing_interest: Callable
var _boundary_index := SimParticipationIndex.new()
var _boundary_index_ready: bool = false
var _dirty_actor_boundaries: Dictionary[String, bool] = {}
# Only changes produced during one ordered pass. The deadline dirty set must
# remain intact until its next query; it is not an incremental execution queue.
var _actor_work_changes: Array[String] = []
var _collect_actor_work_changes: bool = false
const NATIVE_BOUNDARY: StringName = &"native_action"
const NATIVE_EFFECT: StringName = &"native_effect"
var _next_actor_boundary: int = -1
var _navigation: Callable
var _step_validator: Callable
var _executor: SimActionExecutor
var _rng := RandomNumberGenerator.new()
var _next_id: int = 1
var _last_request: int = -1000000
var _action_guard: Callable
var _control_guard: Callable
var _rest_recovery: Callable
var _external_labor: Callable
var _duty_provider: Callable
var _labor_observer: Callable
var _initiative_provider: Callable
var _exposure_rate: Callable


static func from_snapshot(
	content: ReolContentDB,
	saved: Dictionary,
	allowed_subjects: Dictionary = {},
	external_inventory: Dictionary = {}
) -> VillageSimulation:
	# Build an independent candidate without creating opening stock, memories or
	# institutional entries. Region/terrain and cross-domain validation remain
	# the caller's responsibility before this candidate can become authoritative.
	if content == null or not _valid_config(saved.get("config")):
		return null
	if not SimStockInformation.valid_policy(content.stock_information_policy) or not SimPersonalForaging.valid_definitions(content.personal_foraging):
		return null
	if not SimPersonalForaging.matches(saved.config, content.personal_foraging) or not SimLandResources.valid_definitions(content.land_resources):
		return null
	if not SimCapabilityConversation.valid_definitions(content.capability_conversation):
		return null
	var candidate := VillageSimulation.new()
	candidate.motion_rules = content.local_actions
	if not _valid_restore_motion_rules(candidate.motion_rules):
		return null
	candidate._content = content
	if not candidate.restore(saved, allowed_subjects, external_inventory):
		return null
	return candidate


static func _valid_restore_motion_rules(value: Dictionary) -> bool:
	return SimLocalMotion.valid_rules(value)


func initialize(content: ReolContentDB, settings: Dictionary, cells: Dictionary, locations: Dictionary, opening_ms: int = 0) -> bool:
	errors.clear()
	if not _valid_config(settings) or content == null or not SimInventory._valid_count(opening_ms) or not SimStockInformation.valid_policy(content.stock_information_policy) or not SimPersonalForaging.matches(settings, content.personal_foraging):
		errors.append("Invalid simulation definition")
		return false
	if not SimLocalMotion.valid_rules(content.local_actions) or not Workplaces.valid_places(locations, settings, null, content.workplaces) or not Workplaces.actors_clear(locations, cells):
		errors.append("Invalid workplace layout or occupied opening structure")
		return false
	_content = content
	_native_advance = null
	_route_completions.clear()
	_collect_actor_work_changes = false
	_actor_work_changes.clear()
	invalidate_boundary_cache()
	motion_rules = content.local_actions
	config = settings.duplicate(true)
	controlled_actor = str(config.get("controlled_actor", "player"))
	places = locations.duplicate(true)
	_actors = {}
	_actor_projection_ms.clear()
	inventory = SimInventory.new()
	social = SimSocialMemory.new()
	social.configure(config.social_policy)
	institutions = SimInstitutionBook.new()
	_rng.seed = int(config.seed)
	elapsed_ms = opening_ms
	simulation_work = {"step_count": 0, "boundary_count": 0, "batched_minutes": 0, "quiet_batch_calls": 0, "actor_settle_checks": 0, "actor_decision_checks": 0, "actor_merge_checks": 0}
	_next_id = 1
	_last_request = -int(config.request_interval)
	situations = {}
	authorizations = {}
	interaction_results = {}
	if cells.size() != config.actor_profiles.size():
		errors.append("Actor definitions and instance cells disagree")
		return false
	for id: String in cells:
		if not config.actor_profiles.has(id):
			return false
		var profile: Dictionary = config.actor_profiles.get(id, {})
		var definition_id: String = str(profile.get("definition_id", id))
		if content.get_pawn(StringName(definition_id)) == null or not _valid_cell(cells[id]):
			errors.append("Unknown actor or invalid position: " + id)
			return false
		var definition: PawnDef = content.get_pawn(StringName(definition_id))
		_actors[id] = {
			"definition_id": definition_id, "cell": cells[id].duplicate(), "hunger": float(profile.get("hunger", 100.0)),
			"energy": float(profile.get("energy", 100.0)), "active": {}, "goal": "安顿日常",
			"autonomous": bool(profile.get("autonomous", id != controlled_actor)),
			"alive": true, "retry_ms": mini(SimInventory.MAX_COUNT, opening_ms + int(motion_rules.clock.fixed_step_ms)), "receipts": [],
			"position": [TileGrid.cell_to_world(_decode(cells[id])).x, TileGrid.cell_to_world(_decode(cells[id])).y],
			"facing": [0.0, 1.0],
			"need_carry": {"hunger": 0, "energy": 0},
			"exertion_until_ms": 0, "stamina_carry": 0,
			"stock_memory": {}, "rank_id": String(definition.rank_id),
			"qi": definition.max_qi, "stamina": definition.max_stamina, "mood": 60.0,
		}
		_actor_projection_ms[id] = opening_ms
		social.register_actor(id)
		inventory.create_container("actor:" + id, {})
	if not _actors.has(controlled_actor):
		errors.append("Missing controlled actor")
		return false
	for id: String in config.initial_stock:
		if not places.has(id) or not _valid_cell(places[id].get("cell")):
			errors.append("Missing place: " + id)
			return false
		if not inventory.create_container(id, config.initial_stock[id]):
			return false
	for id: String in places:
		if not inventory.containers.has(id):
			inventory.create_container(id, {})
	land_resources = SimLandResources.new()
	if not land_resources.initialize(self, content.land_resources):
		errors.append("Invalid natural resource sources")
		return false
	var institution: Dictionary = config.institution
	for office: Dictionary in institution.offices.values():
		if not str(office.holder).is_empty() and not _actors.has(office.holder):
			errors.append("Unknown office holder")
			return false
	if not institutions.add_institution(institution.id, institution.offices):
		return false
	# Origin entitlements are institutional opening entries, never body attributes.
	var registrar: String = _registrar()
	for id: String in _actors:
		var definition: PawnDef = content.get_pawn(StringName(_actors[id].definition_id))
		var origin: OriginDef = content.get_origin(definition.origin_id)
		if origin != null and origin.starting_contribution > 0:
			institutions.issue("opening:" + id, institution.id, registrar, id, origin.starting_contribution, "origin:" + String(origin.id))
		_observe_stock(id)
	_executor = SimActionExecutor.new(self)
	space_reset.emit()
	return true


func set_navigation(provider: Callable, step_validator: Callable = Callable()) -> void:
	synchronize_actors()
	_route_completions.clear()
	rebuild_workplace_geometry()
	invalidate_boundary_cache()
	_navigation = provider
	_step_validator = step_validator


func set_action_guard(provider: Callable) -> void:
	_action_guard = provider


func set_control_guard(provider: Callable) -> void:
	synchronize_actors()
	invalidate_boundary_cache()
	_control_guard = provider


func set_rest_recovery(provider: Callable) -> void:
	synchronize_actors()
	_rest_recovery = provider


func set_exposure_rate(provider: Callable) -> void:
	synchronize_actors()
	_exposure_rate = provider


func set_external_labor(provider: Callable) -> void:
	synchronize_actors()
	_external_labor = provider


func set_duty_provider(provider: Callable) -> void:
	_duty_provider = provider


func set_labor_observer(provider: Callable) -> void:
	_labor_observer = provider


func set_initiative_provider(provider: Callable) -> void:
	_initiative_provider = provider


func notify_labor(stage: String, actor_id: String, action: Dictionary, event: String = "") -> String:
	return str(_labor_observer.call(stage, actor_id, action, event)) if _labor_observer.is_valid() else ""


func actor_controls(actor_id: String, channel: String) -> bool:
	return _actors.has(actor_id) and bool(_actors[actor_id].alive) and (not _control_guard.is_valid() or bool(_control_guard.call(actor_id, channel)))


func workspace_action_available(actor_id: String) -> bool:
	return actor_controls(actor_id, "communication") and actor_controls(actor_id, "action") and actor_controls(actor_id, "motion") and _actors[actor_id].active.is_empty() and (not _action_guard.is_valid() or bool(_action_guard.call(actor_id)))


func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if from_cell == to_cell:
		return result
	if not _navigation.is_valid():
		return result
	var raw: Array = _navigation.call(from_cell, to_cell)
	for value: Variant in raw:
		if value is Vector2i:
			result.append(value)
	return result


func rebuild_workplace_geometry() -> void:
	_workplace_blocks.clear()
	_stock_places_at_cell.clear()
	_stock_contents.clear()
	_stock_observations.clear()
	_stock_epoch = 0
	var layout: Dictionary = places.get("records", {}).get("workspace", {})
	for raw: Array in layout.get("walls", []):
		_workplace_blocks[SimRouteTravel.cell(raw)] = true
	for id: String in ["desk", "archive"]:
		if layout.get("fixtures", {}).get(id) is Dictionary:
			_workplace_blocks[SimRouteTravel.cell(layout.fixtures[id].cell)] = true


func workplace_blocked(cell: Vector2i) -> bool:
	# enable_opening commits a new accepted layout into the existing places
	# dictionary. This one-way activation also works without replacing places.
	if _workplace_blocks.is_empty() and config.has("workplaces_version"):
		rebuild_workplace_geometry()
	return _workplace_blocks.has(cell)


func step() -> void:
	simulation_work.step_count = int(simulation_work.step_count) + 1
	advance_to_ms((tick_index + 1) * MINUTE_MS)


func next_boundary_ms(effects_only: bool = false) -> int:
	var boundary: int = land_resources.next_boundary_ms()
	var cached: bool = _boundary_revision_provider.is_valid()
	if cached:
		var revision: int = int(_boundary_revision_provider.call())
		if revision != _boundary_revision:
			synchronize_actors()
			invalidate_boundary_cache()
			_boundary_revision = revision
	if not cached or _next_actor_boundary <= elapsed_ms:
		_next_actor_boundary = _query_actor_boundary(cached)
	boundary = mini(boundary, _boundary_index.next_due_ms(NATIVE_EFFECT, SimInventory.MAX_COUNT) if cached and effects_only and native_route_events_enabled else _next_actor_boundary)
	var scenario: Dictionary = config.scenario
	var definition: Dictionary = config.actions[scenario.task]
	var shortage: bool = inventory.quantity(definition.target, definition.item) == 0
	var open: bool = situations.has("kitchen_shortage") and situations.kitchen_shortage.status == "open"
	if shortage:
		if not open:
			boundary = mini(boundary, elapsed_ms + 1)
		boundary = mini(boundary, maxi(elapsed_ms + 1, (_last_request + int(config.request_interval)) * MINUTE_MS))
	elif open:
		boundary = mini(boundary, elapsed_ms + 1)
	return maxi(elapsed_ms + 1, boundary)


func next_world_boundary_ms() -> int:
	return next_boundary_ms(true)


func accept_native_route(id: String, route: Dictionary) -> void:
	if not native_route_events_enabled or not _boundary_revision_provider.is_valid():
		return
	# Only a freshly found/repaired route has a proof for ALL remaining legs.
	# After an intersecting topology revision an old path keeps local boundaries
	# until it is repaired or replaced, even if its first leg is still open.
	var result: int = int(route.due_ms)
	var speed: float = float(motion_rules.motion.speed)
	var cells: Dictionary[Vector2i, bool] = {}
	var previous: Vector2i = TileGrid.world_to_cell(Vector2(float(route.segment_from[0]), float(route.segment_from[1])))
	cells[previous] = true
	for raw: Array in route.path:
		var at: Vector2i = SimRouteTravel.cell(raw)
		cells[at] = true
		if previous.x != at.x and previous.y != at.y:
			cells[Vector2i(previous.x, at.y)] = true
			cells[Vector2i(at.x, previous.y)] = true
		previous = at
	for index: int in range(1, route.path.size()):
		var from: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(route.path[index - 1]))
		var to: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(route.path[index]))
		result += maxi(1, ceili(from.distance_to(to) / speed * 1000.0))
	_route_completions[id] = {"route": route, "at_ms": result, "cells": cells, "revision": _route_geometry_revision()}


func set_route_geometry_revision_provider(provider: Callable) -> void:
	_route_completions.clear()
	_route_geometry_revision_provider = provider


func _route_geometry_revision() -> int:
	return int(_route_geometry_revision_provider.call()) if _route_geometry_revision_provider.is_valid() else int(_boundary_revision_provider.call())


func update_native_route_geometry(cells: Array[Vector2i], previous_revision: int, next_revision: int) -> void:
	if cells.is_empty():
		return # Unknown coverage keeps every previous proof stale.
	for completion: Dictionary in _route_completions.values():
		if int(completion.revision) != previous_revision:
			continue
		var intersects: bool = false
		for cell: Vector2i in cells:
			if completion.cells.has(cell):
				intersects = true
				break
		if not intersects:
			completion.revision = next_revision


func invalidate_native_route_completion(id: String) -> void:
	_route_completions.erase(id)


func _query_actor_boundary(cached: bool) -> int:
	var boundary: int = SimInventory.MAX_COUNT
	var geometry_revision: int = _route_geometry_revision() if cached and native_route_events_enabled else -1
	var ids: Array = []
	if cached and _boundary_index_ready:
		var pending: Dictionary = _dirty_actor_boundaries.duplicate()
		for id: String in _boundary_index.due_ids(NATIVE_BOUNDARY, elapsed_ms):
			pending[id] = true
		ids = pending.keys()
		ids.sort()
	else:
		ids = _actor_ids()
	for id: String in ids:
		var actor: Dictionary = _actors[id]
		var actor_boundary: int = SimInventory.MAX_COUNT
		var effect_boundary: int = SimInventory.MAX_COUNT
		if not bool(actor.alive):
			if cached:
				_boundary_index.cancel_due(NATIVE_BOUNDARY, id)
				_boundary_index.cancel_due(NATIVE_EFFECT, id)
				_dirty_actor_boundaries.erase(id)
			continue
		if not actor.active.is_empty():
			var allowed: bool = actor_controls(id, "action") and actor_controls(id, "motion")
			var completion: Dictionary = _route_completions.get(id, {})
			var accepted: bool = allowed and native_route_events_enabled and actor.active.get("phase") == "travel" and not completion.is_empty() and is_same(completion.route, actor.active) and int(completion.revision) == geometry_revision
			if cached:
				_route_continuations[id] = allowed and actor.active.get("phase") == "travel"
			if not allowed:
				actor_boundary = elapsed_ms + 1
			elif accepted and _native_crossing_interest.is_valid() and not bool(_native_crossing_interest.call(id)) and not _stock_crossing_required(actor):
				# No domain consumes this body's cell edge. Keep the accepted segment
				# continuous until its end; authority queries still project on demand.
				actor_boundary = maxi(elapsed_ms + 1, mini(int(actor.active.due_ms), int(actor.active.started_ms) + int(config.action_timeout) * MINUTE_MS + 1))
			else:
				actor_boundary = _executor.next_boundary_ms(actor)
			if accepted:
				effect_boundary = mini(int(completion.at_ms), int(actor.active.started_ms) + int(config.action_timeout) * MINUTE_MS + 1)
			else:
				effect_boundary = actor_boundary
				if actor.active.get("phase") != "travel":
					_route_completions.erase(id)
		elif bool(actor.autonomous):
			actor_boundary = maxi(elapsed_ms + 1, int(actor.retry_ms))
			effect_boundary = actor_boundary
			_route_completions.erase(id)
		if cached:
			_actor_boundaries[id] = actor_boundary
			_boundary_index.set_member(NATIVE_BOUNDARY, id)
			_boundary_index.set_due(NATIVE_BOUNDARY, id, actor_boundary)
			_boundary_index.set_member(NATIVE_EFFECT, id)
			_boundary_index.set_due(NATIVE_EFFECT, id, effect_boundary)
			_dirty_actor_boundaries.erase(id)
		boundary = mini(boundary, actor_boundary)
	if cached:
		_boundary_index_ready = true
		return _boundary_index.next_due_ms(NATIVE_BOUNDARY, SimInventory.MAX_COUNT)
	return boundary


func set_boundary_revision_provider(provider: Callable) -> void:
	# Opt in only with observable navigation/control dependencies. Arbitrary
	# standalone Callables keep the conservative path. Absolute deadlines are
	# reused until due; this is not a second action state or saved schedule.
	synchronize_actors()
	_boundary_revision_provider = provider
	_route_completions.clear()
	_boundary_revision = -1
	invalidate_boundary_cache()


func set_native_crossing_interest(provider: Callable) -> void:
	_native_crossing_interest = provider
	invalidate_boundary_cache()


func invalidate_boundary_cache() -> void:
	_cancel_actor_advance()
	if _collect_actor_work_changes:
		_actor_work_changes.append("") # Whole-region dependency invalidation.
	_actor_boundaries.clear()
	_route_continuations.clear()
	_boundary_index.clear()
	_boundary_index_ready = false
	_dirty_actor_boundaries.clear()
	_next_actor_boundary = -1


func invalidate_actor_boundary(id: String) -> void:
	_cancel_actor_advance()
	if _collect_actor_work_changes:
		_actor_work_changes.append(id)
	_actor_boundaries.erase(id)
	_route_continuations.erase(id)
	_dirty_actor_boundaries[id] = true
	_next_actor_boundary = -1
	if _route_completions.has(id) and not is_same(_route_completions[id].route, _actors.get(id, {}).get("active", {})):
		_route_completions.erase(id)


func has_cached_boundary_ahead(id: String) -> bool:
	return _boundary_revision_provider.is_valid() and int(_actor_boundaries.get(id, 0)) > elapsed_ms


func continue_native_route(id: String, route: Dictionary, at_ms: int) -> void:
	# A canonical cell crossing is already projected. With the same accepted
	# control/geometry inputs there is no native work/decision effect before
	# this segment ends. Keep its deadline without querying/settling it again.
	if not bool(_route_continuations.get(id, false)) or not _boundary_revision_provider.is_valid() or boundary_dependencies_changed():
		return
	if int(_actor_boundaries.get(id, -1)) != at_ms or int(route.due_ms) <= at_ms or route.path.is_empty():
		return
	if SimRouteTravel.cell(_actors[id].cell) != SimRouteTravel.cell(route.path[0]):
		return # An off-centre diagonal may still cross its other axis first.
	var next: int = mini(int(route.due_ms), int(route.started_ms) + int(config.action_timeout) * MINUTE_MS + 1)
	if next <= at_ms:
		return
	_actor_boundaries[id] = next
	_boundary_index.set_due(NATIVE_BOUNDARY, id, next)
	_next_actor_boundary = -1


func boundary_dependencies_changed() -> bool:
	return _boundary_revision_provider.is_valid() and int(_boundary_revision_provider.call()) != _boundary_revision


func next_boundary_tick() -> int:
	return maxi(tick_index + 1, ceili(float(next_boundary_ms()) / MINUTE_MS))


func advance_to(target_tick: int, max_events: int = 4096) -> bool:
	@warning_ignore("integer_division")
	var maximum_minute: int = SimInventory.MAX_COUNT / MINUTE_MS
	if target_tick < 0 or target_tick > maximum_minute:
		return false
	return advance_to_ms(target_tick * MINUTE_MS, max_events)


func has_pending_actor_interval() -> bool:
	return _native_advance != null


func advance_to_ms(target_ms: int, max_events: int = 4096, should_yield: Callable = Callable()) -> bool:
	if target_ms < elapsed_ms or target_ms > SimInventory.MAX_COUNT or _executor == null:
		return false
	if _native_advance != null and _native_advance.target_ms != target_ms:
		return false
	if _native_advance == null:
		_native_advance = NativeAdvance.new()
		_native_advance.target_ms = target_ms
		_native_advance.initial_minute = tick_index
		_native_advance.events_left = max_events
	var work: NativeAdvance = _native_advance
	while elapsed_ms < target_ms or work.phase != NativePhase.START:
		if should_yield.is_valid() and bool(should_yield.call()):
			return false
		match work.phase:
			NativePhase.START:
				var boundary: int = next_boundary_ms()
				var next: int = mini(target_ms, boundary)
				if next == boundary and work.events_left < 1:
					_native_advance = null
					return false
				work.at_boundary = next == boundary
				work.sparse = _sparse_actor_projection and _boundary_revision_provider.is_valid()
				work.batch = _take_actor_advance(next)
				if not work.sparse:
					# Opaque standalone callbacks retain their pre-advance input order.
					for id: String in _actors:
						_decay_actor(id, elapsed_ms, next - elapsed_ms)
				land_resources.advance_to_ms(next)
				elapsed_ms = next
				if not work.sparse:
					for id: String in _actors:
						_actor_projection_ms[id] = elapsed_ms
					_all_projected_ms = elapsed_ms
				work.projecting = _boundary_index.due_ids(NATIVE_BOUNDARY, elapsed_ms) if work.sparse else _actor_ids()
				work.projecting.sort()
				work.cursor = 0
				work.phase = NativePhase.INTEGRATE
			NativePhase.INTEGRATE:
				# Finish every old-input need before any geometry observer can see
				# peers. A suspended interval remains unpublished during this pass.
				var started: int = Time.get_ticks_usec() if work.batch != null else 0
				if work.sparse:
					while work.cursor < work.projecting.size():
						if work.cursor % 8 == 0 and should_yield.is_valid() and bool(should_yield.call()):
							if work.batch != null:
								actor_execution_work.publish_usec = int(actor_execution_work.publish_usec) + Time.get_ticks_usec() - started
							return false
						var id: String = work.projecting[work.cursor]
						if work.batch != null and work.batch.row_for(id).x >= 0:
							_apply_actor_advance(id, work.batch)
						else:
							_integrate_actor(id)
						work.cursor += 1
				if work.batch != null:
					actor_execution_work.publish_usec = int(actor_execution_work.publish_usec) + Time.get_ticks_usec() - started
				work.cursor = 0
				work.phase = NativePhase.PROJECT
			NativePhase.PROJECT:
				var started: int = Time.get_ticks_usec() if work.batch != null else 0
				while work.cursor < work.projecting.size():
					if work.cursor % 8 == 0 and should_yield.is_valid() and bool(should_yield.call()):
						if work.batch != null:
							actor_execution_work.publish_usec = int(actor_execution_work.publish_usec) + Time.get_ticks_usec() - started
						return false
					_executor.project(work.projecting[work.cursor], elapsed_ms, work.batch)
					work.cursor += 1
				if work.batch != null:
					actor_execution_work.publish_usec = int(actor_execution_work.publish_usec) + Time.get_ticks_usec() - started
				work.due = _boundary_index.due_ids(NATIVE_BOUNDARY, elapsed_ms) if _boundary_revision_provider.is_valid() else _actor_ids()
				work.phase = NativePhase.SETTLE
			NativePhase.SETTLE:
				if work.at_boundary and not _settle_actor_work(work, false, should_yield):
					return false
				work.phase = NativePhase.CHOOSE
			NativePhase.CHOOSE:
				if work.at_boundary:
					if not _settle_actor_work(work, true, should_yield):
						return false
					_update_situations()
					work.events_left -= 1
					simulation_work.boundary_count = int(simulation_work.boundary_count) + 1
				_refresh_stock_epoch()
				if work.sparse and (_stock_observed_epoch != _stock_epoch or _stock_observed_minute != tick_index):
					synchronize_actors()
				work.observing = _actor_ids() if not work.sparse or _stock_observed_epoch != _stock_epoch or _stock_observed_minute != tick_index else _stock_dirty_actors.keys()
				work.observing.sort()
				work.cursor = 0
				work.phase = NativePhase.OBSERVE
			NativePhase.OBSERVE:
				while work.cursor < work.observing.size():
					if work.cursor % 8 == 0 and should_yield.is_valid() and bool(should_yield.call()):
						return false
					var id: String = work.observing[work.cursor]
					work.cursor += 1
					if bool(_actors[id].alive):
						_observe_stock(id)
				_stock_dirty_actors.clear()
				_stock_observed_epoch = _stock_epoch
				_stock_observed_minute = tick_index
				work.phase = NativePhase.START
	simulation_work.batched_minutes = int(simulation_work.batched_minutes) + tick_index - work.initial_minute
	simulation_work.quiet_batch_calls = int(simulation_work.quiet_batch_calls) + 1
	_native_advance = null
	changed.emit()
	return true


func _settle_actor_work(work: NativeAdvance, choosing: bool, should_yield: Callable) -> bool:
	# A pass keeps the original ID order. A synchronous observer can invalidate
	# a later body during this pass; merge that suffix without rescanning N peers.
	# Earlier IDs wait for the next boundary, as in the original ordered loop.
	if not work.work_started:
		work.candidates = work.due.duplicate()
		work.included = {}
		for id: String in work.candidates:
			work.included[id] = true
		_merge_actor_work(work.candidates, work.included, "", _dirty_actor_boundaries.keys() if _boundary_index_ready else _actor_ids())
		_collect_actor_work_changes = true
		work.work_cursor = 0
		work.work_started = true
	while work.work_cursor < work.candidates.size():
		if work.work_cursor % 8 == 0 and should_yield.is_valid() and bool(should_yield.call()):
			return false
		var id: String = work.candidates[work.work_cursor]
		work.work_cursor += 1
		var actor: Dictionary = _actors[id]
		if choosing:
			simulation_work.actor_decision_checks = int(simulation_work.actor_decision_checks) + 1
			if bool(actor.alive) and bool(actor.autonomous) and actor.active.is_empty() and elapsed_ms >= int(actor.retry_ms):
				_choose_routine(id)
		elif not _boundary_revision_provider.is_valid() or int(_actor_boundaries.get(id, 0)) <= elapsed_ms:
			simulation_work.actor_settle_checks = int(simulation_work.actor_settle_checks) + 1
			_executor.settle(id)
		if not _actor_work_changes.is_empty():
			_merge_actor_work(work.candidates, work.included, id, _actor_ids() if _actor_work_changes.has("") else _actor_work_changes)
			_actor_work_changes.clear()
	_collect_actor_work_changes = false
	work.work_started = false
	return true


func _merge_actor_work(candidates: Array, included: Dictionary, after: String, invalidated: Array) -> void:
	var changed: bool = false
	for id: String in invalidated:
		simulation_work.actor_merge_checks = int(simulation_work.actor_merge_checks) + 1
		if id > after and not included.has(id):
			candidates.append(id)
			included[id] = true
			changed = true
	if changed or after.is_empty():
		candidates.sort()


func has_actor(id: Variant) -> bool:
	return _actors.has(id)


func actor_is_alive(id: String) -> bool:
	return _actors.has(id) and bool(_actors[id].alive)


func actor_is_autonomous(id: String) -> bool:
	return _actors.has(id) and bool(_actors[id].autonomous)


func actor_has_action(id: String) -> bool:
	return _actors.has(id) and not _actors[id].active.is_empty()


func set_sparse_actor_projection(enabled: bool) -> void:
	# World adapters opt in only after their continuous-input mutation barriers
	# and navigation/control notifications are bound. Standalone Callables keep
	# eager projection because their captured inputs may change invisibly.
	synchronize_actors()
	_sparse_actor_projection = enabled


func actor_ids() -> Array:
	return _actor_ids()


func actor_state(id: String) -> Dictionary:
	# Original state at its last owner integration. This query emits no signals.
	return _actors.get(id, {})


func synchronize_actor(id: String) -> Dictionary:
	if not _actors.has(id):
		return {}
	var actor: Dictionary = _actors[id]
	if _executor == null or _projecting_actors.has(id):
		return actor
	var previous: int = int(_actor_projection_ms.get(id, elapsed_ms))
	if previous == elapsed_ms:
		return actor
	if not _preparing_actor_advance:
		_cancel_actor_advance()
	_projecting_actors[id] = true
	_integrate_actor(id)
	_executor.project(id, elapsed_ms)
	_projecting_actors.erase(id)
	return actor


func _integrate_actor(id: String) -> void:
	var previous: int = int(_actor_projection_ms.get(id, elapsed_ms))
	if previous != elapsed_ms:
		_actor_projection_ms[id] = elapsed_ms
		_decay_actor(id, previous, elapsed_ms - previous)


func synchronize_actors() -> Dictionary:
	if not _preparing_actor_advance:
		_cancel_actor_advance()
	if _materializing_actors or _all_projected_ms == elapsed_ms:
		return _actors
	_materializing_actors = true
	for id: String in _actor_ids():
		synchronize_actor(id)
	_materializing_actors = false
	_all_projected_ms = elapsed_ms
	return _actors


func _reset_actor_projections() -> void:
	_cancel_actor_advance()
	_route_completions.clear()
	_actor_projection_ms.clear()
	_projecting_actors.clear()
	for id: String in _actors:
		_actor_projection_ms[id] = elapsed_ms
	_all_projected_ms = elapsed_ms


func configure_actor_execution(workers: int = 4, minimum: int = SimActorAdvance.PARALLEL_MINIMUM) -> void:
	_cancel_actor_advance()
	actor_execution_enabled = true
	actor_execution_workers = clampi(workers, 0, 8)
	actor_execution_minimum = maxi(1, minimum)


func prepare_actor_advance(to_ms: int) -> bool:
	_collect_actor_batches()
	if not actor_execution_enabled or not _sparse_actor_projection or not _boundary_revision_provider.is_valid() or to_ms <= elapsed_ms:
		return true
	var revision: int = int(_boundary_revision_provider.call())
	if _prepared_actor_advance != null:
		if _prepared_actor_advance.at_ms == to_ms and _prepared_actor_advance.generation == _actor_advance_generation and _prepared_actor_advance.dependency_revision == revision:
			return _prepared_actor_advance.execution.finish()
		_cancel_actor_advance()
	var ids: Array[String] = _boundary_index.due_ids(NATIVE_BOUNDARY, to_ms)
	if ids.size() < actor_execution_minimum:
		return true
	ids.sort()
	var started: int = Time.get_ticks_usec()
	var batch := SimActorAdvance.new()
	batch.at_ms = to_ms
	var hunger_rate: int = roundi(float(config.needs.hunger_per_minute) * NEED_SCALE)
	var base_rate: int = roundi(float(config.needs.energy_per_minute) * NEED_SCALE)
	var work_rate: int = roundi(float(config.needs.work_energy_per_minute) * NEED_SCALE)
	_preparing_actor_advance = true
	for id: String in ids:
		var body: Dictionary = _actors[id]
		if not bool(body.alive):
			continue
		# Callbacks are evaluated by the authority, before workers start. Only
		# the resulting numbers and an accepted route segment cross the seam.
		var energy_rate: int = base_rate + (int(_exposure_rate.call(id)) if _exposure_rate.is_valid() else 0)
		var laboring: bool = not body.active.is_empty() or (_external_labor.is_valid() and bool(_external_labor.call(id)))
		if laboring:
			energy_rate += work_rate
		if _rest_recovery.is_valid():
			energy_rate -= int(_rest_recovery.call(id)) * NEED_SCALE
		var definition: PawnDef = _content.get_pawn(StringName(body.definition_id))
		batch.append(id, body, int(_actor_projection_ms.get(id, elapsed_ms)), hunger_rate, energy_rate,
			not laboring or str(body.active.get("action", "")) == "rest", definition.max_stamina, int(motion_rules.recovery.stamina_per_second))
	_preparing_actor_advance = false
	batch.generation = _actor_advance_generation
	batch.dependency_revision = revision
	_prepared_actor_advance = batch
	actor_execution_work.prepare_usec = int(actor_execution_work.prepare_usec) + Time.get_ticks_usec() - started
	batch.start(actor_execution_workers)
	actor_execution_work.prepare_usec = int(actor_execution_work.prepare_usec) + batch.preparation_usec
	actor_execution_work.dispatch_usec = int(actor_execution_work.dispatch_usec) + batch.execution.dispatch_usec
	actor_execution_work.batches = int(actor_execution_work.batches) + 1
	actor_execution_work.rows = int(actor_execution_work.rows) + batch.ids.size()
	if batch.execution.parallel:
		actor_execution_work.parallel_batches = int(actor_execution_work.parallel_batches) + 1
	return batch.execution.finish()


func actor_advance_ready() -> bool:
	var ready: bool = _prepared_actor_advance == null or _prepared_actor_advance.execution.finish()
	if not ready:
		actor_execution_work.pending_returns = int(actor_execution_work.pending_returns) + 1
	return ready


func _take_actor_advance(to_ms: int) -> SimActorAdvance:
	var batch: SimActorAdvance = _prepared_actor_advance
	if batch == null:
		return null
	if batch.execution.cancelled or batch.at_ms != to_ms or batch.generation != _actor_advance_generation or not _boundary_revision_provider.is_valid() or batch.dependency_revision != int(_boundary_revision_provider.call()) or not batch.execution.finish():
		_cancel_actor_advance()
		return null
	_prepared_actor_advance = null
	_measure_actor_batch(batch)
	return batch


func _measure_actor_batch(batch: SimActorAdvance) -> void:
	if batch.measured:
		return
	batch.measured = true
	var first: int = 9223372036854775807
	var last: int = 0
	for chunk: SimActorAdvance.Chunk in batch.chunks:
		actor_execution_work.worker_usec = int(actor_execution_work.worker_usec) + chunk.finished_usec - chunk.started_usec
		actor_execution_work.threads[chunk.thread_id] = true
		first = mini(first, chunk.started_usec)
		last = maxi(last, chunk.finished_usec)
	if last > 0:
		actor_execution_work.worker_wall_usec = int(actor_execution_work.worker_wall_usec) + last - first
		actor_execution_work.queue_usec = int(actor_execution_work.queue_usec) + maxi(0, first - batch.execution.submitted_usec)
		actor_execution_work.collection_delay_usec = int(actor_execution_work.collection_delay_usec) + maxi(0, batch.execution.completed_usec - last)


func _apply_actor_advance(id: String, batch: SimActorAdvance) -> void:
	var row: Vector2i = batch.row_for(id)
	var flat: int = row.x * SimActorAdvance.CHUNK_SIZE + row.y
	if int(_actor_projection_ms.get(id, elapsed_ms)) != batch.anchors[flat]:
		actor_execution_work.discarded = int(actor_execution_work.discarded) + 1
		_integrate_actor(id)
		return
	var chunk: SimActorAdvance.Chunk = batch.chunks[row.x]
	var i: int = row.y * SimActorAdvance.InputField.STRIDE
	var o: int = row.y * SimActorAdvance.OutputField.STRIDE
	var body: Dictionary = _actors[id]
	if chunk.input[i + SimActorAdvance.InputField.HUNGER_RATE] != 0:
		SimActorAdvance.write_need(body, "hunger", chunk.output[o + SimActorAdvance.OutputField.HUNGER])
	if chunk.input[i + SimActorAdvance.InputField.ENERGY_RATE] != 0:
		SimActorAdvance.write_need(body, "energy", chunk.output[o + SimActorAdvance.OutputField.ENERGY])
	body.stamina = chunk.output[o + SimActorAdvance.OutputField.STAMINA]
	body.stamina_carry = chunk.output[o + SimActorAdvance.OutputField.STAMINA_CARRY]
	_actor_projection_ms[id] = elapsed_ms
	actor_execution_work.adopted = int(actor_execution_work.adopted) + 1


func _cancel_actor_advance() -> void:
	_actor_advance_generation += 1
	if _prepared_actor_advance == null:
		return
	var batch: SimActorAdvance = _prepared_actor_advance
	_prepared_actor_advance = null
	batch.execution.cancel()
	actor_execution_work.discarded = int(actor_execution_work.discarded) + batch.ids.size()
	if not batch.execution.finish():
		_retired_actor_advances.append(batch)
	else:
		_measure_actor_batch(batch)


func _collect_actor_batches() -> void:
	for index: int in range(_retired_actor_advances.size() - 1, -1, -1):
		if _retired_actor_advances[index].execution.finish():
			_measure_actor_batch(_retired_actor_advances[index])
			_retired_actor_advances.remove_at(index)


func close_actor_execution() -> void:
	_cancel_actor_advance()
	for batch: SimActorAdvance in _retired_actor_advances:
		batch.execution.finish(true)
	_retired_actor_advances.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# RefCounted has already reached zero here; do not call a method on self.
		if _prepared_actor_advance != null:
			_prepared_actor_advance.execution.cancel()
			_prepared_actor_advance.execution.finish(true)
		for batch: SimActorAdvance in _retired_actor_advances:
			batch.execution.finish(true)


func _decay_actor(id: String, from_ms: int, duration_ms: int) -> void:
	_advance_needs(_actors[id], id, from_ms, duration_ms)


func projected_actor_needs(id: String) -> Dictionary:
	# UI evaluates the same accepted input interval without changing the body,
	# its carry, participation deadlines, routes or pending worker candidates.
	var actor: Dictionary = _actors[id]
	var previous: int = int(_actor_projection_ms.get(id, elapsed_ms))
	if previous == elapsed_ms or not bool(actor.alive):
		return actor
	var view: Dictionary = actor.duplicate()
	view.need_carry = actor.need_carry.duplicate()
	_advance_needs(view, id, previous, elapsed_ms - previous)
	return view


func _advance_needs(actor: Dictionary, id: String, from_ms: int, duration_ms: int) -> void:
	var hunger_rate: int = roundi(float(config.needs.hunger_per_minute) * NEED_SCALE)
	var base_energy_rate: int = roundi(float(config.needs.energy_per_minute) * NEED_SCALE)
	var work_rate: int = roundi(float(config.needs.work_energy_per_minute) * NEED_SCALE)
	if not bool(actor.alive):
		return
	var energy_rate: int = base_energy_rate
	if _exposure_rate.is_valid():
		energy_rate += int(_exposure_rate.call(id))
	var laboring: bool = not actor.active.is_empty() or (_external_labor.is_valid() and bool(_external_labor.call(id)))
	if laboring:
		energy_rate += work_rate
	if _rest_recovery.is_valid():
		energy_rate -= int(_rest_recovery.call(id)) * NEED_SCALE
	_decay_need(actor, "hunger", hunger_rate, duration_ms)
	if energy_rate < 0:
		_recover_need(actor, "energy", -energy_rate, duration_ms)
	else:
		_decay_need(actor, "energy", energy_rate, duration_ms)
	if not laboring or str(actor.active.get("action", "")) == "rest":
		var duration: int = maxi(0, from_ms + duration_ms - maxi(from_ms, int(actor.exertion_until_ms)))
		var definition: PawnDef = _content.get_pawn(StringName(actor.definition_id))
		var rate: int = int(motion_rules.recovery.stamina_per_second)
		var gain: int = SimActorAdvance.stamina_gain(int(actor.stamina), definition.max_stamina, int(actor.stamina_carry), rate, duration)
		@warning_ignore("integer_division")
		var units: int = gain / 1000
		actor.stamina = mini(definition.max_stamina, int(actor.stamina) + units)
		actor.stamina_carry = gain % 1000 if int(actor.stamina) < definition.max_stamina else 0


func _recover_need(actor: Dictionary, kind: String, rate: int, duration_ms: int) -> void:
	var available: int = roundi(float(actor[kind]) * NEED_SCALE)
	SimActorAdvance.write_need(actor, kind, SimActorAdvance.need_balance(available, int(actor.need_carry[kind]), -rate, duration_ms))


func _decay_need(actor: Dictionary, kind: String, rate: int, duration_ms: int) -> void:
	if rate == 0:
		return
	var available: int = roundi(float(actor[kind]) * NEED_SCALE)
	SimActorAdvance.write_need(actor, kind, SimActorAdvance.need_balance(available, int(actor.need_carry[kind]), rate, duration_ms))


static func _decode(raw: Array) -> Vector2i:
	return Vector2i(int(raw[0]), int(raw[1]))


func actor_position(actor: Dictionary) -> Vector2:
	return Vector2(float(actor.position[0]), float(actor.position[1]))


func projected_actor_position(id: String) -> Vector2:
	var actor: Dictionary = _actors[id]
	var route: Dictionary = actor.get("active", {})
	if route.get("phase") == "travel":
		return SimRouteTravel.projected_point(route, actor, elapsed_ms)
	return actor_position(actor)


func set_actor_position(id: String, point: Vector2) -> void:
	synchronize_actor(id)
	if SimRouteTravel.point(_actors[id]) != point:
		invalidate_native_route_completion(id)
	invalidate_actor_boundary(id)
	var before: Vector2i = SimRouteTravel.cell(_actors[id].cell)
	SimRouteTravel.put(_actors[id], point)
	if before != SimRouteTravel.cell(_actors[id].cell):
		_stock_dirty_actors[id] = true
		body_space_changed.emit(id)


func project_actor_route(id: String, route: Dictionary, at_ms: int, batch: SimActorAdvance = null) -> void:
	var before: Vector2i = SimRouteTravel.cell(_actors[id].cell)
	if batch != null and batch.at_ms == at_ms and batch.motion_matches(id, _actors[id], route):
		var row: Vector2i = batch.row_for(id)
		var poses: PackedVector2Array = batch.chunks[row.x].poses
		SimRouteTravel.put(_actors[id], poses[row.y * 2])
		var facing: Vector2 = poses[row.y * 2 + 1]
		_actors[id].facing = [facing.x, facing.y]
		actor_execution_work.motion_adopted = int(actor_execution_work.motion_adopted) + 1
	else:
		SimRouteTravel.project(route, _actors[id], at_ms)
	if before != SimRouteTravel.cell(_actors[id].cell):
		_stock_dirty_actors[id] = true
		var crossing: int = SimRouteTravel.crossing_from_cell_ms(route, before, int(route.segment_started_ms))
		body_cell_crossed.emit(id, SimRouteTravel.cell(_actors[id].cell), crossing)
		body_space_changed.emit(id)


func notify_body_space_changed(id: String) -> void:
	# Manual motion writes the same original body, notifying on cell crossings.
	invalidate_native_route_completion(id)
	invalidate_actor_boundary(id)
	_stock_dirty_actors[id] = true
	body_space_changed.emit(id)


func notify_body_cell_crossed(cell: Vector2i, at_ms: int, id: String) -> void:
	# A traversal notice, not a second body or clock. Manual motion already
	# integrates exact integer substeps; consumers settle only at cell crossings.
	body_cell_crossed.emit(id, cell, at_ms)


func set_actor_cell(id: String, grid: Vector2i) -> void:
	set_actor_position(id, TileGrid.cell_to_world(grid))


func submit_action(actor_id: String, action_id: String) -> bool:
	if _executor == null or not actor_controls(actor_id, "action") or not actor_controls(actor_id, "motion"):
		return false
	if _action_guard.is_valid() and not bool(_action_guard.call(actor_id)):
		return false
	return _executor.begin(actor_id, action_id)


func cancel_action(actor_id: String, reason: String = "cancelled") -> void:
	_executor.cancel(actor_id, reason)
	changed.emit()


func remove_actor(actor_id: String) -> void:
	if not _actors.has(actor_id):
		return
	_executor.cancel(actor_id, "actor_unavailable")
	_actors[actor_id].alive = false
	invalidate_actor_boundary(actor_id)
	_actors[actor_id].goal = "已离开，随身物资留在原地"
	# Inventory stays attached to the persistent actor; nothing is duplicated.
	observe("departed", actor_id, "", {})
	changed.emit()


func request_help(requester: String, responder: String, occasion: String = "personal_request") -> Dictionary:
	if not _actors.has(requester) or not _actors.has(responder) or requester == responder:
		return {"status": "refused", "reason": "invalid_actor", "message": "没有可交谈的人。"}
	var source: Dictionary = synchronize_actor(requester)
	var person: Dictionary = synchronize_actor(responder)
	if not bool(source.alive) or not bool(person.alive):
		return {"status": "refused", "reason": "unavailable", "message": "对方已经离开。"}
	if not actor_controls(requester, "communication") or not actor_controls(responder, "communication"):
		return {"status": "refused", "reason": "cannot_communicate", "message": "眼下无法交谈。"}
	if _action_guard.is_valid() and not bool(_action_guard.call(responder)):
		return {"status": "refused", "reason": "existing_commitment", "message": "对方已有正在履行的约定。"}
	var distance: float = _distance(requester, responder)
	if distance > float(config.talk_radius):
		return {"status": "refused", "reason": "out_of_range", "message": "相距太远，需要靠近交谈。"}
	var task: String = config.scenario.task
	var profile: Dictionary = config.actor_profiles.get(responder, {})
	var context: Dictionary = {
		"energy": float(person.energy) / 100.0,
		"busy": 0.0 if person.active.is_empty() else 1.0,
		"distance": distance / float(config.talk_radius),
		"risk": 0.0, "duty": 1.0 if profile.get("duty") == task else 0.0,
		"offer": 0.0, "benevolence": float(profile.get("benevolence", 0.5)),
		"reliability": float(social.relation(responder, requester).get("reliability", 0.5)),
		"affinity": float(social.relation(responder, requester).get("affinity", 0.0)),
		"terms": {
			"item": str(config.actions[task].item), "amount": int(config.actions[task].amount),
			"occasion": occasion,
		},
	}
	# Coarse energy bands prevent unchanged clicks from getting fresh random rolls.
	context.energy = floorf(float(context.energy) * 5.0) / 5.0
	context.distance = floorf(float(context.distance) * 4.0) / 4.0
	var result: Dictionary = social.evaluate_request(requester, responder, task, context, config.social_policy, _rng, tick_index)
	if not result.has("id"):
		return result
	if interaction_results.has(result.id):
		return interaction_results[result.id].duplicate(true)
	if not interaction_results.has(result.id):
		var event_id: String = observe("request", requester, responder, {
			"task": task, "status": result.status,
			"participants": {"reason": result.get("reason", "")},
		})
		result.event_id = event_id
		if result.status == "accepted":
			var succeeded: bool = _executor.begin(responder, task, str(result.id), requester)
			if not succeeded:
				result.status = "unfulfilled"
				result.reason = "resources_or_route_unavailable"
				observe("request_blocked", responder, requester, {"task": task})
	result.message = _request_message(result)
	interaction_results[result.id] = result.duplicate(true)
	changed.emit()
	return result


func report_work(actor_id: String) -> bool:
	if not _actors.has(actor_id):
		return false
	var registrar: String = _registrar()
	if registrar.is_empty() or not bool(_actors[registrar].alive) or _distance(actor_id, registrar) > float(config.talk_radius):
		return false
	if not bool(Workplaces.assessment(self, registrar, "record").ok):
		return false
	var receipts: Array = _actors[actor_id].receipts
	var remaining: Array = []
	for receipt: Dictionary in receipts:
		var event_id: String = receipt.event
		if not social.knowledge[actor_id].has(event_id):
			remaining.append(receipt)
			continue
		if registrar != actor_id:
			social.learn(registrar, event_id, actor_id)
		if not social.knowledge[registrar].has(event_id):
			remaining.append(receipt)
			continue
		if institutions.issue("credit:" + event_id, config.institution.id, registrar, actor_id, int(receipt.amount), event_id):
			observe("registered", registrar, actor_id, {"amount": receipt.amount})
		else:
			remaining.append(receipt)
	_actors[actor_id].receipts = remaining
	return remaining.is_empty()


func approve_promotion(issuer: String, actor_id: String, rank_id: String) -> bool:
	if not _actors.has(issuer) or not _actors.has(actor_id) or not bool(_actors[issuer].alive):
		return false
	if not institutions.has_permission(config.institution.id, issuer, "authorize"):
		return false
	var next: RankDef = _content.get_rank(StringName(rank_id))
	var current: RankDef = _content.get_rank(StringName(_actors[actor_id].rank_id))
	if next == null or current == null or next.tier <= current.tier:
		return false
	if institutions.balance(config.institution.id, actor_id) < next.required_contribution:
		return false
	_actors[actor_id].rank_id = rank_id
	observe("promoted", issuer, actor_id, {"public": {"rank": rank_id}})
	changed.emit()
	return true


func grant_access(issuer: String, subject: String, scope: String) -> bool:
	if not _actors.has(subject) or not _can_authorize(issuer) or not places.has(scope):
		return false
	authorizations[subject + ":" + scope] = {"issuer": issuer, "subject": subject, "scope": scope}
	observe("authorized", issuer, subject, {"location": scope})
	return true


func has_access(subject: String, scope: String) -> bool:
	return authorizations.has(subject + ":" + scope)


func revoke_access(issuer: String, subject: String, scope: String) -> bool:
	if not _can_authorize(issuer):
		return false
	authorizations.erase(subject + ":" + scope)
	observe("access_revoked", issuer, subject, {"location": scope})
	return true


func _can_authorize(issuer: String) -> bool:
	return _actors.has(issuer) and bool(_actors[issuer].alive) and institutions.has_permission(config.institution.id, issuer, "authorize")


func observe(kind: String, actor_id: String, target: String, details: Dictionary) -> String:
	var witnesses: Array[String] = []
	for id: String in _actor_ids():
		if id != actor_id and id != target and bool(_actors[id].alive):
			if _distance(actor_id, id) <= float(config.observation_radius):
				witnesses.append(id)
	return social.record(kind, actor_id, target, details, witnesses, tick_index)


func _actor_ids() -> Array:
	var ids: Array = _actors.keys()
	ids.sort()
	return ids


func action_finished(actor_id: String, action: Dictionary, succeeded: bool, reason: String) -> void:
	var requester: String = action.requester
	var kind: String = "completed" if succeeded else "interrupted"
	var earned: int = int(action.get("credit_earned", 0)) if succeeded else 0
	var labor: String = notify_labor("scope", actor_id, action)
	var details: Dictionary = {"task": action.action, "public": {"work_credit": earned}, "private": {"reason": reason}}
	if not labor.is_empty():
		earned = 0
		details.public = {"work_credit": 0, "labor": labor}
		details.private["action_id"] = action.id
	var event_id: String = observe(kind, actor_id, "", details)
	notify_labor("finish" if succeeded else "fail", actor_id, action, event_id)
	if not requester.is_empty() and succeeded and _distance(actor_id, requester) <= float(config.talk_radius):
		social.learn(requester, event_id, actor_id)
		social.remember_outcome(requester, actor_id, "fulfilled", event_id)
	if earned > 0:
		_actors[actor_id].receipts.append({"event": event_id, "amount": earned})
	if action.action == "report" and succeeded:
		report_work(actor_id)
	# Successful helpers release their commitment; the original decision remains cached.
	if not str(action.request_id).is_empty() and interaction_results.has(action.request_id):
		interaction_results[action.request_id].execution = "fulfilled" if succeeded else "interrupted"


func actor_status(id: String) -> String:
	if not _actors.has(id):
		return "未知人物"
	var actor: Dictionary = _actors[id]
	if actor.active.is_empty():
		return str(actor.goal)
	var action: Dictionary = actor.active
	var label: String = config.actions[action.action].label
	return "前往%s · %s" % [places[action.destination].label, label] if action.phase == "travel" else label


func known_event_lines(actor_id: String, limit: int = 5) -> Array[String]:
	var result: Array[String] = []
	var known: Array[Dictionary] = social.known_events(actor_id)
	var start: int = maxi(0, known.size() - limit)
	for index in range(start, known.size()):
		var event: Dictionary = known[index]
		var person: String = _name(str(event.get("actor", "")))
		var details: Dictionary = event.get("details", {})
		var task: String = str(details.get("task", ""))
		var label: String = str(config.actions.get(task, {}).get("label", task))
		match str(event.get("kind", "")):
			"sparring_started": result.append("%s与%s约好切磋，点到为止。" % [person, _name(str(event.get("target", "")))])
			"practice_hit": result.append("%s一掌点中了%s。" % [person, _name(str(event.get("target", "")))])
			"sparring_ended": result.append("%s与%s收手调息。" % [person, _name(str(event.get("target", "")))])
			"stock_statement": result.append("%s谈到物资情况；这是他的说法。" % person)
			"completed": result.append("%s完成了%s" % [person, label])
			"interrupted": result.append("%s的%s中断了" % [person, label])
			"request": result.append("%s向%s请求%s" % [person, _name(str(event.get("target", ""))), label])
			"registered": result.append("%s为%s记入%d贡献" % [person, _name(str(event.get("target", ""))), int(details.get("amount", 0))])
			"picked_up": result.append("%s取走了物资" % person)
			"request_blocked": result.append("%s暂时无法办理%s" % [person, label])
			_: result.append("%s：%s" % [person, str(event.get("kind", ""))])
	return result


func allocate_id(prefix: String) -> String:
	var id: String = "%s:%d" % [prefix, _next_id]
	_next_id += 1
	return id


func to_dict() -> Dictionary:
	synchronize_actors()
	return {
		"version": SCHEMA_VERSION, "config": config.duplicate(true),
		"actors": _actors.duplicate(true), "places": places.duplicate(true),
		"situations": situations.duplicate(true), "authorizations": authorizations.duplicate(true),
		"interaction_results": interaction_results.duplicate(true),
		"inventory": inventory.to_dict(), "social": social.to_dict(),
		"land_resources": land_resources.to_dict(),
		"institutions": institutions.to_dict(), "tick_index": tick_index, "elapsed_ms": elapsed_ms,
		"controlled_actor": controlled_actor, "rng_state": str(_rng.state),
		"next_id": _next_id, "last_request": _last_request,
	}


func restore(data: Dictionary, allowed_subjects: Dictionary = {}, external_inventory: Dictionary = {}) -> bool:
	# Build and validate everything before swapping state. The previous game survives failure.
	if not SnapshotSchema.validate(data, _content, allowed_subjects, false, false, external_inventory):
		return false
	if int(data.get("version", -1)) != SCHEMA_VERSION or not _valid_config(data.get("config", {})):
		return false
	if not Workplaces.valid_places(data.places, data.config, null, _content.workplaces) or not Workplaces.actors_clear(data.places, data.actors):
		return false
	for field: String in ["actors", "places", "situations", "authorizations", "interaction_results", "inventory", "social", "institutions"]:
		if not data.get(field) is Dictionary:
			return false
	if not _whole(data.get("tick_index")) or not _whole(data.get("next_id")) or int(data.next_id) < 1:
		return false
	if not data.get("rng_state") is String or not str(data.rng_state).is_valid_int():
		return false
	if not data.get("controlled_actor") is String or not data.actors.has(data.controlled_actor):
		return false
	var next_inventory := SimInventory.new()
	var next_social := SimSocialMemory.new()
	var next_book := SimInstitutionBook.new()
	if not next_inventory.restore(data.inventory) or not next_social.restore(data.social) or not next_book.restore(data.institutions):
		return false
	for id: Variant in data.places:
		if not id is String or not data.places[id] is Dictionary or not _valid_cell(data.places[id].get("cell")):
			return false
	for id: Variant in data.actors:
		if not id is String or not _valid_actor(data.actors[id], data.config, data.places):
			return false
		if not next_inventory.containers.has("actor:" + id) or not next_social.knowledge.has(id):
			return false
		if _content == null or _content.get_pawn(StringName(data.actors[id].definition_id)) == null:
			return false
	var active_reservations: Dictionary = {}
	for id: String in data.actors:
		var action: Dictionary = data.actors[id].active
		if action.is_empty():
			continue
		if not str(action.get("requester", "")).is_empty() and not data.actors.has(action.requester):
			return false
		for reservation_id: String in action.reservations:
			if not next_inventory.reservations.has(reservation_id) or active_reservations.has(reservation_id):
				return false
			if next_inventory.reservations[reservation_id].owner_id != id:
				return false
			active_reservations[reservation_id] = true
	for reservation_id: String in external_inventory.get("reservations", {}):
		if active_reservations.has(reservation_id) or not next_inventory.reservations.has(reservation_id):
			return false
		var holder: String = str(next_inventory.reservations[reservation_id].owner_id)
		if not data.actors.has(holder) and (not allowed_subjects.has(holder) or external_inventory.get("external_reservation_owners", {}).get(reservation_id) != holder):
			return false
		active_reservations[reservation_id] = true
	if active_reservations.size() != next_inventory.reservations.size():
		return false
	for institution: Dictionary in next_book.institutions.values():
		for office: Dictionary in institution.offices.values():
			if not str(office.holder).is_empty() and not data.actors.has(office.holder):
				return false
	_native_advance = null
	_collect_actor_work_changes = false
	_actor_work_changes.clear()
	config = data.config.duplicate(true)
	invalidate_boundary_cache()
	_actors = data.actors.duplicate(true)
	places = data.places.duplicate(true)
	situations = data.situations.duplicate(true)
	authorizations = data.authorizations.duplicate(true)
	interaction_results = data.interaction_results.duplicate(true)
	inventory = next_inventory
	social = next_social
	institutions = next_book
	elapsed_ms = int(data.elapsed_ms)
	controlled_actor = data.controlled_actor
	_rng.state = int(data.rng_state)
	_next_id = int(data.next_id)
	_last_request = int(data.get("last_request", 0))
	land_resources = SimLandResources.new()
	# Containers have already been restored. Bind without re-creating sources.
	land_resources.bind_restored(self, _content.land_resources, data.land_resources)
	_executor = SimActionExecutor.new(self)
	_reset_actor_projections()
	simulation_work = {"step_count": 0, "boundary_count": 0, "batched_minutes": 0, "quiet_batch_calls": 0, "actor_settle_checks": 0, "actor_decision_checks": 0, "actor_merge_checks": 0}
	space_reset.emit()
	return true


func _choose_routine(id: String, consider_initiative: bool = true) -> void:
	var actor: Dictionary = synchronize_actor(id)
	actor.retry_ms = elapsed_ms + int(config.decision_interval) * MINUTE_MS
	if float(actor.hunger) <= float(config.needs.eat_below) and submit_action(id, "eat"):
		return
	if float(actor.energy) <= float(config.needs.rest_below) and submit_action(id, "rest"):
		return
	if not actor.receipts.is_empty():
		if report_work(id):
			return
		if submit_action(id, "report"):
			return
	var profile: Dictionary = config.actor_profiles.get(id, {})
	var duty: String = str(profile.get("duty", ""))
	var agreed: String = ""
	if _duty_provider.is_valid():
		agreed = str(_duty_provider.call(id, elapsed_ms))
		if not agreed.is_empty():
			duty = agreed
	if agreed.is_empty() and Workplaces.has_desk_duty(self, id):
		if Workplaces.at_desk(self, id):
			actor.goal = "在桌前值事，凭机构记功簿接待来人"
		elif not submit_action(id, "workspace_return"):
			actor.goal = "值事房去路不通，暂不能归岗"
		return
	if agreed.is_empty() and consider_initiative and _initiative_provider.is_valid() and bool(_initiative_provider.call(id, elapsed_ms)):
		return
	if not duty.is_empty():
		var definition: Dictionary = config.actions[duty]
		if definition.kind not in ["haul", "recipe"] and _choose_supply(id, duty):
			return
		if definition.kind in ["haul", "recipe"]:
			var topics: Array = [definition.item] if definition.kind == "haul" else definition.outputs.keys()
			for item: String in topics:
				if not bool(stock_understanding(id, definition.target, item).known):
					if submit_action(id, "check_kitchen"):
						return
		if _needed(id, duty) and submit_action(id, duty):
			return
		if definition.kind in ["haul", "recipe"] and _choose_supply(id, duty):
			return
	actor.goal = "等候物资或闲暇交往"


func _choose_supply(id: String, duty: String) -> bool:
	# The target buffer is understood through the same finite stock memories as
	# ordinary deliveries. Hidden natural-source counts never rank the choices.
	var actions: Array = config.actions.keys()
	actions.sort()
	for action_id: String in actions:
		var definition: Dictionary = config.actions[action_id]
		if definition.kind != "gather" or definition.get("supports", "") != duty:
			continue
		var belief: Dictionary = stock_understanding(id, definition.target, definition.item)
		if not bool(belief.known):
			return submit_action(id, str(definition.survey))
		if int(belief.amount) < int(definition.stock_below) and submit_action(id, action_id):
			return true
	return false


func needs_action(actor_id: String, action_id: String) -> bool:
	return _actors.has(actor_id) and config.actions.has(action_id) and _needed(actor_id, action_id)


func _needed(actor_id: String, action_id: String) -> bool:
	var definition: Dictionary = config.actions[action_id]
	if definition.kind in ["haul", "gather"]:
		var belief: Dictionary = stock_understanding(actor_id, definition.target, definition.item)
		return not bool(belief.known) or int(belief.amount) < int(definition.stock_below)
	if definition.kind == "recipe":
		for output: String in definition.outputs:
			var belief: Dictionary = stock_understanding(actor_id, definition.target, output)
			if not bool(belief.known) or int(belief.amount) < int(definition.stock_below):
				return true
		return false
	return true


func stock_understanding(observer: String, place: String, item: String) -> Dictionary:
	return SimStockInformation.assess(self, observer, place, item, _content.stock_information_policy)


func tell_stock(speaker: String, listener: String, place: String, item: String, amount: int) -> Dictionary:
	if not actor_controls(speaker, "communication"):
		return {"ok": false, "line": "眼下无法开口传话。"}
	return SimStockInformation.tell(self, speaker, listener, place, item, amount, _content.stock_information_policy)


func ask_stock(observer: String, speaker: String, place: String, item: String) -> Dictionary:
	if not actor_controls(observer, "communication") or not actor_controls(speaker, "communication") or observer == speaker or _distance(observer, speaker) > float(config.talk_radius):
		return {"ok": false, "line": "先走近些，才能当面询问。"}
	var belief: Dictionary = stock_understanding(speaker, place, item)
	if not bool(belief.known):
		return {"ok": false, "line": "对方没有新近的消息，暂时说不清楚。"}
	return tell_stock(speaker, observer, place, item, int(belief.amount))


func _update_situations() -> void:
	var scenario: Dictionary = config.scenario
	var definition: Dictionary = config.actions[scenario.task]
	var shortage: bool = inventory.quantity(definition.target, definition.item) == 0
	if shortage:
		if not situations.has("kitchen_shortage") or situations.kitchen_shortage.status != "open":
			situations["kitchen_shortage"] = {"id": allocate_id("situation"), "status": "open", "since": tick_index, "item": definition.item}
		if tick_index - _last_request >= int(config.request_interval):
			_last_request = tick_index
			var known: Dictionary = _actors[scenario.requester].stock_memory.get(definition.target, {})
			if known.is_empty() or int(known.items.get(definition.item, 0)) > 0:
				return
			for helper: String in scenario.helpers:
				var response: Dictionary = request_help(scenario.requester, helper, str(situations.kitchen_shortage.id))
				if response.get("status") == "accepted":
					break
	elif situations.has("kitchen_shortage") and situations.kitchen_shortage.status == "open":
		situations.kitchen_shortage.status = "resolved"
		situations.kitchen_shortage.resolved_at = tick_index


func observe_current_surroundings(actor_id: String) -> void:
	if _actors.has(actor_id) and bool(_actors[actor_id].alive):
		_refresh_stock_epoch()
		_observe_stock(actor_id)


func _refresh_stock_epoch() -> void:
	var changed_contents: bool = false
	for id: String in places:
		var items: Dictionary = inventory.containers[id]
		if _stock_contents.get(id) != items:
			_stock_contents[id] = items.duplicate(true)
			_stock_epoch += 1
			changed_contents = true
	if changed_contents and _native_crossing_interest.is_valid():
		invalidate_boundary_cache()


func _stock_places_near(cell: Vector2i) -> Array[String]:
	if not _stock_places_at_cell.has(cell):
		var nearby: Array[String] = []
		for id: String in places:
			if Vector2(cell).distance_to(Vector2(SimRouteTravel.cell(places[id].cell))) <= float(config.observation_radius):
				nearby.append(id)
		_stock_places_at_cell[cell] = nearby
	return _stock_places_at_cell[cell]


func _stock_crossing_required(actor: Dictionary) -> bool:
	var route: Dictionary = actor.active
	var origin: Vector2i = TileGrid.world_to_cell(Vector2(float(route.segment_from[0]), float(route.segment_from[1])))
	var target: Vector2i = SimRouteTravel.cell(route.path[0])
	# Off-centre and mixed diagonal legs may enter the two side cells separately.
	for y: int in range(mini(origin.y, target.y), maxi(origin.y, target.y) + 1):
		for x: int in range(mini(origin.x, target.x), maxi(origin.x, target.x) + 1):
			for id: String in _stock_places_near(Vector2i(x, y)):
				var memory: Dictionary = actor.stock_memory.get(id, {})
				if memory.get("tick", -1) != tick_index or memory.get("items") != inventory.containers[id]:
					return true
	return false


func _observe_stock(actor_id: String) -> void:
	var actor: Dictionary = _actors[actor_id]
	var cell: Vector2i = SimRouteTravel.cell(actor.cell)
	var previous_observation: Array = _stock_observations.get(actor_id, [])
	if previous_observation.size() == 3 and previous_observation[0] == cell and previous_observation[1] == tick_index and previous_observation[2] == _stock_epoch:
		return
	_stock_observations[actor_id] = [cell, tick_index, _stock_epoch]
	for id: String in _stock_places_near(cell):
		var previous: Dictionary = actor.stock_memory.get(id, {})
		# The exact same minute/contents are the same observation. Quantity
		# changes remain visible immediately, including direct recipe commits.
		if previous.get("tick", -1) != tick_index or previous.get("items") != inventory.containers[id]:
			actor.stock_memory[id] = {"items": inventory.containers[id].duplicate(true), "tick": tick_index}


func _registrar() -> String:
	var office_data: Dictionary = institutions.institutions[config.institution.id].offices
	for office: Dictionary in office_data.values():
		if office.permissions.has("record"):
			return str(office.holder)
	return ""


func _distance(a: String, b: String) -> float:
	var left: Array = _actors[a].cell
	var right: Array = _actors[b].cell
	return Vector2(float(left[0]), float(left[1])).distance_to(Vector2(float(right[0]), float(right[1])))


func _name(id: String) -> String:
	var definition_id: String = str(_actors.get(id, {}).get("definition_id", id))
	var definition: PawnDef = _content.get_pawn(StringName(definition_id)) if _content != null else null
	return definition.display_name if definition != null else id


func _request_message(result: Dictionary) -> String:
	if result.status == "accepted":
		return "%s答应帮忙送柴。" % _name(result.responder)
	if result.status == "unfulfilled":
		return "%s答应了，但物资或道路暂时不允许。" % _name(result.responder)
	return "%s暂不答应：还要顾及自己的安排与精力。" % _name(result.responder)


static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= 0.0


static func _valid_cell(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _whole(value[0]) and _whole(value[1])


static func _valid_config(value: Variant) -> bool:
	return SimSchema.validate_config(value)


static func _valid_actor(value: Variant, settings: Dictionary, locations: Dictionary) -> bool:
	if not value is Dictionary or not _valid_cell(value.get("cell")):
		return false
	for field: String in ["hunger", "energy"]:
		if not (value.get(field) is float or value.get(field) is int):
			return false
		if not is_finite(float(value[field])) or float(value[field]) < 0.0 or float(value[field]) > 100.0:
			return false
	if not value.get("definition_id") is String or not value.get("goal") is String or not value.get("receipts") is Array:
		return false
	if not value.get("active") is Dictionary or not value.get("alive") is bool or not value.get("autonomous") is bool or not _whole(value.get("retry_ms")):
		return false
	var action: Dictionary = value.active
	if action.is_empty():
		return true
	if not settings.actions.has(action.get("action")) or not locations.has(action.get("destination")):
		return false
	if not action.get("phase") in ["travel", "work"] or not action.get("path") is Array or not action.get("reservations") is Array:
		return false
	if not action.get("id") is String or not _whole(action.get("due_ms")):
		return false
	for cell: Variant in action.path:
		if not _valid_cell(cell):
			return false
	return _whole(action.get("started_ms")) and action.get("carrying") is bool and action.get("request_id") is String and action.get("requester") is String
