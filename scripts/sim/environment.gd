class_name SimEnvironment
extends RefCounted
## Local conditions are projections. Only sampled future exposure is saved;
## the original village owns energy and the original clothes own wetness.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const VERSION: int = 3
const MINUTE_MS: int = 60000
var definitions: Dictionary = {}
var activation_ms: int = 0
var last_pulse_ms: int = 0
var samples: Dictionary = {}
var _owner: WeakRef
var world: RefCounted:
	get:
		return _owner.get_ref()


func bind_world(authority: RefCounted) -> void:
	# Rebind a validated candidate without resetting its saved process.
	_owner = weakref(authority)


func initialize(authority: RefCounted, rules: Dictionary) -> bool:
	# Importers build an isolated candidate with its validated historical v1
	# content. Ordinary content loading only binds the current v2 definition.
	if authority == null or not (SimClimateRules.valid_definitions(rules) or SimClimateRules.valid_legacy_definitions(rules)) or int(rules.human.energy_scale) != VillageSimulation.NEED_SCALE:
		return false
	for region: String in rules.regions:
		if not authority.weather.definitions.regions.has(region):
			return false
	for type: String in authority.clothing.definitions.types:
		if not rules.garments.has(type):
			return false
	_owner = weakref(authority)
	definitions = rules.duplicate(true)
	activation_ms = authority.elapsed_ms
	last_pulse_ms = activation_ms
	return true


static func empty_state(at_ms: int, rules_version: int = 2) -> Dictionary:
	return {"version": VERSION, "rules_version": rules_version, "activation_ms": at_ms, "last_pulse_ms": at_ms, "samples": {}}


func date_label(at_ms: int = -1) -> String:
	return SimWorldCalendar.format_date(definitions.calendar, world.elapsed_ms if at_ms < 0 else at_ms)


func region_for_actor(actor: String) -> String:
	var home: String = world.clothing.home(actor)
	if home.is_empty():
		return ""
	return SimClimateRules.region_at(definitions, SimRouteTravel.cell(world.regions[home].actors[actor].cell))


