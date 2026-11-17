extends "res://tests/custody_smoke.gd"
const Care = preload("res://scripts/sim/kernel/cultivation.gd")
const Plants = preload("res://scripts/sim/kernel/nature_defs.gd")

func seeded(w: RefCounted, host: int, operation: String = "sow_grain", actor: int = 1) -> int:
	w.pages[0].positions[actor - 1] = w.Terrain.center(w.objects.records[host].tile)
	check(w.begin_interaction(actor, {"kind": operation, "target": host}) == "accepted", "Configured planting did not enter the common host")
	advance(w, w.elapsed_ms + 1700)
	var plant: int = int(w.objects.records[host].guest)
	check(plant > 0 and latest(w, actor).facts.get("planted") == plant, "Common planting did not produce one real sprout")
	return plant

func planting_and_care() -> void:
	var w: RefCounted = peaceful()
	var host: int = facility(w, "cultivation_bed", 124, 124, 0)
	var stock: int = w.objects.audit_total("grain")
	var water: int = int(w.objects.records[host].water)
	w.pages[0].positions[0] = Vector2(124.5, 124.5)
	check(w.begin_interaction(1, {"kind": "sow_grain", "target": host}) == "accepted", "Planting was not admitted")
	advance(w, 650)
	var mid: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(mid != null and mid.objects.records[host].guest == 0, "In-progress planting invented the crop or could not resume")
	if mid != null:
		advance(mid, mid.elapsed_ms + 1700)
		check(mid.objects.records[host].guest > 0 and mid.objects.audit_total("grain") == stock - 1, "Restored planting did not commit exactly once")
	w.end_run(1, w.elapsed_ms, "preempted")
	check(w.objects.audit_total("grain") == stock and w.objects.records[host].guest == 0 and w.objects.records[host].water == water, "Canceled planting consumed seed/water or created a ghost plant")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Canceled planting was not restorable")
	var plant: int = seeded(w, host)
	if plant == 0: return
	check(w.objects.audit_total("grain") == stock - 1 and w.objects.records[plant].stage == w.nature.Stage.SPROUT and w.objects.records[plant].cells == w.objects.records[host].cells, "Sowing did not consume exactly one seed into one whole bed")
	check(w.knowledge.records[1].subjects.has(plant), "The planter did not know their own actual sprout")
	w.pages[0].positions[2] = Vector2(125.5, 124.5)
	w.knowledge.observe(w, 3, w.elapsed_ms)
	check(w.knowledge.records[3].subjects.has(plant), "A visible hosted seedling was filtered out like an irrelevant wild plant")
	check(w.begin_interaction(1, {"kind": "sow_herb", "target": host}) == "occupied", "Another crop overwrote an occupied bed")
	w.objects.records[host].water = 70
	var before: int = w.objects.audit_total("water")
	check(w.begin_interaction(1, {"kind": "tend", "target": plant}) == "accepted", "Care did not use the normal operation")
	advance(w, w.elapsed_ms + 1700)
	check(w.objects.records[host].water == 100 and w.objects.audit_total("water") == before - 1 and latest(w, 1).facts.water_added == 30, "Care did not clamp actual water or report actual cost")
	check(w.begin_interaction(1, {"kind": "tend", "target": plant}) == "not_needed" and w.nature.tend(w, 1, plant, w.elapsed_ms).reason == "not_needed", "Full healthy care was advertised or consumed twice")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Real crop/care/observations failed restoration")
	var bare: int = w.nature.create(w, "annual_grass", w.Terrain.index(Vector2i(129, 124)))
	before = w.objects.audit_total("water")
	check(w.nature.tend(w, 1, bare, w.elapsed_ms).reason == "not_needed" and w.objects.audit_total("water") == before, "Healthy bare soil consumed ineffective water")
	w.objects.records[bare].injury_ms = 60000
	check(w.nature.tend(w, 1, bare, w.elapsed_ms).facts.injury_recovered_ms == 60000, "Actual injury could not be cared for on bare terrain")
	var other: int = facility(w, "cultivation_bed", 130, 124, 0)
	var herb: int = seeded(w, other, "sow_herb")
	if herb == 0: return
	w.objects.records[other].water = 80
	check(w.nature.tend(w, 1, herb, w.elapsed_ms).facts.water_added == 10 and w.objects.records[other].water == 90, "Shared care overwatered a plant with a smaller suitable range")
	check(Care.valid(w.objects.records[other], w.facilities.definitions.cultivation_bed), "Physical host failed the shared cultivation contract")
	w.objects.records[other].water = 100
	w.objects.records[herb].injury_ms = 60000
	before = w.objects.audit_total("water")
	check(w.begin_interaction(1, {"kind": "tend", "target": herb}) == "water_excess" and w.nature.tend(w, 1, herb, w.elapsed_ms).reason == "water_excess" and w.objects.audit_total("water") == before, "Waterlogged plants invited repeated ineffective watering")
	var nonanchor: int = facility(w, "cultivation_bed", 134, 124, 0)
	var placed: Dictionary = w.nature.plant_site(w, 1, "sect_grain", w.objects.records[nonanchor].tile + 513)
	check(placed.reason == "accepted" and w.objects.records[placed.get("target", 0)].tile == w.objects.records[nonanchor].tile, "Non-anchor planting drifted the hosted plant's logical origin")
	var obstructed: int = facility(w, "cultivation_bed", 138, 124, 0)
	var foreign: int = w.objects.create("furniture", "wood_chair", w.objects.records[obstructed].tile + 513)
	check(not w.nature.can_plant(w, "sect_grain", w.objects.records[obstructed].tile).ok, "Planting expanded across a foreign non-anchor occupant")
	w.objects.remove_empty(foreign)
	var roof: int = w.objects.create("blueprint", "wood_roof", w.objects.records[obstructed].tile + 513)
	w.objects.records[roof]["layer"] = "roof"
	check(w.nature.can_plant(w, "sect_grain", w.objects.records[obstructed].tile).ok, "A roof blueprint blocked unrelated cultivation ground")
	w.objects.remove_empty(roof)
	check(w.nature.commit(w, 1, {"kind": "gather", "target": obstructed}, w.elapsed_ms).reason == "invalid_target", "Domain commit crashed or harvested a non-plant")

