extends Node2D
## M2 bootstrap: world + player + named pawns + fixed camera + HUD.
##
## Content is data-driven: pawns/ranks/origins come from res://data/*.json.

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

@onready var world: ReolWorld = $World
@onready var fog: FogOfWar = $Fog
@onready var player: PlayerCharacter = $Player
@onready var camera: CameraController = $Camera
@onready var hud: GameHUD = $HUD

var _flying: FlyingMarker
var _content: ReolContentDB
var _pawns: Array[Pawn] = []
var _selected: Pawn


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_default_clear_color(Color("#0b0f12"))
	var spawn_cell: Vector2i = world.find_spawn_cell()
	player.spawn_at(spawn_cell)
	fog.setup(world, spawn_cell)
	camera.setup(world.world_rect(), player.global_position)
	camera.set_focus_target(player)
	hud.set_world(world, player, camera, fog)
	world.set_focus(spawn_cell)

	_flying = FlyingMarker.new()
	_flying.setup(world, spawn_cell + Vector2i(3, 0), 1)
	add_child(_flying)

	_content = ReolContentDB.new()
	if not _content.load_all():
		for message: String in _content.errors:
			push_error("ContentDB: %s" % message)

	var player_def: PawnDef = _content.get_pawn(&"player")
	if player_def != null:
		player.setup_state(PawnState.create(player_def, _content))

	_spawn_named_pawns(spawn_cell)
	_select_player()


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
	world.set_focus(player.cell)
	fog.set_focus(player.cell)
	if _flying != null:
		_flying.visible = fog.is_cell_visible(_flying.cell)
	for pawn: Pawn in _pawns:
		pawn.visible = fog.is_cell_visible(pawn.cell)


func _unhandled_input(event: InputEvent) -> void:
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

	if event.is_action_pressed("toggle_pause"):
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
	if _selected != null:
		_selected.set_selected(false)
	_selected = pawn
	_selected.set_selected(true)
	player.set_selected(false)
	if pawn.state != null:
		hud.show_pawn_state(pawn.state, false)


func _select_player() -> void:
	if _selected != null:
		_selected.set_selected(false)
		_selected = null
	player.set_selected(true)
	if player.state != null:
		hud.show_pawn_state(player.state, true)
