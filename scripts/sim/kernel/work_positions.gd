extends RefCounted
## Derived work geometry. Definitions own rules; object footprints own placement.
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const CARDINALS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

static func errors(rules: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if not rules is Dictionary: return PackedStringArray(["work_positions must be a dictionary"])
	for operation: Variant in rules:
		var rule: Variant = rules[operation]
		if not operation is String or operation.is_empty() or not rule is Dictionary:
			result.append("Invalid work position operation or rule")
			continue
		if rule.get("mode", "") not in ["same", "adjacent", "stations"]:
			result.append("Unknown work position mode: " + str(operation))
		elif rule.mode == "stations":
			var offsets: Variant = rule.get("cells", [])
			if not offsets is Array or offsets.is_empty() or offsets.size() > 64:
				result.append("Stations require 1 to 64 local cells")
				continue
			for pair: Variant in offsets:
				if not pair is Array or pair.size() != 2:
					result.append("Station must contain two integer coordinates")
					continue
				for coordinate: Variant in pair:
					if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or float(coordinate) != floorf(float(coordinate)) or absf(float(coordinate)) > 64:
						result.append("Invalid station coordinate")
	return result

static func subject(world: RefCounted, target: int) -> Dictionary:
	var record: Dictionary = world.objects.records.get(target, {})
	# A potted plant inherits its physical host's access geometry.
	return world.objects.records.get(int(record.get("host", 0)), record)

static func solid(world: RefCounted, record: Dictionary) -> bool:
	var spec: Dictionary = world.facilities.definitions.get(record.get("definition", ""), {})
	if bool(spec.get("facts", {}).get("movement_blocked", false)): return true
	for tile: int in footprint(record):
		if tile >= 0 and world.terrain.blocked[tile] != 0: return true
	return false

static func footprint(record: Dictionary) -> PackedInt32Array:
	return record.get("cells", PackedInt32Array([int(record.get("tile", -1))]))

static func cells(world: RefCounted, target: int, operation: String) -> PackedInt32Array:
	var record: Dictionary = subject(world, target)
	var spec: Dictionary = world.facilities.definitions.get(record.get("definition", ""), {})
	return layout(record, spec, operation, solid(world, record))

static func layout(record: Dictionary, spec: Dictionary, operation: String, colliding: bool) -> PackedInt32Array:
	# Pure definition/placement calculation, also usable by detached UI previews.
	var result := PackedInt32Array()
	if record.is_empty() or int(record.tile) < 0: return result
	var rules: Dictionary = spec.get("work_positions", {})
	# Construction/demolition use their own access rule, never the finished bench's station.
	var fallback: Dictionary = {} if operation in ["construct", "demolish"] else rules.get("default", {})
	var rule: Dictionary = rules.get(operation, fallback)
	var mode: String = str(rule.get("mode", "adjacent" if colliding else "same"))
	var members: PackedInt32Array = footprint(record)
	match mode:
		"same": return members.duplicate()
		"adjacent":
			for tile: int in members:
				for direction: Vector2i in CARDINALS:
					var cell: Vector2i = Terrain.cell(tile) + direction
					if not _inside(cell): continue
					var neighbour: int = Terrain.index(cell)
					if not members.has(neighbour) and not result.has(neighbour): result.append(neighbour)
		"stations":
			var size: Array = spec.get("size", [1, 1])
			var facing: int = int(record.get("facing", 0))
			for pair: Array in rule.cells:
				var offset := Vector2i(int(pair[0]), int(pair[1]))
				match facing:
					1: offset = Vector2i(int(size[1]) - 1 - offset.y, offset.x)
					2: offset = Vector2i(int(size[0]) - 1 - offset.x, int(size[1]) - 1 - offset.y)
					3: offset = Vector2i(offset.y, int(size[0]) - 1 - offset.x)
				var cell: Vector2i = Terrain.cell(record.tile) + offset
				if _inside(cell) and not result.has(Terrain.index(cell)): result.append(Terrain.index(cell))
	return result

static func permits(world: RefCounted, target: int, operation: String, point: Vector2, radius: float, flying: bool = false) -> bool:
	if not point.is_finite() or not _inside(Vector2i(point.floor())) or not world.terrain.can_stand(point, radius, flying): return false
	if not cells(world, target, operation).has(Terrain.index(Vector2i(point.floor()))): return false
	var record: Dictionary = subject(world, target)
	if solid(world, record):
		for tile: int in footprint(record):
			if world._body_overlaps_tile(point, radius, tile): return false
	var members: PackedInt32Array = footprint(record)
	for tile: int in members:
		var low := Vector2(Terrain.cell(tile))
		if Terrain.blocking_fraction(world.terrain.blocked, point, point.clamp(low, low + Vector2.ONE), members) < 0: return true
	return false

static func candidates(world: RefCounted, target: int, operation: String, origin: Vector2, radius: float, flying: bool) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var record: Dictionary = subject(world, target)
	for tile: int in cells(world, target, operation):
		var point: Vector2 = Terrain.center(tile)
		# Large bodies may stand off-centre within a neighbouring cell. Also keep
		# outside future solid blueprints, whose collision has not been enabled yet.
		if solid(world, record):
			# Resolve the shared edge first. A diagonal member must not push a
			# body sideways unnecessarily before its actual neighbouring edge.
			for pass_index: int in 2:
				for member: int in footprint(record):
					var delta: Vector2i = Terrain.cell(tile) - Terrain.cell(member)
					if (delta.x == 0 or delta.y == 0) != (pass_index == 0): continue
					var low := Vector2(Terrain.cell(member))
					if world._body_overlaps_tile(point, radius, member):
						if delta.x < 0: point.x = low.x - radius - 0.001
						elif delta.x > 0: point.x = low.x + 1 + radius + 0.001
						elif delta.y < 0: point.y = low.y - radius - 0.001
						elif delta.y > 0: point.y = low.y + 1 + radius + 0.001
		point = world.terrain.project_point(point, radius, flying)
		if permits(world, target, operation, point, radius, flying): result.append(point)
	result.sort_custom(func(a: Vector2, b: Vector2): return a.distance_squared_to(origin) < b.distance_squared_to(origin))
	return result

static func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < Terrain.SIZE and cell.y < Terrain.SIZE
