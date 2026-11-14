extends Node2D
## One world tool at a time. Native GUI consumes its input before this adapter.
const Actions = preload("res://scripts/presentation/ui/actions.gd")
const Art = preload("res://scripts/presentation/art.gd")
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")
const Bindings = preload("res://scripts/presentation/ui/input_bindings.gd")
var bindings := Bindings.new()
var host: Node2D
var ui: Control
var tool: String = ""
var definition: String = ""
var facing: int = 0
var help_target: int = 0
var direct: bool = true
var _held: Dictionary = {}
var _primary_down: bool = false
var _last_drive: Dictionary = {}
var _aim := Vector2.RIGHT
var _pan_drag: bool = false
var _resume_paused: bool = false
var _pending_context: Dictionary = {}
var _preview_cells := PackedInt32Array()
var _preview_ok: bool = false
var _preview_tile: int = -1
var _preview_sequence: int = -1
var _point := Vector2.ZERO
var _blocked: bool = true
var _focused: bool = true

func configure(game: Node2D, hud: Control) -> void:
	host = game
	ui = hud
	ui.requested.connect(action)
	bindings.install()
	ui.set_bindings(bindings)
	bindings.changed.connect(_bindings_changed)
	if not bindings.notice.is_empty(): ui.feedback(bindings.notice, false)

func _bindings_changed() -> void:
	clear_direct()
	host._hud_next = 0

func pointer_world(screen: Vector2) -> Vector2:
	# Camera shake is an output offset, excluded explicitly from every aim sample.
	return (host.get_canvas_transform().affine_inverse() * screen - host.camera.offset) / Art.TILE

func _update_aim(screen: Vector2) -> void:
	var direction: Vector2 = pointer_world(screen) - host._displayed(1)
	if direction.length_squared() > 0.04: _aim = direction.normalized()

func external_modal() -> bool:
	return host.art_gallery.is_open() or (host._debug_console != null and host._debug_console.is_open())

func locked() -> bool:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return external_modal() or ui.blocks_world() or ui.inventory.visible or focused is LineEdit or focused is TextEdit

func tick(delta: float) -> void:
	if host.frame == null: return
	if locked() or host.paused or not direct or not tool.is_empty() or not _focused:
		if not _blocked: clear_direct()
	else:
		_blocked = false
		_update_aim(get_viewport().get_mouse_position())
		var drive: Dictionary = {"enabled": true, "move": move_vector(), "aim": _aim, "primary": _primary_down}
		if drive != _last_drive:
			host.runner.drive(drive)
			_last_drive = drive
	queue_redraw()
	if not _pending_context.is_empty():
		if _pending_context.epoch != host.frame.epoch:
			_pending_context = {}
		else:
			var data: Dictionary = Actions.observed(host.frame, _pending_context.target, host.fog_enabled)
			if not data.is_empty():
				ui.context_menu(data, _pending_context.screen, _pending_context)
				_pending_context = {}
	if not host.following and not locked():
		var pan: Vector2 = Vector2(float(_held.has("pan_right")) - float(_held.has("pan_left")), float(_held.has("pan_down")) - float(_held.has("pan_up"))).limit_length(1.0)
		host.camera.position += pan * delta * 800.0 / host.camera.zoom.x
	_point = pointer_world(get_viewport().get_mouse_position())
	var tile: int = tile_at(_point)
	if tool in ["build", "plant"] and (tile != _preview_tile or _preview_sequence != host.frame.sequence):
		_preview_sequence = host.frame.sequence
		_preview_tile = tile
		_update_preview(tile)
	if not tool.is_empty(): queue_redraw()

