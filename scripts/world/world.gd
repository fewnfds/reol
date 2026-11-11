class_name ReolWorld
extends Node2D
signal terrain_changed(cells: Array[Vector2i])
signal sight_obstacles_changed(cells: Array[Vector2i])
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
var flora_override: Callable
var _tile_set: TileSet
var _map_data: WorldMapData
var _geometry_reader: SimWorldGeometry
var _loaded: Dictionary[Vector2i, bool] = {}
var _cliff_nodes: Dictionary[Vector2i, CliffChunk] = {}
var _pending_load: Array[Vector2i] = []
var _pending_unload: Array[Vector2i] = []
var _focus_chunk: Vector2i = Vector2i(-9999, -9999)
var _initialized: bool = false
var _obstacles: Callable
var _navigation_revision_provider: Callable
var _cached_navigation_revision: int = -1
var _walkability_cache: Dictionary[Vector2i, bool] = {}
var _navigation_paths: Dictionary[String, Array] = {}
const NAVIGATION_PATH_CACHE_LIMIT: int = 1024
var _sight_obstacles: Callable
var _painting_chunk: Vector2i = Vector2i(-1, -1)
var _painting_offset: int = 0
const PAINT_CELLS_PER_FRAME: int = 256
var _view_rect: Rect2i = Rect2i()
var _priority_cells: Array[Vector2i] = []
var _priority_index: int = 0
# Previewed cells belong to an incomplete chunk until its normal scan finishes.
# Keeping that ownership allows cancellation/unload to erase out-of-order cells.
var _preview_chunks: Dictionary[Vector2i, Dictionary] = {}
var _dirty_cells: Dictionary[Vector2i, bool] = {}
var _dirty_order: Array[Vector2i] = []
var _dirty_cursor: int = 0
var presentation_work: ReolPresentationWork


static func generation_descriptor() -> Dictionary:
	# Changing terrain/height generation requires an explicit version/migration.
	return WorldMapData.generation_descriptor()


func map_data() -> WorldMapData:
	if _map_data == null:
		_map_data = WorldMapData.new()
		_map_data.terrain_changed.connect(_on_terrain_changed)
	return _map_data


func bind_map_data(data: WorldMapData) -> void:
	if data == null or data == _map_data:
		return
	if _map_data != null and _map_data.terrain_changed.is_connected(_on_terrain_changed):
		_map_data.terrain_changed.disconnect(_on_terrain_changed)
	_map_data = data
	if is_instance_valid(presentation_work):
		presentation_work.cancel(&"terrain_prepaint")
	invalidate_navigation()
	_map_data.terrain_changed.connect(_on_terrain_changed)
	_dirty_cells.clear()
	_dirty_order.clear()
	_dirty_cursor = 0
	# A new accepted session may eventually contain different surface deltas.
	# Clear every elevation layer, rather than erasing by the new map's height.
	for layer: TileMapLayer in _layers:
		layer.clear()
	for layer: TileMapLayer in _flora_layers:
		layer.clear()
	_painting_chunk = Vector2i(-1, -1)
	_painting_offset = 0
	_reset_view_priority()
	_preview_chunks.clear()
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
	var remaining: int = PAINT_CELLS_PER_FRAME - _paint_dirty(PAINT_CELLS_PER_FRAME)
	remaining -= _paint_priority(remaining)
	if remaining == 0 or (_painting_chunk.x < 0 and _pending_load.is_empty()):
		if is_instance_valid(presentation_work):
			presentation_work.cancel(&"terrain_prepaint")
		return
	if is_instance_valid(presentation_work):
		presentation_work.request(&"terrain_prepaint", _paint_background.bind(remaining), ReolPresentationWork.Priority.BACKGROUND, 500)
	else:
		_paint_background(remaining)


func _paint_background(remaining: int) -> bool:
	if _painting_chunk.x < 0 and not _pending_load.is_empty():
		_painting_chunk = _pending_load.pop_front()
		_painting_offset = 0
	if _painting_chunk.x >= 0:
		_paint_batch(remaining)
	return true


func _on_terrain_changed(cells: Array[Vector2i]) -> void:
	invalidate_navigation(cells)
	# Rules change immediately. Only already drawn cells need repainting; other
	# cells will read current facts when their streamed chunk is first painted.
	if _initialized:
		for cell: Vector2i in cells:
			if not _dirty_cells.has(cell) and _cell_is_drawn(cell):
				_dirty_cells[cell] = true
				_dirty_order.append(cell)
	terrain_changed.emit(cells.duplicate())


