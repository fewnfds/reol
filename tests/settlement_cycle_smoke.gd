extends "res://tests/sect_provisioning_smoke.gd"
## Exercise the product opening itself. No fixture cleanup, repeated orders or
## resource injection; all later progress comes from the same World owners.
const Opening = preload("res://scripts/sim/scenarios/settlement_opening.gd")
const SETUP = preload("res://data/openings/qinghe_sect.tres")
var by_district: Dictionary = {}
var refusals: Dictionary = {}
var cycle_last_result: int = 0
var initial: Dictionary = {}
var prior_metrics: Dictionary = {}
var qi_flows: Dictionary = {"source_spent": 0, "gained": 0}
var restored_at: Array = []
var worst: Dictionary = {}
const METRICS: Array[String] = ["decisions", "observations", "decision_usec", "observe_usec", "step_usec", "environment_usec", "units_usec", "perception_usec", "unit_decision_usec", "navigation_geometry_usec", "navigation_search_usec"]

func account_opening(w: RefCounted) -> void:
	account(w)
	# Sample independently of the coarse printed snapshots. This captures
	# personal low points during work as well as at the end of each two minutes.
	if w.elapsed_ms % 1000 == 0: sample_vitals(w)
	for id: int in w.activity_results.records:
		if id <= cycle_last_result: continue
		var result: Dictionary = w.activity_results.records[id]
		var district: int = (int(result.actor) - 1) / SETUP.residents_per_district
		if not by_district.has(district): by_district[district] = {}
		var counts: Dictionary = by_district[district]
		if result.status == "completed": counts[result.operation] = int(counts.get(result.operation, 0)) + 1
		else: refusals["%s:%s" % [result.operation, result.reason]] = int(refusals.get("%s:%s" % [result.operation, result.reason], 0)) + 1
		if result.status == "completed":
			qi_flows.source_spent += int(result.facts.get("target_qi_spent", 0))
			qi_flows.gained += int(result.facts.get("qi_gained", 0))
	cycle_last_result = w.activity_results.next_id - 1

func sample_vitals(w: RefCounted) -> void:
	for actor: int in range(2, SETUP.population() + 1):
		var slot: int = w.actor_slots[actor]
		var food: int = w.pages[slot / 256].hunger[slot % 256]
		var strength: int = w.pages[slot / 256].energy[slot % 256]
		var minimum: Dictionary = worst.get(actor, {"satiety": food, "energy": strength})
		minimum.satiety = mini(int(minimum.satiety), food); minimum.energy = mini(int(minimum.energy), strength)
		worst[actor] = minimum

func measured(w: RefCounted) -> Dictionary:
	var counters: Dictionary = w.counters()
	var result: Dictionary = {}
	for key: String in METRICS: result[key] = int(prior_metrics.get(key, 0)) + int(counters.get(key, 0))
	return result

func district_at(point: Vector2) -> int:
	var chosen: int = 0
	var distance: float = INF
	for index: int in SETUP.district_origins.size():
		var candidate: float = point.distance_squared_to(Vector2(SETUP.district_origins[index]) + Vector2(16, 17))
		if candidate < distance: chosen = index; distance = candidate
	return chosen

func lowest_sampled() -> Dictionary:
	var result: Dictionary = {"satiety": {"actor": 0, "value": 10000}, "energy": {"actor": 0, "value": 10000}}
	for actor: int in worst:
		for metric: String in result:
			if int(worst[actor][metric]) < int(result[metric].value): result[metric] = {"actor": actor, "value": int(worst[actor][metric])}
	return result

