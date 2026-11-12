class_name HumanoidSprite
extends Sprite2D
## Disposable native drawing of the original, shared humanoid atlas family.
## The shader sees committed time only, never host TIME or unfinished rules.

const SHADER = preload("res://scripts/entities/humanoid_sprite.gdshader")
const LAYERS: Array[String] = ["sword_far", "jade_far", "cape_far", "body", "robe", "detail", "cape_near", "jade_near", "sword_near"]
const SLOTS: Array[String] = ["preview_sword", "preview_jade", "outer", "base", "body", "body", "outer", "preview_jade", "preview_sword"]
const TINTS: Array[String] = ["none", "none", "outer", "none", "body", "none", "outer", "none", "none"]
static var _material: ShaderMaterial
static var _appearance: HumanoidAppearance
static var _published_ms: int = -1
var _clip := Vector4i(-1, -1, -1, -1)
var _robe := Color(-1, -1, -1, -1)
var _cape := Color(-1, -1, -1, -1)
var _clothing: Dictionary = {}
var _base_robe := Color(-1, -1, -1, -1)


static func publish_time(at_ms: int) -> void:
	if _material == null or _published_ms == at_ms:
		return
	var actions: Dictionary = _appearance.definition.actions
	_material.set_shader_parameter(&"clip_cursors", Vector3i(posmod(at_ms, int(actions.idle.cycle_ms)), posmod(at_ms, int(actions.walk.cycle_ms)), posmod(at_ms, int(actions.gesture.cycle_ms))))
	_published_ms = at_ms


func configure() -> bool:
	var appearance: HumanoidAppearance = HumanoidAppearance.shared()
	# This adapter only accepts the atlas/layer contract it can draw exactly.
	# The ordinary vector/layer renderer remains the missing/custom-asset path.
	if appearance != _appearance or _material == null:
		if appearance.textures.size() != LAYERS.size():
			return false
		for id: String in LAYERS:
			if not appearance.textures.has(id):
				return false
		for layer: Dictionary in appearance.definition.layers:
			var index: int = LAYERS.find(str(layer.id))
			if index < 0 or layer.slot != SLOTS[index] or layer.tint != TINTS[index]:
				return false
		for group: Dictionary in appearance.definition.frames.values():
			for frames: Array in group.values():
				for frame: Dictionary in frames:
					if frame.layer_order != LAYERS:
						return false
		_appearance = appearance
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		for id: String in LAYERS:
			_material.set_shader_parameter(StringName(id), appearance.textures[id])
		var definition: Dictionary = appearance.definition
		_material.set_shader_parameter(&"atlas_grid", Vector2(float(definition.atlas_size[0]) / float(definition.frame_size[0]), float(definition.atlas_size[1]) / float(definition.frame_size[1])))
		for action: String in HumanoidAppearance.ACTIONS:
			var clip: Dictionary = definition.actions[action]
			_material.set_shader_parameter(StringName(action + "_clip"), Vector3i(clip.column, clip.frames, clip.cycle_ms))
		_published_ms = -1
	texture = appearance.textures.body
	material = _material
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	centered = false
	region_enabled = true
	region_rect = Rect2(0, 0, appearance.definition.frame_size[0], appearance.definition.frame_size[1])
	return true


func present(foot: Vector2, robe: Color, clothing: Dictionary, pose: Dictionary) -> void:
	var definition: Dictionary = _appearance.definition
	var point: Vector2 = foot - Vector2(definition.origin[0], definition.origin[1])
	if position != point:
		position = point
	var action: String = str(pose.get("action", "idle"))
	var clip_index: int = HumanoidAppearance.ACTIONS.find(action)
	if clip_index < 0:
		clip_index = 1 if bool(pose.get("moving", false)) else 0
	var direction: int = int(pose.get("direction_index", HumanoidAppearance.DEFAULT_DIRECTION))
	if not pose.has("direction_index"):
		direction = HumanoidAppearance.direction_index(pose.get("direction", Vector2.DOWN), int(pose.get("previous_direction", -1)), float(definition.turn_hysteresis_degrees))
	var clip := Vector4i(direction, clip_index, posmod(int(pose.get("started_ms", 0)), int(definition.actions.gesture.cycle_ms)), int(bool(pose.get("technical_accessories", false))))
	if clip != _clip:
		_clip = clip
		set_instance_shader_parameter(&"pose", clip)
	if robe == _base_robe and clothing == _clothing:
		return
	_base_robe = robe
	_clothing = clothing # Detached outfit; publication never mutates it.
	if clothing.has("body"):
		robe = Color(str(clothing.body.color))
		if bool(clothing.body.wet):
			robe = robe.darkened(0.28)
	if robe != _robe:
		_robe = robe
		# Match the existing CanvasItem's raw modulation in the 2D LDR pipeline;
		# passing Color here asks the server to convert the tint to linear.
		set_instance_shader_parameter(&"robe_tint", Vector4(robe.r, robe.g, robe.b, robe.a))
	var cape := Color(1, 1, 1, 0)
	if clothing.has("outer"):
		cape = Color(str(clothing.outer.color))
		if bool(clothing.outer.get("wet", false)):
			cape = cape.darkened(0.28)
	if cape != _cape:
		_cape = cape
		set_instance_shader_parameter(&"cape_tint", Vector4(cape.r, cape.g, cape.b, cape.a))
