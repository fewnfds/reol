extends RefCounted
## Current ordinary borrowing, saved in flight and resumed under one world clock.

const Replay = preload("res://tests/runtime/helpers/source_care_replay.gd")
const ARCHIVE: String = "res://tests/fixtures/session_v37.json"
const SOURCE_SHA: String = "64c9ee3cf0bfa3cd8bf012a1461f8c2b0992740d4907cd1d8de7b66886bd030a"


func run(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var source_path: String = "user://tests/source_loan_current_%d.json" % Time.get_ticks_usec()
	var check_path: String = "user://tests/source_loan_check_%d.json" % Time.get_ticks_usec()
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary main initializes for source-loan continuation")
		_cleanup(main, source_path, check_path, saved_clock)
		return
	# Both independent scenes compare complete loan futures, not frame budgets.
	runtime.settlement_work_budget = 2147483647
	_reject_archive(runner, runtime)
	var helper := Replay.new()
	var report: Dictionary = {"steps": []}
	var chose: bool = runtime.avatar_adapter.choose("subject:player")
	runner.assert_true(chose, "the ordinary opening selects the original human")
	if not chose:
		_cleanup(main, source_path, check_path, saved_clock)
		return
	GameClock.set_paused(true)
	GameClock.cancel_wait()
	GameClock.set_speed(1.0)
	var world: RegionalSimulation = runtime.world_sim
	var arrived: bool = helper._travel(runtime, "home", world.artifacts.object_cell("hearth_stone"))
	runner.assert_true(arrived, "the player actually walks to the one original medium")
	if not arrived:
		_cleanup(main, source_path, check_path, saved_clock)
		return
	for verb: String in ["take", "study"]:
		var completed: bool = helper._object_action(runtime, verb)
		runner.assert_true(completed, "the ordinary physical action completes without cancelling other residents: " + verb)
		if not completed:
			_cleanup(main, source_path, check_path, saved_clock)
			return
	var loan: Dictionary = helper._ask_at_desk(runtime, "borrow_source", "source_once_body", report)
	var issued: bool = bool(loan.get("ok", false)) and helper._finish_visitor(runtime, "player") and not world.site_affairs.notes.is_empty()
	runner.assert_true(issued, "the actual office holder issues a real bounded borrowing note: " + str(loan))
	if not issued:
		_cleanup(main, source_path, check_path, saved_clock)
		return
	var note_id: String = str(world.site_affairs.notes.values().back().id)
	var note: Dictionary = world.site_affairs.notes[note_id]
	arrived = helper._travel(runtime, "home", world.spirit_sources.source_cell("hearth_seam"))
	var selected: bool = arrived and runtime.spirit_adapter.select_source("hearth_seam")
	runner.assert_true(selected, "the original player reaches and sees the actual source")
	if not selected:
		_cleanup(main, source_path, check_path, saved_clock)
		return
	# The issuer's signed note is not automatically known to the actual keeper.
	# Use the same real face-to-face explanation as the ordinary peaceful path.
	var guard: String = helper._wait_keeper(runtime)
	runner.assert_true(not guard.is_empty(), "the actual keeper arrives before signed source use")
	if guard.is_empty():
		_cleanup(main, source_path, check_path, saved_clock)
		return
	var explained: Dictionary = runtime.interaction_adapter.submit(world.embodiment.subject_for_actor(guard), "explain_source", {"kind": "care_basis", "id": note_id})
	var accepted: bool = explained.get("status") == "completed"
	runner.assert_true(accepted, "the actual keeper receives and accepts the signed note: " + str(explained))
	if not accepted:
		_cleanup(main, source_path, check_path, saved_clock)
		return
	var reply: Dictionary = runtime.spirit_adapter.submit("begin")
	runner.assert_true(bool(reply.get("ok", false)), "a real source operation starts under the signed note: " + str(reply))
	if not bool(reply.get("ok", false)):
		_cleanup(main, source_path, check_path, saved_clock)
		return
	var job: Dictionary = world.spirit_sources.active.player.duplicate(true)
	var job_id: String = str(job.id)
	var before_spent: int = int(world.spirit_sources.sources.hearth_seam.spent)
	var advanced: bool = helper._advance(runtime, 30000)
	runner.assert_true(advanced and str(note.bound) == job_id and str(note.used).is_empty(), "the pending note names the one actual unfinished process")
	if not advanced:
		_cleanup(main, source_path, check_path, saved_clock)
		return
	var saved: Error = runtime.save_game(source_path)
	runner.assert_eq(saved, OK, "ordinary session saves the signed in-flight source work")
	if saved != OK:
		_cleanup(main, source_path, check_path, saved_clock)
		return
	var present: String = _snapshot(runtime)
	var due: int = int(job.due_ms)
	advanced = helper._advance(runtime, due - GameClock.elapsed_ms)
	runner.assert_true(advanced, "the actual source reaches its original deadline")
	if not advanced:
		_cleanup(main, source_path, check_path, saved_clock)
		return
	runner.assert_eq(str(note.used), job_id, "completion consumes the same signed note once")
	runner.assert_true(world.spirit_sources.records.has(job_id), "the original source process leaves its completion receipt")
	var spent: int = int(world.spirit_sources.sources.hearth_seam.spent)
	runner.assert_true(spent > before_spent, "the original source is actually debited at completion")
	var future: String = _snapshot(runtime)
	main.free()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	main = packed.instantiate()
	runner.root.add_child(main)
	runtime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "replacement main initializes before source-loan loading")
		_cleanup(main, source_path, check_path, saved_clock)
		return
	runtime.settlement_work_budget = 2147483647
	var loaded: Error = runtime.load_game(source_path)
	runner.assert_eq(loaded, OK, "a new ordinary scene restores the current in-flight source")
	if loaded != OK:
		_cleanup(main, source_path, check_path, saved_clock)
		return
	runner.assert_eq(_snapshot(runtime), present, "all saved body, signed note and source facts are restored")
	world = runtime.world_sim
	runner.assert_eq(str(world.spirit_sources.active.player.id), job_id, "load retains the original source process identity")
	advanced = helper._advance(runtime, due - GameClock.elapsed_ms)
	runner.assert_true(advanced, "restored source reaches the retained deadline")
	runner.assert_eq(_snapshot(runtime), future, "restored source and all other world domains reach the same future")
	runner.assert_eq(int(world.spirit_sources.sources.hearth_seam.spent), spent, "restoring does not repeat source consumption")
	runner.assert_eq(str(world.site_affairs.notes[note_id].used), job_id, "restoring cannot issue or consume a second note")
	var placed: bool = helper._object_action(runtime, "place")
	runner.assert_true(placed, "the same original medium is physically returned")
	if not placed:
		_cleanup(main, source_path, check_path, saved_clock)
		return
	var returned: Dictionary = helper._ask_at_desk(runtime, "verify_return", note_id, report)
	runner.assert_true(bool(returned.get("ok", false)), "ordinary return verification is requested: " + str(returned))
	if not bool(returned.get("ok", false)):
		_cleanup(main, source_path, check_path, saved_clock)
		return
	var check_id: String = str(returned.process.id)
	var service: Dictionary = world.services.jobs.get(check_id, {})
	runner.assert_true(not service.is_empty() and str(service.get("actor", "")) != "player", "the real issuer performs the verification with another body")
	if service.is_empty():
		_cleanup(main, source_path, check_path, saved_clock)
		return
	var inspector: String = str(service.actor)
	advanced = helper._advance(runtime, 250)
	runner.assert_true(advanced and world.services.owns_actor(inspector), "the inspector's original route is genuinely in flight")
	if not advanced or not world.services.owns_actor(inspector):
		_cleanup(main, source_path, check_path, saved_clock)
		return
	runner.assert_true(world.site_affairs.checks[check_id].observation.is_empty(), "travelling has not yet manufactured site evidence")
	saved = runtime.save_game(check_path)
	runner.assert_eq(saved, OK, "the actual travelling inspector saves in the ordinary session")
	if saved != OK:
		_cleanup(main, source_path, check_path, saved_clock)
		return
	var inspection_present: String = _snapshot(runtime)
	var finished: bool = helper._finish_visitor(runtime, inspector)
	runner.assert_true(finished, "the original inspector completes its real visit and registration")
	if not finished:
		_cleanup(main, source_path, check_path, saved_clock)
		return
	runner.assert_true(int(world.site_affairs.notes[note_id].closed_ms) >= 0, "official closure follows the actual inspection")
	runner.assert_eq(SimInteractionRequests.observe(world, "subject:player", returned.process).status, "pending", "the remote result is not automatically heard")
	var inspection_future: String = _snapshot(runtime)
	loaded = runtime.load_game(check_path)
	runner.assert_eq(loaded, OK, "ordinary loading restores the in-flight inspector")
	if loaded == OK:
		runner.assert_eq(_snapshot(runtime), inspection_present, "the inspector's saved body and original observation state return together")
		finished = helper._finish_visitor(runtime, inspector)
		runner.assert_true(finished, "restored inspector finishes the same original service")
		runner.assert_eq(_snapshot(runtime), inspection_future, "restored inspection produces the same complete joint future")
		var received: Dictionary = helper._ask_at_desk(runtime, "verify_return", note_id, report)
		runner.assert_eq(received.get("status"), "completed", "face-to-face follow-up actually receives the completed result")
	_cleanup(main, source_path, check_path, saved_clock)
	print("SCENARIO source-loan continuity: current signed source, one debit, physical return and saved inspector; old archive rejected")


