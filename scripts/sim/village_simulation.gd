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
var simulation_work: Dictionary = {"step_count": 0, "boundary_count": 0, "batched_minutes": 0, "quiet_batch_calls": 0, "actor_settle_checks": 0, "actor_decision_checks": 0}

var _content: ReolContentDB
var _boundary_revision_provider: Callable
var _boundary_revision: int = -1
var _actor_boundaries: Dictionary[String, int] = {}
var _boundary_index := SimParticipationIndex.new()
var _boundary_index_ready: bool = false
var _dirty_actor_boundaries: Dictionary[String, bool] = {}
var _boundary_invalidation_revision: int = 0
const NATIVE_BOUNDARY: StringName = &"native_action"
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
	simulation_work = {"step_count": 0, "boundary_count": 0, "batched_minutes": 0, "quiet_batch_calls": 0, "actor_settle_checks": 0, "actor_decision_checks": 0}
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


func next_boundary_ms() -> int:
	var boundary: int = land_resources.next_boundary_ms()
	var cached: bool = _boundary_revision_provider.is_valid()
	if cached:
		var revision: int = int(_boundary_revision_provider.call())
		if revision != _boundary_revision:
			synchronize_actors()
			invalidate_boundary_cache()
			_boundary_revision = revision
	if cached and _next_actor_boundary > elapsed_ms:
		boundary = mini(boundary, _next_actor_boundary)
	else:
		_next_actor_boundary = _query_actor_boundary(cached)
		boundary = mini(boundary, _next_actor_boundary)
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


func _query_actor_boundary(cached: bool) -> int:
	var boundary: int = SimInventory.MAX_COUNT
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
		if not bool(actor.alive):
			if cached:
				_boundary_index.cancel_due(NATIVE_BOUNDARY, id)
				_dirty_actor_boundaries.erase(id)
			continue
		if not actor.active.is_empty():
			if not actor_controls(id, "action") or not actor_controls(id, "motion"):
				actor_boundary = elapsed_ms + 1
			else:
				actor_boundary = _executor.next_boundary_ms(actor)
		elif bool(actor.autonomous):
			actor_boundary = maxi(elapsed_ms + 1, int(actor.retry_ms))
		if cached:
			_actor_boundaries[id] = actor_boundary
			_boundary_index.set_member(NATIVE_BOUNDARY, id)
			_boundary_index.set_due(NATIVE_BOUNDARY, id, actor_boundary)
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
	_boundary_revision = -1
	invalidate_boundary_cache()


func invalidate_boundary_cache() -> void:
	_boundary_invalidation_revision += 1
	_actor_boundaries.clear()
	_boundary_index.clear()
	_boundary_index_ready = false
	_dirty_actor_boundaries.clear()
	_next_actor_boundary = -1


func invalidate_actor_boundary(id: String) -> void:
	_boundary_invalidation_revision += 1
	_actor_boundaries.erase(id)
	_dirty_actor_boundaries[id] = true
	_next_actor_boundary = -1


func has_cached_boundary_ahead(id: String) -> bool:
	return _boundary_revision_provider.is_valid() and int(_actor_boundaries.get(id, 0)) > elapsed_ms


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


