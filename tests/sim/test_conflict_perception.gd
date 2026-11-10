extends RefCounted
## Observers keep one finite spatial clue; physics and hidden facts stay separate.

const Combat = preload("res://tests/sim/test_conflicts.gd")
const Perception = preload("res://scripts/sim/conflict_perception.gd")
const ARENA := Vector2(3232.0, 3232.0)
var _combat := Combat.new()


class PerceptionMap extends WorldMapData:
	var cover: Dictionary = {}
	var levels: Dictionary = {}


	func get_terrain(cell: Vector2i) -> int:
		return TERRAIN_ROCK if cover.has(cell) else TERRAIN_GRASS


	func get_elevation(cell: Vector2i) -> int:
		return int(levels.get(cell, 0))


	func independent_copy() -> WorldMapData:
		var copy := PerceptionMap.new()
		copy.cover = cover.duplicate(true)
		copy.levels = levels.duplicate(true)
		return copy


func run(runner: Object) -> void:
	_visibility_uses_the_observer(runner)
	_hidden_motion_and_memory(runner)
	_only_visible_hostile_windups(runner)
	_cross_encounter_projectiles(runner)
	_same_encounter_does_not_grant_sight(runner)
	_unknown_retreat_uses_own_facing(runner)
	_memory_candidate_and_future(runner)
	_fine_and_sparse(runner)
	print("SCENARIO conflict perception: actual observer geometry, hidden movement and windups, finite last sight, cross-encounter incoming shots, memory candidates and deterministic continuation")


func _world(runner: Object, swords: Array[String] = []) -> RegionalSimulation:
	var world: RegionalSimulation = _combat._world(runner, swords)
	if world != null:
		world.bind_map_data(PerceptionMap.new())
	return world


func _map(world: RegionalSimulation) -> PerceptionMap:
	return world.map_data as PerceptionMap


func _point(world: RegionalSimulation, actor: String) -> Vector2:
	return SimRouteTravel.point(world.conflicts.body(actor))


func _row(world: RegionalSimulation) -> Dictionary:
	return world.conflicts.conflicts.values()[0]


func _sight(world: RegionalSimulation, actor: String) -> Dictionary:
	return _row(world).people[actor].sight


func _visibility_uses_the_observer(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	_combat._pair(world, "chen_shouzhuo", "su_zhi", Vector2(300.0, 0.0))
	var sight: Vector2 = _point(world, "chen_shouzhuo")
	runner.assert_true(Perception.can_see(world.conflicts, "su_zhi", sight, 0), "original observer can see a nearby unobstructed person")
	var radius: float = float(world.conflicts.rules.sight_radius)
	runner.assert_true(not Perception.can_see(world.conflicts, "su_zhi", _point(world, "su_zhi") + Vector2(radius + 1.0, 0.0), 0), "observer cannot see beyond its actual finite radius")
	_map(world).cover[Vector2i(52, 50)] = true
	runner.assert_true(not Perception.can_see(world.conflicts, "su_zhi", sight, 0), "actual rock cover blocks the observer independent of player fog")
	_map(world).cover.clear()
	_map(world).levels[TileGrid.world_to_cell(sight)] = 1
	runner.assert_true(not Perception.can_see(world.conflicts, "su_zhi", sight, 1), "person at a different height is not granted same-level combat sight")
	_map(world).levels.clear()
	# Original data ownership must not make a physically distant visitor blind.
	_combat._put(world, "river_su_zhi", _point(world, "su_zhi"))
	runner.assert_true(Perception.can_see(world.conflicts, "river_su_zhi", sight, 0), "visitor sees from its physical position rather than its original region owner")


func _hidden_fixture(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return null
	_combat._pair(world, "chen_shouzhuo", "su_zhi", Vector2(300.0, 0.0))
	world.advance_to_ms(123)
	world.conflicts.body("su_zhi").autonomous = true
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "su_zhi").ok, "finite-memory fixture starts after a real visible warning at a non-grid millisecond")
	runner.assert_eq(_sight(world, "su_zhi").get("at_ms", -1), 123, "visible warning records an actual first sight rather than an assumed past position")
	for y: int in range(45, 59):
		_map(world).cover[Vector2i(52, y)] = true
	_combat._put(world, "chen_shouzhuo", ARENA + Vector2(0.0, 160.0))
	return world