func _reject_archive(runner: Object, runtime: WorldContinuityRuntime) -> void:
	var original: PackedByteArray = FileAccess.get_file_as_bytes(ARCHIVE)
	var raw: Variant = JSON.parse_string(original.get_string_from_utf8())
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SOURCE_SHA, "real source-loan archive retains its recorded digest")
	runner.assert_true(raw is Dictionary, "the original source-loan archive remains readable")
	if not raw is Dictionary:
		return
	var source: Dictionary = raw
	var input: String = _json(source)
	var world: RegionalSimulation = runtime.world_sim
	var content: ReolContentDB = runtime._home._content
	var terrain: WorldMapData = world.map_data
	var before: String = _snapshot(runtime)
	var clock: String = _json(GameClock.to_dict())
	runner.assert_eq(int(source.schema_version), 37, "the old loan retains its genuine version")
	runner.assert_eq(SessionSaveSchema.rejection_reason(source.schema_version), SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT, "the old loan has the environment rejection")
	runner.assert_true(WorldSessionSnapshot.stage(runtime, source).is_empty(), "the old loan cannot invent its missing field history")
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(ARCHIVE)), ERR_INVALID_DATA, "ordinary loading refuses the original old loan")
	runner.assert_eq(runtime._notice, "旧环境格式不再支持，存档未改；请新开局。", "old loan loading explains the rejection")
	runner.assert_true(runtime.world_sim == world and runtime._home._content == content and runtime.world_sim.map_data == terrain, "refusal leaves all live owners intact")
	runner.assert_eq(_json(GameClock.to_dict()), clock, "refusal leaves shared time intact")
	runner.assert_eq(_snapshot(runtime), before, "refusal leaves the complete session intact")
	runner.assert_eq(_json(source), input, "staging does not alter the supplied old archive")
	runner.assert_eq(FileAccess.get_file_as_bytes(ARCHIVE), original, "refusal leaves the original archive bytes intact")


func _cleanup(main: Node, source_path: String, check_path: String, clock: Dictionary) -> void:
	for path: String in [source_path, check_path]:
		for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	if is_instance_valid(main):
		main.free()
	GameClock.restore_state(clock)


func _snapshot(runtime: WorldContinuityRuntime) -> String:
	return _json(WorldSessionSnapshot.capture(runtime))


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