func _garments(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: String in ["body", "outer"]:
		var id: String = world.clothing.worn_at(actor, slot)
		if not id.is_empty():
			var object: Dictionary = world.clothing.objects[id]
			result.append({"id": id, "type": object.type, "wet": int(object.wet)})
	return result


func _insulation(garments: Array) -> int:
	var result: int = 0
	for garment: Dictionary in garments:
		result += SimClimateRules.insulation_at(definitions, str(garment.type), int(garment.wet))
	return result


func _garments_at(actor: String, at_ms: int) -> Array[Dictionary]:
	var worn: Dictionary = {}
	for id: String in world._sorted_keys(world.clothing.objects):
		var object: Dictionary = world.clothing.objects[id]
		if object.owner != actor:
			continue
		var region: String = str(object.region)
		var container: String = str(object.container)
		var was_worn: bool = bool(object.worn)
		for index: int in range(world.clothing.events.size() - 1, -1, -1):
			var event: Dictionary = world.clothing.events[index]
			if int(event.finished_ms) <= at_ms:
				break
			if event.object == id and event.outcome == "completed":
				region = str(event.from_region)
				container = str(event.from_container)
				was_worn = bool(event.from_worn)
		if was_worn and region == world.clothing.home(actor) and container == "actor:" + actor:
			var slot: String = str(world.clothing.definitions.types[object.type].slot)
			# Wetness changes only on the same minute lattice, before this
			# latest sample. Later take/place/wear/remove never change wetness.
			worn[slot] = {"id": id, "type": object.type, "wet": int(object.wet)}
	var result: Array[Dictionary] = []
	for slot: String in ["body", "outer"]:
		if worn.has(slot):
			result.append(worn[slot])
	return result


func insulation_for(actor: String) -> int:
	return _insulation(_garments(actor))


func _temperature(region: String, at_ms: int) -> int:
	var background: Dictionary = SimClimateRules.background_for_region(definitions, world.weather.definitions, world.weather.epoch_ms, region, at_ms)
	return int(background.temperature_tenths)


func _thermal() -> RefCounted:
	return world.get("environment_fields") as RefCounted


func _current_heat_tenths(cell: Vector2i) -> int:
	var heat: RefCounted = _thermal()
	# Village initiative may preview a future decision before the regional
	# clock commits it. Read the original already committed cell authority;
	# neither a future preview nor UI observation advances its integrator.
	return 0 if heat == null else int(heat.current_tenths(cell))


func _sample_heat_tenths(cell: Vector2i, at_ms: int) -> int:
	var heat: RefCounted = _thermal()
	return 0 if heat == null else int(heat.sample_tenths(cell, at_ms))


func _minimum_heat_tenths() -> int:
	var heat: RefCounted = _thermal()
	return 0 if heat == null else int(heat.minimum_offset_tenths())


func _maximum_heat_tenths() -> int:
	var heat: RefCounted = _thermal()
	return 0 if heat == null else int(heat.maximum_offset_tenths())


func _has_sampled_heat(at_ms: int, historical: bool) -> bool:
	var heat: RefCounted = _thermal()
	if heat == null or historical and at_ms != int(heat.last_sample_ms):
		return false
	return bool(heat.has_visible_offsets(historical))


func _neutral_everywhere(at_ms: int, insulation: int, historical: bool = false) -> bool:
	# With visible local heat, retain location even for an actor outside it.
	# Moving after a sample must not erase that historical exposure evidence.
	if _has_sampled_heat(at_ms, historical):
		return false
	for region: String in definitions.regions:
		if int(SimClimateRules.burden(definitions, _temperature(region, at_ms), insulation).energy_rate) != 0:
			return false
	return true


func sample_for(actor: String, at_ms: int) -> Dictionary:
	var garments: Array[Dictionary] = _garments(actor)
	var insulation: int = _insulation(garments)
	var sample: Dictionary = {"at_ms": at_ms, "cell": [], "region": "", "temperature_tenths": 0,
		"heat_tenths": 0, "garments": garments, "insulation_tenths": insulation, "energy_rate": 0}
	if _neutral_everywhere(at_ms, insulation, true):
		return sample
	var home: String = world.clothing.home(actor)
	var region: String = region_for_actor(actor)
	sample.cell = world.regions[home].actors[actor].cell.duplicate()
	sample.region = region
	sample.heat_tenths = _sample_heat_tenths(SimRouteTravel.cell(sample.cell), at_ms)
	var temperature: int = _temperature(region, at_ms) + int(sample.heat_tenths)
	sample.temperature_tenths = temperature
	sample.energy_rate = int(SimClimateRules.burden(definitions, temperature, insulation).energy_rate)
	return sample


func local_conditions(actor: String, at_ms: int = -1) -> Dictionary:
	var region: String = region_for_actor(actor)
	if region.is_empty():
		return {}
	var now: int = world.elapsed_ms if at_ms < 0 else at_ms
	var home: String = world.clothing.home(actor)
	var cell: Vector2i = SimRouteTravel.cell(world.regions[home].actors[actor].cell)
	var heat_tenths: int = 0
	var heat_supported: bool = true
	var heat_reason: String = ""
	var heat: RefCounted = _thermal()
	if heat is SimWorldEnvironmentFields and now < world.elapsed_ms:
		# We retain exposure samples, not complete historical actor positions
		# and every old field segment. Never combine today's offset with an old
		# climate timestamp and present that mixture as a historical fact.
		heat_supported = false
		heat_reason = "history_unavailable"
	elif heat is SimWorldEnvironmentFields or now > world.elapsed_ms and heat != null:
		var projected: Dictionary = heat.project_tenths(cell, now)
		heat_supported = bool(projected.supported)
		if heat_supported:
			heat_tenths = int(projected.value)
		else:
			heat_reason = str(projected.reason)
	else:
		heat_tenths = _current_heat_tenths(cell)
	var background: int = _temperature(region, now)
	if not heat_supported:
		# A long forecast has no single temperature or burden: future sources
		# may make its local offset either positive or negative.
		return {"region": region, "temperature_min_tenths": background + _minimum_heat_tenths(),
			"temperature_max_tenths": background + _maximum_heat_tenths(),
			"heat_supported": false, "heat_reason": heat_reason, "feeling": "此时冷暖仍需临近观察"}
	var temperature: int = background + heat_tenths
	var burden: Dictionary = SimClimateRules.burden(definitions, temperature, insulation_for(actor))
	var feeling: String = "冷暖适宜"
	if int(burden.cold_tenths) > 0:
		feeling = "寒意侵身，现有衣物不足御寒"
	elif int(burden.hot_tenths) > 0:
		feeling = "暑气逼人，容易疲倦"
	if heat_tenths > 0:
		feeling += "，近旁留有暖意"
	elif heat_tenths < 0:
		feeling += "，近旁留有寒意"
	return {"region": region, "temperature_tenths": temperature, "temperature_min_tenths": temperature,
		"temperature_max_tenths": temperature, "heat_supported": true, "heat_tenths": heat_tenths,
		"feeling": feeling, "burden_rate": int(burden.energy_rate)}


func energy_rate(actor: String) -> int:
	return int(samples.get(actor, {}).get("energy_rate", 0))


func warmer_outer(actor: String, type: String, wet: int, at_ms: int) -> bool:
	var conditions: Dictionary = local_conditions(actor, at_ms)
	if conditions.is_empty():
		return false
	var current: int = insulation_for(actor)
	var improved: int = current + SimClimateRules.insulation_at(definitions, type, wet)
	if not bool(conditions.heat_supported):
		# If cold and more effective insulation are both possible, ask again at
		# the actual time. Rate caps and rounding may still make it unnecessary.
		var maximum: int = int(definitions.human.max_insulation_tenths)
		var warmth: int = clampi(current, 0, maximum)
		return clampi(improved, 0, maximum) > warmth and int(conditions.temperature_min_tenths) < int(definitions.human.comfort_min_tenths) - warmth
	if int(conditions.burden_rate) == 0:
		return false
	return int(SimClimateRules.burden(definitions, int(conditions.temperature_tenths), improved).energy_rate) < int(conditions.burden_rate)


func cooler_without_outer(actor: String, type: String, wet: int, at_ms: int) -> bool:
	var conditions: Dictionary = local_conditions(actor, at_ms)
	if conditions.is_empty():
		return false
	var current: int = insulation_for(actor)
	var reduced: int = maxi(0, current - SimClimateRules.insulation_at(definitions, type, wet))
	if not bool(conditions.heat_supported):
		# A possible hot burden can warrant a later recheck; endpoints alone
		# cannot prove an energy-rate improvement under caps and rounding.
		var maximum: int = int(definitions.human.max_insulation_tenths)
		var warmth: int = clampi(current, 0, maximum)
		@warning_ignore("integer_division")
		var hot_threshold: int = int(definitions.human.comfort_max_tenths) - warmth * int(definitions.human.insulation_heat_percent) / 100
		return clampi(reduced, 0, maximum) < warmth and int(conditions.temperature_max_tenths) > hot_threshold
	var temperature: int = int(conditions.temperature_tenths)
	var burden: Dictionary = SimClimateRules.burden(definitions, temperature, current)
	if int(burden.hot_tenths) <= 0:
		return false
	return int(SimClimateRules.burden(definitions, temperature, reduced).energy_rate) < int(burden.energy_rate)


func _first_boundary() -> int:
	if activation_ms > SimInventory.MAX_COUNT - MINUTE_MS:
		return SimInventory.MAX_COUNT
	var complete: int = activation_ms + MINUTE_MS
	var remainder: int = posmod(complete, MINUTE_MS)
	return mini(SimInventory.MAX_COUNT, complete + (MINUTE_MS - remainder if remainder > 0 else 0))


func next_boundary_ms() -> int:
	return _first_boundary() if last_pulse_ms == activation_ms else mini(SimInventory.MAX_COUNT, last_pulse_ms + MINUTE_MS)


func settle_at_ms(now: int) -> void:
	if now < next_boundary_ms() or now - activation_ms < MINUTE_MS or posmod(now, MINUTE_MS) != 0:
		return
	var affected_regions: Dictionary = {}
	for home: String in world._sorted_keys(world.regions):
		var sim: VillageSimulation = world.regions[home]
		var affected: bool = false
		for actor: String in world._sorted_keys(sim.actors):
			if energy_rate(actor) > 0 or not _neutral_everywhere(now, insulation_for(actor)):
				affected = true
				break
		# No time-varying callback: old cached exposure settles first, then all
		# new samples in this region become effective for future intervals.
		if affected:
			world.synchronize_region(home)
			affected_regions[home] = true
	# All original bodies first settle their old cached rate. Only then freeze
	# the one historical thermal sample after this timestamp's real effects.
	var heat: RefCounted = _thermal()
	if heat != null and not heat.mark_sample(now):
		return
	for home: String in world._sorted_keys(world.regions):
		var sim: VillageSimulation = world.regions[home]
		for actor: String in world._sorted_keys(sim.actors):
			samples[actor] = sample_for(actor, now)
		if affected_regions.has(home):
			world.invalidate_region(home)
	last_pulse_ms = now


func to_dict() -> Dictionary:
	return {"version": VERSION, "rules_version": int(definitions.version), "activation_ms": activation_ms,
		"last_pulse_ms": last_pulse_ms, "samples": samples.duplicate(true)}


func restore(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "rules_version", "activation_ms", "last_pulse_ms", "samples"]) or data.version != VERSION or data.rules_version != definitions.version or not Shape.count(data.activation_ms, 0, world.elapsed_ms) or not Shape.count(data.last_pulse_ms, int(data.activation_ms), world.elapsed_ms) or not data.samples is Dictionary:
		return false
	var latest: int = world.elapsed_ms - posmod(world.elapsed_ms, MINUTE_MS)
	var initial: bool = latest - int(data.activation_ms) < MINUTE_MS
	var expected: int = int(data.activation_ms) if initial else latest
	if int(data.last_pulse_ms) != expected:
		return false
	var actors: Array[String] = world._actor_ids(world.regions)
	if expected == int(data.activation_ms):
		if not data.samples.is_empty():
			return false
	elif data.samples.size() != actors.size():
		return false
	else:
		for actor: String in actors:
			if not data.samples.has(actor) or not _valid_sample(actor, data.samples[actor], expected):
				return false
	activation_ms = int(data.activation_ms)
	last_pulse_ms = int(data.last_pulse_ms)
	samples = data.samples.duplicate(true)
	return true


