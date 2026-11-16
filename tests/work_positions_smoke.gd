extends "res://tests/abilities_smoke.gd"
const Positions = preload("res://scripts/sim/kernel/work_positions.gd")

func geometry() -> void:
	var w: RefCounted = fixture()
	var plant: int = w.nature.create(w, "perennial_herb", w.Terrain.index(Vector2i(124, 124)))
	check(Positions.cells(w, plant, "tend") == PackedInt32Array([w.objects.records[plant].tile]), "Nonblocking plant did not require its own cell")
	check(not w.facilities.in_range(w, plant, Vector2(123.9, 124.5), 0.35, "tend"), "Plant work was possible from the neighbouring cell")
	var resource: int = w.source_objects[0]
	check(Positions.cells(w, resource, "harvest") == PackedInt32Array([w.objects.records[resource].tile]), "Nonblocking timber work did not use its source cell")
	var pot: int = w.facilities.seed_fixture(w, "planter", w.Terrain.index(Vector2i(128, 124)))
	w.flush_topology()
	var potted: int = w.nature.create(w, "perennial_herb", w.objects.records[pot].tile)
	check(potted > 0 and Positions.cells(w, potted, "tend").size() == 4, "Potted plant did not inherit its host's neighbours")
	check(not w.facilities.in_range(w, potted, Vector2(128.5, 124.5), 0.35, "tend"), "Potted plant let the worker enter its solid pot")
	var table: int = w.facilities.seed_fixture(w, "wood_table", w.Terrain.index(Vector2i(132, 124)))
	w.flush_topology()
	var neighbours: PackedInt32Array = Positions.cells(w, table, "construct")
	check(neighbours.size() == 6 and not neighbours.has(w.Terrain.index(Vector2i(131, 123))), "Multi-cell perimeter included diagonals or its own footprint")
	var big: Vector2 = w.facilities.interaction_point(w, table, Vector2(130, 124.5), 0.9, false, "demolish")
	check(big.x >= 0 and Positions.permits(w, table, "demolish", big, 0.9), "Large body could not fit in an otherwise open neighbouring cell")
	for facing: int in 4:
		var stove: int = w.facilities.seed_fixture(w, "cook_stove", w.Terrain.index(Vector2i(140 + facing * 5, 124)), facing)
		w.flush_topology()
		var offsets: Array[Vector2i] = [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, -1), Vector2i(1, 1)]
		var expected: int = w.Terrain.index(Vector2i(140 + facing * 5, 124) + offsets[facing])
		check(Positions.cells(w, stove, "cook") == PackedInt32Array([expected]), "Named station did not rotate with the full footprint: %d" % facing)
		check(Positions.cells(w, stove, "construct").size() == 6, "Cooking station leaked into construction access")
		check(w.facilities.in_range(w, stove, w.Terrain.center(expected), 0.35, "cook"), "Rotated cooking station was unusable")
	var definition: Dictionary = w.facilities.definitions.cook_stove.duplicate(true)
	definition.work_positions = {"forge": {"mode": "stations", "cells": [[0, 1]]}}
	w.facilities.definitions["test_forge"] = definition
	var forge: int = w.objects.create("workbench", "test_forge", w.Terrain.index(Vector2i(145, 130)))
	w.objects.reindex(forge, w.facilities.footprint("test_forge", w.objects.records[forge].tile))
	check(Positions.cells(w, forge, "forge").size() == 1, "Custom work operation required a hardcoded instance")
	check(not Positions.errors({"cook": {"mode": "stations", "cells": [[0.5, 1]]}}).is_empty(), "Fractional work cell was accepted")
	check(not Positions.errors({"cook": {"mode": "unknown"}}).is_empty(), "Unknown position rule was accepted")

