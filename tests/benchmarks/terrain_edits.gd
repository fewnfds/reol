extends SceneTree
## Live transaction cost, not frame time or large-population capacity.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var runtime: Node = main._continuity
	if runtime == null or runtime.world_sim == null or not runtime.world_sim.synchronize_regions():
		quit(1)
		return
	var command: Variant = load("res://scripts/sim/terrain_edits.gd")
	var report: Dictionary = {"engine": Engine.get_version_info().string, "map_size": runtime.world_sim.map_data.descriptor().size, "regions": runtime.world_sim.regions.size(), "humans": 0, "samples": []}
	for sim: RefCounted in runtime.world_sim.regions.values():
		report.humans += sim.actors.size()
	for width: int in [1, 4, 16]:
		var timings: Array[float] = []
		for sample: int in range(30):
			var rows: Array = []
			for y: int in range(20, 20 + width):
				for x: int in range(20, 20 + width):
					rows.append([x, y, WorldMapData.TERRAIN_WATER if sample % 2 == 0 else WorldMapData.TERRAIN_GRASS])
			var start: int = Time.get_ticks_usec()
			var result: Dictionary = command.apply(runtime.world_sim, rows)
			var elapsed: float = float(Time.get_ticks_usec() - start) / 1000.0
			if not result.ok:
				printerr("TERRAIN_EDIT_BENCH_FAILED ", result.code)
				quit(1)
				return
			timings.append(elapsed)
		timings.sort()
		report.samples.append({"cells": width * width, "repetitions": timings.size(), "p50_ms": _percentile(timings, 0.5), "p95_ms": _percentile(timings, 0.95), "p99_ms": _percentile(timings, 0.99), "max_ms": timings[-1]})
	print("TERRAIN_EDIT_BENCH ", JSON.stringify(report))
	quit(0)


func _percentile(sorted: Array[float], fraction: float) -> float:
	return sorted[clampi(ceili(sorted.size() * fraction) - 1, 0, sorted.size() - 1)]
