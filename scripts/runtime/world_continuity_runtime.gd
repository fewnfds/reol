class_name WorldContinuityRuntime
extends CommittedWorldCanvas
## Two settlements own persistent data; views follow actual visible bodies.
## This adapter owns presentation and player travel, never regional social rules.

signal region_changed(region_id: String)
signal player_travel_advanced(position_value: Vector2)
signal resident_selected(pawn: Pawn)
signal avatar_changed
signal save_finished(path: String, result: Error)
signal player_command_finished(id: int, kind: String, result: Dictionary)

const Opening = preload("res://scripts/runtime/world_opening.gd")

var world_sim: RegionalSimulation
var centers: Dictionary = {}
var current_region: String = "home"
var settings: Dictionary = {}
var player_journey: Dictionary = {}
var service_adapter: SettlementServicesRuntime
var object_adapter: WorldObjectsRuntime
var sparring_adapter: SparringRuntime
var conflict_adapter: ConflictRuntime
var capability_adapter: CapabilityNetworkRuntime
var field_adapter: FieldOpportunityRuntime
var avian_adapter: AvianLifeRuntime
var soul_adapter: SoulVesselRuntime
var interaction_adapter: InteractionRequestsRuntime
var heat_method_adapter: HeatMethodsRuntime
var construction_adapter: ConstructionRuntime
var clothing_adapter: ClothingRuntime
var spirit_adapter: SpiritSourceRuntime
var natural_adapter: NaturalWorldRuntime
var weather_adapter: WeatherRuntime
var light_adapter: LocalLightRuntime
var large_body_adapter: LargeBodiesRuntime
var avatar_adapter: Node
var avatar_subject: String = "subject:player"
var _opening_selection_available: bool = false

var _home: VillageRuntime
var _remote_views: Dictionary[String, Pawn] = {}
var _panel: WorldContinuityPanel
var _notice: String = "两地各自生活；前往另一处，观察途中和归来的变化。"
var _selected_remote: String = ""
var _known_lines: Array[String] = []
var _courier_cell: Vector2i = Vector2i.ZERO
var _courier_visible: bool = false
var _saves: SimSaveSession
var _field_compute: EnvironmentFieldComputeRuntime
var _retired_field_compute: Array[EnvironmentFieldComputeRuntime] = []
var _player_commands := ReolPlayerCommandBuffer.new()


func home_runtime() -> VillageRuntime:
	return _home


static func valid_runtime_settings(value: Dictionary) -> bool:
	# These are view/navigation policy inputs; RegionalSimulation separately
	# validates the world's regions, routes, owners and common clocks.
	if not SnapshotValues.valid_integer(value.get("event_budget"), 1) or not value.get("runtime") is Dictionary:
		return false
	var policy: Dictionary = value.runtime
	for field: String in ["layout_radius", "layout_budget", "enter_radius", "exit_radius"]:
		if not SnapshotValues.valid_integer(policy.get(field), 1):
			return false
	if int(policy.exit_radius) < int(policy.enter_radius) or not policy.get("remote_names") is Dictionary or not SnapshotValues.valid_integer(policy.get("help_offer_coins"), 0):
		return false
	for key: Variant in policy.remote_names:
		if not key is String or not policy.remote_names[key] is String:
			return false
	return true


func setup(home: VillageRuntime, opening_source_loan: bool = false, opening_source_care: bool = false, opening_field: bool = false) -> bool:
	if home == null or home.simulation == null or world_sim != null:
		return false
	_home = home
	if home._fog != null and not home._fog.visibility_updated.is_connected(redraw_committed_canvas):
		home._fog.visibility_updated.connect(redraw_committed_canvas)
	if home._fog != null and not home._fog.visibility_updated.is_connected(_on_visibility_updated):
		home._fog.visibility_updated.connect(_on_visibility_updated)
	if GameClock.start_minutes != int(home._content.climate.calendar.start_minutes):
		push_error("World continuity: calendar and original clock start hour differ")
		return false
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 8
	if not Opening.assemble(self, home, opening_source_loan, opening_source_care, opening_field):
		return false
	_bind_navigation()
	_build_panel()
	object_adapter = WorldObjectsRuntime.new()
	_attach_adapter(object_adapter, &"WorldObjectsRuntime")
	sparring_adapter = SparringRuntime.new()
	_attach_adapter(sparring_adapter, &"SparringRuntime")
	capability_adapter = CapabilityNetworkRuntime.new()
	_attach_adapter(capability_adapter, &"CapabilityNetworkRuntime")
	conflict_adapter = ConflictRuntime.new()
	_attach_adapter(conflict_adapter, &"ConflictRuntime")
	avian_adapter = AvianLifeRuntime.new()
	_attach_adapter(avian_adapter, &"AvianLifeRuntime")
	soul_adapter = SoulVesselRuntime.new()
	_attach_adapter(soul_adapter, &"SoulVesselRuntime")
	interaction_adapter = InteractionRequestsRuntime.new()
	_attach_adapter(interaction_adapter, &"InteractionRequestsRuntime")
	large_body_adapter = LargeBodiesRuntime.new()
	_attach_adapter(large_body_adapter, &"LargeBodiesRuntime")
	heat_method_adapter = HeatMethodsRuntime.new()
	_attach_adapter(heat_method_adapter, &"HeatMethodsRuntime")
	construction_adapter = ConstructionRuntime.new()
	_attach_adapter(construction_adapter, &"ConstructionRuntime")
	weather_adapter = WeatherRuntime.new()
	_attach_adapter(weather_adapter, &"WeatherRuntime")
	light_adapter = LocalLightRuntime.new()
	_attach_adapter(light_adapter, &"LocalLightRuntime")
	clothing_adapter = ClothingRuntime.new()
	_attach_adapter(clothing_adapter, &"ClothingRuntime")
	spirit_adapter = SpiritSourceRuntime.new()
	_attach_adapter(spirit_adapter, &"SpiritSourceRuntime")
	natural_adapter = NaturalWorldRuntime.new()
	_attach_adapter(natural_adapter, &"NaturalWorldRuntime")
	field_adapter = FieldOpportunityRuntime.new()
	_attach_adapter(field_adapter, &"FieldOpportunityRuntime")
	home.simulation_advanced.connect(_on_advanced)
	_refresh_views(true)
	_refresh_panel()
	GameClock.time_advanced.connect(_capture_committed_canvases)
	_capture_committed_canvases()
	_configure_field_compute()
	_player_commands.finished.connect(_on_player_command_finished)
	GameClock.input_boundary.connect(_drain_player_commands)
	return true


func _attach_adapter(adapter: Node, node_name: StringName) -> void:
	adapter.name = node_name
	add_child(adapter)
	adapter.setup(self)


func _configure_field_compute() -> void:
	if world_sim == null:
		return
	var mode: String = "auto"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--environment-backend="):
			mode = argument.get_slice("=", 1)
	var service := EnvironmentFieldComputeRuntime.new()
	if not service.configure(world_sim.environment_fields._field, mode):
		return
	_field_compute = service
	world_sim.environment_fields._field.set_compute_backend(service)
	service.warmup()


func _retire_field_compute() -> void:
	if _field_compute == null:
		return
	var info: Dictionary = _field_compute.diagnostics()
	if bool(info.busy):
		_field_compute.cancel(int(info.ticket))
		_retired_field_compute.append(_field_compute)
	else:
		_field_compute.close()
	_field_compute = null


