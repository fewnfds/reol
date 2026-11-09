extends RefCounted
## Real-session transaction/restart tests plus explicitly synthetic spatial
## reservations to exercise every current domain without scripted encounters.


func run(runner: Object) -> void:
	var previous: Dictionary = GameClock.to_dict()
	_test_real_session(runner)
	_test_spatial_reservations(runner)
	_test_artifact_contact(runner)
	GameClock.restore_state(previous)
	print("SCENARIO developer terrain: bounded atomic editing, complete routes/corners/footprints, paused synchronization and immediate in-flight save/reload continuity")


func _main(runner: Object) -> Node:
	GameClock.restore_state({"tick_index": 0, "total_minutes": GameClock.start_minutes, "speed": 1.0, "paused": true, "elapsed_ms": 0, "frame_debt_ms": 0.0, "wait_target_ms": 0})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	runner.assert_true(main._continuity != null and main._continuity.world_sim != null, "real flat world assembles before editing")
	return main


func _digest(runtime: WorldContinuityRuntime) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime))).sha256_text()


func _test_real_session(runner: Object) -> void:
	var main: Node = _main(runner)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		main.free()
		return
	runner.assert_true(main._terrain_editor == null, "ordinary launch has no developer editing tool")
	runner.assert_true(runtime.select_starting_avatar("subject:player"), "normal human start is selected")
	var editor := TerrainEditorRuntime.new()
	main.add_child(editor)
	editor.setup(runtime)
	var cell := Vector2i(50, 50)
	var original: int = runtime.world_sim.map_data.get_terrain(cell)
	var replacement: int = (original + 1) % 3
	var rows: Array = [[cell.x, cell.y, replacement]]
	runner.assert_true(not editor.apply_patch(rows).ok, "unprepared tool cannot mutate a running world")
	GameClock.advance_msec(1517)
	# A real fractional frame contribution below the next fixed step must remain
	# owed when developer editing suspends normal time.
	GameClock.set_paused(false)
	GameClock.advance_frame(0.001)
	var old_time: int = GameClock.elapsed_ms
	var debt: float = GameClock._accumulator
	var previous_target: int = runtime.world_sim.target_ms
	runtime.world_sim.target_ms += 500
	runner.assert_eq(editor.prepare().code, "pending_time", "preparation does not erase a world's outstanding target")
	runner.assert_eq(runtime.world_sim.target_ms, previous_target + 500, "a refused preparation retains the original backlog")
	runtime.world_sim.target_ms = previous_target
	var original_action: Dictionary = main.player.motion.action
	main.player.motion.action = {"fixture": "uncovered local segment"}
	runner.assert_eq(editor.prepare().code, "local_motion", "uncovered local sidestep is explicitly refused before editing")
	main.player.motion.action = original_action
	runner.assert_true(editor.prepare().ok, "preparation synchronizes the original world at its current fractional boundary")
	runner.assert_eq(GameClock.elapsed_ms, old_time, "preparation does not advance common time")
	runner.assert_eq(GameClock._accumulator, debt, "preparation retains frame debt")
	for sim: VillageSimulation in runtime.world_sim.regions.values():
		runner.assert_eq(sim.elapsed_ms, old_time, "each lazy region is synchronized before strokes")
	var before: String = _digest(runtime)
	var player: Vector2i = main.player.cell
	var blocked: Dictionary = editor.apply_patch([rows[0], [player.x, player.y, WorldMapData.TERRAIN_WATER]])
	runner.assert_true(not blocked.ok, "one occupied cell rejects an entire mixed brush")
	runner.assert_eq(_digest(runtime), before, "rejection preserves the complete original world including time, bodies, inventories and knowledge")
	var malformed: Array = [[50, 50, replacement], [51.5, 50, WorldMapData.TERRAIN_ROCK]]
	runner.assert_true(not editor.apply_patch(malformed).ok, "fractional brush coordinates reject before any mutation")
	runner.assert_eq(_digest(runtime), before, "malformed mixed brush also preserves the complete session")
	var too_many: Array = []
	for x: int in range(SimTerrainEdits.MAX_CELLS + 1):
		too_many.append([x, 30, WorldMapData.TERRAIN_GRASS])
	runner.assert_eq(editor.apply_patch(too_many).code, "brush_limit", "live command enforces a bounded complete transaction")
	runner.assert_eq(_digest(runtime), before, "budget rejection changes nothing")
	editor.close()
	runner.assert_true(runtime.travel_to("river"), "a real journey starts on the original body")
	runner.assert_true(editor.prepare().ok, "editing preparation preserves an already scheduled journey")
	var journey_before: Dictionary = runtime.player_journey.duplicate(true)
	runner.assert_true(journey_before.get("path", []).size() > 3, "real journey has more than its immediate step")
	if journey_before.get("path", []).size() > 3:
		var future: Array = journey_before.path[3]
		before = _digest(runtime)
		runner.assert_true(not editor.apply_patch([[future[0], future[1], WorldMapData.TERRAIN_ROCK]]).ok, "future journey step is protected beyond path[0]")
		runner.assert_eq(_digest(runtime), before, "future-step rejection does not cancel or reprice the original journey")
	var changed: Dictionary = editor.apply_patch(rows)
	runner.assert_true(changed.ok and changed.changed_cells.has(cell), "safe remote terrain commits atomically to the actual map")
	runner.assert_eq(runtime.world_sim.map_data.get_terrain(cell), replacement, "runtime queries immediately see the accepted terrain")
	runner.assert_eq(runtime.player_journey, journey_before, "a distant safe edit preserves the same in-flight action")
	runner.assert_eq(GameClock.elapsed_ms, old_time, "successful brush spends no simulation time")
	var path: String = "user://tests/terrain_edits_%d.json" % Time.get_ticks_usec()
	var saved: String = _digest(runtime)
	runner.assert_eq(runtime.save_game(path), OK, "edited in-flight session saves immediately through the ordinary saver")
	runner.assert_eq(runtime.load_game(path), OK, "independent ordinary candidate accepts the edited in-flight session")
	runner.assert_eq(_digest(runtime), saved, "ordinary loading preserves the complete edited world")
	runner.assert_true(not editor.apply_patch(rows).ok, "a previously prepared tool cannot write into a replaced session")
	runner.assert_true(editor.prepare().ok, "explicit preparation binds to the accepted replacement session")
	editor.close()
	GameClock.advance_msec(754)
	var whole: String = _digest(runtime)
	runner.assert_eq(runtime.load_game(path), OK, "same original edited session can be restored for the segmented comparison")
	GameClock.advance_msec(200)
	GameClock.advance_msec(554)
	runner.assert_eq(_digest(runtime), whole, "edited in-flight world has the same whole and segmented future after loading")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))
	main.free()


