class_name SimLandResources
extends RefCounted
## Finite natural sources. Inventory owns the goods; this owns growth phase and
## source accounting. Neither growth nor opening the view delivers warehouse goods.

const VERSION: int = 5
const PREFIX: String = "resource:"
const MAX_COUNT: int = SimInventory.MAX_COUNT
const Ecology = preload("res://scripts/sim/herb_ecology_rules.gd")
const Shape = preload("res://scripts/sim/avian_schema.gd")

var sources: Dictionary = {}
var definitions: Dictionary = {}
var _owner: WeakRef
var _sim: RefCounted:
	get:
		return _owner.get_ref()


func initialize(simulation: RefCounted, rules: Dictionary) -> bool:
	if not valid_definitions(rules) or not valid_sources(simulation.config.get("resource_sources", {}), simulation.places, rules) or not valid_actions(simulation.config, rules):
		return false
	_owner = weakref(simulation)
	definitions = rules
	sources = {}
	for id: String in simulation.config.get("resource_sources", {}):
		var terms: Dictionary = terms_for(id)
		if not simulation.inventory.create_container(container_id(id), {str(terms.item): int(terms.initial)}):
			return false
		var ecology: Dictionary = Ecology.empty_state(terms.ecology, simulation.elapsed_ms) if terms.has("ecology") else {}
		var interval: int = int(terms.regrow_ms)
		var next_growth: int = mini(MAX_COUNT, simulation.elapsed_ms - posmod(simulation.elapsed_ms, interval) + interval)
		sources[id] = {"plant_id": "", "next_growth_ms": MAX_COUNT if not ecology.is_empty() else next_growth, "produced": 0, "extracted": 0, "rainfall": 0, "ecology": ecology}
	return true


static func container_id(id: String) -> String:
	return PREFIX + id


func bound_to(simulation: RefCounted) -> bool:
	return _owner != null and _owner.get_ref() == simulation


func terms_for(id: String) -> Dictionary:
	var source: Dictionary = _sim.config.get("resource_sources", {}).get(id, {})
	return definitions.types.get(str(source.get("definition", "")), {})


func next_boundary_ms() -> int:
	var next: int = 0x3fffffffffffffff
	for id: String in sources:
		if not str(sources[id].plant_id).is_empty():
			continue
		var terms: Dictionary = terms_for(id)
		if not sources[id].ecology.is_empty():
			next = mini(next, Ecology.next_boundary_ms(sources[id].ecology, terms.ecology, _sim.inventory.quantity(container_id(id), str(terms.item)), int(terms.capacity)))
			continue
		if _sim.inventory.quantity(container_id(id), terms.item) < int(terms.capacity):
			next = mini(next, int(sources[id].next_growth_ms))
	return next


func advance_to_ms(at_ms: int) -> void:
	for id: String in sources:
		if not str(sources[id].plant_id).is_empty():
			continue
		var state: Dictionary = sources[id]
		var terms: Dictionary = terms_for(id)
		if not state.ecology.is_empty():
			var result: Dictionary = Ecology.advance(state.ecology, terms.ecology, at_ms, _sim.inventory.quantity(container_id(id), str(terms.item)), int(terms.capacity))
			if not result.is_empty():
				state.ecology = result.state
				state.produced = int(state.produced) + int(result.produced)
				_sim.inventory.containers[container_id(id)][terms.item] = int(result.stock)
				_sim.inventory.contents_changed.emit(container_id(id))
			continue
		if at_ms < int(state.next_growth_ms):
			continue
		var interval: int = int(terms.regrow_ms)
		@warning_ignore("integer_division")
		var periods: int = (at_ms - int(state.next_growth_ms)) / interval + 1
		var stock: int = _sim.inventory.quantity(container_id(id), terms.item)
		var space: int = int(terms.capacity) - stock
		@warning_ignore("integer_division")
		var useful_periods: int = mini(periods, (space + int(terms.regrow_amount) - 1) / int(terms.regrow_amount))
		var gain: int = mini(space, useful_periods * int(terms.regrow_amount))
		gain = mini(gain, MAX_COUNT - int(state.produced))
		_sim.inventory.containers[container_id(id)][terms.item] = stock + gain
		_sim.inventory.contents_changed.emit(container_id(id))
		state.produced = int(state.produced) + gain
		# Full sources do not bank missed harvests. Retain the calendar phase,
		# including when a quiet/full source skips many growth pulses at once.
		state.next_growth_ms = mini(MAX_COUNT, at_ms - posmod(at_ms, interval) + interval)


