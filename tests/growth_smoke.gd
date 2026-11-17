extends "res://tests/activities_smoke.gd"
const Growth = preload("res://scripts/sim/kernel/growth.gd")

func learning_and_preserved_sources() -> void:
	var w: RefCounted = peaceful()
	w.pages[0].positions[0] = Vector2(122.5, 120.5)
	check(w.begin_interaction(1, {"kind": "learn", "target": 2}) == "accepted", "Learning fixture refused")
	advance(w, 1200)
	var origin: Dictionary = w.objects.records[1].methods.wood_breath.duplicate()
	check(origin.understanding == 200 and origin.progress == 0 and not w.describe(1).abilities.has("wood_mend"), "Instruction became practical mastery")
	check(w.begin_interaction(1, {"kind": "learn", "target": 2}) == "already_understood" and not w.society.waits.has(2), "Known personal understanding still locked a teacher for a pointless lesson")
	check(not w.operation_target(2).has("methods") and not w.operation_target(2).has("abilities"), "Learning query exposed the target's private mastery")
	check(w.begin_interaction(1, {"kind": "learn_cooking", "target": 2}) == "accepted", "Second defined lesson required a content branch")
	advance(w, w.elapsed_ms + 1200)
	check(w.objects.records[1].methods.cooking.understanding == 200 and w.objects.records[1].methods.wood_breath == origin, "A second lesson changed unrelated understanding")
	var tree: int = w.nature.create(w, "old_tree", w.Terrain.index(Vector2i(124, 124)))
	w.objects.records[tree].stage = w.nature.Stage.MATURE; w.objects.records[tree].growth_ms = int(w.nature.definitions[w.objects.records[tree].definition].mature_ms)
	w.objects.records[tree]["qi"] = 1000
	w.pages[0].positions[0] = Vector2(123.5, 124.5)
	w.begin_interaction(1, {"kind": "practice", "target": tree})
	advance(w, w.elapsed_ms + 3200)
	check(w.objects.records[1].methods.wood_breath.progress == 350 and w.objects.records[tree].qi < 1000, "Practice did not consume a real source")
	var before: Dictionary = w.objects.records[1].methods.wood_breath.duplicate()
	var qi: int = w.objects.records[tree].qi
	var energy: int = w.pages[0].energy[0]
	w.begin_interaction(1, {"kind": "practice", "target": tree})
	var missing_introduction: Dictionary = Persistence.capture(w)
	missing_introduction.domains.objects.records[1].methods.erase("wood_breath")
	check(Persistence.candidate(missing_introduction, 0) == null, "In-progress practice restored without its permanent introduction")
	advance(w, w.elapsed_ms + 200) # Keep ordinary one-second metabolism outside this cost comparison.
	w.command({"kind": "interrupt"})
	check(w.objects.records[1].methods.wood_breath == before and w.objects.records[tree].qi == qi and w.pages[0].energy[0] == energy, "Canceled practice spent final costs or invented progress")
	w.remove_actor(2)
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null and restored.objects.records[1].methods.wood_breath.teacher == 2, "Removing the historical teacher erased or invalidated learning")
	check(w.set_capability_overrides(1, {"metabolism": false}) and w.objects.records[1].methods.wood_breath == before and Persistence.candidate(Persistence.capture(w), 0) != null, "Temporary incapacity made the actor forget")
	var read_world: RefCounted = peaceful()
	read_world.objects.add(1, "breath_manual", 1)
	read_world.begin_interaction(1, {"kind": "study", "target": 1})
	advance(read_world, 1200)
	read_world.objects.transfer(1, 3, "breath_manual", 1, read_world.objects.Stock.right(1), read_world.objects.Stock.right(3)) # Explicit fixture gift transfers title.
	check(Growth.introduced(read_world.objects.records[1], "wood_breath") and Persistence.candidate(Persistence.capture(read_world), 0) != null, "Transferring the real manual erased understanding")
	check(read_world.begin_interaction(3, {"kind": "study", "target": 3}) == "accepted", "In-progress lost-book fixture refused")
	advance(read_world, read_world.elapsed_ms + 16)
	read_world.objects.transfer(3, 1, "breath_manual", 1)
	check(Persistence.candidate(Persistence.capture(read_world), 0) != null, "A legal in-progress change was mistaken for malformed learning history")
	advance(read_world, read_world.elapsed_ms + 1200)
	check(latest(read_world, 3).status == "refused" and latest(read_world, 3).reason == "missing_book" and not read_world.objects.records[3].get("methods", {}).has("wood_breath"), "Lost physical source was hidden as generic unavailable or granted understanding: " + str(latest(read_world, 3)))
	Growth.advance(read_world.objects.records[1], "cooking", 1000, "practice", 0, read_world.elapsed_ms)
	read_world.pages[0].positions[0] = Vector2(122.5, 120.5)
	check(read_world.begin_interaction(1, {"kind": "learn_cooking", "target": 2}) == "accepted", "Practical mastery incorrectly implied theoretical understanding")
	advance(read_world, read_world.elapsed_ms + 100) # Shared contact starts on the completed 50 ms motion boundary.
	check(read_world.actions.get(1, {}).has("started_ms") and read_world.pages[0].due_ms[0] - int(read_world.actions[1].get("started_ms", -1)) == 1000, "Practical mastery shortened instruction instead of only declared work")