func _capture_committed_canvases(_from_ms: int = 0, _to_ms: int = 0) -> void:
	# Connected after the ordinary clock observers: body/fog invalidation and
	# panels are committed, and the clock cannot start another interval yet.
	var snap: bool = _to_ms <= _from_ms
	if not _presentation_ready():
		return
	# All ordinary observers have finished. Publish body views once, sharing
	# the layout, rather than rebuilding them inside each executor continuation.
	var layout: PawnViewLayout = actor_view_layout()
	var poses := HumanoidPose.WorldFrame.new(world_sim, GameClock.elapsed_ms)
	HumanoidSprite.publish_time(GameClock.elapsed_ms)
	_home._sync_actor_views(snap, layout, poses)
	_refresh_views(snap, layout, poses)
	_refresh_advance_views()
	_home.publish_actor_motion(GameClock.elapsed_ms, snap)
	for pawn: Pawn in _remote_views.values():
		pawn.publish_motion(GameClock.elapsed_ms, snap)
	var views: Array[CommittedWorldCanvas] = [self, _home, natural_adapter, object_adapter,
		sparring_adapter, conflict_adapter, avian_adapter, soul_adapter,
		large_body_adapter, construction_adapter, field_adapter, spirit_adapter]
	for view: CommittedWorldCanvas in views:
		if is_instance_valid(view):
			view.clock_published_canvas = true
			view.redraw_committed_canvas(true)


func actor_region(actor: String) -> String:
	if world_sim == null:
		return ""
	for region: String in world_sim.regions:
		if world_sim.regions[region].has_actor(actor):
			return region
	return ""


func actor_view(actor: String) -> Pawn:
	return _home._pawns.get(actor) as Pawn if actor_region(actor) == "home" else _remote_views.get(actor) as Pawn


func actor_view_layout() -> PawnViewLayout:
	# No merger or materialization of body tables. Visitors join residents in
	# their actual visible cell regardless of the owner of their original body.
	var layout := PawnViewLayout.new(_home._fog)
	for sim: VillageSimulation in world_sim.regions.values():
		layout.include_bodies(sim.actors, GameClock.elapsed_ms, sim.native_route_projections())
	layout.finish("player")
	return layout


func select_actor_view(pawn: Pawn) -> void:
	var id: String = String(pawn.pawn_id)
	clear_remote_selection()
	if actor_region(id) != "home":
		_selected_remote = id
	pawn.set_selected(true)
	if _presentation_ready():
		_home._sync_needs(pawn.state, world_sim.regions[actor_region(id)].projected_actor_needs(id))


func visible_actor_status(actor: String) -> String:
	var region_id: String = actor_region(actor)
	var pawn: Pawn = actor_view(actor)
	if region_id.is_empty() or not is_instance_valid(pawn) or not pawn.visible:
		return "已离开视野"
	return world_sim.regions[region_id].actor_status(actor)


func _on_visibility_updated() -> void:
	if world_sim == null or world_sim.has_pending_boundary() or GameClock.is_advancing():
		return
	# Fog updates while paused too. Refresh only scene projections, not clocks,
	# learning, route progress or the hidden world's event outcome.
	_refresh_views(true)
	if field_adapter != null:
		field_adapter.refresh()
	redraw_committed_canvas()


var _navigation_revision: int = 0
var _navigation_connections: Array[Array] = []
var _plant_navigation_cells: Dictionary[String, Vector2i] = {}
var _large_navigation_bounds: Dictionary[String, Rect2i] = {}


func _bind_navigation() -> void:
	for link: Array in _navigation_connections:
		var event: Signal = link[0]
		if is_instance_valid(event.get_object()) and event.is_connected(link[1]):
			event.disconnect(link[1])
	_navigation_connections.clear()
	_plant_navigation_cells.clear()
	_large_navigation_bounds.clear()
	_navigation_revision += 1
	for event: Signal in [world_sim.map_data.terrain_changed, world_sim.construction.space_changed]:
		event.connect(_navigation_changed)
		_navigation_connections.append([event, _navigation_changed])
	for id: String in world_sim.plants.bodies:
		var cell: Variant = _blocking_plant_cell(id)
		if cell is Vector2i:
			_plant_navigation_cells[id] = cell
	for id: String in world_sim.large_bodies.bodies:
		_large_navigation_bounds[id] = world_sim.large_bodies.swept_bounds(id)
	for link: Array in [[world_sim.plants.plant_changed, _plant_navigation_changed], [world_sim.large_bodies.body_space_changed, _large_navigation_changed], [world_sim.large_bodies.bodies_space_changed, _large_navigation_batch_changed]]:
		link[0].connect(link[1])
		_navigation_connections.append(link)
	world_sim.large_bodies.space_reset.connect(_large_navigation_reset)
	_navigation_connections.append([world_sim.large_bodies.space_reset, _large_navigation_reset])
	_home._world.bind_map_data(world_sim.map_data)
	_home._world.set_obstacle_provider(_physical_obstacle, _native_boundary_revision)
	_home._world.set_sight_obstacle_provider(world_sim.construction.blocks_sight)
	if _home._fog != null:
		_home._fog.set_projection_guard(_presentation_ready)
	world_sim.large_bodies.set_geometry(world_sim.map_data.terrain_is_walkable, world_sim.map_data.get_elevation, _incoming_occupancy, true)
	world_sim.construction.set_terrain(world_sim.map_data.terrain_is_walkable, world_sim.map_data.get_elevation)
	world_sim.construction.set_incoming_occupancy(_incoming_occupancy)
	_home.simulation = world_sim.regions.home
	_home._player.motion.bind_body(_home.simulation.synchronize_actor("player"), _home.simulation.notify_body_space_changed.bind("player"), _home.simulation.notify_body_cell_crossed.bind("player"))
	_home._player.set_motion_guard(_player_has_motion_control)
	if not _home._player.cell_changed.is_connected(_on_player_moved):
		_home._player.cell_changed.connect(_on_player_moved)
	world_sim.set_local_action_owner(_local_action_owns)
	_home.bind_shared_motion(world_sim)
	GameClock.bind_wait_guard(_can_wait)
	world_sim.settlement.set_completion_readiness(GameClock.ready_for_publication)
	_home._places = _home.simulation.places.duplicate(true)
	for region: String in world_sim.regions:
		var sim: VillageSimulation = world_sim.regions[region]
		sim.set_navigation(_find_path, _can_step)
		sim.set_boundary_revision_provider(_native_boundary_revision)
		sim.set_route_geometry_revision_provider(_native_geometry_revision)
		sim.set_native_crossing_interest(world_sim.environment_fields.needs_native_crossings.bind(region))
		sim.set_sparse_actor_projection(true)
		# Original route geometry and its change revision are bound above. Local
		# crossings stay in the resumable body owner; gameplay deadlines still
		# split the shared world before any other domain can observe an effect.
		sim.native_route_events_enabled = true
		sim.configure_actor_execution()
	if world_sim.services != null:
		world_sim.services.set_navigation(_find_path, _can_step)
	world_sim.sparring.set_geometry(_practice_contact_allowed, _can_step)
	world_sim.avian_life.set_landing_check(_home._world.is_walkable)
	if object_adapter != null:
		object_adapter.reset_observation()
	if spirit_adapter != null:
		spirit_adapter.reset_observation()
	if avian_adapter != null:
		avian_adapter.reset_observation()
	if soul_adapter != null:
		soul_adapter.reset_observation()
	if interaction_adapter != null:
		interaction_adapter.reset_observation()
	if heat_method_adapter != null:
		heat_method_adapter.reset_observation()
	if construction_adapter != null:
		construction_adapter.reset_observation()
	if natural_adapter != null:
		natural_adapter.reset_observation()
	if conflict_adapter != null:
		conflict_adapter.reset_observation()
	if capability_adapter != null:
		capability_adapter.reset_observation()
	if field_adapter != null:
		field_adapter.reset_observation()


func _navigation_changed(cells: Array[Vector2i] = []) -> void:
	var previous_revision: int = _native_boundary_revision()
	var previous_geometry: int = _native_geometry_revision()
	_navigation_revision += 1
	_home._world.invalidate_navigation(cells, previous_revision)
	for region: String in world_sim.regions:
		var invalidated: Array[String] = world_sim.regions[region].update_native_route_geometry(cells, previous_geometry, _native_geometry_revision(), previous_revision, _native_boundary_revision())
		for actor: String in invalidated:
			world_sim.invalidate_region(region, actor)


