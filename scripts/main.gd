extends Node2D
## Ordinary demo composition: world, player, NPC views, camera and HUD.
##
## Content is data-driven; main assembles adapters and routes selection/input.

const NPC_IDS: Array[StringName] = [
	&"chen_shouzhuo",
	&"a_he",
	&"shi_tou",
	&"su_zhi",
	&"lao_zhou",
]
const NPC_OFFSETS: Array[Vector2i] = [
	Vector2i(3, -2),
	Vector2i(-3, -1),
	Vector2i(4, 2),
	Vector2i(-4, 3),
	Vector2i(2, 4),
]
const SELECT_RADIUS: float = 34.0
const WORLD_GENERATION_PATH: String = "res://data/scenarios/world_generation.json"
const WORLD_GEOGRAPHY_PATH: String = "res://data/scenarios/world_geography.json"

@onready var world: ReolWorld = $World
@onready var fog: FogOfWar = $Fog
@onready var player: PlayerCharacter = $Player
@onready var camera: CameraController = $Camera
@onready var hud: GameHUD = $HUD

var _flying: FlyingMarker
var _content: ReolContentDB
var _pawns: Array[Pawn] = []
var _selected: Pawn
var _village: VillageRuntime
var _continuity: WorldContinuityRuntime
var _avatar: PlayerAvatarRuntime
var _opening_map: WorldMapData
var _opening_content: ReolContentDB
var _opening_started: bool = false
var _terrain_editor: TerrainEditorRuntime


func configure_opening_map(description: Variant, terrain_overrides: Variant = []) -> bool:
	# Creation/preview input only. This cannot replace a running world's map.
	if _opening_started or is_inside_tree() or _opening_map != null:
		return false
	var candidate: WorldMapData = WorldMapData.from_descriptor(description)
	if candidate == null or not candidate.restore_terrain_overrides(terrain_overrides):
		return false
	_opening_map = candidate
	return true


func configure_opening_content(bundle: Variant) -> bool:
	if _opening_started or is_inside_tree() or _opening_content != null:
		return false
	var candidate := ReolContentDB.new()
	if not candidate.load_bundle(bundle) or int(candidate.climate.calendar.start_minutes) != GameClock.start_minutes:
		return false
	_opening_content = candidate
	return true


func configure_opening_geography(profile: Variant) -> bool:
	if _opening_started or is_inside_tree() or _opening_content != null:
		return false
	var source := ReolContentDB.new()
	if not source.load_all():
		return false
	var candidate: ReolContentDB = ReolGeographicContent.build(source.content_bundle(), profile)
	if candidate == null or int(candidate.climate.calendar.start_minutes) != GameClock.start_minutes:
		return false
	_opening_content = candidate
	return true


