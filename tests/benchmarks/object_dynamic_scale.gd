extends SceneTree
## Real multi-cell bodies, shared-clock progression and actual navigation calls.
## Run under an external process guard. Example:
## godot --headless --path . --script res://tests/benchmarks/object_dynamic_scale.gd -- --count 8
## Current production definitions cap this domain at 8; larger requests fail.

const Fixture = preload("res://tests/sim/test_regional_simulation.gd")
const EntityQuery = preload("res://scripts/sim/entity_query.gd")
const SPAN_MS: int = 60_000
const SLICE_MS: int = 500
const EVENT_BUDGET: int = 1
const QUERY_SAMPLES: int = 128
const SEED: int = 6162026
const CHUNK_CELLS: int = 64

var _fixture := Fixture.new()
var _fixture_failures: Array[String] = []
var _report: Dictionary = {
	"benchmark": "object_dynamic_scale",
	"ok": false,
	"scope": "two-region real simulation fixture; flat test map; bounded roaming large bodies",
	"limits": "No rendering, FPS, GPU, RSS, full NPC behavior, combat, ordinary game capacity, save/load or separate-process restart measured.",
	"first_failure": null,
}


class FlatMap extends WorldMapData:
	func get_terrain(cell: Vector2i) -> int:
		return TERRAIN_GRASS if in_bounds(cell) else -1

	func get_elevation(cell: Vector2i) -> int:
		return 0 if in_bounds(cell) else -1


class MonitoredLargeBodies extends SimLargeBodies:
	## Test-only override records actual calls before/after original pathfinding.
	var path_calls: int = 0
	var path_successes: int = 0
	var path_failures: int = 0
	var max_endpoint_distance_cells: int = 0
	var max_path_cells: int = 0
	var path_cost_us: Array[int] = []

	func _path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
		path_calls += 1
		max_endpoint_distance_cells = maxi(max_endpoint_distance_cells, maxi(absi(a.x - b.x), absi(a.y - b.y)))
		var begin: int = Time.get_ticks_usec()
		var result: Array[Vector2i] = super._path(a, b)
		path_cost_us.append(Time.get_ticks_usec() - begin)
		if result.is_empty():
			path_failures += 1
		else:
			path_successes += 1
			max_path_cells = maxi(max_path_cells, result.size())
		return result


func _initialize() -> void:
	call_deferred("_run")


func assert_true(condition: bool, label: String) -> void:
	if not condition:
		_fixture_failures.append(label)


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fixture_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _run() -> void:
	var options: Dictionary = _arguments(OS.get_cmdline_user_args())
	if not bool(options.get("ok", false)):
		_fail("arguments", options)
		return
	var requested: int = int(options.count)
	_report["requested_bodies"] = requested
	_report["actual_bodies"] = 0
	_report["seed"] = SEED
	_report["engine"] = Engine.get_version_info()
	_report["processor"] = OS.get_processor_name()
	_report["logical_processors"] = OS.get_processor_count()
	_report["memory_scope"] = "Godot static allocation counters only; not process RSS or machine/GPU memory"
	_report["memory_static_before_bytes"] = OS.get_static_memory_usage()
	_report["guard"] = "external process guard required; script does not set a resource limit"
	var setup_start: int = Time.get_ticks_usec()
	var world: RegionalSimulation = _fixture._make_world(self)
	if world == null or not _fixture_failures.is_empty():
		_fail("world_fixture_failed", {"assertions": _fixture_failures})
		return
	if world.large_bodies == null or not world.large_bodies.bodies.is_empty():
		_fail("fixture_requires_empty_large_body_owner")
		return
	var existing: SimLargeBodies = world.large_bodies
	var capacity: int = int(existing.definitions.max_bodies)
	_report["configured_body_limit"] = capacity
	_report["body_limit_reason"] = "Production large-body definitions validate max_bodies <= 8; no limit was changed for this benchmark."
	_report["fixture_setup_ms"] = _elapsed_ms(setup_start)
	if requested > capacity:
		_fail("requested_above_real_body_limit", {"requested": requested, "maximum": capacity, "created": 0})
		return
	var domain := MonitoredLargeBodies.new()
	if not domain.initialize(world, existing.definitions):
		_fail("instrumented_owner_initialize_failed")
		return
	world.large_bodies = domain
	world.bind_map_data(FlatMap.new())
	if domain.size() != Vector2i(3, 3):
		_fail("unexpected_footprint", {"size": [domain.size().x, domain.size().y]})
		return
	_report["instrumentation"] = "Test-only subclass wraps the original _path implementation; all actual creation, bodies, clocks and occupancy remain owned by the real simulation."
	_report["definition"] = {"form": domain.definitions.form, "footprint": [3, 3],
		"max_bodies": capacity, "step_ms": domain.definitions.step_ms, "rest_ms": domain.definitions.rest_ms,
		"navigation_radius": domain.definitions.navigation_radius, "navigation_budget": domain.definitions.navigation_budget}
	_report["people"] = _people(world)
	var positions: Dictionary = {}
	var ids: Array[String] = []
	var create_start: int = Time.get_ticks_usec()
	for i: int in requested:
		var id: String = "bench_body_%d" % i
		# These separate 3x3 lanes cross the 64-cell x boundary, away from villages.
		var a := Vector2i(61, 10 + i * 8)
		var b := Vector2i(65, 10 + i * 8)
		if not domain.add_body(id, "benchmark body %d" % i, "home", a, b):
			_report["creation_ms"] = _elapsed_ms(create_start)
			_fail("add_body_failed", {"id": id, "start": [a.x, a.y], "end": [b.x, b.y], "created": ids.size(), "path_calls": domain.path_calls})
			return
		if not world.embodiment.controls(SimLargeBodies.subject_id(id), SimLargeBodies.carrier_id(id), "motion"):
			_fail("body_subject_or_motion_identity_missing", {"id": id})
			return
		ids.append(id)
		positions[id] = {"start": domain.point(id), "chunk": _chunk(domain.body_cell(id)), "moved": false, "crossed": false}
		_report.actual_bodies = ids.size()
	_report["creation_ms"] = _elapsed_ms(create_start)
	_report["creation_scope"] = "public add_body including real embodiment identity and path preflight"
	_report["navigation_after_creation"] = _navigation(domain)
	_report["memory_static_after_creation_bytes"] = OS.get_static_memory_usage()
	if not domain.space_valid():
		_fail("initial_footprints_overlap_or_are_invalid")
		return
	var progressed: Dictionary = _advance(world, domain, ids, positions)
	if not bool(progressed.get("ok", false)):
		_fail("advance_failed", progressed)
		return
	_report["progression"] = progressed
	var queries: Dictionary = _queries(world, domain, ids)
	if not bool(queries.get("ok", false)):
		_fail("body_query_failed", queries)
		return
	_report["queries"] = queries
	_report["navigation_final"] = _navigation(domain)
	_report["memory_static_peak_bytes"] = OS.get_static_memory_peak_usage()
	_report["memory_static_end_bytes"] = OS.get_static_memory_usage()
	_report["ok"] = true
	print(JSON.stringify(_report, "", true, true))
	quit(0)