func _native_boundary_revision() -> int:
	# Connecting the first spatial observer can make cell edges consequential
	# even before a query builds the index. The bit changes existing deadlines;
	# route geometry proofs keep their separate, unchanged geometry revision.
	var spatial: int = int(world_sim.space != null and world_sim.space.needs_native_crossings())
	return (_native_geometry_revision() + world_sim.embodiment.native_motion_revision) * 2 + spatial


func _native_geometry_revision() -> int:
	var revision: int = _navigation_revision
	for sim: VillageSimulation in world_sim.regions.values():
		revision += int(sim.config.get("workplaces_version", 0))
	return revision


func _blocking_plant_cell(id: String) -> Variant:
	var row: Dictionary = world_sim.plants.bodies.get(id, {})
	if row.is_empty() or row.stage in ["root", "removed", "dead"] or not str(row.location.support).is_empty() or not bool(world_sim.plants.definitions.types[row.definition].blocks):
		return null
	return world_sim.plants.cell_of(id)


func _plant_navigation_changed(id: String) -> void:
	var previous: Variant = _plant_navigation_cells.get(id)
	var current: Variant = _blocking_plant_cell(id)
	if previous == current:
		return # Growth, products and dormancy alone do not change walkability.
	var cells: Array[Vector2i] = []
	if previous is Vector2i:
		cells.append(previous)
		_plant_navigation_cells.erase(id)
	if current is Vector2i:
		cells.append(current)
		_plant_navigation_cells[id] = current
	_navigation_changed(cells)


func _large_navigation_changed(id: String) -> void:
	_large_navigation_batch_changed([id])


func _large_navigation_reset() -> void:
	_large_navigation_bounds.clear()
	for id: String in world_sim.large_bodies.bodies:
		_large_navigation_bounds[id] = world_sim.large_bodies.swept_bounds(id)
	_navigation_changed()


func _large_navigation_batch_changed(ids: Array[String]) -> void:
	var changed: Dictionary[Vector2i, bool] = {}
	for id: String in ids:
		var previous: Rect2i = _large_navigation_bounds.get(id, Rect2i())
		var current: Rect2i = world_sim.large_bodies.swept_bounds(id) if world_sim.large_bodies.bodies.has(id) else Rect2i()
		if previous == current:
			continue
		for area: Rect2i in [previous, current]:
			for y: int in range(area.position.y, area.end.y):
				for x: int in range(area.position.x, area.end.x):
					changed[Vector2i(x, y)] = true
		if current.has_area():
			_large_navigation_bounds[id] = current
		else:
			_large_navigation_bounds.erase(id)
	if not changed.is_empty():
		var cells: Array[Vector2i] = []
		cells.assign(changed.keys())
		_navigation_changed(cells)


func _incoming_occupancy(cell: Vector2i) -> bool:
	return world_sim != null and SimMotionClearance.segment_reserves(world_sim.regions.home.synchronize_actor("player"), player_journey, cell)


func _physical_obstacle(cell: Vector2i) -> bool:
	# Construction already includes accepted workplace walls and fixtures.
	return world_sim.plants.blocked(cell) or world_sim.construction.blocked(cell) or world_sim.large_bodies.blocked(cell)


func _workplace_obstacle(cell: Vector2i) -> bool:
	for sim: VillageSimulation in world_sim.regions.values():
		if sim.workplace_blocked(cell):
			return true
	return false


func _opening_ground_open(cell: Vector2i) -> bool:
	if not world_sim.map_data.terrain_is_walkable(cell) or _workplace_obstacle(cell):
		return false
	for sim: VillageSimulation in world_sim.regions.values():
		if SimWorkplaces.roofed(sim.places, cell):
			return false
	return true


func _player_has_motion_control() -> bool:
	return human_player_active() and world_sim != null and world_sim.actor_controls("player", "motion") and not world_sim.health.owns_actor("player")


func human_player_active() -> bool:
	return avatar_subject == "subject:player"


func bird_player_active() -> bool:
	return avatar_subject.begins_with("subject:avian:")


func soul_player_active() -> bool:
	return avatar_subject.begins_with("subject:soul:")


func soul_avatar_id() -> String:
	return avatar_subject.trim_prefix("subject:soul:") if soul_player_active() else ""


func bird_avatar_id() -> String:
	return avatar_subject.trim_prefix("subject:avian:") if bird_player_active() else ""


func controlled_cell() -> Vector2i:
	if soul_player_active():
		return world_sim.soul_vessels.vessel_cell(str(world_sim.soul_vessels.residents[soul_avatar_id()].vessel))
	var id: String = bird_avatar_id()
	return world_sim.avian_life.body_cell(id) if not id.is_empty() and world_sim.avian_life.birds.has(id) else _home._player.cell


func select_starting_avatar(subject: String) -> bool:
	if not _opening_selection_available or GameClock.elapsed_ms != 0 or world_sim.elapsed_ms != 0 or world_sim.target_ms != 0:
		return false
	if subject != "subject:player":
		if subject.begins_with("subject:soul:"):
			if not world_sim.soul_vessels.agency.activate(subject.trim_prefix("subject:soul:")):
				return false
		elif subject.begins_with("subject:avian:"):
			var id: String = subject.trim_prefix("subject:avian:")
			if not world_sim.avian_life.birds.has(id) or not world_sim.avian_life.birds[id].active.is_empty():
				return false
			world_sim.avian_life.birds[id].autonomous = false
		else:
			return false
		_home.simulation.synchronize_actor("player").autonomous = true
		world_sim.invalidate_region("home")
	avatar_subject = subject
	_player_commands.clear()
	_opening_selection_available = false
	avatar_changed.emit()
	return true


func _local_action_owns(actor_id: String) -> bool:
	return actor_id == "player" and not _home._player.motion.action.is_empty()


func _can_wait() -> bool:
	if conflict_adapter != null and conflict_adapter.has_visible_danger():
		return false
	if soul_player_active():
		return true
	if bird_player_active():
		return world_sim.avian_life.birds[bird_avatar_id()].active.get("purpose") != "explore" and Input.get_vector("move_left", "move_right", "move_up", "move_down").is_zero_approx()
	var player: PlayerCharacter = _home._player
	var intent: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return not world_sim.owns_for_scope("player", &"wait") and player.motion.action.is_empty() and player.motion.velocity.is_zero_approx() and player._intent.is_zero_approx() and intent.is_zero_approx()


func _practice_contact_allowed(from: Vector2, to: Vector2) -> bool:
	var from_cell: Vector2i = TileGrid.world_to_cell(from)
	var to_cell: Vector2i = TileGrid.world_to_cell(to)
	if _home._player.altitude != 0 or _home._world.get_elevation(from_cell) != _home._world.get_elevation(to_cell):
		return false
	var length: float = from.distance_to(to)
	var count: int = maxi(1, ceili(length / float(_home._player.motion.rules.motion.sweep_px)))
	var previous: Vector2i = from_cell
	for index: int in range(1, count + 1):
		var current: Vector2i = TileGrid.world_to_cell(from.lerp(to, float(index) / count))
		if current != previous and not _can_step(previous, current - previous):
			return false
		previous = current
	return true


func _can_step(from_cell: Vector2i, direction: Vector2i) -> bool:
	return _home._world.can_step(from_cell, direction)


func _find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	return VillageRuntime.find_grid_path(_home._world, from_cell, to_cell,
		int(settings.runtime.layout_radius), int(settings.runtime.layout_budget))


## Callback work allowance, independent of game rules or saved world time.
var settlement_work_budget: int = 4096
var _advance_view_baseline: Dictionary = {}


