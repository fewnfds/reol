class_name WorldObjectsRuntime
extends Node2D
## Local rendering/selection and intent routing for the pure object domain.

var panel: ObjectInspectionPanel
var selected_object: String = ""
var _owner: WeakRef
var _notice: String = ""
var _settled_event: String = ""


func runtime() -> WorldContinuityRuntime:
	return _owner.get_ref() as WorldContinuityRuntime if _owner != null else null


func setup(adapter: WorldContinuityRuntime) -> void:
	_owner = weakref(adapter)
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 12
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	panel = ObjectInspectionPanel.new()
	screen.add_child(panel)
	panel.set_terms(adapter.world_sim.artifacts.definitions.verbs)
	panel.action_requested.connect(submit)
	adapter.avatar_changed.connect(reset_observation)
	if adapter._home._fog != null and not adapter._home._fog.visibility_updated.is_connected(refresh):
		adapter._home._fog.visibility_updated.connect(refresh)
	queue_redraw()


func select_object(id: String) -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	var view: Dictionary = _perception(id)
	if not bool(view.get("known", false)):
		return false
	if adapter.heat_method_adapter != null:
		adapter.heat_method_adapter.panel.hide()
	selected_object = id
	_notice = ""
	var spirit: Node = adapter.get("spirit_adapter") as Node
	if spirit != null:
		spirit.panel.hide()
	if adapter.soul_adapter != null:
		adapter.soul_adapter.panel.hide()
	panel.show()
	refresh()
	return true


func submit(verb: String) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null:
		return {"ok": false, "line": "世界尚未就绪。"}
	if not adapter.human_player_active():
		return {"ok": false, "line": "当前形态还不能借人的双手操作器物。"}
	if verb == "cancel":
		var warming: bool = adapter.world_sim.artifacts.active.get("player", {}).get("verb") == "warm"
		adapter.stop_player_action()
		_notice = "释热已停止，石中余热没有耗去，身边也没有留下暖流。" if warming else "操作已停止，已投入的灵气不会退回。"
		refresh()
		return {"ok": true, "line": _notice}
	var domain: SimArtifacts = adapter.world_sim.artifacts
	var view: Dictionary = _perception(selected_object)
	if not bool(view.get("known", false)):
		return {"ok": false, "line": "你还没有看清这件器物。"}
	var thermal: bool = domain.has_capability(selected_object, "heat_storage")
	if verb in ["methods", "spirit_source", "to_garden"] and not thermal:
		return _refuse("这件器物没有储热用法，不能借它温养、引息或烘药。")
	if verb == "methods":
		adapter.heat_method_adapter.show_panel()
		return {"ok": true, "line": "翻开自己的温养手记。"}
	if verb == "spirit_source":
		var spirit: Node = adapter.get("spirit_adapter") as Node
		var opened: bool = spirit != null and spirit.show_panel(selected_object)
		_notice = "查看灶旁源隙，选择把息引入何处。" if opened else "先走到灶旁，看清那里地火隙的踪迹。"
		refresh()
		return {"ok": opened, "line": _notice}
	if verb in ["ask_examine", "ask_study"]:
		if not domain.verbs_for(selected_object).has("examine" if verb == "ask_examine" else "study"):
			return _refuse("这件器物眼下不能这样探查。")
		if not bool(view.get("near", false)):
			return _refuse("先走近并看清器物，再请人动手。")
		var selected: String = adapter._home._selected_actor
		if selected == "player" or not adapter._home._is_actor_visible(selected):
			return {"ok": false, "line": "先在器物旁选中看得见的同门，再请他帮忙。"}
		adapter.prepare_player_command()
		var response: Dictionary = adapter.interaction_adapter.submit(adapter.world_sim.embodiment.subject_for_actor(selected), "examine" if verb == "ask_examine" else "study", {"kind": "artifact", "id": selected_object})
		_notice = str(response.line)
		adapter._refresh_panel()
		refresh()
		return response
	if verb == "to_garden":
		var garden: Vector2i = SimRouteTravel.cell(adapter.world_sim.regions.home.places.garden.cell)
		var accepted: bool = bool(view.get("method", false)) and bool(view.get("held", false)) and adapter.travel_to("home", garden)
		_notice = "带着石头前往药圃，到了再尝试烘药。" if accepted else "先学会用法并取在手中，再去药圃。"
		refresh()
		return {"ok": accepted, "line": _notice}
	if verb == "approach":
		var raw: Array = view.cell
		var target := Vector2i(int(raw[0]), int(raw[1]))
		var accepted: bool = adapter.travel_to(str(view.region), target)
		_notice = "正在走向你见到器物的位置。" if accepted else "眼下无法走过去，请先停止其他行动。"
		refresh()
		return {"ok": accepted, "line": _notice}
	# Validate the actual object's affordance before cancelling a real activity.
	if not domain.verbs_for(selected_object).has(verb):
		return _refuse("这件器物没有这种用法。")
	if not bool(view.get("near", false)):
		return _refuse("先走近并看清器物，再动手操作。")
	if not adapter.player_journey.is_empty():
		_notice = "先走到近处，或停止当前行程。"
		refresh()
		return {"ok": false, "line": _notice}
	adapter.prepare_player_command()
	var result: Dictionary = domain.begin("player", verb, selected_object)
	_notice = str(result.line)
	if bool(result.ok):
		adapter.hold_player_motion()
	adapter._refresh_panel()
	refresh()
	return result


