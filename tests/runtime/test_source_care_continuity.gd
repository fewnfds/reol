extends RefCounted
## Current received warnings preserve their real source and shared future.

const Replay = preload("res://tests/runtime/helpers/source_care_replay.gd")
const ARCHIVE: String = "res://tests/fixtures/session_v38.json"
const SHA: String = "79c390a681a1c711b6dc3044bc5d79718b539e5916899187e3132c051a9d6067"


func run(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	var main: Node = _main(runner)
	var runtime: WorldContinuityRuntime = main._continuity
	var path: String = "user://tests/source_care_current_%d.json" % Time.get_ticks_usec()
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary scene initializes for source-care continuity")
		_cleanup(main, path, clock)
		return
	_reject_archive(runner, runtime)
	var helper := Replay.new()
	var selected: bool = runtime.avatar_adapter.choose("subject:player")
	runner.assert_true(selected, "the current ordinary opening chooses the original human")
	if not selected:
		_cleanup(main, path, clock)
		return
	GameClock.cancel_wait()
	GameClock.set_speed(1.0)
	GameClock.set_paused(true)
	var world: RegionalSimulation = runtime.world_sim
	var arrived: bool = helper._travel(runtime, "home", world.artifacts.object_cell("hearth_stone"))
	runner.assert_true(arrived, "the original player physically reaches the source medium")
	if not arrived:
		_cleanup(main, path, clock)
		return
	for verb: String in ["take", "study"]:
		var completed: bool = helper._object_action(runtime, verb)
		runner.assert_true(completed, "the actual medium action completes without cancelling other people: " + verb)
		if not completed:
			_cleanup(main, path, clock)
			return
	var guard: String = helper._wait_keeper(runtime)
	runner.assert_true(not guard.is_empty(), "a real keeper visits through an autonomous duty with a finite grace interval")
	if guard.is_empty():
		_cleanup(main, path, clock)
		return
	var seen: bool = runtime.spirit_adapter.select_source("hearth_seam")
	runner.assert_true(seen, "the original player can see the source from the actual position")
	if not seen:
		_cleanup(main, path, clock)
		return
	var begun: Dictionary = runtime.spirit_adapter.submit("begin")
	var advanced: bool = bool(begun.get("ok", false)) and helper._advance(runtime, 1500)
	runner.assert_true(advanced, "the actual unpermitted source operation advances: " + str(begun))
	if not advanced:
		_cleanup(main, path, clock)
		return
	var alerts: Array[Dictionary] = world.source_care.alerts_for("player")
	runner.assert_eq(alerts.size(), 1, "a real observed action produces one personally received warning")
	if alerts.size() != 1:
		_cleanup(main, path, clock)
		return
	var warning_id: String = str(alerts[0].id)
	var warning: Dictionary = world.source_care.warnings[warning_id]
	runner.assert_true(world.spirit_sources.owns_actor("player") and str(warning.source_job) == str(world.spirit_sources.active.player.id), "warning names the same actual in-flight source work")
	var saved: Error = runtime.save_game(path)
	runner.assert_eq(saved, OK, "the current real warning and original source save together")
	if saved != OK:
		_cleanup(main, path, clock)
		return
	for mode: String in ["stop", "drive"]:
		var expected: String = ""
		for attempt: int in 2:
			var future: String = _continue_warning(runner, runtime, helper, path, warning_id, mode)
			if attempt == 0:
				expected = future
			elif not expected.is_empty() and not future.is_empty():
				runner.assert_eq(future, expected, "independent ordinary loads reach the same full future: " + mode)
	main.free()
	_warning_delivery_before_saved_clock(runner, path)
	_cleanup(null, path, clock)
	print("SCENARIO source care: actual current warning, voluntary stop or guard response, saved future and UI delivery; old archive rejected")


func _continue_warning(runner: Object, runtime: WorldContinuityRuntime, helper: RefCounted, path: String, warning_id: String, mode: String) -> String:
	var loaded: Error = runtime.load_game(path)
	runner.assert_eq(loaded, OK, "ordinary loading restores the current warning: " + mode)
	if loaded != OK:
		return ""
	GameClock.set_paused(true)
	var world: RegionalSimulation = runtime.world_sim
	if not world.source_care.warnings.has(warning_id):
		runner.assert_true(false, "the original warning identity survives loading: " + mode)
		return ""
	var warning: Dictionary = world.source_care.warnings[warning_id]
	var source_id: String = str(warning.source_job)
	var spent: int = int(world.spirit_sources.sources.hearth_seam.spent)
	var qi: int = int(world.conflicts.body("player").qi)
	var due: int = int(warning.due_ms)
	var done: bool
	if mode == "stop":
		var reply: Dictionary = runtime.spirit_adapter.submit("cancel")
		done = bool(reply.get("ok", false)) and helper._advance(runtime, due - GameClock.elapsed_ms + 1000)
	else:
		done = helper._advance(runtime, due - GameClock.elapsed_ms + 700)
		if done:
			var encounter: Dictionary = world.conflicts.conflicts.get(warning.conflict, {})
			var engaged: bool = warning.status == "escalated" and encounter.get("initiator") == "shi_tou" and encounter.get("defender") == "player" and not world.conflicts.actions.is_empty()
			runner.assert_true(engaged, "the actual guard independently begins and pays for its response")
			if engaged:
				runtime.conflict_adapter.yield_player()
			else:
				done = false
	runner.assert_true(done, "the actual warning response can complete: " + mode)
	if not done or not helper._advance(runtime, 5000):
		return ""
	var record: Dictionary = world.spirit_sources.records.get(source_id, {})
	runner.assert_eq(record.get("result"), "cancelled", "the interrupted original source ends once: " + mode)
	runner.assert_eq(int(record.get("output", -1)), 0, "cancelled work grants no early source output: " + mode)
	runner.assert_eq(int(world.spirit_sources.sources.hearth_seam.spent), spent, "cancelled work does not spend the original reserve: " + mode)
	runner.assert_eq(int(world.conflicts.body("player").qi), qi, "cancelled source grants no personal qi: " + mode)
	var departed: bool = world.conflicts.conflict_for("player").is_empty() and helper._travel(runtime, "river") and helper._advance(runtime, 60000)
	runner.assert_true(departed, "the original body physically departs and the rest of the world continues: " + mode)
	if not departed:
		return ""
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, snapshot).is_empty(), "the complete warning future independently stages: " + mode)
	return SnapshotValues.canonical_json(SnapshotValues.normalized(snapshot))


