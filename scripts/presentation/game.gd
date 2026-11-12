extends Node2D
## Sole scene adapter. Only detached frames, commands and receipts cross threads.

const Runner = preload("res://scripts/sim/kernel/runner.gd")
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Population = preload("res://scripts/presentation/population.gd")
const Ground = preload("res://scripts/presentation/terrain_canvas.gd")
const ObjectCanvas = preload("res://scripts/presentation/objects_canvas.gd")
const Fog = preload("res://scripts/presentation/fog.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const Art = preload("res://scripts/presentation/art.gd")
const Atmosphere = preload("res://scripts/presentation/atmosphere.gd")
const ActionEffects = preload("res://scripts/presentation/action_effects.gd")
const ArtGallery = preload("res://scripts/presentation/art_gallery.gd")
const TILE: float = 32.0
var runner := Runner.new()
var population := Population.new()
var ground := Ground.new()
var object_canvas := ObjectCanvas.new()
var fog := Fog.new()
var atmosphere := Atmosphere.new()
var action_effects := ActionEffects.new()
var art_gallery := ArtGallery.new()
var fog_enabled: bool = true
var camera := Camera2D.new()
var hud := Label.new()
var readout := Label.new()
var _state_notice := Label.new()
var _pause_button: Button
var _feedback := Label.new()
var _debug_console: Node
var frame: RefCounted
var selected: int = 1
var selected_tile: int = -1
var following: bool = false
var paused: bool = false
var speed: float = 1.0
var render_ms: float = 0.0
var alpha: float = 1.0
var _actors: int = 24
var _workers: int = -1
var _fps: int = 120
var _duration: float = 0.0
var _mixed: bool = false
var _fog_mode: int = -1
var _warmup: float = 3.0
var _metrics_path: String = ""
var _screenshot_path: String = ""
var _ready_at: int = 0
var _capture_at: int = 0
var _capture_world: int = 0
var _capture_counters: Dictionary = {}
var _frame_times := PackedFloat64Array()
var _process_times := PackedFloat64Array()
var _adoption_times := PackedFloat64Array()
var _gpu_times := PackedFloat64Array()
var _previous_usec: int = 0
var _hud_next: int = 0
var _probe_tile: int = -1
var _last_receipt: String = ""
var _target := Vector2(-1, -1)
var _pending_move: int = 0
var _adoptions: int = 0
var _render_previous := PackedVector2Array()
var _render_current := PackedVector2Array()
var _render_pose: RefCounted
var _render_older: RefCounted
var _render_frame: RefCounted
var _capture_age_usec: int = 0
var _capture_adoptions: int = 0
var _speed_at: int = 0
var _speed_world: int = 0
var _actual_speed: float = 0.0
var _item: String = "wood"
var _build_definition: String = "wood_wall"
var _plant_definition: String = "perennial_herb"
var _help_target: int = 0
var _ranged: bool = false
var _attack_cursor: bool = false


func _ready() -> void:
	_debug_console = get_node_or_null("/root/DebugConsole")
	if _debug_console != null:
		_debug_console.attach(diagnostics)
	for argument: String in OS.get_cmdline_user_args():
		var part: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		if part.size() != 2:
			continue
		match part[0]:
			"actors": _actors = clampi(int(part[1]), 1, 60000)
			"workers": _workers = clampi(int(part[1]), -1, 64)
			"speed": speed = clampf(float(part[1]), 0.25, 16.0)
			"fps": _fps = clampi(int(part[1]), 10, 240)
			"duration": _duration = maxf(0.0, float(part[1]))
			"warmup": _warmup = maxf(0.0, float(part[1]))
			"metrics": _metrics_path = part[1]
			"screenshot": _screenshot_path = part[1]
			"mixed": _mixed = part[1] == "true"
			"fog": _fog_mode = int(part[1] == "true")
	Engine.max_fps = _fps
	fog_enabled = _fog_mode == 1 if _fog_mode >= 0 else _actors < 1000 # Developer overview can show all actors.
	population.fog_enabled = fog_enabled
	ground.use_memory = fog_enabled
	ground.z_index = -10
	population.z_index = -1
	add_child(ground)
	object_canvas.z_index = -5
	add_child(object_canvas)
	add_child(population)
	action_effects.z_index = 2
	add_child(action_effects)
	add_child(fog)
	fog.visible = fog_enabled
	population.configure(_actors)
	add_child(camera)
	add_child(atmosphere)
	add_child(art_gallery)
	camera.position = (Vector2(220, 220) if _actors >= 1000 else Vector2(178, 186)) * TILE
	camera.zoom = Vector2.ONE * (0.21 if _actors >= 1000 else 0.9)
	camera.position_smoothing_enabled = false
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 12
	panel.offset_top = 12
	panel.offset_right = 342
	panel.offset_bottom = -12
	layer.add_child(panel)
	var body := VBoxContainer.new()
	panel.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var layout := VBoxContainer.new()
	scroll.add_child(layout)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	body.add_theme_font_override("font", font)
	body.add_theme_font_size_override("font_size", 13)
	layer.add_child(_state_notice)
	_state_notice.add_theme_font_override("font", font)
	_state_notice.add_theme_font_size_override("font_size", 24)
	_state_notice.add_theme_color_override("font_color", Color.GOLD)
	_state_notice.add_theme_color_override("font_shadow_color", Color.BLACK)
	_state_notice.add_theme_constant_override("shadow_offset_x", 2)
	_state_notice.add_theme_constant_override("shadow_offset_y", 2)
	_state_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_state_notice.offset_left = -300
	_state_notice.offset_right = 300
	_state_notice.offset_top = 12
	_state_notice.offset_bottom = 48
	_state_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_state_notice.visible = false
	readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	readout.custom_minimum_size = Vector2(315, 0)
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(readout)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_feedback)
	body.add_child(scroll)
	hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.custom_minimum_size = Vector2(315, 0)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for group: Array in [["暂停/继续", "1×", "2×", "4×"], ["F 跟随", "恢复工作", "喝药", "攻击选中"], ["R 拿取", "Q 放入", "D 丢下"], ["N 施工", "继续施工", "拆除"], ["休息", "进食", "烹饪"], ["种植", "续播", "照料", "采收", "砍伐", "拔除"], ["交谈", "交换", "请教", "读书"], ["修行", "回春", "记为任务", "请协作"], ["F5 保存", "F9 读取"]]:
		var row := HBoxContainer.new()
		layout.add_child(row)
		for text: String in group:
			var button := Button.new()
			button.text = text
			button.pressed.connect(_button.bind(text))
			row.add_child(button)
			if text == "暂停/继续":
				_pause_button = button
				_pause_button.text = "暂停"
	var item_choice := OptionButton.new()
	item_choice.add_theme_constant_override("icon_max_width", 24)
	for item: String in ["wood", "stone", "grain", "water", "meal", "herb", "potion"]:
		item_choice.add_icon_item(Art.icon("item_" + item), item)
	item_choice.get_popup().max_size = Vector2i(300, 400)
	item_choice.item_selected.connect(func(index: int): _item = item_choice.get_item_text(index))
	layout.add_child(item_choice)
	var build_choice := OptionButton.new()
	for definition: String in ["wood_wall", "wood_door", "long_bed", "wood_chest", "cook_stove", "wood_table", "wood_chair", "wood_roof", "planter", "wood_floor"]:
		build_choice.add_item(definition)
	build_choice.item_selected.connect(func(index: int): _build_definition = build_choice.get_item_text(index))
	layout.add_child(build_choice)
	var plant_choice := OptionButton.new()
	for definition: String in ["perennial_herb", "annual_grass", "fire_herb", "lotus", "desert_thorn", "old_tree"]:
		plant_choice.add_item(definition)
	plant_choice.item_selected.connect(func(index: int): _plant_definition = plant_choice.get_item_text(index))
	layout.add_child(plant_choice)
	var weather_choice := OptionButton.new()
	for label: String in ["天气: 自动", "晴", "雨", "寒风", "热浪"]:
		weather_choice.add_item(label)
	weather_choice.item_selected.connect(func(index: int): _send({"kind": "weather", "weather": index - 1}))
	layout.add_child(weather_choice)
	var combat_row := HBoxContainer.new()
	layout.add_child(combat_row)
	for label: String in ["A 攻移", "H 驻守", "追击", "弓/近战"]:
		var button := Button.new()
		button.text = label
		button.pressed.connect(_button.bind(label))
		combat_row.add_child(button)
	var travel_row := HBoxContainer.new()
	layout.add_child(travel_row)
	for label: String in ["回谷地", "去寒林", "去旱地"]:
		var button := Button.new()
		button.text = label
		button.pressed.connect(_button.bind(label))
		travel_row.add_child(button)
	var body_choice := OptionButton.new()
	for label: String in ["身体: 普通", "飞行", "大体型"]:
		body_choice.add_item(label)
	body_choice.item_selected.connect(func(index: int): _send({"kind": "body", "flight": int(index == 1), "large": index == 2}))
	layout.add_child(body_choice)
	layout.add_child(hud)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if runner.start(_actors, _workers, speed, _mixed) != OK:
		push_error("Simulation thread could not start")
		get_tree().quit(1)


