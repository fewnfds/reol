extends RefCounted
## Hostile actions exercise the actual two-region scheduler and original bodies.

const Fixtures = preload("res://tests/sim/test_regional_simulation.gd")
const ARENA := Vector2(3232.0, 3232.0)
var _fixtures := Fixtures.new()


class CoverMap extends WorldMapData:
	var cover: Dictionary = {}


	func get_terrain(cell: Vector2i) -> int:
		return TERRAIN_ROCK if cover.has(cell) else TERRAIN_GRASS


	func get_elevation(_cell: Vector2i) -> int:
		return 0


	func independent_copy() -> WorldMapData:
		var copy := CoverMap.new()
		copy.cover = cover.duplicate(true)
		return copy


func run(runner: Object) -> void:
	_actual_learning(runner)
	_struck_bystander_interrupts_lesson(runner)
	_real_weapon_and_exact_emission(runner)
	_interruptions_preserve_costs(runner)
	_guard_capacity_and_expiry(runner)
	_melee_fan_and_simultaneous_contact(runner)
	_injury_and_actual_withdrawal(runner)
	_projectile_after_yield(runner)
	_bystander_and_cover_order(runner)
	_independent_regions(runner)
	_fine_and_sparse(runner)
	_inflight_restore(runner)
	print("SCENARIO conflicts: actual learning and held weapons, exact millisecond costs/emission, shields, simultaneous contact, cover/bystanders, yield, two regions and independent continuation")


func _world(runner: Object, swords: Array[String] = []) -> RegionalSimulation:
	var world: RegionalSimulation = _fixtures._make_world(runner)
	if world == null:
		return null
	var index: int = 0
	for region: String in world.regions:
		for actor: String in world.regions[region].actors:
			_put(world, actor, Vector2(8000.0 + index * 128.0, 12000.0))
			index += 1
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))
	for actor: String in swords:
		opening.objects.append({"id": "conflict_sword:" + actor, "definition": "wooden_sword", "region": world.conflicts.home(actor), "container": "actor:" + actor})
	runner.assert_true(world.artifacts.spawn_opening(opening), "actual artifact authority creates declared opening custody")
	return world


func _put(world: RegionalSimulation, actor: String, point: Vector2) -> void:
	SimRouteTravel.put(world.conflicts.body(actor), point)
	world.invalidate_region(world.conflicts.home(actor))


func _pair(world: RegionalSimulation, initiator: String, defender: String, delta: Vector2 = Vector2(80.0, 0.0), origin: Vector2 = ARENA) -> void:
	_put(world, initiator, origin)
	_put(world, defender, origin + delta)


func _canonical(world: RegionalSimulation) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(world.to_dict()))


func _action(world: RegionalSimulation, actor: String, method: String) -> Dictionary:
	var result: Dictionary = {}
	for action: Dictionary in world.conflicts.actions.values():
		if action.actor == actor and action.method == method:
			result = action
	return result


