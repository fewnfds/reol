class_name HumanoidAppearance
extends RefCounted
## Read-only sampling and cached drawing for one eight-facing human family.
## Every visible layer uses one frame; simulation still owns bodies and things.

const MANIFEST_PATH: String = "res://data/definitions/humanoid_appearance.json"
const DIRECTIONS: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const ANCHORS: Array[String] = ["left_hand", "right_hand", "left_waist", "right_waist", "head", "back"]
const ACTIONS: Array[String] = ["idle", "walk", "gesture"]
const MAX_TIMESTAMP: int = 9007199254740991
const DEFAULT_DIRECTION: int = 4

static var _shared: HumanoidAppearance
var diagnostics: Array[String] = []
var definition: Dictionary = {}
var textures: Dictionary = {}
var _layers: Dictionary = {}
var _frames: Dictionary = {}
var _configured: bool = false
var _drawable: bool = false


static func shared() -> HumanoidAppearance:
	if _shared == null:
		_shared = HumanoidAppearance.new()
		_shared.load_manifest()
	return _shared


static func stabilize_pose(pose: Dictionary, previous: Dictionary) -> Dictionary:
	if pose.is_empty():
		return pose
	if previous.has("direction_index") and pose.direction == previous.get("direction"):
		pose.direction_index = previous.direction_index
		return pose
	var appearance: HumanoidAppearance = shared()
	pose.direction_index = direction_index(pose.direction, int(previous.get("direction_index", -1)), float(appearance.definition.get("turn_hysteresis_degrees", 0)))
	return pose


static func reset_cache() -> void:
	# Explicit editor/QA reload only. Never called from the frame renderer.
	_shared = null


func load_manifest(path: String = MANIFEST_PATH) -> bool:
	if not FileAccess.file_exists(path):
		diagnostics.assign(["Appearance manifest is missing: " + path])
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return configure(parsed)


func configure(data: Variant, supplied_textures: Dictionary = {}, read_resources: bool = true) -> bool:
	diagnostics = validate_manifest(data)
	if not diagnostics.is_empty():
		return false
	var next_textures: Dictionary = {}
	if read_resources:
		for layer: Dictionary in data.layers:
			var texture: Texture2D = supplied_textures.get(str(layer.id)) as Texture2D
			if texture == null and ResourceLoader.exists(str(layer.texture), "Texture2D"):
				texture = load(str(layer.texture)) as Texture2D
			if texture == null:
				diagnostics.append("Appearance texture is missing: " + str(layer.texture))
			elif texture.get_width() != int(data.atlas_size[0]) or texture.get_height() != int(data.atlas_size[1]):
				diagnostics.append("Appearance texture size differs from atlas_size: " + str(layer.texture))
			else:
				next_textures[str(layer.id)] = texture
		if not diagnostics.is_empty():
			return false
	var next_definition: Dictionary = data.duplicate(true)
	var next_frames: Dictionary = {}
	var next_layers: Dictionary = {}
	for layer: Dictionary in next_definition.layers:
		next_layers[str(layer.id)] = layer
	for direction: String in DIRECTIONS:
		next_frames[direction] = {}
		for action: String in ACTIONS:
			var clips: Array[Dictionary] = []
			for frame: Dictionary in next_definition.frames[direction][action]:
				var anchors: Dictionary = {}
				for id: String in ANCHORS:
					var source: Dictionary = frame.anchors[id]
					anchors[id] = {"position": Vector2(float(source.position[0]), float(source.position[1])),
						"angle_deg": float(source.angle_deg), "visible": bool(source.visible), "depth": float(source.depth)}
				clips.append({"rect": Rect2(float(frame.rect[0]), float(frame.rect[1]), float(frame.rect[2]), float(frame.rect[3])),
					"origin": Vector2(float(frame.origin[0]), float(frame.origin[1])), "anchors": anchors,
					"layer_order": frame.layer_order})
			next_frames[direction][action] = clips
	definition = next_definition
	textures = next_textures
	_layers = next_layers
	_frames = next_frames
	_configured = true
	_drawable = read_resources
	return true


