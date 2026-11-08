extends RefCounted


func run(runner: Object) -> void:
	_test_third_life_and_finite_perspective(runner)
	_test_actual_carry_archive_and_identity(runner)


func _new_scene(runner: Object) -> Node:
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	# This fixture tests domain and save futures, not per-frame work limits.
	if main._continuity != null:
		main._continuity.settlement_work_budget = 2147483647
	return main


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _test_third_life_and_finite_perspective(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var main: Node = _new_scene(runner)
	var runtime: WorldContinuityRuntime = main._continuity
	runner.assert_true(main._avatar.choose("subject:soul:yan_heng"), "new opening can bind the original independent soul exactly once")
	GameClock.set_paused(true)
	runner.assert_true(runtime.soul_player_active() and not runtime.bird_player_active() and not runtime.human_player_active(), "nonhuman life no longer implicitly means a bird")
	runner.assert_true(not main._avatar.choose("subject:player") and not main._avatar.choose("subject:avian:moss_sparrow"), "soul opening cannot freely reroll to a different living person")
	runner.assert_true(runtime.world_sim.regions.home.actors.player.autonomous and not main.player.avatar_active, "former human keeps an independent autonomous body")
	runner.assert_true(main._avatar.soul._sense.visible and not main.hud._pawn_panel.visible and not runtime._panel.visible and not runtime.service_adapter.panel.visible, "soul's own screen hides human status and institutional information")
	runner.assert_true(not main._avatar._bird_actions.visible and not main._avatar._bird_status.visible, "soul life does not show bird appetite or action controls")
	runner.assert_true(not runtime.start_home_work("forage_grain").ok and not runtime.travel_to("river") and not main.player.request_sidestep(Vector2.RIGHT), "soul cannot order the former body's work, route or sidestep")
	var agency: SimSoulAgency = runtime.world_sim.soul_vessels.agency
	var ring: String = str(runtime.world_sim.soul_vessels.residents.yan_heng.vessel)
	var point: Vector2 = agency.point("yan_heng")
	main.player._intent = Vector2.RIGHT
	GameClock.advance_msec(1000)
	runner.assert_eq(agency.point("yan_heng"), point, "held human movement intent never creates legs for the ring")
	runner.assert_eq(runtime.controlled_cell(), runtime.world_sim.soul_vessels.vessel_cell(ring), "camera and world loading follow the original carrier")
	runner.assert_true(not agency.perceive("yan_heng").has("stock") and not agency.perceive("yan_heng").has("qi"), "spiritual projection does not import a human inventory or power panel")
	for signal_row: Dictionary in agency.perceive("yan_heng").signals:
		runner.assert_eq(signal_row.label, "一道呼吸的气息", "visible human names remain unknown before an actual introduction")
	runner.assert_true(main._avatar.soul.submit("observe").ok, "soul action panel begins its own real perception action")
	GameClock.advance_msec(10000)
	runner.assert_true(agency.events.back().kind == "observed", "personal observation completes on the common world clock")
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, snapshot).is_empty(), "selected soul and original world compose a valid joint save")
	var damaged: Dictionary = snapshot.duplicate(true)
	damaged.avatar_subject = "subject:player"
	runner.assert_true(WorldSessionSnapshot.stage(runtime, damaged).is_empty(), "a save cannot grant human control while retaining a manual independent soul")
	var before: String = _canonical(runtime)
	damaged = snapshot.duplicate(true)
	damaged.continuity.world.soul_vessels.agency.manual = ""
	runner.assert_true(WorldSessionSnapshot.stage(runtime, damaged).is_empty(), "modern missing manual intention cannot silently reassign the player")
	runner.assert_eq(_canonical(runtime), before, "bad life bindings cannot partially change the live world")
	main.free()
	GameClock.restore_state(prior)


