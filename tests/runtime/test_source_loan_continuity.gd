extends RefCounted
## Frozen ordinary new-life borrowing, continued by the same real UI commands.

const Replay = preload("res://tests/runtime/helpers/source_loan_replay.gd")
const ARCHIVE: String = "res://tests/fixtures/session_v37.json"
const SOURCE_SHA: String = "64c9ee3cf0bfa3cd8bf012a1461f8c2b0992740d4907cd1d8de7b66886bd030a"
const SOURCE_MS: int = 874750
const NOTE: String = "site:note:1"
const ORIGINAL: String = "spirit:1"


func run(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	var bytes: String = FileAccess.get_file_as_string(ARCHIVE)
	var source: Dictionary = JSON.parse_string(bytes)
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SOURCE_SHA, "real original source-loan archive retains its independently frozen SHA")
	runner.assert_eq(bytes.to_utf8_buffer().size(), 215793, "real original source-loan archive retains every original UTF-8 byte")
	_assert_original(source, runner)
	var helper := Replay.new()
	var expected: String = ""
	for attempt: int in 2:
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var runtime: WorldContinuityRuntime = main._continuity
		if runtime == null or runtime.world_sim == null:
			runner.assert_true(false, "ordinary independent main initializes before actual source-loan continuation")
			main.free()
			continue
		var suffix: String = "test_%d_%d" % [Time.get_ticks_usec(), attempt]
		var report: Dictionary = helper.replay_loan(runtime, suffix)
		runner.assert_true(bool(report.get("ok", false)), "normal original source-loan replay completes: " + str(report.get("error", "")))
		if bool(report.get("ok", false)):
			var future: Dictionary = WorldSessionSnapshot.capture(runtime)
			_assert_future(runtime, source, report, future, runner)
			var canonical: String = _canonical(future)
			if attempt == 0:
				expected = canonical
			else:
				runner.assert_eq(canonical, expected, "independent real main loaders reach the byte-identical full world after source use, actual verification, received answer and departure")
		main.free()
	runner.assert_eq(FileAccess.get_file_as_string(ARCHIVE), bytes, "real normal-command replay never rewrites the immutable in-progress source fixture")
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SOURCE_SHA, "genuine source archive remains byte-identical after both complete normal-command continuations")
	GameClock.restore_state(clock)
	print("SCENARIO actual source-loan continuity: genuine v37 partial channel, one original source debit, actual same-stone placement, original issuer inspection/registration, private result followed by received reply, river journey and identical independent full futures")


func _assert_original(source: Dictionary, runner: Object) -> void:
	runner.assert_eq(int(source.schema_version), 37, "frozen source is the genuine original source-loan session format")
	runner.assert_eq(int(source.clock.elapsed_ms), SOURCE_MS, "source archive genuinely captures original channel work thirty seconds after starting")
	var world: Dictionary = source.continuity.world
	var original: Dictionary = world.spirit_sources.active.get("player", {})
	runner.assert_true(not original.is_empty(), "real source archive contains original in-progress bodily work")
	if original.is_empty():
		return
	runner.assert_eq(original.id, ORIGINAL, "actual first source process retains its stable original identity")
	runner.assert_eq(int(original.started_ms), 844750, "actual channel start precedes the frozen progress point by the real thirty seconds")
	runner.assert_eq(int(original.due_ms), 964750, "actual channel retains its original two-minute deadline")
	runner.assert_eq(world.artifacts.objects.hearth_stone.container, "actor:player", "actual source archive has the same physically collected original medium")
	runner.assert_eq(int(world.regions.home.actors.player.qi), 19, "partial source labor has not granted its future original body output")
	runner.assert_eq(int(world.spirit_sources.sources.hearth_seam.spent), 0, "partial channel has not spent its reserved batch early")
	var note: Dictionary = world.site_affairs.notes[NOTE]
	runner.assert_eq(note.bound, ORIGINAL, "actual signed promise is associated with the same original unfinished source process")
	runner.assert_eq(note.used, "", "actual signed promise has not been consumed before original completion")
	runner.assert_eq(note.attempts, [ORIGINAL], "source archive contains exactly the one actual first attempt")
	runner.assert_eq(world.site_affairs.checks.size(), 0, "source archive contains no imagined future return inspection")


