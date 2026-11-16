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
const ResponseProbe = preload("res://scripts/presentation/response_probe.gd")
const ActionDefs = preload("res://scripts/sim/kernel/action_defs.gd")
const CombatShapes = preload("res://scripts/presentation/combat_shapes.gd")
const CombatAudio = preload("res://scripts/presentation/combat_audio.gd")
const FeedbackSettings = preload("res://scripts/presentation/feedback_settings.gd")
const ViewRig = preload("res://scripts/presentation/view_rig.gd")
const WorldOverlay = preload("res://scripts/presentation/world_overlay.gd")
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
var view := ViewRig.new()
var camera: Camera2D = view.camera
var world_overlay := WorldOverlay.new()
var tool_overlay := WorldOverlay.new()
var _view_override: float = -1.0
var ui := Hud.new()
var controls := Interaction.new()
var combat_audio := CombatAudio.new()
var combat_shapes := CombatShapes.new()
var feedback := FeedbackSettings.new()
var _debug_console: Node
var frame: RefCounted
var selected: int = 1
var selected_tile: int = -1
var following: bool = true
var paused: bool = false
var speed: float = 1.0
var render_ms: float = 0.0
var alpha: float = 1.0
var _actors: int = 24
var _workers: int = -1
var _fps: int = 120
var _duration: float = 0.0
var _mixed: bool = false
var _capacity: bool = false
var _activity_samples: Array[float] = []
var _mid_at: int = 0
var _mid_counters: Dictionary = {}
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
var _render_cpu_times := PackedFloat64Array()
var _previous_usec: int = 0
var _mask_was_updated: bool = false
var _hud_next: int = 0
var _probe_next: int = 0
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
var _show_sources: bool = false
var _response_probe: RefCounted
var _sim_hz: int = 60
var _combat_lab: bool = false
var _combat_probe: bool = false
var _profile_before: Dictionary = {}
var _last_direction_epoch: int = -1
var _last_displayed_player := Vector2.INF
var _display_move := Vector2.ZERO


func _ready() -> void:
	_debug_console = get_node_or_null("/root/DebugConsole")
	if _debug_console != null:
		_debug_console.attach(diagnostics)
	for argument: String in OS.get_cmdline_user_args():
		var part: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		if part.size() != 2:
			continue
		match part[0]:
			"view-warp": _view_override = clampf(float(part[1]), 0, 1)
			"actors": _actors = clampi(int(part[1]), 1, 60000)
			"workers": _workers = clampi(int(part[1]), -1, 64)
			"speed": speed = clampf(float(part[1]), 0.25, 16.0)
			"fps": _fps = clampi(int(part[1]), 10, 240)
			"duration": _duration = maxf(0.0, float(part[1]))
			"warmup": _warmup = maxf(0.0, float(part[1]))
			"metrics": _metrics_path = part[1]
			"screenshot": _screenshot_path = part[1]
			"mixed": _mixed = part[1] == "true"
			"capacity": _capacity = part[1] == "true"
			"fog": _fog_mode = int(part[1] == "true")
			"sim-hz": _sim_hz = int(part[1]) if int(part[1]) in [20, 60, 100] else 60
			"combat-lab": _combat_lab = part[1] == "true"
			"combat-probe": _combat_probe = part[1] == "true"
			"response-probe":
				if part[1] == "true": _response_probe = ResponseProbe.new()
	if _combat_probe and (_duration <= 0.0 or _actors < 4 or _mixed or _capacity or speed != 1.0):
		push_error("Combat probe requires a bounded capture at 1x with at least four actors")
		get_tree().quit(1)
		return
	if _combat_probe: _combat_lab = true
	if _response_probe != null and (_duration <= 0.0 or _mixed or _capacity or _combat_lab or speed != 1.0):
		push_error("Response probe requires a bounded ordinary capture at 1x")
		get_tree().quit(1)
		return
	# Captures retain the historical fixed view; ordinary play follows the body.
	if _duration > 0.0: following = false
	Engine.max_fps = _fps
	fog_enabled = _fog_mode == 1 if _fog_mode >= 0 else _actors < 1000 # Developer overview can show all actors.
	add_child(view)
	population.fog_enabled = fog_enabled
	ground.use_memory = fog_enabled
	ground.z_index = -10
	population.z_index = -1
	view.world.add_child(ground)
	object_canvas.z_index = -5
	view.world.add_child(object_canvas)
	view.world.add_child(population)
	action_effects.z_index = 2
	view.world.add_child(action_effects)
	population.feedback = action_effects
	add_child(combat_audio)
	view.world.add_child(combat_shapes)
	view.world.add_child(fog)
	fog.visible = fog_enabled
	population.configure(_actors)
	view.world.add_child(atmosphere)
	add_child(art_gallery)
	camera.position = (Vector2(220, 220) if _actors >= 1000 or _capacity else Vector2(178, 186)) * TILE
	camera.zoom = Vector2.ONE * (0.21 if _actors >= 1000 or _capacity else 0.9)
	if _combat_lab:
		camera.position = Art.body_foot(Vector2(144.5, 150.5)) * TILE
		camera.zoom = Vector2.ONE * 0.9
	camera.position_smoothing_enabled = false
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	layer.add_child(ui)
	if _debug_console != null:
		ui.scale_applied.connect(_debug_console.set_ui_scale)
		_debug_console.set_ui_scale(ui.scale.x)
	controls.configure(self, ui)
	feedback.load_settings()
	if _view_override >= 0.0: feedback.view_warp = _view_override
	sync_view()
	world_overlay.paint = _paint_world
	view.world.add_child(world_overlay)
	tool_overlay.z_index = 5
	tool_overlay.paint = controls.paint_world
	view.world.add_child(tool_overlay)
	ui.feedback_settings = feedback
	add_child(controls)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if runner.start(_actors, _workers, speed, _mixed, _capacity, _sim_hz, _combat_lab, _combat_probe) != OK:
		push_error("Simulation thread could not start")
		get_tree().quit(1)


