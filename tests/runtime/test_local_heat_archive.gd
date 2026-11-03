extends RefCounted
## A clicked ordinary run saved halfway through the original warming action.
## Archives are immutable; independent normal scenes must share one future.

const ARCHIVE: String = "res://tests/fixtures/session_v32.json"
const SOURCE_SHA256: String = "a804cc0707f0e1be89372868bbdb58dc4544b4b1aa4e296a00dd999c185cd88a"
const SOURCE_BYTES: int = 171898
const SOURCE_MS: int = 797431
const COMPLETION_MS: int = 840050
const FUTURE_MS: int = 977431


func run(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var original: String = FileAccess.get_file_as_string(ARCHIVE)
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SOURCE_SHA256, "real clicked warming archive retains its independently recorded source SHA")
	runner.assert_eq(original.to_utf8_buffer().size(), SOURCE_BYTES, "real source retains its original full byte length")
	var expected: String = ""
	for attempt: int in 2:
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var runtime: WorldContinuityRuntime = main._continuity
		var loaded: Error = runtime.load_game(ProjectSettings.globalize_path(ARCHIVE))
		runner.assert_eq(loaded, OK, "a new ordinary main scene loads the real unfinished warming action")
		if loaded != OK:
			main.free()
			continue
		var world: RegionalSimulation = runtime.world_sim
		var source_cell := Vector2i(254, 255)
		runner.assert_eq(GameClock.elapsed_ms, SOURCE_MS, "load resumes the actual fractional operation time")
		runner.assert_eq(world.artifacts.active.player.verb, "warm", "the actual held stone is still being operated")
		runner.assert_eq(int(world.artifacts.objects.hearth_stone.charge), 4, "the unfinished source retains its four actual charges after the NPC's earlier cooking")
		runner.assert_eq(world.local_heat.input_energy, 0, "no heat is invented before the operation completes")
		GameClock.advance_msec(COMPLETION_MS - SOURCE_MS)
		runner.assert_eq(int(world.artifacts.objects.hearth_stone.charge), 3, "completion consumes one charge from that same original object")
		runner.assert_eq(world.local_heat.receipts.size(), 1, "one completed original action has exactly one heat source receipt")
		runner.assert_eq(world.local_heat.local_tenths(source_cell), 180, "completion deposits actual finite local warmth rather than a character buff")
		runner.assert_eq(world.environment.samples.player.heat_tenths, 0, "a source just after a minute boundary does not rewrite its past exposure sample")
		GameClock.advance_msec(10000)
		runner.assert_true(world.local_heat.loss_energy > 0 and world.local_heat.local_tenths(source_cell) < 180, "real future time dissipates the source and transfers heat to neighboring space")
		runner.assert_true(runtime.travel_to("river"), "the holder can actually leave by the original journey process")
		GameClock.advance_msec(FUTURE_MS - GameClock.elapsed_ms)
		runner.assert_true(runtime.player_journey.is_empty() and runtime.current_region == "river", "the original body reaches the distant settlement while the original field persists")
		runner.assert_eq(world.local_heat.local_tenths(runtime._home._player.cell), 0, "previously released warmth does not teleport with the carried stone")
		runner.assert_eq(int(world.artifacts.objects.hearth_stone.charge), 3, "carrying the remaining source does not invent or repeatedly spend a pulse")
		var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
		runner.assert_true(not WorldSessionSnapshot.stage(runtime, snapshot).is_empty(), "the full ordinary candidate restores completed heat, receipts, construction and environmental history together")
		var future: String = JSON.stringify(VillageRuntime._json_normalized(snapshot), "", true, true)
		if attempt == 0:
			expected = future
		else:
			runner.assert_eq(future, expected, "two independent ordinary scenes produce byte-identical complete futures from the clicked half-finished source")
		main.free()
	runner.assert_eq(FileAccess.get_file_as_string(ARCHIVE), original, "the clicked source archive is never regenerated or overwritten")
	GameClock.restore_state(prior)
	print("SCENARIO local heat archive: real held-source operation, original NPC resource use, finite completion, local dissipation, physical departure and byte-identical complete ordinary-scene futures")
