extends Node2D
## Sole scene adapter. Only detached frames, commands and receipts cross threads.

const Runner = preload("res://scripts/sim/kernel/runner.gd")
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Population = preload("res://scripts/presentation/population.gd")
const Ground = preload("res://scripts/presentation/terrain_canvas.gd")
const TILE: float = 32.0
var runner := Runner.new()
var population := Population.new()
var ground := Ground.new()
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
var _actors: int = 1000
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
var _render_frame: RefCounted
var _capture_age_usec: int = 0
var _capture_adoptions: int = 0
var _speed_at: int = 0
var _speed_world: int = 0
var _actual_speed: float = 0.0


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
	add_child(population)
	population.configure(_actors)
	add_child(camera)
	camera.position = Vector2(220, 220) * TILE
	camera.zoom = Vector2.ONE * 0.21
	camera.position_smoothing_enabled = false
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(300, 0)
	layer.add_child(panel)
	var layout := VBoxContainer.new()
	panel.add_child(layout)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	layout.add_theme_font_override("font", font)
	layout.add_theme_font_size_override("font_size", 14)
	layout.add_child(hud)
	hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.custom_minimum_size = Vector2(315, 0)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for group: Array in [["暂停/继续", "1×", "2×", "4×"], ["F 跟随", "恢复工作", "喝药", "攻击选中"]]:
		var row := HBoxContainer.new()
		layout.add_child(row)
		for text: String in group:
			var button := Button.new()
			button.text = text
			button.pressed.connect(_button.bind(text))
			row.add_child(button)
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
		_last_receipt = "%s #%d @%d" % [outcome.kind, outcome.actor, outcome.at_ms]
		if outcome.actor == 1 and outcome.kind in ["arrived", "path_failed", "death"]:
			_target = Vector2(-1, -1)
	if next == null:
		hud.text = "正在构建新内核…"
		return
	if frame != next:
		frame = next
		ground.adopt(frame.terrain)
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
	if _render_pose != newer or (frame.paused and _render_frame != frame):
		var adopt_start: int = Time.get_ticks_usec()
		population.adopt(frame, _render_previous, _render_current)
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
	return _render_previous[id - 1].lerp(_render_current[id - 1], alpha)


func _update_hud() -> void:
	var mouse: Vector2i = Vector2i((get_global_mouse_position() / TILE).floor())
	var tile: int = Terrain.index(mouse) if mouse.x >= 0 and mouse.y >= 0 and mouse.x < Terrain.SIZE and mouse.y < Terrain.SIZE else -1
	if tile != _probe_tile:
		_probe_tile = tile
		runner.inspect(selected, tile)
	var stats: Dictionary = frame.counters
	var data: Dictionary = frame.inspected
	var lines := PackedStringArray(["Reol · 重建运行内核", "FPS %d | 世界 %.2fs | 请求 %.1f×" % [Engine.get_frames_per_second(), frame.world_ms / 1000.0, frame.speed],
		"实速 %.3f×" % _actual_speed,
		"单位 %d | worker %d | 房间 %d" % [_actors, stats.workers, stats.rooms],
		"采集 %d / 入库 %d / 材料 %d" % [stats.harvested, stats.stored, stats.material],
		"鼠标格 (%d,%d) | 选中格 %d" % [mouse.x, mouse.y, selected_tile],
		"地块温度 %.2f°C | 房间 %d" % [float(frame.tile_probe.get("temperature", 22.0)), int(frame.tile_probe.get("room", -1))],
		"地块五行 %s" % str(frame.tile_probe.get("elements", [])),
		"潮汐%% 金木水火土 %s" % str(frame.tides),
		"选中#%d HP %d | 状态 %d" % [int(data.get("id", 0)), int(data.get("hp", 0)), int(data.get("mode", 0))],
		"体温 %.2f | 精力 %d | 饥饿 %d" % [float(data.get("temperature", 0)), int(data.get("energy", 0)), int(data.get("hunger", 0))],
		"单位五行 %s" % str(data.get("elements", [])),
		"携带 %d | 药物 %d" % [int(data.get("cargo", 0)), int(data.get("potions", 0))],
		"来源 %d (T 切换选中静态源)" % selected_source,
		"左键选择；右键命令玩家#1移动", "S 停止，J 工作，A 攻击，E 喝药", "B 墙 / G 门 / Delete 拆除(选中格)", "空格暂停；1/2/4 倍速；F 跟随", "方向键平移；滚轮缩放", _last_receipt])
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
			var best: float = 1.0
			for index: int in frame.positions.size():
				var distance: float = point.distance_squared_to(_displayed(index + 1))
				if distance < best:
					best = distance
					selected = index + 1
			selected_tile = Terrain.index(cell) if cell.x >= 0 and cell.y >= 0 and cell.x < Terrain.SIZE and cell.y < Terrain.SIZE else -1
			selected_source = frame.terrain.source_cells.find(selected_tile)
			runner.inspect(selected, selected_tile)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var tile: int = Terrain.index(cell) if cell.x >= 0 and cell.y >= 0 and cell.x < Terrain.SIZE and cell.y < Terrain.SIZE else -1
			if tile >= 0 and frame.terrain.blocked[tile] == 0:
				_pending_move = runner.send({"kind": "move", "actor": 1, "tile": tile})
				if _pending_move > 0:
					_target = Vector2(cell) + Vector2(0.5, 0.5)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: _button("暂停/继续")
			KEY_1: _button("1×")
			KEY_2: _button("2×")
			KEY_4: _button("4×")
			KEY_F: _button("F 跟随")
			KEY_S: runner.send({"kind": "stop", "actor": 1})
			KEY_J: _button("恢复工作")
			KEY_E: _button("喝药")
			KEY_A: _button("攻击选中")
			KEY_T: runner.send({"kind": "source", "actor": 1, "target": selected_source})
			KEY_B: runner.send({"kind": "build", "actor": 1, "tile": selected_tile, "structure": 1})
			KEY_G: runner.send({"kind": "build", "actor": 1, "tile": selected_tile, "structure": 2})
			KEY_DELETE: runner.send({"kind": "build", "actor": 1, "tile": selected_tile, "structure": 0})


func _button(text: String) -> void:
	match text:
		"暂停/继续": paused = not paused
		"1×": speed = 1.0
		"2×": speed = 2.0
		"4×": speed = 4.0
		"F 跟随": following = not following
		"恢复工作": runner.send({"kind": "work", "actor": 1})
		"喝药": runner.send({"kind": "heal", "actor": 1})
		"攻击选中": runner.send({"kind": "attack", "actor": 1, "target": selected})
	if text in ["暂停/继续", "1×", "2×", "4×"]:
		runner.control(paused, speed)


func _draw() -> void:
	if frame == null:
		return
	draw_arc(_displayed(1) * TILE, 15, 0, TAU, 24, Color.GOLD, 2.0)
	if selected > 0:
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