func sync_view() -> void:
	view.strength = feedback.view_warp * ViewRig.MAX_STRENGTH
	view.sync()


func _process(delta: float) -> void:
	var begin: int = Time.get_ticks_usec()
	sync_view()
	var mask_gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(fog.mask.get_viewport_rid()) if _capture_at > 0 and _mask_was_updated else 0.0
	var mask_cpu: float = RenderingServer.viewport_get_measured_render_time_cpu(fog.mask.get_viewport_rid()) if _capture_at > 0 and _mask_was_updated else 0.0
	var mailbox: Dictionary = runner.poll()
	var next: RefCounted = mailbox.frame
	if next != null:
		action_effects.adopt(next, mailbox.outcomes, fog_enabled)
		combat_audio.adopt(next, mailbox.outcomes, fog_enabled)
		if _capture_at > 0:
			var counts: Variant = next.counters.mode_counts
			var busy: int = int(counts[0]) + int(counts[1]) + int(counts[3]) + int(counts[6]) + int(counts[7]) + int(counts[9]) + int(counts[10]) + int(next.counters.stationary_combatants)
			_activity_samples.append(float(busy) / maxi(1, int(next.counters.actors)))
	for receipt: Dictionary in mailbox.receipts:
		if _response_probe != null: _response_probe.accept(receipt, Time.get_ticks_usec())
		_last_receipt = "%s #%d @%d: %s" % [receipt.kind, receipt.seq, receipt.at_ms, receipt.reason]
		ui.feedback(("→ " if receipt.reason == "accepted" else ("✓ " if receipt.ok else "× ")) + Hud.action_name(receipt.kind), receipt.ok)
		if receipt.get("placed", false):
			controls._select(int(receipt.target), -1)
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
			render_ms = maxf(0, next.world_ms - next.interpolation_ms)
			_render_pose = null
			selected = 1
			selected_tile = -1
			_probe_tile = -1
			runner.inspect(1, -1)
			_pending_move = 0
			_target = Vector2(-1, -1)
			_speed_at = 0
			controls.reset_session()
		frame = next
		if int(frame.player.get("hp", 0)) <= 0 and not controls.tool.is_empty(): controls.cancel_tool()
		ground.adopt(frame.terrain, frame.perception)
		if fog_enabled: object_canvas.adopt(frame.perception.memories, frame.perception.get("fringe", {}))
		else: object_canvas.adopt(frame.objects)
		if fog_enabled:
			fog.adopt(frame)
			ground.visibility(fog.visibility)
	if _ready_at == 0:
		_ready_at = begin
		print("KERNEL_READY actors=", _actors, " workers=", frame.counters.workers)
		var catalog: Script = preload("res://scripts/sim/kernel/action_defs.gd")
		print("ACTION_CATALOG abilities=", catalog.ACTIONS.size(), " loadouts=", catalog.LOADOUTS.size(), " signature=", catalog.SIGNATURE)
	var newest: RefCounted = frame.history.back()
	var target_ms: float = newest.world_ms + (begin - newest.completed_usec) / 1000.0 * frame.speed - frame.interpolation_ms
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
	var scenery_changed: bool = population.scenery(object_canvas, fog.visibility, fog.mask.get_texture())
	if scenery_changed or _render_pose != newer or (frame.paused and _render_frame != frame) or population.actor_count != frame.positions.size() or (_render_frame != null and not is_same(_render_frame.actor_slots, frame.actor_slots)):
		var adopt_start: int = Time.get_ticks_usec()
		population.adopt(frame, older, newer, _actions_at(newer), int(render_ms))
		_render_pose = newer
		_render_frame = frame
		_adoptions += 1
		if _capture_at > 0:
			_adoption_times.append((Time.get_ticks_usec() - adopt_start) / 1000.0)
	population.interpolate(alpha, int(render_ms))
	population._shader.set_shader_parameter("controlled_foot", _displayed(1) * TILE)
	if fog_enabled:
		fog.follow_view(newer.at(frame.actor_slots[1], _render_previous[frame.actor_slots[1]], alpha), float(frame.player.get("sight_range", 0.0)))
	atmosphere.adopt(frame, render_ms)
	action_effects.advance(int(render_ms), fog_enabled)
	combat_audio.advance(int(render_ms))
	action_effects.flash = feedback.flash
	action_effects.shake = feedback.shake
	combat_audio.volume = feedback.volume
	if following:
		camera.position = _displayed(1) * TILE
	camera.offset = action_effects.camera_offset() / camera.zoom
	camera.force_update_scroll() # Mouse conversion uses this displayed camera, even without fog.
	_update_direction_marker()
	controls.tick(delta)
	combat_shapes.advance(frame, _render_pose, int(render_ms), fog_enabled, controls.pointer_world(get_viewport().get_mouse_position()) - Art.BODY_FOOT_OFFSET, controls.direct and not controls.locked() and not frame.paused)
	if fog_enabled:
		camera.force_update_scroll()
		_mask_was_updated = fog.sync_mask()
	atmosphere.view(fog.visibility, object_canvas.shelter, fog_enabled)
	if begin >= _probe_next:
		_update_probe()
		_probe_next = begin + 50000
	if begin >= _hud_next:
		_update_hud()
		_hud_next = begin + 100000
	if begin - _speed_at >= 1000000:
		if _speed_at > 0:
			_actual_speed = (frame.world_ms - _speed_world) * 1000.0 / (begin - _speed_at)
		_speed_at = begin
		_speed_world = frame.world_ms
	world_overlay.queue_redraw()
	tool_overlay.queue_redraw()
	if _duration > 0.0:
		if _response_probe != null and _capture_at > 0: _response_probe.tick(self, Time.get_ticks_usec())
		_capture(begin)
	if _capture_at > 0:
		if _previous_usec > 0:
			_frame_times.append((begin - _previous_usec) / 1000.0)
		_process_times.append((Time.get_ticks_usec() - begin) / 1000.0)
		_gpu_times.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()) + mask_gpu + RenderingServer.viewport_get_measured_render_time_gpu(view.viewport.get_viewport_rid()))
		_render_cpu_times.append(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()) + mask_cpu + RenderingServer.viewport_get_measured_render_time_cpu(view.viewport.get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu())
	_previous_usec = begin


