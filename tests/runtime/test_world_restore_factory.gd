extends RefCounted
## Archived rules and assembly are independent from the currently open scene.

const FORAGING_PATH: String = "res://data/definitions/personal_foraging.json"


func run(runner: Object) -> void:
	var previous_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var adapter: WorldContinuityRuntime = main._continuity
	if adapter == null or adapter.world_sim == null:
		runner.assert_true(false, "ordinary opening initializes for independent assembly")
		main.free()
		GameClock.restore_state(previous_clock)
		return
	var first: Dictionary = WorldSessionSnapshot.capture(adapter)
	var second: Dictionary = _different_opening(first)
	var stable: String = _json(first)
	var original_world: RegionalSimulation = adapter.world_sim
	var original_settings: Dictionary = adapter.settings
	var original_centers: Dictionary = adapter.centers
	var original_config: Dictionary = adapter._home._config
	# Leave only the explicit host factory and presentation context. Neither an
	# active simulation nor its map, settings, centers or roster can help stage.
	adapter.world_sim = null
	adapter.settings = {}
	adapter.centers = {}
	adapter._home._config = {}
	var staged: Dictionary = WorldSessionSnapshot.stage(adapter, first)
	adapter.world_sim = original_world
	adapter.settings = original_settings
	adapter.centers = original_centers
	adapter._home._config = original_config
	runner.assert_true(not staged.is_empty(), "saved world assembles without any active world/map, settings, centers or home configuration")
	if not staged.is_empty():
		runner.assert_eq(_json(staged.world.to_dict()), _json(first.continuity.world), "restore-only factory reproduces every saved domain without issuing opening facts")
		runner.assert_true(not staged.world.regions.home._navigation.is_valid(), "isolated restore owns no live navigation callback")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(adapter)), stable, "isolated staging leaves the active session unchanged")

	var path: String = "user://tests/world_restore_%d.json" % Time.get_ticks_usec()
	if _load(adapter, path, second, runner, "B"):
		runner.assert_eq(int(adapter._home._config.actions.keep_wood.minutes), int(second.simulation.config.actions.keep_wood.minutes), "B installs its own scenario rule in the home adapter")
		runner.assert_eq(adapter.centers.river, _cell(second.assembly.centers.river), "B installs its saved region center")
		runner.assert_eq(str(adapter.settings.regions.home.label), str(second.assembly.settings.regions.home.label), "B installs its world presentation settings")
		if _load(adapter, path, first, runner, "A after B"):
			runner.assert_eq(_json(WorldSessionSnapshot.capture(adapter)), stable, "A after B preserves the complete original world and assembly")
			_load(adapter, path, second, runner, "B after A")
	var bad: Dictionary = second.duplicate(true)
	bad.assembly.region_configs.home.actions.keep_wood.minutes += 1
	var before: String = _json(WorldSessionSnapshot.capture(adapter))
	runner.assert_true(WorldSessionSnapshot.stage(adapter, bad).is_empty(), "archive assembly and saved scenario must agree")
	bad = second.duplicate(true)
	bad.continuity.world.erase("services")
	runner.assert_true(WorldSessionSnapshot.stage(adapter, bad).is_empty(), "two-region runtime rejects a missing services owner before publication")
	bad = second.duplicate(true)
	bad.assembly.settings.routes.river_road.amount += 1
	runner.assert_true(WorldSessionSnapshot.stage(adapter, bad).is_empty(), "archive assembly and saved world settings must agree")
	bad = second.duplicate(true)
	bad.assembly.settings.runtime.erase("enter_radius")
	bad.continuity.world.settings = bad.assembly.settings.duplicate(true)
	runner.assert_true(WorldSessionSnapshot.stage(adapter, bad).is_empty(), "unsupported runtime policy rejects before touching the active world")
	runner.assert_eq(_json(WorldSessionSnapshot.capture(adapter)), before, "failed assembly stages preserve content, time, inventory, owners and layout")
	runner.assert_eq(_json(first), stable, "assembly and cross-loads never mutate the input archive")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	main.free()
	GameClock.restore_state(previous_clock)
	print("SCENARIO independent assembly: no live region baseline; same-ID foraging A/B/A; saved centers/settings; strict mismatches; no new-game issuance")


func _different_opening(source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	var documents: Dictionary = result.content_bundle.documents.duplicate(true)
	documents[FORAGING_PATH].actions.keep_wood.minutes += 7
	result.content_bundle = ReolContentBundle.from_documents(documents)
	for id: String in result.assembly.region_configs:
		result.assembly.region_configs[id].actions.keep_wood.minutes += 7
		result.continuity.world.regions[id].config.actions.keep_wood.minutes += 7
	result.simulation.config.actions.keep_wood.minutes += 7
	result.assembly.settings.regions.home.label = "乙版山门"
	result.continuity.world.settings = result.assembly.settings.duplicate(true)
	result.assembly.centers.river[0] += 1
	result.continuity.centers = result.assembly.centers.duplicate(true)
	return result


func _load(adapter: WorldContinuityRuntime, path: String, snapshot: Dictionary, runner: Object, label: String) -> bool:
	runner.assert_eq(SimSaveStore.save_file(path, snapshot), OK, label + " archive writes")
	var result: Error = adapter.load_game(path)
	runner.assert_eq(result, OK, label + " loads its own content and assembly")
	return result == OK


func _cell(raw: Array) -> Vector2i:
	return Vector2i(int(raw[0]), int(raw[1]))


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