func _hidden_motion_and_memory(runner: Object) -> void:
	var world: RegionalSimulation = _hidden_fixture(runner)
	if world == null:
		return
	var original: Dictionary = _sight(world, "su_zhi").duplicate(true)
	var alternate: RegionalSimulation = _world(runner)
	if alternate == null:
		return
	alternate.bind_map_data(_map(world).independent_copy())
	var accepted: bool = alternate.restore(JSON.parse_string(_combat._canonical(world)))
	runner.assert_true(accepted, "independent pursuit starts with the same observed clue and physical cover")
	if not accepted:
		return
	_combat._put(alternate, "chen_shouzhuo", ARENA - Vector2(0.0, 160.0))
	runner.assert_true(world.advance_to_ms(973), "hidden movement advances on the shared scheduler")
	runner.assert_true(alternate.advance_to_ms(973), "a different unseen relocation advances through the same scheduler")
	runner.assert_eq(_sight(world, "su_zhi"), original, "unseen relocation does not rewrite a person's last actual spatial clue")
	runner.assert_true(_point(world, "su_zhi").x < ARENA.x + 300.0, "observer approaches the last seen place after its finite reaction")
	runner.assert_true(_point(world, "su_zhi").is_equal_approx(_point(alternate, "su_zhi")), "navigation around known cover is identical for different hidden opponent coordinates")
	runner.assert_eq(SnapshotValues.normalized(_sight(alternate, "su_zhi")), SnapshotValues.normalized(original), "alternate hidden movement also preserves the original spatial clue")
	runner.assert_true(world.conflicts.actions.is_empty(), "old spatial memory grants neither a hidden attack nor a hidden-windup shield")
	runner.assert_true(world.advance_to_ms(4300), "lost sight can age beyond the configured finite memory")
	runner.assert_true(_sight(world, "su_zhi").is_empty(), "expired sight becomes unknown instead of a permanent tracking marker")
	var stopped: Vector2 = _point(world, "su_zhi")
	world.advance_to_ms(4500)
	runner.assert_true(_point(world, "su_zhi").is_equal_approx(stopped), "unknown opponent no longer supplies a pursuit coordinate")


func _only_visible_hostile_windups(runner: Object) -> void:
	for mode: String in ["visible", "wall", "height", "guard", "away", "sword_far"]:
		var swords: Array[String] = []
		if mode == "sword_far":
			swords.append("chen_shouzhuo")
		var world: RegionalSimulation = _world(runner, swords)
		if world == null:
			return
		_combat._pair(world, "chen_shouzhuo", "su_zhi", Vector2(300.0, 0.0))
		world.conflicts.body("su_zhi").autonomous = true
		runner.assert_true(world.conflicts.begin("chen_shouzhuo", "su_zhi").ok, "windup fixture begins with actual initial visibility: " + mode)
		world.advance_to_ms(500)
		if mode == "wall":
			_map(world).cover[Vector2i(52, 50)] = true
		elif mode == "height":
			_map(world).levels[TileGrid.world_to_cell(_point(world, "chen_shouzhuo"))] = 1
		var method: String = "qi_guard" if mode == "guard" else "sword" if mode == "sword_far" else "qi_bolt"
		var direction: Vector2 = Vector2.UP if mode == "away" else Vector2.RIGHT
		runner.assert_true(world.conflicts.cast("chen_shouzhuo", method, direction).ok, "actual windup pays its cost: " + mode)
		world.advance_to_ms(600)
		var guard: Dictionary = _combat._action(world, "su_zhi", "qi_guard")
		runner.assert_eq(not guard.is_empty(), mode == "visible", "only a visible offensive windup that can reach the observer triggers guard: " + mode)


func _shot_fixture(runner: Object, mode: String) -> RegionalSimulation:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return null
	var guard_point: Vector2 = ARENA
	var shooter: Vector2 = ARENA - Vector2(300.0, 0.0)
	if mode == "short":
		guard_point = ARENA + Vector2(668.0, 0.0)
		shooter = ARENA
	_combat._pair(world, "chen_shouzhuo", "player", Vector2(0.0, 300.0), shooter)
	_combat._pair(world, "shi_tou", "su_zhi", Vector2(0.0, -80.0), guard_point + Vector2(0.0, 80.0))
	world.conflicts.body("su_zhi").autonomous = true
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "player").ok, "independent shot encounter begins: " + mode)
	runner.assert_true(world.conflicts.begin("shi_tou", "su_zhi").ok, "observer has a different actual encounter: " + mode)
	runner.assert_true(world.conflicts.cast("chen_shouzhuo", "qi_bolt", Vector2.LEFT if mode == "away" else Vector2.RIGHT).ok, "other encounter actually emits along the chosen line: " + mode)
	if mode == "wall":
		_map(world).cover[Vector2i(48, 50)] = true
	elif mode == "height":
		_map(world).levels[TileGrid.world_to_cell(guard_point)] = 1
	return world


