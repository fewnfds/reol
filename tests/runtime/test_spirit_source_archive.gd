extends RefCounted
## Immutable ordinary-click source, independently recreated normal scenes.

const Probe = preload("res://tests/runtime/helpers/spirit_source_replay.gd")
const SOURCE_SHA: String = "07e4a64c2e8415afd912220b3c017bd269947c52c0a23d1536b0888d9f090c78"


func run(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	var source: String = FileAccess.get_file_as_string(Probe.ARCHIVE)
	runner.assert_eq(FileAccess.get_sha256(Probe.ARCHIVE), SOURCE_SHA, "actual clicked in-progress source archive keeps its independently recorded SHA")
	runner.assert_eq(source.to_utf8_buffer().size(), 180474, "actual source archive retains all original bytes")
	var future: String = ""
	for suffix: String in ["a", "b"]:
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var report: Dictionary = Probe.new().run(main._continuity, suffix)
		runner.assert_true(not report.has("error") and not report.has("load_error"), "independent ordinary scene resumes the original source and subsequent life uses: " + suffix)
		if not report.has("completed") or not report.get("candidate_valid", false):
			runner.assert_true(false, "complete ordinary source future has a valid independent session candidate: " + suffix)
			main.free()
			continue
		runner.assert_eq(report.source_ms, 930050, "source archive restores the actual partial work instant")
		runner.assert_eq(report.source_qi, 19, "incomplete original work has not prematurely restored qi")
		runner.assert_eq(report.source_stock.hearth_seam.spent, 0, "incomplete original source has only reserved its actual batch")
		runner.assert_eq(report.completed.qi, 20, "actual first completion respects original body capacity")
		runner.assert_eq(report.completed.sources.hearth_seam.spent, 6, "partially accepted body output still spends one actual source batch")
		var first: Dictionary = report.completed.records["spirit:1"]
		runner.assert_eq(first.output, 1, "genuine capacity-limited body receipt contains only actual accepted output")
		runner.assert_eq(first.loss, 3, "genuine capacity-limited body receipt records unaccepted conversion loss")
		runner.assert_eq(report.after_body_use.qi, 16, "source-restored qi pays the original temperature-storage operation")
		runner.assert_eq(report.after_body_use.heat, 180000000, "first original warming spends stored heat into actual fixed space")
		runner.assert_eq(report.after_stone_use.sources.hearth_seam.spent, 12, "second selected destination spends a different actual source batch")
		runner.assert_eq(report.after_stone_use.heat, 360000000, "second original warming uses the same actual stored output")
		runner.assert_eq(report.qi, 16, "ordinary final body has no extra passive qi recovery")
		runner.assert_eq(report.charge, 11, "ordinary final unique stone has actual capped refill and second heat debit")
		runner.assert_eq(report.region, "river", "ordinary original route actually leaves the source region")
		runner.assert_true(report.journey.is_empty() and report.candidate_valid, "complete ordinary source future ends at a coherent arrived session")
		var actual: String = FileAccess.get_file_as_string("res://logs/spirit_source_future_%s.json" % suffix)
		if future.is_empty():
			future = actual
		else:
			runner.assert_eq(actual, future, "two independent ordinary main scenes share one byte-identical complete future")
		main.free()
	runner.assert_eq(FileAccess.get_file_as_string(Probe.ARCHIVE), source, "replaying the ordinary source archive never rewrites its original bytes")
	GameClock.restore_state(clock)
	print("SCENARIO spiritual source archive: actual partial body restoration, original temperature storage/warming, source stone storage, second warming and physical departure continue in one shared future")
