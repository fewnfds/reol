class_name SimBodyRead
extends RefCounted
## A read lease over original hot tables, not another body store. The owner
## collects every reader before changing any lent table. No callbacks, Nodes,
## lazy world queries or shared scratch are used by these methods.

var actors: Dictionary = {}
var anchors: Dictionary = {}
var completions: Dictionary = {}
var boundaries: Dictionary = {}
var continuations: Dictionary = {}
var needs: SimBodyNeedsRead
var at_ms: int
var timeout_ms: int
var geometry_revision: int
var route_events: bool
var commands_allowed: bool
var actor_subjects: Dictionary = {}
var actor_carriers: Dictionary = {}
var subjects: Dictionary = {}
var carriers: Dictionary = {}
var controls: Dictionary = {}
var precise_all: bool
var source_containers: Dictionary = {}
var dirty_containers: Dictionary[String, bool] = {}
var construction_jobs: Dictionary = {}
var stock: Dictionary = {}
var places: Dictionary = {}
var stock_near: Dictionary = {}
var observation_radius: float


static func capture(world: RegionalSimulation, sim: VillageSimulation, region: String) -> SimBodyRead:
	var read := SimBodyRead.new()
	read.actors = sim.actors
	read.anchors = sim._actor_projection_ms
	read.completions = sim.native_route_projections()
	read.boundaries = sim._actor_boundaries
	read.continuations = sim._route_continuations
	read.needs = sim.body_needs_read()
	read.at_ms = sim.elapsed_ms
	read.timeout_ms = int(sim.config.action_timeout) * VillageSimulation.MINUTE_MS
	read.geometry_revision = world.native_geometry_revision()
	read.route_events = sim.native_route_events_enabled
	read.commands_allowed = world.accepts_commands()
	read.actor_subjects = world.embodiment._actor_subjects
	read.actor_carriers = world.embodiment._source_carriers.get("village_actor", {})
	read.subjects = world.embodiment._subjects
	read.carriers = world.embodiment._carriers
	read.controls = world.embodiment._controls
	var fields: SimWorldEnvironmentFields = world.environment_fields
	read.precise_all = not fields._active or (world.space != null and world.space.needs_native_crossings())
	read.source_containers = fields._sources._container_sources.get(region, {})
	for pair: Array in fields._dirty_containers.values():
		if str(pair[0]) == region:
			read.dirty_containers[str(pair[1])] = true
	read.construction_jobs = world.construction.active
	read.stock = sim.inventory.containers
	read.places = sim.places
	read.stock_near = sim._stock_places_at_cell
	read.observation_radius = float(sim.config.observation_radius)
	return read


func controls_action(id: String) -> bool:
	var subject: String = str(actor_subjects.get(id, ""))
	var carrier: String = str(actor_carriers.get(id, ""))
	if not commands_allowed or not subjects.has(subject) or not carriers.has(carrier):
		return false
	var grants: Dictionary = controls.get(carrier, {})
	return grants.get("action", "") == subject and grants.get("motion", "") == subject


func precise_crossings(id: String) -> bool:
	var container: String = "actor:" + id
	if precise_all or dirty_containers.has(container) or source_containers.has(container):
		return true
	var job: Dictionary = construction_jobs.get(id, {})
	return not job.is_empty() and source_containers.has(str(job.project))


func stock_crossing(body: Dictionary, completion: Dictionary = {}) -> bool:
	if not completion.is_empty():
		for place: String in completion.stock_places:
			if _stock_changed(body, place):
				return true
		return false
	var route: Dictionary = body.active
	if route.path.is_empty():
		return false
	var origin: Vector2i = TileGrid.world_to_cell(Vector2(float(route.segment_from[0]), float(route.segment_from[1])))
	var target: Vector2i = SimRouteTravel.cell(route.path[0])
	for y: int in range(mini(origin.y, target.y), maxi(origin.y, target.y) + 1):
		for x: int in range(mini(origin.x, target.x), maxi(origin.x, target.x) + 1):
			var cell := Vector2i(x, y)
			if stock_near.has(cell):
				for place: String in stock_near[cell]:
					if _stock_changed(body, place):
						return true
			else:
				# Missing memo entries stay private; readers never extend the
				# owner's cache or discover/change anyone's knowledge.
				for place: String in places:
					if Vector2(cell).distance_to(Vector2(SimRouteTravel.cell(places[place].cell))) <= observation_radius and _stock_changed(body, place):
						return true
	return false


func _stock_changed(body: Dictionary, place: String) -> bool:
	var memory: Dictionary = body.stock_memory.get(place, {})
	@warning_ignore("integer_division")
	var minute: int = at_ms / VillageSimulation.MINUTE_MS
	return memory.get("tick", -1) != minute or memory.get("items") != stock[place]
