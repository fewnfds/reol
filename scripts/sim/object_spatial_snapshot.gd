class_name SimObjectSpatialSnapshot
extends RefCounted
## Bounded, detached geometry for an explicitly supplied set of references.
## This does not enumerate the world, own object state, or establish that the
## captured locations remain current after a world mutation. A caller must
## capture a new snapshot before using changed source state. The output is an
## authority/debug projection, not player knowledge or movement occupancy.

const BUCKET_SHIFT: int = 4
const BUCKET_SIZE: int = 1 << BUCKET_SHIFT
const MAP_AXIS_LIMIT: int = 8192
const BUCKETS_PER_AXIS: int = MAP_AXIS_LIMIT >> BUCKET_SHIFT
const MAX_OBJECTS: int = 262144
const MAX_ENTRIES: int = 1048576
const MAX_CELLS_PER_OBJECT: int = 4096
const MAX_REFERENCE_FIELDS: int = 8
const MAX_REFERENCE_PART_LENGTH: int = 512
const MAX_REFERENCE_KEY_LENGTH: int = 8192
const MAX_REFERENCE_CHARACTERS: int = 33554432
const MAX_RELATION_LENGTH: int = 128
const MAX_RELATIONS: int = 64
const LAYERS: Array[String] = ["ground", "roof", "air", "container", "planned"]

var _object_limit: int
var _entry_limit: int
var _limits_valid: bool
var _sealed: bool = false
var _captured_world_time_ms: int = -1
var _reference_characters: int = 0

# A sorted flat-string JSON key represents only the external reference, not an
# object or any owner state. Packed arrays keep each cell entry to three ints.
var _reference_keys: Array[String] = []
var _reference_ids: Dictionary[String, int] = {}
var _object_layers := PackedInt32Array()
var _object_relations := PackedInt32Array()
var _relation_ids: Dictionary[String, int] = {}
var _relations: Array[String] = []
var _entry_cells := PackedInt32Array()
var _entry_objects := PackedInt32Array()
var _entry_next := PackedInt32Array()
var _bucket_heads: Dictionary[int, int] = {}


func _init(max_objects: int = MAX_OBJECTS, max_entries: int = MAX_ENTRIES) -> void:
	_object_limit = max_objects
	_entry_limit = max_entries
	_limits_valid = max_objects > 0 and max_objects <= MAX_OBJECTS and max_entries > 0 and max_entries <= MAX_ENTRIES


func append(reference: Dictionary, cells: Array[Vector2i], layer: String, relation: String) -> Dictionary:
	if not _limits_valid:
		return _failure("invalid_limits")
	if _sealed:
		return _failure("sealed")
	if not _valid_reference(reference):
		return _failure("invalid_reference")
	if not LAYERS.has(layer):
		return _failure("invalid_layer")
	if relation.is_empty() or relation.length() > MAX_RELATION_LENGTH:
		return _failure("invalid_relation")
	if cells.is_empty() or cells.size() > MAX_CELLS_PER_OBJECT:
		return _failure("invalid_cells")
	var reference_key: String = JSON.stringify(reference, "", true)
	if reference_key.length() > MAX_REFERENCE_KEY_LENGTH:
		return _failure("invalid_reference")
	if _reference_ids.has(reference_key):
		return _failure("duplicate_reference")
	if _reference_keys.size() >= _object_limit:
		return _failure("object_capacity")
	if reference_key.length() > MAX_REFERENCE_CHARACTERS - _reference_characters:
		return _failure("reference_capacity")
	# Check the whole input before mutating anything. A repeated cell for the
	# same object has one spatial entry, and is not a second physical object.
	var unique: Dictionary[Vector2i, bool] = {}
	var checked: Array[Vector2i] = []
	for cell: Vector2i in cells:
		if not _inside(cell):
			return _failure("invalid_cell")
		if not unique.has(cell):
			unique[cell] = true
			checked.append(cell)
	if checked.size() > _entry_limit - _entry_cells.size():
		return _failure("entry_capacity")
	var relation_id: int = int(_relation_ids.get(relation, -1))
	if relation_id < 0:
		if _relations.size() >= MAX_RELATIONS:
			return _failure("relation_capacity")
		relation_id = _relations.size()
		_relation_ids[relation] = relation_id
		_relations.append(relation)
	var object_id: int = _reference_keys.size()
	_reference_keys.append(reference_key)
	_reference_characters += reference_key.length()
	_reference_ids[reference_key] = object_id
	_object_layers.append(LAYERS.find(layer))
	_object_relations.append(relation_id)
	for cell: Vector2i in checked:
		var bucket: int = _bucket_key(cell)
		var entry: int = _entry_cells.size()
		_entry_cells.append(cell.y * MAP_AXIS_LIMIT + cell.x)
		_entry_objects.append(object_id)
		_entry_next.append(int(_bucket_heads.get(bucket, -1)))
		_bucket_heads[bucket] = entry
	return {"ok": true}