func _paint_dirty(budget: int) -> int:
	var used: int = 0
	while _dirty_cursor < _dirty_order.size() and used < budget:
		var cell: Vector2i = _dirty_order[_dirty_cursor]
		_dirty_cursor += 1
		_dirty_cells.erase(cell)
		# A queued cell may have unloaded before this rendering budget runs.
		if _cell_is_drawn(cell):
			_paint_cell(cell)
		used += 1
	if _dirty_cursor == _dirty_order.size():
		_dirty_order.clear()
		_dirty_cursor = 0
	elif _dirty_cursor >= PAINT_CELLS_PER_FRAME and _dirty_cursor * 2 >= _dirty_order.size():
		# A continuous backlog may never drain. Copy only after consuming at
		# least as many entries as remain, amortizing the retained suffix copy.
		_dirty_order = _dirty_order.slice(_dirty_cursor)
		_dirty_cursor = 0
	return used


func prioritize_view(rect: Rect2i) -> void:
	var bounds: Rect2i = _view_bounds(rect)
	if bounds == _view_rect:
		return
	_view_rect = bounds
	_priority_cells.clear()
	_priority_index = 0
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			if not _cell_is_drawn(cell):
				_priority_cells.append(cell)
			elif _painting_chunk.x >= 0 and not _preview_chunks.has(_painting_chunk):
				var chunk := Vector2i(floori(float(cell.x) / CHUNK_SIZE), floori(float(cell.y) / CHUNK_SIZE))
				if chunk == _painting_chunk:
					_remember_preview_chunk(chunk)
					_ensure_cliff_chunk(chunk)
	var center: Vector2i = bounds.get_center()
	_priority_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_distance: int = (a - center).length_squared()
		var b_distance: int = (b - center).length_squared()
		if a_distance != b_distance:
			return a_distance < b_distance
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)


func is_view_ready(rect: Rect2i) -> bool:
	var bounds: Rect2i = _view_bounds(rect)
	var in_world: Rect2i = rect.intersection(Rect2i(Vector2i.ZERO, Vector2i.ONE * WORLD_SIZE))
	if not bounds.has_area() or bounds != in_world:
		return false
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			if not _cell_is_drawn(Vector2i(x, y)):
				return false
	return true


func _view_bounds(rect: Rect2i) -> Rect2i:
	if not _initialized or _focus_chunk.x < 0 or not rect.has_area():
		return Rect2i()
	var loaded_area := Rect2i((_focus_chunk - Vector2i.ONE * LOAD_RADIUS) * CHUNK_SIZE,
		Vector2i.ONE * (LOAD_RADIUS * 2 + 1) * CHUNK_SIZE)
	return rect.intersection(Rect2i(Vector2i.ZERO, Vector2i.ONE * WORLD_SIZE)).intersection(loaded_area)


func _reset_view_priority() -> void:
	_view_rect = Rect2i()
	_priority_cells.clear()
	_priority_index = 0


func _cell_is_drawn(cell: Vector2i) -> bool:
	return _layers[get_elevation(cell)].get_cell_source_id(cell) >= 0


func _paint_priority(budget: int) -> int:
	var painted: int = 0
	var touched: Dictionary[Vector2i, bool] = {}
	while _priority_index < _priority_cells.size() and painted < budget:
		var cell: Vector2i = _priority_cells[_priority_index]
		_priority_index += 1
		if _cell_is_drawn(cell):
			continue
		var chunk := Vector2i(floori(float(cell.x) / CHUNK_SIZE), floori(float(cell.y) / CHUNK_SIZE))
		_remember_preview_chunk(chunk)
		_preview_chunks[chunk][cell] = true
		_paint_cell(cell)
		touched[chunk] = true
		painted += 1
	for chunk: Vector2i in touched:
		_ensure_cliff_chunk(chunk)
	return painted


func _remember_preview_chunk(chunk: Vector2i) -> void:
	if _preview_chunks.has(chunk):
		return
	_preview_chunks[chunk] = {}
	if chunk == _painting_chunk:
		var base: Vector2i = chunk * CHUNK_SIZE
		for index: int in _painting_offset:
			var cell := base + Vector2i(index % CHUNK_SIZE, floori(float(index) / CHUNK_SIZE))
			_preview_chunks[chunk][cell] = true


