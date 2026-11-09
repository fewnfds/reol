extends RefCounted


func run(runner: Object) -> void:
	_route_crossings(runner)
	var motion := SimLocalMotion.new(JSON.parse_string(FileAccess.get_file_as_string(SimLocalMotion.RULES_PATH)))
	var actor: Dictionary = {"alive": true, "active": {}, "stamina": 20}
	var start: Vector2 = TileGrid.cell_to_world(Vector2i(10, 10))
	motion.relocate(start)
	var open: Callable = func(_cell: Vector2i, _direction: Vector2i) -> bool: return true
	runner.assert_true(motion.begin_sidestep(137, Vector2.RIGHT, actor), "a real body can start a short sidestep at a fractional minute")
	runner.assert_eq(actor.stamina, 12, "sidestep spends existing body stamina once at start")
	runner.assert_true(not motion.begin_sidestep(137, Vector2.RIGHT, actor), "a second command cannot overwrite preparation/recovery")
	motion.advance(137, 237, Vector2.ZERO, open)
	runner.assert_eq(motion.position, start, "preparation does not produce displacement")
	motion.advance(237, 337, Vector2.ZERO, open)
	runner.assert_true(motion.position.is_equal_approx(start + Vector2(60, 0)), "first half of travel moves exactly sixty pixels")
	var halfway: Dictionary = JSON.parse_string(JSON.stringify(motion.to_dict()))
	var restored := SimLocalMotion.new(JSON.parse_string(FileAccess.get_file_as_string(SimLocalMotion.RULES_PATH)))
	runner.assert_true(restored.restore(halfway, motion.position, 337), "real in-flight phase/position restores through JSON")
	motion.advance(337, 687, Vector2.ZERO, open)
	restored.advance(337, 687, Vector2.ZERO, open)
	runner.assert_eq(motion.to_dict(), restored.to_dict(), "saved trajectory has identical final phase")
	runner.assert_eq(motion.position, restored.position, "saved trajectory neither replays nor skips displacement")
	runner.assert_true(motion.position.is_equal_approx(start + Vector2(120, 0)), "full trajectory has finite distance")
	runner.assert_true(motion.action.is_empty() and motion.last_outcome == "finished", "recovery finishes only at its world deadline")
	runner.assert_eq(actor.stamina, 12, "advancing or restoring cannot spend stamina again")
	var coarse := SimLocalMotion.new(JSON.parse_string(FileAccess.get_file_as_string(SimLocalMotion.RULES_PATH)))
	coarse.relocate(start)
	actor.stamina = 20
	coarse.begin_sidestep(137, Vector2.RIGHT, actor)
	coarse.advance(137, 687, Vector2.ZERO, open)
	runner.assert_eq(coarse.position, motion.position, "one coarse interval and fine phases have the same displacement")
	var wall: Callable = func(cell: Vector2i, direction: Vector2i) -> bool: return cell.x + direction.x <= 10
	var stopped := SimLocalMotion.new(JSON.parse_string(FileAccess.get_file_as_string(SimLocalMotion.RULES_PATH)))
	stopped.relocate(start)
	actor.stamina = 20
	stopped.begin_sidestep(0, Vector2.RIGHT, actor)
	stopped.advance(0, 550, Vector2.ZERO, wall)
	runner.assert_eq(stopped.cell(), Vector2i(10, 10), "fast sidestep cannot tunnel through a blocked next cell")
	runner.assert_eq(stopped.last_outcome, "blocked", "terrain obstruction has a concrete outcome")
	runner.assert_eq(actor.stamina, 12, "hitting a wall does not refund committed exertion")
	actor.stamina = 7
	runner.assert_true(not stopped.begin_sidestep(550, Vector2.RIGHT, actor), "insufficient stamina refuses the action")
	actor.stamina = 20
	stopped.begin_sidestep(550, Vector2.RIGHT, actor)
	stopped.advance(550, 600, Vector2.ZERO, open, false)
	runner.assert_true(stopped.action.is_empty() and stopped.last_outcome == "control_lost", "loss of body control interrupts short actions")
	runner.assert_eq(actor.stamina, 12, "loss of control preserves already spent stamina")
	for mutation: String in ["future", "direction", "cost", "velocity", "missing"]:
		var bad: Dictionary = halfway.duplicate(true)
		match mutation:
			"future": bad.action.started_ms = 338
			"direction": bad.action.direction = [2, 0]
			"cost": bad.action.stamina_spent = 0
			"velocity": bad.velocity = [9999, 0]
			"missing": bad.erase("action")
		var before: Dictionary = restored.to_dict()
		runner.assert_true(not restored.restore(bad, start, 337), "invalid trajectory is rejected: " + mutation)
		runner.assert_eq(restored.to_dict(), before, "invalid trajectory does not mutate live motion")
	print("SCENARIO short action: one body/cost, preparation→swept displacement→recovery, JSON resume, wall and control interruption")


func _route_crossings(runner: Object) -> void:
	# Primary geometric contract: floor-based ownership changes at the same
	# first integer millisecond used by the original segment projection.
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		for offset: Vector2 in [Vector2.ZERO, Vector2(3, -5)]:
			var body: Dictionary = {"position": [], "cell": [], "facing": [0.0, 1.0]}
			SimRouteTravel.put(body, TileGrid.cell_to_world(Vector2i(10, 10)) + offset)
			var target: Vector2i = Vector2i(10, 10) + direction
			var route: Dictionary = {"path": [[target.x, target.y]]}
			SimRouteTravel.begin_segment(route, body, 100, 96.0)
			var now: int = 100
			while SimRouteTravel.cell(body.cell) != target:
				var before: Vector2i = SimRouteTravel.cell(body.cell)
				var crossing: int = SimRouteTravel.crossing_ms(route, body, now)
				SimRouteTravel.project(route, body, crossing - 1)
				runner.assert_eq(SimRouteTravel.cell(body.cell), before, "the millisecond before a native route crossing retains its original cell")
				SimRouteTravel.project(route, body, crossing)
				runner.assert_true(SimRouteTravel.cell(body.cell) != before and crossing > now, "native route crossing uses the first actual floor-owned cell on each axis")
				if SimRouteTravel.cell(body.cell) == before or crossing <= now:
					break
				now = crossing
