extends "res://tests/institution_duties_smoke.gd"

func field_fixture() -> Dictionary:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	f.well = workshop(w, f.org, "water_well", Vector2i(121, 125))
	f.beds = [workshop(w, f.org, "cultivation_bed", Vector2i(124, 125)), workshop(w, f.org, "cultivation_bed", Vector2i(128, 125))]
	w.objects.add(f.source, "grain", 4, Stock.right(0, f.org))
	w.flush_topology()
	for actor: int in [3, 4]: resident(w, actor, f.beds + [int(f.source), int(f.well), int(f.destination)])
	f.scope = {"sites": f.beds.duplicate(), "sources": [int(f.source), int(f.well)], "destination": int(f.destination)}
	f.appointment = w.institutions.appoint(w, f.org, 3, "field_cultivator", f.beds + [int(f.source), int(f.well), int(f.destination)], f.scope)
	check(f.appointment > 0, "Real cultivation appointment refused")
	return f

func field_rights_and_work() -> void:
	var f: Dictionary = field_fixture()
	var w: RefCounted = f.world
	w.decisions.prepare(w, 0)
	advance(w, 20000)
	for bed: int in f.beds:
		var crop: int = w.objects.records[bed].guest
		check(crop > 0, "Autonomous field duty did not source seed and plant every bed: " + str(w.livelihood.describe(3)))
		if crop == 0: continue
		check(w.objects.records[crop].organization == f.org and crop not in w.institutions.appointments[f.appointment].targets, "Crop title or stable appointment scope was changed")
		check(Stock.permits_at(w.operation_actor(3), w.operation_target(crop), "cultivate", "grain") and Stock.permits_at(w.operation_actor(3), w.operation_target(crop), "supply", "grain"), "Stable host did not authorize field output")
		check(not Stock.permits_at(w.operation_actor(3), w.operation_target(crop), "demolish", "grain") and not Stock.permits_at(w.operation_actor(4), w.operation_target(crop), "cultivate", "grain"), "Field rights spread to unrelated purposes or people")
		w.objects.records[bed].water = 35
		w.knowledge.refresh(w, 3, bed, w.elapsed_ms)
	w.decisions.wake(w, 3, w.elapsed_ms, "knowledge_observed")
	advance(w, 60000)
	check(f.beds.all(func(bed: int): return w.objects.records[bed].water > 35), "Farmer did not actually collect public water for cultivation and care for both crops: " + str(w.livelihood.describe(3)))
	check(int(w.facilities.completed.get("draw_water", 0)) == 2 and int(w.objects.records[f.well].source_generated) - w.objects.amount(f.well, "water") == 2, "Field care did not collect and consume two real public water items")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Running field duty did not restore")
	# The same authority must follow the next real plant, not the old plant ID.
	var first: int = w.objects.records[f.beds[0]].guest
	w.nature.remove(w, first, w.elapsed_ms)
	w.knowledge.refresh(w, 3, int(f.beds[0]), w.elapsed_ms)
	w.decisions.wake(w, 3, w.elapsed_ms, "knowledge_observed")
	advance(w, w.elapsed_ms + 15000)
	check(w.objects.records[f.beds[0]].guest > first and w.institutions.appointments[f.appointment].active, "A new crop lost stable field authority")
	var scope: Dictionary = f.scope.duplicate(true)
	scope.destination = int(f.source)
	check(w.institutions.Duties.scope_valid(w, "field_cultivator", scope, f.beds + [int(f.source), int(f.well)], true), "Seed store could not also receive real harvests")
	scope.sites.append(int(f.well))
	check(not w.institutions.Duties.scope_valid(w, "field_cultivator", scope, f.beds + [int(f.source), int(f.well)], true), "A water source was accepted as cultivation ground")
	check(w.institutions.Channels.post_duty(w.institutions, w, 3, f.source, f.appointment, w.elapsed_ms).reason == "not_authorized", "A field appointment posted an administrative stock order")
	# Removing one host leaves other sites; losing the last site closes the duty.
	w.nature.remove(w, int(w.objects.records[f.beds[0]].guest), w.elapsed_ms)
	check(w.remove_static(int(f.beds[0])) and w.institutions.appointments[f.appointment].active, "One removed bed revoked the entire field")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Partially removed field scope did not restore")
	w.nature.remove(w, int(w.objects.records[f.beds[1]].guest), w.elapsed_ms)
	check(w.remove_static(int(f.beds[1])) and not w.institutions.appointments[f.appointment].active, "Empty field scope retained active work")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Inactive empty historical scope did not restore")

