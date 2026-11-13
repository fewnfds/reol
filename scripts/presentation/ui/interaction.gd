extends Node2D
## One world tool at a time. Native GUI consumes its input before this adapter.
const Actions = preload("res://scripts/presentation/ui/actions.gd")
const Art = preload("res://scripts/presentation/art.gd")
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")
var host: Node2D
var ui: Control
var tool: String = ""
var definition: String = ""
var facing: int = 0
var help_target: int = 0
var ranged: bool = false
var _pan_drag: bool = false
var _resume_paused: bool = false
var _pending_context: Dictionary = {}
var _preview_cells := PackedInt32Array()
var _preview_ok: bool = false
var _preview_tile: int = -1
var _preview_sequence: int = -1
var _point := Vector2.ZERO
const KEYS: Dictionary = {"pause": KEY_SPACE, "speed1": KEY_1, "speed2": KEY_2, "speed4": KEY_4, "speed8": KEY_8,
	"follow": KEY_F, "stop": KEY_S, "work": KEY_J, "heal": KEY_E, "attack_move": KEY_A,
	"hold": KEY_H, "build_menu": KEY_B, "inventory": KEY_I, "move_tool": KEY_M,
	"rotate_take": KEY_R, "put": KEY_Q, "drop": KEY_D, "demolish_tool": KEY_DELETE,
	"save": KEY_F5, "load": KEY_F9, "path": KEY_P,
	"pan_left": KEY_LEFT, "pan_right": KEY_RIGHT, "pan_up": KEY_UP, "pan_down": KEY_DOWN}

func configure(game: Node2D, hud: Control) -> void:
	host = game
	ui = hud
	ui.requested.connect(action)
	for name_key: String in KEYS:
		var input_name: String = "game_" + name_key
		if not InputMap.has_action(input_name): InputMap.add_action(input_name)
		var event := InputEventKey.new()
		event.physical_keycode = KEYS[name_key]
		if not InputMap.action_has_event(input_name, event): InputMap.action_add_event(input_name, event)

func external_modal() -> bool:
	return host.art_gallery.is_open() or (host._debug_console != null and host._debug_console.is_open())

func locked() -> bool:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return external_modal() or ui.blocks_world() or focused is LineEdit or focused is TextEdit

