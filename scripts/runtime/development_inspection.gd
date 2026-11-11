class_name DevelopmentInspectionRuntime
extends Node2D
## Development-only reads at complete boundaries. No simulation, knowledge or
## save owner. Detached output remains usable while the coordinator is busy.
const SAMPLE_USEC: int = 250000
var _main: WeakRef
var selected_cell := Vector2i(-1, -1)
var _next_sample: int = 0
var _selection_rect := Rect2()
var _has_selection: bool = false

var main: Node2D:
	get: return _main.get_ref() as Node2D if _main != null else null
var runtime: WorldContinuityRuntime:
	get: return main._continuity if main != null else null


func setup(scene: Node2D) -> void:
	_main = weakref(scene)
	z_index = 30
	main.hud.inspector.operation_requested.connect(_operate)
	main.hud.inspector.object_selected.connect(_select_object)
	main.hud.inspector.visibility_changed.connect(queue_redraw)
	GameClock.time_advanced.connect(_published)
	runtime.avatar_changed.connect(_reset)
	_refresh()


func _published(_from: int, _to: int) -> void:
	if Time.get_ticks_usec() >= _next_sample:
		_refresh()


func _process(_delta: float) -> void:
	# Mouse coordinates are scene/host data. Field and object reads stay bounded
	# to 4Hz, including while paused; no per-frame scan of world bodies.
	main.hud.set_pointer_position(get_global_mouse_position())
	if Time.get_ticks_usec() >= _next_sample:
		_refresh()


func _refresh() -> void:
	if runtime == null or not runtime._presentation_ready() or GameClock.has_pending_advance():
		return
	_next_sample = Time.get_ticks_usec() + SAMPLE_USEC
	var world: RegionalSimulation = runtime.world_sim
	var cell: Vector2i = runtime.controlled_cell()
	var context: Dictionary = world.environment_fields.context_at(cell)
	var position_value: Vector2 = main.player.global_position
	if runtime.bird_player_active():
		position_value = SimAvianLife.point(world.avian_life.birds[runtime.bird_avatar_id()])
	elif runtime.soul_player_active():
		position_value = world.soul_vessels.agency.point(runtime.soul_avatar_id())
	var climate_region: String = SimClimateRules.region_at(world.environment.definitions, cell)
	var exposure: Dictionary = world.environment.local_conditions("player") if runtime.human_player_active() else {}
	exposure.erase("feeling")
	main.hud.set_development_snapshot({"at_ms": world.elapsed_ms, "subject": runtime.avatar_subject,
		"cell": cell, "position": position_value, "environment": context,
		"weather": world.weather.current_kind(climate_region), "exposure": exposure})
	if _has_selection and main.hud.inspector.visible:
		main.hud.inspector.present(inspect_cell(selected_cell))


func inspect_cell(cell: Vector2i) -> Dictionary:
	var world: RegionalSimulation = runtime.world_sim
	var natural: Dictionary = world.map_data.natural_cell(cell).duplicate(true)
	var rows: Array = [{"label": "地块 / terrain (%d,%d)" % [cell.x, cell.y], "reference": {"kind": "terrain"},
		"values": {"cell": cell, "terrain": world.map_data.get_terrain(cell), "elevation": world.map_data.get_elevation(cell),
			"natural": natural, "environment": world.environment_fields.context_at(cell),
			"perception_cost_cells": world.construction.perception_cost(cell)}}]
	var query: Dictionary = world.space.query(Rect2i(cell, Vector2i.ONE))
	if bool(query.ok):
		for reference: Dictionary in query.references:
			var row: Dictionary = world.describe_object(reference)
			if bool(row.ok):
				rows.append({"reference": reference.duplicate(true), "label": _label(reference, row), "values": _values(reference, row)})
	# Place markers / finite resources are records rather than spawned instances.
	for region: String in world.regions:
		var sim: VillageSimulation = world.regions[region]
		for id: String in sim.places:
			if SimRouteTravel.cell(sim.places[id].cell) == cell:
				rows.append({"reference": {"kind": "place", "region": region, "id": id}, "label": "场所 / " + region + ":" + id,
					"values": {"place": sim.places[id].duplicate(true), "stock": sim.inventory.containers.get(id, {}).duplicate(true)}})
	return {"at_ms": world.elapsed_ms, "cell": cell, "objects": rows, "query_status": "complete" if query.ok else str(query.reason)}


func _label(reference: Dictionary, row: Dictionary) -> String:
	var kind: String = reference.kind
	var id: String = str(reference.get("id", reference.get("part", "")))
	var name_value: String = str(row.attributes.get("definition", row.attributes.get("component", row.attributes.get("definition_id", ""))))
	var world: RegionalSimulation = runtime.world_sim
	if kind == "construction":
		name_value = str(world.construction.definitions.types[world.construction.projects[id].type].label)
	elif kind == "plant":
		name_value = str(world.plants.definitions.types[world.plants.bodies[id].definition].label)
	elif kind == "workplace":
		name_value = str({"walls": "值事房墙", "door": "值事房门口", "desk": "值事桌", "archive": "档案柜", "roof": "值事房屋面"}.get(reference.part, reference.part))
	elif kind == "stock":
		name_value = "%s ×%s" % [str(row.attributes.item_type), str(row.attributes.quantity)]
		id = str(reference.container)
	return "%s / %s / %s" % [kind, name_value, id]


