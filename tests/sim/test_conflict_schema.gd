extends RefCounted
## Real shared actors execute lessons and actions before their candidate
## histories are altered. A shape-only manufactured victory is not evidence.

const Schema = preload("res://scripts/sim/conflict_schema.gd")
const Support = preload("res://tests/sim/spirit_source_test_support.gd")


func run(runner: Object) -> void:
	var world: RegionalSimulation = Support.make(runner, {"qi": {"player": 12}})
	if world == null:
		return
	var domain: SimConflicts = world.conflicts
	runner.assert_true(Schema.validate(domain.to_dict(), domain), "empty actual conflict authority is a valid candidate")
	var lesson: Dictionary = domain.teach("chen_shouzhuo", "player")
	runner.assert_true(lesson.ok, "existing experienced person starts a real two-body martial demonstration")
	if not lesson.ok:
		return
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + int(domain.rules.lesson_ms)), "shared time completes the actual demonstration")
	runner.assert_true(domain.knows("player", "qi_bolt"), "completed demonstration rather than a known flag supplies the real new technique")
	runner.assert_true(Schema.validate(domain.to_dict(), domain), "completed real lesson validates before any hostile action")
	var began: Dictionary = domain.begin("player", "chen_shouzhuo")
	runner.assert_true(began.ok, "actual taught player and original person enter a bounded encounter")
	if not began.ok:
		return
	runner.assert_true(domain.cast("player", "qi_guard", Vector2.RIGHT).ok, "guard startup debits original qi and allocates an action")
	var prepared: Dictionary = domain.to_dict()
	_check(runner, prepared, domain, "real guard preparation")
	for fault: String in ["unknown_method", "free_cost", "wrong_due", "not_taught", "extra_action", "direction", "foreign_actor", "false_emission"]:
		var bad: Dictionary = prepared.duplicate(true)
		match fault:
			"unknown_method": bad.actions["conflict:action:1"].method = "invented"
			"free_cost": bad.actions["conflict:action:1"].qi_spent = 0
			"wrong_due": bad.actions["conflict:action:1"].due_ms += 1
			"not_taught": bad.lessons["conflict:lesson:1"].status = "interrupted"
			"extra_action": bad.next_cost_id += 1
			"direction": bad.actions["conflict:action:1"].direction = [2.0, 0.0]
			"foreign_actor": bad.actions["conflict:action:1"].actor = "su_zhi"
			"false_emission": bad.actions["conflict:action:1"].emitted = true
		_reject(runner, bad, domain, fault)
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + int(domain.rules.methods.qi_guard.prepare_ms)), "guard emits at its actual effect boundary")
	var guarded: Dictionary = domain.to_dict()
	_check(runner, guarded, domain, "real emitted guard")
	for fault: String in ["deleted_guard", "free_capacity", "extended_guard", "false_origin"]:
		var bad: Dictionary = guarded.duplicate(true)
		match fault:
			"deleted_guard": bad.barriers.clear()
			"free_capacity": bad.barriers.player.remaining += 1
			"extended_guard": bad.barriers.player.until_ms += 1
			"false_origin": bad.actions["conflict:action:1"].emission.origin = [-1, 0]
		_reject(runner, bad, domain, fault)
	domain.cancel("player")
	_check(runner, domain.to_dict(), domain, "yielding keeps the emitted guard and its already-paid action")
	# The same guard remains a real object after the conflict ends; a new
	# cast cannot refresh it through a restart or a renamed encounter.
	runner.assert_true(domain.barriers.has("player"), "ending an encounter does not erase a paid lingering guard")
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + int(domain.rules.methods.qi_guard.duration_ms)), "lingering guard ages on the same world time without active combat")
	_check(runner, domain.to_dict(), domain, "expired emitted guard")
	_projectile(runner)
	_guarded_contact_and_retreat(runner)
	_guard_json_boundaries(runner)
	_cross_owner_same_place(runner)
	_struck_bystander_lesson(runner)
	print("SCENARIO conflict candidate: actual teaching, costs/phases, emitted guard conservation, lingering effects and rejected forged causal history")


