extends "res://tests/teaching_smoke.gd"
## Exercise real Nature sources through the same World clock and operation host.

func qi_source(w: RefCounted, kind: String, tile: Vector2i, amount: int) -> int:
	var id: int = w.nature.create(w, kind, w.Terrain.index(tile))
	check(id > 0, "Could not create a real qi source: " + kind)
	if id == 0: return 0
	var record: Dictionary = w.objects.records[id]
	record.stage = w.nature.Stage.MATURE
	record.growth_ms = int(w.nature.definitions[kind].mature_ms)
	record.qi = amount
	w.nature._sync(w, id)
	w.flush_topology()
	return id

func source_total(w: RefCounted) -> int:
	var count: int = 0
	for id: int in w.nature.ids: count += int(w.objects.records[id].get("qi", 0))
	return count

func source_intervals_and_recovery() -> void:
	var w: RefCounted = lesson_world()
	var source: int = qi_source(w, "spirit_bamboo", Vector2i(124, 124), 0)
	for index: int in 5:
		w.step(400)
		w.nature.evaluate(w, source, w.elapsed_ms)
	check(w.objects.records[source].qi == 4 and w.objects.records[source].qi_carry == 0, "Nonintegral evaluations lost source recovery fractions")
	check(not w.objects.records[source].sapient and w.operation_target(source).source_qi_band == 0 and not w.operation_target(source).has("qi"), "Source capacity became intelligence or exact public quantity")
	w.objects.records[source].qi = 1200
	w.objects.records[source].qi_carry = 0
	w.step(900); w.nature.evaluate(w, source, w.elapsed_ms)
	check(w.objects.records[source].qi_carry == 0, "A full source banked fractional hidden recovery")
	w.objects.records[source].qi -= 100
	w.step(100); w.nature.evaluate(w, source, w.elapsed_ms)
	check(w.objects.records[source].qi == 1100 and w.objects.records[source].qi_carry == 200, "Full-source time was retroactively recovered after spending")
	var record: Dictionary = w.objects.records[source]
	record.stage = w.nature.Stage.SPROUT; record.qi = 0; record.qi_carry = 0
	record.growth_ms = int(w.nature.definitions.spirit_bamboo.mature_ms) - 1500
	record.rate = 1000
	for index: int in 5:
		w.step(400); w.nature.evaluate(w, source, w.elapsed_ms)
	check(record.stage == w.nature.Stage.MATURE and record.qi == 1 and record.qi_carry == 0, "Maturity crossing included immature time in recovery")
	w.pages[0].positions[2] = Vector2(123.5, 124.5)
	w.sight.sync(w)
	w.knowledge.observe(w, 3, w.elapsed_ms)
	check(w.knowledge.records[3].subjects.has(source), "A nonsapient qi plant without fruit was invisible to observation: " + str({"target": w.operation_target(source), "position": w.combat.position(w, 3), "seen": w.sight.observed_position(w, 3, source), "near": w.objects.nearby(w.combat.position(w, 3), 8.0, false)}))
	var saved: Dictionary = Persistence.capture(w)
	check(Persistence.candidate(saved, 0) != null, "Fractional source or public observation failed restoration")
	var bad: Dictionary = saved.duplicate(true)
	bad.domains.objects.records[source].qi_carry = -1
	check(Persistence.candidate(bad, 0) == null, "Negative source carry was accepted")
	bad = saved.duplicate(true); bad.domains.objects.records[source].qi = 1201
	check(Persistence.candidate(bad, 0) == null, "Variant source exceeded its own configured capacity")
	record.hp = 0; w.nature.evaluate(w, source, w.elapsed_ms)
	check(record.stage == w.nature.Stage.WITHERED and record.qi == 0 and record.qi_carry == 0, "Dead source retained usable qi or recovery carry")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "A withered historical source could not restore")

func full_and_unfinished_practice() -> void:
	var w: RefCounted = lesson_world()
	var tree: int = qi_source(w, "old_tree", Vector2i(124, 124), 1000)
	w.pages[0].positions[0] = Vector2(123.5, 124.5)
	w.Growth.seed(w.objects.records[1], "wood_breath", 0, false)
	w.objects.records[1]["qi"] = 3000
	for index: int in 3:
		check(w.execute_operation(1, {"kind": "practice", "target": tree}) == "accepted", "Full personal qi blocked unfinished practical mastery")
		advance(w, w.elapsed_ms + 3200)
	check(w.Growth.mastered(w.objects.records[1], "wood_breath"), "Full-qi novice could not acquire mastery through real practice")
	var before: int = w.objects.records[tree].qi
	var energy: int = w.pages[0].energy[0]
	check(w.execute_operation(1, {"kind": "practice", "target": tree}) == "qi_full" and w.objects.records[tree].qi == before and w.pages[0].energy[0] == energy, "Mastered full-qi practice spent resources or started a useless host")
	w.objects.records[1].qi = 0; w.pages[0].energy[0] = 700
	check(w.execute_operation(1, {"kind": "practice", "target": tree}) == "body_not_ready" and w.gate.current(1).is_empty(), "Unready practice walked before checking body resources")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Full/unfinished mastery or shortage failed restoration")

func _run() -> void:
	source_intervals_and_recovery()
	full_and_unfinished_practice()
	print("QI_SOURCES_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
