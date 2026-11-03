extends "res://tests/run_tests.gd"
## Immutable clicked v30 archive, loaded in two independent ordinary scenes.
## This is a targeted real-source regression; it does not alter the fixture.
## The recorded v30 full JSON hashes apply only before the facing migration.

const ARCHIVE: String = "res://tests/fixtures/session_v30.json"
const ARCHIVE_SHA: String = "3c977831104d238ec0fb02c28a74fc0dd8abed07faf313b7c3cec3e945b57588"
const FUTURE_SHA: String = "dfc3882e86a8722800666402ab41d9f5436057c47555783365c0317c96c26a1f"
const FUTURE_MS: int = 57902000
var _clock: ReolGameClock


func _run_tests() -> void:
	_clock = root.get_node("GameClock") as ReolGameClock
	var prior_clock: Dictionary = _clock.to_dict()
	var source: String = FileAccess.get_file_as_string(ARCHIVE)
	assert_eq(FileAccess.get_sha256(ARCHIVE), ARCHIVE_SHA, "the actual clicked v30 source keeps its independently recorded SHA256")
	assert_eq(source.to_utf8_buffer().size(), 783701, "the original pending-dressing archive retains its recorded byte count")
	var expected: String = ""
	for attempt: int in 2:
		var future: String = _resume_archive(attempt)
		assert_true(not future.is_empty(), "fresh actual scene %d produces a complete archived future" % attempt)
		if future.is_empty():
			continue
		if SessionSaveSchema.VERSION == 30:
			assert_eq(future.to_utf8_buffer().size(), 497771, "actual-scene future matches the independently recorded joint byte count")
			assert_eq(future.sha256_text(), FUTURE_SHA, "actual-scene future matches the independently recorded process-restart SHA256")
			assert_eq(future.hash(), 2419595148, "actual-scene future matches the independently recorded Godot string hash")
		if attempt == 0:
			expected = future
		else:
			assert_true(future == expected, "two independent actual scenes preserve the identical complete future, including original people, cold, clothing and physical travel")
		print("Environment archive attempt %d: %d UTF-8 bytes / hash %d / sha256 %s" % [attempt, future.to_utf8_buffer().size(), future.hash(), future.sha256_text()])
	assert_eq(FileAccess.get_file_as_string(ARCHIVE), source, "the real v30 source remains byte-for-byte unchanged after both scene continuations")
	_clock.restore_state(prior_clock)
	print("Environment archive probe: %d assertions / %d failures" % [checks, failed])
	quit(1 if failed > 0 else 0)


