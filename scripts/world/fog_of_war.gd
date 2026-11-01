class_name FogOfWar
extends Node2D
## Per-cell fog of war: HIDDEN / EXPLORED / VISIBLE.
##
## One 512x512 texture is stretched over the region; each pixel is one cell.
## Visibility is recomputed around the focus at 10 Hz, with height/rock
## occlusion. Explored cells stay dim; hidden cells are black.

const STATE_HIDDEN: int = 0
const STATE_EXPLORED: int = 1
const STATE_VISIBLE: int = 2

const VISION_RADIUS: int = 10
const UPDATE_INTERVAL: float = 0.1

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


func setup(world_ref: ReolWorld, start_cell: Vector2i) -> void:
	world = world_ref
	_focus_cell = start_cell
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
	_focus_cell = cell


func _process(delta: float) -> void:
	if not _active:
		return
	_accumulator += delta
	if _accumulator < UPDATE_INTERVAL:
		return
	_accumulator = 0.0
	update_now()


func update_now() -> void:
	if world == null or _image == null:
		return

	_clear_visible()
	var origin_elevation: int = world.get_elevation(_focus_cell)
	for dy in range(-VISION_RADIUS, VISION_RADIUS + 1):
		for dx in range(-VISION_RADIUS, VISION_RADIUS + 1):
			if dx * dx + dy * dy > VISION_RADIUS * VISION_RADIUS:
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

		var cell := Vector2i(x0, y0)
		if world.get_terrain(cell) == ReolWorld.TERRAIN_ROCK:
			return false
		if world.get_elevation(cell) > from_elevation:
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
