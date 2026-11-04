class_name VillageRuntime
extends Node2D
## Connects the fixed-tick simulation to world navigation, actors, and UI.
## _process only interpolates NPC visuals; rules advance on GameClock.tick.

signal simulation_advanced
signal body_state_changed
signal content_replaced(content: ReolContentDB)

const CONFIG_PATH: String = "res://data/scenarios/village.json"
const SAVE_PATH: String = "user://village_save.json"
const SAVE_VERSION: int = SessionSaveSchema.VERSION
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var simulation: VillageSimulation
var continuity: Node

var _world: ReolWorld
var _player: PlayerCharacter
var _fog: FogOfWar
var _pawns: Dictionary[String, Pawn] = {}
var _content: ReolContentDB
var _config: Dictionary = {}
var _places: Dictionary = {}
var _selected_actor: String = "player"
var _panel: VillagePanel
var _notice: String = "选中同门可以开口求助；WASD 可中断自己的行动。"
var _visual_starts: Dictionary[String, Vector2] = {}
var _visual_targets: Dictionary[String, Vector2] = {}
var _visual_progress: float = 1.0
var _shared_motion_world: WeakRef


func setup(
	world: ReolWorld,
	player: PlayerCharacter,
	pawns: Array[Pawn],
	content: ReolContentDB,
	initial_workplaces: bool = false
) -> bool:
	if world == null or player == null or content == null or simulation != null:
		return false
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 7
	_world = world
	_player = player
	_content = content
	if not _world.map_data().configure_nature(content.natural_environment):
		return false
	if get_parent() != null:
		_fog = get_parent().get_node_or_null("Fog") as FogOfWar
	if _fog != null and not _fog.visibility_updated.is_connected(queue_redraw):
		_fog.visibility_updated.connect(queue_redraw)
	for pawn: Pawn in pawns:
		_pawns[String(pawn.pawn_id)] = pawn
	if not _load_config():
		return false
	if not _ensure_initial_reachability():
		return false
	_places = _layout_places(_actor_cells())
	if _places.is_empty():
		push_error("VillageRuntime: facilities could not be placed on reachable cells")
		return false
	if initial_workplaces:
		if not _assemble_workplace():
			push_error("VillageRuntime: no accessible footprint for the opening office")
			return false
		_world.set_obstacle_provider(_workspace_obstacle)
		_config = _snapshot_json_value(_config)
		_places = _snapshot_json_value(_places)
	var next_simulation := VillageSimulation.new()
	if not next_simulation.initialize(_content, _config, _actor_cells(), _places, GameClock.elapsed_ms):
		push_error("VillageRuntime: simulation initialization failed: %s" % str(next_simulation.errors))
		return false
	simulation = next_simulation
	simulation.set_navigation(_find_path, _world.can_step)
	_player.bind_locomotion(_world, GameClock, _player_actor, _player_can_act, _automatic_player_motion, _player_walking_projection, _player_can_continue_action)
	if not _player.manual_movement_started.is_connected(cancel_player_action):
		_player.manual_movement_started.connect(cancel_player_action)
	if not _player.cell_changed.is_connected(_sync_player_cell):
		_player.cell_changed.connect(_sync_player_cell)
	_build_panel()
	_sync_actor_views(true)
	GameClock.time_advanced.connect(_on_time_advanced)
	_refresh_panel()
	queue_redraw()
	return true


func _assemble_workplace() -> bool:
	var institution: String = str(_config.institution.id)
	if SimWorkplaces.enable_opening(_config, _places, _actor_cells(), _world.map_data(), institution):
		return true
	var original: Array = _places.records.cell.duplicate()
	var desired: Vector2i = _decode_cell(original)
	var candidates: Array[Vector2i] = _reachable_cells(_player.cell)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - desired).length_squared() < (b - desired).length_squared())
	for cell: Vector2i in candidates:
		var occupied: bool = false
		for id: String in _places:
			if id != "records" and _decode_cell(_places[id].cell) == cell:
				occupied = true
		if occupied or cell.distance_to(desired) > 12.0:
			continue
		_places.records.cell = [cell.x, cell.y]
		if SimWorkplaces.enable_opening(_config, _places, _actor_cells(), _world.map_data(), institution):
			return true
	_places.records.cell = original
	return false


