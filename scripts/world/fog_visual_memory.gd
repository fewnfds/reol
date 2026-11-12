class_name FogVisualMemory
extends RefCounted
## Last-seen stationary silhouettes, by layer and cell. These are appearance
## tuples only: no entity references, inventories, health, actions or callbacks.
## Empty visible cells erase old silhouettes; unseen cells are never refreshed.
const LAYERS: Array[String] = ["construction", "plants", "physical", "home_sites", "river_sites"]
# Appearance tuples: construction [px,py,glyph,wall_mask,rotation,storage/bench/seat bits];
# plants [px,py,tree,fire,stage]; physical [left,top]; sites [px,py,kind,label,phase,part].
var _layers: Dictionary = {}


func observe(layer: String, visible_cells: Array[Vector2i], appearances: Dictionary) -> void:
	assert(layer in LAYERS)
	var known: Dictionary = _layers.get(layer, {})
	for cell: Vector2i in visible_cells:
		var rows: Array = appearances.get(cell, [])
		if rows.is_empty():
			known.erase(cell)
		else:
			known[cell] = rows.duplicate(true)
	_layers[layer] = known


func cells(layer: String) -> Dictionary:
	return _layers.get(layer, {})


func clear() -> void:
	_layers.clear()


func to_array() -> Array:
	var result: Array = []
	for layer: String in LAYERS:
		var known: Dictionary = cells(layer)
		var positions: Array = known.keys()
		positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or a.y == b.y and a.x < b.x)
		for cell: Vector2i in positions:
			result.append([layer, cell.x, cell.y, known[cell].duplicate(true)])
	return result


func restore(data: Array) -> void:
	# The session candidate validates this before adopting the world/fog.
	clear()
	for row: Array in data:
		var layer: String = row[0]
		if not _layers.has(layer): _layers[layer] = {}
		var appearances: Array = row[3].duplicate(true)
		if layer == "construction":
			for appearance: Array in appearances:
				for index: int in [3, 4, 5]: appearance[index] = int(appearance[index])
		_layers[layer][Vector2i(int(row[1]), int(row[2]))] = appearances


static func valid(data: Variant, explored_runs: Array) -> bool:
	if not data is Array or data.size() > LAYERS.size() * WorldMapData.WORLD_SIZE * WorldMapData.WORLD_SIZE:
		return false
	var seen: Dictionary = {}
	for row: Variant in data:
		if not row is Array or row.size() != 4 or not row[0] is String or row[0] not in LAYERS:
			return false
		if not _integer(row[1], 0, WorldMapData.WORLD_SIZE - 1) or not _integer(row[2], 0, WorldMapData.WORLD_SIZE - 1):
			return false
		var index: int = int(row[2]) * WorldMapData.WORLD_SIZE + int(row[1])
		var key: String = row[0] + ":" + str(index)
		if seen.has(key) or not _explored(index, explored_runs) or not row[3] is Array or row[3].is_empty() or row[3].size() > 64:
			return false
		seen[key] = true
		for appearance: Variant in row[3]:
			if not _valid_appearance(str(row[0]), appearance): return false
	return true


static func _valid_appearance(layer: String, row: Variant) -> bool:
	if not row is Array or row.size() < 2:
		return false
	var limit: float = WorldMapData.WORLD_SIZE * TileGrid.TILE_SIZE + 256.0
	for index: int in 2:
		if not (row[index] is int or row[index] is float) or not is_finite(float(row[index])) or absf(float(row[index])) > limit:
			return false
	match layer:
		"construction":
			return row.size() == 6 and row[2] in ["blueprint", "ruined", "roof", "bed", "wall", "door", "window", "furniture"] and _integer(row[3], 0, 15) and _integer(row[4], 0, 3) and _integer(row[5], 0, 7)
		"plants": return row.size() == 5 and row[2] is bool and row[3] is bool and _text(row[4])
		"physical": return row.size() == 2
		"home_sites", "river_sites": return row.size() == 6 and _text(row[2]) and _text(row[3]) and _text(row[4]) and row[5] in ["marker", "roof", "wall", "door", "desk", "archive", "anchor"]
	return false


static func _text(value: Variant) -> bool:
	return value is String and value.length() <= 256


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum


static func _explored(index: int, runs: Array) -> bool:
	var low: int = 0
	var high: int = runs.size()
	while low < high:
		var middle: int = (low + high) / 2
		var run: Array = runs[middle]
		if index < int(run[0]): high = middle
		elif index >= int(run[0]) + int(run[1]): low = middle + 1
		else: return true
	return false
