extends RefCounted
## Genuine unfinished source plus explicitly labelled synthetic v43-v46 envelopes.
## No thermal law, body sample, frozen content or original fixture is rewritten.

const ARCHIVE: String = "res://tests/fixtures/session_v32.json"
const SHA: String = "a804cc0707f0e1be89372868bbdb58dc4544b4b1aa4e296a00dd999c185cd88a"


func run(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var bytes: String = FileAccess.get_file_as_string(ARCHIVE)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var loaded: Error = runtime.load_game(ProjectSettings.globalize_path(ARCHIVE))
	runner.assert_eq(loaded, OK, "genuine v32 held-stone source enters the one current runtime")
	if loaded == OK:
		_exercise(runner, runtime)
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SHA, "source amount migration retains independently recorded original fixture SHA")
	runner.assert_eq(FileAccess.get_file_as_string(ARCHIVE), bytes, "conversion and rejection never rewrite original fixture bytes")
	main.free()
	GameClock.restore_state(prior)
	print("SCENARIO heat amount migration: genuine in-flight archive, explicit v43-v46 envelopes, receipt-derived transfer amounts, frozen bundle and unchanged bodies/energy, strict current format and atomic failure")


func _exercise(runner: Object, runtime: WorldContinuityRuntime) -> void:
	var pending: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_eq(int(pending.schema_version), SessionSaveSchema.VERSION, "in-flight archive writes only the current root")
	runner.assert_eq(int(pending.continuity.world.artifacts.version), SimArtifacts.VERSION, "in-flight archive writes only the current artifact format")
	var pending_legacy: Dictionary = _legacy(pending, 46)
	var pending_candidate: Dictionary = WorldSessionSnapshot.stage(runtime, pending_legacy)
	runner.assert_true(not pending_candidate.is_empty(), "a legacy unfinished operation stages before it has a heat amount")
	if pending_candidate.is_empty():
		return
	GameClock.advance_msec(840050 - GameClock.elapsed_ms)
	var current: Dictionary = WorldSessionSnapshot.capture(runtime)
	var heat: Dictionary = current.continuity.world.local_heat
	runner.assert_eq(heat.receipts.size(), 1, "genuine operation completes with exactly one original receipt")
	if heat.receipts.size() != 1:
		return
	var action: String = str(heat.receipts.keys()[0])
	var event_index: int = _event_index(current, action)
	runner.assert_true(event_index >= 0, "the unique original source has its matching artifact event")
	if event_index < 0:
		return
	var event: Dictionary = current.continuity.world.artifacts.events[event_index]
	runner.assert_eq(event.heat_amount, heat.receipts[action].amount, "completed artifact event stores the actual accepted amount")
	for version: int in [43, 44, 45, 46]:
		var source: Dictionary = _legacy(current, version)
		var before: String = _json(source)
		var upgraded: Dictionary = SessionSaveSchema.upgrade(source)
		runner.assert_true(not upgraded.is_empty(), "explicit synthetic v%d envelope converts through the historical boundary" % version)
		if upgraded.is_empty():
			continue
		runner.assert_eq(_json(upgraded), _json(current), "v%d conversion changes only versions and receipt-derived event amount" % version)
		runner.assert_eq(_json(upgraded.content_bundle), _json(source.content_bundle), "v%d conversion preserves the original content and digest" % version)
		runner.assert_eq(_json(upgraded.simulation), _json(source.simulation), "v%d conversion leaves original bodies, inventories and exposure facts unchanged" % version)
		runner.assert_eq(_json(upgraded.continuity.world.local_heat), _json(source.continuity.world.local_heat), "v%d conversion preserves exact thermal state, slope and history" % version)
		var staged: Dictionary = WorldSessionSnapshot.stage(runtime, source)
		runner.assert_true(not staged.is_empty(), "v%d receipt amount passes complete independent candidate validation" % version)
		runner.assert_eq(_json(source), before, "v%d conversion does not repair source input in place" % version)
	var resumed: RegionalSimulation = pending_candidate.world
	runner.assert_true(resumed.advance_to_ms(840050), "independent pending candidate completes at the original common-time boundary")
	runner.assert_eq(_json(resumed.to_dict()), _json(current.continuity.world), "resuming the old in-flight source neither repeats cost nor changes the complete world")
	# Both current and imported owners must also retain the same later future.
	var complete_candidate: Dictionary = WorldSessionSnapshot.stage(runtime, _legacy(current, 46))
	if not complete_candidate.is_empty():
		var whole: RegionalSimulation = complete_candidate.world
		var future: int = 853781
		runner.assert_true(whole.advance_to_ms(future), "imported completed source advances a whole future interval")
		for at_ms: int in [840051, 840367, 844999, 850000, future]:
			runner.assert_true(resumed.advance_to_ms(at_ms), "resumed source advances the same future in arbitrary pieces")
		runner.assert_eq(_json(resumed.to_dict()), _json(whole.to_dict()), "old pending/completed conversion and whole/sliced future produce identical complete facts")
	for kind: String in ["missing_amount", "changed_amount", "non_warm_amount", "missing_receipt", "changed_receipt", "wrong_digest", "forged_flow", "mixed_current", "legacy_future_field", "legacy_missing_receipt"]:
		var bad: Dictionary = current.duplicate(true)
		match kind:
			"missing_amount": bad.continuity.world.artifacts.events[event_index].erase("heat_amount")
			"changed_amount": bad.continuity.world.artifacts.events[event_index].heat_amount += 1
			"non_warm_amount": bad.continuity.world.artifacts.events[0]["heat_amount"] = event.heat_amount
			"missing_receipt": bad.continuity.world.local_heat.receipts.erase(action)
			"changed_receipt": bad.continuity.world.local_heat.receipts[action].amount += 1
			"wrong_digest": bad.content_bundle.digest = "0".repeat(64)
			"forged_flow": bad.continuity.world.local_heat.flows = [{"from": "254,255", "to": "", "rate": 1}]
			"mixed_current": bad.continuity.world.version = 38
			"legacy_future_field":
				bad = _legacy(current, 46)
				bad.continuity.world.artifacts.events[event_index]["heat_amount"] = event.heat_amount
			"legacy_missing_receipt":
				bad = _legacy(current, 46)
				bad.continuity.world.local_heat.receipts.erase(action)
		_reject(runner, runtime, bad, kind)


