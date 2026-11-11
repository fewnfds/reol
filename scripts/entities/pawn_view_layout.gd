class_name PawnViewLayout
extends RefCounted
## One disposable sample of accepted motion. Only observed cells need a
## drawing layout; bodies sharing them include visitors from other owners.

const CROWD_RADIUS: float = 24.0

var cells: Dictionary[String, Vector2i] = {}
var points: Dictionary[String, Vector2] = {}
var native_legs: Dictionary[String, int] = {}
var offsets: Dictionary[String, Vector2] = {}

var _fog: FogOfWar
var _observed: Dictionary[Vector2i, bool] = {}
var _occupants: Dictionary[Vector2i, String] = {}
var _crowds: Dictionary[Vector2i, Array] = {}


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
		if _crowds.has(cell):
			_crowds[cell].append(id)
		elif _occupants.has(cell):
			_crowds[cell] = [_occupants[cell], id]
		else:
			_occupants[cell] = id


func finish(center_actor_id: String) -> void:
	for ids: Array in _crowds.values():
		ids.erase(center_actor_id)
		ids.sort()
		for index: int in ids.size():
			var angle: float = -PI * 0.5 + TAU * float(index) / float(ids.size())
			offsets[ids[index]] = Vector2(cos(angle), sin(angle)) * CROWD_RADIUS
	_occupants.clear()
	_crowds.clear()


func include_publication(frame: SimBodyPublication) -> void:
	for id: String in frame.rows:
		var row: Dictionary = frame.rows[id]
		var cell: Vector2i = row.cell
		cells[id] = cell
		if not _observed.has(cell):
			_observed[cell] = _fog == null or _fog.is_cell_visible(cell)
		if not _observed[cell]:
			continue
		points[id] = row.point
		if not bool(row.alive):
			continue
		if _crowds.has(cell):
			_crowds[cell].append(id)
		elif _occupants.has(cell):
			_crowds[cell] = [_occupants[cell], id]
		else:
			_occupants[cell] = id


func sees(cell: Vector2i) -> bool:
	return _fog == null or bool(_observed.get(cell, false))
