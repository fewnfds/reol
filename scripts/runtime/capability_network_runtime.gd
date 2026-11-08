class_name CapabilityNetworkRuntime
extends Node
## Rebuildable view of the actor's own evidence; no learning state lives here.

const UI = preload("res://scripts/ui/reol_ui_theme.gd")
var panel: PanelContainer
var badge: PanelContainer
var _owner: WeakRef
var _nodes: Dictionary = {}
var _detail: Label
var _progress: Label
var _notice: Label
var _begin: Button
var _cancel: Button
var _badge_line: Label
var _selected: String = "mobile_guard"
var _last_refresh_ms: int = -1


func runtime() -> WorldContinuityRuntime:
	return _owner.get_ref() as WorldContinuityRuntime if _owner != null else null


func setup(adapter: WorldContinuityRuntime) -> void:
	_owner = weakref(adapter)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	var screen := Control.new()
	layer.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.theme = UI.create()
	panel.add_theme_stylebox_override("panel", UI.panel(UI.GOLD))
	screen.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -400
	panel.offset_right = 400
	panel.offset_top = 105
	panel.offset_bottom = 650
	var column := VBoxContainer.new()
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	UI.label(header, "我的本领 · 所知从何而来", UI.GOLD, 20)
	UI.button(header, "收起", panel.hide)
	UI.label(column, "选择一项查看自己的来源。读过、试过、会用各有依据；图上的联系不等于已经掌握。", UI.MUTED, 13)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 220
	row.add_child(left)
	for id: String in adapter.home_runtime()._content.capability_network.nodes:
		var spec: Dictionary = adapter.home_runtime()._content.capability_network.nodes[id]
		var button: Button = UI.button(left, str(spec.label), _select.bind(id))
		button.custom_minimum_size.y = 44
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_nodes[id] = button
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(scroll)
	_detail = UI.label(scroll, "", UI.PAPER, 14)
	_detail.custom_minimum_size.x = 470
	_progress = UI.label(column, "", UI.JADE, 14)
	_notice = UI.label(column, "", UI.WARNING, 14)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	_begin = UI.button(actions, "练习行气护身 · 一分钟", begin_practice)
	_cancel = UI.button(actions, "中止本次练习", cancel_practice)
	UI.label(column, "U回到招式操作 · 行气护身只放开护障施法时的缓步；原动作结束后本就能正常走动。", UI.MUTED, 12)
	panel.hide()
	badge = PanelContainer.new()
	badge.theme = panel.theme
	screen.add_child(badge)
	badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -320
	badge.offset_right = -16
	badge.offset_top = 72
	_badge_line = UI.label(badge, "", UI.JADE, 13)
	GameClock.time_advanced.connect(_on_advanced)
	adapter.avatar_changed.connect(reset_observation)
	panel.visibility_changed.connect(refresh)
	refresh()


func _select(id: String) -> void:
	_selected = id
	refresh()


func show_panel() -> void:
	if not runtime().human_player_active():
		return
	runtime().conflict_adapter.panel.hide()
	panel.show()
	refresh()


func begin_practice() -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if not adapter.human_player_active() or adapter.home_runtime()._player.altitude != 0 or not adapter.player_journey.is_empty() or not adapter.home_runtime()._player.motion.action.is_empty():
		_notice.text = "先以人身落地，结束闪身和远行，再找空地练习。"
		return {"ok": false, "line": _notice.text}
	adapter.prepare_player_command()
	var response: Dictionary = adapter.world_sim.capability_practice.begin("player", "mobile_guard")
	_notice.text = str(response.get("line", "这次练习没有开始。"))
	if bool(response.get("ok", false)):
		adapter.hold_player_motion(true)
	refresh()
	return response