func _input(event: InputEvent) -> void:
	if external_modal() and ui.binding_editor != null: ui.binding_editor.focus_lost()
	if ui.binding_editor != null and ui.binding_editor.consume(event):
		get_viewport().set_input_as_handled()
		return
	for key: String in ["left", "right", "up", "down"]:
		if event.is_action_released("act_" + key): _held.erase(key)
		if event.is_action_released("game_pan_" + key): _held.erase("pan_" + key)
	if event.is_action_released("act_primary"): _primary_down = false
	if ui.inventory.visible and event is InputEventMouseButton and event.pressed:
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused is LineEdit and not focused.get_global_rect().has_point(event.position):
			get_viewport().gui_release_focus()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		_pan_drag = false # Release can land on GUI instead of the world.
	if external_modal(): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if ui.binding_editor != null and ui.binding_editor.escape():
			pass
		elif ui.modal_kind() == "bindings":
			action("close_bindings", {})
		elif ui.modal_kind() == "settings":
			action("close_settings", {})
		elif ui.modal_kind() != "":
			action("close_modal", {})
		elif ui._context_panel.visible:
			ui.close_context()
		elif not tool.is_empty():
			cancel_tool()
		elif ui.close_layer():
			pass
		else:
			action("pause_menu", {})
		get_viewport().set_input_as_handled()
	elif ui._context_panel.visible and event is InputEventMouseButton and event.pressed:
		if not ui._context_panel.get_global_rect().has_point(event.position):
			ui.close_context()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if host.frame == null or external_modal() or not _focused: return
	if event is InputEventWithModifiers and (event.alt_pressed or event.ctrl_pressed or event.meta_pressed): return
	if direct and not locked() and not host.paused and tool.is_empty():
		for key: String in ["left", "right", "up", "down"]:
			if event.is_action_pressed("act_" + key) and not event.is_echo():
				_held[key] = true
				get_viewport().set_input_as_handled()
				return
		for button: String in ["primary", "skill", "step"]:
			if event.is_action_pressed("act_" + button) and not event.is_echo():
				if button == "primary": _primary_down = true
				# Capture direction on the edge, including a click before the next tick.
				_update_aim(event.position if event is InputEventMouseButton else get_viewport().get_mouse_position())
				_send({"kind": "action", "button": button, "aim": _aim, "move": move_vector()})
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_pan_drag = event.pressed and not locked()
		if _pan_drag: host.following = false
		get_viewport().set_input_as_handled()
		return
	if locked(): return
	if event.is_pressed() and not event.is_echo():
		for spec: Dictionary in Bindings.SPECS:
			var id: String = spec.id
			if not id.begins_with("game_") or not Bindings.active(id, direct): continue
			if host.paused and id in ["game_heal", "game_ability"]: continue
			if event.is_action_pressed(id):
				if id.begins_with("game_pan_"): _held[id.trim_prefix("game_")] = true
				else: action(id.trim_prefix("game_"), {})
				get_viewport().set_input_as_handled()
				return
		if event is InputEventKey and event.physical_keycode == KEY_P:
			action("path", {})
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and _pan_drag:
		host.camera.position -= event.relative / host.camera.zoom
		return
	if event is InputEventMouseButton and event.pressed:
		var point: Vector2 = pointer_world(event.position)
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			host.camera.zoom = Vector2.ONE * clampf(host.camera.zoom.x * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.1, 2.0)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if not tool.is_empty(): cancel_tool()
			elif not direct: _right_click(point, event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT and (not direct or not tool.is_empty()):
			if not tool.is_empty(): _confirm_tool(point)
			else:
				var candidates: Array[int] = pick(point)
				var id: int = 0
				if not candidates.is_empty(): id = candidates[(candidates.find(host.selected) + 1) % candidates.size()]
				_select(id, tile_at(point))
		get_viewport().set_input_as_handled()

func action(kind: String, payload: Dictionary) -> void:
	if host.frame == null: return
	var target: int = int(payload.get("target", host.selected))
	if payload.has("epoch") and int(payload.epoch) != host.frame.epoch: return
	if ui._context_panel.visible: ui.close_context()
	match kind:
		"context":
			clear_direct()
			direct = not direct
			cancel_tool()
			ui.feedback("ACT操作" if direct else "交互／营造：%s返回ACT" % bindings.hint("game_context"), true)
		"interact":
			var nearest: int = 0
			var distance: float = 2.5
			var candidates: Array = host.frame.objects.keys() + host.frame.actor_slots.keys()
			for id: int in candidates:
				if id == 1: continue
				var point: Vector2
				if host.frame.actor_slots.has(id):
					var slot: int = host.frame.actor_slots[id]
					if host.frame.health[slot] <= 0 or (host.fog_enabled and host.frame.visible[slot] == 0): continue
					point = host._displayed(id)
				else:
					var data: Dictionary = host.frame.perception.memories.get(id, {}) if host.fog_enabled else host.frame.objects[id]
					if data.is_empty() or data.kind in ["wall", "door", "floor", "roof"]: continue
					if host.fog_enabled and not _visible_object(data): continue
					point = Art.body_foot(Terrain.center(int(data.tile)))
				var current: float = host._displayed(1).distance_to(point)
				if current < distance: distance = current; nearest = id
			if nearest > 0:
				clear_direct()
				_select(nearest, -1)
				_pending_context = {"target": nearest, "screen": get_viewport_rect().size * 0.5, "epoch": host.frame.epoch}
		"equip_sword", "equip_bow": _send({"kind": "equip", "item": "iron_sword" if kind == "equip_sword" else "short_bow"})
		"combat_practice":
			clear_direct()
			_send({"kind": "combat_practice", "mode": payload.get("mode", "light")})
		"pause":
			clear_direct()
			host.paused = not host.paused
			host.runner.control(host.paused, host.speed)
		"speed", "speed1", "speed2", "speed4", "speed8":
			host.speed = float(payload.get("speed", {"speed1": 1, "speed2": 2, "speed4": 4, "speed8": 8}.get(kind, 1)))
			host.runner.control(host.paused, host.speed)
		"follow": host.following = not host.following
		"path": host._show_path = not host._show_path
		"build_menu", "plant_menu", "character", "travel", "dev":
			clear_direct()
			if kind in ["build_menu", "plant_menu"]: direct = false
			cancel_tool()
			ui.toggle_drawer({"build_menu": "build", "plant_menu": "plant"}.get(kind, kind))
		"close_drawer": ui.toggle_drawer(ui._drawer_name)
		"inventory":
			clear_direct()
			ui.open_bag(1)
		"inspect_bag":
			clear_direct()
			ui.open_bag(int(payload.get("subject", 1)))
		"take", "put", "drop":
			clear_direct()
			ui.open_stock(kind, 1 if kind == "drop" else target)
		"stock_send": _send(payload)
		"unequip": _send({"kind": "unequip", "slot": str(payload.slot)})
		"trade": ui.open_simple("trade")
		"trade_commit":
			_send({"kind": "trade", "target": target, "give_item": "potion", "give_amount": 1, "want_item": "breath_manual", "want_amount": 1})
			ui.close_modal()
		"pause_menu":
			clear_direct()
			_resume_paused = host.paused
			host.paused = true
			host.runner.control(true, host.speed)
			ui.open_simple("pause")
		"resume", "close_modal":
			if ui.modal_kind() in ["pause", "settings", "bindings"]:
				host.paused = _resume_paused
				host.runner.control(host.paused, host.speed)
			ui.close_modal()
		"settings":
			clear_direct()
			ui.open_simple("settings")
		"bindings":
			clear_direct()
			ui.open_simple("bindings")
		"close_bindings": ui.open_simple("settings")
		"close_settings": ui.open_simple("pause")
		"ui_scale":
			ui.apply_scale(int(payload.percent))
		"ui_scale_commit": ui.commit_scale()
		"place_build", "place_plant":
			direct = false
			tool = "build" if kind == "place_build" else "plant"
			definition = payload.definition
			_preview_sequence = -1
			ui.toggle_drawer(ui._drawer_name)
			ui.show_tool("build" if tool == "build" else "plant", Actions.buildings.get(definition, Actions.plants.get(definition, {})).get("label", ""))
		"demolish_tool":
			direct = false
			tool = "demolish"
			ui.show_tool("close")
		"rotate_take":
			if tool == "build":
				facing = (facing + 1) % 4
				ui._rotate_button.text = ["N", "E", "S", "W"][facing]
				_preview_sequence = -1
			else:
				var observed: Dictionary = Actions.observed(host.frame, target, host.fog_enabled)
				for spec: Dictionary in Actions.for_target(observed, host.frame.player, help_target):
					if spec.id == "take" and spec.enabled:
						action("take", {"target": target})
						break
		"request_worker":
			direct = false
			help_target = target
			tool = "worker"
			ui.show_tool("link", "#%d" % target)
		"request_help": _send({"kind": kind, "target": target, "task_target": help_target})
		"camera":
			host.following = false
			host.camera.position = Art.body_foot(payload.position) * Art.TILE
		"map_move":
			host.following = false
			host.camera.position = Art.body_foot(payload.position) * Art.TILE
		"map_out", "map_in":
			ui.minimap.span = clampf(ui.minimap.span * (1.333333 if kind == "map_out" else 0.75), 32.0, 512.0)
			ui.minimap._apply_view()
		"map_follow": ui.minimap.follow_player = not ui.minimap.follow_player
		"cancel_tool": cancel_tool()
		"gallery": host.art_gallery.toggle()
		"debug":
			if host._debug_console != null: host._debug_console.toggle()
		"source_overlay": host._show_sources = not host._show_sources
		"source": _send({"kind": "source", "tile": host.selected_tile})
		"journey":
			host.following = true
			_send({"kind": "journey", "region": int(payload.region)})
		"body", "weather":
			var command: Dictionary = payload.duplicate()
			command.kind = kind
			_send(command)
		"work", "save", "load":
			clear_direct()
			_send({"kind": kind})
		"heal", "ability": _send({"kind": kind})
		"study": _send({"kind": kind, "target": 1})
		"continue_build", "demolish", "rest", "eat", "cook", "sow", "tend", "gather", "cut", "uproot", "talk", "learn", "practice":
			_send({"kind": kind, "target": target})
	host._hud_next = 0

func _send(command: Dictionary) -> int:
	if command.get("kind", "") not in ["save", "load", "combat_practice"] and int(host.frame.player.get("hp", 0)) <= 0:
		ui.feedback("HP 0", false)
		return 0
	var target: int = int(command.get("target", 0))
	if target > 0 and host.fog_enabled:
		var known: Dictionary = Actions.observed(host.frame, target, true)
		if known.is_empty() or known.get("memory", false):
			ui.feedback("⊘", false)
			return 0
	return host._send(command)

func _visible_object(data: Dictionary) -> bool:
	for tile: int in data.get("cells", PackedInt32Array([int(data.tile)])):
		if host.frame.perception.tiles[tile] != 0: return true
	return false

func _select(id: int, tile: int) -> void:
	host.selected = id
	host.selected_tile = tile
	host.runner.inspect(id, host._probe_tile)
	host._hud_next = 0

func _right_click(point: Vector2, screen: Vector2) -> void:
	var candidates: Array[int] = pick(point, false)
	if candidates.is_empty(): return
	var target: int = candidates[0]
	_select(target, tile_at(point))
	_pending_context = {"target": target, "position": point, "screen": screen, "epoch": host.frame.epoch}

func _confirm_tool(point: Vector2) -> void:
	var candidates: Array[int] = pick(point, false)
	var target: int = candidates[0] if not candidates.is_empty() else 0
	match tool:
		"build", "plant":
			_update_preview(tile_at(point))
			if not _preview_ok: return
			_send({"kind": "construct" if tool == "build" else "plant", "definition": definition, "tile": tile_at(point), "facing": facing})
		"demolish":
			if target == 0 or host.frame.actor_slots.has(target): return
			_send({"kind": "demolish", "target": target})
		"worker":
			if target == 0 or target == 1 or not host.frame.actor_slots.has(target): return
			_send({"kind": "request_help", "target": target, "task_target": help_target})
	cancel_tool()

func cancel_tool() -> void:
	tool = ""
	_preview_cells.clear()
	_pending_context = {}
	ui.show_tool("")
	queue_redraw()

func reset_session() -> void:
	clear_direct()
	cancel_tool()
	help_target = 0
	_pan_drag = false
	ui.reset_session()

func move_vector() -> Vector2:
	return Vector2(float(_held.has("right")) - float(_held.has("left")), float(_held.has("down")) - float(_held.has("up"))).limit_length(1.0)

func clear_direct() -> void:
	_held.clear()
	_primary_down = false
	_blocked = true
	host.runner.invalidate_control()
	_last_drive = {"enabled": false}

func _notification(what: int) -> void:
	if host == null: return
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT] and _focused:
		_focused = false
		_pan_drag = false
		if ui.binding_editor != null: ui.binding_editor.focus_lost()
		clear_direct()
	elif what in [NOTIFICATION_WM_WINDOW_FOCUS_IN, NOTIFICATION_APPLICATION_FOCUS_IN]: _focused = true