func _legacy(current: Dictionary, version: int) -> Dictionary:
	var result: Dictionary = current.duplicate(true)
	result.schema_version = version
	result.continuity.world.version = 38
	result.continuity.world.artifacts.version = 6
	for event: Dictionary in result.continuity.world.artifacts.events:
		event.erase("heat_amount")
	if version <= 45:
		result.world.erase("terrain_overrides")
	if version == 43:
		result.erase("assembly")
	return result


func _reject(runner: Object, runtime: WorldContinuityRuntime, bad: Dictionary, kind: String) -> void:
	var world: RegionalSimulation = runtime.world_sim
	var before: String = _json(WorldSessionSnapshot.capture(runtime))
	var clock: String = _json(GameClock.to_dict())
	var input: String = _json(bad)
	runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "source amount candidate rejects " + kind)
	runner.assert_true(runtime.world_sim == world, "rejected " + kind + " retains the original owner")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, "rejected " + kind + " preserves the complete live session")
	runner.assert_eq(_json(GameClock.to_dict()), clock, "rejected " + kind + " preserves common time")
	runner.assert_eq(_json(bad), input, "rejected " + kind + " never rewrites its input")


func _event_index(snapshot: Dictionary, action: String) -> int:
	var events: Array = snapshot.continuity.world.artifacts.events
	for index: int in events.size():
		if events[index].action == action:
			return index
	return -1


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
