extends RefCounted
## A composed isolated field scenario. The ordinary world is not switched yet.

const Index = preload("res://scripts/sim/environment_field_index.gd")
const Tide = preload("res://scripts/sim/environment_field_tide.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const Response = preload("res://scripts/sim/environment_field_response.gd")


func run(runner: Object) -> void:
	var index := Index.new()
	runner.assert_true(index.configure(Vector2i(48, 24), 4), "the isolated composed field configures")
	var origin := Vector2i(8, 8)
	var destination := Vector2i(32, 8)
	var heat: Dictionary = {"id": "original_fire_stone", "cell": origin, "radius": 4,
		"channels": [0, 0, 0, 10000, 0, 10000, 0]}
	var cold: Dictionary = {"id": "original_ice_stone", "cell": origin, "radius": 4,
		"channels": [0, 0, 10000, 0, 0, 0, 10000]}
	runner.assert_true(bool(index.set_source(heat).ok) and bool(index.set_source(cold).ok), "same-grade ice and fire each project one original source")
	var opening: Dictionary = index.sample_base(origin)
	var tide: Dictionary = Tide.sample(17, origin, 12345)
	var diagnostics: Dictionary = index.diagnostics()
	for at_ms: int in [0, 12345, 300000, 600000, 1200000]:
		var cycle: Dictionary = Tide.sample(17, origin, at_ms)
		var target: Dictionary = Rules.thermal_target(20000, int(opening.channels[5]), int(opening.channels[6]), int(cycle.multiplier))
		runner.assert_eq(target.temperature_milli, 20000, "equal ice/fire remains neutral throughout environmental tides")
		runner.assert_true(int(opening.channels[2]) > 0 and int(opening.channels[3]) > 0, "neutral temperature does not erase independent water and fire affinities")
	runner.assert_eq(index.diagnostics(), diagnostics, "tide sampling never rebuilds the base field or mutates source projections")
	var known: Dictionary = index.sample_base(destination)
	runner.assert_eq(known.channels, PackedInt64Array([0, 0, 0, 0, 0, 0, 0]), "the distant destination starts outside both finite circles")

	# Settle the old local response at the actual move boundary, then change
	# the derived projection. This test owns the fixture event ordering only.
	var before := Response.new()
	runner.assert_true(before.configure(0, 5000, 20000.0, 20000.0, 0.0, 2000), "balanced surroundings retain their neutral actual temperature")
	var settled: Dictionary = before.sample(5000)
	heat.cell = destination
	var changed: Dictionary = index.set_source(heat)
	runner.assert_true(bool(changed.ok) and changed.affected.has_point(origin) and changed.affected.has_point(destination), "a move dirties both old and new influence ranges")
	var old_base: Dictionary = index.sample_base(origin)
	var new_base: Dictionary = index.sample_base(destination)
	runner.assert_eq(old_base.channels[5], 0, "the old location has no remaining hot source")
	runner.assert_eq(new_base.channels[5], 10000, "the new location gets the source's unchanged nominal strength")
	runner.assert_eq(index.diagnostics().source_count, 2, "moving the source creates no extra original item or ghost source")
	var old_goal: int = int(Rules.thermal_target(20000, int(old_base.channels[5]), int(old_base.channels[6]), int(tide.multiplier)).temperature_milli)
	var new_goal: int = int(Rules.thermal_target(20000, int(new_base.channels[5]), int(new_base.channels[6]), int(tide.multiplier)).temperature_milli)
	runner.assert_true(old_goal < 20000 and new_goal > 20000, "after separation, the two circles produce independent cold/hot targets")
	var old_response := Response.new()
	var new_response := Response.new()
	runner.assert_true(old_response.configure(5000, 9000, float(settled.value), float(old_goal), 0.0, 2000), "old site begins cooling from the settled actual state")
	runner.assert_true(new_response.configure(5000, 9000, 20000.0, float(new_goal), 0.0, 2000), "new site starts warming without jumping straight to the target")
	runner.assert_eq(new_response.sample(5000).value, 20000.0, "a source arrival does not instantly replace the environment's actual temperature")
	runner.assert_true(float(old_response.sample(9000).value) > float(old_goal) and float(new_response.sample(9000).value) < float(new_goal), "both actual values remain between their old state and target")
	var restored := Response.new()
	runner.assert_true(restored.restore(JSON.parse_string(JSON.stringify(new_response.to_dict(), "", true, true))), "the active local response restores from its complete isolated state")
	runner.assert_eq(restored.sample(9000), new_response.sample(9000), "a running response has the same future after complete JSON recovery")

	print("SCENARIO source field contract: one source identity through a move, independent five-element channels, balanced tides and actual environment continuity; ordinary world integration remains pending")
