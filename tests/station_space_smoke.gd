extends "res://tests/activities_smoke.gd"
const Service = preload("res://scripts/sim/kernel/service_positions.gd")

func place(w: RefCounted, actor: int, point: Vector2) -> void:
	w.release(actor)
	var slot: int = w.actor_slots[actor]
	var page: RefCounted = w.pages[slot / 256]; var row: int = slot % 256
	page.positions[row] = point; page.targets[row] = point; page.motion.erase(row)
	page.modes[row] = w.Units.Mode.IDLE
	w.stations.invalidate()

func local_admissions_and_motion() -> void:
	var w: RefCounted = peaceful()
	advance(w, 16)
	for actor: int in w.actor_slots: place(w, actor, Vector2(120.5 + actor * 3, 120.5))
	var target := Vector2(124.5, 126.5)
	check(Service.occupants(w, target, 0.35, 1).is_empty(), "Empty station incorrectly occupied")
	w.pages[0].move_to(1, target, w.Units.Mode.APPROACH)
	check(Service.occupants(w, target, 0.35, 1) == [2], "Same-batch destination admission absent from station query")
	w.clear_navigation(2); w.pages[0].modes[1] = w.Units.Mode.IDLE
	check(Service.occupants(w, target, 0.35, 1).is_empty(), "Cancelled approach retained its station destination")
	# Endpoint boxes alone miss this interior right-angle turn. The exact query
	# uses the same normalized timed motion as work and collision settlement.
	w._motion_begin = 16; w._motion_end = 116; w._commit_ms = 66
	w.combat.previous.clear(); w.combat.previous.append(w.pages[0].positions.duplicate())
	w.combat.previous[0][1] = Vector2(120.5, 120.5)
	w.pages[0].positions[1] = Vector2(128.5, 120.5)
	w.pages[0].targets[1] = Vector2(128.5, 120.5)
	w.pages[0].motion[1] = PackedVector3Array([Vector3(120.5, 120.5, 0), Vector3(124.5, 126.5, 0.5), Vector3(128.5, 120.5, 1)])
	w.stations.invalidate()
	check(Service.occupants(w, target, 0.35, 1, false) == [2], "Timed interior motion knot omitted from station broad phase")
	w._commit_ms = 16
	check(Service.occupants(w, target, 0.35, 1, false).is_empty(), "Broad phase candidate was mistaken for exact occupancy")
	w._commit_ms = -1; w._motion_begin = 0; w._motion_end = 0
	place(w, 2, target)
	check(Service.occupants(w, target, 0.35, 1, false) == [2], "Current body missing from station")
	w.pages[0].health[1] = 0
	check(Service.occupants(w, target, 0.35, 1, false).is_empty(), "Dead candidate blocked station")
	w.pages[0].health[1] = 2000
	check(w.remove_actor(2), "Station fixture could not remove actor")
	var replacement: int = w.spawn_actor(w.Terrain.index(Vector2i(140, 140)))
	check(replacement != 2 and w.actor_slots[replacement] == 1 and Service.occupants(w, target, 0.35, 1, false).is_empty(), "Reused body slot retained old station identity")
	place(w, replacement, target)
	check(Service.occupants(w, target, 0.35, 1, false) == [replacement], "Spawn did not invalidate station index")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Station derived index prevented restore")
	if restored != null:
		check(Service.occupants(restored, target, 0.35, 1, false) == [replacement], "Restored station index not rebuilt")
		restored.pages[0].move_to(2, Vector2(130.5, 130.5), w.Units.Mode.APPROACH)
		check(Service.occupants(restored, Vector2(130.5, 130.5), 0.35, 1).has(3), "Restore omitted destination callback")

func unrelated_population() -> void:
	var w: RefCounted = peaceful()
	advance(w, 16)
	for actor: int in w.actor_slots: place(w, actor, Vector2(120.5 + actor * 3, 120.5))
	var target := Vector2(126.5, 120.5)
	var baseline: Array[int] = Service.occupants(w, target, 0.35, 1, false)
	var initial: int = w.stations.candidates
	Service.occupants(w, target, 0.35, 1, false)
	var local_count: int = w.stations.candidates - initial
	var spawned: int = 0
	for index: int in 300:
		if w.spawn_actor(w.Terrain.index(Vector2i(200 + index % 10, 200 + index / 10))) > 0: spawned += 1
	var start: int = w.stations.candidates
	check(Service.occupants(w, target, 0.35, 1, false) == baseline and w.stations.candidates - start == local_count, "Unrelated far bodies amplified exact station candidates")
	check(spawned >= 200, "Too few unrelated bodies to exercise station scale")
	print("STATION_LOCAL candidates=", local_count, " unrelated=", spawned, " indexed=", w.stations.indexed)

func _run() -> void:
	local_admissions_and_motion()
	unrelated_population()
	print("STATION_SPACE_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