func _hits_for(world: RegionalSimulation, actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hit: Dictionary in world.conflicts.hits.values():
		if hit.actor == actor:
			result.append(hit)
	return result


func _assert_future(world: RegionalSimulation, runner: Object, target_ms: int, label: String) -> void:
	var restored: RegionalSimulation = _world(runner)
	if restored == null:
		return
	if world.map_data != null:
		restored.bind_map_data(world.map_data.independent_copy())
	var accepted: bool = restored.restore(JSON.parse_string(_canonical(world)))
	runner.assert_true(accepted, label + " accepts a real independent candidate")
	if not accepted:
		return
	runner.assert_true(world.advance_to_ms(target_ms) and restored.advance_to_ms(target_ms), label + " reaches the shared future")
	runner.assert_eq(_canonical(restored), _canonical(world), label + " retains exactly the same complete future")


func _actual_learning(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	_pair(world, "chen_shouzhuo", "player")
	runner.assert_true(not world.conflicts.knows("player", "qi_bolt"), "ordinary observer does not start with a borrowed technique")
	runner.assert_true(world.conflicts.teach("chen_shouzhuo", "player").ok, "known teacher agrees to a real minute of paired demonstration")
	runner.assert_true(world.conflicts.owns_actor("player") and world.conflicts.owns_actor("chen_shouzhuo"), "lesson occupies both actual bodies")
	runner.assert_true(world.advance_to_ms(59999), "lesson progresses to one millisecond before completion")
	runner.assert_true(not world.conflicts.knows("player", "qi_bolt"), "unfinished demonstration grants no early technique")
	_assert_future(world, runner, 60000, "unfinished lesson restore")
	runner.assert_true(world.advance_to_ms(60000), "shared clock reaches the exact lesson completion")
	for method: String in ["sword", "qi_bolt", "qi_guard"]:
		runner.assert_true(world.conflicts.knows("player", method), "completed paired demonstration teaches " + method)
	runner.assert_true(not world.conflicts.owns_actor("player"), "completed lesson releases its execution owner")
	var stopped: RegionalSimulation = _world(runner)
	if stopped == null:
		return
	_pair(stopped, "chen_shouzhuo", "player")
	runner.assert_true(stopped.conflicts.teach("chen_shouzhuo", "player").ok, "a separate interrupted lesson genuinely starts")
	stopped.advance_to_ms(30000)
	stopped.conflicts.cancel("player")
	stopped.advance_to_ms(60000)
	runner.assert_true(not stopped.conflicts.knows("player", "qi_bolt"), "cancelled demonstration does not become knowledge at its former due time")
	runner.assert_eq(stopped.conflicts.lessons.values()[0].status, "interrupted", "cancelled demonstration retains its truthful history")
	runner.assert_true(not stopped.conflicts.owns_actor("player") and not stopped.conflicts.owns_actor("chen_shouzhuo"), "cancellation releases both lesson participants")


func _real_weapon_and_exact_emission(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	_pair(world, "chen_shouzhuo", "player", Vector2(300.0, 0.0))
	runner.assert_true(world.advance_to_ms(123), "combat can begin at an arbitrary shared millisecond")
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "player").ok, "actual hostile intention starts over the original bodies")
	var before: String = _canonical(world)
	runner.assert_true(not world.conflicts.cast("chen_shouzhuo", "sword", Vector2.RIGHT).ok, "knowing swordplay without actual weapon custody cannot strike")
	runner.assert_eq(_canonical(world), before, "rejected missing weapon spends nothing and changes no world fact")
	var qi: int = int(world.conflicts.body("chen_shouzhuo").qi)
	var stamina: int = int(world.conflicts.body("chen_shouzhuo").stamina)
	runner.assert_true(world.conflicts.cast("chen_shouzhuo", "qi_bolt", Vector2.RIGHT).ok, "known projectile starts using the original qi and stamina")
	var action: Dictionary = _action(world, "chen_shouzhuo", "qi_bolt")
	runner.assert_eq(int(action.effect_ms), 623, "123ms start plus 500ms preparation emits exactly at 623ms")
	runner.assert_eq(int(world.conflicts.body("chen_shouzhuo").qi), qi - 3, "beginning one spell pays its qi exactly once")
	runner.assert_eq(int(world.conflicts.body("chen_shouzhuo").stamina), stamina - 2, "beginning one spell pays original stamina exactly once")
	world.advance_to_ms(622)
	runner.assert_true(world.conflicts.projectiles.is_empty() and not bool(action.emitted), "projectile does not emerge one millisecond early")
	world.advance_to_ms(623)
	runner.assert_eq(world.conflicts.projectiles.size(), 1, "exact effect boundary creates one projectile")
	runner.assert_eq(int(action.emission.at_ms), 623, "saved emission records the real exact boundary")
	runner.assert_eq(world.conflicts.phase("chen_shouzhuo", 623), "contact", "exact emission enters the contact phase")
	var emitted_state: String = _canonical(world)
	world.advance_to_ms(623)
	runner.assert_eq(_canonical(world), emitted_state, "settling the same emission time cannot duplicate a spell or cost")
	var held: RegionalSimulation = _world(runner, ["chen_shouzhuo"])
	if held == null:
		return
	_pair(held, "chen_shouzhuo", "player")
	runner.assert_eq(held.artifacts.held_weapon("chen_shouzhuo"), "conflict_sword:chen_shouzhuo", "real declared object is found in one actor container")
	runner.assert_true(held.conflicts.begin("chen_shouzhuo", "player").ok, "armed encounter starts")
	runner.assert_true(held.conflicts.cast("chen_shouzhuo", "sword", Vector2.RIGHT).ok, "actual held weapon enables known swordplay")
	runner.assert_eq(_action(held, "chen_shouzhuo", "sword").object, "conflict_sword:chen_shouzhuo", "strike provenance references the original unique sword")


func _struck_bystander_interrupts_lesson(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	_pair(world, "chen_shouzhuo", "shi_tou", Vector2(300.0, 0.0))
	_put(world, "su_zhi", ARENA + Vector2(80.0, 0.0))
	_put(world, "player", ARENA + Vector2(80.0, 64.0))
	world.conflicts.body("su_zhi").autonomous = true
	world.conflicts.body("su_zhi").retry_ms = 120000
	world.invalidate_region("home")
	runner.assert_true(world.conflicts.teach("su_zhi", "player").ok, "real bystander agrees to demonstrate a guard before the unrelated encounter")
	var lesson: Dictionary = world.conflicts.lessons.values()[0]
	runner.assert_eq(int(lesson.due_ms), 60000, "bystander demonstration genuinely requires one full minute")
	runner.assert_true(world.conflicts.owns_actor("su_zhi") and world.conflicts.owns_actor("player"), "unrelated lesson initially occupies both original bodies")
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "shi_tou").ok, "other people's encounter begins independently of the occupied bystanders")
	runner.assert_true(world.conflicts.cast("chen_shouzhuo", "qi_bolt", Vector2.RIGHT).ok, "real projectile travels through the teacher's position")
	runner.assert_true(world.advance_to_ms(649), "shared scheduler reaches one millisecond before bystander contact")
	runner.assert_eq(lesson.status, "active", "unhit lesson is still active immediately before actual contact")
	runner.assert_true(not world.conflicts.knows("player", "qi_guard"), "partial demonstration grants no technique before interruption")
	runner.assert_true(world.advance_to_ms(650), "actual projectile reaches the intervening teacher at its contact boundary")
	var hits: Array[Dictionary] = _hits_for(world, "su_zhi")
	runner.assert_eq(hits.size(), 1, "unrelated projectile contacts the real intervening teacher once")
	if not hits.is_empty():
		runner.assert_eq(int(hits[0].at_ms), 650, "teacher injury retains its exact actual projectile contact instant")
		runner.assert_eq(int(hits[0].impact), 12, "teacher receives the real unabsorbed impact")
	runner.assert_eq(world.health.combat_burden("su_zhi"), 12, "bystander contact creates a sourced bodily contusion")
	runner.assert_eq(lesson.status, "interrupted", "actual harmful contact interrupts the teaching occupation immediately")
	runner.assert_eq(int(lesson.finished_ms), 650, "lesson records interruption at contact rather than its abandoned due time")
	runner.assert_true(not world.conflicts.owns_actor("su_zhi") and not world.conflicts.owns_actor("player"), "contact releases both the struck teacher and unstruck pupil")
	runner.assert_true(bool(world.conflicts.body("su_zhi").autonomous) and not bool(world.conflicts.body("player").autonomous), "interruption restores each participant's original autonomous or manual policy")
	runner.assert_true(not world.conflicts.conflict_for("chen_shouzhuo").is_empty() and not world.conflicts.conflict_for("shi_tou").is_empty(), "interrupting bystander teaching leaves the unrelated actual encounter intact")
	_assert_future(world, runner, 60000, "immediate harmed-bystander lesson restore")
	runner.assert_eq(lesson.status, "interrupted", "abandoned demonstration never changes into completed at its former deadline")
	runner.assert_true(not world.conflicts.knows("player", "qi_guard"), "pupil gains no guard technique when the interrupted lesson's original minute elapses")


