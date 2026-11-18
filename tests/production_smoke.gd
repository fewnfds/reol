extends "res://tests/custody_smoke.gd"
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const Production = preload("res://scripts/sim/kernel/production.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")

func at_stove(w: RefCounted, actor: int, stove: int) -> void:
	var cell: Vector2i = w.Terrain.cell(w.objects.records[stove].tile)
	for other: int in w.actor_slots:
		if other != actor and not w.actions.has(other) and w.combat.position(w, other).distance_to(Vector2(cell) + Vector2(0.5, 1.5)) < 1.0:
			var previous: int = w.actor_slots[other]
			w.pages[previous / 256].positions[previous % 256] = Vector2(cell) + Vector2(-1.5, 1.5)
	var slot: int = w.actor_slots[actor]
	w.pages[slot / 256].positions[slot % 256] = Vector2(cell) + Vector2(0.5, 1.5)

func start(w: RefCounted, actor: int, operation: String, stove: int) -> bool:
	at_stove(w, actor, stove)
	if not w.objects.records[stove].has("process"):
		for item: String in Operations.OPERATIONS[operation].recipe.inputs:
			var deficit: int = maxi(0, int(Operations.OPERATIONS[operation].recipe.inputs[item]) - w.objects.available_amount(stove, item))
			if deficit > 0: w.institutions.move_goods(w, actor, stove, item, deficit, "put", {}, w.elapsed_ms)
	var reason: String = w.begin_interaction(actor, {"kind": operation, "target": stove})
	check(reason == "accepted", "Production admission refused: " + reason)
	if reason != "accepted": return false
	w.settle_action(actor, w.elapsed_ms)
	check(w.actions.has(actor) and w.actions[actor].has("started_ms"), "Production did not actually start")
	return w.actions.has(actor)

func handoff_and_identity() -> void:
	var w: RefCounted = peaceful()
	var stove: int = facility(w, "cook_stove", 124, 124, 0)
	Growth.seed(w.objects.records[1], "cooking", 0)
	clear_private(w, 3, "grain")
	clear_private(w, 3, "water")
	var grain: int = w.objects.audit_total("grain")
	var water: int = w.objects.audit_total("water")
	if not start(w, 1, "cook", stove): return
	var stale: Dictionary = Operations.domain_action(w.actions[1]).duplicate(true)
	check(w.actions[1].base_work_ms == 4000 and w.actions[1].scheduled_ms == 3000, "Mastery did not schedule standard labor separately")
	check(w.objects.amount(stove, "grain") == 2 and w.objects.available_amount(stove, "grain") == 0 and w.objects.audit_total("grain") == grain and w.objects.total("water") == water, "Physical workshop ingredients were consumed or remained externally available")
	advance(w, 1500)
	w.end_run(1, w.elapsed_ms, "preempted")
	check(w.objects.records[stove].process.remaining_ms == 2000 and latest(w, 1).facts.worked_ms == 2000, "Half master time was not half standard work")
	var process_id: int = w.objects.records[stove].process.id
	if not start(w, 3, "cook", stove): return
	check(w.actions[3].scheduled_ms == 2000 and w.objects.records[stove].process.id == process_id, "Empty-handed beginner repeated input or old master rate")
	advance(w, 1900)
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "In-flight resumed production did not restore")
	advance(w, 3700)
	if restored != null:
		advance(restored, 3700)
		check(restored.objects.records[stove] == w.objects.records[stove] and restored.activity_results.records == w.activity_results.records, "Restore changed production output or receipts")
	check(not w.objects.records[stove].has("process") and w.objects.amount(stove, "meal", Stock.right(1)) == 3 and w.objects.audit_total("grain") == grain - 2, "Handoff changed title or failed physical conversion")
	check(w.objects.records[3].methods.cooking.progress == 62 and latest(w, 3).facts.labor == [{"actor": 3, "worked_ms": 2000}, {"actor": 1, "worked_ms": 2000}], "Actual contribution did not determine learning/evidence")
	check(Production.commit(w, 1, stale, w.elapsed_ms).reason == "process_changed" and w.objects.amount(stove, "meal") == 3, "Old run duplicated an already completed batch")
	# The single physical work position must refuse a second concurrent artisan.
	if not start(w, 1, "cook", stove): return
	var slot: int = w.actor_slots[3]
	w.pages[slot / 256].positions[slot % 256] = Vector2(123.5, 126.5)
	check(w.begin_interaction(3, {"kind": "cook", "target": stove}) == "target_busy", "Occupied workshop admitted a second artisan")
	advance(w, w.elapsed_ms + 3400)
	check(not w.actions.has(3) and w.objects.amount(stove, "meal") == 6, "Denied artisan opened a phantom batch")

