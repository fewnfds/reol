extends RefCounted
## Owner-only identity, static placement and inventories. No periodic object loop.
## Actor positions stay in body pages; these records do not duplicate them.
const STATE_FIELDS: Array = ["records", "next_id"]
const Sight = preload("res://scripts/sim/kernel/sight.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")

var next_id: int = 1
var records: Dictionary = {}
var by_tile: Dictionary = {}
var buckets: Dictionary = {}
var interaction_buckets: Dictionary = {} # Cold derived index excludes structures.
var layout_revision: int = 0
var transfers: int = 0
var totals: Dictionary = {}
var definitions: Dictionary = {}
var _summaries: Dictionary = {} # Detached aggregate caches, never source quantities.
var _held_totals: Dictionary = {}


func _init() -> void:
	definitions = Items.load_definitions()


func create(kind: String, definition: String, tile: int = -1, capacity: int = -1) -> int:
	var id: int = next_id
	next_id += 1
	records[id] = {"id": id, "kind": kind, "definition": definition, "tile": tile,
		"stock": {}, "owner": 0, "organization": 0, "capacity": capacity, "sight_range": Sight.DEFAULT_RANGE if kind == "actor" else 0.0}
	_summaries[id] = {}
	_held_totals[id] = {}
	if kind != "actor":
		records[id].hp = 100
	else:
		records[id]["equipment"] = {}
		records[id]["body_profile"] = definition
		records[id]["body_origin"] = "independent"
	if tile >= 0:
		if not by_tile.has(tile):
			by_tile[tile] = []
		by_tile[tile].append(id)
		_index_bucket(id, tile)
	layout_revision += 1
	return id


func amount(id: int, item: String, filter: Dictionary = {}) -> int:
	if not records.has(id): return 0
	return int(_summaries.get(id, {}).get(item, 0)) if filter.is_empty() else Stock.count(records[id].stock, item, filter)

func inventory_summary(id: int, filter: Dictionary = {}) -> Dictionary:
	if not records.has(id): return {}
	return _summaries.get(id, {}).duplicate() if filter.is_empty() else Stock.summary(records[id].stock, filter)

func usable_summary(id: int) -> Dictionary:
	return inventory_summary(id, spending_right(id))

func spending_right(id: int) -> Dictionary:
	return Stock.right(id) if records.get(id, {}).get("kind") == "actor" else default_right(id)

func equipment_summary(id: int) -> Dictionary:
	var result: Dictionary = {}
	for slot: String in records.get(id, {}).get("equipment", {}): result[slot] = records[id].equipment[slot].item
	return result


func count_inventory(id: int) -> int:
	var result: int = 0
	for count: int in _summaries.get(id, {}).values(): result += count
	return result


func default_right(id: int) -> Dictionary:
	return Stock.right(id) if records[id].kind == "actor" else Stock.right(int(records[id].owner), int(records[id].organization))

func add(id: int, item: String, count: int, right: Dictionary = {}) -> void:
	# Trusted fixture/natural creation or explicit destruction. Character actions
	# use consume/transfer after their domain has authorized the actual group.
	if count == 0: return
	assert(records.has(id) and Items.valid(item))
	if count < 0:
		assert(amount(id, item, right) >= -count)
		_extract(records[id].stock, item, -count, right)
	else:
		var batch: Dictionary = Stock.attribution(default_right(id) if right.is_empty() else right)
		batch["count"] = count
		assert(_fits(records[id].stock, item, [batch]))
		_insert(records[id].stock, item, batch)
	_refresh(id)

func consume(id: int, required: Dictionary, filter: Dictionary, field: String = "stock") -> bool:
	if not records.has(id): return false
	if field not in ["stock", "work_stock"]: return false
	var contents: Dictionary = records[id].get(field, {})
	for item: String in required:
		if not Items.valid(item) or int(required[item]) <= 0 or Stock.count(contents, item, filter) < int(required[item]): return false
	for item: String in required: _extract(contents, item, int(required[item]), filter)
	_refresh(id)
	return true