func _workspace_obstacle(cell: Vector2i) -> bool:
	return SimWorkplaces.blocked(_places, cell)


func select_actor(id: String) -> void:
	if simulation == null or not simulation.actors.has(id):
		return
	_selected_actor = id
	_refresh_panel()


func _player_actor() -> Dictionary:
	if is_instance_valid(continuity):
		continuity.prepare_home_command()
	return simulation.actors.player


func _player_can_act() -> bool:
	return _player_can_continue_action() and (not is_instance_valid(continuity) or continuity.world_sim.elapsed_ms == continuity.world_sim.target_ms)


func _player_can_continue_action() -> bool:
	# An already paid sidestep consumes an in-flight interval while target_ms
	# is ahead. Only starting a new command requires the backlog to be empty.
	return simulation.actor_controls("player", "action") and (not is_instance_valid(continuity) or not continuity.world_sim.owns_for_scope("player", &"player_action"))


func _automatic_player_motion() -> bool:
	return not simulation.actors.player.active.is_empty() or (is_instance_valid(continuity) and (not continuity.player_journey.is_empty() or continuity.world_sim.owns_for_scope("player", &"automatic_motion")))


func _player_walking_projection() -> Dictionary:
	if is_instance_valid(continuity):
		return continuity.world_sim.conflicts.walking_projection("player")
	return {"allowed": true, "speed_fraction": 1.0}


func bind_shared_motion(authority: RegionalSimulation) -> void:
	if _shared_motion_world != null:
		var previous: RegionalSimulation = _shared_motion_world.get_ref() as RegionalSimulation
		if previous != null:
			previous.set_manual_motion_executor(Callable())
	_shared_motion_world = weakref(authority) if authority != null else null
	_player.set_shared_motion_executor(authority != null)
	if authority != null:
		authority.set_manual_motion_executor(_advance_player_motion)


func _advance_player_motion(from_ms: int, to_ms: int) -> void:
	# Leave view/cell signals until the existing end-of-world projection; an
	# intermediate body position must not make UI observers reenter settlement.
	_player.advance_motion_interval(from_ms, to_ms, false)


func snapshot_context() -> Dictionary:
	# Explicit references needed by the session boundary. This is not a second
	# copy of authoritative state, and is obtained only for capture or staging.
	return {"content": _content, "player": _player, "fog": _fog}


func adopt_content(content: ReolContentDB) -> void:
	# Called only at the successful session commit boundary. View state keeps its
	# identity (HUD references it) and rebinds definitions in _sync_needs below.
	_content = content


func valid_snapshot(snapshot: Dictionary, candidate_map: WorldMapData = null, opening: Variant = null) -> bool:
	return _valid_snapshot(snapshot, candidate_map, opening)


func matches_snapshot_world(candidate: VillageSimulation, candidate_map: WorldMapData = null, opening: Variant = null) -> bool:
	return _matches_world(candidate, candidate_map, opening)


func cancel_player_action() -> void:
	if is_instance_valid(continuity):
		continuity.prepare_home_command()
		continuity.cancel_travel()
	if simulation != null:
		simulation.cancel_action("player", "manual_override")
		if is_instance_valid(continuity):
			continuity.world_sim.invalidate_region("home")


func save_game(path: String = SAVE_PATH) -> Error:
	if is_instance_valid(continuity):
		return continuity.save_game(path)
	if simulation == null:
		return ERR_UNCONFIGURED
	_sync_player_cell()
	var snapshot: Dictionary = _snapshot_json_value({
		"schema_version": SAVE_VERSION,
		"content_bundle": _content.content_bundle(),
		"assembly": ReolWorldAssemblyInputs.standalone(_config),
		"avatar_subject": "subject:player",
		"world_seed": ReolWorld.WORLD_SEED,
		"world": SessionSaveSchema.capture_world(_fog, _player.cell),
		"simulation": simulation.to_dict(),
		"clock": GameClock.to_dict(),
		"player": {
			"cell": [_player.cell.x, _player.cell.y],
			"position": [_player.global_position.x, _player.global_position.y],
			"altitude": _player.altitude,
			"motion": _player.motion.to_dict(),
		},
	})
	var result: Error = SimSaveStore.save_file(path, snapshot)
	_notice = "近况已记下。" if result == OK else "没有记下近况：%s" % error_string(result)
	_refresh_panel()
	return result


