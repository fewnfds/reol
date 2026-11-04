extends SceneTree
## Paired background/boundary query cost with real bound definitions.
## This is neither simulation throughput nor a rendered frame measurement.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var content: RefCounted = load("res://scripts/data/content_db.gd").new()
	if not content.load_all():
		quit(1)
		return
	var climate: Variant = load("res://scripts/sim/climate_rules.gd")
	var report: Dictionary = {"engine": Engine.get_version_info().string,
		"climate_regions": content.climate.regions.size(), "samples": [], "checksum": 0}
	for count: int in [128, 512, 4096]:
		var timings: Array[float] = []
		for sample: int in 30:
			var start: int = Time.get_ticks_usec()
			for index: int in count:
				var point := Vector2i(250 if index % 2 == 0 else 300, 255)
				var now: int = 797431 + index * 3076917 + sample * 97
				var background: Dictionary = climate.background_at(content.climate, content.weather, 797431, point, now)
				var boundary: int = climate.next_background_boundary_ms(content.climate, content.weather, 797431, str(background.region), now)
				if boundary <= now:
					printerr("CLIMATE_QUERY_BENCH_FAILED nonfuture boundary")
					quit(1)
					return
				report.checksum = int(report.checksum) + int(background.temperature_tenths) + boundary - now
			timings.append(float(Time.get_ticks_usec() - start) / 1000.0)
		timings.sort()
		report.samples.append({"paired_queries": count, "repetitions": timings.size(),
			"p50_ms": _percentile(timings, 0.5), "p95_ms": _percentile(timings, 0.95),
			"p99_ms": _percentile(timings, 0.99), "max_ms": timings[-1]})
	print("CLIMATE_QUERY_BENCH ", JSON.stringify(report))
	quit(0)


func _percentile(sorted: Array[float], fraction: float) -> float:
	return sorted[clampi(ceili(sorted.size() * fraction) - 1, 0, sorted.size() - 1)]
