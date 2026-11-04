extends RefCounted
## The ordinary request page, body controller and joint file boundary agree.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
var fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_actual_body_care(runner)
	_legacy_sources(runner)
	_real_legacy(runner)
	_real_archive(runner)
	print("SCENARIO health runtime: private body sense, continuous-position care, both-body exclusion and cancellation, same joint-file future, explicit old-source migration")


func _fixture(runner: Object) -> Dictionary:
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return {}
	var runtime: WorldContinuityRuntime = fixture.continuity
	for region: String in runtime.world_sim.regions:
		var sim: VillageSimulation = runtime.world_sim.regions[region]
		for actor: String in sim.actors:
			sim.cancel_action(actor, "health_fixture_setup")
			sim.actors[actor].autonomous = false
		runtime.world_sim.invalidate_region(region)
	var cell: Vector2i = runtime.world_sim.artifacts.object_cell("hearth_stone")
	fixture.player.spawn_at(cell)
	runtime.prepare_player_command()
	return fixture


func _injure(runner: Object, runtime: WorldContinuityRuntime) -> void:
	var answer: Dictionary = runtime.world_sim.artifacts.begin("player", "heat", "hearth_stone")
	runner.assert_true(answer.ok, "normal runtime performs the actual risky untrained action")
	if answer.ok:
		GameClock.advance_msec(int(runtime.world_sim.artifacts.active.player.due_ms) - GameClock.elapsed_ms)
	runner.assert_true(not runtime.world_sim.health.current_source("player").is_empty(), "shared scene clock commits the original backlash and its continuing bodily effect")


func _prepare_doctor(runtime: WorldContinuityRuntime) -> void:
	var sim: VillageSimulation = runtime.world_sim.regions.home
	sim.set_actor_cell("su_zhi", SimRouteTravel.cell(sim.actors.player.cell))
	sim.actors.su_zhi.autonomous = true
	sim.actors.su_zhi.retry_ms = GameClock.elapsed_ms + 6000000
	sim.actors.su_zhi.energy = 85.0
	runtime.world_sim.invalidate_region("home")


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)