func _valid_sample(actor: String, sample: Variant, at_ms: int) -> bool:
	var minimum_heat: int = _minimum_heat_tenths()
	var maximum_heat: int = _maximum_heat_tenths()
	if not Shape.keys(sample, ["at_ms", "cell", "region", "temperature_tenths", "heat_tenths", "garments", "insulation_tenths", "energy_rate"]) or not Shape.count(sample.at_ms, at_ms, at_ms) or not sample.garments is Array or sample.garments.size() > 2 or not sample.region is String or not Shape.count(sample.temperature_tenths, -10000 + minimum_heat, 10000 + maximum_heat) or not Shape.count(sample.heat_tenths, minimum_heat, maximum_heat) or not Shape.count(sample.insulation_tenths, 0, 2000) or not Shape.count(sample.energy_rate, 0, int(definitions.human.max_energy_rate)):
		return false
	if not Shape.count(int(sample.temperature_tenths) - int(sample.heat_tenths), -10000, 10000):
		return false
	var heat: RefCounted = _thermal()
	if heat is SimWorldEnvironmentFields:
		# Current field archives cannot borrow or invent an exposure sampled
		# before their own activation. The latest observation must match the
		# field's preserved sample, even if its current target has since changed.
		if at_ms < int(heat.activation_ms) or at_ms != int(heat.last_sample_ms):
			return false
	elif heat != null and at_ms >= int(heat.activation_ms) and at_ms != int(heat.last_sample_ms):
		return false
	var slots: Dictionary = {}
	for garment: Variant in sample.garments:
		if not Shape.keys(garment, ["id", "type", "wet"]) or not garment.id is String or not world.clothing.objects.has(garment.id) or not garment.type is String or not definitions.garments.has(garment.type) or not Shape.count(garment.wet, 0, 100):
			return false
		var object: Dictionary = world.clothing.objects[garment.id]
		if object.owner != actor or object.type != garment.type:
			return false
		var slot: String = str(world.clothing.definitions.types[garment.type].slot)
		if slots.has(slot):
			return false
		slots[slot] = true
	var insulation: int = _insulation(sample.garments)
	var actual: Array[Dictionary] = _garments_at(actor, at_ms)
	if actual.size() != sample.garments.size():
		return false
	for index: int in actual.size():
		if not Shape.same_record(sample.garments[index], actual[index]):
			return false
	if insulation != int(sample.insulation_tenths):
		return false
	if sample.region.is_empty():
		return sample.cell is Array and sample.cell.is_empty() and int(sample.temperature_tenths) == 0 and int(sample.heat_tenths) == 0 and int(sample.energy_rate) == 0 and _neutral_everywhere(at_ms, insulation, true)
	if not Shape.cell_valid(sample.cell) or SimClimateRules.region_at(definitions, SimRouteTravel.cell(sample.cell)) != sample.region:
		return false
	if heat is SimWorldEnvironmentFields and not bool(heat.sample_result(SimRouteTravel.cell(sample.cell), at_ms).get("supported", false)):
		return false
	var heat_tenths: int = _sample_heat_tenths(SimRouteTravel.cell(sample.cell), at_ms)
	var temperature: int = _temperature(str(sample.region), at_ms) + heat_tenths
	return heat_tenths == int(sample.heat_tenths) and temperature == int(sample.temperature_tenths) and int(SimClimateRules.burden(definitions, temperature, insulation).energy_rate) == int(sample.energy_rate)