func _ready() -> void:
	_opening_started = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	# This scenario chooses only a new world's map. Loading an archive later
	# reconstructs its own descriptor, including the unchanged historical hills.
	var opening_map: WorldMapData = _opening_map
	_opening_map = null
	if opening_map == null:
		var description: Variant = JSON.parse_string(FileAccess.get_file_as_string(WORLD_GENERATION_PATH))
		opening_map = WorldMapData.from_descriptor(description)
	if opening_map == null:
		push_error("Invalid new-world map scenario: " + WORLD_GENERATION_PATH)
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	_content = _opening_content
	_opening_content = null
	if _content == null:
		var source := ReolContentDB.new()
		if source.load_all():
			var geography: Variant = JSON.parse_string(FileAccess.get_file_as_string(WORLD_GEOGRAPHY_PATH))
			_content = ReolGeographicContent.build(source.content_bundle(), geography)
	# The existing shared clock owns the opening hour. Reject unsupported
	# calendars before publishing a map, bodies, or a partially initialized world.
	if _content == null or int(_content.climate.calendar.start_minutes) != GameClock.start_minutes:
		push_error("Invalid new-world geography/content or clock origin: " + WORLD_GEOGRAPHY_PATH)
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	world.bind_map_data(opening_map)
	if GameClock.elapsed_ms == 0:
		GameClock.set_paused(true)
	RenderingServer.set_default_clear_color(Color("#0b0f12"))
	var spawn_cell: Vector2i = world.find_spawn_cell()
	player.spawn_at(spawn_cell)
	camera.setup(world.world_rect(), player.global_position)
	camera.set_focus_target(player)
	hud.set_world(world, player, camera, fog)
	world.set_focus(spawn_cell)

	_flying = FlyingMarker.new()
	_flying.setup(world, spawn_cell + Vector2i(3, 0), 1)
	add_child(_flying)

	var player_def: PawnDef = _content.get_pawn(&"player")
	if player_def != null:
		player.setup_state(PawnState.create(player_def, _content))

	_spawn_named_pawns(spawn_cell)
	_village = _create_village_runtime()
	_village.name = "VillageRuntime"
	add_child(_village)
	if not _village.setup(world, player, _pawns, _content, true):
		push_error("Village framework initialization failed")
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	_continuity = WorldContinuityRuntime.new()
	_continuity.name = "WorldContinuityRuntime"
	add_child(_continuity)
	if not _continuity.setup(_village, true, true, true):
		push_error("World continuity initialization failed")
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	($DayNight as DayNight).bind_world(_continuity)
	# The first observation must use the complete world geometry, including the
	# opening offices and the regional construction sight provider. Exploration
	# is persistent, so recomputing after an early observation cannot undo it.
	fog.setup(world, spawn_cell)
	# Village setup synchronized the views while every fog cell was still hidden.
	_village._sync_actor_views(true)
	_continuity.player_travel_advanced.connect(_on_travel_advanced)
	_continuity.resident_selected.connect(_select_pawn)
	_village.simulation_advanced.connect(_refresh_interaction)
	_village.body_state_changed.connect(hud.refresh_body)
	_village.content_replaced.connect(_on_content_replaced)
	player.cell_changed.connect(_refresh_interaction)
	hud.help_requested.connect(_request_selected_help)
	_select_player()
	_avatar = PlayerAvatarRuntime.new()
	_avatar.name = "PlayerAvatarRuntime"
	add_child(_avatar)
	_avatar.setup(self, _continuity)
	if OS.get_cmdline_user_args().has("--world-editor"):
		_terrain_editor = TerrainEditorRuntime.new()
		_terrain_editor.name = "TerrainEditorRuntime"
		add_child(_terrain_editor)
		_terrain_editor.setup(_continuity)


func _create_village_runtime() -> VillageRuntime:
	return VillageRuntime.new()


func _on_content_replaced(content: ReolContentDB) -> void:
	_content = content
	_pawns.assign(_village.actor_views())
	if is_instance_valid(_selected):
		_selected.set_selected(false)
	_selected = null
	if _continuity == null or _continuity.human_player_active():
		_select_player()
	else:
		player.set_selected(false)


func _on_travel_advanced(position_value: Vector2) -> void:
	if _continuity != null and not _continuity.human_player_active():
		return
	camera.global_position = position_value
	camera._clamp_to_world()


func _spawn_named_pawns(spawn_cell: Vector2i) -> void:
	var used: Dictionary[Vector2i, bool] = {spawn_cell: true}
	for index in NPC_IDS.size():
		var definition: PawnDef = _content.get_pawn(NPC_IDS[index])
		if definition == null:
			push_warning("Missing pawn definition: %s" % NPC_IDS[index])
			continue
		var cell: Vector2i = world.find_walkable_near(
			spawn_cell + NPC_OFFSETS[index], 6
		)
		var attempts: int = 0
		while used.has(cell) and attempts < 32:
			cell = world.find_walkable_near(cell + Vector2i(1, 0), 4)
			attempts += 1
		used[cell] = true

		var pawn := Pawn.new()
		pawn.name = "Pawn_%s" % definition.id
		pawn.setup(definition, _content, world, cell)
		add_child(pawn)
		_pawns.append(pawn)


