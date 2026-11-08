extends RefCounted
## New rooms use the actual runtime, shared clock and joint save candidate.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const Workplaces = preload("res://scripts/sim/workplaces.gd")
const ARCHIVE: String = "res://tests/fixtures/session_v34.json"
const ARCHIVE_SHA: String = "07e4a64c2e8415afd912220b3c017bd269947c52c0a23d1536b0888d9f090c78"
var _fixtures: RefCounted = Fixtures.new()


func run(runner: Object) -> void:
	_new_room_runtime(runner)
	_original_archive(runner)
	print("SCENARIO workplace runtime: actual setup, staffed report/reward, doorway navigation, joint in-flight continuation, atomic failures and rejection of the genuine retired v34 archive")


func _fixture(runner: Object) -> Dictionary:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": false})
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "workplace runtime content loads")
		GameClock.restore_state(saved_clock)
		return {}
	var world: ReolWorld = Fixtures.FlatWorld.new()
	var player := PlayerCharacter.new()
	player.setup_state(PawnState.create(content.get_pawn(&"player"), content))
	player.spawn_at(Vector2i(30, 30))
	var pawns: Array[Pawn] = []
	var index: int = 0
	for id: StringName in content.pawns:
		if id == &"player":
			continue
		var pawn := Pawn.new()
		pawn.setup(content.get_pawn(id), content, world, Vector2i(31 + index, 30))
		pawns.append(pawn)
		index += 1
	var home := VillageRuntime.new()
	# The synthetic map has its own geometry despite using the legacy descriptor.
	# Rebuild that same geometry for a staged test snapshot, independently of
	# the live test world, as the shared continuity fixture does.
	home.restore_map_factory = func(_descriptor: Dictionary) -> WorldMapData: return Fixtures.FlatMap.new()
	var adapter := WorldContinuityRuntime.new()
	# This fixture exercises long workplace futures, not per-frame budgets.
	adapter.settlement_work_budget = 2147483647
	var result: Dictionary = {"clock": saved_clock, "world": world, "player": player,
		"pawns": pawns, "home": home, "continuity": adapter}
	if not home.setup(world, player, pawns, content, true) or not adapter.setup(home):
		runner.assert_true(false, "new physical workplaces initialize through both original runtime adapters")
		_fixtures._dispose(result)
		return {}
	return result


