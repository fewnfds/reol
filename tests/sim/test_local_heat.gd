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
	var climate_boundary_x: int = 256
	var west_background: int = 0
	var east_background: int = 0
	var background_schedule: Array[Dictionary] = []


	func roof(_cell: Vector2i) -> bool:
		roof_queries += 1
		return roofed


	func barrier(cell: Vector2i) -> Variant:
		barrier_queries += 1
		return barriers.get("%d,%d" % [cell.x, cell.y], "open")


	func background(cell: Vector2i, at_ms: int) -> int:
		var region: String = "west" if cell.x < climate_boundary_x else "east"
		var value: int = west_background if region == "west" else east_background
		for change: Dictionary in background_schedule:
			if int(change.at_ms) <= at_ms and change.has(region):
				value = int(change[region])
		return value


	func background_boundary(cell: Vector2i, at_ms: int) -> int:
		var region: String = "west" if cell.x < climate_boundary_x else "east"
		var next: int = SimInventory.MAX_COUNT
		for change: Dictionary in background_schedule:
			if change.has(region) and int(change.at_ms) > at_ms:
				next = mini(next, int(change.at_ms))
		return next


func run(runner: Object) -> void:
	_topology_preflight(runner)
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
	print("SCENARIO local heat: fixed-reference cell energy with explicit ambient allocation, conservative integer flux, arbitrary split equivalence, old-layout settlement, historical samples and atomic receipt validation")


func _rules() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/local_heat.json"))


func _make(rules: Dictionary = {}, at_ms: int = 0) -> Dictionary:
	var authority := Authority.new()
	authority.elapsed_ms = at_ms
	var heat := Heat.new()
	var configured: bool = heat.initialize(authority, _rules() if rules.is_empty() else rules)
	heat.set_background(Callable(authority, "background"), Callable(authority, "background_boundary"))
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


func _zero_background_cell_energy(heat: RefCounted) -> int:
	return -int(heat.definitions.reference_tenths) * int(heat.definitions.capacity_per_tenth)


func _reference_baseline_energy(heat: RefCounted) -> int:
	# These legacy-dynamics scenarios explicitly bind constant 0°C background.
	# Their Q includes the fixed-reference baseline in every allocated cell.
	return _zero_background_cell_energy(heat) * heat.cells.size()


func _json(heat: RefCounted) -> String:
	return JSON.stringify(heat.to_dict(), "", true, true)


func _definitions(runner: Object) -> void:
	runner.assert_true(Heat.valid_definitions(_rules()), "default local heat rules have safe integer outflow bounds")
	runner.assert_eq(_rules().version, 3, "current heat definitions include fixed-reference device exchange")
	runner.assert_eq(_rules().reference_tenths, -10000, "cell energy uses the declared fixed temperature reference")
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
	runner.assert_eq(_energy(fixture.heat), _reference_baseline_energy(fixture.heat) + int(fixture.heat.definitions.pulse_energy), "activation allocates background Q and adds the complete source without earlier leakage")
	runner.assert_eq(fixture.heat.cells.size(), 25, "default source activates a bounded five-by-five fixed spatial patch")
	runner.assert_eq(fixture.heat.ambient_in, _reference_baseline_energy(fixture.heat), "the allocated reference baseline enters through the exterior ledger")
	for now: int in [1, 9999, 10000, 10001, 17343, 60000, 121623]:
		_advance(fixture, now)
		runner.assert_eq(_energy(fixture.heat) + fixture.heat.loss_energy, fixture.heat.input_energy + fixture.heat.ambient_in, "cell Q and declared exterior exchanges conserve at %dms" % now)
		var nonnegative: bool = true
		for row: Dictionary in fixture.heat.cells.values():
			nonnegative = nonnegative and int(row.energy) >= 0
		runner.assert_true(nonnegative, "frozen flux never overdraws a cell at %dms" % now)
	runner.assert_true(fixture.heat.loss_energy > 0, "finite unroofed space loses energy to its explicit exterior bath")
	runner.assert_true(fixture.heat.cells["101,100"].energy > _zero_background_cell_energy(fixture.heat), "neighboring fixed space receives source energy above its allocated baseline")


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