func passive_and_capacity() -> void:
	var w: RefCounted = peaceful()
	var stove: int = facility(w, "cook_stove", 124, 124, 0)
	Growth.seed(w.objects.records[1], "herbalism", 0, false)
	Growth.seed(w.objects.records[3], "herbalism", 0, false)
	w.objects.add(1, "herb", 2)
	w.institutions.move_goods(w, 1, stove, "herb", 2, "put", {}, 0)
	w.institutions.move_goods(w, 1, stove, "water", 1, "put", {}, 0)
	w.pages[0].energy[0] = 99
	var stock: Dictionary = w.objects.records[1].stock.duplicate(true)
	check(w.begin_interaction(1, {"kind": "brew", "target": stove}) == "insufficient_resource" and not w.objects.records[stove].has("process") and w.objects.records[1].stock == stock, "Unpayable production changed input or WIP")
	w.pages[0].energy[0] = 1000
	w.objects.records[stove].capacity = 0
	check(w.begin_interaction(1, {"kind": "brew", "target": stove}) == "no_output_capacity" and w.pages[0].energy[0] == 1000, "Full output paid start cost")
	w.objects.records[stove].capacity = -1
	if not start(w, 1, "brew", stove): return
	advance(w, 1600)
	var record: Dictionary = w.objects.records[stove]
	check(record.process.stage == "passive" and record.process.ready_ms == 5500 and not w.reservations.has(stove) and not w.actions.has(1), "Passive phase held a worker/slot or used another clock")
	check(w.begin_interaction(3, {"kind": "brew", "target": stove}) == "unattended_in_progress", "Unfinished passive batch was collected early")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Passive production did not restore")
	w.kill(1, w.elapsed_ms)
	check(record.process.stage == "passive" and w.objects.amount(stove, "herb") == 2, "Worker death erased physical batch")
	advance(w, 5500)
	if not start(w, 3, "brew", stove): return
	advance(w, 6100)
	check(w.objects.amount(stove, "potion", Stock.right(1)) == 1 and not record.has("process") and w.objects.records[3].methods.herbalism.progress == 25, "Finisher repeated costs, ownership or prepper learning")
	check(w.objects.records[1].methods.herbalism.progress == 0, "Final collection granted new practice to a dead prepper")
	if restored != null:
		advance(restored, 5500)
		start(restored, 3, "brew", stove)
		advance(restored, 6100)
		check(restored.objects.records[stove] == record, "Passive restoration changed the real batch")

func blocked_output_and_salvage() -> void:
	var w: RefCounted = peaceful()
	var stove: int = facility(w, "cook_stove", 124, 124, 0)
	if not start(w, 1, "cook", stove): return
	w.objects.records[stove].capacity = 3
	w.objects.add(stove, "wood", 1)
	advance(w, 4100)
	check(latest(w, 1).reason == "no_output_capacity" and w.objects.records[stove].process.remaining_ms == 1 and w.objects.amount(stove, "grain") == 2, "Blocked output lost finished labor or its physical input: " + str(latest(w, 1)))
	w.objects.add(stove, "wood", -1)
	if not start(w, 3, "cook", stove): return
	advance(w, w.elapsed_ms + 32)
	check(w.objects.amount(stove, "meal") == 3 and not w.objects.records[stove].has("process"), "Freed output could not complete original batch")
	w.objects.records[stove].capacity = 6
	w.institutions.move_goods(w, 1, stove, "meal", 3, "take", {}, w.elapsed_ms)
	if not start(w, 1, "cook", stove): return
	advance(w, w.elapsed_ms + 300)
	var grain: int = w.objects.total("grain")
	var wood: int = w.objects.total("wood")
	var result: Dictionary = w.facilities.demolish_result(w, stove, w.elapsed_ms)
	check(result.status == "completed" and w.objects.total("grain") == grain and w.objects.total("wood") == wood and w.objects.audit_total("grain") == grain, "Dismantling lost WIP or body materials")
	check(w.objects.amount(result.facts.salvage_pile, "grain", Stock.right(1)) == 2 and Persistence.candidate(Persistence.capture(w), 0) != null, "Salvage changed WIP attribution or left a phantom run")

