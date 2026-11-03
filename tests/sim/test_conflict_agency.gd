extends RefCounted
## Actor names and encounter roles do not confer control or automatic policy.

const Combat = preload("res://tests/sim/test_conflicts.gd")
var _combat := Combat.new()


func run(runner: Object) -> void:
	_initiator_and_manual_defender(runner)
	_both_npcs_sample_before_committing(runner)
	_current_channels_override_policy(runner)
	_interruption_preserves_both_policies(runner)
	_original_player_body_can_be_autonomous(runner)
	_pause_and_retreat_follow_policy(runner)
	_cross_owner_initiator_continuation(runner)
	_sparse_and_restored_futures(runner)
	_strict_cause_upgrade(runner)
	print("SCENARIO conflict agency: per-person policy, real control channels, automatic initiators, manual defenders, simultaneous cues, independent retreat and exact continued futures")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _combat._world(runner)
	if world == null:
		return null
	# The older combat fixture may request an automatic defender for its own
	# scenarios. This suite declares each participant's policy explicitly.
	for region: String in world.regions:
		var sim: VillageSimulation = world.regions[region]
		for actor: String in sim.actors:
			sim.actors[actor].autonomous = false
		world.invalidate_region(region)
	return world


func _first_action(world: RegionalSimulation, actor: String) -> Dictionary:
	for action: Dictionary in world.conflicts.actions.values():
		if action.actor == actor:
			return action
	return {}


func _count_actions(world: RegionalSimulation, actor: String) -> int:
	var count: int = 0
	for action: Dictionary in world.conflicts.actions.values():
		if action.actor == actor:
			count += 1
	return count


func _row(world: RegionalSimulation) -> Dictionary:
	return world.conflicts.conflicts.values()[0]


func _set_policy(world: RegionalSimulation, actor: String, automatic: bool) -> void:
	world.conflicts.body(actor).autonomous = automatic
	world.invalidate_region(world.conflicts.home(actor))


func _automatic_pair(runner: Object, both: bool = false) -> RegionalSimulation:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return null
	_combat._pair(world, "chen_shouzhuo", "shi_tou", Vector2(300.0, 0.0))
	_set_policy(world, "chen_shouzhuo", true)
	_set_policy(world, "shi_tou", both)
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "shi_tou").ok, "explicit autonomous initiator begins over the original nearby bodies")
	return world


func _initiator_and_manual_defender(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	_combat._pair(world, "chen_shouzhuo", "player")
	runner.assert_true(world.conflicts.teach("chen_shouzhuo", "player").ok, "manual defender first learns the actual methods instead of failing to act only from ignorance")
	runner.assert_true(world.advance_to_ms(60000), "original paired demonstration completes")
	_combat._pair(world, "chen_shouzhuo", "player", Vector2(300.0, 0.0))
	_set_policy(world, "chen_shouzhuo", true)
	var defender_point: Vector2 = SimRouteTravel.point(world.conflicts.body("player"))
	var defender_qi: int = int(world.conflicts.body("player").qi)
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "player").ok, "NPC can initiate while the capable player remains manual")
	runner.assert_true(_row(world).people.chen_shouzhuo.previous_autonomous and not _row(world).people.player.previous_autonomous, "encounter preserves each distinct original policy")
	runner.assert_true(world.advance_to_ms(60600), "real shared time passes the defender reaction and a visible windup")
	runner.assert_eq(_count_actions(world, "chen_shouzhuo"), 1, "autonomous initiator independently pays for its first attack")
	runner.assert_true(SimRouteTravel.point(world.conflicts.body("chen_shouzhuo")).x > Combat.ARENA.x, "autonomous initiator actually moves rather than waiting for a defender-only branch")
	runner.assert_eq(_count_actions(world, "player"), 0, "manual defender is not given an automatic guard or attack")
	runner.assert_eq(world.conflicts.body("player").qi, defender_qi, "AI does not spend the manual defender's original qi")
	runner.assert_true(SimRouteTravel.point(world.conflicts.body("player")).is_equal_approx(defender_point), "AI does not move the manual defender")
	runner.assert_true(world.conflicts.cast("player", "qi_guard", Vector2.LEFT).ok, "manual defender may still deliberately use the learned guard")