func _process(delta: float) -> void:
	var begin: int = Time.get_ticks_usec()
	var mailbox: Dictionary = runner.poll()
	var next: RefCounted = mailbox.frame
	if next != null:
		action_effects.adopt(next, mailbox.outcomes, fog_enabled)
	for receipt: Dictionary in mailbox.receipts:
		_last_receipt = "%s #%d @%d: %s" % [receipt.kind, receipt.seq, receipt.at_ms, receipt.reason]
		_feedback.text = _last_receipt
		_feedback.modulate = Color.WHITE if receipt.ok else Color(1.0, 0.45, 0.4)
		print("COMMAND_RESULT ", JSON.stringify(receipt))
		if receipt.seq == _pending_move and not receipt.ok:
			_target = Vector2(-1, -1)
	for outcome: Dictionary in mailbox.outcomes:
		if next != null and outcome.get("epoch", next.epoch) != next.epoch:
			continue
		if outcome.actor != 1 and int(outcome.get("target", 0)) != 1:
			continue # NPC traffic must not bury the player's command feedback.
		_last_receipt = "%s #%d @%d" % [outcome.kind, outcome.actor, outcome.at_ms]
		_feedback.text = _last_receipt
		print("PLAYER_OUTCOME ", JSON.stringify(outcome))
		if outcome.actor == 1 and outcome.kind in ["arrived", "path_failed", "death"]:
			_target = Vector2(-1, -1)
	if next == null:
		readout.text = "正在构建新内核…"
		return
	if frame != next:
		if frame == null or frame.epoch != next.epoch or frame.paused != next.paused or frame.speed != next.speed:
			print("SESSION_STATE ", JSON.stringify({"epoch": next.epoch, "world_ms": next.world_ms, "paused": next.paused, "speed": next.speed}))
		if frame != null and frame.epoch != next.epoch:
			render_ms = maxf(0, next.world_ms - 50)
			_render_pose = null
			selected = 1
			selected_tile = -1
			_pending_move = 0
			_target = Vector2(-1, -1)
			_speed_at = 0
		frame = next
		var dead: bool = not frame.player.is_empty() and int(frame.player.get("hp", 0)) <= 0
		_state_notice.visible = frame.paused or dead
		_state_notice.text = "玩家#1已死亡 · 无法执行行动" + (" | 已暂停" if frame.paused else "") if dead else "已暂停 · 空格继续"
		_pause_button.text = "继续" if frame.paused else "暂停"
		ground.adopt(frame.terrain, frame.perception)
		object_canvas.adopt(frame.perception.memories if fog_enabled else frame.objects)
		if fog_enabled:
			fog.adopt(frame)
			ground.visibility(fog.visibility)
	if _ready_at == 0:
		_ready_at = begin
		print("KERNEL_READY actors=", _actors, " workers=", frame.counters.workers)
	var newest: RefCounted = frame.history.back()
	var target_ms: float = newest.world_ms + (begin - newest.completed_usec) / 1000.0 * frame.speed - 50.0
	render_ms = clampf(maxf(render_ms, target_ms), frame.history[0].world_ms, frame.world_ms)
	if frame.paused:
		render_ms = frame.world_ms
	var older: RefCounted = frame.history[0]
	var newer: RefCounted = older
	for pose: RefCounted in frame.history:
		newer = pose
		if pose.world_ms >= render_ms:
			break
		older = pose
	alpha = clampf((render_ms - older.world_ms) / maxf(1.0, newer.world_ms - older.world_ms), 0.0, 1.0)
	_render_previous = older.positions
	_render_current = newer.positions
	_render_older = older
	var scenery_changed: bool = population.scenery(object_canvas, fog.visibility)
	if scenery_changed or _render_pose != newer or (frame.paused and _render_frame != frame) or population.actor_count != frame.positions.size() or (_render_frame != null and not is_same(_render_frame.actor_slots, frame.actor_slots)):
		var adopt_start: int = Time.get_ticks_usec()
		population.adopt(frame, older, newer)
		_render_pose = newer
		_render_frame = frame
		_adoptions += 1
		if _capture_at > 0:
			_adoption_times.append((Time.get_ticks_usec() - adopt_start) / 1000.0)
	population.interpolate(alpha, int(render_ms))
	atmosphere.adopt(frame, render_ms)
	action_effects.advance(int(render_ms), fog_enabled)
	if following:
		camera.position = _displayed(1) * TILE
	elif not art_gallery.is_open() and (_debug_console == null or not _debug_console.is_open()):
		var pan := Vector2(float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT)), float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP)))
		camera.position += pan.normalized() * delta * 800.0 / camera.zoom.x
	atmosphere.view(fog.visibility, object_canvas.shelter, fog_enabled)
	if begin >= _hud_next:
		_update_hud()
		_hud_next = begin + 100000
	if begin - _speed_at >= 1000000:
		if _speed_at > 0:
			_actual_speed = (frame.world_ms - _speed_world) * 1000.0 / (begin - _speed_at)
		_speed_at = begin
		_speed_world = frame.world_ms
	queue_redraw()
	if _duration > 0.0:
		_capture(begin)
	if _capture_at > 0:
		if _previous_usec > 0:
			_frame_times.append((begin - _previous_usec) / 1000.0)
		_process_times.append((Time.get_ticks_usec() - begin) / 1000.0)
		_gpu_times.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	_previous_usec = begin