func observed_harvest_and_revoke() -> void:
	var f: Dictionary = field_fixture()
	var w: RefCounted = f.world
	var crop: int = w.nature.create(w, "sect_grain", w.objects.records[f.beds[0]].tile)
	w.objects.records[crop].stage = w.nature.Stage.MATURE
	w.objects.records[crop].growth_ms = int(w.nature.definitions.sect_grain.mature_ms)
	w.objects.add(crop, "grain", 5, Stock.right(0, f.org))
	w.knowledge.refresh(w, 3, int(f.beds[0]), 0)
	check(w.knowledge.records[3].subjects.has(crop), "Observing a visible host did not observe its visible crop")
	w.decisions.prepare(w, 0)
	advance(w, 20000)
	check(w.objects.amount(f.destination, "grain", Stock.right(0, f.org)) == 5 and w.nature.collections == 5, "Harvest did not retain supply attribution through explicit public deposit")
	w.objects.records[f.destination].capacity = 5
	w.objects.add(crop, "grain", 2, Stock.right(0, f.org))
	w.objects.records[f.beds[0]].water = 35
	w.knowledge.refresh(w, 3, int(f.beds[0]), w.elapsed_ms)
	w.knowledge.refresh(w, 3, int(f.destination), w.elapsed_ms)
	w.decisions.wake(w, 3, w.elapsed_ms, "knowledge_observed")
	advance(w, 40000)
	check(w.objects.amount(crop, "grain") == 2 and w.objects.records[f.beds[0]].water > 35, "Full store stopped care or harvested output without a destination")
	w.command({"kind": "interrupt", "actor": 3})
	var issued: Dictionary = w.institutions.move_goods(w, 3, f.source, "grain", 1, "take", {"purpose": "cultivate"}, w.elapsed_ms)
	check(issued.status == "completed" and w.institutions.revoke(w, f.appointment), "Could not revoke a carrier of real seed")
	w.objects.records[3].autonomous = true
	w.decisions.resume(w, 3, w.elapsed_ms)
	advance(w, 55000)
	check(w.institutions.return_bundles(w, 3).is_empty(), "Revoked farmer did not return entrusted seed")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Revoked mandate/field history did not restore")

func variant_and_empty_source() -> void:
	var f: Dictionary = field_fixture()
	var w: RefCounted = f.world
	check(w.objects.consume(f.source, {"grain": 4}, Stock.right(0, f.org)), "Could not set a genuinely empty seed source")
	var herb_bed: int = workshop(w, f.org, "cultivation_bed", Vector2i(132, 125))
	w.objects.add(f.source, "herb", 1, Stock.right(0, f.org))
	w.flush_topology()
	w.knowledge.seed(w, 4, w.operation_target(herb_bed), 0)
	var appointment: int = w.institutions.appoint(w, f.org, 4, "herb_cultivator", [herb_bed, int(f.source), int(f.well), int(f.destination)], {"sites": [herb_bed], "sources": [int(f.source), int(f.well)], "destination": int(f.destination)})
	check(appointment > 0, "Shared herb duty variant refused")
	w.decisions.prepare(w, 0)
	advance(w, 25000)
	check(f.beds.all(func(bed: int): return w.objects.records[bed].guest == 0) and w.institutions.appointments[f.appointment].active, "Empty seed source fabricated a crop or revoked the role")
	var crop: int = int(w.objects.records[herb_bed].guest)
	check(crop > 0 and w.objects.records[crop].definition == "perennial_herb", "Different crop configuration required a separate planner")
	w.objects.add(f.source, "grain", 2, Stock.right(0, f.org))
	advance(w, 60000)
	check(f.beds.all(func(bed: int): return w.objects.records[bed].guest > 0), "A restored seed source did not wake the existing duty")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Mixed crop duties/temporary shortage did not restore")

