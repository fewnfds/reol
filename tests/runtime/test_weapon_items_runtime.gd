extends RefCounted
## Real custody UI, authorized senses and continuous holder presentation.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const SWORD: String = "training_sword"
var _fixtures := Fixtures.new()


class ControlledFog extends FogOfWar:
	var showing: bool = true


	func is_cell_visible(_cell: Vector2i) -> bool:
		return showing


class RaisedMap extends WorldMapData:
	func get_elevation(_cell: Vector2i) -> int:
		return 2


class OneCellSightBarrier extends WorldMapData:
	var blocked_cell: Vector2i

	func get_elevation(_cell: Vector2i) -> int:
		return 0

	func get_terrain(cell: Vector2i) -> int:
		return TERRAIN_ROCK if cell == blocked_cell else TERRAIN_GRASS


func run(runner: Object) -> void:
	_handling_and_joint_resume(runner)
	_holder_views(runner)
	_regional_approach(runner)
	_limited_observation(runner)
	_hidden_peer_layout(runner)
	_carried_stack_hits(runner)
	_pointer_input(runner)
	print("SCENARIO weapon UI: configured nonthermal verbs, actual take/place and joint resume, interpolated holders, limited memory and transformed pointer selection")


func _fixture(runner: Object, opening_field: bool = false) -> Dictionary:
	var fixture: Dictionary = _fixtures._fixture(runner, {}, true, opening_field)
	if fixture.is_empty():
		return fixture
	var runtime: WorldContinuityRuntime = fixture.continuity
	# Workplaces enable the same training sword assembled by the ordinary Main
	# before activation of the environment field and its original source index.
	if not runtime.world_sim.artifacts.objects.has(SWORD):
		runner.assert_true(false, "ordinary opening assembles its training sword")
		_fixtures._dispose(fixture)
		return {}
	fixture.player.spawn_at(SimRouteTravel.cell(fixture.home.simulation.places.dorm.cell))
	runtime.prepare_player_command()
	return fixture


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(runtime.world_sim.to_dict()))


func _thermal_hidden(runner: Object, panel: ObjectInspectionPanel, context: String) -> void:
	for verb: String in ["heat", "charge", "dry", "force", "warm", "methods", "to_garden", "spirit_source"]:
		runner.assert_true(not panel._buttons[verb].visible, context + " hides unsupported thermal action: " + verb)


func _finish(runner: Object, runtime: WorldContinuityRuntime) -> bool:
	if not runtime.world_sim.artifacts.active.has("player"):
		runner.assert_true(false, "the expected player artifact action is active before completion")
		return false
	GameClock.advance_msec(int(runtime.world_sim.artifacts.active.player.due_ms) - GameClock.elapsed_ms)
	return true


