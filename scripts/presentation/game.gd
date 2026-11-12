extends Node2D
## Sole scene adapter. Only detached frames, commands and receipts cross threads.

const Runner = preload("res://scripts/sim/kernel/runner.gd")
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Population = preload("res://scripts/presentation/population.gd")
const Ground = preload("res://scripts/presentation/terrain_canvas.gd")
const ObjectCanvas = preload("res://scripts/presentation/objects_canvas.gd")
const TILE: float = 32.0
var runner := Runner.new()
var population := Population.new()
var ground := Ground.new()
var object_canvas := ObjectCanvas.new()
var camera := Camera2D.new()
var hud := Label.new()
var frame: RefCounted
var selected: int = 1
var selected_source: int = -1
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


func _ready() -> void:
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
	Engine.max_fps = _fps
	ground.z_index = -10
	population.z_index = -1
	add_child(ground)
	object_canvas.z_index = -5
	add_child(object_canvas)
	add_child(population)
	population.configure(_actors)
	add_child(camera)
	camera.position = (Vector2(220, 220) if _actors >= 1000 else Vector2(178, 186)) * TILE
	camera.zoom = Vector2.ONE * (0.21 if _actors >= 1000 else 0.9)
	camera.position_smoothing_enabled = false
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 12
	panel.offset_top = 12
	panel.offset_right = 342
	panel.offset_bottom = -12
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var layout := VBoxContainer.new()
	scroll.add_child(layout)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	layout.add_theme_font_override("font", font)
	layout.add_theme_font_size_override("font_size", 13)
	hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.custom_minimum_size = Vector2(315, 0)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for group: Array in [["暂停/继续", "1×", "2×", "4×"], ["F 跟随", "恢复工作", "喝药", "攻击选中"], ["R 拿取", "Q 放入", "D 丢下"], ["N 施工", "继续施工", "拆除"], ["休息", "进食", "烹饪"], ["F5 保存", "F9 读取"]]:
		var row := HBoxContainer.new()
		layout.add_child(row)
		for text: String in group:
			var button := Button.new()
			button.text = text
			button.pressed.connect(_button.bind(text))
			row.add_child(button)
	var item_choice := OptionButton.new()
	for item: String in ["wood", "stone", "grain", "water", "meal", "herb", "potion"]:
		item_choice.add_item(item)
	item_choice.item_selected.connect(func(index: int): _item = item_choice.get_item_text(index))
	layout.add_child(item_choice)
	var build_choice := OptionButton.new()
	for definition: String in ["wood_wall", "wood_door", "long_bed", "wood_chest", "cook_stove", "wood_table", "wood_chair", "wood_roof", "planter"]:
		build_choice.add_item(definition)
	build_choice.item_selected.connect(func(index: int): _build_definition = build_choice.get_item_text(index))
	layout.add_child(build_choice)
	layout.add_child(hud)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if runner.start(_actors, _workers, speed) != OK:
		push_error("Simulation thread could not start")
		get_tree().quit(1)


