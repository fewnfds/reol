extends RefCounted
## Real owners are exercised through the lifecycle; the source view must not
## create stock, advance time, or give omniscient results to a game observer.

const LifecycleFixture = preload("res://tests/sim/test_object_lifecycle.gd")
const Definitions = preload("res://scripts/data/environment_source_definitions.gd")
const Bindings = preload("res://scripts/sim/environment_source_bindings.gd")

# The fixture's navigation Callables retain this object for the entire run.
var _fixture := LifecycleFixture.new()


func run(runner: Object) -> void:
	_definition_contract(runner)
	_ground_sources_and_lifecycle(runner)
	print("SCENARIO ground environmental sources: validated signed profiles, original placements and stock, maximum composition, bounded queries and detached restoration")


func _profile(wood: int, fire: int, earth: int, metal: int, water: int, grade: int, radius: int = 4) -> Dictionary:
	return {
		"elements": {"wood": wood, "fire": fire, "earth": earth, "metal": metal, "water": water},
		"thermal_grade": grade, "radius_cells": radius,
		"activation": "intrinsic", "origin": "footprint_anchor"
	}


func _definitions() -> Dictionary:
	return {
		"version": 1,
		"profiles": {
			"none": _profile(0, 0, 0, 0, 0, 0, 2),
			"earth": _profile(0, 0, 1000, 100, 0, 0),
			"hot": _profile(0, 6000, 0, 0, 0, 4000),
			"cold": _profile(0, 2000, 0, 0, 0, -4000),
			"weak": _profile(0, 4000, 0, 0, 0, 2000)
		},
		"bindings": {
			"artifacts": {"plain_slate": "earth", "stone_slab": "earth"},
			"materials": {"wood": "hot", "grain": "cold", "herb": "weak"}
		}
	}


func _definition_contract(runner: Object) -> void:
	var raw: Dictionary = _definitions()
	var definitions: RefCounted = Definitions.new()
	if not _ok(runner, definitions.configure(raw), "source profile schema accepts a signed cold grade and ordinary profiles"):
		return
	runner.assert_true(definitions.is_configured(), "a complete candidate becomes configured")
	var digest: String = definitions.digest()
	runner.assert_eq(digest.length(), 64, "source configuration exposes a SHA-256 content digest")
	runner.assert_eq(definitions.max_radius(), 4, "the largest configured template determines local query reach")
	runner.assert_eq(definitions.profile("material", "grain").get("thermal_grade"), -4000, "cold is one negative thermal grade")
	runner.assert_eq(definitions.profile("artifact", "plain_slate").get("profile_id"), definitions.profile("artifact", "stone_slab").get("profile_id"), "two definitions can use the same source profile")
	runner.assert_eq(definitions.profile("material", "unknown").get("reason"), "profile_missing", "a missing binding is distinct from explicit zero influence")
	var before: Dictionary = definitions.to_dict()
	raw.profiles.hot.elements.fire = 1
	var exposed: Dictionary = definitions.profile("material", "wood")
	if exposed.get("elements") is Array:
		exposed.elements[1] = 1
	var exported: Dictionary = definitions.to_dict()
	exported.profiles.hot.thermal_grade = 1
	runner.assert_eq(definitions.profile("material", "wood").get("thermal_grade"), 4000, "returned definitions cannot mutate the installed profile")
	runner.assert_eq(definitions.profile("material", "wood").get("elements"), [0, 6000, 0, 0, 0], "source channels are detached from caller input and output")
	runner.assert_eq(definitions.to_dict(), before, "definition export is detached")
	runner.assert_eq(definitions.digest(), digest, "external mutation cannot change the installed digest")
	runner.assert_true(not definitions.configure(_definitions()), "an active definition set cannot be silently replaced")
	runner.assert_eq(definitions.to_dict(), before, "reconfiguration refusal retains the original candidate")

	var invalids: Array[Dictionary] = []
	var unknown_root: Dictionary = _definitions()
	unknown_root["unknown"] = 1
	invalids.append(unknown_root)
	var dual_grade: Dictionary = _definitions()
	dual_grade.profiles.hot["cold_grade"] = 1000
	invalids.append(dual_grade)
	var negative_element: Dictionary = _definitions()
	negative_element.profiles.hot.elements.fire = -1
	invalids.append(negative_element)
	var enormous_grade: Dictionary = _definitions()
	enormous_grade.profiles.hot.thermal_grade = 10001
	invalids.append(enormous_grade)
	var fractional_grade: Dictionary = _definitions()
	fractional_grade.profiles.hot.thermal_grade = 1.5
	invalids.append(fractional_grade)
	var unsupported_radius: Dictionary = _definitions()
	unsupported_radius.profiles.hot.radius_cells = 3
	invalids.append(unsupported_radius)
	var dangling: Dictionary = _definitions()
	dangling.bindings.materials.wood = "missing_profile"
	invalids.append(dangling)
	var invalid_zero: Dictionary = _definitions()
	invalid_zero.profiles.none.elements.wood = 1
	invalids.append(invalid_zero)
	for invalid: Dictionary in invalids:
		var candidate: RefCounted = Definitions.new()
		runner.assert_true(not candidate.configure(invalid), "malformed, ambiguous or unsupported profile fails before publication")
		runner.assert_true(not candidate.is_configured() and candidate.to_dict().is_empty(), "invalid configuration does not publish a partial candidate")
		runner.assert_true(candidate.configure(_definitions()), "a rejected candidate remains reusable for a valid configuration")


