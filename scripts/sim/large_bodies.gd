class_name SimLargeBodies
extends RefCounted
signal body_space_changed(id: String)
signal bodies_space_changed(ids: Array[String])
signal space_reset

var _sweep_changes: Dictionary = {}
var space_updating: bool = false
## One physical source per large body. Views and Embodiment only reference it.
## A bounded roaming sample, not a complete species/needs/combat simulation.

const VERSION: int = 1
const Shape = preload("res://scripts/sim/avian_schema.gd")
const Schema = preload("res://scripts/sim/large_body_schema.gd")

var definitions: Dictionary = {}
var bodies: Dictionary = {}
var events: Array[Dictionary] = []
var elapsed_ms: int = 0
var next_id: int = 1
var _owner: WeakRef
var _terrain: Callable
var _elevation: Callable
var _incoming: Callable
## Host policy, not saved state. Only synchronous static-map queries opt in.
var _reuse_static_geometry: bool = false

var world: RefCounted:
	get:
		return _owner.get_ref() if _owner != null else null


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "form", "step_ms", "rest_ms", "retry_ms", "feed_interval_ms", "contact_px", "food", "food_amount", "navigation_radius", "navigation_budget", "max_bodies"]) or data.version != VERSION or data.form != "ancient_beast" or data.food != "meal":
		return false
	for key: String in ["step_ms", "rest_ms", "retry_ms", "feed_interval_ms", "contact_px", "food_amount", "navigation_radius", "navigation_budget", "max_bodies"]:
		if not Shape.count(data[key], 1, 1000000):
			return false
	return int(data.max_bodies) <= 8 and int(data.navigation_radius) <= 32 and int(data.navigation_budget) <= 4096


func bind_world(authority: RefCounted) -> void:
	# Rebind a validated candidate without resetting its saved process.
	_owner = weakref(authority)


func initialize(authority: RefCounted, content: Dictionary) -> bool:
	if authority == null or not valid_definitions(content):
		return false
	_owner = weakref(authority)
	definitions = content.duplicate(true)
	elapsed_ms = authority.elapsed_ms
	return true


func set_geometry(terrain: Callable, elevation: Callable, incoming: Callable = Callable(), reuse_static_geometry: bool = false) -> void:
	_terrain = terrain
	_elevation = elevation
	_incoming = incoming
	_reuse_static_geometry = reuse_static_geometry


static func subject_id(id: String) -> String:
	return "subject:large:" + id


static func carrier_id(id: String) -> String:
	return "body:large:" + id


func size() -> Vector2i:
	var form: Array = world._content.body_forms.forms[definitions.form].footprint
	return Vector2i(int(form[0]), int(form[1]))


func add_body(id: String, label: String, region: String, a: Vector2i, b: Vector2i) -> bool:
	if world.elapsed_ms != world.target_ms or bodies.size() >= int(definitions.max_bodies) or bodies.has(id) or not SimInventory._nonempty(id) or not SimInventory._nonempty(label) or not world.regions.has(region) or a == b or not SimBodyGeometry.can_stand(a, size(), _walkable, _elevation) or not SimBodyGeometry.can_stand(b, size(), _walkable, _elevation):
		return false
	var path: Array[Vector2i] = _path(a, b)
	if path.is_empty():
		return false
	for cell: Vector2i in SimBodyGeometry.cells(a, size()):
		if occupied_by_other(cell):
			return false
	var registry := SimEmbodiment.new()
	if not registry.configure(world._content.body_forms) or not registry.restore(world.embodiment.to_dict()) or not registry.add_subject(subject_id(id)) or not registry.add_carrier(carrier_id(id), str(definitions.form), {"kind": "large_body", "id": id}) or not registry.reside(subject_id(id), carrier_id(id)):
		return false
	for channel: String in SimEmbodiment.CHANNELS:
		if not registry.grant_control(subject_id(id), carrier_id(id), channel):
			return false
	var point: Vector2 = TileGrid.cell_to_world(a)
	bodies[id] = {"label": label, "region": region, "position": [point.x, point.y],
		"waypoints": [[a.x, a.y], [b.x, b.y]], "destination": 1, "facing": 1,
		"step": {}, "path": [], "retry_ms": elapsed_ms + int(definitions.rest_ms), "last_fed_ms": -1}
	world.embodiment = registry
	body_space_changed.emit(id)
	return true


func point(id: String) -> Vector2:
	return SimAvianLife.point(bodies[id])


func body_cell(id: String) -> Vector2i:
	return TileGrid.world_to_cell(point(id))


func swept_bounds(id: String) -> Rect2i:
	var body: Dictionary = bodies[id]
	if body.step.is_empty():
		return SimBodyGeometry.bounds(body_cell(id), size())
	return SimBodyGeometry.bounds(SimRouteTravel.cell(body.step.from), size()).merge(SimBodyGeometry.bounds(SimRouteTravel.cell(body.step.to), size()))


func blocked(cell: Vector2i) -> bool:
	for id: String in bodies:
		if swept_bounds(id).has_point(cell):
			return true
	return false


