class_name FogOfWar
extends Node2D
signal visibility_updated
## Per-cell fog of war: HIDDEN / EXPLORED / VISIBLE.
##
## One 512x512 texture is stretched over the region; each pixel is one cell.
## Visibility is recomputed around the focus at 10 Hz, with height/rock
## occlusion. Explored cells stay dim; hidden cells are black.

const STATE_HIDDEN: int = 0
const STATE_EXPLORED: int = 1
const STATE_VISIBLE: int = 2
const EXPLORATION_ENCODING: String = "explored_runs_v1"

const VISION_RADIUS: int = 10
const UPDATE_INTERVAL: float = 0.1
const OCCLUSION_WIDTH: int = VISION_RADIUS * 2 + 1

const COLOR_HIDDEN := Color(0.0, 0.0, 0.0, 1.0)
const COLOR_EXPLORED := Color(0.0, 0.0, 0.0, 0.62)
const COLOR_VISIBLE := Color(0.0, 0.0, 0.0, 0.0)

var world: ReolWorld
var _focus_cell: Vector2i = Vector2i.ZERO
var _states := PackedByteArray()
var _visible_cells: Array[Vector2i] = []
var _image: Image
var _texture: ImageTexture
var _sprite: Sprite2D
var _accumulator: float = 0.0
var _active: bool = false
var _visibility_dirty: bool = true
var _observer_altitude: int = 0
var _observer_radius: int = VISION_RADIUS
var _projection_guard: Callable
var _ray_obstructions := PackedByteArray()


func set_projection_guard(guard: Callable) -> void:
	_projection_guard = guard


func setup(world_ref: ReolWorld, start_cell: Vector2i) -> void:
	if world != null:
		if world.terrain_changed.is_connected(_on_terrain_changed):
			world.terrain_changed.disconnect(_on_terrain_changed)
		if world.sight_obstacles_changed.is_connected(_on_sight_obstacles_changed):
			world.sight_obstacles_changed.disconnect(_on_sight_obstacles_changed)
	world = world_ref
	if not world.terrain_changed.is_connected(_on_terrain_changed):
		world.terrain_changed.connect(_on_terrain_changed)
	world.sight_obstacles_changed.connect(_on_sight_obstacles_changed)
	_focus_cell = start_cell
	_visibility_dirty = true
	_states.resize(ReolWorld.WORLD_SIZE * ReolWorld.WORLD_SIZE)
	_states.fill(STATE_HIDDEN)

	_image = Image.create(
		ReolWorld.WORLD_SIZE,
		ReolWorld.WORLD_SIZE,
		false,
		Image.FORMAT_RGBA8
	)
	_image.fill(COLOR_HIDDEN)
	_texture = ImageTexture.create_from_image(_image)

	_sprite = Sprite2D.new()
	_sprite.texture = _texture
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sprite.scale = Vector2(float(TileGrid.TILE_SIZE), float(TileGrid.TILE_SIZE))
	_sprite.position = Vector2.ZERO
	add_child(_sprite)

	z_index = 8
	_active = true
	update_now()


func set_focus(cell: Vector2i) -> void:
	if _focus_cell == cell:
		return
	_focus_cell = cell
	_visibility_dirty = true


func set_observer(altitude: int, radius: int) -> void:
	altitude = clampi(altitude, 0, 2)
	radius = clampi(radius, 1, VISION_RADIUS)
	if altitude != _observer_altitude or radius != _observer_radius:
		_observer_altitude = altitude
		_observer_radius = radius
		_visibility_dirty = true


func invalidate_visibility() -> void:
	# Future terrain/occluder edits can invalidate a stationary observer explicitly.
	_visibility_dirty = true


func _on_terrain_changed(_cells: Array[Vector2i]) -> void:
	invalidate_visibility()