func _capture_advance_view_state() -> Dictionary:
	var labor: String = world_sim.budgeted_labor.latest_for("player")
	return {"artifact_events": world_sim.artifacts.events.size(), "artifact_users": world_sim.artifacts.active.size(),
		"object_busy": world_sim.object_lifecycle.owns_actor("player"),
		"soul_events": world_sim.soul_vessels.events.size(), "soul_users": world_sim.soul_vessels.active.size(),
		"admission_entries": world_sim.admissions.entries.size(), "admission_users": world_sim.admissions.active.size(),
		"record_events": world_sim.method_records.events.size(), "record_users": world_sim.method_records.active.size(),
		"production_phase": str(world_sim.personal_production.active.get("player", {}).get("phase", "")),
		"labor_id": labor, "labor_status": str(world_sim.budgeted_labor.contracts[labor].status) if not labor.is_empty() else ""}


func advance_to_ms(target_ms: int) -> int:
	if world_sim == null:
		return GameClock.elapsed_ms
	if world_sim.settlement.has_failed():
		_report_settlement_failure()
		return GameClock.elapsed_ms
	if avatar_adapter != null and not world_sim.has_pending_boundary():
		avatar_adapter.prepare_step()
	# Earlier continuations may have changed a domain before the public clock
	# can advance. Compare against the first observation until views commit.
	if _advance_view_baseline.is_empty():
		_advance_view_baseline = _capture_advance_view_state()
	var cursor: int = world_sim.settled_ms()
	var work_left: int = maxi(1, settlement_work_budget)
	while cursor < target_ms or world_sim.has_pending_boundary():
		if work_left <= 0 or GameClock.frame_budget_exhausted():
			if world_sim.has_pending_boundary():
				return GameClock.elapsed_ms
			break
		var resuming: bool = world_sim.has_pending_boundary()
		var end: int = world_sim.pending_boundary_ms() if resuming else world_sim.next_runtime_boundary_ms(target_ms)
		if not world_sim.environment_fields.can_settle_at_ms(end):
			world_sim.target_ms = maxi(world_sim.target_ms, target_ms)
			GameClock.set_paused(true)
			_notice = "环境结算达到数值边界；待处理时间已保留。"
			_refresh_panel()
			return GameClock.elapsed_ms if resuming else world_sim.settled_ms()
		if not resuming and not player_journey.is_empty():
			if not _player_has_motion_control():
				cancel_travel()
				continue
			end = mini(end, int(player_journey.due_ms))
			end = mini(end, SimRouteTravel.crossing_ms(player_journey, _home.simulation.synchronize_actor("player"), world_sim.elapsed_ms))
			var body_cell: Vector2i = _cell(_home.simulation.synchronize_actor("player").cell)
			if not player_journey.path.is_empty() and not _can_step(body_cell, _cell(player_journey.path[0]) - body_cell):
				if not SimRouteTravel.repair(_home.simulation, "player", player_journey, world_sim.elapsed_ms):
					cancel_travel()
					_notice = "道路已改变，暂时无法到达目的地。"
				continue
		var old_errors: int = world_sim.errors.size()
		var completed: bool = world_sim.advance_to_ms(end, int(settings.event_budget), work_left, GameClock.frame_budget_exhausted, GameClock.frame_budget_has_room)
		work_left -= world_sim.settlement_work
		cursor = world_sim.settled_ms()
		if world_sim.has_pending_boundary():
			if world_sim.settlement.has_failed():
				_report_settlement_failure()
				return GameClock.elapsed_ms
			if world_sim.errors.size() > old_errors:
				GameClock.set_paused(true)
			_notice = "世界事务待处理，未完成时间已保留。"
			if _panel != null:
				_panel.update_notice(_notice)
			# No notification may publish a partially completed boundary, even
			# if this invocation completed earlier boundaries before yielding.
			return GameClock.elapsed_ms
		# A blow at the final boundary can impose a new reaction lock after the
		# body's last displacement. Commit its speed constraint at this same
		# boundary, so a genuine immediate save is already a valid candidate.
		var walking: Dictionary = world_sim.conflicts.walking_projection("player")
		_home._player.motion.limit_walking_speed(float(walking.speed_fraction) if bool(walking.allowed) else 0.0)
		if _home._player.motion.velocity.is_zero_approx() and _home._player.motion.action.is_empty():
			_home._player.manual_visual_moving = false
		_advance_player_travel()
		if not completed:
			# Exhausting an event budget is normal pending work. The clock keeps
			# the request and retries on a later frame without publishing its end.
			if world_sim.errors.size() > old_errors:
				GameClock.set_paused(true)
			_notice = "世界事务待处理，未完成时间已保留。"
			_refresh_panel()
			break
	return cursor


func _refresh_advance_views() -> void:
	if _advance_view_baseline.is_empty():
		return
	var prior: Dictionary = _advance_view_baseline
	_home._player._project_motion()
	if clothing_adapter != null:
		clothing_adapter.refresh()
	if spirit_adapter != null:
		spirit_adapter.refresh()
	if interaction_adapter != null:
		interaction_adapter.refresh_progress()
	if field_adapter != null:
		field_adapter.refresh()
	if construction_adapter != null:
		construction_adapter.refresh()
		construction_adapter.redraw_committed_canvas()
	_update_region()
	if object_adapter != null and (object_adapter.panel.visible or prior.object_busy != world_sim.object_lifecycle.owns_actor("player")):
		object_adapter.refresh()
	if soul_adapter != null:
		if soul_adapter.panel.visible:
			soul_adapter.refresh()
		else:
			soul_adapter.redraw_committed_canvas()
	if prior.artifact_events != world_sim.artifacts.events.size() or prior.artifact_users != world_sim.artifacts.active.size() or prior.soul_events != world_sim.soul_vessels.events.size() or prior.soul_users != world_sim.soul_vessels.active.size():
		# A completed fractional-minute experiment need not coincide with a
		# native-life event or minute notification. Refresh its shared activity.
		_refresh_panel()
	if prior.admission_entries != world_sim.admissions.entries.size() or prior.admission_users != world_sim.admissions.active.size():
		_refresh_panel()
	if prior.record_events != world_sim.method_records.events.size() or prior.record_users != world_sim.method_records.active.size():
		_refresh_panel()
		heat_method_adapter.refresh_choices()
	if prior.production_phase != str(world_sim.personal_production.active.get("player", {}).get("phase", "")):
		# Arrival/completion can fall between minute notifications. The body
		# and batch already changed, so collection must become available now.
		_refresh_panel()
	if not str(prior.labor_id).is_empty() and prior.labor_status != str(world_sim.budgeted_labor.contracts[prior.labor_id].status):
		_refresh_panel()
	_advance_view_baseline = {}


func project_player_journey(to_ms: int) -> void:
	# Called by the original regional motion executor only after preflight, at
	# each accepted sub-boundary. Never project the whole requested interval
	# before a limited event budget has actually reached it.
	if not player_journey.is_empty():
		_home.simulation.project_actor_route("player", player_journey, to_ms)


