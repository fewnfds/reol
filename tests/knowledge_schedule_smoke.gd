extends "res://tests/activities_smoke.gd"

func scheduled_world() -> RefCounted:
	var w: RefCounted = peaceful()
	w.knowledge.records.clear() # No seed/record side effect may be required for first perception.
	return w

func changing_dependencies() -> void:
	var w := World.new()
	check(w.initialize(4, 0, false, "empty"), "Dependency world could not initialize")
	var org: int = w.institutions.create("田务")
	w.institutions.admit(w, org, 2, [])
	var site: int = w.facilities.create_completed(w, "cultivation_bed", w.Terrain.index(Vector2i(134, 124)))
	var store: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(138, 124)))
	for target: int in [site, store]: w.objects.records[target].organization = org
	var crop: int = w.nature.create(w, "sect_grain", w.objects.records[site].tile)
	check(crop > 0 and w.institutions.appoint(w, org, 2, "field_cultivator", [site, store], {"sites": [site], "sources": [store], "destination": store}) > 0, "Dependency fixture did not bind a real field duty")
	w.knowledge.records.erase(2)
	for target: int in [site, store]: w.knowledge.seed(w, 2, w.operation_target(target), 0)
	w.knowledge._store(w, 2, w.knowledge._snapshot(w, crop), "seen", 2, 2, 0, 0, 0)
	for index: int in 125:
		var target: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(220 + index % 20 * 2, 220 + index / 20 * 2)))
		w.knowledge.seed(w, 2, w.operation_target(target), 0)
	var incoming: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(140, 126)))
	w.knowledge._batch_actor = 2; w.knowledge._protection_dirty = true
	check(not w.knowledge._store(w, 2, w.knowledge._snapshot(w, incoming), "seen", 2, 2, 0, 0, 0) and w.knowledge.records[2].subjects.has(crop), "An acquired duty occupant lost protection at full capacity")
	w.nature.remove(w, crop, 0)
	w.knowledge._store(w, 2, w.knowledge._snapshot(w, site), "seen", 2, 2, 0, 0, 0)
	check(w.knowledge._store(w, 2, w.knowledge._snapshot(w, incoming), "seen", 2, 2, 0, 0, 0) and not w.knowledge.records[2].subjects.has(crop), "A removed duty occupant retained stale batch protection")
	w.knowledge._batch_actor = 0; w.knowledge._protected = {}
	w.flush_topology()
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Changed bounded dependencies did not restore")

func _run() -> void:
	changing_dependencies()
	var w: RefCounted = scheduled_world()
	var small: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(small != null, "Observation deadlines did not restore")
	if small == null: quit(1); return
	var before: int = w.knowledge.observations
	w.step(50)
	for index: int in 5: small.step(10)
	check(w.knowledge.observations - before == 2 and w.knowledge.records == small.knowledge.records, "Simultaneous due observations were unbounded or depended on outer frame size")
	w.step(50)
	for index: int in 5: small.step(10)
	check(w.knowledge.observations - before == w.actor_slots.size(), "An overdue observer was starved")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Partially drained observation batch did not restore")
	if restored == null: quit(1); return
	for index: int in 20: w.step(50)
	restored.step(1000)
	check(w.knowledge.records == restored.knowledge.records, "Observation order/evidence changed across restore and large steps")
	# Event/contact feedback is targeted and stays immediate, independent of the
	# future full-observation deadline or ordinary pulse quota.
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(124, 124)))
	w.objects.add(chest, "meal", 1)
	w.flush_topology()
	w.pages[0].positions[0] = Vector2(123.5, 124.5)
	check(w.knowledge.refresh(w, 1, chest, w.elapsed_ms) and w.knowledge.view(1, chest, w.elapsed_ms).inventory.meal == 1, "Targeted feedback was delayed behind periodic observations")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Immediate feedback corrupted the scheduled world")
	print("KNOWLEDGE_SCHEDULE_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
