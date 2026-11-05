class_name SimEnvironmentFieldIndex
extends RefCounted
## Rebuildable source projections for the isolated F0 solver, not an item owner.
## Each id refers to one original object/pile. Quantity, custody, energy and
## source lifecycle stay with the caller. No scene tree, clock or file access.

const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const CHANNELS: int = 7 # metal, wood, water, fire, earth, hot, cold
const BUCKET_SIZE: int = 16
const MAX_AXIS: int = 4096
const MAX_CAPACITY: int = 4194304

var _size := Vector2i.ZERO
var _capacity: int = 0
var _sources: Dictionary[String, Dictionary] = {}
var _buckets: Dictionary[Vector2i, Array] = {}
var _radius_counts: Dictionary[int, int] = {}
var _max_radius: int = 0
var _kernel_tables: Dictionary[int, PackedInt64Array] = {}
var _revision: int = 0


func configure(size: Vector2i, capacity: int = 65536) -> bool:
	if _capacity != 0 or size.x < 1 or size.y < 1 or size.x > MAX_AXIS or size.y > MAX_AXIS or capacity < 1 or capacity > MAX_CAPACITY:
		return false
	_size = size
	_capacity = capacity
	return true


func set_source(source: Dictionary) -> Dictionary:
	if _capacity == 0:
		return _failure("not_configured")
	var checked: Dictionary = _validate(source)
	if not bool(checked.ok):
		return checked
	var row: Dictionary = checked.row
	var id: String = row.id
	var previous: Dictionary = _sources.get(id, {})
	if previous == row:
		return {"ok": true, "changed": false, "revision": _revision, "affected": Rect2i()}
	if previous.is_empty() and _sources.size() >= _capacity:
		return _failure("source_capacity")
	# Validate everything before changing the derived index. Build the bounded
	# kernel table before mutation; only encountered radii allocate a table.
	_ensure_kernel(int(row.radius))
	var affected: Rect2i = _coverage(row)
	if not previous.is_empty():
		affected = affected.merge(_coverage(previous))
		_unindex(previous, int(row.radius))
	_sources[id] = row
	_index(row)
	_revision += 1
	return {"ok": true, "changed": true, "revision": _revision, "affected": affected.intersection(Rect2i(Vector2i.ZERO, _size))}


func remove_source(id: String) -> Dictionary:
	if _capacity == 0:
		return _failure("not_configured")
	if not _sources.has(id):
		return _failure("unknown_source")
	var row: Dictionary = _sources[id]
	var affected: Rect2i = _coverage(row).intersection(Rect2i(Vector2i.ZERO, _size))
	_unindex(row)
	_sources.erase(id)
	_revision += 1
	return {"ok": true, "revision": _revision, "affected": affected}


func sample_base(cell: Vector2i) -> Dictionary:
	if _capacity == 0:
		return _failure("not_configured")
	if not _inside(cell):
		return _failure("outside_map")
	var values := PackedInt64Array()
	values.resize(CHANNELS)
	var winners: Array[String] = []
	winners.resize(CHANNELS)
	winners.fill("")
	var checked: int = 0
	if not _sources.is_empty():
		var low: Vector2i = _bucket(Vector2i(maxi(0, cell.x - _max_radius), maxi(0, cell.y - _max_radius)))
		var high: Vector2i = _bucket(Vector2i(mini(_size.x - 1, cell.x + _max_radius), mini(_size.y - 1, cell.y + _max_radius)))
		for y: int in range(low.y, high.y + 1):
			for x: int in range(low.x, high.x + 1):
				for id: String in _buckets.get(Vector2i(x, y), []):
					checked += 1
					var row: Dictionary = _sources[id]
					var dx: int = absi(cell.x - int(row.cell.x))
					var dy: int = absi(cell.y - int(row.cell.y))
					var radius: int = int(row.radius)
					if dx >= radius or dy >= radius:
						continue
					var table: PackedInt64Array = _kernel_tables[radius]
					var weight: int = table[dy * radius + dx]
					if weight == 0:
						continue
					var channels: PackedInt64Array = row.channels
					for channel: int in CHANNELS:
						@warning_ignore("integer_division")
						var contribution: int = (channels[channel] * weight + Rules.SCALE / 2) / Rules.SCALE
						if contribution > values[channel] or contribution > 0 and contribution == values[channel] and id < winners[channel]:
							values[channel] = contribution
							winners[channel] = id
	return {"ok": true, "channels": values, "winners": winners, "revision": _revision, "candidate_count": checked}


func diagnostics() -> Dictionary:
	var kernel_values: int = 0
	for table: PackedInt64Array in _kernel_tables.values():
		kernel_values += table.size()
	return {"source_count": _sources.size(), "bucket_count": _buckets.size(), "kernel_values": kernel_values, "max_radius": _max_radius, "revision": _revision}


func _validate(source: Dictionary) -> Dictionary:
	if source.size() != 4 or not source.has("id") or not source.has("cell") or not source.has("radius") or not source.has("channels"):
		return _failure("source_shape")
	if not source.id is String or source.id.is_empty() or source.id.length() > 128:
		return _failure("source_id")
	if not source.cell is Vector2i or not _inside(source.cell):
		return _failure("source_cell")
	if not source.radius is int or source.radius < 1 or source.radius > Rules.MAX_RADIUS:
		return _failure("source_radius")
	if not source.channels is PackedInt64Array and not source.channels is Array:
		return _failure("source_channels")
	if source.channels.size() != CHANNELS:
		return _failure("source_channels")
	var channels := PackedInt64Array()
	for value: Variant in source.channels:
		if not value is int or value < 0 or value > Rules.MAX_GRADE_MILLI:
			return _failure("source_channel_value")
		channels.append(value)
	return {"ok": true, "row": {"id": source.id, "cell": source.cell, "radius": source.radius, "channels": channels}}


func _index(row: Dictionary) -> void:
	var bucket: Vector2i = _bucket(row.cell)
	if not _buckets.has(bucket):
		_buckets[bucket] = []
	_buckets[bucket].append(row.id)
	var radius: int = int(row.radius)
	_radius_counts[radius] = _radius_counts.get(radius, 0) + 1
	_max_radius = maxi(_max_radius, radius)


func _unindex(row: Dictionary, keep_radius: int = -1) -> void:
	var bucket: Vector2i = _bucket(row.cell)
	_buckets[bucket].erase(row.id)
	if _buckets[bucket].is_empty():
		_buckets.erase(bucket)
	var radius: int = int(row.radius)
	_radius_counts[radius] -= 1
	if _radius_counts[radius] == 0:
		_radius_counts.erase(radius)
		# No source needs this radius anymore. Retire its rebuildable template.
		if radius != keep_radius:
			_kernel_tables.erase(radius)
		if _max_radius == radius:
			_max_radius = 0
			for remaining: int in _radius_counts:
				_max_radius = maxi(_max_radius, remaining)


func _ensure_kernel(radius: int) -> void:
	if _kernel_tables.has(radius):
		return
	var table := PackedInt64Array()
	table.resize(radius * radius)
	for y: int in radius:
		for x: int in radius:
			table[y * radius + x] = int(Rules.kernel(Vector2i(x, y), radius).weight)
	_kernel_tables[radius] = table


func _coverage(row: Dictionary) -> Rect2i:
	var radius: int = int(row.radius)
	return Rect2i(row.cell - Vector2i(radius, radius), Vector2i(radius * 2 + 1, radius * 2 + 1))


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _size.x and cell.y < _size.y


func _bucket(cell: Vector2i) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(cell.x / BUCKET_SIZE, cell.y / BUCKET_SIZE)


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