func _cross_encounter_projectiles(runner: Object) -> void:
	for mode: String in ["toward", "away", "short", "wall", "height"]:
		var world: RegionalSimulation = _shot_fixture(runner, mode)
		if world == null:
			return
		world.advance_to_ms(1300 if mode == "short" else 650)
		var guard: Dictionary = _combat._action(world, "su_zhi", "qi_guard")
		runner.assert_eq(not guard.is_empty(), mode == "toward", "incoming projectile is judged by actual sight, height, direction and remaining range across encounter IDs: " + mode)
		if mode == "toward":
			runner.assert_eq(guard.started_ms, 600, "other encounter's visible threat is recognized at the observer's first free reaction boundary")
			runner.assert_true(world.conflicts.projectiles.size() == 1, "guard decision concerns a genuinely in-flight projectile")


func _same_encounter_does_not_grant_sight(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	_combat._pair(world, "chen_shouzhuo", "su_zhi", Vector2(300.0, 0.0))
	world.conflicts.body("su_zhi").autonomous = true
	world.conflicts.begin("chen_shouzhuo", "su_zhi")
	# Move both the physical caster and emitted shot outside the observer's eye.
	_combat._put(world, "chen_shouzhuo", ARENA - Vector2(350.0, 0.0))
	world.conflicts.cast("chen_shouzhuo", "qi_bolt", Vector2.LEFT)
	world.advance_to_ms(650)
	runner.assert_eq(world.conflicts.projectiles.size(), 1, "same encounter contains a real remote receding projectile")
	runner.assert_true(_combat._action(world, "su_zhi", "qi_guard").is_empty(), "sharing an encounter does not reveal an unseen receding shot")


func _unknown_retreat_uses_own_facing(runner: Object) -> void:
	var world: RegionalSimulation = _hidden_fixture(runner)
	if world == null:
		return
	world.advance_to_ms(4300)
	runner.assert_true(_sight(world, "su_zhi").is_empty(), "retreat fixture has genuinely lost its spatial clue")
	world.conflicts.body("su_zhi").facing = [0.0, -1.0]
	_combat._put(world, "chen_shouzhuo", ARENA + Vector2(0.0, 240.0))
	world.conflicts.cancel("su_zhi")
	var direction: Array = _row(world).withdrawal.direction
	runner.assert_eq(direction, [0.0, 1.0], "unknown retreat follows the person's own backward direction instead of the opponent's hidden location")


func _memory_candidate_and_future(runner: Object) -> void:
	var world: RegionalSimulation = _hidden_fixture(runner)
	if world == null:
		return
	world.advance_to_ms(973)
	var saved: Dictionary = JSON.parse_string(_combat._canonical(world))
	var restored: RegionalSimulation = _world(runner)
	if restored == null:
		return
	restored.bind_map_data(world.map_data.independent_copy())
	var accepted: bool = restored.restore(saved)
	runner.assert_true(accepted, "independent candidate accepts a genuine past sight after its old line has become obstructed")
	if not accepted:
		return
	runner.assert_eq(_combat._canonical(restored), _combat._canonical(world), "JSON restore preserves the whole present, including finite spatial evidence")
	for corruption: String in ["future", "radius", "level", "extra", "missing", "activation"]:
		var forged: Dictionary = saved.duplicate(true)
		var sight: Dictionary = forged.conflicts.conflicts.values()[0].people.su_zhi.sight
		match corruption:
			"future": sight.at_ms = int(saved.elapsed_ms) + 1
			"radius": sight.observer_position[0] = float(sight.position[0]) + float(world.conflicts.rules.sight_radius) + 100.0
			"level": sight.level = 4
			"extra": sight["hidden_target_action"] = "fictional"
			"missing": forged.conflicts.conflicts.values()[0].people.su_zhi.erase("sight")
			"activation": forged.conflicts.perception_since_ms = int(saved.elapsed_ms) + 1
		var before: String = _combat._canonical(restored)
		runner.assert_true(not restored.restore(forged), "strict spatial-memory candidate rejects " + corruption)
		runner.assert_eq(_combat._canonical(restored), before, "rejected spatial-memory candidate leaves all original state untouched: " + corruption)
	world.advance_to_ms(4500)
	restored.advance_to_ms(4500)
	runner.assert_eq(_combat._canonical(restored), _combat._canonical(world), "independent restored memory expires into the identical full future")


func _fine_and_sparse(runner: Object) -> void:
	var sparse: RegionalSimulation = _hidden_fixture(runner)
	var fine: RegionalSimulation = _hidden_fixture(runner)
	if sparse == null or fine == null:
		return
	runner.assert_true(sparse.advance_to_ms(4500), "absent observer advances directly through memory expiry")
	var reached: bool = true
	for at_ms: int in range(140, 4500, 17):
		reached = fine.advance_to_ms(at_ms) and reached
	reached = fine.advance_to_ms(4500) and reached
	runner.assert_true(reached, "nearby observer reaches the same end through irregular fine updates")
	runner.assert_eq(_combat._canonical(fine), _combat._canonical(sparse), "perception and hidden pursuit share exactly one future across fine and sparse stepping")
