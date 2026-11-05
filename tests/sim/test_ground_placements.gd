extends RefCounted
## Real regional owner, detached location metadata and bounded spatial indices.

const Fixtures = preload("res://tests/sim/test_world_object_query.gd")
const Ground = preload("res://scripts/sim/ground_placements.gd")
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_test_shape_and_geometry(runner)
	_test_replacement_and_budget(runner)
	_test_restore_and_rebind(runner)
	_test_unpublished_discard(runner)
	_test_revision_and_binding(runner)
	_test_map_edges_and_invalid_restore(runner)
	print("SCENARIO ground placements: exact footprints, atomic replacement, scoped budget, detached candidate and rebind")


func _world(runner: Object, with_map: bool = true) -> RegionalSimulation:
	var fixture: Dictionary = _fixtures._world(runner)
	if fixture.is_empty():
		return null
	var world: RegionalSimulation = fixture.world
	if with_map:
		world.bind_map_data(Fixtures.FlatMap.new())
	return world


func _test_shape_and_geometry(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, false)
	if world == null:
		return
	var ground := Ground.new()
	runner.assert_true(ground.configure(world), "ground owner binds the original world")
	runner.assert_eq(ground.can_place("home", Vector2i(20, 20)).get("reason"), "terrain_unavailable", "missing map cannot certify placement")
	world.bind_map_data(Fixtures.FlatMap.new())
	var at := Vector2i(20, 20)
	var original_ref: Dictionary = {"kind": "artifact", "id": "alpha"}
	var added: Dictionary = ground.register_slot("ground:a", "home", original_ref, at, Vector2i(2, 2))
	runner.assert_true(bool(added.get("ok", false)), "a valid unique object occupies one footprint")
	if not bool(added.get("ok", false)):
		return
	runner.assert_eq(ground.stats().cells, 4, "a two-by-two footprint indexes four cells")
	original_ref.id = "changed_input"
	var located: Dictionary = ground.locate("home", "ground:a")
	runner.assert_eq(located.reference.id, "alpha", "reference input is detached")
	located.reference.id = "changed_output"
	runner.assert_eq(ground.locate("home", "ground:a").reference.id, "alpha", "location result is detached")
	var before: Dictionary = ground.to_dict()
	var before_stats: Dictionary = ground.stats()
	runner.assert_eq(ground.register_slot("ground:b", "river", {"kind": "artifact", "id": "beta"}, Vector2i(21, 21)).get("reason"), "ground_occupied", "different accounting regions share the same ground coordinates")
	runner.assert_eq(ground.register_slot("ground:b", "home", {"kind": "artifact", "id": "alpha"}, Vector2i(30, 30)).get("reason"), "reference_already_placed", "one source cannot occupy two live slots")
	runner.assert_eq(ground.register_slot("ground:b", "home", {"kind": "stock", "domain": "village", "region": "river", "container": "box", "item": "wood"}, Vector2i(30, 30)).get("reason"), "invalid_reference", "stock accounting region must agree with slot")
	runner.assert_eq(ground.register_slot("ground:b", "home", {"kind": "artifact", "id": "beta"}, Vector2i(511, 511), Vector2i(2, 1)).get("reason"), "invalid_geometry", "footprint cannot cross map boundary")
	runner.assert_eq(ground.to_dict(), before, "failed registrations do not change placement facts")
	runner.assert_eq(ground.stats(), before_stats, "failed registrations do not change the indices or revision")
	world.target_ms = world.elapsed_ms + 1
	runner.assert_eq(ground.can_place("home", Vector2i(30, 30)).get("reason"), "pending_time", "unsettled world cannot commit placement")
	world.target_ms = world.elapsed_ms
	world.regions.home.elapsed_ms = world.elapsed_ms - 1 if world.elapsed_ms > 0 else 1
	runner.assert_eq(ground.can_place("home", Vector2i(30, 30)).get("reason"), "unsynchronized_region", "source region must share committed world time")
	world.regions.home.elapsed_ms = world.elapsed_ms