func _topology_snapshot(fixture: Dictionary) -> Dictionary:
	# Do not call to_dict(): it resolves dirty geometry and would conceal a
	# preflight that mutated the original segment or performed a freeze.
	var heat: SimLocalHeat = fixture.heat
	return {"world_ms": int(fixture.world.elapsed_ms), "last_ms": heat.last_ms,
		"segment_started_ms": heat.segment_started_ms, "boundary_ms": heat.next_boundary_ms(),
		"cells": heat.cells.duplicate(true), "flows": heat.flows.duplicate(true),
		"input_energy": heat.input_energy, "continuous_input": heat.continuous_input,
		"absorbed_energy": heat.absorbed_energy, "ambient_in": heat.ambient_in,
		"loss_energy": heat.loss_energy, "device_input": heat.device_input.duplicate(true),
		"device_absorbed": heat.device_absorbed.duplicate(true),
		"device_switches": heat.device_switches.duplicate(true), "receipts": heat.receipts.duplicate(true),
		"last_sample_ms": heat.last_sample_ms, "last_sample_cells": heat.last_sample_cells.duplicate(true),
		"last_sample_input": heat.last_sample_input, "last_sample_loss": heat.last_sample_loss,
		"last_sample_ambient_in": heat.last_sample_ambient_in,
		"last_sample_continuous_input": heat.last_sample_continuous_input,
		"last_sample_absorbed": heat.last_sample_absorbed, "last_sample_mode": heat.last_sample_mode,
		"geometry_dirty": heat._geometry_dirty, "roof_queries": int(fixture.world.roof_queries),
		"barrier_queries": int(fixture.world.barrier_queries)}


func _topology_preflight(runner: Object) -> void:
	var footprint: Array[Vector2i] = [Vector2i(100, 100), Vector2i.ZERO, Vector2i(511, 511)]
	var empty: Array[Vector2i] = []
	var fixture: Dictionary = _make()
	runner.assert_true(_deposit(fixture, "warm:preflight"), "topology preflight uses a real finite heat source")
	_advance(fixture, 137)
	var before: Dictionary = _topology_snapshot(fixture)
	runner.assert_true(fixture.heat.can_change_topology(137, footprint), "current bounded nonempty topology footprint can be preflighted")
	runner.assert_true(not fixture.heat.can_change_topology(137, empty), "an empty topology footprint is refused")
	for outside: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(512, 0), Vector2i(0, 512)]:
		var invalid: Array[Vector2i] = [Vector2i(100, 100), outside]
		runner.assert_true(not fixture.heat.can_change_topology(137, invalid), "every changed coordinate must lie inside the world: %s" % outside)
	runner.assert_true(not fixture.heat.can_change_topology(136, footprint), "a past instant cannot preflight a topology change")
	runner.assert_true(not fixture.heat.can_change_topology(138, footprint), "a future instant cannot preflight before heat is synchronized")
	runner.assert_eq(_topology_snapshot(fixture), before, "successful and refused preflights do not settle, dirty, alter Q or query geometry")
	runner.assert_true(not fixture.heat.before_topology_change(136), "a before hook cannot settle backward")
	runner.assert_eq(_topology_snapshot(fixture), before, "a past before hook leaves the original frozen state clean")
	fixture.world.elapsed_ms = 138
	before = _topology_snapshot(fixture)
	runner.assert_true(not fixture.heat.can_change_topology(138, footprint), "a world instant ahead of the heat clock is refused instead of settled")
	runner.assert_eq(_topology_snapshot(fixture), before, "an unsynchronized preflight leaves both clocks and the original field untouched")

	var unresolved: Dictionary = _make()
	runner.assert_true(_deposit(unresolved, "warm:unresolved_topology"), "unresolved topology case starts from actual heat")
	runner.assert_true(unresolved.heat.before_topology_change(0), "a current before hook opens the topology transaction")
	before = _topology_snapshot(unresolved)
	runner.assert_true(not unresolved.heat.can_change_topology(0, footprint), "a live nonempty field with unresolved geometry cannot pass preflight")
	runner.assert_true(not unresolved.heat.before_topology_change(-1), "a repeated before hook still refuses a past instant")
	runner.assert_eq(_topology_snapshot(unresolved), before, "refused preflight and past before hook leave already dirty geometry unresolved without querying it")
	unresolved.heat.after_topology_change(0)
	runner.assert_true(unresolved.heat.can_change_topology(0, footprint), "a completed topology transaction can be preflighted again")

	_topology_exhausted_ledger(runner, footprint)
	_topology_preflight_future(runner, footprint)


