extends RefCounted
## Genuine unfinished v1 source carried through labelled v43-v47 envelopes.
## Never project a new fixed-Q state back into a fictitious old thermal field.

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
		_exercise(runner, runtime, bytes)
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SHA, "source amount migration retains independently recorded original fixture SHA")
	runner.assert_eq(FileAccess.get_file_as_string(ARCHIVE), bytes, "conversion and rejection never rewrite original fixture bytes")
	main.free()
	GameClock.restore_state(prior)
	print("SCENARIO heat amount migration: genuine in-flight v1 archive, explicit v43-v47 envelopes, actual resumed source and receipt, strict current format and atomic failure")


func _exercise(runner: Object, runtime: WorldContinuityRuntime, bytes: String) -> void:
	var pending: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_eq(int(pending.schema_version), SessionSaveSchema.VERSION, "in-flight archive writes only the current root")
	runner.assert_eq(int(pending.continuity.world.artifacts.version), SimArtifacts.VERSION, "in-flight archive writes only the current artifact format")
	var source: Variant = JSON.parse_string(bytes)
	var content: ReolContentDB = ReolContentDB.legacy_v42()
	if not source is Dictionary or content == null:
		runner.assert_true(false, "the genuine v32 and recorded compatibility definitions are available")
		return
	var historical: Dictionary = SessionSaveSchema._upgrade(source, content)
	if historical.is_empty():
		runner.assert_true(false, "the genuine v32 reaches the old v47 envelope")
		return
	var old_heat: Dictionary = historical.continuity.world.local_heat
	runner.assert_eq(int(old_heat.version), 1, "the historical boundary retains the original v1 heat state")
	runner.assert_true(old_heat.receipts.is_empty() and old_heat.cells.is_empty(), "the archived warming action has not yet deposited a source")
	var pending_candidate: Dictionary = {}
	var converted: Dictionary = {}
	for version: int in [43, 44, 45, 46, 47]:
		var legacy: Dictionary = _legacy(historical, version)
		var before: String = _json(legacy)
		runner.assert_eq(_json(SessionSaveSchema._upgrade(legacy, null)), _json(historical), "v%d envelope returns to the identical old v47 state" % version)
		var staged: Dictionary = WorldSessionSnapshot.stage(runtime, legacy)
		runner.assert_true(not staged.is_empty(), "v%d unfinished source passes independent v1 and v2 candidate validation" % version)
		runner.assert_eq(_json(legacy), before, "v%d conversion never mutates its input" % version)
		if staged.is_empty():
			continue
		if pending_candidate.is_empty():
			pending_candidate = staged
			converted = staged.snapshot
		else:
			runner.assert_eq(_json(staged.snapshot), _json(converted), "v%d imports the same complete pending world" % version)
	if pending_candidate.is_empty():
		return
	runner.assert_eq(_json(converted.continuity.world.artifacts.active), _json(historical.continuity.world.artifacts.active), "import retains the original unfinished action and its actual due time")
	runner.assert_eq(_json(converted.continuity.world.environment.samples), _json(historical.continuity.world.environment.samples), "import preserves the sampled body temperatures and exposure history")
	runner.assert_eq(_json(converted.simulation.actors), _json(historical.simulation.actors), "import preserves the original bodies")
	runner.assert_eq(_json(converted.simulation.inventory), _json(historical.simulation.inventory), "import preserves the original inventory and ledger")
	runner.assert_eq(converted.continuity.world.local_heat.last_sample_mode, "legacy_excess", "the old sampled heat keeps its explicit legacy interpretation")
	runner.assert_eq(int(converted.continuity.world.local_heat.version), 2, "the accepted live field has the current version")
	var heat_path: String = "res://data/definitions/local_heat.json"
	for path: String in historical.content_bundle.documents:
		if path != heat_path:
			runner.assert_eq(_json(converted.content_bundle.documents[path]), _json(historical.content_bundle.documents[path]), "thermal import preserves the archived non-heat document " + path)
	runner.assert_eq(int(historical.content_bundle.documents[heat_path].version), 1, "the archived heat definition remains v1")
	runner.assert_eq(int(converted.content_bundle.documents[heat_path].version), 2, "the imported heat definition is explicitly v2")
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
	var resumed: RegionalSimulation = pending_candidate.world
	runner.assert_true(resumed.advance_to_ms(840050), "independent pending candidate completes at the original common-time boundary")
	runner.assert_eq(_json(resumed.to_dict()), _json(current.continuity.world), "resuming the old in-flight source neither repeats cost nor changes the complete world")
	# Both current and imported owners must also retain the same later future.
	var complete_candidate: Dictionary = WorldSessionSnapshot.stage(runtime, current)
	runner.assert_true(not complete_candidate.is_empty(), "the completed current source stages without projecting Q backwards")
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
				bad = _legacy(historical, 46)
				bad.continuity.world.artifacts.events[0]["heat_amount"] = event.heat_amount
			"legacy_missing_receipt":
				bad = _legacy(historical, 46)
				# Deliberately claim the later real completion at the earlier time
				# without its receipt; the old boundary must refuse this forgery.
				var forged_event: Dictionary = event.duplicate(true)
				forged_event.erase("heat_amount")
				bad.continuity.world.artifacts.events.append(forged_event)
				runner.assert_true(SessionSaveSchema._upgrade(bad, null).is_empty(), "a claimed legacy completion without its original receipt cannot acquire an amount")
		_reject(runner, runtime, bad, kind)


func _legacy(historical: Dictionary, version: int) -> Dictionary:
	var result: Dictionary = historical.duplicate(true)
	result.schema_version = version
	if version < 47:
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
