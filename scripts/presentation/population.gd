extends MultiMeshInstance2D
## Main-thread rendering adapter: one native upload per adopted display frame.
## GPU interpolates committed positions and samples the existing eight-way atlas.

const Art = preload("res://scripts/presentation/art.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const OPERATION_CLIPS: Dictionary = {
	"construct": Art.Clip.BUILD, "continue_build": Art.Clip.BUILD, "demolish": Art.Clip.BUILD, "fit_eaves": Art.Clip.BUILD,
	"cook": Art.Clip.CRAFT, "cut": Art.Clip.HARVEST, "gather": Art.Clip.HARVEST, "mine": Art.Clip.HARVEST, "uproot": Art.Clip.HARVEST,
	"tend": Art.Clip.WATER, "sow": Art.Clip.WATER, "plant": Art.Clip.WATER,
	"rest": Art.Clip.REST, "eat": Art.Clip.EAT, "study": Art.Clip.READ, "learn": Art.Clip.READ,
	"talk": Art.Clip.READ, "trade": Art.Clip.READ, "practice": Art.Clip.MEDITATE}
const SHADER = preload("res://scripts/presentation/population.gdshader")
const TILE: float = Art.TILE
var _shader := ShaderMaterial.new()
var _directions := PackedInt32Array()
var _colors: Array[Color] = []
var _buffer := PackedFloat32Array()
var _identities := PackedInt64Array()
var _epoch: int = -1
var fog_enabled: bool = false
var feedback: Node2D
var actor_count: int = 0
var _scenery: Node2D
var _scenery_revision: int = -1
var _motion_texture: ImageTexture
var _motion_pose: RefCounted
var _motion_headers: Dictionary = {}
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
	_identities.resize(count)
	_identities.fill(0)
	for index: int in count:
		_buffer[index * 16] = 1.0
		_buffer[index * 16 + 5] = 1.0
		_buffer[index * 16 + 11] = 1.0
	for index: int in count:
		_colors.append(Color(1.6, 1.12, 0.70) if index == 0 else [Color(0.85, 1.10, 1.18), Color(1.4, 0.88, 1.12), Color(1.1, 1.12, 0.78), Color(1.25, 0.95, 0.8)][index % 4])
	multimesh.custom_aabb = AABB(Vector3(0, 0, -1), Vector3(512 * TILE, 512 * TILE, 2))