func _test_replacement_and_budget(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var ground := Ground.new()
	ground.configure(world)
	var ref: Dictionary = {"kind": "artifact", "id": "alpha"}
	runner.assert_true(bool(ground.register_slot("ground:old", "home", ref, Vector2i(15, 15), Vector2i(2, 2)).get("ok", false)), "replacement fixture starts across buckets")
	runner.assert_true(bool(ground.register_slot("ground:other", "home", {"kind": "artifact", "id": "other"}, Vector2i(18, 15)).get("ok", false)), "another object has an independent location")
	var before: Dictionary = ground.to_dict()
	var before_stats: Dictionary = ground.stats()
	var rejected: Dictionary = ground.register_slot("ground:new", "home", ref, Vector2i(17, 15), Vector2i(2, 2), "ground:old")
	runner.assert_eq(rejected.get("reason"), "ground_occupied", "moving into another object's cell is rejected")
	runner.assert_eq(ground.to_dict(), before, "failed replacement leaves old and other slots unchanged")
	runner.assert_eq(ground.stats(), before_stats, "failed replacement leaves indices and revision unchanged")
	runner.assert_eq(ground.register_slot("ground:new", "home", {"kind": "artifact", "id": "wrong"}, Vector2i(15, 15), Vector2i.ONE, "ground:old").get("reason"), "invalid_replacement", "replacement must be the same original artifact")
	runner.assert_true(bool(ground.register_slot("ground:new", "home", ref, Vector2i(16, 16), Vector2i(2, 2), "ground:old").get("ok", false)), "a replacement may overlap its own old footprint")
	runner.assert_true(not bool(ground.locate("home", "ground:old").get("active", true)), "old metadata remains inactive after atomic replacement")
	runner.assert_true(bool(ground.locate("home", "ground:new").get("active", false)), "new location is active")
	runner.assert_eq(ground.query(Rect2i(15, 15, 1, 1)).get("ids"), [], "old non-overlapping cell is immediately free")
	var one: Dictionary = ground.query(Rect2i(16, 16, 2, 2))
	runner.assert_eq(one.get("ids"), ["ground:new"], "a multi-cell item is returned only once")
	var across: Dictionary = ground.query(Rect2i(15, 15, 3, 3))
	runner.assert_eq(across.get("ids"), ["ground:new"], "a query spanning buckets returns the same original object only once")
	var exact: Dictionary = ground.query(Rect2i(16, 16, 1, 1), 3)
	runner.assert_true(bool(exact.get("complete", false)) and int(exact.get("work_used", -1)) == 3, "a budget exactly covering a bucket, candidate and hit succeeds")
	var short: Dictionary = ground.query(Rect2i(16, 16, 1, 1), 2)
	runner.assert_true(short.get("reason") == "budget_exhausted" and not short.has("ids"), "one less work unit fails without publishing a partial hit")
	var exhausted: Dictionary = ground.query(Rect2i(0, 0, 512, 512), 1)
	runner.assert_true(not bool(exhausted.ok) and not bool(exhausted.complete) and exhausted.reason == "budget_exhausted", "budget exhaustion is not an empty complete result")
	runner.assert_true(not exhausted.has("ids") and int(exhausted.work_used) <= 1, "budget failure publishes no partial IDs")
	runner.assert_eq(ground.query(Rect2i(0, 0, 1, 1), 0).get("reason"), "invalid_budget", "zero query budget is rejected")
	runner.assert_eq(ground.query(Rect2i(511, 511, 2, 1)).get("reason"), "invalid_area", "query geometry cannot exceed map")
	runner.assert_true(not bool(ground.deactivate("ground:old").get("changed", true)), "deactivating the already-inactive replacement is idempotent")


func _test_restore_and_rebind(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var replacement_world: RegionalSimulation = _world(runner)
	if world == null or replacement_world == null:
		return
	var ground := Ground.new()
	ground.configure(world)
	var artifact: Dictionary = {"kind": "artifact", "id": "reusable"}
	var stock: Dictionary = {"kind": "stock", "domain": "village", "region": "home", "container": "ground:stock", "item": "wood"}
	runner.assert_true(bool(ground.register_slot("ground:reusable", "home", artifact, Vector2i(30, 30)).get("ok", false)), "artifact location is registered")
	runner.assert_true(bool(ground.deactivate("ground:reusable").get("ok", false)), "inactive history remains addressable")
	runner.assert_true(bool(ground.register_slot("ground:stock", "home", stock, Vector2i(30, 30)).get("ok", false)), "inactive metadata does not occupy the cell")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(ground.to_dict()))
	var restored := Ground.new()
	runner.assert_true(restored.restore(saved), "detached valid metadata restores without a world or map")
	runner.assert_eq(restored.to_dict(), ground.to_dict(), "restored saved slots retain values and historical anchors")
	runner.assert_eq(restored.query(Rect2i(30, 30, 1, 1)).get("ids"), ["ground:stock"], "only active metadata reconstructs occupancy")
	var untouched: Dictionary = restored.to_dict()
	var untouched_stats: Dictionary = restored.stats()
	var damaged: Dictionary = saved.duplicate(true)
	damaged.slots["ground:stock"].cell = [4294967297, 0]
	runner.assert_true(not restored.restore(damaged), "oversized raw JSON coordinate is rejected before narrowing")
	damaged = saved.duplicate(true)
	damaged.slots["ground:stock"].size = [1.5, 1]
	runner.assert_true(not restored.restore(damaged), "fractional footprint is rejected")
	damaged = saved.duplicate(true)
	damaged.slots["ground:reusable"].active = true
	runner.assert_true(not restored.restore(damaged), "two active owners cannot occupy the same cell")
	damaged = saved.duplicate(true)
	damaged.slots["ground:reusable"].active = true
	damaged.slots["ground:reusable"].cell = [31, 30]
	damaged.slots["ground:reusable"].reference = stock.duplicate(true)
	runner.assert_true(not restored.restore(damaged), "one source reference cannot appear in two active slots")
	runner.assert_eq(restored.to_dict(), untouched, "rejected candidates do not alter restored facts")
	runner.assert_eq(restored.stats(), untouched_stats, "rejected candidates do not alter derived indexes or revision")
	restored.rebind(replacement_world)
	runner.assert_true(restored.bound_to(replacement_world) and not restored.bound_to(world), "validated candidate rebinds to the published world")
	runner.assert_true(bool(restored.register_slot("ground:after_rebind", "home", {"kind": "artifact", "id": "after"}, Vector2i(32, 30)).get("ok", false)), "new writes use the rebound world")


func _test_unpublished_discard(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var ground := Ground.new()
	ground.configure(world)
	var before: Dictionary = ground.to_dict()
	runner.assert_true(bool(ground.register_slot("ground:temporary", "home", {"kind": "artifact", "id": "temp"}, Vector2i(40, 40)).get("ok", false)), "a private short transaction can register its candidate")
	ground.discard_uncommitted("ground:temporary")
	runner.assert_eq(ground.to_dict(), before, "unpublished rollback removes all metadata")
	runner.assert_eq(ground.stats().cells, 0, "unpublished rollback removes derived occupied cells")
	runner.assert_eq(ground.query(Rect2i(40, 40, 1, 1)).get("ids"), [], "unpublished rollback leaves no local query result")
	runner.assert_true(bool(ground.register_slot("ground:temporary", "home", {"kind": "artifact", "id": "temp"}, Vector2i(40, 40)).get("ok", false)), "unpublished reference and identity are free to retry")


func _test_revision_and_binding(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var other: RegionalSimulation = _world(runner)
	if world == null or other == null:
		return
	var ground := Ground.new()
	runner.assert_true(not ground.configure(null), "a missing world cannot become the placement authority")
	runner.assert_eq(ground.can_place("home", Vector2i(10, 10)).get("reason"), "world_unavailable", "an unbound registry cannot authorize a placement")
	runner.assert_true(ground.configure(world) and ground.configure(world), "binding the same authority twice is harmless")
	runner.assert_true(not ground.configure(other) and ground.bound_to(world), "configure cannot silently switch a live authority")
	var before: int = ground.revision
	var reference: Dictionary = {"kind": "artifact", "id": "revision_subject"}
	var added: Dictionary = ground.register_slot("ground:revision_subject", "home", reference, Vector2i(10, 10))
	runner.assert_true(bool(added.get("ok", false)), "revision fixture is registered")
	var observed: Dictionary = ground.query(Rect2i(10, 10, 1, 1))
	var registered_revision: int = ground.revision
	runner.assert_true(registered_revision > before and int(observed.revision) == registered_revision, "a successful registration advances the observable registry revision")
	var rejected: Dictionary = ground.register_slot("ground:duplicate", "home", reference, Vector2i(11, 10))
	runner.assert_eq(rejected.get("reason"), "reference_already_placed", "a duplicate identity is rejected")
	runner.assert_eq(ground.revision, registered_revision, "a rejected write does not invalidate a valid snapshot")
	var deactivated: Dictionary = ground.deactivate("ground:revision_subject")
	runner.assert_true(bool(deactivated.get("changed", false)) and ground.revision > int(observed.revision), "deactivation invalidates the older query revision")
	runner.assert_eq(ground.query(Rect2i(10, 10, 1, 1)).get("ids"), [], "deactivation removes the object from spatial results")
	var after_deactivate: int = ground.revision
	runner.assert_true(not bool(ground.deactivate("ground:revision_subject").get("changed", true)), "repeated deactivation is a no-op")
	runner.assert_eq(ground.revision, after_deactivate, "a no-op does not invalidate another snapshot")
	runner.assert_eq(ground.register_slot("ground:stale", "home", reference, Vector2i(10, 10), Vector2i.ONE, "ground:revision_subject").get("reason"), "invalid_replacement", "an inactive source cannot be replaced as if still live")
	runner.assert_eq(ground.register_slot("ground:missing", "home", reference, Vector2i(10, 10), Vector2i.ONE, "ground:missing_source").get("reason"), "invalid_replacement", "a missing ground source cannot be silently accepted")
	var retained: Dictionary = ground.to_dict()
	ground.rebind(null)
	runner.assert_true(not ground.bound_to(world), "unbinding clears the live authority")
	runner.assert_eq(ground.can_place("home", Vector2i(10, 10)).get("reason"), "world_unavailable", "writes cannot use an unbound authority")
	runner.assert_eq(ground.to_dict(), retained, "unbinding cannot erase location facts")
	ground.rebind(other)
	runner.assert_true(ground.bound_to(other), "a published candidate can bind to its replacement authority")
	var before_restore: int = ground.revision
	runner.assert_true(ground.restore(retained) and ground.revision > before_restore, "successful restore invalidates earlier spatial results even for the same facts")


func _test_map_edges_and_invalid_restore(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var ground := Ground.new()
	ground.configure(world)
	var edge := Vector2i(Ground.MAP_SIZE - 1, Ground.MAP_SIZE - 1)
	runner.assert_true(bool(ground.register_slot("ground:edge", "home", {"kind": "artifact", "id": "edge"}, edge).get("ok", false)), "the final valid map cell accepts a one-cell object")
	runner.assert_eq(ground.query(Rect2i(edge, Vector2i.ONE)).get("ids", []), ["ground:edge"], "the final valid map cell is queryable")
	runner.assert_eq(ground.can_place("home", Vector2i(-1, 0)).get("reason"), "invalid_geometry", "a negative placement coordinate is rejected")
	runner.assert_eq(ground.can_place("home", edge, Vector2i(2, 1)).get("reason"), "invalid_geometry", "a footprint cannot cross the positive map edge")
	runner.assert_eq(ground.can_place("home", Vector2i.ZERO, Vector2i(0, 1)).get("reason"), "invalid_geometry", "an empty footprint is rejected")
	runner.assert_eq(ground.can_place("home", Vector2i.ZERO, Vector2i(Ground.MAX_SIZE + 1, 1)).get("reason"), "invalid_geometry", "a footprint larger than the supported limit is rejected")
	runner.assert_eq(ground.query(Rect2i(-1, 0, 1, 1)).get("reason"), "invalid_area", "negative query coordinates cannot wrap into the map")
	runner.assert_eq(ground.query(Rect2i(0, 0, 0, 1)).get("reason"), "invalid_area", "empty query areas fail explicitly")
	var saved: Dictionary = ground.to_dict()
	var before_stats: Dictionary = ground.stats()
	var damaged: Dictionary = saved.duplicate(true)
	damaged.slots["ground:edge"].cell = [Ground.MAP_SIZE - 1, Ground.MAP_SIZE - 1]
	damaged.slots["ground:edge"].size = [2, 1]
	runner.assert_true(not ground.restore(damaged), "restoration rejects a footprint whose end crosses the map")
	damaged = saved.duplicate(true)
	damaged.slots["ground:edge"].cell = [-1, 0]
	runner.assert_true(not ground.restore(damaged), "restoration rejects a negative raw coordinate")
	damaged = saved.duplicate(true)
	damaged.slots["ground:edge"].cell = ["511", 511]
	runner.assert_true(not ground.restore(damaged), "restoration rejects a string masquerading as a coordinate")
	runner.assert_eq(ground.to_dict(), saved, "invalid edge candidates leave facts unchanged")
	runner.assert_eq(ground.stats(), before_stats, "invalid edge candidates leave registry revision and indices unchanged")