func _test_spatial_reservations(runner: Object) -> void:
	var main: Node = _main(runner)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		main.free()
		return
	var world: RegionalSimulation = runtime.world_sim
	var map: WorldMapData = world.map_data
	var rows: Array = []
	for y: int in range(76, 90):
		for x: int in range(76, 90):
			rows.append([x, y, WorldMapData.TERRAIN_GRASS])
	runner.assert_true(map.apply_terrain_patch(rows).ok, "synthetic guard fixture uses a known clear small patch")
	runner.assert_true(world.synchronize_regions(), "guard fixture is at one common boundary")
	var sim: VillageSimulation = world.regions.home
	sim.set_actor_cell("player", Vector2i(80, 80))
	var path: Array = [[81, 80], [82, 80], [83, 80], [84, 80]]
	var block: Array = [[84, 80, WorldMapData.TERRAIN_ROCK]]
	# Synthetic active records test the guard only, not their domain schemas.
	for domain: RefCounted in [world.construction, world.resting, world.personal_production, world.capability_practice]:
		var original: Dictionary = domain.active
		domain.active = {"player": {"path": path}}
		runner.assert_eq(SimTerrainEdits.inspect(world, block).code, "reserved_route", "each original active domain protects all remaining path steps")
		domain.active = original
	var old_action: Dictionary = sim.actors.player.active
	sim.actors.player.active = {"path": path}
	runner.assert_eq(SimTerrainEdits.inspect(world, block).code, "reserved_route", "native body action protects the complete remaining route")
	sim.actors.player.active = {"path": [[81, 81]]}
	runner.assert_true(SimTerrainEdits.inspect(world, [[81, 80, WorldMapData.TERRAIN_WATER]]).ok, "one diagonal bypass remains usable")
	runner.assert_eq(SimTerrainEdits.inspect(world, [[81, 80, WorldMapData.TERRAIN_WATER], [80, 81, WorldMapData.TERRAIN_ROCK]]).code, "reserved_route", "a whole brush cannot close both diagonal bypasses while leaving endpoints unchanged")
	sim.actors.player.active = old_action
	world.soul_vessels.agency.errands["player"] = {"path": path}
	runner.assert_eq(SimTerrainEdits.inspect(world, block).code, "reserved_route", "soul-requested errands use their original complete route")
	world.soul_vessels.agency.errands.erase("player")
	world.services.active_jobs["player"] = "synthetic_guard"
	world.services.jobs.synthetic_guard = {"path": path}
	runner.assert_eq(SimTerrainEdits.inspect(world, block).code, "reserved_route", "service active index resolves the complete route without scanning historical jobs")
	world.services.active_jobs.erase("player")
	world.services.jobs.erase("synthetic_guard")
	var fixed: Vector2i = SimRouteTravel.cell(sim.places.store.cell)
	runner.assert_eq(SimTerrainEdits.inspect(world, [[fixed.x, fixed.y, WorldMapData.TERRAIN_WATER]]).code, "fixed_space", "fixed service/source anchor cannot be submerged")
	var contact_start: Vector2 = TileGrid.cell_to_world(Vector2i(80, 80))
	var contact_end: Vector2 = TileGrid.cell_to_world(Vector2i(84, 80))
	world.artifacts.active.player = {"verb": "draw", "draw": {"caster_position": [contact_start.x, contact_start.y], "from_cell": [84, 80]}}
	runner.assert_eq(SimTerrainEdits.inspect(world, [[82, 80, WorldMapData.TERRAIN_ROCK]]).code, "active_contact", "remote draw's intermediate contact is protected without scanning events")
	world.artifacts.active.erase("player")
	world.private_exchange.jobs.synthetic_guard = {"buyer_position": [contact_start.x, contact_start.y], "seller_position": [contact_end.x, contact_end.y]}
	world.private_exchange.active_jobs["synthetic_guard"] = true
	runner.assert_eq(SimTerrainEdits.inspect(world, [[82, 80, WorldMapData.TERRAIN_ROCK]]).code, "active_contact", "current private contact uses the derived active index")
	world.private_exchange.active_jobs.erase("synthetic_guard")
	world.private_exchange.jobs.erase("synthetic_guard")
	sim.set_actor_cell("player", Vector2i(100, 100))
	runner.assert_true(world.large_bodies.add_body("guard_beast", "占地样本", "home", Vector2i(80, 80), Vector2i(86, 80)), "a real unique large body is generated on the original authority")
	if world.large_bodies.bodies.has("guard_beast"):
		runner.assert_eq(SimTerrainEdits.inspect(world, [[81, 81, WorldMapData.TERRAIN_WATER]]).code, "occupied", "off-center part of the real footprint is protected")
		world.large_bodies.bodies.guard_beast.path = [[81, 80], [82, 80], [83, 80]]
		runner.assert_eq(SimTerrainEdits.inspect(world, [[84, 81, WorldMapData.TERRAIN_ROCK]]).code, "reserved_route", "full footprint of a future large-body step is protected")
	main.free()


