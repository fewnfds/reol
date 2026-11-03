class_name NaturalEnvironment
extends RefCounted
## Static substrate, vegetation cover and habitat potential, derived from the
## existing map. These are not harvested objects, wildlife populations or qi.
## Mutable water, growth, beings and finite spirit supplies retain their owners.

const DEFAULT_PATH: String = "res://data/definitions/natural_environment.json"
const SURFACES: Array[String] = ["water", "stone", "ore_rock", "shore", "wetland", "woodland", "gravel", "meadow", "grassland"]
const ELEMENTS: Array[String] = ["metal", "wood", "water", "fire", "earth"]
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]
static var _defaults: Dictionary = {}

var _rules: Dictionary = {}
var _seed: int = 0
var _noises: Dictionary = {}
var _cache: Dictionary = {}
var _cache_order: Array[Vector2i] = []
var _cache_cursor: int = 0
var _map: WeakRef


func _init(seed: int, rules: Dictionary = {}) -> void:
	var selected: Dictionary = rules
	if selected.is_empty():
		if _defaults.is_empty():
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_PATH))
			if valid_definitions(parsed):
				_defaults = parsed
		selected = _defaults
	if not valid_definitions(selected):
		return
	_rules = selected.duplicate(true)
	_seed = seed
	for key: String in _rules.noise:
		var definition: Dictionary = _rules.noise[key]
		var noise := FastNoiseLite.new()
		noise.seed = seed + int(definition.seed_offset)
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = float(definition.frequency)
		noise.fractal_octaves = int(definition.octaves)
		_noises[key] = noise


func is_valid() -> bool:
	return not _rules.is_empty()


func cell_at(map: RefCounted, cell: Vector2i) -> Dictionary:
	return _cell(map, cell).duplicate(true)


func surface_at(map: RefCounted, cell: Vector2i) -> String:
	return str(_cell(map, cell).get("surface_id", ""))


func affinity_at(map: RefCounted, cell: Vector2i, element: String) -> int:
	return int(_cell(map, cell).get("elements", {}).get(element, 0))


func growth_factor_at(map: RefCounted, cell: Vector2i) -> int:
	# Potential suitability only: callers still need original available water,
	# temperature, time and the source's own finite growth/capacity accounting.
	return int(_cell(map, cell).get("growth_factor", 0))


func surface_definitions() -> Dictionary:
	return _rules.get("surfaces", {}).duplicate(true)


func flora_definitions() -> Dictionary:
	return _rules.get("flora", {}).duplicate(true)


func relation(from_element: String, to_element: String) -> String:
	if not is_valid() or from_element not in ELEMENTS or to_element not in ELEMENTS:
		return "unknown"
	if from_element == to_element:
		return "same"
	if _rules.elements.engenders[from_element] == to_element:
		return "engenders"
	if _rules.elements.controls[from_element] == to_element:
		return "controls"
	if _rules.elements.engenders[to_element] == from_element:
		return "engendered_by"
	return "controlled_by"


func cache_size() -> int:
	return _cache.size()


func _cell(map: RefCounted, cell: Vector2i) -> Dictionary:
	if not is_valid() or map == null or not map.in_bounds(cell):
		return {}
	if _map == null or _map.get_ref() != map:
		# Derived values belong to one spatial authority, including when a test
		# or an independent candidate supplies a different map at the same cell.
		_cache.clear()
		_cache_order.clear()
		_cache_cursor = 0
		_map = weakref(map)
	if _cache.has(cell):
		return _cache[cell]
	var result: Dictionary = _derive(map, cell)
	var limit: int = int(_rules.cache_cells)
	if _cache_order.size() < limit:
		_cache_order.append(cell)
	else:
		_cache.erase(_cache_order[_cache_cursor])
		_cache_order[_cache_cursor] = cell
		_cache_cursor = (_cache_cursor + 1) % limit
	_cache[cell] = result
	return result


