extends RefCounted
## Ordinary scene inputs commit bounded conflict only on the shared clock.

const Space = preload("res://scripts/sim/conflict_space.gd")


func run(runner: Object) -> void:
	_panel_learning_and_keys(runner)
	_committed_continuation(runner)
	print("SCENARIO conflict UI: actual U panel and nearby teaching, real held sword, paused Q/E/R on the next shared instant, X without refunds and ordinary joint continuation")


func _scene(runner: Object) -> Dictionary:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null or runtime.conflict_adapter == null:
		runner.assert_true(false, "ordinary main scene constructs the conflict runtime")
		main.free()
		GameClock.restore_state(saved_clock)
		return {}
	# Domain and save deadlines here are not a per-frame work-budget test.
	runtime.settlement_work_budget = 2147483647
	for region: String in runtime.world_sim.regions:
		var sim: VillageSimulation = runtime.world_sim.regions[region]
		for actor: String in sim.actors:
			sim.cancel_action(actor, "conflict_runtime_fixture")
			sim.actors[actor].autonomous = false
		runtime.world_sim.invalidate_region(region)
	var arena: Dictionary = _arena(main)
	if arena.is_empty():
		runner.assert_true(false, "generated main map contains a real unobstructed demonstration space")
		main.free()
		GameClock.restore_state(saved_clock)
		return {}
	return {"main": main, "runtime": runtime, "ui": runtime.conflict_adapter, "clock": saved_clock, "arena": arena}


func _arena(main: Node) -> Dictionary:
	var world: RegionalSimulation = main._continuity.world_sim
	var cells: Array[Vector2i] = VillageRuntime.find_reachable_cells(main.world, main.player.cell, 12, 2048)
	for cell: Vector2i in cells:
		var point: Vector2 = TileGrid.cell_to_world(cell) + Vector2(3.25, -2.5)
		for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
			var other: Vector2 = point + axis * 80.0
			var other_cell: Vector2i = TileGrid.world_to_cell(other)
			if main.world.is_walkable(other_cell) and Space.level(world, point) == Space.level(world, other) and Space.clear_segment(world, point, other, Space.level(world, point)):
				return {"point": point, "axis": axis}
	return {}


func _dispose(fixture: Dictionary) -> void:
	(fixture.main as Node).free()
	GameClock.restore_state(fixture.clock)


func _pair(fixture: Dictionary, target: String) -> void:
	var main: Node = fixture.main
	var runtime: WorldContinuityRuntime = fixture.runtime
	var point: Vector2 = fixture.arena.point
	main.player.motion.relocate(point)
	main.player._project_motion()
	runtime.world_sim.regions.home.set_actor_position(target, point + (fixture.arena.axis as Vector2) * 80.0)
	runtime.world_sim.invalidate_region("home")
	runtime.home_runtime()._sync_actor_views(true)
	main.fog.set_focus(main.player.cell)
	main.fog.update_now()
	main._process(0.0)
	runtime.home_runtime().select_actor(target)


func _key(ui: ConflictRuntime, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	ui._unhandled_input(event)


func _button(root: Node, prefix: String) -> Button:
	for child: Node in root.get_children():
		if child is Button and child.text.begins_with(prefix):
			return child
		var found: Button = _button(child, prefix)
		if found != null:
			return found
	return null


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime)))


func _player_actions(world: RegionalSimulation) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for action: Dictionary in world.conflicts.actions.values():
		if action.actor == "player":
			rows.append(action)
	return rows


func _learn(fixture: Dictionary, runner: Object, button: bool = false) -> bool:
	_pair(fixture, "chen_shouzhuo")
	var runtime: WorldContinuityRuntime = fixture.runtime
	var ui: ConflictRuntime = fixture.ui
	runner.assert_eq(ui.selected_target(), "chen_shouzhuo", "the ordinary inspector resolves the selected visible nearby teacher")
	if button:
		var teach: Button = _button(ui.panel, "请所选人物示范")
		runner.assert_true(teach != null, "U panel contains an actionable demonstration control")
		if teach == null:
			return false
		teach.pressed.emit()
	else:
		runner.assert_true(ui.teach_selected().ok, "selected nearby teacher accepts the actual paired demonstration")
	var active: Dictionary = {}
	for lesson: Dictionary in runtime.world_sim.conflicts.lessons.values():
		if lesson.pupil == "player" and lesson.status == "active":
			active = lesson
	runner.assert_true(not active.is_empty(), "ordinary teaching creates one genuinely timed lesson over both original bodies")
	if active.is_empty():
		return false
	runner.assert_true(not runtime.world_sim.conflicts.knows("player", "qi_bolt"), "pressing the teaching button grants no premature ability")
	runner.assert_true(not GameClock.request_wait(), "generic wait cannot silently skip an occupied demonstration")
	GameClock.advance_msec(int(active.due_ms) - GameClock.elapsed_ms - 1)
	runner.assert_true(not runtime.world_sim.conflicts.knows("player", "qi_bolt"), "a real lesson is still incomplete one millisecond before its due time")
	GameClock.advance_msec(1)
	for method: String in ["sword", "qi_bolt", "qi_guard"]:
		runner.assert_true(runtime.world_sim.conflicts.knows("player", method), "only actual completed demonstration unlocks the known method: " + method)
	runner.assert_true(not runtime.world_sim.conflicts.owns_actor("player"), "finished demonstration releases the player's actual body")
	runner.assert_true(ui._status.text.contains("凝气弹"), "U panel refreshes learned methods from actual personal knowledge")
	return true