func independent_craft_and_shared_costs() -> void:
	var w: RefCounted = peaceful()
	var stoves: Array[int] = []
	for actor: int in [1, 3]:
		var x: int = 124 if actor == 1 else 128
		stoves.append(w.facilities.create_completed(w, "cook_stove", w.Terrain.index(Vector2i(x, 124))))
		w.objects.add(actor, "grain", 2)
		w.objects.add(actor, "water", 1)
		w.pages[0].positions[actor - 1] = Vector2(x + 0.5, 125.5)
	Growth.seed(w.objects.records[3], "cooking", 0)
	Growth.seed(w.objects.records[3], "wood_breath", 0)
	w.flush_topology()
	var grain: int = w.objects.audit_total("grain")
	for index: int in 2: w.begin_interaction(1 if index == 0 else 3, {"kind": "cook", "target": stoves[index]})
	advance(w, 16)
	check(w.pages[0].due_ms[0] - w.actions[1].started_ms == 4000 and w.pages[0].due_ms[2] - w.actions[3].started_ms == 3000, "Mastered craft had no actual duration consumer")
	advance(w, 4300)
	check(w.objects.amount(stoves[0], "meal") == 3 and w.objects.amount(stoves[1], "meal") == 3 and w.objects.audit_total("grain") == grain - 4, "Player and NPC used different recipe costs")
	check(w.objects.records[1].methods.cooking.progress == 125 and not w.objects.records[1].methods.has("wood_breath") and Growth.mastered(w.objects.records[3], "wood_breath"), "Craft progress spilled into an unrelated method")
	w.objects.records[1]["abilities"] = {"external_grant": true}
	Growth.seed(w.objects.records[1], "wood_breath", w.elapsed_ms)
	check(w.describe(1).abilities.has("wood_mend") and w.describe(1).abilities.has("external_grant") and not w.objects.records[1].abilities.has("wood_mend"), "Derived unlock duplicated truth or overwrote another grant")
	var tree: int = w.nature.create(w, "old_tree", w.Terrain.index(Vector2i(124, 128)))
	w.objects.records[tree].stage = w.nature.Stage.MATURE; w.objects.records[tree].growth_ms = int(w.nature.definitions[w.objects.records[tree].definition].mature_ms)
	w.objects.records[tree]["qi"] = 1000
	w.objects.records[1]["qi"] = 2990
	w.pages[0].positions[0] = Vector2(123.5, 128.5)
	w.begin_interaction(1, {"kind": "practice", "target": tree})
	advance(w, w.elapsed_ms + 3200)
	check(latest(w, 1).facts.qi_gained == 10 and w.objects.records[1].qi == 3000 and w.describe(1).abilities.has("external_grant"), "Clamped practice reported requested qi or erased another grant")

