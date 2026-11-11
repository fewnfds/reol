class_name SimBodyRead
extends RefCounted
## A read lease over original hot tables, not another body store. The owner
## collects every reader before changing any lent table. No callbacks, Nodes,
## lazy world queries or shared scratch are used by these methods.

var actors: Dictionary = {}
var anchors: Dictionary = {}
var completions: Dictionary = {}
var pawns: Dictionary = {}
var at_ms: int
var hunger_rate: int
var base_energy_rate: int
var work_energy_rate: int
var stamina_rate: int
var timeout_ms: int
var geometry_revision: int
var route_events: bool
var commands_allowed: bool
var actor_subjects: Dictionary = {}
var actor_carriers: Dictionary = {}
var subjects: Dictionary = {}
var carriers: Dictionary = {}
var controls: Dictionary = {}
var worn: Dictionary = {}
var garments: Dictionary = {}
var garment_wet_threshold: int
var garment_energy_rate: int
var exposures: Dictionary = {}
var production: Dictionary = {}
var clothing_jobs: Dictionary = {}
var field_purposes: Dictionary = {}
var field_trips: Dictionary = {}
var resting: Dictionary = {}
var damp_beds: Dictionary = {}
var bed_wet_threshold: int
var dry_recovery: int
var wet_recovery: int
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
	read.pawns = world._content.pawns
	read.at_ms = sim.elapsed_ms
	read.hunger_rate = roundi(float(sim.config.needs.hunger_per_minute) * VillageSimulation.NEED_SCALE)
	read.base_energy_rate = roundi(float(sim.config.needs.energy_per_minute) * VillageSimulation.NEED_SCALE)
	read.work_energy_rate = roundi(float(sim.config.needs.work_energy_per_minute) * VillageSimulation.NEED_SCALE)
	read.stamina_rate = int(sim.motion_rules.recovery.stamina_per_second)
	read.timeout_ms = int(sim.config.action_timeout) * VillageSimulation.MINUTE_MS
	read.geometry_revision = world.native_geometry_revision()
	read.route_events = sim.native_route_events_enabled
	read.commands_allowed = world.accepts_commands()
	read.actor_subjects = world.embodiment._actor_subjects
	read.actor_carriers = world.embodiment._source_carriers.get("village_actor", {})
	read.subjects = world.embodiment._subjects
	read.carriers = world.embodiment._carriers
	read.controls = world.embodiment._controls
	read.worn = world.clothing._worn
	read.garments = world.clothing.objects
	read.garment_wet_threshold = int(world.clothing.definitions.wet_threshold)
	read.garment_energy_rate = roundi(float(world.clothing.definitions.wet_energy_per_minute) * VillageSimulation.NEED_SCALE)
	read.exposures = world.environment.samples
	read.production = world.personal_production.active
	read.clothing_jobs = world.clothing.active
	if world.field_opportunities != null:
		read.field_purposes = world.field_opportunities.purposes
		read.field_trips = world.field_opportunities.trips
	read.resting = world.resting.active
	read.damp_beds = world.weather.damp_beds
	read.bed_wet_threshold = int(world.weather.definitions.wet_threshold)
	read.dry_recovery = int(world.resting.definitions.energy_per_minute)
	read.wet_recovery = int(world.weather.definitions.wet_recovery)
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


func energy_input(id: String, body: Dictionary) -> Vector2i:
	var rate: int = base_energy_rate + int(exposures.get(id, {}).get("energy_rate", 0))
	var garment: String = str(worn.get(id, {}).get("body", ""))
	if not garment.is_empty() and int(garments[garment].wet) >= garment_wet_threshold:
		rate += garment_energy_rate
	var field: Dictionary = field_purposes.get(id, {})
	var field_labor: bool = field.get("phase", "") in ["outbound", "returning"] and field_trips.get(field.get("trip", ""), {}).get("status") == "active"
	var laboring: bool = not body.active.is_empty() or production.has(id) or clothing_jobs.has(id) or field_labor
	if laboring:
		rate += work_energy_rate
	var rest: Dictionary = resting.get(id, {})
	if rest.get("phase", "") == "sleep":
		rate -= (wet_recovery if int(damp_beds.get(rest.bed, 0)) >= bed_wet_threshold else dry_recovery) * VillageSimulation.NEED_SCALE
	return Vector2i(rate, int(not laboring or str(body.active.get("action", "")) == "rest"))


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