func entrusted_and_interrupted() -> void:
	var w: RefCounted = peaceful()
	var org: int = organization(w)
	var host: int = facility(w, "cultivation_bed", 124, 124, org)
	var store: int = facility(w, "granary", 127, 124, org)
	w.objects.add(store, "grain", 2, Stock.right(0, org))
	clear_private(w, 1, "grain")
	w.pages[0].positions[0] = Vector2(126.5, 124.5)
	carry(w, 1, store, "grain", 1, "take", "cultivate")
	var plant: int = seeded(w, host)
	if plant == 0: return
	check(w.objects.records[plant].organization == org and w.institutions.entrustments.is_empty() and w.objects.amount(1, "grain") == 0, "Entrusted seed was rejected, privatized or left as an unclosed issue")
	check(w.begin_interaction(2, {"kind": "sow_grain", "target": store}) == "invalid_target", "Plant operation accepted a non-cultivation facility")
	var empty: int = facility(w, "cultivation_bed", 130, 124, org)
	check(w.begin_interaction(2, {"kind": "sow_grain", "target": empty}) == "not_authorized", "Planting bypassed public cultivation authorization")
	w.pages[0].positions[0] = Vector2(126.5, 124.5)
	carry(w, 1, store, "grain", 1, "take", "cultivate")
	var site: Dictionary = w.nature.plant_site(w, 1, "sect_grain", w.objects.records[empty].tile, org)
	check(site.reason == "accepted", "Original prepaid sowing site was not supported")
	if site.reason != "accepted": return
	var next_entrust: int = w.institutions.next_entrust
	var total: int = w.objects.audit_total("grain")
	var result: Dictionary = w.nature.commit(w, 1, {"kind": "uproot", "target": site.target}, w.elapsed_ms)
	check(result.status == "completed" and w.institutions.next_entrust == next_entrust and w.objects.audit_total("grain") == total and w.objects.records[empty].guest == 0, "Removing uncommitted input minted an issue, lost seed or retained the host edge")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Preserved entrusted seed batch/remains did not restore")
	# Physical source access and entrusted use are distinct permissions. Keep both.
	var well: int = facility(w, "water_well", 134, 124, org)
	while w.elapsed_ms < 30000: w.step(mini(1000, 30000 - w.elapsed_ms))
	clear_private(w, 1, "water")
	w.institutions.admit(w, org, 1, ["cultivate"])
	w.pages[0].positions[0] = Vector2(133.5, 124.5)
	check(w.begin_interaction(1, {"kind": "draw_water", "target": well, "purpose": "cultivate"}) == "not_authorized", "A consumption purpose bypassed the well's separate source permission")
	w.institutions.admit(w, org, 1, ["supply", "cultivate"])
	check(w.begin_interaction(1, {"kind": "draw_water", "target": well, "purpose": "cultivate"}) == "accepted", "Explicit authorized cultivation water could not be drawn")
	advance(w, w.elapsed_ms + 1700)
	var drawn: int = int(latest(w, 1).facts.get("amount", 0))
	check(drawn > 0 and w.objects.amount(1, "water") == drawn and w.institutions.bundles(w, 1).any(func(bundle: Dictionary): return bundle.purpose == "cultivate" and bundle.items.get("water", 0) == drawn), "Drawn water lost its explicitly declared entrusted purpose")
	w.pages[0].positions[0] = Vector2(124.5, 124.5)
	check(w.begin_interaction(1, {"kind": "tend", "target": plant}) == "accepted", "Actually drawn public cultivation water could not care for the public crop")
	advance(w, w.elapsed_ms + 1700)
	check(w.objects.amount(1, "water") == drawn - 1 and w.objects.records[host].water == 100, "Authorized public source/care did not consume one real water")
	var replenishment: int = int(w.objects.records[well].source_due_ms)
	while w.elapsed_ms < replenishment: w.step(mini(1000, replenishment - w.elapsed_ms))
	var serial: int = w.institutions.next_entrust
	w.objects.records[1].capacity = w.objects.count_inventory(1)
	check(w.institutions.acquire_yield(w, 1, well, "water", 1, w.elapsed_ms, "cultivate") == 0 and w.institutions.next_entrust == serial, "A full recipient minted a pointless entrusted issue")
	w.objects.records[1].capacity = -1
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Public water source/use left an inconsistent issue ledger")