func next_ecology_sample_ms() -> int:
	var result: int = MAX_COUNT
	for id: String in sources:
		if not str(sources[id].plant_id).is_empty():
			continue
		if not sources[id].ecology.is_empty():
			result = mini(result, Ecology.next_sample_ms(sources[id].ecology, terms_for(id).ecology))
	return result


func set_ecology_conditions(id: String, at_ms: int, temperature_tenths: int, rain: bool, heat_tenths: int = 0) -> bool:
	if not sources.has(id) or sources[id].ecology.is_empty() or not Ecology.temperature_valid(temperature_tenths, heat_tenths):
		return false
	var state: Dictionary = sources[id].ecology
	var rules: Dictionary = terms_for(id).ecology
	if at_ms != int(state.last_ms) or at_ms < int(state.sample_ms):
		return false
	var initial: bool = at_ms == int(state.activation_ms) and int(state.sample_ms) == at_ms
	if not initial and (at_ms != Ecology.next_sample_ms(state, rules) or posmod(at_ms, int(rules.sample_ms)) != 0):
		return false
	state.sample_ms = at_ms
	state.temperature_tenths = temperature_tenths
	state.heat_tenths = heat_tenths
	state.rain = rain
	return true


func can_irrigate(id: String) -> bool:
	return sources.has(id) and not sources[id].ecology.is_empty() and int(sources[id].ecology.water) < int(terms_for(id).ecology.soil_capacity)


func irrigate(action: Dictionary, actor_id: String, definition: Dictionary) -> bool:
	var id: String = str(definition.get("resource", ""))
	if not sources.has(id) or sources[id].ecology.is_empty() or not _sim.has_actor(actor_id) or definition.get("kind") != "irrigate" or definition.get("item") != "water" or definition.get("amount") != 1:
		return false
	var state: Dictionary = sources[id].ecology
	var rules: Dictionary = terms_for(id).ecology
	var action_id: String = str(action.get("id", ""))
	var operation: String = action_id + ":irrigate"
	var bag: String = "actor:" + actor_id
	var request: Dictionary = {"kind": "consume", "container": bag, "item": "water", "amount": 1}
	if state.irrigation_receipts.has(action_id):
		return state.irrigation_receipts[action_id].actor == actor_id and _sim.inventory.operations.has(operation) and Shape.same_record(_sim.inventory.operations[operation], request)
	var place: String = str(_sim.config.resource_sources[id].place)
	var body: Dictionary = _sim.actor_state(actor_id)
	var reservation: String = action_id + ":water"
	if int(state.last_ms) != int(_sim.elapsed_ms) or not SimInventory._nonempty(action_id) or action.get("phase") != "work" or bool(action.get("carrying", true)) or not action.get("reservations") is Array or action.reservations.size() != 1 or action.reservations[0] != reservation or definition.get("target") != place:
		return false
	if not _sim.actor_controls(actor_id, "action") or not _sim.actor_controls(actor_id, "motion") or body.active.get("id") != action_id or _sim.actor_position(body).distance_to(TileGrid.cell_to_world(SimRouteTravel.cell(_sim.places[place].cell))) > 0.001:
		return false
	var promised: Dictionary = {"container": bag, "item": "water", "amount": 1, "owner_id": actor_id}
	if not _sim.inventory.reservations.has(reservation) or not Shape.same_record(_sim.inventory.reservations[reservation], promised) or _sim.inventory.operations.has(operation):
		return false
	var candidate: Dictionary = Ecology.with_irrigation(state, rules, action_id, actor_id, 1, int(_sim.elapsed_ms))
	if candidate.is_empty():
		return false
	# The candidate inventory proves private disposal after releasing exactly
	# this action's reservation. Retain the original inventory object itself.
	var inventory := SimInventory.new()
	if not inventory.restore(_sim.inventory.to_dict()):
		return false
	inventory.release(reservation)
	if not inventory.consume(operation, bag, "water", 1):
		return false
	_sim.inventory.containers = inventory.containers
	_sim.inventory.reservations = inventory.reservations
	_sim.inventory.operations = inventory.operations
	_sim.inventory.custody = inventory.custody
	_sim.inventory.contents_changed.emit(bag)
	state.assign(candidate)
	return true