func tick(delta: float) -> void:
	if host.frame == null: return
	if not _pending_context.is_empty():
		if _pending_context.epoch != host.frame.epoch:
			_pending_context = {}
		else:
			var data: Dictionary = Actions.observed(host.frame, _pending_context.target, host.fog_enabled)
			if not data.is_empty():
				ui.context_menu(data, _pending_context.screen, _pending_context)
				_pending_context = {}
	if not host.following and not locked():
		var pan: Vector2 = Input.get_vector("game_pan_left", "game_pan_right", "game_pan_up", "game_pan_down")
		host.camera.position += pan * delta * 800.0 / host.camera.zoom.x
	_point = host.get_global_mouse_position() / Art.TILE
	var tile: int = tile_at(_point)
	if tool in ["build", "plant"] and (tile != _preview_tile or _preview_sequence != host.frame.sequence):
		_preview_sequence = host.frame.sequence
		_preview_tile = tile
		_update_preview(tile)
	if not tool.is_empty(): queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		_pan_drag = false # Release can land on GUI instead of the world.
	if external_modal(): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if ui.modal_kind() != "":
			action("close_modal", {})
		elif ui._context_panel.visible:
			ui.close_context()
		elif not tool.is_empty():
			cancel_tool()
		elif ui.close_layer():
			pass
		elif host.selected != 0:
			_select(0, -1)
		else:
			action("pause_menu", {})
		get_viewport().set_input_as_handled()
	elif ui._context_panel.visible and event is InputEventMouseButton and event.pressed:
		if not ui._context_panel.get_global_rect().has_point(event.position):
			ui.close_context()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if host.frame == null or external_modal(): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_pan_drag = event.pressed and not locked()
		if _pan_drag: host.following = false
		get_viewport().set_input_as_handled()
		return
	if locked(): return
	if event is InputEventMouseMotion and _pan_drag:
		host.camera.position -= event.relative / host.camera.zoom
		return
	if event is InputEventMouseButton and event.pressed:
		var point: Vector2 = host.get_canvas_transform().affine_inverse() * event.position / Art.TILE
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			host.camera.zoom = Vector2.ONE * clampf(host.camera.zoom.x * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.1, 2.0)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if not tool.is_empty(): cancel_tool()
			else: _right_click(point, event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if not tool.is_empty(): _confirm_tool(point)
			else:
				var candidates: Array[int] = pick(point)
				var id: int = 0
				if not candidates.is_empty(): id = candidates[(candidates.find(host.selected) + 1) % candidates.size()]
				_select(id, tile_at(point))
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		for key: String in KEYS:
			if key.begins_with("pan_"): continue
			if event.is_action_pressed("game_" + key):
				action(key, {})
				get_viewport().set_input_as_handled()
				break

func action(kind: String, payload: Dictionary) -> void:
	if host.frame == null: return
	var target: int = int(payload.get("target", host.selected))
	if payload.has("epoch") and int(payload.epoch) != host.frame.epoch: return
	if ui._context_panel.visible: ui.close_context()
	match kind:
		"pause":
			host.paused = not host.paused
			host.runner.control(host.paused, host.speed)
		"speed", "speed1", "speed2", "speed4", "speed8":
			host.speed = float(payload.get("speed", {"speed1": 1, "speed2": 2, "speed4": 4, "speed8": 8}.get(kind, 1)))
			host.runner.control(host.paused, host.speed)
		"follow": host.following = not host.following
		"ranged": ranged = not ranged
		"path": host._show_path = not host._show_path
		"build_menu", "plant_menu", "character", "travel", "dev":
			cancel_tool()
			ui.toggle_drawer({"build_menu": "build", "plant_menu": "plant"}.get(kind, kind))
		"close_drawer": ui.toggle_drawer(ui._drawer_name)
		"inventory": ui.open_stock("drop", 1)
		"take", "put", "drop": ui.open_stock(kind, 1 if kind == "drop" else target)
		"stock_commit": ui.commit_stock()
		"stock_send": _send(payload)
		"trade": ui.open_simple("trade")
		"trade_commit":
			_send({"kind": "trade", "target": target, "give_item": "potion", "give_amount": 1, "want_item": "breath_manual", "want_amount": 1})
			ui.close_modal()
		"pause_menu":
			_resume_paused = host.paused
			host.paused = true
			host.runner.control(true, host.speed)
			ui.open_simple("pause")
		"resume", "close_modal":
			if ui.modal_kind() in ["pause", "settings"]:
				host.paused = _resume_paused
				host.runner.control(host.paused, host.speed)
			ui.close_modal()
		"settings": ui.open_simple("settings")
		"close_settings": ui.open_simple("pause")
		"ui_scale":
			ui.apply_scale(int(payload.percent))
		"ui_scale_commit": ui.commit_scale()
		"place_build", "place_plant":
			tool = "build" if kind == "place_build" else "plant"
			definition = payload.definition
			_preview_sequence = -1
			ui.toggle_drawer(ui._drawer_name)
			ui.show_tool("build" if tool == "build" else "plant", Actions.buildings.get(definition, Actions.plants.get(definition, {})).get("label", ""))
		"move_tool", "attack_move", "demolish_tool":
			tool = {"move_tool": "move", "attack_move": "attack", "demolish_tool": "demolish"}[kind]
			ui.show_tool({"move": "move", "attack": "attack", "demolish": "close"}[tool])
		"rotate_take":
			if tool == "build":
				facing = (facing + 1) % 4
				ui._rotate_button.text = ["N", "E", "S", "W"][facing]
				_preview_sequence = -1
			else: ui.open_stock("take", target)
		"request_worker":
			help_target = target
			tool = "worker"
			ui.show_tool("link", "#%d" % target)
		"request_help": _send({"kind": kind, "target": target, "task_target": help_target})
		"pursue", "hold": _send({"kind": kind, "target": target if kind == "pursue" else 0, "ranged": ranged})
		"context_move": _move(payload.position)
		"camera":
			host.following = false
			host.camera.position = Art.body_foot(payload.position) * Art.TILE
		"map_move":
			if not tool.is_empty(): cancel_tool()
			elif not ui.blocks_world(): _move(Art.body_foot(payload.position))
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
		"stop", "work", "heal", "ability", "save", "load": _send({"kind": kind})
		"study": _send({"kind": kind, "target": 1})
		"continue_build", "demolish", "rest", "eat", "cook", "sow", "tend", "gather", "cut", "uproot", "talk", "learn", "practice":
			_send({"kind": kind, "target": target})
	host._hud_next = 0

func _send(command: Dictionary) -> int:
	if command.get("kind", "") not in ["save", "load"] and int(host.frame.player.get("hp", 0)) <= 0:
		ui.feedback("HP 0", false)
		return 0
	var target: int = int(command.get("target", 0))
	if target > 0 and host.fog_enabled:
		var known: Dictionary = Actions.observed(host.frame, target, true)
		if known.is_empty() or known.get("memory", false):
			ui.feedback("⊘", false)
			return 0
	return host._send(command)

func _select(id: int, tile: int) -> void:
	host.selected = id
	host.selected_tile = tile
	host.runner.inspect(id, host._probe_tile)
	host._hud_next = 0

func _move(point: Vector2) -> void:
	if tile_at(point) < 0: return
	host._pending_move = _send({"kind": "move", "position": Art.body_position(point)})
	if host._pending_move > 0: host._target = point

func _right_click(point: Vector2, screen: Vector2) -> void:
	var candidates: Array[int] = pick(point, false)
	if candidates.is_empty(): _move(point); return
	var target: int = candidates[0]
	var slot: int = int(host.frame.actor_slots.get(target, -1))
	if slot >= 0 and target != 1 and host.frame.sides[slot] != int(host.frame.player.get("side", 0)):
		_send({"kind": "pursue", "target": target, "ranged": ranged})
		return
	_select(target, tile_at(point))
	_pending_context = {"target": target, "position": point, "screen": screen, "epoch": host.frame.epoch}

func _confirm_tool(point: Vector2) -> void:
	var candidates: Array[int] = pick(point, false)
	var target: int = candidates[0] if not candidates.is_empty() else 0
	match tool:
		"move": _move(point)
		"attack":
			if host.frame.actor_slots.has(target) and target != 1: _send({"kind": "pursue", "target": target, "ranged": ranged})
			else: _send({"kind": "attack_move", "position": Art.body_position(point), "ranged": ranged})
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
	cancel_tool()
	help_target = 0
	_pan_drag = false
	ui.reset_session()

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
		draw_arc(_point * Art.TILE, 10, 0, TAU, 16, Style.DANGER if tool in ["attack", "demolish"] else Style.TEAL, 2.0)
