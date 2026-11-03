class_name SimHerbEcologyRules
extends RefCounted
## One-millisecond discrete water law, integrated in batches only until the
## next actual threshold. Water is integer micro-units; progress is water-work.
## A normal warm wet millisecond absorbs uptake_per_ms units and advances that
## much work. The last dry millisecond absorbs only water that really remains.
## Moisture hysteresis prevents a weak rain from repeatedly toggling growth.
## Rain is atmospheric input at this patch, not inventory water or spring rain.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const MAX_COUNT: int = SimInventory.MAX_COUNT
const STATE_KEYS: Array[String] = ["version", "rules_version", "activation_ms", "last_ms", "sample_ms", "temperature_tenths", "heat_tenths", "rain", "water", "wet", "progress", "rain_input", "irrigated", "evaporated", "absorbed", "overflow", "discarded_progress", "base_produced", "irrigation_receipts"]


static func valid_definitions(rules: Variant) -> bool:
	if not Shape.keys(rules, ["version", "sample_ms", "temperature_min_tenths", "temperature_max_tenths", "default_temperature_tenths", "soil_capacity", "initial_water", "resume_water", "water_per_item", "rain_per_ms", "evaporation_per_ms", "uptake_per_ms", "growth_ms", "counter_limit"]) or rules.version != 1 or rules.sample_ms != 60000:
		return false
	for field: String in ["temperature_min_tenths", "temperature_max_tenths", "default_temperature_tenths"]:
		if not Shape.count(rules[field], -10000, 10000):
			return false
	if int(rules.temperature_min_tenths) >= int(rules.temperature_max_tenths) or not Shape.count(rules.counter_limit, 1000000000, MAX_COUNT):
		return false
	if not Shape.count(rules.soil_capacity, 1, 1000000000000) or not Shape.count(rules.initial_water, 0, int(rules.soil_capacity)) or not Shape.count(rules.resume_water, 1, int(rules.soil_capacity)) or not Shape.count(rules.water_per_item, 1, 1000000000000):
		return false
	if not Shape.count(rules.rain_per_ms, 0, 10000) or not Shape.count(rules.evaporation_per_ms, 0, 10000) or not Shape.count(rules.uptake_per_ms, 1, 10000) or not Shape.count(rules.growth_ms, 60000, 864000000):
		return false
	return int(rules.growth_ms) * int(rules.uptake_per_ms) <= int(rules.counter_limit) and int(rules.soil_capacity) <= int(rules.counter_limit) and int(rules.water_per_item) <= int(rules.counter_limit)


static func empty_state(rules: Dictionary, at_ms: int, base_produced: int = 0, conditions: Dictionary = {}) -> Dictionary:
	var water: int = int(rules.initial_water)
	return {"version": 1, "rules_version": int(rules.version), "activation_ms": at_ms,
		"last_ms": at_ms, "sample_ms": at_ms,
		"temperature_tenths": int(conditions.get("temperature_tenths", rules.default_temperature_tenths)),
		"heat_tenths": int(conditions.get("heat_tenths", 0)), "rain": bool(conditions.get("rain", false)),
		"water": water, "wet": water >= int(rules.resume_water), "progress": 0,
		"rain_input": 0, "irrigated": 0, "evaporated": 0, "absorbed": 0, "overflow": 0,
		"discarded_progress": 0, "base_produced": base_produced, "irrigation_receipts": {}}


static func next_sample_ms(state: Dictionary, rules: Dictionary) -> int:
	var step: int = int(rules.sample_ms)
	if int(state.sample_ms) == int(state.activation_ms):
		if int(state.activation_ms) > MAX_COUNT - step:
			return MAX_COUNT
		var complete: int = int(state.activation_ms) + step
		var remainder: int = posmod(complete, step)
		return mini(MAX_COUNT, complete + (step - remainder if remainder > 0 else 0))
	return mini(MAX_COUNT, int(state.sample_ms) + step)


static func temperature_valid(temperature: Variant, heat: Variant) -> bool:
	return Shape.count(heat, 0, MAX_COUNT - 10000) and Shape.count(temperature, -10000, MAX_COUNT) and int(temperature) - int(heat) >= -10000 and int(temperature) - int(heat) <= 10000


static func warm(state: Dictionary, rules: Dictionary) -> bool:
	return int(state.temperature_tenths) >= int(rules.temperature_min_tenths) and int(state.temperature_tenths) <= int(rules.temperature_max_tenths)


static func growth_work(rules: Dictionary) -> int:
	return int(rules.growth_ms) * int(rules.uptake_per_ms)


static func produced_after_activation(state: Dictionary, rules: Dictionary) -> int:
	# Account for fractional final dry milliseconds without rounding growth up.
	@warning_ignore("integer_division")
	return (int(state.absorbed) - int(state.progress) - int(state.discarded_progress)) / growth_work(rules)


