extends RefCounted
## Frozen reol_noise v1 reference copied before the E3-b0 map extraction.
## This helper deliberately does not load ReolWorld or WorldMapData. Updating
## production generation must not silently update the compatibility reference.

const WORLD_SIZE: int = 512
const WORLD_SEED: int = 20261101
const ELEVATION_LEVELS: int = 4
const TERRAIN_WATER: int = 0
const TERRAIN_GRASS: int = 1
const TERRAIN_ROCK: int = 2

var _terrain: PackedByteArray = PackedByteArray()
var _elevation: PackedByteArray = PackedByteArray()


func _init() -> void:
	var terrain_noise := FastNoiseLite.new()
	terrain_noise.seed = WORLD_SEED
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	terrain_noise.frequency = 0.018
	terrain_noise.fractal_octaves = 3
	var height_noise := FastNoiseLite.new()
	height_noise.seed = WORLD_SEED + 1
	height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	height_noise.frequency = 0.012
	height_noise.fractal_octaves = 3
	_terrain.resize(WORLD_SIZE * WORLD_SIZE)
	_elevation.resize(WORLD_SIZE * WORLD_SIZE)
	# Cache only this frozen reference, so the full directed-neighbour sweep
	# does not spend most of the test resampling the same old noise values.
	for y: int in WORLD_SIZE:
		for x: int in WORLD_SIZE:
			var terrain_value: float = terrain_noise.get_noise_2d(float(x), float(y))
			var terrain: int = TERRAIN_GRASS
			if terrain_value < -0.45:
				terrain = TERRAIN_WATER
			elif terrain_value > 0.5:
				terrain = TERRAIN_ROCK
			var height: int = 0
			if terrain != TERRAIN_WATER:
				var height_value: float = height_noise.get_noise_2d(float(x), float(y))
				if height_value > 0.38:
					height = 3
				elif height_value > 0.08:
					height = 2
				elif height_value > -0.28:
					height = 1
				if terrain == TERRAIN_ROCK:
					height = maxi(height, 2)
			var index: int = y * WORLD_SIZE + x
			_terrain[index] = terrain
			_elevation[index] = mini(height, ELEVATION_LEVELS - 1)


static func generation_descriptor() -> Dictionary:
	return {"generator": "reol_noise", "generator_version": 1,
		"seed": WORLD_SEED, "size": WORLD_SIZE}


func get_terrain(cell: Vector2i) -> int:
	return int(_terrain[cell.y * WORLD_SIZE + cell.x]) if _in_bounds(cell) else -1


func get_elevation(cell: Vector2i) -> int:
	return int(_elevation[cell.y * WORLD_SIZE + cell.x]) if _in_bounds(cell) else -1


func terrain_is_walkable(cell: Vector2i) -> bool:
	return get_terrain(cell) == TERRAIN_GRASS


func terrain_can_step(from_cell: Vector2i, step: Vector2i) -> bool:
	if step == Vector2i.ZERO:
		return true
	if not _can_move(from_cell, from_cell + step):
		return false
	if step.x == 0 or step.y == 0:
		return true
	# Original permissive corner rule: one accessible orthogonal side is enough.
	return _can_move(from_cell, from_cell + Vector2i(step.x, 0)) or _can_move(from_cell, from_cell + Vector2i(0, step.y))


func _can_move(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	# The old query validates its destination, not that its origin is grass.
	return terrain_is_walkable(to_cell) and absi(get_elevation(from_cell) - get_elevation(to_cell)) <= 1


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < WORLD_SIZE and cell.y < WORLD_SIZE