func adopt(frame: RefCounted, previous: RefCounted, current_pose: RefCounted, actions: Dictionary = {}, at_ms: int = 0) -> void:
	if actor_count != frame.positions.size():
		configure(frame.positions.size())
	if _epoch != frame.epoch:
		_epoch = frame.epoch
		_identities.fill(0)
		_directions.fill(4)
	if _motion_pose != current_pose:
		_motion_pose = current_pose
		_motion_headers = {}
		var values := PackedFloat32Array()
		for slot: int in current_pose.motion:
			var knots: PackedVector3Array = current_pose.motion[slot]
			var header: int = values.size() / 4
			_motion_headers[slot] = header + 1
			values.append_array(PackedFloat32Array([float(header + 1), float(knots.size()), 0.0, 0.0]))
			for point: Vector3 in knots:
				var foot: Vector2 = Art.body_foot(Vector2(point.x, point.y)) * TILE
				values.append_array(PackedFloat32Array([foot.x, foot.y, point.z, 0.0]))
		var width: int = mini(1024, maxi(1, values.size() / 4))
		var height: int = maxi(1, ceili(float(values.size()) / 4 / width))
		values.resize(width * height * 4)
		var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBAF, values.to_byte_array())
		if _motion_texture == null or _motion_texture.get_width() != width or _motion_texture.get_height() != height:
			_motion_texture = ImageTexture.create_from_image(image)
			_shader.set_shader_parameter("motion_map", _motion_texture)
		else:
			_motion_texture.update(image)
	var buffer: PackedFloat32Array = _buffer
	var hurts: Dictionary = {}
	for reaction: Dictionary in current_pose.reaction_segments:
		if at_ms >= int(reaction.stun_from) and at_ms < int(reaction.stun_until) and at_ms >= int(reaction.from_ms) and at_ms < int(reaction.until_ms): hurts[reaction.actor] = true
	for index: int in frame.positions.size():
		var id: int = frame.ids[index]
		var same_current: bool = index < current_pose.ids.size() and current_pose.ids[index] == id
		var same_previous: bool = index < previous.ids.size() and previous.ids[index] == id
		var current: Vector2 = Art.body_foot(current_pose.positions[index] if same_current else frame.positions[index]) * TILE
		var from: Vector2 = Art.body_foot(previous.positions[index]) * TILE if same_current and same_previous else current
		var delta: Vector2 = current - from
		if _identities[index] != id:
			_directions[index] = 4
		if index < frame.aims.size():
			var direction: Vector2 = actions[id].direction if actions.has(id) and actions[id].visual != "evade" else frame.aims[index]
			_directions[index] = Art.facing(direction, _directions[index])
		var offset: int = index * 16
		# Native 2D transform = two padded rows (8 floats), then RGBA/custom.
		buffer[offset + 3] = current.x
		buffer[offset + 7] = current.y
		var color: Color = _colors[index]
		if feedback != null: color *= feedback.tint(id, at_ms)
		buffer[offset + 8] = color.r
		buffer[offset + 9] = color.g
		buffer[offset + 10] = color.b
		buffer[offset + 11] = 1.0 if id > 0 and (not fog_enabled or id == 1 or (index < frame.visible.size() and frame.visible[index] != 0)) else 0.0
		if frame.entities.has(id): buffer[offset + 11] = 0.0 # Companion glyph is drawn by CombatShapes.
		buffer[offset + 12] = from.x
		buffer[offset + 13] = from.y
		var motion_header: int = int(_motion_headers.get(index, 0)) if same_current and same_previous else 0
		buffer[offset + 14] = _directions[index] + motion_header * 8
		var clip: int = Art.Clip.IDLE
		var mode: int = frame.modes[index]
		if mode == Units.Mode.ACTION and frame.operations.has(id):
			clip = OPERATION_CLIPS.get(Operations.OPERATIONS[frame.operations[id]].handler, Art.Clip.IDLE)
		elif mode == Units.Mode.HARVEST and not frame.combat.has(id):
			clip = Art.Clip.HARVEST
		if actions.has(id) and actions[id].visual != "evade": clip = Art.Clip.SHOOT if actions[id].visual == "shoot" else Art.Clip.MELEE
		var hurt: bool = hurts.has(id)
		if frame.paused or at_ms >= frame.world_ms:
			var reaction: Dictionary = frame.reactions.get(id, {})
			hurt = at_ms >= int(reaction.get("stun_from", 0)) and at_ms < int(reaction.get("stun_until", 0))
		_identities[index] = id
		if frame.health[index] <= 0:
			clip = Art.Clip.DEAD
		elif hurt:
			clip = Art.Clip.HURT
		elif frame.flight[index] > 0 and clip in [Art.Clip.IDLE, Art.Clip.WALK]:
			clip = Art.Clip.FLY
		elif not delta.is_zero_approx() and clip in [Art.Clip.IDLE, Art.Clip.WALK]:
			clip = Art.Clip.WALK
		buffer[offset + 15] = float(int(not delta.is_zero_approx()) + int(frame.radii[index] > 0.5) * 2 + int(frame.flight[index] > 0) * 4 + clip * 8 + int(id % 11) * 256)
		if actions.has(id) and clip in [Art.Clip.MELEE, Art.Clip.SHOOT]:
			var state: Dictionary = actions[id]
			var keyframe: int = 0
			if at_ms >= int(state.recovery_ms): keyframe = 3
			elif at_ms >= int(state.active_ms): keyframe = 1 + clampi(int(float(at_ms - int(state.active_ms)) / maxi(1, int(state.recovery_ms) - int(state.active_ms)) * 2), 0, 1)
			buffer[offset + 15] += 4096 + keyframe * 8192
		if index < frame.actor_sprites.size() and frame.actor_sprites[index] != 0:
			buffer[offset + 15] += Art.ACTOR_VARIANT_BIT
	_buffer = buffer
	_compose(buffer)


func interpolate(alpha: float, at_ms: int) -> void:
	_shader.set_shader_parameter(&"alpha", alpha)
	_shader.set_shader_parameter(&"world_ms", float(posmod(at_ms, 14400)))


func scenery(value: Node2D, visibility: Texture2D, fog_mask: Texture2D = null) -> bool:
	_scenery = value
	_shader.set_shader_parameter("visible_map", visibility)
	_shader.set_shader_parameter("use_fog", fog_enabled)
	_shader.set_shader_parameter("fog_mask", fog_mask)
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
		order.append(float(Art.depth(actors[index * 16 + 7]) * ORDER_STRIDE + index))
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