func get_terrain(cell: Vector2i) -> int:
	return map_data().get_terrain(cell)


func get_elevation(cell: Vector2i) -> int:
	return map_data().get_elevation(cell)


func is_walkable(cell: Vector2i) -> bool:
	if _geometry_reader != null:
		return _geometry_reader.is_walkable(cell)
	var reusable: bool = _refresh_navigation_cache()
	var revision: int = _cached_navigation_revision
	if reusable and _walkability_cache.has(cell):
		return _walkability_cache[cell]
	var walkable: bool = terrain_is_walkable(cell) and (not _obstacles.is_valid() or not bool(_obstacles.call(cell)))
	if reusable and _navigation_revision_provider.is_valid() and int(_navigation_revision_provider.call()) == revision:
		_walkability_cache[cell] = walkable
	return walkable


func set_obstacle_provider(provider: Callable, revision_provider: Callable = Callable()) -> void:
	# Opt in only when all terrain/clearance dependencies are observable. Opaque
	# callbacks remain live on every query, including standalone callers.
	_geometry_reader = null
	_obstacles = provider
	_navigation_revision_provider = revision_provider
	invalidate_navigation()


func bind_geometry(reader: SimWorldGeometry, revision_provider: Callable) -> void:
	_geometry_reader = reader
	_obstacles = Callable()
	_navigation_revision_provider = revision_provider
	invalidate_navigation()


func invalidate_navigation(cells: Array[Vector2i] = [], previous_revision: int = -1) -> void:
	# A local edit may open a better route outside a cached path. Clear paths,
	# but retain unaffected point queries when the owner supplies exact cells.
	_navigation_paths.clear()
	var revision: int = int(_navigation_revision_provider.call()) if _navigation_revision_provider.is_valid() else -1
	if cells.is_empty() or (revision != _cached_navigation_revision and previous_revision != _cached_navigation_revision):
		_walkability_cache.clear()
	else:
		for cell: Vector2i in cells:
			_walkability_cache.erase(cell)
	_cached_navigation_revision = revision


func _refresh_navigation_cache() -> bool:
	if not _navigation_revision_provider.is_valid():
		return false
	if int(_navigation_revision_provider.call()) != _cached_navigation_revision:
		invalidate_navigation()
	return true


func find_grid_path(from: Vector2i, to: Vector2i, radius: int, budget: int) -> Array[Vector2i]:
	if _geometry_reader != null:
		return _geometry_reader.find_path(from, to, radius, budget)
	var reusable: bool = _refresh_navigation_cache()
	var revision: int = _cached_navigation_revision
	var key: String = "%s:%s:%d:%d" % [from, to, radius, budget]
	if reusable and _navigation_paths.has(key):
		return _navigation_paths[key].duplicate()
	var path: Array[Vector2i] = SimGridNavigation.find_path(from, to, is_walkable, can_step, radius, budget)
	if reusable and _navigation_revision_provider.is_valid() and int(_navigation_revision_provider.call()) == revision:
		if _navigation_paths.size() >= NAVIGATION_PATH_CACHE_LIMIT:
			_navigation_paths.clear()
		_navigation_paths[key] = path.duplicate()
	return path


func set_sight_obstacle_provider(provider: Callable) -> void:
	_sight_obstacles = provider
	var changed: Array[Vector2i] = []
	sight_obstacles_changed.emit(changed)


func is_sight_blocked(cell: Vector2i) -> bool:
	return _sight_obstacles.is_valid() and bool(_sight_obstacles.call(cell))


func notify_sight_obstacles_changed(cells: Array[Vector2i]) -> void:
	sight_obstacles_changed.emit(cells.duplicate())


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
	if _geometry_reader != null:
		return _geometry_reader.can_step(from_cell, step)
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
	_reset_view_priority()
	if _painting_chunk.x >= 0 and (absi(_painting_chunk.x - _focus_chunk.x) > UNLOAD_RADIUS or absi(_painting_chunk.y - _focus_chunk.y) > UNLOAD_RADIUS):
		_cancel_painting()
	for chunk: Vector2i in _preview_chunks.keys():
		if absi(chunk.x - _focus_chunk.x) > UNLOAD_RADIUS or absi(chunk.y - _focus_chunk.y) > UNLOAD_RADIUS:
			_clear_preview_chunk(chunk)
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


