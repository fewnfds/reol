extends RefCounted
## Main owner of the live spatial contract: stale membership can hide a real
## body/item or reuse a removed placement. Two small original-owner worlds,
## never Main, cover geometry, updates and independent restore.

const Fixture = preload("res://tests/sim/test_object_lifecycle.gd")
var _fixture := Fixture.new()


class Observer extends RefCounted:
	var notices: Array[Dictionary] = []
	var immutable: bool = true

	func on_changed(change: Dictionary) -> void:
		immutable = immutable and change.is_read_only() and change.references.is_read_only() and change.old_cells.is_read_only() and change.new_cells.is_read_only()
		for reference: Dictionary in change.references:
			immutable = immutable and reference.is_read_only()
		notices.append(change.duplicate(true))


class ReentrantObserver extends RefCounted:
	var owner: WeakRef
	var results: Array[Dictionary] = []

	func on_changed(change: Dictionary) -> void:
		if change.reason != "projection_changed" or change.references.is_empty():
			return
		var world: RegionalSimulation = owner.get_ref()
		var kind: String = change.references[0].kind
		if kind == "avian":
			results.append(world.query_space(Rect2i(world.avian_life.body_cell("reed_sparrow"), Vector2i.ONE), [kind]))
		elif kind == "large_body":
			results.append(world.query_space(Rect2i(world.large_bodies.body_cell("later_beast"), Vector2i.ONE), [kind]))


func run(runner: Object) -> void:
	_live_originals(runner)
	_failure_and_restore(runner)
	_committed_movement_and_budget(runner)
	print("SCENARIO world space: live bounded authority queries, original movement/layers/transactions, immutable changes and rebuilt restore")