func finite_source() -> void:
	var w: RefCounted = peaceful()
	var source: int = facility(w, "water_well", 124, 124, 0)
	var record: Dictionary = w.objects.records[source]
	clear_private(w, 1, "water")
	w.pages[0].positions[0] = Vector2(123.5, 124.5)
	check(w.begin_interaction(1, {"kind": "draw_water", "target": source}) == "empty", "Empty natural source fabricated available water")
	var total: int = w.objects.total("water")
	advance(w, 15000)
	check(record.source_generated == 1 and w.objects.amount(source, "water") == 1 and w.objects.total("water") == total + 2, "Bounded natural source did not replenish actual stock") # Two wells: original world + this fixture.
	check(w.begin_interaction(1, {"kind": "draw_water", "target": source}) == "accepted", "Real replenished water could not be collected")
	advance(w, 16200)
	check(w.objects.amount(source, "water") == 0 and latest(w, 1).facts.amount == 1, "Water source pickup duplicated its requested maximum")
	var stove: int = facility(w, "cook_stove", 128, 124, 0)
	if not start(w, 1, "cook", stove): return
	advance(w, 20400)
	check(w.objects.amount(1, "water") == 0 and w.objects.amount(stove, "meal") == 3, "Replenished water was not the real input to a shared recipe")
	check(w.begin_interaction(1, {"kind": "eat", "target": stove}) == "accepted", "Actual replenished-water meal could not be consumed")
	advance(w, 21600)
	check(w.objects.amount(stove, "meal") == 2 and latest(w, 1).facts.consumed == {"meal": 1}, "Source-to-production-to-consumption did not close physically")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Source due time/generated counters did not restore")
	if restored == null: return
	advance(w, 30000)
	advance(restored, 30000)
	check(w.objects.records[source] == restored.objects.records[source], "Restored source replenished at another time")
	w.objects.add(source, "water", 23)
	advance(w, 60000)
	check(w.objects.amount(source, "water") == 24 and record.source_generated == 2, "Full source accumulated future inventory")
	w.objects.add(source, "water", -24)
	advance(w, 75000)
	check(w.objects.amount(source, "water") == 1 and record.source_generated == 3, "Depleted source released stored-up future water")

