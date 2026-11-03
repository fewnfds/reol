extends RefCounted
## Candidate geometry must never be priced against the live scene or map.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
var _fixtures := Fixtures.new()


class QueryTrapMap extends Fixtures.FlatMap:
	var reject_queries: bool = false
	var live_reads: int = 0


	func terrain_is_walkable(cell: Vector2i) -> bool:
		if reject_queries:
			live_reads += 1
			return false
		return super.terrain_is_walkable(cell)


	func get_elevation(cell: Vector2i) -> int:
		if reject_queries:
			live_reads += 1
			return -1
		return super.get_elevation(cell)


	func independent_copy() -> WorldMapData:
		return Fixtures.FlatMap.new()


func run(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	var session: RegionalSimulation = adapter.world_sim
	var view: ReolWorld = fixture.world
	runner.assert_true(session.map_data == view.map_data(), "session owns the exact map borrowed by the visible world")
	var trap := QueryTrapMap.new()
	session.bind_map_data(trap)
	view.bind_map_data(trap)
	adapter._bind_navigation()
	runner.assert_true(adapter.travel_to("river"), "original travel starts before the independent map check")
	GameClock.advance_msec(50)
	runner.assert_true(not adapter.player_journey.is_empty(), "map candidate contains an actual fractional in-flight player route")
	var snapshot: Dictionary = WorldSessionSnapshot.capture(adapter)
	var stable: String = _canonical(adapter)
	trap.reject_queries = true
	view.set_obstacle_provider(func(_cell: Vector2i) -> bool: return true)
	var staged: Dictionary = WorldSessionSnapshot.stage(adapter, snapshot)
	runner.assert_true(not staged.is_empty(), "independent candidate accepts the original map while every live terrain and dynamic obstacle query rejects")
	runner.assert_eq(trap.live_reads, 0, "first position, actual journey, residents, beasts and grounded birds never query live map during staging")
	trap.reject_queries = false
	adapter._bind_navigation()
	if not staged.is_empty():
		var candidate: RegionalSimulation = staged.world
		var data: WorldMapData = staged.map
		runner.assert_true(data != trap and candidate.map_data == data, "candidate has its own map instead of a borrowed live map")
		runner.assert_true(candidate.construction._terrain.get_object() == data and candidate.construction._elevation.get_object() == data, "construction callbacks use candidate data before geometry validation")
		runner.assert_true(candidate.large_bodies._terrain.get_object() == data and candidate.large_bodies._elevation.get_object() == data, "large-body callbacks use the same independent candidate map")
		runner.assert_true(not candidate.construction._incoming.is_valid() and not candidate.large_bodies._incoming.is_valid(), "candidate geometry does not inherit live in-flight occupancy callbacks")
	runner.assert_eq(_canonical(adapter), stable, "successful staging leaves the entire active world unchanged")
	var bad: Dictionary = snapshot.duplicate(true)
	bad.world.generator_version = 2
	runner.assert_true(WorldSessionSnapshot.stage(adapter, bad).is_empty(), "unknown generation rejects before a session replacement")
	bad = snapshot.duplicate(true)
	bad.player.cell = [-1, -1]
	bad.player.position = [-32, -32]
	runner.assert_true(WorldSessionSnapshot.stage(adapter, bad).is_empty(), "saved position must still belong to independent terrain")
	runner.assert_true(adapter.world_sim == session and session.map_data == trap and view.map_data() == trap, "failed stages preserve active simulation and both authoritative/view map references")
	runner.assert_eq(_canonical(adapter), stable, "failed stages preserve body, inventory, clock, exploration and pending work")
	var path: String = "user://tests/world_map_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(adapter.save_game(path), OK, "normal session save preserves the existing descriptor-only format")
	runner.assert_eq(adapter.load_game(path), OK, "normal loader commits an independently validated map")
	runner.assert_true(adapter.world_sim.map_data != trap and view.map_data() == adapter.world_sim.map_data, "accepted load replaces the map and reconnects the original view")
	runner.assert_eq(_canonical(adapter), stable, "equivalent map replacement changes no serialized game fact")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	_fixtures._dispose(fixture)
	print("SCENARIO independent map: one session source, isolated first spatial check, no live terrain/dynamic callback reads and atomic replacement")


func _canonical(adapter: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(adapter)), "", true, true)
