class_name WorldObjectsRuntime
extends CommittedWorldCanvas
## Local rendering/selection and intent routing for the pure object domain.

var panel: ObjectInspectionPanel
var selected_object: String = ""
var _owner: WeakRef
var _notice: String = ""
var _settled_event: String = ""
var _selection_hit: Vector2 = Vector2.INF
## Presentation pointer only; the action and its result remain in lifecycle.
var _physical_action: String = ""


func runtime() -> WorldContinuityRuntime:
	return _owner.get_ref() as WorldContinuityRuntime if _owner != null else null


func _can_observe(adapter: WorldContinuityRuntime) -> bool:
	return adapter != null and adapter.world_sim != null and (adapter.world_sim.settlement == null or not adapter.world_sim.settlement.is_pending())


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
	panel.cycle_requested.connect(_cycle_selection)
	adapter.avatar_changed.connect(reset_observation)
	if adapter._home._fog != null and not adapter._home._fog.visibility_updated.is_connected(refresh):
		adapter._home._fog.visibility_updated.connect(refresh)
	redraw_committed_canvas()


func select_object(id: String, hit_point: Vector2 = Vector2.INF) -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	if not _can_observe(adapter):
		return false
	var view: Dictionary = _perception(id)
	if not bool(view.get("known", false)):
		return false
	if adapter.heat_method_adapter != null:
		adapter.heat_method_adapter.panel.hide()
	selected_object = id
	_selection_hit = hit_point
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
		var result: Dictionary = adapter.request_player_command("cancel")
		if not result.ok or result.queued:
			_notice = str(result.line)
			refresh()
			return result
		_notice = "释热已停止，石中余热没有耗去，身边也没有留下暖流。" if warming else "操作已停止，已投入的灵气不会退回。"
		refresh()
		return {"ok": true, "line": _notice}
	var domain: SimArtifacts = adapter.world_sim.artifacts
	var view: Dictionary = _perception(selected_object)
	if not bool(view.get("known", false)):
		return {"ok": false, "line": "你还没有看清这件器物。"}
	if adapter.world_sim.object_lifecycle != null and adapter.world_sim.object_lifecycle.manages(selected_object):
		if verb == "approach":
			var observed: Array = view.cell
			var accepted: bool = adapter.travel_to(str(view.region), Vector2i(int(observed[0]), int(observed[1])))
			_notice = "正在走向你见到器物的位置。" if accepted else "眼下无法走过去，请先停止其他行动。"
			refresh()
			return {"ok": accepted, "line": _notice}
		return _submit_physical(verb, view)
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