func extract(action: Dictionary, actor_id: String, definition: Dictionary) -> bool:
	var id: String = str(definition.resource)
	if not sources.has(id) or action.reservations.size() != 1:
		return false
	var amount: int = int(definition.amount)
	var operation: String = str(action.id) + ":harvest"
	var already: bool = _sim.inventory.operations.has(operation)
	if not already and amount > MAX_COUNT - int(sources[id].extracted):
		return false
	if not _sim.inventory.transfer(operation, container_id(id), "actor:" + actor_id,
		str(definition.item), amount, str(action.reservations[0])):
		return false
	if not already:
		sources[id].extracted = int(sources[id].extracted) + amount
	return true


func receive_rain(id: String, amount: int) -> void:
	if not sources.has(id) or _sim.config.resource_sources[id].definition != "spring" or amount <= 0:
		return
	var terms: Dictionary = terms_for(id)
	var stock: int = _sim.inventory.quantity(container_id(id), str(terms.item))
	var gain: int = mini(mini(amount, int(terms.capacity) - stock), MAX_COUNT - int(sources[id].rainfall))
	_sim.inventory.containers[container_id(id)][terms.item] = stock + gain
	_sim.inventory.contents_changed.emit(container_id(id))
	sources[id].rainfall = int(sources[id].rainfall) + gain


func describe(actor_id: String, id: String) -> String:
	if not sources.has(id) or not _sim.has_actor(actor_id):
		return ""
	var terms: Dictionary = terms_for(id)
	var place: String = str(_sim.config.resource_sources[id].place)
	var nearby: bool = _sim.actor_position(_sim.actor_state(actor_id)).distance_to(
		TileGrid.cell_to_world(Vector2i(int(_sim.places[place].cell[0]), int(_sim.places[place].cell[1])))) <= float(_sim.config.observation_radius) * TileGrid.TILE_SIZE
	if not nearby:
		return str(terms.description) + " 眼下离得远，看不清可采情形。"
	var stock: int = _sim.inventory.quantity(container_id(id), terms.item)
	var line: String = str(terms.description) + (" 近处可见还有可采之物。" if stock > 0 else " 近处已采空，须等它自然恢复。")
	if not sources[id].ecology.is_empty():
		var ecology: Dictionary = sources[id].ecology
		# A few mature leaves do not hide the soil and current new-growth
		# conditions. All clues remain local, qualitative and independent.
		if int(ecology.water) == 0:
			line += " 土面发干，叶片微卷。"
		elif not ecology.wet:
			line += " 土面略有湿意，叶片仍待缓过来。"
		else:
			line += " 土中尚有湿意。"
		if not Ecology.warm(ecology, terms.ecology):
			line += " 冷暖不合，嫩叶暂歇着不长。"
		elif int(ecology.water) > 0 and ecology.wet and stock < int(terms.capacity):
			line += " 细嫩新叶正在舒展。"
	return line


func ecology_observation(id: String) -> Dictionary:
	if not sources.has(id) or sources[id].ecology.is_empty():
		return {}
	var terms: Dictionary = terms_for(id)
	if _sim.inventory.quantity(container_id(id), str(terms.item)) > 0:
		return {"phase": "harvestable"}
	var state: Dictionary = sources[id].ecology
	if int(state.water) == 0:
		return {"phase": "dry"}
	if not Ecology.warm(state, terms.ecology):
		return {"phase": "dormant"}
	return {"phase": "growing"}


func to_dict() -> Dictionary:
	return {"version": VERSION, "sources": sources.duplicate(true)}


func bind_restored(simulation: RefCounted, rules: Dictionary, state: Dictionary) -> void:
	# The complete candidate has passed valid_state before the caller commits it.
	_owner = weakref(simulation)
	definitions = rules
	sources = state.sources.duplicate(true)
	# JSON decodes whole numbers as floats. Preserve every declared integer
	# before another serialization, especially the exact MAX_COUNT sentinel;
	# formatting its decoded float repeatedly can lose the final decimal unit.
	for source: Dictionary in sources.values():
		for field: String in ["next_growth_ms", "produced", "extracted", "rainfall"]:
			source[field] = int(source[field])
		var ecology: Dictionary = source.ecology
		if ecology.is_empty():
			continue
		for field: String in Ecology.STATE_KEYS:
			if field not in ["rain", "wet", "irrigation_receipts"]:
				ecology[field] = int(ecology[field])
		for receipt: Dictionary in ecology.irrigation_receipts.values():
			for field: String in ["at_ms", "amount", "water_units"]:
				receipt[field] = int(receipt[field])