func occupied_by_other(cell: Vector2i, except_body: String = "") -> bool:
	for id: String in bodies:
		if id != except_body and swept_bounds(id).has_point(cell):
			return true
	for sim: VillageSimulation in world.regions.values():
		for actor: Dictionary in sim.synchronize_actors().values():
			if bool(actor.alive) and SimRouteTravel.cell(actor.cell) == cell:
				return true
		for place: Dictionary in sim.places.values():
			if SimRouteTravel.cell(place.cell) == cell:
				return true
	if world.avian_life != null:
		for id: String in world.avian_life.birds:
			if int(world.avian_life.birds[id].altitude) == 0 and world.avian_life.body_cell(id) == cell:
				return true
	if SimMotionClearance.active_segment_reserves(world, cell):
		return true
	return _incoming.is_valid() and bool(_incoming.call(cell))


func _walkable(cell: Vector2i) -> bool:
	if not _terrain.is_valid() or not bool(_terrain.call(cell)) or world.construction != null and world.construction.blocked(cell) or world.plants != null and world.plants.blocked(cell):
		return false
	for sim: VillageSimulation in world.regions.values():
		for place: Dictionary in sim.places.values():
			if SimRouteTravel.cell(place.cell) == cell:
				return false
	return true


func _path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	# Actual occupancy and each step's clearance are still checked live below.
	return SimBodyGeometry.find_path(a, b, size(), _walkable, _elevation, int(definitions.navigation_radius), int(definitions.navigation_budget), _reuse_static_geometry)


func next_boundary_ms() -> int:
	var next: int = SimInventory.MAX_COUNT
	for body: Dictionary in bodies.values():
		next = mini(next, int(body.retry_ms) if body.step.is_empty() else int(body.step.due_ms))
	return maxi(elapsed_ms + 1, next)


func settle_at_ms(now: int) -> void:
	if now < elapsed_ms:
		return
	space_updating = true
	_sweep_changes.clear()
	elapsed_ms = now
	var moved: Array[String] = []
	for id: String in SimAvianLife.sorted_keys(bodies):
		var body: Dictionary = bodies[id]
		if not body.step.is_empty():
			var step: Dictionary = body.step
			var from: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(step.from))
			var to: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(step.to))
			var ratio: float = clampf(float(now - int(step.started_ms)) / float(int(definitions.step_ms)), 0.0, 1.0)
			var projected: Vector2 = from.lerp(to, ratio)
			var before: Vector2i = body_cell(id)
			body.position = [projected.x, projected.y]
			if before != body_cell(id):
				moved.append(id)
			if now < int(step.due_ms):
				continue
			body.step = {}
			_notify_sweep_change(id)
			if body_cell(id) == SimRouteTravel.cell(body.waypoints[body.destination]):
				body.destination = 1 - int(body.destination)
				body.path = []
				body.retry_ms = now + int(definitions.rest_ms)
				continue
			body.retry_ms = now
		if int(body.retry_ms) <= now:
			_start_step(id)
	for id: String in _sweep_changes:
		if not moved.has(id):
			moved.append(id)
	_sweep_changes.clear()
	if not moved.is_empty():
		bodies_space_changed.emit(moved)
	space_updating = false


func _start_step(id: String) -> void:
	var body: Dictionary = bodies[id]
	body.retry_ms = elapsed_ms + int(definitions.retry_ms)
	# Far-region actors may be projected lazily. Settle their actual bodies before
	# claiming a sweep, rather than treating an outdated cell as empty space.
	if not world.synchronize_regions():
		return
	if not world.embodiment.controls(subject_id(id), carrier_id(id), "motion"):
		return
	var at: Vector2i = body_cell(id)
	if body.path.is_empty():
		var route: Array[Vector2i] = _path(at, SimRouteTravel.cell(body.waypoints[body.destination]))
		if route.size() <= 1:
			return
		for cell: Vector2i in route.slice(1):
			body.path.append([cell.x, cell.y])
	var next: Vector2i = SimRouteTravel.cell(body.path[0])
	if not SimBodyGeometry.can_step(at, next - at, size(), _walkable, _elevation):
		body.path = []
		return
	# The proposed footprint is one synchronous decision. Original bodies and
	# accepted segments do not change between these cell reads; scan them once.
	var reservations: Dictionary = SimMotionClearance.capture_active_reservations(world)
	var occupied: Dictionary[Vector2i, bool] = {}
	for sim: VillageSimulation in world.regions.values():
		for actor: String in sim.actor_ids():
			var original: Dictionary = sim.actor_state(actor)
			if bool(original.alive):
				occupied[SimRouteTravel.cell(original.cell)] = true
		for place: Dictionary in sim.places.values():
			occupied[SimRouteTravel.cell(place.cell)] = true
	if world.avian_life != null:
		for bird: String in world.avian_life.birds:
			if int(world.avian_life.birds[bird].altitude) == 0:
				occupied[world.avian_life.body_cell(bird)] = true
	for cell: Vector2i in SimBodyGeometry.cells(next, size()):
		if occupied.has(cell) or bool(reservations.all) or reservations.cells.has(cell):
			return
		for other: String in bodies:
			if other != id and swept_bounds(other).has_point(cell):
				return
		if _incoming.is_valid() and bool(_incoming.call(cell)):
			return
	body.path.pop_front()
	body.facing = SimBodyGeometry.DIRECTIONS.find(next - at)
	body.step = {"from": [at.x, at.y], "to": [next.x, next.y], "started_ms": elapsed_ms, "due_ms": elapsed_ms + int(definitions.step_ms)}
	_notify_sweep_change(id)