func _submit_physical(verb: String, view: Dictionary) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	var authority: RegionalSimulation = adapter.world_sim
	var domain: SimArtifacts = authority.artifacts
	var lifecycle: SimObjectLifecycle = authority.object_lifecycle
	var id: String = selected_object
	if verb not in ["take", "place"] or not domain.has_capability(id, "physical") or not domain.verbs_for(id).has(verb):
		return _refuse("这件实物眼下不能这样操作。")
	if not bool(view.get("near", false)):
		return _refuse("先走近并看清实物，再动手操作。")
	if not adapter.player_journey.is_empty() or adapter.home_runtime()._player.altitude != 0 or not adapter.home_runtime()._player.motion.action.is_empty():
		return _refuse("先落地停稳，结束远行或闪身，再动手操作。")
	if authority.elapsed_ms != authority.target_ms:
		return _refuse("世界事务仍在接续，请稍后再动手。")
	var home: String = domain.actor_home("player")
	if home.is_empty() or not domain.objects.has(id):
		return _refuse("找不到本人或这件实物。")
	var item: Dictionary = domain.objects[id]
	if str(item.region) != home:
		return _refuse("这件实物不在本人当前的区域账本内。")
	var from_container: String = str(item.container)
	var destination: Dictionary
	if verb == "take":
		if not from_container.begins_with("ground:"):
			return _refuse("只能从地面取起这件实物；其他人或场所保管的东西需另行处理。")
		var footprint: Rect2i = _physical_ground_rect(id, authority)
		if footprint.size == Vector2i.ZERO or not _visible(id, authority):
			return _refuse("地面上的实物已经移走或看不清了。")
		if adapter.world_sim != authority:
			return _refuse("世界状态已经改变，请重新选择实物。")
		destination = {"region": home, "container": "actor:player"}
	else:
		if from_container != "actor:player":
			return _refuse("先把实物拿在自己手中。")
		var cell: Vector2i = adapter.controlled_cell()
		var raw_size: Array = domain.definitions.types[item.definition].placement.footprint
		var clearance: Dictionary = lifecycle.ground.can_place(home, cell, Vector2i(int(raw_size[0]), int(raw_size[1])))
		if not bool(clearance.get("ok", false)):
			return _refuse("脚边没有足够的可用地面放下这件实物。")
		destination = {"region": home, "cell": [cell.x, cell.y]}
	# Do not stop an existing activity just because the player clicked an
	# invalid command. The lifecycle also checks body ownership on schedule.
	if not authority.actor_controls("player", "action") or not authority.actor_controls("player", "motion") or authority.owns_for_scope("player", &"body"):
		return _refuse("先完成或中断手头的事情。")
	var actor: Dictionary = authority.regions[home].synchronize_actor("player")
	var origin: Vector2 = SimRouteTravel.point(actor)
	var target: Vector2 = TileGrid.cell_to_world(domain.object_cell(id)) if verb == "take" else origin
	var level: int = SimConflictSpace.level(authority, origin)
	var radius: float = float(domain.definitions.interaction_radius) * TileGrid.TILE_SIZE
	if origin.distance_to(target) > radius or level != SimConflictSpace.level(authority, target) or not SimConflictSpace.clear_segment(authority, origin, target, level):
		return _refuse("实物不在同高且无遮挡的触及范围内。")
	var command: String = _physical_command(lifecycle)
	if command.is_empty():
		return _refuse("当前无法安排更多实物动作。")
	var request: Dictionary = {"command": command, "op": "move", "id": id,
		"from": {"region": home, "container": from_container}, "to": destination}
	var terms: Dictionary = domain.verbs_for(id)[verb]
	var response: Dictionary = lifecycle.schedule(request, "player", int(terms.minutes) * 60000, true)
	if not bool(response.get("ok", false)):
		return _refuse("无法开始这次实物操作，请检查占地和当前状态。")
	_physical_action = command
	GameClock.cancel_wait()
	# Preserve the exact simulated position recorded by the timed action.
	adapter.hold_player_motion(true)
	_notice = "正在取起实物，完成前它仍在原处。" if verb == "take" else "正在把实物放到脚边，完成前它仍由本人保管。"
	adapter._refresh_panel()
	refresh()
	return {"ok": true, "line": _notice, "action": response.action}


func _physical_command(lifecycle: SimObjectLifecycle) -> String:
	# Existing receipts/actions persist through save/load and include cancelled
	# actions. No separate counter or per-frame scan is needed.
	var prefix: String = "player_physical:"
	var first: int = lifecycle.actions.size() + lifecycle.receipts.size() + 1
	for offset: int in range(1024):
		var command: String = prefix + str(first + offset)
		if not lifecycle.actions.has(command) and not lifecycle.receipts.has(command) and not lifecycle.ground.slots.has("ground:" + command):
			return command
	return ""