static func _wet(state: Dictionary, rules: Dictionary) -> void:
	if int(state.water) == 0:
		state.wet = false
	elif int(state.water) >= int(rules.resume_water):
		state.wet = true


static func _rates(state: Dictionary, rules: Dictionary, stock: int, capacity: int) -> Array[int]:
	var limit: int = int(rules.counter_limit)
	var rain: int = mini(int(rules.rain_per_ms) if state.rain else 0, limit - int(state.rain_input))
	var evaporation: int = mini(mini(int(rules.evaporation_per_ms), limit - int(state.evaporated)), int(state.water) + rain)
	var can_grow: bool = bool(state.wet) and warm(state, rules) and stock < capacity and int(state.base_produced) + produced_after_activation(state, rules) < MAX_COUNT
	var uptake: int = mini(mini(int(rules.uptake_per_ms), limit - int(state.absorbed)), int(state.water) + rain - evaporation) if can_grow else 0
	var overflow: int = maxi(0, int(state.water) + rain - evaporation - uptake - int(rules.soil_capacity))
	# At extreme ledger saturation, unaccepted atmospheric input never enters
	# the soil or a claimed rainfall account. Normal play is far below this.
	if overflow > limit - int(state.overflow):
		rain -= overflow - (limit - int(state.overflow))
		evaporation = mini(evaporation, int(state.water) + rain)
		uptake = mini(uptake, int(state.water) + rain - evaporation)
		overflow = maxi(0, int(state.water) + rain - evaporation - uptake - int(rules.soil_capacity))
	return [rain, evaporation, uptake, overflow]


static func _bounded_duration(duration: int, remaining: int, rate: int) -> int:
	if rate <= 0:
		return duration
	@warning_ignore("integer_division")
	return mini(duration, maxi(1, remaining / rate))


static func _step_duration(state: Dictionary, rules: Dictionary, stock: int, capacity: int, rates: Array[int], requested: int) -> int:
	var duration: int = requested
	var limit: int = int(rules.counter_limit)
	for index: int in range(4):
		var field: String = ["rain_input", "evaporated", "absorbed", "overflow"][index]
		duration = _bounded_duration(duration, limit - int(state[field]), rates[index])
	var net: int = rates[0] - rates[1] - rates[2]
	if net < 0:
		duration = _bounded_duration(duration, int(state.water), -net)
	elif net > 0 and int(state.water) < int(rules.soil_capacity):
		duration = _bounded_duration(duration, int(rules.soil_capacity) - int(state.water), net)
		if not state.wet and int(state.water) < int(rules.resume_water):
			duration = _bounded_duration(duration, int(rules.resume_water) - int(state.water), net)
	if rates[2] > 0 and stock < capacity:
		duration = _bounded_duration(duration, growth_work(rules) - int(state.progress), rates[2])
	return duration


static func advance(previous: Dictionary, rules: Dictionary, at_ms: int, initial_stock: int, capacity: int) -> Dictionary:
	if not Shape.count(at_ms, int(previous.last_ms), MAX_COUNT) or not Shape.count(initial_stock, 0, capacity):
		return {}
	var state: Dictionary = previous.duplicate(true)
	var stock: int = initial_stock
	var produced: int = 0
	while int(state.last_ms) < at_ms:
		_wet(state, rules)
		if stock >= capacity and int(state.progress) > 0:
			state.discarded_progress = int(state.discarded_progress) + int(state.progress)
			state.progress = 0
		var rates: Array[int] = _rates(state, rules, stock, capacity)
		var duration: int = _step_duration(state, rules, stock, capacity, rates, at_ms - int(state.last_ms))
		var rain: int = rates[0] * duration
		var evaporation: int = rates[1] * duration
		var uptake: int = rates[2] * duration
		var water: int = int(state.water) + rain - evaporation - uptake
		var overflow: int = maxi(0, water - int(rules.soil_capacity))
		state.water = water - overflow
		state.rain_input = int(state.rain_input) + rain
		state.evaporated = int(state.evaporated) + evaporation
		state.absorbed = int(state.absorbed) + uptake
		state.overflow = int(state.overflow) + overflow
		state.progress = int(state.progress) + uptake
		state.last_ms = int(state.last_ms) + duration
		var target: int = growth_work(rules)
		if int(state.progress) >= target and stock < capacity:
			state.progress = int(state.progress) - target
			stock += 1
			produced += 1
		if stock >= capacity and int(state.progress) > 0:
			state.discarded_progress = int(state.discarded_progress) + int(state.progress)
			state.progress = 0
		_wet(state, rules)
	return {"state": state, "stock": stock, "produced": produced}


