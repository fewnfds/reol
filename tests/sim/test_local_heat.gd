extends RefCounted
## Pure finite heat tests; no regional/UI/persistence integration is implied.

const Heat = preload("res://scripts/sim/local_heat.gd")


class ArtifactLog extends RefCounted:
	var events: Array[Dictionary] = []


class Authority extends RefCounted:
	var elapsed_ms: int = 0
	var artifacts := ArtifactLog.new()
	var roofed: bool = false
	var barriers: Dictionary = {}
	var roof_queries: int = 0
	var barrier_queries: int = 0


	func roof(_cell: Vector2i) -> bool:
		roof_queries += 1
		return roofed


	func barrier(cell: Vector2i) -> Variant:
		barrier_queries += 1
		return barriers.get("%d,%d" % [cell.x, cell.y], "open")


func run(runner: Object) -> void:
	_definitions(runner)
	_conservation(runner)
	_split_and_topology(runner)
	_impulse_timing(runner)
	_read_only_projections(runner)
	_history_and_restore(runner)
	_capacity_and_activation(runner)
	_stable_residual_long_future(runner)
	_exact_source_patches(runner)
	_bad_candidates(runner)
	print("SCENARIO local heat: sparse fixed cells, conservative integer flux, arbitrary split equivalence, old-layout settlement, immediate nonretroactive impulses, historical minute heat and atomic receipt validation")


func _rules() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/local_heat.json"))


func _make(rules: Dictionary = {}, at_ms: int = 0) -> Dictionary:
	var authority := Authority.new()
	authority.elapsed_ms = at_ms
	var heat := Heat.new()
	var configured: bool = heat.initialize(authority, _rules() if rules.is_empty() else rules)
	heat.set_geometry(Callable(authority, "roof"), Callable(authority, "barrier"))
	return {"world": authority, "heat": heat, "configured": configured}


func _advance(fixture: Dictionary, now: int, fine: bool = false) -> void:
	if fine:
		while fixture.world.elapsed_ms + 317 < now:
			fixture.world.elapsed_ms += 317
			fixture.heat.settle_at_ms(fixture.world.elapsed_ms)
	fixture.world.elapsed_ms = now
	fixture.heat.settle_at_ms(now)


func _deposit(fixture: Dictionary, action: String, cell: Vector2i = Vector2i(100, 100)) -> bool:
	var receipt: Dictionary = {"action": action, "actor": "player", "object": "warm_stone", "at_ms": fixture.world.elapsed_ms, "cell": [cell.x, cell.y], "amount": int(fixture.heat.definitions.pulse_energy)}
	if not fixture.heat.deposit(receipt):
		return false
	fixture.world.artifacts.events.append({"action": action, "actor": "player", "object": "warm_stone", "at_ms": fixture.world.elapsed_ms, "cell": [cell.x, cell.y], "kind": "warmed", "heat_amount": receipt.amount})
	return true


func _energy(heat: RefCounted) -> int:
	var total: int = 0
	for row: Dictionary in heat.cells.values():
		total += int(row.energy)
	return total


func _json(heat: RefCounted) -> String:
	return JSON.stringify(heat.to_dict(), "", true, true)


func _definitions(runner: Object) -> void:
	runner.assert_true(Heat.valid_definitions(_rules()), "default local heat rules have safe integer outflow bounds")
	var rules: Dictionary = _rules()
	rules.conductance.open = 1000
	runner.assert_true(not Heat.valid_definitions(rules), "unstable four-edge plus atmosphere coefficients are rejected")
	rules = _rules()
	rules.pulse_energy = 0
	runner.assert_true(not Heat.valid_definitions(rules), "a heat source pulse must contain a bounded positive energy")