func aptitude_and_persistent_injury() -> void:
	var w: RefCounted = peaceful()
	check(w.set_aptitudes(1, {"physique": 20, "comprehension": 20}), "Valid source aptitudes refused")
	check(w.pages[0].max_health[0] == 2050 and not w.set_aptitudes(1, {"physique": -1}), "Physique had no bounded hot-stat consumer")
	w.objects.add(1, "breath_manual", 1)
	w.objects.add(3, "breath_manual", 1)
	w.set_aptitudes(3, {"comprehension": 1})
	for actor: int in [1, 3]: w.begin_interaction(actor, {"kind": "study", "target": actor})
	advance(w, 1200)
	check(Growth.introduced(w.objects.records[1], "wood_breath") and not Growth.introduced(w.objects.records[3], "wood_breath") and w.objects.records[3].methods.wood_breath.understanding == 110, "Comprehension did not change actual understanding progress")
	w.pages[0].body_heat[0] = -50
	w.pages[0].tolerance[0] = 0
	advance(w, 2200)
	check(w.objects.records[1].get("conditions", {}).has("thermal_strain") and w.pages[0].move_speed[0] == 4.5, "Actual thermal damage produced no persistent consequence")
	w.set_capability_overrides(1, {"metabolism": false})
	check(not Growth.needs_rest(w.objects.records[1]) and w.objects.records[1].conditions.has("thermal_strain") and w.pages[0].move_speed[0] == 5.0, "Dormant persistent condition still requested pointless rest or lost its source")
	w.set_capability_overrides(1, {})
	w.pages[0].health[0] = w.pages[0].max_health[0] - 1
	check(w.command({"kind": "heal"}).ok and w.pages[0].health[0] == w.pages[0].max_health[0] and w.objects.records[1].conditions.has("thermal_strain"), "HP treatment incorrectly removed persistent injury")
	w.pages[0].body_heat[0] = 22
	w.pages[0].energy[0] = 1000
	var bed: int = w.facilities.create_completed(w, "wood_bed", w.Terrain.index(Vector2i(124, 124)))
	w.flush_topology()
	w.pages[0].positions[0] = Vector2(124.5, 124.5) # This nonblocking bed is used from its own cell.
	for attempt: int in 2:
		check(w.begin_interaction(1, {"kind": "rest", "target": bed}) == "accepted", "Safe recovery could not start")
		advance(w, w.elapsed_ms + 2100)
		if attempt == 0:
			var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
			check(restored != null and restored.objects.records[1].conditions == w.objects.records[1].conditions and restored.pages[0].move_speed[0] == w.pages[0].move_speed[0], "Partial recovery did not survive source/derived reconstruction")
	check(w.objects.records[1].conditions.is_empty() and w.pages[0].move_speed[0] == 5.0 and latest(w, 1).facts.energy_restored == 3000, "Safe rest did not consume physique and recover persistent condition: " + str({"conditions": w.objects.records[1].conditions, "speed": w.pages[0].move_speed[0], "history": w.activity_results.view(1), "temperature": w.pages[0].body_heat[0]}))

func catalog_and_bad_restore() -> void:
	check(Growth.Defs.ERRORS.is_empty() and Growth.Defs.METHODS.is_read_only() and Growth.Defs.METHODS.wood_breath.unlocks.is_read_only(), "Growth catalog failed validation/freeze")
	var variant: Resource = load("res://data/definitions/growth/wood_breath.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	variant.qi_gain = 101
	check(not variant.errors().is_empty(), "Cultivation definition minted qi without a sufficient source")
	variant.qi_gain = 60
	variant.source_qi_cost = 3001
	check(not variant.errors().is_empty(), "Cultivation definition required more qi than any legal source can store")
	var operation: Resource = load("res://data/definitions/operations/cook.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	operation.learning_method = "wood_breath"
	check(not operation.errors().is_empty(), "An authored practical consumer bypassed required introduction and produced unreadable progress")
	var w: RefCounted = peaceful()
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Normal source mastery did not restore")
	for field: String in ["progress", "learned_ms", "teacher"]:
		var bad: Dictionary = Persistence.capture(w)
		bad.domains.objects.records[2].methods.wood_breath[field] = -1
		check(Persistence.candidate(bad, 0) == null, "Malformed method field restored: " + field)
	var bad: Dictionary = Persistence.capture(w)
	bad.domains.objects.records[2].methods.wood_breath.merge({"source": "practice", "teacher": 0}, true)
	check(Persistence.candidate(bad, 0) == null, "Introduced method restored an impossible first-practice origin")
	bad = Persistence.capture(w)
	bad.growth_signature = "different-rules"
	check(Persistence.candidate(bad, 0) == null, "Changed growth rules adopted an old snapshot")

func _run() -> void:
	learning_and_preserved_sources()
	independent_craft_and_shared_costs()
	aptitude_and_persistent_injury()
	catalog_and_bad_restore()
	print("GROWTH_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