func _struck_bystander_lesson(runner: Object) -> void:
	var world: RegionalSimulation = Support.make(runner)
	if world == null:
		return
	var domain: SimConflicts = world.conflicts
	var origin: Vector2 = TileGrid.cell_to_world(Vector2i(100, 100))
	for actor: String in world.regions.home.actors:
		world.regions.home.set_actor_position(actor, origin + Vector2(1280, 1280))
	world.regions.home.set_actor_position("chen_shouzhuo", origin)
	world.regions.home.set_actor_position("shi_tou", origin + Vector2(300, 0))
	world.regions.home.set_actor_position("su_zhi", origin + Vector2(80, 0))
	world.regions.home.set_actor_position("player", origin + Vector2(80, 64))
	world.regions.home.actors.su_zhi.autonomous = true
	world.invalidate_region("home")
	runner.assert_true(domain.teach("su_zhi", "player").ok, "original autonomous teacher starts a real lesson in the path of another encounter")
	runner.assert_true(domain.begin("chen_shouzhuo", "shi_tou").ok, "different actual bodies begin an independent encounter beside the lesson")
	runner.assert_true(domain.cast("chen_shouzhuo", "qi_bolt", Vector2.RIGHT).ok, "independent encounter launches the actual projectile toward the teaching bystander")
	runner.assert_true(world.advance_to_ms(700), "original projectile physically reaches the bystander before the lesson can finish")
	runner.assert_true(world.health.combat_burden("su_zhi") > 0, "lesson interruption is backed by an actual unabsorbed original impact")
	runner.assert_eq(domain.lessons["conflict:lesson:1"].status, "interrupted", "unabsorbed third-party contact interrupts the actual lesson")
	runner.assert_eq(domain.lessons["conflict:lesson:1"].finished_ms, 650, "lesson interruption uses the precise original contact instant")
	runner.assert_true(bool(world.regions.home.actors.su_zhi.autonomous) and not bool(world.regions.home.actors.player.autonomous), "interrupted lesson restores each original participant's own autonomy")
	runner.assert_true(not domain.conflict_for("chen_shouzhuo").is_empty(), "bystander lesson interruption does not cancel the separate actual hostile encounter")
	_check_json_restore(runner, world, "real bystander interruption with independent ongoing encounter")
	domain.cancel("chen_shouzhuo")
	runner.assert_true(world.advance_to_ms(60000), "shared time passes the old interrupted lesson deadline")
	runner.assert_true(not domain.knows("player", "qi_guard"), "an interrupted bystander lesson never grants its unfinished method later")
	_check_json_restore(runner, world, "retained interruption after its former teaching deadline")


