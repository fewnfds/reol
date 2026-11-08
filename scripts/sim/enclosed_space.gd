class_name SimEnclosedSpace
extends RefCounted
## Derived bounded topology. A doorway separates spaces even while open.
## Enclosure never implies a roof or thermal/weather protection.

const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]


static func detect(bounds: Rect2i, projects: Dictionary, types: Dictionary, elevation: Callable = Callable()) -> Dictionary:
	var edges: Dictionary = {}
	for id: String in projects:
		var project: Dictionary = projects[id]
		if project.state == "built" and types[project.type].facts.enclosure_boundary:
			for cell: Vector2i in SimConstructionGeometry.cells(project, types[project.type]):
				edges[cell] = {"id": id, "project": project}
	var result: Dictionary = {}
	for start: Vector2i in SimConstruction.cells_in(bounds):
		if edges.has(start) or result.has(start):
			continue
		var queue: Array[Vector2i] = [start]
		var found: Dictionary = {start: true}
		var doors: Dictionary = {}
		var enclosed: bool = true
		var flat: bool = true
		var level: int = int(elevation.call(start)) if elevation.is_valid() else 0
		var cursor: int = 0
		while cursor < queue.size():
			var cell: Vector2i = queue[cursor]
			cursor += 1
			if elevation.is_valid() and int(elevation.call(cell)) != level:
				flat = false
			for direction: Vector2i in SIDES:
				var neighbor: Vector2i = cell + direction
				if not bounds.has_point(neighbor):
					enclosed = false
				elif edges.has(neighbor):
					var edge: Dictionary = edges[neighbor]
					if types[edge.project.type].door:
						doors[edge.id] = bool(edge.project.open)
				elif not found.has(neighbor):
					found[neighbor] = true
					queue.append(neighbor)
		var opened: int = 0
		for value: bool in doors.values():
			if value:
				opened += 1
		var space: Dictionary = {"enclosed": enclosed, "flat": flat, "area": queue.size(), "doors": doors.size(), "open_doors": opened, "roofed": false}
		for cell: Vector2i in queue:
			result[cell] = space
	return result