func load_game(path: String = SAVE_PATH) -> Error:
	if is_instance_valid(continuity):
		return continuity.load_game(path)
	if simulation == null:
		return ERR_UNCONFIGURED
	var loaded: Dictionary = SimSaveStore.load_file(path)
	if not bool(loaded.get("ok", false)):
		return _load_failed(str(loaded.get("message", "无法读取存档。")))
	var raw_snapshot: Variant = loaded.get("data")
	if not raw_snapshot is Dictionary:
		return _load_failed("近况文件格式不正确。")
	var snapshot: Dictionary = SessionSaveSchema.upgrade(raw_snapshot)
	var content := ReolContentDB.new()
	if not content.load_bundle(snapshot.get("content_bundle")):
		return _load_failed("近况里的内容定义不完整。")
	var candidate_map: WorldMapData = _world.map_data().independent_copy()
	if not candidate_map.configure_nature(content.natural_environment):
		return _load_failed("近况里的自然地表定义不正确。")
	if not _valid_snapshot(snapshot, candidate_map, snapshot.assembly.region_configs.home):
		return _load_failed("这份近况不适用于当前山门。")
	# Validate into a separate simulation so failed loads leave the live state intact.
	var restored: VillageSimulation = VillageSimulation.from_snapshot(content, snapshot["simulation"])
	if restored == null or not _matches_world(restored, candidate_map, snapshot.assembly.region_configs.home):
		return _load_failed("近况里的行动或账目不完整。")
	var saved_player: Dictionary = snapshot["player"]
	var player_cell: Vector2i = _decode_cell(saved_player["cell"])
	if _decode_cell(restored.actors["player"]["cell"]) != player_cell:
		return _load_failed("近况里的位置记录不一致。")
	if not GameClock.restore_state(snapshot["clock"]):
		return _load_failed("近况里的时间记录不正确。")
	simulation = restored
	adopt_content(content)
	_config = restored.config.duplicate(true)
	_world.bind_map_data(candidate_map)
	simulation.set_navigation(_find_path, _world.can_step)
	_places = simulation.places.duplicate(true)
	_player.spawn_at(player_cell)
	var saved_position: Array = saved_player["position"]
	_player.motion.bind_body(simulation.actors.player)
	_player.restore_motion(saved_player.motion, Vector2(float(saved_position[0]), float(saved_position[1])), int(snapshot.clock.elapsed_ms))
	_player.set_altitude(int(saved_player["altitude"]))
	_world.set_focus(player_cell)
	if _fog != null:
		_fog.restore_exploration(snapshot.world.exploration, player_cell)
	_sync_actor_views(true)
	if not simulation.actors.has(_selected_actor):
		_selected_actor = "player"
	_notice = "已回到记下近况的那一刻。"
	_refresh_panel()
	queue_redraw()
	content_replaced.emit(content)
	simulation_advanced.emit()
	return OK


static func find_grid_path(
	world: ReolWorld,
	from_cell: Vector2i,
	to_cell: Vector2i,
	radius: int,
	budget: int
) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if world == null or radius < 0 or budget < 1:
		return empty
	if not world.is_walkable(from_cell) or not world.is_walkable(to_cell):
		return empty
	if not _within_radius(from_cell, to_cell, radius):
		return empty
	var queue: Array[Vector2i] = [from_cell]
	var previous: Dictionary[Vector2i, Vector2i] = {from_cell: from_cell}
	var head: int = 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if current == to_cell:
			var path: Array[Vector2i] = [current]
			while current != from_cell:
				current = previous[current]
				path.append(current)
			path.reverse()
			return path
		for direction: Vector2i in DIRECTIONS:
			var next_cell: Vector2i = current + direction
			if previous.has(next_cell) or not _within_radius(from_cell, next_cell, radius):
				continue
			if previous.size() >= budget:
				continue
			if not world.can_step(current, direction):
				continue
			previous[next_cell] = current
			queue.append(next_cell)
	return empty


