extends RefCounted
## The ordinary caption projects shared time and only the active body's senses.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	var view: WeatherRuntime = adapter.weather_adapter
	view.refresh()
	var caption: Label = view._caption
	var conditions: Dictionary = adapter.world_sim.environment.local_conditions("player")
	runner.assert_true(caption.visible and caption.text.begins_with(adapter.world_sim.environment.date_label()), "local caption shows the same calendar projection as the actual world")
	runner.assert_true(not str(conditions.feeling).is_empty() and caption.text.contains(str(conditions.feeling)), "human caption projects the original human's qualitative conditions")
	runner.assert_true(not caption.text.contains("°") and not caption.text.contains("℃") and not caption.text.contains("负担"), "normal senses do not reveal developer temperature and burden numbers")
	runner.assert_true(caption.clip_text and caption.size.x <= 618.0, "local line stays within the left HUD width instead of covering the person panel")
	var before: String = _canonical(adapter)
	view.refresh()
	view.refresh()
	runner.assert_eq(_canonical(adapter), before, "reading or redrawing conditions never submits world actions or exposure costs")
	GameClock.advance_msec(60000)
	view.refresh()
	runner.assert_true(caption.text.begins_with(adapter.world_sim.environment.date_label()), "clock signal and manual refresh share one current calendar")
	_stage_calendar_snapshot(adapter, runner)
	adapter.avatar_subject = "subject:avian:home_sparrow"
	view.refresh()
	runner.assert_true(caption.visible and caption.text == "%s · %s" % [adapter.world_sim.environment.date_label(), "山间落雨" if adapter.world_sim.weather.current_kind(view._weather_region) == "rain" else "天晴"], "bird can see date/weather without being given a human body's cold or heat judgment")
	runner.assert_true(not caption.tooltip_text.contains("实际衣着"), "bird weather help does not prescribe human clothing")
	adapter.avatar_subject = "subject:soul:yan_heng"
	view.refresh()
	runner.assert_true(not caption.visible, "disembodied perception does not acquire human weather senses through the HUD")
	adapter.avatar_subject = "subject:player"
	view.refresh()
	runner.assert_true(caption.visible, "returning the view to the human restores its own conditions")
	_fixtures._dispose(fixture)
	print("SCENARIO environment caption: one calendar, local qualitative human conditions, no hidden numeric weather knowledge, bird/soul boundaries and read-only rendering")


func _canonical(adapter: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(adapter)), "", true, true)


func _stage_calendar_snapshot(adapter: WorldContinuityRuntime, runner: Object) -> void:
	var snapshot: Dictionary = WorldSessionSnapshot.capture(adapter)
	var before: String = _canonical(adapter)
	var live: RegionalSimulation = adapter.world_sim
	var staged: Dictionary = WorldSessionSnapshot.stage(adapter, snapshot)
	runner.assert_true(not staged.is_empty(), "ordinary joint snapshot stages with the calendar offset derived from existing clock fields")
	if not staged.is_empty():
		var candidate: RegionalSimulation = staged.world
		runner.assert_true(candidate != live, "calendar validation constructs an independent candidate world")
		runner.assert_eq(candidate.environment.to_dict(), snapshot.continuity.world.environment, "ordinary stage preserves the saved environmental sample and activation boundary")
		runner.assert_eq(candidate.elapsed_ms, GameClock.elapsed_ms, "candidate environment and session retain one shared elapsed time")
	runner.assert_true(adapter.world_sim == live and _canonical(adapter) == before, "successful calendar staging leaves the entire live world and clock unchanged")
	var altered: Dictionary = snapshot.duplicate(true)
	altered.clock.total_minutes = int(altered.clock.total_minutes) + 1
	runner.assert_true(WorldSessionSnapshot.stage(adapter, altered).is_empty(), "a different calendar epoch cannot silently shift an otherwise valid world's seasons")
	runner.assert_true(adapter.world_sim == live and _canonical(adapter) == before, "rejected clock offset leaves the original environment, clock and all pending actions unchanged")
