extends RefCounted
## Constant-condition ecology is a pure water/work law. Original inventory
## quantities and irrigation consumes are exercised with one small authority.

const Rules = preload("res://scripts/sim/herb_ecology_rules.gd")
const Land = preload("res://scripts/sim/land_resources.gd")


class Authority extends RefCounted:
	var elapsed_ms: int = 0
	var inventory := SimInventory.new()
	var actors: Dictionary = {"player": {"active": {}, "cell": [10, 10]}}
	var places: Dictionary = {"garden": {"cell": [10, 10]}, "store": {"cell": [12, 10]}}
	var config: Dictionary = {"observation_radius": 5,
		"resource_sources": {"herb_slope": {"definition": "wild_herbs", "place": "garden"}, "woodlot": {"definition": "woodland", "place": "store"}},
		"actions": {"irrigate_herb": {"kind": "irrigate", "resource": "herb_slope", "target": "garden", "item": "water", "amount": 1, "minutes": 2, "contribution": 0}}}


	func actor_controls(_actor: String, _channel: String) -> bool:
		return true


	func has_actor(id: Variant) -> bool:
		return actors.has(id)

	func actor_state(id: String) -> Dictionary:
		return actors.get(id, {})


	func actor_position(body: Dictionary) -> Vector2:
		return TileGrid.cell_to_world(Vector2i(int(body.cell[0]), int(body.cell[1])))


func run(runner: Object) -> void:
	_definitions(runner)
	_thresholds_and_drought(runner)
	_cold_and_old_cache(runner)
	_rain_fullness_and_split(runner)
	_irrigation_and_real_inventory(runner)
	_legacy_activation(runner)
	_exact_small_step_law(runner)
	_repeated_json_integer_contract(runner)
	_bad_state_and_extremes(runner)
	print("SCENARIO herb ecology: finite source inventory, cached future climate, exact wet/dry and growth thresholds, water/absorption work accounting, real private-water consumes and explicit legacy activation")


func _definitions_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/land_resources.json"))


func _rules() -> Dictionary:
	return _definitions_data().types.wild_herbs.ecology


func _balance(runner: Object, state: Dictionary, rules: Dictionary, produced: int, label: String) -> void:
	runner.assert_eq(int(rules.initial_water) + int(state.rain_input) + int(state.irrigated), int(state.water) + int(state.evaporated) + int(state.absorbed) + int(state.overflow), label + " conserves every soil-water micro-unit")
	runner.assert_eq(int(state.absorbed), produced * Rules.growth_work(rules) + int(state.progress) + int(state.discarded_progress), label + " derives every new herb from actual absorbed water-work")
	runner.assert_true(int(state.water) >= 0 and int(state.water) <= int(rules.soil_capacity), label + " keeps water inside finite soil capacity")


func _advance(state: Dictionary, rules: Dictionary, at_ms: int, stock: int = 0, capacity: int = 8) -> Dictionary:
	return Rules.advance(state, rules, at_ms, stock, capacity)


func _canonical(state: Dictionary) -> String:
	return JSON.stringify(state, "", true, true)


func _definitions(runner: Object) -> void:
	var rules: Dictionary = _rules()
	runner.assert_true(Rules.valid_definitions(rules) and Land.valid_definitions(_definitions_data()), "ordinary pinned source definitions include a valid finite herb ecology")
	for key: String in ["soil_capacity", "resume_water", "uptake_per_ms", "growth_ms"]:
		var bad: Dictionary = rules.duplicate(true)
		bad[key] = 0
		runner.assert_true(not Rules.valid_definitions(bad), "invalid zero ecology extent or rate is refused: " + key)
	runner.assert_true(Rules.temperature_valid(1000200, 1000000), "a real previously supported strong local heat source remains valid cached plant temperature")
	runner.assert_true(not Rules.temperature_valid(1000200, 0), "a huge plant temperature cannot masquerade as an unsupported outdoor climate")
	runner.assert_eq(Rules.next_sample_ms(Rules.empty_state(rules, 1234), rules), 120000, "fractional legacy activation requires a full minute before its first globally aligned sample")


