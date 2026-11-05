extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const EXCHANGE_ARCHIVE: String = "res://tests/fixtures/session_v42_exchange.json"
const RING: String = "stele_drawing_ring"


class ReloadDuringVisibility extends SimArtifacts:
	## The callback replaces the session exactly between the genuine visibility
	## decision and the following cell lookup, as a debugger callback can do.
	var reload: Callable
	var load_result: int = ERR_UNCONFIGURED
	var fired: bool = false
	var load_returned: bool = false
	var post_load_cell_read: bool = false
	var owner_at_cell: int = 0

	func can_see(actor: String, id: String) -> bool:
		var seen: bool = super.can_see(actor, id)
		if seen and not fired and reload.is_valid():
			fired = true
			load_result = int(reload.call())
			load_returned = true
		return seen

	func object_cell(id: String) -> Vector2i:
		if load_returned:
			post_load_cell_read = true
			var authority: RefCounted = world
			owner_at_cell = authority.get_instance_id() if authority != null else 0
			# Record the missing owner as a failed assertion rather than generating
			# a debugger break that would abort the test before it can report.
			if authority == null:
				return Vector2i(-1, -1)
		return super.object_cell(id)


class MaskFog extends FogOfWar:
	var hidden_cells: Dictionary = {}

	func is_cell_visible(cell: Vector2i) -> bool:
		return not hidden_cells.has(cell)


class BudgetLimitedLifecycle extends SimObjectLifecycle:
	func artifact_candidates(_center: Vector2i, _radius: int, _budget: int = 4096) -> Dictionary:
		return {"ok": false, "reason": "budget_exhausted"}


func run(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var adapter: WorldObjectsRuntime = runtime.object_adapter
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))
	runner.assert_eq(runtime.world_sim.artifacts.objects.size(), opening.objects.size(), "new actual runtime issues the declared opening objects")
	runner.assert_true(adapter.select_object("hearth_stone") and adapter.panel.visible, "nearby visible object opens its dedicated inspector")
	runner.assert_true(not adapter.panel._buttons.charge.visible, "unknown activation does not expose the learned recharge operation")
	var before: Dictionary = runtime.world_sim.artifacts.to_dict()
	adapter.refresh()
	adapter.panel.hide()
	adapter.select_object("hearth_stone")
	runner.assert_eq(runtime.world_sim.artifacts.to_dict(), before, "opening/closing object UI creates no knowledge or resource change")
	runner.assert_true(bool(adapter.submit("approach").ok), "inspector can order a real terrain-backed approach")
	var deadline: int = GameClock.elapsed_ms + 120 * 60000
	while not runtime.player_journey.is_empty() and GameClock.tick_index < deadline:
		GameClock.advance_ticks(1)
	runner.assert_true(runtime.player_journey.is_empty(), "approach finishes without teleporting")
	runner.assert_true(bool(adapter.submit("take").ok), "actual inspector can take the unique instance")
	GameClock.advance_ticks(int(runtime.world_sim.artifacts.definitions.verbs.take.minutes))
	runner.assert_eq(runtime.world_sim.artifacts.objects.hearth_stone.container, "actor:player", "taking in the game changes real custody")
	runner.assert_true(bool(adapter.submit("study").ok), "actual inspector starts paid investigation")
	runner.assert_true(not bool(runtime.submit_service("rest").ok), "visitor service cannot steal an artifact executor's body")
	runner.assert_true(not runtime.travel_to("river"), "new automatic travel cannot silently overwrite an experiment")
	GameClock.advance_ticks(1)
	var path: String = "user://tests/artifact_runtime_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "in-progress artifact and all other world domains save together")
	var pending: Dictionary = runtime.world_sim.artifacts.to_dict()
	var qi: int = int(fixture.home.simulation.actors.player.qi)
	fixture.home.cancel_player_action()
	runner.assert_true(not runtime.world_sim.artifacts.owns_actor("player"), "manual movement's existing cancel path interrupts investigation")
	runner.assert_eq(fixture.home.simulation.actors.player.qi, qi, "manual cancellation cannot refund invested qi")
	runner.assert_eq(runtime.load_game(path), OK, "normal load restores unfinished artifact work")
	runner.assert_eq(runtime.world_sim.artifacts.to_dict(), pending, "artifact remaining duration and custody are restored exactly")
	var finish: int = int(runtime.world_sim.artifacts.active.player.due_ms)
	GameClock.advance_msec(finish - GameClock.elapsed_ms)
	runner.assert_true(bool(runtime.world_sim.artifacts.describe("player", "hearth_stone").method), "restored investigation completes and yields personal method knowledge")
	adapter.select_object("hearth_stone")
	runner.assert_true(adapter.panel._buttons.charge.visible, "learning exposes the relevant operation through an authorized view")
	var denial: Dictionary = adapter.submit("take")
	runner.assert_true(not bool(denial.ok) and adapter.panel._notice.text == denial.line, "older experiment outcome cannot overwrite a new command's refusal")
	runner.assert_true(bool(adapter.submit("to_garden").ok), "known heat method and carried stone allow a real trip to the garden")
	GameClock.advance_msec(5000)
	runner.assert_true(runtime.player_journey.is_empty(), "short garden route has physically finished before craft begins")
	runner.assert_true(adapter.panel._buttons.dry.visible, "personal control method exposes the second heat use")
	var raw_herbs: int = fixture.home.simulation.inventory.quantity("garden", "herb")
	runner.assert_true(bool(adapter.submit("dry").ok), "actual inspector starts drying at a fractional-minute time")
	var due_ms: int = int(runtime.world_sim.artifacts.active.player.due_ms)
	GameClock.advance_msec(due_ms - GameClock.elapsed_ms - 1)
	runner.assert_eq(fixture.home.simulation.inventory.quantity("garden", "dried_herb"), 0, "UI-driven craft cannot finish one millisecond early")
	GameClock.advance_msec(1)
	runner.assert_eq(fixture.home.simulation.inventory.quantity("garden", "herb"), raw_herbs - 2, "UI-driven drying actually consumes its raw herbs")
	runner.assert_eq(fixture.home.simulation.inventory.quantity("garden", "dried_herb"), 2, "UI-driven drying leaves its actual product")
	runner.assert_true(not runtime.service_adapter.panel._phase.text.contains("正在办理"), "shared activity panel clears at a fractional-minute artifact completion")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	fixtures._dispose(fixture)
	_test_reentrant_load_during_visibility(runner)
	_test_local_view_and_footprints(runner)
	print("SCENARIO object UI: approach→take→investigate, no duplicate body owner, manual cancel and joint resume")