func transfer(source: int, target: int, item: String, requested: int, filter: Dictionary = {}, replacement: Dictionary = {}, source_field: String = "stock", target_field: String = "stock") -> int:
	if not Items.valid(item) or source == target or requested <= 0 or not records.has(source) or not records.has(target):
		return 0
	if source_field not in ["stock", "materials", "work_stock"] or target_field not in ["stock", "work_stock"]: return 0
	var contents: Dictionary = records[source].get(source_field, {})
	var destination: Dictionary = records[target].get(target_field, {})
	var count: int = mini(requested, Stock.count(contents, item, filter))
	var capacity: int = records[target].capacity
	if target_field == "stock" and capacity >= 0:
		count = mini(count, maxi(0, capacity - count_inventory(target)))
	if count <= 0:
		return 0
	var selected: Array = _select(contents, item, count, filter)
	if not replacement.is_empty():
		for batch: Dictionary in selected: batch.merge(Stock.attribution(replacement), true)
	if not _fits(destination, item, selected): return 0
	_extract(contents, item, count, filter)
	for batch: Dictionary in selected: _insert(destination, item, batch)
	records[target][target_field] = destination
	_refresh(source)
	_refresh(target)
	transfers += 1
	return count

func claim(source: int, actor: int, item: String, requested: int) -> int:
	# Explicit first acquisition of untitled goods, never implicit in transport.
	return transfer(source, actor, item, requested, Stock.right(), Stock.right(actor))

func install_materials(id: int) -> void:
	assert(records[id].get("materials", {}).is_empty())
	records[id]["materials"] = records[id].stock
	records[id].stock = {}
	_refresh(id)

func can_receive(id: int, output: Dictionary, right: Dictionary) -> bool:
	if not records.has(id): return false
	var count: int = 0
	for item: String in output:
		var batch: Dictionary = right.duplicate()
		batch["count"] = int(output[item])
		if not Items.valid(item) or batch.count <= 0 or not _fits(records[id].stock, item, [batch]): return false
		count += int(batch.count)
	return records[id].capacity < 0 or count_inventory(id) + count <= records[id].capacity

func retitle(id: int, field: String, filter: Dictionary, replacement: Dictionary) -> void:
	assert(field in ["stock", "materials"])
	var next: Dictionary = {}
	for item: String in records[id].get(field, {}):
		for batch: Dictionary in records[id][field][item]:
			var copy: Dictionary = batch.duplicate()
			if Stock.matches(copy, filter): copy.merge(Stock.attribution(replacement), true)
			_insert(next, item, copy)
	records[id][field] = next
	_refresh(id)

func goods_summary(id: int, worn: bool = false) -> Dictionary:
	var result: Dictionary = inventory_summary(id)
	if worn:
		for gear: Dictionary in records.get(id, {}).get("equipment", {}).values(): result[gear.item] = int(result.get(gear.item, 0)) + 1
	return result

func public_contents(id: int) -> Dictionary:
	# Observable attribution of a static store's contents, detached from custody
	# mandates. A public workshop can hold somebody's privately owned output.
	var result: Dictionary = {}
	for item: String in records.get(id, {}).get("stock", {}):
		result[item] = []
		for batch: Dictionary in records[id].stock[item]:
			var group: Dictionary = {"owner": int(batch.owner), "organization": int(batch.organization), "entrusted": int(batch.entrust) > 0, "count": int(batch.count)}
			var merged: bool = false
			for entry: Dictionary in result[item]:
				if entry.owner == group.owner and entry.organization == group.organization and entry.entrusted == group.entrusted:
					entry.count += int(group.count); merged = true; break
			if not merged: result[item].append(group)
	return result

func goods_amount(id: int, item: String, filter: Dictionary, worn: bool = false) -> int:
	var result: int = amount(id, item, filter)
	if worn:
		for gear: Dictionary in records[id].get("equipment", {}).values():
			if gear.item == item and Stock.matches(gear, filter): result += 1
	return result

func transfer_possessions(source: int, target: int, item: String, requested: int, filter: Dictionary, replacement: Dictionary, worn: bool = false) -> int:
	var moved: int = transfer(source, target, item, requested, filter, replacement)
	if worn:
		for slot: String in records[source].get("equipment", {}).keys():
			if moved >= requested: break
			var gear: Dictionary = records[source].equipment[slot]
			if gear.item == item and Stock.matches(gear, filter) and unequip(source, slot, target, replacement) == "unequipped": moved += 1
	return moved

func groups(id: int, worn: bool = false) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	var contents: Array = []
	for batches: Array in records.get(id, {}).get("stock", {}).values(): contents.append_array(batches)
	if worn: contents.append_array(records.get(id, {}).get("equipment", {}).values())
	for batch: Dictionary in contents:
		var key: String = Stock.key(batch)
		if not seen.has(key):
			seen[key] = true
			result.append(Stock.attribution(batch))
	return result