func blocked_bed_does_not_starve_other_sites() -> void:
	var f: Dictionary = field_fixture()
	var w: RefCounted = f.world
	for y: int in range(124, 128):
		for x: int in range(123, 127):
			if x in [123, 126] or y in [124, 127]: workshop(w, f.org, "wood_wall", Vector2i(x, y))
	w.flush_topology()
	w.decisions.prepare(w, 0)
	advance(w, 60000)
	check(w.objects.records[f.beds[0]].guest == 0 and w.objects.records[f.beds[1]].guest > 0, "One unreachable bed exhausted all planning work for other sites: " + str(w.livelihood.describe(3)))
	check(w.institutions.appointments[f.appointment].active and Persistence.candidate(Persistence.capture(w), 0) != null, "Blocked field changed social authority or corrupted recovery")

func dry_mature_fields_under_small_allowance() -> void:
	var f: Dictionary = field_fixture()
	var w: RefCounted = f.world
	var fields: Array = f.beds.duplicate()
	for index: int in 10: fields.append(workshop(w, f.org, "cultivation_bed", Vector2i(134 + index % 5 * 3, 125 + index / 5 * 3)))
	check(w.institutions.revoke(w, f.appointment), "Could not replace field scope")
	var appointed: Array = fields + [int(f.source), int(f.well), int(f.destination)]
	var appointment: int = w.institutions.appoint(w, f.org, 3, "field_cultivator", appointed, {"sites": fields, "sources": [int(f.source), int(f.well)], "destination": int(f.destination)})
	for bed: int in fields:
		var crop: int = w.nature.create(w, "sect_grain", w.objects.records[bed].tile)
		w.objects.records[bed].water = 35
		if bed == int(fields[0]):
			w.objects.records[crop].stage = w.nature.Stage.MATURE
			w.objects.records[crop].growth_ms = int(w.nature.definitions.sect_grain.mature_ms)
			w.objects.add(crop, "grain", 3, Stock.right(0, f.org))
		w.knowledge.seed(w, 3, w.operation_target(bed), 0)
		w.knowledge.seed(w, 3, w.operation_target(crop), 0)
	w.flush_topology()
	# Known dry fields and empty well: even four planning units can discover
	# the water-independent harvest, including on the thirsty mature crop.
	var planner: RefCounted = w.livelihood.Planner.new()
	var view: Dictionary = w.livelihood._self_view(w, 3)
	var known: Dictionary = w.knowledge.known(3, 0)
	planner.configure(view, w.operation_target(3), known, {}, w.combat.position(w, 3), 0, {"work": 0, "cursor": 0}, {})
	var candidates: Array = planner.candidates({"params": {"appointment": appointment}}, {"pattern": "duty"}, 4)
	check(not candidates.is_empty() and candidates[0].step.input.kind == "gather", "Repeated water shortages consumed the whole field allowance before harvest")
	# A physically stocked but previously unreachable source is equally unable
	# to satisfy this round's shared prerequisite; do not retry it per bed.
	planner.blocked["draw_water:%d" % f.well] = true
	planner.known[f.well].inventory = {"water": 5}
	planner.budget.work = 0
	candidates = planner.candidates({"params": {"appointment": appointment}}, {"pattern": "duty"}, 4)
	check(not candidates.is_empty() and candidates[0].step.input.kind == "gather", "A rejected water source starved water-independent field work")
	w.decisions.prepare(w, 0)
	advance(w, 12000)
	check(w.objects.amount(f.destination, "grain") == 3 and w.nature.collections == 3, "A thirsty mature field could not actually harvest and deposit without water")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Many dry fields with actual harvest did not restore")
	var source_view: Dictionary = w.operation_target(f.source)
	var split: Dictionary = {"id": 3, "scope_grants": [{"organization": f.org, "targets": [int(f.source)], "purposes": ["take"], "items": ["grain"], "all_items": false}]}
	check(w.institutions.Duties.source_quantity(split, source_view, "grain", f.org) > 0 and w.institutions.Duties.source_quantity(split, source_view, "grain", f.org, "cook") == 0, "Source estimate ignored the separate issue purpose")
	split.scope_grants[0].purposes.append("cook")
	check(w.institutions.Duties.source_quantity(split, source_view, "grain", f.org, "cook") > 0, "Matching issue authority failed source preflight")
	var well_view: Dictionary = w.operation_target(f.well)
	split.scope_grants[0] = {"organization": f.org, "targets": [int(f.well)], "purposes": ["supply"], "items": ["water"], "all_items": false}
	check(Stock.access_reason(split, well_view, "collect_source", {"item": "water", "purpose": "cultivate"}) == "not_authorized", "Source collection query ignored the separate issue purpose")
	split.scope_grants[0].purposes.append("cultivate")
	check(Stock.access_reason(split, well_view, "collect_source", {"item": "water", "purpose": "cultivate"}).is_empty(), "Combined source and use authority was rejected")
	planner.actor = {"bundles": [{"organization": 0, "purpose": "", "items": {"grain": 2}}]}
	planner.known = {1: {"id": 1, "tile": 10, "inventory": {}}}
	check(not planner.Institutions.source_shortfall(planner, {"grain": 2}, 0, "cook", [1]), "Private held ingredients vanished from restricted source preflight")

