extends RefCounted
## High world coordinates must not invalidate an actually simulated diagonal shot.

const Combat = preload("res://tests/sim/test_conflicts.gd")
const ORIGIN := Vector2(30123.125, 29011.375)
const DIRECTION := Vector2(-0.8864195346832275, 0.4628826081752777)
var _combat := Combat.new()


func run(runner: Object) -> void:
	_diagonal_contact_and_future(runner)
	_full_range(runner)
	_legacy_inflight_rounding(runner)
	print("SCENARIO projectile precision: high-coordinate diagonal contact/range, bounded float32 evidence, old in-flight positions, false lateral displacement and identical complete futures")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _combat._world(runner)
	if world != null:
		world.bind_map_data(Combat.CoverMap.new())
	return world


func _flight(runner: Object, bystander: bool = true) -> RegionalSimulation:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return null
	_combat._pair(world, "chen_shouzhuo", "player", Vector2(0.0, -300.0), ORIGIN)
	runner.assert_true(world.advance_to_ms(123), "precision scenario begins at an arbitrary common millisecond")
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "player").ok, "real high-coordinate encounter starts")
	runner.assert_true(world.conflicts.cast("chen_shouzhuo", "qi_bolt", DIRECTION).ok, "original body pays for a real diagonal projectile")
	var action: Dictionary = world.conflicts.actions.values()[0]
	if bystander:
		_combat._put(world, "lao_zhou", ORIGIN + _v(action.direction) * 540.0)
	runner.assert_true(world.advance_to_ms(673), "actual preparation emits and advances the projectile one step")
	runner.assert_eq(world.conflicts.projectiles.size(), 1, "precision scenario contains a real travelling shot")
	# Yielding is a real command. Its emitted projectile continues without
	# introducing another AI movement/attack variable into this geometry test.
	world.conflicts.cancel("chen_shouzhuo")
	runner.assert_true(world.conflicts.conflict_for("chen_shouzhuo").is_empty() and world.conflicts.projectiles.size() == 1, "real yielding leaves the already paid projectile in flight")
	return world


func _copy(world: RegionalSimulation, runner: Object, label: String) -> RegionalSimulation:
	var restored: RegionalSimulation = _world(runner)
	if restored == null:
		return null
	var accepted: bool = restored.restore(JSON.parse_string(_combat._canonical(world)))
	runner.assert_true(accepted, label + " accepts every real joint fact in an independent candidate")
	return restored if accepted else null


func _diagonal_contact_and_future(runner: Object) -> void:
	var sparse: RegionalSimulation = _flight(runner)
	if sparse == null:
		return
	runner.assert_true(sparse.advance_to_ms(1023), "high-coordinate diagonal travels eight actual steps")
	var shot: Dictionary = sparse.conflicts.projectiles.values()[0]
	var ideal: Vector2 = _v(shot.origin) + _v(shot.direction) * float(shot.travelled)
	runner.assert_eq(shot.position, [ideal.x, ideal.y], "new shot positions derive from emission and scalar travel without repeated coordinate drift")
	var fine: RegionalSimulation = _copy(sparse, runner, "actual diagonal in-flight save")
	if fine == null:
		return
	runner.assert_true(sparse.advance_to_ms(2200), "sparse world resolves the long diagonal shot")
	var reached: bool = true
	for now: int in range(1040, 2201, 17):
		reached = fine.advance_to_ms(now) and reached
	reached = fine.advance_to_ms(2200) and reached
	runner.assert_true(reached, "fine displayed steps reach the same post-contact common time")
	runner.assert_eq(_combat._canonical(fine), _combat._canonical(sparse), "diagonal contact, costs, injury and unrelated world facts have the identical fine/sparse future")
	runner.assert_eq(sparse.conflicts.hits.size(), 1, "long diagonal genuinely strikes the original bystander")
	if sparse.conflicts.hits.is_empty():
		return
	var hit: Dictionary = sparse.conflicts.hits.values()[0]
	runner.assert_eq(hit.actor, "lao_zhou", "actual swept contact belongs to the original bystander body")
	runner.assert_true(SimConflicts.Schema.validate(sparse.conflicts.to_dict(), sparse.conflicts), "high-coordinate contact geometry accepts its own real evidence")
	_copy(sparse, runner, "actual diagonal hit save")
	_reject_lateral_hit(sparse, runner)