func _displayed(id: int) -> Vector2:
	var slot: int = int(frame.actor_slots.get(id, -1))
	if slot < 0:
		return Vector2.ZERO
	if slot >= _render_current.size() or slot >= _render_previous.size() or _render_older.ids[slot] != id or _render_pose == null or _render_pose.ids[slot] != id:
		return Art.body_foot(frame.positions[slot])
	return Art.body_foot(_render_pose.at(slot, _render_previous[slot], alpha))


func _actions_at(pose: RefCounted) -> Dictionary:
	if frame.paused or render_ms >= frame.world_ms: return frame.combat
	var result: Dictionary = {}
	for segment: Dictionary in pose.action_segments:
		if render_ms >= int(segment.from_ms) and render_ms < int(segment.until_ms): result[segment.actor] = segment
	return result


func _update_probe() -> void:
	var point: Vector2 = controls.pointer_world(get_viewport().get_mouse_position())
	var tile: int = Interaction.tile_at(point)
	var valid: bool = tile >= 0 and not controls.external_modal() and get_viewport().gui_get_hovered_control() == null
	if valid and fog_enabled: valid = frame.perception.tiles[tile] != 0
	if valid and tile != _probe_tile:
		_probe_tile = tile
		runner.inspect(selected, tile)
	var sampled_tile: int = int(frame.tile_probe.get("tile", -1))
	var sampled_visible: bool = sampled_tile >= 0 and (not fog_enabled or frame.perception.tiles[sampled_tile] != 0)
	ui.probe(frame, valid and sampled_visible)

