extends RefCounted
## One-pass reuse is explicit; custom callbacks keep their original trace.

const Devices = preload("res://tests/sim/test_thermal_devices.gd")
var _devices := Devices.new()


class GeometrySpy extends RefCounted:
	var construction: SimConstruction
	var trace: Array[Vector2i] = []
	var closed: bool = false

	func barrier(cell: Vector2i) -> bool:
		trace.append(cell)
		return closed or construction.thermal_barrier(cell)

	func roof(cell: Vector2i) -> bool:
		return construction.thermal_roofed(cell)


class ChangingBackground extends RefCounted:
	var geometry: GeometrySpy
	var calls: int = 0

	func query(_cell: Vector2i, _at_ms: int) -> int:
		calls += 1
		geometry.closed = calls % 2 == 0
		return 215


func run(runner: Object) -> void:
	var world: RegionalSimulation = _devices._world(runner)
	if world == null or not _devices._action(runner, world, "player", "study", Devices.FIRE) or not _devices._action(runner, world, "player", "enable", Devices.FIRE):
		return
	var reached: bool = world.advance_to_ms(int(world.elapsed_ms) + 5731)
	runner.assert_true(reached, "the actual finite source reaches the non-boundary heat checkpoint")
	if not reached:
		return
	var before: Dictionary = world.to_dict()
	var heat: SimLocalHeat = world.environment_fields
	var spy := GeometrySpy.new()
	spy.construction = world.construction
	heat.set_geometry(spy.roof, spy.barrier)
	var original: Array[Dictionary] = heat._candidate_flows(heat.cells, heat.last_ms)
	var original_trace: Array[Vector2i] = spy.trace.duplicate()
	runner.assert_eq(original_trace.size(), heat.cells.size() * 8, "default provider retains the original two barrier reads per side")
	spy.trace.clear()
	heat.set_geometry(spy.roof, spy.barrier, true)
	var reused: Array[Dictionary] = heat._candidate_flows(heat.cells, heat.last_ms)
	runner.assert_eq(_json(reused), _json(original), "one-pass reuse preserves every ordered candidate flow and integer rate")
	var unique: Dictionary = {}
	for cell: Vector2i in spy.trace:
		unique[cell] = true
	runner.assert_eq(spy.trace.size(), unique.size(), "opted-in barrier is evaluated at most once per cell within a pass")
	runner.assert_true(spy.trace.size() < original_trace.size(), "real patch reuse removes redundant wall queries")
	spy.trace.clear()
	spy.closed = true
	var closed: Array[Dictionary] = heat._candidate_flows(heat.cells, heat.last_ms)
	runner.assert_true(_json(closed) != _json(original), "the next pass reads changed geometry instead of retaining stale conductance")
	spy.trace.clear()
	heat.set_geometry(spy.roof, spy.barrier)
	var closed_reference: Array[Dictionary] = heat._candidate_flows(heat.cells, heat.last_ms)
	runner.assert_eq(_json(closed), _json(closed_reference), "changed geometry has the same rates with and without reuse")
	runner.assert_eq(spy.trace, original_trace, "rebinding without the third argument restores original callback order and count")

	# An arbitrary background may change a geometry provider between reads.
	# Explicit geometry opt-in must not cache across those custom callbacks.
	var background := ChangingBackground.new()
	background.geometry = spy
	heat.set_background(background.query, Callable())
	spy.trace.clear()
	spy.closed = false
	background.calls = 0
	var custom_reference: Array[Dictionary] = heat._candidate_flows(heat.cells, heat.last_ms)
	var custom_trace: Array[Vector2i] = spy.trace.duplicate()
	var background_calls: int = background.calls
	heat.set_geometry(spy.roof, spy.barrier, true)
	spy.trace.clear()
	spy.closed = false
	background.calls = 0
	var custom_requested: Array[Dictionary] = heat._candidate_flows(heat.cells, heat.last_ms)
	runner.assert_eq(_json(custom_requested), _json(custom_reference), "custom background preserves original values even when it changes geometry between calls")
	runner.assert_eq(spy.trace, custom_trace, "custom background keeps original geometry callback trace despite explicit opt-in")
	runner.assert_eq(background.calls, background_calls, "custom background callback count is unchanged")

	heat.set_background(Callable(), Callable())
	heat.set_geometry(world.construction.thermal_roofed, world.construction.thermal_barrier, true)
	runner.assert_true(heat.restore(before.local_heat), "the original frozen segment restores after temporary query-provider bindings")
	runner.assert_eq(_json(world.to_dict()), _json(before), "query comparisons changed no Q, balance, actor, event or physical time")
	runner.assert_true(not before.local_heat.has("reuse_within_pass") and not before.local_heat.has("_reuse_conductance_within_pass"), "provider reuse policy is not a second saved physical state")

	var candidate: RegionalSimulation = _devices._world(runner)
	if candidate == null or not candidate.restore(JSON.parse_string(_json(before))):
		runner.assert_true(false, "original full JSON candidate restores")
		return
	# The reference runs with the original provider behavior; the independent
	# current candidate retains the production opt-in configured by restoration.
	heat.set_geometry(world.construction.thermal_roofed, world.construction.thermal_barrier)
	runner.assert_true(heat.restore(before.local_heat), "reference retains its exact old frozen anchor with reuse disabled")
	var target: int = int(world.elapsed_ms) + 27337
	runner.assert_true(world.advance_to_ms(target), "uncached physical world reaches the future")
	runner.assert_true(candidate.advance_to_ms(target - 20000) and candidate.advance_to_ms(target - 1) and candidate.advance_to_ms(target), "restored cached world reaches the same future in different slices")
	runner.assert_eq(_json(candidate.to_dict()), _json(world.to_dict()), "production reuse and uncached reference have the same complete future")
	_devices._conserved(runner, world, "uncached future conserves actual source/field energy")
	_devices._conserved(runner, candidate, "cached future conserves actual source/field energy")
	print("SCENARIO heat geometry reuse: stable opt-in, original custom callback trace, no cross-pass cache, complete JSON/sliced future and original stock conservation")


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
