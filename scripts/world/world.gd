class_name ReolWorld
extends Node2D
## Chunked 2D orthographic top-down world with a simple elevation layer.
##
## v0.1 slice: one generated region (512x512), 64x64 chunks, 5x5 loaded.
## Terrain type and elevation are separate: grass/water/rock + height 0..3.
## Each elevation is rendered on its own TileMapLayer shifted up by ELEVATION_PX;
## south-facing drops get a cliff face. Fog and clock arrive in later slices.

const WORLD_SIZE: int = 512
const CHUNK_SIZE: int = 64
const LOAD_RADIUS: int = 2
const UNLOAD_RADIUS: int = 3
const WORLD_SEED: int = 20261101
const ELEVATION_LEVELS: int = 4
const ELEVATION_PX: int = 16
const ALTITUDE_PX: int = 28

const TERRAIN_WATER: int = 0
const TERRAIN_GRASS: int = 1
const TERRAIN_ROCK: int = 2

var _layers: Array[TileMapLayer] = []
var _tile_set: TileSet
var _terrain_noise: FastNoiseLite
var _height_noise: FastNoiseLite
var _loaded: Dictionary[Vector2i, bool] = {}
var _cliff_nodes: Dictionary[Vector2i, CliffChunk] = {}
var _pending_load: Array[Vector2i] = []
var _pending_unload: Array[Vector2i] = []
var _focus_chunk: Vector2i = Vector2i(-9999, -9999)
var _initialized: bool = false


func _ready() -> void:
	initialize()


func initialize() -> void:
	if _initialized:
		return
	_initialized = true

	_terrain_noise = FastNoiseLite.new()
	_terrain_noise.seed = WORLD_SEED
	_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrain_noise.frequency = 0.018
	_terrain_noise.fractal_octaves = 3

	_height_noise = FastNoiseLite.new()
	_height_noise.seed = WORLD_SEED + 1
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height_noise.frequency = 0.012
	_height_noise.fractal_octaves = 3

	_tile_set = _build_tile_set()
	for level in ELEVATION_LEVELS:
		var layer := TileMapLayer.new()
		layer.name = "Ground%d" % level
		layer.tile_set = _tile_set
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		layer.position = Vector2(0.0, -float(level * ELEVATION_PX))
		var tint: float = 0.9 + 0.05 * float(level)
		layer.modulate = Color(tint, tint, tint)
		add_child(layer)
		_layers.append(layer)


func set_focus(cell: Vector2i) -> void:
	var chunk := Vector2i(
		floori(float(cell.x) / float(CHUNK_SIZE)),
		floori(float(cell.y) / float(CHUNK_SIZE))
	)
	if chunk == _focus_chunk:
		return
	_focus_chunk = chunk
	_rebuild_queues()


func _process(_delta: float) -> void:
	if not _pending_unload.is_empty():
		var unload_coord: Vector2i = _pending_unload.pop_front()
		_unload_chunk(unload_coord)
	if not _pending_load.is_empty():
		var load_coord: Vector2i = _pending_load.pop_front()
		_load_chunk(load_coord)


func get_terrain(cell: Vector2i) -> int:
	if not _in_bounds(cell):
		return -1
	if _terrain_noise == null:
		return -1
	var n: float = _terrain_noise.get_noise_2d(float(cell.x), float(cell.y))
	if n < -0.45:
		return TERRAIN_WATER
	if n > 0.5:
		return TERRAIN_ROCK
	return TERRAIN_GRASS


func get_elevation(cell: Vector2i) -> int:
	if not _in_bounds(cell):
		return -1
	var terrain: int = get_terrain(cell)
	if terrain == TERRAIN_WATER:
		return 0

	var n: float = _height_noise.get_noise_2d(float(cell.x), float(cell.y))
	var elevation: int = 0
	if n > 0.38:
		elevation = 3
	elif n > 0.08:
		elevation = 2
	elif n > -0.28:
		elevation = 1
	else:
		elevation = 0

	if terrain == TERRAIN_ROCK:
		elevation = maxi(elevation, 2)
	return mini(elevation, ELEVATION_LEVELS - 1)


func is_walkable(cell: Vector2i) -> bool:
	return get_terrain(cell) == TERRAIN_GRASS


