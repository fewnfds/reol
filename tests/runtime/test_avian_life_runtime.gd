extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var adapter: AvianLifeRuntime = runtime.avian_adapter
	var domain: SimAvianLife = runtime.world_sim.avian_life
	runner.assert_eq(domain.birds.size(), 2, "real two-region adapter assembles nonhuman life once")
	var before: Dictionary = domain.to_dict()
	runner.assert_true(adapter.select_bird("moss_sparrow") and adapter.panel.visible, "nearby visible bird opens its own inspector")
	adapter.refresh()
	adapter.panel.hide()
	adapter.select_bird("moss_sparrow")
	runner.assert_eq(domain.to_dict(), before, "opening bird UI creates no new knowledge or food")
	runner.assert_true(bool(adapter.submit("approach").ok), "UI orders a real approach to the bird")
	GameClock.advance_msec(5000)
	runner.assert_true(bool(adapter.submit("approach").ok), "moving bird can be approached again at its current position")
	GameClock.advance_msec(1000)
	fixture.home.simulation.inventory.containers["actor:player"]["meal"] = 1
	runner.assert_true(bool(adapter.submit("feed").ok), "real carried meal can become scattered edible crumbs")
	runner.assert_eq(fixture.home.simulation.inventory.quantity("actor:player", "meal"), 0, "UI gift consumes actual player food")
	var original: int = fixture.home.simulation.inventory.quantity("garden", "herb")
	runner.assert_true(bool(adapter.submit("ask_herb").ok), "gesture starts a real accepted light-load errand")
	var end: int = GameClock.elapsed_ms + 60000
	while domain.inventory.quantity("bird:moss_sparrow", "herb") == 0 and GameClock.elapsed_ms < end:
		GameClock.advance_msec(50)
	runner.assert_eq(domain.inventory.quantity("bird:moss_sparrow", "herb"), 1, "bird actually picks up one sprig before delivery")
	var path: String = "user://tests/avian_runtime_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "carried nonhuman cargo saves with the ordinary world")
	var carried: Dictionary = domain.to_dict()
	GameClock.advance_msec(10000)
	var future: String = JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)
	runner.assert_eq(fixture.home.simulation.inventory.quantity("garden", "herb"), original + 1, "UI request produces a real garden delivery")
	runner.assert_eq(runtime.load_game(path), OK, "same main runtime restores in-flight nonhuman life")
	domain = runtime.world_sim.avian_life
	runner.assert_eq(VillageRuntime._json_normalized(domain.to_dict()), VillageRuntime._json_normalized(carried), "carried item and pending nonhuman action recover intact across JSON numeric types")
	GameClock.advance_msec(10000)
	runner.assert_eq(JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true), future, "normal load continues nonhuman errands and all old domains to the same future")
	runner.assert_eq(fixture.home.simulation.inventory.quantity("garden", "herb"), original + 1, "load cannot deliver a second copy")
	runner.assert_true(runtime.travel_to("river", domain.body_cell("reed_sparrow")), "same original player body travels to the far bird's habitat")
	GameClock.advance_msec(20000)
	runner.assert_true(adapter.select_bird("reed_sparrow"), "visitor sees a far bird by actual position, without becoming a resident")
	fixture.home.simulation.inventory.containers["actor:player"]["meal"] = 1
	runner.assert_true(bool(adapter.submit("feed").ok), "far habitat can receive food from the visitor's one original home ledger")
	runner.assert_eq(fixture.home.simulation.inventory.quantity("actor:player", "meal"), 0, "visiting does not create a second bag or consume another resident's food")
	runner.assert_eq(runtime.save_game(path), OK, "cross-habitat food provenance enters the same save")
	runner.assert_eq(runtime.load_game(path), OK, "cross-habitat gift validates against the actual original inventory")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	fixtures._dispose(fixture)
	print("SCENARIO visible avian: approach, actual food gift, specific request and physical herb cargo resume in the joint session")