func _ground_sources_and_lifecycle(runner: Object) -> void:
	var world: RegionalSimulation = _fixture._world(runner)
	if world == null:
		return
	var definitions: RefCounted = Definitions.new()
	if not _ok(runner, definitions.configure(_definitions()), "source definitions install for the real world fixture"):
		return
	var query: RefCounted = Bindings.new()
	runner.assert_eq(query.sample_base(Vector2i.ZERO).get("reason"), "definitions_unavailable", "an unconfigured query refuses to invent a field")
	if not _ok(runner, query.configure(world, definitions), "an explicit source candidate binds the original world owners"):
		return
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var inventory: SimInventory = world.regions.home.inventory
	# Fixture supply is set on the real owner before the first transfer. The
	# lifecycle then makes each of the tested 1, 4, 16 and 10000-unit piles.
	inventory.containers.store.wood = 10000
	var stone: Dictionary = lifecycle.execute(_fixture._spawn("env_slab", "env_slab_instance", "stone_slab", [127, 120]))
	var movable: Dictionary = lifecycle.execute(_fixture._spawn("env_slate", "env_slate_instance", "plain_slate", [100, 120]))
	if not _ok(runner, bool(stone.get("ok", false)) and bool(movable.get("ok", false)), "two actual independent artifacts are created by their owner"):
		return
	var slab_ref: Dictionary = {"kind": "artifact", "id": "env_slab_instance"}
	var slate_ref: Dictionary = {"kind": "artifact", "id": "env_slate_instance"}
	var slab: Dictionary = query.project(slab_ref)
	runner.assert_eq(slab.get("status"), "source", "the two-cell real object projects as one source")
	runner.assert_eq(slab.get("cell"), Vector2i(127, 120), "the even-width source uses the left anchor")
	runner.assert_eq(slab.get("size"), Vector2i(2, 1), "source projection preserves the full original footprint")
	var origin: Dictionary = query.sample_base(Vector2i(127, 120))
	var neighbor: Dictionary = query.sample_base(Vector2i(128, 120))
	runner.assert_true(bool(origin.get("ok", false)) and bool(neighbor.get("ok", false)), "both sides of a bucket boundary are sampleable")
	runner.assert_eq(origin.get("source_count"), 1, "a two-cell artifact contributes one source")
	runner.assert_true(origin.get("elements") is Array and neighbor.get("elements") is Array, "successful samples expose all five element channels")
	if origin.get("elements") is Array and neighbor.get("elements") is Array:
		runner.assert_eq(origin.elements[2], 1000, "the one physical slab supplies its peak at its source point")
		runner.assert_eq(neighbor.elements[2], 750, "the second occupied cell is not a second full-strength source")

	var held: Dictionary = lifecycle.execute(_fixture._move("env_hold", "env_slate_instance", _fixture._location("ground:env_slate"), _fixture._location("actor:player")))
	if not _ok(runner, bool(held.get("ok", false)), "the original artifact moves into the player's actual container"):
		return
	runner.assert_eq(query.project(slate_ref).get("reason"), "unsupported_location", "carried items are not advertised as ordinary ground sources")
	var old_position: Dictionary = query.sample_base(Vector2i(100, 120))
	if old_position.get("elements") is Array:
		runner.assert_eq(old_position.elements, [0, 0, 0, 0, 0], "carrying the original does not leave a source duplicate")
	var dropped: Dictionary = lifecycle.execute(_fixture._move("env_drop", "env_slate_instance", held.to, _fixture._ground(101, 120)))
	if not _ok(runner, bool(dropped.get("ok", false)), "the same original artifact may return to a different ground cell"):
		return
	runner.assert_eq(query.project(slate_ref).get("cell"), Vector2i(101, 120), "ground re-entry is projected at the new original location")
	var removed: Dictionary = lifecycle.execute({"command": "env_remove", "op": "remove", "id": "env_slate_instance", "from": dropped.to.duplicate(true)})
	if not _ok(runner, bool(removed.get("ok", false)), "the real artifact is removed"):
		return
	runner.assert_eq(query.project(slate_ref).get("reason"), "not_found", "removal cannot leave a queryable source instance")

	var stock_ref: Dictionary = _stock("home", "ground:env_wood_1", "wood")
	for increment: int in [1, 3, 12, 9984]:
		var command: String = "env_wood_%d" % increment
		var transfer: Dictionary = lifecycle.execute(_fixture._transfer(command, _fixture._location("store"), _fixture._ground(130, 120), "wood", increment))
		if not _ok(runner, bool(transfer.get("ok", false)), "material is really transferred or merged by its original ledger"):
			return
		var total: int = inventory.quantity(stock_ref.container, "wood")
		var pile: Dictionary = query.project(stock_ref)
		var sample: Dictionary = query.sample_base(Vector2i(130, 120))
		runner.assert_true(bool(pile.get("ok", false)) and bool(sample.get("ok", false)), "the original active pile is available for projection and sampling")
		runner.assert_eq(pile.get("quantity"), total, "projection reads the actual current pile quantity")
		runner.assert_eq(pile.get("thermal_grade"), 4000, "one pile has constant source strength regardless of its quantity")
		runner.assert_eq(sample.get("hot_grade"), 4000, "the source peak remains unchanged as the stack grows")
		runner.assert_eq(sample.get("thermal_grade"), 4000, "positive thermal grade is not multiplied by item count")
		if sample.get("elements") is Array:
			runner.assert_eq(sample.elements[1], 6000, "five-element influence is also independent of stack quantity")
		if increment == 1:
			var diagonal: Dictionary = query.sample_base(Vector2i(131, 121))
			runner.assert_true(bool(diagonal.get("ok", false)) and absi(int(diagonal.get("hot_grade", 0)) - 2586) <= 1, "diagonal attenuation uses Euclidean square-root-two distance")
	runner.assert_eq(inventory.quantity(stock_ref.container, "wood"), 10000, "the real pile reached all four tested quantities")
	var pickup: Dictionary = lifecycle.execute(_fixture._transfer("env_split_pickup", _fixture._location(stock_ref.container), _fixture._location("actor:player"), "wood", 5))
	if not _ok(runner, bool(pickup.get("ok", false)), "a portion moves into the actual actor inventory"):
		return
	var split: Dictionary = lifecycle.execute(_fixture._transfer("env_split_drop", _fixture._location("actor:player"), _fixture._ground(131, 120), "wood", 5))
	if not _ok(runner, bool(split.get("ok", false)), "the carried portion becomes a second real ground pile"):
		return
	var split_ref: Dictionary = _stock("home", "ground:env_split_drop", "wood")
	runner.assert_eq(query.project(split_ref).get("quantity"), 5, "the split pile reads its own ledger entry")
	runner.assert_eq(query.sample_base(Vector2i(130, 120)).get("hot_grade"), 4000, "overlapping same-material piles take the maximum, never their sum")
	var merge: Dictionary = lifecycle.execute(_fixture._transfer("env_merge_again", _fixture._location(split_ref.container), _fixture._ground(130, 120), "wood", 5))
	if not _ok(runner, bool(merge.get("ok", false)), "both piles can merge through the real lifecycle"):
		return
	runner.assert_eq(query.project(split_ref).get("reason"), "not_found", "a fully merged-away pile leaves no active source")
	runner.assert_eq(query.project(stock_ref).get("quantity"), 10000, "the surviving pile owns the whole quantity exactly once")
	var collect: Dictionary = lifecycle.execute(_fixture._transfer("env_collect", _fixture._location(stock_ref.container), _fixture._location("store"), "wood", 10000))
	if not _ok(runner, bool(collect.get("ok", false)), "all material returns to its real store"):
		return
	runner.assert_eq(query.project(stock_ref).get("reason"), "not_found", "an emptied pile has no remaining source")
	runner.assert_eq(query.sample_base(Vector2i(130, 120)).get("hot_grade"), 0, "a storage container is not a ground emitter")

	_composition_and_boundaries(runner, world, definitions, query)