func _cross_owner_same_place(runner: Object) -> void:
	var world: RegionalSimulation = Support.make(runner)
	if world == null:
		return
	var domain: SimConflicts = world.conflicts
	var teacher: String = "river_chen_shouzhuo"
	var distant: String = Support.canonical(domain.to_dict())
	runner.assert_true(not domain.teach(teacher, "player").ok, "different original owners cannot substitute for actually approaching a distant teacher")
	runner.assert_true(not domain.begin("chen_shouzhuo", teacher).ok, "cross-owner enemy still must actually be nearby")
	runner.assert_eq(Support.canonical(domain.to_dict()), distant, "distant cross-owner requests allocate no lesson or encounter")
	var origin: Vector2 = SimRouteTravel.point(domain.body(teacher))
	world.regions.home.set_actor_position("player", origin + Vector2(0, 64))
	world.invalidate_region("home")
	var answer: Dictionary = domain.teach(teacher, "player")
	runner.assert_true(answer.ok, "original river teacher and visiting home-owned body can demonstrate at their one shared physical location")
	if not answer.ok:
		return
	var lesson_id: String = "conflict:lesson:1"
	runner.assert_eq(domain.lessons[lesson_id].region, "river", "lesson context follows the teacher's existing owner")
	runner.assert_eq(domain.home("player"), "home", "learning across the boundary never migrates or duplicates the pupil's body")
	_check_json_restore(runner, world, "same-place cross-owner lesson in flight")
	var bad: Dictionary = domain.to_dict()
	bad.lessons[lesson_id].region = "home"
	_reject(runner, bad, domain, "lesson record assigned to the pupil instead of original teacher")
	bad = domain.to_dict()
	bad.lessons[lesson_id].pupil_position[0] += float(domain.rules.lesson_radius) + 1.0
	_reject(runner, bad, domain, "cross-owner lesson at a fabricated distant teaching position")
	runner.assert_true(world.advance_to_ms(int(domain.lessons[lesson_id].due_ms)), "actual cross-owner lesson consumes the same shared duration")
	runner.assert_true(domain.knows("player", "qi_bolt"), "only the completed original foreign teacher grants the visiting pupil a real method")
	world.regions.home.set_actor_position("player", origin + Vector2(float(domain.rules.engage_radius) + 1.0, 0))
	world.invalidate_region("home")
	runner.assert_true(not domain.begin("player", teacher).ok, "already trained visiting body still cannot declare a distant encounter")
	world.regions.home.set_actor_position("player", origin + Vector2(0, 80))
	world.invalidate_region("home")
	answer = domain.begin("player", teacher)
	runner.assert_true(answer.ok, "learned visiting body can declare an actual same-place cross-owner encounter")
	if not answer.ok:
		return
	var encounter_id: String = domain.conflict_for("player")
	runner.assert_eq(domain.conflicts[encounter_id].region, "river", "encounter context follows the defender without changing either body owner")
	bad = domain.to_dict()
	bad.conflicts[encounter_id].region = "home"
	_reject(runner, bad, domain, "cross-owner encounter assigned to the initiator instead of original defender")
	runner.assert_true(domain.cast("player", "qi_bolt", Vector2.UP).ok, "visiting body pays its original home qi for a projectile aimed at the actual river body")
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + int(domain.rules.methods.qi_bolt.prepare_ms)), "cross-owner paid projectile reaches its original emission boundary")
	_check_json_restore(runner, world, "same-place cross-owner projectile in flight")
	var restored: RegionalSimulation = Support.valid_restore(runner, world)
	if restored == null:
		return
	var future: int = world.elapsed_ms + 2000
	runner.assert_true(world.advance_to_ms(future) and restored.advance_to_ms(future), "both actual body owners continue the same foreign encounter after independent restore")
	runner.assert_eq(Support.canonical(restored.to_dict()), Support.canonical(world.to_dict()), "cross-owner contact, counteractions and original qi/health retain exactly the same complete future")
	domain.cancel(teacher)
	_check_json_restore(runner, world, "cross-owner defender's actual withdrawal")


func _guard_json_boundaries(runner: Object) -> void:
	var world: RegionalSimulation = Support.make(runner)
	if world == null:
		return
	var domain: SimConflicts = world.conflicts
	runner.assert_true(domain.begin("chen_shouzhuo", "shi_tou").ok, "original capable bodies begin the guard restore boundary scenario")
	runner.assert_true(domain.cast("chen_shouzhuo", "qi_guard", Vector2.RIGHT).ok, "original qi pays for the guard whose JSON history will be restored")
	for at_ms: int in [0, 149, 150, 499, 500]:
		runner.assert_true(world.advance_to_ms(at_ms), "guard restore scenario reaches actual phase %d" % at_ms)
		_check_json_restore(runner, world, "guard phase %d" % at_ms)
		if at_ms != 150:
			continue
		var parsed: Dictionary = JSON.parse_string(Support.canonical(domain.to_dict()))
		for fault: String in ["boolean_capacity", "fractional_capacity", "text_capacity", "negative_capacity", "boolean_expiry", "fractional_expiry", "text_expiry", "extra_field", "missing_field", "wrong_action", "extra_actor", "non_record"]:
			var bad: Dictionary = parsed.duplicate(true)
			match fault:
				"boolean_capacity": bad.barriers.chen_shouzhuo.remaining = true
				"fractional_capacity": bad.barriers.chen_shouzhuo.remaining += 0.5
				"text_capacity": bad.barriers.chen_shouzhuo.remaining = "12"
				"negative_capacity": bad.barriers.chen_shouzhuo.remaining = -1
				"boolean_expiry": bad.barriers.chen_shouzhuo.until_ms = true
				"fractional_expiry": bad.barriers.chen_shouzhuo.until_ms += 0.5
				"text_expiry": bad.barriers.chen_shouzhuo.until_ms = "2550"
				"extra_field": bad.barriers.chen_shouzhuo.gratis = true
				"missing_field": bad.barriers.chen_shouzhuo.erase("action")
				"wrong_action": bad.barriers.chen_shouzhuo.action = "conflict:action:2"
				"extra_actor": bad.barriers.player = bad.barriers.chen_shouzhuo.duplicate(true)
				"non_record": bad.barriers.chen_shouzhuo = []
			_reject(runner, bad, domain, "JSON guard " + fault)
	domain.cancel("chen_shouzhuo")
	_check_json_restore(runner, world, "paid guard lingers after encounter ends")
	runner.assert_true(world.advance_to_ms(2549), "lingering guard reaches the last millisecond before expiry")
	_check_json_restore(runner, world, "guard at expiry minus one")
	runner.assert_true(world.advance_to_ms(2550), "lingering guard reaches its exact expiry")
	runner.assert_true(domain.barriers.is_empty(), "exact expiry removes the original guard rather than renewing it")
	_check_json_restore(runner, world, "guard at exact expiry")