func _displayed(id: int) -> Vector2:
	var slot: int = int(frame.actor_slots.get(id, -1))
	if slot < 0:
		return Vector2.ZERO
	if slot >= _render_current.size() or slot >= _render_previous.size() or _render_older.ids[slot] != id or _render_pose == null or _render_pose.ids[slot] != id:
		return frame.positions[slot]
	return _render_previous[slot].lerp(_render_current[slot], alpha)


func _update_hud() -> void:
	var mouse: Vector2i = Vector2i((get_global_mouse_position() / TILE).floor())
	var tile: int = Terrain.index(mouse) if mouse.x >= 0 and mouse.y >= 0 and mouse.x < Terrain.SIZE and mouse.y < Terrain.SIZE else -1
	if tile != _probe_tile:
		_probe_tile = tile
		runner.inspect(selected, tile)
	var stats: Dictionary = frame.counters
	var data: Dictionary = frame.inspected
	var player: Dictionary = frame.player
	_feedback.text = _last_receipt
	readout.text = "\n".join(PackedStringArray(["Reol · 功能重构试玩", "FPS %d | 世界 %.2fs | 请求 %.1f×" % [Engine.get_frames_per_second(), frame.world_ms / 1000.0, frame.speed],
		"实速 %.3f× | %s" % [_actual_speed, "已暂停（空格继续）" if frame.paused else "运行中"],
		"玩家#1 HP %d | %s" % [int(player.get("hp", 0)), str(Units.Mode.find_key(int(player.get("mode", Units.Mode.FREE))))],
		"单位 %d | worker %d | 房间 %d" % [stats.actors, stats.workers, stats.rooms],
		"采集 %d / 入库 %d / 材料 %d" % [stats.harvested, stats.stored, stats.material],
		"鼠标格 (%d,%d) | 选中格 %d" % [mouse.x, mouse.y, selected_tile],
		"地块温度 %.2f°C | 房间 %d" % [float(frame.tile_probe.get("temperature", 22.0)), int(frame.tile_probe.get("room", -1))],
		"基底 %s | 地被 %d | 地板 %d" % [frame.tile_probe.get("substrate", ""), int(frame.tile_probe.get("cover", 0)), int(frame.tile_probe.get("flooring", 0))],
		"地块五行 %s" % str(frame.tile_probe.get("elements", [])),
		"潮汐%% 金木水火土 %s" % str(frame.tides)]))
	var lines := PackedStringArray([
		"历法/天气 %s" % str(stats.get("calendar", {})),
		"植物 %d / 采收 %d" % [int(stats.get("plants", 0)), int(stats.get("plant_collections", 0))],
		"交战 %d / 弹道 %d / 命中 %d / 远程 %s" % [int(stats.get("combatants", 0)), int(stats.get("projectiles", 0)), int(stats.get("hits", 0)), str(_ranged)],
		"选中#%d HP %d | 状态 %d" % [int(data.get("id", 0)), int(data.get("hp", 0)), int(data.get("mode", 0))],
		"类型 %s / %s" % [data.get("kind", ""), data.get("definition", "")],
		"身体: 飞行 %d / 半径 %.2f" % [int(data.get("flight", 0)), float(data.get("radius", 0))],
		"视距 %.2f 格" % float(data.get("sight_range", 0)),
		"体温 %.2f | 精力 %d | 饥饿 %d" % [float(data.get("temperature", 0)), int(data.get("energy", 0)), int(data.get("hunger", 0))],
		"单位五行 %s" % str(data.get("elements", [])),
		"灵气 %d / 修行 %s / 方法 %s / 能力 %s" % [int(data.get("qi", 0)), str(data.get("practice", 0)), str(data.get("methods", {})), str(data.get("abilities", {}))],
		"库存 %s" % str(data.get("inventory", {})),
		"行动 %s" % str(data.get("action", {})),
		"生长 %d / 阶段 %d / 速率 %d / 伤害时长 %d" % [int(data.get("growth_ms", 0)), int(data.get("stage", -1)), int(data.get("rate", 0)), int(data.get("injury_ms", 0))],
		"左键选择；右键命令玩家#1移动", "S 停止，J 工作，A 攻击，E 喝药", "N 建造 / B 墙 / G 门 / Delete 拆除", "空格暂停；1/2/4 倍速；F 跟随", "方向键平移；滚轮缩放", "F8 素材图鉴；F12 调试", _last_receipt])
	hud.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if frame == null:
		return
	if (art_gallery.is_open() or (_debug_console != null and _debug_console.is_open())) and event is InputEventKey:
		return
	if event is InputEventMouseButton and event.pressed:
		var point: Vector2 = get_canvas_transform().affine_inverse() * event.position / TILE
		var cell := Vector2i(point.floor())
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = Vector2.ONE * clampf(camera.zoom.x * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.1, 2.0)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if _attack_cursor:
				_attack_cursor = false
				_send({"kind": "attack_move", "tile": Terrain.index(cell), "ranged": _ranged})
				return
			var previous_selected: int = selected
			selected = 0
			var best: float = INF
			for index: int in frame.positions.size():
				var id: int = frame.ids[index]
				if id == 0:
					continue
				if fog_enabled and id != 1 and (index >= frame.visible.size() or frame.visible[index] == 0):
					continue
				var body_scale: float = 1.6 if frame.radii[index] > 0.5 else 1.0
				var dead: bool = frame.health[index] <= 0
				var lift: float = 6.0 * body_scale if frame.flight[index] != 0 and not dead else 0.0
				var visual: Vector2 = _displayed(id) - Vector2(0, lift / TILE)
				var relative: Vector2 = point - visual
				var bounds := Rect2(Vector2(-0.6, -0.85), Vector2(1.2, 1.0)) if dead else Rect2(Vector2(-0.45, -1.15), Vector2(0.9, 1.3))
				if not Rect2(bounds.position * body_scale, bounds.size * body_scale).has_point(relative):
					continue
				var distance: float = relative.distance_squared_to(Vector2(0, -0.5 * body_scale))
				if distance < best:
					best = distance
					selected = id
			selected_tile = Terrain.index(cell) if cell.x >= 0 and cell.y >= 0 and cell.x < Terrain.SIZE and cell.y < Terrain.SIZE else -1
			if selected == 0 and object_canvas.by_tile.has(selected_tile):
				var candidates: Array = object_canvas.by_tile[selected_tile]
				selected = candidates[(candidates.find(previous_selected) + 1) % candidates.size()]
			runner.inspect(selected, selected_tile)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var tile: int = Terrain.index(cell) if cell.x >= 0 and cell.y >= 0 and cell.x < Terrain.SIZE and cell.y < Terrain.SIZE else -1
			if tile >= 0:
				_pending_move = _send({"kind": "move", "actor": 1, "tile": tile})
				if _pending_move > 0:
					_target = Vector2(cell) + Vector2(0.5, 0.5)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: _button("暂停/继续")
			KEY_1: _button("1×")
			KEY_2: _button("2×")
			KEY_4: _button("4×")
			KEY_F: _button("F 跟随")
			KEY_S: _send({"kind": "stop", "actor": 1})
			KEY_J: _button("恢复工作")
			KEY_E: _button("喝药")
			KEY_A: _button("A 攻移")
			KEY_H: _button("H 驻守")
			KEY_T: _send({"kind": "source", "actor": 1, "tile": selected_tile})
			KEY_B: _send({"kind": "construct", "actor": 1, "tile": selected_tile, "definition": "wood_wall"})
			KEY_G: _send({"kind": "construct", "actor": 1, "tile": selected_tile, "definition": "wood_door"})
			KEY_N: _button("N 施工")
			KEY_DELETE: _button("拆除")
			KEY_R: _button("R 拿取")
			KEY_Q: _button("Q 放入")
			KEY_D: _button("D 丢下")
			KEY_F5: _button("F5 保存")
			KEY_F9: _button("F9 读取")


