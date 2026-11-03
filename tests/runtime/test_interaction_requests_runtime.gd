extends RefCounted

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")


func run(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = fixtures._fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var adapter: InteractionRequestsRuntime = runtime.interaction_adapter
	var world: RegionalSimulation = runtime.world_sim
	var cell: Vector2i = world.artifacts.object_cell("hearth_stone")
	fixture.player.spawn_at(cell)
	for sim: VillageSimulation in world.regions.values():
		for actor: String in sim.actors:
			sim.cancel_action(actor, "fixture_setup")
			sim.actors[actor].autonomous = false
	world.regions.home.set_actor_cell("su_zhi", cell)
	runtime.prepare_player_command()
	var before: String = _canonical(runtime)
	adapter.show_panel()
	runner.assert_true(adapter.panel.visible, "human has a model-free structured request panel")
	runner.assert_eq(adapter.verb_choice.item_count, runtime._home._content.interaction_requests.verbs.size(), "menu includes public request vocabulary without revealing target's hidden abilities")
	runner.assert_true(_has_key(adapter.receivers(), "subject:su_zhi"), "actual nearby person appears among receivers")
	runner.assert_true(_has_key(adapter.objects_for("examine"), {"kind": "artifact", "id": "hearth_stone"}), "visible artifact is addressed by its original reference")
	adapter.rebuild_choices()
	runner.assert_eq(_canonical(runtime), before, "opening and refreshing choices grants no knowledge or changes a domain")
	runner.assert_true(fixture.player.request_sidestep(Vector2.RIGHT), "real short motion starts before a busy request")
	runner.assert_eq(adapter.submit("subject:su_zhi", "examine", {"kind": "artifact", "id": "hearth_stone"}).status, "unavailable", "short motion cannot be bypassed by a panel request")
	runner.assert_true(str(adapter._reply.text).contains("先停稳"), "busy panel request gives visible feedback")
	fixture.player.motion.cancel("fixture_setup")
	var reply: Dictionary = adapter.submit("subject:su_zhi", "examine", {"kind": "artifact", "id": "hearth_stone"})
	runner.assert_eq(reply.status, "started", "UI intent starts the original timed inspection")
	if not bool(reply.ok):
		fixtures._dispose(fixture)
		return
	runner.assert_true(not str(adapter._progress.text).contains("细裂"), "pending panel cannot reveal a future conclusion")
	GameClock.advance_msec(10050)
	var path: String = "user://tests/interaction_requests_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "existing joint save captures the pending domain action")
	GameClock.advance_msec(110000)
	var future: String = _canonical(runtime)
	runner.assert_eq(SimInteractionRequests.observe(runtime.world_sim, runtime.avatar_subject, reply.process).status, "completed", "actual elapsed action supplies an attributed response")
	runner.assert_eq(runtime.load_game(path), OK, "ordinary load validates all prior domains without a new request schema")
	runner.assert_true(adapter._receipt.is_empty() and not adapter.panel.visible, "load discards only stale UI receipt and future text")
	adapter.show_panel()
	runner.assert_eq(adapter._receipt, reply.process, "reopening reconstructs the request from original pending participants")
	GameClock.advance_msec(110000)
	runner.assert_eq(_canonical(runtime), future, "UI reconstruction cannot reroll or duplicate the saved process")
	runner.assert_true(str(adapter._progress.text).contains("苏芷") and str(adapter._progress.text).contains("细裂"), "panel presents the heard conclusion after real completion")
	world = runtime.world_sim
	var point: Vector2 = TileGrid.cell_to_world(cell)
	world.avian_life.birds.moss_sparrow.position = [point.x, point.y]
	reply = adapter.submit("subject:avian:moss_sparrow", "examine", {"kind": "artifact", "id": "hearth_stone"})
	runner.assert_eq(reply.status, "not_understood", "same UI lets a bird fail to understand an identification request")
	runner.assert_true(not world.artifacts.active.has("moss_sparrow"), "UI does not manufacture a human examiner from a bird")
	world.regions.home.set_actor_cell("su_zhi", cell + Vector2i(20, 20))
	adapter.rebuild_choices()
	runner.assert_true(not _has_key(adapter.receivers(), "subject:su_zhi"), "distant person disappears from currently visible choices")
	runner.assert_eq(adapter.submit("subject:su_zhi", "examine", {"kind": "artifact", "id": "hearth_stone"}).status, "unheard", "stale selection does not summon a remote NPC")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	fixtures._dispose(fixture)
	print("SCENARIO request UI: visible receiver/action/object/medium, original costs and private result, same joint-save future")


func _has_key(rows: Array[Dictionary], key: Variant) -> bool:
	for row: Dictionary in rows:
		if row.key == key:
			return true
	return false


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(WorldSessionSnapshot.capture(runtime)), "", true, true)