func travel_to(region_id: String, destination_cell: Variant = null) -> bool:
	if not human_player_active() or not _player_command_ready():
		return false
	if world_sim.object_lifecycle.owns_actor("player"):
		_notice = "先完成或停止手中的实物取放，再安排远行。"
		_refresh_panel()
		return false
	if world_sim != null and world_sim.private_exchange.owns_actor("player"):
		_notice = "先完成或停止当面交割，再安排远行。"
		_refresh_panel()
		return false
	if world_sim != null and world_sim.capability_practice.owns_actor("player"):
		_notice = "先完成或中止行气练习，再安排远行；WASD可直接中断练习。"
		_refresh_panel()
		return false
	if world_sim != null and world_sim.conflicts.owns_actor("player"):
		_notice = "先退让或结束交锋，再安排长途行旅；也可以自行走位离开。"
		return false
	if world_sim != null and world_sim.spirit_sources.owns_actor("player"):
		_notice = "先完成或停止引息，再动身。"
		_refresh_panel()
		return false
	if world_sim != null and world_sim.health.owns_actor("player"):
		_notice = "先完成或停止当面的诊治，再动身。"
		_refresh_panel()
		return false
	if world_sim != null and world_sim.clothing.owns_actor("player"):
		return false
	if world_sim != null and world_sim.method_records.owns_actor("player"):
		return false
	if world_sim != null and world_sim.personal_production.owns_actor("player"):
		return false
	if world_sim != null and world_sim.construction.owns_actor("player"):
		return false
	if world_sim != null and world_sim.resting.owns_actor("player"):
		return false
	if world_sim != null and world_sim.admissions.owns_actor("player"):
		return false
	if world_sim != null and world_sim.sparring.owns_actor("player"):
		return false
	if _local_action_owns("player"):
		return false
	var site: Dictionary = {}
	if region_id.begins_with("site:"):
		# A site route is a remembered destination, never a third village or
		# an arbitrary coordinate override supplied by the caller.
		if destination_cell != null:
			return false
		site = world_sim.field_opportunities.destination("player", region_id.trim_prefix("site:"))
		if site.is_empty():
			_notice = "本人还没有听到或亲自看清这处去路。"
			_refresh_panel()
			return false
	elif not centers.has(region_id):
		return false
	if not _player_has_motion_control():
		_notice = "眼下无法支配身体行走。"
		_refresh_panel()
		return false
	if world_sim.artifacts.owns_actor("player"):
		_notice = "先完成或停止手中的器物操作。"
		_refresh_panel()
		return false
	if world_sim.services != null and world_sim.services.owns_actor("player"):
		_notice = "先完成或停止正在办理的事务。"
		_refresh_panel()
		return false
	var target: Vector2i = _cell(site.cell) if not site.is_empty() else destination_cell if destination_cell is Vector2i else centers[region_id]
	var path: Array[Vector2i] = _find_path(_home._player.cell, target)
	if path.is_empty():
		_notice = "暂时没有可走的路。"
		_refresh_panel()
		return false
	prepare_home_command()
	_home.simulation.cancel_action("player", "travel_order")
	world_sim.invalidate_region("home", "player")
	var encoded: Array = []
	for cell: Vector2i in path:
		if cell != _home._player.cell:
			encoded.append([cell.x, cell.y])
	if not _home.simulation.actor_position(_home.simulation.synchronize_actor("player")).is_equal_approx(TileGrid.cell_to_world(_home._player.cell)):
		encoded.push_front([_home._player.cell.x, _home._player.cell.y])
	player_journey = {"destination": region_id, "path": encoded, "due_ms": world_sim.elapsed_ms + 1, "segment_started_ms": world_sim.elapsed_ms, "segment_from": _home.simulation.synchronize_actor("player").position.duplicate()}
	SimRouteTravel.begin_segment(player_journey, _home.simulation.synchronize_actor("player"), world_sim.elapsed_ms, float(_home._player.motion.rules.motion.speed))
	if destination_cell is Vector2i:
		player_journey["target"] = [target.x, target.y]
	_notice = "正在前往%s，WASD 可中断。" % _journey_label(region_id)
	_refresh_panel()
	return true


func travel_to_site(id: String) -> bool:
	return not id.is_empty() and travel_to("site:" + id)


func _journey_label(destination: String) -> String:
	if destination.begins_with("site:"):
		var known: Dictionary = world_sim.field_opportunities.destination("player", destination.trim_prefix("site:"))
		return str(known.get("label", "所记的野外去处"))
	return str(settings.regions.get(destination, {}).get("label", "原先的去处"))


func cancel_travel() -> void:
	if world_sim != null and not world_sim.accepts_commands():
		return
	if not player_journey.is_empty():
		player_journey = {}
		_notice = "行程已中断，世界仍继续运转。"
	if service_adapter != null:
		service_adapter.cancel_manual()
	if world_sim != null:
		# Manual walking/evasion is part of the original phase-aware bout.
		# Explicit stop and hostile contact still end it through their own entry.
		world_sim.interrupt_occupation("player", "manual_override", true)
		if world_sim.conflicts.conflict_for("player").is_empty():
			world_sim.conflicts.cancel("player")


func prepare_home_command(actor_id: String = "") -> void:
	if world_sim != null:
		world_sim.synchronize_region("home", actor_id)


func prepare_player_command() -> void:
	prepare_home_command("player")
	_home._sync_player_cell()


func _player_command_context() -> String:
	return str(world_sim.get_instance_id()) + ":" + avatar_subject if world_sim != null else ""


func _player_command_ready() -> bool:
	return world_sim != null and not GameClock.has_pending_advance() \
		and world_sim.accepts_commands() and not world_sim.has_pending_boundary() \
		and not world_sim.settlement.has_failed() and world_sim.elapsed_ms == GameClock.elapsed_ms \
		and world_sim.target_ms == world_sim.elapsed_ms and (_saves == null or not _saves.pending())


func request_player_command(kind: String, args: Dictionary = {}) -> Dictionary:
	# `queued` means only that the host remembers the intent. Resources and
	# targets are checked by the original action entry when a boundary is ready.
	if world_sim == null or world_sim.settlement.has_failed() or _opening_selection_available or not ReolPlayerCommandBuffer.LIFETIME_MS.has(kind):
		return {"ok": false, "queued": false, "line": "眼下无法受理这个操作。"}
	if kind == "travel" and (not args.get("region") is String or not (args.get("cell") == null or args.get("cell") is Vector2i)):
		return {"ok": false, "queued": false, "line": "没有可用的目的地。"}
	if kind == "sidestep":
		var direction: Variant = args.get("direction", Input.get_vector("move_left", "move_right", "move_up", "move_down"))
		if not direction is Vector2 or not direction.is_finite():
			return {"ok": false, "queued": false, "line": "没有可用的闪避方向。"}
		args = {"direction": _home._player.motion.facing if direction.is_zero_approx() else direction}
	GameClock.cancel_wait()
	_player_commands.supersede(kind)
	_drain_player_commands()
	if _player_command_ready():
		return _execute_player_command(kind, args)
	var id: int = _player_commands.enqueue(kind, args, _player_command_context(), Time.get_ticks_msec())
	GameClock.request_input_boundary()
	return {"ok": true, "queued": true, "id": id, "line": "已记下操作，待当前结算完成后尝试。"}


func _execute_player_command(kind: String, args: Dictionary) -> Dictionary:
	var ok: bool = false
	match kind:
		"sidestep": ok = _home._player.request_sidestep(args.direction)
		"travel": ok = travel_to(str(args.region), args.get("cell"))
		"cancel": ok = stop_player_action()
	return {"ok": ok, "queued": false, "line": "操作已执行。" if ok else "眼下的状态无法执行这个操作。"}


func _drain_player_commands() -> void:
	_player_commands.expire(_player_command_context(), Time.get_ticks_msec())
	while _player_commands.pending() and _player_command_ready():
		var item: Dictionary = _player_commands.take()
		_player_commands.complete(item, _execute_player_command(str(item.kind), item.args))


func _on_player_command_finished(id: int, kind: String, result: Dictionary) -> void:
	player_command_finished.emit(id, kind, result)
	if result.get("reason", "") in ["superseded", "context_changed"]:
		return
	_notice = "等待的操作已过期，请重新操作。" if result.get("reason") == "expired" else str(result.get("line", ""))
	if _panel != null:
		_panel.update_notice(_notice)


func _request_travel(region: String) -> void:
	var result: Dictionary = request_player_command("travel", {"region": region})
	if bool(result.queued) or not bool(result.ok):
		_notice = str(result.line)
		_panel.update_notice(_notice)


func stop_player_action(reason: String = "player_cancelled") -> bool:
	# This is an external command, including when called by a synchronous UI
	# observer. Domain-internal interruption keeps its own authorized entry.
	if world_sim == null or not world_sim.accepts_commands() or world_sim.settlement != null and world_sim.has_pending_boundary():
		return false
	if soul_player_active():
		return bool(world_sim.soul_vessels.agency.command(soul_avatar_id(), "cancel").ok)
	if bird_player_active():
		world_sim.avian_life.cancel(bird_avatar_id())
		return true
	if world_sim.sparring.owns_actor("player"):
		world_sim.sparring.stop()
	world_sim.plants.cancel("player")
	world_sim.conflicts.cancel("player")
	world_sim.capability_practice.cancel("player", reason)
	world_sim.private_exchange.cancel("player", reason)
	cancel_travel()
	world_sim.services.cancel("player", reason)
	_home.simulation.cancel_action("player", reason)
	world_sim.invalidate_region("home")
	_refresh_panel()
	if interaction_adapter != null:
		interaction_adapter.refresh_progress()
	return true