static func previous_opening_config(current: Dictionary) -> Dictionary:
	# Exactly the additive P1-a content is absent in an old world. Keep every
	# other setting subject to the existing strict scenario compatibility check.
	var result: Dictionary = current.duplicate(true)
	result.erase("resource_sources")
	var removed: Array[String] = []
	for id: String in result.actions:
		if result.actions[id].kind == "gather":
			removed.append(str(result.actions[id].survey))
			removed.append(id)
		elif result.actions[id].kind in ["forage", "irrigate"]:
			removed.append(id)
	for id: String in removed:
		result.actions.erase(id)
	return result


static func opening_matches(saved: Variant, current: Dictionary) -> bool:
	if not saved is Dictionary:
		return false
	var saved_text: String = JSON.stringify(JSON.parse_string(JSON.stringify(saved)), "", true, true)
	if saved_text == JSON.stringify(JSON.parse_string(JSON.stringify(current)), "", true, true):
		return true
	if not current.get("actions") is Dictionary:
		return false
	return not saved.has("resource_sources") and saved_text == JSON.stringify(JSON.parse_string(JSON.stringify(previous_opening_config(current))), "", true, true)


static func empty_state() -> Dictionary:
	return {"version": VERSION, "sources": {}}


static func upgrade_state(previous: Dictionary, config: Dictionary, rules: Dictionary, at_ms: int, conditions: Dictionary = {}) -> Dictionary:
	if not Shape.keys(previous, ["version", "sources"]) or previous.version != 2 or not previous.sources is Dictionary:
		return {}
	var result: Dictionary = previous.duplicate(true)
	result.version = VERSION
	for id: String in result.sources:
		if not config.get("resource_sources", {}).has(id):
			return {}
		var source: Dictionary = result.sources[id]
		if not Shape.keys(source, ["next_growth_ms", "produced", "extracted", "rainfall"]):
			return {}
		var terms: Dictionary = rules.types.get(config.resource_sources[id].get("definition"), {})
		if terms.is_empty():
			return {}
		for field: String in ["next_growth_ms", "produced", "extracted", "rainfall"]:
			if not Shape.count(source[field], 0, MAX_COUNT):
				return {}
		var interval: int = int(terms.regrow_ms)
		@warning_ignore("integer_division")
		var periods: int = at_ms / interval
		if int(source.next_growth_ms) != mini(MAX_COUNT, at_ms - posmod(at_ms, interval) + interval) or int(source.produced) > periods * int(terms.regrow_amount):
			return {}
		source["plant_id"] = ""
		source.ecology = Ecology.empty_state(terms.ecology, at_ms, int(source.produced), conditions.get(id, {})) if terms.has("ecology") else {}
		if not source.ecology.is_empty():
			source.next_growth_ms = MAX_COUNT
	return result


