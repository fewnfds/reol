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
const Hud = preload("res://scripts/presentation/ui/hud.gd")
const Interaction = preload("res://scripts/presentation/ui/interaction.gd")
const TILE: float = Art.TILE
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
var ui := Hud.new()
var controls := Interaction.new()
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
var _show_path: bool = false


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
	layer.add_child(ui)
	controls.configure(self, ui)
	controls.z_index = 5
	add_child(controls)
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
		ui.feedback(("→ " if receipt.reason == "accepted" else ("✓ " if receipt.ok else "× ")) + Hud.action_name(receipt.kind), receipt.ok)
		if receipt.get("placed", false):
			selected = int(receipt.target)
			runner.inspect(selected, _probe_tile)
		print("COMMAND_RESULT ", JSON.stringify(receipt))
		if receipt.seq == _pending_move and not receipt.ok:
			_target = Vector2(-1, -1)
		elif receipt.seq == _pending_move and receipt.has("position"):
			_target = Art.body_foot(receipt.position)
	for outcome: Dictionary in mailbox.outcomes:
		if next != null and outcome.get("epoch", next.epoch) != next.epoch:
			continue
		if outcome.actor != 1 and int(outcome.get("target", 0)) != 1:
			continue # NPC traffic must not bury the player's command feedback.
		_last_receipt = "%s #%d @%d" % [outcome.kind, outcome.actor, outcome.at_ms]
		if outcome.kind in ["completed", "transferred", "path_failed", "death", "empty_or_full"]:
			ui.feedback("✓" if outcome.kind in ["completed", "transferred"] else "×", outcome.kind in ["completed", "transferred"])
		print("PLAYER_OUTCOME ", JSON.stringify(outcome))
		if outcome.actor == 1 and outcome.kind in ["arrived", "path_failed", "death"]:
			_target = Vector2(-1, -1)
	if next == null:
		ui.show_tool("gear")
		return
	if frame != next:
		if frame == null: ui.show_tool("")
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
			controls.reset_session()
		frame = next
		if int(frame.player.get("hp", 0)) <= 0 and not controls.tool.is_empty(): controls.cancel_tool()
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
	controls.tick(delta)
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
		return Art.body_foot(frame.positions[slot])
	return Art.body_foot(_render_pose.at(slot, _render_previous[slot], alpha))


func _update_hud() -> void:
	var screen: Vector2 = get_viewport().get_mouse_position()
	var point: Vector2 = get_global_mouse_position() / TILE
	var cell := Vector2i(point.floor())
	var tile: int = Interaction.tile_at(point)
	var valid: bool = tile >= 0 and not controls.external_modal() and get_viewport().gui_get_hovered_control() == null
	if valid and fog_enabled: valid = frame.perception.tiles[tile] != 0
	if valid and tile != _probe_tile:
		_probe_tile = tile
		runner.inspect(selected, tile)
	ui.refresh(frame, selected, fog_enabled, _actual_speed, following, controls.ranged, controls.help_target)
	ui.probe(frame, cell, screen, valid)
	var view_size: Vector2 = get_viewport_rect().size / camera.zoom / TILE
	var camera_rect := Rect2(camera.position / TILE - Art.BODY_FOOT_OFFSET - view_size * 0.5, view_size)
	ui.minimap.adopt(frame, ground.material, fog, fog_enabled, camera_rect)


func _send(command: Dictionary) -> int:
	if frame == null:
		return 0
	command.epoch = frame.epoch
	var seq: int = runner.send(command)
	print("PLAYER_COMMAND seq=%d %s" % [seq, JSON.stringify(command)])
	if seq == 0:
		_last_receipt = "指令未入队：队列已满或会话关闭"
		ui.feedback("×", false)
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
			"player": frame.player, "inspected": frame.inspected, "counters": frame.counters,
			"tool": controls.tool, "minimap_usec": ui.minimap.work_usec})
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
	if _show_path and frame.actor_slots.has(selected) and (not fog_enabled or frame.visible[frame.actor_slots[selected]] != 0) and frame.inspected.get("id", 0) == selected:
		var points := PackedVector2Array([_displayed(selected) * TILE])
		for point: Vector2 in frame.inspected.get("route_preview", PackedVector2Array()):
			points.append(Art.body_foot(point) * TILE)
		if points.size() > 1: draw_polyline(points, Color(0.3, 0.9, 1.0, 0.65), 1.5)
	for index: int in frame.projectiles.size():
		var position: Vector2 = frame.projectiles[index]
		var point: Vector2 = Art.body_foot(position)
		if not fog_enabled or _visible_point(position):
			var direction: Vector2 = frame.projectile_velocities[index].normalized()
			draw_line(point * TILE - direction * 9, point * TILE + direction * 4, Color(0.88, 0.78, 0.56), 2)
			draw_line(point * TILE + direction * 4, point * TILE + direction.rotated(0.45) * -2, Color(0.85, 0.94, 0.90), 2)
			draw_line(point * TILE + direction * 4, point * TILE + direction.rotated(-0.45) * -2, Color(0.85, 0.94, 0.90), 2)
	for source: int in frame.mobile_cells.size():
		if frame.mobile_cells[source] < 0:
			continue
		if fog_enabled and frame.perception.tiles[frame.mobile_cells[source]] == 0:
			continue
		draw_arc(Art.body_foot(Terrain.center(frame.mobile_cells[source])) * TILE, 10, 0, TAU, 12, Ground.SOURCE_COLORS[source % 7], 1.5)


func _visible_point(point: Vector2) -> bool:
	return point.x >= 0 and point.y >= 0 and point.x < Terrain.SIZE and point.y < Terrain.SIZE and frame.perception.tiles[Terrain.index(Vector2i(point))] != 0


func _capture(now: int) -> void:
	if _capture_at == 0:
		if now - _ready_at >= _warmup * 1000000.0:
			_capture_at = now
			_capture_world = frame.world_ms
			_capture_counters = frame.counters.duplicate(true)
			_capture_counters["minimap_usec"] = ui.minimap.work_usec
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
	report.minimap_usec = ui.minimap.work_usec
	report.minimap_usec_delta = ui.minimap.work_usec - int(_capture_counters.get("minimap_usec", 0))
	report.minimap_rebuilds = ui.minimap.rebuilds
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
