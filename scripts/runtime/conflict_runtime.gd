class_name ConflictRuntime
extends CommittedWorldCanvas
## Visible intentions and cues; bodies, techniques and costs stay in the sim.

const UI = preload("res://scripts/ui/reol_ui_theme.gd")
var panel: PanelContainer
var badge: PanelContainer
var _line: Label
var _status: Label
var _badge_label: Label
var _owner: WeakRef
var _notice: String = "选中近处人物，可请教本领；敌意交锋会留下真实消耗和挫伤。"
var _pending: String = ""
var _pending_direction: Vector2 = Vector2.DOWN
var _fight_buttons: Dictionary = {}


func runtime() -> WorldContinuityRuntime:
	return _owner.get_ref() as WorldContinuityRuntime if _owner != null else null


func setup(adapter: WorldContinuityRuntime) -> void:
	_owner = weakref(adapter)
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 13
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var screen := Control.new()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.theme = UI.create()
	panel.add_theme_stylebox_override("panel", UI.panel(UI.GOLD))
	screen.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -240
	panel.offset_right = 240
	panel.offset_top = 130
	var column := VBoxContainer.new()
	panel.add_child(column)
	UI.label(column, "本领与交锋", UI.GOLD, 20)
	_line = UI.label(column, "", UI.PAPER, 14)
	_line.custom_minimum_size = Vector2(450, 54)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status = UI.label(column, "", UI.JADE, 14)
	_status.custom_minimum_size.x = 450
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var row := HBoxContainer.new()
	column.add_child(row)
	UI.button(row, "请所选人物示范", teach_selected)
	UI.button(row, "向所选人物表明驱离敌意", engage_selected)
	UI.button(column, "查看本人的学习与实践", func() -> void: adapter.capability_adapter.show_panel())
	for method: String in adapter.world_sim.conflicts.rules.methods:
		var spec: Dictionary = adapter.world_sim.conflicts.rules.methods[method]
		_fight_buttons[method] = UI.button(column, str(spec.label) + {"sword": " · Q", "qi_bolt": " · E", "qi_guard": " · R"}[method], request_cast.bind(method))
	UI.button(column, "退让，停止交锋 · X", yield_player)
	UI.button(column, "收起 · U", panel.hide)
	UI.label(column, "I查看真实器物 · U本领 · WASD走位 · Shift闪身\n有限手段不取性命；已发出的气弹不会因停手消失。", UI.MUTED, 12)
	panel.hide()
	badge = PanelContainer.new()
	badge.theme = panel.theme
	badge.add_theme_stylebox_override("panel", UI.panel(UI.WARNING))
	screen.add_child(badge)
	badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	badge.offset_left = -260
	badge.offset_right = 260
	badge.offset_top = -88
	badge.offset_bottom = -12
	_badge_label = UI.label(badge, "", UI.PAPER, 14)
	GameClock.time_advanced.connect(_on_advanced)
	adapter.avatar_changed.connect(reset_observation)
	refresh()


func selected_target() -> String:
	var adapter: WorldContinuityRuntime = runtime()
	var id: String = adapter._selected_remote if not adapter._selected_remote.is_empty() else adapter.home_runtime()._selected_actor
	return id if id != "player" and _visible(id) else ""


func teach_selected() -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if not adapter.human_player_active() or adapter.home_runtime()._player.altitude != 0:
		return _result(false, "先以人身落地站稳，再当面练习；空中技法尚未开放。")
	adapter.prepare_player_command()
	var target: String = selected_target()
	if target.is_empty():
		return _result(false, "先选中身边看得见的人物。")
	var response: Dictionary = adapter.world_sim.conflicts.teach(target, "player")
	if bool(response.ok):
		adapter.hold_player_motion(true)
	return _result(bool(response.ok), str(response.line))