func operation() -> void:
	var w: RefCounted = fixture()
	var stove: int = w.facilities.seed_fixture(w, "cook_stove", w.Terrain.index(Vector2i(124, 123)))
	w.flush_topology()
	w.pages[0].positions[0] = Vector2(124.5, 122.5) # Wrong side.
	var grain: int = w.objects.amount(1, "grain")
	check(w.begin_interaction(1, {"kind": "cook", "target": stove}) == "accepted", "Cooking approach refused")
	check(w.pages[0].targets[0] == Vector2(124.5, 124.5), "Cook did not approach the configured single station")
	advance(w, 6500)
	check(w.objects.amount(stove, "meal") == 3 and w.objects.amount(1, "grain") == grain - 2, "Cooking at the real station did not finish once")
	var blocked: RefCounted = fixture()
	var bench: int = blocked.facilities.seed_fixture(blocked, "cook_stove", blocked.Terrain.index(Vector2i(124, 123)))
	blocked.queue_structure(blocked.Terrain.index(Vector2i(124, 124)), true, false)
	blocked.flush_topology()
	check(blocked.begin_interaction(1, {"kind": "cook", "target": bench}) == "no_operation_place", "A blocked designated station fell back to another side")

func construction() -> void:
	var w: RefCounted = fixture()
	w.objects.claim(w.source_objects[0], 1, "wood", 20)
	var placed: Dictionary = w.facilities.blueprint(w, 1, "wood_table", w.Terrain.index(Vector2i(124, 123)))
	check(placed.reason == "accepted", "Construction fixture failed")
	if placed.reason != "accepted": return
	var target: int = placed.target
	w.objects.records[target].remaining_ms = 800
	w.pages[0].positions[0] = Vector2(123.5, 123.5)
	w.pages[0].positions[1] = Vector2(125.5, 123.5) # Occupies the second cell.
	var stock: int = w.objects.amount(1, "wood")
	check(w.begin_interaction(1, {"kind": "construct", "target": target}) == "accepted", "Construction approach failed")
	advance(w, 300)
	check(not w.objects.records[target].construction_started and w.objects.records[target].remaining_ms == 800, "Occupied footprint started work or consumed labour")
	check(w.terrain.blocked[w.objects.records[target].tile] == 0, "Waiting site trapped its occupant")
	var waiting_save: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(waiting_save != null and waiting_save.actions[1].get("waiting", false) and not waiting_save.actions[1].has("started_ms"), "Waiting construction lost its no-labour state during restore")
	w.pages[0].positions[1] = Vector2(128.5, 123.5)
	advance(w, 550)
	if waiting_save != null:
		waiting_save.pages[0].positions[1] = Vector2(128.5, 123.5)
		advance(waiting_save, 550)
		check(waiting_save.actions[1].started_ms == w.actions[1].started_ms, "Waiting restore started work at a different time")
	check(w.objects.records[target].construction_started, "Freed footprint did not start construction")
	for tile: int in w.objects.records[target].cells:
		check(w.terrain.blocked[tile] != 0 and w.terrain.enclosures[tile] == 0, "Half-built footprint did not acquire solid-only space")
	var active_save: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(active_save != null and active_save.actions[1].started_ms == w.actions[1].started_ms, "Active construction failed to restore its original labour interval")
	advance(w, 650)
	w.command({"kind": "interrupt"})
	var remaining: int = w.objects.records[target].remaining_ms
	if active_save != null:
		advance(active_save, 650)
		active_save.command({"kind": "interrupt"})
		check(active_save.objects.records[target].remaining_ms == remaining, "Active restore repeated or erased construction labour")
	check(remaining < 800 and remaining > 0 and w.objects.records[target].construction_started, "Interrupt reset labour or unfinished presence")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null and restored.objects.records[target].construction_started, "Unfinished solid site failed restore")
	if restored != null:
		check(restored.begin_interaction(1, {"kind": "construct", "target": target}) == "accepted", "Restored site refused continuation")
		advance(restored, 1600)
		check(restored.objects.records[target].kind == "table" and restored.objects.amount(1, "wood") == stock, "Continuation failed or paid materials twice")
	var bad: Dictionary = Persistence.capture(w)
	bad.domains.objects.records[target].construction_started = "yes"
	check(Persistence.candidate(bad, 0) == null, "Invalid construction phase was adopted")
	bad = Persistence.capture(w)
	bad.domains.objects.records[target].cells = "invalid"
	check(Persistence.candidate(bad, 0) == null, "Invalid unfinished footprint escaped candidate validation")
	w.facilities.demolish(w, target)
	w.flush_topology()
	check(not w.objects.records.has(target) and w.terrain.blocked[w.Terrain.index(Vector2i(125, 123))] == 0, "Removing unfinished work left collision behind")