func _on_time_advanced(_from_ms: int, to_ms: int) -> void:
	if simulation == null:
		return
	var old_events: int = int(simulation.simulation_work.boundary_count)
	var previous_minute: int = simulation.tick_index
	if is_instance_valid(continuity):
		continuity.advance_to_ms(to_ms)
	else:
		simulation.advance_to_ms(to_ms)
	_player._project_motion()
	_sync_actor_views(true)
	if old_events != int(simulation.simulation_work.boundary_count) or previous_minute != simulation.tick_index:
		_refresh_panel()
		queue_redraw()
		simulation_advanced.emit()


func _process(delta: float) -> void:
	if simulation == null or GameClock.paused or _visual_progress >= 1.0:
		return
	var rate: float = GameClock.view_transition_rate() * GameClock.speed
	_visual_progress = minf(1.0, _visual_progress + delta * rate)
	for id: String in _visual_targets:
		var pawn: Pawn = _pawns.get(id)
		if is_instance_valid(pawn):
			pawn.global_position = _visual_starts[id].lerp(
				_visual_targets[id], _visual_progress
			)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or simulation == null:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_F5:
		save_game()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F9:
		load_game()
		get_viewport().set_input_as_handled()


func _sync_player_cell() -> void:
	# SimLocalMotion writes this very body. Keep legacy standalone probes explicit.
	if _player.motion._body != simulation.actors.player:
		_player.motion.bind_body(simulation.actors.player)
	if is_instance_valid(continuity):
		continuity.world_sim.invalidate_region("home")


func _sync_actor_views(snap: bool) -> void:
	_visual_progress = 1.0 if snap else 0.0
	var layout: Dictionary = continuity.actor_view_layout() if is_instance_valid(continuity) else PawnViewLayout.build(simulation.actors, "player")
	for id: String in _pawns:
		if not simulation.actors.has(id):
			continue
		var pawn: Pawn = _pawns[id]
		var actor: Dictionary = simulation.actors[id]
		var pose: Dictionary = HumanoidPose.in_world(continuity.world_sim, id, GameClock.elapsed_ms) if is_instance_valid(continuity) else HumanoidPose.from_body(actor, GameClock.elapsed_ms, actor.active)
		pawn.appearance_pose = HumanoidPose.stabilized(pose, pawn.appearance_pose)
		if is_instance_valid(continuity):
			pawn.clothing_appearance = continuity.world_sim.clothing.appearance(id)
		pawn.set_view_layout(layout.get(id, {}))
		pawn.cell = _decode_cell(actor["cell"])
		pawn.visible = bool(actor.alive) and (_fog.is_cell_visible(pawn.cell) if _fog != null else true)
		var target: Vector2 = simulation.actor_position(actor)
		_visual_starts[id] = pawn.global_position
		_visual_targets[id] = target
		if snap:
			pawn.global_position = target
		_sync_needs(pawn.state, actor)
		pawn.queue_redraw()
	if is_instance_valid(continuity):
		_player.clothing_appearance = continuity.world_sim.clothing.appearance("player")
		_player.appearance_pose = HumanoidPose.stabilized(HumanoidPose.in_world(continuity.world_sim, "player", GameClock.elapsed_ms, continuity.player_journey, _player.manual_visual_moving, _player.motion.action), _player.appearance_pose)
	else:
		_player.appearance_pose = HumanoidPose.stabilized(HumanoidPose.from_body(simulation.actors.player, GameClock.elapsed_ms, simulation.actors.player.active, _player.manual_visual_moving), _player.appearance_pose)
	_sync_needs(_player.state, simulation.actors["player"])
	if is_instance_valid(continuity) and _player.state != null:
		# A visible visitor's body can be projected across a quiet interval without
		# waking every resident in their home settlement for a HUD update.
		var elapsed: int = maxi(0, int(continuity.world_sim.current_time) - simulation.tick_index)
		_player.state.hunger = maxf(0.0, _player.state.hunger - float(_config.needs.hunger_per_minute) * elapsed)
		var energy_rate: float = float(_config.needs.energy_per_minute)
		if not simulation.actors.player.active.is_empty():
			energy_rate += float(_config.needs.work_energy_per_minute)
		_player.state.energy = maxf(0.0, _player.state.energy - energy_rate * elapsed)
	body_state_changed.emit()