static func valid_definitions(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not value.get("types") is Dictionary or value.types.is_empty():
		return false
	for id: Variant in value.types:
		var terms: Variant = value.types[id]
		if not _text(id) or not terms is Dictionary or not _text(terms.get("label")) or not _text(terms.get("item")) or not _text(terms.get("description")):
			return false
		for field: String in ["initial", "capacity", "regrow_ms", "regrow_amount"]:
			if not _count(terms.get(field), 0 if field == "initial" else 1):
				return false
		if int(terms.initial) > int(terms.capacity) or int(terms.capacity) > 1000000 or int(terms.regrow_ms) < 60000 or int(terms.regrow_ms) > 864000000 or int(terms.regrow_amount) > int(terms.capacity):
			return false
		if terms.has("ecology") and (id != "wild_herbs" or not Ecology.valid_definitions(terms.ecology)):
			return false
	return true


static func valid_sources(value: Variant, places: Dictionary, rules: Dictionary) -> bool:
	if not value is Dictionary:
		return false
	for id: Variant in value:
		var entry: Variant = value[id]
		if not _text(id) or str(id).contains(":") or not entry is Dictionary or entry.size() != 2 or not rules.types.has(entry.get("definition")) or not places.has(entry.get("place")):
			return false
	return true


static func valid_state(value: Variant, config: Dictionary, places: Dictionary, inventory: SimInventory, at_ms: int, rules: Dictionary, rainfall_limit: int = 0) -> bool:
	if not value is Dictionary or value.size() != 2 or value.get("version") != VERSION or not value.get("sources") is Dictionary:
		return false
	var entries: Dictionary = config.get("resource_sources", {})
	if not valid_sources(entries, places, rules) or not valid_actions(config, rules) or entries.size() != value.sources.size():
		return false
	for id: String in entries:
		var terms: Dictionary = rules.types[entries[id].definition]
		var state: Variant = value.sources.get(id)
		var container: String = container_id(id)
		if not Shape.keys(state, ["plant_id", "next_growth_ms", "produced", "extracted", "rainfall", "ecology"]) or not inventory.containers.has(container) or inventory.containers[container].size() != 1:
			return false
		for field: String in ["next_growth_ms", "produced", "extracted", "rainfall"]:
			if not _count(state.get(field)):
				return false
		var interval: int = int(terms.regrow_ms)
		if not state.plant_id is String:
			return false
		var delegated: bool = not state.plant_id.is_empty()
		if delegated and (state.next_growth_ms != MAX_COUNT or state.ecology != {}):
			return false
		var managed: bool = terms.has("ecology") and not delegated
		if managed and (state.next_growth_ms != MAX_COUNT or not Ecology.valid_state(state.ecology, terms.ecology, int(state.produced), at_ms)) or not managed and (not state.ecology is Dictionary or not state.ecology.is_empty()):
			return false
		if not managed and not delegated and int(state.next_growth_ms) != mini(MAX_COUNT, at_ms - posmod(at_ms, interval) + interval):
			return false
		var amount: int = inventory.quantity(container, terms.item)
		if int(state.rainfall) > rainfall_limit or int(state.rainfall) > 0 and entries[id].definition != "spring":
			return false
		if not inventory.containers[container].has(terms.item) or amount > int(terms.capacity) or int(state.extracted) > int(terms.initial) + int(state.produced) + int(state.rainfall) or amount != int(terms.initial) + int(state.produced) + int(state.rainfall) - int(state.extracted):
			return false
		@warning_ignore("integer_division")
		var periods: int = (int(state.ecology.activation_ms) if managed else at_ms) / interval
		var historical_produced: int = int(state.ecology.base_produced) if managed else int(state.produced)
		if not delegated and historical_produced > periods * int(terms.regrow_amount):
			return false
		var extracted: int = 0
		for operation_id: String in inventory.operations:
			var operation: Dictionary = inventory.operations[operation_id]
			if operation.get("source") != container:
				continue
			if operation.kind != "transfer" or operation.item != terms.item or not str(operation.target).begins_with("actor:") or not operation_id.ends_with(":harvest") or int(operation.amount) > MAX_COUNT - extracted:
				return false
			extracted += int(operation.amount)
		if extracted != int(state.extracted):
			return false
		if managed and not _valid_irrigation_receipts(state.ecology, inventory):
			return false
	var referenced: Dictionary = {}
	for source: Dictionary in value.sources.values():
		if not source.ecology.is_empty():
			for action: String in source.ecology.irrigation_receipts:
				if referenced.has(action):
					return false
				referenced[action] = true
	for operation: String in inventory.operations:
		if operation.ends_with(":irrigate") and not referenced.has(operation.trim_suffix(":irrigate")):
			return false
	return true


static func _valid_irrigation_receipts(state: Dictionary, inventory: SimInventory) -> bool:
	for action: String in state.irrigation_receipts:
		var row: Dictionary = state.irrigation_receipts[action]
		var operation: String = action + ":irrigate"
		var expected: Dictionary = {"kind": "consume", "container": "actor:" + str(row.actor), "item": "water", "amount": int(row.amount)}
		if not inventory.operations.has(operation) or not Shape.same_record(inventory.operations[operation], expected):
			return false
	return true


static func valid_actions(config: Dictionary, rules: Dictionary) -> bool:
	var entries: Dictionary = config.get("resource_sources", {})
	for action: Dictionary in config.actions.values():
		if action.kind not in ["gather", "forage", "irrigate"]:
			continue
		if not entries.has(action.get("resource")) or not rules.types.has(entries[action.resource].get("definition")):
			return false
		var terms: Dictionary = rules.types[entries[action.resource].definition]
		if action.kind == "irrigate":
			if entries[action.resource].definition != "wild_herbs" or not terms.has("ecology") or action.get("target") != entries[action.resource].place or action.get("item") != "water" or action.get("amount") != 1 or action.get("minutes") != 2 or action.get("contribution") != 0:
				return false
			continue
		if action.get("item") != terms.item or not _count(action.get("amount"), 1) or int(action.amount) > int(terms.capacity):
			return false
	return true


static func _text(value: Variant) -> bool:
	return SimInventory._nonempty(value)


static func _count(value: Variant, minimum: int = 0) -> bool:
	return SimInventory._valid_count(value) and int(value) >= minimum
