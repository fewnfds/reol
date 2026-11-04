extends SceneTree
## Headless, bounded baseline driven by tools/world_benchmark.py.
## This measures the existing 512-square world and opening, not a larger map,
## rendered frames, player-built structures, or a population scaling test.

const BATCH_SIZE: int = 256
const MAX_CELLS: int = WorldMapData.WORLD_SIZE * WorldMapData.WORLD_SIZE


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or not args[0].is_valid_int() or not args[1].is_valid_int():
		_fail("expected cell count and simulated minute count")
		return
	var cells: int = int(args[0])
	var minutes: int = int(args[1])
	if cells < 1 or cells > MAX_CELLS or minutes < 1 or minutes > 120:
		_fail("workload outside supported bounds")
		return

	var start: int = Time.get_ticks_usec()
	var content := ReolContentDB.new()
	if not content.load_all():
		_fail("content: %s" % str(content.errors))
		return
	var content_ms: float = _ms_since(start)
	content = null

	start = Time.get_ticks_usec()
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		_fail("main scene not found")
		return
	var main: Node = scene.instantiate()
	root.add_child(main)
	var scene_ms: float = _ms_since(start)
	if main._continuity == null or main._continuity.world_sim == null:
		main.free()
		_fail("real scene failed to initialize its world")
		return
	var world: RegionalSimulation = main._continuity.world_sim
	var clock: ReolGameClock = root.get_node("GameClock") as ReolGameClock
	var map: WorldMapData = world.map_data
	if map == null or clock == null or world.regions.is_empty():
		main.free()
		_fail("real scene missing map or regional simulation")
		return
	var actor_count: int = 0
	for village: VillageSimulation in world.regions.values():
		actor_count += village.actors.size()

	var batch_ms: Array[float] = []
	var checksum: int = 0
	start = Time.get_ticks_usec()
	var batch_start: int = start
	for index: int in range(cells):
		@warning_ignore("integer_division")
		var cell := Vector2i(index % WorldMapData.WORLD_SIZE, index / WorldMapData.WORLD_SIZE)
		var natural: Dictionary = map.natural_cell(cell)
		if natural.is_empty():
			main.free()
			_fail("natural cell missing at %s" % str(cell))
			return
		checksum += int(natural.fertility) + int(natural.elements.earth)
		if (index + 1) % BATCH_SIZE == 0 or index + 1 == cells:
			batch_ms.append(_ms_since(batch_start))
			batch_start = Time.get_ticks_usec()
	var map_ms: float = _ms_since(start)
	var cache_cells: int = int(map._nature.call("cache_size"))

	var step_ms: Array[float] = []
	var beginning_ms: int = clock.elapsed_ms
	for _minute: int in range(minutes):
		start = Time.get_ticks_usec()
		clock.advance_ticks(1)
		step_ms.append(_ms_since(start))
		if world.elapsed_ms != clock.elapsed_ms:
			main.free()
			_fail("shared clock and regional world diverged")
			return
	var report: Dictionary = {
		"kind": "existing_opening_headless_baseline",
		"scope": "actual generated 512x512 map; contiguous natural-cell queries; actual opening regions and actors; headless shared-clock minute advances; no rendering, dynamic terrain, population stress, save/load or large-map scaling",
		"godot": Engine.get_version_info(),
		"debug_build": OS.has_feature("debug"),
		"generation": WorldMapData.generation_descriptor(),
		"workload": {"natural_cells": cells, "batch_size": BATCH_SIZE, "requested_minutes": minutes,
			"actual_simulated_ms": clock.elapsed_ms - beginning_ms,
			"regions": world.regions.size(), "village_actors": actor_count},
		"content_init_ms": content_ms, "scene_init_ms": scene_ms,
		"natural_query_total_ms": map_ms, "natural_query_batch_ms": _distribution(batch_ms),
		"minute_step_ms": _distribution(step_ms), "natural_checksum": checksum,
		"natural_cache_cells_after_queries": cache_cells,
		"regional_work": world.simulation_work.duplicate(true),
	}
	main.free()
	print("BENCHMARK_RESULT " + JSON.stringify(report, "", true, true))
	quit(0)


func _ms_since(start: int) -> float:
	return float(Time.get_ticks_usec() - start) / 1000.0


func _distribution(values: Array[float]) -> Dictionary:
	values.sort()
	return {"samples": values.size(), "p50": _percentile(values, 0.50),
		"p95": _percentile(values, 0.95), "p99": _percentile(values, 0.99)}


func _percentile(values: Array[float], fraction: float) -> float:
	return values[maxi(0, ceili(values.size() * fraction) - 1)]


func _fail(message: String) -> void:
	printerr("BENCHMARK_ERROR " + message)
	quit(1)