func _physical_status(authority: RegionalSimulation, id: String) -> Dictionary:
	var lifecycle: SimObjectLifecycle = authority.object_lifecycle
	var current: Dictionary = authority.describe_actor_action("player")
	if bool(current.ok) and current.domain == "object_lifecycle" and current.target == id:
		_physical_action = current.id
		var action: Dictionary = lifecycle.actions[current.id]
		var taking: bool = str(action.request.to.get("container", "")) == "actor:player"
		var remaining: int = int(current.remaining_ms)
		return {"busy": true, "line": "正在取起实物" if taking else "正在放下实物",
			"remaining": ceili(float(remaining) / 60000.0), "remaining_ms": remaining}
	# A loaded, still-active action is discovered above; its terminal result is
	# then read from the same original lifecycle record rather than copied.
	var completed: Variant = lifecycle.actions.get(_physical_action)
	if completed is Dictionary and completed.get("actor") == "player" and completed.get("request", {}).get("id") == id:
		var action_state: String = str(completed.get("status", ""))
		if action_state in ["completed", "failed", "cancelled"]:
			var taking: bool = str(completed.request.to.get("container", "")) == "actor:player"
			var line: String = ("已取起实物。" if taking else "已把实物放在脚边。") if action_state == "completed" else ("操作已中断，实物留在原处。" if action_state == "cancelled" else "操作未能完成，实物留在原处。")
			return {"busy": false, "line": line, "remaining": 0, "event": "physical:%s:%s" % [_physical_action, action_state]}
	return {"busy": false, "line": "", "remaining": 0, "event": ""}


func draw_targets() -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	var adapter: WorldContinuityRuntime = runtime()
	if not _can_observe(adapter) or not adapter.human_player_active():
		return choices
	var authority: RegionalSimulation = adapter.world_sim
	var domain: SimArtifacts = authority.artifacts
	if not domain.has_capability(selected_object, "remote_draw"):
		return choices
	var definition: Dictionary = domain.definitions.types[domain.objects[selected_object].definition]
	var candidates: Array[String] = _local_candidates(authority, int(definition.drawing.range_cells))
	candidates.sort()
	for id: String in candidates:
		if not domain.objects.has(id):
			continue
		var item: Dictionary = domain.objects[id]
		if id == selected_object or not definition.drawing.target_definitions.has(item.definition) or str(item.container).begins_with("actor:"):
			continue
		var visible: bool = _visible(id, authority)
		if adapter.world_sim != authority:
			choices.clear()
			return choices
		if not visible:
			continue
		var target: Vector2 = TileGrid.cell_to_world(domain.object_cell(id))
		var origin: Vector2 = authority.regions[domain.actor_home("player")].projected_actor_position("player")
		var level: int = SimConflictSpace.level(authority, origin)
		if origin.distance_to(target) > float(definition.drawing.range_cells) * TileGrid.TILE_SIZE or level != SimConflictSpace.level(authority, target) or not SimConflictSpace.clear_segment(authority, origin, target, level):
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
	if not _can_observe(runtime()):
		return
	selected_object = ""
	_selection_hit = Vector2.INF
	_notice = ""
	_settled_event = ""
	_physical_action = ""
	clear_committed_canvas()
	panel.hide()
	redraw_committed_canvas()


func refresh() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if not _can_observe(adapter):
		return
	if not selected_object.is_empty():
		var view: Dictionary = _perception(selected_object)
		if not bool(view.get("known", false)):
			reset_observation()
		else:
			var thermal: bool = adapter.world_sim.artifacts.has_capability(selected_object, "heat_storage")
			var lifecycle: SimObjectLifecycle = adapter.world_sim.object_lifecycle
			var managed: bool = lifecycle != null and lifecycle.manages(selected_object)
			var terms: Dictionary = adapter.world_sim.artifacts.verbs_for(selected_object)
			if managed:
				var physical_terms: Dictionary = {}
				for verb: String in ["take", "place"]:
					if terms.has(verb):
						physical_terms[verb] = terms[verb]
				terms = physical_terms
			panel.set_terms(terms, thermal if not managed else false)
			var status: Dictionary = _physical_status(adapter.world_sim, selected_object) if managed else adapter.world_sim.artifacts.status("player", selected_object)
			var active_job: Dictionary = adapter.world_sim.artifacts.active.get("player", {})
			if active_job.get("verb") == "draw":
				status["remaining_ms"] = maxi(0, int(active_job.due_ms) - int(adapter.world_sim.elapsed_ms))
			if not bool(status.busy) and not str(status.get("event", "")).is_empty() and _settled_event != str(status.event):
				_settled_event = str(status.event)
				_notice = str(status.line)
			panel.set_draw_targets(draw_targets())
			panel.set_cycle_available(_selection_hit != Vector2.INF)
			panel.update_view(view, status, _notice)
			var spirit: Node = adapter.get("spirit_adapter") as Node
			panel.set_source_entry(thermal and spirit != null and spirit.has_known_source())
	redraw_committed_canvas()


