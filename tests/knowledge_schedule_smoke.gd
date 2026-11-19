extends "res://tests/activities_smoke.gd"

func scheduled_world() -> RefCounted:
	var w: RefCounted = peaceful()
	w.knowledge.records.clear() # No seed/record side effect may be required for first perception.
	w.knowledge.rebuild_observation_schedule(w)
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

func planning_projection_lifetime() -> void:
	var w: RefCounted = scheduled_world()
	var k: RefCounted = w.knowledge
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(124, 124)))
	w.objects.add(chest, "meal", 1)
	k.created(w, 2, chest, 0)
	k.created(w, 2, 3, 0)
	var held: Dictionary = k.planning_clues(2, 0)
	check(held == k.known(2, 0) and held.is_read_only() and held[chest].inventory.is_read_only(), "Planning received a mutable or different private projection")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null and restored.knowledge.planning_clues(2, 0) == held, "Planning projection did not rebuild from durable evidence")
	w.objects.add(chest, "meal", 1)
	check(k.planning_clues(2, 0)[chest].inventory.meal == 1 and k.planning_clues(1, 0).is_empty(), "An unseen change or another character's memory entered the planning projection")
	k.created(w, 2, chest, 0)
	check(k.planning_clues(2, 0)[chest].inventory.meal == 2 and held[chest].inventory.meal == 1, "Updating evidence edited a held planning job's snapshot")
	var revision: int = k.evidence(2, 3).revision
	k.created(w, 2, 3, 1000) # Same payload and revision, with a later expiry.
	check(k.evidence(2, 3).revision == revision and k.planning_clues(2, k.MOBILE_FRESH_MS + 1) == k.known(2, k.MOBILE_FRESH_MS + 1), "Same-value receipt left a stale expiry")
	var stale_at: int = k.MOBILE_FRESH_MS + 1001
	check(k.planning_clues(2, stale_at)[3].tile < 0 and held[3].tile >= 0, "Ageing a new projection edited a held version")
	check(k.planning_clues(2, 1000)[3].tile == held[3].tile, "An older request reused a future projection")
	k.seed(w, 2, k.view(2, 3, 1000), 0)
	check(k.planning_clues(2, k.MOBILE_FRESH_MS + 1)[3].tile < 0, "An earlier seed was hidden by a longer cached expiry")
	k.forget_actor(2)
	check(k.planning_clues(2, 0).is_empty(), "Retiring private evidence retained the cached subjects")

func indexed_admission() -> void:
	var w := World.new()
	check(w.initialize(101, 0, false, "empty"), "Admission fixture did not initialize")
	var k: RefCounted = w.knowledge
	for actor: int in w.actor_slots: k.set_observation_due(w, actor, 5000)
	for actor: int in [2, 9, 10, 11]: k.set_observation_due(w, actor, 0)
	w.kill(101, 0)
	k.admit(w, 9, 0, 0) # An urgent dependency does not spend an ordinary slot.
	for piece: int in 2:
		var item: Dictionary = w.deferred.take(0, {})
		if item.is_empty():
			check(false, "Admitted observation lost its continuation")
			return
		check(int(item.actor) == 9 and not k.service(w, 9, 0), "Urgent scan fixture did not leave a continuation")
		w.deferred.again(item, 0)
	check(int(k._scans.get(9, {}).get("cursor", 0)) > 0, "Urgent scan did not run its first slice")
	k.request(w, 9, 25)
	k.request(w, 9, 30)
	check(not k._scans.has(9), "Repeated arrival reused the previous location's scan")
	k.pulse(w, 50)
	check(w.deferred.ready.size() == 3 and w.deferred.ready.has("observe:2") and w.deferred.ready.has("observe:10") and not w.deferred.ready.has("observe:11"), "Admission changed living quota or numeric deadline tie order")
	check(w.deferred.ready.get("observe:9", {}).get("priority") == 0, "Ordinary admission changed an urgent request")
	w.kill(10, 0) # Cancel an already admitted scan.
	check(w.remove_actor(11, 0), "Admission fixture failed to remove an overdue actor")
	var born: int = w.spawn_actor(w.Terrain.index(Vector2i(140, 132)))
	check(born > 101, "Admission fixture failed to reuse an actor slot")
	k.pulse(w, 100)
	check(w.deferred.ready.size() == 3 and not w.deferred.ready.has("observe:10") and not w.deferred.ready.has("observe:11") and w.deferred.ready.has(w.deferred.key("observe", born)), "Repeated arrivals, death or slot reuse corrupted admission")
	check(w.deferred.ready.get("observe:9", {}).get("first_ms") == 0, "Repeated arrivals reset the oldest request")

func direct_observation_while_queued() -> void:
	var w := World.new()
	check(w.initialize(1, 0, false, "empty"), "Direct observation fixture did not initialize")
	var k: RefCounted = w.knowledge
	k.admit(w, 1, 0, 0)
	k.observe(w, 1, 0)
	w.step(50)
	check(k.observations == 1 and w.deferred.ready.is_empty(), "A completed direct observation ran again as a queued scan")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Future observation was rejected at restore")
	if restored == null: return
	k.pulse(w, 4999)
	restored.knowledge.pulse(restored, 4999)
	check(w.deferred.ready.is_empty() and restored.deferred.ready.is_empty(), "Future observation was admitted early")
	k.pulse(w, 5000)
	restored.knowledge.pulse(restored, 5000)
	check(w.deferred.ready.has("observe:1") and w.deferred.ready == restored.deferred.ready, "Next deadline was lost after a direct observation met a queued dependency")

func _run() -> void:
	indexed_admission()
	direct_observation_while_queued()
	changing_dependencies()
	planning_projection_lifetime()
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
