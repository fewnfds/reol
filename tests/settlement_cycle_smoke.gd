extends "res://tests/sect_provisioning_smoke.gd"
## Exercise the product opening itself. No fixture cleanup, repeated orders or
## resource injection; all later progress comes from the same World owners.
const Opening = preload("res://scripts/sim/scenarios/settlement_opening.gd")
const SETUP = preload("res://data/openings/qinghe_sect.tres")
var by_district: Dictionary = {}
var refusals: Dictionary = {}
var cycle_last_result: int = 0

func account_opening(w: RefCounted) -> void:
	account(w)
	for id: int in w.activity_results.records:
		if id <= cycle_last_result: continue
		var result: Dictionary = w.activity_results.records[id]
		var district: int = (int(result.actor) - 1) / SETUP.residents_per_district
		if not by_district.has(district): by_district[district] = {}
		var counts: Dictionary = by_district[district]
		if result.status == "completed": counts[result.operation] = int(counts.get(result.operation, 0)) + 1
		else: refusals[result.reason] = int(refusals.get(result.reason, 0)) + 1
	cycle_last_result = w.activity_results.next_id - 1

func snapshot_opening(w: RefCounted) -> Dictionary:
	var satiety: Array = []
	var energy: Array = []
	for actor: int in range(2, 101):
		var slot: int = w.actor_slots[actor]
		satiety.append(int(w.pages[slot / 256].hunger[slot % 256]))
		energy.append(int(w.pages[slot / 256].energy[slot % 256]))
	satiety.sort(); energy.sort()
	return {"at_ms": w.elapsed_ms, "satiety": [satiety[0], satiety[4], satiety[49]], "energy": [energy[0], energy[4], energy[49]], "items": {"grain": w.objects.audit_total("grain"), "meal": w.objects.audit_total("meal"), "water": w.objects.audit_total("water")}, "generated": w.nature.generated_items, "actions": adopted, "refusals": refusals, "decisions": w.livelihood.decisions, "decision_ms": w.livelihood.decision_usec / 1000, "observation_ms": w.knowledge.observe_usec / 1000}

func _run() -> void:
	var w := World.new()
	check(w.initialize(SETUP.population(), 0, false, "empty"), "Normal foundation failed")
	check(Opening.assemble(w, SETUP).is_empty(), "Normal opening adoption failed")
	var initial: Dictionary = {}
	for item: String in ["grain", "water", "meal"]: initial[item] = w.objects.audit_total(item)
	var finish: int = w.environment.DAY_MS * 3 / 2
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--days="): finish = roundi(float(arg.trim_prefix("--days=")) * w.environment.DAY_MS)
	var wall: int = Time.get_ticks_msec()
	var resumed: bool = false
	while w.elapsed_ms < finish:
		w.step(mini(250, finish - w.elapsed_ms)); account_opening(w)
		if not resumed and w.elapsed_ms >= 617000:
			var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
			check(restored != null, "Actual normal opening could not restore during its source/food workflows")
			if restored != null: w = restored
			resumed = true
		if w.elapsed_ms % 120000 == 0:
			print("NORMAL_SETTLEMENT ", JSON.stringify(snapshot_opening(w)), " wall_ms=", Time.get_ticks_msec() - wall)
	var generated_water: int = 0
	for source: int in w.facilities.sources: generated_water += int(w.objects.records[source].source_generated)
	check(w.objects.audit_total("grain") + int(consumed.get("grain", 0)) == int(initial.grain) + int(w.nature.generated_items.get("grain", 0)), "Normal grain source/conversion audit failed")
	check(w.objects.audit_total("water") + int(consumed.get("water", 0)) == int(initial.water) + generated_water, "Normal water source/conversion audit failed")
	check(w.objects.audit_total("meal") + int(consumed.get("meal", 0)) == int(initial.meal) + 3 * int(adopted.get("cook", 0)), "Normal meals/real cooking/consumption audit failed")
	for actor: int in range(2, 101):
		check(w.combat.alive(w, actor) and w.pages[0].hunger[actor - 1] > 1800, "A normal autonomous resident ended hungry/dead: " + str(actor) + " " + str(w.livelihood.describe(actor)))
	for district: int in 4:
		for operation: String in ["sow_grain", "draw_water", "tend", "gather", "put", "post_duty", "accept_post", "cook", "eat", "rest", "practice"]:
			check(int(by_district.get(district, {}).get(operation, 0)) > 0, "Normal district missed real workflow: " + str(district) + ":" + operation)
	check(int(adopted.get("learn", 0)) + int(adopted.get("teach_wood_breath", 0)) > 0, "Normal opening never had real teaching")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Final normal opening failed restoration")
	print("SETTLEMENT_CYCLE_SMOKE errors=", errors, " wall_ms=", Time.get_ticks_msec() - wall, " districts=", by_district, " consumed=", consumed, " final=", snapshot_opening(w))
	quit(0 if errors == 0 else 1)
