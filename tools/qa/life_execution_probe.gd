extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var runtime: Node = main._continuity
	for version: int in range(1, 6):
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/session_v%d.json" % version))
		var upgraded: Dictionary = SessionSaveSchema.upgrade(raw, runtime._home._content)
		var result: Dictionary = {"version": version, "upgrade": not upgraded.is_empty()}
		if not upgraded.is_empty():
			result.valid_home = runtime._home._valid_snapshot(upgraded)
			result.staged = not load("res://scripts/runtime/world_session_snapshot.gd").stage(runtime, raw).is_empty()
			if not bool(result.staged):
				result.region_schema = SimSnapshotSchema.validate(upgraded.simulation, runtime._home._content, _actors(upgraded.continuity.world.regions))
		print("PROBE ", JSON.stringify(result))
	main.free()
	quit()


func _actors(regions: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for region: Dictionary in regions.values():
		for id: String in region.synchronize_actors():
			result[id] = true
	return result


func assert_true(_value: bool, _label: String) -> void:
	pass
