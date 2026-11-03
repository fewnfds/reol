extends RefCounted
## Real clicked source, two independent normal scenes and one full future.

const Probe = preload("res://tests/runtime/helpers/herb_ecology_replay.gd")
const SOURCE_SHA: String = "d1a4e0f5fbaa4b87728f34723fe75876647ccd114f3622ef830fd17f7822c9e2"


func run(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	var source: String = FileAccess.get_file_as_string(Probe.ARCHIVE)
	runner.assert_eq(FileAccess.get_sha256(Probe.ARCHIVE), SOURCE_SHA, "actual clicked irrigation archive keeps original independent SHA")
	runner.assert_eq(source.to_utf8_buffer().size(), 189595, "actual archive keeps complete original bytes")
	var future: String = ""
	for suffix: String in ["a", "b"]:
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var report: Dictionary = Probe.new().run(main._continuity, suffix)
		runner.assert_true(not report.has("error") and not report.has("load_error"), "independent main scene replays ordinary irrigation/harvest/drying/journey: " + suffix)
		if not report.has("completed") or not report.has("candidate_valid"):
			main.free()
			continue
		runner.assert_eq(report.source_water, 12, "uncompleted irrigation keeps original private water")
		runner.assert_eq(report.completed.water, 11, "real completion spends exactly one original water")
		runner.assert_eq(report.completed.soil.irrigated, 60000000, "real completion puts one water's finite units into the original soil")
		runner.assert_eq(report.completed.soil.irrigation_receipts.size(), 1, "repeated restore and completion have only one irrigation receipt")
		runner.assert_eq(report.bag.herb, 0, "gathered fresh herbs were actually consumed by drying")
		runner.assert_eq(report.bag.dried_herb, 2, "physically collected dried material remains in original pocket")
		runner.assert_eq(report.region, "river", "original route really leaves the ecological home area")
		runner.assert_true(report.candidate_valid, "the entire ordinary ecological future passes independent candidate checks")
		var actual: String = FileAccess.get_file_as_string("res://logs/herb_ecology_future_%s.json" % suffix)
		if future.is_empty():
			future = actual
		else:
			runner.assert_eq(actual, future, "two independent ordinary main scenes share one byte-identical complete future")
		main.free()
	runner.assert_eq(FileAccess.get_file_as_string(Probe.ARCHIVE), source, "real source archive remains immutable")
	GameClock.restore_state(clock)
	print("SCENARIO herb archive: original private water, actual irrigation labor, same plant harvest, drying/collection and physical departure share one complete future")
