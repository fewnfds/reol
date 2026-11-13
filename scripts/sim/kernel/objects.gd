extends RefCounted
## Owner-only identity, static placement and inventories. No periodic object loop.
## Actor positions stay in body pages; these records do not duplicate them.
const STATE_FIELDS: Array = ["records", "next_id"]
const Sight = preload("res://scripts/sim/kernel/sight.gd")

var next_id: int = 1
var records: Dictionary = {}
var by_tile: Dictionary = {}
var buckets: Dictionary = {}
var interaction_buckets: Dictionary = {} # Cold derived index excludes structures.
var layout_revision: int = 0
var transfers: int = 0
var totals: Dictionary = {}
var definitions: Dictionary = {}


func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/items.json"))
	if parsed is Dictionary:
		definitions = parsed


func create(kind: String, definition: String, tile: int = -1, capacity: int = -1) -> int:
	var id: int = next_id
	next_id += 1
	records[id] = {"id": id, "kind": kind, "definition": definition, "tile": tile,
		"inventory": {}, "capacity": capacity, "sight_range": Sight.DEFAULT_RANGE if kind == "actor" else 0.0}
	if kind != "actor":
		records[id].hp = 100
	if tile >= 0:
		if not by_tile.has(tile):
			by_tile[tile] = []
		by_tile[tile].append(id)
		_index_bucket(id, tile)
	layout_revision += 1
	return id


func amount(id: int, item: String) -> int:
	return int(records[id].inventory.get(item, 0)) if records.has(id) else 0


func count_inventory(id: int) -> int:
	var total: int = 0
	if records.has(id):
		for count: int in records[id].inventory.values():
			total += count
	return total


func add(id: int, item: String, count: int) -> void:
	if count == 0:
		return
	var inventory: Dictionary = records[id].inventory
	var next: int = int(inventory.get(item, 0)) + count
	if next == 0:
		inventory.erase(item)
	else:
		inventory[item] = next
	totals[item] = int(totals.get(item, 0)) + count
	records[id]["inventory_revision"] = int(records[id].get("inventory_revision", 0)) + 1


func transfer(source: int, target: int, item: String, requested: int) -> int:
	if not definitions.has(item) or source == target or requested <= 0 or not records.has(source) or not records.has(target):
		return 0
	var count: int = mini(requested, amount(source, item))
	var capacity: int = records[target].capacity
	if capacity >= 0:
		count = mini(count, maxi(0, capacity - count_inventory(target)))
	if count <= 0:
		return 0
	add(source, item, -count)
	add(target, item, count)
	transfers += 1
	return count


func remove_empty(id: int) -> bool:
	if not records.has(id) or count_inventory(id) != 0 or not records[id].get("materials", {}).is_empty():
		return false
	for tile: int in records[id].get("cells", PackedInt32Array([records[id].tile])):
		if by_tile.has(tile):
			by_tile[tile].erase(id)
			if by_tile[tile].is_empty():
				by_tile.erase(tile)
	_unindex_buckets(id, records[id].get("cells", PackedInt32Array([records[id].tile])))
	records.erase(id)
	layout_revision += 1
	return true


func exchange(a: int, b: int, give: String, given: int, want: String, wanted: int) -> bool:
	if a == b or not records.has(a) or not records.has(b) or given <= 0 or wanted <= 0 or amount(a, give) < given or amount(b, want) < wanted:
		return false
	if (records[a].capacity >= 0 and count_inventory(a) - given + wanted > records[a].capacity) or (records[b].capacity >= 0 and count_inventory(b) - wanted + given > records[b].capacity):
		return false
	# Validate both final capacities before either side changes. Ordinary
	# transfer() twice could partially commit when the first side is full.
	add(a, give, -given)
	add(b, want, -wanted)
	add(b, give, given)
	add(a, want, wanted)
	transfers += 2
	return true


func reindex(id: int, cells: PackedInt32Array) -> void:
	var record: Dictionary = records[id]
	var previous: PackedInt32Array = record.get("cells", PackedInt32Array([record.tile]))
	_unindex_buckets(id, previous)
	for tile: int in previous:
		if by_tile.has(tile):
			by_tile[tile].erase(id)
			if by_tile[tile].is_empty():
				by_tile.erase(tile)
	record["cells"] = cells
	for tile: int in cells:
		if not by_tile.has(tile):
			by_tile[tile] = []
		by_tile[tile].append(id)
		_index_bucket(id, tile)
	layout_revision += 1


func total(item: String) -> int:
	return int(totals.get(item, 0))


func audit_total(item: String) -> int:
	var count: int = 0
	for id: int in records:
		count += amount(id, item)
		count += int(records[id].get("materials", {}).get(item, 0))
	return count


func layout() -> Dictionary:
	var result: Dictionary = {}
	for id: int in records:
		var record: Dictionary = records[id]
		if record.tile >= 0:
			result[id] = {"id": id, "kind": record.kind, "definition": record.definition, "tile": record.tile,
				"cells": record.get("cells", PackedInt32Array([record.tile])).duplicate(), "layer": record.get("layer", "ground"),
				"stage": record.get("stage", -1), "vegetation_level": record.get("vegetation_level", 3), "sapient": record.get("sapient", false), "facing": record.get("facing", 0)}
	return result


func _bucket(tile: int) -> int:
	return (tile / 512 / 16) * 32 + (tile % 512) / 16


func _index_bucket(id: int, tile: int) -> void:
	if tile < 0:
		return
	var bucket: int = _bucket(tile)
	if not buckets.has(bucket):
		buckets[bucket] = []
	if not buckets[bucket].has(id):
		buckets[bucket].append(id)
	if records[id].kind not in ["wall", "door", "roof", "floor"]:
		if not interaction_buckets.has(bucket):
			interaction_buckets[bucket] = []
		if not interaction_buckets[bucket].has(id):
			interaction_buckets[bucket].append(id)


func _unindex_buckets(id: int, cells: PackedInt32Array) -> void:
	for tile: int in cells:
		var bucket: int = _bucket(tile)
		if buckets.has(bucket):
			buckets[bucket].erase(id)
			if buckets[bucket].is_empty():
				buckets.erase(bucket)
		if interaction_buckets.has(bucket):
			interaction_buckets[bucket].erase(id)
			if interaction_buckets[bucket].is_empty():
				interaction_buckets.erase(bucket)


func nearby(position: Vector2, radius: float, structures: bool = true) -> Array[int]:
	var result: Array[int] = []
	var seen: Dictionary = {}
	var index: Dictionary = buckets if structures else interaction_buckets
	var low := Vector2i((position - Vector2.ONE * radius) / 16.0)
	var high := Vector2i((position + Vector2.ONE * radius) / 16.0)
	for y: int in range(maxi(0, low.y), mini(31, high.y) + 1):
		for x: int in range(maxi(0, low.x), mini(31, high.x) + 1):
			for id: int in index.get(y * 32 + x, []):
				if seen.has(id):
					continue
				seen[id] = true
				var record: Dictionary = records[id]
				if not structures and record.kind in ["wall", "door", "roof", "floor"]:
					continue
				var tile: int = record.tile
				var point := Vector2(tile % 512 + 0.5, tile / 512 + 0.5)
				if point.distance_squared_to(position) <= radius * radius:
					result.append(id)
				elif record.has("cells"):
					for member: int in record.cells:
						point = Vector2(member % 512 + 0.5, member / 512 + 0.5)
						if point.distance_squared_to(position) <= radius * radius:
							result.append(id)
							break
	return result
