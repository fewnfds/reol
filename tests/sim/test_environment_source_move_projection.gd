extends RefCounted
## Forecasts use actual lifecycle preflights; they never move the source owner.
## The lifecycle remains the sole authority for occupancy and final publication.

const LifecycleFixture = preload("res://tests/sim/test_object_lifecycle.gd")
const SourceFixture = preload("res://tests/sim/test_environment_source_bindings.gd")
const Definitions = preload("res://scripts/data/environment_source_definitions.gd")
const Bindings = preload("res://scripts/sim/environment_source_bindings.gd")

var _fixture := LifecycleFixture.new()
var _sources := SourceFixture.new()


func run(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._world(runner)
	if world == null:
		return
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var spawn: Dictionary = lifecycle.execute(_fixture._spawn("projection_wide", "projection_slab", "stone_slab", [127, 120]))
	runner.assert_true(bool(spawn.get("ok", false)), "a real two-cell artifact enters the world")
	if not bool(spawn.get("ok", false)):
		return
	var definitions := Definitions.new()
	var query := Bindings.new()
	if not definitions.configure(_sources._definitions()) or not query.configure(world, definitions):
		runner.assert_true(false, "the real world and definitions bind")
		return
	var move: Dictionary = _fixture._move("projection_move", "projection_slab", spawn.to, _fixture._ground(131, 120))
	var opened: Dictionary = lifecycle.prepare_move_plan(move)
	runner.assert_true(bool(opened.get("ok", false)), "the real lifecycle preflights the whole move")
	if not bool(opened.get("ok", false)):
		return
	var before: String = _fixture._state(world)
	var forecast: Dictionary = query.project_move(opened.plan)
	runner.assert_true(bool(forecast.get("ok", false)), "a preflighted future position can be projected")
	if not bool(forecast.get("ok", false)):
		return
	runner.assert_eq(forecast.operation, "set", "ground to ground changes one source")
	runner.assert_eq(forecast.reference, {"kind": "artifact", "id": "projection_slab"}, "the existing artifact remains the identity")
	runner.assert_eq(forecast.before.cell, Vector2i(127, 120), "old source uses the original two-cell footprint anchor")
	runner.assert_eq(forecast.after.cell, Vector2i(131, 120), "future source uses the same footprint anchor at the destination")
	runner.assert_eq(forecast.field_change.cell, Vector2i(131, 120), "candidate field input uses the future source origin")
	runner.assert_eq(forecast.field_change.radius, 4, "candidate radius comes from the original definition profile")
	runner.assert_eq(Array(forecast.field_change.channels), [100, 0, 0, 0, 1000, 0, 0], "candidate channels retain the established packed order")
	runner.assert_eq(_fixture._state(world), before, "forecasting does not move, duplicate or revise the original world")
	runner.assert_eq(query.project(forecast.reference).cell, Vector2i(127, 120), "ordinary projection still sees the original source")
	forecast.after.elements[2] = 99
	forecast.field_change.channels[4] = 99
	var again: Dictionary = query.project_move(opened.plan)
	runner.assert_eq(again.after.elements, [0, 0, 1000, 100, 0], "forecast results cannot mutate the source definition")
	runner.assert_eq(again.field_change.channels[4], 1000, "packed forecast buffers are detached")

	# An authentic preflight becomes stale when another ground placement changes
	# the original ground revision, before any speculative source can be used.
	var blocker: Dictionary = lifecycle.execute(_fixture._spawn("projection_other", "projection_other_item", "plain_slate", [140, 120]))
	runner.assert_true(bool(blocker.get("ok", false)), "an independent real placement updates the ground epoch")
	runner.assert_eq(query.project_move(opened.plan).get("reason"), "stale_plan", "the old candidate cannot survive an owner revision")
	var blocked: Dictionary = lifecycle.prepare_move_plan(_fixture._move("projection_occupied", "projection_slab", spawn.to, _fixture._ground(140, 120)))
	runner.assert_true(not bool(blocked.get("ok", true)), "the original lifecycle rejects an occupied target before projection")
	var fresh: Dictionary = lifecycle.prepare_move_plan(move)
	runner.assert_true(bool(fresh.get("ok", false)), "the original move can be preflighted again")
	if not bool(fresh.get("ok", false)):
		return
	var tampered: Dictionary = {"request": fresh.plan.request, "reference": fresh.plan.reference,
		"from": fresh.plan.from, "target": fresh.plan.target, "size": fresh.plan.size,
		"definition": fresh.plan.definition, "at_ms": int(fresh.plan.at_ms) + 1,
		"ground_revision": fresh.plan.ground_revision, "artifact_generation": fresh.plan.artifact_generation}
	runner.assert_eq(query.project_move(tampered).get("reason"), "stale_plan", "a plan from another time is rejected")
	var installed: Dictionary = lifecycle.execute(move)
	runner.assert_true(bool(installed.get("ok", false)), "the same real artifact can then move")
	if not bool(installed.get("ok", false)):
		return
	runner.assert_eq(query.project(installed.reference).cell, Vector2i(131, 120), "the normal projection changes only after authority commits")
	runner.assert_eq(query.project_move(fresh.plan).get("reason"), "stale_plan", "a committed move cannot reuse its previous preflight")

	var pickup: Dictionary = _fixture._move("projection_pickup", "projection_slab", installed.to, _fixture._location("actor:player"))
	var pickup_plan: Dictionary = lifecycle.prepare_move_plan(pickup)
	runner.assert_true(bool(pickup_plan.get("ok", false)), "pickup is preflighted against the real owner")
	if not bool(pickup_plan.get("ok", false)):
		return
	var to_hand: Dictionary = query.project_move(pickup_plan.plan)
	runner.assert_eq(to_hand.get("operation"), "remove", "picking up removes the ground source")
	runner.assert_eq(to_hand.get("field_change"), {}, "removal does not invent a replacement source")
	var held: Dictionary = lifecycle.execute(pickup)
	runner.assert_true(bool(held.get("ok", false)), "the real object is now held")
	if not bool(held.get("ok", false)):
		return
	var drop: Dictionary = _fixture._move("projection_drop", "projection_slab", held.to, _fixture._ground(151, 120))
	var drop_plan: Dictionary = lifecycle.prepare_move_plan(drop)
	runner.assert_true(bool(drop_plan.get("ok", false)), "dropping the same held object is preflighted")
	if not bool(drop_plan.get("ok", false)):
		return
	var to_ground: Dictionary = query.project_move(drop_plan.plan)
	runner.assert_eq(to_ground.get("operation"), "set", "dropping projects a ground source")
	runner.assert_eq(to_ground.before.status, "no_source", "the carried object contributes no ground source")
	runner.assert_eq(to_ground.after.cell, Vector2i(151, 120), "the footprint remains anchored at the new location")
	runner.assert_eq(query.project(installed.reference).get("reason"), "unsupported_location", "forecasting the drop does not place the held object")

	var zero_raw: Dictionary = _sources._definitions()
	zero_raw.bindings.artifacts.stone_slab = "none"
	var zero_definitions := Definitions.new()
	var zero_query := Bindings.new()
	if zero_definitions.configure(zero_raw) and zero_query.configure(world, zero_definitions):
		var zero: Dictionary = zero_query.project_move(drop_plan.plan)
		runner.assert_true(bool(zero.get("ok", false)), "an explicit non-emitter can be forecast")
		runner.assert_eq(zero.get("operation"), "none", "moving an explicit non-emitter does not create a field source")
	else:
		runner.assert_true(false, "the explicit zero-profile configuration binds")

	world.target_ms = world.elapsed_ms + 1
	runner.assert_eq(query.project_move(drop_plan.plan).get("reason"), "world_has_backlog", "ordinary forecasts cannot skip world time debt")
	runner.assert_eq(query.project_move(drop_plan.plan, RefCounted.new()).get("reason"), "invalid_event_context", "a foreign token cannot grant access to an incomplete event")
	world.target_ms = world.elapsed_ms
	print("SCENARIO environmental source move projection: one original identity, planned geometry, stale owners and strict event context")
