class_name DevelopmentInspectionRuntime
extends Node2D
## Development-only reads at complete boundaries. No simulation, knowledge or
## save owner. Detached output remains usable while the coordinator is busy.
const SAMPLE_USEC: int = 250000
const Picker = preload("res://scripts/runtime/world_unit_picker.gd")
var _main: WeakRef
var _next_sample: int = 0
var _selection_rects: Array[Rect2] = []
var _selection_refs: Array[Dictionary] = []
var _hover_cell := Vector2i(-1, -1)

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
	for panel: Control in _unit_operation_panels():
		panel.visibility_changed.connect(_operation_panel_visibility.bind(panel))
	var construction_panel: Control = runtime.construction_adapter.panel
	construction_panel.visibility_changed.connect(_operation_panel_visibility.bind(construction_panel))
	_refresh()


func _unit_operation_panels() -> Array[Control]:
	return [runtime.object_adapter.panel, runtime.natural_adapter.panel, runtime.avian_adapter.panel,
		runtime.soul_adapter.panel, runtime.spirit_adapter.panel, runtime.interaction_adapter.panel,
		runtime.heat_method_adapter.panel]


func _close_unit_operations() -> void:
	for panel: Control in _unit_operation_panels():
		panel.hide()


func _operation_panel_visibility(panel: Control) -> void:
	if panel.visible:
		main.hud.inspector.hide()


func _published(_from: int, _to: int) -> void:
	if Time.get_ticks_usec() >= _next_sample:
		_refresh()


func _process(_delta: float) -> void:
	# Pointer motion is presentation-only. A changed hovered tile reads one cell;
	# unchanged terrain/unit data refreshes at 4Hz, only at complete boundaries.
	main.hud.set_pointer_position(get_global_mouse_position())
	if main.hud.pointer_over_interface():
		_hover_cell = Vector2i(-1, -1)
		main.hud.set_terrain_snapshot({})
	elif runtime._presentation_ready() and not GameClock.has_pending_advance():
		var cell: Vector2i = runtime.natural_adapter.cell_at_point(get_global_mouse_position())
		if cell != _hover_cell:
			_hover_cell = cell
			_refresh_hover()
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
	if not _selection_refs.is_empty() and main.hud.inspector.visible:
		_refresh_selection()
	_refresh_hover()


func _refresh_hover() -> void:
	var world: RegionalSimulation = runtime.world_sim
	if not world.map_data.in_bounds(_hover_cell) or main.hud.pointer_over_interface():
		main.hud.set_terrain_snapshot({})
		return
	main.hud.set_terrain_snapshot({"at_ms": world.elapsed_ms, "cell": _hover_cell,
		"terrain": world.map_data.get_terrain(_hover_cell), "elevation": world.map_data.get_elevation(_hover_cell),
		"natural": world.map_data.natural_cell(_hover_cell).duplicate(true),
		"environment": world.environment_fields.context_at(_hover_cell)})


func _inspect_reference(reference: Dictionary) -> Dictionary:
	var world: RegionalSimulation = runtime.world_sim
	var cell: Vector2i
	var values: Dictionary
	var label: String
	match str(reference.kind):
		"place":
			var sim: VillageSimulation = world.regions.get(reference.region)
			if sim == null or not sim.places.has(reference.id): return {}
			cell = SimRouteTravel.cell(sim.places[reference.id].cell)
			values = {"place": sim.places[reference.id].duplicate(true), "stock": sim.inventory.containers.get(reference.id, {}).duplicate(true)}
			label = "场所 / " + str(reference.region) + ":" + str(reference.id)
		"vessel":
			if not world.soul_vessels.vessels.has(reference.id): return {}
			cell = world.soul_vessels.vessel_cell(str(reference.id))
			values = world.soul_vessels.vessels[reference.id].duplicate(true)
			label = "vessel / " + str(reference.id)
		"spirit_source":
			if not world.spirit_sources.sources.has(reference.id): return {}
			cell = runtime.spirit_adapter.source_cell(str(reference.id))
			values = world.spirit_sources.sources[reference.id].duplicate(true)
			label = "spirit_source / " + str(reference.id)
		_:
			var row: Dictionary = world.describe_object(reference)
			if not row.get("ok", false) or row.spatial.cells.is_empty(): return {}
			cell = TileGrid.world_to_cell(row.spatial.anchor_px)
			values = _values(reference, row)
			label = _label(reference, row)
	return {"reference": reference.duplicate(true), "cell": cell, "label": label, "values": values}