func _derive(map: RefCounted, cell: Vector2i) -> Dictionary:
	var terrain: int = map.get_terrain(cell)
	var elevation: int = map.get_elevation(cell)
	var land: Dictionary = _rules.land
	var water: int = _nearby_water(map, cell)
	var moisture: int = clampi(_noise_at("moisture", cell) + water - elevation * int(land.elevation_dryness), 0, 100)
	var canopy: int = _noise_at("canopy", cell)
	var mineral: int = _noise_at("mineral", cell)
	var fertility: int = clampi(int(land.fertility_center) + _percent(moisture, int(land.fertility_moisture)) + _percent(canopy, int(land.fertility_canopy)) - elevation * int(land.fertility_height_loss) - _percent(mineral, int(land.fertility_mineral_loss)), 0, 100)
	var exposure: int = clampi(int(land.exposure_center) + elevation * int(land.exposure_height) - _percent(canopy, int(land.exposure_canopy_loss)), 0, 100)
	var surface: String = _surface(terrain, elevation, moisture, canopy, mineral, fertility, water)
	if terrain == int(_rules.terrain_ids.water):
		moisture = 100
		fertility = 0
	elif terrain == int(_rules.terrain_ids.rock):
		fertility = 0
	var definition: Dictionary = _rules.surfaces[surface]
	var elements: Dictionary = _element_affinities(definition.elements, moisture, canopy, mineral, fertility, exposure)
	var dominant: String = ELEMENTS[0]
	for element: String in ELEMENTS:
		if int(elements[element]) > int(elements[dominant]):
			dominant = element
	var flora: Dictionary = _flora_at(cell, definition)
	var growth: int = _growth_factor(fertility, moisture, mineral)
	if terrain == int(_rules.terrain_ids.water) or terrain == int(_rules.terrain_ids.rock):
		growth = 0
	return {"surface_id": surface, "label": str(definition.label), "color": str(definition.color),
		"moisture_potential": moisture, "fertility": fertility, "mineralization": mineral,
		"exposure": exposure, "canopy_potential": canopy, "elevation": elevation,
		"water_nearby": water, "growth_factor": growth, "elements": elements,
		"dominant_element": dominant, "dominant_element_label": str(_rules.elements.labels[dominant]),
		"flora": flora, "habitat": definition.habitat.duplicate()}


func _surface(terrain: int, elevation: int, moisture: int, canopy: int, mineral: int, fertility: int, water: int) -> String:
	var land: Dictionary = _rules.land
	if terrain == int(_rules.terrain_ids.water):
		return "water"
	if terrain == int(_rules.terrain_ids.rock):
		return "ore_rock" if mineral >= int(land.ore_threshold) else "stone"
	if water >= int(land.shore_water_threshold):
		return "shore"
	if moisture >= int(land.wetland_moisture) and elevation <= int(land.wetland_max_height):
		return "wetland"
	if canopy >= int(land.woodland_canopy):
		return "woodland"
	if moisture < int(land.gravel_moisture) or elevation >= int(land.gravel_height) and fertility < int(land.gravel_fertility):
		return "gravel"
	if fertility >= int(land.meadow_fertility):
		return "meadow"
	return "grassland"


func _nearby_water(map: RefCounted, cell: Vector2i) -> int:
	# Eight probes, no flood fill and no recursive natural-cell queries. This
	# expresses substrate adjacency, not a simulated or withdrawable water body.
	if map.get_terrain(cell) == int(_rules.terrain_ids.water):
		return 100
	for index: int in _rules.land.water_probe_distances.size():
		var distance: int = int(_rules.land.water_probe_distances[index])
		for direction: Vector2i in DIRECTIONS:
			if map.get_terrain(cell + direction * distance) == int(_rules.terrain_ids.water):
				return int(_rules.land.water_probe_bonus[index])
	return 0


func _noise_at(key: String, cell: Vector2i) -> int:
	var noise: FastNoiseLite = _noises[key]
	return clampi(int(round(float(_rules.land.noise_center) + noise.get_noise_2d(float(cell.x), float(cell.y)) * float(_rules.land.noise_scale))), 0, 100)