func _arguments(args: PackedStringArray) -> Dictionary:
	if args.is_empty():
		return {"ok": true, "count": 8}
	if args.size() != 2 or args[0] != "--count" or not args[1].is_valid_int():
		return {"ok": false, "reason": "expected optional --count followed by an integer from 1 to 128"}
	var count: int = int(args[1])
	if count < 1 or count > 128:
		return {"ok": false, "reason": "count must be from 1 to 128", "count": count}
	return {"ok": true, "count": count}


func _people(world: RegionalSimulation) -> Dictionary:
	var living: int = 0
	var total: int = 0
	var autonomous: int = 0
	for simulation: VillageSimulation in world.regions.values():
		for actor: Dictionary in simulation.actors.values():
			total += 1
			if bool(actor.get("alive", false)):
				living += 1
			if bool(actor.get("autonomous", false)):
				autonomous += 1
	var player_present: bool = world.regions.home.actors.has("player")
	return {"actor_records": total, "living_actor_records": living, "home_player_present": player_present,
		"other_actor_records": total - (1 if player_present else 0), "autonomous_flagged_records": autonomous,
		"scope": "fixture actor records; not all active independent AI agents"}


func _advance(world: RegionalSimulation, domain: MonitoredLargeBodies, ids: Array[String], positions: Dictionary) -> Dictionary:
	var start_ms: int = world.elapsed_ms
	var pending_target: int = start_ms + SLICE_MS
	var zero_budget_result: bool = world.advance_to_ms(pending_target, 0)
	if zero_budget_result or world.elapsed_ms != start_ms or world.target_ms != pending_target:
		return {"ok": false, "stage": "zero_budget_backlog", "elapsed_ms": world.elapsed_ms, "target_ms": world.target_ms}
	var segment_times: Array[int] = []
	var budget_yields: int = 1
	var attempts: int = 0
	var moving_observations: int = 0
	var crossing_observations: int = 0
	var work_start: int = int(world.simulation_work.boundaries)
	var now_target: int = pending_target
	while now_target <= start_ms + SPAN_MS:
		var segment_begin: int = Time.get_ticks_usec()
		while world.elapsed_ms < now_target:
			var before: int = world.elapsed_ms
			var errors_before: int = world.errors.size()
			var reached: bool = world.advance_to_ms(now_target, EVENT_BUDGET)
			attempts += 1
			if world.errors.size() != errors_before:
				return {"ok": false, "stage": "simulation_error", "before": before, "elapsed": world.elapsed_ms,
					"target": world.target_ms, "errors": world.errors.duplicate()}
			if not reached:
				budget_yields += 1
				if world.target_ms != now_target or world.elapsed_ms <= before or world.elapsed_ms >= now_target:
					return {"ok": false, "stage": "budget_resume", "before": before, "elapsed": world.elapsed_ms,
						"target": world.target_ms, "requested": now_target, "errors": world.errors.duplicate()}
			if attempts > 10000:
				return {"ok": false, "stage": "resume_attempt_limit", "elapsed": world.elapsed_ms, "target": now_target}
		segment_times.append(Time.get_ticks_usec() - segment_begin)
		if world.elapsed_ms != now_target or world.target_ms != now_target:
			return {"ok": false, "stage": "slice_clock", "elapsed": world.elapsed_ms, "target": world.target_ms, "expected": now_target}
		for id: String in ids:
			var info: Dictionary = positions[id]
			if domain.point(id) != info.start:
				info.moved = true
			if not domain.bodies[id].step.is_empty():
				moving_observations += 1
			var chunk: Vector2i = _chunk(domain.body_cell(id))
			if chunk != info.chunk:
				crossing_observations += 1
				info.crossed = true
				info.chunk = chunk
		now_target += SLICE_MS
	var moved: int = 0
	var crossed: int = 0
	for id: String in ids:
		moved += 1 if bool(positions[id].moved) else 0
		crossed += 1 if bool(positions[id].crossed) else 0
	if moved != ids.size() or crossed == 0 or not domain.space_valid():
		return {"ok": false, "stage": "motion_or_clearance", "moved": moved, "crossed": crossed, "bodies": ids.size()}
	return {"ok": true, "start_ms": start_ms, "end_ms": world.elapsed_ms, "span_ms": SPAN_MS, "slice_ms": SLICE_MS,
		"slices": segment_times.size(), "slice_ms_cost": _percentiles(segment_times), "event_budget_per_call": EVENT_BUDGET,
		"advance_calls": attempts, "budget_yields_including_one_zero_budget_probe": budget_yields,
		"observed_world_boundaries": int(world.simulation_work.boundaries) - work_start,
		"bodies_ever_moved": moved, "moving_body_observations": moving_observations, "bodies_observed_crossing_chunk": crossed,
		"body_crossing_ratio": float(crossed) / float(ids.size()), "sampled_chunk_crossings": crossing_observations,
		"crossing_scope": "64-cell anchor chunks sampled after each 500 ms slice, not per-step exact tracing",
		"scope": "synchronous common-time advances include all active fixture world domains, not rendering or isolated body ticks"}


