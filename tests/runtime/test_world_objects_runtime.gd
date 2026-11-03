extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var adapter: WorldObjectsRuntime = runtime.object_adapter
	runner.assert_eq(runtime.world_sim.artifacts.objects.size(), 1, "new actual runtime assembles its opening object")
	runner.assert_true(adapter.select_object("hearth_stone") and adapter.panel.visible, "nearby visible object opens its dedicated inspector")
	runner.assert_true(not adapter.panel._buttons.charge.visible, "unknown activation does not expose the learned recharge operation")
	var before: Dictionary = runtime.world_sim.artifacts.to_dict()
	adapter.refresh()
	adapter.panel.hide()
	adapter.select_object("hearth_stone")
	runner.assert_eq(runtime.world_sim.artifacts.to_dict(), before, "opening/closing object UI creates no knowledge or resource change")
	runner.assert_true(bool(adapter.submit("approach").ok), "inspector can order a real terrain-backed approach")
	var deadline: int = GameClock.elapsed_ms + 120 * 60000
	while not runtime.player_journey.is_empty() and GameClock.tick_index < deadline:
		GameClock.advance_ticks(1)
	runner.assert_true(runtime.player_journey.is_empty(), "approach finishes without teleporting")
	runner.assert_true(bool(adapter.submit("take").ok), "actual inspector can take the unique instance")
	GameClock.advance_ticks(int(runtime.world_sim.artifacts.definitions.verbs.take.minutes))
	runner.assert_eq(runtime.world_sim.artifacts.objects.hearth_stone.container, "actor:player", "taking in the game changes real custody")
	runner.assert_true(bool(adapter.submit("study").ok), "actual inspector starts paid investigation")
	runner.assert_true(not bool(runtime.submit_service("rest").ok), "visitor service cannot steal an artifact executor's body")
	runner.assert_true(not runtime.travel_to("river"), "new automatic travel cannot silently overwrite an experiment")
	GameClock.advance_ticks(1)
	var path: String = "user://tests/artifact_runtime_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "in-progress artifact and all other world domains save together")
	var pending: Dictionary = runtime.world_sim.artifacts.to_dict()
	var qi: int = int(fixture.home.simulation.actors.player.qi)
	fixture.home.cancel_player_action()
	runner.assert_true(not runtime.world_sim.artifacts.owns_actor("player"), "manual movement's existing cancel path interrupts investigation")
	runner.assert_eq(fixture.home.simulation.actors.player.qi, qi, "manual cancellation cannot refund invested qi")
	runner.assert_eq(runtime.load_game(path), OK, "normal load restores unfinished artifact work")
	runner.assert_eq(runtime.world_sim.artifacts.to_dict(), pending, "artifact remaining duration and custody are restored exactly")
	var finish: int = int(runtime.world_sim.artifacts.active.player.due_ms)
	GameClock.advance_msec(finish - GameClock.elapsed_ms)
	runner.assert_true(bool(runtime.world_sim.artifacts.describe("player", "hearth_stone").method), "restored investigation completes and yields personal method knowledge")
	adapter.select_object("hearth_stone")
	runner.assert_true(adapter.panel._buttons.charge.visible, "learning exposes the relevant operation through an authorized view")
	var denial: Dictionary = adapter.submit("take")
	runner.assert_true(not bool(denial.ok) and adapter.panel._notice.text == denial.line, "older experiment outcome cannot overwrite a new command's refusal")
	runner.assert_true(bool(adapter.submit("to_garden").ok), "known heat method and carried stone allow a real trip to the garden")
	GameClock.advance_msec(5000)
	runner.assert_true(runtime.player_journey.is_empty(), "short garden route has physically finished before craft begins")
	runner.assert_true(adapter.panel._buttons.dry.visible, "personal control method exposes the second heat use")
	var raw_herbs: int = fixture.home.simulation.inventory.quantity("garden", "herb")
	runner.assert_true(bool(adapter.submit("dry").ok), "actual inspector starts drying at a fractional-minute time")
	var due_ms: int = int(runtime.world_sim.artifacts.active.player.due_ms)
	GameClock.advance_msec(due_ms - GameClock.elapsed_ms - 1)
	runner.assert_eq(fixture.home.simulation.inventory.quantity("garden", "dried_herb"), 0, "UI-driven craft cannot finish one millisecond early")
	GameClock.advance_msec(1)
	runner.assert_eq(fixture.home.simulation.inventory.quantity("garden", "herb"), raw_herbs - 2, "UI-driven drying actually consumes its raw herbs")
	runner.assert_eq(fixture.home.simulation.inventory.quantity("garden", "dried_herb"), 2, "UI-driven drying leaves its actual product")
	runner.assert_true(not runtime.service_adapter.panel._phase.text.contains("正在办理"), "shared activity panel clears at a fractional-minute artifact completion")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	fixtures._dispose(fixture)
	print("SCENARIO object UI: approach→take→investigate, no duplicate body owner, manual cancel and joint resume")
