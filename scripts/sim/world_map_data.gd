class_name WorldMapData
extends RefCounted
## Authoritative map queries, independent of loaded/rendered chunks.
## Legacy v1 stays immutable; flat v1 may carry sparse terrain overrides.

signal terrain_changed(cells: Array[Vector2i])

const WORLD_SIZE: int = 512
const WORLD_SEED: int = 20261101
const GENERATOR_ID: String = "reol_noise"
const GENERATOR_VERSION: int = 1
const FLAT_GENERATOR_ID: String = "reol_flat_noise"
const FLAT_GENERATOR_VERSION: int = 1
# NaturalEnvironment permits seed offsets through 10000. Keeping their sum in
# signed 32-bit range avoids relying on engine integer narrowing behavior.
const FLAT_MAX_SEED: int = 2147473647
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
var _flat: bool = false
var _terrain_overrides: Dictionary = {}
var _base_terrain_cache := PackedByteArray()


func _init() -> void:
	_terrain_noise = FastNoiseLite.new()
	_height_noise = FastNoiseLite.new()
	# Keep the old seed-before-settings initialization order for legacy v1.
	_initialize_generation(legacy_descriptor())
	_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrain_noise.frequency = 0.018
	_terrain_noise.fractal_octaves = 3
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height_noise.frequency = 0.012
	_height_noise.fractal_octaves = 3


func _initialize_generation(value: Dictionary) -> void:
	# Called only on a new instance, with the fixed legacy tuple or an already
	# validated factory input. Do not reuse this to mutate an active map.
	_generation = {"generator": value.generator, "generator_version": int(value.generator_version),
		"seed": int(value.seed), "size": int(value.size)}
	_map_seed = int(_generation.seed)
	_map_size = int(_generation.size)
	_flat = _generation.generator == FLAT_GENERATOR_ID
	_base_terrain_cache.resize(_map_size * _map_size)
	_base_terrain_cache.fill(0) # Unknown; generated terrain is stored as type + 1.
	_terrain_noise.seed = _map_seed
	_height_noise.seed = _map_seed + 1


static func generation_descriptor() -> Dictionary:
	return {"generator": GENERATOR_ID, "generator_version": GENERATOR_VERSION,
		"seed": WORLD_SEED, "size": WORLD_SIZE}


static func legacy_descriptor() -> Dictionary:
	# Historical tuple, deliberately independent of the current default.
	return {"generator": "reol_noise", "generator_version": 1, "seed": 20261101, "size": 512}


static func flat_descriptor(seed: int) -> Dictionary:
	var value: Dictionary = {"generator": FLAT_GENERATOR_ID, "generator_version": FLAT_GENERATOR_VERSION,
		"seed": seed, "size": 512}
	return value if valid_descriptor(value) else {}