func _refuse(line: String) -> Dictionary:
	_notice = line
	refresh()
	return {"ok": false, "line": line}


func reset_observation() -> void:
	selected_object = ""
	_notice = ""
	_settled_event = ""
	panel.hide()
	queue_redraw()


func refresh() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null:
		return
	if not selected_object.is_empty():
		var view: Dictionary = _perception(selected_object)
		if not bool(view.get("known", false)):
			reset_observation()
		else:
			var thermal: bool = adapter.world_sim.artifacts.has_capability(selected_object, "heat_storage")
			panel.set_terms(adapter.world_sim.artifacts.verbs_for(selected_object), thermal)
			var status: Dictionary = adapter.world_sim.artifacts.status("player", selected_object)
			if not bool(status.busy) and not str(status.get("event", "")).is_empty() and _settled_event != str(status.event):
				_settled_event = str(status.event)
				_notice = str(status.line)
			panel.update_view(view, status, _notice)
			var spirit: Node = adapter.get("spirit_adapter") as Node
			panel.set_source_entry(thermal and spirit != null and spirit.has_known_source())
	queue_redraw()


func _process(_delta: float) -> void:
	# Only presentation: carried items follow the holder's interpolated view.
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter != null and not adapter.human_player_active():
		return
	if adapter == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and panel.visible:
			panel.hide()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_I:
			if panel.visible:
				panel.hide()
			else:
				var candidates: Array = adapter.world_sim.artifacts.objects.keys()
				candidates.sort()
				var thermal: Array = []
				var others: Array = []
				for id: String in candidates:
					if adapter.world_sim.artifacts.has_capability(id, "heat_storage"):
						thermal.append(id)
					else:
						others.append(id)
				candidates = thermal + others
				for id: String in candidates:
					if select_object(id):
						break
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cursor: Vector2 = get_canvas_transform().affine_inverse() * event.position
		for id: String in adapter.world_sim.artifacts.objects:
			if _visible(id) and cursor.distance_to(_display_point(id)) <= 22.0 and select_object(id):
				get_viewport().set_input_as_handled()
				break


func _visible(id: String) -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active():
		return false
	var domain: SimArtifacts = adapter.world_sim.artifacts
	return domain.can_see("player", id) and (adapter._home._fog == null or adapter._home._fog.is_cell_visible(domain.object_cell(id)))