func _guard_capacity_and_expiry(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, ["shi_tou"])
	if world == null:
		return
	_pair(world, "chen_shouzhuo", "shi_tou")
	world.conflicts.body("shi_tou").autonomous = true
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "shi_tou").ok, "shield encounter starts with a real armed defender")
	var qi: int = int(world.conflicts.body("chen_shouzhuo").qi)
	runner.assert_true(world.conflicts.cast("chen_shouzhuo", "qi_guard", Vector2.RIGHT).ok, "guard preparation pays and starts once")
	world.advance_to_ms(149)
	runner.assert_true(not world.conflicts.barriers.has("chen_shouzhuo"), "guard offers no protection during preparation")
	world.advance_to_ms(150)
	runner.assert_eq(world.conflicts.barriers.chen_shouzhuo.remaining, 12, "emitted guard has its finite configured capacity")
	runner.assert_eq(world.conflicts.barriers.chen_shouzhuo.until_ms, 2550, "guard duration begins at actual emission")
	world.advance_to_ms(500)
	runner.assert_eq(world.conflicts.barriers.chen_shouzhuo.remaining, 12, "remaining protection survives completed casting recovery")
	var before: String = _canonical(world)
	runner.assert_true(not world.conflicts.cast("chen_shouzhuo", "qi_guard", Vector2.RIGHT).ok, "existing guard cannot be stacked into fresh capacity")
	runner.assert_eq(_canonical(world), before, "rejected guard stacking pays no extra cost")
	_assert_future(world, runner, 900, "emitted finite guard restore")
	world.advance_to_ms(900)
	var hits: Array[Dictionary] = _hits_for(world, "chen_shouzhuo")
	runner.assert_eq(hits.size(), 1, "one sword contact consumes the guard once")
	if not hits.is_empty():
		runner.assert_eq(int(hits[0].absorbed), 12, "guard accounts for the actual absorbed impact")
		runner.assert_eq(int(hits[0].impact), 0, "fully absorbed hit leaves no invented wound")
	runner.assert_true(not world.conflicts.barriers.has("chen_shouzhuo"), "spent guard is removed rather than refilled next tick")
	runner.assert_eq(world.health.combat_burden("chen_shouzhuo"), 0, "full protection leaves original health free of contusion")
	runner.assert_eq(int(world.conflicts.body("chen_shouzhuo").qi), qi - 3, "emission and absorption never spend guard qi twice")
	var expiry: RegionalSimulation = _world(runner)
	if expiry == null:
		return
	_pair(expiry, "chen_shouzhuo", "player")
	expiry.conflicts.begin("chen_shouzhuo", "player")
	expiry.conflicts.cast("chen_shouzhuo", "qi_guard", Vector2.RIGHT)
	expiry.advance_to_ms(500)
	expiry.conflicts.cancel("chen_shouzhuo")
	expiry.advance_to_ms(2549)
	runner.assert_true(expiry.conflicts.barriers.has("chen_shouzhuo"), "yielding does not erase already emitted unspent protection")
	expiry.advance_to_ms(2550)
	runner.assert_true(not expiry.conflicts.barriers.has("chen_shouzhuo"), "unspent guard expires on its own exact future boundary")