func _actual_body_care(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var panel: InteractionRequestsRuntime = runtime.interaction_adapter
	var player: PlayerCharacter = fixture.player
	panel.show_panel()
	runner.assert_true(panel._body_sense.text.contains("没有持续"), "C displays the original person's qualitative body sense")
	_injure(runner, runtime)
	panel.refresh_progress()
	runner.assert_true(panel._body_sense.text.contains("灼涩"), "body sense updates after an actual completed risk, without opening a second status authority")
	_prepare_doctor(runtime)
	player.motion.relocate(TileGrid.cell_to_world(player.cell) + Vector2(3.5, 0.0))
	runtime.prepare_player_command()
	var point: Vector2 = player.motion.position
	var reply: Dictionary = panel.submit("subject:su_zhi", "diagnose", {"kind": "body", "id": "player"})
	runner.assert_eq(reply.status, "started", "structured C request starts actual consensual examination")
	if reply.status != "started":
		fixtures._dispose(fixture)
		return
	runner.assert_true(player.motion.position.is_equal_approx(point), "requesting care preserves the exact continuous position between cell centers")
	runner.assert_true(not player.has_motion_control(), "medical body ownership reaches the ordinary manual movement guard")
	runner.assert_true(not player.request_sidestep(Vector2.RIGHT), "flash movement cannot bypass care ownership")
	runner.assert_true(not runtime.travel_to("river"), "a second journey cannot own the examining body")
	runner.assert_true(not runtime.world_sim.services.begin("player", "home", "eat").ok, "the service adapter cannot concurrently use the patient")
	player._intent = Vector2.RIGHT
	GameClock.advance_msec(1000)
	player._intent = Vector2.ZERO
	runner.assert_true(player.motion.position.is_equal_approx(point), "held movement input spends world time without moving the occupied body")
	runner.assert_true(not panel._progress.text.contains("查到"), "unfinished examination does not reveal its later diagnosis")
	runtime.stop_player_action()
	runner.assert_true(not runtime.world_sim.health.owns_actor("player") and not runtime.world_sim.health.owns_actor("su_zhi"), "normal stop cancels care and releases both original participants")
	runner.assert_true(runtime.world_sim.regions.home.actors.su_zhi.autonomous and not runtime.world_sim.regions.home.actors.player.autonomous, "stop restores each participant's original autonomy")
	runner.assert_true(player.has_motion_control() and player.motion.position.is_equal_approx(point), "stopping returns control at the same physical point")
	reply = panel.submit("subject:su_zhi", "diagnose", {"kind": "body", "id": "player"})
	runner.assert_eq(reply.status, "started", "a new real examination may be requested after cancellation")
	if reply.status != "started":
		fixtures._dispose(fixture)
		return
	GameClock.advance_msec(int(runtime.world_sim.health.jobs[reply.process.id].due_ms) - GameClock.elapsed_ms)
	runner.assert_true(panel._progress.text.contains("查到"), "the actual completed examination supplies its private conclusion")
	runtime.world_sim.regions.home.inventory.containers["actor:player"]["herb"] = 1
	reply = panel.submit("subject:su_zhi", "treat", {"kind": "body", "id": "player"})
	runner.assert_eq(reply.status, "started", "the same request page starts real treatment after diagnosis and patient supply")
	if reply.status != "started":
		fixtures._dispose(fixture)
		return
	runner.assert_true(player.motion.position.is_equal_approx(point), "actual treatment also preserves the continuous patient position")
	GameClock.advance_msec(31000)
	var path: String = "user://tests/health_runtime_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "normal joint file save captures both bodies and already invested medicine mid-treatment")
	var stored: Dictionary = SimSaveStore.load_file(path).data
	var horizon: int = 3600000
	GameClock.advance_msec(horizon)
	var future: String = _canonical(runtime)
	runner.assert_eq(runtime.load_game(path), OK, "normal candidate loader resumes the real in-progress treatment")
	runner.assert_true(runtime.world_sim.health.owns_actor("player") and not panel.panel.visible, "load preserves medical ownership but clears stale future UI")
	panel.show_panel()
	runner.assert_eq(panel._receipt, reply.process, "reopening C reconstructs the same original care process")
	runner.assert_true(panel._body_sense.text.contains("灼涩") and not panel._progress.text.contains("已完成"), "load presents current body sense without leaking a future cure")
	GameClock.advance_msec(horizon)
	runner.assert_eq(_canonical(runtime), future, "ordinary joint-file continuation reaches exactly the same complete future")
	runner.assert_eq(runtime.world_sim.regions.home.inventory.quantity("actor:player", "herb"), 0, "file continuation cannot refund or duplicate the invested herb")
	var stable: String = _canonical(runtime)
	stored.continuity.world.erase("health")
	var bad_path: String = path + "_invalid.json"
	runner.assert_eq(SimSaveStore.save_file(bad_path, stored), OK, "bad modern fixture is still ordinary valid JSON")
	runner.assert_eq(runtime.load_game(bad_path), ERR_INVALID_DATA, "modern session with a missing health authority is refused")
	runner.assert_eq(_canonical(runtime), stable, "failed modern load preserves every live body, time, medicine and consequence")
	_clean(path)
	_clean(bad_path)
	fixtures._dispose(fixture)


func _legacy_sources(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	_injure(runner, runtime)
	# Build an explicit pre-health format from real effects. This is a temporary
	# migration counterexample, never a replacement of a genuine archive.
	var legacy: Dictionary = WorldSessionSnapshot.capture(runtime)
	legacy.schema_version = 28
	legacy.continuity.world.version = 25
	legacy.continuity.world.erase("health")
	# This temporary pre-health format also predates the later environment
	# authority; retaining a modern field is correctly refused by migration.
	legacy.continuity.world.erase("environment")
	legacy.continuity.world.erase("local_heat")
	legacy.continuity.world.erase("spirit_sources")
	legacy.continuity.world.erase("site_affairs")
	legacy.continuity.world.erase("source_care")
	runner.assert_eq(SnapshotValues.normalized(legacy.continuity.world.capability_practice), SnapshotValues.normalized(SimCapabilityPractice.empty_state()), "temporary pre-health projection contains no actual later practice to erase")
	legacy.continuity.world.erase("capability_practice")
	runner.assert_eq(SnapshotValues.normalized(legacy.continuity.world.field_opportunities), SnapshotValues.normalized(SimFieldOpportunities.empty_state()), "temporary pre-health projection has no later field activity to erase")
	legacy.continuity.world.erase("field_opportunities")
	var exchange_state: Variant = SnapshotValues.normalized(legacy.continuity.world.private_exchange)
	var empty_exchange: Variant = SnapshotValues.normalized(SimPrivateExchange.empty_state())
	runner.assert_eq(exchange_state, empty_exchange, "temporary pre-health projection has no exchange, consent, or receipt to erase")
	if exchange_state != empty_exchange:
		fixtures._dispose(fixture)
		return
	legacy.continuity.world.erase("private_exchange")
	# Project the current artifact envelope only when the original history is
	# actually v4-compatible; do not discard research, draw or exchange evidence.
	var old_artifacts: Dictionary = legacy.continuity.world.artifacts
	runner.assert_eq(int(old_artifacts.version), SimArtifacts.VERSION, "temporary projection starts from the current artifact envelope")
	var can_project_artifacts: bool = int(old_artifacts.version) == SimArtifacts.VERSION
	var artifact_history: Array = old_artifacts.active.values()
	artifact_history.append_array(old_artifacts.events)
	for row: Variant in artifact_history:
		var no_exchange: bool = row is Dictionary and not row.has("exchange") and row.get("verb") != "private_exchange" and row.get("kind") != "exchanged"
		runner.assert_true(no_exchange, "temporary pre-health artifact history contains no private exchange evidence")
		var v4_compatible: bool = no_exchange and not row.has("draw") and row.get("verb") not in ["use_research", "draw"] and row.get("kind") not in ["use_learned", "drawn"]
		runner.assert_true(v4_compatible, "temporary pre-health artifact history contains no later research or drawing")
		can_project_artifacts = can_project_artifacts and v4_compatible
	if not can_project_artifacts:
		fixtures._dispose(fixture)
		return
	old_artifacts.version = 4
	# The explicit old-format counterexample also predates body-facing v5.
	# Downgrade only this temporary test value; immutable real archives stay
	# untouched and all original effect/action/resource fields remain present.
	# It also predates source-v3 ecology and its irrigation action. Project
	# those additions away explicitly rather than asking the migration to
	# accept a modern source hidden under an old root version.
	var resource_rules: Dictionary = runtime.world_sim._content.land_resources
	_pre_health_village(runner, legacy.simulation, resource_rules)
	for sim: Dictionary in legacy.continuity.world.regions.values():
		_pre_health_village(runner, sim, resource_rules)
	var floor_value: int = int(legacy.continuity.world.artifacts.next_id)
	var original_effects: Variant = legacy.continuity.world.artifacts.events.duplicate(true)
	var path: String = "user://tests/health_legacy_source_%d.json" % Time.get_ticks_usec()
	var bad_path: String = path + ".modern_domain.json"
	# An allegedly old format must not retain today's conflict authority.
	# Keep the malformed candidate as a negative case before projecting only
	# this temporary value; the ordinary migration must continue to reject it.
	var stable: String = _canonical(runtime)
	var live: RegionalSimulation = runtime.world_sim
	runner.assert_eq(SimSaveStore.save_file(bad_path, legacy), OK, "mismatched old envelope remains ordinary readable JSON")
	runner.assert_eq(runtime.load_game(bad_path), ERR_INVALID_DATA, "pre-conflict root cannot carry a modern conflict domain through migration")
	runner.assert_true(runtime.world_sim == live, "rejected old-format conflict domain keeps the original live owner")
	runner.assert_eq(_canonical(runtime), stable, "rejected old-format conflict domain preserves every original consequence, item and clock fact")
	legacy.continuity.world.erase("conflicts")
	var mixed_artifacts: Dictionary = legacy.duplicate(true)
	mixed_artifacts.continuity.world.artifacts.version = 5
	runner.assert_eq(SimSaveStore.save_file(bad_path, mixed_artifacts), OK, "old-format fixture with modern artifact envelope is readable JSON")
	runner.assert_eq(runtime.load_game(bad_path), ERR_INVALID_DATA, "pre-drawing root cannot carry a modern artifact envelope")
	runner.assert_true(runtime.world_sim == live, "rejected mixed artifact envelope keeps the original live owner")
	runner.assert_eq(_canonical(runtime), stable, "rejected mixed artifact envelope preserves every original consequence, item and clock fact")
	runner.assert_eq(SimSaveStore.save_file(path, legacy), OK, "temporary old-format migration fixture contains an actual original backlash")
	var loaded: Error = runtime.load_game(path)
	runner.assert_eq(loaded, OK, "pre-health session migrates through the ordinary joint loader")
	if loaded != OK:
		_clean(path)
		_clean(bad_path)
		fixtures._dispose(fixture)
		return
	runner.assert_eq(runtime.world_sim.health.to_dict().version, 2, "pre-health session explicitly reaches the current sourced-injury schema")
	runner.assert_eq(runtime.world_sim.health.conflict_source_floor, 1, "new conflict consequences start with the actual empty hit history")
	var expected_conflicts: Dictionary = SimConflicts.empty_state()
	expected_conflicts.perception_since_ms = int(legacy.continuity.world.elapsed_ms)
	runner.assert_eq(SnapshotValues.normalized(runtime.world_sim.conflicts.to_dict()), SnapshotValues.normalized(expected_conflicts), "pre-conflict history gains only saved-present perception activation and no imagined hits, encounters or teaching")
	runner.assert_eq(runtime.world_sim.health.source_floor, floor_value, "new consequences begin at the old artifact allocator boundary")
	runner.assert_true(runtime.world_sim.health.wounds.is_empty() and runtime.world_sim.health.jobs.is_empty(), "old actual backlash is preserved without inventing a historical new injury or treatment")
	runner.assert_eq(runtime.world_sim.regions.home.actors.player.facing, legacy.player.motion.facing, "temporary pre-health format gains only its player's explicitly recorded original heading")
	runner.assert_eq(VillageRuntime._json_normalized(runtime.world_sim.artifacts.events), VillageRuntime._json_normalized(original_effects), "migration does not rewrite original effects to hide the past")
	_injure(runner, runtime)
	runner.assert_eq(runtime.world_sim.health.wounds.size(), 1, "a genuinely new effect after migration still creates its own consequence exactly once")
	_clean(path)
	_clean(bad_path)
	fixtures._dispose(fixture)


func _pre_health_village(runner: Object, sim: Dictionary, rules: Dictionary) -> void:
	sim.version = 4
	for body: Dictionary in sim.actors.values():
		body.erase("facing")
	sim.config.actions.erase("irrigate_herb")
	sim.land_resources.version = 2
	for id: String in sim.land_resources.sources:
		var source: Dictionary = sim.land_resources.sources[id]
		var definition: String = str(sim.config.resource_sources[id].definition)
		var terms: Dictionary = rules.types[definition]
		var interval: int = int(terms.regrow_ms)
		@warning_ignore("integer_division")
		var old_periods: int = int(sim.elapsed_ms) / interval
		# The staged backlash occurs before any herb maturity. Do not erase or
		# rewrite actual goods to force an unrepresentable modern future into
		# this earlier format; the old production bound must already hold.
		runner.assert_true(int(source.produced) <= old_periods * int(terms.regrow_amount), "temporary pre-health source has legal original production before removing later ecology: " + id)
		source.erase("ecology")
		source.next_growth_ms = mini(SimInventory.MAX_COUNT, int(sim.elapsed_ms) - posmod(int(sim.elapsed_ms), interval) + interval)


func _real_legacy(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var path: String = "res://tests/fixtures/session_v28.json"
	var original: String = FileAccess.get_file_as_string(path)
	var source: Dictionary = JSON.parse_string(original)
	var runtime: WorldContinuityRuntime = main._continuity
	runner.assert_eq(runtime.load_game(ProjectSettings.globalize_path(path)), OK, "genuine v28 clothing archive remains readable through the new health migration")
	runner.assert_eq(runtime.world_sim.health.source_floor, int(source.continuity.world.artifacts.next_id), "real archive uses its original allocator boundary, not the current new-game value")
	runner.assert_true(runtime.world_sim.health.wounds.is_empty(), "the real pre-health archive gains no invented historical injuries")
	runner.assert_eq(GameClock.elapsed_ms, int(source.clock.elapsed_ms), "health migration preserves the archive's exact ongoing common time")
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "genuine v28 archive stays byte-for-byte unchanged")
	main.free()
	GameClock.restore_state(prior)


func _clean(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _real_archive(runner: Object) -> void:
	var prior: Dictionary = GameClock.to_dict()
	var path: String = "res://tests/fixtures/session_v29.json"
	var original: String = FileAccess.get_file_as_string(path)
	runner.assert_eq(FileAccess.get_sha256(path), "78252157f410869b94ff9ffcb98fe898a02d3525b1815cf52bab8df3db59e1c1", "real v29 care archive keeps its independently recorded source bytes")
	var expected: String = ""
	for attempt: int in 2:
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var runtime: WorldContinuityRuntime = main._continuity
		var loaded: Error = runtime.load_game(ProjectSettings.globalize_path(path))
		runner.assert_eq(loaded, OK, "genuine clicked v29 treatment archive loads through a fresh ordinary scene")
		if loaded != OK:
			main.free()
			continue
		var world: RegionalSimulation = runtime.world_sim
		var job: Dictionary = world.health.jobs.get("health:action:2", {})
		runner.assert_true(not job.is_empty(), "actual archived preparation retains its original stable task ID")
		if job.is_empty():
			main.free()
			continue
		var source: String = str(job.source)
		var identities: Dictionary = {}
		for region: String in world.regions:
			identities[region] = world.regions[region].actors.keys()
		runner.assert_eq(GameClock.elapsed_ms, 2261073, "real archive preserves the precise unfinished-care common time")
		runner.assert_eq(job.verb, "treat", "real archive captures actual treatment rather than examination")
		runner.assert_eq(job.status, "active", "real treatment is still pending at the saved time")
		runner.assert_eq(job.started_ms, 2231073, "original treatment start is never rebased on load")
		runner.assert_eq(job.due_ms, 2351073, "original treatment deadline is never restarted on load")
		runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "herb"), 1, "archive has already invested one herb and still carries its other real herb")
		runner.assert_eq(world.health.wounds[source].treated_ms, -1, "pending archived treatment grants no premature condition")
		runner.assert_true(world.health.owns_actor("player") and world.health.owns_actor("su_zhi"), "both original participants remain occupied after independent loading")
		GameClock.advance_msec(90000)
		runner.assert_eq(GameClock.elapsed_ms, 2351073, "remaining preparation time reaches the original deadline")
		runner.assert_eq(world.health.jobs["health:action:2"].status, "completed", "archived treatment completes once through the ordinary scene clock")
		runner.assert_eq(world.health.wounds[source].treated_ms, 2351073, "care condition begins at its original real completion")
		runner.assert_true(not world.health.current_source("player").is_empty(), "finishing preparation does not instantly heal the archived injury")
		runner.assert_true(world.regions.home.actors.su_zhi.autonomous and not world.health.owns_actor("su_zhi"), "doctor resumes her own ordinary life after the actual preparation")
		runner.assert_true(runtime.travel_to("river"), "recovered control can undertake an actual departure while bodily healing continues")
		runner.assert_true(not runtime.player_journey.is_empty(), "departing requests a real journey rather than switching a region label")
		GameClock.advance_msec(3510000)
		runner.assert_eq(GameClock.elapsed_ms, 5861073, "absent care and world life reach the common one-hour archive horizon")
		runner.assert_eq(runtime.current_region, "river", "real travel arrives at the distant settlement")
		runner.assert_true(runtime.player_journey.is_empty(), "actual journey finishes through common elapsed time")
		runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "herb"), 1, "offscreen recovery and fresh loading never duplicate or refund the invested medicine")
		runner.assert_eq(world.health.wounds[source].recovered_ms, 4680000, "same original injury resolves at the independently observed world pulse")
		runner.assert_true(world.health.current_source("player").is_empty(), "the actual archived patient eventually recovers offscreen")
		for region: String in world.regions:
			runner.assert_eq(world.regions[region].actors.keys(), identities[region], "medical continuation and departure never clone, replace or lose original people in " + region)
		var future: String = _canonical(runtime)
		if attempt == 0:
			expected = future
		else:
			runner.assert_eq(future, expected, "two independent ordinary scenes resume the real pending-care archive to the identical complete world future")
		main.free()
	runner.assert_eq(FileAccess.get_file_as_string(path), original, "genuine clicked v29 treatment archive stays byte-for-byte unchanged")
	GameClock.restore_state(prior)