func _thresholds_and_drought(runner: Object) -> void:
	var rules: Dictionary = _rules()
	var source: Dictionary = Rules.empty_state(rules, 0)
	var prior: Dictionary = _advance(source, rules, 7199999)
	runner.assert_eq(prior.produced, 0, "the final millisecond before actual maturity yields no herb")
	var exact: Dictionary = _advance(prior.state, rules, 7200000, int(prior.stock))
	runner.assert_eq(exact.produced, 1, "the exact mature-water-work threshold yields one original-source item")
	runner.assert_eq(exact.state.water, 0, "the default soil's initial water is actually exhausted by evaporation and this first growth")
	runner.assert_true(not exact.state.wet, "real water exhaustion stops subsequent growth rather than issuing an abstract drought modifier")
	var late: Dictionary = _advance(exact.state, rules, 7200001, 1)
	runner.assert_eq(late.produced, 0, "the first dry millisecond cannot immediately grow another herb")
	var distant: Dictionary = _advance(late.state, rules, 5 * 86400000, 1)
	runner.assert_eq(distant.stock, 1, "dry constant-condition fast-forward never accumulates imaginary missed mature plants")
	_balance(runner, distant.state, rules, 1, "ordinary depletion")
	var tiny: Dictionary = rules.duplicate(true)
	tiny.initial_water = 3
	tiny.resume_water = 1
	var last_drop: Dictionary = _advance(Rules.empty_state(tiny, 0), tiny, 1)
	runner.assert_eq(last_drop.state.evaporated, 1, "the last dry millisecond first pays its one actual evaporated micro-unit")
	runner.assert_eq(last_drop.state.absorbed, 2, "growth absorbs only the remaining two micro-units rather than rounding a full four")
	runner.assert_eq(last_drop.state.progress, 2, "fractional final-millisecond growth remains exact saved work")
	_balance(runner, last_drop.state, tiny, 0, "fractional last drop")


func _cold_and_old_cache(runner: Object) -> void:
	var rules: Dictionary = _rules()
	var state: Dictionary = Rules.empty_state(rules, 0, 0, {"temperature_tenths": 0})
	var cold: Dictionary = _advance(state, rules, 1200000)
	runner.assert_eq(cold.produced, 0, "water cannot bypass the plant's own cold dormancy window")
	runner.assert_eq(cold.state.progress, 0, "cold time accumulates no hidden growth debt")
	runner.assert_eq(cold.state.water, int(rules.initial_water) - 1200000, "dormant soil still loses its actual evaporation")
	state = cold.state.duplicate(true)
	state.temperature_tenths = 200
	state.sample_ms = 1200000
	var warm: Dictionary = _advance(state, rules, 1300000)
	runner.assert_eq(warm.state.progress, 400000, "a changed future cache starts growth only after its real new timestamp")
	runner.assert_eq(cold.state.progress, 0, "future integration cannot mutate the previously settled cold record")
	_balance(runner, warm.state, rules, 0, "warm after cold")
	var sim: Authority = Authority.new()
	var land := Land.new()
	land.initialize(sim, _definitions_data())
	runner.assert_true(land.set_ecology_conditions("herb_slope", 0, 0, false), "initial real conditions may replace the explicit default at activation")
	sim.elapsed_ms = 60000
	land.advance_to_ms(sim.elapsed_ms)
	runner.assert_true(land.set_ecology_conditions("herb_slope", 60000, 200, false), "the exact next global minute admits its actual new cache")
	runner.assert_eq(land.sources.herb_slope.ecology.progress, 0, "the warm sample does not rewrite the completed cold minute")
	runner.assert_true(not land.set_ecology_conditions("herb_slope", 60000, 0, true), "repeated same-minute sampling cannot overwrite already committed future conditions")
	sim.elapsed_ms = 180000
	land.advance_to_ms(sim.elapsed_ms)
	runner.assert_true(not land.set_ecology_conditions("herb_slope", 180000, 200, true), "a skipped parent sample is refused instead of inventing its missing rain segment")


