extends RefCounted
## Genuine received warning, public UI responses and independent joint futures.

const Replay = preload("res://tests/runtime/helpers/source_care_replay.gd")
const ARCHIVE: String = "res://tests/fixtures/session_v38.json"
const SHA: String = "79c390a681a1c711b6dc3044bc5d79718b539e5916899187e3132c051a9d6067"


func run(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	var original: String = FileAccess.get_file_as_string(ARCHIVE)
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SHA, "actual received-warning archive retains its frozen original SHA")
	runner.assert_eq(original.to_utf8_buffer().size(), 229976, "actual warning archive retains all original UTF-8 bytes")
	for mode: String in ["stop", "drive"]:
		var expected: String = ""
		for attempt: int in 2:
			var main: Node = _main(runner)
			var runtime: WorldContinuityRuntime = main._continuity
			var helper := Replay.new()
			var report: Dictionary = helper.replay_warning(runtime, "test_%s_%d" % [mode, attempt], mode)
			runner.assert_true(bool(report.get("ok", false)), "actual saved-warning normal response completes: " + mode + ": " + str(report.get("error", "")))
			if bool(report.get("ok", false)):
				runner.assert_eq(runtime.current_region, "river", "original person actually departs to the other settlement after " + mode)
				runner.assert_eq(runtime.world_sim.source_care.warnings.size(), 1, "one actual source process never becomes repeated warnings or repeated attacks")
				runner.assert_eq(runtime.world_sim.conflicts.conflicts.size(), 1 if mode == "drive" else 0, "ordinary response has the exact actual conflict count: " + mode)
				var canonical: String = SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime)))
				if attempt == 0:
					expected = canonical
				else:
					runner.assert_eq(canonical, expected, "independent full main loaders produce byte-identical joint futures after " + mode)
			main.free()
	_warning_delivery_before_saved_clock(runner)
	runner.assert_eq(FileAccess.get_file_as_string(ARCHIVE), original, "normal warning continuations and UI checks never rewrite the immutable source fixture")
	GameClock.restore_state(clock)
	print("SCENARIO actual source care: ordinary voluntary stop or paid NPC drive-off, genuine immutable warning, independent full-world futures, loading delivers before next clock step and nonhuman view isolation")


func _main(runner: Object) -> Node:
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	return main


func _warning_delivery_before_saved_clock(runner: Object) -> void:
	var main: Node = _main(runner)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime.load_game(ProjectSettings.globalize_path(ARCHIVE)) != OK:
		runner.assert_true(false, "UI warning fixture loads through the actual loader")
		main.free()
		return
	var helper := Replay.new()
	var warning: Dictionary = runtime.world_sim.source_care.warnings.values().front()
	runtime.interaction_adapter.reset_observation()
	runner.assert_true(runtime.spirit_adapter.select_source("hearth_seam"), "ordinary original source panel can be open when a warning arrives")
	runtime.interaction_adapter.receive_current_care_alerts()
	runner.assert_true(runtime.interaction_adapter.panel.visible and not runtime.spirit_adapter.panel.visible, "received warning is readable above the dismissed source panel")
	runner.assert_true(runtime.world_sim.spirit_sources.owns_actor("player"), "dismissing source presentation never cancels the original physical channel")
	runner.assert_true(helper._advance(runtime, int(warning.due_ms) - GameClock.elapsed_ms - 1), "original received warning advances to exactly one millisecond before escalation")
	var at_ms: int = GameClock.elapsed_ms
	var facts: String = SnapshotValues.canonical_json(SnapshotValues.normalized(runtime.world_sim.to_dict()))
	GameClock.set_speed(4.0)
	runner.assert_true(GameClock.request_wait(1), "player's actual wait command can be saved before the next native frame")
	var path: String = "user://source_care_delivery_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "actual running-clock near-deadline world saves normally")
	runner.assert_eq(runtime.load_game(path), OK, "near-deadline saved warning loads normally")
	runner.assert_eq(GameClock.elapsed_ms, at_ms, "loading an already received warning never consumes its final millisecond")
	runner.assert_true(GameClock.paused and GameClock.wait_target_ms == 0 and GameClock.speed == 1.0, "already received warning is delivered before restored waiting or four-times speed can advance")
	runner.assert_true(runtime.interaction_adapter.panel.visible, "actual request panel opens for the currently inhabited person's warning")
	runner.assert_eq(runtime.interaction_adapter._receipt.id, warning.id, "actual panel recalls the original warning rather than creating a second process")
	runner.assert_eq(SnapshotValues.canonical_json(SnapshotValues.normalized(runtime.world_sim.to_dict())), facts, "load-time warning presentation never changes original world facts or random decisions")
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, WorldSessionSnapshot.capture(runtime)).is_empty(), "paused delivered warning remains a complete valid joint candidate")
	# A deliberately changed view is an isolated UI input, not a playable body
	# switch or a saved world. Restore it before any action or serialization.
	for subject: String in ["subject:avian:moss_sparrow", "subject:soul:yan_heng"]:
		var original_subject: String = runtime.avatar_subject
		runtime.avatar_subject = subject
		runtime.interaction_adapter.reset_observation()
		GameClock.set_paused(false)
		runtime.interaction_adapter.receive_current_care_alerts()
		runner.assert_true(not GameClock.paused and not runtime.interaction_adapter.panel.visible, "a nonhuman view never receives the original human's private warning: " + subject)
		runtime.avatar_subject = original_subject
	GameClock.set_paused(true)
	runtime.interaction_adapter.receive_current_care_alerts()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.free()