func _process(_delta: float) -> void:
	# Only presentation: carried items follow the holder's interpolated view.
	redraw_committed_canvas()


func _unhandled_input(event: InputEvent) -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if not _can_observe(adapter) or not adapter.human_player_active():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and panel.visible:
			panel.hide()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_I:
			if panel.visible:
				panel.hide()
			else:
				var authority: RegionalSimulation = adapter.world_sim
				var candidates: Array[String] = _local_candidates(authority)
				candidates.sort()
				var thermal: Array[String] = []
				var others: Array[String] = []
				for id: String in candidates:
					if authority.artifacts.has_capability(id, "heat_storage"):
						thermal.append(id)
					else:
						others.append(id)
				thermal.append_array(others)
				for id: String in thermal:
					# A remembered but unseen object must not become discoverable
					# merely because its actual position is in the spatial query.
					var visible: bool = _visible(id, authority)
					if adapter.world_sim != authority:
						break
					if visible and select_object(id):
						break
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cursor: Vector2 = get_canvas_transform().affine_inverse() * event.position
		var authority: RegionalSimulation = adapter.world_sim
		var hits: Array[String] = _visible_hits(cursor, authority)
		if not hits.is_empty():
			# Independently moving holders can overlap a placed icon after layout.
			# Keep only the clicked position, not a potentially stale hit list.
			var previous: int = hits.find(selected_object) if panel.visible else -1
			if select_object(hits[(previous + 1) % hits.size()], cursor):
				get_viewport().set_input_as_handled()


func _cycle_selection() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if not _can_observe(adapter) or not adapter.human_player_active() or not panel.visible or _selection_hit == Vector2.INF:
		return
	var authority: RegionalSimulation = adapter.world_sim
	var hits: Array[String] = _visible_hits(_selection_hit, authority)
	if hits.is_empty():
		return
	var previous: int = hits.find(selected_object)
	if hits.size() == 1 and previous == 0:
		return
	var id: String = hits[(previous + 1) % hits.size()]
	# Recheck the chosen instance: an old selection or an old perception is
	# never authority for what may be selected at the clicked position now.
	if _visible(id, authority):
		select_object(id, _selection_hit)


func _visible_hits(cursor: Vector2, authority: RegionalSimulation) -> Array[String]:
	if not _can_observe(runtime()):
		return []
	var points: Dictionary = _visible_display_points(authority)
	var hits: Array[String] = []
	for id: String in points:
		var footprint: Rect2i = _physical_ground_rect(id, authority)
		if footprint.size != Vector2i.ZERO:
			var cell: Vector2i = TileGrid.world_to_cell(cursor)
			var adapter: WorldContinuityRuntime = runtime()
			if adapter != null and footprint.has_point(cell) and _cell_visible(cell, adapter.controlled_cell(), _observation_radius(authority)) and _physical_tile_rect(cell).has_point(cursor):
				hits.append(id)
		elif cursor.distance_squared_to(points[id]) <= 22.0 * 22.0:
			hits.append(id)
	hits.sort_custom(func(left: String, right: String) -> bool:
		var left_distance: float = cursor.distance_squared_to(points[left])
		var right_distance: float = cursor.distance_squared_to(points[right])
		return left < right if left_distance == right_distance else left_distance < right_distance)
	return hits


func _visible(id: String, observed_world: RegionalSimulation = null) -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	if not _can_observe(adapter) or not adapter.human_player_active():
		return false
	# A reload may replace the accepted session during a debugger callback.
	# Keep the observed world alive for every weak-owned domain read in this view.
	var authority: RegionalSimulation = observed_world if observed_world != null else adapter.world_sim
	if authority == null:
		return false
	var domain: SimArtifacts = authority.artifacts
	var footprint: Rect2i = _physical_ground_rect(id, authority)
	if footprint.size != Vector2i.ZERO:
		return _visible_footprint_cell(footprint, authority) != Vector2i(-1, -1)
	return domain.can_see("player", id) and (adapter._home._fog == null or adapter._home._fog.is_cell_visible(domain.object_cell(id)))


