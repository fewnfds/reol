extends SceneTree
## Pure map edit cost, not a rendered frame or a populated-world capacity claim.


func _initialize() -> void:
	call_deferred("_measure")


func _measure() -> void:
	var report: Dictionary = {"engine": Engine.get_version_info().string,
		"seed": 42, "map_size": 512, "repeats": 10, "cases": []}
	for count: int in [256, 4096, 32768]:
		var map: WorldMapData = WorldMapData.from_descriptor(WorldMapData.flat_descriptor(42))
		var base: Array = []
		var changed: Array = []
		for index: int in count:
			var x: int = index % 512
			var y: int = index / 512
			var original: int = map.get_terrain(Vector2i(x, y))
			base.append([x, y, original])
			changed.append([x, y, (original + 1) % 3])
		map.apply_terrain_patch(changed) # Warm the noise/rules and allocation path.
		var samples: Array[int] = []
		var affected: int = 0
		for iteration: int in 10:
			var start: int = Time.get_ticks_usec()
			var result: Dictionary = map.apply_terrain_patch(base if iteration % 2 == 0 else changed)
			samples.append(Time.get_ticks_usec() - start)
			if not bool(result.ok) or result.changed_cells.size() != count:
				printerr("TERRAIN_BENCHMARK_FAILED inconsistent complete patch")
				quit(1)
				return
			affected = maxi(affected, result.affected_cells.size())
		samples.sort()
		var start: int = Time.get_ticks_usec()
		var encoded: String = JSON.stringify(map.terrain_overrides())
		var serialization_us: int = Time.get_ticks_usec() - start
		report.cases.append({"cells_per_edit": count, "max_affected_cells": affected,
			"step_p50_us": samples[4], "step_p95_us": samples[9], "step_p99_us": samples[9],
			"samples_us": samples, "serialization_us": serialization_us,
			"serialized_bytes": encoded.to_utf8_buffer().size()})
	print("TERRAIN_BENCHMARK ", JSON.stringify(report))
	quit(0)