func _rain_fullness_and_split(runner: Object) -> void:
	var rules: Dictionary = _rules()
	rules.initial_water = 0
	var dry: Dictionary = Rules.empty_state(rules, 1234, 0, {"temperature_tenths": 200, "rain": true})
	var coarse: Dictionary = _advance(dry, rules, 18000000)
	var state: Dictionary = dry
	var stock: int = 0
	var produced: int = 0
	for at_ms: int in [1235, 1900, 60000, 316789, 599999, 601111, 7200000, 15000000, 18000000]:
		var part: Dictionary = _advance(state, rules, at_ms, stock)
		state = part.state
		stock = int(part.stock)
		produced += int(part.produced)
	runner.assert_eq(_canonical(state), _canonical(coarse.state), "rain recharge, wet hysteresis, capacity and maturity are invariant under arbitrary cuts")
	runner.assert_eq(stock, coarse.stock, "fine and coarse climate integration create exactly the same original-source mature quantity")
	runner.assert_true(stock > 0 and int(state.rain_input) > 0 and int(state.overflow) > 0, "actual rain restores a dry patch and excess water has an explicit overflow destination")
	_balance(runner, state, rules, produced, "rainy fine/coarse future")
	var full: Dictionary = _advance(Rules.empty_state(rules, 0, 0, {"rain": true}), rules, 10 * 86400000)
	runner.assert_eq(full.stock, 8, "a long wet future fills only the real finite source capacity")
	var after: Dictionary = _advance(full.state, rules, 20 * 86400000, 8)
	runner.assert_eq(after.produced, 0, "a full original source cannot bank a second hidden pile of mature herbs")
	runner.assert_eq(after.state.progress, 0, "a full source retains no almost-mature future payout")
	runner.assert_eq(after.state.absorbed, full.state.absorbed, "a full source stops growth uptake rather than consuming water for free stored output")
	_balance(runner, after.state, rules, int(full.produced), "full source")
	var harvested: Dictionary = _advance(after.state, rules, int(after.state.last_ms) + 1, 7)
	runner.assert_eq(harvested.produced, 0, "opening one slot after many full days does not instantly receive a missed crop")


func _irrigation_and_real_inventory(runner: Object) -> void:
	var data: Dictionary = _definitions_data()
	data.types.wild_herbs.ecology.initial_water = 0
	var sim: Authority = Authority.new()
	sim.inventory.create_container("actor:player", {"water": 2})
	var land := Land.new()
	runner.assert_true(land.initialize(sim, data), "the real source authority initializes on the original inventory containers")
	var action: Dictionary = {"id": "native:action:1", "phase": "work", "carrying": false, "reservations": ["native:action:1:water"]}
	sim.actors.player.active = action
	var definition: Dictionary = sim.config.actions.irrigate_herb
	runner.assert_true(sim.inventory.reserve("native:action:1:water", "actor:player", "water", 1, "player"), "irrigation reserves an actual privately disposable unit of carried water")
	runner.assert_true(land.irrigate(action, "player", definition), "one preflighted native water consume and soil input commit together")
	runner.assert_eq(sim.inventory.quantity("actor:player", "water"), 1, "actual successful watering consumes one original pocket unit")
	runner.assert_eq(land.sources.herb_slope.ecology.irrigated, int(data.types.wild_herbs.ecology.water_per_item), "the soil ledger contains exactly its original unit conversion")
	runner.assert_true(sim.inventory.operations.has("native:action:1:irrigate"), "the finite soil input references its unique original consume operation")
	var before: String = _canonical(land.to_dict()) + _canonical(sim.inventory.to_dict())
	runner.assert_true(land.irrigate(action, "player", definition), "an identical completed native action can be acknowledged idempotently")
	runner.assert_eq(_canonical(land.to_dict()) + _canonical(sim.inventory.to_dict()), before, "repeated successful acknowledgment neither consumes another unit nor adds more soil water")
	runner.assert_true(Land.valid_state(land.to_dict(), sim.config, sim.places, sim.inventory, 0, data), "original source and consume references validate in both directions")
	var forged: Dictionary = land.to_dict()
	forged.sources.herb_slope.ecology.irrigation_receipts["native:action:1"].actor = "someone_else"
	runner.assert_true(not Land.valid_state(forged, sim.config, sim.places, sim.inventory, 0, data), "a real consume cannot authorize another actor's fabricated soil receipt")
	var removed: Dictionary = land.to_dict()
	removed.sources.herb_slope.ecology = Rules.empty_state(data.types.wild_herbs.ecology, 0)
	runner.assert_true(not Land.valid_state(removed, sim.config, sim.places, sim.inventory, 0, data), "an original irrigation consume without its reverse soil receipt is refused")
	var public_water: Authority = Authority.new()
	public_water.inventory.create_container("actor:player", {"water": 1})
	public_water.inventory.entrust("public:water", "actor:player", "water", 1, {"domain": "fixture"})
	var public_land := Land.new()
	public_land.initialize(public_water, data)
	public_water.actors.player.active = action.duplicate(true)
	runner.assert_true(not public_water.inventory.reserve("native:action:1:water", "actor:player", "water", 1, "player"), "entrusted carried water is not privately disposable irrigation stock")
	runner.assert_true(not public_land.irrigate(action, "player", definition), "without a valid private reservation no partial soil or inventory effect is committed")
	runner.assert_eq(public_land.sources.herb_slope.ecology.irrigated, 0, "refused public-water disposal leaves the dry original soil unchanged")
	var full: Dictionary = Rules.empty_state(_rules(), 0)
	full.water = int(_rules().soil_capacity)
	full.rain_input = int(_rules().soil_capacity) - int(_rules().initial_water)
	var received: Dictionary = Rules.with_irrigation(full, _rules(), "actual:completed", "player", 1, 0)
	runner.assert_eq(received.water, full.water, "water arriving after rain filled the soil cannot exceed capacity")
	runner.assert_eq(received.overflow, int(_rules().water_per_item), "all of a late incoming carried unit is recorded as actual overflow")