func _reject_archive(runner: Object, runtime: WorldContinuityRuntime) -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(ARCHIVE)
	var raw: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SHA, "actual received-warning archive retains its frozen original digest")
	runner.assert_true(raw is Dictionary, "the historical warning archive remains readable")
	if not raw is Dictionary:
		return
	var source: Dictionary = raw
	var input: String = SnapshotValues.canonical_json(SnapshotValues.normalized(source))
	var world: RegionalSimulation = runtime.world_sim
	var content: ReolContentDB = runtime._home._content
	var terrain: WorldMapData = world.map_data
	var before: String = SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime)))
	var clock: String = SnapshotValues.canonical_json(SnapshotValues.normalized(GameClock.to_dict()))
	runner.assert_eq(int(source.schema_version), 38, "the warning archive retains its actual old version")
	runner.assert_eq(SessionSaveSchema.rejection_reason(source.schema_version), SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT, "the old warning has the environment rejection")
	runner.assert_true(WorldSessionSnapshot.stage(runtime, source).is_empty(), "the old warning cannot invent its missing field history")
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(ARCHIVE)), ERR_INVALID_DATA, "ordinary loading refuses the historical warning")
	runner.assert_eq(runtime._notice, "旧环境格式不再支持，存档未改；请新开局。", "historical warning rejection gives the reason")
	runner.assert_true(runtime.world_sim == world and runtime._home._content == content and runtime.world_sim.map_data == terrain, "historical refusal keeps live owners intact")
	runner.assert_eq(SnapshotValues.canonical_json(SnapshotValues.normalized(GameClock.to_dict())), clock, "historical refusal keeps common time")
	runner.assert_eq(SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime))), before, "historical refusal keeps the complete world")
	runner.assert_eq(SnapshotValues.canonical_json(SnapshotValues.normalized(source)), input, "staging never mutates the supplied archive")
	runner.assert_eq(FileAccess.get_file_as_bytes(ARCHIVE), bytes, "historical refusal leaves original file bytes intact")


func _cleanup(main: Node, path: String, clock: Dictionary) -> void:
	if is_instance_valid(main):
		main.free()
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	GameClock.restore_state(clock)


func _main(runner: Object) -> Node:
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	return main


func _warning_delivery_before_saved_clock(runner: Object, archive: String) -> void:
	var main: Node = _main(runner)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime.load_game(ProjectSettings.globalize_path(archive)) != OK:
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
