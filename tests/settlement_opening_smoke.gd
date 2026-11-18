extends "res://tests/qi_sources_smoke.gd"
const Opening = preload("res://scripts/sim/scenarios/settlement_opening.gd")
const SETUP = preload("res://data/openings/qinghe_sect.tres")

func body_source_lifecycle() -> void:
	var w := World.new(); w.initialize(4, 0)
	var tile: int = w.terrain.nearest_open(w.Terrain.index(Vector2i(180, 180)))
	var actor: int = w.spawn_actor(tile)
	var slot: int = w.actor_slots[actor]
	check(w.pages[slot / 256].source_ids[slot % 256] == -1 and w.pages[slot / 256].targets[slot % 256] == w.pages[slot / 256].positions[slot % 256], "A new idle body inherited a developer timber target")
	check(w.remove_actor(actor), "A newly created body could not release its slot")
	actor = w.spawn_actor(tile); slot = w.actor_slots[actor]
	var page: RefCounted = w.pages[slot / 256]
	check(page.source_ids[slot % 256] == -1 and page.needs_enabled[slot % 256] == 1 and page.environment_enabled[slot % 256] == 1, "Slot reuse lost capability derivation or inherited a source")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Developer opening with a reused idle body failed restoration")

func malformed_openings() -> void:
	var bad: Resource = SETUP.duplicate(true)
	bad.title = "   "
	check(not Opening.compile(bad).errors.is_empty(), "A blank institutional title reached the asserting owner")
	bad = SETUP.duplicate(true)
	bad.residents_per_district = 0; bad.spawn_offsets.clear()
	check(not Opening.compile(bad).errors.is_empty(), "A zero-resident opening bypassed Resource range hints")
	bad = SETUP.duplicate(true)
	for placement: Resource in bad.layouts[0].placements:
		if placement.definition == "wood_bed": placement.extent.x = 4
	check(not Opening.compile(bad).errors.is_empty(), "Missing residences were silently accepted")
	bad = SETUP.duplicate(true); bad.appointments[0].role = "imaginary_office"
	check(not Opening.compile(bad).errors.is_empty(), "An unknown role was silently accepted")
	bad = SETUP.duplicate(true); bad.resident_profiles[0].mentor_slot = 7
	check(not Opening.compile(bad).errors.is_empty(), "A resident was their own acquaintance mentor")
	bad = SETUP.duplicate(true); bad.resident_profiles[0].mastered.append("wood_breath")
	check(not Opening.compile(bad).errors.is_empty(), "A duplicate method could reach an asserting seed call")
	bad = SETUP.duplicate(true); bad.qi_offsets.append(bad.qi_offsets[0])
	check(not Opening.compile(bad).errors.is_empty(), "Two reservoirs could occupy the same initial point")
	bad = SETUP.duplicate(true)
	for placement: Resource in bad.layouts[0].placements:
		if placement.definition == "wood_wall": placement.stock["grain"] = 1; break
	check(not Opening.compile(bad).errors.is_empty(), "Initial goods were silently installed inside a wall")
	bad = SETUP.duplicate(true)
	var wall := preload("res://scripts/sim/definitions/openings/placement_def.gd").new()
	wall.key = "blocked_stove"; wall.definition = "wood_wall"; wall.offsets = [Vector2i(14, 10)]
	bad.layouts[1].placements.append(wall)
	check(Opening.compile(bad).errors.is_empty(), "Blocked-station counterexample was invalid before actual space adoption")
	var candidate := World.new()
	candidate.initialize(bad.population(), 0, false, "empty")
	check(not Opening.assemble(candidate, bad).is_empty(), "A stove with its only work position blocked was silently accepted")
	bad = SETUP.duplicate(true)
	for placement: Resource in bad.layouts[0].placements:
		if placement.definition == "wood_door": placement.definition = "wood_wall"
	candidate = World.new(); candidate.initialize(bad.population(), 0, false, "empty")
	check(not Opening.assemble(candidate, bad).is_empty(), "Sealed dormitories were accepted because beds had local empty cells")
	bad = SETUP.duplicate(true)
	wall = preload("res://scripts/sim/definitions/openings/placement_def.gd").new()
	wall.key = "reservoir_enclosure"; wall.definition = "wood_wall"
	wall.offsets = [Vector2i(23, 3), Vector2i(25, 3), Vector2i(24, 2), Vector2i(24, 4)]
	bad.layouts[1].placements.append(wall)
	candidate = World.new(); candidate.initialize(bad.population(), 0, false, "empty")
	check(not Opening.assemble(candidate, bad).is_empty(), "A deferred startup search silently accepted a sealed reservoir")
	bad = SETUP.duplicate(true)
	var private_chest := preload("res://scripts/sim/definitions/openings/placement_def.gd").new()
	private_chest.key = "meal_chests"; private_chest.definition = "wood_chest"; private_chest.offsets = [Vector2i(26, 15)]
	bad.layouts[1].placements.append(private_chest)
	candidate = World.new(); candidate.initialize(bad.population(), 0, false, "empty")
	check(Opening.assemble(candidate, bad).is_empty(), "A separately configured chest could not adopt")
	for origin: Vector2i in bad.district_origins:
		var chest: int = candidate.objects.by_tile[candidate.Terrain.index(origin + Vector2i(26, 15))][0]
		check(not candidate.institutions.services.get(chest, {}).has("eat"), "A placement group accidentally broadened another chest's service flag")