func _legacy_activation(runner: Object) -> void:
	var sim: Authority = Authority.new()
	var rules: Dictionary = _definitions_data()
	var old: Dictionary = {"version": 2, "sources": {
		"herb_slope": {"next_growth_ms": 14400000, "produced": 1, "extracted": 0, "rainfall": 0},
		"woodlot": {"next_growth_ms": 10800000, "produced": 4, "extracted": 0, "rainfall": 0}}}
	var before: String = _canonical(old)
	var upgraded: Dictionary = Land.upgrade_state(old, sim.config, rules, 10001234, {"herb_slope": {"temperature_tenths": 0, "rain": true, "heat_tenths": 0}})
	runner.assert_true(not upgraded.is_empty(), "a legally phased old source upgrades without replaying pre-activation plant ecology")
	if upgraded.is_empty():
		return
	runner.assert_eq(upgraded.sources.herb_slope.produced, 1, "old produced goods remain the exact historical baseline")
	runner.assert_eq(upgraded.sources.herb_slope.ecology.base_produced, 1, "new ecological growth does not claim credit for legacy periodic goods")
	runner.assert_eq(upgraded.sources.herb_slope.ecology.activation_ms, 10001234, "legacy plants activate at the original saved millisecond")
	runner.assert_eq(upgraded.sources.herb_slope.ecology.rain_input, 0, "current rain is a future cache rather than retroactive water input")
	runner.assert_eq(upgraded.sources.herb_slope.next_growth_ms, SimInventory.MAX_COUNT, "managed herbs no longer retain their old periodic growth clock")
	runner.assert_true(upgraded.sources.woodlot.ecology.is_empty(), "ordinary woodland retains its original growth law")
	runner.assert_eq(_canonical(old), before, "activation never mutates the original historical input archive")
	var corrupt: Dictionary = old.duplicate(true)
	corrupt.sources.herb_slope.next_growth_ms += 1
	runner.assert_true(Land.upgrade_state(corrupt, sim.config, rules, 10001234).is_empty(), "migration cannot hide an illegal old growth phase by replacing it with the new disabled clock")
	corrupt = old.duplicate(true)
	corrupt.sources.herb_slope.produced = 2
	runner.assert_true(Land.upgrade_state(corrupt, sim.config, rules, 10001234).is_empty(), "migration refuses legacy production beyond its real periodic time upper bound")
	var fresh: Authority = Authority.new()
	var land := Land.new()
	land.initialize(fresh, rules)
	land.set_ecology_conditions("herb_slope", 0, 0, false)
	fresh.elapsed_ms = 7200000
	land.advance_to_ms(fresh.elapsed_ms)
	runner.assert_eq(land.sources.herb_slope.produced, 0, "cold herbs do not also receive the original two-hour periodic item")
	runner.assert_eq(fresh.inventory.quantity("resource:woodlot", "wood"), 16, "the same new source authority preserves ordinary woodland periodic growth")