func _test_local_view_and_footprints(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var adapter: WorldContinuityRuntime = fixture.continuity
	var view: WorldObjectsRuntime = adapter.object_adapter
	var authority: RegionalSimulation = adapter.world_sim
	var lifecycle: SimObjectLifecycle = authority.object_lifecycle
	adapter.prepare_player_command()
	var center: Vector2i = adapter.controlled_cell()
	var chosen := Vector2i(-1, -1)
	for y: int in range(center.y - 2, center.y + 2):
		for x: int in range(center.x - 2, center.x + 2):
			if bool(lifecycle.ground.can_place("home", Vector2i(x, y), Vector2i(2, 1)).get("ok", false)):
				chosen = Vector2i(x, y)
				break
		if chosen.x >= 0:
			break
	runner.assert_true(chosen.x >= 0, "local fixture has room for a real two-cell placement")
	if chosen.x >= 0:
		var spawn: Dictionary = lifecycle.execute({"command": "view_slab", "op": "spawn", "id": "view_slab", "definition": "stone_slab", "to": {"region": "home", "cell": [chosen.x, chosen.y]}})
		runner.assert_true(bool(spawn.get("ok", false)), "local view starts with a real lifecycle-managed slab")
		var distant: Vector2i = center + Vector2i(15, 15)
		var far_spawn: Dictionary = lifecycle.execute({"command": "view_far", "op": "spawn", "id": "view_far", "definition": "plain_slate", "to": {"region": "home", "cell": [distant.x, distant.y]}})
		runner.assert_true(bool(far_spawn.get("ok", false)), "local view fixture also has a distant managed object")
		if bool(spawn.get("ok", false)) and bool(far_spawn.get("ok", false)):
			var candidates: Array[String] = view._local_candidates(authority)
			runner.assert_true(candidates.has("view_slab") and not candidates.has("view_far"), "nearby managed objects are queried without enumerating distant managed objects")
			runner.assert_eq(view._physical_ground_rect("view_slab", authority), Rect2i(chosen, Vector2i(2, 1)), "one drawn object uses its original two-cell footprint")
			var other: Vector2i = chosen + Vector2i.RIGHT
			runner.assert_true(view._visible_hits(TileGrid.cell_to_world(chosen), authority).has("view_slab"), "the first visible footprint cell can be selected")
			runner.assert_true(view._visible_hits(TileGrid.cell_to_world(other), authority).has("view_slab"), "the other visible footprint cell selects the same object")
			var fog := MaskFog.new()
			fixture.home._fog = fog
			fog.hidden_cells[other] = true
			runner.assert_true(view._visible_hits(TileGrid.cell_to_world(chosen), authority).has("view_slab"), "the visible part of the same footprint stays selectable")
			runner.assert_true(not view._visible_hits(TileGrid.cell_to_world(other), authority).has("view_slab"), "the hidden footprint cell cannot be selected through fog")
			fixture.home._fog = null
			fog.free()
			var carried: Dictionary = lifecycle.execute({"command": "view_carry", "op": "move", "id": "view_slab", "from": spawn.to, "to": {"region": "home", "container": "actor:player"}})
			runner.assert_true(bool(carried.get("ok", false)), "the same original slab may move into the actor container")
			if bool(carried.get("ok", false)):
				runner.assert_eq(view._physical_ground_rect("view_slab", authority).size, Vector2i.ZERO, "a carried object no longer renders a ground footprint")
				runner.assert_true(view._local_candidates(authority).has("view_slab"), "the carried original remains in the local candidate query")
	var limited := BudgetLimitedLifecycle.new()
	authority.object_lifecycle = limited
	runner.assert_true(view._local_candidates(authority).is_empty() and view._visible_display_points(authority).is_empty(), "a budget-exhausted local query does not fall back to an unrestricted scan")
	authority.object_lifecycle = lifecycle
	fixtures._dispose(fixture)


func _test_reentrant_load_during_visibility(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var path: String = "user://tests/objects_reentrant_%d.json" % Time.get_ticks_usec()
	var loaded: Error = runtime.load_game(ProjectSettings.globalize_path(EXCHANGE_ARCHIVE))
	runner.assert_eq(loaded, OK, "reentrant view regression loads the original pending handover")
	if loaded == OK:
		GameClock.set_paused(true)
		var adapter: WorldObjectsRuntime = runtime.object_adapter
		runner.assert_true(runtime._home._fog != null, "the real view has fog, so visibility includes the following cell read")
		var visible_before: bool = adapter._visible(RING)
		runner.assert_true(visible_before, "the original holder and ring are actually visible before the interruption")
		var saved: Error = runtime.save_game(path)
		runner.assert_eq(saved, OK, "the current original handover is saved for a real reentrant reload")
		if saved == OK and visible_before and runtime._home._fog != null:
			var expected: String = SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime)))
			var old_id: int = runtime.world_sim.get_instance_id()
			var old_ref: WeakRef = weakref(runtime.world_sim)
			var probe := ReloadDuringVisibility.new()
			var initialized: bool = probe.initialize(runtime.world_sim, runtime._home._content.artifacts)
			var copied: bool = initialized and probe.restore(runtime.world_sim.artifacts.to_dict())
			runner.assert_true(copied, "the view probe preserves the original artifact state and owner")
			if copied:
				runtime.world_sim.artifacts = probe
				probe.reload = Callable(runtime, "load_game").bind(path)
				var visible_after: bool = adapter._visible(RING)
				runner.assert_true(probe.fired and probe.load_result == OK, "visibility synchronously commits the independent saved replacement")
				runner.assert_true(runtime.world_sim.get_instance_id() != old_id, "the actual runtime world was replaced during the view call")
				runner.assert_true(probe.post_load_cell_read and probe.owner_at_cell == old_id, "the old artifact owner survives through the subsequent cell lookup")
				runner.assert_true(visible_after, "the interrupted view finishes with the genuinely visible ring")
				runner.assert_true(old_ref.get_ref() == null, "the old world is released after the completed view call")
				runner.assert_eq(runtime.world_sim.regions.home.inventory.quantity("actor:player", "coin"), 6, "the replacement retains the original unspent money")
				runner.assert_eq(runtime.world_sim.regions.home.inventory.available("actor:player", "coin"), 2, "the replacement retains the original four-coin reservation")
				runner.assert_eq(runtime.world_sim.artifacts.objects[RING].container, "actor:river_shi_tou", "the replacement retains the seller's original ring")
				var after: String = SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime)))
				runner.assert_true(after == expected, "reentrant presentation and loading preserve the entire saved session")
				# The old view's equivalent expression holds only the artifact domain.
				# Repeating the same real reload demonstrates that the failure is due
				# to its missing world reference, not an ineffective test callback.
				var control_ref: WeakRef = weakref(runtime.world_sim)
				var control := ReloadDuringVisibility.new()
				var control_ready: bool = control.initialize(runtime.world_sim, runtime._home._content.artifacts) and control.restore(runtime.world_sim.artifacts.to_dict())
				runner.assert_true(control_ready, "the control starts from the same original artifact state")
				if control_ready:
					runtime.world_sim.artifacts = control
					control.reload = Callable(runtime, "load_game").bind(path)
					var loose_result: bool = _visibility_without_world_reference(runtime, RING)
					runner.assert_true(control.fired and control.load_result == OK, "the control performs the same synchronous successful reload")
					runner.assert_true(control.post_load_cell_read and control.owner_at_cell == 0, "a loose domain loses its old world before the next cell read")
					runner.assert_true(not loose_result and control_ref.get_ref() == null, "the control cannot safely finish after its old owner is released")
					var control_after: String = SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime)))
					runner.assert_true(control_after == expected, "both interleavings leave the actual replacement snapshot intact")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	main.free()
	GameClock.restore_state(saved_clock)


func _visibility_without_world_reference(runtime: WorldContinuityRuntime, id: String) -> bool:
	var domain: SimArtifacts = runtime.world_sim.artifacts
	return domain.can_see("player", id) and (runtime._home._fog == null or runtime._home._fog.is_cell_visible(domain.object_cell(id)))