func _both_npcs_sample_before_committing(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	_combat._pair(world, "chen_shouzhuo", "shi_tou", Vector2(300.0, 0.0))
	_set_policy(world, "chen_shouzhuo", true)
	_set_policy(world, "shi_tou", true)
	# Configure a valid one-step reaction rule before opening this scenario.
	# No stored decision/action is edited to manufacture a simultaneous past.
	world.conflicts.rules.reaction_ms = int(world.conflicts.rules.step_ms)
	runner.assert_true(SimConflicts.valid_rules(world.conflicts.rules), "symmetric boundary scenario uses a valid reaction rule")
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "shi_tou").ok, "both original NPCs begin with the configured reaction rule")
	runner.assert_true(world.advance_to_ms(50), "both automatic original people reach their first common decision boundary")
	var first: Dictionary = _first_action(world, "chen_shouzhuo")
	var second: Dictionary = _first_action(world, "shi_tou")
	runner.assert_true(not first.is_empty() and not second.is_empty(), "both NPCs independently initiate an action on the same boundary")
	if first.is_empty() or second.is_empty():
		return
	runner.assert_eq(first.started_ms, second.started_ms, "both action commitments have the same actual millisecond")
	runner.assert_eq(first.method, "qi_bolt", "first NPC sees no future windup before anyone commits")
	runner.assert_eq(second.method, "qi_bolt", "second NPC cannot react with a guard to the first NPC's newly created same-boundary windup")
	runner.assert_true(world.conflicts.Schema.validate(world.conflicts.to_dict(), world.conflicts), "symmetric real commitments preserve strict action/cost evidence")


func _current_channels_override_policy(runner: Object) -> void:
	for channel: String in ["motion", "action", "communication"]:
		var world: RegionalSimulation = _automatic_pair(runner)
		if world == null:
			return
		var actor: String = "chen_shouzhuo"
		var embodiment: SimEmbodiment = world.embodiment
		var start: Vector2 = SimRouteTravel.point(world.conflicts.body(actor))
		runner.assert_true(embodiment.release_control(embodiment.subject_for_actor(actor), embodiment.carrier_for_source("village_actor", actor), channel), "original channel is genuinely relinquished: " + channel)
		runner.assert_true(world.advance_to_ms(50), "next boundary reevaluates actual channel rather than cached policy: " + channel)
		runner.assert_eq(_count_actions(world, actor), 0, "automatic policy cannot start an action through a lost channel: " + channel)
		runner.assert_true(SimRouteTravel.point(world.conflicts.body(actor)).is_equal_approx(start), "automatic policy cannot move through a lost channel: " + channel)
		if channel in ["motion", "action"]:
			runner.assert_eq(_row(world).reason, "control_lost", "lost physical control terminates the original encounter: " + channel)
		else:
			runner.assert_eq(_row(world).ended_ms, -1, "communication loss pauses automatic strategy without erasing a still-controlled physical encounter")


func _interruption_preserves_both_policies(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var point: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(world.regions.home.places.kitchen.cell))
	_combat._pair(world, "chen_shouzhuo", "shi_tou", Vector2(64.0, 0.0), point)
	_set_policy(world, "chen_shouzhuo", true)
	_set_policy(world, "shi_tou", true)
	runner.assert_true(world.artifacts.begin("chen_shouzhuo", "inspect", "hearth_stone").ok, "original automatic initiator occupies its body inspecting the real source artifact")
	runner.assert_true(not world.conflicts.body("chen_shouzhuo").autonomous and world.artifacts.previous_autonomy("chen_shouzhuo"), "actual occupation temporarily owns the body while retaining its policy")
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "shi_tou").ok, "hostile intention interrupts that real original occupation")
	runner.assert_true(_row(world).people.chen_shouzhuo.previous_autonomous and _row(world).people.shi_tou.previous_autonomous, "both previous policies were collected before interruption callbacks ran")
	runner.assert_true(not world.artifacts.owns_actor("chen_shouzhuo"), "original artifact occupation has actually released its one body")
	runner.assert_true(world.advance_to_ms(50), "interrupted automatic original body can choose its first real hostile action")
	runner.assert_eq(_count_actions(world, "chen_shouzhuo"), 1, "temporary occupation did not silently convert the initiator to manual policy")


func _original_player_body_can_be_autonomous(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	_combat._pair(world, "chen_shouzhuo", "player")
	runner.assert_true(world.conflicts.teach("chen_shouzhuo", "player").ok and world.advance_to_ms(60000), "original player-named person gains a real technique through the ordinary lesson")
	_combat._pair(world, "chen_shouzhuo", "player", Vector2(300.0, 0.0))
	# The actual bird/soul opening sets this original body policy in runtime.
	# This rule scenario tests that actor identity never overrides that policy.
	_set_policy(world, "player", true)
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "player").ok, "autonomous original person remains a valid encounter participant despite its former player name")
	runner.assert_true(world.advance_to_ms(60600), "former player body's own reaction boundary arrives")
	runner.assert_eq(_count_actions(world, "player"), 1, "player-named autonomous original person chooses its own actual action")
	runner.assert_eq(_first_action(world, "player").method, "qi_bolt", "the original person uses actual learned knowledge without borrowing a different avatar")
	_copy(world, runner, "autonomous original player-named body")