func snapshot_opening(w: RefCounted) -> Dictionary:
	var satiety: Array = []
	var energy: Array = []
	var districts: Array = []
	for index: int in SETUP.district_origins.size(): districts.append({"name": SETUP.district_names[index], "satiety": [], "energy": [], "items": {"grain": 0, "meal": 0, "water": 0}, "crops": {}, "actions": by_district.get(index, {}), "explores": 0, "memories_max": 0})
	for actor: int in range(2, SETUP.population() + 1):
		var slot: int = w.actor_slots[actor]
		var food: int = w.pages[slot / 256].hunger[slot % 256]
		var strength: int = w.pages[slot / 256].energy[slot % 256]
		var home: Dictionary = districts[(actor - 1) / SETUP.residents_per_district]
		satiety.append(food); energy.append(strength)
		home.satiety.append(food); home.energy.append(strength)
		home.explores += int(w.livelihood.records.get(actor, {}).get("explore_count", 0))
		home.memories_max = maxi(home.memories_max, w.knowledge.records.get(actor, {}).get("subjects", {}).size())
	for record: Dictionary in w.objects.records.values():
		var point: Vector2 = w.combat.position(w, record.id) if w.actor_slots.has(record.id) else w.Terrain.center(record.tile)
		var area: Dictionary = districts[district_at(point)]
		for item: String in area.items: area.items[item] += w.objects.amount(record.id, item)
		if record.kind == "plant" and record.definition == "sect_grain":
			var stage: String = w.nature.Stage.keys()[record.stage]
			area.crops[stage] = int(area.crops.get(stage, 0)) + 1
	for district: Dictionary in districts:
		district.satiety.sort(); district.energy.sort()
		district.satiety = [district.satiety[0], district.satiety[mini(4, district.satiety.size() - 1)], district.satiety[district.satiety.size() / 2]]
		district.energy = [district.energy[0], district.energy[district.energy.size() / 2]]
	satiety.sort(); energy.sort()
	return {"at_ms": w.elapsed_ms, "satiety": [satiety[0], satiety[4], satiety[satiety.size() / 2]], "energy": [energy[0], energy[4], energy[energy.size() / 2]], "lowest_sampled": lowest_sampled(), "items": {"grain": w.objects.audit_total("grain"), "meal": w.objects.audit_total("meal"), "water": w.objects.audit_total("water")}, "generated": w.nature.generated_items, "actions": adopted, "refusals": refusals, "districts": districts, "metrics": measured(w)}

func audit(w: RefCounted) -> void:
	var generated_water: int = 0
	var source_qi: int = 0
	var personal_qi: int = 0
	for source: int in w.facilities.sources: generated_water += int(w.objects.records[source].source_generated)
	for plant: int in w.nature.ids: source_qi += int(w.objects.records[plant].get("qi", 0))
	for actor: int in w.actor_slots: personal_qi += int(w.objects.records[actor].get("qi", 0))
	check(w.objects.audit_total("grain") + int(consumed.get("grain", 0)) == int(initial.grain) + int(w.nature.generated_items.get("grain", 0)), "Normal grain source/conversion audit failed")
	check(w.objects.audit_total("water") + int(consumed.get("water", 0)) == int(initial.water) + generated_water, "Normal water source/conversion audit failed")
	check(w.objects.audit_total("meal") + int(consumed.get("meal", 0)) == int(initial.meal) + 3 * int(adopted.get("cook", 0)), "Normal meals/real cooking/consumption audit failed")
	check(source_qi + int(qi_flows.source_spent) == int(initial.source_qi) + w.nature.generated_qi, "Normal finite qi sources failed conservation")
	check(personal_qi == int(initial.personal_qi) + int(qi_flows.gained), "Normal no-damage opening gained/lost unexplained personal qi")

func checkpoint(w: RefCounted, path: String) -> void:
	if path.is_empty(): return
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Could not write the explicit diagnostic checkpoint")
	if file == null: return
	file.store_var({"format": "reol-cycle-audit-1", "world": Persistence.capture(w), "initial": initial, "adopted": adopted, "consumed": consumed, "by_district": by_district, "refusals": refusals, "cycle_last_result": cycle_last_result, "last_result": last_result, "qi_flows": qi_flows, "metrics": measured(w), "restored_at": restored_at, "worst": worst}, false)
	file.close()

