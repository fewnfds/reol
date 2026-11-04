extends RefCounted
## Historical envelopes enter through the session importer. A raw old regional
## value cannot replace the current simulation or its unfinished real work.

const Fixtures = preload("res://tests/sim/test_regional_simulation.gd")
const ARCHIVES: Array[String] = ["session_v34.json", "session_v35.json", "session_v36.json", "session_v37.json", "session_v38.json", "session_v39.json", "session_v40.json", "session_v41_draw.json"]


func run(runner: Object) -> void:
	var fixture := Fixtures.new()
	var world: RegionalSimulation = fixture._make_world(runner)
	if world == null:
		return
	runner.assert_true(world.regions.home.submit_action("player", "deliver_wood"), "restore-boundary probe owns real native work")
	world.invalidate_region("home")
	runner.assert_true(world.advance_to_ms(50), "unfinished original haul reaches its actual fractional time")
	runner.assert_true(not world.regions.home.actors.player.active.is_empty(), "the rejected old candidate cannot erase an already running haul")
	var before: String = _json(world.to_dict())
	var owners: Dictionary = {}
	for name: StringName in RegionalSimulation.SNAPSHOT_DOMAINS:
		owners[name] = world.get(name)
	owners[&"home"] = world.regions.home
	owners[&"river"] = world.regions.river
	owners[&"in_transit"] = world.in_transit
	for index: int in ARCHIVES.size():
		var path: String = "res://tests/fixtures/" + ARCHIVES[index]
		var bytes: String = FileAccess.get_file_as_string(path)
		var original: Dictionary = JSON.parse_string(bytes)
		var regional: Dictionary = original.continuity.world
		var input: String = _json(regional)
		runner.assert_eq(int(regional.version), 30 + index, "probe uses the real archived regional format: " + ARCHIVES[index])
		runner.assert_true(not world.restore(regional), "direct restoration rejects the retired raw regional entrance: " + ARCHIVES[index])
		runner.assert_eq(_json(world.to_dict()), before, "rejected old region preserves all bodies, custody, time and unfinished work: " + ARCHIVES[index])
		var same_owners: bool = world.regions.home == owners[&"home"] and world.regions.river == owners[&"river"] and world.in_transit == owners[&"in_transit"]
		for name: StringName in RegionalSimulation.SNAPSHOT_DOMAINS:
			same_owners = same_owners and world.get(name) == owners[name]
		runner.assert_true(same_owners, "rejected old region preserves every live authority: " + ARCHIVES[index])
		runner.assert_eq(_json(regional), input, "direct rejection never converts the caller's old value in place: " + ARCHIVES[index])
		runner.assert_eq(FileAccess.get_file_as_string(path), bytes, "direct rejection never rewrites the historical archive: " + ARCHIVES[index])
	var candidate: RegionalSimulation = fixture._make_world(runner)
	if candidate == null:
		return
	runner.assert_true(candidate.restore(JSON.parse_string(before)), "current regional JSON still restores through the ordinary current entrance")
	runner.assert_eq(_json(candidate.to_dict()), before, "the current entrance preserves the complete in-flight world")
	runner.assert_true(world.advance_to_ms(60050) and candidate.advance_to_ms(60050), "independent current worlds continue their original haul")
	runner.assert_eq(_json(candidate.to_dict()), _json(world.to_dict()), "current regional restoration retains the same complete future")
	print("SCENARIO regional restore boundary: real v30-v37 raw regions rejected atomically; current in-flight original work and its independent future retained")


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
