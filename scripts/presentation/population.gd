extends MultiMeshInstance2D
## Main-thread rendering adapter: one native upload per adopted display frame.
## GPU interpolates committed positions and samples the existing eight-way atlas.

const Art = preload("res://scripts/presentation/art.gd")
const SHADER = preload("res://scripts/presentation/population.gdshader")
const TILE: float = 32.0
var _shader := ShaderMaterial.new()
var _directions := PackedInt32Array()
var _colors: Array[Color] = []
var _buffer := PackedFloat32Array()
var _health := PackedInt32Array()
var _identities := PackedInt64Array()
var _hurt_until := PackedInt64Array()
var _epoch: int = -1
var fog_enabled: bool = false
var actor_count: int = 0
var _scenery: Node2D
var _scenery_revision: int = -1
const ORDER_STRIDE: int = 1048576


func configure(count: int) -> void:
	_colors.clear()
	_shader.shader = SHADER
	material = _shader
	texture = Art.ACTORS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = count
	actor_count = count
	_shader.set_shader_parameter("world_atlas", Art.WORLD)
	_directions.resize(count)
	_directions.fill(4)
	_buffer.resize(count * 16)
	_health.resize(count)
	_identities.resize(count)
	_hurt_until.resize(count)
	_health.fill(0)
	_identities.fill(0)
	_hurt_until.fill(0)
	for index: int in count:
		_buffer[index * 16] = 1.0
		_buffer[index * 16 + 5] = 1.0
		_buffer[index * 16 + 11] = 1.0
	for index: int in count:
		_colors.append(Color(1.6, 1.12, 0.70) if index == 0 else [Color(0.85, 1.10, 1.18), Color(1.4, 0.88, 1.12), Color(1.1, 1.12, 0.78), Color(1.25, 0.95, 0.8)][index % 4])
	multimesh.custom_aabb = AABB(Vector3(0, 0, -1), Vector3(512 * TILE, 512 * TILE, 2))


func adopt(frame: RefCounted, previous: RefCounted, current_pose: RefCounted) -> void:
	if actor_count != frame.positions.size():
		configure(frame.positions.size())
	if _epoch != frame.epoch:
		_epoch = frame.epoch
		_identities.fill(0)
		_hurt_until.fill(0)
		_directions.fill(4)
	var buffer: PackedFloat32Array = _buffer
	for index: int in frame.positions.size():
		var id: int = frame.ids[index]
		var same_current: bool = index < current_pose.ids.size() and current_pose.ids[index] == id
		var same_previous: bool = index < previous.ids.size() and previous.ids[index] == id
		var current: Vector2 = (current_pose.positions[index] if same_current else frame.positions[index]) * TILE
		var from: Vector2 = previous.positions[index] * TILE if same_current and same_previous else current
		var delta: Vector2 = current - from
		if _identities[index] != id:
			_directions[index] = 4
			_hurt_until[index] = 0
		if not delta.is_zero_approx():
			_directions[index] = Art.facing(delta, _directions[index])
		var offset: int = index * 16
		# Native 2D transform = two padded rows (8 floats), then RGBA/custom.
		buffer[offset + 3] = current.x
		buffer[offset + 7] = current.y
		var color: Color = _colors[index]
		buffer[offset + 8] = color.r
		buffer[offset + 9] = color.g
		buffer[offset + 10] = color.b
		buffer[offset + 11] = 1.0 if id > 0 and (not fog_enabled or id == 1 or (index < frame.visible.size() and frame.visible[index] != 0)) else 0.0
		buffer[offset + 12] = from.x
		buffer[offset + 13] = from.y
		buffer[offset + 14] = _directions[index]
		var clip: int = frame.visuals[index] if index < frame.visuals.size() else Art.Clip.IDLE
		if _identities[index] == id and frame.health[index] < _health[index]:
			_hurt_until[index] = frame.world_ms + 180
		_identities[index] = id
		_health[index] = frame.health[index]
		if frame.health[index] <= 0:
			clip = Art.Clip.DEAD
		elif _hurt_until[index] > frame.world_ms:
			clip = Art.Clip.HURT
		elif frame.flight[index] > 0 and clip in [Art.Clip.IDLE, Art.Clip.WALK]:
			clip = Art.Clip.FLY
		elif not delta.is_zero_approx() and clip in [Art.Clip.IDLE, Art.Clip.WALK]:
			clip = Art.Clip.WALK
		buffer[offset + 15] = float(int(not delta.is_zero_approx()) + int(frame.radii[index] > 0.5) * 2 + int(frame.flight[index] > 0) * 4 + clip * 8 + int(id % 11) * 256)
	_compose(buffer)


func interpolate(alpha: float, at_ms: int) -> void:
	_shader.set_shader_parameter(&"alpha", alpha)
	_shader.set_shader_parameter(&"world_ms", float(posmod(at_ms, 14400)))


func scenery(value: Node2D, visibility: Texture2D) -> bool:
	_scenery = value
	_shader.set_shader_parameter("visible_map", visibility)
	_shader.set_shader_parameter("use_fog", fog_enabled)
	var changed: bool = _scenery_revision != value.revision
	_scenery_revision = value.revision
	return changed


func _compose(actors: PackedFloat32Array) -> void:
	# Native numeric sort plus a linear merge. Entire sprites share painter order
	# across static scenery and interpolated actors, without per-actor Nodes.
	if _scenery == null or _scenery.order.is_empty():
		multimesh.instance_count = actor_count
		multimesh.buffer = actors
		return
	var order := PackedFloat64Array()
	for index: int in actor_count:
		order.append(float(int(actors[index * 16 + 7] * 256.0) * ORDER_STRIDE + index))
	order.sort()
	var merged := PackedFloat32Array()
	var a: int = 0
	var b: int = 0
	while a < order.size() or b < _scenery.order.size():
		var use_actor: bool = b == _scenery.order.size() or (a < order.size() and order[a] < _scenery.order[b])
		var source: PackedFloat32Array = actors if use_actor else _scenery.buffer
		var key: float = order[a] if use_actor else _scenery.order[b]
		var offset: int = (int(key) % ORDER_STRIDE) * 16
		merged.append_array(source.slice(offset, offset + 16))
		if use_actor: a += 1
		else: b += 1
	var count: int = merged.size() / 16
	if multimesh.instance_count != count:
		multimesh.instance_count = count
	multimesh.buffer = merged