func _interruptions_preserve_costs(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	_pair(world, "chen_shouzhuo", "player")
	runner.assert_true(world.regions.home.submit_action("player", "rest"), "native occupation genuinely owns the future defender before warning")
	runner.assert_true(not world.conflicts.body("player").active.is_empty(), "original native action exists before conflict takes over")
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "player").ok, "hostile warning interrupts the prior real occupation")
	runner.assert_true(world.conflicts.body("player").active.is_empty(), "interrupted native action cannot execute concurrently with the conflict")
	var qi: int = int(world.conflicts.body("chen_shouzhuo").qi)
	runner.assert_true(world.conflicts.cast("chen_shouzhuo", "qi_bolt", Vector2.RIGHT).ok, "cancellable preparation pays original qi")
	world.advance_to_ms(499)
	world.conflicts.cancel("chen_shouzhuo")
	runner.assert_eq(_action(world, "chen_shouzhuo", "qi_bolt").status, "interrupted", "cancellation before emission records the real incomplete action")
	runner.assert_eq(int(world.conflicts.body("chen_shouzhuo").qi), qi - 3, "cancelled preparation does not regenerate spent qi")
	_assert_future(world, runner, 1500, "cancelled preparation restore")
	runner.assert_true(world.conflicts.projectiles.is_empty() and world.conflicts.hits.is_empty(), "cancelled preparation never emits at its discarded future deadline")


