extends Node2D
## M1 bootstrap: orthographic top-down world + player + fixed camera + debug HUD.

@onready var world: ReolWorld = $World
@onready var player: PlayerCharacter = $Player
@onready var camera: CameraController = $Camera
@onready var hud: GameHUD = $HUD


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#0b0f12"))
	var spawn_cell: Vector2i = world.find_spawn_cell()
	player.spawn_at(spawn_cell)
	camera.setup(world.world_rect(), player.global_position)
	camera.set_focus_target(player)
	hud.set_world(world, player, camera)
	world.set_focus(spawn_cell)


func _process(_delta: float) -> void:
	world.set_focus(player.cell)