func _sync_needs(state: PawnState, actor: Dictionary) -> void:
	if state == null:
		return
	state.pawn_def = _content.get_pawn(StringName(actor.definition_id))
	state.origin = _content.get_origin(state.pawn_def.origin_id)
	state.hunger = float(actor["hunger"])
	state.energy = float(actor["energy"])
	state.qi = int(actor["qi"])
	state.stamina = int(actor["stamina"])
	state.mood = float(actor["mood"])
	state.rank = _content.get_rank(StringName(actor["rank_id"]))


func _actor_cells() -> Dictionary:
	var cells: Dictionary = {"player": [_player.cell.x, _player.cell.y]}
	for id: String in _pawns:
		var pawn: Pawn = _pawns[id]
		cells[id] = [pawn.cell.x, pawn.cell.y]
	return cells


func _find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	return find_grid_path(
		_world, from_cell, to_cell,
		int(_config["navigation_radius"]), int(_config["navigation_budget"])
	)


func _ensure_initial_reachability() -> bool:
	# Initial placement may move an actor off an isolated grass patch. Once the
	# simulation starts, unreachable journeys fail instead of teleporting actors.
	var reachable: Array[Vector2i] = _reachable_cells(_player.cell)
	if reachable.is_empty():
		return false
	var reachable_set: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in reachable:
		reachable_set[cell] = true
	var occupied: Dictionary[Vector2i, bool] = {_player.cell: true}
	for pawn: Pawn in _pawns.values():
		if reachable_set.has(pawn.cell) and not occupied.has(pawn.cell):
			occupied[pawn.cell] = true
			continue
		var replacement := Vector2i(-1, -1)
		var closest: int = 9223372036854775807
		for cell: Vector2i in reachable:
			if occupied.has(cell):
				continue
			var distance: int = (cell - pawn.cell).length_squared()
			if distance < closest:
				closest = distance
				replacement = cell
		if replacement.x < 0:
			push_error("VillageRuntime: not enough connected cells for the initial actors")
			return false
		pawn.cell = replacement
		pawn.global_position = TileGrid.cell_to_world(replacement)
		pawn.queue_redraw()
		occupied[replacement] = true
	return true


func _load_config() -> bool:
	var json := JSON.new()
	var result: Error = json.parse(FileAccess.get_file_as_string(CONFIG_PATH))
	if result != OK or not json.data is Dictionary:
		push_error("VillageRuntime: invalid %s: %s" % [CONFIG_PATH, json.get_error_message()])
		return false
	_config = json.data
	if (
		not _valid_integer(_config.get("navigation_radius"), 0)
		or not _valid_integer(_config.get("navigation_budget"), 1)
		or not _config.get("place_defs") is Array
	):
		push_error("VillageRuntime: missing navigation or facility definitions")
		return false
	return true


func _layout_places(actor_cells: Dictionary) -> Dictionary:
	var origin: Vector2i = _player.cell
	var reachable: Array[Vector2i] = _reachable_cells(origin)
	var used: Dictionary[Vector2i, bool] = {}
	for value: Array in actor_cells.values():
		used[_decode_cell(value)] = true
	var result: Dictionary = {}
	for value: Variant in _config["place_defs"]:
		if not value is Dictionary:
			return {}
		var definition: Dictionary = value
		if not definition.get("id") is String or not _number_pair(definition.get("offset"), true):
			return {}
		var id: String = definition["id"]
		if id.is_empty() or result.has(id):
			return {}
		var desired: Vector2i = origin + _decode_cell(definition["offset"])
		var chosen := Vector2i(-1, -1)
		var closest: int = 9223372036854775807
		for candidate: Vector2i in reachable:
			if used.has(candidate):
				continue
			var distance: int = (candidate - desired).length_squared()
			if distance < closest:
				closest = distance
				chosen = candidate
		if chosen.x < 0:
			return {}
		used[chosen] = true
		result[id] = {"cell": [chosen.x, chosen.y], "label": str(definition.get("label", id))}
	return result


