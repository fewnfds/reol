class_name ReolWorld
extends Node2D
## Chunked 2D orthographic top-down world.
##
## v0.1 slice: one generated region (512x512), 64x64 chunks, 5x5 loaded.
## Height is data-only for now; visual elevation and fog arrive in the next slice.

const WORLD_SIZE: int = 512
const CHUNK_SIZE: int = 64
const LOAD_RADIUS: int = 2
const UNLOAD_RADIUS: int = 3
const WORLD_SEED: int = 20261101

const TILE_WATER: int = 0
const TILE_LOW_GRASS: int = 1
const TILE_GRASS: int = 2
const TILE_ROCK: int = 3

var _layer: TileMapLayer
var _noise: FastNoiseLite
var _loaded: Dictionary[Vector2i, bool] = {}
var _pending_load: Array[Vector2i] = []
var _pending_unload: Array[Vector2i] = []
var _focus_chunk: Vector2i = Vector2i(-9999, -9999)


func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = WORLD_SEED
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.018
	_noise.fractal_octaves = 3

	_layer = TileMapLayer.new()
	_layer.name = "Ground"
	_layer.tile_set = _build_tile_set()
	_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_layer)


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


func get_elevation(cell: Vector2i) -> int:
	if not _in_bounds(cell):
		return -1
	var n: float = _noise.get_noise_2d(float(cell.x), float(cell.y))
	if n < -0.42:
		return TILE_WATER
	if n < -0.05:
		return TILE_LOW_GRASS
	if n < 0.38:
		return TILE_GRASS
	return TILE_ROCK


func is_walkable(cell: Vector2i) -> bool:
	var elevation: int = get_elevation(cell)
	return elevation == TILE_LOW_GRASS or elevation == TILE_GRASS


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
			var elevation: int = get_elevation(cell)
			_layer.set_cell(cell, 0, Vector2i(elevation, 0))
	_loaded[chunk] = true


func _unload_chunk(chunk: Vector2i) -> void:
	var base := chunk * CHUNK_SIZE
	for local_y in range(CHUNK_SIZE):
		for local_x in range(CHUNK_SIZE):
			_layer.erase_cell(base + Vector2i(local_x, local_y))
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
	for index in 4:
		source.create_tile(Vector2i(index, 0))
	tile_set.add_source(source, 0)
	return tile_set


func _build_atlas_texture() -> ImageTexture:
	var colors: Array[Color] = [
		Color("#1f3b4d"),
		Color("#2f4a3a"),
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