func _melee_fan_and_simultaneous_contact(runner: Object) -> void:
	for delta: Vector2 in [Vector2(-80.0, 0.0), Vector2(0.0, 80.0), Vector2(120.0, 0.0), Vector2(80.0, 0.0)]:
		var world: RegionalSimulation = _world(runner, ["chen_shouzhuo"])
		if world == null:
			return
		_pair(world, "chen_shouzhuo", "player", delta)
		runner.assert_true(world.conflicts.begin("chen_shouzhuo", "player").ok, "fan geometry fixture starts at " + str(delta))
		runner.assert_true(world.conflicts.cast("chen_shouzhuo", "sword", Vector2.RIGHT).ok, "fan geometry uses a real weapon and actual action")
		world.advance_to_ms(400)
		runner.assert_eq(_hits_for(world, "player").size(), 1 if delta == Vector2(80.0, 0.0) else 0, "only a target inside current reach and facing fan is contacted: " + str(delta))
	var mutual: RegionalSimulation = _world(runner, ["chen_shouzhuo", "shi_tou"])
	if mutual == null:
		return
	_pair(mutual, "chen_shouzhuo", "shi_tou")
	mutual.conflicts.body("shi_tou").autonomous = true
	mutual.conflicts.begin("chen_shouzhuo", "shi_tou")
	mutual.advance_to_ms(600)
	runner.assert_eq(_action(mutual, "shi_tou", "sword").get("started_ms", -1), 600, "armed defender starts its own strike after reaction")
	runner.assert_true(mutual.conflicts.cast("chen_shouzhuo", "sword", Vector2.RIGHT).ok, "initiator independently starts a simultaneous strike")
	mutual.advance_to_ms(900)
	runner.assert_eq(mutual.conflicts.hits.size(), 2, "same-boundary mutual strikes both land before interruption effects")
	for actor: String in ["chen_shouzhuo", "shi_tou"]:
		runner.assert_eq(_hits_for(mutual, actor).size(), 1, "mutual contact injures " + actor + " exactly once")
		runner.assert_eq(mutual.health.combat_burden(actor), 12, "actual sourced contusion remains on " + actor)
	mutual.advance_to_ms(950)
	runner.assert_eq(mutual.conflicts.hits.size(), 2, "contact window does not strike the same target again on a later tick")


func _injury_and_actual_withdrawal(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, ["chen_shouzhuo"])
	if world == null:
		return
	_pair(world, "chen_shouzhuo", "a_he")
	world.conflicts.body("a_he").autonomous = true
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "a_he").ok, "injury-driven withdrawal begins as an actual encounter with an autonomous noncombatant")
	runner.assert_true(world.conflicts.cast("chen_shouzhuo", "sword", Vector2.RIGHT).ok, "first real strike starts")
	world.advance_to_ms(750)
	runner.assert_eq(world.health.combat_burden("a_he"), 12, "one real contact creates its sourced burden")
	runner.assert_true(world.conflicts.cast("chen_shouzhuo", "sword", Vector2.RIGHT).ok, "second strike requires the first recovery to finish")
	world.advance_to_ms(1050)
	var encounter: Dictionary = world.conflicts.conflicts.values()[0]
	runner.assert_eq(world.health.combat_burden("a_he"), 24, "two committed contacts accumulate original body consequences")
	runner.assert_eq(encounter.reason, "withdrawn", "health limit ends the exchange before lethal combat")
	runner.assert_eq(encounter.yielded, "a_he", "the affected autonomous defender is the person withdrawing")
	runner.assert_true(world.conflicts.conflict_for("a_he").is_empty() and world.conflicts.owns_actor("a_he"), "ended exchange retains only the actual autonomous retreat owner")
	var point: Vector2 = SimRouteTravel.point(world.conflicts.body("a_he"))
	world.advance_to_ms(1100)
	runner.assert_true(SimRouteTravel.point(world.conflicts.body("a_he")).x > point.x, "withdrawal physically moves the autonomous person away")
	runner.assert_true(not world.conflicts.begin("chen_shouzhuo", "a_he").ok, "a seriously bruised person is not immediately forced into a fresh bout")
	_assert_future(world, runner, 2200, "partly travelled withdrawal restore")
	runner.assert_eq(encounter.withdrawal.status, "completed", "retreat eventually finishes its finite movement")
	runner.assert_eq(encounter.withdrawal.reason, "distance", "unobstructed retreat ends after actual distance")
	runner.assert_true(not world.conflicts.owns_actor("a_he"), "completed retreat releases its body owner")
	runner.assert_true(bool(world.conflicts.body("a_he").alive), "this bounded drive-off prototype leaves the person alive")


