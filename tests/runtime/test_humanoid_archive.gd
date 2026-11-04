extends RefCounted
## Genuine clicked/stepped/travelling archive, resumed through ordinary scenes.

const ARCHIVE: String = "res://tests/fixtures/session_v31.json"
const SOURCE_SHA256: String = "3753f178d701b26d2bd479f5acd06068037fcfa03bf2e5f7b58e5ebd6dacc991"
const SOURCE_BYTES: int = 136019
const SOURCE_MS: int = 1623
const FUTURE_MS: int = 121623
const SolarProjection = preload("res://tests/runtime/helpers/solar_legacy_projection.gd")


func run(runner: Object) -> void:
	_real_travelling_archive(runner)
	_original_v30_boundary(runner)
	print("SCENARIO humanoid archive: actual fractional journey, one original facing/body, persistent people and clothes, independent full-scene future and unchanged legacy environment")


func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)


func _legacy_environment(value: Dictionary, prior: Dictionary, snapshot: Dictionary) -> Dictionary:
	# E2 adds zero heat without resampling; the later solar migration only
	# changes the bound rules version when its fixed defaults are present.
	if prior.get("version") != 1:
		return {}
	var result: Dictionary = SolarProjection.prior_environment(value, prior, snapshot)
	if result.is_empty() or not result.get("samples") is Dictionary:
		return {}
	result.version = 1
	for sample: Dictionary in result.samples.values():
		if not SnapshotValues.valid_integer(sample.get("heat_tenths"), 0) or sample.heat_tenths != 0:
			return {}
		sample.erase("heat_tenths")
	return result


func _real_travelling_archive(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var original: String = FileAccess.get_file_as_string(ARCHIVE)
	var source: Dictionary = JSON.parse_string(original)
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SOURCE_SHA256, "genuine v31 source matches its independently recorded clicked-run SHA256")
	runner.assert_eq(original.to_utf8_buffer().size(), SOURCE_BYTES, "genuine v31 source retains its original complete byte length")
	var expected: String = ""
	for attempt: int in 2:
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var runtime: WorldContinuityRuntime = main._continuity
		var loaded: Error = runtime.load_game(ProjectSettings.globalize_path(ARCHIVE))
		runner.assert_eq(loaded, OK, "real v31 travel archive loads through a newly instantiated ordinary main scene")
		if loaded != OK:
			main.free()
			continue
		var world: RegionalSimulation = runtime.world_sim
		var player: PlayerCharacter = runtime._home._player
		runner.assert_eq(GameClock.elapsed_ms, SOURCE_MS, "real archive resumes the original fractional movement instant")
		runner.assert_eq(runtime.current_region, "home", "saved player is still physically near home instead of already at the destination")
		runner.assert_true(not runtime.player_journey.is_empty() and runtime.player_journey.destination == "river", "load retains the actual incomplete journey and its destination")
		runner.assert_eq(_canonical(runtime.player_journey), _canonical(source.continuity.player_journey), "load does not reroute or restart the archived movement segment")
		runner.assert_true(player.motion.position.is_equal_approx(Vector2(float(source.player.position[0]), float(source.player.position[1]))), "fractional body position is not snapped to a tile center on load")
		runner.assert_eq(player.motion.facing, Vector2.RIGHT, "recorded real rightward movement preserves the body's last heading")
		runner.assert_eq(_canonical(player.motion.to_dict().facing), _canonical(world.regions.home.actors.player.facing), "controller and original body have one shared facing after load")
		runner.assert_eq(_canonical(world.clothing.to_dict()), _canonical(source.continuity.world.clothing), "appearance loading preserves all original garment ownership, wetness and pending actions")
		runner.assert_eq(_canonical(_legacy_environment(world.environment.to_dict(), source.continuity.world.environment, WorldSessionSnapshot.capture(runtime))), _canonical(source.continuity.world.environment), "appearance loading does not resample or restart the saved environment")
		var identities: Dictionary = {}
		for region: String in world.regions:
			identities[region] = world.regions[region].actors.keys()
		var garments: Dictionary = world.clothing.objects.duplicate(true)
		GameClock.advance_msec(FUTURE_MS - SOURCE_MS)
		runner.assert_eq(GameClock.elapsed_ms, FUTURE_MS, "normal common clock reaches the independently chosen continuation horizon")
		runner.assert_true(runtime.player_journey.is_empty() and runtime.current_region == "river", "original walking process actually arrives at river rather than switching a label")
		runner.assert_eq(player.cell, runtime.centers.river, "real body ends on the actual destination cell")
		runner.assert_eq(player.motion.position, TileGrid.cell_to_world(runtime.centers.river), "actual arrival commits the destination's continuous point")
		var body: Dictionary = world.regions.home.actors.player
		runner.assert_eq(player.motion.facing, SimRouteTravel.facing(body), "arrival keeps the same one-body direction through the local controller")
		runner.assert_true(absf(player.motion.facing.length() - 1.0) < 0.001, "completed route retains a valid final heading without resetting to an idle default")
		for region: String in world.regions:
			runner.assert_eq(world.regions[region].actors.keys(), identities[region], "leaving and arriving preserve all original actor IDs in " + region)
		runner.assert_eq(world.clothing.objects.keys(), garments.keys(), "offscreen and nearby views do not create replacement clothes")
		for id: String in garments:
			runner.assert_true(world.clothing.objects[id].type == garments[id].type and world.clothing.objects[id].owner == garments[id].owner, "original garment identity and ownership survive travel: " + id)
		runner.assert_eq(_canonical(player.clothing_appearance), _canonical(world.clothing.appearance("player")), "arrived player view projects the same actual worn objects")
		var future: String = _canonical(WorldSessionSnapshot.capture(runtime))
		if attempt == 0:
			expected = future
		else:
			runner.assert_true(future == expected, "two independent ordinary main scenes resume the real in-flight v31 archive to byte-identical complete joint futures")
		main.free()
	runner.assert_eq(FileAccess.get_file_as_string(ARCHIVE), original, "real clicked v31 source is never overwritten or regenerated by tests")
	GameClock.restore_state(prior)


func _original_v30_boundary(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var path: String = "res://tests/fixtures/session_v30.json"
	var original: String = FileAccess.get_file_as_string(path)
	var source: Dictionary = JSON.parse_string(original)
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var loaded: Error = runtime.load_game(ProjectSettings.globalize_path(path))
	runner.assert_eq(loaded, OK, "genuine v30 night-clothing archive migrates through the normal scene loader")
	if loaded == OK:
		var world: RegionalSimulation = runtime.world_sim
		runner.assert_eq(GameClock.elapsed_ms, int(source.clock.elapsed_ms), "new facing contract preserves the older world's actual time")
		runner.assert_eq(_canonical(world.clothing.to_dict()), _canonical(source.continuity.world.clothing), "v30 migration does not replace clothing, reset wetness or finish the pending dressing early")
		runner.assert_eq(_canonical(_legacy_environment(world.environment.to_dict(), source.continuity.world.environment, WorldSessionSnapshot.capture(runtime))), _canonical(source.continuity.world.environment), "v30 migration preserves the real environmental exposure and activation boundary")
		runner.assert_eq(_canonical(world.weather.to_dict()), _canonical(source.continuity.world.weather), "v30 migration preserves the existing rainy phase and real wet beds")
		runner.assert_eq(_canonical(world.regions.home.actors.player.facing), _canonical(source.player.motion.facing), "v30 player's original recorded facing becomes the single persistent body heading")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "real v30 source remains byte-for-byte unchanged")
	main.free()
	GameClock.restore_state(prior)
