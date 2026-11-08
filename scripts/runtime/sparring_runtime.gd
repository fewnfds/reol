class_name SparringRuntime
extends CommittedWorldCanvas
## Input and visible practice cues. Persistent stages belong to SimSparring.

const UI = preload("res://scripts/ui/reol_ui_theme.gd")
var panel: PanelContainer
var _line: Label
var _status: Label
var _invite: Button
var _strike: Button
var _stop: Button
var _badge: PanelContainer
var _badge_label: Label
var _notice: String = "选中身边同门，再开口约练。"
var _owner: WeakRef


func runtime() -> WorldContinuityRuntime:
	return _owner.get_ref() as WorldContinuityRuntime if _owner != null else null


func setup(adapter: WorldContinuityRuntime) -> void:
	_owner = weakref(adapter)
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 13
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	panel = PanelContainer.new()
	panel.theme = UI.create()
	panel.add_theme_stylebox_override("panel", UI.panel(UI.GOLD))
	screen.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -245
	panel.offset_right = 245
	panel.offset_top = 98
	var column := VBoxContainer.new()
	panel.add_child(column)
	UI.label(column, "同门切磋 · 点到为止", UI.GOLD, 20)
	_line = UI.label(column, _notice, UI.PAPER, 14)
	_line.custom_minimum_size = Vector2(460, 42)
	_status = UI.label(column, "", UI.JADE, 14)
	var row := HBoxContainer.new()
	column.add_child(row)
	_invite = UI.button(row, "约所选同门", invite_selected)
	_strike = UI.button(row, "试掌 · J", strike)
	_stop = UI.button(row, "收手", stop)
	UI.button(column, "收起 · K", panel.hide)
	UI.label(column, "WASD 走位 · Shift 闪身 · 空格暂停", UI.MUTED, 12)
	panel.hide()
	_badge = PanelContainer.new()
	_badge.theme = UI.create()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_theme_stylebox_override("panel", UI.panel(UI.GOLD))
	screen.add_child(_badge)
	_badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_badge.offset_left = -230
	_badge.offset_right = 230
	_badge.offset_top = -68
	_badge.offset_bottom = -18
	_badge_label = UI.label(_badge, "", UI.PAPER, 14)
	GameClock.time_advanced.connect(_on_time_advanced)
	refresh()


func invite_selected() -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if not adapter.human_player_active():
		return {"ok": false, "line": "雀身还没有与同门约掌的表达办法。"}
	if not adapter.player_journey.is_empty() or not adapter._home._player.motion.action.is_empty():
		_notice = "先停下行程或闪身，再开口约练。"
		refresh()
		return {"ok": false, "line": _notice}
	adapter.prepare_player_command()
	var target: String = adapter._selected_remote if not adapter._selected_remote.is_empty() else adapter._home._selected_actor
	if target == "player" or not _visible(target):
		_notice = "先点击身边看得见的同门，再开口约练。"
		refresh()
		return {"ok": false, "line": _notice}
	var result: Dictionary = adapter.world_sim.sparring.invite("player", target)
	_notice = str(result.line)
	if bool(result.ok):
		adapter._home._player.motion.velocity = Vector2.ZERO
		panel.hide()
	adapter._home._sync_actor_views(true)
	refresh()
	return result


func strike() -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	var domain: SimSparring = adapter.world_sim.sparring
	if not domain.owns_actor("player"):
		return false
	var player: PlayerCharacter = adapter._home._player
	var accepted: bool = domain.strike("player", SimRouteTravel.point(domain.body(domain.opponent("player"))) - player.motion.position)
	if accepted:
		player.motion.velocity = Vector2.ZERO
		player.resources_changed.emit()
		adapter._home._sync_actor_views(true)
	refresh()
	return accepted


func stop() -> void:
	if runtime().world_sim.settlement != null and runtime().world_sim.settlement.is_pending():
		_notice = "当前结算尚未完成，本次停手未受理。"
		refresh()
		return
	runtime().world_sim.sparring.stop()
	_notice = "双方收手，各自调息；身上物资和已发生的事情都保留下来。"
	refresh()


func reset_observation() -> void:
	if not can_refresh_canvas():
		return
	clear_committed_canvas()
	_notice = "已接续保存时的约练与动作。" if runtime().world_sim.sparring.owns_actor("player") else "选中山门同门，再开口约练。"
	panel.hide()
	refresh()


func refresh() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or panel == null:
		return
	_line.text = _notice
	if not can_refresh_canvas():
		return
	var domain: SimSparring = adapter.world_sim.sparring
	var active: bool = domain.owns_actor("player")
	_invite.disabled = active
	_strike.disabled = not active or domain.action_blocks("player") or not adapter._home._player.motion.action.is_empty()
	_stop.disabled = not active
	_badge.visible = active
	if active:
		var target: String = domain.opponent("player")
		var opponent_stamina: int = int(domain.body(target).stamina)
		var state: String = "步履仍稳" if opponent_stamina > int(domain.rules.stop_stamina) * 2 else "已显疲态"
		_status.text = "你：%s · 对方%s" % [_phase_line(domain.phase("player", adapter.world_sim.elapsed_ms)), state]
		_badge_label.text = "切磋 · %s · 体力%d\nJ 出掌 · Shift 闪身 · K 面板" % [_phase_line(domain.phase("player", adapter.world_sim.elapsed_ms)), int(domain.body("player").stamina)]
	elif not domain.last_result.is_empty():
		_status.text = "已经收手。短时体力会在调息后恢复。"
	else:
		_status.text = "对方有自己的活计和处境，可以拒绝。"
	queue_redraw()


func _on_time_advanced(_from: int, _to: int) -> void:
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not runtime().human_player_active():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_K:
			panel.visible = not panel.visible
			refresh()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_J and runtime().world_sim.sparring.owns_actor("player"):
			strike()
			get_viewport().set_input_as_handled()


func _visible(id: String) -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	var person: Dictionary = adapter.world_sim.sparring.body(id)
	if person.is_empty():
		return false
	return adapter._home._fog == null or adapter._home._fog.is_cell_visible(SimRouteTravel.cell(person.cell))


func _build_canvas() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or adapter.world_sim.sparring.bout.is_empty():
		return
	var domain: SimSparring = adapter.world_sim.sparring
	for id: String in domain.bout.people:
		if not _visible(id):
			continue
		var point: Vector2 = SimRouteTravel.point(domain.body(id))
		point.y -= adapter._home._world.get_elevation(TileGrid.world_to_cell(point)) * ReolWorld.ELEVATION_PX
		var action: Dictionary = domain.bout.people[id].action
		capture_arc(point, 26, 0, TAU, 24, UI.GOLD, 2, true)
		if action.is_empty():
			continue
		var raw: Array = action.direction
		var angle: float = Vector2(float(raw[0]), float(raw[1])).angle()
		var half: float = deg_to_rad(float(domain.rules.strike.half_angle_degrees))
		var color: Color = UI.GOLD if domain.phase(id, adapter.world_sim.elapsed_ms) == "prepare" else UI.WARNING
		if domain.phase(id, adapter.world_sim.elapsed_ms) == "recover":
			color.a = 0.25
		var reach: float = float(domain.rules.strike.reach)
		capture_arc(point, reach, angle - half, angle + half, 20, color, 3, true)
		capture_line(point, point + Vector2.from_angle(angle - half) * reach, color, 1.5, true)
		capture_line(point, point + Vector2.from_angle(angle + half) * reach, color, 1.5, true)


static func _phase_line(phase: String) -> String:
	match phase:
		"prepare": return "起势"
		"contact": return "发力"
		"recover": return "收势"
	return "可走位或出掌"