func _exact_small_step_law(runner: Object) -> void:
	# Deliberately tiny soil makes every moisture threshold occur within a few
	# milliseconds, while preserving the actual whole growth-work definition.
	for rainy: bool in [false, true]:
		for initial: int in [0, 1, 3, 7, 18, 19]:
			var rules: Dictionary = _rules()
			rules.soil_capacity = 19
			rules.initial_water = initial
			rules.resume_water = 6
			rules.rain_per_ms = 3
			rules.evaporation_per_ms = 1
			rules.uptake_per_ms = 4
			var opening: Dictionary = Rules.empty_state(rules, 0, 0, {"rain": rainy})
			var coarse: Dictionary = _advance(opening, rules, 257)
			var fine: Dictionary = opening
			for at_ms: int in range(1, 258):
				fine = _advance(fine, rules, at_ms).state
			runner.assert_eq(_canonical(fine), _canonical(coarse.state), "257 genuine one-millisecond steps match threshold batching at soil %d/rain %s" % [initial, rainy])
	var sim: Authority = Authority.new()
	var data: Dictionary = _definitions_data()
	data.types.wild_herbs.ecology.initial_water = 0
	var land := Land.new()
	land.initialize(sim, data)
	land.set_ecology_conditions("herb_slope", 0, 0, false)
	var line: String = land.describe("player", "herb_slope")
	runner.assert_true(line.contains("可采") and line.contains("土面发干") and line.contains("暂歇"), "existing mature herbs do not hide local dry soil or current cold dormancy clues")
	sim.actors.player.cell = [100, 100]
	var far: String = land.describe("player", "herb_slope")
	runner.assert_true(far.contains("离得远") and not far.contains("土面发干") and not far.contains("暂歇"), "distant remembered source identity reveals no live soil or dormancy state")


func _repeated_json_integer_contract(runner: Object) -> void:
	for final_ms: int in [0, SimInventory.MAX_COUNT]:
		var data: Dictionary = _definitions_data()
		data.types.wild_herbs.ecology.initial_water = 0
		var sim: Authority = Authority.new()
		sim.elapsed_ms = final_ms
		sim.inventory.create_container("actor:player", {"water": 1})
		var land := Land.new()
		land.initialize(sim, data)
		land.advance_to_ms(final_ms)
		var action: Dictionary = {"id": "native:action:1", "phase": "work", "carrying": false, "reservations": ["native:action:1:water"]}
		sim.actors.player.active = action
		sim.inventory.reserve("native:action:1:water", "actor:player", "water", 1, "player")
		runner.assert_true(land.irrigate(action, "player", sim.config.actions.irrigate_herb), "the integer-roundtrip fixture uses a real consume receipt at %dms" % final_ms)
		var original: String = _canonical(land.to_dict())
		for full_precision: bool in [false, true]:
			for cycle: int in range(4):
				var decoded: Dictionary = JSON.parse_string(JSON.stringify(land.to_dict(), "", true, full_precision))
				runner.assert_true(Land.valid_state(decoded, sim.config, sim.places, sim.inventory, final_ms, data), "actual JSON retains a legal integer source before bind at %dms/%s/%d" % [final_ms, full_precision, cycle])
				land.bind_restored(sim, data, decoded)
				runner.assert_eq(_canonical(land.to_dict()), original, "repeated decoded-float binding preserves the exact full source with %s precision at %dms/%d" % [full_precision, final_ms, cycle])
				runner.assert_true(land.sources.herb_slope.next_growth_ms is int and land.sources.herb_slope.ecology.last_ms is int and land.sources.herb_slope.ecology.irrigation_receipts["native:action:1"].at_ms is int, "persisted source, ecology and receipt times are normalized to integer ownership")


func _bad_state_and_extremes(runner: Object) -> void:
	var rules: Dictionary = _rules()
	var grown: Dictionary = _advance(Rules.empty_state(rules, 0), rules, 7200000)
	runner.assert_true(Rules.valid_state(grown.state, rules, 1, 7200000), "the actual dry mature boundary is a fully valid ecology state")
	for field: String in ["water", "absorbed", "evaporated", "rain_input", "progress", "discarded_progress"]:
		var bad: Dictionary = grown.state.duplicate(true)
		bad[field] = int(bad[field]) + 1
		runner.assert_true(not Rules.valid_state(bad, rules, 1, 7200000), "forged water or growth ledger is rejected: " + field)
	var huge: Dictionary = _advance(Rules.empty_state(rules, 0, 0, {"rain": true}), rules, SimInventory.MAX_COUNT)
	runner.assert_true(not huge.is_empty(), "constant-condition integration safely reaches the supported integer time maximum")
	_balance(runner, huge.state, rules, int(huge.produced), "supported time maximum")
	runner.assert_true(Rules.valid_state(huge.state, rules, int(huge.produced), SimInventory.MAX_COUNT), "explicit rate-budget saturation remains exact JSON-safe conserved state")
	var decoded: Dictionary = JSON.parse_string(_canonical(huge.state))
	runner.assert_true(Rules.valid_state(decoded, rules, int(huge.produced), SimInventory.MAX_COUNT), "real JSON numeric decoding retains the extreme water/work ledger")