func _values(reference: Dictionary, description: Dictionary) -> Dictionary:
	var value: Dictionary = {"reference": reference.duplicate(true), "attributes": description.attributes.duplicate(true)}
	var world: RegionalSimulation = runtime.world_sim
	var id: String = str(reference.get("id", ""))
	match str(reference.kind):
		"construction":
			value["instance"] = world.construction.projects[id].duplicate(true)
			value.instance.erase("line")
			value["definition"] = world.construction.definitions.types[value.instance.type].duplicate(true)
			value["contents"] = world.regions.home.inventory.containers.get(id + ":contents", {}).duplicate(true)
			value["cultivation"] = world.construction.cultivation.get(id, {}).duplicate(true)
		"actor":
			var sim: VillageSimulation = world.regions[description.record_region]
			value["body"] = sim.actor_state(id).duplicate(true)
			value["projected_needs"] = sim.projected_actor_needs(id).duplicate(true)
			value["inventory"] = sim.inventory.containers.get("actor:" + id, {}).duplicate(true)
			value["wounds"] = []
			for wound: Dictionary in world.health.wounds.values():
				if wound.actor == id:
					value.wounds.append(wound.duplicate(true))
		"plant": value["body"] = world.plants.bodies[id].duplicate(true)
		"artifact": value["instance"] = world.artifacts.objects[id].duplicate(true)
		"avian": value["body"] = world.avian_life.birds[id].duplicate(true)
		"large_body": value["body"] = world.large_bodies.bodies[id].duplicate(true)
	for key: String in description:
		if not value.has(key):
			value[key] = description[key]
	return value


func select_point(point: Vector2) -> bool:
	if not runtime._presentation_ready() or GameClock.has_pending_advance():
		return false
	var cell: Vector2i = runtime.natural_adapter.cell_at_point(point)
	if not runtime.world_sim.map_data.in_bounds(cell):
		return false
	selected_cell = cell
	_has_selection = true
	var display: Vector2 = TileGrid.cell_to_world(cell) - Vector2(0, runtime.world_sim.map_data.get_elevation(cell) * ReolWorld.ELEVATION_PX)
	_selection_rect = Rect2(display - Vector2.ONE * TileGrid.TILE_SIZE * 0.5, Vector2.ONE * TileGrid.TILE_SIZE)
	if runtime.human_player_active():
		main._select_at(point)
	main.hud.inspector.show()
	main.hud.inspector.present(inspect_cell(cell))
	queue_redraw()
	return true


func _select_object(reference: Dictionary) -> void:
	if reference.kind != "actor" or not runtime._presentation_ready():
		return
	if reference.id == "player":
		main._select_player()
	else:
		var pawn: Pawn = runtime.actor_view(str(reference.id))
		if is_instance_valid(pawn) and pawn.visible:
			main._select_pawn(pawn)


func _operate(reference: Dictionary, cell: Vector2i) -> void:
	if not runtime._presentation_ready() or GameClock.has_pending_advance():
		main.hud.inspector.show_notice("pending_boundary：等待完整结算后再操作。")
		return
	if not runtime.human_player_active():
		main.hud.inspector.show_notice("avatar_unavailable：此处是人身操作；当前身份沿原键位行动。")
		return
	if not main.fog.is_cell_visible(cell):
		main.hud.inspector.show_notice("visible=0：后台检查可读此格，实际操作须先走近看见。")
		return
	match str(reference.kind):
		"construction":
			runtime.construction_adapter.show_panel()
			var adapter: ConstructionRuntime = runtime.construction_adapter
			var type: String = str(runtime.world_sim.construction.projects[reference.id].type)
			for index: int in adapter.type_choice.item_count:
				if adapter.type_choice.get_item_metadata(index) == type:
					adapter.type_choice.select(index)
					break
			adapter.select_cell(cell)
			adapter.refresh_choices(str(reference.id))
			adapter.refresh()
		"artifact":
			if not runtime.object_adapter.select_object(str(reference.id)):
				main.hud.inspector.show_notice("object_unavailable：原器物面板拒绝此次操作。")
				return
		"terrain", "plant":
			if not runtime.natural_adapter.observe(cell):
				main.hud.inspector.show_notice("observation_unavailable：当前身体无法观察此格。")
				return
		"actor", "workplace": runtime.interaction_adapter.show_panel()
		"avian":
			runtime.avian_adapter.panel.show()
			runtime.avian_adapter.refresh()
	main.hud.inspector.hide()


func _reset() -> void:
	_has_selection = false
	main.hud.inspector.hide()
	_next_sample = 0
	queue_redraw()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if main._terrain_editor != null and main._terrain_editor.overlay.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var point: Vector2 = get_canvas_transform().affine_inverse() * event.position
		# Keep the construction tool's existing click-to-place selection route.
		if runtime.construction_adapter.panel.visible:
			return
		if select_point(point):
			get_viewport().set_input_as_handled()


func _draw() -> void:
	if _has_selection and main != null and main.hud.inspector.visible:
		draw_rect(_selection_rect, Color(0.3, 0.9, 1.0, 0.9), false, 2.0)