func _perception(id: String) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active():
		return {"known": false}
	var domain: SimArtifacts = adapter.world_sim.artifacts
	if not domain.objects.has(id):
		return {"known": false}
	var item: Dictionary = domain.objects[id]
	var held: bool = item.container == "actor:player" and item.region == domain.actor_home("player")
	if _visible(id) or held:
		var view: Dictionary = domain.describe("player", id)
		view["region"] = item.region
		return view
	# Remember an actual personal/received record, never the hidden object's
	# current condition or location. Physical distance alone cannot reveal fog.
	return SimArtifacts.Understanding.remembered(domain, "player", id)


func _display_point(id: String) -> Vector2:
	var adapter: WorldContinuityRuntime = runtime()
	var domain: SimArtifacts = adapter.world_sim.artifacts
	var cell: Vector2i = domain.object_cell(id)
	var point: Vector2 = TileGrid.cell_to_world(cell)
	var item: Dictionary = domain.objects[id]
	var altitude: int = 0
	if item.container.begins_with("actor:"):
		var holder: String = str(item.container).trim_prefix("actor:")
		if holder == "player":
			point = adapter._home._player.global_position
			altitude = adapter._home._player.altitude
		else:
			var pawn: Pawn = adapter._home._pawns.get(holder) if item.region == "home" else adapter._remote_views.get(holder)
			if is_instance_valid(pawn):
				point = pawn.global_position + pawn.visual_offset
			else:
				point = SimRouteTravel.point(adapter.world_sim.regions[item.region].actors[holder])
	return point + Vector2(20, -24 - adapter._home._world.get_elevation(cell) * ReolWorld.ELEVATION_PX - altitude * ReolWorld.ALTITUDE_PX)


func _draw() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or adapter.world_sim == null:
		return
	for id: String in adapter.world_sim.artifacts.objects:
		if not _visible(id):
			continue
		var point: Vector2 = _display_point(id)
		if adapter.world_sim.artifacts.has_capability(id, "weapon"):
			_draw_wooden_sword(point)
			continue
		if adapter.world_sim.artifacts.has_capability(id, "remote_draw"):
			_draw_drawing_ring(point)
			continue
		var diamond := PackedVector2Array([point + Vector2(0, -9), point + Vector2(8, 0), point + Vector2(0, 9), point + Vector2(-8, 0)])
		draw_circle(point, 13, Color("#251c20"))
		draw_colored_polygon(diamond, Color("#a6553b"))
		draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color("#f0c989"), 2)
		draw_line(point + Vector2(-3, -3), point + Vector2(3, 3), Color("#e8b479"), 1.5)


func _draw_wooden_sword(point: Vector2) -> void:
	var tip: Vector2 = point + Vector2(8, -15)
	var pommel: Vector2 = point + Vector2(-8, 14)
	draw_line(pommel, tip, Color("#251c20"), 8)
	draw_line(point + Vector2(-2, 4), tip, Color("#d6ad71"), 5)
	draw_line(pommel, point + Vector2(-2, 4), Color("#6b513b"), 5)
	draw_line(point + Vector2(-8, 0), point + Vector2(5, 7), Color("#251c20"), 6)
	draw_line(point + Vector2(-8, 0), point + Vector2(5, 7), Color("#b8804b"), 3)


func _draw_drawing_ring(point: Vector2) -> void:
	# A hollow copper ring, without the warm stone's glow or solid centre.
	draw_arc(point, 9.0, 0.0, TAU, 24, Color("#251c20"), 6.0)
	draw_arc(point, 9.0, 0.0, TAU, 24, Color("#a8926a"), 3.0)
	draw_arc(point, 8.0, PI * 1.1, PI * 1.8, 8, Color("#ded8b9"), 1.0)
	draw_line(point + Vector2(7, -6), point + Vector2(11, -5), Color("#e6e4d2"), 2.0)
	draw_line(point + Vector2(-8, 3), point + Vector2(-11, 5), Color("#c2c8bf"), 2.0)
