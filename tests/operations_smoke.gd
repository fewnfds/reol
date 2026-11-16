extends "res://tests/abilities_smoke.gd"
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Query = preload("res://scripts/sim/kernel/operation_query.gd")
const UI = preload("res://scripts/presentation/ui/actions.gd")
const Operation = preload("res://scripts/sim/definitions/operations/operation_def.gd")

func shared_rules() -> void:
	var w: RefCounted = fixture()
	var stove: int = w.facilities.create_completed(w, "cook_stove", w.Terrain.index(Vector2i(124, 124)))
	w.flush_topology()
	w.objects.add(1, "grain", -w.objects.amount(1, "grain"))
	var target: Dictionary = w.operation_target(stove)
	var options: Array[Dictionary] = UI.for_target(target, w.describe(1), 0)
	var cook: Dictionary = {}
	for option: Dictionary in options:
		if option.id == "cook": cook = option
	check(not cook.is_empty() and not cook.enabled and w.begin_interaction(1, {"kind": "cook", "target": stove}) == "missing_items", "UI and owner disagreed on common ingredients")
	w.objects.add(1, "grain", 2)
	w.pages[0].positions[0] = Vector2(124.5, 125.5)
	check(Query.evaluate(Operations.OPERATIONS.cook, w.operation_actor(1), target).ready, "Shared query did not observe real ingredients")
	check(w.begin_interaction(1, {"kind": "cook", "target": stove}) == "accepted", "Cooking admission failed")
	var original: Dictionary = w.gate.current(1)
	check(w.begin_interaction(1, {"kind": "unknown_operation", "target": stove}) == "unknown_operation" and w.begin_transfer(1, {"kind": "unknown_operation", "target": stove}) == "unknown_operation" and w.gate.current(1) == original, "Unknown request polluted a current host")
	var pile: int = w.objects.create("pile", "wood", w.Terrain.index(Vector2i(126, 125)))
	w.objects.transfer(w.source_objects[0], pile, "wood", 1)
	check(w.begin_interaction(1, {"kind": "demolish", "target": pile}) == "invalid_target" and w.gate.current(1) == original, "Invalid target cancelled existing labor")
	advance(w, 4500)
	check(w.objects.amount(stove, "meal") == 3 and w.objects.amount(1, "grain") == 0, "Shared definition did not reach real cooking output")
	var actual: Array = w.activity_results.view(1)
	check(not actual.is_empty() and actual.back().facts.consumed == {"grain": 2, "water": 1} and actual.back().facts.produced == {"meal": 3}, "Cooking result invented inputs or omitted real outputs")
	var remembered: Dictionary = w.operation_target(stove)
	w.objects.add(stove, "meal", -3)
	check(Query.evaluate(Operations.OPERATIONS.eat, w.operation_actor(1), remembered).ready and w.begin_interaction(1, {"kind": "eat", "target": stove}) == "no_food", "Query consulted hidden inventory or owner trusted stale evidence")
	remembered.erase("inventory")
	var unknown: Dictionary = Query.evaluate(Operations.OPERATIONS.eat, w.operation_actor(1), remembered)
	check(not unknown.ready and unknown.unknown.has("inventory"), "Missing observation became a false known amount")
	remembered["memory"] = true
	check(UI.for_target(remembered, w.describe(1), 0).is_empty(), "Hidden memory exposed live buttons")
	w.set_capability_overrides(1, {"work": false})
	w.objects.add(1, "grain", 2)
	check(not Query.evaluate(Operations.OPERATIONS.cook, w.operation_actor(1), target).ready and w.begin_interaction(1, {"kind": "cook", "target": stove}) == "body_has_no_work_capability", "UI/query execution ignored current capability")
	var state: Dictionary = Persistence.capture(w)
	state.operation_signature = "other rules"
	check(Persistence.candidate(state, 0) == null, "Restore accepted different operation rules")

