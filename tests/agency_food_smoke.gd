extends "res://tests/knowledge_smoke.gd"
const Agency = preload("res://scripts/sim/kernel/agency_defs.gd")

func resident(w: RefCounted, actor: int, targets: Array) -> void:
	w.livelihood.records.erase(actor)
	w.knowledge.records.erase(actor)
	w.objects.records[actor].autonomous = true
	for target: int in targets:
		if w.actor_slots.has(target): w.knowledge.refresh(w, actor, target, w.elapsed_ms)
		else: w.knowledge.seed(w, actor, w.operation_target(target), w.elapsed_ms)
	w.knowledge.set_observation_due(w, actor, w.elapsed_ms + 5000)
	w.decisions.resume(w, actor, w.elapsed_ms)

func food_prerequisites_and_reentry() -> void:
	var w: RefCounted = peaceful()
	move_actor(w, 2, Vector2(123.5, 120.5))
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(122, 122)))
	var stove: int = w.facilities.create_completed(w, "cook_stove", w.Terrain.index(Vector2i(126, 122)))
	w.objects.add(chest, "grain", 4); w.objects.add(chest, "water", 2)
	w.objects.add(2, "grain", -w.objects.amount(2, "grain"))
	w.objects.add(2, "water", -w.objects.amount(2, "water"))
	w.objects.add(2, "meal", -w.objects.amount(2, "meal"))
	w.flush_topology()
	w.pages[0].hunger[1] = 1500
	w.pages[0].energy[1] = 10000
	resident(w, 2, [chest, stove])
	decide(w, 0)
	check(w.actions.get(2, {}).get("kind") == "take", "Hungry actor did not start real missing-ingredient transfer")
	var limit: int = 15000
	while w.elapsed_ms < limit and not w.objects.records[stove].has("process"): advance(w, w.elapsed_ms + 50)
	check(w.objects.records[stove].has("process"), "Ingredient acquisition did not progress into actual cooking")
	if not w.objects.records[stove].has("process"): return
	var goal_id: int = w.livelihood.records[2].intention.goal
	var goods: int = w.objects.total("grain")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Purpose/method and actual in-process pot did not restore")
	w.command({"kind": "interrupt", "actor": 2})
	check(w.livelihood.records[2].goals.has(goal_id) and w.objects.records[stove].has("process"), "Manual control erased personal goal or actual pot")
	w.objects.records[2].autonomous = true
	w.decisions.resume(w, 2, w.elapsed_ms)
	advance(w, w.elapsed_ms + 14000)
	check(w.pages[0].hunger[1] >= 7000 and w.objects.total("grain") == goods - 2 and w.objects.amount(chest, "grain") == 2 and w.objects.amount(chest, "water") == 1, "Cooking/eating failed to reenter with exact material deficits")
	check(w.facilities.completed.get("eat", 0) >= 2 and w.facilities.completed.get("cook", 0) >= 1, "Food goal completed without real processing/consumption")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Completed food loop lost candidate integrity")
	if restored != null:
		advance(restored, restored.elapsed_ms + 14000)
		check(restored.pages[0].hunger[1] >= 7000, "Restored autonomous method did not continue without a new order")

func self_food_and_player_parity() -> void:
	var w: RefCounted = peaceful()
	w.objects.add(1, "meal", 1)
	w.pages[0].hunger[0] = 1000
	check(w.execute_operation(1, {"kind": "eat", "target": 1}) == "accepted", "Player cannot use the shared self-inventory eating rule")
	advance(w, 1100)
	check(w.objects.amount(1, "meal") == 0 and w.pages[0].hunger[0] > 3900, "Self food operation did not consume real private meal")
	w.objects.add(2, "meal", 1 - w.objects.amount(2, "meal")); w.pages[0].hunger[1] = 1500
	resident(w, 2, [])
	decide(w, w.elapsed_ms)
	check(w.actions.get(2, {}).get("kind") == "eat" and w.actions[2].target == 2, "Autonomous actor ignored its actual carried meal")
	advance(w, w.elapsed_ms + 1200)
	check(w.objects.amount(2, "meal") == 0 and w.pages[0].hunger[1] > 4400, "Autonomous self eating bypassed actual consumption")

func partial_material_planning() -> void:
	var w: RefCounted = peaceful()
	for item: String in ["grain", "water"]: w.objects.add(2, item, -w.objects.amount(2, item))
	var stove: int = w.facilities.create_completed(w, "cook_stove", w.Terrain.index(Vector2i(126, 122)))
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(122, 122)))
	w.objects.add(2, "water", 1)
	var planner: RefCounted = preload("res://scripts/sim/kernel/agency_planner.gd").new()
	var known: Dictionary = {stove: w.operation_target(stove), chest: w.operation_target(chest)}
	var self_view: Dictionary = w.operation_actor(2); self_view["speed"] = w.pages[0].move_speed[1]
	planner.configure(self_view, w.operation_target(2), known, {}, w.combat.position(w, 2), w.elapsed_ms, {"work": 0, "cursor": 0}, {})
	var step: Dictionary = planner._resolve(w.Operations.OPERATIONS.cook, known[stove], [])
	check(step.get("input", {}).get("kind") == "put" and step.input.item == "water" and step.input.target == stove, "Unavailable grain hid a useful carried-water delivery")
	w.objects.add(2, "water", -1)
	w.objects.add(chest, "water", 1)
	known[chest] = w.operation_target(chest)
	self_view = w.operation_actor(2); self_view["speed"] = w.pages[0].move_speed[1]
	planner.configure(self_view, w.operation_target(2), known, {}, w.combat.position(w, 2), w.elapsed_ms, {"work": 0, "cursor": 0}, {})
	step = planner._resolve(w.Operations.OPERATIONS.cook, known[stove], [])
	check(step.get("input", {}).get("kind") == "take" and step.input.item == "water" and step.input.target == chest, "Unavailable first input hid another obtainable ingredient")
	w.deferred.close()

func _run() -> void:
	check(Agency.ERRORS.is_empty(), "Invalid authored agency library: " + str(Agency.ERRORS))
	food_prerequisites_and_reentry()
	self_food_and_player_parity()
	partial_material_planning()
	print("AGENCY_FOOD_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