func _button(text: String) -> void:
	if frame == null:
		return
	match text:
		"暂停/继续": paused = not paused
		"1×": speed = 1.0
		"2×": speed = 2.0
		"4×": speed = 4.0
		"F 跟随": following = not following
		"恢复工作": _send({"kind": "work", "actor": 1})
		"喝药": _send({"kind": "heal", "actor": 1})
		"攻击选中": _send({"kind": "attack", "actor": 1, "target": selected})
		"R 拿取": _send({"kind": "take", "actor": 1, "target": selected, "item": _item, "amount": 10, "epoch": frame.epoch})
		"Q 放入": _send({"kind": "put", "actor": 1, "target": selected, "item": _item, "amount": 10, "epoch": frame.epoch})
		"D 丢下": _send({"kind": "drop", "actor": 1, "item": _item, "amount": 10, "epoch": frame.epoch})
		"F5 保存": _send({"kind": "save", "epoch": frame.epoch})
		"F9 读取": _send({"kind": "load", "epoch": frame.epoch})
		"N 施工": _send({"kind": "construct", "actor": 1, "tile": selected_tile, "definition": _build_definition, "epoch": frame.epoch})
		"继续施工": _send({"kind": "continue_build", "actor": 1, "target": selected})
		"拆除": _send({"kind": "demolish", "actor": 1, "target": selected})
		"休息": _send({"kind": "rest", "actor": 1, "target": selected})
		"进食": _send({"kind": "eat", "actor": 1, "target": selected})
		"烹饪": _send({"kind": "cook", "actor": 1, "target": selected})
		"种植": _send({"kind": "plant", "tile": selected_tile, "definition": _plant_definition})
		"照料": _send({"kind": "tend", "target": selected})
		"采收": _send({"kind": "gather", "target": selected})
		"砍伐": _send({"kind": "cut", "target": selected})
		"续播": _send({"kind": "sow", "target": selected})
		"交谈": _send({"kind": "talk", "target": selected})
		"交换": _send({"kind": "trade", "target": selected, "give_item": "potion", "give_amount": 1, "want_item": "breath_manual", "want_amount": 1})
		"请教": _send({"kind": "learn", "target": selected})
		"读书": _send({"kind": "study", "target": 1})
		"修行": _send({"kind": "practice", "target": selected})
		"回春": _send({"kind": "ability"})
		"记为任务": _help_target = selected
		"请协作": _send({"kind": "request_help", "target": selected, "task_target": _help_target})
		"拔除": _send({"kind": "uproot", "target": selected})
		"A 攻移": _attack_cursor = true
		"H 驻守": _send({"kind": "hold", "ranged": _ranged})
		"追击": _send({"kind": "pursue", "target": selected, "ranged": _ranged})
		"弓/近战": _ranged = not _ranged
		"回谷地", "去寒林", "去旱地":
			following = true
			_send({"kind": "journey", "region": ["回谷地", "去寒林", "去旱地"].find(text)})
	if text in ["暂停/继续", "1×", "2×", "4×"]:
		runner.control(paused, speed)