func _test_artifact_contact(runner: Object) -> void:
	var main: Node = _main(runner)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		main.free()
		return
	# This contact case compares completed minute-long take/place actions.
	# Other terrain cases retain their normal budget and pending-state probes.
	runtime.settlement_work_budget = 2147483647
	runner.assert_true(runtime.select_starting_avatar("subject:player"), "artifact-contact probe selects the original human")
	var world: RegionalSimulation = runtime.world_sim
	var ring: String = "stele_drawing_ring"
	var source: Vector2i = world.artifacts.object_cell(ring)
	var middle: Vector2i = source + Vector2i.RIGHT
	var standing: Vector2i = source + Vector2i.RIGHT * 2
	# Controlled setup preserves the real item/field slot/body and original
	# begin/complete rules, rather than inventing an active artifact record.
	runner.assert_true(world.map_data.apply_terrain_patch([[middle.x, middle.y, WorldMapData.TERRAIN_GRASS], [standing.x, standing.y, WorldMapData.TERRAIN_GRASS]]).ok, "real fixed ring has a clear two-cell contact in the fixture")
	world.regions.home.set_actor_cell("player", standing)
	main.player.spawn_at(standing)
	var editor := TerrainEditorRuntime.new()
	main.add_child(editor)
	editor.setup(runtime)
	for verb: String in ["take", "place"]:
		var begun: Dictionary = world.artifacts.begin("player", verb, ring)
		runner.assert_true(begun.ok, "original " + verb + " action starts with clear contact")
		if not begun.ok:
			break
		runner.assert_true(editor.prepare().ok, "developer preparation retains the genuine " + verb + " action")
		var before: String = _digest(runtime)
		var safe_replacement: int = (world.map_data.get_terrain(Vector2i(50, 50)) + 1) % 3
		var result: Dictionary = editor.apply_patch([[50, 50, safe_replacement], [middle.x, middle.y, WorldMapData.TERRAIN_ROCK]])
		runner.assert_eq(result.code, "active_contact", "ordinary " + verb + " contact rejects an intervening rock before commit")
		runner.assert_eq(_digest(runtime), before, "rejected " + verb + " obstruction changes no world state or safe cell")
		var original_job: Dictionary = world.artifacts.active.player.duplicate(true)
		editor.close()
		GameClock.advance_msec(int(original_job.due_ms) - GameClock.elapsed_ms)
		var expected: String = "actor:player" if verb == "take" else "site:broken_stele"
		runner.assert_eq(world.artifacts.objects[ring].container, expected, "original " + verb + " then completes with the original object")
		if verb == "take":
			# Returning the held ring must reserve the destination contact, not
			# only the holder's now-coincident body/object positions.
			runner.assert_eq(world.artifacts.object_cell(ring), standing, "held original ring follows the one real body")
	main.free()