func seal(world_time_ms: int) -> Dictionary:
	if not _limits_valid:
		return _failure("invalid_limits")
	if _sealed:
		return _failure("sealed")
	if world_time_ms < 0:
		return _failure("invalid_time")
	_captured_world_time_ms = world_time_ms
	_sealed = true
	# This build-only uniqueness table is no longer needed for immutable reads.
	_reference_ids.clear()
	return {"ok": true, "scope": "captured_references", "live": false, "world_time_ms": world_time_ms}


func query(area: Rect2i, layer: String = "", relation: String = "", budget: int = 4096) -> Dictionary:
	if not _limits_valid:
		return _query_failure("invalid_limits", 0)
	if not _sealed:
		return _query_failure("unsealed", 0)
	if not _valid_area(area):
		return _query_failure("invalid_area", 0)
	if not layer.is_empty() and not LAYERS.has(layer):
		return _query_failure("invalid_layer", 0)
	if relation.length() > MAX_RELATION_LENGTH:
		return _query_failure("invalid_relation", 0)
	if budget <= 0:
		return _query_failure("invalid_budget", 0)
	var layer_id: int = LAYERS.find(layer) if not layer.is_empty() else -1
	var relation_id: int = int(_relation_ids.get(relation, -2)) if not relation.is_empty() else -1
	var used: int = 0
	var references: Array[Dictionary] = []
	var seen: Dictionary[int, bool] = {}
	# Bounds are half-open. Each visited bucket, each candidate cell entry, and
	# each materialized result consumes one unit. Even a failed query never
	# returns partial references that could be mistaken for a complete answer.
	var right: int = int(area.position.x) + int(area.size.x)
	var bottom: int = int(area.position.y) + int(area.size.y)
	var first_bucket_x: int = area.position.x >> BUCKET_SHIFT
	var first_bucket_y: int = area.position.y >> BUCKET_SHIFT
	var last_bucket_x: int = (right - 1) >> BUCKET_SHIFT
	var last_bucket_y: int = (bottom - 1) >> BUCKET_SHIFT
	for by: int in range(first_bucket_y, last_bucket_y + 1):
		for bx: int in range(first_bucket_x, last_bucket_x + 1):
			if used >= budget:
				return _query_failure("budget_exhausted", used)
			used += 1
			var entry: int = int(_bucket_heads.get(by * BUCKETS_PER_AXIS + bx, -1))
			while entry >= 0:
				if used >= budget:
					return _query_failure("budget_exhausted", used)
				used += 1
				var code: int = _entry_cells[entry]
				@warning_ignore("integer_division")
				var cell_y: int = code / MAP_AXIS_LIMIT
				var cell_x: int = code % MAP_AXIS_LIMIT
				var object_id: int = _entry_objects[entry]
				if cell_x >= area.position.x and cell_x < right and cell_y >= area.position.y and cell_y < bottom and (layer_id < 0 or _object_layers[object_id] == layer_id) and (relation_id == -1 or _object_relations[object_id] == relation_id) and not seen.has(object_id):
					if used >= budget:
						return _query_failure("budget_exhausted", used)
					used += 1
					seen[object_id] = true
					var decoded: Variant = JSON.parse_string(_reference_keys[object_id])
					if not decoded is Dictionary:
						return _query_failure("invalid_snapshot", used)
					references.append(decoded)
				entry = _entry_next[entry]
	return {"ok": true, "complete": true, "references": references, "work_used": used,
		"scope": "captured_references", "live": false, "world_time_ms": _captured_world_time_ms}


func stats() -> Dictionary:
	return {"objects": _reference_keys.size(), "entries": _entry_cells.size(), "buckets": _bucket_heads.size(),
		"reference_characters": _reference_characters, "sealed": _sealed,
		"scope": "captured_references", "live": false, "world_time_ms": _captured_world_time_ms}


static func _valid_reference(reference: Dictionary) -> bool:
	if reference.is_empty() or reference.size() > MAX_REFERENCE_FIELDS:
		return false
	for field: Variant in reference:
		if not field is String or field.is_empty() or field.length() > MAX_REFERENCE_PART_LENGTH:
			return false
		var value: Variant = reference[field]
		if not value is String or value.is_empty() or value.length() > MAX_REFERENCE_PART_LENGTH:
			return false
	return true


static func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < MAP_AXIS_LIMIT and cell.y < MAP_AXIS_LIMIT


static func _valid_area(area: Rect2i) -> bool:
	return _inside(area.position) and area.size.x > 0 and area.size.y > 0 and int(area.position.x) + int(area.size.x) <= MAP_AXIS_LIMIT and int(area.position.y) + int(area.size.y) <= MAP_AXIS_LIMIT


static func _bucket_key(cell: Vector2i) -> int:
	return (cell.y >> BUCKET_SHIFT) * BUCKETS_PER_AXIS + (cell.x >> BUCKET_SHIFT)


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _query_failure(reason: String, work_used: int) -> Dictionary:
	return {"ok": false, "reason": reason, "complete": false, "work_used": work_used,
		"scope": "captured_references", "live": false}