func _conservation(runner: Object) -> void:
	var fixture: Dictionary = _make()
	runner.assert_true(fixture.configured, "pure heat authority initializes independently of any map scene")
	runner.assert_eq(fixture.heat.next_boundary_ms(), SimInventory.MAX_COUNT, "empty heat does not schedule a world-wide ten-second wakeup")
	runner.assert_true(_deposit(fixture, "warm:1"), "a completed source impulse deposits exactly one real receipt")
	runner.assert_eq(_energy(fixture.heat), int(fixture.heat.definitions.pulse_energy), "an impulse adds its full source energy without an earlier interval of leakage")
	runner.assert_eq(fixture.heat.cells.size(), 25, "default source activates a bounded five-by-five fixed spatial patch")
	for now: int in [1, 9999, 10000, 10001, 17343, 60000, 121623]:
		_advance(fixture, now)
		runner.assert_eq(_energy(fixture.heat) + fixture.heat.loss_energy, fixture.heat.input_energy, "internal edge transfers plus declared outdoor losses conserve at %dms" % now)
		var nonnegative: bool = true
		for row: Dictionary in fixture.heat.cells.values():
			nonnegative = nonnegative and int(row.energy) >= 0
		runner.assert_true(nonnegative, "frozen flux never overdraws a cell at %dms" % now)
	runner.assert_true(fixture.heat.loss_energy > 0, "finite unroofed space loses energy to its explicit exterior bath")
	runner.assert_true(fixture.heat.cells["101,100"].energy > 0, "the neighboring fixed space receives a paired physical transfer")


func _split_and_topology(runner: Object) -> void:
	var coarse: Dictionary = _make()
	var fine: Dictionary = _make()
	for fixture: Dictionary in [coarse, fine]:
		_advance(fixture, 137)
		runner.assert_true(_deposit(fixture, "warm:1"), "off-lattice source is accepted at its actual completed timestamp")
	for fixture: Dictionary in [coarse, fine]:
		_advance(fixture, 7301, fixture == fine)
		var previous: int = _energy(fixture.heat)
		fixture.heat.before_topology_change(7301)
		fixture.heat.before_topology_change(7301)
		fixture.world.roofed = true
		fixture.world.barriers["101,100"] = "closed_door"
		fixture.heat.after_topology_change(7301)
		runner.assert_eq(_energy(fixture.heat), previous, "roof and door changes preserve all fixed-cell energy at the mutation instant")
		_advance(fixture, 17463, fixture == fine)
		runner.assert_true(_deposit(fixture, "warm:2"), "a later off-lattice source opens only its actual future segment")
		for now: int in [60000, 120000]:
			_advance(fixture, now, fixture == fine)
			runner.assert_true(fixture.heat.mark_sample(now), "historical exposure sample uses the aligned original minute")
		_advance(fixture, 121623, fixture == fine)
	runner.assert_eq(_json(coarse.heat), _json(fine.heat), "hundreds of extra settle calls preserve the entire frozen-flux state and future")
	var outdoor: Dictionary = _make()
	var roof: Dictionary = _make()
	roof.world.roofed = true
	for fixture: Dictionary in [outdoor, roof]:
		_deposit(fixture, "warm:1")
		_advance(fixture, 60000)
	runner.assert_true(_energy(roof.heat) > _energy(outdoor.heat), "real covering changes loss coefficients rather than issuing a temperature buff")


func _impulse_timing(runner: Object) -> void:
	var rules: Dictionary = _rules()
	rules.source_radius = 0
	for kind: String in rules.conductance:
		rules.conductance[kind] = 0
	var fixture: Dictionary = _make(rules)
	_advance(fixture, 9257)
	runner.assert_true(_deposit(fixture, "warm:1"), "late source accepts its actual off-lattice finish")
	runner.assert_eq(fixture.heat.loss_energy, 0, "the newly added source cannot leak across the preceding 9257ms")
	_advance(fixture, 10000)
	var expected: int = 3600 * 743
	runner.assert_eq(fixture.heat.loss_energy, expected, "only 743ms of the frozen current source flux reaches the bath")
	var before: String = _json(fixture.heat)
	var replay: Dictionary = fixture.heat.receipts["warm:1"].duplicate(true)
	replay.at_ms = 10000
	runner.assert_true(not fixture.heat.deposit(replay), "the same original action cannot deposit a second impulse")
	runner.assert_eq(_json(fixture.heat), before, "duplicate source rejection leaves the entire heat state untouched")


