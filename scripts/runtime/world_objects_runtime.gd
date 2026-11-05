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
	panel.draw_requested.connect(submit_draw)
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
	if verb == "use_research" and adapter.home_runtime()._player.altitude != 0:
		return _refuse("先落地停稳，再循内纹试引。")
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
		adapter.hold_player_motion(verb == "use_research")
	adapter._refresh_panel()
	refresh()
	return result


func _refuse(line: String) -> Dictionary:
	_notice = line
	refresh()
	return {"ok": false, "line": line}


func draw_targets() -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active():
		return choices
	var domain: SimArtifacts = adapter.world_sim.artifacts
	if not domain.has_capability(selected_object, "remote_draw"):
		return choices
	var definition: Dictionary = domain.definitions.types[domain.objects[selected_object].definition]
	for id: String in adapter.world_sim._sorted_keys(domain.objects):
		var item: Dictionary = domain.objects[id]
		if id == selected_object or not definition.drawing.target_definitions.has(item.definition) or str(item.container).begins_with("actor:") or not _visible(id):
			continue
		var target: Vector2 = TileGrid.cell_to_world(domain.object_cell(id))
		var origin: Vector2 = SimRouteTravel.point(adapter.world_sim.regions[domain.actor_home("player")].actors.player)
		var level: int = SimConflictSpace.level(adapter.world_sim, origin)
		if origin.distance_to(target) > float(definition.drawing.range_cells) * TileGrid.TILE_SIZE or level != SimConflictSpace.level(adapter.world_sim, target) or not SimConflictSpace.clear_segment(adapter.world_sim, origin, target, level):
			continue
		choices.append({"id": id, "label": str(domain.describe("player", id).label)})
	return choices


func submit_draw(target: String) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active():
		return {"ok": false, "line": "当前形体尚不能这样引物。"}
	var offered: bool = false
	for choice: Dictionary in draw_targets():
		offered = offered or choice.id == target
	if not offered or not bool(_perception(selected_object).get("held", false)):
		return _refuse("须持环，看清短距内松置且无遮挡的小器物。")
	if adapter.home_runtime()._player.altitude != 0 or not adapter.player_journey.is_empty() or not adapter.home_runtime()._player.motion.action.is_empty():
		return _refuse("先落地停稳，结束远行或闪身，再凝神引物。")
	adapter.prepare_player_command()
	var response: Dictionary = adapter.world_sim.artifacts.begin_draw("player", selected_object, target)
	_notice = str(response.line)
	if bool(response.ok):
		adapter.hold_player_motion(true)
	adapter._refresh_panel()
	refresh()
	return response


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
			var active_job: Dictionary = adapter.world_sim.artifacts.active.get("player", {})
			if active_job.get("verb") == "draw":
				status["remaining_ms"] = maxi(0, int(active_job.due_ms) - int(adapter.world_sim.elapsed_ms))
			if not bool(status.busy) and not str(status.get("event", "")).is_empty() and _settled_event != str(status.event):
				_settled_event = str(status.event)
				_notice = str(status.line)
			panel.set_draw_targets(draw_targets())
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
		var authority: RegionalSimulation = adapter.world_sim
		var points: Dictionary = _visible_display_points(authority)
		var hits: Array[String] = []
		for id: String in points:
			if cursor.distance_squared_to(points[id]) <= 22.0 * 22.0:
				hits.append(id)
		hits.sort_custom(func(left: String, right: String) -> bool:
			var left_distance: float = cursor.distance_squared_to(points[left])
			var right_distance: float = cursor.distance_squared_to(points[right])
			return left < right if left_distance == right_distance else left_distance < right_distance)
		if not hits.is_empty():
			# Independently moving holders can overlap a placed icon after layout.
			# Repeated clicks cycle the actual visible hits without moving any item.
			var previous: int = hits.find(selected_object) if panel.visible else -1
			if select_object(hits[(previous + 1) % hits.size()]):
				get_viewport().set_input_as_handled()


func _visible(id: String, observed_world: RegionalSimulation = null) -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active():
		return false
	# A reload may replace the accepted session during a debugger callback.
	# Keep the observed world alive for every weak-owned domain read in this view.
	var authority: RegionalSimulation = observed_world if observed_world != null else adapter.world_sim
	var domain: SimArtifacts = authority.artifacts
	return domain.can_see("player", id) and (adapter._home._fog == null or adapter._home._fog.is_cell_visible(domain.object_cell(id)))


func _perception(id: String) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active():
		return {"known": false}
	var authority: RegionalSimulation = adapter.world_sim
	var domain: SimArtifacts = authority.artifacts
	if not domain.objects.has(id):
		return {"known": false}
	var item: Dictionary = domain.objects[id]
	var held: bool = item.container == "actor:player" and item.region == domain.actor_home("player")
	if _visible(id, authority) or held:
		var view: Dictionary = domain.describe("player", id)
		view["region"] = item.region
		return view
	# Remember an actual personal/received record, never the hidden object's
	# current condition or location. Physical distance alone cannot reveal fog.
	return SimArtifacts.Understanding.remembered(domain, "player", id)