func pick(point: Vector2, include_flat: bool = true) -> Array[int]:
	var result: Array[int] = []
	var best: float = INF
	var nearest: int = 0
	for slot: int in host.frame.ids.size():
		var id: int = host.frame.ids[slot]
		if id == 0 or (not include_flat and id == 1) or (host.fog_enabled and host.frame.visible[slot] == 0): continue
		var scale_value: float = 1.6 if host.frame.radii[slot] > 0.5 else 1.0
		var foot: Vector2 = host._displayed(id)
		var dead: bool = host.frame.health[slot] <= 0
		if not include_flat and dead: continue
		if host.frame.flight[slot] != 0 and not dead: foot.y -= 6.0 * scale_value / Art.TILE
		var relative: Vector2 = point - foot
		var bounds := Rect2(Vector2(-0.6, -0.85), Vector2(1.2, 1.0)) if dead else Rect2(Vector2(-0.45, -1.15), Vector2(0.9, 1.3))
		if not Rect2(bounds.position * scale_value, bounds.size * scale_value).has_point(relative): continue
		var distance: float = relative.distance_squared_to(Vector2(0, -0.5 * scale_value))
		if distance < best: best = distance; nearest = id
	if nearest > 0: result.append(nearest)
	for id: int in host.object_canvas.by_tile.get(tile_at(point), []):
		if host.fog_enabled and not host.frame.perception.memories.has(id): continue
		var rec: Dictionary = host.object_canvas.objects[id]
		if not include_flat and rec.get("layer", "ground") in ["floor", "roof"]: continue
		if not result.has(id): result.append(id)
	return result