func _new_room_runtime(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	var home: VillageRuntime = fixture.home
	for region: String in adapter.world_sim.regions:
		var local: VillageSimulation = adapter.world_sim.regions[region]
		runner.assert_eq(local.config.get("workplaces_version", 0), 1, "both opening settlements opt into physical room policy")
		runner.assert_true(Workplaces.valid_places(local.places, local.config, adapter.world_sim.map_data), "saved room fits the runtime's actual terrain")
		var room: Dictionary = local.places.records.workspace
		runner.assert_true(not fixture.world.is_walkable(SimRouteTravel.cell(room.walls[0])), "view and player world reject the original room wall")
		runner.assert_true(not fixture.world.is_walkable(SimRouteTravel.cell(room.fixtures.archive.cell)), "actual cabinet tile blocks runtime movement")
		runner.assert_true(fixture.world.is_walkable(SimRouteTravel.cell(room.door)), "actual runtime doorway remains open")
		runner.assert_true(adapter.world_sim.clothing.region_roofed(region, SimRouteTravel.cell(room.clerk_cell)), "original clothing simulation recognizes the real office roof: " + region)
		runner.assert_true(not adapter.world_sim.clothing.region_roofed(region, adapter.centers[region]), "ordinary outdoor ground remains exposed: " + region)
	var beginning: Array = home.simulation.actors.chen_shouzhuo.position.duplicate()
	runner.assert_true(adapter.submit_service("work:deliver_wood").ok, "player starts original material work through the visible service adapter")
	GameClock.advance_msec(int(home.simulation.motion_rules.clock.fixed_step_ms))
	runner.assert_eq(home.simulation.actors.chen_shouzhuo.active.get("action", ""), "workspace_return", "unoccupied incumbent actually chooses to return to office")
	runner.assert_eq(home.simulation.actors.chen_shouzhuo.position, beginning, "office intention does not teleport its officer")
	_finish_player(adapter, runner)
	runner.assert_true(Workplaces.at_desk(home.simulation, "chen_shouzhuo"), "original officer completes real path into the office")
	runner.assert_true(not home.simulation.actors.player.receipts.is_empty(), "real player labour has evidence to bring to the desk")
	runner.assert_true(adapter.submit_service("work:report").ok, "original reporting intention walks player to the physical office")
	_finish_player(adapter, runner)
	var sim: VillageSimulation = home.simulation
	var institution: String = str(sim.config.institution.id)
	var credit: int = sim.institutions.balance(institution, "player")
	runner.assert_true(credit > 0 and sim.actors.player.receipts.is_empty(), "staffed native reporting records real completed work exactly once")
	var original_meals: int = sim.inventory.quantity("actor:player", "meal")
	runner.assert_true(adapter.submit_service("redeem").ok, "player requests real stocked reward from the same physical office")
	GameClock.advance_msec(1000)
	runner.assert_true(adapter.world_sim.services.owns_actor("player"), "joint save is taken during actual timed reward processing")
	var snapshot: Dictionary = WorldSessionSnapshot.capture(adapter)
	var before: String = _canonical(snapshot)
	var staged: Dictionary = WorldSessionSnapshot.stage(adapter, snapshot)
	runner.assert_true(not staged.is_empty(), "complete modern room session stages during original reward processing")
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(adapter)), before, "valid staging leaves active room, body, ledger and stock unchanged")
	var path: String = "user://tests/workplace_runtime_%d.json" % Time.get_ticks_usec()
	var bad_path: String = path + ".bad.json"
	runner.assert_eq(adapter.save_game(path), OK, "original saver stores rooms and pending processing in a single joint snapshot")
	var broken: Dictionary = snapshot.duplicate(true)
	broken.simulation.places.records.workspace.fixtures.register.institution = "private_notebook"
	broken.continuity.world.regions.home.places.records.workspace.fixtures.register.institution = "private_notebook"
	runner.assert_eq(SimSaveStore.save_file(bad_path, broken), OK, "invalid institutional reference is still an ordinary readable JSON file")
	runner.assert_true(adapter.load_game(bad_path) != OK, "ordinary loader rejects corrupted modern public record references")
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(adapter)), before, "failed load preserves pending real exchange and all live state")
	GameClock.advance_msec(12 * VillageSimulation.MINUTE_MS)
	var future: String = _canonical(WorldSessionSnapshot.capture(adapter))
	runner.assert_eq(home.simulation.institutions.balance(institution, "player"), credit - 1, "original service debits one contribution after staffed processing")
	runner.assert_eq(home.simulation.inventory.quantity("actor:player", "meal"), original_meals + 1, "one existing meal is delivered to the same persistent player")
	runner.assert_eq(adapter.load_game(path), OK, "ordinary joint loader resumes the in-flight room service")
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(adapter)), before, "load restores original processing instant and physical layout")
	GameClock.advance_msec(12 * VillageSimulation.MINUTE_MS)
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(adapter)), future, "loaded pending reward has the identical complete shared future")
	var start: Vector2i = fixture.player.cell
	runner.assert_true(adapter.travel_to("river"), "player can leave the office and travel to the other live settlement")
	GameClock.advance_msec(100)
	runner.assert_true(not adapter.player_journey.is_empty(), "the ordinary journey remains in flight for the next save")
	var travel_snapshot: Dictionary = WorldSessionSnapshot.capture(adapter)
	runner.assert_true(not WorldSessionSnapshot.stage(adapter, travel_snapshot).is_empty(), "actual doorway departure and remote office form a coherent in-flight candidate")
	_assert_fixed_room_route_rejection(adapter, travel_snapshot, runner)
	runner.assert_eq(adapter.save_game(path), OK, "same joint saver stores actual player travel away from the room")
	GameClock.advance_msec(15 * VillageSimulation.MINUTE_MS)
	var travel_future: String = _canonical(WorldSessionSnapshot.capture(adapter))
	runner.assert_true(fixture.player.cell != start and adapter.player_journey.is_empty(), "actual movement eventually arrives at the other settlement")
	runner.assert_eq(adapter.load_game(path), OK, "original loader restores the partial departure route")
	GameClock.advance_msec(15 * VillageSimulation.MINUTE_MS)
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(adapter)), travel_future, "near/far room and NPC continuation remains identical after loading travel")
	_remove_test_files(path)
	_remove_test_files(bad_path)
	_fixtures._dispose(fixture)


func _original_archive(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(ARCHIVE)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ARCHIVE))
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), ARCHIVE_SHA, "genuine v34 source retains its recorded digest")
	if bytes.is_empty() or not parsed is Dictionary:
		runner.assert_true(false, "the genuine v34 source is a readable archive")
		GameClock.restore_state(saved_clock)
		return
	var source: Dictionary = parsed
	var input: String = _canonical(source)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var adapter: WorldContinuityRuntime = main._continuity
	if adapter == null or adapter.world_sim == null:
		runner.assert_true(false, "ordinary workplace scene initializes before rejecting the archive")
		main.free()
		GameClock.restore_state(saved_clock)
		return
	# A visibility update must capture the committed projection immediately;
	# the deferred draw may happen after the next world boundary suspends.
	main._village._canvas_at_ms = -1
	adapter._canvas_at_ms = -1
	main.fog.visibility_updated.emit()
	runner.assert_true(main._village._canvas_at_ms == GameClock.elapsed_ms and adapter._canvas_at_ms == GameClock.elapsed_ms, "both room views synchronously capture actual visibility updates at the complete public clock")
	runner.assert_true(adapter.world_sim.regions.home.config.has("workplaces_version"), "ordinary new main scene enables current rooms")
	var live: RegionalSimulation = adapter.world_sim
	var terrain: WorldMapData = live.map_data
	var before: String = _canonical(WorldSessionSnapshot.capture(adapter))
	runner.assert_eq(SessionSaveSchema.rejection_reason(source.get("schema_version")), SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT, "v34 is identified as a retired environment archive")
	runner.assert_true(SessionSaveSchema.upgrade(source).is_empty() and WorldSessionSnapshot.stage(adapter, source).is_empty(), "v34 cannot be staged into the current workplace world")
	runner.assert_eq(adapter.load_game(ProjectSettings.globalize_path(ARCHIVE)), ERR_INVALID_DATA, "ordinary loader explicitly rejects the genuine old v34 archive")
	runner.assert_true(adapter.world_sim == live and live.map_data == terrain, "rejection retains the current live world and map owners")
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(adapter)), before, "rejection preserves the complete current room, player and clock state")
	runner.assert_eq(_canonical(source), input, "validation does not rewrite the supplied archive")
	runner.assert_eq(FileAccess.get_file_as_bytes(ARCHIVE), bytes, "rejection preserves the genuine archive bytes")
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), ARCHIVE_SHA, "rejection preserves the recorded digest")
	main.free()
	GameClock.restore_state(saved_clock)