func _reachable_cells(origin: Vector2i) -> Array[Vector2i]:
	return find_reachable_cells(_world, origin, int(_config.navigation_radius), int(_config.navigation_budget))


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	_panel = VillagePanel.new()
	screen.add_child(_panel)
	_panel.action_requested.connect(_on_action_requested)
	_panel.help_requested.connect(_on_help_requested)
	_panel.save_requested.connect(save_game)
	_panel.load_requested.connect(load_game)


func _refresh_panel() -> void:
	if _panel == null or simulation == null:
		return
	if is_instance_valid(continuity):
		_panel.visible = false
		return
	var definition: PawnDef = _content.get_pawn(StringName(_selected_actor))
	var title: String = definition.display_name if definition != null else _selected_actor
	if _selected_actor == "player":
		title = "你"
	var details: String = "你随身：柴 %d · 饭 %d · 药草 %d" % [
		simulation.inventory.quantity("actor:player", "wood"),
		simulation.inventory.quantity("actor:player", "meal"),
		simulation.inventory.quantity("actor:player", "herb"),
	]
	if _selected_actor == "player":
		var actor: Dictionary = simulation.actors["player"]
		details = "饱食 %d · 精力 %d · 功德堂 %d 功\n%s" % [
			int(actor["hunger"]), int(actor["energy"]),
			simulation.institutions.balance("sect", "player"), details,
		]
	var visible_actor: bool = _is_actor_visible(_selected_actor)
	var status: String = simulation.actor_status(_selected_actor) if visible_actor else "已离开视野"
	_panel.update_view(
		title, status, details, simulation.known_event_lines("player", 3), _notice,
		_selected_actor != "player" and visible_actor
	)


func _is_actor_visible(id: String) -> bool:
	if id == "player":
		return true
	var pawn: Pawn = _pawns.get(id)
	if not is_instance_valid(pawn):
		return false
	return _fog.is_cell_visible(pawn.cell) if _fog != null else pawn.visible


func _on_action_requested(action_id: String) -> void:
	if is_instance_valid(continuity):
		continuity.prepare_home_command()
		continuity.cancel_travel()
	_sync_player_cell()
	if simulation.submit_action("player", action_id):
		_notice = "你已动身。WASD 可以中断行动。"
	else:
		_notice = "眼下做不了这件事，可能正在忙，或缺少可用的物资与路。"
	if is_instance_valid(continuity):
		continuity.world_sim.invalidate_region("home")
	_refresh_panel()


func _on_help_requested() -> void:
	request_selected_help()


func request_selected_help() -> Dictionary:
	if _selected_actor == "player" or not _is_actor_visible(_selected_actor):
		return {"status": "refused", "reason": "not_visible", "message": "请先选中视野内的同门。"}
	if is_instance_valid(continuity) and continuity.current_region != "home":
		return {"status": "refused", "reason": "not_local", "message": "对方眼下不在这里。"}
	_sync_player_cell()
	if is_instance_valid(continuity):
		continuity.prepare_home_command()
	var result: Dictionary = simulation.request_help("player", _selected_actor)
	if is_instance_valid(continuity):
		continuity.world_sim.invalidate_region("home")
	_notice = str(result.get("message", result.get("line", "对方听到了你的请求。")))
	_refresh_panel()
	return result


func selected_interaction() -> Dictionary:
	var available: bool = _selected_actor != "player" and _is_actor_visible(_selected_actor)
	if is_instance_valid(continuity):
		available = available and continuity.current_region == "home"
	return {"enabled": available, "line": "请帮忙送柴" if available else "选中同门可商量送柴"}


func resource_is_observable(sim: VillageSimulation, source_id: String) -> bool:
	if sim == null or simulation == null or not sim.config.get("resource_sources", {}).has(source_id):
		return false
	if is_instance_valid(continuity) and not continuity.human_player_active():
		return false
	var source: Dictionary = sim.config.resource_sources[source_id]
	if not sim.places.has(str(source.place)):
		return false
	var cell: Vector2i = _decode_cell(sim.places[source.place].cell)
	if _fog != null and not _fog.is_cell_visible(cell):
		return false
	var observer: Vector2 = simulation.actor_position(simulation.actors.player)
	return observer.distance_to(TileGrid.cell_to_world(cell)) <= float(sim.config.observation_radius) * TileGrid.TILE_SIZE


