extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = adapter.world_sim
	var cell: Vector2i = adapter.controlled_cell()
	var before: String = _canonical(adapter)
	var sky: Dictionary = SimNaturalLight.sky(world, cell)
	runner.assert_true(bool(sky.supported), "ordinary opening has rule-backed natural light")
	if not bool(sky.supported):
		fixtures._dispose(fixture)
		return
	runner.assert_eq(sky.at_ms, world.elapsed_ms, "light uses the original accepted physical timestamp")
	runner.assert_eq(sky, SimNaturalLight.sky(world, cell), "same original geography/weather/time gives the same complete sky")
	var local: Dictionary = SimNaturalLight.at_cell(world, cell)
	runner.assert_true(bool(local.supported) and not bool(local.roofed), "open ground reads original absence of a roof")
	runner.assert_eq(local.local_relative, sky.total_relative, "open ground does not create a second light scale")
	runner.assert_true(not SimNaturalLight.sky(world, Vector2i(-1, 0)).supported, "outside map has no fabricated light value")
	runner.assert_true(not SimNaturalLight.sky(null, cell).has("total_relative"), "missing world is explicit failure, never zero brightness")
	runner.assert_true(adapter.natural_adapter.describe(cell).contains(SimNaturalLight.description(local)), "ordinary visible ground observes the same qualitative local light")
	var distant: Vector2i = cell + Vector2i(20, 0)
	runner.assert_true(not adapter.natural_adapter.describe(distant).contains("日光"), "light query does not bypass the observation interface's visibility boundary")
	var tint := DayNight.new()
	tint.bind_world(adapter)
	runner.assert_eq(tint.color, DayNight.color_for_sky(sky), "normal world tint projects the same rule-backed sky")
	runner.assert_true(adapter.weather_adapter._caption.text.contains(SimNaturalLight.description(local).trim_suffix("。")), "weather HUD and light query agree at the same accepted time")
	runner.assert_eq(_canonical(adapter), before, "light, observation and tint queries change no world, body, knowledge or clock facts")

	# Real budget denial keeps physical time; desired time is not a solar clock.
	var debt_target: int = world.elapsed_ms + 1001
	runner.assert_true(not world.advance_to_ms(debt_target, 0), "zero event budget creates real retained simulation debt")
	tint.refresh()
	adapter.weather_adapter.refresh()
	runner.assert_eq(SimNaturalLight.sky(world, cell), sky, "owed future time cannot leak future sunlight")
	runner.assert_eq(tint.color, DayNight.color_for_sky(sky), "tint stays at the actual physical boundary while time is owed")
	GameClock.advance_msec(debt_target - GameClock.elapsed_ms)
	runner.assert_eq(world.elapsed_ms, debt_target, "the original clock/executor finishes its retained debt")
	tint.refresh()
	runner.assert_eq(tint.color, DayNight.color_for_sky(SimNaturalLight.sky(world, cell)), "debt settlement changes presentation from the same accepted source")

	# Independent current candidate uses its own content and exact current time.
	# The original clock and executor reached the same accepted time above.
	var path: String = "user://tests/natural_light_%d.json" % Time.get_ticks_usec()
	var save_result: Error = adapter.save_game(path)
	runner.assert_eq(save_result, OK, "ordinary joint saver captures the current natural-light content contract")
	if save_result == OK:
		var saved_sky: Dictionary = SimNaturalLight.sky(world, adapter.controlled_cell())
		GameClock.advance_msec(1001)
		var loaded: Error = adapter.load_game(path)
		runner.assert_eq(loaded, OK, "ordinary loader accepts its independently assembled current candidate")
		if loaded == OK:
			runner.assert_true(adapter.world_sim != world, "load replaces the accepted candidate rather than borrowing original light state")
			runner.assert_eq(SimNaturalLight.sky(adapter.world_sim, adapter.controlled_cell()), saved_sky, "load recovers exact sunlight from its own saved content and time")
			runner.assert_eq(tint.color, DayNight.color_for_sky(saved_sky), "ordinary load signal immediately rebinds visible tint")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	tint.free()
	fixtures._dispose(fixture)
	_authored_geography(runner)
	print("SCENARIO natural light runtime: original time/geography/weather, local visible observation, no query mutation, real retained debt, ordinary joint save/load and tint rebinding")


func _authored_geography(runner: Object) -> void:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "authored geography starts from the validated current pack")
		return
	var bundle: Dictionary = content.content_bundle()
	var climate: Dictionary = bundle.documents["res://data/definitions/climate.json"]
	# A different world at the same civil hour, not a relabelled old archive.
	climate.solar.latitude_mdeg = 90000
	climate.solar.vernal_day = 90
	climate.solar.relative_scale = 100000
	bundle = ReolContentBundle.from_documents(bundle.documents)
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner, bundle)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	var light: Dictionary = SimNaturalLight.sky(adapter.world_sim, adapter.controlled_cell())
	runner.assert_true(bool(light.supported) and light.polar_state == "night" and light.total_relative == 0, "authored polar geography gives night at the same opening civil hour")
	var tint := DayNight.new()
	tint.bind_world(adapter)
	runner.assert_eq(tint.color, DayNight.NIGHT, "ordinary tint uses authored polar night rather than a fixed 08:00 table")
	var path: String = "user://tests/authored_solar_%d.json" % Time.get_ticks_usec()
	var saved: Error = adapter.save_game(path)
	runner.assert_eq(saved, OK, "current authored solar content is accepted by the ordinary save boundary")
	if saved == OK:
		var loaded: Error = adapter.load_game(path)
		runner.assert_eq(loaded, OK, "current authored solar content loads without an import default")
		if loaded == OK:
			runner.assert_eq(SimNaturalLight.sky(adapter.world_sim, adapter.controlled_cell()), light, "current restore retains nondefault latitude, phase and relative scale")
			runner.assert_eq(tint.color, DayNight.NIGHT, "load immediately projects the saved polar night")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	tint.free()
	fixtures._dispose(fixture)


func _canonical(adapter: WorldContinuityRuntime) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(adapter)))