func hold_player_motion(preserve_position: bool = false) -> void:
	if preserve_position:
		# A process may be bound to an exact continuous position. Stopping it
		# must not silently snap the original body to the centre of its cell.
		_home._player.motion.cancel("holding_position")
		_home._player.manual_visual_moving = false
		_home._player._project_motion()
	else:
		_home._player.spawn_at(_home._player.cell)


func player_inventory() -> SimInventory:
	return _home.simulation.inventory


func player_goal() -> String:
	return str(_home.simulation.synchronize_actor("player").goal)


func start_home_work(action_id: String) -> Dictionary:
	if not human_player_active():
		return {"ok": false, "line": "眼下不是人身，无法替那位杂役支配双手。"}
	if (not action_id in ["deliver_wood", "deliver_water", "deliver_grain", "cook", "report", "check_kitchen", "gather_wood", "forage_grain", "draw_water", "gather_herb", "irrigate_herb"] and not _home._content.personal_foraging.actions.has(action_id)) or not _home.simulation.config.actions.has(action_id):
		return {"ok": false, "line": "这项劳作尚未开放。"}
	if current_region != "home" or not player_journey.is_empty():
		return {"ok": false, "line": "这些是山门的杂务，请先回山门。"}
	if world_sim.services.owns_actor("player"):
		return {"ok": false, "line": "先完成或停止正在办理的事务。"}
	prepare_player_command()
	if not _home.simulation.synchronize_actor("player").active.is_empty():
		return {"ok": false, "line": "先完成或停止眼前的劳作。"}
	var terms: Dictionary = _home.simulation.config.actions[action_id]
	if terms.kind == "irrigate":
		var source: Dictionary = _home.simulation.land_resources.sources.get(str(terms.resource), {})
		var plant_id: String = str(source.get("plant_id", ""))
		if not plant_id.is_empty():
			var care: Dictionary = world_sim.plants.jobs.begin("player", plant_id, "water")
			if bool(care.ok):
				hold_player_motion(true)
			return {"ok": bool(care.ok), "line": "已动身照料药丛；用自己的水浇灌，药草仍须慢慢生长。" if bool(care.ok) else "眼下无法照料；请确认有自己可用的水、道路和空闲的双手。"}
	var accepted: bool = _home.simulation.submit_action("player", action_id)
	if accepted:
		world_sim.invalidate_region("home")
		hold_player_motion()
	if _home.simulation.config.actions[action_id].kind == "irrigate":
		return {"ok": accepted, "line": "已动身照料药丛；到场用自己的水浇灌，完成后不记公差贡献。" if accepted else "眼下无法照料；请确认有自己可用的水、道路和空闲的双手。"}
	var personal: bool = _home.simulation.config.actions[action_id].kind == "forage"
	return {"ok": accepted, "line": ("已动身%s；采得实物自留，不记公差贡献。" if personal else "已动身%s；成果另到功德堂登记。") % str(_home.simulation.config.actions[action_id].label) if accepted else "眼下无法接下：请查看物资、道路和自身状况。"}


func talk_to_selected(action: String) -> Dictionary:
	if not human_player_active():
		return {"ok": false, "line": "雀鸣还不能替那位杂役说话。"}
	if current_region != "home" or not action in ["ask", "shortage", "supplied", "claim", "show_pass", "verify", "receipt"]:
		return {"ok": false, "line": "先在山门选中附近同门，再当面交谈。"}
	var selected: String = _home._selected_actor
	if selected == "player" or not _home._is_actor_visible(selected):
		return {"ok": false, "line": "先选中视野内的一位同门。"}
	prepare_player_command()
	var sim: VillageSimulation = _home.simulation
	var result: Dictionary
	if action in ["claim", "show_pass", "verify", "receipt"]:
		result = world_sim.admissions.start("player", selected, action)
		if bool(result.ok):
			hold_player_motion()
	elif action == "ask":
		result = sim.ask_stock("player", selected, "kitchen", "wood")
	else:
		var amount: int = 0 if action == "shortage" else int(sim.config.actions.deliver_wood.stock_below)
		result = sim.tell_stock("player", selected, "kitchen", "wood", amount)
	if bool(result.get("ok", false)):
		world_sim.invalidate_region("home")
	return result


func known_kitchen_line() -> String:
	var belief: Dictionary = _home.simulation.stock_understanding("player", "kitchen", "wood")
	if not bool(belief.known):
		return "山门柴火：尚无新近见闻，可询问或亲自查看。"
	var enough: bool = int(belief.amount) >= int(_home.simulation.config.actions.deliver_wood.stock_below)
	var supply: String = "余柴充足" if enough else "余柴不多"
	var source: String = "你亲眼见过" if belief.basis == "observed" else "%s说" % _home.simulation._name(str(belief.source))
	return "山门柴火：%s%s%s" % [source, supply, "，旧闻有出入。" if bool(belief.conflicted) else "。"]


func request_selected_help() -> Dictionary:
	if not human_player_active():
		return {"ok": false, "line": "先用这副身体能表达的办法交流。"}
	return _home.request_selected_help()


func selected_interaction() -> Dictionary:
	if current_region == "river":
		return {"enabled": false, "line": "互助可到仓库找陆行舟"}
	return _home.selected_interaction()


func clear_remote_selection() -> void:
	if _remote_views.has(_selected_remote):
		_remote_views[_selected_remote].set_selected(false)
	_selected_remote = ""


func hide_legacy_controls() -> void:
	_home._panel.visible = false


func _advance_player_travel() -> void:
	if player_journey.is_empty():
		return
	if not _player_has_motion_control():
		cancel_travel()
		_notice = "无法继续行走，停在当前位置。"
		return
	if world_sim.elapsed_ms < int(player_journey.due_ms):
		return
	var path: Array = player_journey.path
	if not path.is_empty():
		_home.simulation.set_actor_cell("player", _cell(path.pop_front()))
	world_sim.invalidate_region("home", "player")
	if path.is_empty():
		_notice = "已到达%s。" % _journey_label(str(player_journey.destination))
		player_journey = {}
		_refresh_panel()
	else:
		SimRouteTravel.begin_segment(player_journey, _home.simulation.synchronize_actor("player"), world_sim.elapsed_ms, float(_home._player.motion.rules.motion.speed))


func _update_region() -> void:
	var focus: Vector2i = controlled_cell()
	var nearest: String = ""
	var distance: float = float(settings.runtime.enter_radius)
	for id: String in centers:
		var candidate: float = focus.distance_to(centers[id])
		if candidate < distance:
			distance = candidate
			nearest = id
	if not current_region.is_empty() and focus.distance_to(centers[current_region]) < float(settings.runtime.exit_radius):
		if nearest.is_empty():
			nearest = current_region
	if nearest == current_region:
		return
	if not world_sim.set_active_region(nearest):
		return
	current_region = nearest
	_refresh_views(true)
	region_changed.emit(nearest)


func _on_player_moved() -> void:
	# Entering a settlement and nearby interaction affordances must not wait
	# for a minute-product boundary after continuous movement.
	if world_sim == null or world_sim.elapsed_ms != world_sim.target_ms:
		return
	_update_region()
	_refresh_panel()
	_home.redraw_committed_canvas()
	redraw_committed_canvas()


func _on_advanced() -> void:
	_update_region()
	if not GameClock.is_advancing():
		_refresh_views(false)
	_refresh_panel()
	redraw_committed_canvas()