func _element_affinities(base: Array, moisture: int, canopy: int, mineral: int, fertility: int, exposure: int) -> Dictionary:
	var rule: Dictionary = _rules.elements
	return {"metal": clampi(int(base[0]) + _percent(mineral, int(rule.mineral_metal_bonus)), 0, 100),
		"wood": clampi(int(base[1]) + _percent(canopy, int(rule.canopy_wood_bonus)), 0, 100),
		"water": clampi(int(base[2]) + _percent(moisture, int(rule.moisture_water_bonus)), 0, 100),
		"fire": clampi(int(base[3]) + _percent(_percent(exposure, 100 - moisture), int(rule.dry_exposure_fire_bonus)), 0, 100),
		"earth": clampi(int(base[4]) + _percent(fertility, int(rule.fertility_earth_bonus)), 0, 100)}


func _flora_at(cell: Vector2i, surface: Dictionary) -> Dictionary:
	if _roll(cell, 11) % 100 >= int(surface.density):
		return {}
	var weights: Dictionary = surface.flora
	var total: int = 0
	# Stable identifier ordering makes dictionary presentation irrelevant.
	var ids: Array = weights.keys()
	ids.sort()
	for id: String in ids:
		total += int(weights[id])
	var selected: int = _roll(cell, 29) % total
	for id: String in ids:
		selected -= int(weights[id])
		if selected < 0:
			var flora: Dictionary = _rules.flora[id].duplicate()
			flora.id = id
			flora.placement_id = "cover:%d:%d:%d:%s" % [_seed, cell.x, cell.y, id]
			flora.variant = _roll(cell, 37) % 4
			return flora
	return {}


func _growth_factor(fertility: int, moisture: int, mineral: int) -> int:
	var land: Dictionary = _rules.land
	var usable: int = clampi(moisture - int(land.growth_moisture_floor), 0, int(land.growth_moisture_optimal))
	var water_factor: int = int(100.0 * float(usable) / float(land.growth_moisture_optimal))
	return clampi(_percent(fertility, water_factor) - _percent(mineral, int(land.growth_mineral_loss)), 0, 100)


func _roll(cell: Vector2i, salt: int) -> int:
	return int((cell.x * 73856093 ^ cell.y * 19349663 ^ _seed * 83492791 ^ salt * 1640531513) & 0x7fffffff)


@warning_ignore("integer_division")
static func _percent(value: int, percent: int) -> int:
	return value * percent / 100


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	if value is bool or not (value is int or value is float):
		return false
	return is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum


static func _keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size():
		return false
	for key: String in keys:
		if not value.has(key):
			return false
	return true