func instant_effects() -> void:
	var w: RefCounted = fixture()
	var page: RefCounted = w.pages[0]
	var person: Dictionary = w.objects.records[1]
	page.health[0] -= 50
	person["qi"] = 50
	check(w.command({"kind": "ability"}).reason == "ability_not_mastered", "Unknown healing ability was available")
	person["abilities"] = {"wood_mend": true}
	page.energy[0] = 499
	check(not w.command({"kind": "ability"}).ok and person.qi == 50 and page.energy[0] == 499, "Failed ability partially paid")
	page.energy[0] = 1000
	check(w.command({"kind": "ability"}).reason == "ability_used" and person.qi == 30 and page.energy[0] == 500 and page.health[0] == page.max_health[0] - 25, "Instant operation did not pay and heal through P4")
	var healed: bool = false
	for event: Dictionary in w.outcomes:
		if event.kind == "healed" and event.get("amount", 0) == 25 and event.actor == 1 and event.target == 1: healed = true
	check(healed, "Shared healing omitted actual attributed outcome")
	var before: Dictionary = {"hp": page.health[0], "qi": person.qi, "energy": page.energy[0]}
	w.combat.status[1] = {"stun_until": 1000}
	check(w.command({"kind": "ability"}).reason == "stunned" and page.health[0] == before.hp and person.qi == before.qi and not UI.self_ready(w.describe(1), "wood_mend"), "Stunned instant operation bypassed admission")
	w.combat.status.erase(1)
	w.combat.request(w, 1, "primary", Vector2.RIGHT)
	check(w.command({"kind": "ability"}).reason == "action_committed" and person.qi == before.qi, "Instant operation bypassed combat commitment")
	w.release(1)
	person.qi = 50
	page.energy[0] = 1000
	var chest: int = w.depot_objects[0]
	w.objects.transfer(w.source_objects[0], chest, "wood", 2)
	check(w.begin_transfer(1, {"kind": "take", "target": chest, "item": "wood", "amount": 1}) == "accepted", "Noncombat host fixture failed")
	var run: Dictionary = w.gate.current(1)
	check(w.execute_operation(1, {"kind": "wood_mend", "target": 1}) == "completed" and w.gate.current(1) == run, "Synchronous self effect replaced unrelated noncombat labor")
	check(w.execute_operation(1, {"kind": "wood_mend", "target": 2}) == "invalid_target", "Self operation healed someone else")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Instant operation broke running-host restore")