func _committed_movement_and_budget(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._world(runner)
	if world == null:
		return
	var sim: VillageSimulation = world.regions.home
	runner.assert_true(world.space.prepare().ok, "movement regression starts with a prepared projection")
	var observer := Observer.new()
	world.space.changed.connect(observer.on_changed)
	var body: Dictionary = sim.actors.player
	var destination: Vector2i = SimRouteTravel.cell(body.cell) + Vector2i(3, 0)
	var route: Dictionary = {"path": [[destination.x, destination.y]], "segment_from": body.position.duplicate(), "segment_started_ms": world.elapsed_ms, "due_ms": world.elapsed_ms + 1000}
	# This is the real regional advancement ordering: source time advances
	# before the world commits the same boundary, while its target is pending.
	world.target_ms += 1000
	sim.elapsed_ms += 1000
	sim.project_actor_route("player", route, sim.elapsed_ms)
	runner.assert_true(world.space._ready, "a source clock leading during normal advance does not discard the prepared spatial index")
	runner.assert_eq(observer.notices.back().reason, "projection_changed", "normal movement emits a local delta instead of full restored invalidation")
	world.elapsed_ms += 1000
	world.synchronize_regions()
	world.avian_life.settle_at_ms(world.elapsed_ms)
	world.large_bodies.settle_at_ms(world.elapsed_ms)
	var result: Dictionary = world.query_space(Rect2i(destination, Vector2i.ONE), ["actor"], "ground", 4)
	runner.assert_true(result.ok and result.references == [{"kind": "actor", "id": "player"}], "small local budget still works after a regional movement boundary without rebuilding every source")

	for id: String in world.avian_life.birds:
		world.avian_life.birds[id].autonomous = false
		world.avian_life.cancel(id)
		runner.assert_true(world.avian_life.command_flight(id, Vector2.RIGHT), "two original birds start concurrent flight")
	var reentrant := ReentrantObserver.new()
	reentrant.owner = weakref(world)
	world.space.changed.connect(reentrant.on_changed)
	world.advance_to_ms(world.elapsed_ms + 500)
	runner.assert_true(reentrant.results.size() >= 2, "both changed birds publish within the same original owner batch")
	for queried: Dictionary in reentrant.results:
		runner.assert_true(not queried.ok and queried.reason == "pending_projection", "reentrant batch observation cannot claim a complete result before every moved body link is current")
	var bird_cell: Vector2i = world.avian_life.body_cell("reed_sparrow")
	runner.assert_true(_at(world, bird_cell, ["avian"]).references.has({"kind": "avian", "id": "reed_sparrow"}), "the complete post-batch query finds the second moved bird")

	runner.assert_true(world.large_bodies.add_body("later_beast", "同批山兽", "river", Vector2i(170, 140), Vector2i(175, 140)), "second large body joins the original population")
	world.large_bodies.bodies.test_beast.retry_ms = world.elapsed_ms + 1
	world.large_bodies.bodies.later_beast.retry_ms = world.elapsed_ms + 1
	world.advance_to_ms(world.elapsed_ms + 1)
	reentrant.results.clear()
	world.advance_to_ms(world.elapsed_ms + ((int(world.large_bodies.definitions.step_ms) * 3) >> 2))
	runner.assert_true(reentrant.results.size() >= 2, "large-body batch also exercises reentrant observation")
	for queried: Dictionary in reentrant.results:
		runner.assert_true(not queried.ok and queried.reason == "pending_projection", "large-body partial batches explicitly reject reentrant queries")
	runner.assert_true(_at(world, world.large_bodies.body_cell("later_beast"), ["large_body"]).references.has({"kind": "large_body", "id": "later_beast"}), "second large body is present after all links commit")
	world.space.changed.disconnect(reentrant.on_changed)

	# A legitimate crowded body cell, with budget below one decoded candidate.
	world.synchronize_regions()
	for id: String in sim.actors:
		sim.set_actor_cell(id, Vector2i(125, 123))
	var limited: Dictionary = world.query_space(Rect2i(Vector2i(125, 123), Vector2i.ONE), ["actor"], "ground", 1)
	runner.assert_true(not limited.ok and limited.reason == "budget_exhausted" and limited.work_used == 1 and limited.references.is_empty(), "dense local collection stops at the candidate budget without publishing a partial set")
	var dense: Dictionary = _at(world, Vector2i(125, 123), ["actor"])
	runner.assert_true(dense.ok and dense.references.size() == sim.actors.size(), "the same dense cell returns all original bodies when budget is sufficient")


func _at(world: RegionalSimulation, cell: Vector2i, kinds: Array = [], layer: String = "") -> Dictionary:
	return world.query_space(Rect2i(cell, Vector2i.ONE), kinds, layer)


func _live_originals(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._world(runner)
	if world == null:
		return
	var sim: VillageSimulation = world.regions.home
	runner.assert_true(SimWorkplaces.enable_opening(sim.config, sim.places, sim.actors, world.map_data, str(sim.config.institution.id), sim._content.workplaces), "the original workplace owner assembles its opening geometry")
	var before: String = _fixture._state(world)
	var prepared: Dictionary = world.space.prepare()
	runner.assert_true(bool(prepared.ok), "derived membership is assembled from the existing owners")
	if not bool(prepared.ok):
		return
	var observer := Observer.new()
	world.space.changed.connect(observer.on_changed)
	var player: Dictionary = {"kind": "actor", "id": "player"}
	var origin: Vector2i = SimRouteTravel.cell(sim.actors.player.cell)
	var initial: Dictionary = _at(world, origin)
	runner.assert_true(initial.ok and initial.complete and initial.live and initial.references.has(player), "a live point query finds the original actor")
	runner.assert_eq(initial.visibility, "authority_only", "spatial truth does not become player knowledge")
	runner.assert_eq(_fixture._state(world), before, "preparation and queries do not write original state or knowledge")
	var destination := Vector2i(125, 123)
	sim.set_actor_cell("player", destination)
	runner.assert_true(not _at(world, origin, ["actor"]).references.has(player), "relocation removes the old body links")
	runner.assert_true(_at(world, destination, ["actor"]).references.has(player), "relocation enrolls the original body at its new cell")
	runner.assert_eq(observer.notices.back().old_cells, [origin], "change notice reports the actual old cells")
	runner.assert_eq(observer.notices.back().new_cells, [destination], "change notice reports the actual new cells")
	var motion := SimLocalMotion.new(JSON.parse_string(FileAccess.get_file_as_string(SimLocalMotion.RULES_PATH)))
	motion.bind_body(sim.actors.player, sim.notify_body_space_changed.bind("player"))
	motion.relocate(TileGrid.cell_to_world(destination + Vector2i.RIGHT))
	runner.assert_true(not _at(world, destination, ["actor"]).references.has(player) and _at(world, destination + Vector2i.RIGHT, ["actor"]).references.has(player), "manual motion updates the same live body projection")
	var route: Dictionary = {"path": [[128, 123]], "segment_from": sim.actors.player.position.duplicate(), "segment_started_ms": world.elapsed_ms, "due_ms": world.elapsed_ms + 1000}
	sim.project_actor_route("player", route, world.elapsed_ms + 1000)
	runner.assert_true(_at(world, Vector2i(128, 123), ["actor"]).references.has(player), "route execution publishes membership through its original owner")

	var bird: Dictionary = {"kind": "avian", "id": "moss_sparrow"}
	world.avian_life.birds.moss_sparrow.autonomous = false
	var bird_cell: Vector2i = world.avian_life.body_cell("moss_sparrow")
	runner.assert_true(_at(world, bird_cell, ["avian"], "air").references.has(bird), "an airborne body belongs to the air layer")
	runner.assert_true(world.avian_life.command_land("moss_sparrow").ok, "original avian authority lands at the same cell")
	runner.assert_true(_at(world, bird_cell, ["avian"], "ground").references.has(bird) and _at(world, bird_cell, ["avian"], "air").references.is_empty(), "a layer-only change cannot leave an airborne copy")
	runner.assert_true(world.avian_life.command_flight("moss_sparrow", Vector2.RIGHT), "the original body takes off again")
	runner.assert_true(_at(world, bird_cell, ["avian"], "air").references.has(bird), "takeoff refreshes membership without cell motion")

	var beast: Dictionary = {"kind": "large_body", "id": "test_beast"}
	var multi: Dictionary = world.query_space(Rect2i(Vector2i(111, 113), Vector2i(3, 3)), ["large_body"])
	runner.assert_true(multi.ok and multi.references == [beast], "a nine-cell body is returned once")
	runner.assert_true(world.large_bodies.add_body("later_beast", "后来的山兽", "river", Vector2i(170, 140), Vector2i(175, 140)), "a body created after preparation enrolls through its original owner")
	runner.assert_true(_at(world, Vector2i(171, 141), ["large_body"]).references.has({"kind": "large_body", "id": "later_beast"}), "a new body's non-anchor footprint cell resolves immediately")
	world.advance_to_ms(int(world.large_bodies.bodies.test_beast.retry_ms))
	var step: Dictionary = world.large_bodies.bodies.test_beast.step
	runner.assert_true(not step.is_empty(), "original large-body movement begins on the common clock")
	if not step.is_empty():
		world.advance_to_ms(int(step.started_ms) + ((int(world.large_bodies.definitions.step_ms) * 3) >> 2))
		var current: Vector2i = world.large_bodies.body_cell("test_beast")
		runner.assert_true(_at(world, current, ["large_body"]).references.has(beast), "moving multi-cell bodies refresh after their whole original settlement")
	var flown: Vector2i = world.avian_life.body_cell("moss_sparrow")
	runner.assert_true(_at(world, flown, ["avian"]).references.has(bird), "flight cell crossings keep live membership current")
	var life: SimObjectLifecycle = world.object_lifecycle
	var spawned: Dictionary = life.execute(_fixture._spawn("live_slab", "live_slab", "stone_slab", [127, 120]))
	runner.assert_true(spawned.ok, "a second multi-cell kind is created by its original owner")
	var slab: Dictionary = {"kind": "artifact", "id": "live_slab"}
	var found: Dictionary = world.query_space(Rect2i(Vector2i(127, 120), Vector2i(2, 1)), ["artifact"])
	runner.assert_true(found.ok and found.references == [slab], "both footprint cells across a bucket boundary identify one item")
	runner.assert_eq(observer.notices.back().new_cells, [Vector2i(127, 120), Vector2i(128, 120)], "committed creation describes the actual complete footprint")
	runner.assert_true(life.execute(_fixture._move("live_take", "live_slab", spawned.to, _fixture._location("actor:player"))).ok, "taking moves the unique original into its real container")
	runner.assert_true(_at(world, Vector2i(128, 120), ["artifact"]).references.is_empty(), "contained items leave the live ground query")
	runner.assert_eq(observer.notices.back().old_cells, [Vector2i(127, 120), Vector2i(128, 120)], "take notice invalidates every original footprint cell")
	var dropped: Dictionary = life.execute(_fixture._move("live_drop", "live_slab", _fixture._location("actor:player"), _fixture._ground(130, 120)))
	runner.assert_true(dropped.ok and _at(world, Vector2i(131, 120), ["artifact"]).references == [slab], "drop enters a different layout along the same index")
	runner.assert_true(life.execute({"command": "live_remove", "op": "remove", "id": "live_slab", "from": dropped.to}).ok, "removal terminates the original")
	runner.assert_true(_at(world, Vector2i(131, 120), ["artifact"]).references.is_empty(), "removal cannot leave a phantom placement")
	var stock: Dictionary = life.execute(_fixture._transfer("live_stock", _fixture._location("store"), _fixture._ground(135, 120), "wood", 1))
	runner.assert_true(stock.ok and _at(world, Vector2i(135, 120), ["stock"]).references == [stock.reference], "ground quantity entries reuse the original ledger and slot index")

	sim.set_actor_cell("player", Vector2i(108, 104))
	var cell := Vector2i(110, 107)
	var paper: Dictionary = world.construction.place("player", "wood_bed", cell)
	runner.assert_true(paper.ok, "a different structure definition creates a real blueprint")
	var reference: Dictionary = {"kind": "construction", "id": paper.get("project", "")}
	runner.assert_true(_at(world, cell, ["construction"], "planned").references == [reference] and _at(world, cell, ["construction"], "ground").references.is_empty(), "paper remains separate from physical structures")
	runner.assert_eq(observer.notices.back().reason, "structure_committed", "blueprint creation publishes a committed invalidation")
	runner.assert_true(world.construction.cancel_project("player", paper.project).ok, "original construction authority cancels paper")
	runner.assert_true(_at(world, cell, ["construction"]).references.is_empty(), "cancelled paper leaves no live spatial reference")
	var built_cell := Vector2i(111, 108)
	var door: Dictionary = world.construction.place("player", "wood_door", built_cell)
	runner.assert_true(door.ok and world.construction.begin("player", door.project).ok, "another layout uses original real construction")
	_finish_construction(runner, world)
	var door_ref: Dictionary = {"kind": "construction", "id": door.project}
	runner.assert_true(_at(world, built_cell, ["construction"], "ground").references == [door_ref] and _at(world, built_cell, ["construction"], "planned").references.is_empty(), "completion moves the one project from planned to physical projection")
	runner.assert_true(world.construction.begin("player", door.project, "demolish").ok, "demolition uses the original structure owner")
	_finish_construction(runner, world)
	runner.assert_true(_at(world, built_cell, ["construction"]).references.is_empty(), "finished demolition removes the spatial structure")
	runner.assert_true(observer.immutable, "all spatial notices and nested references are immutable")
	var footprint: Dictionary = world.describe_object({"kind": "workplace", "region": "home", "part": "walls"})
	var walls: Dictionary = _at(world, footprint.spatial.cells[0], ["workplace"])
	runner.assert_true(walls.ok and walls.references.has(footprint.reference), "fixed original nonrectangular components share the same query")


func _finish_construction(runner: Object, world: RegionalSimulation) -> void:
	for _step: int in 120:
		if not world.construction.active.has("player"):
			return
		if not world.advance_to_ms(maxi(world.elapsed_ms + 1, world.construction.next_boundary_ms())):
			break
	runner.assert_true(false, "construction reaches its terminal state within its existing bounded phases")


func _failure_and_restore(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._world(runner)
	if world == null:
		return
	var area := Rect2i(Vector2i(108, 104), Vector2i.ONE)
	var observer := Observer.new()
	world.space.changed.connect(observer.on_changed)
	world.regions.home.set_actor_cell("player", Vector2i(125, 123))
	runner.assert_eq(observer.notices.back().reason, "projection_invalidated", "subscribers receive invalidation before the first lazy rebuild")
	world.regions.home.set_actor_cell("player", area.position)
	runner.assert_eq(world.query_space(area, [], "", 1).get("reason"), "budget_exhausted", "first-use rebuild also consumes the explicit work budget")
	var notice_count: int = observer.notices.size()
	world.regions.home.set_actor_cell("player", Vector2i(125, 123))
	runner.assert_eq(observer.notices.size(), notice_count + 1, "an incomplete rebuild does not disconnect future invalidations")
	world.regions.home.set_actor_cell("player", area.position)
	runner.assert_true(world.space.prepare().ok, "an adequate budget can rebuild after an incomplete attempt")
	var before: String = _fixture._state(world)
	for args: Array in [[area, ["unknown_kind"], "", 4096], [area, [], "container", 4096], [area, [], "", 0], [Rect2i(-1, 0, 1, 1), [], "", 4096]]:
		var failed: Dictionary = world.query_space.callv(args)
		runner.assert_true(not failed.ok and not failed.complete and failed.references.is_empty(), "invalid/unsupported queries never claim a successful empty result")
	world.target_ms += 1
	runner.assert_eq(world.query_space(area).get("reason"), "pending_time", "backlog cannot masquerade as live emptiness")
	world.target_ms -= 1
	world.regions.river.elapsed_ms += 1
	runner.assert_eq(world.query_space(area, ["actor"]).get("reason"), "stale_source", "a stale remote body may enter the queried area, so the whole body result is refused")
	world.regions.river.elapsed_ms -= 1
	runner.assert_eq(_fixture._state(world), before, "failed queries never settle time or modify owners")
	var old_space: SimWorldSpace = world.space
	var saved: Dictionary = JSON.parse_string(before)
	var invalid: Dictionary = saved.duplicate(true)
	invalid.next_id = 0
	runner.assert_true(not world.restore(invalid), "invalid candidate restoration fails")
	runner.assert_true(world.space == old_space and world.query_space(area).ok, "failed restoration preserves the live service and world")
	runner.assert_true(world.restore(saved), "valid original owners replace the world atomically")
	runner.assert_true(world.space != old_space and world.query_space(area).ok, "successful restoration rebuilds derived links from the restored owners")
	runner.assert_eq(old_space.query(area).get("reason"), "world_replaced", "old handles explicitly reject replacement generations")
	runner.assert_eq(_fixture._state(world), before, "rebuilding cannot add another saved state or event history")