func _assert_future(runtime: WorldContinuityRuntime, source: Dictionary, report: Dictionary, future: Dictionary, runner: Object) -> void:
	var world: RegionalSimulation = runtime.world_sim
	var note: Dictionary = world.site_affairs.notes[NOTE]
	var record: Dictionary = world.spirit_sources.records.get(ORIGINAL, {})
	runner.assert_eq(int(report.source_ms), SOURCE_MS, "normal replay loaded the exact real archive instant")
	runner.assert_true(bool(report.candidate_valid), "normal replay independently stages the complete original world future")
	runner.assert_eq(runtime.current_region, "river", "original player actually travels to the other settlement after hearing the result")
	runner.assert_true(runtime.player_journey.is_empty(), "actual other-settlement arrival leaves no imaginary pending journey")
	runner.assert_eq(GameClock.elapsed_ms, world.elapsed_ms, "ordinary runtime clock and source/service owners share the same final millisecond")
	runner.assert_true(not record.is_empty(), "original in-progress source retains its actual completion receipt")
	if record.is_empty():
		return
	runner.assert_eq(record.result, "success", "original channel genuinely succeeds once")
	runner.assert_eq(int(record.started_ms), 844750, "continuation never restarts the actual saved source work")
	runner.assert_eq(int(record.finished_ms), 964750, "actual saved channel completes at its retained exact boundary")
	runner.assert_eq(int(record.output), 1, "original nearly full body accepts only the one actual remaining energy unit")
	runner.assert_eq(int(record.loss), 3, "unaccepted original conversion output remains a real recorded loss")
	runner.assert_eq(int(world.spirit_sources.sources.hearth_seam.spent), 6, "entire real continuation spends exactly one original source batch")
	runner.assert_eq(int(world.regions.home.actors.player.qi), 20, "original player receives its one actual capacity-limited source output")
	runner.assert_eq(note.used, ORIGINAL, "same signed note names the original actual successful source receipt")
	runner.assert_eq(note.bound, "", "actual source completion releases the temporary association")
	runner.assert_eq(note.attempts, [ORIGINAL], "saving, loading and actual departure do not duplicate the original attempt")
	runner.assert_eq(world.site_affairs.notes.size(), 1, "normal continuation never duplicates the signed borrowing")
	runner.assert_eq(world.artifacts.objects.hearth_stone.container, "kitchen", "normal placement leaves the same original stone at its agreed real return place")
	runner.assert_eq(world.artifacts.objects.size(), source.continuity.world.artifacts.objects.size(), "actual borrowing and return never manufacture replacement equipment")
	runner.assert_true(int(note.closed_ms) > int(record.finished_ms), "official return closure follows actual source use")
	var check: Dictionary = world.site_affairs.checks.get(note.closure_job, {})
	runner.assert_true(not check.is_empty(), "official closure names an original actual verification job")
	if check.is_empty():
		return
	var job: Dictionary = world.services.jobs[check.job]
	runner.assert_eq(job.actor, note.issuer, "actual verifier uses the original issuing office holder's body")
	runner.assert_true(job.actor != "player" and check.requester == "player", "travelling official and requesting original player remain different people")
	runner.assert_eq(job.kind, "site_return", "same original service owns both inspection and registration stages")
	runner.assert_eq(job.status, "completed", "actual inspection service finishes normally at the original desk")
	runner.assert_eq(job.stage, "register", "actual completed service records its final registration stage")
	runner.assert_eq(check.observation.object, "hearth_stone", "site evidence concerns the exact original public stone")
	runner.assert_eq(check.observation.container, "kitchen", "site evidence observes the original agreed actual place")
	runner.assert_true(int(check.observation.at_ms) < int(check.registered_ms), "actual site observation precedes the separate real desk registration")
	runner.assert_eq(int(check.registered_ms), int(note.closed_ms), "same actual registration closes its original obligation once")
	var seen_departure: bool = false
	var seen_unreceived: bool = false
	for step: Dictionary in report.steps:
		if step.kind == "actual_inspector_departed":
			seen_departure = true
			runner.assert_true(bool(step.player_free), "ordinary accepted inspection leaves the original applicant free to act")
			runner.assert_eq(step.job.actor, note.issuer, "actual in-flight inspection snapshot has the same original executing official")
			runner.assert_true(step.check.observation.is_empty(), "actual in-flight inspection snapshot has no prematurely granted site evidence")
		elif step.kind == "actual_return_registered":
			seen_unreceived = true
			runner.assert_eq(step.remote_poll.status, "pending", "pure query before the actual answer cannot reveal completed remote registration")
	runner.assert_true(seen_departure and seen_unreceived, "normal replay actually checks both the travelling body and the unreceived-result knowledge boundary")
	runner.assert_eq(report.received.status, "completed", "ordinary in-person follow-up actually receives the registered result")
	runner.assert_true(str(report.received.line).contains("声称") and str(report.received.line).contains("复位"), "received formal wording preserves claim versus observed equipment return")
	var receipt: Dictionary = {"domain": "site_affairs", "id": str(check.job), "performer": world.embodiment.subject_for_actor(str(check.issuer))}
	var before_query: String = _canonical(WorldSessionSnapshot.capture(runtime))
	runner.assert_eq(SimInteractionRequests.observe(world, "subject:player", receipt).status, "completed", "actual hearer may remember the result after departing for another settlement")
	runner.assert_eq(SimInteractionRequests.observe(world, "subject:shi_tou", receipt).status, "unconfirmed", "another original resident gains no private result from knowing its process ID")
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(runtime)), before_query, "remembering received evidence and refusing another hearer are pure state queries")
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, future).is_empty(), "complete actual future independently validates all original body, inventory, source, service and social owners")


func _canonical(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