func _send(command: Dictionary) -> int:
	if frame == null:
		return 0
	command.epoch = frame.epoch
	var seq: int = runner.send(command)
	print("PLAYER_COMMAND seq=%d %s" % [seq, JSON.stringify(command)])
	if seq == 0:
		_last_receipt = "指令未入队：队列已满或会话关闭"
		_feedback.text = _last_receipt
		_feedback.modulate = Color(1.0, 0.45, 0.4)
	return seq


func diagnostics() -> Dictionary:
	var focused: Control = get_viewport().gui_get_focus_owner()
	var hovered: Control = get_viewport().gui_get_hovered_control()
	var result: Dictionary = {"mailbox": runner.diagnostics(), "selected": selected, "selected_tile": selected_tile,
		"last_result": _last_receipt, "last_move_seq": _pending_move, "actual_speed": _actual_speed,
		"fps": Engine.get_frames_per_second(), "focused_control": str(focused.get_path()) if focused != null else "",
		"hovered_control": str(hovered.get_path()) if hovered != null else ""}
	if frame != null:
		result.merge({"epoch": frame.epoch, "sequence": frame.sequence, "world_ms": frame.world_ms, "paused": frame.paused,
			"speed": frame.speed, "frame_age_ms": (Time.get_ticks_usec() - frame.published_usec) / 1000.0,
			"player": frame.player, "inspected": frame.inspected})
	return result