static func valid_descriptor(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 4:
		return false
	for key: Variant in value:
		if not key is String or key not in ["generator", "generator_version", "seed", "size"]:
			return false
	if not value.get("generator") is String:
		return false
	for key: String in ["generator_version", "seed", "size"]:
		if not SnapshotValues.valid_integer(value.get(key), 0):
			return false
	if value.generator == "reol_noise":
		var expected: Dictionary = legacy_descriptor()
		return value.generator_version == expected.generator_version and value.seed == expected.seed and value.size == expected.size
	if value.generator == FLAT_GENERATOR_ID:
		return value.generator_version == FLAT_GENERATOR_VERSION and value.size == 512 and value.seed >= 1 and value.seed <= FLAT_MAX_SEED
	return false


static func from_descriptor(value: Variant) -> WorldMapData:
	if not valid_descriptor(value):
		return null
	var result := WorldMapData.new()
	if value.generator == FLAT_GENERATOR_ID:
		result._initialize_generation(value)
	return result


func descriptor() -> Dictionary:
	return _generation.duplicate(true)


func independent_copy() -> WorldMapData:
	# Reconstruct without retaining live callbacks or derived-cache references.
	var result: WorldMapData = from_descriptor(_generation)
	if result == null:
		return null
	result._terrain_overrides = _terrain_overrides.duplicate(true)
	if not _nature_definitions.is_empty():
		if not result.configure_nature(_nature_definitions):
			return null
	return result


func terrain_overrides() -> Array:
	# Return a canonical, independent JSON-compatible value, not the map's store.
	var cells: Array[Vector2i] = []
	cells.assign(_terrain_overrides.keys())
	_sort_cells(cells)
	var result: Array = []
	for cell: Vector2i in cells:
		result.append([cell.x, cell.y, int(_terrain_overrides[cell])])
	return result


func restore_terrain_overrides(raw: Variant) -> bool:
	# This is a low-level map boundary, not permission to edit a live world.
	# Validate the entire replacement before changing this authority or its cache.
	if not raw is Array or raw.size() > _map_size * _map_size:
		return false
	if not _flat:
		return raw.is_empty()
	var parsed: Dictionary = _parse_terrain_rows(raw, true)
	if not bool(parsed.ok):
		return false
	var replacement: Dictionary = parsed.rows
	var updates: Dictionary = {}
	for cell: Vector2i in _terrain_overrides:
		if not replacement.has(cell):
			updates[cell] = _base_terrain(cell)
	for cell: Vector2i in replacement:
		updates[cell] = int(replacement[cell])
	_commit_terrain_updates(updates)
	return true


func valid_terrain_overrides(raw: Variant) -> bool:
	# Envelope validation must not derive nature, emit changes or read today's
	# default environment rules before the saved content bundle is restored.
	if not raw is Array or raw.size() > _map_size * _map_size:
		return false
	if not _flat:
		return raw.is_empty()
	return bool(_parse_terrain_rows(raw, true).ok)


func apply_terrain_patch(raw: Variant) -> Dictionary:
	# A caller must validate ownership, occupancy, time and player permissions.
	# Patches may contain a base value to remove an existing override.
	if not _flat:
		return _failed_terrain_patch()
	var parsed: Dictionary = _parse_terrain_rows(raw, false)
	if not bool(parsed.ok):
		return _failed_terrain_patch()
	return _commit_terrain_updates(parsed.rows)


func inspect_terrain_patch(raw: Variant) -> Dictionary:
	# Independent proposed cells only: no full-map copy, cache access or signal.
	# World commands use the same parser as the final low-level commit.
	if not _flat:
		return {"ok": false}
	return _parse_terrain_rows(raw, false)


func _parse_terrain_rows(raw: Variant, reject_base: bool) -> Dictionary:
	if not raw is Array or raw.size() > _map_size * _map_size:
		return {"ok": false}
	var rows: Dictionary = {}
	for row: Variant in raw:
		if not row is Array or row.size() != 3:
			return {"ok": false}
		if not SnapshotValues.valid_integer(row[0], 0) or not SnapshotValues.valid_integer(row[1], 0) or not SnapshotValues.valid_integer(row[2], 0):
			return {"ok": false}
		if float(row[0]) >= _map_size or float(row[1]) >= _map_size or float(row[2]) > TERRAIN_ROCK:
			return {"ok": false}
		var cell := Vector2i(int(row[0]), int(row[1]))
		var terrain: int = int(row[2])
		if rows.has(cell) or (reject_base and terrain == _base_terrain(cell)):
			return {"ok": false}
		rows[cell] = terrain
	return {"ok": true, "rows": rows}


func _commit_terrain_updates(updates: Dictionary) -> Dictionary:
	var changed_cells: Array[Vector2i] = []
	var water_changed: Array[Vector2i] = []
	for cell: Vector2i in updates:
		var previous: int = get_terrain(cell)
		var next: int = int(updates[cell])
		if previous == next:
			continue
		changed_cells.append(cell)
		if (previous == TERRAIN_WATER) != (next == TERRAIN_WATER):
			water_changed.append(cell)
	_sort_cells(changed_cells)
	if changed_cells.is_empty():
		var empty_cells: Array[Vector2i] = []
		return {"ok": true, "changed_cells": changed_cells, "affected_cells": empty_cells}
	var affected: Dictionary = {}
	for cell: Vector2i in changed_cells:
		affected[cell] = true
	if not water_changed.is_empty():
		var distances: Array = _nature_rules().call("water_probe_distances")
		for cell: Vector2i in water_changed:
			for distance: int in distances:
				for direction: Vector2i in Nature.DIRECTIONS:
					var neighbor: Vector2i = cell + direction * distance
					if in_bounds(neighbor):
						affected[neighbor] = true
	# All input has been validated. Apply the whole batch before invalidating
	# the derived cache or publishing one sorted notification to observers.
	for cell: Vector2i in changed_cells:
		var terrain: int = int(updates[cell])
		if terrain == _base_terrain(cell):
			_terrain_overrides.erase(cell)
		else:
			_terrain_overrides[cell] = terrain
	if _nature != null:
		_nature.call("clear_cache")
	var affected_cells: Array[Vector2i] = []
	affected_cells.assign(affected.keys())
	_sort_cells(affected_cells)
	var notification: Array[Vector2i] = affected_cells.duplicate()
	terrain_changed.emit(notification)
	return {"ok": true, "changed_cells": changed_cells, "affected_cells": affected_cells}


static func _failed_terrain_patch() -> Dictionary:
	var empty_changed: Array[Vector2i] = []
	var empty_affected: Array[Vector2i] = []
	return {"ok": false, "changed_cells": empty_changed, "affected_cells": empty_affected}


static func _sort_cells(cells: Array[Vector2i]) -> void:
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)


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
	if _terrain_overrides.has(cell):
		return int(_terrain_overrides[cell])
	return _base_terrain(cell)


func _base_terrain(cell: Vector2i) -> int:
	var index: int = cell.y * _map_size + cell.x
	var cached: int = _base_terrain_cache[index]
	if cached != 0:
		return cached - 1
	var n: float = _terrain_noise.get_noise_2d(float(cell.x), float(cell.y))
	var terrain: int = TERRAIN_WATER if n < -0.45 else (TERRAIN_ROCK if n > 0.5 else TERRAIN_GRASS)
	_base_terrain_cache[index] = terrain + 1
	return terrain


func get_elevation(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return -1
	if _flat:
		return 0
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
