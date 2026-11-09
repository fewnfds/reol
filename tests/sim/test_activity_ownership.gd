extends RefCounted
## Activity queries read original process owners; they never reserve a body.

const Support = preload("res://tests/sim/spirit_source_test_support.gd")
const SparringFixture = preload("res://tests/sim/test_sparring.gd")


func run(runner: Object) -> void:
	_source_and_callback(runner)
	_independent_restore(runner)
	_artifact_and_sparring_profiles(runner)
	print("SCENARIO activity ownership: original sources, callbacks, phase-specific sparring, cancellation and independent in-flight restore")


func _source_and_callback(runner: Object) -> void:
	var world: RegionalSimulation = Support.make(runner, {"qi": {"player": 10}})
	if world == null:
		return
	for scope: StringName in [&"local", &"body", &"journey", &"manual_action", &"stationary", &"wait", &"player_action", &"automatic_motion"]:
		runner.assert_true(not world.owns_for_scope("absent", scope), "missing actor does not invent an activity: " + String(scope))
	runner.assert_true(not world.native_action_allowed("absent"), "control checks still refuse a missing body")
	runner.assert_true(world.owns_for_scope("player", &"misspelled_scope"), "unknown internal scope fails closed")
	runner.assert_true(world.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone").ok, "original source operation acquires its actual process")
	for scope: StringName in [&"local", &"body", &"journey", &"manual_action", &"stationary", &"player_action", &"automatic_motion"]:
		runner.assert_true(world.owns_for_scope("player", scope), "source-owned body blocks the existing contract: " + String(scope))
	runner.assert_true(not world.owns_for_scope("player", &"wait"), "source activity does not invent the sparring-only wait restriction")
	runner.assert_true(not world.body_action_owns("player", &"spirit_sources"), "source completion may exclude only its own process")
	runner.assert_true(world.spirit_sources.readiness("player", "hearth_seam", "body", "hearth_stone", true).is_empty(), "own in-flight source remains ready without self-conflict")
	var before: String = Support.canonical(world.to_dict())
	world.set_local_action_owner(func(actor: String) -> bool: return actor == "player")
	runner.assert_true(world.body_action_owns("player", &"spirit_sources"), "excluding self still detects an adapter-owned short action")
	runner.assert_true(world.owns_for_scope("player", &"local", &"local_motion"), "excluding local motion does not hide the source domain")
	runner.assert_eq(Support.canonical(world.to_dict()), before, "query and adapter binding do not mutate persistent facts")
	world.set_local_action_owner(Callable())
	world.spirit_sources.cancel("player")
	runner.assert_true(not world.body_action_owns("player"), "cancel releases original ownership without clearing a second lock table")
	world.set_local_action_owner(func(actor: String) -> bool: return actor == "player")
	runner.assert_true(world.local_action_owns("player"), "original local callback remains part of the legacy local contract")
	runner.assert_true(not world.owns_for_scope("player", &"journey"), "candidate journey queries do not inspect a live adapter")
	runner.assert_true(not world.body_action_owns("player", &"local_motion"), "local callback can be explicitly excluded")
	world.set_local_action_owner(Callable())
	world.regions.home.actors.player.autonomous = true
	runner.assert_true(world.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone").ok, "former native autonomy is captured by the real activity")
	runner.assert_true(world.activity_previous_autonomy("player"), "saved return autonomy is read from its actual owner")
	world.spirit_sources.cancel("player")
	runner.assert_true(not world.activity_previous_autonomy("player") and world.regions.home.actors.player.autonomous, "restored native autonomy is not confused with an active return marker")


func _independent_restore(runner: Object) -> void:
	var world: RegionalSimulation = Support.make(runner, {"qi": {"player": 10}})
	if world == null:
		return
	runner.assert_true(world.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone").ok, "continuity fixture starts through the original source API")
	runner.assert_true(world.advance_to_ms(30000), "real process advances before independent save")
	var restored: RegionalSimulation = Support.valid_restore(runner, world, {"qi": {"player": 10}})
	if restored == null:
		return
	runner.assert_true(restored.spirit_sources != world.spirit_sources, "restored process has an independent owner")
	runner.assert_true(restored.spirit_sources.world == restored, "restored source is bound to the committed world")
	for name: StringName in RegionalSimulation.SaveDomains.ids():
		if name == &"embodiment":
			continue
		runner.assert_true(restored.get(name).get("world") == restored, "restored domain binds publicly to committed authority: " + String(name))
	runner.assert_true(restored.body_action_owns("player"), "query finds restored source state rather than a stale cached reference")
	runner.assert_true(not restored.body_action_owns("player", &"spirit_sources"), "restored source exclusion does not block on itself")
	world.spirit_sources.cancel("player")
	runner.assert_true(not world.body_action_owns("player") and restored.body_action_owns("player"), "cancelling live source cannot release independent restored activity")
	runner.assert_true(restored.advance_to_ms(120000), "restored operation completes under the unchanged staged clock")
	runner.assert_eq(restored.regions.home.actors.player.qi, 14, "restored original body receives the source output once")
	runner.assert_true(not restored.body_action_owns("player"), "completion releases actual restored domain ownership")
	var future: String = Support.canonical(restored.to_dict())
	var second: RegionalSimulation = Support.valid_restore(runner, restored, {"qi": {"player": 10}})
	if second == null:
		return
	runner.assert_eq(Support.canonical(second.to_dict()), future, "new domain catalog preserves the complete canonical saved state")
	var bad: Dictionary = second.to_dict()
	bad.erase("spirit_sources")
	runner.assert_true(not second.restore(bad), "catalog shape validation still rejects a missing required saved domain")
	runner.assert_eq(Support.canonical(second.to_dict()), future, "failed domain restoration leaves committed world unchanged")


func _artifact_and_sparring_profiles(runner: Object) -> void:
	var world: RegionalSimulation = Support.make(runner)
	if world == null:
		return
	runner.assert_true(world.artifacts.begin("player", "study", "hearth_stone").ok, "actual artifact study starts on the original body")
	runner.assert_true(world.body_action_owns("player"), "artifact study participates in shared bodily ownership")
	runner.assert_true(not world.local_action_owns("player"), "legacy local subset remains distinct from artifact ownership")
	runner.assert_true(world.owns_for_scope("player", &"manual_action"), "artifact activity still excludes saved manual short actions")
	runner.assert_true(not world.body_action_owns("player", &"artifacts"), "excluding the actual artifact process releases only that owner")
	var bout: RegionalSimulation = SparringFixture.new()._make(runner)
	if bout == null:
		return
	runner.assert_true(bout.sparring.invite("player", "shi_tou").ok, "practice fixture enters through actual mutual invitation")
	runner.assert_true(bout.owns_for_scope("player", &"journey") and bout.owns_for_scope("player", &"wait"), "an agreed bout excludes leaving and clock waits")
	runner.assert_true(not bout.owns_for_scope("player", &"manual_action") and not bout.owns_for_scope("player", &"player_action"), "a resting sparring phase permits the existing manual movement contract")
	runner.assert_true(bout.sparring.strike("player", Vector2.RIGHT), "one real strike begins its original short action")
	runner.assert_true(bout.owns_for_scope("player", &"manual_action") and bout.owns_for_scope("player", &"automatic_motion"), "the active strike phase blocks manual movement")
	bout.sparring.stop()
	runner.assert_true(not bout.body_action_owns("player"), "stopping practice releases the original bout owner")