func _notify_sweep_change(id: String) -> void:
	# Starting/ending a sweep changes occupied cells even if the center has
	# not crossed a cell. Reuse the original spatial notification contract.
	if space_updating:
		_sweep_changes[id] = true
	else:
		body_space_changed.emit(id)


func visible_to(actor: String, id: String) -> bool:
	var home: String = world.artifacts.actor_home(actor)
	if home.is_empty() or not bodies.has(id):
		return false
	var sim: VillageSimulation = world.regions[home]
	return bool(sim.synchronize_actor(actor).alive) and SimBodyGeometry.contact_distance(SimRouteTravel.point(sim.synchronize_actor(actor)), point(id), size()) <= float(sim.config.observation_radius * TileGrid.TILE_SIZE)


func offer_food(actor: String, id: String, food: String) -> Dictionary:
	if world.elapsed_ms != world.target_ms or food != definitions.food or not visible_to(actor, id):
		return _reply(false, "先看清眼前的山兽和要递出的饭食。", "unheard")
	var home: String = world.artifacts.actor_home(actor)
	world.synchronize_region(home)
	var sim: VillageSimulation = world.regions[home]
	var body: Dictionary = bodies[id]
	if not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or not sim.synchronize_actor(actor).active.is_empty() or world.local_action_owns(actor) or world.artifacts.owns_actor(actor) or world.services != null and world.services.owns_actor(actor):
		return _reply(false, "先停下手头的事情，再腾手递食。")
	if not body.step.is_empty():
		return _reply(false, "山兽正在迈步，先等它停稳。")
	if SimBodyGeometry.contact_distance(SimRouteTravel.point(sim.synchronize_actor(actor)), point(id), size()) > float(definitions.contact_px) or swept_bounds(id).has_point(SimRouteTravel.cell(sim.synchronize_actor(actor).cell)):
		return _reply(false, "站到山兽身侧，隔着身体边缘递出食物。", "unheard")
	if int(body.last_fed_ms) >= 0 and elapsed_ms - int(body.last_fed_ms) < int(definitions.feed_interval_ms):
		return _reply(false, "它嗅了嗅，没有再张口；这一会儿不想吃。", "refused")
	if sim.inventory.available("actor:" + actor, food) < int(definitions.food_amount):
		return _reply(false, "行囊里没有可自行处分的这份饭食。")
	var event_id: String = "large_food:%d" % next_id
	if not sim.inventory.consume(event_id, "actor:" + actor, food, int(definitions.food_amount)):
		return _reply(false, "食物已被别的事情占用。")
	next_id += 1
	body.last_fed_ms = elapsed_ms
	events.append({"id": event_id, "body": id, "actor": actor, "region": home, "at_ms": elapsed_ms, "item": food, "amount": int(definitions.food_amount)})
	world.invalidate_region(home)
	return _reply(true, "山兽俯首吃下你递出的饭食；它仍有自己的去处。", "completed", event_id)


static func _reply(ok: bool, line: String, code: String = "unavailable", id: String = "") -> Dictionary:
	return {"ok": ok, "line": line, "code": code, "id": id}


func space_valid() -> bool:
	for id: String in bodies:
		var body: Dictionary = bodies[id]
		var anchor: Vector2i = body_cell(id) if body.step.is_empty() else SimRouteTravel.cell(body.step.from)
		if not SimBodyGeometry.can_stand(anchor, size(), _walkable, _elevation):
			return false
		if not body.step.is_empty() and not SimBodyGeometry.can_step(anchor, SimRouteTravel.cell(body.step.to) - anchor, size(), _walkable, _elevation):
			return false
		for other: String in bodies:
			if other != id and swept_bounds(id).intersects(swept_bounds(other)):
				return false
	return true


func to_dict() -> Dictionary:
	return {"version": VERSION, "elapsed_ms": elapsed_ms, "bodies": bodies.duplicate(true), "events": events.duplicate(true), "next_id": next_id}


static func empty_state(now: int) -> Dictionary:
	return {"version": VERSION, "elapsed_ms": now, "bodies": {}, "events": [], "next_id": 1}


func restore(data: Variant) -> bool:
	if not Schema.validate(data, self):
		return false
	bodies = data.bodies.duplicate(true)
	events.assign(data.events.duplicate(true))
	elapsed_ms = int(data.elapsed_ms)
	next_id = int(data.next_id)
	_sweep_changes.clear()
	space_reset.emit()
	return true