func _pause_and_retreat_follow_policy(runner: Object) -> void:
	var automatic: RegionalSimulation = _automatic_pair(runner)
	if automatic == null:
		return
	runner.assert_true(automatic.advance_to_ms(1050), "automatic initiator finishes its own first real cast")
	var action: Dictionary = _first_action(automatic, "chen_shouzhuo")
	runner.assert_eq(action.status, "completed", "initiator action retains its actual completed outcome")
	runner.assert_eq(_row(automatic).people.chen_shouzhuo.ready_ms, 1500, "AI pause follows an automatic initiator rather than the defender role")
	runner.assert_true(automatic.advance_to_ms(1499), "time reaches one millisecond before the automatic pause expires")
	runner.assert_eq(_count_actions(automatic, "chen_shouzhuo"), 1, "automatic initiator cannot cast again during its own pause")
	var manual: RegionalSimulation = _world(runner)
	if manual == null:
		return
	_combat._pair(manual, "chen_shouzhuo", "shi_tou", Vector2(300.0, 0.0))
	runner.assert_true(manual.conflicts.begin("chen_shouzhuo", "shi_tou").ok and manual.conflicts.cast("chen_shouzhuo", "qi_bolt", Vector2.RIGHT).ok, "manual original actor deliberately commits its own cast")
	runner.assert_true(manual.advance_to_ms(1000), "manual original cast reaches its real completed time")
	runner.assert_eq(_row(manual).people.chen_shouzhuo.ready_ms, 1000, "manual actor is not given an artificial AI pause")
	manual.conflicts.cancel("shi_tou")
	runner.assert_true(_row(manual).withdrawal.is_empty(), "yielding manual defender receives no forced AI displacement")
	var retreating: RegionalSimulation = _automatic_pair(runner)
	if retreating == null:
		return
	retreating.conflicts.cancel("chen_shouzhuo")
	var row: Dictionary = _row(retreating)
	runner.assert_eq(row.withdrawal.get("actor"), "chen_shouzhuo", "automatic initiator can genuinely retreat when yielding")
	var origin: Vector2 = SimRouteTravel.point(retreating.conflicts.body("chen_shouzhuo"))
	runner.assert_true(retreating.advance_to_ms(100), "automatic initiator retreat advances on the original scheduler")
	runner.assert_true(SimRouteTravel.point(retreating.conflicts.body("chen_shouzhuo")).x < origin.x, "automatic initiator actually moves away from its own last perceived opponent")
	var restored: RegionalSimulation = _copy(retreating, runner, "automatic initiator retreat")
	if restored == null:
		return
	runner.assert_true(retreating.advance_to_ms(5000) and restored.advance_to_ms(5000), "original and restored automatic retreat reach a common future")
	runner.assert_eq(_combat._canonical(restored), _combat._canonical(retreating), "automatic initiator retreat, policy restoration and all unrelated state continue identically")
	runner.assert_eq(row.withdrawal.status, "completed", "automatic retreat reaches its finite stopping distance")
	runner.assert_true(retreating.conflicts.body("chen_shouzhuo").autonomous, "finite retreat restores the original autonomous policy")


func _copy(world: RegionalSimulation, runner: Object, label: String) -> RegionalSimulation:
	var copy: RegionalSimulation = _world(runner)
	if copy == null:
		return null
	var accepted: bool = copy.restore(JSON.parse_string(_combat._canonical(world)))
	runner.assert_true(accepted, label + " restores as an independent strict candidate")
	return copy if accepted else null