func _draw() -> void:
	if frame == null:
		return
	draw_arc(_displayed(1) * TILE, 15, 0, TAU, 24, Color.GOLD, 2.0)
	if frame.actor_slots.has(selected) and (not fog_enabled or frame.visible[frame.actor_slots[selected]] != 0):
		draw_arc(_displayed(selected) * TILE, 18, 0, TAU, 24, Color.CYAN, 2.0)
	elif selected_tile >= 0:
		draw_rect(Rect2(Vector2(Terrain.cell(selected_tile)) * TILE, Vector2.ONE * TILE), Color.CYAN, false, 2.0)
	if _target.x >= 0:
		draw_circle(_target * TILE, 5, Color.GOLD)
	for index: int in frame.projectiles.size():
		var point: Vector2 = frame.projectiles[index]
		if not fog_enabled or _visible_point(point):
			var direction: Vector2 = frame.projectile_velocities[index].normalized()
			draw_line(point * TILE - direction * 9, point * TILE + direction * 4, Color(0.88, 0.78, 0.56), 2)
			draw_line(point * TILE + direction * 4, point * TILE + direction.rotated(0.45) * -2, Color(0.85, 0.94, 0.90), 2)
			draw_line(point * TILE + direction * 4, point * TILE + direction.rotated(-0.45) * -2, Color(0.85, 0.94, 0.90), 2)
	for source: int in frame.mobile_cells.size():
		if frame.mobile_cells[source] < 0:
			continue
		if fog_enabled and frame.perception.tiles[frame.mobile_cells[source]] == 0:
			continue
		draw_arc(Terrain.center(frame.mobile_cells[source]) * TILE, 10, 0, TAU, 12, Ground.SOURCE_COLORS[source % 7], 1.5)


