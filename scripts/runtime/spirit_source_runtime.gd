class_name SpiritSourceRuntime
extends Node2D
## Source view and intentions only. SimSpiritSources owns all costs and effects.

var panel: SpiritSourcePanel
var selected_source: String = ""
var _owner: WeakRef
var _selected_object: String = ""
var _notice: String = ""
var _settled_event: String = ""
var _seen_sources: Dictionary = {}


func runtime() -> WorldContinuityRuntime:
	return _owner.get_ref() as WorldContinuityRuntime if _owner != null else null


func domain() -> RefCounted:
	var adapter: WorldContinuityRuntime = runtime()
	return adapter.world_sim.get("spirit_sources") as RefCounted if adapter != null and adapter.world_sim != null else null


func setup(adapter: WorldContinuityRuntime) -> void:
	_owner = weakref(adapter)
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 12
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	panel = SpiritSourcePanel.new()
	screen.add_child(panel)
	panel.action_requested.connect(submit)
	panel.choice_changed.connect(_on_choice_changed)
	if domain() != null:
		panel.set_terms(int(domain().definitions.duration_ms))
	queue_redraw()


func show_panel(object_id: String = "") -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active() or domain() == null:
		return false
	_selected_object = object_id
	if selected_source.is_empty():
		var candidates: Array = domain().definitions.sources.keys()
		candidates.sort()
		for id: String in candidates:
			if select_source(id):
				return true
		return false
	return select_source(selected_source)


func has_known_source() -> bool:
	var source: RefCounted = domain()
	if source == null:
		return false
	for id: String in source.definitions.sources:
		if bool(perception(id).get("known", false)):
			return true
	return false


func select_source(id: String) -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	var source: RefCounted = domain()
	if adapter == null or not adapter.human_player_active() or source == null or not source.definitions.sources.has(id):
		return false
	var view: Dictionary = perception(id)
	if not bool(view.get("known", false)):
		return false
	selected_source = id
	_notice = ""
	for key: String in ["object_adapter", "heat_method_adapter", "soul_adapter", "avian_adapter", "sparring_adapter", "interaction_adapter"]:
		var other: Node = adapter.get(key) as Node
		if other != null and other.get("panel") is Control:
			(other.get("panel") as Control).hide()
	panel.show()
	refresh()
	if is_inside_tree():
		panel.target_choice.grab_focus()
	return true


func source_cell(id: String) -> Vector2i:
	var source: RefCounted = domain()
	if source == null or not source.definitions.sources.has(id):
		return Vector2i(-1, -1)
	var terms: Dictionary = source.definitions.sources[id]
	var adapter: WorldContinuityRuntime = runtime()
	if not adapter.world_sim.regions.has(str(terms.region)):
		return Vector2i(-1, -1)
	var sim: VillageSimulation = adapter.world_sim.regions[str(terms.region)]
	return SimRouteTravel.cell(sim.places[str(terms.place)].cell) if sim.places.has(str(terms.place)) else Vector2i(-1, -1)


func source_visible(id: String) -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	var source: RefCounted = domain()
	if adapter == null or not adapter.human_player_active() or source == null:
		return false
	var cell: Vector2i = source_cell(id)
	if cell.x < 0 or adapter._home._fog != null and not adapter._home._fog.is_cell_visible(cell):
		return false
	var sim: VillageSimulation = adapter.world_sim.regions.home
	return sim.actor_position(sim.actors.player).distance_to(TileGrid.cell_to_world(cell)) <= float(sim.config.observation_radius) * TileGrid.TILE_SIZE


func perception(id: String) -> Dictionary:
	var source: RefCounted = domain()
	if source == null or not source.definitions.sources.has(id):
		return {"known": false, "near": false, "objects": []}
	var view: Dictionary = source.describe("player", id).duplicate(true)
	var visible_source: bool = source_visible(id)
	if visible_source:
		_seen_sources[id] = true
	elif not _seen_sources.has(id) and not bool(view.get("remembered", false)):
		# A nearby source behind an occluder is not a new observation merely
		# because the rule layer knows its distance. The player's own original
		# source history can still supply its remembered location after load.
		view.known = bool(view.get("known", false)) and not bool(view.get("near", false))
	if not visible_source:
		view.known = bool(view.get("known", false)) or _seen_sources.has(id)
		view.near = false
		view.objects = []
		view.line = "你只记得这处源隙在灶旁；眼下看不清近况。" if bool(view.get("known", false)) else "尚未亲眼看清这处源隙；先到灶旁看看。"
	return view


