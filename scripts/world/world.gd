class_name ReolWorld
extends Node2D
## Chunked 2D orthographic top-down world with a simple elevation layer.
##
## v0.1 slice: one generated region (512x512), 64x64 chunks, 5x5 loaded.
## Terrain type and elevation are separate: grass/water/rock + height 0..3.
## Each elevation is rendered on its own TileMapLayer shifted up by ELEVATION_PX;
## south-facing drops get a cliff face. Presentation does not alter terrain rules.

const Visuals = preload("res://scripts/world/terrain_visuals.gd")

const WORLD_SIZE: int = WorldMapData.WORLD_SIZE
const CHUNK_SIZE: int = 64
const LOAD_RADIUS: int = 2
const UNLOAD_RADIUS: int = 3
const WORLD_SEED: int = WorldMapData.WORLD_SEED
const GENERATOR_ID: String = WorldMapData.GENERATOR_ID
const GENERATOR_VERSION: int = WorldMapData.GENERATOR_VERSION
const ELEVATION_LEVELS: int = WorldMapData.ELEVATION_LEVELS
const ELEVATION_PX: int = 16
const ALTITUDE_PX: int = 28

const TERRAIN_WATER: int = WorldMapData.TERRAIN_WATER
const TERRAIN_GRASS: int = WorldMapData.TERRAIN_GRASS
const TERRAIN_ROCK: int = WorldMapData.TERRAIN_ROCK

var _layers: Array[TileMapLayer] = []
var _flora_layers: Array[TileMapLayer] = []
var _flora_ids: Array = []
var _tile_set: TileSet
var _map_data: WorldMapData
var _loaded: Dictionary[Vector2i, bool] = {}
var _cliff_nodes: Dictionary[Vector2i, CliffChunk] = {}
var _pending_load: Array[Vector2i] = []
var _pending_unload: Array[Vector2i] = []
var _focus_chunk: Vector2i = Vector2i(-9999, -9999)
var _initialized: bool = false
var _obstacles: Callable
var _painting_chunk: Vector2i = Vector2i(-1, -1)
var _painting_offset: int = 0
const PAINT_CELLS_PER_FRAME: int = 256


static func generation_descriptor() -> Dictionary:
	# Changing terrain/height generation requires an explicit version/migration.
	return WorldMapData.generation_descriptor()


func map_data() -> WorldMapData:
	if _map_data == null:
		_map_data = WorldMapData.new()
	return _map_data


func bind_map_data(data: WorldMapData) -> void:
	if data == null or data == _map_data:
		return
	_map_data = data
	# A new accepted session may eventually contain different surface deltas.
	# Clear every elevation layer, rather than erasing by the new map's height.
	for layer: TileMapLayer in _layers:
		layer.clear()
	for layer: TileMapLayer in _flora_layers:
		layer.clear()
	_painting_chunk = Vector2i(-1, -1)
	_painting_offset = 0
	for cliff: CliffChunk in _cliff_nodes.values():
		cliff.queue_free()
	_cliff_nodes.clear()
	_loaded.clear()
	_pending_load.clear()
	_pending_unload.clear()
	if _initialized and _focus_chunk != Vector2i(-9999, -9999):
		_rebuild_queues()


func _ready() -> void:
	initialize()


func initialize() -> void:
	if _initialized:
		return
	map_data()
	if map_data().natural_surface_definitions().is_empty():
		push_error("World: natural environment definitions are missing or invalid")
		set_process(false)
		return
	_initialized = true

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
		var cover := TileMapLayer.new()
		cover.name = "Vegetation%d" % level
		cover.tile_set = _tile_set
		cover.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		cover.position = layer.position
		cover.modulate = layer.modulate
		add_child(cover)
		_flora_layers.append(cover)


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
	if _painting_chunk.x < 0 and not _pending_load.is_empty():
		_painting_chunk = _pending_load.pop_front()
		_painting_offset = 0
	if _painting_chunk.x >= 0:
		_paint_batch(PAINT_CELLS_PER_FRAME)


func get_terrain(cell: Vector2i) -> int:
	return map_data().get_terrain(cell)


func get_elevation(cell: Vector2i) -> int:
	return map_data().get_elevation(cell)


func is_walkable(cell: Vector2i) -> bool:
	return terrain_is_walkable(cell) and (not _obstacles.is_valid() or not bool(_obstacles.call(cell)))


func set_obstacle_provider(provider: Callable) -> void:
	_obstacles = provider


func terrain_is_walkable(cell: Vector2i) -> bool:
	return map_data().terrain_is_walkable(cell)


func terrain_can_step(from_cell: Vector2i, step: Vector2i) -> bool:
	if step == Vector2i.ZERO:
		return true
	if not _terrain_can_move(from_cell, from_cell + step):
		return false
	return diagonal_step_allowed(step, _terrain_can_move(from_cell, from_cell + Vector2i(step.x, 0)), _terrain_can_move(from_cell, from_cell + Vector2i(0, step.y)))