func _read_only_projections(runner: Object) -> void:
	var fixture: Dictionary = _make()
	_advance(fixture, 1370)
	_deposit(fixture, "warm:projection")
	_advance(fixture, 5000)
	var before: String = _json(fixture.heat)
	var roofs_before: int = fixture.world.roof_queries
	var barriers_before: int = fixture.world.barrier_queries
	var historical: Dictionary = _make()
	_advance(historical, 1370)
	_deposit(historical, "warm:projection")
	_advance(historical, 2000)
	runner.assert_eq(fixture.heat.project_tenths(Vector2i(100, 100), 2000), historical.heat.local_tenths(Vector2i(100, 100)), "same-segment reverse projection reconstructs the actual former source-cell heat")
	runner.assert_eq(fixture.heat.project_tenths(Vector2i(101, 100), 2000), historical.heat.local_tenths(Vector2i(101, 100)), "same-segment reverse projection also reverses actual paired incoming heat")
	var continued: Dictionary = _make({}, 5000)
	continued.world.artifacts.events = fixture.world.artifacts.events.duplicate(true)
	runner.assert_true(continued.heat.restore(JSON.parse_string(before)), "prediction comparison uses an independently restored actual frozen segment")
	for at_ms: int in [5000, 6666, 9999, 10000]:
		_advance(continued, at_ms)
		for cell: Vector2i in [Vector2i(100, 100), Vector2i(101, 100)]:
			runner.assert_eq(fixture.heat.project_tenths(cell, at_ms), continued.heat.local_tenths(cell), "pure prediction matches actual integration through its inclusive next boundary at %dms/%s" % [at_ms, cell])
	for unsupported: int in [-1, 1369, 10001, SimInventory.MAX_COUNT + 1]:
		runner.assert_eq(fixture.heat.project_tenths(Vector2i(100, 100), unsupported), -1, "unsupported projection time is explicit rather than invented cold at %dms" % unsupported)
	runner.assert_eq(fixture.heat.project_tenths(Vector2i(-1, 0), 6000), -1, "projection rejects an invalid spatial target explicitly")
	runner.assert_eq(fixture.heat.project_tenths(Vector2i(400, 400), 6000), 0, "a valid unallocated cell has no source heat in the same supported segment")
	runner.assert_eq(_json(fixture.heat), before, "all past and future projections leave complete authoritative heat state unchanged")
	runner.assert_eq(fixture.world.roof_queries, roofs_before, "pure projection never samples roof geometry")
	runner.assert_eq(fixture.world.barrier_queries, barriers_before, "pure projection never samples wall or door geometry")
	_deposit(fixture, "warm:projection:2")
	runner.assert_eq(fixture.heat.project_tenths(Vector2i(100, 100), 4999), -1, "a completed source establishes a new anchor instead of pretending to retain earlier heat history")
	# MAX_COUNT lies 991ms past its previous global ten-second boundary;
	# start inside that actual final interval, not across two frozen segments.
	var limit: Dictionary = _make({}, SimInventory.MAX_COUNT - 500)
	_deposit(limit, "warm:limit")
	var limit_before: String = _json(limit.heat)
	var predicted: int = limit.heat.project_tenths(Vector2i(100, 100), SimInventory.MAX_COUNT)
	runner.assert_true(predicted >= 0, "the supported time maximum is an inclusive bounded projection endpoint")
	runner.assert_eq(_json(limit.heat), limit_before, "a maximum-time prediction cannot advance the original source before its world commits")
	_advance(limit, SimInventory.MAX_COUNT)
	runner.assert_eq(limit.heat.local_tenths(Vector2i(100, 100)), predicted, "actual integration at the supported maximum agrees with the prior pure projection")
	var resumed_limit: Dictionary = _make({}, SimInventory.MAX_COUNT)
	resumed_limit.world.artifacts.events = limit.world.artifacts.events.duplicate(true)
	runner.assert_true(resumed_limit.heat.restore(JSON.parse_string(_json(limit.heat))), "the saturated final segment and its exact source patch remain restorable")