func clocks_and_bad_candidates() -> void:
	var w: RefCounted = peaceful()
	var host: int = facility(w, "cultivation_bed", 124, 124, 0)
	var plant: int = seeded(w, host)
	if plant == 0: return
	var record: Dictionary = w.objects.records[plant]
	# Exercise the production boundary, without shortening authored durations.
	record.growth_ms = int(Plants.DEFINITIONS.sect_grain.mature_ms) - 3000
	record.rate = 1000
	w.nature.evaluate(w, plant, int(record.last_ms) + 5000)
	check(record.stage == w.nature.Stage.MATURE and record.product_ms == 2000 and not w.nature.generated_items.has("grain"), "Crossing maturity counted the whole interval as production")
	record.rate = 1000
	record.product_ms = int(Plants.DEFINITIONS.sect_grain.product.period_ms) - 1000
	var total: int = w.objects.audit_total("grain")
	w.nature.evaluate(w, plant, int(record.last_ms) + 5000)
	check(w.objects.audit_total("grain") == total + 1 and w.nature.generated_items.grain == 1 and record.product_ms == 4000, "Real natural production did not conserve its generated counter")
	w.objects.add(plant, "grain", 12 - w.objects.amount(plant, "grain"))
	record.rate = 1000
	w.nature.evaluate(w, plant, int(record.last_ms) + 5000)
	check(record.product_ms == 0, "A full crop banked future production time")
	w.objects.add(plant, "grain", -12)
	record.rate = 1000
	w.nature.evaluate(w, plant, int(record.last_ms) + 5000)
	check(w.objects.amount(plant, "grain") == 0 and record.product_ms == 5000, "Harvesting a capped crop released free backlogged output")
	# Night is cessation of growth, not annual injury.
	var annual: int = w.nature.create(w, "annual_grass", w.Terrain.index(Vector2i(129, 124)))
	w.environment.light = 0
	w.nature.evaluate(w, annual, w.elapsed_ms)
	check(w.objects.records[annual].rate == 0 and not w.objects.records[annual].adverse, "Night incorrectly injured a healthy annual")
	var legal: RefCounted = peaceful()
	var bed: int = facility(legal, "cultivation_bed", 124, 124, 0)
	var sprout: int = seeded(legal, bed)
	if sprout == 0: return
	var state: Dictionary = Persistence.capture(legal)
	check(Persistence.candidate(state, 0) != null, "Base cultivation save was invalid")
	for field: String in ["product_ms", "age_ms", "injury_ms", "last_ms", "growth_ms"]:
		var bad: Dictionary = state.duplicate(true)
		bad.domains.objects.records[sprout][field] = -1
		check(Persistence.candidate(bad, 0) == null, "Restore accepted a negative plant clock: " + field)
	for mutation: String in ["water", "water_ms", "host", "guest", "stage", "counter", "signature"]:
		var bad: Dictionary = state.duplicate(true)
		match mutation:
			"water": bad.domains.objects.records[bed].water = 101
			"water_ms": bad.domains.objects.records[bed].water_ms = 30000
			"host": bad.domains.objects.records[sprout].host = 0
			"guest": bad.domains.objects.records[bed].guest = 0
			"stage": bad.domains.objects.records[sprout].stage = legal.nature.Stage.MATURE
			"counter": bad.domains.nature.generated_items = {"grain": -1}
			"signature": bad.nature_signature = "different plant rules"
		check(Persistence.candidate(bad, 0) == null, "Restore accepted an inconsistent cultivation edge/clock: " + mutation)
	var source: int = facility(legal, "water_well", 128, 124, 0)
	legal.pages[0].positions[0] = Vector2(127.5, 124.5)
	check(legal.begin_interaction(1, {"kind": "demolish", "target": source}) == "accepted", "Finite source could not be removed through the normal operation")
	advance(legal, legal.elapsed_ms + 500)
	check(not legal.objects.records.has(source) and not legal.facilities.sources.has(source) and Persistence.candidate(Persistence.capture(legal), 0) != null, "Source removal retained its physical/source registration")