func _run() -> void:
	var finish: int = 3600000
	var segment_end: int = -1
	var checkpoint_path: String = ""
	var resume: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--days="): finish = roundi(float(arg.trim_prefix("--days=")) * 1200000)
		elif arg.begins_with("--checkpoint="): checkpoint_path = arg.trim_prefix("--checkpoint=")
		elif arg.begins_with("--until-ms="): segment_end = int(arg.trim_prefix("--until-ms="))
		elif arg == "--resume": resume = true
	segment_end = finish if segment_end < 0 else mini(segment_end, finish)
	var w := World.new()
	if resume:
		var file := FileAccess.open(checkpoint_path, FileAccess.READ)
		if file == null: check(false, "Missing diagnostic checkpoint"); quit(1); return
		var state: Dictionary = file.get_var(false); file.close()
		check(state.get("format") == "reol-cycle-audit-1", "Unknown diagnostic checkpoint")
		var restored: RefCounted = Persistence.candidate(state.world, 0)
		if restored == null: check(false, "Diagnostic checkpoint failed actual world restoration"); quit(1); return
		w = restored
		initial = state.initial; adopted = state.adopted; consumed = state.consumed; by_district = state.by_district; refusals = state.refusals
		cycle_last_result = state.cycle_last_result; last_result = state.last_result; qi_flows = state.qi_flows; prior_metrics = state.metrics; restored_at = state.restored_at; worst = state.worst
	else:
		check(w.initialize(SETUP.population(), 0, false, "empty"), "Normal foundation failed")
		check(Opening.assemble(w, SETUP).is_empty(), "Normal opening adoption failed")
		for item: String in ["grain", "water", "meal"]: initial[item] = w.objects.audit_total(item)
		initial.source_qi = SETUP.district_origins.size() * SETUP.qi_offsets.size() * SETUP.initial_source_qi
		initial.personal_qi = 0
	var wall: int = Time.get_ticks_msec()
	while w.elapsed_ms < segment_end:
		w.step(mini(250, segment_end - w.elapsed_ms)); account_opening(w)
		if w.elapsed_ms in [617000, 1650000] and w.elapsed_ms not in restored_at:
			var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
			check(restored != null, "Actual normal opening could not restore during its source/food workflows")
			if restored != null: prior_metrics = measured(w); w = restored
			restored_at.append(w.elapsed_ms)
		if w.elapsed_ms % 120000 == 0:
			var current: Dictionary = snapshot_opening(w)
			audit(w); checkpoint(w, checkpoint_path)
			print("NORMAL_SETTLEMENT ", JSON.stringify(current), " wall_ms=", Time.get_ticks_msec() - wall)
	audit(w); checkpoint(w, checkpoint_path)
	if w.elapsed_ms < finish:
		print("SETTLEMENT_CYCLE_PARTIAL errors=", errors, " at_ms=", w.elapsed_ms, " wall_ms=", Time.get_ticks_msec() - wall, " final=", JSON.stringify(snapshot_opening(w)))
		quit(0 if errors == 0 else 1); return
	for actor: int in range(2, SETUP.population() + 1):
		var slot: int = w.actor_slots[actor]
		check(w.combat.alive(w, actor) and w.pages[slot / 256].hunger[slot % 256] > 1800 and w.pages[slot / 256].energy[slot % 256] > 0 and int(worst.get(actor, {}).get("energy", 0)) > 0, "A normal autonomous resident ended hungry, exhausted or dead: " + str(actor) + " " + str(w.livelihood.describe(actor)))
	for district: int in 4:
		for operation: String in ["sow_grain", "draw_water", "tend", "gather", "put", "post_duty", "accept_post", "cook", "eat", "rest", "practice"]:
			check(int(by_district.get(district, {}).get(operation, 0)) > 0, "Normal district missed real workflow: " + str(district) + ":" + operation)
	check(int(adopted.get("learn", 0)) + int(adopted.get("teach_wood_breath", 0)) > 0, "Normal opening never had real teaching")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Final normal opening failed restoration")
	print("SETTLEMENT_CYCLE_SMOKE errors=", errors, " wall_ms=", Time.get_ticks_msec() - wall, " districts=", by_district, " consumed=", consumed, " final=", snapshot_opening(w))
	quit(0 if errors == 0 else 1)