func invalid_process_and_recipe() -> void:
	var w: RefCounted = peaceful()
	var stove: int = facility(w, "cook_stove", 124, 124, 0)
	if not start(w, 1, "cook", stove): return
	advance(w, 300)
	var state: Dictionary = Persistence.capture(w)
	for field: String in ["id", "stage", "remaining_ms", "ready_ms", "contributions"]:
		var bad: Dictionary = state.duplicate(true)
		bad.domains.objects.records[stove].process[field] = {"id": 0, "stage": "no", "remaining_ms": 0, "ready_ms": 1, "contributions": {1: 2}}[field]
		check(Persistence.candidate(bad, 0) == null, "Bad process restored: " + field)
	var bad: Dictionary = state.duplicate(true)
	bad.domains.objects.records[stove].process.locked_inputs.grain += 1
	check(Persistence.candidate(bad, 0) == null, "Malformed input lock bypassed recipe/account validation")
	bad = state.duplicate(true)
	bad.domains.world.actions[1].process_id += 1
	check(Persistence.candidate(bad, 0) == null, "Mismatched process run restored")
	for field: String in ["started_ms", "participants", "expected_process"]:
		bad = state.duplicate(true)
		bad.domains.world.actions[1][field] = {"started_ms": "bad", "participants": [], "expected_process": 0}[field]
		check(Persistence.candidate(bad, 0) == null, "Malformed production action was not safely rejected: " + field)
	bad = state.duplicate(true)
	bad.domains.objects.records[stove].erase("process")

	bad.domains.world.actions[1].process_id = 0
	bad.domains.world.actions[1].process_stage = ""
	check(Persistence.candidate(bad, 0) == null, "Empty process dereferenced a nonexistent carrier")
	bad = state.duplicate(true)
	bad.domains.objects.records[stove].process.remaining_ms = 3999
	bad.domains.objects.records[stove].process.contributions = {1: 9223372036854775807, 2: 9223372036854775807, 3: 3}
	check(Persistence.candidate(bad, 0) == null, "Overflowed contributions wrapped to legal total")
	bad = state.duplicate(true)
	bad.domains.objects.records[stove].process.remaining_ms = 3999
	bad.domains.objects.records[stove].process.contributions = {stove: 1}
	check(Persistence.candidate(bad, 0) == null, "Nonworker object gained production contribution")
	var variant: Resource = load("res://data/definitions/operations/cook.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	variant.recipe.id = "double_rations"
	variant.recipe.inputs.assign({"grain": 4, "water": 2})
	variant.recipe.outputs.assign({"meal": 6})
	variant.recipe.work_ms = 1000
	check(variant.errors().is_empty(), "Same-mechanism recipe required new code")
	w.end_run(1, w.elapsed_ms, "preempted")
	var other: int = facility(w, "cook_stove", 128, 124, 0)
	w.facilities.definitions.cook_stove.capabilities.workbench.recipes.append("double_rations")
	var original: Dictionary = Operations.OPERATIONS
	var values: Dictionary = original.duplicate(true)
	values.cook = variant.values()
	Operations.OPERATIONS = Operations.freeze(values)
	start(w, 1, "cook", other)
	advance(w, w.elapsed_ms + 1100)
	check(w.objects.amount(other, "meal") == 6 and not w.objects.records[other].has("process"), "Defined recipe variant did not execute through original World")
	Operations.OPERATIONS = original
	variant.recipe.inputs["grain"] = 0
	check(not variant.errors().is_empty(), "Invalid recipe accepted zero inputs")

func source_boundary_and_bad_state() -> void:
	var w: RefCounted = peaceful()
	advance(w, 1020)
	var source: int = facility(w, "water_well", 124, 124, 0)
	check(w.objects.records[source].source_due_ms == 17000 and Persistence.candidate(Persistence.capture(w), 0) != null, "Non-second source installation did not use its pulse contract")
	advance(w, 16032)
	check(w.objects.amount(source, "water") == 0 and Persistence.candidate(Persistence.capture(w), 0) != null, "Legal source save between nominal due and pulse was refused")
	advance(w, 17000)
	check(w.objects.amount(source, "water") == 1, "Rounded source missed its next real pulse")
	var state: Dictionary = Persistence.capture(w)
	for value: Variant in ["bad", -1, 17000, 17001, 999999999]:
		var bad: Dictionary = state.duplicate(true)
		bad.domains.objects.records[source].source_due_ms = value
		check(Persistence.candidate(bad, 0) == null, "Malformed source due was accepted: " + str(value))
	var bad: Dictionary = state.duplicate(true)
	bad.domains.objects.records[source].source_generated = -1
	check(Persistence.candidate(bad, 0) == null, "Negative natural production restored")
	bad = state.duplicate(true)
	bad.domains.objects.records[source].stock.water[0].owner = 1
	check(Persistence.candidate(bad, 0) == null, "Source restored foreign stock attribution")

func contribution_bound() -> void:
	var process: Dictionary = {"contributions": {}}
	for actor: int in range(1, 131): Production._contribute(process, actor, 1)
	var total: int = 0
	for amount: int in process.contributions.values(): total += amount
	check(process.contributions.size() == 128 and total == 130 and process.contributions[129] == 1 and process.contributions[130] == 1 and process.contributions[0] == 3, "Contribution compression lost work or unpredictably anonymized recent workers")

func pause_cancel_and_locks() -> void:
	var w: RefCounted = peaceful()
	var stove: int = facility(w, "cook_stove", 124, 124, 0)
	if not start(w, 1, "cook", stove): return
	advance(w, 1000)
	var process: Dictionary = w.objects.records[stove].process
	var grain: int = w.objects.audit_total("grain")
	check(not w.objects.consume(stove, {"grain": 1}, Stock.right(1)), "Eat/consume bypassed ingredient lock")
	check(w.objects.transfer(stove, 3, "grain", 2) == 0, "Transfer stole locked ingredients")
	check(Production.control(w, stove, process.id, "pause", w.elapsed_ms) == "management_updated", "Pause refused")
	var remaining: int = process.remaining_ms
	advance(w, 3000)
	check(process.remaining_ms == remaining and w.objects.audit_total("grain") == grain and Persistence.candidate(Persistence.capture(w), 0) != null, "Paused work advanced, consumed or failed restore")
	check(Production.control(w, stove, process.id, "resume", w.elapsed_ms) == "management_updated", "Resume refused")
	check(Production.control(w, stove, process.id, "cancel", w.elapsed_ms) == "management_updated", "Cancel refused")
	check(not w.objects.records[stove].has("process") and w.objects.available_amount(stove, "grain") == 2 and w.objects.audit_total("grain") == grain and w.objects.amount(stove, "meal") == 0, "Cancel fabricated a refund, kept work or made output")
	check(Production.control(w, stove, process.id, "cancel", w.elapsed_ms) == "process_changed", "Old process control affected a later identity")

func _run() -> void:
	pause_cancel_and_locks()
	handoff_and_identity()
	passive_and_capacity()
	blocked_output_and_salvage()
	finite_source()
	invalid_process_and_recipe()
	source_boundary_and_bad_state()
	contribution_bound()
	print("PRODUCTION_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
