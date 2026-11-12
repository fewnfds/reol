extends MultiMeshInstance2D
## Main-thread rendering adapter: one native upload per adopted display frame.
## GPU interpolates committed positions and samples the existing eight-way atlas.

const Appearance = preload("res://scripts/entities/humanoid_appearance.gd")
const SHADER = preload("res://scripts/presentation/population.gdshader")
const TILE: float = 32.0
var _shader := ShaderMaterial.new()
var _directions := PackedInt32Array()
var _colors: Array[Color] = []
var _buffer := PackedFloat32Array()


func configure(count: int) -> void:
	var appearance: RefCounted = Appearance.shared()
	_shader.shader = SHADER
	for layer: String in ["body", "robe", "detail"]:
		_shader.set_shader_parameter(layer, appearance.textures[layer])
	material = _shader
	texture = appearance.textures.body
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var quad := QuadMesh.new()
	quad.size = Vector2(96.0, 96.0)
	quad.center_offset = Vector3(0.0, -17.0, 0.0)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = count
	_directions.resize(count)
	_directions.fill(4)
	_buffer.resize(count * 16)
	for index: int in count:
		_buffer[index * 16] = 1.0
		_buffer[index * 16 + 5] = 1.0
		_buffer[index * 16 + 11] = 1.0
	for index: int in count:
		_colors.append(Color(0.95, 0.72, 0.18) if index == 0 else Color.from_hsv(fposmod(index * 0.618, 1.0), 0.4, 0.85))
	multimesh.custom_aabb = AABB(Vector3(0, 0, -1), Vector3(512 * TILE, 512 * TILE, 2))


func adopt(frame: RefCounted, previous: PackedVector2Array, current_points: PackedVector2Array) -> void:
	var buffer: PackedFloat32Array = _buffer
	for index: int in frame.positions.size():
		var current: Vector2 = current_points[index] * TILE
		var from: Vector2 = previous[index] * TILE
		var delta: Vector2 = current - from
		if not delta.is_zero_approx():
			_directions[index] = Appearance.direction_index(delta, _directions[index], 5.0)
		var offset: int = index * 16
		# Native 2D transform = two padded rows (8 floats), then RGBA/custom.
		buffer[offset + 3] = current.x
		buffer[offset + 7] = current.y
		var color: Color = _colors[index] if frame.health[index] > 0 else Color(0.3, 0.3, 0.3)
		buffer[offset + 8] = color.r
		buffer[offset + 9] = color.g
		buffer[offset + 10] = color.b
		buffer[offset + 12] = from.x
		buffer[offset + 13] = from.y
		buffer[offset + 14] = _directions[index]
		buffer[offset + 15] = float(not delta.is_zero_approx())
	multimesh.buffer = buffer


func interpolate(alpha: float, at_ms: int) -> void:
	_shader.set_shader_parameter(&"alpha", alpha)
	_shader.set_shader_parameter(&"cursors", Vector2i(posmod(at_ms, 1600), posmod(at_ms, 900)))
