class_name PawnViewLayout
extends RefCounted
## One disposable sample of accepted motion and observed cells. Presentation
## never moves bodies aside when they share a cell.

var cells: Dictionary[String, Vector2i] = {}
var points: Dictionary[String, Vector2] = {}
var native_legs: Dictionary[String, int] = {}

var _fog: FogOfWar
var _observed: Dictionary[Vector2i, bool] = {}
var _sample_cells: Array[Vector2i] = []
var _visibility_frozen: bool = false


func _init(fog: FogOfWar = null) -> void:
	_fog = fog


func include_bodies(actors: Dictionary, at_ms: int = -1, native_routes: Dictionary = {}) -> void:
	for id: String in actors:
		var body: Dictionary = actors[id]
		var raw_cell: Variant = body.get("cell", [])
		if not raw_cell is Array or raw_cell.size() != 2:
			continue
		var cell: Vector2i
		var point: Vector2
		var leg: int = -1
		if at_ms >= 0:
			var route: Dictionary = body.active
			if route.get("phase") == "travel":
				var completion: Dictionary = native_routes.get(id, {})
				if bool(completion.get("coarse", false)) and is_same(completion.route, route):
					var timeline: SimRouteTravel.Timeline = completion.timeline
					leg = timeline.leg_at(at_ms)
					point = timeline.point_on_leg(at_ms, leg)
				else:
					point = SimRouteTravel.projected_point(route, body, at_ms)
			else:
				point = SimRouteTravel.point(body)
			cell = TileGrid.world_to_cell(point)
		else:
			cell = SimRouteTravel.cell(raw_cell)
		cells[id] = cell
		if _fog != null:
			if not _observed.has(cell):
				_observed[cell] = _fog.is_cell_visible(cell)
			if not _observed[cell]:
				continue
		if at_ms >= 0:
			points[id] = point
			if leg >= 0:
				native_legs[id] = leg


func include_publication(frame: SimBodyPublication) -> void:
	# Geometry uses detached values prepared with the body
	# publication. Visibility stays on the host and cannot teach the world.
	cells = frame.cells
	points = frame.points
	_sample_cells = frame.sample_cells


func freeze_visibility() -> void:
	if _visibility_frozen:
		return
	for cell: Vector2i in _sample_cells:
		_observed[cell] = _fog == null or _fog.is_cell_visible(cell)
	_visibility_frozen = true
	_fog = null # A deferred presentation job retains no live visibility Node.


func sees(cell: Vector2i) -> bool:
	if _visibility_frozen:
		return bool(_observed.get(cell, false))
	if _fog == null:
		return true
	if not _observed.has(cell):
		_observed[cell] = _fog.is_cell_visible(cell)
	return bool(_observed[cell])