func _reject_lateral_hit(world: RegionalSimulation, runner: Object) -> void:
	var present: String = _combat._canonical(world)
	var bad: Dictionary = JSON.parse_string(present)
	var hit: Dictionary = bad.conflicts.hits.values()[0]
	var action: Dictionary = bad.conflicts.actions[hit.action]
	var normal := Vector2(-float(action.direction[1]), float(action.direction[0]))
	for field: String in ["segment_from", "segment_to"]:
		var displaced: Vector2 = _v(hit[field]) + normal
		hit[field] = [displaced.x, displaced.y]
	var end: Vector2 = _v(action.projectile_end.position) + normal
	action.projectile_end.position = [end.x, end.y]
	runner.assert_true(not world.restore(bad), "coherently moving an alleged contact segment one pixel sideways still fails ray evidence")
	runner.assert_eq(_combat._canonical(world), present, "false lateral evidence leaves all live costs, bodies, injury and history untouched")


func _full_range(runner: Object) -> void:
	var world: RegionalSimulation = _flight(runner, false)
	if world == null:
		return
	runner.assert_true(world.advance_to_ms(2200), "unobstructed high-coordinate diagonal reaches its finite range")
	var action: Dictionary = world.conflicts.actions.values()[0]
	runner.assert_eq(action.projectile_end.reason, "range", "empty diagonal ends by actual range rather than an invented hit")
	runner.assert_eq(action.projectile_end.travelled, world.conflicts.rules.methods.qi_bolt.reach, "range retains the exact scalar travel budget")
	var ideal: Vector2 = _v(action.emission.origin) + _v(action.direction) * float(action.projectile_end.travelled)
	runner.assert_eq(action.projectile_end.position, [ideal.x, ideal.y], "range endpoint has no accumulated float32 lateral drift")
	runner.assert_true(SimConflicts.Schema.validate(world.conflicts.to_dict(), world.conflicts), "full-range evidence remains loadable at high world coordinates")
	_copy(world, runner, "actual maximum-range save")


func _legacy_inflight_rounding(runner: Object) -> void:
	var world: RegionalSimulation = _flight(runner)
	if world == null:
		return
	world.advance_to_ms(1023)
	var snapshot: Dictionary = JSON.parse_string(_combat._canonical(world))
	var shot: Dictionary = snapshot.conflicts.projectiles.values()[0]
	# Explicit numeric compatibility counterexample, not a replacement archive:
	# reproduce exactly the old repeated float32 addition for this real shot.
	var legacy: Vector2 = _v(shot.origin)
	var step: Vector2 = _v(shot.direction) * (float(world.conflicts.rules.methods.qi_bolt.speed) * float(world.conflicts.rules.step_ms) / 1000.0)
	@warning_ignore("integer_division")
	var steps: int = (int(shot.last_ms) - int(shot.spawned_ms)) / int(world.conflicts.rules.step_ms)
	for _index: int in range(steps):
		legacy += step
	shot.position = [legacy.x, legacy.y]
	var before: String = SnapshotValues.canonical_json(SnapshotValues.normalized(snapshot))
	var accepted: bool = world.restore(snapshot)
	runner.assert_true(accepted, "bounded old in-flight coordinate rounding remains valid")
	if not accepted:
		return
	runner.assert_eq(_combat._canonical(world), before, "restoring legacy precision preserves the original saved position and direction exactly")
	var fine: RegionalSimulation = _copy(world, runner, "legacy rounded in-flight save")
	if fine == null:
		return
	var invalid: Dictionary = JSON.parse_string(before)
	var bad_shot: Dictionary = invalid.conflicts.projectiles.values()[0]
	var offset: Vector2 = _v(bad_shot.position) + Vector2(-float(bad_shot.direction[1]), float(bad_shot.direction[0]))
	bad_shot.position = [offset.x, offset.y]
	runner.assert_true(not world.restore(invalid), "legacy rounding tolerance rejects a one-pixel lateral position fabrication")
	runner.assert_eq(_combat._canonical(world), before, "rejected in-flight fabrication cannot move or rewrite the saved shot")
	world.advance_to_ms(2200)
	for now: int in range(1040, 2201, 17):
		fine.advance_to_ms(now)
	fine.advance_to_ms(2200)
	runner.assert_eq(_combat._canonical(world), _combat._canonical(fine), "same old rounded shot has exactly the same complete future across display cadences")
	_copy(world, runner, "continued legacy shot contact save")


func _v(point: Array) -> Vector2:
	return Vector2(float(point[0]), float(point[1]))
