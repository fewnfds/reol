extends RefCounted
## One temporary-pack catalog. No gameplay definitions or simulation ownership.

const WORLD = preload("res://assets/art/world.png")
const ACTORS = preload("res://assets/art/actors.png")
const GROUND = preload("res://assets/art/terrain.png")
const Clip = preload("res://scripts/sim/kernel/frame.gd").Visual
const TILE: float = 32.0
const BODY_FOOT_OFFSET := Vector2(0.0, 0.5)
static var _catalog: Dictionary = {}
static var _icons: Dictionary = {}


static func body_foot(position: Vector2) -> Vector2:
	# Logical positions stay continuous. A cell-centred body is drawn with its
	# feet at the cell's bottom centre, without snapping as it crosses cells.
	return position + BODY_FOOT_OFFSET


static func body_position(foot: Vector2) -> Vector2:
	return foot - BODY_FOOT_OFFSET


static func footprint_foot(extent: Rect2i) -> Vector2:
	return Vector2(extent.position.x + extent.size.x * 0.5, extent.end.y)


static func catalog() -> Dictionary:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/catalog.json"))
	return _catalog


static func region(key: String) -> Rect2:
	var value: Array = catalog().entries.get(key, catalog().entries.rock).rect
	return Rect2(value[0], value[1], value[2], value[3])


static func icon(key: String) -> Texture2D:
	if not _icons.has(key):
		var texture := AtlasTexture.new()
		texture.atlas = WORLD
		texture.region = region(key)
		_icons[key] = texture
	return _icons[key]


static func facing(delta: Vector2, previous: int) -> int:
	if delta.is_zero_approx():
		return previous
	var angle: float = atan2(delta.x, -delta.y)
	if absf(wrapf(angle - previous * PI * 0.25, -PI, PI)) <= PI * 0.125 + deg_to_rad(5.0):
		return previous
	return posmod(roundi(angle / (PI * 0.25)), 8)