func _check_json_restore(runner: Object, world: RegionalSimulation, label: String) -> void:
	var before: String = Support.canonical(world.to_dict())
	var parsed: Dictionary = JSON.parse_string(Support.canonical(world.conflicts.to_dict()))
	runner.assert_true(Schema.validate(parsed, world.conflicts), label + " accepts integral JSON numbers in the independently reconstructed history")
	var restored: RegionalSimulation = Support.make(runner)
	if restored == null:
		return
	var accepted: bool = restored.restore(JSON.parse_string(before))
	runner.assert_true(accepted, label + " restores the whole world through JSON")
	if accepted:
		runner.assert_eq(Support.canonical(restored.to_dict()), before, label + " retains the exact canonical joint state")
	runner.assert_eq(Support.canonical(world.to_dict()), before, label + " leaves the original world unchanged")


func _projectile(runner: Object) -> void:
	var world: RegionalSimulation = Support.make(runner)
	if world == null:
		return
	var domain: SimConflicts = world.conflicts
	world.regions.home.set_actor_cell("shi_tou", SimRouteTravel.cell(world.regions.home.places.kitchen.cell) + Vector2i(3, 0))
	world.invalidate_region("home")
	runner.assert_true(domain.begin("chen_shouzhuo", "shi_tou").ok, "two originally capable people enter a real projectile encounter")
	runner.assert_true(domain.cast("chen_shouzhuo", "qi_bolt", Vector2.RIGHT).ok, "real ranged technique pays original qi")
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + int(domain.rules.methods.qi_bolt.prepare_ms)), "original projectile is emitted at the actual boundary")
	var emitted: Dictionary = domain.to_dict()
	_check(runner, emitted, domain, "real newly emitted projectile")
	if not emitted.projectiles.is_empty():
		for fault: String in ["deleted_shot", "teleported_shot", "free_distance", "changed_direction", "future_shot", "fake_end"]:
			var bad: Dictionary = emitted.duplicate(true)
			var id: String = str(bad.projectiles.keys()[0])
			match fault:
				"deleted_shot": bad.projectiles.erase(id)
				"teleported_shot": bad.projectiles[id].position[0] += 100
				"free_distance": bad.projectiles[id].travelled += 100
				"changed_direction": bad.projectiles[id].direction = [0, 1]
				"future_shot": bad.projectiles[id].last_ms = world.elapsed_ms + 1
				"fake_end": bad.actions[id].projectile_end = {"at_ms": world.elapsed_ms, "reason": "range", "position": bad.projectiles[id].position, "travelled": 0}
			_reject(runner, bad, domain, fault)
	domain.cancel("chen_shouzhuo")
	_check(runner, domain.to_dict(), domain, "yielding keeps a launched projectile in flight")
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 2000), "real launched projectile continues after the encounter ends")
	_check(runner, domain.to_dict(), domain, "projectile terminates with a result receipt")


