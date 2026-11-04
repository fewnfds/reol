class_name LocalLightRuntime
extends Node2D
## Pure presentation of bounded rule light. The clock/structures own facts;
## a frame may coalesce dirty projections without skipping world settlement.

const RADIUS: int = 10
const SIDE: int = RADIUS * 2 + 1
var light: PointLight2D
var last_projection: Dictionary = {}
var last_image: Image
var _owner: WeakRef
var _dirty: bool = true
var _texture: ImageTexture


func setup(adapter: WorldContinuityRuntime) -> void:
	_owner = weakref(adapter)
	process_mode = Node.PROCESS_MODE_ALWAYS
	light = PointLight2D.new()
	light.name = "LocalRuleLight"
	light.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	light.texture_scale = TileGrid.TILE_SIZE
	light.color = Color("ffbe7c")
	light.energy = 1.0
	light.enabled = false
	add_child(light)
	adapter.avatar_changed.connect(_mark_dirty)
	adapter.region_changed.connect(func(_id: String) -> void: _mark_dirty())
	adapter.player_travel_advanced.connect(func(_point: Vector2) -> void: _mark_dirty())
	adapter.home_runtime()._player.cell_changed.connect(_mark_dirty)
	adapter.home_runtime()._world.terrain_changed.connect(_on_cells)
	adapter.home_runtime()._world.sight_obstacles_changed.connect(_on_cells)
	if adapter.home_runtime()._fog != null:
		adapter.home_runtime()._fog.visibility_updated.connect(_mark_dirty)
	GameClock.time_advanced.connect(func(_from: int, _to: int) -> void: _mark_dirty())
	refresh()


func _mark_dirty() -> void:
	_dirty = true


func _on_cells(_cells: Array[Vector2i]) -> void:
	_mark_dirty()


func _process(_delta: float) -> void:
	if _dirty:
		refresh()


func refresh() -> void:
	_dirty = false
	light.enabled = false
	last_projection = {}
	last_image = null
	var adapter: WorldContinuityRuntime = _owner.get_ref() as WorldContinuityRuntime
	if adapter == null or adapter.soul_player_active():
		return
	var center: Vector2i = adapter.controlled_cell()
	var fog: FogOfWar = adapter.home_runtime()._fog
	var cells: Array[Vector2i] = []
	for y: int in range(center.y - RADIUS, center.y + RADIUS + 1):
		for x: int in range(center.x - RADIUS, center.x + RADIUS + 1):
			var cell := Vector2i(x, y)
			if adapter.world_sim.map_data.in_bounds(cell) and (fog.is_cell_visible(cell) if fog != null else center.distance_to(cell) <= 5.0):
				cells.append(cell)
	var patch: Dictionary = SimLocalLight.local_patch(adapter.world_sim, cells)
	if not bool(patch.supported):
		return
	last_projection = patch
	var any_light: bool = false
	for value: int in patch.values.values():
		if value > 0:
			any_light = true
			break
	if not any_light:
		return
	var image: Image = Image.create(SIDE, SIDE, false, Image.FORMAT_RGB8)
	image.fill(Color.BLACK)
	for cell: Vector2i in patch.values:
		var relative: int = int(patch.values[cell])
		if relative <= 0:
			continue
		var strength: float = minf(1.0, float(relative) / float(patch.relative_scale))
		# Add-mode Light2D reads RGB, not alpha. Nearest sampling keeps zero
		# texels outside current sight from bleeding across their cell boundary.
		image.set_pixel(cell.x - center.x + RADIUS, cell.y - center.y + RADIUS, Color(strength, strength, strength))
	# Keep the actual CPU upload for diagnostics. Headless dummy rendering does
	# not update its readback copy on ImageTexture.update; native GPU QA waits
	# for a rendered frame and inspects the real texture separately.
	last_image = image
	if _texture == null:
		_texture = ImageTexture.create_from_image(image)
		light.texture = _texture
	else:
		_texture.update(image)
	light.position = TileGrid.cell_to_world(center)
	light.enabled = true