func _process(_delta: float) -> void:
	var focus: Vector2i = _continuity.controlled_cell() if _continuity != null else player.cell
	world.set_focus(focus)
	# Rebinding a saved map clears its view. Paint the actual screen before the
	# rest of a 64x64 chunk, including the adjacent chunk across a screen edge.
	var half_view: Vector2 = get_viewport_rect().size * 0.5 / camera.zoom
	var start := Vector2i(((camera.global_position - half_view) / TileGrid.TILE_SIZE).floor())
	var end := Vector2i(((camera.global_position + half_view) / TileGrid.TILE_SIZE).ceil())
	end.y += ceili(float(ReolWorld.ELEVATION_LEVELS * ReolWorld.ELEVATION_PX) / TileGrid.TILE_SIZE)
	world.prioritize_view(Rect2i(start, end - start))
	fog.set_focus(focus)
	if _flying != null:
		_flying.visible = hud.diagnostics_visible() and fog.is_cell_visible(_flying.cell)
	for pawn: Pawn in _pawns:
		pawn.visible = fog.is_cell_visible(pawn.cell) and (_village == null or _village.simulation == null or _village.simulation.actor_is_alive(String(pawn.pawn_id)))
	if _selected != null and (not is_instance_valid(_selected) or not _selected.visible):
		_select_player()


func _unhandled_input(event: InputEvent) -> void:
	if _continuity != null and not _continuity.human_player_active():
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			var world_position: Vector2 = (
				get_canvas_transform().affine_inverse() * mouse.position
			)
			_select_at(world_position)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			_select_player()
			get_viewport().set_input_as_handled()
			return



func _input(event: InputEvent) -> void:
	if _terrain_editor != null and _terrain_editor.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	# Global time controls must run before GUI focus can treat Space as a button click.
	if _avatar != null and _avatar.opening.visible and event is InputEventKey and event.keycode not in [KEY_TAB, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("move_left") or event.is_action_pressed("move_right") or event.is_action_pressed("move_up") or event.is_action_pressed("move_down"):
		GameClock.cancel_wait()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SHIFT:
		player.request_sidestep()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		GameClock.request_wait()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_pause"):
		GameClock.toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_1"):
		GameClock.set_speed(1.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_2"):
		GameClock.set_speed(2.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_4"):
		GameClock.set_speed(4.0)
		get_viewport().set_input_as_handled()


func _select_at(world_position: Vector2) -> void:
	if _continuity != null and _continuity.select_remote_at(world_position):
		return
	var best: Pawn = null
	var best_distance: float = SELECT_RADIUS / camera.zoom.x
	for pawn: Pawn in _pawns:
		if not pawn.visible:
			continue
		var distance: float = pawn.selection_center().distance_to(world_position)
		if distance < best_distance:
			best = pawn
			best_distance = distance

	if player.selection_center().distance_to(world_position) < best_distance:
		_select_player()
	elif best != null:
		_select_pawn(best)
	else:
		_select_player()


func _select_pawn(pawn: Pawn) -> void:
	if is_instance_valid(_selected):
		_selected.set_selected(false)
	_selected = pawn
	_selected.set_selected(true)
	player.set_selected(false)
	if _continuity != null:
		_continuity.select_actor_view(pawn)
	if pawn.state != null:
		hud.show_pawn_state(pawn.state, false, pawn.display_name_override)
	if _village != null:
		_village.select_actor(String(pawn.pawn_id) if _continuity == null or _continuity.actor_region(String(pawn.pawn_id)) == "home" else "player")
	_refresh_interaction()


func _select_player() -> void:
	if is_instance_valid(_selected):
		_selected.set_selected(false)
	_selected = null
	if _continuity != null:
		_continuity.clear_remote_selection()
	player.set_selected(true)
	if player.state != null:
		hud.show_pawn_state(player.state, true)
	if _village != null:
		_village.select_actor("player")
	_refresh_interaction()


func _refresh_interaction() -> void:
	if _continuity == null:
		return
	var interaction: Dictionary = _continuity.selected_interaction()
	hud.set_interaction(str(interaction.line), bool(interaction.enabled))
	if is_instance_valid(_selected):
		hud.set_activity(_continuity.visible_actor_status(String(_selected.pawn_id)))
	else:
		hud.set_activity("")


func _request_selected_help() -> void:
	var result: Dictionary = _continuity.request_selected_help()
	hud.set_activity(str(result.get("message", result.get("line", "对方听到了。"))))