func _perception(id: String) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if not _can_observe(adapter) or not adapter.human_player_active():
		return {"known": false}
	var authority: RegionalSimulation = adapter.world_sim
	var domain: SimArtifacts = authority.artifacts
	if not domain.objects.has(id):
		return {"known": false}
	var item: Dictionary = domain.objects[id]
	var held: bool = item.container == "actor:player" and item.region == domain.actor_home("player")
	var footprint: Rect2i = _physical_ground_rect(id, authority)
	if footprint.size != Vector2i.ZERO:
		var visible_cell: Vector2i = _visible_footprint_cell(footprint, authority)
		if adapter.world_sim != authority:
			return {"known": false}
		if visible_cell != Vector2i(-1, -1) and visible_cell != footprint.position:
			# The anchor may be beyond sight or hidden by fog. Expose only the
			# observed cell and ordinary appearance; do not authorize operations
			# using the unseen anchor or reveal its current location.
			var definition: Dictionary = domain.definitions.types[item.definition]
			return {"known": true, "label": str(definition.unknown_name), "line": str(definition.appearance),
				"method": false, "held": false, "near": false, "cell": [visible_cell.x, visible_cell.y], "region": item.region}
	if _visible(id, authority) or held:
		var view: Dictionary = domain.describe("player", id)
		view["region"] = item.region
		return view
	# Remember an actual personal/received record, never the hidden object's
	# current condition or location. Physical distance alone cannot reveal fog.
	return SimArtifacts.Understanding.remembered(domain, "player", id)


func _display_point(id: String, observed_world: RegionalSimulation = null) -> Vector2:
	var adapter: WorldContinuityRuntime = runtime()
	if not _can_observe(adapter):
		return Vector2.INF
	var authority: RegionalSimulation = observed_world if observed_world != null else adapter.world_sim
	var points: Dictionary = _visible_display_points(authority)
	return points[id] if points.has(id) else _base_display_point(id, authority)


func _observation_radius(authority: RegionalSimulation) -> int:
	if authority == null:
		return -1
	var home: String = authority.artifacts.actor_home("player")
	return int(authority.regions[home].config.observation_radius) if not home.is_empty() else -1


func _local_candidates(authority: RegionalSimulation, radius: int = -1) -> Array[String]:
	var ids: Array[String] = []
	var adapter: WorldContinuityRuntime = runtime()
	if not _can_observe(adapter) or authority == null or adapter.world_sim != authority or authority.object_lifecycle == null or not adapter.human_player_active():
		return ids
	if radius < 0:
		radius = _observation_radius(authority)
	if radius < 0:
		return ids
	# A failed or incomplete bounded query is never replaced with a global scan.
	# The returned IDs are authority-only and must still pass visibility checks.
	var found: Dictionary = authority.object_lifecycle.artifact_candidates(adapter.controlled_cell(), radius)
	if not bool(found.get("ok", false)):
		return ids
	for id: String in found.ids:
		ids.append(id)
	return ids


func _visible_display_points(authority: RegionalSimulation) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if not _can_observe(adapter) or authority == null:
		return {}
	var domain: SimArtifacts = authority.artifacts
	# Separate only currently visible objects sharing this exact visual anchor.
	# These offsets are presentation only: cell, custody and reach stay in the
	# original domain. Singleton positions and holder interpolation stay intact.
	# Only nearby candidates are inspected; these live queries are never used
	# during partial settlement. Drawing retains the last complete projection.
	var points: Dictionary = {}
	var groups: Dictionary = {}
	for id: String in _local_candidates(authority):
		var visible: bool = _visible(id, authority)
		if adapter.world_sim != authority:
			return {}
		if not visible:
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
				point = authority.regions[item.region].projected_actor_position(holder)
	var offset := Vector2(20, -24 - adapter._home._world.get_elevation(cell) * ReolWorld.ELEVATION_PX - altitude * ReolWorld.ALTITUDE_PX)
	if domain.has_capability(id, "thermal_exchange"):
		# A visual offset distinguishes objects at the same original place. It
		# does not change their cell, heat source, custody or interaction range.
		var definition: Dictionary = domain.definitions.types[item.definition]
		offset.x += -32.0 if definition.thermal.mode == "emit" else 32.0
	return point + offset


