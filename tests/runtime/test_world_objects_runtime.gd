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
	_test_editor_physical_action_and_resume(runner)
	print("SCENARIO object UI: approach→take→investigate, no duplicate body owner, manual cancel and joint resume")


func _test_editor_physical_action_and_resume(runner: Object) -> void:
	# The ordinary main scene uses the real flat map descriptor required by the
	# editing tool; the lightweight runtime fixture intentionally does not.
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": GameClock.start_minutes, "speed": 1.0, "paused": true, "elapsed_ms": 0, "frame_debt_ms": 0.0, "wait_target_ms": 0})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "physical action fixture assembles the ordinary main scene")
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var selected: bool = runtime.select_starting_avatar("subject:player")
	runner.assert_true(selected, "physical action fixture selects the actual human")
	if not selected:
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var view: WorldObjectsRuntime = runtime.object_adapter
	var editor := TerrainEditorRuntime.new()
	main.add_child(editor)
	editor.setup(runtime)
	runtime.prepare_player_command()
	var opening: Vector2i = runtime.controlled_cell()
	var area := Vector2i(-1, -1)
	var near_cell := Vector2i(-1, -1)
	var far_cell := Vector2i(-1, -1)
	var other_cell := Vector2i(-1, -1)
	var world: RegionalSimulation = runtime.world_sim
	var ground: SimGroundPlacements = world.object_lifecycle.ground
	# Find a clear nearby starting cell and reach target on the actual terrain.
	# The player's relocation is fixture setup, before any item/action is created.
	for dy: int in range(-5, 6):
		for dx: int in range(-5, 6):
			var candidate: Vector2i = opening + Vector2i(dx, dy)
			if not bool(ground.can_place("home", candidate, Vector2i(2, 1)).get("ok", false)):
				continue
			var origin: Vector2 = TileGrid.cell_to_world(candidate)
			var level: int = SimConflictSpace.level(world, origin)
			for offset: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN, Vector2i(1, -1), Vector2i(-1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
				var point: Vector2i = candidate + offset
				if Rect2i(candidate, Vector2i(2, 1)).intersects(Rect2i(point, Vector2i(2, 1))) or not bool(ground.can_place("home", point, Vector2i(2, 1)).get("ok", false)):
					continue
				if not SimConflictSpace.clear_segment(world, origin, TileGrid.cell_to_world(point), level):
					continue
				area = candidate
				near_cell = point
				break
			if area.x >= 0:
				break
		if area.x >= 0:
			break
	if area.x < 0:
		runner.assert_true(false, "ordinary flat world has a reachable two-cell pickup and clear drop area")
		main.free()
		GameClock.restore_state(saved_clock)
		return
	main.player.spawn_at(area)
	runtime.prepare_player_command()
	main.fog.set_focus(area)
	main.fog.update_now()
	if not main.fog.is_cell_visible(near_cell):
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN, Vector2i(1, -1), Vector2i(-1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
			var point: Vector2i = area + offset
			if Rect2i(area, Vector2i(2, 1)).intersects(Rect2i(point, Vector2i(2, 1))) or not bool(ground.can_place("home", point, Vector2i(2, 1)).get("ok", false)) or not main.fog.is_cell_visible(point):
				continue
			var origin: Vector2 = TileGrid.cell_to_world(area)
			if SimConflictSpace.clear_segment(world, origin, TileGrid.cell_to_world(point), SimConflictSpace.level(world, origin)):
				near_cell = point
				break
	var near_visible: bool = main.fog.is_cell_visible(near_cell)
	runner.assert_true(near_visible, "the actual nearby pickup cell is visible")
	if not near_visible:
		main.free()
		GameClock.restore_state(saved_clock)
		return
	for dy: int in range(-5, 6):
		for dx: int in range(-5, 6):
			var offset := Vector2i(dx, dy)
			if offset.length() <= float(world.artifacts.definitions.interaction_radius) or offset.length() > float(world.regions.home.config.observation_radius):
				continue
			var point: Vector2i = area + offset
			if main.fog.is_cell_visible(point) and not Rect2i(near_cell, Vector2i(2, 1)).has_point(point) and bool(ground.can_place("home", point).get("ok", false)):
				far_cell = point
				break
		if far_cell.x >= 0:
			break
	for offset: Vector2i in [Vector2i(-3, 0), Vector2i(3, 0), Vector2i(0, -3), Vector2i(0, 3)]:
		var point: Vector2i = area + offset
		if point != far_cell and not Rect2i(near_cell, Vector2i(2, 1)).has_point(point) and bool(ground.can_place("home", point).get("ok", false)):
			other_cell = point
			break
	var open: bool = near_cell.x >= 0 and far_cell.x >= 0 and other_cell.x >= 0
	runner.assert_true(open, "ordinary physical fixture has near, observed-far and other-custody ground cells")
	if not open:
		main.free()
		GameClock.restore_state(saved_clock)
		return
	runner.assert_true(not bool(editor.place_object("stone_slab", near_cell).get("ok", true)), "the developer object tool cannot mutate an unprepared session")
	var prepared: Dictionary = editor.prepare()
	runner.assert_true(bool(prepared.get("ok", false)), "the developer tool prepares the actual paused session: " + str(prepared))
	if not bool(prepared.get("ok", false)):
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var original_time: int = runtime.world_sim.elapsed_ms
	var inventory_before: Dictionary = runtime.world_sim.regions.home.inventory.to_dict()
	var created: Dictionary = editor.place_object("stone_slab", near_cell)
	var distant: Dictionary = editor.place_object("plain_slate", far_cell)
	var other: Dictionary = editor.place_object("plain_slate", other_cell)
	var created_all: bool = bool(created.get("ok", false)) and bool(distant.get("ok", false)) and bool(other.get("ok", false))
	runner.assert_true(created_all, "developer tool creates three actual managed instances using definitions: " + str([created, distant, other]))
	if not created_all:
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var slab: String = str(created.get("reference", {}).get("id", ""))
	var far_id: String = str(distant.get("reference", {}).get("id", ""))
	var other_id: String = str(other.get("reference", {}).get("id", ""))
	var ids_valid: bool = not slab.is_empty() and not far_id.is_empty() and not other_id.is_empty()
	runner.assert_true(ids_valid, "editor returns the original instance references")
	if not ids_valid:
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var life: SimObjectLifecycle = runtime.world_sim.object_lifecycle
	runner.assert_eq(runtime.world_sim.elapsed_ms, original_time, "developer object creation does not advance the shared clock")
	runner.assert_eq(runtime.world_sim.regions.home.inventory.to_dict(), inventory_before, "developer object creation does not consume or create inventory stock")
	var extra: Vector2i = area + Vector2i(0, -4)
	var free_extra: bool = bool(ground.can_place("home", extra, Vector2i(2, 1)).get("ok", false)) and not Rect2i(near_cell, Vector2i(2, 1)).intersects(Rect2i(extra, Vector2i(2, 1))) and not Rect2i(extra, Vector2i(2, 1)).has_point(far_cell) and not Rect2i(extra, Vector2i(2, 1)).has_point(other_cell)
	if free_extra:
		var last_record: Dictionary = editor.place_object("stone_slab", extra)
		runner.assert_true(bool(last_record.get("ok", false)), "developer places a second removable wide item")
		if bool(last_record.get("ok", false)):
			var extra_id: String = str(last_record.reference.id)
			var erased: Dictionary = editor.remove_object(extra + Vector2i.RIGHT)
			runner.assert_true(bool(erased.get("ok", false)) and not runtime.world_sim.artifacts.objects.has(extra_id), "developer removal uses the non-anchor footprint cell and removes the unique original")
			runner.assert_true(ground.query_cell(extra).get("ids", []).is_empty() and ground.query_cell(extra + Vector2i.RIGHT).get("ids", []).is_empty(), "developer removal releases all of the wide footprint")
	runner.assert_true(life.manages(slab) and runtime.world_sim.artifacts.objects[slab].definition == "stone_slab", "the new slab has one original lifecycle and definition")
	var original_slot: String = str(created.to.container)
	for point: Vector2i in [near_cell, near_cell + Vector2i.RIGHT]:
		runner.assert_eq(ground.query_cell(point).get("ids"), [original_slot], "both editor-created slab cells reference the same slot")
	var overlap: Dictionary = editor.place_object("plain_slate", near_cell + Vector2i.RIGHT)
	runner.assert_true(not bool(overlap.get("ok", true)), "developer placement rejects the slab's occupied second cell")
	editor.close()

	var wait_started: bool = GameClock.request_wait(5)
	runner.assert_true(wait_started, "the ordinary human can begin waiting before physical handling")
	GameClock.set_paused(true)
	var waiting_until: int = GameClock.wait_target_ms
	runner.assert_true(wait_started and waiting_until > GameClock.elapsed_ms, "pausing leaves the scheduled wait in progress")
	runner.assert_true(view.select_object(far_id), "an observed but distant item can be selected")
	runner.assert_true(not bool(view.submit("take").get("ok", true)), "the ordinary panel cannot take an observed distant item")
	runner.assert_eq(runtime.world_sim.artifacts.objects[far_id].container, distant.to.container, "distance refusal leaves the original item on the ground")
	runner.assert_eq(GameClock.wait_target_ms, waiting_until, "a refused distant take does not cancel the existing wait")

	# Authority setup models a visible item already held by another person. The
	# player must request consent instead of silently moving that original.
	var actors: Dictionary = runtime.world_sim.regions.home.actors
	var holder: String = ""
	for candidate: String in actors:
		var candidate_cell: Vector2i = SimRouteTravel.cell(actors[candidate].cell)
		if candidate != "player" and bool(actors[candidate].alive) and candidate_cell.distance_to(area) <= float(runtime.world_sim.artifacts.definitions.interaction_radius) and main.fog.is_cell_visible(candidate_cell):
			holder = candidate
			break
	if holder.is_empty():
		for candidate: String in actors:
			if candidate != "player" and bool(actors[candidate].alive):
				holder = candidate
				break
		if not holder.is_empty():
			runtime.world_sim.regions.home.set_actor_cell(holder, area)
	runner.assert_true(not holder.is_empty(), "the original home region contains another holder")
	if not holder.is_empty():
		var gave: Dictionary = life.execute({"command": "runtime_other_custody", "op": "move", "id": other_id,
			"from": other.to, "to": {"region": "home", "container": "actor:" + holder}})
		runner.assert_true(bool(gave.get("ok", false)), "another person's actual container receives the managed instance")
		if bool(gave.get("ok", false)):
			runner.assert_true(view.select_object(other_id), "the nearby held instance remains perceptible")
			runner.assert_true(not bool(view.submit("take").get("ok", true)), "the panel cannot take another person's item without consent")
			runner.assert_eq(runtime.world_sim.artifacts.objects[other_id].container, "actor:" + holder, "refusal preserves the original holder")

	if not view.select_object(slab):
		runner.assert_true(false, "the nearby editor-created slab opens its ordinary object panel")
		main.free()
		GameClock.restore_state(saved_clock)
		return
	runner.assert_true(view.panel._buttons.take.visible and not view.panel._buttons.place.visible, "the unheld slab offers take")
	for verb: String in ["inspect", "study", "examine", "ask_study", "ask_examine"]:
		runner.assert_true(not view.panel._buttons[verb].visible, "managed physical UI excludes unsupported " + verb)
	runner.assert_eq(GameClock.wait_target_ms, waiting_until, "the original paused wait remains until an action is accepted")
	var take: Dictionary = view.submit("take")
	runner.assert_true(bool(take.get("ok", false)) and life.owns_actor("player"), "the panel schedules original timed lifecycle take")
	if not bool(take.get("ok", false)):
		main.free()
		GameClock.restore_state(saved_clock)
		return
	runner.assert_eq(GameClock.wait_target_ms, 0, "a successful take cancels the previously paused wait")
	runner.assert_true(not GameClock.request_wait(5), "waiting cannot start while the physical take owns the player")
	runner.assert_eq(GameClock.wait_target_ms, 0, "refusing a new wait during the take leaves no wait target")
	var first_id: String = str(take.get("action", {}).get("request", {}).get("command", ""))
	runner.assert_true(not first_id.is_empty() and life.actions.has(first_id), "the active take has one lifecycle command")
	runner.assert_true(view.panel._buttons.take.disabled, "the panel displays the original in-flight take as busy")
	GameClock.advance_msec(1000)
	runtime.stop_player_action()
	runner.assert_true(not life.owns_actor("player"), "ordinary player cancellation releases the lifecycle body")
	if not first_id.is_empty() and life.actions.has(first_id):
		runner.assert_eq(life.actions[first_id].status, "cancelled", "the original take is cancelled")
	GameClock.advance_msec(60000)
	runner.assert_eq(runtime.world_sim.artifacts.objects[slab].container, original_slot, "a cancelled take cannot later move or copy the slab")
	runner.assert_eq(ground.query_cell(near_cell + Vector2i.RIGHT).get("ids"), [original_slot], "cancellation keeps the complete two-cell footprint")
	view.select_object(slab)
	var retry_wait: bool = GameClock.request_wait(5)
	runner.assert_true(retry_wait, "the player can start a new wait after cancelling the first take")
	GameClock.set_paused(true)
	runner.assert_true(retry_wait and GameClock.wait_target_ms > GameClock.elapsed_ms, "the new paused wait has a real future target")
	var retry: Dictionary = view.submit("take")
	runner.assert_true(bool(retry.get("ok", false)), "the same actual item can be taken again after cancellation")
	if not bool(retry.get("ok", false)):
		main.free()
		GameClock.restore_state(saved_clock)
		return
	runner.assert_eq(GameClock.wait_target_ms, 0, "the retried take clears its pre-existing wait before the ordinary save")
	runner.assert_true(not GameClock.request_wait(5), "the retried take also rejects a new wait")
	runner.assert_eq(GameClock.wait_target_ms, 0, "the retried action remains compatible with ordinary save and load")
	var action_id: String = str(retry.get("action", {}).get("request", {}).get("command", ""))
	if action_id.is_empty() or not life.actions.has(action_id):
		runner.assert_true(false, "retry identifies the real pending lifecycle action")
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var due: int = int(life.actions[action_id].due_ms)
	GameClock.advance_msec(1000)
	var path: String = "user://tests/physical_runtime_%d.json" % Time.get_ticks_usec()
	var saved: Error = runtime.save_game(path)
	runner.assert_eq(saved, OK, "the in-flight physical action saves through the ordinary session")
	if saved != OK:
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var loaded: Error = runtime.load_game(path)
	runner.assert_eq(loaded, OK, "ordinary load restores the independent original-world candidate")
	if loaded != OK:
		_cleanup_physical_save(path)
		main.free()
		GameClock.restore_state(saved_clock)
		return
	life = runtime.world_sim.object_lifecycle
	ground = life.ground
	runner.assert_true(life.actions.has(action_id) and life.owns_actor("player"), "the restored original action still owns the player body")
	if life.actions.has(action_id):
		runner.assert_eq(life.actions[action_id].status, "active", "the action remains in progress after loading")
		runner.assert_eq(int(life.actions[action_id].due_ms), due, "load preserves the original completion time")
	var remaining: int = due - GameClock.elapsed_ms
	if remaining > 1:
		GameClock.advance_msec(remaining - 1)
		runner.assert_eq(runtime.world_sim.artifacts.objects[slab].container, original_slot, "the restored take does not move an item one millisecond early")
		GameClock.advance_msec(1)
	runner.assert_eq(runtime.world_sim.artifacts.objects[slab].container, "actor:player", "the restored take moves the same original into the player's container")
	runner.assert_true(ground.query_cell(near_cell).get("ids", []).is_empty() and ground.query_cell(near_cell + Vector2i.RIGHT).get("ids", []).is_empty(), "both old floor cells are released after completion")
	runner.assert_true(view.select_object(slab) and view.panel._buttons.place.visible, "the carried original offers place in the ordinary panel")
	var underfoot: Vector2i = runtime.controlled_cell()
	var obstacle: Dictionary = life.execute({"command": "runtime_place_obstacle", "op": "spawn", "id": "runtime_place_obstacle", "definition": "plain_slate", "to": {"region": "home", "cell": [underfoot.x + 1, underfoot.y]}})
	runner.assert_true(bool(obstacle.get("ok", false)), "a separate item occupies only the slab's future second cell")
	if bool(obstacle.get("ok", false)):
		runner.assert_true(not bool(view.submit("place").get("ok", true)), "placing a two-cell item rejects an occupied second cell")
		runner.assert_eq(runtime.world_sim.artifacts.objects[slab].container, "actor:player", "refused placement preserves custody")
		var removed: Dictionary = life.execute({"command": "runtime_remove_obstacle", "op": "remove", "id": "runtime_place_obstacle", "from": obstacle.to})
		runner.assert_true(bool(removed.get("ok", false)), "the original obstruction can be removed")
	var placed: Dictionary = view.submit("place")
	runner.assert_true(bool(placed.get("ok", false)), "panel schedules placing the carried item at the player's feet")
	if bool(placed.get("ok", false)):
		var place_action: Dictionary = placed.get("action", {})
		var place_due: int = int(place_action.get("due_ms", GameClock.elapsed_ms))
		if place_due > GameClock.elapsed_ms:
			GameClock.advance_msec(place_due - GameClock.elapsed_ms)
		var slot: String = str(runtime.world_sim.artifacts.objects[slab].container)
		runner.assert_true(slot.begins_with("ground:"), "the same original item now belongs to the actual ground")
		runner.assert_eq(ground.query_cell(underfoot).get("ids"), [slot], "placed slab occupies its first real cell")
		runner.assert_eq(ground.query_cell(underfoot + Vector2i.RIGHT).get("ids"), [slot], "placed slab occupies its second real cell")
	_cleanup_physical_save(path)
	main.free()
	GameClock.restore_state(saved_clock)
	_test_contact_change_at_deadline(runner)


func _test_contact_change_at_deadline(runner: Object) -> void:
	# Use the real main scene/map for a contact obstruction at the deadline.
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": GameClock.start_minutes, "speed": 1.0, "paused": true, "elapsed_ms": 0, "frame_debt_ms": 0.0, "wait_target_ms": 0})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	if runtime == null or runtime.world_sim == null:
		runner.assert_true(false, "contact deadline fixture assembles the ordinary scene")
		main.free()
		GameClock.restore_state(saved_clock)
		return
	runner.assert_true(runtime.select_starting_avatar("subject:player"), "contact deadline fixture selects the actual human")
	var world: RegionalSimulation = runtime.world_sim
	var origin: Vector2i = runtime.controlled_cell()
	var start := Vector2i(-1, -1)
	var middle := Vector2i(-1, -1)
	var origin_point: Vector2 = TileGrid.cell_to_world(origin)
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var between: Vector2i = origin + direction
		var target: Vector2i = origin + direction * 2
		if not bool(world.object_lifecycle.ground.can_place("home", target).get("ok", false)):
			continue
		if world.map_data.get_terrain(between) != WorldMapData.TERRAIN_GRASS:
			continue
		var target_point: Vector2 = TileGrid.cell_to_world(target)
		if SimConflictSpace.clear_segment(world, origin_point, target_point, SimConflictSpace.level(world, origin_point)):
			middle = between
			start = target
			break
	if start.x < 0:
		runner.assert_true(false, "the ordinary map has a nearby two-cell unobstructed contact")
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var editor := TerrainEditorRuntime.new()
	main.add_child(editor)
	editor.setup(runtime)
	var prepared: Dictionary = editor.prepare()
	var created: Dictionary = editor.place_object("plain_slate", start) if bool(prepared.get("ok", false)) else {}
	runner.assert_true(bool(created.get("ok", false)), "developer editor places the real contact item")
	if not bool(created.get("ok", false)):
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var id: String = str(created.get("reference", {}).get("id", ""))
	var slot: String = str(created.to.container)
	editor.close()
	var view: WorldObjectsRuntime = runtime.object_adapter
	var selected: bool = view.select_object(id)
	var take: Dictionary = view.submit("take") if selected else {}
	var action: Dictionary = take.get("action", {})
	var command: String = str(action.get("request", {}).get("command", ""))
	runner.assert_true(bool(take.get("ok", false)) and not command.is_empty(), "ordinary panel begins a real contact-constrained take")
	if not bool(take.get("ok", false)) or command.is_empty():
		main.free()
		GameClock.restore_state(saved_clock)
		return
	# Low-level edit models another world operation changing topology between
	# acceptance and deadline; the developer editor's own guard is separate.
	var patch: Dictionary = world.map_data.apply_terrain_patch([[middle.x, middle.y, WorldMapData.TERRAIN_ROCK]])
	runner.assert_true(bool(patch.get("ok", false)), "the intervening cell becomes blocking terrain")
	if bool(patch.get("ok", false)):
		var remaining: int = int(action.due_ms) - GameClock.elapsed_ms
		if remaining > 0:
			GameClock.advance_msec(remaining)
		var record: Dictionary = world.object_lifecycle.actions.get(command, {})
		runner.assert_eq(record.get("status"), "failed", "contact is revalidated at the actual action deadline")
		runner.assert_eq(world.artifacts.objects[id].container, slot, "blocked contact never moves the item into the player's hands")
		runner.assert_eq(world.object_lifecycle.ground.query_cell(start).get("ids"), [slot], "blocked completion keeps the single original floor placement")
	main.free()
	GameClock.restore_state(saved_clock)


func _cleanup_physical_save(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


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
			fog.hidden_cells.erase(other)
			fog.hidden_cells[chosen] = true
			runner.assert_true(view._visible_display_points(authority).has("view_slab"), "a visible second cell keeps the slab visible when its anchor is fogged")
			runner.assert_true(not view._visible_hits(TileGrid.cell_to_world(chosen), authority).has("view_slab") and view._visible_hits(TileGrid.cell_to_world(other), authority).has("view_slab"), "only the visible cell can be selected when the anchor is fogged")
			var fog_view: Dictionary = view._perception("view_slab")
			runner.assert_true(bool(fog_view.get("known", false)) and fog_view.get("cell") == [other.x, other.y] and not bool(fog_view.get("near", true)), "the fogged anchor is not exposed through the partial object view")
			fog.hidden_cells.clear()
			var radius: int = int(authority.regions.home.config.observation_radius)
			fixture.player.spawn_at(other + Vector2i.RIGHT * radius)
			adapter.prepare_player_command()
			runner.assert_true(not authority.artifacts.can_see("player", "view_slab"), "the slab anchor is outside the actual observation radius")
			runner.assert_true(view._visible_display_points(authority).has("view_slab"), "a second cell inside the radius keeps its slab visible")
			runner.assert_true(not view._visible_hits(TileGrid.cell_to_world(chosen), authority).has("view_slab") and view._visible_hits(TileGrid.cell_to_world(other), authority).has("view_slab"), "a cell beyond the radius remains hidden and unselectable")
			var edge_view: Dictionary = view._perception("view_slab")
			runner.assert_true(bool(edge_view.get("known", false)) and edge_view.get("cell") == [other.x, other.y] and not bool(edge_view.get("near", true)), "the partial view references only the cell inside the observation radius")
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
	# The controlled current fixture still performs an actual timed take and
	# consenting handover; no historical snapshot is needed for this regression.
	var fixtures := Fixtures.new()
	var exchange: RefCounted = load("res://tests/runtime/test_private_exchange_runtime.gd").new()
	var fixture: Dictionary = exchange._prepared(runner, fixtures, true)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var fog := MaskFog.new()
	fog.setup(fixture.world, fixture.player.cell)
	fixture.home._fog = fog
	var path: String = _unused_reentrant_path()
	if path.is_empty():
		runner.assert_true(false, "reentrant visibility has an unused save path")
	else:
		_reentrant_current_handover(runner, fixture, path)
	_remove_reentrant(path)
	fixture.home._fog = null
	fog.free()
	fixtures._dispose(fixture)
	load("res://tests/runtime/helpers/legacy_rejection_archive.gd").run(runner, {
		EXCHANGE_ARCHIVE: "e13c2616a25f482db2397b585417d027c2759172393c6929eb98a4713b676ebf",
	})


func _reentrant_current_handover(runner: Object, fixture: Dictionary, path: String) -> void:
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	var subject: String = world.embodiment.subject_for_actor("river_shi_tou")
	var accepted: Dictionary = runtime.interaction_adapter.submit(subject, "private_exchange", {"kind": "private_artifact", "id": RING})
	runner.assert_true(bool(accepted.get("ok", false)) and accepted.get("status") == "started", "current holder accepts a genuine in-flight handover")
	if not bool(accepted.get("ok", false)):
		return
	var buyer: int = world.regions.home.inventory.quantity("actor:player", "coin")
	var available: int = world.regions.home.inventory.available("actor:player", "coin")
	var owner: String = str(world.artifacts.objects[RING].container)
	runner.assert_eq(available, buyer - 4, "the real pending handover reserves the quoted four coins")
	runner.assert_eq(owner, "actor:river_shi_tou", "the genuine pending ring remains with its current holder")
	world = null
	GameClock.set_paused(true)
	var adapter: WorldObjectsRuntime = runtime.object_adapter
	runner.assert_true(runtime._home._fog != null, "visibility includes the following fog cell read")
	var visible_before: bool = adapter._visible(RING)
	runner.assert_true(visible_before, "the original holder and ring are actually visible before interruption")
	var saved: Error = runtime.save_game(path)
	runner.assert_eq(saved, OK, "the current handover is saved for a real reentrant reload")
	if saved != OK or not visible_before or runtime._home._fog == null:
		return
	var expected: String = SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime)))
	var old_id: int = runtime.world_sim.get_instance_id()
	var old_ref: WeakRef = weakref(runtime.world_sim)
	var probe := ReloadDuringVisibility.new()
	var initialized: bool = probe.initialize(runtime.world_sim, runtime._home._content.artifacts)
	var copied: bool = initialized and probe.restore(runtime.world_sim.artifacts.to_dict())
	runner.assert_true(copied, "view probe preserves original artifact state and owner")
	if not copied:
		return
	runtime.world_sim.artifacts = probe
	probe.reload = Callable(runtime, "load_game").bind(path)
	var visible_after: bool = adapter._visible(RING)
	runner.assert_true(probe.fired and probe.load_result == OK, "visibility synchronously commits the independent saved replacement")
	runner.assert_true(runtime.world_sim.get_instance_id() != old_id, "the actual runtime world was replaced during the view call")
	runner.assert_true(probe.post_load_cell_read and probe.owner_at_cell == old_id, "the old artifact owner survives through the subsequent cell lookup")
	runner.assert_true(visible_after, "the interrupted view finishes with the genuinely visible ring")
	runner.assert_true(old_ref.get_ref() == null, "the old world is released after the completed view call")
	runner.assert_eq(runtime.world_sim.regions.home.inventory.quantity("actor:player", "coin"), buyer, "replacement retains original unspent money")
	runner.assert_eq(runtime.world_sim.regions.home.inventory.available("actor:player", "coin"), available, "replacement retains the original reservation")
	runner.assert_eq(runtime.world_sim.artifacts.objects[RING].container, owner, "replacement retains the seller's original ring")
	var after: String = SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime)))
	runner.assert_eq(after, expected, "reentrant presentation and loading preserve the entire saved session")
	# The control deliberately omits the strong world reference and demonstrates
	# the original lifetime bug at exactly the same synchronous reload boundary.
	var control_ref: WeakRef = weakref(runtime.world_sim)
	var control := ReloadDuringVisibility.new()
	var control_ready: bool = control.initialize(runtime.world_sim, runtime._home._content.artifacts) and control.restore(runtime.world_sim.artifacts.to_dict())
	runner.assert_true(control_ready, "control starts from the same original artifact state")
	if not control_ready:
		return
	runtime.world_sim.artifacts = control
	control.reload = Callable(runtime, "load_game").bind(path)
	var loose_result: bool = _visibility_without_world_reference(runtime, RING)
	runner.assert_true(control.fired and control.load_result == OK, "control performs the same synchronous successful reload")
	runner.assert_true(control.post_load_cell_read and control.owner_at_cell == 0, "a loose domain loses its old world before the next cell read")
	runner.assert_true(not loose_result and control_ref.get_ref() == null, "control cannot safely finish after its old owner is released")
	var control_after: String = SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime)))
	runner.assert_eq(control_after, expected, "both interleavings leave the actual replacement snapshot intact")


func _unused_reentrant_path() -> String:
	for attempt: int in 100:
		var path: String = "user://tests/objects_reentrant_%d_%d.json" % [Time.get_ticks_usec(), attempt]
		var occupied: bool = false
		for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
			if FileAccess.file_exists(path + suffix):
				occupied = true
				break
		if not occupied:
			return path
	return ""


func _remove_reentrant(path: String) -> void:
	if path.is_empty():
		return
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _visibility_without_world_reference(runtime: WorldContinuityRuntime, id: String) -> bool:
	var domain: SimArtifacts = runtime.world_sim.artifacts
	return domain.can_see("player", id) and (runtime._home._fog == null or runtime._home._fog.is_cell_visible(domain.object_cell(id)))
