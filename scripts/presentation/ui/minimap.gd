extends Control
## Reuses ground/fog GPU textures; only static descriptors and visible dots cache.
signal camera_requested(point: Vector2)
signal move_requested(point: Vector2)
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const MapShader = preload("res://scripts/presentation/ui/minimap.gdshader")
var span: float = 80.0
var center := Vector2(178, 186)
var follow_player: bool = true
var _quad := ColorRect.new()
var _shade := ShaderMaterial.new()
var _static_texture: ImageTexture
var _objects: Dictionary = {}
var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _player_point := Vector2.ZERO
var _player_alive: bool = true
var _camera_rect := Rect2()
var _dragging: bool = false
var _next_dots: int = 0
var _epoch: int = -1
var rebuilds: int = 0
var work_usec: int = 0

func _ready() -> void:
	custom_minimum_size = Vector2(192, 192)
	clip_contents = true
	add_child(_quad)
	_quad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.shader = MapShader
	_quad.material = _shade
	_quad.show_behind_parent = true
	_shade.set_shader_parameter("tile_atlas", preload("res://assets/art/terrain.png"))
	resized.connect(queue_redraw)

func adopt(frame: RefCounted, ground_material: ShaderMaterial, fog: Node2D, use_fog: bool, camera_rect: Rect2) -> void:
	if frame == null: return
	var started: int = Time.get_ticks_usec()
	if _epoch != frame.epoch:
		_epoch = frame.epoch
		_objects = {}
		_next_dots = 0
		follow_player = true
	var player_position: Vector2 = frame.player.get("position", center)
	_player_point = player_position
	_player_alive = int(frame.player.get("hp", 0)) > 0
	if follow_player: center = player_position
	_shade.set_shader_parameter("ground_map", ground_material.get_shader_parameter("ground_map"))
	_shade.set_shader_parameter("visible_map", fog.visibility)
	_shade.set_shader_parameter("explored_map", fog.explored)
	_shade.set_shader_parameter("use_fog", use_fog)
	_apply_view()
	var objects: Dictionary = frame.perception.memories if use_fog else frame.objects
	if not is_same(objects, _objects):
		_objects = objects
		_rebuild_static()
	var now: int = Time.get_ticks_msec()
	if now >= _next_dots:
		_next_dots = now + 100
		_points.clear()
		_colors.clear()
		var player_side: int = int(frame.player.get("side", 0))
		for slot: int in frame.ids.size():
			var id: int = frame.ids[slot]
			if id <= 1 or frame.health[slot] <= 0 or (use_fog and frame.visible[slot] == 0): continue
			_points.append(frame.positions[slot])
			_colors.append(Color("ed6c63") if frame.sides[slot] != player_side else Color("8cd7d3"))
	_camera_rect = camera_rect
	queue_redraw()
	work_usec += Time.get_ticks_usec() - started

func _rebuild_static() -> void:
	var bitmap := Image.create_empty(512, 512, false, Image.FORMAT_R8)
	# Draw layered map descriptors, not live inventories or a second scene.
	for pass_index: int in 2:
		for rec: Dictionary in _objects.values():
			var kind: String = str(rec.kind)
			if (kind == "roof") != (pass_index == 1): continue
			var code: int = 0
			if kind in ["wall", "roof"]: code = 1
			elif kind == "door": code = 2
			elif kind == "resource": code = 3 if int(rec.get("vegetation_level", 3)) >= 3 else 6
			elif kind == "plant": code = 3 if rec.definition == "old_tree" else 6
			elif kind == "blueprint": code = 5
			elif kind not in ["floor", "pile"]: code = 4
			if code == 0: continue
			for tile: int in rec.get("cells", PackedInt32Array([rec.tile])):
				bitmap.set_pixelv(Terrain.cell(tile), Color(float(code) / 255.0, 0, 0))
	if _static_texture == null: _static_texture = ImageTexture.create_from_image(bitmap)
	else: _static_texture.update(bitmap)
	_shade.set_shader_parameter("static_map", _static_texture)
	rebuilds += 1

func _apply_view() -> void:
	center = center.clamp(Vector2.ONE * span * 0.5, Vector2.ONE * (512.0 - span * 0.5))
	_shade.set_shader_parameter("origin", center - Vector2.ONE * span * 0.5)
	_shade.set_shader_parameter("span", span)

func _draw() -> void:
	for index: int in _points.size():
		var point: Vector2 = (_points[index] - center + Vector2.ONE * span * 0.5) / span * size
		if Rect2(Vector2.ZERO, size).has_point(point): draw_circle(point, 2.0, _colors[index])
	var player: Vector2 = (_player_point - center + Vector2.ONE * span * 0.5) / span * size
	if _player_alive and Rect2(Vector2.ZERO, size).has_point(player): draw_circle(player, 3.0, Color.GOLD)
	var view := Rect2((_camera_rect.position - center + Vector2.ONE * span * 0.5) / span * size, _camera_rect.size / span * size)
	draw_rect(view, Color(1, 1, 0.85, 0.85), false, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color("768d78"), false, 2.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				span = clampf(span * (0.75 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.333333), 32.0, 512.0)
				_apply_view()
				queue_redraw()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.pressed: camera_requested.emit(world_point(event.position))
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			move_requested.emit(world_point(event.position))
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		camera_requested.emit(world_point(event.position))
		accept_event()

func world_point(local: Vector2) -> Vector2:
	return (center + (local / size - Vector2.ONE * 0.5) * span).clamp(Vector2.ZERO, Vector2.ONE * 511.999)