static func _select(contents: Dictionary, item: String, count: int, filter: Dictionary) -> Array:
	var result: Array = []
	for batch: Dictionary in contents.get(item, []):
		if not Stock.matches(batch, filter): continue
		var selected: Dictionary = batch.duplicate()
		selected.count = mini(int(batch.count), count)
		result.append(selected)
		count -= int(selected.count)
		if count == 0: break
	return result

static func _extract(contents: Dictionary, item: String, count: int, filter: Dictionary) -> Array:
	var selected: Array = _select(contents, item, count, filter)
	for taken: Dictionary in selected:
		for batch: Dictionary in contents[item].duplicate():
			if Stock.key(batch) != Stock.key(taken): continue
			batch.count -= taken.count
			if batch.count == 0: contents[item].erase(batch)
			break
	if contents.has(item) and contents[item].is_empty(): contents.erase(item)
	return selected

static func _insert(contents: Dictionary, item: String, batch: Dictionary) -> void:
	if not contents.has(item): contents[item] = []
	var index: int = 0
	for existing: Dictionary in contents[item]:
		if Stock.key(existing) == Stock.key(batch):
			existing.count += batch.count
			return
		if Stock.key(existing) > Stock.key(batch): break
		index += 1
	contents[item].insert(index, batch.duplicate())

static func _fits(contents: Dictionary, item: String, incoming: Array) -> bool:
	var total: int = Stock.count(contents, item)
	var keys: Dictionary = {}
	for batch: Dictionary in contents.get(item, []): keys[Stock.key(batch)] = true
	for batch: Dictionary in incoming:
		total += int(batch.count)
		keys[Stock.key(batch)] = true
	return total <= Stock.MAX_COUNT and keys.size() <= Stock.MAX_GROUPS

func _refresh(id: int, changed: bool = true) -> void:
	for item: String in _held_totals.get(id, {}): totals[item] = int(totals.get(item, 0)) - int(_held_totals[id][item])
	_summaries[id] = Stock.summary(records[id].stock)
	var held: Dictionary = _summaries[id].duplicate()
	for item: String in records[id].get("materials", {}): held[item] = int(held.get(item, 0)) + Stock.count(records[id].materials, item)
	for item: String in records[id].get("work_stock", {}): held[item] = int(held.get(item, 0)) + Stock.count(records[id].work_stock, item)
	for gear: Dictionary in records[id].get("equipment", {}).values(): held[gear.item] = int(held.get(gear.item, 0)) + 1
	_held_totals[id] = held
	for item: String in held: totals[item] = int(totals.get(item, 0)) + int(held[item])
	if changed: records[id]["inventory_revision"] = int(records[id].get("inventory_revision", 0)) + 1


func can_remove(id: int) -> bool:
	return records.has(id) and count_inventory(id) == 0 and records[id].get("materials", {}).is_empty() and records[id].get("work_stock", {}).is_empty() and records[id].get("equipment", {}).is_empty()

func can_consolidate(id: int, fields: Array) -> bool:
	var combined: Dictionary = {}
	for field: String in fields:
		for item: String in records[id].get(field, {}):
			var batches: Array = records[id][field][item]
			if not _fits(combined, item, batches): return false
			for batch: Dictionary in batches: _insert(combined, item, batch)
	return true


func remove_empty(id: int) -> bool:
	# Low-level identity/index operation. World.remove_static owns facility cleanup.
	if not can_remove(id):
		return false
	for tile: int in records[id].get("cells", PackedInt32Array([records[id].tile])):
		if by_tile.has(tile):
			by_tile[tile].erase(id)
			if by_tile[tile].is_empty():
				by_tile.erase(tile)
	_unindex_buckets(id, records[id].get("cells", PackedInt32Array([records[id].tile])))
	records.erase(id)
	_summaries.erase(id)
	_held_totals.erase(id)
	layout_revision += 1
	return true