func _topology_exhausted_ledger(runner: Object, footprint: Array[Vector2i]) -> void:
	var rules: Dictionary = _rules()
	rules.source_radius = 0
	rules.max_exchange_energy = -int(rules.reference_tenths) * int(rules.capacity_per_tenth)
	var fixture: Dictionary = _make(rules)
	runner.assert_true(fixture.configured, "finite exchange budget uses valid heat definitions")
	fixture.world.background_schedule.append({"at_ms": 1, "west": 1000, "east": 1000})
	runner.assert_true(_deposit(fixture, "warm:bounded_exchange"), "a real source fills the bounded ambient allocation")
	runner.assert_eq(int(fixture.heat.ambient_in), int(rules.max_exchange_energy), "original cell allocation exhausts the actual ambient input budget")
	fixture.world.elapsed_ms = 1
	runner.assert_true(fixture.heat.settle_at_ms(1), "the actual weather boundary settles before the exchange is exhausted")
	var incoming: bool = false
	for flow: Dictionary in fixture.heat.flows:
		incoming = incoming or (str(flow.from).is_empty() and int(flow.rate) > 0)
	runner.assert_true(incoming, "warmer background creates a genuine incoming heat slope after the boundary")
	var before: Dictionary = _topology_snapshot(fixture)
	runner.assert_true(fixture.heat.can_change_topology(1, footprint), "zero elapsed time can preflight even when the ambient ledger is full")
	runner.assert_true(not fixture.heat.can_settle_at_ms(2), "the next real interval cannot borrow from an exhausted ambient ledger")
	runner.assert_eq(_topology_snapshot(fixture), before, "budget checks do not alter the full ledger or physical field")
	fixture.world.elapsed_ms = 2
	before = _topology_snapshot(fixture)
	runner.assert_true(not fixture.heat.can_change_topology(2, footprint), "the unsynchronized post-exhaustion instant cannot pass topology preflight")
	runner.assert_true(not fixture.heat.before_topology_change(2), "a before hook reports the failed physical settlement")
	runner.assert_eq(_topology_snapshot(fixture), before, "failed settlement neither advances Q nor falsely marks geometry dirty")


func _topology_preflight_future(runner: Object, footprint: Array[Vector2i]) -> void:
	var with_preflight: Dictionary = _make()
	var reference: Dictionary = _make()
	for fixture: Dictionary in [with_preflight, reference]:
		runner.assert_true(_deposit(fixture, "warm:preflight_future"), "the compared topology futures start from the same real source")
		_advance(fixture, 1250)
	var before: Dictionary = _topology_snapshot(with_preflight)
	runner.assert_true(with_preflight.heat.can_change_topology(1250, footprint), "the normal topology transaction passes preflight")
	runner.assert_eq(_topology_snapshot(with_preflight), before, "successful preflight leaves the existing thermal trajectory unmodified")
	for fixture: Dictionary in [with_preflight, reference]:
		var original_q: int = _energy(fixture.heat)
		runner.assert_true(fixture.heat.before_topology_change(1250), "the settled topology before hook succeeds")
		runner.assert_true(fixture.heat.before_topology_change(1250), "a repeated same-instant before hook is harmless")
		fixture.world.roofed = true
		fixture.world.barriers["101,100"] = "closed_door"
		fixture.heat.after_topology_change(1250)
		runner.assert_eq(_energy(fixture.heat), original_q, "roof and door changes do not create heat at the mutation instant")
	runner.assert_eq(_json(with_preflight.heat), _json(reference.heat), "preflight and direct before/after preserve the same frozen segment and ledger")
	_advance(with_preflight, 17463, true)
	_advance(reference, 17463)
	runner.assert_eq(_json(with_preflight.heat), _json(reference.heat), "the preflighted topology has the same unevenly sliced physical future")


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


func _projection_supported(runner: Object, result: Dictionary, label: String) -> bool:
	var valid: bool = result.size() == 2 and result.get("supported") is bool and result.supported and result.has("value") and result.value is int
	runner.assert_true(valid, label + " returns a supported integer value without a failure reason")
	return valid


func _projection_matches(runner: Object, result: Dictionary, expected: int, label: String) -> void:
	if _projection_supported(runner, result, label):
		runner.assert_eq(result.value, expected, label)


