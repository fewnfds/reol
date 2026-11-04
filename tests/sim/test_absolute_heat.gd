extends RefCounted
## Fixed-reference Q and declared background clocks, without a scene or climate DB.

const HeatFixtures = preload("res://tests/sim/test_local_heat.gd")
const CELL: Vector2i = Vector2i(100, 100)
const EAST_CELL: Vector2i = Vector2i(400, 100)
var _fixtures := HeatFixtures.new()


func run(runner: Object) -> void:
	_weather_wakes_quiet_cells(runner)
	_two_climate_regions(runner)
	_colder_bath_reclaims_energy(runner)
	_unallocated_neighbor_exchange(runner)
	_source_budget_rejects_atomically(runner)
	_zero_q_sample(runner)
	_split_and_signed_sample_restore(runner)
	print("SCENARIO absolute heat: declared background clocks wake zero flux, two climates produce signed offsets, inward/outward exterior exchange conserves Q, bounded sources reject atomically and sampled history resumes independently")


func _isolated_rules() -> Dictionary:
	var rules: Dictionary = _fixtures._rules()
	rules.source_radius = 0
	rules.pulse_energy = 1
	for kind: String in rules.conductance:
		rules.conductance[kind] = 0
	return rules


func _configure_weather(fixture: Dictionary, west: int, east: int, changes: Array[Dictionary]) -> void:
	# The schedule is a declared input before the first activation. Tests never
	# mutate already elapsed weather to create a desired temperature result.
	fixture.world.west_background = west
	fixture.world.east_background = east
	fixture.world.background_schedule = changes.duplicate(true)


func _conserved(runner: Object, fixture: Dictionary, label: String) -> void:
	runner.assert_eq(_fixtures._energy(fixture.heat) + fixture.heat.loss_energy, fixture.heat.input_energy + fixture.heat.ambient_in, label)
	var bounded: bool = true
	for row: Dictionary in fixture.heat.cells.values():
		bounded = bounded and int(row.energy) >= 0 and int(row.energy) <= int(fixture.heat.definitions.max_cell_energy)
	runner.assert_true(bounded, label + " keeps each original Q within its declared bounds")