static func next_boundary_ms(state: Dictionary, rules: Dictionary, stock: int, capacity: int) -> int:
	var current: Dictionary = state.duplicate(true)
	_wet(current, rules)
	var rates: Array[int] = _rates(current, rules, stock, capacity)
	var duration: int = _step_duration(current, rules, stock, capacity, rates, MAX_COUNT - int(state.last_ms))
	return mini(MAX_COUNT, int(state.last_ms) + duration) if duration > 0 else MAX_COUNT


static func with_irrigation(previous: Dictionary, rules: Dictionary, action_id: String, actor: String, amount: int, at_ms: int) -> Dictionary:
	if not SimInventory._nonempty(action_id) or not SimInventory._nonempty(actor) or amount != 1 or at_ms != int(previous.last_ms):
		return {}
	var units: int = int(rules.water_per_item)
	var receipt: Dictionary = {"actor": actor, "at_ms": at_ms, "amount": amount, "water_units": units}
	if previous.irrigation_receipts.has(action_id):
		return previous.duplicate(true) if Shape.same_record(previous.irrigation_receipts[action_id], receipt) else {}
	var excess: int = maxi(0, int(previous.water) + units - int(rules.soil_capacity))
	if int(previous.irrigated) > int(rules.counter_limit) - units or int(previous.overflow) > int(rules.counter_limit) - excess:
		return {}
	var state: Dictionary = previous.duplicate(true)
	state.water = int(state.water) + units - excess
	state.irrigated = int(state.irrigated) + units
	state.overflow = int(state.overflow) + excess
	state.irrigation_receipts[action_id] = receipt
	_wet(state, rules)
	return state


static func valid_state(state: Variant, rules: Dictionary, produced: int, at_ms: int) -> bool:
	if not Shape.keys(state, STATE_KEYS) or state.version != 1 or state.rules_version != rules.version or not Shape.count(state.activation_ms, 0, at_ms) or not Shape.count(state.last_ms, int(state.activation_ms), at_ms) or int(state.last_ms) != at_ms:
		return false
	if not Shape.count(state.sample_ms, int(state.activation_ms), at_ms) or state.sample_ms != state.activation_ms and posmod(int(state.sample_ms), int(rules.sample_ms)) != 0 or not temperature_valid(state.temperature_tenths, state.heat_tenths) or not state.rain is bool or not state.wet is bool:
		return false
	if not Shape.count(state.water, 0, int(rules.soil_capacity)) or not Shape.count(state.progress, 0, growth_work(rules) - 1) or not Shape.count(state.base_produced, 0, produced) or not state.irrigation_receipts is Dictionary:
		return false
	for field: String in ["rain_input", "irrigated", "evaporated", "absorbed", "overflow", "discarded_progress"]:
		if not Shape.count(state[field], 0, int(rules.counter_limit)):
			return false
	if int(state.water) == 0 and state.wet or int(state.water) >= int(rules.resume_water) and not state.wet:
		return false
	if int(rules.initial_water) + int(state.rain_input) + int(state.irrigated) != int(state.water) + int(state.evaporated) + int(state.absorbed) + int(state.overflow):
		return false
	var grown: int = produced - int(state.base_produced)
	@warning_ignore("integer_division")
	var maximum_grown: int = int(rules.counter_limit) / growth_work(rules)
	if grown > maximum_grown or int(state.absorbed) != grown * growth_work(rules) + int(state.progress) + int(state.discarded_progress):
		return false
	var duration: int = at_ms - int(state.activation_ms)
	if not _within_rate(int(state.rain_input), int(rules.rain_per_ms), duration) or not _within_rate(int(state.evaporated), int(rules.evaporation_per_ms), duration) or not _within_rate(int(state.absorbed), int(rules.uptake_per_ms), duration):
		return false
	var irrigation_sum: int = 0
	for action: Variant in state.irrigation_receipts:
		var row: Variant = state.irrigation_receipts[action]
		if not SimInventory._nonempty(action) or not Shape.keys(row, ["actor", "at_ms", "amount", "water_units"]) or not SimInventory._nonempty(row.actor) or not Shape.count(row.at_ms, int(state.activation_ms), at_ms) or row.amount != 1 or row.water_units != rules.water_per_item:
			return false
		irrigation_sum += int(row.water_units)
		if irrigation_sum > int(rules.counter_limit):
			return false
	return irrigation_sum == int(state.irrigated)


static func _within_rate(amount: int, rate: int, duration: int) -> bool:
	if amount == 0:
		return true
	if rate == 0:
		return false
	# Divide rather than multiply an arbitrarily long world age by a rate.
	@warning_ignore("integer_division")
	return (amount - 1) / rate + 1 <= duration