func fresh_idle_and_private_occupant() -> void:
	var f: Dictionary = field_fixture()
	var w: RefCounted = f.world
	var crops: Array = []
	for bed: int in f.beds:
		crops.append(w.nature.create(w, "sect_grain", w.objects.records[bed].tile))
		w.knowledge.refresh(w, 3, bed, 0)
	for target: int in [int(f.source), int(f.well), int(f.destination)]: w.knowledge.refresh(w, 3, target, 0)
	var planner: RefCounted = w.livelihood.Planner.new()
	var view: Dictionary = w.livelihood._self_view(w, 3)
	var clues: Dictionary = w.knowledge.known(3, 0)
	planner.configure(view, w.operation_target(3), clues, {}, w.combat.position(w, 3), 0, {"work": 0, "cursor": 0}, {})
	check(planner.candidates({"params": {"appointment": f.appointment}}, {"pattern": "duty"}, 16).is_empty(), "Fresh healthy fields demanded continuous inspection")
	var duty: Dictionary = view.duties[f.appointment]
	check(not planner.Institutions.review_due(view, duty, 0, clues), "An idle field falsely competed with shared teaching")
	w.objects.records[f.beds[0]].water = 35
	w.objects.add(f.well, "water", 1)
	w.knowledge.refresh(w, 3, int(f.well), 0)
	w.knowledge.refresh(w, 3, int(f.beds[0]), 0)
	check(planner.Institutions.review_due(view, duty, 0, w.knowledge.known(3, 0)), "Fresh known urgent field work vanished from social consent")
	# A public host does not turn another person's crop into shared property.
	w.objects.records[crops[0]].owner = 1; w.objects.records[crops[0]].organization = 0
	w.knowledge.refresh(w, 3, int(f.beds[0]), 0)
	clues = w.knowledge.known(3, 0)
	planner.configure(view, w.operation_target(3), clues, {}, w.combat.position(w, 3), 0, {"work": 0, "cursor": 0}, {})
	check(planner.candidates({"params": {"appointment": f.appointment}}, {"pattern": "duty"}, 4).is_empty(), "Private crop consumed public field planning work")
	check(not planner.Institutions.Cultivation.retained(duty, view, clues).has("%d:cultivate:water" % f.org), "Private crop retained public watering supplies")
	check(w.institutions.Duties.source_quantity(view, clues[int(f.source)], "grain", f.org, "cultivate") > 0, "Field fixture lost its real seed")
	clues[int(f.beds[1])].occupant = 0
	clues[int(f.source)].inventory.clear(); clues[int(f.source)].contents.clear()
	check(not planner.Institutions.review_due(view, duty, 0, clues), "Known empty seed sources falsely competed as actionable field work")