func _update_hud() -> void:
	ui.refresh(frame, selected, fog_enabled, _actual_speed, following, controls.help_target, controls.direct)
	var visible_world: Rect2 = view.visible_rect()
	var camera_rect := Rect2(visible_world.position / TILE, visible_world.size / TILE)
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
			"player": frame.player, "inspected": frame.inspected, "counters": frame.counters, "action_trace": frame.action_trace, "decision_trace": frame.decision_trace,
			"tool": controls.tool, "minimap_usec": ui.minimap.work_usec})
	return result


func _update_direction_marker() -> void:
	var position: Vector2 = _displayed(1)
	_display_move = Vector2.ZERO
	if _last_direction_epoch == frame.epoch and _last_displayed_player.is_finite() and not frame.paused:
		var movement: Vector2 = position - _last_displayed_player
		if movement.length_squared() > 0.00000001 and movement.length_squared() < 1.0: _display_move = movement.normalized()
	_last_displayed_player = position
	_last_direction_epoch = frame.epoch


func _draw_control_direction(canvas: Node2D, origin: Vector2, actions: Dictionary) -> void:
	if not controls.direct or controls.locked() or frame.paused or int(frame.player.get("hp", 0)) <= 0: return
	var aim: Vector2 = controls._aim
	var side := Vector2(-aim.y, aim.x)
	canvas.draw_colored_polygon(PackedVector2Array([origin + aim * 24, origin + aim * 17 + side * 3, origin + aim * 17 - side * 3]), Color("e8ddb1"))
	if not _display_move.is_zero_approx() and _display_move.dot(aim) < 0.7:
		var normal := Vector2(-_display_move.y, _display_move.x)
		canvas.draw_polyline(PackedVector2Array([origin + _display_move * 8 + normal * 3, origin + _display_move * 12, origin + _display_move * 8 - normal * 3]), Color("80c5bf"), 1.5, true)
	var action: Dictionary = actions.get(1, {})
	if not action.is_empty() and not ActionDefs.is_evade(action.kind) and render_ms >= int(action.started_ms) and render_ms < int(action.end_ms):
		var angle: float = Vector2(action.direction).angle()
		canvas.draw_arc(origin, 15, angle - 0.42, angle + 0.42, 10, Color("ffb45f"), 3.2, true)


