extends RefCounted
## Historical handovers are immutable; current exchange coverage lives in the
## ordinary controlled UI and joint-save suite, not a retired old environment.

const ARCHIVE: String = "res://tests/fixtures/session_v42_exchange.json"
const SHA256: String = "e13c2616a25f482db2397b585417d027c2759172393c6929eb98a4713b676ebf"


func run(runner: Object) -> void:
	# test_private_exchange_runtime._accept_and_restore exercises a real current
	# handover through the ordinary interface, including reservation, one
	# delivery, cancellation and the same complete post-load world future.
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary scene initializes for historical handover rejection")
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var original: PackedByteArray = FileAccess.get_file_as_bytes(ARCHIVE)
	var raw: Variant = JSON.parse_string(original.get_string_from_utf8())
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SHA256, "the real handover archive retains its recorded digest")
	runner.assert_true(raw is Dictionary, "the historical handover archive remains readable")
	if raw is Dictionary:
		var source: Dictionary = raw
		var source_before: String = _json(source)
		var world: RegionalSimulation = runtime.world_sim
		var content: ReolContentDB = runtime._home._content
		var terrain: WorldMapData = world.map_data
		var before: String = _json(WorldSessionSnapshot.capture(runtime))
		var clock: String = _json(GameClock.to_dict())
		runner.assert_eq(int(source.schema_version), 42, "the handover archive retains its original root format")
		runner.assert_eq(SessionSaveSchema.rejection_reason(source.schema_version), SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT, "the original handover has the explicit old-environment reason")
		runner.assert_true(WorldSessionSnapshot.stage(runtime, source).is_empty(), "old handover cannot invent field history in a new session")
		runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(ARCHIVE)), ERR_INVALID_DATA, "ordinary loading refuses the real historical handover")
		runner.assert_eq(runtime._notice, "旧环境格式不再支持，存档未改；请新开局。", "the historical handover reports the reason")
		runner.assert_true(runtime.world_sim == world and runtime._home._content == content and runtime.world_sim.map_data == terrain, "rejection leaves the original live owners intact")
		runner.assert_eq(_json(GameClock.to_dict()), clock, "rejection leaves the shared clock intact")
		runner.assert_eq(_json(WorldSessionSnapshot.capture(runtime)), before, "rejection leaves the whole live world, stock and body intact")
		runner.assert_eq(_json(source), source_before, "staging does not mutate the supplied historical input")
		runner.assert_eq(FileAccess.get_file_as_bytes(ARCHIVE), original, "the historical handover file is not rewritten")
	main.free()
	GameClock.restore_state(saved_clock)
	print("SCENARIO private exchange continuity: immutable historical handover refused; current real handover and cancellation covered by runtime suite")


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