func interrupted_delivery_keeps_service_capacity() -> void:
	var f: Dictionary = field_fixture()
	var w: RefCounted = f.world
	w.institutions.admit(w, f.org, 3, ["eat"])
	var meals: int = workshop(w, f.org, "wood_chest", Vector2i(123, 122))
	check(w.institutions.arrange_service(w, meals, "eat", [], true), "Could not establish a real food service")
	w.knowledge.seed(w, 3, w.operation_target(meals), 0)
	var crop: int = w.nature.create(w, "sect_grain", w.objects.records[f.beds[0]].tile)
	w.objects.records[crop].stage = w.nature.Stage.MATURE
	w.objects.records[crop].growth_ms = int(w.nature.definitions.sect_grain.mature_ms)
	w.objects.add(crop, "grain", 5, Stock.right(0, f.org))
	w.knowledge.refresh(w, 3, int(f.beds[0]), 0)
	w.decisions.prepare(w, 0)
	while w.elapsed_ms < 10000 and w.nature.collections == 0: advance(w, w.elapsed_ms + 50)
	check(w.nature.collections == 5 and w.objects.amount(3, "grain") == 5, "Could not intercept an actual harvest in transit")
	w.objects.records[f.destination].capacity = 1
	w.objects.add(f.destination, "wood", 1, Stock.right(0, f.org))
	w.knowledge.refresh(w, 3, int(f.destination), w.elapsed_ms)
	w.objects.records[f.source].capacity = w.objects.count_inventory(f.source)
	w.knowledge.refresh(w, 3, int(f.source), w.elapsed_ms)
	# Remove the actual source while its public output is already carried.
	# History remains useful until deposit; it is not another live crop.
	w.objects.records[crop].hp = 0
	w.nature.evaluate(w, crop, w.elapsed_ms)
	w.knowledge.refresh(w, 3, crop, w.elapsed_ms)
	advance(w, w.elapsed_ms + 10000)
	check(not w.objects.records.has(crop) and w.objects.amount(3, "grain") == 5 and w.objects.amount(meals, "grain") == 0, "A replaced crop lost held harvest or polluted the meal store")
	check(w.livelihood.protected_targets(w, 3).has(crop) and Persistence.candidate(Persistence.capture(w), 0) != null, "Historical harvest origin was unprotected or unrestorable")
	check(w.institutions.revoke(w, f.appointment), "Could not revoke an actual returning harvester")
	# Also fill its source store: only the meal service remains physically free.
	var source_before: int = w.objects.amount(f.source, "grain")
	w.objects.records[f.source].capacity = w.objects.count_inventory(f.source)
	w.knowledge.refresh(w, 3, int(f.source), w.elapsed_ms)
	advance(w, w.elapsed_ms + 15000)
	check(w.objects.amount(meals, "grain") == 0 and w.objects.amount(3, "grain") == 5, "General returns filled the food service with raw harvest")
	w.objects.records[f.source].capacity += 5
	advance(w, w.elapsed_ms + 20000)
	check(w.objects.amount(3, "grain") == 0 and w.objects.amount(f.source, "grain") == source_before + 5, "Held public harvest did not return when material storage became available")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Temporarily held public harvest corrupted history")

func dead_crop_and_prepaid_sowing() -> void:
	var f: Dictionary = field_fixture()
	var w: RefCounted = f.world
	var dead: int = w.nature.create(w, "sect_grain", w.objects.records[f.beds[0]].tile)
	w.objects.records[dead].hp = 0
	var seeding: int = w.nature.create(w, "sect_grain", w.objects.records[f.beds[1]].tile, true)
	check(w.objects.transfer(f.source, seeding, "grain", 1, Stock.right(0, f.org)) == 1, "Prepaid seed did not enter its actual carrier")
	w.nature.evaluate(w, dead, 0)
	for bed: int in f.beds: w.knowledge.refresh(w, 3, bed, 0)
	var grain: int = w.objects.audit_total("grain")
	check(w.institutions.appoint(w, f.org, 4, "field_cultivator", f.beds + [int(f.source), int(f.well), int(f.destination)], f.scope) > 0, "A shared field appointment was refused")
	w.decisions.prepare(w, 0)
	advance(w, 25000)
	check(not w.objects.records.has(dead) and w.objects.records[f.beds[0]].guest > 0 and w.objects.records[seeding].stage == w.nature.Stage.SPROUT, "Farmers did not remove a dead crop and resume prepaid sowing")
	check(w.objects.audit_total("grain") == grain - 2 and w.nature.generated_items.get("grain", 0) == 0, "Dead clearing/shared planting fabricated or double-consumed seed/body output")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Dead crop/shared continuation did not restore")

func _run() -> void:
	check(Roles.ERRORS.is_empty() and Operations.ERRORS.is_empty(), "Invalid cultivation authoring: " + str(Roles.ERRORS))
	field_rights_and_work()
	observed_harvest_and_revoke()
	variant_and_empty_source()
	blocked_bed_does_not_starve_other_sites()
	dry_mature_fields_under_small_allowance()
	fresh_idle_and_private_occupant()
	interrupted_delivery_keeps_service_capacity()
	dead_crop_and_prepaid_sowing()
	print("CULTIVATION_DUTIES_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