func _weather_wakes_quiet_cells(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._make(_isolated_rules())
	_configure_weather(fixture, 0, 0, [{"at_ms": 3257, "west": 300}])
	runner.assert_true(_fixtures._deposit(fixture, "warm:quiet"), "one real sub-rate impulse activates a cell against its current background")
	runner.assert_true(fixture.heat.flows.is_empty(), "an actual one-unit impulse has no rounded-up exterior flow")
	runner.assert_eq(fixture.heat.next_boundary_ms(), 3257, "a real weather boundary stays scheduled even when all frozen flux is zero")
	var initial: int = _fixtures._energy(fixture.heat)
	var allocated: int = int(fixture.heat.ambient_in)
	var before: String = _fixtures._json(fixture.heat)
	_fixtures._projection_matches(runner, fixture.heat.project_tenths(CELL, 3257), -300, "inclusive weather-boundary projection uses unchanged Q and the new background with correct negative rounding")
	_fixtures._projection_unsupported(runner, fixture.heat.project_tenths(CELL, 3258), "beyond_boundary", "zero-flow prediction cannot skip a declared background change")
	runner.assert_true(_fixtures._json(fixture.heat) == before, "weather predictions never advance or rewrite the quiet cell")
	_fixtures._advance(fixture, 3257)
	runner.assert_eq(_fixtures._energy(fixture.heat), initial, "warming the outdoor bath does not instantly reset the allocated Q")
	runner.assert_eq(fixture.heat.ambient_in, allocated, "the weather change itself transfers no energy before a real interval")
	runner.assert_eq(fixture.heat.current_tenths(CELL), -300, "positive cell Q can represent a real temperature below the warmer background")
	runner.assert_true(not fixture.heat.flows.is_empty(), "the original now-colder cell begins receiving a real exterior flux")
	var stable: String = _fixtures._json(fixture.heat)
	var roof_queries: int = fixture.world.roof_queries
	var barrier_queries: int = fixture.world.barrier_queries
	for repeat: int in 3:
		runner.assert_eq(fixture.heat.current_tenths(CELL), -300, "current temperature query preserves the same committed signed offset")
	runner.assert_true(_fixtures._json(fixture.heat) == stable, "current_tenths is an authoritative-state read only")
	runner.assert_eq(fixture.world.roof_queries, roof_queries, "current query does not resample cover")
	runner.assert_eq(fixture.world.barrier_queries, barrier_queries, "current query does not resample walls")
	_fixtures._advance(fixture, 4257)
	runner.assert_true(_fixtures._energy(fixture.heat) > initial and fixture.heat.ambient_in > allocated, "only actual elapsed inward flux increases Q and the matching exterior input")
	var offset: int = fixture.heat.current_tenths(CELL)
	runner.assert_true(offset > -300 and offset < 0, "allocated cell warms gradually while retaining a real negative deviation")
	runner.assert_eq(fixture.heat.input_energy, 1, "incoming outdoor energy is not attributed to the unique source pulse")
	_conserved(runner, fixture, "zero-flux weather wakeup conserves the declared source and exterior ledger")


func _two_climate_regions(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._make()
	_configure_weather(fixture, -50, 150, [{"at_ms": 3257, "west": 350, "east": 450}])
	runner.assert_true(_fixtures._deposit(fixture, "warm:west", CELL) and _fixtures._deposit(fixture, "warm:east", EAST_CELL), "two separated original sources activate against their own local climate")
	var capacity: int = int(fixture.heat.definitions.capacity_per_tenth)
	var reference: int = int(fixture.heat.definitions.reference_tenths)
	var expected_background: int = 25 * capacity * ((-50 - reference) + (150 - reference))
	runner.assert_eq(fixture.heat.ambient_in, expected_background, "distinct climate patches allocate their actual background Q once each")
	runner.assert_eq(fixture.heat.current_tenths(CELL), 180, "western source begins with its own 18-degree offset")
	runner.assert_eq(fixture.heat.current_tenths(EAST_CELL), 180, "eastern source has the same source offset despite a different absolute background")
	_fixtures._advance(fixture, 3257)
	var western: int = fixture.heat.current_tenths(CELL)
	var eastern: int = fixture.heat.current_tenths(EAST_CELL)
	runner.assert_true(western < 0 and eastern < 0, "both actual climates can overtake retained source heat and produce negative offsets")
	runner.assert_true(western < eastern, "different real background rises preserve different local thermal consequences")
	runner.assert_eq(fixture.heat.input_energy, 2 * int(fixture.heat.definitions.pulse_energy), "two climate changes do not fabricate extra artifact input")
	_conserved(runner, fixture, "two local climates share the same explicit energy accounting")
	var before: String = _fixtures._json(fixture.heat)
	runner.assert_eq(fixture.heat.current_tenths(Vector2i(50, 50)), 0, "an unallocated western cell follows its background without a duplicate heat store")
	runner.assert_eq(fixture.heat.current_tenths(Vector2i(450, 50)), 0, "an unallocated eastern cell also has zero offset in its own climate")
	runner.assert_true(_fixtures._json(fixture.heat) == before, "unallocated temperature queries do not allocate cells or alter climate history")


func _colder_bath_reclaims_energy(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._make(_isolated_rules())
	_configure_weather(fixture, 200, 200, [{"at_ms": 4321, "west": -200}])
	runner.assert_true(_fixtures._deposit(fixture, "warm:falling"), "cold-weather case starts from a real background allocation and finite pulse")
	var initial: int = _fixtures._energy(fixture.heat)
	_fixtures._advance(fixture, 4321)
	runner.assert_eq(_fixtures._energy(fixture.heat), initial, "outdoor cooling leaves current stored Q continuous at the exact phase boundary")
	runner.assert_eq(fixture.heat.current_tenths(CELL), 400, "a colder outdoor bath makes the same allocated cell warmer relative to outside")
	_fixtures._advance(fixture, 30000)
	runner.assert_true(_fixtures._energy(fixture.heat) < initial, "actual subsequent outward flow removes energy from the original cell")
	runner.assert_true(fixture.heat.loss_energy > fixture.heat.input_energy, "outflow can exceed source input because the exterior reclaims its earlier allocated background energy")
	var offset: int = fixture.heat.current_tenths(CELL)
	runner.assert_true(offset >= 0 and offset < 400, "cooling approaches the actual colder bath without resetting or negating Q")
	_conserved(runner, fixture, "cooling accounts for previously allocated exterior energy as well as the source")


func _unallocated_neighbor_exchange(runner: Object) -> void:
	var rules: Dictionary = _fixtures._rules()
	rules.source_radius = 0
	rules.pulse_energy = 1
	rules.bath_loss.roofed = 0
	rules.bath_loss.unroofed = 0
	var fixture: Dictionary = _fixtures._make(rules)
	fixture.world.climate_boundary_x = 101
	_configure_weather(fixture, 0, 300, [{"at_ms": 2000, "east": -300}])
	runner.assert_true(_fixtures._deposit(fixture, "warm:border"), "single active boundary cell has a real unallocated eastern neighbor")
	var initial: int = _fixtures._energy(fixture.heat)
	var allocated: int = int(fixture.heat.ambient_in)
	_fixtures._advance(fixture, 1000)
	runner.assert_true(_fixtures._energy(fixture.heat) > initial and fixture.heat.ambient_in > allocated, "warmer unallocated neighbor transfers energy through the finite boundary even without direct bath loss")
	runner.assert_eq(fixture.heat.cells.size(), 1, "boundary exchange does not invent an allocated neighboring reservoir")
	runner.assert_true(fixture.heat.next_boundary_ms() <= 2000, "the unallocated neighbor's real climate boundary participates in the frozen schedule")
	_fixtures._advance(fixture, 2000)
	var peak: int = _fixtures._energy(fixture.heat)
	var loss_before: int = int(fixture.heat.loss_energy)
	_fixtures._advance(fixture, 4000)
	runner.assert_true(_fixtures._energy(fixture.heat) < peak and fixture.heat.loss_energy > loss_before, "the same physical boundary can reverse direction after actual neighboring weather changes")
	_conserved(runner, fixture, "finite incoming and outgoing boundary flows preserve the single cell ledger")


func _source_budget_rejects_atomically(runner: Object) -> void:
	var rules: Dictionary = _fixtures._rules()
	rules.source_radius = 0
	var pulse: int = ceili(float(rules.max_cell_energy) * 0.5)
	rules.pulse_energy = pulse
	rules.max_total_input = pulse * 2
	var fixture: Dictionary = _fixtures._make(rules)
	runner.assert_true(fixture.configured, "bounded source-input fixture has valid original stability and energy limits")
	if not fixture.configured:
		return
	runner.assert_true(_fixtures._deposit(fixture, "warm:budget:1", CELL), "first finite source fits the original input budget")
	runner.assert_true(_fixtures._deposit(fixture, "warm:budget:2", EAST_CELL), "second separated source reaches the exact original input limit")
	var before: String = _fixtures._json(fixture.heat)
	var third := Vector2i(300, 100)
	runner.assert_true(not fixture.heat.can_deposit(third, pulse), "a third source is refused before any activation or physical debit")
	runner.assert_true(not _fixtures._deposit(fixture, "warm:budget:3", third), "the authoritative source transfer also refuses the exhausted input budget")
	runner.assert_true(_fixtures._json(fixture.heat) == before, "budget refusal changes no Q, ambient allocation, receipt or frozen slope")
	runner.assert_true(fixture.heat.cells.size() == 2 and fixture.heat.receipts.size() == 2, "rejected source leaves no partial allocation or provenance")
	_conserved(runner, fixture, "source input limit preserves both original activated cells and exterior allocation")


func _zero_q_sample(runner: Object) -> void:
	var rules: Dictionary = _fixtures._rules()
	rules.pulse_energy = 1
	var fixture: Dictionary = _fixtures._make(rules)
	var reference: int = int(rules.reference_tenths)
	_configure_weather(fixture, reference, reference, [])
	runner.assert_true(_fixtures._deposit(fixture, "warm:reference"), "numerical reference boundary allocates real zero-Q neighbors around a one-unit source")
	_fixtures._advance(fixture, 60000)
	runner.assert_true(fixture.heat.mark_sample(60000), "aligned absolute sample records the actual reference-boundary state")
	runner.assert_eq(fixture.heat.last_sample_mode, "absolute", "zero-Q history belongs to the new absolute sample representation")
	runner.assert_eq(fixture.heat.last_sample_cells.size(), 25, "zero-Q allocated cells remain distinct from absent historical cells")
	runner.assert_true(fixture.heat.last_sample_cells.has("98,98") and int(fixture.heat.last_sample_cells["98,98"]) == 0, "an actually allocated zero-energy corner is explicitly retained in the sample")
	_conserved(runner, fixture, "reference-boundary one-unit source keeps exact nonnegative Q accounting")
	var resumed: Dictionary = _fixtures._make(rules, 60000)
	_configure_weather(resumed, reference, reference, [])
	resumed.world.artifacts.events = fixture.world.artifacts.events.duplicate(true)
	runner.assert_true(resumed.heat.restore(JSON.parse_string(_fixtures._json(fixture.heat))), "independent JSON restore preserves explicitly sampled zero-Q cells")


func _split_and_signed_sample_restore(runner: Object) -> void:
	var coarse: Dictionary = _fixtures._make(_isolated_rules())
	var fine: Dictionary = _fixtures._make(_isolated_rules())
	var changes: Array[Dictionary] = [{"at_ms": 3257, "west": 300}, {"at_ms": 73123, "west": -200}, {"at_ms": 111111, "west": 125}]
	for fixture: Dictionary in [coarse, fine]:
		_configure_weather(fixture, 0, 0, changes)
		runner.assert_true(_fixtures._deposit(fixture, "warm:history"), "split weather scenario begins with the same real source")
		_fixtures._advance(fixture, 60000, fixture == fine)
		runner.assert_true(fixture.heat.mark_sample(60000), "the original aligned sample captures actual fixed-reference state")
		runner.assert_eq(fixture.heat.last_sample_mode, "absolute", "new sample explicitly distinguishes absolute Q from imported legacy excess")
		runner.assert_eq(fixture.heat.last_sample_cells.size(), fixture.heat.cells.size(), "an absolute sample records every allocated cell")
		runner.assert_true(fixture.heat.sample_tenths(CELL, 60000) < 0, "historical sample preserves a real negative thermal deviation")
		var sample_sum: int = 0
		for energy: Variant in fixture.heat.last_sample_cells.values():
			sample_sum += int(energy)
		runner.assert_eq(sample_sum + fixture.heat.last_sample_loss, fixture.heat.last_sample_input + fixture.heat.last_sample_ambient_in, "absolute sample carries its own conserved exterior/source accounting")
		_fixtures._advance(fixture, 66789, fixture == fine)
	runner.assert_true(_fixtures._json(coarse.heat) == _fixtures._json(fine.heat), "many extra settle calls neither add weather boundaries nor change Q, flow or sampled history")
	var historical: int = coarse.heat.sample_tenths(CELL, 60000)
	var data: Dictionary = JSON.parse_string(_fixtures._json(coarse.heat))
	var resumed: Dictionary = _fixtures._make(_isolated_rules(), 66789)
	_configure_weather(resumed, 0, 0, changes)
	resumed.world.artifacts.events = coarse.world.artifacts.events.duplicate(true)
	var loaded: bool = resumed.heat.restore(data)
	runner.assert_true(loaded, "independent kernel restores an off-lattice weather slope and its negative historical sample")
	if not loaded:
		return
	runner.assert_true(_fixtures._json(resumed.heat) == _fixtures._json(coarse.heat), "JSON restoration normalizes exactly the original absolute energy and exterior ledger")
	for fixture: Dictionary in [coarse, fine, resumed]:
		_fixtures._advance(fixture, 151623, fixture != coarse)
		runner.assert_eq(fixture.heat.sample_tenths(CELL, 60000), historical, "later colder and warmer weather never reprices the original sampled background")
		_conserved(runner, fixture, "uneven weather continuation retains the original source/exterior ledger")
	runner.assert_true(_fixtures._json(coarse.heat) == _fixtures._json(fine.heat) and _fixtures._json(coarse.heat) == _fixtures._json(resumed.heat), "whole, sliced and independently restarted weather futures have the same complete thermal state")
	var before: String = _fixtures._json(resumed.heat)
	var saved: Dictionary = resumed.heat.to_dict()
	var wrong_slope: Dictionary = saved.duplicate(true)
	if not wrong_slope.flows.is_empty():
		wrong_slope.flows[0].rate += 1
		runner.assert_true(not resumed.heat.restore(wrong_slope), "forged incoming or outgoing frozen slope cannot redefine a saved weather interval")
		runner.assert_true(_fixtures._json(resumed.heat) == before, "rejecting a forged weather slope leaves the live cell and historical background unchanged")
	var wrong_ambient: Dictionary = saved.duplicate(true)
	wrong_ambient.ambient_in += 1
	runner.assert_true(not resumed.heat.restore(wrong_ambient), "a candidate cannot invent an extra unit of exterior input")
	runner.assert_true(_fixtures._json(resumed.heat) == before, "invalid exterior accounting is rejected before any live replacement")