func _test_actual_carry_archive_and_identity(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var main: Node = _new_scene(runner)
	var path: String = _unused_path()
	if path.is_empty():
		runner.assert_true(false, "soul carry has an unused temporary save path")
	else:
		_current_carry_and_identity(runner, main, path)
	_remove(path)
	main.free()
	GameClock.restore_state(prior)
	# Current carry, consent and whole-world sparse/fine restoration also have
	# independent regional coverage in tests/sim/test_soul_agency.gd.
	load("res://tests/runtime/helpers/legacy_rejection_archive.gd").run(runner, {
		"res://tests/fixtures/session_v12.json": "",
		"res://tests/fixtures/session_v13.json": "",
	})
	print("SCENARIO soul player: finite senses, actual cooperation, original carry and current joint restart")


func _current_carry_and_identity(runner: Object, main: Node, path: String) -> void:
	var runtime: WorldContinuityRuntime = main._continuity
	var chosen: bool = main._avatar.choose("subject:soul:yan_heng")
	runner.assert_true(chosen, "current opening chooses the original independent soul")
	if not chosen:
		return
	GameClock.set_paused(true)
	var world: RegionalSimulation = runtime.world_sim
	var agency: SimSoulAgency = world.soul_vessels.agency
	# Controlled initial placement keeps the real former human within hearing;
	# the request, consent, actual pickup, carrying and cost remain real actions.
	var ring_cell: Vector2i = world.soul_vessels.vessel_cell("old_ring")
	world.regions.home.cancel_action("player", "fixture_setup")
	world.regions.home.actors.player.retry_ms = GameClock.elapsed_ms + 10000
	main.player.spawn_at(ring_cell)
	runtime._home._sync_player_cell()
	world.invalidate_region("home")
	main._avatar.soul._selected = "player"
	main._avatar.soul.project()
	var response: Dictionary = main._avatar.soul.submit("call")
	runner.assert_true(bool(response.get("ok", false)), "the soul sends an actual request to the nearby former human")
	if not bool(response.get("ok", false)):
		return
	GameClock.advance_msec(int(world.soul_vessels.definitions.agency.actions["call"].ms))
	var accepted: bool = agency.errands.has("player")
	runner.assert_true(accepted, "the original human independently accepts the request")
	if not accepted:
		return
	var deadline: int = GameClock.elapsed_ms + 120000
	while agency.errands.has("player") and not bool(agency.errands.player.picked) and GameClock.elapsed_ms < deadline:
		var next: int = agency.next_boundary_ms()
		if next <= GameClock.elapsed_ms:
			break
		GameClock.advance_msec(next - GameClock.elapsed_ms)
	var carrying: bool = agency.errands.has("player") and bool(agency.errands.player.picked)
	runner.assert_true(carrying, "the same original human physically picks up the unique ring before the checkpoint")
	if not carrying:
		return
	runner.assert_eq(world.soul_vessels.vessels.old_ring.container, "actor:player", "the real original ring is in the real helper's custody")
	runner.assert_true(not world.regions.home.actors.player.autonomous, "accepted carry temporarily occupies the original autonomous body")
	var saved: Dictionary = WorldSessionSnapshot.capture(runtime)
	var before: String = _canonical(runtime)
	var corrupt: Dictionary = saved.duplicate(true)
	corrupt.continuity.world.soul_vessels.agency.social.requests = {}
	runner.assert_true(WorldSessionSnapshot.stage(runtime, corrupt).is_empty(), "joint carry without the actual helper's consent is rejected")
	runner.assert_eq(_canonical(runtime), before, "bad carry candidate leaves the real process untouched")
	var error: Error = runtime.save_game(path)
	runner.assert_eq(error, OK, "ordinary saver records the current in-flight soul carry")
	if error != OK:
		return
	main.player._intent = Vector2.RIGHT
	GameClock.advance_msec(100000)
	var future: String = _canonical(runtime)
	runner.assert_true(runtime.world_sim.soul_vessels.agency.errands.is_empty() and runtime.world_sim.regions.home.actors.player.autonomous, "actual carry completes and the helper returns to independent life")
	var loaded: Error = runtime.load_game(path)
	runner.assert_eq(loaded, OK, "ordinary loader restores the same current in-progress carry")
	if loaded != OK:
		return
	runner.assert_eq(runtime.avatar_subject, "subject:soul:yan_heng", "load restores the same independent soul identity")
	runner.assert_true(not main._avatar.opening.visible and main._avatar.soul._sense.visible, "load restores the soul's limited screen")
	runner.assert_eq(main._avatar.global_position, runtime.world_sim.soul_vessels.agency.point("yan_heng"), "camera follows the actual carried vessel")
	main.player._intent = Vector2.ZERO
	GameClock.advance_msec(100000)
	runner.assert_eq(_canonical(runtime), future, "restored carry and inputless continuation yield the same complete world")


func _unused_path() -> String:
	for attempt: int in 100:
		var path: String = "user://tests/soul_carry_%d_%d.json" % [Time.get_ticks_usec(), attempt]
		var occupied: bool = false
		for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
			if FileAccess.file_exists(path + suffix):
				occupied = true
				break
		if not occupied:
			return path
	return ""


func _remove(path: String) -> void:
	if path.is_empty():
		return
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