func _run() -> void:
	body_source_lifecycle()
	malformed_openings()
	var compiled: Dictionary = Opening.compile(SETUP)
	check(compiled.errors.is_empty(), "Normal opening definition was rejected: " + str(compiled.errors))
	if not compiled.errors.is_empty(): quit(1); return
	var w := World.new()
	check(w.initialize(SETUP.population(), 0, false, "empty"), "Empty common foundation failed")
	check(w.source_objects.is_empty() and w.terrain.resources.is_empty() and w.nature.ids.is_empty() and w.objects.total("potion") == 0 and w.society.contacts.is_empty(), "Common foundation ran developer fixtures")
	check(w.perception.explored.count(0) == w.perception.explored.size() and w.knowledge.records.is_empty(), "An unplaced foundation already created exploration or personal memories")
	check(w.combat.scan.ids.is_empty(), "Unplaced bodies already populated a stale query index")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "A legitimate world without timber sources failed restoration")
	var bad: Dictionary = Persistence.capture(w)
	bad.pages[0].source_ids[0] = -2
	check(Persistence.candidate(bad, 0) == null, "An invalid absent-source sentinel was accepted")
	var adopted_errors: PackedStringArray = Opening.assemble(w, SETUP)
	check(adopted_errors.is_empty(), "Normal opening could not adopt initial conditions: " + str(adopted_errors))
	if not adopted_errors.is_empty(): quit(1); return
	var departments: Dictionary = w.institutions.Departments.view(w.institutions, w, 1)
	var supplies: Dictionary = departments.selected
	var kitchen_id: int = 0
	for department: Dictionary in departments.departments:
		if str(department.title).ends_with("膳堂"): kitchen_id = department.id
	var kitchen: Dictionary = w.institutions.Departments.view(w.institutions, w, 1, kitchen_id).selected
	check(w.institutions.Departments.manages_person(w.institutions, 1, 7), "Named resident did not resolve to a managed subordinate")
	check(str(supplies.title).ends_with("仓务") and supplies.workers.size() == 6 and not supplies.workers.any(func(worker: Dictionary): return worker.id == 7), "Six-person supplies roster included an unrelated kitchen worker")
	check(kitchen_id > 0 and kitchen.workers.any(func(worker: Dictionary): return worker.id == 7), "Kitchen roster omitted the managed resident")
	check(not w.objects.records.values().any(func(record: Dictionary): return record.kind == "roof"), "Settlement opening spawned legacy roof tiles")
	check(w.actor_count == 100 and w.objects.total("grain") == 48 and w.objects.total("meal") == 128 and w.objects.total("potion") == 0, "Finite initial people/food or absence of developer gifts changed")
	var names: Dictionary = {}
	var sexes: Dictionary = {}
	for actor: int in w.actor_slots:
		var person: Dictionary = w.objects.records[actor]
		var name: String = person.get("name", "")
		check(name.length() in [2, 3, 4] and not names.has(name), "Invalid or duplicate resident name: " + name)
		for character: String in name:
			check(character.unicode_at(0) >= 0x4e00 and character.unicode_at(0) < 0xa000, "Resident name contains a non-Han character")
		names[name] = true
		sexes[person.get("sex", "")] = true
	check(sexes.size() == 2 and sexes.has("male") and sexes.has("female"), "Normal opening lacked both character variants")
	var saved: Dictionary = Persistence.capture(w)
	var reopened: RefCounted = Persistence.candidate(saved, 0)
	check(reopened != null, "Normal zero-time settlement failed actual restoration")
	if reopened != null:
		for actor: int in w.actor_slots:
			var person: Dictionary = w.objects.records[actor]
			var restored_person: Dictionary = reopened.objects.records[actor]
			check(person.name == restored_person.name and person.sex == restored_person.sex and person.get("resident_title", "") == restored_person.get("resident_title", ""), "Restoring changed resident identity")
	var old_record: Dictionary = saved.domains.objects.records[7]
	old_record["name"] = "东篱院弟子07"
	old_record.erase("sex")
	old_record.erase("resident_title")
	reopened = Persistence.candidate(saved, 0)
	check(reopened != null and reopened.objects.records[7].name == "东篱院弟子07" and not reopened.objects.records[7].has("sex"), "Legacy actor identity failed restoration")
	check(w.knowledge.view(15, 8, 0).get("teaches", {}).has("cooking"), "A known cooking mentor was seeded with an unrelated method only")
	check(w.decisions.records[8].next_ms == 450 and w.knowledge.records[8].due_ms <= w.decisions.records[8].next_ms, "Assembly scheduled planning before final activation or first observation")
	check(not w.knowledge.view(8, 14, 0).is_empty() and w.society.Contacts.known(w.society, 8, 14), "A mutual initial acquaintance lacked the reverse personal introduction")
	check(w.perception.explored[w.Terrain.index(Vector2i(178, 184))] == 0, "The player's placeholder position remained explored in the normal opening")
	check(w.knowledge.view(1, 2, 0).get("tile", -1) == w.Terrain.index(Vector2i(w.combat.position(w, 2).floor())), "The first observation missed the resident beside the player")
	var before: PackedInt32Array = w.pages[0].elements.duplicate()
	w.pages[0].sample_environment(0.0)
	check(before == w.pages[0].elements, "Zero-time environment still reflected placeholder positions")
	var old_trait: float = w.livelihood.records[33].dispositions.sociability
	check(w.livelihood.set_dispositions(w, 8, {"sociability": 0.1}), "Personal disposition change failed")
	check(w.livelihood.records[33].dispositions.sociability == old_trait and SETUP.resident_profiles[0].dispositions.sociability == 1.4, "Runtime personal traits mutated a peer or shared opening Resource")
	for actor: int in w.actor_slots:
		var services: Dictionary = w.institutions.Access.service_targets(w.institutions, actor)
		var beds: Array = services.get("rest", [])
		check(beds.size() == 1, "Resident lacks exactly one assigned residence: " + str(actor))
		check(w.objects.records[actor].get("autonomous", false) == (actor != 1) and int(w.objects.records[actor].get("side", 0)) == 0, "Normal resident inherited a developer controller/enemy")
		check(w.knowledge.records[actor].subjects.size() < 64, "Opening gave a resident the entire world's inventory")
	while w.elapsed_ms < 20000: w.step(250)
	check(w.facilities.completed.get("sow_grain", 0) > 0 or w.nature.ids.size() > 8, "Normal residents did not actually start their field responsibility")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Running normal settlement failed actual restoration")
	if restored != null:
		w = restored
		while w.elapsed_ms < 25000: w.step(250)
		check(w.actor_count == 100 and w.pages[0].needs_enabled[0] == 1 and w.pages[0].environment_enabled[0] == 1 and Persistence.candidate(Persistence.capture(w), 0) != null, "The restored normal settlement could not actually continue")
	print("SETTLEMENT_OPENING_SMOKE errors=", errors, " population=", w.actor_count, " initial_food=", w.objects.total("meal"), " nature=", w.nature.ids.size(), " activities=", w.facilities.completed, " teaching=", w.society.completed)
	quit(0 if errors == 0 else 1)