func _on_sight_obstacles_changed(cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		invalidate_visibility()
		return
	for cell: Vector2i in cells:
		if (cell - _focus_cell).length_squared() <= _observer_radius * _observer_radius:
			invalidate_visibility()
			return


func _process(delta: float) -> void:
	if not _active:
		return
	_accumulator += delta
	if _accumulator < UPDATE_INTERVAL or not _visibility_dirty:
		return
	_accumulator = 0.0
	update_now()


func update_now() -> void:
	if world == null or _image == null:
		return
	if _projection_guard.is_valid() and not bool(_projection_guard.call()):
		return # Keep both the last image and the dirty request until commit.
	_visibility_dirty = false

	_clear_visible()
	var origin_elevation: int = world.get_elevation(_focus_cell) + _observer_altitude
	# Rays share intermediate cells. Query the original world once per cell for
	# this observer/elevation only; the next update discards the whole scratchpad.
	_ray_obstructions.resize(OCCLUSION_WIDTH * OCCLUSION_WIDTH)
	_ray_obstructions.fill(0)
	for dy in range(-_observer_radius, _observer_radius + 1):
		for dx in range(-_observer_radius, _observer_radius + 1):
			if dx * dx + dy * dy > _observer_radius * _observer_radius:
				continue
			var cell := _focus_cell + Vector2i(dx, dy)
			if not _in_bounds(cell):
				continue
			if not _has_line_of_sight(_focus_cell, cell, origin_elevation):
				continue
			var index: int = _index(cell)
			_states[index] = STATE_VISIBLE
			_image.set_pixel(cell.x, cell.y, COLOR_VISIBLE)
			_visible_cells.append(cell)

	_texture.update(_image)
	visibility_updated.emit()


func is_cell_visible(cell: Vector2i) -> bool:
	if not _in_bounds(cell) or _states.is_empty():
		return false
	return _states[_index(cell)] == STATE_VISIBLE


func is_explored(cell: Vector2i) -> bool:
	if not _in_bounds(cell) or _states.is_empty():
		return false
	return _states[_index(cell)] != STATE_HIDDEN


func get_state(cell: Vector2i) -> int:
	if not _in_bounds(cell) or _states.is_empty():
		return STATE_HIDDEN
	return _states[_index(cell)]


static func empty_exploration() -> Dictionary:
	return {"encoding": EXPLORATION_ENCODING, "runs": []}


func exploration_to_dict() -> Dictionary:
	# Persist memory only. Current visibility is derived from the restored focus.
	var runs: Array = []
	var start: int = -1
	for index in _states.size():
		if _states[index] != STATE_HIDDEN:
			if start < 0:
				start = index
		elif start >= 0:
			runs.append([start, index - start])
			start = -1
	if start >= 0:
		runs.append([start, _states.size() - start])
	return {"encoding": EXPLORATION_ENCODING, "runs": runs}


static func is_valid_exploration(data: Variant) -> bool:
	if not data is Dictionary or data.size() != 2 or data.get("encoding") != EXPLORATION_ENCODING or not data.get("runs") is Array:
		return false
	var size: int = ReolWorld.WORLD_SIZE * ReolWorld.WORLD_SIZE
	if data.runs.size() > size:
		return false
	var previous_end: int = -1
	for run: Variant in data.runs:
		if not run is Array or run.size() != 2:
			return false
		for component: Variant in run:
			if not (component is int or component is float) or not is_finite(float(component)):
				return false
			if float(component) < 0.0 or float(component) > size or float(component) != floorf(float(component)):
				return false
		var start: int = int(run[0])
		var length: int = int(run[1])
		# Sorted, separated runs form one canonical, bounded representation.
		if length < 1 or start <= previous_end or start + length > size:
			return false
		previous_end = start + length
	return true


func restore_exploration(data: Dictionary, focus: Vector2i) -> bool:
	if not _active or not is_valid_exploration(data) or not _in_bounds(focus):
		return false
	_states.fill(STATE_HIDDEN)
	_visible_cells.clear()
	_image.fill(COLOR_HIDDEN)
	for run: Array in data.runs:
		for index in range(int(run[0]), int(run[0]) + int(run[1])):
			_states[index] = STATE_EXPLORED
			var y: int = floori(float(index) / ReolWorld.WORLD_SIZE)
			_image.set_pixel(index % ReolWorld.WORLD_SIZE, y, COLOR_EXPLORED)
	_focus_cell = focus
	_accumulator = 0.0
	update_now()
	return true


func _clear_visible() -> void:
	for cell in _visible_cells:
		if not _in_bounds(cell):
			continue
		var index: int = _index(cell)
		_states[index] = STATE_EXPLORED
		_image.set_pixel(cell.x, cell.y, COLOR_EXPLORED)
	_visible_cells.clear()


func _has_line_of_sight(
	from_cell: Vector2i, to_cell: Vector2i, from_elevation: int
) -> bool:
	var x0: int = from_cell.x
	var y0: int = from_cell.y
	var x1: int = to_cell.x
	var y1: int = to_cell.y
	var dx: int = absi(x1 - x0)
	var sx: int = 1 if x0 < x1 else -1
	var dy: int = -absi(y1 - y0)
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy

	while true:
		if x0 == x1 and y0 == y1:
			return true
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
		if x0 == x1 and y0 == y1:
			return true

		var index: int = (y0 - from_cell.y + VISION_RADIUS) * OCCLUSION_WIDTH + x0 - from_cell.x + VISION_RADIUS
		var obstruction: int = _ray_obstructions[index]
		if obstruction == 0:
			var cell := Vector2i(x0, y0)
			var blocked: bool = (
				world.get_terrain(cell) == ReolWorld.TERRAIN_ROCK
				or world.is_sight_blocked(cell)
				or world.get_elevation(cell) > from_elevation
			)
			obstruction = 2 if blocked else 1
			_ray_obstructions[index] = obstruction
		if obstruction == 2:
			return false

	return false


func _index(cell: Vector2i) -> int:
	return cell.y * ReolWorld.WORLD_SIZE + cell.x


func _in_bounds(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < ReolWorld.WORLD_SIZE
		and cell.y < ReolWorld.WORLD_SIZE
	)
