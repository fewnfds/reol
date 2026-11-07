extends RefCounted
## Stable original-body heading without a second movement clock or distance sum.

const Fixtures = preload("res://tests/sim/test_village_simulation.gd")
const RegionalFixtures = preload("res://tests/sim/test_regional_simulation.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_one_body_heading(runner)
	_route_sampling_and_resume(runner)
	_relocation_and_wall(runner)
	_village_fine_batch(runner)
	_near_far_views(runner)
	_legacy_and_invalid_snapshots(runner)
	print("SCENARIO body facing: one original heading, stable route direction, relocation/wall boundaries, fine/batched/restarted continuation and explicit legacy rejection")


func _body() -> Dictionary:
	var at: Vector2 = TileGrid.cell_to_world(Vector2i(10, 10))
	return {"position": [at.x, at.y], "cell": [10, 10], "facing": [0.0, 1.0]}


func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)


func _one_body_heading(runner: Object) -> void:
	var body: Dictionary = _body()
	var motion := SimLocalMotion.new()
	motion.bind_body(body)
	motion.facing = Vector2.LEFT
	runner.assert_eq(body.facing, [-1.0, 0.0], "manual heading writes the one original body")
	SimRouteTravel.face(body, Vector2(1, -1))
	runner.assert_true(motion.facing.is_equal_approx(Vector2(1, -1).normalized()), "route turn is immediately visible through the bound local controller")
	runner.assert_eq(_canonical(motion.to_dict().facing), _canonical(body.facing), "legacy motion snapshot projects the same heading instead of keeping a competing value")
	var second_view := SimLocalMotion.new()
	second_view.bind_body(body)
	runner.assert_eq(second_view.facing, motion.facing, "a rebuilt controller reads the current original heading")
	second_view.facing = Vector2.UP
	runner.assert_eq(motion.facing, Vector2.UP, "two views of one body cannot drift into independent facing state")
	var before: Dictionary = body.duplicate(true)
	SimRouteTravel.face(body, Vector2.ZERO)
	runner.assert_eq(body, before, "a stopped route cannot erase the last meaningful heading")


func _route_sampling_and_resume(runner: Object) -> void:
	var coarse: Dictionary = _body()
	SimRouteTravel.put(coarse, SimRouteTravel.point(coarse) + Vector2(0.3, 0.2))
	var fine: Dictionary = coarse.duplicate(true)
	var route: Dictionary = {"path": [[11, 9]]}
	SimRouteTravel.begin_segment(route, coarse, 137, 240.0)
	var end: int = int(route.due_ms)
	var halfway: int = 137 + ((end - 137) >> 1)
	SimRouteTravel.project(route, coarse, halfway)
	for at: int in range(138, halfway + 1):
		SimRouteTravel.project(route, fine, at)
	runner.assert_eq(_canonical(fine), _canonical(coarse), "arbitrary fractional route samples retain the exact same heading and point")
	runner.assert_true(SimRouteTravel.valid_segment(route, coarse, halfway, 240.0), "mid-route facing addition leaves the original geometric contract unchanged")
	var restored: Dictionary = JSON.parse_string(_canonical(coarse))
	var saved_route: Dictionary = JSON.parse_string(_canonical(route))
	SimRouteTravel.project(route, coarse, end)
	SimRouteTravel.project(saved_route, restored, end)
	runner.assert_eq(_canonical(restored), _canonical(coarse), "mid-route JSON resume reaches the same exact body and heading")
	var before: Dictionary = restored.duplicate(true)
	SimRouteTravel.project(saved_route, restored, end)
	runner.assert_eq(restored, before, "repeated route projection does not turn or displace the finished body again")
	var empty: Dictionary = {"path": []}
	SimRouteTravel.project(empty, restored, end + 50)
	runner.assert_eq(restored, before, "no route retains the last heading without a phantom stride")