func definitions() -> void:
	check(Operations.ERRORS.is_empty() and Operations.OPERATIONS.cook.targets.is_read_only(), "Operation catalog was invalid or shallow-frozen")
	var library: Resource = Operations.LIBRARY.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	library.operations.append(library.operations[0])
	check(not library.compile().errors.is_empty(), "Duplicate operation ID was overwritten")
	var alias: Resource = load("res://data/definitions/operations/cook.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	alias.command_alias = "demolish"
	check(not alias.errors().is_empty(), "Arbitrary UI alias bypassed the operation contract")
	var values: Dictionary = Operations.OPERATIONS.duplicate(true)
	values.cook.title = "做饭"
	values.cook.icon = "book"
	check(Operations.signature(values) == Operations.SIGNATURE, "Cosmetics invalidated world rules")
	values.cook.duration_ms += 1
	check(Operations.signature(values) != Operations.SIGNATURE, "Changed operation timing was unsigned")
	var variant: Resource = load("res://data/definitions/operations/wood_mend.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	variant.id = "lesser_mend"
	variant.title = "小回春"
	variant.costs[0].amount = 5
	variant.effects.effects[0].amount = 3
	check(variant.errors().is_empty(), "Same-mechanism variant required a new handler")
	# Load-time table replacement is explicit and restored, never a mutable live catalog.
	var original: Dictionary = Operations.OPERATIONS
	var expanded: Dictionary = original.duplicate(true)
	expanded[variant.id] = variant.values()
	var transfer: Resource = load("res://data/definitions/operations/take.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	transfer.id = "take_grain"
	transfer.title = "取粮"
	transfer.targets[0].kinds = PackedStringArray(["workbench"])
	transfer.targets[0].target_item = "grain"
	check(transfer.errors().is_empty(), "Same-mechanism transfer variant rejected")
	expanded[transfer.id] = transfer.values()
	Operations.OPERATIONS = Operations.freeze(expanded)
	var w: RefCounted = fixture()
	w.objects.records[1]["abilities"] = {"wood_mend": true}
	w.objects.records[1]["qi"] = 5
	w.pages[0].health[0] -= 10
	var hp: int = w.pages[0].health[0]
	check(w.command({"kind": "lesser_mend", "target": 1}).ok and w.objects.records[1].qi == 0 and w.pages[0].health[0] == hp + 3, "New defined self effect did not execute without World changes")
	var stove: int = w.facilities.create_completed(w, "cook_stove", w.Terrain.index(Vector2i(124, 124)))
	w.objects.add(stove, "grain", 2)
	w.pages[0].positions[0] = Vector2(124.5, 125.5)
	var menu: bool = false
	for option: Dictionary in UI.for_target(w.operation_target(stove), w.describe(1), 0):
		if option.id == transfer.id and option.enabled: menu = true
	var before: int = w.objects.amount(1, "grain")
	check(menu and w.command({"kind": transfer.id, "target": stove, "item": "grain", "amount": 2}).ok, "Declared transfer menu did not reach its host")
	advance(w, 2000)
	check(w.objects.amount(stove, "grain") == 0 and w.objects.amount(1, "grain") == before + 2, "Transfer variant used hardcoded stock kinds/items")
	Operations.OPERATIONS = original

func arrival_and_restore() -> void:
	var w: RefCounted = fixture()
	var source: int = w.source_objects[0]
	check(w.begin_transfer(1, {"kind": "take", "target": source, "item": "wood", "amount": 1}) == "accepted", "Transfer restore fixture failed")
	var data: Dictionary = Persistence.capture(w)
	for invalid: String in ["harvest", "wood_mend", "no_such_operation"]:
		var corrupted: Dictionary = data.duplicate(true)
		corrupted.domains.world.actions[1].kind = invalid
		check(Persistence.candidate(corrupted, 0) == null, "Invalid operation host bypassed pre-Gate restore validation")
	data.domains.world.actions[1].target = 2
	var loaded: RefCounted = Persistence.candidate(data, 0)
	check(loaded != null, "Current in-flight target is not a restore-time availability test")
	if loaded != null:
		loaded.objects.add(2, "wood", 1)
		loaded.settle_action(1, loaded.elapsed_ms)
		check(loaded.objects.amount(2, "wood") == 1 and not loaded.actions.has(1), "Arrival bypassed declared transfer targets")
	w.release(1)
	w.decisions.resume(w, 2, 0)
	check(w.begin_interaction(1, {"kind": "talk", "target": 2}) == "accepted" and w.society.waits.has(2), "Partner restore fixture failed")
	data = Persistence.capture(w)
	data.domains.world.actions[1].partner_waiting = false
	check(Persistence.candidate(data, 0) == null, "One-sided partner host restored into a permanent occupation")
	var first_wait: Dictionary = w.society.waits[2].duplicate()
	var other: Dictionary = {"kind": "talk", "target": 2, "run_id": 999}
	w.society.invite(w, 3, other)
	check(w.society.waits[2] == first_wait and w.actions.has(1), "Invitation stole another activity's partner")
	w.objects.records[2].autonomous = true
	w.actions[1].partner_resume = true
	w.end_run(2, 0, "interrupted")
	check(not w.actions.has(1) and w.society.waits.is_empty() and w.decisions.wakeups.has(2), "Direct partner interruption stranded autonomous life")
	w.objects.records[2].autonomous = false
	var stove: int = w.facilities.create_completed(w, "cook_stove", w.Terrain.index(Vector2i(130, 130)))
	w.objects.add(stove, "meal", 1)
	var meal_reason: String = w.begin_interaction(1, {"kind": "eat", "target": stove})
	check(meal_reason == "accepted", "In-flight meal fixture refused: " + meal_reason)
	w.objects.add(stove, "meal", -1)
	loaded = Persistence.candidate(Persistence.capture(w), 0)
	check(loaded != null, "Remote stock change invalidated a legitimate in-flight activity")
	if loaded != null:
		loaded.settle_action(1, loaded.elapsed_ms)
		check(not loaded.actions.has(1) and loaded.objects.amount(stove, "meal") == 0, "Restored arrival trusted stale meal availability")

func _run() -> void:
	definitions()
	shared_rules()
	instant_effects()
	arrival_and_restore()
	print("OPERATIONS_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
