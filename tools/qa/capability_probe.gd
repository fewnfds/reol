extends SceneTree
## Isolate roundtrip boundaries without modifying the live rules.


func _initialize() -> void:
	call_deferred("_probe")


func _probe() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var runtime: Node = main._continuity
	var clock: Node = root.get_node("GameClock")
	var sessions: GDScript = load("res://scripts/runtime/world_session_snapshot.gd")
	clock.set_paused(true)
	var loaded: Error = runtime.load_game(ProjectSettings.globalize_path("res://tests/fixtures/session_v35.json"))
	if loaded != OK:
		printerr("original load=", loaded)
		quit(1)
		return
	runtime.conflict_adapter.yield_player()
	clock.advance_msec(5000)
	var response: Dictionary = runtime.capability_adapter.begin_practice()
	print("begin=", response)
	if not bool(response.ok):
		quit(1)
		return
	clock.advance_msec(15000)
	var path: String = ProjectSettings.globalize_path("res://logs/capability_probe_session.json")
	runtime.save_game(path)
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var practice: RefCounted = runtime.world_sim.capability_practice
	var state: Dictionary = stored.continuity.world.capability_practice
	print("shape=", practice.Schema.validate(state, practice))
	print("source schema=", runtime.world_sim.spirit_sources.Schema.validate(stored.continuity.world.spirit_sources, runtime.world_sim.spirit_sources))
	print("raw stage=", not sessions.stage(runtime, sessions.capture(runtime)).is_empty())
	print("json stage=", not sessions.stage(runtime, stored).is_empty())
	for row: Dictionary in state.active.values():
		print("job=", practice.Schema._job(row, practice), " direction=", practice.Schema._direction(row.direction, practice.definitions.nodes.mobile_guard))
		for index: int in row.path.size():
			print("path ", index, " strict=", row.path[index] == practice._target_cell(row, int(row.step_index) + index), " normalized=", SnapshotValues.normalized(row.path[index]) == SnapshotValues.normalized(practice._target_cell(row, int(row.step_index) + index)))
	quit(0)