func _relocation_and_wall(runner: Object) -> void:
	var body: Dictionary = _body()
	var motion := SimLocalMotion.new()
	motion.bind_body(body)
	motion.facing = Vector2.LEFT
	motion.relocate(TileGrid.cell_to_world(Vector2i(40, 30)))
	runner.assert_eq(motion.facing, Vector2.LEFT, "repositioning to a distant cell does not pretend the body walked or turned")
	runner.assert_true(motion.velocity.is_zero_approx() and motion.action.is_empty(), "relocation retains the existing clear-motion semantics")
	var edge: Vector2 = TileGrid.cell_to_world(Vector2i(10, 10))
	edge.x = 11.0 * TileGrid.TILE_SIZE - 0.01
	motion.relocate(edge)
	var wall: Callable = func(cell: Vector2i, direction: Vector2i) -> bool: return cell.x + direction.x <= 10
	motion.advance(0, 500, Vector2.RIGHT, wall)
	var stopped: Vector2 = motion.position
	motion.advance(500, 1000, Vector2.RIGHT, wall)
	runner.assert_true(motion.blocked and stopped.is_equal_approx(motion.position) and motion.velocity.is_zero_approx(), "continued input at a wall produces no actual walking displacement")
	runner.assert_eq(motion.facing, Vector2.RIGHT, "looking toward a blocked input remains separate from actually walking")
	runner.assert_true(body.keys().size() == 3, "heading does not create a second accumulated distance or animation clock")


func _village_fine_batch(runner: Object) -> void:
	var fine: VillageSimulation = _fixtures._make_simulation(runner)
	var coarse: VillageSimulation = _fixtures._make_simulation(runner)
	if fine == null or coarse == null:
		return
	runner.assert_true(fine.submit_action("player", "deliver_wood") and coarse.submit_action("player", "deliver_wood"), "native actor starts the same original labor route")
	for at: int in [137, 300, 733, 1449]:
		while fine.elapsed_ms < at:
			fine.advance_to_ms(mini(at, fine.elapsed_ms + 13))
		coarse.advance_to_ms(at)
		runner.assert_eq(_canonical(fine.to_dict()), _canonical(coarse.to_dict()), "fine and sparse native route/body state agree at %dms" % at)
	var saved: Dictionary = JSON.parse_string(_canonical(coarse.to_dict()))
	var resumed: VillageSimulation = _fixtures._make_simulation(runner)
	runner.assert_true(resumed.restore(saved), "original village loader accepts pending body heading")
	fine.advance_to_ms(240000)
	resumed.advance_to_ms(240000)
	runner.assert_eq(_canonical(resumed.to_dict()), _canonical(fine.to_dict()), "restored native labor and original body reach one identical later future")
	var bad: Dictionary = saved.duplicate(true)
	bad.actors.player.erase("facing")
	var before: String = _canonical(resumed.to_dict())
	runner.assert_true(not resumed.restore(bad), "modern body cannot omit its persistent heading")
	runner.assert_eq(_canonical(resumed.to_dict()), before, "invalid body heading leaves all original village state untouched")
	bad = saved.duplicate(true)
	bad.actors.player.facing = [2.0, 0.0]
	runner.assert_true(not resumed.restore(bad), "non-unit modern heading is rejected")


func _near_far_views(runner: Object) -> void:
	var regional_fixtures := RegionalFixtures.new()
	var near: RegionalSimulation = regional_fixtures._make_world(runner)
	var far: RegionalSimulation = regional_fixtures._make_world(runner)
	if near == null or far == null:
		return
	near.set_active_region("home")
	far.set_active_region("")
	for world: RegionalSimulation in [near, far]:
		runner.assert_true(world.regions.home.submit_action("shi_tou", "deliver_wood"), "same original local NPC starts its material route")
		runner.assert_true(world.regions.river.submit_action("river_shi_tou", "deliver_wood"), "same original remote NPC starts its material route")
		world.invalidate_region("home")
		world.invalidate_region("river")
	for target: int in [137, 1933, 121137]:
		while near.elapsed_ms < target:
			near.advance_to_ms(mini(target, near.elapsed_ms + 47))
		far.advance_to_ms(target)
		runner.assert_eq(_regional_state(near), _regional_state(far), "local/far execution and sampling preserve the same physical headings and world at %dms" % target)
	var saved: Dictionary = JSON.parse_string(_canonical(far.to_dict()))
	var resumed: RegionalSimulation = regional_fixtures._make_world(runner)
	runner.assert_true(resumed.restore(saved), "joint original-world restore accepts both in-progress body headings")
	near.set_active_region("river")
	resumed.set_active_region("home")
	near.advance_to_ms(600000)
	resumed.advance_to_ms(600000)
	runner.assert_eq(_regional_state(near), _regional_state(resumed), "switching which view is near does not reset heading or change the joint future")


func _regional_state(world: RegionalSimulation) -> String:
	var snapshot: Dictionary = world.to_dict()
	snapshot.erase("active_region")
	return _canonical(snapshot)