func cancel_practice() -> void:
	if runtime().world_sim.settlement != null and runtime().world_sim.settlement.is_pending():
		_notice.text = "当前结算尚未完成，本次停止未受理。"
	else:
		var accepted: bool = runtime().world_sim.capability_practice.cancel("player", "player_cancelled")
		_notice.text = "已中止；已付时间与气力保留，未完成便没有练成本领。" if accepted else "眼下没有正在进行的练习。"
	refresh()


func reset_observation() -> void:
	panel.hide()
	_notice.text = ""
	_last_refresh_ms = -1
	refresh()


func _on_advanced(_from: int, to: int) -> void:
	if _last_refresh_ms < 0 or to - _last_refresh_ms >= 250:
		refresh()


func refresh() -> void:
	if runtime() != null and runtime().world_sim.settlement.is_pending():
		return
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or panel == null:
		return
	_last_refresh_ms = adapter.world_sim.elapsed_ms
	var domain: RefCounted = adapter.world_sim.capability_practice
	var status: Dictionary = domain.status("player")
	var active: bool = bool(status.get("active", false))
	badge.visible = active and adapter.human_player_active() and not panel.visible
	_badge_line.text = str(status.get("line", ""))
	if not panel.visible:
		return
	if not adapter.human_player_active():
		panel.hide()
		return
	var projection: Dictionary = SimCapabilityQueries.project(adapter.world_sim, "player")
	var selected: Dictionary = {}
	for node: Dictionary in projection.nodes:
		var id: String = str(node.id)
		if _nodes.has(id):
			_nodes[id].text = str(node.label) + "\n" + _state_label(str(node.state))
			_nodes[id].modulate = UI.GOLD if id == _selected else Color.WHITE
		if id == _selected:
			selected = node
	var lines: Array[String] = []
	if not selected.is_empty():
		lines.append(str(selected.label) + "\n" + str(selected.line))
		for source: Dictionary in selected.get("sources", []):
			lines.append(_source_line(source))
		for instance: Dictionary in selected.get("instances", []):
			lines.append("\n" + str(instance.get("label", instance.get("content_id", ""))) + "：" + str(instance.get("line", "")))
		for missing: String in selected.get("missing", []):
			lines.append("· " + missing)
		for edge: Dictionary in projection.edges:
			if edge.get("to") == _selected or edge.get("from") == _selected:
				lines.append("联系：" + str(edge.get("label", "")))
	_detail.text = "\n\n".join(lines)
	_progress.text = str(status.get("line", "")) if active else "基础：走路、交流、停下和已有闪身不需要在图上解锁。"
	_begin.visible = _selected == "mobile_guard"
	_cancel.visible = active
	_begin.disabled = active or domain.learned("player", "mobile_guard") or not str(domain.readiness("player", "mobile_guard")).is_empty()


func _source_line(source: Dictionary) -> String:
	var actor: String = str(source.get("source", ""))
	for simulation: VillageSimulation in runtime().world_sim.regions.values():
		if simulation.actors.has(actor):
			actor = simulation._name(actor)
			break
	var label: String = {"background": "既有经历", "lesson": "当面示范", "artifact_event": "亲自实践", "opening_experience": "既有器物经验", "method_draft": "本人草案", "record_read": "实际阅读", "practice": "完成练习"}.get(str(source.get("kind", "")), "本人经历")
	var time: int = int(source.get("at_ms", -1))
	return "来源：" + label + (" · " + actor if not actor.is_empty() else "") + (" · 历时%d分%d秒" % [floori(float(time) / 60000.0), floori(float(time) / 1000.0) % 60] if time >= 0 else " · 当时时刻未记")


func _state_label(state: String) -> String:
	return {"unknown": "尚无亲历依据", "learned": "本人会用", "known_versions": "有本人所知的版本", "read": "亲自辨读过", "observed": "亲眼见过，尚不懂用", "held_unread": "实际持有，尚未读", "reported": "曾获具名指点", "draft": "本人草拟", "can_practice": "可尝试练习", "practicing": "正在实际练习", "conditions_missing": "眼下条件不足"}.get(state, state)