func _build_canvas() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if not _can_observe(adapter):
		return
	var authority: RegionalSimulation = adapter.world_sim
	var points: Dictionary = _visible_display_points(authority)
	if not _can_observe(adapter) or adapter.world_sim != authority:
		return
	var current: Dictionary = authority.artifacts.active.get("player", {})
	if current.has("draw") and points.has(str(current.draw.target)):
		var from: Vector2 = points[str(current.object)] if points.has(str(current.object)) else _base_display_point(str(current.object), authority)
		var to: Vector2 = points[str(current.draw.target)]
		var progress: float = clampf(float(authority.elapsed_ms - int(current.started_ms)) / float(int(current.due_ms) - int(current.started_ms)), 0.0, 1.0)
		capture_line(from, to, Color(0.63, 0.81, 0.77, 0.28), 1.0)
		capture_arc(to, 13.0 + 5.0 * (1.0 - progress), -PI * 0.5, TAU * progress - PI * 0.5, 24, Color("#c4ded5"), 2.0)
	for id: String in points:
		var point: Vector2 = points[id]
		if authority.artifacts.has_capability(id, "physical"):
			_draw_physical(id, point, authority)
			continue
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
			capture_circle(point, 11, Color("#302826"))
			capture_circle(point, 7, Color("#b5a86d"))
			capture_circle(point + Vector2(-2, -2), 3, Color("#f4e8ad"))
			continue
		var diamond := PackedVector2Array([point + Vector2(0, -9), point + Vector2(8, 0), point + Vector2(0, 9), point + Vector2(-8, 0)])
		capture_circle(point, 13, Color("#251c20"))
		capture_polygon(diamond, Color("#a6553b"))
		capture_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color("#f0c989"), 2)
		capture_line(point + Vector2(-3, -3), point + Vector2(3, 3), Color("#e8b479"), 1.5)


func _physical_ground_rect(id: String, authority: RegionalSimulation) -> Rect2i:
	var domain: SimArtifacts = authority.artifacts
	if not domain.has_capability(id, "physical") or authority.object_lifecycle == null:
		return Rect2i()
	var item: Dictionary = domain.objects[id]
	if not str(item.container).begins_with("ground:"):
		return Rect2i()
	var slot: Dictionary = authority.object_lifecycle.ground.locate(str(item.region), str(item.container))
	if not bool(slot.get("ok", false)) or not bool(slot.get("active", false)) or slot.reference.get("kind") != "artifact" or slot.reference.get("id") != id:
		return Rect2i()
	return Rect2i(slot.cell, slot.size)


func _visible_footprint_cell(footprint: Rect2i, authority: RegionalSimulation) -> Vector2i:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or adapter.world_sim != authority or not adapter.human_player_active():
		return Vector2i(-1, -1)
	var home: String = authority.artifacts.actor_home("player")
	if home.is_empty() or not authority.regions[home].actor_is_alive("player"):
		return Vector2i(-1, -1)
	var observer: Vector2i = adapter.controlled_cell()
	var radius: int = int(authority.regions[home].config.observation_radius)
	var first := Vector2i(maxi(footprint.position.x, observer.x - radius), maxi(footprint.position.y, observer.y - radius))
	var end := Vector2i(mini(footprint.end.x, observer.x + radius + 1), mini(footprint.end.y, observer.y + radius + 1))
	for y: int in range(first.y, end.y):
		for x: int in range(first.x, end.x):
			var cell := Vector2i(x, y)
			var visible: bool = _cell_visible(cell, observer, radius)
			# A visibility callback may synchronously replace the accepted world.
			# Keep the old authority alive but never publish its stale projection.
			if adapter.world_sim != authority:
				return Vector2i(-1, -1)
			if visible:
				return cell
	return Vector2i(-1, -1)