func _refresh_views(snap: bool, layout: PawnViewLayout = null, poses: HumanoidPose.WorldFrame = null) -> void:
	if not _presentation_ready():
		return
	# A body keeps its original ledger owner while travelling. Only actual
	# visibility decides whether its nonhome scene projection is materialized.
	var visible_bodies: Dictionary = {}
	if layout == null:
		layout = actor_view_layout()
	if poses == null:
		poses = HumanoidPose.WorldFrame.new(world_sim, world_sim.elapsed_ms)
	var reuse_native_leg: bool = poses.at_ms == GameClock.elapsed_ms
	for region: String in world_sim.regions:
		if region == "home":
			continue
		var remote: VillageSimulation = world_sim.regions[region]
		var residents: Dictionary = remote.actors
		for id: String in residents:
			var actor: Dictionary = residents[id]
			if not bool(actor.alive):
				continue
			var cell: Vector2i = layout.cells[id] if layout.cells.has(id) else _cell(actor.cell)
			if _home._fog == null and cell.distance_to(controlled_cell()) > float(_home.simulation.config.observation_radius):
				continue
			if not layout.sees(cell):
				continue
			# Visibility does not materialize or advance the original body.
			visible_bodies[id] = true
			if not _remote_views.has(id):
				var created_pawn := Pawn.new()
				created_pawn.name = "Visitor_" + id
				created_pawn.setup(_home._content.get_pawn(StringName(actor.definition_id)), _home._content, _home._world, cell)
				created_pawn.pawn_id = StringName(id)
				created_pawn.display_name_override = str(settings.runtime.remote_names.get(id, remote._name(id)))
				add_child(created_pawn)
				_remote_views[id] = created_pawn
			var pawn: Pawn = _remote_views[id]
			var leg: int = int(layout.native_legs.get(id, -1)) if reuse_native_leg else -1
			pawn.appearance_pose = HumanoidPose.stabilized(poses.pose(remote, id, actor, leg), pawn.appearance_pose)
			pawn.clothing_appearance = world_sim.clothing.appearance(id)
			pawn.set_view_layout(layout.offsets.get(id, Vector2.ZERO))
			pawn.cell = cell
			if pawn.selected:
				_home._sync_needs(pawn.state, remote.projected_actor_needs(id))
			pawn.project_position(layout.points[id] if layout.points.has(id) else remote.projected_actor_position(id))
			if not GameClock.is_advancing():
				pawn.publish_motion(GameClock.elapsed_ms, snap)
			pawn.show()
			pawn.refresh_appearance()
	for id: String in _remote_views.keys():
		if visible_bodies.has(id):
			continue
		if _selected_remote == id:
			clear_remote_selection()
		_remote_views[id].hide()
		_remote_views[id].queue_free()
		_remote_views.erase(id)
	_update_courier_view()


func _process(_delta: float) -> void:
	if _field_compute != null:
		_field_compute.maintain()
	for index: int in range(_retired_field_compute.size() - 1, -1, -1):
		var service: EnvironmentFieldComputeRuntime = _retired_field_compute[index]
		service.maintain()
		if not bool(service.diagnostics().busy):
			service.close()
			_retired_field_compute.remove_at(index)
	if _saves != null:
		_saves.process_save()
	_drain_player_commands()


func _unhandled_input(event: InputEvent) -> void:
	if not human_player_active() or not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
		return
	var point: Vector2 = get_canvas_transform().affine_inverse() * mouse.position
	if select_remote_at(point):
		get_viewport().set_input_as_handled()


func select_remote_at(point: Vector2) -> bool:
	if not human_player_active():
		return false
	var nearest: Pawn
	var distance: float = 36.0
	for id: String in _remote_views:
		var pawn: Pawn = _remote_views[id]
		var candidate: float = pawn.selection_center().distance_to(point)
		if pawn.visible and candidate < distance:
			distance = candidate
			nearest = pawn
	if nearest == null:
		return false
	if _home._player.selection_center().distance_to(point) < distance:
		return false
	for pawn: Pawn in _home._pawns.values():
		if pawn.visible and pawn.selection_center().distance_to(point) < distance:
			return false
	clear_remote_selection()
	_selected_remote = String(nearest.pawn_id)
	nearest.set_selected(true)
	resident_selected.emit(nearest)
	_refresh_panel()
	return true


func _update_courier_view() -> void:
	_courier_visible = false
	# Actual courier position is interpolated along a validated terrain route;
	# cargo ownership and progress come exclusively from the world simulation.
	for id: String in world_sim.couriers:
		var position_value: Vector2 = world_sim.courier_cell(id)
		_courier_cell = Vector2i(roundi(position_value.x), roundi(position_value.y))
		_courier_visible = _home._fog.is_cell_visible(_courier_cell) if _home._fog != null else true
		break


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	_panel = WorldContinuityPanel.new()
	screen.add_child(_panel)
	_panel.travel_requested.connect(_request_travel)
	_panel.route_toggle_requested.connect(_toggle_route)
	_panel.save_requested.connect(_home.request_save)
	_panel.load_requested.connect(_home.load_game)
	service_adapter = SettlementServicesRuntime.new()
	service_adapter.setup(self, screen)


func submit_service(action_id: String) -> Dictionary:
	return service_adapter.submit(action_id)


func _toggle_route() -> void:
	var blocked: bool = bool(world_sim.routes.river_road.blocked)
	world_sim.set_route_blocked("river_road", not blocked)
	_notice = "测试：道路已恢复，行程继续。" if blocked else "测试：道路中断，运输将停在途中。"
	_refresh_views(true)
	_refresh_panel()


func _report_settlement_failure() -> void:
	GameClock.set_paused(true)
	_notice = "世界结算失败，已停止推进；可读取已有近况恢复。原因：" + world_sim.settlement.error
	if _panel != null:
		_panel.update_notice(_notice)


func _presentation_ready() -> bool:
	return world_sim != null and not world_sim.has_pending_boundary()


func _refresh_panel() -> void:
	if _panel == null or world_sim == null:
		return
	if world_sim.has_pending_boundary():
		_panel.update_notice(_notice)
		return
	var here: String = str(settings.regions.get(current_region, {}).get("label", "山野"))
	if current_region.is_empty() and human_player_active():
		for site: Dictionary in world_sim.field_opportunities.nearby_visible_sites("player"):
			if _home._fog == null or _home._fog.is_cell_visible(_cell(site.cell)):
				here = "山野 · " + str(site.label)
				break
	hide_legacy_controls()
	if current_region == "river":
		here += " · 点击居民查看活动"
	var lines: Array[String] = []
	if not _selected_remote.is_empty():
		var selected: Pawn = _remote_views.get(_selected_remote)
		if not is_instance_valid(selected) or not selected.visible:
			_selected_remote = ""
	if not current_region.is_empty():
		var sim: VillageSimulation = world_sim.regions[current_region]
		lines.append("来信只反映寄出时的情形；近况还需当面打听。")
		for line: String in world_sim.known_event_lines(current_region, 3):
			if human_player_active() and not _known_lines.has(line):
				_known_lines.append(line)
		lines.append("人物各自生活；点击眼前的人查看活动。" if current_region == "river" else "宗门的工作和往来照常继续。")
	if not _selected_remote.is_empty():
		var region_id: String = actor_region(_selected_remote)
		if not region_id.is_empty():
			lines.append("%s：%s" % [str(settings.runtime.remote_names.get(_selected_remote, world_sim.regions[region_id]._name(_selected_remote))), visible_actor_status(_selected_remote)])
	for line: String in _known_lines.slice(maxi(0, _known_lines.size() - 3)):
		lines.append(line)
	_panel.update_view(here, "\n".join(lines), _notice)
	if service_adapter != null:
		service_adapter.refresh()
	if object_adapter != null:
		object_adapter.refresh()
	if spirit_adapter != null:
		spirit_adapter.refresh()
	if soul_adapter != null:
		soul_adapter.refresh()


func _save_service() -> SimSaveSession:
	if _saves == null:
		_saves = SimSaveSession.new()
		_saves.configure(_capture_session, _stage_session, _adopt_session,
			_save_ready, GameClock, _save_failed)
		_saves.save_finished.connect(_on_save_finished)
	return _saves


