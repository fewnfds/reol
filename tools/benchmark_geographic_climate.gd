extends SceneTree
## Bounded creation/query timing, not world throughput or FPS. Run under the
## existing world_benchmark.py process/memory guard.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var content := ReolContentDB.new()
	if not content.load_all():
		quit(1)
		return
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/world_geography.json"))
	var compile_samples: Array[int] = []
	var candidate_samples: Array[int] = []
	var query_samples: Array[int] = []
	var result: Dictionary = {}
	for index: int in 30:
		profile.solar.latitude_mdeg = -85000 + index * 5000
		var start: int = Time.get_ticks_usec()
		result = SimGeographicClimate.compile(content.climate, profile)
		compile_samples.append(Time.get_ticks_usec() - start)
		start = Time.get_ticks_usec()
		var candidate: ReolContentDB = ReolGeographicContent.build(content.content_bundle(), profile)
		candidate_samples.append(Time.get_ticks_usec() - start)
		if result.is_empty() or candidate == null or candidate.climate != SnapshotValues.normalized(result):
			printerr("GEOGRAPHIC_BENCHMARK_FAILED candidate differs")
			quit(1)
			return
		start = Time.get_ticks_usec()
		for query: int in 512:
			var at: int = index * 86400000 + query * 12347
			if SimClimateRules.background_for_region(result, content.weather, 0, "home", at).is_empty() or SimClimateRules.next_background_boundary_ms(result, content.weather, 0, "home", at) <= at:
				quit(1)
				return
		query_samples.append(Time.get_ticks_usec() - start)
	print("GEOGRAPHIC_BENCHMARK_RESULT ", JSON.stringify({"samples": 30, "regions": 2, "compiled_knots_per_region": [result.regions.home.seasonal_curve.size(), result.regions.home.daily_curve.size()], "queries_per_sample": 512,
		"compile_us": _stats(compile_samples), "complete_candidate_us": _stats(candidate_samples), "background_and_boundary_us": _stats(query_samples)}))
	quit(0)


func _stats(samples: Array[int]) -> Dictionary:
	samples.sort()
	var total: int = 0
	for value: int in samples:
		total += value
	return {"mean": float(total) / samples.size(), "p95": samples[ceili(samples.size() * 0.95) - 1], "p99": samples[ceili(samples.size() * 0.99) - 1]}