func _refresh_selection(preferred: Dictionary = {}) -> void:
	var rows: Array = []
	for reference: Dictionary in _selection_refs:
		var row: Dictionary = _inspect_reference(reference)
		if not row.is_empty(): rows.append(row)
	if rows.is_empty():
		clear_selection()
		return
	main.hud.inspector.present({"at_ms": runtime.world_sim.elapsed_ms,
		"objects": rows, "selected_reference": preferred})
	_update_selection_geometry(main.hud.inspector.selected_reference())


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
	var picked: Dictionary = Picker.pick(main, point)
	if not picked.ok:
		return false
	_close_unit_operations()
	if picked.references.is_empty():
		clear_selection()
		if runtime.human_player_active(): main._select_player()
		return true
	var previous: Dictionary = main.hud.inspector.selected_reference()
	var index: int = 0
	if _selection_refs == picked.references and main.hud.inspector.visible:
		index = (_selection_refs.find(previous) + 1) % _selection_refs.size()
	_selection_refs.assign(picked.references)
	main.hud.inspector.show()
	_refresh_selection(_selection_refs[index])
	_select_object(main.hud.inspector.selected_reference())
	return true


func _select_object(reference: Dictionary) -> void:
	if reference.is_empty() or not runtime._presentation_ready() or GameClock.has_pending_advance():
		return
	if runtime.human_player_active():
		if reference.kind == "actor":
			if reference.id == "player":
				main._select_player()
			else:
				var pawn: Pawn = runtime.actor_view(str(reference.id))
				if is_instance_valid(pawn) and pawn.visible: main._select_pawn(pawn)
		elif reference.kind == "artifact":
			runtime.object_adapter.select_object(str(reference.id), Vector2.INF, false)
	_update_selection_geometry(reference)


func _update_selection_geometry(reference: Dictionary) -> void:
	_selection_rects.clear()
	# Moving bodies already have native selection/presentation; never draw a
	# second actor marker from a sampled grid cell.
	if not reference.is_empty() and reference.kind not in ["actor", "avian", "large_body", "vessel", "spirit_source", "place"]:
		var row: Dictionary = runtime.world_sim.describe_object(reference)
		if row.get("ok", false):
			for cell: Vector2i in row.spatial.cells:
				var display: Vector2 = TileGrid.cell_to_world(cell) - Vector2(0, runtime.world_sim.map_data.get_elevation(cell) * ReolWorld.ELEVATION_PX)
				_selection_rects.append(Rect2(display - Vector2.ONE * TileGrid.TILE_SIZE * 0.5, Vector2.ONE * TileGrid.TILE_SIZE))
	queue_redraw()


func _operate(reference: Dictionary, cell: Vector2i) -> void:
	if not runtime._presentation_ready() or GameClock.has_pending_advance():
		main.hud.inspector.show_notice("pending_boundary：等待完整结算后再操作。")
		return
	if not runtime.human_player_active():
		main.hud.inspector.show_notice("avatar_unavailable：此处是人身操作；当前身份沿原键位行动。")
		return
	var selected: Dictionary = _inspect_reference(reference)
	if selected.is_empty():
		main.hud.inspector.show_notice("object_unavailable：单位已移除，请重新选择。")
		return
	cell = selected.cell
	if not main.fog.is_cell_visible(cell):
		main.hud.inspector.show_notice("visible=0：实际操作须先走近看见。")
		return
	_close_unit_operations()
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
		"plant":
			if not runtime.natural_adapter.observe(cell, str(reference.id)):
				main.hud.inspector.show_notice("observation_unavailable：当前身体无法观察此格。")
				return
		"actor", "workplace": runtime.interaction_adapter.show_panel()
		"avian":
			if not runtime.avian_adapter.select_bird(str(reference.id)): return
		"large_body":
			if not runtime.large_body_adapter.select_body(str(reference.id)): return
		"vessel":
			if not runtime.soul_adapter.select_vessel(str(reference.id)): return
		"spirit_source":
			if not runtime.spirit_adapter.select_source(str(reference.id)): return
	main.hud.inspector.hide()


func _reset() -> void:
	clear_selection()
	_hover_cell = Vector2i(-1, -1)
	main.hud.set_terrain_snapshot({})
	_next_sample = 0
	_refresh()


func clear_selection() -> void:
	_selection_refs.clear()
	_selection_rects.clear()
	main.hud.inspector.clear()
	queue_redraw()


func _draw() -> void:
	if main != null and main.hud.inspector.visible:
		for rect: Rect2 in _selection_rects:
			draw_rect(rect, Color(0.3, 0.9, 1.0, 0.9), false, 2.0)