func _save_ready() -> bool:
	return world_sim != null and not GameClock.has_pending_advance() and GameClock.elapsed_ms == world_sim.elapsed_ms and world_sim.target_ms == world_sim.elapsed_ms and not world_sim.has_pending_boundary() and not world_sim.settlement.has_failed()


func _save_failed() -> bool:
	return world_sim == null or world_sim.settlement.has_failed()


func _capture_session() -> Dictionary:
	_home._sync_player_cell()
	return WorldSessionSnapshot.capture(self)


func _stage_session(snapshot: Dictionary) -> Dictionary:
	var rejection: String = SessionSaveSchema.rejection_reason(snapshot.get("schema_version"))
	if not rejection.is_empty():
		return {"rejection": rejection}
	return WorldSessionSnapshot.stage(self, snapshot)


func save_game(path: String) -> Error:
	# Strict synchronous API for tools/callers already at a complete boundary.
	if world_sim == null:
		return ERR_UNCONFIGURED
	var result: Error = _save_service().save_now(path)
	_show_save_result(result)
	return result


func request_save(path: String) -> Error:
	if world_sim == null:
		return ERR_UNCONFIGURED
	var result: Error = _save_service().request_save(path)
	_notice = "正在完成当前结算，随后保存……" if result == OK else "未能受理保存：" + error_string(result)
	_refresh_panel()
	return result


func _on_save_finished(path: String, result: Error) -> void:
	_show_save_result(result)
	save_finished.emit(path, result)


func _show_save_result(result: Error) -> void:
	if result == OK:
		_notice = "两地近况和在途事务已记下。"
	elif result == ERR_BUSY:
		_notice = "世界事务尚未完成，暂不能保存；已有存档保持原样。"
	else:
		_notice = "保存失败：%s" % error_string(result)
	_refresh_panel()


func _exit_tree() -> void:
	if _field_compute != null:
		_field_compute.shutdown()
	for service: EnvironmentFieldComputeRuntime in _retired_field_compute:
		service.shutdown()
	_retired_field_compute.clear()
	if world_sim != null:
		world_sim.close_actor_execution()
	if _saves != null:
		_saves.save_finished.disconnect(_on_save_finished)
		_saves.cancel_save()


func load_game(path: String) -> Error:
	var result: Error = _save_service().load_now(path)
	if result == OK:
		_notice = "两地已接续到保存时刻，途中事务保持原样。"
	elif result == ERR_BUSY:
		_notice = "当前事务仍在处理，暂不能读取。"
	elif _saves.reason == SessionSaveSchema.REJECTION_LEGACY_BUILDINGS:
		_notice = "这份存档采用旧建筑模型；当前版本需要新建世界，原档未改动。"
	elif _saves.reason == SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT:
		_notice = "旧环境格式不再支持，存档未改；请新开局。"
	elif _saves.reason == SessionSaveSchema.REJECTION_LEGACY_ACTIONS:
		_notice = "旧行动格式不再支持，存档未改；请新开局。"
	elif _saves.reason == SessionSaveSchema.REJECTION_LEGACY_EVENTS:
		_notice = "这份旧档没有完整事件、植物与会话规则；请新开局，原档未改动。"
	elif _saves.reason == "unreadable":
		_notice = "没有读到可用近况，请先保存一次。"
	else:
		_notice = "近况里的时间、行动或账目不适用于当前世界。"
	_refresh_panel()
	return result


func _adopt_session(staged: Dictionary) -> void:
	var snapshot: Dictionary = staged.snapshot
	var extra: Dictionary = snapshot.continuity
	# All validation is complete before changing any live world or clock state.
	var previous_world: RegionalSimulation = world_sim
	_player_commands.clear()
	_retire_field_compute()
	world_sim = staged.world
	_configure_field_compute()
	_advance_view_baseline = {}
	_home._clock_interval_had_events = false
	previous_world.close_actor_execution()
	previous_world.retire_space()
	previous_world.plants.retire_bindings()
	_home.adopt_content(staged.content)
	settings = world_sim.settings.duplicate(true)
	centers = {}
	for id: String in snapshot.assembly.centers:
		centers[id] = _cell(snapshot.assembly.centers[id])
	_home._config = world_sim.regions.home.config.duplicate(true)
	avatar_subject = str(snapshot.avatar_subject)
	_opening_selection_available = false
	_bind_navigation()
	_home.reconcile_actor_views()
	service_adapter.reset_observation()
	player_journey = extra.player_journey.duplicate(true)
	_known_lines.assign(extra.known_lines)
	current_region = world_sim.active_region
	_selected_remote = ""
	# Drop all views on load: their body/state references belonged to the previous
	# snapshot. New ones unfold from the validated replacement, without reseeding.
	for pawn: Pawn in _remote_views.values():
		pawn.queue_free()
	_remote_views.clear()
	GameClock.restore_state(snapshot.clock)
	_home._player.spawn_at(_cell(snapshot.player.cell))
	_home._player.restore_motion(snapshot.player.motion, Vector2(float(snapshot.player.position[0]), float(snapshot.player.position[1])), int(snapshot.clock.elapsed_ms))
	_home._player.set_altitude(int(snapshot.player.altitude))
	_home._world.set_focus(controlled_cell())
	if _home._fog != null:
		if human_player_active():
			_home._fog.set_observer(0, FogOfWar.VISION_RADIUS)
		elif soul_player_active():
			_home._fog.set_observer(0, int(world_sim.soul_vessels.definitions.agency.sense_cells))
		else:
			_home._fog.set_observer(int(world_sim.avian_life.birds[bird_avatar_id()].altitude), int(world_sim.avian_life.rules().observation_cells))
		_home._fog.restore_exploration(snapshot.world.exploration, controlled_cell())
	player_travel_advanced.emit(_home._player.global_position)
	_home._sync_actor_views(true)
	_refresh_views(true)
	if sparring_adapter != null:
		sparring_adapter.reset_observation()
	redraw_committed_canvas()
	avatar_changed.emit()
	if interaction_adapter != null:
		interaction_adapter.receive_current_care_alerts()
	_home.content_replaced.emit(_home._content)
	_capture_committed_canvases()


func known_lines() -> Array[String]:
	return _known_lines.duplicate()


func runtime() -> Node:
	return self


func _build_canvas() -> void:
	if world_sim == null:
		return
	var sim: VillageSimulation = world_sim.regions.river
	var font: Font = ThemeDB.fallback_font
	for id: String in sim.places:
		var place: Dictionary = sim.places[id]
		var cell: Vector2i = _cell(place.cell)
		var workspace: Dictionary = place.get("workspace", {}).duplicate(true)
		if workspace.is_empty() and _home._fog != null and not _home._fog.is_explored(cell):
			continue
		var point: Vector2 = TileGrid.cell_to_world(cell)
		point.y -= float(_home._world.get_elevation(cell) * ReolWorld.ELEVATION_PX)
		capture_custom(Callable(FacilityVisuals, "draw_facility").bind(self, id, point, "河湾·" + str(place.label), Color("#81b4a4"), _home.herb_phase_for(sim, id), workspace, _home._place_is_explored))
	if _courier_visible:
		var point: Vector2 = TileGrid.cell_to_world(_courier_cell)
		point.y -= float(_home._world.get_elevation(_courier_cell) * ReolWorld.ELEVATION_PX)
		capture_circle(point + Vector2(0, -12), 10, Color("#e2a44c"))
		capture_text_outline(font, point + Vector2(-64, -32), "陆行舟·运粮", HORIZONTAL_ALIGNMENT_CENTER, 128, 14, 4, Color("#0b0f12"))
		capture_text(font, point + Vector2(-64, -32), "陆行舟·运粮", HORIZONTAL_ALIGNMENT_CENTER, 128, 14, Color("#f6deae"))


static func _cell(raw: Array) -> Vector2i:
	return Vector2i(int(raw[0]), int(raw[1]))