func _queries(world: RegionalSimulation, domain: MonitoredLargeBodies, ids: Array[String]) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var description_costs: Array[int] = []
	var entity_costs: Array[int] = []
	for _i: int in QUERY_SAMPLES:
		var id: String = ids[rng.randi_range(0, ids.size() - 1)]
		var reference: Dictionary = {"kind": "large_body", "id": id}
		var begin: int = Time.get_ticks_usec()
		var described: Dictionary = world.describe_object(reference)
		description_costs.append(Time.get_ticks_usec() - begin)
		begin = Time.get_ticks_usec()
		var location: Dictionary = EntityQuery.locate(world, reference)
		entity_costs.append(Time.get_ticks_usec() - begin)
		if not bool(described.get("ok", false)) or described.get("reference") != reference or not described.get("spatial") is Dictionary:
			return {"ok": false, "kind": "description", "id": id, "result": described}
		if described.spatial.get("cells", []).size() != 9 or not bool(location.get("ok", false)) or location.get("footprint") != Vector2i(3, 3) or location.get("swept_bounds_cells") != domain.swept_bounds(id):
			return {"ok": false, "kind": "footprint", "id": id, "description": described, "location": location}
	return {"ok": true, "samples": QUERY_SAMPLES, "sampling": "seeded with replacement",
		"describe_ms": _percentiles(description_costs), "entity_query_ms": _percentiles(entity_costs),
		"scope": "original body reference and 3x3 cell projection; conservative sweep is checked against real owner"}


func _navigation(domain: MonitoredLargeBodies) -> Dictionary:
	return {"path_calls": domain.path_calls, "succeeded": domain.path_successes, "failed": domain.path_failures,
		"max_endpoint_chebyshev_cells": domain.max_endpoint_distance_cells, "max_returned_path_cells": domain.max_path_cells,
		"path_ms": _percentiles(domain.path_cost_us) if not domain.path_cost_us.is_empty() else {},
		"scope": "instrumented calls to original pathfinder; endpoint distance is not search radius or examined-node count"}


func _chunk(cell: Vector2i) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(cell.x / CHUNK_CELLS, cell.y / CHUNK_CELLS)


func _elapsed_ms(start_usec: int) -> float:
	return float(Time.get_ticks_usec() - start_usec) / 1000.0


func _percentiles(costs: Array[int]) -> Dictionary:
	var sorted: Array[int] = costs.duplicate()
	sorted.sort()
	return {"p50": _percentile_ms(sorted, 0.50), "p95": _percentile_ms(sorted, 0.95),
		"p99": _percentile_ms(sorted, 0.99), "max": float(sorted.back()) / 1000.0}


func _percentile_ms(sorted: Array[int], percentile: float) -> float:
	var index: int = clampi(int(ceil(float(sorted.size()) * percentile)) - 1, 0, sorted.size() - 1)
	return float(sorted[index]) / 1000.0


func _fail(reason: String, detail: Dictionary = {}) -> void:
	_report["ok"] = false
	_report["first_failure"] = {"reason": reason, "detail": detail}
	print(JSON.stringify(_report, "", true, true))
	quit(1)
