class_name WorldUnitPicker
extends RefCounted
## One world-click query. Spatial candidates come from original indexes; small
## rendered icons use their existing adapters' hit tests. No action is executed.


static func pick(main: Node2D, point: Vector2) -> Dictionary:
	var runtime: WorldContinuityRuntime = main._continuity
	if not runtime._presentation_ready() or GameClock.has_pending_advance():
		return {"ok": false, "reason": "pending_boundary"}
	var world: RegionalSimulation = runtime.world_sim
	var cell: Vector2i = runtime.natural_adapter.cell_at_point(point)
	if not world.map_data.in_bounds(cell):
		return {"ok": true, "cell": cell, "references": []}
	# Query the complete screen-sized hit margin, including raised terrain and
	# body glyphs above their anchors. A fixed five-cell box missed zoomed-out
	# actors even when the cursor was inside the rendered selection radius.
	var margin: int = ceili((main.SELECT_RADIUS / main.camera.zoom.x + ReolWorld.ELEVATION_LEVELS * ReolWorld.ELEVATION_PX + ReolWorld.ALTITUDE_PX * 2) / TileGrid.TILE_SIZE)
	var area := Rect2i(cell - Vector2i.ONE * margin, Vector2i.ONE * (margin * 2 + 1)).intersection(Rect2i(0, 0, WorldMapData.WORLD_SIZE, WorldMapData.WORLD_SIZE))
	var query: Dictionary = world.space.presentation_candidates(area)
	if not query.ok:
		return query
	var hits: Array[Dictionary] = []
	for reference: Dictionary in query.references:
		if reference.kind == "artifact":
			continue # Placed/carried icons share their original rendered hit test.
		var row: Dictionary = world.describe_object(reference)
		if not row.get("ok", false):
			continue
		var center: Vector2 = row.spatial.anchor_px
		var radius: float = 0.0
		var priority: int = 0
		match str(reference.kind):
			"actor":
				var view: Node2D = main.player if reference.id == "player" else runtime.actor_view(str(reference.id))
				if not is_instance_valid(view) or not view.visible:
					continue
				center = view.selection_center()
				radius = main.SELECT_RADIUS / main.camera.zoom.x
			"avian":
				if not runtime.avian_adapter._visible(str(reference.id)):
					continue
				center = runtime.avian_adapter._bird_point(str(reference.id))
				radius = 18.0 / main.camera.zoom.x
			"large_body":
				if not runtime.large_body_adapter.is_visible_body(str(reference.id)):
					continue
				center = runtime.large_body_adapter.display_point(str(reference.id))
				radius = TileGrid.TILE_SIZE * 1.35
			_:
				if not row.spatial.cells.has(cell) or not main.fog.is_cell_visible(cell):
					continue
				priority = 2 if row.spatial.layer == "roof" else 3 if row.spatial.layer == "planned" else 1
		if radius > 0.0 and center.distance_to(point) > radius:
			continue
		hits.append({"reference": reference, "priority": priority, "distance": center.distance_squared_to(point)})
	for id: String in runtime.object_adapter._visible_hits(point, world):
		hits.append({"reference": {"kind": "artifact", "id": id}, "priority": 0,
			"distance": runtime.object_adapter._display_point(id, world).distance_squared_to(point)})
	if runtime.human_player_active():
		for id: String in world.soul_vessels.vessels:
			var center: Vector2 = runtime.soul_adapter._display_point(id)
			if runtime.soul_adapter._visible(id) and center.distance_to(point) <= 18.0 / main.camera.zoom.x:
				hits.append({"reference": {"kind": "vessel", "id": id}, "priority": 0, "distance": center.distance_squared_to(point)})
		for id: String in world.spirit_sources.definitions.sources:
			var center: Vector2 = runtime.spirit_adapter._display_point(id)
			if runtime.spirit_adapter.source_visible(id) and center.distance_to(point) <= 18.0 / main.camera.zoom.x:
				hits.append({"reference": {"kind": "spirit_source", "id": id}, "priority": 0, "distance": center.distance_squared_to(point)})
	# Fixed site markers are visible records, not spawned entities or terrain.
	if main.fog.is_cell_visible(cell):
		for region: String in world.regions:
			for id: String in world.regions[region].places:
				if SimRouteTravel.cell(world.regions[region].places[id].cell) == cell:
					hits.append({"reference": {"kind": "place", "region": region, "id": id}, "priority": 4, "distance": 0.0})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.priority != b.priority: return a.priority < b.priority
		if a.distance != b.distance: return a.distance < b.distance
		return JSON.stringify(a.reference, "", true) < JSON.stringify(b.reference, "", true))
	var references: Array[Dictionary] = []
	for hit: Dictionary in hits:
		if not references.has(hit.reference):
			references.append(hit.reference)
	return {"ok": true, "cell": cell, "references": references}