func _guarded_contact_and_retreat(runner: Object) -> void:
	var world: RegionalSimulation = Support.make(runner)
	if world == null:
		return
	var domain: SimConflicts = world.conflicts
	var origin: Vector2i = SimRouteTravel.cell(world.regions.home.places.kitchen.cell)
	for actor: String in world.regions.home.actors:
		world.regions.home.set_actor_cell(actor, origin + Vector2i(20, 20))
	world.regions.home.set_actor_cell("shi_tou", origin)
	world.regions.home.set_actor_cell("chen_shouzhuo", origin + Vector2i(1, 0))
	world.regions.home.actors.chen_shouzhuo.autonomous = true
	world.invalidate_region("home")
	runner.assert_true(domain.begin("shi_tou", "chen_shouzhuo").ok, "original capable bodies face each other in a real guarded encounter")
	runner.assert_true(domain.cast("shi_tou", "qi_guard", Vector2.RIGHT).ok, "initiator prepares a real guard before the defender reacts")
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 1500), "defender reacts and its real projectile reaches the guarded body")
	var state: Dictionary = domain.to_dict()
	_check(runner, state, domain, "real absorbed projectile contact")
	var guarded_id: String = ""
	for id: String in state.hits:
		if int(state.hits[id].absorbed) > 0:
			guarded_id = id
	if guarded_id.is_empty():
		runner.assert_true(false, "contact fixture genuinely contains a guard absorption rather than skipping contact validation")
		return
	runner.assert_eq(int(state.hits[guarded_id].impact), 0, "matching actual guard capacity absorbs the whole original light projectile")
	for fault: String in ["leaked_guard", "double_hit", "unlaunched_hit", "false_segment", "wrong_attacker", "extra_impact"]:
		var bad: Dictionary = state.duplicate(true)
		var hit: Dictionary = bad.hits[guarded_id]
		match fault:
			"leaked_guard":
				hit.guard_action = ""
				hit.impact += int(hit.absorbed)
				hit.absorbed = 0
			"double_hit":
				var id: String = "conflict:hit:%d" % int(bad.next_hit_id)
				bad.hits[id] = hit.duplicate(true)
				bad.hits[id].id = id
				bad.next_hit_id += 1
			"unlaunched_hit": bad.actions[hit.action].emitted = false
			"false_segment": hit.segment_from[0] -= 100
			"wrong_attacker": hit.attacker = hit.actor
			"extra_impact": hit.impact += 1
		_reject(runner, bad, domain, fault)
	domain.cancel("chen_shouzhuo")
	var retreating: Dictionary = domain.to_dict()
	_check(runner, retreating, domain, "defender physically withdraws after yielding")
	var encounter_id: String = str(retreating.conflicts.keys()[0])
	if retreating.conflicts[encounter_id].withdrawal.is_empty():
		runner.assert_true(false, "defender yield creates a real withdrawing body")
		return
	runner.assert_true(Schema.cross_valid(domain), "real active withdrawal has one body at the saved origin plus travelled distance")
	for fault: String in ["missing_retreat", "distance", "finished_early", "direction"]:
		var bad: Dictionary = retreating.duplicate(true)
		match fault:
			"missing_retreat": bad.conflicts[encounter_id].withdrawal.clear()
			"distance": bad.conflicts[encounter_id].withdrawal.distance = float(domain.rules.retreat_distance) + 1.0
			"finished_early": bad.conflicts[encounter_id].withdrawal.finished_ms = world.elapsed_ms
			"direction": bad.conflicts[encounter_id].withdrawal.direction = [0.0, 0.0]
		_reject(runner, bad, domain, "withdrawal " + fault)
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 2000), "withdrawing original NPC actually spends time stepping away")
	_check(runner, domain.to_dict(), domain, "completed original body withdrawal")


func _check(runner: Object, data: Dictionary, domain: SimConflicts, label: String) -> void:
	var before: String = Support.canonical(domain.to_dict())
	runner.assert_true(Schema.validate(data, domain), label + " candidate validates")
	runner.assert_eq(Support.canonical(domain.to_dict()), before, label + " validation leaves the live authority unchanged")


func _reject(runner: Object, bad: Dictionary, domain: SimConflicts, label: String) -> void:
	var before: String = Support.canonical(domain.to_dict())
	var input: String = Support.canonical(bad)
	runner.assert_true(not Schema.validate(bad, domain), "rejects altered conflict candidate: " + label)
	runner.assert_eq(Support.canonical(domain.to_dict()), before, "rejected candidate changes no live fact: " + label)
	runner.assert_eq(Support.canonical(bad), input, "rejected candidate is not silently repaired: " + label)