func _resume_archive(attempt: int) -> String:
	# Use the ordinary generated-terrain main-scene pattern of
	# tests/runtime/test_world_persistence.gd, never a synthetic flat world.
	_clock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var runtime: Node = main._continuity
	var loaded: Error = runtime.load_game(ProjectSettings.globalize_path(ARCHIVE))
	assert_eq(loaded, OK, "ordinary actual scene %d loads the real pending-dressing archive" % attempt)
	if loaded != OK:
		main.free()
		return ""
	var world: RefCounted = runtime.world_sim
	var identities: Dictionary = {}
	for region: String in world.regions:
		identities[region] = world.regions[region].actors.keys()
	var object_count: int = world.clothing.objects.size()
	var prior_events: int = world.clothing.events.size()
	var action: Dictionary = world.clothing.active.get("player", {})
	assert_true(not action.is_empty(), "the archived original body remains occupied by actual dressing")
	if action.is_empty():
		main.free()
		return ""
	assert_eq(_clock.elapsed_ms, 57602000, "actual archive retains its fractional shared world time")
	assert_eq(action.id, "clothing:action:4", "the original physical dressing keeps its stable process ID")
	assert_eq(action.started_ms, 57600000, "loading does not restart the already spent dressing time")
	assert_eq(action.due_ms, 57605000, "the original clothing deadline still has exactly three seconds remaining")
	assert_eq(action.verb, "wear", "the actual archived action is wearing the owned outer layer")
	assert_eq(action.object, "clothing:spare:1", "the action refers to the original finite cape")
	assert_true(not world.clothing.objects["clothing:robe:player"].worn and not world.clothing.objects["clothing:spare:1"].worn, "unfinished dressing grants no premature worn use")
	assert_eq(world.environment.energy_rate("player"), 4000, "the original prior cold sample is preserved through loading")
	assert_eq(world.environment.samples.player.at_ms, 57600000, "the cached exposure retains its actual sampling time")
	assert_true(world.environment.samples.player.garments.is_empty(), "the cold sample records the actual undressed body at that prior moment")
	assert_true(not runtime.travel_to("river"), "the actual resumed dressing still excludes a second travel process")
	assert_true(not runtime._home._player.request_sidestep(Vector2.RIGHT), "the actual resumed dressing still excludes a concurrent short body action")
	_clock.advance_msec(3000)
	assert_eq(_clock.elapsed_ms, 57605000, "the original three remaining seconds finish at the archived deadline")
	assert_true(not world.clothing.owns_actor("player") and world.clothing.objects["clothing:spare:1"].worn, "ordinary completion releases the same body and changes its one actual garment use")
	assert_eq(world.environment.energy_rate("player"), 4000, "completed dressing does not rewrite the preceding cold interval")
	assert_eq(world.clothing.events.size(), prior_events + 1, "resuming adds exactly one original completion record")
	assert_eq(_event_count(world, "clothing:action:4"), 1, "the resumed actual process cannot complete twice")
	_clock.advance_msec(55000)
	assert_eq(_clock.elapsed_ms, 57660000, "the next original full minute reaches the subsequent exposure sample")
	assert_eq(world.environment.energy_rate("player"), 0, "the next sample applies the now truly worn cape to future cold burden")
	assert_eq(world.environment.samples.player.garments.size(), 1, "the new sample references only the one actually worn layer")
	assert_eq(world.environment.samples.player.garments[0].id, "clothing:spare:1", "the new sample identifies the original physical cape")
	assert_eq(world.environment.local_conditions("player").region, "home", "the original departure point is geographically in the mountain climate")
	var departure: Vector2 = runtime._home._player.motion.position
	assert_true(runtime.travel_to("river"), "the released original body can begin an actual journey to the other settlement")
	assert_true(not runtime.player_journey.is_empty(), "the travel request creates an unfinished terrain-backed route")
	assert_true(runtime._home._player.motion.position.is_equal_approx(departure), "requesting departure does not teleport the actual body")
	var crossed_climate: bool = false
	var segments: int = 0
	while not runtime.player_journey.is_empty() and _clock.elapsed_ms < FUTURE_MS and segments < 2000:
		var due: int = int(runtime.player_journey.due_ms)
		if due <= _clock.elapsed_ms:
			assert_true(false, "the original in-flight route must keep a future segment deadline")
			break
		_clock.advance_msec(mini(due, FUTURE_MS) - _clock.elapsed_ms)
		segments += 1
		var local: Dictionary = world.environment.local_conditions("player")
		if local.region == "river":
			crossed_climate = true
			assert_true(runtime._home._player.cell.x >= 270, "lowland climate begins at the explicit geographic boundary rather than the body's home affiliation")
	assert_true(runtime.player_journey.is_empty(), "the actual original route completes through its own segment deadlines")
	assert_true(crossed_climate, "real intermediate movement crosses from mountain into lowland climate")
	assert_eq(runtime.current_region, "river", "the continuous body actually arrives in the distant settlement")
	assert_eq(runtime._home._player.cell, runtime.centers.river, "arrival reaches the original destination cell")
	assert_true(world.regions.home.actors.has("player") and not world.regions.river.actors.has("player"), "geographic climate does not clone or transfer the original body's state ownership")
	assert_eq(world.environment.local_conditions("player").region, "river", "the visiting original body senses its real destination climate")
	if _clock.elapsed_ms < FUTURE_MS:
		_clock.advance_msec(FUTURE_MS - _clock.elapsed_ms)
	assert_eq(_clock.elapsed_ms, FUTURE_MS, "archived dressing, journey and offscreen life reach the independently recorded common horizon")
	assert_eq(world.clothing.objects.size(), object_count, "resuming and traveling never duplicate the original clothing instances")
	assert_eq(world.clothing.events.size(), prior_events + 1, "the original world retains exactly one additional dressing event through the full future")
	assert_eq(_event_count(world, "clothing:action:4"), 1, "the physical dressing still has only one completion after arrival")
	for region: String in world.regions:
		assert_eq(world.regions[region].actors.keys(), identities[region], "scene continuation preserves the original named people in " + region)
	var snapshot_script: GDScript = load("res://scripts/runtime/world_session_snapshot.gd")
	var captured: Dictionary = snapshot_script.capture(runtime)
	var future: String = JSON.stringify(JSON.parse_string(JSON.stringify(captured, "", true, true)), "", true, true)
	main.free()
	return future


func _event_count(world: RefCounted, id: String) -> int:
	var count: int = 0
	for event: Dictionary in world.clothing.events:
		if event.id == id:
			count += 1
	return count