func _process(delta: float) -> void:
	var begin: int = Time.get_ticks_usec()
	var mailbox: Dictionary = runner.poll()
	var next: RefCounted = mailbox.frame
	for receipt: Dictionary in mailbox.receipts:
		_last_receipt = "%s #%d @%d: %s" % [receipt.kind, receipt.seq, receipt.at_ms, receipt.reason]
		if receipt.seq == _pending_move and not receipt.ok:
			_target = Vector2(-1, -1)
	for outcome: Dictionary in mailbox.outcomes:
		if next != null and outcome.get("epoch", next.epoch) != next.epoch:
			continue
		_last_receipt = "%s #%d @%d" % [outcome.kind, outcome.actor, outcome.at_ms]
		if outcome.actor == 1 and outcome.kind in ["arrived", "path_failed", "death"]:
			_target = Vector2(-1, -1)
	if next == null:
		hud.text = "正在构建新内核…"
		return
	if frame != next:
		if frame != null and frame.epoch != next.epoch:
			render_ms = maxf(0, next.world_ms - 50)
			_render_pose = null
			selected = 1
			selected_tile = -1
			selected_source = -1
			_pending_move = 0
			_target = Vector2(-1, -1)
			_speed_at = 0
		frame = next
		ground.adopt(frame.terrain)
		object_canvas.adopt(frame.objects)
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
	if _render_pose != newer or (frame.paused and _render_frame != frame) or population.multimesh.instance_count != frame.positions.size() or (_render_frame != null and not is_same(_render_frame.actor_slots, frame.actor_slots)):
		var adopt_start: int = Time.get_ticks_usec()
		population.adopt(frame, older, newer)
		_render_pose = newer
		_render_frame = frame
		_adoptions += 1
		if _capture_at > 0:
			_adoption_times.append((Time.get_ticks_usec() - adopt_start) / 1000.0)
	population.interpolate(alpha, int(render_ms))
	if following:
		camera.position = _displayed(1) * TILE
	else:
		var pan := Vector2(float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT)), float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP)))
		camera.position += pan.normalized() * delta * 800.0 / camera.zoom.x
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
	var lines := PackedStringArray(["Reol · 实物与接续", "FPS %d | 世界 %.2fs | 请求 %.1f×" % [Engine.get_frames_per_second(), frame.world_ms / 1000.0, frame.speed],
		"实速 %.3f×" % _actual_speed,
		"单位 %d | worker %d | 房间 %d" % [stats.actors, stats.workers, stats.rooms],
		"采集 %d / 入库 %d / 材料 %d" % [stats.harvested, stats.stored, stats.material],
		"鼠标格 (%d,%d) | 选中格 %d" % [mouse.x, mouse.y, selected_tile],
		"地块温度 %.2f°C | 房间 %d" % [float(frame.tile_probe.get("temperature", 22.0)), int(frame.tile_probe.get("room", -1))],
		"地块五行 %s" % str(frame.tile_probe.get("elements", [])),
		"潮汐%% 金木水火土 %s" % str(frame.tides),
		"选中#%d HP %d | 状态 %d" % [int(data.get("id", 0)), int(data.get("hp", 0)), int(data.get("mode", 0))],
		"类型 %s / %s" % [data.get("kind", ""), data.get("definition", "")],
		"体温 %.2f | 精力 %d | 饥饿 %d" % [float(data.get("temperature", 0)), int(data.get("energy", 0)), int(data.get("hunger", 0))],
		"单位五行 %s" % str(data.get("elements", [])),
		"库存 %s" % str(data.get("inventory", {})),
		"行动 %s" % str(data.get("action", {})),
		"左键选择；右键命令玩家#1移动", "S 停止，J 工作，A 攻击，E 喝药", "N 建造 / B 墙 / G 门 / Delete 拆除", "空格暂停；1/2/4 倍速；F 跟随", "方向键平移；滚轮缩放", _last_receipt])
	hud.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if frame == null:
		return
	if event is InputEventMouseButton and event.pressed:
		var point: Vector2 = get_global_mouse_position() / TILE
		var cell := Vector2i(point.floor())
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = Vector2.ONE * clampf(camera.zoom.x * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.1, 2.0)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			selected = 0
			var best: float = 0.16
			for index: int in frame.positions.size():
				var id: int = frame.ids[index]
				if id == 0:
					continue
				var distance: float = point.distance_squared_to(_displayed(id))
				if distance < best:
					best = distance
					selected = id
			selected_tile = Terrain.index(cell) if cell.x >= 0 and cell.y >= 0 and cell.x < Terrain.SIZE and cell.y < Terrain.SIZE else -1
			if selected == 0 and object_canvas.by_tile.has(selected_tile):
				selected = object_canvas.by_tile[selected_tile][0]
			selected_source = frame.terrain.source_cells.find(selected_tile)
			runner.inspect(selected, selected_tile)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var tile: int = Terrain.index(cell) if cell.x >= 0 and cell.y >= 0 and cell.x < Terrain.SIZE and cell.y < Terrain.SIZE else -1
			if tile >= 0 and frame.terrain.blocked[tile] == 0:
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
			KEY_A: _button("攻击选中")
			KEY_T: _send({"kind": "source", "actor": 1, "target": selected_source})
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
	if text in ["暂停/继续", "1×", "2×", "4×"]:
		runner.control(paused, speed)


func _send(command: Dictionary) -> int:
	if frame == null:
		return 0
	command.epoch = frame.epoch
	return runner.send(command)


func _draw() -> void:
	if frame == null:
		return
	draw_arc(_displayed(1) * TILE, 15, 0, TAU, 24, Color.GOLD, 2.0)
	if frame.actor_slots.has(selected):
		draw_arc(_displayed(selected) * TILE, 18, 0, TAU, 24, Color.CYAN, 2.0)
	elif selected_tile >= 0:
		draw_rect(Rect2(Vector2(Terrain.cell(selected_tile)) * TILE, Vector2.ONE * TILE), Color.CYAN, false, 2.0)
	if _target.x >= 0:
		draw_circle(_target * TILE, 5, Color.GOLD)
	for source: int in frame.mobile_cells.size():
		if frame.mobile_cells[source] < 0:
			continue
		draw_arc(Terrain.center(frame.mobile_cells[source]) * TILE, 10, 0, TAU, 12, Ground.SOURCE_COLORS[source % 7], 1.5)


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
	for key: String in ["steps", "moved_cells", "harvested", "deliveries", "step_usec", "environment_usec", "units_usec", "effects_usec", "snapshot_usec", "overload_demand_usec", "path_requests", "path_failures"]:
		report[key + "_delta"] = float(report[key]) - float(_capture_counters[key])
	report.visible_instances = population.multimesh.instance_count
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
	get_tree().quit(0 if report.material == report.initial_material and report.deliveries_delta > 0 else 1)


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
