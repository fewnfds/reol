extends RefCounted
## Controlled geometry probes, not the ordinary field-adventure playthrough.
## Original body owners remain intact; only candidate attacks forge a route.

const Fixtures = preload("res://tests/runtime/test_conflict_runtime.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	var fixture: Dictionary = _fixtures._scene(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.runtime
	var main: Node = fixture.main
	runner.assert_true(runtime.avatar_adapter.choose("subject:player"), "view probe chooses the actual original human life")
	var world: RegionalSimulation = runtime.world_sim
	var fields: SimFieldOpportunities = world.field_opportunities
	var id: String = str(fields.definitions.site.id)
	runner.assert_true(fields.sites.has(id), "main scene explicitly opts into the original field opening")
	if not fields.sites.has(id):
		_fixtures._dispose(fixture)
		return
	var unknown: Dictionary = WorldSessionSnapshot.capture(runtime)
	var world_before: String = _canonical(world.to_dict())
	runner.assert_true(fields.known_sites("player").is_empty(), "an opening player's notes do not automatically inherit another person's clue")
	runtime.field_adapter.show_panel()
	runner.assert_eq(runtime.field_adapter.site_choice.item_count, 0, "the field page exposes no destination option before personal knowledge")
	runtime.field_adapter.refresh()
	runner.assert_eq(_canonical(world.to_dict()), world_before, "opening and refreshing a field page generates no clue, item, process or resource")
	runtime.field_adapter.panel.hide()
	runner.assert_true(not runtime.travel_to_site(id), "a raw existing site identifier cannot order an unknown journey")
	runner.assert_true(not runtime.travel_to("site:" + id, runtime.centers.home), "site routing rejects caller-supplied coordinate overrides")
	runner.assert_true(runtime.player_journey.is_empty(), "unknown and overridden site commands create no partial player route")
	var site_cell: Vector2i = SimRouteTravel.cell(fields.sites[id].cell)
	var site_point: Vector2 = TileGrid.cell_to_world(site_cell)
	# Deliberate initial view-probe placement. This test is about projection
	# ownership/FOW/selection; the ordinary timed expedition is tested elsewhere.
	main.player.motion.relocate(site_point)
	main.player._project_motion()
	world.regions.home.set_actor_position("chen_shouzhuo", site_point)
	world.regions.river.set_actor_position("river_shi_tou", site_point)
	world.invalidate_region("home")
	world.invalidate_region("river")
	main.fog.set_focus(site_cell)
	main.fog.update_now()
	runtime._update_region()
	runtime.home_runtime()._sync_actor_views(true)
	runtime._refresh_views(true)
	main._process(0.0)
	runner.assert_eq(runtime.current_region, "", "the actual landmark is outside both settlement presentation radii")
	runner.assert_eq(runtime.actor_region("chen_shouzhuo"), "home", "the original home actor retains its persistent owner at the field location")
	runner.assert_eq(runtime.actor_region("river_shi_tou"), "river", "the original foreign actor retains its different persistent owner at the same field location")
	var home_view: Pawn = runtime.actor_view("chen_shouzhuo")
	var foreign_view: Pawn = runtime.actor_view("river_shi_tou")
	runner.assert_true(is_instance_valid(home_view) and home_view.visible, "an original home actor is actually visible outside its own settlement")
	runner.assert_true(is_instance_valid(foreign_view) and foreign_view.visible, "an original river actor is materialized by physical sight outside river presentation")
	if not is_instance_valid(home_view) or not is_instance_valid(foreign_view):
		_fixtures._dispose(fixture)
		return
	runner.assert_true(not home_view.selection_center().is_equal_approx(foreign_view.selection_center()), "one global crowd layout separates original actors from different owners sharing one cell")
	main._select_at(foreign_view.selection_center())
	runner.assert_eq(runtime._selected_remote, "river_shi_tou", "ordinary field click selects the actual foreign original body")
	runner.assert_eq(fixture.ui.selected_target(), "river_shi_tou", "combat target routing follows the physically selected body rather than current region")
	runner.assert_eq(runtime.visible_actor_status("river_shi_tou"), world.regions.river.actor_status("river_shi_tou"), "visible status is read from the selected actor's real owner")
	main._select_at(home_view.selection_center())
	runner.assert_eq(runtime._selected_remote, "", "selecting an original home actor clears the stale foreign selection")
	runner.assert_eq(fixture.ui.selected_target(), "chen_shouzhuo", "subsequent combat input resolves the newly selected home actor")
	var receivers: Array[Dictionary] = runtime.interaction_adapter.receivers()
	var actual_subjects: Array[String] = []
	for receiver: Dictionary in receivers:
		actual_subjects.append(str(receiver.key))
	runner.assert_true(actual_subjects.has(world.embodiment.subject_for_actor("chen_shouzhuo")) and actual_subjects.has(world.embodiment.subject_for_actor("river_shi_tou")), "C and the visible world agree on both physically present actors despite different original ledgers")
	var observed: Dictionary = fields.observe_site("player", id)
	runner.assert_true(observed.ok and not fields.destination("player", id).is_empty(), "actually looking from the original body at the same-height visible landmark grants a sourced personal destination")
	var forged: Dictionary = unknown.duplicate(true)
	var path: Array[Vector2i] = runtime._find_path(SimRouteTravel.cell(forged.player.cell), site_cell)
	runner.assert_true(not path.is_empty(), "the adversarial journey has a genuinely navigable ordinary terrain route")
	if not path.is_empty():
		var encoded: Array = []
		for cell: Vector2i in path:
			if cell != SimRouteTravel.cell(forged.player.cell):
				encoded.append([cell.x, cell.y])
		var journey: Dictionary = {"destination": "site:" + id, "path": encoded, "due_ms": int(forged.clock.elapsed_ms) + 1, "segment_started_ms": int(forged.clock.elapsed_ms), "segment_from": forged.player.position.duplicate()}
		SimRouteTravel.begin_segment(journey, forged.simulation.actors.player, int(forged.clock.elapsed_ms), float(main.player.motion.rules.motion.speed))
		forged.continuity.player_journey = journey
		var live_before: String = _canonical(WorldSessionSnapshot.capture(runtime))
		runner.assert_true(WorldSessionSnapshot.stage(runtime, forged).is_empty(), "a candidate with no personal clue cannot borrow the live session's later knowledge to authorize a site journey")
		runner.assert_eq(_canonical(WorldSessionSnapshot.capture(runtime)), live_before, "rejected site knowledge attack changes no live clock, original body, view, clue or item")
	# A paused observer/fog update must retire the foreign view immediately,
	# without relying on another simulation tick or changing its original body.
	main._select_at(foreign_view.selection_center())
	var foreign_position: Array = world.regions.river.actors.river_shi_tou.position.duplicate()
	main.player.motion.relocate(TileGrid.cell_to_world(runtime.centers.home))
	main.player._project_motion()
	main.fog.set_focus(main.player.cell)
	main.fog.update_now()
	main._process(0.0)
	runner.assert_true(not runtime._remote_views.has("river_shi_tou") and runtime._selected_remote.is_empty(), "paused FOW refresh removes the unseen foreign projection and stale selection immediately")
	runner.assert_eq(world.regions.river.actors.river_shi_tou.position, foreign_position, "unloading a field view never moves or resets the original hidden actor")
	main.player.motion.relocate(site_point)
	main.player._project_motion()
	world.regions.river.actors.river_shi_tou.alive = false
	world.regions.home.actors.chen_shouzhuo.alive = false
	main.fog.set_focus(site_cell)
	main.fog.update_now()
	runtime.home_runtime()._sync_actor_views(true)
	main._process(0.0)
	runner.assert_true(not runtime._remote_views.has("river_shi_tou") and not home_view.visible, "a visible cell cannot materialize either owner's dead body as a living pawn")
	world.regions.river.actors.river_shi_tou.alive = true
	world.regions.home.actors.chen_shouzhuo.alive = true
	_fixtures._dispose(fixture)
	print("SCENARIO field views: unknown destination privacy, original home/river bodies outside both settlements, global crowd layout, actual click/C/owner coherence, candidate-own knowledge and paused FOW retirement")


func _canonical(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