func visible_resource_sources(sim: VillageSimulation) -> Dictionary:
	var visible_sources: Dictionary = {}
	if sim == null:
		return visible_sources
	for id: String in sim.config.get("resource_sources", {}):
		if resource_is_observable(sim, id):
			visible_sources[id] = true
	return visible_sources


func herb_phase_for(sim: VillageSimulation, place_id: String) -> String:
	if sim == null:
		return ""
	for id: String in sim.config.get("resource_sources", {}):
		var source: Dictionary = sim.config.resource_sources[id]
		if source.definition != "wild_herbs" or source.place != place_id or not sim.land_resources.sources.has(id):
			continue
		# An explored facility is still drawn, but its living state is read only
		# when the current body can see it at the original observation distance.
		if not resource_is_observable(sim, id):
			return "unknown"
		return str(sim.land_resources.ecology_observation(id).get("phase", ""))
	return ""


func _draw() -> void:
	if _world == null:
		return
	for id: String in _places:
		var place: Dictionary = _places[id]
		var cell: Vector2i = _decode_cell(place.cell)
		if _fog != null and not _fog.is_explored(cell):
			continue
		var center: Vector2 = TileGrid.cell_to_world(cell)
		center.y -= float(_world.get_elevation(cell) * ReolWorld.ELEVATION_PX)
		FacilityVisuals.draw_facility(self, id, center, str(place.label), Color("#cfbc80"), herb_phase_for(simulation, id), place.get("workspace", {}), _place_is_explored)


func _place_is_explored(cell: Vector2i) -> bool:
	return _fog == null or _fog.is_explored(cell)


func _load_failed(message: String) -> Error:
	_notice = message
	_refresh_panel()
	return ERR_INVALID_DATA


func _valid_snapshot(snapshot: Dictionary, candidate_map: WorldMapData = null, opening: Variant = null) -> bool:
	if not SessionSaveSchema.is_valid_world(snapshot):
		return false
	if not snapshot.has("continuity") and snapshot.avatar_subject != "subject:player":
		return false
	if not snapshot.has("continuity") and snapshot.get("simulation", {}).get("actors", {}).get("player", {}).get("autonomous", false):
		return false
	if not snapshot.get("simulation") is Dictionary or not snapshot.get("clock") is Dictionary:
		return false
	var saved_simulation: Dictionary = snapshot["simulation"]
	var expected: Dictionary = _config if opening == null else opening
	if not saved_simulation.get("config") is Dictionary or not SimLandResources.opening_matches(RegionalSimulation._base_workplace_config(saved_simulation.config), RegionalSimulation._base_workplace_config(expected)):
		return false
	if saved_simulation.get("controlled_actor") != "player":
		return false
	if not snapshot.get("player") is Dictionary:
		return false
	var clock: Dictionary = snapshot["clock"]
	if not ReolGameClock.is_valid_state(clock) or not clock.has("elapsed_ms"):
		return false
	if saved_simulation.get("tick_index") != clock["tick_index"]:
		return false
	var saved_player: Dictionary = snapshot["player"]
	if not _number_pair(saved_player.get("cell"), true) or not _number_pair(saved_player.get("position")):
		return false
	if not _valid_integer(saved_player.get("altitude"), 0) or int(saved_player["altitude"]) > 2:
		return false
	var cell: Vector2i = _decode_cell(saved_player["cell"])
	var position_data: Array = saved_player["position"]
	var position_value := Vector2(float(position_data[0]), float(position_data[1]))
	if not _player.motion.valid_state(saved_player.get("motion"), int(clock.elapsed_ms)):
		return false
	if not saved_simulation.get("actors") is Dictionary or not saved_simulation.actors.get("player") is Dictionary or not SimLocalMotion._vector(saved_simulation.actors.player.get("facing")) or not Vector2(float(saved_player.motion.facing[0]), float(saved_player.motion.facing[1])).is_equal_approx(SimRouteTravel.facing(saved_simulation.actors.player)):
		return false
	if not saved_player.motion.action.is_empty() and (not saved_simulation.get("actors") is Dictionary or not saved_simulation.actors.get("player") is Dictionary or not saved_simulation.actors.player.get("active", {}).is_empty()):
		return false
	var terrain: WorldMapData = candidate_map if candidate_map != null else _world.map_data()
	return terrain.terrain_is_walkable(cell) and TileGrid.world_to_cell(position_value) == cell