func advance_to_ms(target_ms: int, max_events: int = 4096) -> bool:
	if target_ms < elapsed_ms or target_ms > SimInventory.MAX_COUNT or _executor == null:
		return false
	var events_left: int = max_events
	var initial_minute: int = tick_index
	var ids: Array = []
	if not _sparse_actor_projection or not _boundary_revision_provider.is_valid():
		ids = _actor_ids()
	while elapsed_ms < target_ms:
		var boundary: int = next_boundary_ms()
		var next: int = mini(target_ms, boundary)
		if next == boundary and events_left < 1:
			return false
		var sparse: bool = _sparse_actor_projection and _boundary_revision_provider.is_valid()
		if not sparse:
			# Keep opaque standalone input callbacks on their original pre-advance
			# interval and order; they have not promised observable rate changes.
			for id: String in _actors:
				_decay_actor(id, elapsed_ms, next - elapsed_ms)
		land_resources.advance_to_ms(next)
		elapsed_ms = next
		if not sparse:
			# All original needs were integrated above in their old-input order.
			# A synchronous geometry/crossing observer must not integrate a later
			# body twice or project it ahead of this stable projection pass.
			for id: String in ids:
				_actor_projection_ms[id] = elapsed_ms
			_all_projected_ms = elapsed_ms
		var projecting: Array = _boundary_index.due_ids(NATIVE_BOUNDARY, elapsed_ms) if sparse else ids
		projecting.sort() # Original same-millisecond actor order, not heap order.
		if sparse:
			# Due bodies finish their old-input needs before synchronous geometry
			# notices can inspect peers. This is still only the due set, not N
			# integrations for each other actor's cell crossing.
			for id: String in projecting:
				_integrate_actor(id)
		for id: String in projecting:
			_executor.project(id, elapsed_ms)
		if next == boundary:
			var due: Array = _boundary_index.due_ids(NATIVE_BOUNDARY, elapsed_ms) if _boundary_revision_provider.is_valid() else ids
			_settle_actor_work(due, false)
			_settle_actor_work(due, true)
			_update_situations()
			events_left -= 1
			simulation_work.boundary_count = int(simulation_work.boundary_count) + 1
		_refresh_stock_epoch()
		var observing: Array = _actor_ids() if not sparse or _stock_observed_epoch != _stock_epoch or _stock_observed_minute != tick_index else _stock_dirty_actors.keys()
		observing.sort()
		for id: String in observing:
			if bool(_actors[id].alive):
				_observe_stock(id)
		_stock_dirty_actors.clear()
		_stock_observed_epoch = _stock_epoch
		_stock_observed_minute = tick_index
	simulation_work.batched_minutes = int(simulation_work.batched_minutes) + tick_index - initial_minute
	simulation_work.quiet_batch_calls = int(simulation_work.quiet_batch_calls) + 1
	changed.emit()
	return true


func _settle_actor_work(due: Array, choosing: bool) -> void:
	# A pass keeps the original ID order. A synchronous observer can invalidate
	# a later body during this pass; merge that suffix without rescanning N peers.
	# Earlier IDs wait for the next boundary, as in the original ordered loop.
	var candidates: Array = due.duplicate()
	var included: Dictionary = {}
	for id: String in candidates:
		included[id] = true
	_merge_actor_work(candidates, included, "")
	var revision: int = _boundary_invalidation_revision
	var cursor: int = 0
	while cursor < candidates.size():
		var id: String = candidates[cursor]
		cursor += 1
		var actor: Dictionary = _actors[id]
		if choosing:
			simulation_work.actor_decision_checks = int(simulation_work.actor_decision_checks) + 1
			if bool(actor.alive) and bool(actor.autonomous) and actor.active.is_empty() and elapsed_ms >= int(actor.retry_ms):
				_choose_routine(id)
		elif not _boundary_revision_provider.is_valid() or int(_actor_boundaries.get(id, 0)) <= elapsed_ms:
			simulation_work.actor_settle_checks = int(simulation_work.actor_settle_checks) + 1
			_executor.settle(id)
		if revision != _boundary_invalidation_revision:
			_merge_actor_work(candidates, included, id)
			revision = _boundary_invalidation_revision


func _merge_actor_work(candidates: Array, included: Dictionary, after: String) -> void:
	var changed: bool = false
	var invalidated: Array = _dirty_actor_boundaries.keys() if _boundary_index_ready else _actor_ids()
	for id: String in invalidated:
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
	if _materializing_actors or _all_projected_ms == elapsed_ms:
		return _actors
	_materializing_actors = true
	for id: String in _actor_ids():
		synchronize_actor(id)
	_materializing_actors = false
	_all_projected_ms = elapsed_ms
	return _actors


func _reset_actor_projections() -> void:
	_actor_projection_ms.clear()
	_projecting_actors.clear()
	for id: String in _actors:
		_actor_projection_ms[id] = elapsed_ms
	_all_projected_ms = elapsed_ms


func _decay_actor(id: String, from_ms: int, duration_ms: int) -> void:
	var hunger_rate: int = roundi(float(config.needs.hunger_per_minute) * NEED_SCALE)
	var base_energy_rate: int = roundi(float(config.needs.energy_per_minute) * NEED_SCALE)
	var work_rate: int = roundi(float(config.needs.work_energy_per_minute) * NEED_SCALE)
	var actor: Dictionary = _actors[id]
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
		var missing: int = definition.max_stamina - int(actor.stamina)
		if missing == 0:
			actor.stamina_carry = 0
			return
		var rate: int = int(motion_rules.recovery.stamina_per_second)
		var gain: int = int(actor.stamina_carry) + rate * mini(duration, ceili(float(missing * 1000) / rate))
		@warning_ignore("integer_division")
		var units: int = gain / 1000
		actor.stamina = mini(definition.max_stamina, int(actor.stamina) + units)
		actor.stamina_carry = gain % 1000 if int(actor.stamina) < definition.max_stamina else 0