func engage_selected() -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if not adapter.human_player_active() or adapter.home_runtime()._player.altitude != 0:
		return _result(false, "先以人身落地站稳；这些手段只用于地面交锋。")
	adapter.prepare_player_command()
	var target: String = selected_target()
	if target.is_empty() or not adapter.player_journey.is_empty() or not adapter.home_runtime()._player.motion.action.is_empty():
		return _result(false, "先停下行程，选中眼前人物，再明确动手意图。")
	var response: Dictionary = adapter.world_sim.conflicts.begin("player", target)
	if bool(response.ok):
		GameClock.cancel_wait()
		GameClock.set_speed(1.0)
		adapter.hold_player_motion(true)
		adapter.service_adapter.panel.hide()
		panel.hide()
	return _result(bool(response.ok), str(response.line))


func request_cast(method: String) -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	var domain: SimConflicts = adapter.world_sim.conflicts
	if not adapter.human_player_active() or adapter.home_runtime()._player.altitude != 0 or domain.conflict_for("player").is_empty() or not domain.knows("player", method):
		return false
	var direction: Vector2 = get_global_mouse_position() - _visual(SimRouteTravel.point(domain.body("player")))
	if direction.is_zero_approx():
		direction = SimRouteTravel.facing(domain.body("player"))
	_pending = method
	_pending_direction = direction.normalized()
	_notice = "已选" + str(domain.rules.methods[method].label) + ("，继续时间后起势。" if GameClock.paused else "，将依眼前时刻施展。")
	refresh()
	return true


func yield_player() -> void:
	if runtime().world_sim.settlement != null and runtime().world_sim.settlement.is_pending():
		_notice = "当前结算尚未完成，本次停手未受理。"
		refresh()
		return
	_pending = ""
	runtime().world_sim.conflicts.cancel("player")
	_notice = "已经退让停手。可自行离开调息；挫伤和已付代价不会重置。"
	refresh()


func _on_advanced(_from: int, _to: int) -> void:
	if has_visible_danger():
		GameClock.cancel_wait()
		GameClock.set_speed(1.0)
	if not _pending.is_empty():
		var method: String = _pending
		_pending = ""
		var response: Dictionary = runtime().world_sim.conflicts.cast("player", method, _pending_direction)
		_notice = str(response.line)
		if bool(response.ok):
			var walking: Dictionary = runtime().world_sim.conflicts.walking_projection("player")
			if bool(walking.allowed):
				runtime().home_runtime()._player.motion.limit_walking_speed(float(walking.speed_fraction))
			else:
				runtime().hold_player_motion(true)
	refresh()


func has_visible_danger() -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active():
		return false
	var domain: SimConflicts = adapter.world_sim.conflicts
	for row: Dictionary in domain.conflicts.values():
		if int(row.ended_ms) == -1 and (_visible(str(row.initiator)) or _visible(str(row.defender))):
			return true
	for shot: Dictionary in domain.projectiles.values():
		if adapter.home_runtime()._fog == null or adapter.home_runtime()._fog.is_cell_visible(TileGrid.world_to_cell(SimConflicts._vector(shot.position))):
			return true
	return false


func reset_observation() -> void:
	if not can_refresh_canvas():
		return
	clear_committed_canvas()
	_pending = ""
	if panel != null:
		panel.hide()
	_notice = "本领、交锋和已付代价均沿保存时刻接续。"
	refresh()


func refresh() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or panel == null:
		return
	_line.text = _notice
	if not can_refresh_canvas():
		return
	var domain: SimConflicts = adapter.world_sim.conflicts
	var active: bool = not domain.conflict_for("player").is_empty()
	# Keep the world readable during actual fighting, including after a load.
	adapter.set_life_panels_available(adapter.human_player_active() and not active)
	badge.visible = active and adapter.human_player_active()
	var known: Array[String] = []
	for method: String in domain.rules.methods:
		if domain.knows("player", method):
			known.append(str(domain.rules.methods[method].label))
		_fight_buttons[method].disabled = not active or not domain.knows("player", method) or domain.action_blocks("player")
	var injury: String = "身有挫伤，宜先歇息" if adapter.world_sim.health.combat_burden("player") > 0 else "尚无交锋挫伤"
	_status.text = "已会：%s\n%s；木剑请到住处实际取用。" % ["、".join(known) if not known.is_empty() else "尚未学过这些手段", injury]
	if active:
		var phase: String = domain.phase("player", adapter.world_sim.elapsed_ms)
		_badge_label.text = "交锋 · %s · %s\nQ木剑 / E气弹 / R护障 · X退让 · 空格暂停" % [{"": "可走位", "prepare": "起势", "contact": "发力", "recover": "收势"}[phase], injury]
	redraw_committed_canvas()


