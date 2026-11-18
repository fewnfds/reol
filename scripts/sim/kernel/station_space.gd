extends RefCounted
## Rebuild once after a body batch; destination admissions update in place.
## Broad phase covers every timed motion knot, then callers test exact time.
const CELL: float = 4.0
var bodies: Dictionary = {}
var destinations: Dictionary = {}
var body_cells: Dictionary = {}
var destination_cells: Dictionary = {}
var valid: bool = false
var queries: int = 0
var candidates: int = 0
var indexed: int = 0

func invalidate() -> void:
	valid = false

func _cells(low: Vector2, high: Vector2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var first := Vector2i((low / CELL).floor())
	var last := Vector2i((high / CELL).floor())
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1): result.append(Vector2i(x, y))
	return result

func _place(index: Dictionary, memberships: Dictionary, actor: int, low: Vector2, high: Vector2) -> void:
	for cell: Vector2i in memberships.get(actor, []):
		index[cell].erase(actor)
		if index[cell].is_empty(): index.erase(cell)
	var cells: Array[Vector2i] = _cells(low, high)
	memberships[actor] = cells
	for cell: Vector2i in cells:
		if not index.has(cell): index[cell] = {}
		index[cell][actor] = true

func destination_changed(actor: int, point: Vector2, target: Vector2, radius: float) -> void:
	if not valid or actor <= 0: return
	_place(destinations, destination_cells, actor, target - Vector2.ONE * radius, target + Vector2.ONE * radius)
	# Current owner movement/teleport admissions can occur within the same commit.
	var combined: Array = body_cells.get(actor, []).duplicate()
	for cell: Vector2i in _cells(point - Vector2.ONE * radius, point + Vector2.ONE * radius):
		if cell not in combined: combined.append(cell)
		if not bodies.has(cell): bodies[cell] = {}
		bodies[cell][actor] = true
	body_cells[actor] = combined

func rebuild(world: RefCounted) -> void:
	bodies.clear(); destinations.clear(); body_cells.clear(); destination_cells.clear()
	for page_index: int in world.pages.size():
		var page: RefCounted = world.pages[page_index]
		for row: int in page.ids.size():
			var actor: int = int(page.ids[row])
			if actor <= 0 or page.health[row] <= 0: continue
			indexed += 1
			var point: Vector2 = page.positions[row]
			var low: Vector2 = point
			var high: Vector2 = point
			if page_index < world.combat.previous.size() and row < world.combat.previous[page_index].size():
				low = low.min(world.combat.previous[page_index][row]); high = high.max(world.combat.previous[page_index][row])
			for knot: Vector3 in page.motion.get(row, PackedVector3Array()):
				low = low.min(Vector2(knot.x, knot.y)); high = high.max(Vector2(knot.x, knot.y))
			var padding: Vector2 = Vector2.ONE * (float(page.radii[row]) + 0.04)
			_place(bodies, body_cells, actor, low - padding, high + padding)
			_place(destinations, destination_cells, actor, page.targets[row] - padding, page.targets[row] + padding)
	valid = true

func nearby(world: RefCounted, point: Vector2, radius: float, include_destinations: bool) -> Array:
	# Time zero includes explicit opening/test placement before the first body batch.
	if not valid or world.elapsed_ms == 0: rebuild(world)
	queries += 1
	var found: Dictionary = {}
	for cell: Vector2i in _cells(point - Vector2.ONE * radius, point + Vector2.ONE * radius):
		for actor: int in bodies.get(cell, {}): found[actor] = true
		if include_destinations:
			for actor: int in destinations.get(cell, {}): found[actor] = true
	candidates += found.size()
	return found.keys()
