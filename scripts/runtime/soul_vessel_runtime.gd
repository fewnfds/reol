class_name SoulVesselRuntime
extends Node2D
## Selection, visible custody and player intents; no soul truth enters the panel.

var panel: SoulVesselPanel
var selected_vessel: String = ""
var _notice: String = ""
var _last_event: String = ""
var _owner: WeakRef


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
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	panel = SoulVesselPanel.new()
	screen.add_child(panel)
	panel.set_terms(adapter.world_sim.soul_vessels.definitions.verbs)
	panel.action_requested.connect(submit)
	queue_redraw()


func select_vessel(id: String) -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active() or not _visible(id):
		return false
	selected_vessel = id
	_notice = ""
	adapter.object_adapter.panel.hide()
	panel.show()
	refresh()
	return true


func submit(verb: String) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active() or selected_vessel.is_empty():
		return {"ok": false, "line": "眼下没有能这样接触旧戒的人身。"}
	var domain: SimSoulVessels = adapter.world_sim.soul_vessels
	var view: Dictionary = domain.describe("player", selected_vessel)
	var result: Dictionary = {"ok": false, "line": "先到近处看清旧戒。"}
	if verb == "cancel":
		adapter.stop_player_action()
		result = {"ok": true, "line": "已经中断接触；已付投入不退。"}
	elif bool(view.get("known", false)):
		if verb in ["approach", "to_garden"]:
			var cell: Vector2i = SimRouteTravel.cell(view.cell) if verb == "approach" else SimRouteTravel.cell(adapter.world_sim.regions.home.places.garden.cell)
			var accepted: bool = adapter.travel_to("home", cell)
			result = {"ok": accepted, "line": "正在走向你选择的地方。" if accepted else "先完成或中断当前事情。"}
		elif not adapter.player_journey.is_empty():
			result = {"ok": false, "line": "先走到近处，或停止行程再传意。"}
		else:
			adapter.prepare_player_command()
			var target: String = ""
			var recipient: String = ""
			var destination: String = ""
			if verb == "guide":
				var ids: Array = adapter.world_sim.artifacts.objects.keys()
				ids.sort()
				for id: String in ids:
					if adapter.world_sim.artifacts.can_see("player", id):
						target = id
						break
			elif verb == "give":
				recipient = adapter._home._selected_actor
				if recipient == "player" or not adapter._home._is_actor_visible(recipient):
					recipient = ""
			elif verb == "place":
				for region: String in adapter.world_sim.regions:
					for place: String in adapter.world_sim.regions[region].places:
						if domain._near_destination("player", region + ":" + place):
							destination = region + ":" + place
							break
					if not destination.is_empty():
						break
			result = domain.begin("player", verb, selected_vessel, target, recipient, destination)
			if bool(result.ok):
				adapter.hold_player_motion()
	_notice = str(result.line)
	adapter._refresh_panel()
	refresh()
	return result


func reset_observation() -> void:
	selected_vessel = ""
	_notice = ""
	_last_event = ""
	panel.hide()
	queue_redraw()


func refresh() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null:
		return
	if not selected_vessel.is_empty():
		var view: Dictionary = adapter.world_sim.soul_vessels.describe("player", selected_vessel)
		if not adapter.human_player_active() or not bool(view.get("known", false)):
			reset_observation()
		else:
			var status: Dictionary = adapter.world_sim.soul_vessels.status("player")
			if not bool(status.busy) and not str(status.get("event", "")).is_empty() and str(status.event) != _last_event:
				_last_event = str(status.event)
				_notice = str(status.line)
			panel.update_view(view, status, _notice)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and panel.visible:
			panel.hide()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_O:
			if panel.visible:
				panel.hide()
			else:
				var ids: Array = adapter.world_sim.soul_vessels.vessels.keys()
				ids.sort()
				for id: String in ids:
					if select_vessel(id):
						break
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for id: String in adapter.world_sim.soul_vessels.vessels:
			if _visible(id) and get_global_mouse_position().distance_to(_display_point(id)) <= 18.0 and select_vessel(id):
				get_viewport().set_input_as_handled()
				break


func _visible(id: String) -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	var domain: SimSoulVessels = adapter.world_sim.soul_vessels
	return domain.can_see("player", id) and (adapter._home._fog == null or adapter._home._fog.is_cell_visible(domain.vessel_cell(id)))


func _display_point(id: String) -> Vector2:
	var adapter: WorldContinuityRuntime = runtime()
	var domain: SimSoulVessels = adapter.world_sim.soul_vessels
	var cell: Vector2i = domain.vessel_cell(id)
	var point: Vector2 = TileGrid.cell_to_world(cell)
	var item: Dictionary = domain.vessels[id]
	if str(item.container).begins_with("actor:"):
		var body: Dictionary = adapter.world_sim.regions[item.region].actors[str(item.container).trim_prefix("actor:")]
		point = Vector2(float(body.position[0]), float(body.position[1]))
	return point + Vector2(-22, -25 - adapter._home._world.get_elevation(cell) * ReolWorld.ELEVATION_PX)


func _draw() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active():
		return
	for id: String in adapter.world_sim.soul_vessels.vessels:
		if _visible(id):
			var point: Vector2 = _display_point(id)
			draw_circle(point, 12, Color("#132b2e"))
			draw_arc(point, 7, 0.3, TAU - 0.3, 20, Color("#b5c8bd"), 3)
			draw_line(point + Vector2(5, -5), point + Vector2(8, -9), Color("#deb56d"), 2)
