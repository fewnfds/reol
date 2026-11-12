extends RefCounted
## Small visibility/knowledge counterexamples. Load measurements stay external.

const World = preload("res://scripts/sim/kernel/world.gd")
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")


static func run(check: Callable) -> void:
	var w := World.new()
	w.initialize(6, 0)
	var page: RefCounted = w.pages[0]
	for row: int in 6:
		w.release(row + 1)
		w.objects.records[row + 1].autonomous = false
		page.modes[row] = 4
		page.positions[row] = Vector2(140.5, 140.5 + row)
	var a: int = Terrain.index(Vector2i(130, 130))
	var b: int = Terrain.index(Vector2i(134, 130))
	w.sight.smooth_loss[a + 1] = 1.0
	check.call(not w.sight.sees_tile(a, b, 4.0) and w.sight.sees_tile(a, b, 5.0) and not w.sight.sees_tile(a, a, 0.0), "Sight ignored a zero remaining budget, its own range or blindness")
	w.sight.smooth_loss[a + 1] = 0.0
	var far: int = Terrain.index(Vector2i(170, 147))
	check.call(w.sight.sees_tile(a, far, 60.0) and w.sight.sees_tile(far, a, 60.0), "Long sight has no symmetric fallback outside the prepared table")
	check.call(not w.sight.sees(Vector2(20.99, 20.99), Terrain.index(Vector2i(44, 21)), 24.0) and w.sight.sees(Vector2(20.99, 20.99), Terrain.index(Vector2i(44, 21)), 25.0), "Sight-table rim disagrees with the tile-centre rule")
	page.positions[0] = Vector2(146.5, 150.5)
	page.positions[1] = Vector2(153.5, 150.5)
	var wall: int = Terrain.index(Vector2i(150, 150))
	var wall_id: int = w.facilities.seed_fixture(w, "wood_wall", wall)
	w.flush_topology()
	w.perception.update(w, w.elapsed_ms, true)
	check.call(w.sight.observed_position(w, 1, 2) != null and w.perception.tiles[Terrain.index(Vector2i(153, 150))] != 0, "Player map and unit sight disagree about a visible target behind a wall")
	w.combat.begin(w, 1, "pursue", 2, -1, true)
	w.step()
	check.call(w.combat.shots == 0 and w.combat.repaths > 0, "Seeing through range loss allowed an arrow through a solid wall")
	# Change only vision, while standing still: no geometry edit may be needed.
	w.objects.records[1].sight_range = 2.0
	w.perception.update(w, w.elapsed_ms + 50)
	check.call(w.perception.tiles[Terrain.index(Vector2i(153, 150))] == 0 and w.sight.observed_position(w, 1, 2) == null, "Changing personal sight failed to update the player map")
	w.objects.records[1].sight_range = 24.0
	w.facilities.demolish(w, wall_id)
	w.flush_topology()
	w.release(1)
	page.positions[0] = Vector2(146.5, 150.5)
	page.positions[1] = Vector2(153.95, 150.95)
	w.combat.begin(w, 1, "pursue", 2)
	w.step()
	var last_seen: Vector2 = w.combat.orders[1].last_seen_pos
	page.positions[1] = Vector2(300.5, 300.5)
	for step: int in 6:
		w.step()
	check.call(w.combat.orders[1].last_seen_pos == last_seen and page.targets[0] == Terrain.index(Vector2i(last_seen)), "Losing sight leaked the target's new real position into pursuit")
	var saved: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check.call(saved != null and saved.combat.orders[1].last_seen_pos == last_seen and saved.objects.records[1].sight_range == 24.0, "Save/load lost a frozen combat contact or personal sight")
	page.positions[0] = Terrain.center(Terrain.index(Vector2i(last_seen)))
	w.step()
	check.call(not w.combat.orders.has(1) and w.combat.begin(w, 1, "pursue", 2) == "target_not_visible", "A lost contact stayed locked or an unseen target received a fresh pursuit")
	# Blind projectile damage gives a direction clue, never a hidden actor ID.
	w.release(2)
	w.objects.records[2].sight_range = 2.0
	page.positions[0] = Vector2(170.5, 150.5)
	page.positions[1] = Vector2(160.5, 150.5)
	w.objects.records[2]["ranged"] = true
	w.combat.damage(w, 1, 2, 1, w.elapsed_ms, Vector2.RIGHT)
	check.call(w.combat.orders[2].target == 0 and w.combat.orders[2].ranged and w.combat.orders[2].destination == Terrain.index(Vector2i(166, 150)), "Blind retaliation leaked the hidden shooter or lost the defender's ranged mode")
	# A working person with no combat order must still discover a local threat.
	w.release(2)
	w.objects.records[2].sight_range = 24.0
	w.objects.records[2].autonomous = true
	w.objects.records[3]["side"] = 1
	page.positions[1] = Vector2(150.5, 155.5)
	page.positions[2] = Vector2(155.5, 155.5)
	page.modes[1] = 2
	page.due_ms[1] = w.elapsed_ms + 10000
	for step: int in 4:
		w.step()
	check.call(w.combat.orders.has(2) and w.combat.orders[2].target == 3, "A peaceful worker could not discover its first nearby threat")
	# Geometry invalidates while stationary; multi-cell objects expose visible cells.
	w.release(1)
	page.positions[0] = Vector2(146.5, 150.5)
	w.objects.records[1].sight_range = 7.0
	w.perception.update(w, w.elapsed_ms, true)
	wall_id = w.facilities.seed_fixture(w, "wood_wall", wall)
	w.flush_topology()
	w.perception.update(w, w.elapsed_ms + 50)
	check.call(w.perception.tiles[Terrain.index(Vector2i(153, 150))] == 0, "Stationary observation retained stale sight after a wall appeared")
	var multi: Dictionary = {"tile": Terrain.index(Vector2i(154, 149)), "cells": PackedInt32Array([Terrain.index(Vector2i(154, 149)), Terrain.index(Vector2i(151, 149))])}
	check.call(w.sight.sees_object(page.positions[0], multi, 7.0), "A visible footprint cell did not reveal its static object")
	for row: int in 6:
		w.release(row + 1)
		w.objects.records[row + 1].autonomous = false
		w.objects.records[row + 1]["side"] = 0
		page.modes[row] = 4
	w.objects.records[1].sight_range = 24.0
	page.positions[1] = Vector2(151.5, 150.5)
	page.positions[2] = Vector2(146.5, 156.5)
	w.objects.records[2].side = 1
	w.objects.records[3].side = 1
	w.combat.begin(w, 1, "hold", 0, -1, true)
	for step: int in 4:
		w.step()
	check.call(w.combat.orders[1].target == 3, "Stationary guard locked a blocked target instead of a clear target")
	w.release(1)
	w.facilities.demolish(w, wall_id)
	w.flush_topology()
	w.combat.begin(w, 1, "pursue", 2)
	var contact: Vector2 = w.combat.orders[1].last_seen_pos
	page.positions[1] = Vector2(300.5, 300.5)
	w.kill(2)
	w.remove_actor(2)
	var replacement: int = w.spawn_actor(Terrain.index(Vector2i(301, 301)))
	w.step()
	check.call(w.combat.orders.has(1) and w.combat.orders[1].target == 2 and w.combat.orders[1].last_seen_pos == contact and replacement != 2, "Hidden destruction or reused body slot leaked truth into a frozen contact")
	w.release(1)
	# A sealed target must not interrupt the same peaceful worker every 200ms.
	page.positions[3] = Vector2(152.5, 154.5)
	page.positions[2] = Vector2(155.5, 154.5)
	w.objects.records[4].autonomous = true
	page.modes[3] = 2
	page.due_ms[3] = w.elapsed_ms + 10000
	for y: int in range(153, 156):
		for x: int in range(154, 157):
			if x == 155 and y == 154:
				continue
			w.facilities.seed_fixture(w, "wood_wall", Terrain.index(Vector2i(x, y)))
	w.flush_topology()
	for step: int in 10:
		w.step()
	check.call(not w.combat.orders.has(4) and w.objects.records[4].get("threat_scan_after", 0) > w.elapsed_ms, "Unreachable visible enemy kept interrupting peaceful work")
	var paths: int = w.combat.repaths
	for step: int in 50:
		w.step()
	check.call(not w.combat.orders.has(4) and w.combat.repaths == paths and Persistence.candidate(Persistence.capture(w), 0) != null, "Known unreachable contact retried after cooldown or could not survive save/load")
	w.release(4)
	page.positions[3] = Vector2(152.5, 154.5)
	page.positions[2] = Vector2(158.5, 154.5)
	page.modes[3] = 2
	page.due_ms[3] = w.elapsed_ms + 10000
	for step: int in 4:
		w.step()
	check.call(w.combat.orders.has(4) and w.combat.orders[4].target == 3, "Moving into a new reachable position left an enemy permanently blacklisted")