func _discard_save(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _handling_and_joint_resume(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var adapter: WorldObjectsRuntime = runtime.object_adapter
	var before: String = _canonical(runtime)
	runner.assert_true(adapter.select_object(SWORD), "nearby wooden sword opens the existing real inspector")
	runner.assert_true(adapter.panel._buttons.take.visible and adapter.panel._buttons.study.visible and adapter.panel._buttons.examine.visible, "wooden sword exposes its configured handling operations")
	runner.assert_eq(adapter.panel._buttons.study.text, "熟悉握持与收放", "the selected object's own action supplies its button label")
	runner.assert_true(adapter.panel._buttons.study.tooltip_text.contains("需2分钟") and adapter.panel._buttons.examine.tooltip_text.contains("需1分钟"), "tooltips use the sword's actual duration rather than stone timings")
	adapter.panel.set_source_entry(true)
	_thermal_hidden(runner, adapter.panel, "unfamiliar sword")
	adapter.refresh()
	runner.assert_eq(_canonical(runtime), before, "object selection and presentation manufacture no real resources or knowledge")
	runner.assert_true(adapter.submit("take").ok, "ordinary inspector commits a real timed take for the unique sword")
	before = _canonical(runtime)
	for verb: String in ["methods", "spirit_source", "to_garden", "charge", "warm", "force"]:
		runner.assert_true(not adapter.submit(verb).ok, "raw thermal request cannot bypass the selected tool's affordance: " + verb)
	runner.assert_eq(_canonical(runtime), before, "unsupported raw requests neither spend qi nor interrupt the in-progress take")
	if not _finish(runner, runtime):
		_fixtures._dispose(fixture)
		return
	runner.assert_eq(runtime.world_sim.artifacts.held_weapon("player"), SWORD, "finished take transfers the same actual instance to the player's custody")
	runner.assert_true(adapter.panel._buttons.place.visible and not adapter.panel._buttons.take.visible, "custody changes the actual available take/place controls")
	runner.assert_true(adapter.submit("study").ok, "inspector can commit deliberate nonthermal tool familiarization")
	GameClock.advance_msec(617)
	var path: String = "user://tests/weapon_runtime_%d.json" % Time.get_ticks_usec()
	var saved: Error = runtime.save_game(path)
	runner.assert_eq(saved, OK, "unfinished sword handling saves through the ordinary joint world snapshot")
	if saved != OK:
		_discard_save(path)
		_fixtures._dispose(fixture)
		return
	before = _canonical(runtime)
	if not _finish(runner, runtime):
		_discard_save(path)
		_fixtures._dispose(fixture)
		return
	var future: String = _canonical(runtime)
	var loaded: Error = runtime.load_game(path)
	runner.assert_eq(loaded, OK, "ordinary load restores the pending tool action and original custody")
	if loaded != OK:
		_discard_save(path)
		_fixtures._dispose(fixture)
		return
	runner.assert_eq(_canonical(runtime), before, "tool UI does not lose the actual pending action during restore")
	if not _finish(runner, runtime):
		_discard_save(path)
		_fixtures._dispose(fixture)
		return
	runner.assert_eq(_canonical(runtime), future, "loaded joint world reaches the identical real tool future")
	runner.assert_true(adapter.select_object(SWORD), "restored familiar sword can reopen in the same inspector")
	runner.assert_true(runtime.world_sim.artifacts.describe("player", SWORD).method, "actual completed familiarization is known to its operator")
	_thermal_hidden(runner, adapter.panel, "familiar sword")
	runner.assert_true(adapter.submit("place").ok, "ordinary place control commits actual placement at the sword's storage place")
	if not _finish(runner, runtime):
		_discard_save(path)
		_fixtures._dispose(fixture)
		return
	runner.assert_eq(runtime.world_sim.artifacts.objects[SWORD].container, "dorm", "sword returns to its configured room rather than a hard-coded kitchen")
	_discard_save(path)
	_fixtures._dispose(fixture)


func _holder_views(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var domain: SimArtifacts = runtime.world_sim.artifacts
	var adapter: WorldObjectsRuntime = runtime.object_adapter
	fixture.world.bind_map_data(RaisedMap.new())
	domain.objects[SWORD].container = "actor:player"
	fixture.player.global_position += Vector2(7.25, -3.5)
	fixture.player.altitude = 1
	var offset := Vector2(20, -24 - 2 * ReolWorld.ELEVATION_PX - ReolWorld.ALTITUDE_PX)
	runner.assert_true(adapter._display_point(SWORD).is_equal_approx(fixture.player.global_position + offset), "carried sword follows the player's continuous point and both terrain and flight heights")
	domain.objects[SWORD].container = "actor:chen_shouzhuo"
	var pawn: Pawn = fixture.home._pawns.chen_shouzhuo
	pawn.global_position += Vector2(6.75, 4.25)
	pawn.visual_offset = Vector2(-5, 3)
	offset = Vector2(20, -24 - 2 * ReolWorld.ELEVATION_PX)
	runner.assert_true(adapter._display_point(SWORD).is_equal_approx(pawn.global_position + pawn.visual_offset + offset), "NPC-held sword follows its interpolated view and crowd offset without inheriting player flight")
	runtime.current_region = "river"
	runtime._refresh_views(true)
	runner.assert_true(not runtime._remote_views.has("river_chen_shouzhuo"), "changing the region label alone does not reveal the distant holder")
	# This is a presentation fixture with a synthetic elevation map, not a
	# travel test. Place the original player body by the remote holder so the
	# no-Fog fallback creates the view from actual physical proximity.
	var remote_body: Dictionary = runtime.world_sim.regions.river.actors.river_chen_shouzhuo
	fixture.player.altitude = 0
	fixture.player.spawn_at(SimRouteTravel.cell(remote_body.cell))
	runtime.prepare_player_command()
	runtime._refresh_views(true)
	runner.assert_true(runtime._remote_views.has("river_chen_shouzhuo"), "physically approaching the remote holder materializes its view")
	if not runtime._remote_views.has("river_chen_shouzhuo"):
		_fixtures._dispose(fixture)
		return
	# The ordinary workplace opening also gives this resident a sword. Keep
	# that existing carried object with another resident in this controlled
	# presentation fixture so the tested holder has a single display marker.
	if domain.objects.has("river_training_sword"):
		domain.objects.river_training_sword.container = "actor:river_shi_tou"
	domain.objects[SWORD].region = "river"
	domain.objects[SWORD].container = "actor:river_chen_shouzhuo"
	var remote: Pawn = runtime._remote_views.river_chen_shouzhuo
	remote.global_position += Vector2(-3.25, 8.5)
	remote.visual_offset = Vector2(4, -2)
	runner.assert_true(adapter._display_point(SWORD).is_equal_approx(remote.global_position + remote.visual_offset + offset), "river-held sword uses the remote resident's actual nearby view")
	remote.free()
	runtime._remote_views.erase("river_chen_shouzhuo")
	var actual: Vector2 = SimRouteTravel.point(runtime.world_sim.regions.river.actors.river_chen_shouzhuo)
	runner.assert_true(adapter._display_point(SWORD).is_equal_approx(actual + offset), "uninstantiated holder fallback uses the original body's continuous position")
	_fixtures._dispose(fixture)


func _limited_observation(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var adapter: WorldObjectsRuntime = runtime.object_adapter
	var domain: SimArtifacts = runtime.world_sim.artifacts
	var fog := ControlledFog.new()
	fog.showing = false
	fixture.home._fog = fog
	var before: String = _canonical(runtime)
	runner.assert_true(domain.can_see("player", SWORD), "hidden sword fixture is physically close enough for the old distance-only test")
	runner.assert_true(not adapter.select_object(SWORD) and not adapter._visible(SWORD), "fog prevents discovering a physically close but unseen unknown sword")
	runner.assert_eq(_canonical(runtime), before, "rejected hidden selection grants no personal record")
	fog.showing = true
	runner.assert_true(adapter.select_object(SWORD) and adapter.submit("inspect").ok, "physical observation can create a genuine paid record")
	if not _finish(runner, runtime):
		fixture.home._fog = null
		fog.free()
		_fixtures._dispose(fixture)
		return
	var remembered: Array = domain.events.back().cell.duplicate()
	domain.objects[SWORD].container = "garden"
	fog.showing = false
	adapter.refresh()
	var memory: Dictionary = adapter._perception(SWORD)
	runner.assert_true(memory.known and not memory.near and not memory.held, "departed known tool offers memory rather than live proximity or custody")
	runner.assert_eq(memory.cell, remembered, "memory retains the last personally known location after an unseen move")
	runner.assert_true(memory.cell != [domain.object_cell(SWORD).x, domain.object_cell(SWORD).y], "the new hidden actual location cannot leak into the inspection projection")
	runner.assert_true(str(memory.line).contains("上次留下的记录"), "open object panel identifies remembered information as an old record")
	before = _canonical(runtime)
	runner.assert_true(not adapter.submit("inspect").ok, "raw object request cannot act through a memory-only inspection")
	runner.assert_eq(_canonical(runtime), before, "memory-only raw refusal cannot start work or acquire knowledge")
	runtime.avatar_subject = "subject:soul:yan_heng"
	runtime.avatar_changed.emit()
	runner.assert_true(not adapter.panel.visible and not adapter.select_object(SWORD), "soul embodiment cannot retain the previous body's object inspector or senses")
	runner.assert_true(not adapter._perception(SWORD).get("known", false), "direct object projection also respects the active embodiment's sense boundary")
	fixture.home._fog = null
	fog.free()
	_fixtures._dispose(fixture)


func _regional_approach(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var domain: SimArtifacts = runtime.world_sim.artifacts
	domain.objects[SWORD].region = "river"
	var target: Vector2i = domain.object_cell(SWORD)
	fixture.player.spawn_at(target + Vector2i(3, 0))
	runtime.prepare_player_command()
	var adapter: WorldObjectsRuntime = runtime.object_adapter
	runner.assert_true(adapter.select_object(SWORD), "visible remote-region tool can open from its actual nearby location")
	runner.assert_true(adapter.submit("approach").ok, "tool inspector can begin an actual approach in the other settlement")
	runner.assert_eq(runtime.player_journey.get("destination"), "river", "approach records the object's own region rather than a fixed home region")
	runner.assert_eq(runtime.player_journey.get("target"), [target.x, target.y], "regional approach uses the observed object's actual target cell")
	_fixtures._dispose(fixture)


func _hidden_peer_layout(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner, true)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var adapter: WorldObjectsRuntime = runtime.object_adapter
	var domain: SimArtifacts = runtime.world_sim.artifacts
	var world: RegionalSimulation = runtime.world_sim
	var ring_id: String = "stele_drawing_ring"
	var carrier: String = "chen_shouzhuo"
	if not domain.objects.has(ring_id):
		runner.assert_true(false, "ordinary field opening assembles its original ring")
		_fixtures._dispose(fixture)
		return
	# Bring the original opening ring to the shared cell through its real timed
	# take. Carrying it keeps its environment source correctly absent while the
	# controlled holder is positioned for this presentation-only layout test.
	for sim: VillageSimulation in world.regions.values():
		for actor: String in sim.actors:
			sim.cancel_action(actor, "fixture_setup")
			sim.actors[actor].autonomous = false
	world.regions.home.set_actor_cell(carrier, domain.object_cell(ring_id))
	world.invalidate_region("home")
	world.invalidate_region("river")
	var take: Dictionary = domain.begin(carrier, "take", ring_id)
	runner.assert_true(take.ok, "the original ring can be taken for the hidden peer fixture")
	if not take.ok:
		_fixtures._dispose(fixture)
		return
	GameClock.advance_msec(int(domain.active[carrier].due_ms) - GameClock.elapsed_ms)
	runner.assert_eq(domain.objects[ring_id].container, "actor:" + carrier, "the hidden peer remains the original ring in real custody")
	if domain.objects[ring_id].container != "actor:" + carrier:
		_fixtures._dispose(fixture)
		return
	var target: Vector2i = domain.object_cell(SWORD)
	world.regions.home.set_actor_cell(carrier, target)
	world.invalidate_region("home")
	var holder: Pawn = fixture.home._pawns[carrier]
	holder.global_position = TileGrid.cell_to_world(target)
	holder.visual_offset = Vector2.ZERO
	var standing: Vector2i = target + Vector2i.RIGHT * 2
	var map := OneCellSightBarrier.new()
	map.blocked_cell = target + Vector2i.RIGHT
	fixture.world.bind_map_data(map)
	runtime.world_sim.map_data = map
	fixture.player.spawn_at(standing)
	runtime.prepare_player_command()
	runner.assert_true(domain.object_cell(ring_id) == target, "the hidden ring and visible sword occupy the same actual cell")
	runner.assert_true(adapter._base_display_point(ring_id, world).is_equal_approx(adapter._base_display_point(SWORD, world)), "the hidden ring and visible sword share the same visual anchor")
	runner.assert_true(adapter._visible(SWORD) and adapter._visible("amber_pearl"), "ordinary co-located objects remain visible")
	runner.assert_true(not adapter._visible(ring_id), "the ring's genuine sight requirement fails at the blocking cell")
	var before: String = _canonical(runtime)
	var sword_with_hidden: Vector2 = adapter._display_point(SWORD)
	var pearl_with_hidden: Vector2 = adapter._display_point("amber_pearl")
	runner.assert_eq(_canonical(runtime), before, "laying out visible and hidden objects changes no real world state")
	var shared_hit: Vector2 = (sword_with_hidden + pearl_with_hidden) * 0.5
	runner.assert_true(adapter.select_object(SWORD, shared_hit), "a visible object may retain its pointer location for the inspector")
	adapter.panel._cycle.pressed.emit()
	runner.assert_eq(adapter.selected_object, "amber_pearl", "cycle button signal uses visible hits and excludes the unseen ring")
	runner.assert_eq(_canonical(runtime), before, "cycling past the unseen peer does not discover it or change world state")
	world.regions.home.set_actor_cell(carrier, target + Vector2i(10, 10))
	world.invalidate_region("home")
	holder.global_position = TileGrid.cell_to_world(target + Vector2i(10, 10))
	before = _canonical(runtime)
	runner.assert_true(adapter._display_point(SWORD).is_equal_approx(sword_with_hidden), "moving an unseen co-located ring away does not move the visible sword")
	runner.assert_true(adapter._display_point("amber_pearl").is_equal_approx(pearl_with_hidden), "moving an unseen co-located ring away does not move the visible pearl")
	runner.assert_eq(_canonical(runtime), before, "recomputing the layout without the unseen ring changes no real world state")
	_fixtures._dispose(fixture)


func _carried_stack_hits(runner: Object) -> void:
	var fixture: Dictionary = _fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var adapter: WorldObjectsRuntime = runtime.object_adapter
	var domain: SimArtifacts = runtime.world_sim.artifacts
	# Arrange the original carrier at a continuous subcell position. The two
	# held markers share a base anchor; the lower rank then overlaps the real
	# stationary warm stone at the kitchen without sharing its container.
	# The ordinary fixture is intentionally detached; input needs an actual
	# viewport and canvas transform, so attach just this adapter for its clicks.
	var parent: Node = adapter.get_parent()
	if parent != null:
		parent.remove_child(adapter)
	runner.root.add_child(adapter)
	domain.objects[SWORD].container = "actor:player"
	domain.objects.amber_pearl.container = "actor:player"
	var kitchen: Vector2i = domain.object_cell("hearth_stone")
	fixture.player.spawn_at(kitchen)
	fixture.player.global_position += Vector2(0, 16)
	runtime.prepare_player_command()
	var pearl: Vector2 = adapter._display_point("amber_pearl")
	var stone: Vector2 = adapter._display_point("hearth_stone")
	runner.assert_true(pearl.is_equal_approx(stone), "a real held stack marker can overlap a stationary object's final marker")
	var before: String = _canonical(runtime)
	var old_canvas: Transform2D = runner.root.canvas_transform
	runner.root.canvas_transform = Transform2D(0.0, runner.root.get_visible_rect().get_center() - stone)
	var object_point: Vector2 = adapter.get_canvas_transform() * stone
	adapter.reset_observation()
	_viewport_click(runner.root, object_point)
	runner.assert_eq(adapter.selected_object, "amber_pearl", "viewport mouse dispatch selects the first overlapping marker")
	runner.assert_true(adapter.panel.visible and adapter.panel._cycle.visible, "pointer selection opens the real inspector and its cycle control")
	var button: Button = adapter.panel._cycle
	# This runner is synchronous and cannot wait for deferred GUI layout. Test
	# the connected component here; the asynchronous native QA dispatches real
	# viewport clicks after layout and checks the obstruction regression.
	runner.assert_true(button.is_visible_in_tree(), "pointer inspection exposes the cycle component")
	if button.is_visible_in_tree():
		for expected: String in ["hearth_stone", "amber_pearl"]:
			button.pressed.emit()
			runner.assert_eq(adapter.selected_object, expected, "cycle component reaches each overlapping visible object")
			runner.assert_eq(_canonical(runtime), before, "cycle component changes no bodies, custody, time, costs or knowledge")
		# A previously selected candidate may move away while the panel is open.
		domain.objects.amber_pearl.container = "dorm"
		runner.assert_true(not adapter._visible("amber_pearl") or adapter._display_point("amber_pearl").distance_to(stone) > 22.0, "the old selection has left the clicked hit area")
		before = _canonical(runtime)
		button.pressed.emit()
		runner.assert_eq(adapter.selected_object, "hearth_stone", "cycle recomputes the current visible hit area after an object moves")
		runner.assert_eq(_canonical(runtime), before, "recomputing after a move changes no world state")
		var fog := ControlledFog.new()
		fixture.home._fog = fog
		fog.showing = false
		button.pressed.emit()
		runner.assert_eq(adapter.selected_object, "hearth_stone", "no currently visible hit leaves the current selection unchanged")
		fog.showing = true
		domain.objects.erase("hearth_stone")
		button.pressed.emit()
		runner.assert_eq(adapter.selected_object, SWORD, "a deleted selection safely cycles to the remaining visible hit")
		fixture.home._fog = null
		fog.free()
	runner.root.canvas_transform = old_canvas
	runner.root.remove_child(adapter)
	if parent != null:
		parent.add_child(adapter)
	_fixtures._dispose(fixture)


func _viewport_click(viewport: Viewport, at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	viewport.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = at
	press.global_position = at
	press.pressed = true
	viewport.push_input(press, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = at
	release.global_position = at
	release.pressed = false
	viewport.push_input(release, true)


func _pointer_input(runner: Object) -> void:
	var saved_clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var adapter: WorldObjectsRuntime = runtime.object_adapter
	var target_id: String = SWORD
	if not runtime.world_sim.artifacts.objects.has(target_id):
		runner.assert_true(false, "ordinary Main opens with its original training sword")
		main.free()
		GameClock.restore_state(saved_clock)
		return
	var target: Vector2i = runtime.world_sim.artifacts.object_cell(target_id)
	main.player.spawn_at(target)
	runtime.prepare_player_command()
	main.fog.set_focus(target)
	main.fog.update_now()
	main.camera.zoom = Vector2(1.3, 1.3)
	main.camera.global_position = main.player.global_position + Vector2(91, -57)
	main.camera.force_update_scroll()
	var domain: SimArtifacts = runtime.world_sim.artifacts
	var pearl_id: String = "amber_pearl"
	runner.assert_true(domain.objects.has(pearl_id), "ordinary opening contains the co-located glowing pearl")
	if not domain.objects.has(pearl_id):
		main.free()
		GameClock.restore_state(saved_clock)
		return
	runner.assert_true(domain.object_cell(target_id) == domain.object_cell(pearl_id), "the actual sword and pearl share the original physical cell")
	runner.assert_true(adapter._visible(target_id) and adapter._visible(pearl_id), "both co-located opening objects are currently visible")
	var sword_point: Vector2 = adapter._display_point(target_id)
	var pearl_point: Vector2 = adapter._display_point(pearl_id)
	runner.assert_true(not sword_point.is_equal_approx(pearl_point), "visible co-located objects have distinct rendered and selectable points")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var before: String = _canonical(runtime)
	for id: String in [target_id, pearl_id]:
		adapter.reset_observation()
		click.position = adapter.get_canvas_transform() * adapter._display_point(id)
		adapter._unhandled_input(click)
		runner.assert_eq(adapter.selected_object, id, "transformed left-click selects the correct co-located visible object: " + id)
		runner.assert_true(adapter.panel.visible, "the co-located object click opens the real inspector: " + id)
		runner.assert_eq(_canonical(runtime), before, "pointer selection changes no world time, custody, resources or personal knowledge: " + id)
	adapter.reset_observation()
	click.position = adapter.get_canvas_transform() * sword_point
	click.pressed = false
	adapter._unhandled_input(click)
	runner.assert_true(not adapter.panel.visible, "mouse release cannot reopen the object inspector")
	var fire_id: String = "fire_stone"
	var cold_id: String = "cold_stone"
	runner.assert_true(domain.objects.has(fire_id) and domain.objects.has(cold_id), "ordinary opening contains both real thermal devices")
	if domain.objects.has(fire_id) and domain.objects.has(cold_id):
		var kitchen: Vector2i = domain.object_cell(fire_id)
		runner.assert_eq(domain.object_cell(cold_id), kitchen, "both thermal modes share the original kitchen anchor")
		main.player.spawn_at(kitchen)
		runtime.prepare_player_command()
		main.fog.set_focus(kitchen)
		main.fog.update_now()
		runner.assert_true(adapter._visible(fire_id) and adapter._visible(cold_id), "both thermal devices are visible from their actual kitchen")
		runner.assert_true(not adapter._display_point(fire_id).is_equal_approx(adapter._display_point(cold_id)), "original emit and absorb devices retain distinct presentation points")
		before = _canonical(runtime)
		click.pressed = true
		for id: String in [fire_id, cold_id]:
			adapter.reset_observation()
			click.position = adapter.get_canvas_transform() * adapter._display_point(id)
			adapter._unhandled_input(click)
			runner.assert_eq(adapter.selected_object, id, "transformed click selects the correct thermal device: " + id)
			runner.assert_eq(_canonical(runtime), before, "thermal pointer selection changes no original device or world state: " + id)
		main.player.spawn_at(target)
		runtime.prepare_player_command()
		main.fog.set_focus(target)
		main.fog.update_now()
		adapter.reset_observation()
	runtime.world_sim.artifacts.objects.hearth_stone.container = "dorm"
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_I
	adapter._unhandled_input(key)
	runner.assert_eq(adapter.selected_object, "hearth_stone", "I retains the known thermal-object default while wooden swords remain directly clickable")
	main.free()
	GameClock.restore_state(saved_clock)