@warning_ignore("integer_division")
func _cancel_painting() -> void:
	var abandoned: Vector2i = _painting_chunk
	var base: Vector2i = _painting_chunk * CHUNK_SIZE
	for index: int in _painting_offset:
		var cell: Vector2i = base + Vector2i(index % CHUNK_SIZE, index / CHUNK_SIZE)
		for layer: TileMapLayer in _layers:
			layer.erase_cell(cell)
		for layer: TileMapLayer in _flora_layers:
			layer.erase_cell(cell)
	_clear_preview_chunk(_painting_chunk)
	_painting_chunk = Vector2i(-1, -1)
	_painting_offset = 0
	_reset_view_priority()
	if absi(abandoned.x - _focus_chunk.x) <= LOAD_RADIUS and absi(abandoned.y - _focus_chunk.y) <= LOAD_RADIUS and not _pending_load.has(abandoned):
		_pending_load.append(abandoned)


@warning_ignore("integer_division")
func _paint_batch(budget: int) -> void:
	var chunk: Vector2i = _painting_chunk
	var base: Vector2i = chunk * CHUNK_SIZE
	var stop: int = mini(CHUNK_SIZE * CHUNK_SIZE, _painting_offset + budget)
	for index: int in range(_painting_offset, stop):
		var cell: Vector2i = base + Vector2i(index % CHUNK_SIZE, index / CHUNK_SIZE)
		if not _cell_is_drawn(cell):
			_paint_cell(cell)
		if _preview_chunks.has(chunk):
			_preview_chunks[chunk][cell] = true
	_painting_offset = stop
	if stop < CHUNK_SIZE * CHUNK_SIZE:
		if _preview_chunks.has(chunk):
			_ensure_cliff_chunk(chunk)
		return
	_painting_chunk = Vector2i(-1, -1)
	_painting_offset = 0
	_preview_chunks.erase(chunk)
	_loaded[chunk] = true
	_ensure_cliff_chunk(chunk)


func _paint_cell(cell: Vector2i) -> void:
	var natural: Dictionary = map_data().natural_cell(cell)
	var elevation: int = get_elevation(cell)
	var surface: int = NaturalEnvironment.SURFACES.find(str(natural.get("surface_id", "grassland")))
	_layers[elevation].set_cell(cell, 0, Vector2i(surface, Visuals.variant_for(cell)))
	_flora_layers[elevation].erase_cell(cell)
	var flora: Dictionary = natural.get("flora", {})
	if not flora.is_empty() and (not flora_override.is_valid() or not bool(flora_override.call(cell))):
		_flora_layers[elevation].set_cell(cell, 1, Vector2i(_flora_ids.find(flora.id), int(flora.variant)))


func _clear_preview_chunk(chunk: Vector2i) -> void:
	for cell: Vector2i in _preview_chunks.get(chunk, {}):
		for layer: TileMapLayer in _layers:
			layer.erase_cell(cell)
		for layer: TileMapLayer in _flora_layers:
			layer.erase_cell(cell)
	_preview_chunks.erase(chunk)
	if _cliff_nodes.has(chunk):
		_cliff_nodes[chunk].queue_free()
		_cliff_nodes.erase(chunk)


func _ensure_cliff_chunk(chunk: Vector2i) -> void:
	if _cliff_nodes.has(chunk):
		var existing: CliffChunk = _cliff_nodes[chunk]
		existing.complete = _loaded.has(chunk)
		existing.partial_cells = _preview_chunks.get(chunk, {})
		existing.queue_redraw()
		return

	var cliff := CliffChunk.new()
	cliff.world = self
	cliff.chunk = chunk
	cliff.chunk_size = CHUNK_SIZE
	cliff.tile_size = TileGrid.TILE_SIZE
	cliff.elevation_px = ELEVATION_PX
	cliff.complete = _loaded.has(chunk)
	cliff.partial_cells = _preview_chunks.get(chunk, {})
	cliff.position = Vector2(chunk * CHUNK_SIZE * TileGrid.TILE_SIZE)
	cliff.z_index = 5
	add_child(cliff)
	_cliff_nodes[chunk] = cliff


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


func refresh_flora(cell: Vector2i) -> void:
	if _initialized and not _layers.is_empty() and _cell_is_drawn(cell):
		_paint_cell(cell)