static func valid_definitions(data: Variant) -> bool:
	if not _keys(data, ["version", "cache_cells", "terrain_ids", "noise", "land", "elements", "surfaces", "flora", "fauna"]) or not _integer(data.version, 1, 1) or not _integer(data.cache_cells, 1, 65536):
		return false
	if not _keys(data.terrain_ids, ["water", "rock"]) or not _integer(data.terrain_ids.water, 0, 0) or not _integer(data.terrain_ids.rock, 2, 2):
		return false
	if not _keys(data.noise, ["moisture", "canopy", "mineral"]):
		return false
	for key: String in data.noise:
		var noise: Variant = data.noise[key]
		if not _keys(noise, ["seed_offset", "frequency", "octaves"]) or not _integer(noise.seed_offset, 1, 10000) or not _integer(noise.octaves, 1, 8):
			return false
		if noise.frequency is bool or not (noise.frequency is int or noise.frequency is float) or not is_finite(float(noise.frequency)) or float(noise.frequency) <= 0.0 or float(noise.frequency) > 1.0:
			return false
	var land_keys: Array[String] = ["noise_center", "noise_scale", "water_probe_distances", "water_probe_bonus", "elevation_dryness", "fertility_center", "fertility_moisture", "fertility_canopy", "fertility_height_loss", "fertility_mineral_loss", "exposure_center", "exposure_height", "exposure_canopy_loss", "ore_threshold", "shore_water_threshold", "wetland_moisture", "wetland_max_height", "woodland_canopy", "gravel_moisture", "gravel_height", "gravel_fertility", "meadow_fertility", "growth_moisture_floor", "growth_moisture_optimal", "growth_mineral_loss"]
	if not _keys(data.land, land_keys):
		return false
	for key: String in land_keys:
		if key not in ["water_probe_distances", "water_probe_bonus"] and not _integer(data.land[key], 0, 100):
			return false
	if int(data.land.growth_moisture_optimal) < 1 or not data.land.water_probe_distances is Array or not data.land.water_probe_bonus is Array or data.land.water_probe_distances.size() != 2 or data.land.water_probe_bonus.size() != 2:
		return false
	if not _integer(data.land.water_probe_distances[0], 1, 8) or not _integer(data.land.water_probe_distances[1], int(data.land.water_probe_distances[0]) + 1, 8) or not _integer(data.land.water_probe_bonus[0], 0, 100) or not _integer(data.land.water_probe_bonus[1], 0, int(data.land.water_probe_bonus[0])):
		return false
	if not _keys(data.elements, ["order", "labels", "engenders", "controls", "mineral_metal_bonus", "canopy_wood_bonus", "moisture_water_bonus", "dry_exposure_fire_bonus", "fertility_earth_bonus"]) or data.elements.order != ELEMENTS:
		return false
	for key: String in ["labels", "engenders", "controls"]:
		if not _keys(data.elements[key], ELEMENTS):
			return false
	for element: String in ELEMENTS:
		if not data.elements.labels[element] is String or data.elements.labels[element].is_empty() or data.elements.engenders[element] not in ELEMENTS or data.elements.controls[element] not in ELEMENTS:
			return false
		if data.elements.engenders[element] == element or data.elements.controls[element] == element or data.elements.engenders[element] == data.elements.controls[element]:
			return false
	if not _five_cycle(data.elements.engenders) or not _five_cycle(data.elements.controls):
		return false
	for element: String in ELEMENTS:
		if data.elements.controls[element] != data.elements.engenders[data.elements.engenders[element]]:
			return false
	for key: String in ["mineral_metal_bonus", "canopy_wood_bonus", "moisture_water_bonus", "dry_exposure_fire_bonus", "fertility_earth_bonus"]:
		if not _integer(data.elements[key], 0, 100):
			return false
	if not _keys(data.surfaces, SURFACES) or not data.flora is Dictionary or data.flora.is_empty() or not data.fauna is Dictionary or data.fauna.is_empty():
		return false
	for id: Variant in data.flora:
		var flora: Variant = data.flora[id]
		if not id is String or id.is_empty() or not _keys(flora, ["label", "kind", "element", "color", "height"]) or not flora.label is String or flora.label.is_empty() or not flora.kind is String or flora.kind.is_empty() or flora.element not in ELEMENTS or not _color(flora.color) or not _integer(flora.height, 1, 64):
			return false
	for id: Variant in data.fauna:
		var fauna: Variant = data.fauna[id]
		if not id is String or id.is_empty() or not _keys(fauna, ["label", "diet", "body"]) or not fauna.label is String or fauna.label.is_empty() or not fauna.diet is String or fauna.diet.is_empty() or not fauna.body is String or fauna.body.is_empty():
			return false
	for id: String in SURFACES:
		var surface: Variant = data.surfaces[id]
		if not _keys(surface, ["label", "color", "density", "elements", "flora", "habitat"]) or not surface.label is String or surface.label.is_empty() or not _color(surface.color) or not _integer(surface.density, 0, 100):
			return false
		if not surface.elements is Array or surface.elements.size() != ELEMENTS.size() or not surface.flora is Dictionary or surface.flora.is_empty() or not surface.habitat is Array:
			return false
		for value: Variant in surface.elements:
			if not _integer(value, 0, 100):
				return false
		for flora: Variant in surface.flora:
			if not flora is String or not data.flora.has(flora) or not _integer(surface.flora[flora], 1, 10000):
				return false
		var seen: Dictionary = {}
		for fauna: Variant in surface.habitat:
			if not fauna is String or not data.fauna.has(fauna) or seen.has(fauna):
				return false
			seen[fauna] = true
	return true


static func _color(value: Variant) -> bool:
	return value is String and value.length() == 7 and value.begins_with("#") and value.substr(1).is_valid_hex_number()


static func _five_cycle(edges: Dictionary) -> bool:
	var current: String = ELEMENTS[0]
	var seen: Dictionary = {}
	for _step: int in ELEMENTS.size():
		if seen.has(current):
			return false
		seen[current] = true
		current = str(edges[current])
	return current == ELEMENTS[0] and seen.size() == ELEMENTS.size()
