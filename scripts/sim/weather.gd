class_name SimWeather
extends RefCounted
## Local deterministic climate and minute exposure. Original inventories/bodies
## retain water/needs; roofs and beds remain real construction projects.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const MINUTE_MS: int = 60000
var definitions: Dictionary = {}
var epoch_ms: int = 0
var last_pulse_ms: int = 0
var damp_beds: Dictionary = {}
var _owner: WeakRef
var world: RefCounted:
	get:
		return _owner.get_ref()


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "phases", "regions", "wet_per_pulse", "dry_per_pulse", "wet_threshold", "wet_recovery", "rain_source_type", "rain_source_per_pulse"]) or data.version != 1 or not data.phases is Array or data.phases.is_empty() or not Shape.keys(data.regions, ["home", "river"]):
		return false
	for phase: Variant in data.phases:
		if not Shape.keys(phase, ["kind", "duration_ms"]) or phase.kind not in ["clear", "rain"] or not Shape.count(phase.duration_ms, MINUTE_MS, 86400000) or int(phase.duration_ms) % MINUTE_MS != 0:
			return false
	for region: Variant in data.regions.values():
		if not Shape.keys(region, ["offset_ms"]) or not Shape.count(region.offset_ms, 0, 86400000) or int(region.offset_ms) % MINUTE_MS != 0:
			return false
	return Shape.count(data.wet_per_pulse, 1, 100) and Shape.count(data.dry_per_pulse, 1, 100) and Shape.count(data.wet_threshold, 1, 100) and Shape.count(data.wet_recovery, 1, 5) and data.rain_source_type == "spring" and Shape.count(data.rain_source_per_pulse, 1, 10)


func bind_world(authority: RefCounted) -> void:
	# Rebind a validated candidate without resetting its saved process.
	_owner = weakref(authority)


func initialize(parent: RefCounted, rules: Dictionary) -> bool:
	if not valid_definitions(rules):
		return false
	for region: String in parent.regions:
		if not rules.regions.has(region):
			return false
	_owner = weakref(parent)
	definitions = rules.duplicate(true)
	epoch_ms = parent.elapsed_ms
	last_pulse_ms = epoch_ms
	return true


static func empty_state(at_ms: int) -> Dictionary:
	return {"version": 1, "epoch_ms": at_ms, "last_pulse_ms": at_ms, "damp_beds": {}}


static func kind_at(rules: Dictionary, region: String, epoch: int, at_ms: int) -> String:
	var cycle: int = 0
	for phase: Dictionary in rules.phases:
		cycle += int(phase.duration_ms)
	var cursor: int = posmod(maxi(0, at_ms - epoch) + int(rules.regions[region].offset_ms), cycle)
	for phase: Dictionary in rules.phases:
		if cursor < int(phase.duration_ms):
			return str(phase.kind)
		cursor -= int(phase.duration_ms)
	return "clear"


func current_kind(region: String) -> String:
	return kind_at(definitions, region, epoch_ms, world.elapsed_ms)


func next_boundary_ms() -> int:
	return mini(SimInventory.MAX_COUNT, last_pulse_ms - posmod(last_pulse_ms, MINUTE_MS) + MINUTE_MS)


func settle_at_ms(now: int) -> void:
	if now < next_boundary_ms():
		return
	# Scheduler never skips an environmental pulse. Integrate original needs
	# under the preceding exposure before changing this interval's wetness.
	for region: String in world.regions:
		var sim: RefCounted = world.regions[region]
		if kind_at(definitions, region, epoch_ms, last_pulse_ms) == "rain":
			for id: String in sim.land_resources.sources:
				var terms: Dictionary = sim.land_resources.terms_for(id)
				if sim.config.resource_sources[id].definition == definitions.rain_source_type and sim.inventory.quantity(SimLandResources.container_id(id), str(terms.item)) < int(terms.capacity):
					world.synchronize_region(region)
					sim.land_resources.receive_rain(id, int(definitions.rain_source_per_pulse))
					world.invalidate_region(region)
	var construction: SimConstruction = world.construction
	for id: String in construction.projects:
		if not construction.is_bed(id) or int(construction.projects[id].completed_ms) > last_pulse_ms:
			continue
		var cell: Vector2i = SimRouteTravel.cell(construction.projects[id].cell)
		var raining: bool = kind_at(definitions, str(construction.definitions.site.region), epoch_ms, last_pulse_ms) == "rain"
		var wet: int = int(damp_beds.get(id, 0))
		wet = mini(100, wet + int(definitions.wet_per_pulse)) if raining and not construction.roofed(cell) else maxi(0, wet - int(definitions.dry_per_pulse))
		if wet == int(damp_beds.get(id, 0)):
			continue
		world.synchronize_region(str(construction.definitions.site.region))
		if wet == 0:
			damp_beds.erase(id)
		else:
			damp_beds[id] = wet
		world.invalidate_region(str(construction.definitions.site.region))
	if world.clothing != null:
		world.clothing.weather_pulse(last_pulse_ms)
	last_pulse_ms = now