func _result(ok: bool, line: String) -> Dictionary:
	_notice = line
	refresh()
	return {"ok": ok, "line": line}


func _visible(actor: String) -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	var person: Dictionary = adapter.world_sim.conflicts.body(actor)
	return not person.is_empty() and (adapter.home_runtime()._fog == null or adapter.home_runtime()._fog.is_cell_visible(SimRouteTravel.cell(person.cell)))


func _visual(point: Vector2) -> Vector2:
	return point - Vector2(0, runtime().world_sim.map_data.get_elevation(TileGrid.world_to_cell(point)) * ReolWorld.ELEVATION_PX)


func _build_canvas() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active():
		return
	var domain: SimConflicts = adapter.world_sim.conflicts
	for id: String in domain.conflicts:
		var row: Dictionary = domain.conflicts[id]
		if int(row.ended_ms) != -1:
			continue
		for actor: String in row.people:
			if not _visible(actor):
				continue
			var point: Vector2 = _visual(SimRouteTravel.point(domain.body(actor)))
			capture_arc(point, 26, 0, TAU, 24, UI.WARNING, 2)
			var aid: String = str(row.people[actor].action)
			if aid.is_empty():
				continue
			var action: Dictionary = domain.actions[aid]
			var direction: Vector2 = SimConflicts._vector(action.direction)
			var color: Color = UI.GOLD if domain.phase(actor, adapter.world_sim.elapsed_ms) == "prepare" else UI.WARNING
			if action.method == "sword":
				var half: float = deg_to_rad(float(domain.rules.methods.sword.half_angle_degrees))
				capture_arc(point, float(domain.rules.methods.sword.reach), direction.angle() - half, direction.angle() + half, 24, color, 3)
			elif action.method == "qi_bolt":
				capture_line(point, point + direction * 100, color, 2)
	for actor: String in domain.barriers:
		if _visible(actor):
			capture_arc(_visual(SimRouteTravel.point(domain.body(actor))), 34, 0, TAU, 28, UI.JADE, 4)
	for shot: Dictionary in domain.projectiles.values():
		var point: Vector2 = SimConflicts._vector(shot.position)
		var cell: Vector2i = TileGrid.world_to_cell(point)
		if adapter.home_runtime()._fog == null or adapter.home_runtime()._fog.is_cell_visible(cell):
			var display: Vector2 = point - Vector2(0, int(shot.level) * ReolWorld.ELEVATION_PX)
			capture_line(display - SimConflicts._vector(shot.direction) * 18, display, UI.JADE, 5)
			capture_circle(display, 5, UI.PAPER)


func _unhandled_input(event: InputEvent) -> void:
	if not runtime().human_player_active() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_U:
		if runtime().capability_adapter != null and runtime().capability_adapter.panel.visible:
			runtime().capability_adapter.panel.hide()
			panel.show()
		else:
			panel.visible = not panel.visible
		refresh()
		get_viewport().set_input_as_handled()
	elif not runtime().world_sim.conflicts.conflict_for("player").is_empty():
		if event.keycode == KEY_X:
			yield_player()
			get_viewport().set_input_as_handled()
		else:
			var method: String = {KEY_Q: "sword", KEY_E: "qi_bolt", KEY_R: "qi_guard"}.get(event.keycode, "")
			if not method.is_empty():
				request_cast(method)
				get_viewport().set_input_as_handled()