func _legacy_and_invalid_snapshots(runner: Object) -> void:
	var path: String = "res://tests/fixtures/session_v30.json"
	var original: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var legacy: Dictionary = JSON.parse_string(original.get_string_from_utf8())
	runner.assert_eq(FileAccess.get_sha256(path), "3c977831104d238ec0fb02c28a74fc0dd8abed07faf313b7c3cec3e945b57588", "the real v30 body archive retains its recorded bytes")
	runner.assert_eq(int(legacy.schema_version), 30, "the body archive retains its original root version")
	runner.assert_eq(SessionSaveSchema.rejection_reason(legacy.schema_version), SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT, "v30 reports the explicit old-environment rejection")
	runner.assert_true(SessionSaveSchema.upgrade(legacy).is_empty(), "v30 cannot be silently upgraded into a world without its actual field history")
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "ordinary scene initializes for body archive rejection")
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var live_world: RegionalSimulation = runtime.world_sim
	var live_content: ReolContentDB = runtime._home._content
	var live_map: WorldMapData = live_world.map_data
	var current: Dictionary = WorldSessionSnapshot.capture(runtime)
	var stable: String = _canonical(current)
	var stable_clock: String = _canonical(GameClock.to_dict())
	runner.assert_true(WorldSessionSnapshot.stage(runtime, legacy).is_empty(), "the original v30 candidate is rejected before publishing a world")
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(path)), ERR_INVALID_DATA, "ordinary loading refuses the real v30 body archive")
	runner.assert_eq(runtime._notice, "旧环境格式不再支持，存档未改；请新开局。", "ordinary loading explains why the old archive cannot be opened")
	runner.assert_true(runtime.world_sim == live_world and runtime._home._content == live_content and runtime.world_sim.map_data == live_map, "rejecting v30 leaves the world, content and map owners untouched")
	runner.assert_eq(_canonical(GameClock.to_dict()), stable_clock, "rejecting v30 does not alter the shared clock")
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(runtime)), stable, "rejecting v30 preserves the complete current session and body")
	runner.assert_eq(FileAccess.get_file_as_bytes(path), original, "rejecting v30 never rewrites the real archive")
	# Current-format cases must exercise real validation, rather than passing
	# merely because the original source was an unsupported old version.
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, current).is_empty(), "the undamaged current body candidate is independently loadable")
	var temp_path: String = "user://tests/body_facing_%d.json" % Time.get_ticks_usec()
	var damaged: Dictionary = current.duplicate(true)
	damaged.continuity.world.regions.home.actors.player.energy = float(damaged.continuity.world.regions.home.actors.player.energy) - 1.0
	_reject_current_body(runtime, damaged, temp_path, runner, "mismatched original home bodies")
	damaged = current.duplicate(true)
	var facing: Array = damaged.player.motion.facing
	damaged.player.motion.facing = [0.0, 1.0] if absf(float(facing[0])) > 0.1 else [1.0, 0.0]
	_reject_current_body(runtime, damaged, temp_path, runner, "a motion heading that disagrees with the original body")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(temp_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path + suffix))
	main.free()
	GameClock.restore_state(saved_clock)


func _reject_current_body(runtime: WorldContinuityRuntime, candidate: Dictionary, path: String, runner: Object, label: String) -> void:
	var old_world: RegionalSimulation = runtime.world_sim
	var old_content: ReolContentDB = runtime._home._content
	var old_map: WorldMapData = old_world.map_data
	var before: String = _canonical(WorldSessionSnapshot.capture(runtime))
	var old_clock: String = _canonical(GameClock.to_dict())
	var original: String = _canonical(candidate)
	runner.assert_true(WorldSessionSnapshot.stage(runtime, candidate).is_empty(), label + " is rejected during staging")
	runner.assert_eq(SimSaveStore.save_file(path, candidate), OK, label + " can be represented as an untrusted current-format save")
	runner.assert_eq(runtime.load_game(path), ERR_INVALID_DATA, label + " is rejected by ordinary loading")
	runner.assert_true(runtime.world_sim == old_world and runtime._home._content == old_content and runtime.world_sim.map_data == old_map, label + " leaves the live owners unchanged")
	runner.assert_eq(_canonical(GameClock.to_dict()), old_clock, label + " leaves the shared clock unchanged")
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(runtime)), before, label + " leaves the full current session unchanged")
	runner.assert_eq(_canonical(candidate), original, label + " does not mutate the rejected input")