func exchange(a: int, b: int, give: String, given: int, want: String, wanted: int, filter_a: Dictionary = {}, filter_b: Dictionary = {}, transfer_title: bool = false) -> bool:
	if not Items.valid(give) or not Items.valid(want) or a == b or not records.has(a) or not records.has(b) or given <= 0 or wanted <= 0 or amount(a, give, filter_a) < given or amount(b, want, filter_b) < wanted:
		return false
	if (records[a].capacity >= 0 and count_inventory(a) - given + wanted > records[a].capacity) or (records[b].capacity >= 0 and count_inventory(b) - wanted + given > records[b].capacity):
		return false
	# Validate both final capacities before either side changes. Ordinary
	# transfer() twice could partially commit when the first side is full.
	var left: Dictionary = records[a].stock.duplicate(true)
	var right: Dictionary = records[b].stock.duplicate(true)
	var to_right: Array = _extract(left, give, given, filter_a)
	var to_left: Array = _extract(right, want, wanted, filter_b)
	if transfer_title:
		for batch: Dictionary in to_left: batch.merge(Stock.right(a), true)
		for batch: Dictionary in to_right: batch.merge(Stock.right(b), true)
	if not _fits(left, want, to_left) or not _fits(right, give, to_right): return false
	for batch: Dictionary in to_left: _insert(left, want, batch)
	for batch: Dictionary in to_right: _insert(right, give, batch)
	records[a].stock = left
	records[b].stock = right
	_refresh(a)
	_refresh(b)
	transfers += 2
	return true


func equip(id: int, item: String, filter: Dictionary = {}) -> String:
	if filter.is_empty(): filter = Stock.right(id)
	if not Items.valid(item) or not records.has(id) or records[id].kind != "actor" or amount(id, item, filter) <= 0:
		return "empty"
	var slot: String = str(Items.spec(item).get("slot", ""))
	if not Items.SLOTS.has(slot): return "not_equipment"
	var record: Dictionary = records[id]
	var previous: Dictionary = record.equipment.get(slot, {})
	var final_count: int = count_inventory(id) - 1 + int(not previous.is_empty())
	if record.capacity >= 0 and final_count > record.capacity: return "no_capacity"
	# All validation precedes mutation. Equipped items stay in the same audit total.
	var next_stock: Dictionary = record.stock.duplicate(true)
	var selected: Dictionary = _extract(next_stock, item, 1, filter)[0]
	if not previous.is_empty():
		var old_batch: Dictionary = Stock.attribution(previous)
		old_batch["count"] = 1
		if not _fits(next_stock, previous.item, [old_batch]): return "no_capacity"
		_insert(next_stock, previous.item, old_batch)
	selected.erase("count")
	selected["item"] = item
	record.stock = next_stock
	record.equipment[slot] = selected
	_refresh(id)
	return "equipped"


func unequip(id: int, slot: String, destination: int = 0, replacement: Dictionary = {}) -> String:
	if not records.has(id) or not records[id].get("equipment", {}).has(slot): return "empty"
	if destination == 0: destination = id
	if not records.has(destination): return "invalid_target"
	if records[destination].capacity >= 0 and count_inventory(destination) >= records[destination].capacity: return "no_capacity"
	var gear: Dictionary = records[id].equipment[slot]
	var batch: Dictionary = Stock.attribution(gear)
	if not replacement.is_empty(): batch.merge(Stock.attribution(replacement), true)
	batch["count"] = 1
	if not _fits(records[destination].stock, gear.item, [batch]): return "no_capacity"
	records[id].equipment.erase(slot)
	_insert(records[destination].stock, gear.item, batch)
	_refresh(id)
	if destination != id: _refresh(destination)
	return "unequipped"


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
		count += Stock.count(records[id].stock, item) # Audit source quantities independently of caches.
		count += Stock.count(records[id].get("materials", {}), item)
		count += Stock.count(records[id].get("work_stock", {}), item)
		for equipped: Dictionary in records[id].get("equipment", {}).values(): count += int(equipped.item == item)
	return count


func layout() -> Dictionary:
	var result: Dictionary = {}
	for id: int in records:
		var record: Dictionary = records[id]
		if record.tile >= 0:
			result[id] = {"id": id, "kind": record.kind, "definition": record.definition, "tile": record.tile,
				"cells": record.get("cells", PackedInt32Array([record.tile])).duplicate(), "layer": record.get("layer", "ground"),
				"stage": record.get("stage", -1), "vegetation_level": record.get("vegetation_level", 3), "sapient": record.get("sapient", false), "facing": record.get("facing", 0), "construction_started": record.get("construction_started", false)}
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