func _history_and_restore(runner: Object) -> void:
	var fixture: Dictionary = _make()
	_deposit(fixture, "warm:1")
	_advance(fixture, 60000)
	runner.assert_true(fixture.heat.mark_sample(60000), "full minute stores a sparse historical thermal snapshot")
	var historical: Dictionary = fixture.heat.last_sample_cells.duplicate(true)
	var sensed: int = fixture.heat.sample_tenths(Vector2i(100, 100), 60000)
	_advance(fixture, 62563)
	_deposit(fixture, "warm:2")
	fixture.heat.before_topology_change(62563)
	fixture.world.roofed = true
	fixture.heat.after_topology_change(62563)
	runner.assert_eq(fixture.heat.last_sample_cells, historical, "a later source and roof cannot rewrite the already sampled minute")
	runner.assert_eq(fixture.heat.sample_tenths(Vector2i(100, 100), 60000), sensed, "historical cold validation never reads today's warmer live cell")
	runner.assert_eq(fixture.heat.sample_tenths(Vector2i(100, 100), 59999), 0, "the kernel does not invent unsupported earlier heat history")
	_advance(fixture, 66789)
	var data: Dictionary = JSON.parse_string(_json(fixture.heat))
	var resumed: Dictionary = _make({}, 66789)
	resumed.world.roofed = true
	resumed.world.artifacts.events = fixture.world.artifacts.events.duplicate(true)
	runner.assert_true(resumed.heat.restore(data), "actual JSON numeric roundtrip restores the off-lattice frozen segment and historical sample")
	runner.assert_eq(_json(resumed.heat), _json(fixture.heat), "restoration normalizes numeric values to the same complete thermal state")
	_advance(fixture, 151623)
	_advance(resumed, 151623, true)
	runner.assert_eq(_json(resumed.heat), _json(fixture.heat), "the restarted pure kernel has the same future despite a different calling cadence")


func _capacity_and_activation(runner: Object) -> void:
	var rules: Dictionary = _rules()
	rules.max_cells = 25
	var fixture: Dictionary = _make(rules, 456789)
	runner.assert_eq(fixture.heat.to_dict(), Heat.empty_state(456789), "old-world activation creates no fake historical room heat or source")
	runner.assert_true(_deposit(fixture, "warm:1", Vector2i(400, 400)), "a source in a distant world coordinate has no first-area gate")
	var before: String = _json(fixture.heat)
	runner.assert_true(not fixture.heat.can_deposit(Vector2i(100, 100), int(rules.pulse_energy)), "a new source exceeding the finite spatial budget is rejected before charge is spent")
	runner.assert_true(not _deposit(fixture, "warm:2", Vector2i(100, 100)), "spatial overload never silently discards existing heat")
	runner.assert_eq(_json(fixture.heat), before, "failed spatial allocation preserves existing source and energy state")
	runner.assert_true(not fixture.heat.can_deposit(Vector2i(-1, 0), int(rules.pulse_energy)), "out-of-world source coordinates are rejected")
	runner.assert_true(not fixture.heat.can_deposit(Vector2i(400, 400), int(rules.max_cell_energy)), "a full cell cannot accept an impulse past its declared capacity")
	var edges: Dictionary = _make()
	runner.assert_true(_deposit(edges, "warm:edge", Vector2i.ZERO), "a source at the world edge uses only real in-bounds cells")
	runner.assert_eq(edges.heat.cells.size(), 9, "world-edge activation clips the patch without allocating negative cells")