func _projectile_after_yield(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	_pair(world, "chen_shouzhuo", "player", Vector2(300.0, 0.0))
	world.conflicts.begin("chen_shouzhuo", "player")
	world.conflicts.cast("chen_shouzhuo", "qi_bolt", Vector2.RIGHT)
	world.advance_to_ms(500)
	var qi: int = int(world.conflicts.body("chen_shouzhuo").qi)
	world.conflicts.cancel("chen_shouzhuo")
	runner.assert_true(not world.conflicts.owns_actor("chen_shouzhuo"), "yield releases encounter occupation")
	runner.assert_eq(world.conflicts.projectiles.size(), 1, "already emitted projectile survives yielding")
	_assert_future(world, runner, 1300, "post-yield travelling shot restore")
	world.advance_to_ms(1300)
	runner.assert_eq(_hits_for(world, "player").size(), 1, "emitted shot reaches the actual person after encounter end")
	runner.assert_eq(world.health.combat_burden("player"), 12, "post-yield contact still produces actual health consequence")
	runner.assert_eq(int(world.conflicts.body("chen_shouzhuo").qi), qi, "yield does not refund a cost already committed")
	runner.assert_true(world.conflicts.projectiles.is_empty(), "hit consumes projectile once")
	var before: int = world.conflicts.hits.size()
	world.advance_to_ms(1500)
	runner.assert_eq(world.conflicts.hits.size(), before, "ending and future ticking cannot replay the consumed projectile")


func _bystander_and_cover_order(runner: Object) -> void:
	for wall_before: bool in [false, true]:
		var world: RegionalSimulation = _world(runner)
		if world == null:
			return
		var map := CoverMap.new()
		world.bind_map_data(map)
		# Both possible contacts lie in the same 22px projectile segment.
		var origin := Vector2(3201.0, 3232.0)
		_pair(world, "chen_shouzhuo", "player", Vector2(0.0, 300.0), origin)
		_put(world, "a_he", Vector2(3259.0 if not wall_before else 3270.0, origin.y))
		map.cover[Vector2i(51, 50)] = true
		runner.assert_true(world.conflicts.begin("chen_shouzhuo", "player").ok, "off-axis opponent allows initial unobstructed warning")
		runner.assert_true(world.conflicts.cast("chen_shouzhuo", "qi_bolt", Vector2.RIGHT).ok, "projectile follows chosen direction rather than snapping to its opponent")
		world.advance_to_ms(500)
		world.conflicts.cancel("chen_shouzhuo")
		world.advance_to_ms(700)
		var hits: Array[Dictionary] = _hits_for(world, "a_he")
		runner.assert_eq(hits.size(), 0 if wall_before else 1, "same-segment spatial ordering respects " + ("wall before person" if wall_before else "person before wall"))
		runner.assert_eq(_hits_for(world, "player").size(), 0, "chosen opponent outside the shot path is not automatically hit")
		var action: Dictionary = _action(world, "chen_shouzhuo", "qi_bolt")
		runner.assert_eq(action.projectile_end.get("reason", ""), "blocked" if wall_before else "hit", "projectile records the actual first obstruction")
		runner.assert_eq(world.health.combat_burden("a_he"), 0 if wall_before else 12, "actual bystander health follows cover ordering")


func _independent_regions(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	_pair(world, "chen_shouzhuo", "player", Vector2(300.0, 0.0))
	_pair(world, "river_chen_shouzhuo", "river_su_zhi", Vector2(80.0, 0.0), ARENA + Vector2(1600.0, 0.0))
	world.conflicts.body("river_su_zhi").autonomous = true
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "player").ok, "home encounter starts")
	runner.assert_true(world.conflicts.begin("river_chen_shouzhuo", "river_su_zhi").ok, "second region starts a concurrent independent encounter")
	runner.assert_true(world.conflicts.cast("chen_shouzhuo", "qi_bolt", Vector2.RIGHT).ok, "only home launches an incoming projectile")
	world.advance_to_ms(650)
	runner.assert_true(not world.conflicts.conflict_for("chen_shouzhuo").is_empty() and not world.conflicts.conflict_for("river_chen_shouzhuo").is_empty(), "both encounter owners remain active at the same shared time")
	runner.assert_true(_action(world, "river_su_zhi", "qi_guard").is_empty(), "remote unrelated projectile does not trigger an impossible local shield response")
	runner.assert_true(not world.conflicts.barriers.has("river_su_zhi"), "remote person does not acquire free protection")
	world.conflicts.cancel("chen_shouzhuo")
	runner.assert_true(not world.conflicts.conflict_for("river_chen_shouzhuo").is_empty(), "yielding in one region leaves the other encounter running")