func _paint_world(canvas: Node2D) -> void:
	if frame == null:
		return
	canvas.draw_arc(_displayed(1) * TILE, 15, 0, TAU, 24, Color.GOLD, 2.0)
	var actions: Dictionary = _actions_at(_render_pose) if _render_pose != null else {}
	_draw_control_direction(canvas, _displayed(1) * TILE, actions)
	for actor: int in actions:
		var slot: int = int(frame.actor_slots.get(actor, -1))
		if slot < 0 or (fog_enabled and frame.visible[slot] == 0): continue
		var state: Dictionary = actions[actor]
		if render_ms < int(state.started_ms) or render_ms >= int(state.end_ms): continue
		var def: Dictionary = ActionDefs.ACTIONS[state.kind]
		var origin: Vector2 = _displayed(actor) * TILE
		var direction: Vector2 = state.direction
		var active: bool = render_ms >= int(state.active_ms) and render_ms < int(state.recovery_ms)
		var color := Color("f9d384") if actor == 1 else Color("ff7868")
		if def.has("reach"):
			var polygon: PackedVector2Array = ActionDefs.sector(def, direction)
			for index: int in polygon.size(): polygon[index] = origin + polygon[index] * TILE
			var winding: bool = render_ms < int(state.active_ms)
			var enemy: bool = int(def.post) > 0
			if enemy and winding:
				var warning: float = clampf((render_ms - int(state.started_ms)) / maxi(1, int(state.active_ms) - int(state.started_ms)), 0, 1)
				canvas.draw_colored_polygon(polygon, Color(color, 0.05 + warning * 0.13))
				canvas.draw_arc(origin, float(def.reach) * TILE, direction.angle() - float(def.angle), direction.angle() - float(def.angle) + warning * float(def.angle) * 2, 20, Color(color, 0.9), 2.0, true)
			elif active: canvas.draw_colored_polygon(polygon, Color(color, 0.25))
			if active:
				var progress: float = clampf(float(render_ms - int(state.active_ms)) / int(def.active), 0, 1)
				var tip: Vector2 = origin + direction.rotated(lerpf(-float(def.angle), float(def.angle), progress)) * float(def.reach) * TILE
				canvas.draw_line(origin + direction * 6, tip, Color("fff3c2"), 4.5 if preload("res://scripts/sim/kernel/effect_payload.gd").summary(def.payload).heavy_hit else 3.0, true)
			elif winding and not enemy:
				canvas.draw_arc(origin, 19, direction.angle() - 0.3, direction.angle() + 0.3, 8, Color(color, 0.5), 2, true)
			if bool(def.get("steady", false)) and render_ms < int(state.recovery_ms):
				canvas.draw_arc(origin, 18, -2.8, -0.35, 16, Color("edbe67"), 3.0, true)
		elif not ActionDefs.is_evade(state.kind):
			if render_ms < int(state.recovery_ms): canvas.draw_line(origin, origin + direction * (22 if actor == 1 else 80), Color(color, 0.8), 2.0, true)
		else:
			canvas.draw_line(origin - direction * 22, origin, Color(color, 0.6), 5.0, true)
			if render_ms < int(state.started_ms) + ActionDefs.EVADE_MS: canvas.draw_arc(origin, 13, 0, TAU, 18, Color("b1e5e3"), 1.8, true)
	# Visible local health/anti-control cues; no hidden enemy values are revealed.
	if not frame.practice_mode.is_empty():
		for id: int in frame.actor_slots:
			var slot: int = frame.actor_slots[id]
			if id == 1 or frame.sides[slot] != 1 or frame.health[slot] <= 0 or (fog_enabled and frame.visible[slot] == 0): continue
			var point: Vector2 = _displayed(id) * TILE + Vector2(0, -43)
			var max_hp: float = maxf(1, frame.max_health[slot])
			canvas.draw_line(point - Vector2(16, 0), point + Vector2(16, 0), Color("292523"), 4)
			canvas.draw_line(point - Vector2(16, 0), point - Vector2(16, 0) + Vector2(32 * clampf(frame.health[slot] / max_hp, 0, 1), 0), Color("df8b70"), 3)
	for id: int in frame.reactions:
		if not frame.actor_slots.has(id): continue
		var slot: int = frame.actor_slots[id]
		if frame.health[slot] <= 0 or (fog_enabled and id != 1 and frame.visible[slot] == 0): continue
		var value: Dictionary = frame.reactions[id]
		if value.get("punishable", false) and not value.get("punished", false) and render_ms >= int(value.get("recovery_from", 0)) and render_ms < int(value.get("recovery_until", 0)):
			var point: Vector2 = _displayed(id) * TILE
			for side: float in [-1.0, 1.0]:
				canvas.draw_polyline(PackedVector2Array([point + Vector2(side * 23, -7), point + Vector2(side * 18, 0), point + Vector2(side * 23, 7)]), Color("b1e5e3"), 1.8, true)
		if int(value.get("stun_used", 0)) > ActionDefs.CONTROL_BUDGET_MS - 40 and render_ms >= int(value.get("guard_from", 0)) and render_ms < int(value.get("stun_window", 0)) + ActionDefs.CONTROL_WINDOW_MS:
			canvas.draw_arc(_displayed(id) * TILE, 13, 0.2, 2.9, 12, Color("91a9d2"), 1.5, true)
	if frame.actor_slots.has(selected) and (not fog_enabled or frame.visible[frame.actor_slots[selected]] != 0):
		canvas.draw_arc(_displayed(selected) * TILE, 18, 0, TAU, 24, Color.CYAN, 2.0)
	elif selected_tile >= 0:
		canvas.draw_rect(Rect2(Vector2(Terrain.cell(selected_tile)) * TILE, Vector2.ONE * TILE), Color.CYAN, false, 2.0)
	if _target.x >= 0:
		canvas.draw_circle(_target * TILE, 5, Color.GOLD)
	if _show_path and frame.actor_slots.has(selected) and (not fog_enabled or frame.visible[frame.actor_slots[selected]] != 0) and frame.inspected.get("id", 0) == selected:
		var points := PackedVector2Array([_displayed(selected) * TILE])
		for point: Vector2 in frame.inspected.get("route_preview", PackedVector2Array()):
			points.append(Art.body_foot(point) * TILE)
		if points.size() > 1: canvas.draw_polyline(points, Color(0.3, 0.9, 1.0, 0.65), 1.5)
	if not _show_sources: return
	for source: int in frame.mobile_cells.size():
		if frame.mobile_cells[source] < 0:
			continue
		if fog_enabled and frame.perception.tiles[frame.mobile_cells[source]] == 0:
			continue
		canvas.draw_arc(Art.body_foot(Terrain.center(frame.mobile_cells[source])) * TILE, 10, 0, TAU, 12, Ground.SOURCE_COLORS[source % 7], 1.5)