func source_cycle() -> void:
	var w := World.new()
	w.initialize(1, 0)
	w.release(1); w.objects.records[1].autonomous = false; w.objects.records[1].side = 0
	w.livelihood.forget(1)
	for id: int in w.nature.ids.duplicate(): w.nature.remove(w, id)
	w.flush_topology()
	w.environment.weather_override = 0
	var host: int = facility(w, "cultivation_bed", 124, 124, 0)
	var well: int = facility(w, "water_well", 128, 124, 0)
	var plant: int = seeded(w, host)
	if plant == 0: return
	var grain: int = w.objects.audit_total("grain")
	var water: int = w.objects.audit_total("water")
	var max_step_usec: int = 0
	while w.elapsed_ms < w.environment.DAY_MS * 2:
		var started: int = Time.get_ticks_usec()
		w.step(mini(1000, w.environment.DAY_MS * 2 - w.elapsed_ms))
		max_step_usec = maxi(max_step_usec, Time.get_ticks_usec() - started)
	var generated: int = int(w.nature.generated_items.get("grain", 0))
	var water_generated: int = 0
	for source: int in w.facilities.sources: water_generated += int(w.objects.records[source].source_generated)
	print("TWO_DAY_SOURCE ", {"crop": generated, "host": w.objects.records[host], "water_generated": w.objects.records[well].source_generated, "well": w.objects.amount(well, "water"), "water_delta": w.objects.audit_total("water") - water})
	check(w.objects.records[plant].stage == w.nature.Stage.MATURE and generated >= 1 and w.objects.audit_total("grain") == grain + generated and w.objects.records[plant].adverse, "Two unattended days did not produce and then stop at actual drought: " + str(w.objects.records[plant]))
	check(w.objects.records[host].water == 1 and w.objects.records[well].source_generated == 24 and w.objects.amount(well, "water") == 24 and w.objects.audit_total("water") == water + water_generated, "Living crop or bounded full well lost actual water accounting")
	w.pages[0].positions[0] = Vector2(127.5, 124.5)
	check(w.begin_interaction(1, {"kind": "draw_water", "target": well}) == "accepted", "Water could not be collected after the full source interval")
	advance(w, w.elapsed_ms + 1700)
	check(w.objects.amount(well, "water") == 20, "Well did not actually release finite stock")
	w.pages[0].positions[0] = Vector2(124.5, 124.5)
	check(w.begin_interaction(1, {"kind": "tend", "target": plant}) == "accepted", "Nearly dry living crop could not be watered")
	advance(w, w.elapsed_ms + 1700)
	check(w.objects.records[host].water == 40 and w.objects.audit_total("water") == water + water_generated - 1 and latest(w, 1).facts.water_added == 40, "Watering did not consume one actual sourced item")
	check(w.begin_interaction(1, {"kind": "gather", "target": plant}) == "accepted", "Actual day-grown crop could not be harvested")
	advance(w, w.elapsed_ms + 1700)
	check(w.objects.amount(plant, "grain") == 0 and w.objects.audit_total("grain") == grain + generated and int(latest(w, 1).facts.get("amount", 0)) == generated, "Harvesting minted or lost the natural crop")
	while w.elapsed_ms < w.environment.DAY_MS * 3:
		w.step(mini(1000, w.environment.DAY_MS * 3 - w.elapsed_ms))
	check(int(w.nature.generated_items.get("grain", 0)) > generated and w.objects.records[plant].hp > 0 and w.objects.audit_total("grain") == grain + int(w.nature.generated_items.grain), "Watering/harvesting did not resume actual production on the next day")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Two-day actual source/consumption state did not restore")
	print("CULTIVATION_SOURCE_CYCLE ", {"world_ms": w.elapsed_ms, "grain_generated": w.nature.generated_items.get("grain", 0), "water_generated_local_well": w.objects.records[well].source_generated, "host_water": w.objects.records[host].water, "max_1s_step_usec": max_step_usec, "errors": errors})

func _run() -> void:
	if "--source-cycle" in OS.get_cmdline_user_args():
		source_cycle()
		quit(0 if errors == 0 else 1)
		return
	check(Plants.ERRORS.is_empty(), "Plant definitions failed validation: " + str(Plants.ERRORS))
	planting_and_care()
	entrusted_and_interrupted()
	clocks_and_bad_candidates()
	print("CULTIVATION_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