func _assert_fixed_room_route_rejection(adapter: WorldContinuityRuntime, snapshot: Dictionary, runner: Object) -> void:
	var original: Array = snapshot.continuity.player_journey.path
	if original.size() < 2:
		runner.assert_true(false, "fixed-room route corruption scenario has at least two genuine future steps")
		return
	var stable: String = _canonical(WorldSessionSnapshot.capture(adapter))
	# Retain the entire current segment and original destination. A harmless
	# backtrack proves that an added future loop is otherwise a valid session.
	var control: Dictionary = snapshot.duplicate(true)
	var safe_path: Array = [original[0].duplicate(), original[1].duplicate(), original[0].duplicate()]
	safe_path.append_array(original.slice(1))
	control.continuity.player_journey.path = safe_path
	runner.assert_true(not WorldSessionSnapshot.stage(adapter, control).is_empty(), "a terrain-valid future backtrack stages when it avoids fixed walls and furniture")
	var room: Dictionary = snapshot.continuity.world.regions.home.places.records.workspace
	var targets: Dictionary = {"wall": room.walls[0], "cabinet": room.fixtures.archive.cell}
	for kind: String in targets:
		var broken: Dictionary = snapshot.duplicate(true)
		var excursion: Array = _grid_route(SimRouteTravel.cell(original[0]), SimRouteTravel.cell(targets[kind]))
		var altered: Array = [original[0].duplicate()]
		altered.append_array(excursion.slice(1))
		excursion.reverse()
		altered.append_array(excursion.slice(1))
		altered.append_array(original.slice(1))
		broken.continuity.player_journey.path = altered
		runner.assert_true(SessionSaveSchema.is_valid_world(broken), "fixed-room detour preserves all ordinary world/session envelope fields: " + kind)
		runner.assert_true(WorldSessionSnapshot._valid_journey(broken.assembly.centers, broken.continuity.player_journey, SimRouteTravel.cell(broken.player.cell), int(broken.clock.elapsed_ms), adapter.world_sim.map_data), "detour still passes original static terrain and endpoint route validation: " + kind)
		runner.assert_true(SimRouteTravel.valid_segment(broken.continuity.player_journey, broken.continuity.world.regions.home.actors.player, int(broken.clock.elapsed_ms), float(adapter.home_runtime()._player.motion.rules.motion.speed)), "detour leaves the exact in-flight body segment valid: " + kind)
		runner.assert_true(WorldSessionSnapshot.stage(adapter, broken).is_empty(), "candidate rejects the future route specifically crossing a fixed room obstacle: " + kind)
		runner.assert_eq(_canonical(WorldSessionSnapshot.capture(adapter)), stable, "fixed-room future-route rejection does not alter the live journey or world: " + kind)


func _grid_route(from: Vector2i, to: Vector2i) -> Array:
	var result: Array = [[from.x, from.y]]
	var cursor: Vector2i = from
	while cursor.x != to.x:
		cursor.x += 1 if cursor.x < to.x else -1
		result.append([cursor.x, cursor.y])
	while cursor.y != to.y:
		cursor.y += 1 if cursor.y < to.y else -1
		result.append([cursor.x, cursor.y])
	return result


func _finish_player(adapter: WorldContinuityRuntime, runner: Object) -> void:
	var stop: int = GameClock.elapsed_ms + 40 * VillageSimulation.MINUTE_MS
	while (not adapter.world_sim.regions.home.actors.player.active.is_empty() or adapter.world_sim.services.owns_actor("player")) and GameClock.elapsed_ms < stop:
		GameClock.advance_msec(VillageSimulation.MINUTE_MS)
	runner.assert_true(adapter.world_sim.regions.home.actors.player.active.is_empty() and not adapter.world_sim.services.owns_actor("player"), "original player intention completes using common world time")


func _remove_test_files(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _canonical(value: Variant) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(value), "", true, true)