func submit(verb: String) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	var source: RefCounted = domain()
	if adapter == null or source == null or not adapter.human_player_active():
		return {"ok": false, "line": "眼下没有这副人身引息的方法。"}
	if verb == "cancel":
		if not source.owns_actor("player"):
			return _reply(false, "眼下没有正在进行的引息。")
		if not adapter.stop_player_action():
			return _reply(false, "当前结算尚未完成，本次停止未受理。")
		return _reply(true, "已停止自己的引息；未完成的源息没有收入身体或温石。")
	if verb == "object":
		if adapter.object_adapter.select_object(_selected_object):
			panel.hide()
			return {"ok": true, "line": "回到温石记录。"}
		return _reply(false, "眼下没有可回看的温石，先在近旁选定一块。")
	if selected_source.is_empty() or not source.definitions.sources.has(selected_source):
		return _reply(false, "先选中近旁见到的源隙。")
	if verb == "approach":
		var view: Dictionary = perception(selected_source)
		if not bool(view.get("known", false)):
			return _reply(false, "还没看清它的位置，先到灶旁看看。")
		var terms: Dictionary = source.definitions.sources[selected_source]
		var accepted: bool = adapter.travel_to(str(terms.region), source_cell(selected_source))
		return _reply(accepted, "正沿原路走到灶旁；到达后再选好目标引息。" if accepted else "先完成或停止手头的事情，才能走过去。")
	if verb != "begin":
		return _reply(false, "眼下没有这种引息做法。")
	if not adapter.player_journey.is_empty():
		return _reply(false, "先走到源隙近旁，或停止当前行程。")
	adapter.prepare_player_command()
	if not source_visible(selected_source):
		return _reply(false, "先亲眼看清近旁的源隙，再动手引息。")
	_selected_object = panel.selected_object()
	var result: Dictionary = source.begin("player", selected_source, panel.selected_target(), _selected_object)
	if bool(result.get("ok", false)):
		adapter.hold_player_motion(true)
	_notice = str(result.get("line", "这次引息没有开始。"))
	adapter._refresh_panel()
	refresh()
	return result


func _reply(ok: bool, line: String) -> Dictionary:
	_notice = line
	refresh()
	return {"ok": ok, "line": line}


func _on_choice_changed() -> void:
	_selected_object = panel.selected_object()
	refresh()


func reset_observation() -> void:
	selected_source = ""
	_selected_object = ""
	_notice = ""
	_settled_event = ""
	_seen_sources.clear()
	if panel != null:
		panel.hide()
	queue_redraw()


func refresh() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if panel == null or adapter == null or adapter.world_sim == null:
		return
	panel.update_notice(_notice)
	if adapter.world_sim.settlement != null and adapter.world_sim.settlement.is_pending():
		return
	var source: RefCounted = domain()
	if source == null:
		return
	if not adapter.human_player_active():
		panel.hide()
		queue_redraw()
		return
	if not selected_source.is_empty():
		var status: Dictionary = source.status("player")
		var event: String = str(status.get("event", ""))
		if not bool(status.get("busy", false)) and not event.is_empty() and event != _settled_event:
			_settled_event = event
			_notice = str(status.get("line", "引息已结束。"))
		panel.update_view(perception(selected_source), status, _notice, _selected_object)
		if not panel.selected_object().is_empty():
			_selected_object = panel.selected_object()
	queue_redraw()


func _display_point(id: String) -> Vector2:
	var adapter: WorldContinuityRuntime = runtime()
	var cell: Vector2i = source_cell(id)
	return TileGrid.cell_to_world(cell) + Vector2(-27, 17 - adapter._home._world.get_elevation(cell) * ReolWorld.ELEVATION_PX)


func _draw() -> void:
	var source: RefCounted = domain()
	if source == null:
		return
	var status: Dictionary = source.status("player")
	for id: String in source.definitions.sources:
		if not source_visible(id):
			continue
		var point: Vector2 = _display_point(id)
		draw_rect(Rect2(point + Vector2(-12, -5), Vector2(24, 12)), Color("#252829"))
		draw_rect(Rect2(point + Vector2(-9, -2), Vector2(8, 3)), Color("#ad583a"))
		draw_rect(Rect2(point + Vector2(-2, 1), Vector2(11, 3)), Color("#d99554"))
		draw_rect(Rect2(point + Vector2(-3, -1), Vector2(4, 3)), Color("#f0c989"))
		if str(status.get("source", "")) == id and bool(status.get("busy", false)):
			draw_arc(point, 16, 0.0, TAU, 16, Color("#d9be79"), 1.0)


func _unhandled_input(event: InputEvent) -> void:
	var adapter: WorldContinuityRuntime = runtime()
	var source: RefCounted = domain()
	if adapter == null or source == null or not adapter.human_player_active():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and panel.visible:
		panel.hide()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for id: String in source.definitions.sources:
			if source_visible(id) and get_global_mouse_position().distance_to(_display_point(id)) <= 18.0 and select_source(id):
				get_viewport().set_input_as_handled()
				break