func can_move(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if not is_walkable(to_cell):
		return false
	var from_elevation: int = get_elevation(from_cell)
	var to_elevation: int = get_elevation(to_cell)
	return elevation_step_allowed(from_elevation, to_elevation)


func can_step(from_cell: Vector2i, step: Vector2i) -> bool:
	if step == Vector2i.ZERO:
		return true
	if not can_move(from_cell, from_cell + step):
		return false
	if step.x == 0 or step.y == 0:
		return true
	var x_open: bool = can_move(from_cell, from_cell + Vector2i(step.x, 0))
	var y_open: bool = can_move(from_cell, from_cell + Vector2i(0, step.y))
	return diagonal_step_allowed(step, x_open, y_open)


static func diagonal_step_allowed(step: Vector2i, x_open: bool, y_open: bool) -> bool:
	if step.x == 0 or step.y == 0:
		return true
	return x_open or y_open


static func elevation_step_allowed(from_elevation: int, to_elevation: int) -> bool:
	return absi(to_elevation - from_elevation) <= 1


func terrain_name(cell: Vector2i) -> String:
	match get_terrain(cell):
		TERRAIN_WATER:
			return "水"
		TERRAIN_GRASS:
			return "草"
		TERRAIN_ROCK:
			return "岩"
		_:
			return "?"


func find_spawn_cell() -> Vector2i:
	var center := Vector2i(WORLD_SIZE / 2, WORLD_SIZE / 2)
	if is_walkable(center):
		return center
	for radius in range(1, 96):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var candidate := center + Vector2i(dx, dy)
				if is_walkable(candidate):
					return candidate
	return center


func find_walkable_near(origin: Vector2i, radius: int = 8) -> Vector2i:
	if is_walkable(origin):
		return origin
	for search_radius in range(1, radius + 1):
		for dx in range(-search_radius, search_radius + 1):
			for dy in range(-search_radius, search_radius + 1):
				if (
					absi(dx) != search_radius
					and absi(dy) != search_radius
				):
					continue
				var candidate := origin + Vector2i(dx, dy)
				if is_walkable(candidate):
					return candidate
	return origin


func world_rect() -> Rect2:
	return Rect2(
		Vector2.ZERO,
		Vector2(
			float(WORLD_SIZE * TileGrid.TILE_SIZE),
			float(WORLD_SIZE * TileGrid.TILE_SIZE)
		)
	)


func loaded_chunk_count() -> int:
	return _loaded.size()


func pending_chunk_count() -> int:
	return _pending_load.size()


func _rebuild_queues() -> void:
	_pending_load.clear()
	for dy in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var chunk := _focus_chunk + Vector2i(dx, dy)
			if _chunk_in_bounds(chunk) and not _loaded.has(chunk):
				_pending_load.append(chunk)
	_pending_load.sort_custom(
		func(a, b):
			return (a - _focus_chunk).length_squared() < (b - _focus_chunk).length_squared()
	)

	_pending_unload.clear()
	for key in _loaded.keys():
		var chunk: Vector2i = key
		if (
			absi(chunk.x - _focus_chunk.x) > UNLOAD_RADIUS
			or absi(chunk.y - _focus_chunk.y) > UNLOAD_RADIUS
		):
			_pending_unload.append(chunk)


func _load_chunk(chunk: Vector2i) -> void:
	var base := chunk * CHUNK_SIZE
	for local_y in range(CHUNK_SIZE):
		for local_x in range(CHUNK_SIZE):
			var cell := base + Vector2i(local_x, local_y)
			var terrain: int = get_terrain(cell)
			var elevation: int = get_elevation(cell)
			_layers[elevation].set_cell(cell, 0, Vector2i(terrain, 0))

	var cliff := CliffChunk.new()
	cliff.world = self
	cliff.chunk = chunk
	cliff.chunk_size = CHUNK_SIZE
	cliff.tile_size = TileGrid.TILE_SIZE
	cliff.elevation_px = ELEVATION_PX
	cliff.z_index = 5
	add_child(cliff)
	_cliff_nodes[chunk] = cliff
	_loaded[chunk] = true


func _unload_chunk(chunk: Vector2i) -> void:
	var base := chunk * CHUNK_SIZE
	for local_y in range(CHUNK_SIZE):
		for local_x in range(CHUNK_SIZE):
			var cell := base + Vector2i(local_x, local_y)
			var elevation: int = get_elevation(cell)
			_layers[elevation].erase_cell(cell)

	var cliff: CliffChunk = _cliff_nodes.get(chunk)
	if cliff != null:
		cliff.queue_free()
		_cliff_nodes.erase(chunk)
	_loaded.erase(chunk)


func _chunk_in_bounds(chunk: Vector2i) -> bool:
	var count: int = WORLD_SIZE / CHUNK_SIZE
	return chunk.x >= 0 and chunk.y >= 0 and chunk.x < count and chunk.y < count


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < WORLD_SIZE and cell.y < WORLD_SIZE


func _build_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TileGrid.TILE_SIZE, TileGrid.TILE_SIZE)
	tile_set.tile_shape = TileSet.TILE_SHAPE_SQUARE

	var source := TileSetAtlasSource.new()
	source.texture = _build_atlas_texture()
	source.texture_region_size = Vector2i(TileGrid.TILE_SIZE, TileGrid.TILE_SIZE)
	for index in 3:
		source.create_tile(Vector2i(index, 0))
	tile_set.add_source(source, 0)
	return tile_set


func _build_atlas_texture() -> ImageTexture:
	var colors: Array[Color] = [
		Color("#1f3b4d"),
		Color("#3d5c46"),
		Color("#4a4a45"),
	]
	var atlas := Image.create(
		TileGrid.TILE_SIZE * colors.size(),
		TileGrid.TILE_SIZE,
		false,
		Image.FORMAT_RGBA8
	)
	atlas.fill(Color(0.0, 0.0, 0.0, 0.0))

	for index in colors.size():
		var base: Color = colors[index]
		var edge: Color = base.darkened(0.28)
		var offset_x: int = index * TileGrid.TILE_SIZE
		for y in TileGrid.TILE_SIZE:
			for x in TileGrid.TILE_SIZE:
				var color: Color = base
				if (
					x < 2
					or y < 2
					or x >= TileGrid.TILE_SIZE - 2
					or y >= TileGrid.TILE_SIZE - 2
				):
					color = edge
				atlas.set_pixel(offset_x + x, y, color)
	return ImageTexture.create_from_image(atlas)