func _stable_residual_long_future(runner: Object) -> void:
	var fixture: Dictionary = _make()
	runner.assert_true(_deposit(fixture, "warm:1"), "stable residual comes from the ordinary finite source, without forged cell energy")
	for index: int in range(2000):
		if fixture.heat.flows.is_empty():
			break
		_advance(fixture, fixture.heat.next_boundary_ms())
	runner.assert_true(fixture.heat.flows.is_empty(), "ordinary integer cooling naturally reaches a no-flow residual")
	if not fixture.heat.flows.is_empty():
		return
	var residual: int = _energy(fixture.heat)
	runner.assert_true(residual > 0 and fixture.heat.input_energy > fixture.heat.loss_energy, "no-flow stability preserves the tiny real positive remainder")
	var invisible: bool = true
	for row: Dictionary in fixture.heat.cells.values():
		invisible = invisible and int(row.energy) < int(fixture.heat.definitions.capacity_per_tenth)
	runner.assert_true(invisible, "the actual default residual is below one tenth of a degree in every cell")
	runner.assert_eq(fixture.heat.next_boundary_ms(), SimInventory.MAX_COUNT, "nonzero but no-flow heat schedules no endless ten-second wakeup")
	var at_ms: int = fixture.world.elapsed_ms
	var sample_at: int = at_ms - posmod(at_ms, 60000) + 60000
	_advance(fixture, sample_at)
	runner.assert_true(fixture.heat.mark_sample(sample_at), "quiet heat still supports the original minute exposure sample")
	var data: Dictionary = JSON.parse_string(_json(fixture.heat))
	var resumed: Dictionary = _make({}, sample_at)
	resumed.world.artifacts.events = fixture.world.artifacts.events.duplicate(true)
	runner.assert_true(resumed.heat.restore(data), "real no-flow residual survives JSON and fresh-kernel restoration")
	var roof_before: int = fixture.world.roof_queries
	var barrier_before: int = fixture.world.barrier_queries
	var future: int = sample_at + 360 * 86400000 + 1623
	var before_prediction: String = _json(fixture.heat)
	runner.assert_eq(fixture.heat.project_tenths(Vector2i(100, 100), future), 0, "a no-flow residual supports a constant read-only projection across a year")
	runner.assert_eq(_json(fixture.heat), before_prediction, "long stable prediction neither commits time nor moves its historical segment anchor")
	_advance(fixture, future)
	for offset: int in [1, 39999, 86400000, 180 * 86400000 + 731]:
		_advance(resumed, sample_at + offset)
	_advance(resumed, future)
	runner.assert_eq(_json(resumed.heat), _json(fixture.heat), "year-long direct and unevenly split quiet futures have identical complete state")
	runner.assert_eq(_energy(fixture.heat), residual, "fast-forward never erases the conserved residual to manufacture silence")
	runner.assert_eq(_energy(fixture.heat) + fixture.heat.loss_energy, fixture.heat.input_energy, "input minus recorded loss still equals real heat after a year")
	runner.assert_eq(fixture.world.roof_queries, roof_before, "year-long stable settlement performs zero extra roof queries")
	runner.assert_eq(fixture.world.barrier_queries, barrier_before, "year-long stable settlement performs zero extra barrier queries")
	runner.assert_eq(fixture.heat.segment_started_ms, future, "quiet fast-forward anchors the empty segment at the actual save timestamp")
	var after_year: Dictionary = _make({}, future)
	after_year.world.artifacts.events = fixture.world.artifacts.events.duplicate(true)
	runner.assert_true(after_year.heat.restore(JSON.parse_string(_json(fixture.heat))), "year-long off-lattice quiet save remains a valid restore candidate")
	for candidate: Dictionary in [fixture, resumed, after_year]:
		runner.assert_true(_deposit(candidate, "warm:2"), "a real new source wakes the long-quiet fixed cells")
		runner.assert_true(candidate.heat.next_boundary_ms() < SimInventory.MAX_COUNT, "reactivated flux restores the aligned ten-second schedule")
		_advance(candidate, future + 17643, candidate == resumed)
	runner.assert_eq(_json(fixture.heat), _json(resumed.heat), "a new impulse after long quiet retains fine/coarse future equivalence")
	runner.assert_eq(_json(fixture.heat), _json(after_year.heat), "long-quiet full restart does not change the next real source response")
	# A genuinely insulating layout can be quiet while retaining useful heat.
	# Opening its actual roof must resample even though no timer was running.
	var rules: Dictionary = _rules()
	rules.source_radius = 0
	rules.bath_loss.roofed = 0
	for kind: String in rules.conductance:
		rules.conductance[kind] = 0
	var insulated: Dictionary = _make(rules)
	insulated.world.roofed = true
	_deposit(insulated, "warm:sealed")
	_advance(insulated, future)
	runner.assert_eq(insulated.heat.next_boundary_ms(), SimInventory.MAX_COUNT, "an actually insulated no-flow layout also sleeps without losing its energy")
	var retained: int = _energy(insulated.heat)
	insulated.heat.before_topology_change(future)
	insulated.world.roofed = false
	insulated.heat.after_topology_change(future)
	runner.assert_eq(_energy(insulated.heat), retained, "opening a quiet roof changes the future flux without resetting heat")
	runner.assert_true(insulated.heat.next_boundary_ms() < SimInventory.MAX_COUNT, "a real topology change wakes previously unscheduled heat exchange")
	_advance(insulated, future + 1234)
	runner.assert_true(insulated.heat.loss_energy > 0, "the newly exposed roof leaks only across its actual future interval")