func _display_point(id: String, observed_world: RegionalSimulation = null) -> Vector2:
	var adapter: WorldContinuityRuntime = runtime()
	var authority: RegionalSimulation = observed_world if observed_world != null else adapter.world_sim
	var points: Dictionary = _visible_display_points(authority)
	return points[id] if points.has(id) else _base_display_point(id, authority)


func _visible_display_points(authority: RegionalSimulation) -> Dictionary:
	var domain: SimArtifacts = authority.artifacts
	# Separate only currently visible objects sharing this exact visual anchor.
	# These offsets are presentation only: cell, custody and reach stay in the
	# original domain. Singleton positions and holder interpolation stay intact.
	# Build once per draw or pointer event so many objects do not trigger one
	# full visibility scan per item. Nothing is cached across frames or saved.
	var points: Dictionary = {}
	var groups: Dictionary = {}
	for id: String in domain.objects:
		if not _visible(id, authority):
			continue
		var cell: Vector2i = domain.object_cell(id)
		var point: Vector2 = _base_display_point(id, authority)
		points[id] = point
		var cells: Dictionary = groups.get(point, {})
		var peers: Array = cells.get(cell, [])
		peers.append(id)
		cells[cell] = peers
		groups[point] = cells
	for point: Vector2 in groups:
		for peers: Array in groups[point].values():
			if peers.size() <= 1:
				continue
			peers.sort()
			for index: int in range(peers.size()):
				points[peers[index]] = point + Vector2(0, (float(index) - float(peers.size() - 1) * 0.5) * 32.0)
	return points


func _base_display_point(id: String, authority: RegionalSimulation) -> Vector2:
	var adapter: WorldContinuityRuntime = runtime()
	var domain: SimArtifacts = authority.artifacts
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
				point = SimRouteTravel.point(authority.regions[item.region].actors[holder])
	var offset := Vector2(20, -24 - adapter._home._world.get_elevation(cell) * ReolWorld.ELEVATION_PX - altitude * ReolWorld.ALTITUDE_PX)
	if domain.has_capability(id, "thermal_exchange"):
		# A visual offset distinguishes objects at the same original place. It
		# does not change their cell, heat source, custody or interaction range.
		var definition: Dictionary = domain.definitions.types[item.definition]
		offset.x += -32.0 if definition.thermal.mode == "emit" else 32.0
	return point + offset


func _draw() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or adapter.world_sim == null:
		return
	var authority: RegionalSimulation = adapter.world_sim
	var points: Dictionary = _visible_display_points(authority)
	var current: Dictionary = authority.artifacts.active.get("player", {})
	if current.has("draw") and points.has(str(current.draw.target)):
		var from: Vector2 = points[str(current.object)] if points.has(str(current.object)) else _base_display_point(str(current.object), authority)
		var to: Vector2 = points[str(current.draw.target)]
		var progress: float = clampf(float(authority.elapsed_ms - int(current.started_ms)) / float(int(current.due_ms) - int(current.started_ms)), 0.0, 1.0)
		draw_line(from, to, Color(0.63, 0.81, 0.77, 0.28), 1.0)
		draw_arc(to, 13.0 + 5.0 * (1.0 - progress), -PI * 0.5, TAU * progress - PI * 0.5, 24, Color("#c4ded5"), 2.0)
	for id: String in points:
		var point: Vector2 = points[id]
		if authority.artifacts.has_capability(id, "weapon"):
			_draw_wooden_sword(point)
			continue
		if authority.artifacts.has_capability(id, "remote_draw"):
			_draw_drawing_ring(point)
			continue
		if authority.artifacts.has_capability(id, "thermal_exchange"):
			var definition: Dictionary = authority.artifacts.definitions.types[authority.artifacts.objects[id].definition]
			_draw_thermal_stone(point, definition.thermal.mode == "emit")
			continue
		if authority.artifacts.has_capability(id, "intrinsic_light"):
			draw_circle(point, 11, Color("#302826"))
			draw_circle(point, 7, Color("#b5a86d"))
			draw_circle(point + Vector2(-2, -2), 3, Color("#f4e8ad"))
			continue
		var diamond := PackedVector2Array([point + Vector2(0, -9), point + Vector2(8, 0), point + Vector2(0, 9), point + Vector2(-8, 0)])
		draw_circle(point, 13, Color("#251c20"))
		draw_colored_polygon(diamond, Color("#a6553b"))
		draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color("#f0c989"), 2)
		draw_line(point + Vector2(-3, -3), point + Vector2(3, 3), Color("#e8b479"), 1.5)


func _draw_thermal_stone(point: Vector2, warm: bool) -> void:
	var rim: Color = Color("#f1bd8a") if warm else Color("#c3e8ed")
	var body: Color = Color("#a64f36") if warm else Color("#588fa5")
	var outline := PackedVector2Array([point + Vector2(-8, -6), point + Vector2(2, -10), point + Vector2(10, -3), point + Vector2(8, 7), point + Vector2(-4, 10), point + Vector2(-10, 3)])
	draw_circle(point, 13, Color("#251c20"))
	draw_colored_polygon(outline, body)
	draw_polyline(PackedVector2Array([outline[0], outline[1], outline[2], outline[3], outline[4], outline[5], outline[0]]), rim, 2.0)
	draw_line(point + Vector2(-5, -3), point + Vector2(4, 4), rim, 1.5)


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
