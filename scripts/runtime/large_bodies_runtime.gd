class_name LargeBodiesRuntime
extends CommittedWorldCanvas
## Projection and pointing only; no body state or separate update clock.

const UI = preload("res://scripts/ui/reol_ui_theme.gd")
var _owner: WeakRef


static func assemble(adapter: WorldContinuityRuntime) -> bool:
	var scenario: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/large_bodies.json"))
	if not scenario is Dictionary or scenario.get("version") != 1 or not scenario.get("bodies") is Dictionary:
		return false
	var domain: SimLargeBodies = adapter.world_sim.large_bodies
	domain.set_geometry(adapter.world_sim.map_data.terrain_is_walkable, adapter.world_sim.map_data.get_elevation, adapter._incoming_occupancy, true)
	for id: String in scenario.bodies:
		var row: Dictionary = scenario.bodies[id]
		var preferred: Vector2i = adapter.centers[row.region] + SimRouteTravel.cell(row.offset)
		var found: bool = false
		for radius: int in range(int(row.search_radius) + 1):
			for dy: int in range(-radius, radius + 1):
				for dx: int in range(-radius, radius + 1):
					if maxi(absi(dx), absi(dy)) != radius:
						continue
					var a: Vector2i = preferred + Vector2i(dx, dy)
					if not SimBodyGeometry.can_stand(a, domain.size(), domain._walkable, domain._elevation):
						continue
					for direction: Vector2i in SimBodyGeometry.DIRECTIONS:
						var b: Vector2i = a + direction * int(row.roam_distance)
						if domain.add_body(id, str(row.label), str(row.region), a, b):
							found = true
							break
					if found:
						break
				if found:
					break
			if found:
				break
		if not found:
			return false
	return true


func runtime() -> WorldContinuityRuntime:
	return _owner.get_ref() as WorldContinuityRuntime if _owner != null else null


func setup(adapter: WorldContinuityRuntime) -> void:
	_owner = weakref(adapter)
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 10
	GameClock.time_advanced.connect(_on_time_advanced)
	adapter.avatar_changed.connect(reset_observation)


func reset_observation() -> void:
	clear_committed_canvas()


func _on_time_advanced(_from: int, _to: int) -> void:
	if can_refresh_canvas():
		redraw_committed_canvas()


func is_visible_body(id: String) -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or adapter.soul_player_active() or not adapter.world_sim.large_bodies.bodies.has(id):
		return false
	var domain: SimLargeBodies = adapter.world_sim.large_bodies
	if adapter.human_player_active() and not domain.visible_to("player", id):
		return false
	if adapter.bird_player_active():
		var bird: Dictionary = adapter.world_sim.avian_life.birds[adapter.bird_avatar_id()]
		if SimBodyGeometry.contact_distance(SimAvianLife.point(bird), domain.point(id), domain.size()) > float(adapter.world_sim.avian_life.rules().observation_cells * TileGrid.TILE_SIZE):
			return false
	for cell: Vector2i in SimBodyGeometry.cells(domain.body_cell(id), domain.size()):
		if adapter._home._fog == null or adapter._home._fog.is_cell_visible(cell):
			return true
	return false


func display_point(id: String) -> Vector2:
	var domain: SimLargeBodies = runtime().world_sim.large_bodies
	return domain.point(id) - Vector2(0, runtime()._home._world.get_elevation(domain.body_cell(id)) * ReolWorld.ELEVATION_PX)


func select_body(id: String) -> bool:
	if not runtime().human_player_active() or not is_visible_body(id):
		return false
	var interaction: InteractionRequestsRuntime = runtime().interaction_adapter
	interaction.show_panel()
	for index: int in interaction.receiver_choice.item_count:
		if interaction.receiver_choice.get_item_metadata(index) == SimLargeBodies.subject_id(id):
			interaction.receiver_choice.select(index)
	for index: int in interaction.verb_choice.item_count:
		if interaction.verb_choice.get_item_metadata(index) == "offer_food":
			interaction.verb_choice.select(index)
	interaction.rebuild_choices()
	for index: int in interaction.medium_choice.item_count:
		if interaction.medium_choice.get_item_metadata(index) == "gesture":
			interaction.medium_choice.select(index)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not runtime().human_player_active() or not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var point: Vector2 = get_canvas_transform().affine_inverse() * event.position
	if select_at(point):
		get_viewport().set_input_as_handled()


func select_at(point: Vector2) -> bool:
	for id: String in runtime().world_sim.large_bodies.bodies:
		if is_visible_body(id) and point.distance_to(display_point(id)) < float(TileGrid.TILE_SIZE) * 1.35 and select_body(id):
			return true
	return false


func _build_canvas() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null:
		return
	var domain: SimLargeBodies = adapter.world_sim.large_bodies
	var tile: float = float(TileGrid.TILE_SIZE)
	for id: String in domain.bodies:
		if not is_visible_body(id):
			continue
		var point: Vector2 = display_point(id)
		var direction: Vector2 = Vector2(SimBodyGeometry.DIRECTIONS[int(domain.bodies[id].facing)])
		capture_transform(point + Vector2(0, tile * 0.45), 0, Vector2(1.2, 0.65))
		capture_circle(Vector2.ZERO, tile, Color(0.06, 0.12, 0.11, 0.45))
		capture_transform(point, direction.angle(), Vector2.ONE)
		for offset: Vector2 in [Vector2(-0.6, -0.65), Vector2(0.5, -0.65), Vector2(-0.6, 0.65), Vector2(0.5, 0.65)]:
			capture_circle(offset * tile, tile * 0.25, Color("#4d564e"))
		capture_transform(point, direction.angle(), Vector2(1.2, 0.9))
		capture_circle(Vector2.ZERO, tile * 0.9, Color("#7a806c"))
		capture_circle(Vector2(-tile * 0.15, -tile * 0.1), tile * 0.57, Color("#98977c"))
		capture_transform(point, direction.angle(), Vector2.ONE)
		capture_polygon(PackedVector2Array([Vector2(-0.55, -0.25) * tile, Vector2(-0.35, -0.7) * tile, Vector2(0.25, -0.65) * tile, Vector2(0.45, -0.15) * tile, Vector2(0.15, 0.5) * tile, Vector2(-0.5, 0.45) * tile]), Color("#b0ac8e"))
		capture_circle(Vector2(tile * 0.95, 0), tile * 0.38, Color("#666d5b"))
		capture_line(Vector2(tile * 0.9, -tile * 0.27), Vector2(tile * 1.15, -tile * 0.57), Color("#d9cdab"), 5)
		capture_line(Vector2(tile * 0.9, tile * 0.27), Vector2(tile * 1.15, tile * 0.57), Color("#d9cdab"), 5)
		capture_circle(Vector2(tile * 1.07, -tile * 0.16), tile * 0.045, Color("#e2c878"))
		capture_circle(Vector2(tile * 1.07, tile * 0.16), tile * 0.045, Color("#e2c878"))
		capture_transform(Vector2.ZERO)
		var caption: String = str(domain.bodies[id].label) + (" · 迈步" if not domain.bodies[id].step.is_empty() else " · 伏地休憩")
		capture_text(ThemeDB.fallback_font, point + Vector2(-tile * 1.2, -tile * 1.35), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.PAPER)