func _capture(now: int) -> void:
	if _capture_at == 0:
		if now - _ready_at >= _warmup * 1000000.0:
			_capture_at = now
			_capture_world = frame.world_ms
			_capture_counters = frame.counters.duplicate(true)
			_profile_before = frame.profile.duplicate(true)
			_capture_counters["minimap_usec"] = ui.minimap.work_usec
			_capture_age_usec = now - frame.published_usec
			_capture_adoptions = _adoptions
			print("KERNEL_CAPTURE_STARTED")
		return
	if now - _capture_at < _duration * 1000000.0:
		if _mid_at == 0 and now - _capture_at >= _duration * 500000.0:
			_mid_at = now
			_mid_counters = frame.counters.duplicate(true)
		return
	_duration = 0.0
	var report: Dictionary = frame.counters.duplicate(true)
	report.wall_seconds = (now - _capture_at) / 1000000.0
	report.world_delta_ms = frame.world_ms - _capture_world
	report.actual_speed = report.world_delta_ms / 1000.0 / report.wall_seconds
	report.requested_speed = speed
	report.fps_limit = _fps
	report.mixed = _mixed
	report.sim_hz = _sim_hz
	report.combat_lab = _combat_lab
	report.scenario = "capacity-act-v1" if _capacity else ("combat-lab-v1" if _combat_lab else ("mixed-act-v1" if _mixed else "ordinary"))
	report.activity_fraction = _percentiles(_activity_samples)
	report.view_warp = feedback.view_warp
	report.world_viewport = [view.viewport.size.x, view.viewport.size.y]
	report.camera = {"position": [camera.position.x, camera.position.y], "zoom": camera.zoom.x}
	report.ui_open = {"drawer": ui._drawer_name, "inventory": ui.inventory.visible}
	if _combat_probe:
		report.scenario = "framework-combat-v1"
		report.profile = frame.profile.duplicate(true)
		for field: String in _profile_before:
			if frame.profile[field] is int and not field.begins_with("peak_"): report.profile[field + "_delta"] = int(frame.profile[field]) - int(_profile_before[field])
	report.segments = []
	if _mid_at > 0:
		for index: int in 2:
			var before: Dictionary = _capture_counters if index == 0 else _mid_counters
			var after: Dictionary = _mid_counters if index == 0 else frame.counters
			var wall: float = ((_mid_at - _capture_at) if index == 0 else (now - _mid_at)) / 1000000.0
			report.segments.append({"actual_speed": (int(after.world_ms) - int(before.world_ms)) / 1000.0 / wall,
				"moved_cells": float(after.moved_cells) - float(before.moved_cells), "hits": int(after.hits) - int(before.hits),
				"deliveries": int(after.deliveries) - int(before.deliveries), "alive": after.alive})
	report.renderer = RenderingServer.get_video_adapter_name()
	report.release = not OS.is_debug_build()
	report.frame_ms = _percentiles(_frame_times)
	report.process_ms = _percentiles(_process_times)
	report.adoption_ms = _percentiles(_adoption_times)
	report.gpu_ms = _percentiles(_gpu_times)
	report.render_cpu_ms = _percentiles(_render_cpu_times)
	var measured_steps: int = int(report.steps) - int(_capture_counters.steps)
	report.step_ms = _percentiles(report.step_window_usec.slice(-measured_steps) if measured_steps > 0 else [], 0.001)
	report.step_percentile_samples = mini(measured_steps, report.step_window_usec.size())
	report.measured_steps = measured_steps
	report.step_mean_ms = (int(report.step_usec) - int(_capture_counters.step_usec)) / 1000.0 / maxi(1, measured_steps)
	report.start_frame_age_usec = _capture_age_usec
	report.finish_frame_age_usec = now - frame.published_usec
	report.erase("step_window_usec")
	for key: String in ["steps", "moved_cells", "harvested", "deliveries", "step_usec", "environment_usec", "units_usec", "effects_usec", "snapshot_usec", "overload_demand_usec", "path_requests", "path_failures", "nature_usec", "combat_usec", "combat_prepare_usec", "combat_resolve_usec", "combat_collect_usec", "combat_damage_usec", "combat_slices", "melee_candidates", "melee_tests", "shots", "hits", "plant_collections", "plant_evaluations", "perception_usec", "sight_observers", "sight_candidates", "sight_queries", "sight_index_usec", "sight_batch_usec", "sight_parallel_batches", "sight_sync_usec", "sight_rebuilds", "unit_decisions", "unit_decision_usec"]:
		report[key + "_delta"] = float(report[key]) - float(_capture_counters[key])
	report.instance_slots = population.actor_count
	report.fog = fog_enabled
	report.visible_instances = frame.visible.count(1) if fog_enabled else frame.counters.actors
	report.adopted_frames = _adoptions
	report.adopted_frames_delta = _adoptions - _capture_adoptions
	report.minimap_usec = ui.minimap.work_usec
	report.minimap_usec_delta = ui.minimap.work_usec - int(_capture_counters.get("minimap_usec", 0))
	report.minimap_rebuilds = ui.minimap.rebuilds
	if _response_probe != null:
		report.scenario = "synthetic-move-response-v1"
		report.response_chain = _response_probe.report(_percentiles)
	if not _metrics_path.is_empty():
		var file := FileAccess.open(_metrics_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
		else:
			push_error("Cannot write metrics: " + _metrics_path)
	print("KERNEL_RESULT ", JSON.stringify(report))
	if not _screenshot_path.is_empty():
		get_viewport().get_texture().get_image().save_png(_screenshot_path)
	var valid: bool = report.world_delta_ms > 0 and report.moved_cells_delta > 0 and report.material == report.initial_material
	if _response_probe != null:
		valid = valid and report.response_chain.sample_count > 0 and report.response_chain.failures.is_empty()
	get_tree().quit(0 if valid else 1)


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