func _panel_learning_and_keys(runner: Object) -> void:
	var fixture: Dictionary = _scene(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.runtime
	var ui: ConflictRuntime = fixture.ui
	var before: String = _canonical(runtime)
	runner.assert_true(not ui.panel.visible, "ordinary scene starts with the conflict panel closed")
	_key(ui, KEY_U)
	runner.assert_true(ui.panel.visible, "U opens the real scene's technique and conflict panel")
	_key(ui, KEY_U)
	runner.assert_true(not ui.panel.visible, "U closes the same panel")
	runner.assert_eq(_canonical(runtime), before, "opening and closing U changes no time, resource, knowledge or social fact")
	_key(ui, KEY_Q)
	runner.assert_true(ui._pending.is_empty(), "Q outside an encounter cannot queue an undeclared attack")
	runner.assert_true(not ui.teach_selected().ok and not ui.engage_selected().ok, "self selection cannot teach or initiate hostile intent")
	_pair(fixture, "chen_shouzhuo")
	fixture.main.player.set_altitude(1)
	runner.assert_true(not ui.teach_selected().ok and runtime.world_sim.conflicts.lessons.is_empty(), "ground-only demonstration cannot start from the debug airborne human")
	fixture.main.player.set_altitude(0)
	_key(ui, KEY_U)
	if not _learn(fixture, runner, true):
		_dispose(fixture)
		return
	fixture.main.player.set_altitude(1)
	runner.assert_true(not ui.engage_selected().ok and runtime.world_sim.conflicts.conflicts.is_empty(), "learned ground techniques do not silently enable airborne combat")
	fixture.main.player.set_altitude(0)
	var player: PlayerCharacter = fixture.main.player
	var object_ui: WorldObjectsRuntime = runtime.object_adapter
	var sword_cell: Vector2i = runtime.world_sim.artifacts.object_cell("training_sword")
	player.spawn_at(sword_cell)
	runtime.prepare_player_command()
	fixture.main.fog.set_focus(sword_cell)
	fixture.main.fog.update_now()
	runner.assert_true(object_ui.select_object("training_sword") and object_ui.submit("take").ok, "combat fixture obtains the opening sword through the ordinary real-custody UI")
	if not runtime.world_sim.artifacts.active.has("player"):
		_dispose(fixture)
		return
	GameClock.advance_msec(int(runtime.world_sim.artifacts.active.player.due_ms) - GameClock.elapsed_ms)
	runner.assert_eq(runtime.world_sim.artifacts.held_weapon("player"), "training_sword", "weapon-ready combat uses the same unique held object, not a cosmetic preview")
	_pair(fixture, "a_he")
	GameClock.set_speed(4.0)
	runner.assert_true(GameClock.request_wait(), "idle fixture can explicitly start a wait before hostility")
	GameClock.set_paused(true)
	var engage: Button = _button(ui.panel, "向所选人物表明驱离敌意")
	runner.assert_true(engage != null, "real U panel exposes an explicit hostile-intent control")
	if engage == null:
		_dispose(fixture)
		return
	engage.pressed.emit()
	runner.assert_true(not runtime.world_sim.conflicts.conflict_for("player").is_empty() and ui.badge.visible, "hostile-intent control commits an encounter and exposes its live status badge")
	runner.assert_eq(GameClock.speed, 1.0, "hostility returns the common world to ordinary speed")
	runner.assert_eq(GameClock.wait_target_ms, 0, "hostility stops the previous generic fast-forward")
	runner.assert_true(GameClock.paused and not runtime.travel_to("river"), "explicit pause is retained and encounter occupation blocks automatic travel")
	for entry: Array in [[KEY_Q, "sword"], [KEY_E, "qi_bolt"], [KEY_R, "qi_guard"]]:
		var method: String = str(entry[1])
		var spec: Dictionary = runtime.world_sim.conflicts.rules.methods[method]
		var qi: int = int(runtime.world_sim.conflicts.body("player").qi)
		var stamina: int = int(runtime.world_sim.conflicts.body("player").stamina)
		var count: int = _player_actions(runtime.world_sim).size()
		var now: int = GameClock.elapsed_ms
		before = _canonical(runtime)
		_key(ui, entry[0])
		runner.assert_eq(ui._pending, method, "paused keyboard input selects the actual method: " + method)
		runner.assert_eq(_canonical(runtime), before, "paused Q/E/R selection does not spend or start a simulated action: " + method)
		# Supply a controlled cursor-equivalent aim into empty space; method and
		# timing still pass through the actual input adapter and common clock.
		ui._pending_direction = -(fixture.arena.axis as Vector2)
		GameClock._process(1.0)
		GameClock.advance_msec(0)
		runner.assert_eq(GameClock.elapsed_ms, now, "paused frame processing does not advance common time")
		runner.assert_eq(_player_actions(runtime.world_sim).size(), count, "paused or zero-time processing cannot commit the queued attack")
		var step: int = int(GameClock._rules.clock.fixed_step_ms)
		GameClock.set_paused(false)
		GameClock._process(float(step) / 1000.0)
		GameClock.set_paused(true)
		runner.assert_eq(GameClock.elapsed_ms, now + step, "resuming commits one actual common fixed step")
		runner.assert_eq(_player_actions(runtime.world_sim).size(), count + 1, "next positive common time commits the queued method once")
		var action: Dictionary = _player_actions(runtime.world_sim).back()
		runner.assert_eq(action.method, method, "committed method follows the Q/E/R request")
		runner.assert_eq(action.started_ms, GameClock.elapsed_ms, "runtime submits at the newly committed shared instant")
		runner.assert_eq(int(runtime.world_sim.conflicts.body("player").qi), qi - int(spec.qi), "one committed input pays its actual qi exactly once")
		runner.assert_eq(int(runtime.world_sim.conflicts.body("player").stamina), stamina - int(spec.stamina), "one committed input pays its actual stamina exactly once")
		runner.assert_true(ui._pending.is_empty() and runtime.world_sim.conflicts.phase("player", GameClock.elapsed_ms) == "prepare", "committed request clears its transient queue and enters preparation")
		GameClock.advance_msec(int(spec.prepare_ms) - 1)
		runner.assert_true(not action.emitted, "input-driven method cannot emit one millisecond early: " + method)
		GameClock.advance_msec(1)
		runner.assert_true(action.emitted, "input-driven method emits on its exact actual preparation boundary: " + method)
		if method == "qi_bolt":
			runner.assert_true(runtime.world_sim.conflicts.projectiles.has(action.id), "E creates a real travelling projectile")
		elif method == "qi_guard":
			runner.assert_true(runtime.world_sim.conflicts.barriers.has("player"), "R creates finite actual protection after preparation")
		else:
			runner.assert_eq(action.object, "training_sword", "Q strike references the original actual sword")
		GameClock.advance_msec(int(action.due_ms) - GameClock.elapsed_ms)
		if runtime.world_sim.conflicts.conflict_for("player").is_empty():
			runner.assert_true(false, "empty-space method test retains the original uninjured opponent")
			_dispose(fixture)
			return
	var qi_after: int = int(runtime.world_sim.conflicts.body("player").qi)
	var barriers: Dictionary = runtime.world_sim.conflicts.barriers.duplicate(true)
	_key(ui, KEY_E)
	_key(ui, KEY_X)
	runner.assert_true(ui._pending.is_empty() and runtime.world_sim.conflicts.conflict_for("player").is_empty(), "X clears uncommitted input and ends the player's actual hostile encounter")
	runner.assert_eq(runtime.world_sim.conflicts.body("player").qi, qi_after, "X does not refund any previously committed qi")
	runner.assert_eq(runtime.world_sim.conflicts.barriers, barriers, "X leaves already emitted finite protection on its own lifetime")
	runner.assert_true(not ui.badge.visible, "actual end of the encounter removes its live badge")
	runner.assert_true(runtime.service_adapter.panel.visible and runtime._panel.visible, "ending a fight restores the ordinary service and travel panels")
	_dispose(fixture)


func _committed_continuation(runner: Object) -> void:
	var fixture: Dictionary = _scene(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.runtime
	var ui: ConflictRuntime = fixture.ui
	if not _learn(fixture, runner):
		_dispose(fixture)
		return
	# This fixture disables all background routines. Restore this opponent's
	# actual agency before opening, so later injury comes from a real response
	# rather than the old assumption that every defender is automatically AI.
	runtime.world_sim.conflicts.body("chen_shouzhuo").autonomous = true
	runtime.world_sim.invalidate_region("home")
	runner.assert_true(not bool(runtime.world_sim.conflicts.body("player").autonomous), "continued injury fixture retains the player's actual manual policy before hostility")
	runner.assert_true(ui.engage_selected().ok, "actual selected teacher can enter a separate declared hostile encounter")
	var encounter_id: String = runtime.world_sim.conflicts.conflict_for("player")
	if encounter_id.is_empty():
		_dispose(fixture)
		return
	var encounter: Dictionary = runtime.world_sim.conflicts.conflicts[encounter_id]
	runner.assert_true(bool(encounter.people.chen_shouzhuo.previous_autonomous) and not bool(encounter.people.player.previous_autonomous), "ordinary opening captures the autonomous defender and manual player independently")
	runner.assert_true(not runtime.service_adapter.panel.visible and not runtime._panel.visible, "actual combat clears large work and travel panels from the world view")
	var airborne: Dictionary = WorldSessionSnapshot.capture(runtime)
	airborne.player.altitude = 1
	runner.assert_true(WorldSessionSnapshot.stage(runtime, airborne).is_empty(), "independent joint candidate rejects a ground conflict combined with debug flight")
	_key(ui, KEY_E)
	ui._pending_direction = fixture.arena.axis
	GameClock.advance_msec(1)
	GameClock.advance_msec(617)
	var actions: Array[Dictionary] = _player_actions(runtime.world_sim)
	runner.assert_true(not actions.is_empty() and runtime.world_sim.conflicts.projectiles.has(actions.back().id), "ordinary save fixture contains a genuinely emitted and travelling player shot")
	runner.assert_true(ui.has_visible_danger() and not runtime._can_wait(), "actually visible conflict and projectiles prevent silently waiting through danger")
	fixture.main.fog.set_focus(Vector2i.ZERO)
	fixture.main.fog.update_now()
	runner.assert_true(not ui.has_visible_danger(), "unseen conflicts and projectiles cannot expose remote danger through the UI")
	GameClock.set_speed(4.0)
	ui._on_advanced(GameClock.elapsed_ms, GameClock.elapsed_ms)
	runner.assert_eq(GameClock.speed, 4.0, "unseen remote combat does not slow the player's time")
	fixture.main.fog.set_focus(fixture.main.player.cell)
	fixture.main.fog.update_now()
	ui._on_advanced(GameClock.elapsed_ms, GameClock.elapsed_ms)
	runner.assert_eq(GameClock.speed, 1.0, "perceived danger returns to readable real-time speed")
	var path: String = "user://tests/conflict_runtime_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "ordinary atomic save includes learned methods, paid actions, encounters and travelling shots")
	var present: String = _canonical(runtime)
	GameClock.advance_msec(2000)
	var future: String = _canonical(runtime)
	var qi: int = int(runtime.world_sim.conflicts.body("player").qi)
	ui._pending = "sword"
	runner.assert_eq(runtime.load_game(path), OK, "ordinary loader restores the real committed hostile timeline")
	runner.assert_true(ui._pending.is_empty(), "load discards an uncommitted UI request from the replaced timeline")
	runner.assert_true(not runtime.service_adapter.panel.visible and not runtime._panel.visible, "ordinary loading of an ongoing fight keeps the world view unobstructed")
	runner.assert_eq(_canonical(runtime), present, "load preserves exact original resources, action phase, bodies and in-flight projectile")
	GameClock.advance_msec(2000)
	runner.assert_eq(_canonical(runtime), future, "loaded main scene reaches the identical complete conflict and social-world future")
	runner.assert_eq(runtime.world_sim.conflicts.body("player").qi, qi, "replaying a committed timeline never charges the same cast twice")
	var burden: float = runtime.world_sim.health.combat_burden("player")
	runner.assert_true(burden > 0.0, "continued hostile counterattack leaves an actual nonzero injury before yield persistence is checked")
	var sourced_response: bool = false
	for hit: Dictionary in runtime.world_sim.conflicts.hits.values():
		if hit.actor == "player" and hit.attacker == "chen_shouzhuo" and int(hit.impact) > 0:
			sourced_response = true
	runner.assert_true(sourced_response, "nonzero persisted injury has an actual original opponent action and contact receipt")
	_key(ui, KEY_X)
	runner.assert_eq(runtime.world_sim.health.combat_burden("player"), burden, "runtime yield retains the player's actual persistent injury burden")
	runner.assert_eq(runtime.save_game(path), OK, "ended encounter and nonzero actual injuries save through the same ordinary store")
	present = _canonical(runtime)
	GameClock.advance_msec(113)
	runner.assert_eq(runtime.load_game(path), OK, "ordinary load also accepts an ended encounter with original injury provenance")
	runner.assert_eq(_canonical(runtime), present, "restored ended encounter retains real injuries, learned methods and previously spent costs")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	_dispose(fixture)
