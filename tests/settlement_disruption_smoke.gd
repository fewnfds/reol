extends "res://tests/settlement_cycle_smoke.gd"
## An interruption of actual autonomous production in the normal hundred-person
## opening. No added recipes, gifts, shortened labor or compelled successor.

func _run() -> void:
	var w := World.new()
	check(w.initialize(100, 0, false, "empty") and Opening.assemble(w, SETUP).is_empty(), "Normal opening failed before disruption")
	for item: String in ["grain", "water", "meal"]: initial[item] = w.objects.audit_total(item)
	initial.source_qi = SETUP.district_origins.size() * SETUP.qi_offsets.size() * SETUP.initial_source_qi
	initial.personal_qi = 0
	var worker: int = 0
	var stove: int = 0
	while w.elapsed_ms < 120000 and worker == 0:
		w.step(50); account_opening(w)
		for actor: int in w.actions:
			var action: Dictionary = w.actions[actor]
			if action.kind == "cook" and action.has("started_ms") and w.elapsed_ms - int(action.started_ms) >= 500:
				worker = actor; stove = int(action.target); break
	check(worker > 0 and stove > 0, "No actual autonomous cooking batch started in the normal opening")
	if worker == 0: quit(1); return
	var process: int = int(w.objects.records[stove].process.id)
	var organization: int = int(w.objects.records[stove].organization)
	var far_actor: int = 99 if worker < 76 else 24
	var old_clue: PackedByteArray = var_to_bytes(w.knowledge.view(far_actor, worker, w.elapsed_ms))
	var stock: PackedByteArray = var_to_bytes(w.objects.records[stove].stock)
	# The disruption is deliberate test input; ordinary life up to and after it
	# remains the product World, institutions, knowledge and autonomous planner.
	w.kill(worker, w.elapsed_ms, "verification")
	account_opening(w); audit(w)
	check(not w.actions.has(worker) and worker not in w.reservations.values(), "Dead worker retained an activity or place lock")
	check(int(w.objects.records[stove].process.id) == process and int(w.objects.records[stove].process.remaining_ms) < 4000 and int(w.objects.records[stove].process.remaining_ms) > 0, "Worker death erased or completed unfinished shared labor")
	check(var_to_bytes(w.objects.records[stove].stock) == stock and int(w.objects.records[stove].process.contributions.get(worker, 0)) > 0, "Death lost public inputs or the actual contribution")
	check(var_to_bytes(w.knowledge.view(far_actor, worker, w.elapsed_ms)) == old_clue, "Remote resident learned an unobserved death")
	var path: String = "user://settlement-disruption-fixture.bin"
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Interrupted normal world could not open its test save")
	if file == null: quit(1); return
	file.store_var(Persistence.capture(w), false); file.close()
	file = FileAccess.open(path, FileAccess.READ)
	var restored: RefCounted = Persistence.candidate(file.get_var(false), 0)
	file.close(); DirAccess.remove_absolute(path)
	check(restored != null, "Interrupted hundred-person shared process failed actual file restoration")
	if restored == null: quit(1); return
	w = restored
	check(int(w.objects.records[stove].process.id) == process and var_to_bytes(w.objects.records[stove].stock) == stock, "Restoration replaced the actual batch or its attribution")
	var successor: int = 0
	var completed_at: int = -1
	var delivered: bool = false
	var fed: bool = false
	var finish: int = w.elapsed_ms + 180000
	while w.elapsed_ms < finish and not (successor > 0 and (delivered or fed)):
		w.step(250); account_opening(w)
		for result: Dictionary in w.activity_results.records.values():
			if result.status != "completed": continue
			if result.operation == "cook" and int(result.facts.get("process_id", 0)) == process:
				successor = int(result.actor)
				completed_at = int(result.at_ms)
				check(result.actor != worker and result.facts.labor.any(func(entry: Dictionary): return entry.actor == worker and int(entry.worked_ms) > 0), "Shared completion lost the deceased preparer's labor or revived their controller")
			if successor > 0 and int(result.at_ms) >= completed_at and result.operation == "put" and result.facts.get("item") == "meal":
				for delivery: Dictionary in result.facts.get("deliveries", []):
					if int(delivery.origin) == stove and int(delivery.organization) == organization and int(delivery.amount) > 0: delivered = true
			if successor > 0 and int(result.at_ms) >= completed_at and result.operation == "eat" and int(result.target) == stove and int(result.facts.get("consumed", {}).get("meal", 0)) > 0: fed = true
	audit(w)
	if successor == 0 or not (delivered or fed):
		print("DISRUPTION_UNFINISHED worker=", worker, " successor=", successor, " delivered=", delivered, " fed=", fed, " stove=", w.objects.records[stove], " actions=", adopted)
		checkpoint(w, "res://logs/t13-disruption-unfinished.bin")
	# Existing meal chests may still be full enough. A public meal eaten at its
	# actual stove is equally real provision; do not require unnecessary hauling.
	check(successor > 0 and (delivered or fed), "Normal sect did not autonomously finish and use the interrupted public cooking batch")
	check(not w.combat.alive(w, worker) and not w.actions.has(worker) and worker not in w.reservations.values(), "Recovery resurrected the dead worker or their locks")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Recovered autonomous production failed final restoration")
	print("SETTLEMENT_DISRUPTION_SMOKE errors=", errors, " at_ms=", w.elapsed_ms, " worker=", worker, " successor=", successor, " process=", process, " delivered=", delivered, " fed=", fed, " actions=", adopted)
	quit(0 if errors == 0 else 1)
