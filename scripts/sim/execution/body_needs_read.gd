class_name SimBodyNeedsRead
extends RefCounted
## Borrowed inputs for native body needs, separate from movement/geometry.
## Source adapts the original owners on the coordinator. The read itself has
## no callbacks or world reference and can be lent to independent body tasks.

class Source extends RefCounted:
	var _owner: WeakRef
	var world: RegionalSimulation:
		get: return _owner.get_ref() if _owner != null else null

	func _init(authority: RegionalSimulation) -> void:
		_owner = weakref(authority)

	func recovery_for(id: String) -> int:
		var authority: RegionalSimulation = world
		return authority.resting.recovery_for(id) if authority != null else 0

	func laboring(id: String) -> bool:
		var authority: RegionalSimulation = world
		return authority != null and (authority.personal_production.owns_actor(id) or authority.clothing.owns_actor(id) or (authority.field_opportunities != null and authority.field_opportunities.owns_actor(id)))

	func exposure_rate(id: String) -> int:
		var authority: RegionalSimulation = world
		return authority.clothing.energy_rate(id) + authority.environment.energy_rate(id) if authority != null else 0

	func matches(sim: VillageSimulation) -> bool:
		return world != null and sim._rest_recovery == recovery_for and sim._external_labor == laboring and sim._exposure_rate == exposure_rate

	func capture(sim: VillageSimulation) -> SimBodyNeedsRead:
		if not matches(sim):
			return null # Opaque overrides stay on their original ordered owner.
		return SimBodyNeedsRead.capture(world, sim)

var pawns: Dictionary = {}
var hunger_rate: int
var base_energy_rate: int
var work_energy_rate: int
var stamina_rate: int
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


static func capture(world: RegionalSimulation, sim: VillageSimulation) -> SimBodyNeedsRead:
	var read := SimBodyNeedsRead.new()
	read.pawns = world._content.pawns
	read.hunger_rate = roundi(float(sim.config.needs.hunger_per_minute) * VillageSimulation.NEED_SCALE)
	read.base_energy_rate = roundi(float(sim.config.needs.energy_per_minute) * VillageSimulation.NEED_SCALE)
	read.work_energy_rate = roundi(float(sim.config.needs.work_energy_per_minute) * VillageSimulation.NEED_SCALE)
	read.stamina_rate = int(sim.motion_rules.recovery.stamina_per_second)
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