func _terrain_can_move(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	return terrain_is_walkable(to_cell) and elevation_step_allowed(get_elevation(from_cell), get_elevation(to_cell))


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
	return WorldMapData.diagonal_step_allowed(step, x_open, y_open)


static func elevation_step_allowed(from_elevation: int, to_elevation: int) -> bool:
	return WorldMapData.elevation_step_allowed(from_elevation, to_elevation)


func terrain_name(cell: Vector2i) -> String:
	return str(map_data().natural_cell(cell).get("label", "?"))


func find_spawn_cell() -> Vector2i:
	var center := Vector2i(WORLD_SIZE >> 1, WORLD_SIZE >> 1)
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
	if _painting_chunk.x >= 0 and (absi(_painting_chunk.x - _focus_chunk.x) > UNLOAD_RADIUS or absi(_painting_chunk.y - _focus_chunk.y) > UNLOAD_RADIUS):
		_cancel_painting()
	_pending_load.clear()
	for dy in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var chunk := _focus_chunk + Vector2i(dx, dy)
			if _chunk_in_bounds(chunk) and not _loaded.has(chunk) and chunk != _painting_chunk:
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
	# Explicit synchronous entry for tools/tests; normal streaming is budgeted.
	if _loaded.has(chunk):
		return
	if _painting_chunk.x >= 0:
		_cancel_painting()
	_pending_load.erase(chunk)
	_painting_chunk = chunk
	_painting_offset = 0
	_paint_batch(CHUNK_SIZE * CHUNK_SIZE)


@warning_ignore("integer_division")
func _cancel_painting() -> void:
	var base: Vector2i = _painting_chunk * CHUNK_SIZE
	for index: int in _painting_offset:
		var cell: Vector2i = base + Vector2i(index % CHUNK_SIZE, index / CHUNK_SIZE)
		for layer: TileMapLayer in _layers:
			layer.erase_cell(cell)
		for layer: TileMapLayer in _flora_layers:
			layer.erase_cell(cell)
	_painting_chunk = Vector2i(-1, -1)
	_painting_offset = 0


@warning_ignore("integer_division")
func _paint_batch(budget: int) -> void:
	var chunk: Vector2i = _painting_chunk
	var base: Vector2i = chunk * CHUNK_SIZE
	var stop: int = mini(CHUNK_SIZE * CHUNK_SIZE, _painting_offset + budget)
	for index: int in range(_painting_offset, stop):
		var cell: Vector2i = base + Vector2i(index % CHUNK_SIZE, index / CHUNK_SIZE)
		var natural: Dictionary = map_data().natural_cell(cell)
		var elevation: int = get_elevation(cell)
		var surface: int = NaturalEnvironment.SURFACES.find(str(natural.get("surface_id", "grassland")))
		_layers[elevation].set_cell(cell, 0, Vector2i(surface, Visuals.variant_for(cell)))
		var flora: Dictionary = natural.get("flora", {})
		if not flora.is_empty():
			_flora_layers[elevation].set_cell(cell, 1, Vector2i(_flora_ids.find(flora.id), int(flora.variant)))
	_painting_offset = stop
	if stop < CHUNK_SIZE * CHUNK_SIZE:
		return
	_painting_chunk = Vector2i(-1, -1)
	_painting_offset = 0

	var cliff := CliffChunk.new()
	cliff.world = self
	cliff.chunk = chunk
	cliff.chunk_size = CHUNK_SIZE
	cliff.tile_size = TileGrid.TILE_SIZE
	cliff.elevation_px = ELEVATION_PX
	cliff.position = Vector2(base * TileGrid.TILE_SIZE)
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
			_flora_layers[elevation].erase_cell(cell)

	var cliff: CliffChunk = _cliff_nodes.get(chunk)
	if cliff != null:
		cliff.queue_free()
		_cliff_nodes.erase(chunk)
	_loaded.erase(chunk)


func _chunk_in_bounds(chunk: Vector2i) -> bool:
	var count: int = floori(float(WORLD_SIZE) / float(CHUNK_SIZE))
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
	for index: int in NaturalEnvironment.SURFACES.size():
		for variant: int in Visuals.VARIANTS:
			source.create_tile(Vector2i(index, variant))
	tile_set.add_source(source, 0)
	var rules := NaturalEnvironment.new(WORLD_SEED)
	var plants: Dictionary = rules.flora_definitions()
	_flora_ids = plants.keys()
	_flora_ids.sort()
	var cover := TileSetAtlasSource.new()
	cover.texture = ImageTexture.create_from_image(Visuals.build_flora_image(TileGrid.TILE_SIZE, plants))
	cover.texture_region_size = source.texture_region_size
	for index: int in _flora_ids.size():
		for variant: int in Visuals.VARIANTS:
			cover.create_tile(Vector2i(index, variant))
	tile_set.add_source(cover, 1)
	return tile_set


func _build_atlas_texture() -> ImageTexture:
	return ImageTexture.create_from_image(Visuals.build_natural_image(TileGrid.TILE_SIZE, map_data().natural_surface_definitions()))
