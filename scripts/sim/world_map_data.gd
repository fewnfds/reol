class_name WorldMapData
extends RefCounted
## Authoritative static map queries, independent of loaded/rendered chunks.
## Version-one generation is deliberately identical to the original ReolWorld.

const WORLD_SIZE: int = 512
const WORLD_SEED: int = 20261101
const GENERATOR_ID: String = "reol_noise"
const GENERATOR_VERSION: int = 1
const ELEVATION_LEVELS: int = 4
const TERRAIN_WATER: int = 0
const TERRAIN_GRASS: int = 1
const TERRAIN_ROCK: int = 2
const Nature = preload("res://scripts/sim/natural_environment.gd")

var _terrain_noise: FastNoiseLite
var _height_noise: FastNoiseLite
var _nature: RefCounted
var _nature_definitions: Dictionary = {}
var _generation: Dictionary
var _map_seed: int
var _map_size: int


func _init() -> void:
	# Keep this v1 instance independent of future default-generator constants.
	_generation = legacy_descriptor()
	_map_seed = int(_generation.seed)
	_map_size = int(_generation.size)
	_terrain_noise = FastNoiseLite.new()
	_terrain_noise.seed = _map_seed
	_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrain_noise.frequency = 0.018
	_terrain_noise.fractal_octaves = 3
	_height_noise = FastNoiseLite.new()
	_height_noise.seed = _map_seed + 1
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height_noise.frequency = 0.012
	_height_noise.fractal_octaves = 3


static func generation_descriptor() -> Dictionary:
	return {"generator": GENERATOR_ID, "generator_version": GENERATOR_VERSION,
		"seed": WORLD_SEED, "size": WORLD_SIZE}


static func legacy_descriptor() -> Dictionary:
	# Historical tuple, deliberately independent of the current default.
	return {"generator": "reol_noise", "generator_version": 1, "seed": 20261101, "size": 512}


static func valid_descriptor(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 4:
		return false
	for key: Variant in value:
		if not key is String or key not in ["generator", "generator_version", "seed", "size"]:
			return false
	if not value.get("generator") is String or value.generator != "reol_noise":
		return false
	var expected: Dictionary = legacy_descriptor()
	for key: String in ["generator_version", "seed", "size"]:
		if not SnapshotValues.valid_integer(value.get(key), 0) or value[key] != expected[key]:
			return false
	return true


static func from_descriptor(value: Variant) -> WorldMapData:
	if not valid_descriptor(value):
		return null
	return WorldMapData.new()


func descriptor() -> Dictionary:
	return _generation.duplicate(true)


func independent_copy() -> WorldMapData:
	# No mutable surface exists in v1. Reconstruct, never retain live callbacks.
	# Future delta restore belongs here before any candidate spatial validation.
	var result: WorldMapData = from_descriptor(_generation)
	if result == null:
		return null
	if not _nature_definitions.is_empty():
		if not result.configure_nature(_nature_definitions):
			return null
	return result


func configure_nature(rules: Dictionary) -> bool:
	if not Nature.valid_definitions(rules):
		return false
	_nature_definitions = rules.duplicate(true)
	_nature = Nature.new(_map_seed, _nature_definitions)
	return true


func natural_cell(cell: Vector2i) -> Dictionary:
	return _nature_rules().cell_at(self, cell)


func natural_surface(cell: Vector2i) -> String:
	return _nature_rules().surface_at(self, cell)


func natural_affinity(cell: Vector2i, element: String) -> int:
	return _nature_rules().affinity_at(self, cell, element)


func natural_growth_factor(cell: Vector2i) -> int:
	return _nature_rules().growth_factor_at(self, cell)


func natural_surface_definitions() -> Dictionary:
	return _nature_rules().surface_definitions()


func _nature_rules() -> RefCounted:
	if _nature == null:
		_nature = Nature.new(_map_seed, _nature_definitions)
	return _nature


func get_terrain(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return -1
	var n: float = _terrain_noise.get_noise_2d(float(cell.x), float(cell.y))
	if n < -0.45:
		return TERRAIN_WATER
	if n > 0.5:
		return TERRAIN_ROCK
	return TERRAIN_GRASS


func get_elevation(cell: Vector2i) -> int:
	if not in_bounds(cell):
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
	if terrain == TERRAIN_ROCK:
		elevation = maxi(elevation, 2)
	return mini(elevation, ELEVATION_LEVELS - 1)


func terrain_is_walkable(cell: Vector2i) -> bool:
	return get_terrain(cell) == TERRAIN_GRASS


func terrain_can_step(from_cell: Vector2i, step: Vector2i) -> bool:
	if step == Vector2i.ZERO:
		return true
	if not terrain_can_move(from_cell, from_cell + step):
		return false
	return diagonal_step_allowed(step,
		terrain_can_move(from_cell, from_cell + Vector2i(step.x, 0)),
		terrain_can_move(from_cell, from_cell + Vector2i(0, step.y)))


func terrain_can_move(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	return terrain_is_walkable(to_cell) and elevation_step_allowed(get_elevation(from_cell), get_elevation(to_cell))


static func diagonal_step_allowed(step: Vector2i, x_open: bool, y_open: bool) -> bool:
	return step.x == 0 or step.y == 0 or x_open or y_open


static func elevation_step_allowed(from_elevation: int, to_elevation: int) -> bool:
	return absi(to_elevation - from_elevation) <= 1


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _map_size and cell.y < _map_size