static func _physical_tile_rect(cell: Vector2i) -> Rect2:
	return Rect2(TileGrid.cell_to_world(cell) - Vector2.ONE * (TileGrid.HALF_TILE - 4.0), Vector2.ONE * (TileGrid.TILE_SIZE - 8.0))


func _cell_visible(cell: Vector2i, observer: Vector2i, radius: int) -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	return adapter != null and radius >= 0 and observer.distance_to(cell) <= float(radius) and (adapter._home._fog == null or adapter._home._fog.is_cell_visible(cell))


func _draw_physical(id: String, point: Vector2, authority: RegionalSimulation) -> void:
	var footprint: Rect2i = _physical_ground_rect(id, authority)
	if footprint.size == Vector2i.ZERO:
		# Carried or stored objects remain a small marker, not a ground footprint.
		capture_rect(Rect2(point - Vector2(9, 7), Vector2(18, 14)), Color("#777b7b"))
		capture_rect(Rect2(point - Vector2(9, 7), Vector2(18, 14)), Color("#c0c4bf"), false, 1.5)
		return
	var adapter: WorldContinuityRuntime = runtime()
	var observer: Vector2i = adapter.controlled_cell()
	var radius: int = _observation_radius(authority)
	# Large footprints are clipped to the observation window before iterating.
	var first := Vector2i(maxi(footprint.position.x, observer.x - radius), maxi(footprint.position.y, observer.y - radius))
	var end := Vector2i(mini(footprint.end.x, observer.x + radius + 1), mini(footprint.end.y, observer.y + radius + 1))
	for y: int in range(first.y, end.y):
		for x: int in range(first.x, end.x):
			var cell := Vector2i(x, y)
			if not _cell_visible(cell, observer, radius):
				continue
			var bounds: Rect2 = _physical_tile_rect(cell)
			capture_rect(bounds, Color("#777b7b"))
			capture_rect(bounds, Color("#c0c4bf"), false, 1.5)


func _draw_thermal_stone(point: Vector2, warm: bool) -> void:
	var rim: Color = Color("#f1bd8a") if warm else Color("#c3e8ed")
	var body: Color = Color("#a64f36") if warm else Color("#588fa5")
	var outline := PackedVector2Array([point + Vector2(-8, -6), point + Vector2(2, -10), point + Vector2(10, -3), point + Vector2(8, 7), point + Vector2(-4, 10), point + Vector2(-10, 3)])
	capture_circle(point, 13, Color("#251c20"))
	capture_polygon(outline, body)
	capture_polyline(PackedVector2Array([outline[0], outline[1], outline[2], outline[3], outline[4], outline[5], outline[0]]), rim, 2.0)
	capture_line(point + Vector2(-5, -3), point + Vector2(4, 4), rim, 1.5)


func _draw_wooden_sword(point: Vector2) -> void:
	var tip: Vector2 = point + Vector2(8, -15)
	var pommel: Vector2 = point + Vector2(-8, 14)
	capture_line(pommel, tip, Color("#251c20"), 8)
	capture_line(point + Vector2(-2, 4), tip, Color("#d6ad71"), 5)
	capture_line(pommel, point + Vector2(-2, 4), Color("#6b513b"), 5)
	capture_line(point + Vector2(-8, 0), point + Vector2(5, 7), Color("#251c20"), 6)
	capture_line(point + Vector2(-8, 0), point + Vector2(5, 7), Color("#b8804b"), 3)


func _draw_drawing_ring(point: Vector2) -> void:
	# A hollow copper ring, without the warm stone's glow or solid centre.
	capture_arc(point, 9.0, 0.0, TAU, 24, Color("#251c20"), 6.0)
	capture_arc(point, 9.0, 0.0, TAU, 24, Color("#a8926a"), 3.0)
	capture_arc(point, 8.0, PI * 1.1, PI * 1.8, 8, Color("#ded8b9"), 1.0)
	capture_line(point + Vector2(7, -6), point + Vector2(11, -5), Color("#e6e4d2"), 2.0)
	capture_line(point + Vector2(-8, 3), point + Vector2(-11, 5), Color("#c2c8bf"), 2.0)