func bed_wetness(bed: String) -> int:
	return int(damp_beds.get(bed, 0))


func bed_is_wet(bed: String) -> bool:
	return bed_wetness(bed) >= int(definitions.wet_threshold)


func structures_changed() -> void:
	for bed: String in damp_beds.keys():
		if not world.construction.is_bed(bed):
			damp_beds.erase(bed)


static func rain_budget(data: Variant, rules: Dictionary, region: String, now: int) -> int:
	if not data is Dictionary or not Shape.count(data.get("epoch_ms"), 0, now) or not rules.regions.has(region):
		return 0
	# Upper bound on physically elapsed rain pulses, in O(number of phases).
	# The first partial interval is accounted separately; no float large-time math.
	var epoch: int = int(data.epoch_ms)
	var first: int = epoch - posmod(epoch, MINUTE_MS) + MINUTE_MS
	if now < first:
		return 0
	var count: int = 1 if kind_at(rules, region, epoch, epoch) == "rain" else 0
	var last_sample: int = now - posmod(now, MINUTE_MS) - MINUTE_MS
	if last_sample < first:
		return count * int(rules.rain_source_per_pulse)
	var shift: int = int(rules.regions[region].offset_ms) - epoch
	var lower: int = first + shift
	var upper: int = last_sample + shift
	var cycle: int = 0
	for phase: Dictionary in rules.phases:
		cycle += int(phase.duration_ms)
	var start: int = 0
	for phase: Dictionary in rules.phases:
		var end: int = start + int(phase.duration_ms)
		if phase.kind == "rain":
			count += _pulse_prefix(upper, cycle, start, end) - _pulse_prefix(lower - MINUTE_MS, cycle, start, end)
		start = end
	return mini(SimInventory.MAX_COUNT, count * int(rules.rain_source_per_pulse))


static func _pulse_prefix(value: int, cycle: int, start: int, end: int) -> int:
	# Cumulative count of points on this shifted minute lattice. The same
	# remainder applies at both bounds, including a fractional epoch offset.
	@warning_ignore("integer_division")
	var quotient: int = (value - posmod(value, cycle)) / cycle
	var residual: int = posmod(value, cycle)
	@warning_ignore("integer_division")
	var phase_points: int = (end - start) / MINUTE_MS
	var remainder: int = posmod(value, MINUTE_MS)
	@warning_ignore("integer_division")
	var partial: int = clampi((residual - start - remainder) / MINUTE_MS + 1, 0, phase_points)
	return quotient * phase_points + partial


func to_dict() -> Dictionary:
	return {"version": 1, "epoch_ms": epoch_ms, "last_pulse_ms": last_pulse_ms, "damp_beds": damp_beds.duplicate(true)}


func restore(data: Dictionary) -> bool:
	if not Shape.keys(data, ["version", "epoch_ms", "last_pulse_ms", "damp_beds"]) or data.version != 1 or not Shape.count(data.epoch_ms, 0, world.elapsed_ms) or not Shape.count(data.last_pulse_ms, int(data.epoch_ms), world.elapsed_ms) or not data.damp_beds is Dictionary:
		return false
	var expected: int = maxi(int(data.epoch_ms), world.elapsed_ms - posmod(world.elapsed_ms, MINUTE_MS))
	if int(data.last_pulse_ms) != expected:
		return false
	for bed: Variant in data.damp_beds:
		if not bed is String or not world.construction.is_bed(bed) or not Shape.count(data.damp_beds[bed], 1, 100) or int(world.construction.projects[bed].completed_ms) >= int(data.last_pulse_ms):
			return false
		var region: String = str(world.construction.definitions.site.region)
		var before: int = maxi(int(data.epoch_ms), int(world.construction.projects[bed].completed_ms))
		var exposure: int = rain_budget(data, definitions, region, world.elapsed_ms) - rain_budget(data, definitions, region, before)
		@warning_ignore("integer_division")
		var maximum_wetness: int = exposure / int(definitions.rain_source_per_pulse) * int(definitions.wet_per_pulse)
		if int(data.damp_beds[bed]) > maximum_wetness:
			return false
	for region: String in world.regions:
		var sim: RefCounted = world.regions[region]
		var budget: int = rain_budget(data, definitions, region, world.elapsed_ms)
		for id: String in sim.land_resources.sources:
			var count: int = int(sim.land_resources.sources[id].rainfall)
			if count > budget or count > 0 and sim.config.resource_sources[id].definition != definitions.rain_source_type:
				return false
	epoch_ms = int(data.epoch_ms)
	last_pulse_ms = int(data.last_pulse_ms)
	damp_beds = data.damp_beds.duplicate(true)
	return true
