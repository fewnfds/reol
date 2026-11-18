extends RefCounted
## Sprite-alpha selection uses the same atlas, pivots and depth as the 2D batch.
## Ground coordinates remain the authority for placement and skill targeting.
const Art = preload("res://scripts/presentation/art.gd")
static var _world: Image
static var _actors: Image

static func _opaque(image: Image, pixel: Vector2i) -> bool:
	return pixel.x >= 0 and pixel.y >= 0 and pixel.x < image.get_width() and pixel.y < image.get_height() and image.get_pixelv(pixel).a > 0.1

static func hits(host: Node2D, point: Vector2, include_flat: bool) -> Array[int]:
	if _world == null: _world = Art.WORLD.get_image()
	if _actors == null: _actors = Art.ACTORS.get_image()
	var candidates: Array[Dictionary] = []
	var scenery: Node2D = host.object_canvas
	for sort_key: float in scenery.order:
		var index: int = int(sort_key) % scenery.ORDER_STRIDE
		var id: int = scenery.identities[index]
		if host.fog_enabled and not host.frame.perception.memories.has(id): continue
		var rec: Dictionary = scenery.objects[id]
		if not include_flat and rec.get("layer", "") == "floor": continue
		var at: int = index * 16
		var buffer: PackedFloat32Array = scenery.buffer
		var flags: int = int(buffer[at+15])
		var anchor := Vector2((flags >> 11) & 63, (flags >> 17) & 127)
		var position := Vector2(buffer[at+3], buffer[at+7])
		var scale_value := Vector2(buffer[at], buffer[at+5])
		var pixel: Vector2 = (point - position) / scale_value + anchor
		if (flags & 256) != 0 and (not host.fog_enabled or host.frame.perception.tiles[rec.tile] != 0):
			pixel.x -= sin(fmod(host.render_ms / 1000.0, 7200.0) * 1.2 + position.x * 0.03) * -(pixel.y-anchor.y) * 0.012
		if not Rect2(0,0,64,64).has_point(pixel): continue
		var slot: int = int(buffer[at+14])
		if _opaque(_world, Vector2i(pixel.floor()) + Vector2i(slot % 8, slot / 8) * 64):
			candidates.append({"id":id, "key":sort_key, "actor":false})
	var actors: PackedFloat32Array = host.population._buffer
	for slot: int in host.frame.ids.size():
		var id: int = host.frame.ids[slot]
		if id == 0 or (not include_flat and (id == 1 or host.frame.health[slot] <= 0)): continue
		var at: int = slot * 16
		if actors[at+11] <= 0.0: continue
		var flags: int = int(actors[at+15])
		var state: int = (flags >> 3) & 15
		var scale_value: float = 1.6 if (flags & 2) != 0 else 1.0
		var foot: Vector2 = host._displayed(id) * Art.TILE
		var pixel: Vector2 = (point - foot) / scale_value + Vector2(24,42)
		if (flags & 4) != 0 and state != 14: pixel.y += 6.0
		if not Rect2(0,0,48,48).has_point(pixel): continue
		var frame_index: int = int(fmod(posmod(int(host.render_ms),14400) + ((flags >> 8) & 15) * 83.0, 1600.0 if state == 0 else 900.0) / (400.0 if state == 0 else 225.0))
		if (flags & 4096) != 0: frame_index = (flags >> 13) & 3
		if state == 14 or (state == 2 and (flags & 1) == 0): frame_index = 0
		var direction: int = int(actors[at+14]) % 8
		if _opaque(_actors, Vector2i(pixel.floor()) + Vector2i(direction*4+frame_index,state)*48):
			candidates.append({"id":id,"key":float(Art.depth(actors[at+7])*scenery.ORDER_STRIDE+slot),"actor":true})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): return a.key > b.key if a.key != b.key else a.actor and not b.actor)
	var result: Array[int] = []
	for candidate: Dictionary in candidates:
		if not result.has(int(candidate.id)): result.append(int(candidate.id))
	return result