func _recover_need(actor: Dictionary, kind: String, rate: int, duration_ms: int) -> void:
	# The same saved fractional debt works for positive and negative rates.
	# Saturate before multiplication, keeping huge absent-world jumps in range.
	var available: int = roundi(float(actor[kind]) * NEED_SCALE)
	if duration_ms >= ceili(float((100 * NEED_SCALE - available) * MINUTE_MS + int(actor.need_carry[kind])) / rate):
		actor[kind] = 100.0
		actor.need_carry[kind] = 0
		return
	var numerator: int = int(actor.need_carry[kind]) - rate * duration_ms
	@warning_ignore("integer_division")
	var spent: int = numerator / MINUTE_MS
	var remainder: int = numerator % MINUTE_MS
	if remainder < 0:
		spent -= 1
		remainder += MINUTE_MS
	actor[kind] = float(available - spent) / NEED_SCALE
	actor.need_carry[kind] = remainder


func _decay_need(actor: Dictionary, kind: String, rate: int, duration_ms: int) -> void:
	# Fixed-point numerator with a saved remainder; fine frames and sparse
	# absent-region jumps lose exactly the same fractions, including rate changes.
	if rate == 0:
		return
	var available: int = roundi(float(actor[kind]) * NEED_SCALE)
	if duration_ms >= ceili(float(available * MINUTE_MS - int(actor.need_carry[kind])) / rate):
		actor[kind] = 0.0
		actor.need_carry[kind] = 0
		return
	var numerator: int = int(actor.need_carry[kind]) + rate * duration_ms
	@warning_ignore("integer_division")
	var spent: int = numerator / MINUTE_MS
	var remaining: int = maxi(0, roundi(float(actor[kind]) * NEED_SCALE) - spent)
	actor[kind] = float(remaining) / NEED_SCALE
	actor.need_carry[kind] = numerator % MINUTE_MS if remaining > 0 else 0


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
	invalidate_actor_boundary(id)
	var before: Vector2i = SimRouteTravel.cell(_actors[id].cell)
	SimRouteTravel.put(_actors[id], point)
	if before != SimRouteTravel.cell(_actors[id].cell):
		_stock_dirty_actors[id] = true
		body_space_changed.emit(id)


func project_actor_route(id: String, route: Dictionary, at_ms: int) -> void:
	var before: Vector2i = SimRouteTravel.cell(_actors[id].cell)
	SimRouteTravel.project(route, _actors[id], at_ms)
	if before != SimRouteTravel.cell(_actors[id].cell):
		_stock_dirty_actors[id] = true
		var crossing: int = SimRouteTravel.crossing_from_cell_ms(route, before, int(route.segment_started_ms))
		body_cell_crossed.emit(id, SimRouteTravel.cell(_actors[id].cell), crossing)
		body_space_changed.emit(id)


func notify_body_space_changed(id: String) -> void:
	# Manual motion writes the same original body, notifying on cell crossings.
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
	simulation_work = {"step_count": 0, "boundary_count": 0, "batched_minutes": 0, "quiet_batch_calls": 0, "actor_settle_checks": 0, "actor_decision_checks": 0}
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
	for id: String in places:
		var items: Dictionary = inventory.containers[id]
		if _stock_contents.get(id) != items:
			_stock_contents[id] = items.duplicate(true)
			_stock_epoch += 1


func _observe_stock(actor_id: String) -> void:
	var actor: Dictionary = _actors[actor_id]
	var cell: Vector2i = SimRouteTravel.cell(actor.cell)
	var previous_observation: Array = _stock_observations.get(actor_id, [])
	if previous_observation.size() == 3 and previous_observation[0] == cell and previous_observation[1] == tick_index and previous_observation[2] == _stock_epoch:
		return
	_stock_observations[actor_id] = [cell, tick_index, _stock_epoch]
	if not _stock_places_at_cell.has(cell):
		var nearby: Array[String] = []
		for id: String in places:
			if Vector2(cell).distance_to(Vector2(SimRouteTravel.cell(places[id].cell))) <= float(config.observation_radius):
				nearby.append(id)
		_stock_places_at_cell[cell] = nearby
	for id: String in _stock_places_at_cell[cell]:
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