func _matches_world(candidate: VillageSimulation, candidate_map: WorldMapData = null, opening: Variant = null) -> bool:
	var terrain: WorldMapData = candidate_map if candidate_map != null else _world.map_data()
	var expected_actors: Dictionary = {}
	var expected_places: Array = []
	if opening == null:
		# Legacy adapter query: compare against the currently bound scene. Saved
		# candidates always pass an explicit archived opening below.
		for id: String in _actor_cells():
			expected_actors[id] = id
		expected_places = _places.keys()
	else:
		for id: String in opening.actor_profiles:
			expected_actors[id] = opening.actor_profiles[id].get("definition_id", id)
		for definition: Dictionary in opening.place_defs:
			expected_places.append(str(definition.id))
	if candidate.actors.size() != expected_actors.size() or candidate.places.size() != expected_places.size():
		return false
	for id: String in expected_actors:
		if not candidate.actors.has(id) or candidate.actors[id]["definition_id"] != expected_actors[id]:
			return false
	for id: String in expected_places:
		if not candidate.places.has(id) or not candidate.places[id].get("label") is String:
			return false
	for actor: Dictionary in candidate.actors.values():
		var current: Vector2i = _decode_cell(actor["cell"])
		if not terrain.terrain_is_walkable(current):
			return false
		var active: Dictionary = actor["active"]
		for step_data: Array in active.get("path", []):
			var next_cell: Vector2i = _decode_cell(step_data)
			var direction: Vector2i = next_cell - current
			if absi(direction.x) > 1 or absi(direction.y) > 1 or not terrain.terrain_can_step(current, direction):
				return false
			current = next_cell
		if not active.is_empty():
			var destination: String = str(active.get("destination", ""))
			if not candidate.places.has(destination):
				return false
			if current != _decode_cell(candidate.places[destination]["cell"]):
				return false
	for place: Dictionary in candidate.places.values():
		if not terrain.terrain_is_walkable(_decode_cell(place["cell"])):
			return false
	if not SimWorkplaces.valid_places(candidate.places, candidate.config, terrain):
		return false
	return true


static func _within_radius(origin: Vector2i, cell: Vector2i, radius: int) -> bool:
	return maxi(absi(cell.x - origin.x), absi(cell.y - origin.y)) <= radius


static func find_reachable_cells(world: ReolWorld, origin: Vector2i, radius: int, budget: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if world == null or not world.is_walkable(origin):
		return result
	var seen: Dictionary[Vector2i, bool] = {origin: true}
	result.append(origin)
	var head: int = 0
	while head < result.size():
		var current: Vector2i = result[head]
		head += 1
		for direction: Vector2i in DIRECTIONS:
			var cell: Vector2i = current + direction
			if seen.has(cell) or not _within_radius(origin, cell, radius):
				continue
			if seen.size() >= budget or not world.can_step(current, direction):
				continue
			seen[cell] = true
			result.append(cell)
	return result


static func _decode_cell(data: Array) -> Vector2i:
	return Vector2i(int(data[0]), int(data[1]))


static func _finite_number(value: Variant) -> bool:
	return SnapshotValues.finite_number(value)


static func _valid_integer(value: Variant, minimum: int) -> bool:
	return SnapshotValues.valid_integer(value, minimum)


static func _number_pair(value: Variant, integers_only: bool = false) -> bool:
	return SnapshotValues.number_pair(value, integers_only)


static func _json_normalized(value: Variant) -> Variant:
	# Compatibility for existing probes and adapters; rules live at persistence.
	return SnapshotValues.normalized(value)


static func _snapshot_json_value(value: Variant) -> Variant:
	return SnapshotValues.for_save(value)