static func tile_at(point: Vector2) -> int:
	return Terrain.index(Vector2i(point.floor())) if point.x >= 0 and point.y >= 0 and point.x < 512 and point.y < 512 else -1

func _update_preview(tile: int) -> void:
	_preview_cells.clear()
	_preview_ok = tile >= 0
	if tile < 0: return
	var spec: Dictionary = Actions.buildings.get(definition, {}) if tool == "build" else Actions.plants.get(definition, {})
	var dimensions: Array = spec.get("size", [1, 1])
	var extent := Vector2i(int(dimensions[0]), int(dimensions[1]))
	if facing % 2 == 1: extent = Vector2i(extent.y, extent.x)
	var cell: Vector2i = Terrain.cell(tile)
	var stock: Dictionary = host.frame.player.get("inventory", {})
	var item: String = str(spec.get("item", "")) if tool == "build" else str(spec.get("product", {}).get("item", ""))
	_preview_ok = int(stock.get(item, 0)) >= int(spec.get("amount", 1))
	for y: int in extent.y:
		for x: int in extent.x:
			var current: int = tile_at(Vector2(cell + Vector2i(x, y)))
			if current < 0: _preview_ok = false; continue
			_preview_cells.append(current)
			if host.fog_enabled and host.frame.perception.tiles[current] == 0: _preview_ok = false; continue
			var surface: int = host.frame.perception.ground[current] if host.fog_enabled else host.frame.terrain.surface_at(current)
			var layer: String = str(spec.get("layer", "ground"))
			var has_pot: bool = false
			for id: int in host.object_canvas.by_tile.get(current, []):
				var rec: Dictionary = host.object_canvas.objects[id]
				var other_layer: String = str(rec.get("layer", "ground"))
				if tool == "plant" and rec.definition == "planter": has_pot = true; continue
				if tool == "plant" and rec.kind not in ["floor", "roof", "pile"]: _preview_ok = false
				if tool == "build":
					var vegetation: int = int(Actions.plants.get(rec.definition, {}).get("vegetation_level", 0)) if rec.kind == "plant" else (int(rec.get("vegetation_level", 3)) if rec.kind == "resource" else 0)
					if layer == "floor" and vegetation >= 2: _preview_ok = false
					elif rec.kind != "pile" and other_layer == layer: _preview_ok = false
			if tool == "build" and layer == "floor" and ((surface & 7) == 3 or (surface & 8) != 0): _preview_ok = false
			if tool == "plant":
				var substrate: String = "soil" if has_pot else str({1: "soil", 2: "sand", 3: "water", 4: "soil"}.get(surface & 7, ""))
				if not spec.get("substrates", []).has(substrate) or (not has_pot and (surface & 8) != 0) or (has_pot and spec.get("blocks", false)): _preview_ok = false

func _draw() -> void:
	if direct and host.frame != null and not locked() and not host.paused and tool.is_empty():
		var pointer: Vector2 = get_global_mouse_position()
		draw_arc(pointer, 4.0 / host.camera.zoom.x, 0, TAU, 16, Style.GOLD, 1.0 / host.camera.zoom.x)
	if tool.is_empty() or host.frame == null or locked(): return
	var color: Color = Style.TEAL if _preview_ok else Style.DANGER
	if tool in ["build", "plant"]:
		for tile: int in _preview_cells:
			var rect := Rect2(Vector2(Terrain.cell(tile)) * Art.TILE, Vector2.ONE * Art.TILE)
			draw_rect(rect, Color(color, 0.22))
			draw_rect(rect, color, false, 2.0)
		if not _preview_cells.is_empty():
			var point: Vector2 = Terrain.center(_preview_cells[0]) * Art.TILE
			var direction: Vector2 = Vector2.UP.rotated(facing * PI * 0.5) * 13
			draw_line(point, point + direction, color, 3.0)
			draw_circle(point + direction, 3, color)
	else:
		draw_arc(_point * Art.TILE, 10, 0, TAU, 16, Style.DANGER if tool == "demolish" else Style.TEAL, 2.0)