func _visible_point(point: Vector2) -> bool:
	return point.x >= 0 and point.y >= 0 and point.x < Terrain.SIZE and point.y < Terrain.SIZE and frame.perception.tiles[Terrain.index(Vector2i(point))] != 0


func _capture(now: int) -> void:
	if _capture_at == 0:
		if now - _ready_at >= _warmup * 1000000.0:
			_capture_at = now
			_capture_world = frame.world_ms
			_capture_counters = frame.counters.duplicate(true)
			_capture_age_usec = now - frame.published_usec
			_capture_adoptions = _adoptions
			print("KERNEL_CAPTURE_STARTED")
		return
	if now - _capture_at < _duration * 1000000.0:
		return
	_duration = 0.0
	var report: Dictionary = frame.counters.duplicate(true)
	report.wall_seconds = (now - _capture_at) / 1000000.0
	report.world_delta_ms = frame.world_ms - _capture_world
	report.actual_speed = report.world_delta_ms / 1000.0 / report.wall_seconds
	report.requested_speed = speed
	report.fps_limit = _fps
	report.mixed = _mixed
	report.renderer = RenderingServer.get_video_adapter_name()
	report.release = not OS.is_debug_build()
	report.frame_ms = _percentiles(_frame_times)
	report.process_ms = _percentiles(_process_times)
	report.adoption_ms = _percentiles(_adoption_times)
	report.gpu_ms = _percentiles(_gpu_times)
	var measured_steps: int = int(report.steps) - int(_capture_counters.steps)
	report.step_ms = _percentiles(report.step_window_usec.slice(-measured_steps) if measured_steps > 0 else [], 0.001)
	report.start_frame_age_usec = _capture_age_usec
	report.finish_frame_age_usec = now - frame.published_usec
	report.erase("step_window_usec")
	for key: String in ["steps", "moved_cells", "harvested", "deliveries", "step_usec", "environment_usec", "units_usec", "effects_usec", "snapshot_usec", "overload_demand_usec", "path_requests", "path_failures", "nature_usec", "combat_usec", "shots", "hits", "plant_collections", "plant_evaluations", "perception_usec", "sight_observers", "sight_candidates", "sight_queries", "sight_index_usec", "sight_batch_usec", "sight_parallel_batches", "sight_sync_usec", "sight_rebuilds"]:
		report[key + "_delta"] = float(report[key]) - float(_capture_counters[key])
	report.instance_slots = population.actor_count
	report.fog = fog_enabled
	report.visible_instances = frame.visible.count(1) if fog_enabled else frame.counters.actors
	report.adopted_frames = _adoptions
	report.adopted_frames_delta = _adoptions - _capture_adoptions
	if not _metrics_path.is_empty():
		var file := FileAccess.open(_metrics_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
		else:
			push_error("Cannot write metrics: " + _metrics_path)
	print("KERNEL_RESULT ", JSON.stringify(report))
	if not _screenshot_path.is_empty():
		get_viewport().get_texture().get_image().save_png(_screenshot_path)
	get_tree().quit(0 if report.deliveries_delta > 0 else 1)


func _percentiles(values: Variant, scale: float = 1.0) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted: Variant = values.duplicate()
	sorted.sort()
	var sum: float = 0.0
	for value: float in sorted:
		sum += value
	return {"mean": sum / sorted.size() * scale, "p50": float(sorted[int((sorted.size() - 1) * 0.5)]) * scale,
		"p95": float(sorted[int((sorted.size() - 1) * 0.95)]) * scale, "p99": float(sorted[int((sorted.size() - 1) * 0.99)]) * scale, "max": float(sorted[-1]) * scale}


func _exit_tree() -> void:
	runner.close()