static func validate_manifest(data: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not data is Dictionary:
		return ["Appearance manifest must be a record."]
	if not _integer(data.get("schema_version"), 1, 1) or not data.get("id") is String or str(data.id).is_empty():
		errors.append("Appearance manifest needs schema_version 1 and a stable id.")
	if not _pair(data.get("frame_size"), true, 1, 4096) or not _pair(data.get("atlas_size"), true, 1, 32768) or not _pair(data.get("origin"), false, -4096, 4096):
		errors.append("Appearance frame_size, atlas_size or origin is invalid.")
		return errors
	if not data.get("directions") is Array or data.directions != DIRECTIONS:
		errors.append("Appearance must contain all eight explicit directions in canonical order.")
	if not _number(data.get("turn_hysteresis_degrees"), 0.0, 20.0):
		errors.append("Appearance turn_hysteresis_degrees must be defined from 0 to 20.")
	var layer_ids: Array[String] = []
	if not data.get("layers") is Array or data.layers.is_empty():
		errors.append("Appearance needs visible layer definitions.")
		return errors
	for layer: Variant in data.layers:
		if not layer is Dictionary or not layer.get("id") is String or str(layer.id).is_empty() or layer_ids.has(str(layer.id)):
			errors.append("Appearance layer ids must be unique nonempty strings.")
			continue
		layer_ids.append(str(layer.id))
		if not layer.get("texture") is String or not str(layer.texture).begins_with("res://") or not layer.get("slot") in ["base", "body", "outer", "preview_sword", "preview_jade"] or not layer.get("tint") in ["none", "body", "outer"]:
			errors.append("Appearance layer has an invalid texture, slot or tint: " + str(layer.id))
	if not data.get("actions") is Dictionary or not data.get("frames") is Dictionary:
		errors.append("Appearance needs action definitions and eight-direction frames.")
		return errors
	for action: String in ACTIONS:
		var clip: Variant = data.actions.get(action)
		if not clip is Dictionary or not _integer(clip.get("column"), 0, 4096) or not _integer(clip.get("frames"), 1, 1024) or not _integer(clip.get("cycle_ms"), 1, 60000):
			errors.append("Appearance action has invalid columns, frames or duration: " + action)
			continue
		if (int(clip.column) + int(clip.frames)) * int(data.frame_size[0]) > int(data.atlas_size[0]):
			errors.append("Appearance action exceeds the atlas width: " + action)
		for direction_index_value: int in DIRECTIONS.size():
			var direction: String = DIRECTIONS[direction_index_value]
			var group: Variant = data.frames.get(direction)
			if not group is Dictionary or not group.get(action) is Array or group[action].size() != int(clip.frames):
				errors.append("Appearance direction/action is incomplete: %s/%s" % [direction, action])
				continue
			for index: int in int(clip.frames):
				var entry: Variant = group[action][index]
				var context: String = "%s/%s/%d" % [direction, action, index]
				if not entry is Dictionary:
					errors.append("Appearance frame must be a record: " + context)
					continue
				if entry.has("flip_h") or entry.has("flip_v") or entry.has("mirror"):
					errors.append("Appearance may not substitute a mirrored frame: " + context)
				if not _valid_rect(entry.get("rect"), data, int(clip.column) + index, direction_index_value) or not _pair(entry.get("origin"), false, -4096, 4096) or entry.origin != data.origin:
					errors.append("Appearance frame has an invalid atlas region or changing foot origin: " + context)
				if not entry.get("layer_order") is Array or not _same_ids(entry.layer_order, layer_ids):
					errors.append("Appearance frame must order each defined layer exactly once: " + context)
				if not entry.get("anchors") is Dictionary:
					errors.append("Appearance frame needs anatomical anchors: " + context)
					continue
				for anchor: String in ANCHORS:
					var attach: Variant = entry.anchors.get(anchor)
					if not attach is Dictionary or not _pair(attach.get("position"), false, -4096, 4096) or not _number(attach.get("angle_deg"), -3600.0, 3600.0) or not attach.get("visible") is bool or not _number(attach.get("depth"), -4096.0, 4096.0):
						errors.append("Appearance anatomical anchor is invalid: %s/%s" % [context, anchor])
	return errors


static func _valid_rect(rect: Variant, data: Dictionary, column: int, row: int) -> bool:
	return rect is Array and rect.size() == 4 and _integer(rect[0], 0, int(data.atlas_size[0])) and _integer(rect[1], 0, int(data.atlas_size[1])) and _integer(rect[2], 1, int(data.frame_size[0])) and _integer(rect[3], 1, int(data.frame_size[1])) and int(rect[0]) == column * int(data.frame_size[0]) and int(rect[1]) == row * int(data.frame_size[1]) and int(rect[2]) == int(data.frame_size[0]) and int(rect[3]) == int(data.frame_size[1]) and int(rect[0]) + int(rect[2]) <= int(data.atlas_size[0]) and int(rect[1]) + int(rect[3]) <= int(data.atlas_size[1])


static func _same_ids(value: Array, expected: Array[String]) -> bool:
	if value.size() != expected.size():
		return false
	var seen: Dictionary = {}
	for id: Variant in value:
		if not id is String or not expected.has(id) or seen.has(id):
			return false
		seen[id] = true
	return true


static func _pair(value: Variant, whole: bool, minimum: int, maximum: int) -> bool:
	return value is Array and value.size() == 2 and (_integer(value[0], minimum, maximum) and _integer(value[1], minimum, maximum) if whole else _number(value[0], minimum, maximum) and _number(value[1], minimum, maximum))


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum


static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum


static func direction_index(direction: Vector2, previous: int = -1, hysteresis_degrees: float = 0.0) -> int:
	if not direction.is_finite() or direction.is_zero_approx():
		return previous if previous >= 0 and previous < DIRECTIONS.size() else DEFAULT_DIRECTION
	var angle: float = atan2(direction.x, -direction.y)
	if previous >= 0 and previous < DIRECTIONS.size():
		var center: float = float(previous) * PI * 0.25
		if absf(wrapf(angle - center, -PI, PI)) <= PI * 0.125 + deg_to_rad(clampf(hysteresis_degrees, 0.0, 20.0)):
			return previous
	return posmod(roundi(angle / (PI * 0.25)), DIRECTIONS.size())


func sample(pose: Dictionary = {}) -> Dictionary:
	if not _configured:
		return {}
	var raw_time: Variant = pose.get("time_ms", 0)
	var now: int = int(raw_time) if _integer(raw_time, 0, MAX_TIMESTAMP) else 0
	var facing: Variant = pose.get("direction", Vector2.DOWN)
	var previous: int = int(pose.get("previous_direction", -1))
	var index: int = direction_index(facing if facing is Vector2 else Vector2.DOWN, previous, float(definition.turn_hysteresis_degrees))
	var explicit_index: Variant = pose.get("direction_index", -1)
	if _integer(explicit_index, 0, DIRECTIONS.size() - 1):
		index = int(explicit_index)
	var action: String = str(pose.get("action", ""))
	if action not in ACTIONS:
		action = "walk" if bool(pose.get("moving", false)) else "idle"
	var clip: Dictionary = definition.actions[action]
	var elapsed: int = now
	if action == "gesture":
		var started: Variant = pose.get("started_ms", now)
		elapsed = maxi(0, now - int(started)) if _integer(started, 0, MAX_TIMESTAMP) else 0
	var cursor: int = posmod(elapsed, int(clip.cycle_ms))
	@warning_ignore("integer_division")
	var frame_index: int = cursor * int(clip.frames) / int(clip.cycle_ms)
	var frame: Dictionary = _frames[DIRECTIONS[index]][action][frame_index]
	return {"direction": index, "direction_id": DIRECTIONS[index], "action": action,
		"frame": frame_index, "phase": float(cursor) / float(clip.cycle_ms),
		"rect": frame.rect, "origin": frame.origin, "anchors": frame.anchors, "layer_order": frame.layer_order}


func visible_layer_ids(pose: Dictionary, clothing: Dictionary) -> Array[String]:
	var sampled: Dictionary = sample(pose)
	var result: Array[String] = []
	if sampled.is_empty():
		return result
	for id: String in sampled.layer_order:
		var slot: String = str(_layers[id].slot)
		if slot == "outer" and not clothing.has("outer"):
			continue
		if slot.begins_with("preview_") and not bool(pose.get("technical_accessories", false)):
			continue
		result.append(id)
	return result


func draw_layers(canvas: CanvasItem, foot: Vector2, robe: Color, clothing: Dictionary, pose: Dictionary = {}) -> bool:
	if not _drawable:
		return false
	var sampled: Dictionary = sample(pose)
	if sampled.is_empty():
		return false
	var destination := Rect2(foot - sampled.origin, sampled.rect.size)
	for id: String in sampled.layer_order:
		var layer: Dictionary = _layers[id]
		var slot: String = str(layer.slot)
		if slot == "outer" and not clothing.has("outer") or slot.begins_with("preview_") and not bool(pose.get("technical_accessories", false)):
			continue
		var tint := Color.WHITE
		if layer.tint == "body":
			tint = robe
		elif layer.tint == "outer":
			tint = Color(str(clothing.outer.color))
			if bool(clothing.outer.get("wet", false)):
				tint = tint.darkened(0.28)
		canvas.draw_texture_rect_region(textures[id], destination, sampled.rect, tint)
	return true