func _projection_unsupported(runner: Object, result: Dictionary, reason: String, label: String) -> void:
	var valid: bool = result.size() == 2 and result.get("supported") is bool and not result.supported and result.get("reason") is String and not result.has("value")
	runner.assert_true(valid, label + " returns a reason without a temperature value")
	if valid:
		runner.assert_eq(result.reason, reason, label + " identifies the failure")


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
	_projection_matches(runner, fixture.heat.project_tenths(Vector2i(100, 100), 2000), historical.heat.local_tenths(Vector2i(100, 100)), "same-segment reverse projection reconstructs the actual former source-cell heat")
	_projection_matches(runner, fixture.heat.project_tenths(Vector2i(101, 100), 2000), historical.heat.local_tenths(Vector2i(101, 100)), "same-segment reverse projection also reverses actual paired incoming heat")
	var continued: Dictionary = _make({}, 5000)
	continued.world.artifacts.events = fixture.world.artifacts.events.duplicate(true)
	runner.assert_true(continued.heat.restore(JSON.parse_string(before)), "prediction comparison uses an independently restored actual frozen segment")
	for at_ms: int in [5000, 6666, 9999, 10000]:
		_advance(continued, at_ms)
		for cell: Vector2i in [Vector2i(100, 100), Vector2i(101, 100)]:
			_projection_matches(runner, fixture.heat.project_tenths(cell, at_ms), continued.heat.local_tenths(cell), "pure prediction matches actual integration through its inclusive next boundary at %dms/%s" % [at_ms, cell])
	for time_and_reason: Array in [[-1, "invalid_time"], [1369, "history_unavailable"], [10001, "beyond_boundary"], [SimInventory.MAX_COUNT + 1, "invalid_time"]]:
		_projection_unsupported(runner, fixture.heat.project_tenths(Vector2i(100, 100), int(time_and_reason[0])), str(time_and_reason[1]), "unsupported projection at %dms" % int(time_and_reason[0]))
	_projection_unsupported(runner, fixture.heat.project_tenths(Vector2i(-1, 0), 6000), "invalid_cell", "projection rejects an invalid spatial target")
	_projection_matches(runner, fixture.heat.project_tenths(Vector2i(400, 400), 6000), 0, "a valid unallocated cell has no source heat in the same supported segment")
	runner.assert_eq(fixture.heat.current_tenths(Vector2i(100, 100)), fixture.heat.local_tenths(Vector2i(100, 100)), "pure current query reports the same committed offset as the settled convenience accessor")
	runner.assert_eq(_json(fixture.heat), before, "all past and future projections leave complete authoritative heat state unchanged")
	runner.assert_eq(fixture.world.roof_queries, roofs_before, "pure projection never samples roof geometry")
	runner.assert_eq(fixture.world.barrier_queries, barriers_before, "pure projection never samples wall or door geometry")
	_deposit(fixture, "warm:projection:2")
	_projection_unsupported(runner, fixture.heat.project_tenths(Vector2i(100, 100), 4999), "history_unavailable", "a completed source establishes a new anchor instead of pretending to retain earlier heat history")
	var uninitialized := Heat.new()
	_projection_unsupported(runner, uninitialized.project_tenths(Vector2i(100, 100), 0), "uninitialized", "projection rejects an uninitialized heat authority")
	var unresolved: Dictionary = _make()
	_deposit(unresolved, "warm:unresolved")
	_advance(unresolved, 5000)
	unresolved.heat.before_topology_change(5000)
	_projection_unsupported(runner, unresolved.heat.project_tenths(Vector2i(100, 100), 5001), "geometry_unresolved", "projection does not invent a slope while changed geometry is unresolved")
	var inconsistent: Dictionary = _make()
	_deposit(inconsistent, "warm:inconsistent")
	# Forge a damaged in-memory state only in this isolated fixture: its frozen
	# outgoing flow cannot be applied to the now-empty original source cell.
	runner.assert_eq(inconsistent.heat.storage_summary().q_slots, inconsistent.heat.cell_count(), "custom-background corruption fixture keeps original fine ownership")
	inconsistent.heat._cell_store.fine["100,100"].energy = 0
	_projection_unsupported(runner, inconsistent.heat.project_tenths(Vector2i(100, 100), 1), "inconsistent_projection", "projection rejects a slope that would overdraw its source")
	# MAX_COUNT lies 991ms past its previous global ten-second boundary;
	# start inside that actual final interval, not across two frozen segments.
	var limit: Dictionary = _make({}, SimInventory.MAX_COUNT - 500)
	_deposit(limit, "warm:limit")
	var limit_before: String = _json(limit.heat)
	var predicted: Dictionary = limit.heat.project_tenths(Vector2i(100, 100), SimInventory.MAX_COUNT)
	var limit_supported: bool = _projection_supported(runner, predicted, "the supported time maximum is an inclusive bounded projection endpoint")
	runner.assert_eq(_json(limit.heat), limit_before, "a maximum-time prediction cannot advance the original source before its world commits")
	_advance(limit, SimInventory.MAX_COUNT)
	if limit_supported:
		runner.assert_eq(limit.heat.local_tenths(Vector2i(100, 100)), predicted.value, "actual integration at the supported maximum agrees with the prior pure projection")
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
	runner.assert_true(residual > _reference_baseline_energy(fixture.heat) and fixture.heat.input_energy > fixture.heat.loss_energy, "no-flow stability preserves the tiny positive remainder above background Q")
	var invisible: bool = true
	for row: Dictionary in fixture.heat.cells.values():
		invisible = invisible and int(row.energy) - _zero_background_cell_energy(fixture.heat) < int(fixture.heat.definitions.capacity_per_tenth)
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
	_projection_matches(runner, fixture.heat.project_tenths(Vector2i(100, 100), future), 0, "a no-flow residual supports a constant read-only projection across a year")
	runner.assert_eq(_json(fixture.heat), before_prediction, "long stable prediction neither commits time nor moves its historical segment anchor")
	_advance(fixture, future)
	for offset: int in [1, 39999, 86400000, 180 * 86400000 + 731]:
		_advance(resumed, sample_at + offset)
	_advance(resumed, future)
	runner.assert_eq(_json(resumed.heat), _json(fixture.heat), "year-long direct and unevenly split quiet futures have identical complete state")
	runner.assert_eq(_energy(fixture.heat), residual, "fast-forward never erases the conserved residual to manufacture silence")
	runner.assert_eq(_energy(fixture.heat) + fixture.heat.loss_energy, fixture.heat.input_energy + fixture.heat.ambient_in, "source and ambient input minus recorded outflow still equal real Q after a year")
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
	var corner_energy: int = int(missing.cells["98,98"].energy)
	runner.assert_eq(corner_energy, _zero_background_cell_energy(fixture.heat), "counterexample removes a corner at pure background, with no source excess or active flux")
	missing.ambient_in = int(missing.ambient_in) - corner_energy
	missing.cells.erase("98,98")
	runner.assert_eq(_energy_from_state(missing) + int(missing.loss_energy), int(missing.input_energy) + int(missing.ambient_in), "missing-corner candidate preserves energy balance so source coverage must reject it")
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
	bad = data.duplicate(true)
	bad.ambient_in += 1
	candidates.append(bad)
	bad = data.duplicate(true)
	bad.model_started_ms = 61235
	candidates.append(bad)
	bad = data.duplicate(true)
	bad.last_sample_ambient_in += 1
	candidates.append(bad)
	bad = data.duplicate(true)
	bad.last_sample_mode = "unsupported_mode"
	candidates.append(bad)
	bad = data.duplicate(true)
	bad.ambient_in = SimInventory.MAX_COUNT
	candidates.append(bad)
	for index: int in range(candidates.size()):
		runner.assert_true(not fixture.heat.restore(candidates[index]), "invalid energy, receipt, slope or historical sample candidate %d is refused" % index)
		runner.assert_eq(_json(fixture.heat), before, "invalid candidate %d never partially mutates live heat" % index)
	fixture.world.artifacts.events.append({"action": "unreceipted", "actor": "player", "object": "warm_stone", "at_ms": 60001, "cell": [100, 100], "kind": "warmed"})
	runner.assert_true(not fixture.heat.restore(data), "every real warmed source must have a corresponding receipt, in both directions")
	runner.assert_eq(_json(fixture.heat), before, "missing reverse source correspondence is atomically rejected")


func _energy_from_state(state: Dictionary) -> int:
	var sum: int = 0
	for row: Dictionary in state.cells.values():
		sum += int(row.energy)
	return sum