func _cross_owner_initiator_continuation(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	_combat._pair(world, "chen_shouzhuo", "river_shi_tou", Vector2(300.0, 0.0))
	_set_policy(world, "chen_shouzhuo", true)
	runner.assert_true(world.advance_to_ms(123), "cross-owner automatic encounter starts at a real non-grid millisecond")
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "river_shi_tou").ok, "original home NPC initiates against an actually nearby river-owned original body")
	runner.assert_eq(_row(world).region, "river", "encounter record ownership remains the responder's original region")
	runner.assert_true(world.advance_to_ms(173), "automatic initiator moves and starts a real cast across record ownership")
	runner.assert_eq(_count_actions(world, "chen_shouzhuo"), 1, "home initiator acts through its own body despite the river encounter owner")
	world.conflicts.cancel("chen_shouzhuo")
	var restored: RegionalSimulation = _copy(world, runner, "cross-owner automatic initiator withdrawal")
	if restored == null:
		return
	runner.assert_true(world.advance_to_ms(5000) and restored.advance_to_ms(5000), "original owners continue the cross-owner retreat to the same shared future")
	runner.assert_eq(_combat._canonical(restored), _combat._canonical(world), "cross-owner automatic retreat and restored policy have exactly the same complete future")
	runner.assert_eq(_row(world).withdrawal.status, "completed", "cross-owner initiator completes its own finite displacement")
	runner.assert_true(world.regions.home.actors.chen_shouzhuo.autonomous, "initiator returns to autonomy in the original home body")
	runner.assert_true(not world.regions.river.actors.river_shi_tou.autonomous, "manual cross-owner defender retains its own original policy")


func _sparse_and_restored_futures(runner: Object) -> void:
	var sparse: RegionalSimulation = _automatic_pair(runner, true)
	if sparse == null:
		return
	runner.assert_true(sparse.advance_to_ms(673), "two automatic original people reach a genuinely in-progress save")
	var fine: RegionalSimulation = _copy(sparse, runner, "two automatic people with active actions")
	if fine == null:
		return
	runner.assert_true(sparse.advance_to_ms(5000), "sparse scheduler completes the same two-person process")
	var reached: bool = true
	for now: int in range(690, 5000, 17):
		reached = fine.advance_to_ms(now) and reached
	reached = fine.advance_to_ms(5000) and reached
	runner.assert_true(reached, "fine scheduler reaches the exact same shared millisecond")
	runner.assert_eq(_combat._canonical(fine), _combat._canonical(sparse), "both automatic decisions, qi/stamina, physical contacts, injuries and complete unrelated world state share the same future")


func _strict_cause_upgrade(runner: Object) -> void:
	var world: RegionalSimulation = _automatic_pair(runner)
	if world == null:
		return
	runner.assert_true(world.advance_to_ms(673), "migration source contains an actual emitted original action")
	var modern: Dictionary = world.conflicts.to_dict()
	var legacy: Dictionary = modern.duplicate(true)
	legacy.version = 2
	for row: Dictionary in legacy.conflicts.values():
		row.erase("cause")
	var before: String = SnapshotValues.canonical_json(legacy)
	var upgraded: Dictionary = SimConflicts.upgrade_source_care(legacy)
	runner.assert_eq(upgraded, modern, "strict v2 upgrade adds only empty causes and the v3 domain version")
	runner.assert_eq(SnapshotValues.canonical_json(legacy), before, "v2 conversion leaves the original candidate history untouched")
	runner.assert_true(SimConflicts.upgrade_source_care(modern).is_empty(), "modern conflict state cannot be relabelled through the old converter")
	for fault: String in ["bool_version", "missing_sight", "modern_cause", "extra_field", "broken_sequence"]:
		var bad: Dictionary = legacy.duplicate(true)
		match fault:
			"bool_version": bad.version = true
			"missing_sight": bad.conflicts.values()[0].people.chen_shouzhuo.erase("sight")
			"modern_cause": bad.conflicts.values()[0]["cause"] = {}
			"extra_field": bad["repair_me"] = true
			"broken_sequence": bad.next_cost_id += 1
		runner.assert_true(SimConflicts.upgrade_source_care(bad).is_empty(), "v2 converter rejects a mismatched old shape instead of repairing it: " + fault)
	var bad_cause: Dictionary = modern.duplicate(true)
	bad_cause.conflicts.values()[0].cause = {"domain": "invented", "id": "source_care:warning:1"}
	runner.assert_true(not world.conflicts.Schema.validate(bad_cause, world.conflicts), "unknown causal domain is rejected by the conflict authority")
	var snapshot: Dictionary = JSON.parse_string(_combat._canonical(world))
	snapshot.conflicts.conflicts.values()[0].cause = {"domain": "source_care", "id": "missing:warning"}
	var present: String = _combat._canonical(world)
	runner.assert_true(not world.restore(snapshot), "orphan source-care cause fails the independent combined candidate")
	runner.assert_eq(_combat._canonical(world), present, "rejecting orphan provenance leaves every live body, clock and cost unchanged")
	runner.assert_true(not world.conflicts.begin_source_care("missing:warning").ok, "trusted care entry cannot manufacture a warning")
	runner.assert_eq(_combat._canonical(world), present, "invalid internal care opening changes no live state")