func competing_builders() -> void:
	var w: RefCounted = fixture()
	w.objects.claim(w.source_objects[0], 1, "wood", 20)
	var target: int = w.facilities.blueprint(w, 1, "wood_table", w.Terrain.index(Vector2i(124, 123))).target
	w.objects.records[target].remaining_ms = 500
	w.pages[0].positions[0] = Vector2(123.5, 123.5)
	w.pages[0].positions[1] = Vector2(124.5, 122.5)
	for actor: int in [1, 2]:
		check(w.begin_interaction(actor, {"kind": "construct", "target": target}) == "accepted", "Competing manual builder was refused")
	advance(w, 1400)
	check(w.objects.records[target].kind == "table" and not w.objects.records[target].has("construction_started"), "Waiting builder restarted a completed object")
	check(not w.actions.has(2) and w.facilities.completed.get("construct", 0) == 1, "Stale construction did not end exactly once")
	check(w.facilities.start_construction(w, target, w.elapsed_ms) == "unavailable", "Completed object accepted construction start")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Competing builders corrupted a normal save")

func budgeted_approach() -> void:
	var w: RefCounted = fixture()
	var target: int = w.facilities.seed_fixture(w, "wood_table", w.Terrain.index(Vector2i(124, 123)))
	w.queue_structure(w.Terrain.index(Vector2i(122, 123)), true, false)
	w.flush_topology()
	var nav: RefCounted = w.lanes[0].navigation
	nav.remaining = 0
	nav.preparations = 0
	var origin := Vector2(121.5, 122.5)
	var candidates: Array[Vector2] = Positions.candidates(w, target, "demolish", origin, 0.35, false)
	check(not candidates.is_empty() and not w.terrain.segment_clear(origin, candidates[0], 0.35), "Budget fixture did not block the nearest approach")
	var point: Vector2 = w.facilities.interaction_point(w, target, origin, 0.35, false, "demolish")
	check(point.x >= 0 and w.terrain.segment_clear(origin, point, 0.35), "Deferred nearest candidate hid a directly reachable work position")
	check(nav.preparations == 0 and nav.remaining == 0, "Direct work approach consumed an exhausted search budget")

func large_body_future_footprint() -> void:
	var w: RefCounted = fixture()
	w.objects.claim(w.source_objects[0], 1, "wood", 20)
	var target: int = w.facilities.blueprint(w, 1, "wood_table", w.Terrain.index(Vector2i(132, 124))).target
	w.queue_structure(w.Terrain.index(Vector2i(134, 122)), true, false)
	w.flush_topology()
	var valid := Vector2(133.099, 123.099)
	check(Positions.permits(w, target, "construct", valid, 0.9), "Large-body corner fixture has no legal work point")
	var found: bool = false
	for point: Vector2 in Positions.candidates(w, target, "construct", Vector2(133, 121), 0.9, false):
		if Vector2i(point.floor()) == Vector2i(133, 123): found = true
	check(found, "Future footprint omitted a legal large-body station beside a diagonal wall")

func _run() -> void:
	geometry()
	operation()
	construction()
	competing_builders()
	budgeted_approach()
	large_body_future_footprint()
	print("WORK_POSITIONS_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