func _composition_and_boundaries(runner: Object, world: RegionalSimulation, definitions: RefCounted, query: RefCounted) -> void:
	var lifecycle: SimObjectLifecycle = world.object_lifecycle
	var hot: Dictionary = lifecycle.execute(_fixture._transfer("env_hot", _fixture._location("store"), _fixture._ground(199, 200), "wood", 1))
	# This regional fixture deliberately starts the home store without grain;
	# its kitchen has real opening grain and is a supported source container.
	var cold: Dictionary = lifecycle.execute(_fixture._transfer("env_cold", _fixture._location("kitchen"), _fixture._ground(201, 200), "grain", 1))
	var weak: Dictionary = lifecycle.execute(_fixture._transfer("env_weak", _fixture._location("garden"), _fixture._ground(200, 201), "herb", 1))
	runner.assert_true(bool(hot.get("ok", false)), "hot source ground transfer: %s" % str(hot))
	runner.assert_true(bool(cold.get("ok", false)), "cold source ground transfer: %s" % str(cold))
	runner.assert_true(bool(weak.get("ok", false)), "weaker source ground transfer: %s" % str(weak))
	if not bool(hot.get("ok", false)) or not bool(cold.get("ok", false)) or not bool(weak.get("ok", false)):
		return
	var hot_ref: Dictionary = _stock("home", "ground:env_hot", "wood")
	var cold_ref: Dictionary = _stock("home", "ground:env_cold", "grain")
	var before: String = _fixture._state(world)
	var sample: Dictionary = query.sample_base(Vector2i(200, 200))
	runner.assert_true(bool(sample.get("ok", false)) and bool(sample.get("complete", false)), "sample contains a complete local result")
	runner.assert_true(sample.get("elements") is Array and sample.elements.size() == 5, "a complete sample has exactly five ordered element channels")
	runner.assert_eq(sample.get("hot_grade"), 3000, "distance attenuates the strongest heat source")
	runner.assert_eq(sample.get("cold_grade"), 3000, "an equal cold source retains its independent effective strength")
	runner.assert_eq(sample.get("thermal_grade"), 0, "equal effective hot and cold cancel about the neutral point")
	if sample.get("elements") is Array:
		runner.assert_eq(sample.elements[1], 4500, "overlapping fire influence takes the strongest effective source")
	runner.assert_eq(sample.get("visibility"), "authority_only", "developer view is not a player's discovered knowledge")
	runner.assert_eq(sample.get("scope"), "active_ground_base_targets", "coverage is limited to explicitly supported ground targets")
	runner.assert_eq(sample.get("world_time_ms"), world.elapsed_ms, "the projection names its committed world time")
	runner.assert_eq(sample.get("config_digest"), definitions.digest(), "the projection identifies the exact explicit source configuration")
	runner.assert_eq(sample.get("rule_version"), 2, "results identify nearest-integer base target calculation separately from configuration digest")
	runner.assert_eq(_fixture._state(world), before, "source and field queries neither mutate nor advance the original world")
	var altered: Dictionary = sample.duplicate(true)
	if altered.get("elements") is Array:
		altered.elements[1] = -1
	runner.assert_eq(query.sample_base(Vector2i(200, 200)).get("elements"), sample.get("elements"), "mutating a detached result cannot change a future query")
	var bounded: Dictionary = query.sample_base(Vector2i(200, 200), 1)
	runner.assert_true(not bool(bounded.get("ok", true)) and not bool(bounded.get("complete", true)), "exhausting the work budget rejects an incomplete result")
	runner.assert_eq(bounded.get("reason"), "budget_exhausted", "budget exhaustion has an explicit reason")
	runner.assert_true(not bounded.has("elements") and not bounded.has("thermal_grade"), "partial field values cannot be mistaken for a complete sample")
	# Equal +/-2-strength sources at distance one with a radius-four kernel each
	# attenuate to 1.5. Both round to magnitude 2; truncation would return 1.
	var rounding_raw: Dictionary = _definitions()
	rounding_raw.profiles.hot.thermal_grade = 2
	rounding_raw.profiles.hot.elements.fire = 2
	rounding_raw.profiles.cold.thermal_grade = -2
	rounding_raw.profiles.cold.elements.fire = 0
	rounding_raw.profiles.weak.thermal_grade = 0
	rounding_raw.profiles.weak.elements.fire = 0
	var rounding_definitions: RefCounted = Definitions.new()
	var rounding_query: RefCounted = Bindings.new()
	if _ok(runner, rounding_definitions.configure(rounding_raw) and rounding_query.configure(world, rounding_definitions), "fractional-strength source definitions bind the same actual world"):
		var rounded: Dictionary = rounding_query.sample_base(Vector2i(200, 200))
		runner.assert_true(bool(rounded.get("ok", false)), "real sources with half-unit effective values are sampled")
		runner.assert_eq(rounded.get("hot_grade"), 2, "real positive source rounds a half unit up")
		runner.assert_eq(rounded.get("cold_grade"), 2, "real negative source rounds the same magnitude up")
		runner.assert_eq(rounded.get("thermal_grade"), 0, "symmetric rounded hot and cold still cancel")
		runner.assert_eq(rounded.get("elements"), [0, 2, 0, 0, 0], "the real five-element field uses the same nearest rounding")

	var remove_hot: Dictionary = lifecycle.execute(_fixture._transfer("env_hot_away", _fixture._location(hot_ref.container), _fixture._location("actor:player"), "wood", 1))
	if not _ok(runner, bool(remove_hot.get("ok", false)), "the strongest ground heat source is picked up"):
		return
	var next: Dictionary = query.sample_base(Vector2i(200, 200))
	runner.assert_eq(next.get("hot_grade"), 1500, "the weaker surviving source takes over after the maximum moves away")
	runner.assert_eq(next.get("cold_grade"), 3000, "removing heat leaves the cold source intact")
	runner.assert_eq(next.get("thermal_grade"), -1500, "net thermal grade is recomputed from both remaining extrema")
	if next.get("elements") is Array:
		runner.assert_eq(next.elements[1], 3000, "the next-strongest element source replaces the removed maximum")

	# Accounting regions are not separate maps: the adjacent river pile must
	# influence this same global cell even though its stock uses another ledger.
	var river_request: Dictionary = {"command": "env_river", "op": "stock_transfer", "from": {"region": "river", "container": "store"}, "to": {"region": "river", "cell": [210, 200]}, "item": "grain", "amount": 1}
	var river: Dictionary = lifecycle.execute(river_request)
	if not _ok(runner, bool(river.get("ok", false)), "a second region contributes a real independently accounted ground pile"):
		return
	var river_sample: Dictionary = query.sample_base(Vector2i(209, 200))
	runner.assert_eq(river_sample.get("cold_grade"), 3000, "a nearby source contributes across the accounting-region boundary")

	var unbound_raw: Dictionary = _definitions()
	unbound_raw.bindings.materials.erase("grain")
	var unbound_definitions: RefCounted = Definitions.new()
	var incomplete_query: RefCounted = Bindings.new()
	if _ok(runner, unbound_definitions.configure(unbound_raw) and incomplete_query.configure(world, unbound_definitions), "an explicitly incomplete development profile can be validated without inventing missing data"):
		runner.assert_eq(incomplete_query.project(cold_ref).get("reason"), "profile_missing", "a real source with no binding reports a missing profile")
		var missing_sample: Dictionary = incomplete_query.sample_base(Vector2i(201, 200))
		runner.assert_eq(missing_sample.get("reason"), "profile_missing", "a sample cannot silently treat a nearby missing profile as zero")
		runner.assert_true(not bool(missing_sample.get("complete", true)), "missing source data is not presented as a complete field")
	var no_source_raw: Dictionary = _definitions()
	no_source_raw.bindings.artifacts.stone_slab = "none"
	var no_source_definitions: RefCounted = Definitions.new()
	var no_source_query: RefCounted = Bindings.new()
	if _ok(runner, no_source_definitions.configure(no_source_raw) and no_source_query.configure(world, no_source_definitions), "explicit zero-source profile configures"):
		runner.assert_eq(no_source_query.project({"kind": "artifact", "id": "env_slab_instance"}).get("status"), "no_source", "explicit zero is distinguishable from a missing profile")
		var zero: Dictionary = no_source_query.sample_base(Vector2i(127, 120))
		runner.assert_true(bool(zero.get("ok", false)) and int(zero.get("source_count", -1)) == 0, "an explicitly non-emitting artifact yields a complete zero-source sample")
		runner.assert_eq(zero.get("elements"), [0, 0, 0, 0, 0], "zero-source sample has zero element influence")

	var saved_json: String = _fixture._state(world)
	var saved: Variant = JSON.parse_string(saved_json)
	var candidate: RegionalSimulation = _fixture._world(runner)
	runner.assert_true(saved is Dictionary and candidate != null, "a JSON world and independent candidate are available for the source restoration test")
	if saved is Dictionary and candidate != null:
		var loaded: bool = candidate.restore(saved)
		runner.assert_true(loaded, "the ordinary world restores into an independent candidate without a saved source registry")
		if loaded:
			var restored_query: RefCounted = Bindings.new()
			if _ok(runner, restored_query.configure(candidate, definitions), "the same explicitly identified source definitions bind after restoration"):
				var restored: Dictionary = restored_query.sample_base(Vector2i(200, 200))
				runner.assert_eq(restored.get("elements"), next.get("elements"), "restoration derives the same five-element base target from original owners")
				runner.assert_eq(restored.get("thermal_grade"), next.get("thermal_grade"), "restoration derives the same thermal base target")
				runner.assert_eq(restored.get("config_digest"), definitions.digest(), "the explicit definitions remain identifiable after ordinary world restoration")

	world.target_ms = world.elapsed_ms + 1
	runner.assert_eq(query.sample_base(Vector2i(200, 200)).get("reason"), "world_has_backlog", "a query cannot silently sample past owed world work")
	runner.assert_eq(query.project(cold_ref).get("reason"), "world_has_backlog", "a single-source query also refuses pending time")
	world.target_ms = world.elapsed_ms
	world.elapsed_ms += 1
	world.target_ms = world.elapsed_ms
	runner.assert_eq(query.project(cold_ref).get("reason"), "stale_source", "an unsynchronized region's old stock is identified as stale")
	runner.assert_eq(query.sample_base(Vector2i(200, 200)).get("reason"), "stale_source", "stale nearby sources cannot form an authoritative field")
	world.elapsed_ms -= 1
	world.target_ms = world.elapsed_ms


func _stock(region: String, container: String, item: String) -> Dictionary:
	return {"kind": "stock", "domain": "village", "region": region, "container": container, "item": item}


func _ok(runner: Object, value: bool, label: String) -> bool:
	runner.assert_true(value, label)
	return value
