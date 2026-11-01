extends Node2D
## M1 bootstrap: orthographic top-down world + player + fixed camera + debug HUD.

@onready var world: ReolWorld = $World
@onready var fog: FogOfWar = $Fog
@onready var player: PlayerCharacter = $Player
@onready var camera: CameraController = $Camera
@onready var hud: GameHUD = $HUD

var _flying: FlyingMarker


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


func _process(_delta: float) -> void:
	world.set_focus(player.cell)
	fog.set_focus(player.cell)
	if _flying != null:
		_flying.visible = fog.is_cell_visible(_flying.cell)


func _unhandled_input(event: InputEvent) -> void:
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