func _exact_source_patches(runner: Object) -> void:
	var empty: Dictionary = _make()
	var vacant: Dictionary = empty.heat.to_dict()
	vacant.cells["400,400"] = {"cell": [400, 400], "energy": 0}
	runner.assert_true(not empty.heat.restore(vacant), "an unheated candidate cannot reserve spatial budget with a zero-energy phantom cell")
	runner.assert_true(empty.heat.cells.is_empty(), "phantom empty-world allocation is refused atomically")
	var fixture: Dictionary = _make()
	_deposit(fixture, "warm:patch")
	var before: String = _json(fixture.heat)
	var ghost: Dictionary = fixture.heat.to_dict()
	ghost.cells["400,400"] = {"cell": [400, 400], "energy": 0}
	runner.assert_true(not fixture.heat.restore(ghost), "a real source cannot authorize an unrelated zero-energy spatial allocation")
	runner.assert_eq(_json(fixture.heat), before, "rejecting an extra patch cell leaves all heat and source receipts intact")
	var missing: Dictionary = fixture.heat.to_dict()
	runner.assert_eq(missing.cells["98,98"].energy, 0, "the counterexample removes a genuinely cold corner, without altering total energy or active flux")
	missing.cells.erase("98,98")
	runner.assert_true(not fixture.heat.restore(missing), "a source's unheated corner is still part of its actual complete allocated patch")
	runner.assert_eq(_json(fixture.heat), before, "rejecting a missing patch cell never changes the existing finite spatial domain")
	_deposit(fixture, "warm:overlap", Vector2i(101, 100))
	runner.assert_eq(fixture.heat.cells.size(), 30, "two overlapping actual sources own the exact spatial union rather than two copies of shared cells")
	runner.assert_true(fixture.heat.restore(JSON.parse_string(_json(fixture.heat))), "overlapping complete source patches remain a valid candidate after JSON")
	var edge: Dictionary = _make()
	_deposit(edge, "warm:edge", Vector2i.ZERO)
	runner.assert_true(edge.heat.restore(JSON.parse_string(_json(edge.heat))), "exact patch validation respects the real clipped domain at a world edge")


func _bad_candidates(runner: Object) -> void:
	var fixture: Dictionary = _make()
	_deposit(fixture, "warm:1")
	_advance(fixture, 60000)
	fixture.heat.mark_sample(60000)
	_advance(fixture, 61234)
	var data: Dictionary = fixture.heat.to_dict()
	var before: String = _json(fixture.heat)
	var candidates: Array[Dictionary] = []
	var bad: Dictionary = data.duplicate(true)
	bad.cells["100,100"].energy = int(bad.cells["100,100"].energy) + 1
	candidates.append(bad)
	bad = data.duplicate(true)
	bad.receipts["warm:1"].object = "forged_stone"
	candidates.append(bad)
	bad = data.duplicate(true)
	bad.receipts.clear()
	candidates.append(bad)
	bad = data.duplicate(true)
	bad.flows[0].rate = int(bad.flows[0].rate) + 1
	candidates.append(bad)
	bad = data.duplicate(true)
	bad.last_sample_cells["100,100"] = int(bad.last_sample_cells["100,100"]) + 1
	candidates.append(bad)
	bad = data.duplicate(true)
	bad.activation_ms = 61234
	candidates.append(bad)
	for index: int in range(candidates.size()):
		runner.assert_true(not fixture.heat.restore(candidates[index]), "invalid energy, receipt, slope or historical sample candidate %d is refused" % index)
		runner.assert_eq(_json(fixture.heat), before, "invalid candidate %d never partially mutates live heat" % index)
	fixture.world.artifacts.events.append({"action": "unreceipted", "actor": "player", "object": "warm_stone", "at_ms": 60001, "cell": [100, 100], "kind": "warmed"})
	runner.assert_true(not fixture.heat.restore(data), "every real warmed source must have a corresponding receipt, in both directions")
	runner.assert_eq(_json(fixture.heat), before, "missing reverse source correspondence is atomically rejected")
