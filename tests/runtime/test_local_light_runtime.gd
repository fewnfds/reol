extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	var light: LocalLightRuntime = adapter.light_adapter
	GameClock.set_paused(true)
	var at: Vector2i = adapter.world_sim.artifacts.object_cell("fire_stone")
	fixture.player.spawn_at(at)
	var fog := FogOfWar.new()
	fog.setup(fixture.world, at)
	fog.set_observer(0, 3)
	fog.update_now()
	fixture.home._fog = fog
	for verb: String in ["study", "enable"]:
		var action: Dictionary = adapter.world_sim.artifacts.begin("player", verb, "fire_stone")
		runner.assert_true(action.ok, "the original visible actor starts an actual light-source action: " + verb)
		if not action.ok:
			fixture.home._fog = null
			fog.free()
			fixtures._dispose(fixture)
			return
		GameClock.advance_msec(int(adapter.world_sim.artifacts.active.player.due_ms) - GameClock.elapsed_ms)
	var before: String = _canonical(adapter)
	light.refresh()
	runner.assert_true(light.light.enabled, "a rule-backed current source enables the actual PointLight2D projection")
	for cell: Vector2i in light.last_projection.get("values", {}):
		runner.assert_true(fog.is_cell_visible(cell), "the light texture contains only this observer's current visible cells")
	# Inspect the submitted image in headless mode; the dummy renderer retains
	# its initial readback copy across update(). Native QA checks the GPU image.
	var texture: Image = light.last_image
	var texture_center: Vector2i = TileGrid.world_to_cell(light.light.position)
	for y: int in LocalLightRuntime.SIDE:
		for x: int in LocalLightRuntime.SIDE:
			var cell: Vector2i = texture_center + Vector2i(x - LocalLightRuntime.RADIUS, y - LocalLightRuntime.RADIUS)
			if not fog.is_cell_visible(cell):
				runner.assert_eq(texture.get_pixel(x, y), Color.BLACK, "hidden texels cannot become a scene light or reveal hidden space: cell=%s texel=(%d,%d) center=%s projected=%s" % [cell, x, y, texture_center, light.last_projection.get("values", {}).has(cell)])
	runner.assert_eq(light.light.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "the GPU does not interpolate light over a hidden cell boundary")
	runner.assert_true(adapter.natural_adapter.describe(at).contains("暖光"), "ordinary visible observation uses the same local-light rule")
	adapter.weather_adapter.refresh()
	runner.assert_true(adapter.weather_adapter._caption.text.contains("暖光"), "the current body's environment row observes local light")
	runner.assert_eq(_canonical(adapter), before, "projection, local caption and observation change no serialized world or knowledge")
	fog.set_focus(at + Vector2i(25, 0))
	fog.update_now()
	light.refresh()
	runner.assert_true(not light.light.enabled, "a previously explored source leaves no light texture in lost sight")
	runner.assert_true(not adapter.natural_adapter.describe(at).contains("暖光"), "a hidden old observation cannot query live light")
	fog.set_focus(at)
	fog.update_now()
	adapter.avatar_subject = "subject:soul:yan_heng"
	light.refresh()
	runner.assert_true(not light.light.enabled and light.last_projection.is_empty(), "a soul receives no borrowed physical lighting projection")
	adapter.avatar_subject = "subject:player"
	var action: Dictionary = adapter.world_sim.artifacts.begin("player", "disable", "fire_stone")
	runner.assert_true(action.ok, "the actual stop-light action starts")
	if action.ok:
		GameClock.advance_msec(int(adapter.world_sim.artifacts.active.player.due_ms) - GameClock.elapsed_ms)
		light.refresh()
		runner.assert_true(not adapter.world_sim.local_heat.device_emission_rates(GameClock.elapsed_ms).rates.has("fire_stone"), "the completed real switch removes the original fire stone's emission")
		var has_light: bool = false
		for value: int in light.last_projection.get("values", {}).values():
			has_light = has_light or value > 0
		runner.assert_eq(light.light.enabled, has_light, "switching one real source preserves independently present intrinsic light")
	fixture.home._fog = null
	fog.free()
	fixtures._dispose(fixture)
	_genuine_archive(runner)
	print("SCENARIO local-light view: original clock/actions, same bounded rule projection, nearest visible texels, honest lost sight/soul boundaries, no knowledge or stock side effects")


func _canonical(adapter: WorldContinuityRuntime) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(adapter)))


func _genuine_archive(runner: Object) -> void:
	const ARCHIVE: String = "res://tests/fixtures/session_v49_thermal.json"
	var original: PackedByteArray = FileAccess.get_file_as_bytes(ARCHIVE)
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	fixture.home.restore_map_factory = WorldMapData.from_descriptor
	var result: Error = adapter.load_game(ProjectSettings.globalize_path(ARCHIVE))
	runner.assert_eq(result, OK, "the genuine archived active fire stone loads through ordinary independent migration")
	if result == OK:
		var world: RegionalSimulation = adapter.world_sim
		var at: Vector2i = world.artifacts.object_cell("fire_stone")
		runner.assert_true(world.artifacts.objects.fire_stone.enabled and world.local_heat.continuous_input > 0, "the real historical source retains its enabled state and already paid heat")
		runner.assert_true(not world.artifacts.definitions.types.fire_stone.has("lighting"), "the archived content is not enriched from current installed fire-stone data")
		var before: String = _canonical(adapter)
		var light: Dictionary = SimLocalLight.at_cell(world, at)
		runner.assert_true(light.supported and int(light.artificial_relative) == 0, "an actual old active source remains optically unchanged")
		runner.assert_eq(_canonical(adapter), before, "reading the historical source leaves its complete migrated state untouched")
	runner.assert_eq(FileAccess.get_file_as_bytes(ARCHIVE), original, "the original historical fixture remains byte-for-byte unchanged")
	fixtures._dispose(fixture)