func _progression_fixture(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return null
	_pair(world, "chen_shouzhuo", "player", Vector2(300.0, 0.0))
	world.advance_to_ms(123)
	world.conflicts.begin("chen_shouzhuo", "player")
	world.conflicts.cast("chen_shouzhuo", "qi_bolt", Vector2.RIGHT)
	return world


func _fine_and_sparse(runner: Object) -> void:
	var sparse: RegionalSimulation = _progression_fixture(runner)
	var fine: RegionalSimulation = _progression_fixture(runner)
	if sparse == null or fine == null:
		return
	runner.assert_true(sparse.advance_to_ms(2000), "absent encounter advances directly to future time")
	var reached: bool = true
	for at_ms: int in range(140, 2001, 17):
		reached = fine.advance_to_ms(at_ms) and reached
	reached = fine.advance_to_ms(2000) and reached
	runner.assert_true(reached, "fine-grained nearby stepping reaches the same future time")
	runner.assert_eq(_canonical(fine), _canonical(sparse), "same future is independent of display update cadence")


func _inflight_restore(runner: Object) -> void:
	var world: RegionalSimulation = _progression_fixture(runner)
	if world == null:
		return
	world.advance_to_ms(673)
	runner.assert_eq(world.conflicts.projectiles.size(), 1, "snapshot captures a genuinely emitted and travelling shot")
	var snapshot: Dictionary = JSON.parse_string(_canonical(world))
	var restored: RegionalSimulation = _world(runner)
	if restored == null:
		return
	var accepted: bool = restored.restore(snapshot)
	runner.assert_true(accepted, "independent joint candidate accepts the real in-flight conflict")
	if not accepted:
		return
	runner.assert_eq(_canonical(restored), _canonical(world), "restoring in-flight action preserves all present facts")
	world.advance_to_ms(2000)
	restored.advance_to_ms(2000)
	runner.assert_eq(_canonical(restored), _canonical(world), "restored shot, resources, injuries and unrelated life reach the same future")
	var before: String = _canonical(restored)
	var forged: Dictionary = JSON.parse_string(before)
	forged.conflicts.actions.values()[0].qi_spent = 0
	runner.assert_true(not restored.restore(forged), "joint restore rejects a spell whose paid qi was erased")
	runner.assert_eq(_canonical(restored), before, "rejected conflict candidate cannot partly replace the actual world")
