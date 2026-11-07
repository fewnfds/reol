extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const LegacyRejection = preload("res://tests/runtime/helpers/legacy_rejection_archive.gd")
var fixtures := Fixtures.new()


func run(runner: Object) -> void:
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var sim: VillageSimulation = runtime.world_sim.regions.home
	# Only arrange the test player's starting approach. NPCs retain their normal
	# bodies, autonomy, resources and decisions throughout this scenario.
	fixture.player.spawn_at(SimRouteTravel.cell(sim.actors.chen_shouzhuo.cell))
	runtime.prepare_player_command()
	var bought: Dictionary = runtime.interaction_adapter.submit("subject:chen_shouzhuo", "trade", {"kind": "trade_offer", "id": "buy_meal"}, "spoken", {"lots": 1})
	runner.assert_true(bought.ok, "real player purchase can fund public labor without injected cash or goods")
	if not bought.ok:
		fixtures._dispose(fixture)
		return
	GameClock.advance_msec(180000)
	var found: bool = false
	for step: int in 360:
		var id: String = runtime.world_sim.budgeted_labor.latest_for("shi_tou")
		if not id.is_empty() and runtime.world_sim.budgeted_labor.contracts[id].status == "working":
			found = true
			break
		GameClock.advance_msec(30000)
	runner.assert_true(found, "ordinary autonomous residents find and negotiate an actually funded job")
	if found:
		var path: String = "user://tests/autonomous_livelihood_%d.json" % Time.get_ticks_usec()
		runner.assert_eq(runtime.save_game(path), OK, "normal joint save includes original NPC labor and bounded personal search")
		GameClock.advance_msec(3600000)
		var future: String = _canonical(runtime)
		var id: String = runtime.world_sim.budgeted_labor.latest_for("shi_tou")
		runner.assert_eq(runtime.world_sim.budgeted_labor.contracts[id].status, "paid", "normal scene NPC proceeds from real delivery to real acceptance")
		runner.assert_eq(runtime.world_sim.regions.home.inventory.available("actor:shi_tou", "meal"), 1, "normal scene NPC spends original wages on a carried reserve")
		runner.assert_eq(runtime.player_inventory().quantity("actor:player", "coin"), 4, "NPC life cannot take money directly from the player's bag")
		runner.assert_eq(runtime.load_game(path), OK, "normal candidate loader restores the autonomous NPC mid-job")
		GameClock.advance_msec(3600000)
		runner.assert_eq(_canonical(runtime), future, "all autonomous residents, inventories and messages resume the identical joint future")
		for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	fixtures._dispose(fixture)
	# Current run() already exercises autonomous decisions, paid work and joint resume.
	LegacyRejection.run(runner, {
		"res://tests/fixtures/conversation_v26.json": "d493d2c58815eaf289ebd5a91399a86cd0ab07514dedcc0eb9e59f73d77d342a",
		"res://tests/fixtures/session_v27.json": "ad45652fbdc5cc6db88e0af152cb4074a171e65f7948abfa5e9b79243f23e502",
	}, ["autonomous_livelihood"])
	print("SCENARIO ordinary autonomous livelihood: player sale funds public budget, unmodified residents seek/fulfil/claim/buy; joint save resumes without an NPC script override")


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)
