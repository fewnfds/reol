extends "res://tests/institution_matters_smoke.gd"

func passive_handoff_and_cancellation() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	for actor: int in [3, 4]:
		w.institutions.admit(w, f.org, actor, Array(w.institutions.PURPOSES))
		Growth.seed(w.objects.records[actor], "herbalism", 0, false)
	w.objects.add(f.source, "herb", 4, Stock.right(0, f.org)); w.objects.add(f.source, "water", 2, Stock.right(0, f.org))
	var spec: Dictionary = {"kind": "produce", "organization": f.org, "target": f.stove, "operation": "brew", "item": "potion", "sources": [f.source], "total": 1, "quota": 1}
	var matter: int = w.institutions.create_matter(w, 1, spec)
	var share: int = w.institutions.accept_share(w, 3, matter)
	manual_transfer(w, 3, f.source, "herb", 2, "take", {"purpose": "produce"})
	manual_transfer(w, 3, f.source, "water", 1, "take", {"purpose": "produce"})
	manual_transfer(w, 3, f.stove, "herb", 2, "put", {"purpose": "produce"})
	manual_transfer(w, 3, f.stove, "water", 1, "put", {"purpose": "produce"})
	move_actor(w, 3, Vector2(127.5, 123.5))
	check(w.execute_operation(3, {"kind": "brew", "target": int(f.stove)}) == "accepted", "Obligated brewer did not start real work")
	w.settle_action(3, w.elapsed_ms)
	advance(w, w.elapsed_ms + 1600)
	check(w.objects.records[f.stove].process.stage == "passive" and w.institutions.shares[share].fulfilled == 0, "Passive-stage receipt was credited as finished production")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Passive obligation did not restore with its physical batch")
	if restored == null: return
	w = restored
	var ready: int = w.objects.records[f.stove].process.ready_ms
	advance(w, ready)
	move_actor(w, 3, Vector2(125.5, 125.5)) # The first worker must actually vacate the unique craft station.
	move_actor(w, 4, Vector2(127.5, 123.5))
	check(w.execute_operation(4, {"kind": "brew", "target": int(f.stove)}) == "accepted", "Other actual worker could not finish the same batch")
	w.settle_action(4, w.elapsed_ms)
	advance(w, w.elapsed_ms + 600)
	check(w.institutions.shares[share].state == "completed" and w.objects.amount(f.stove, "potion", Stock.right(0, f.org)) == 1 and w.objects.amount(f.source, "herb") == 2, "Non-obligor finishing failed to credit the real preparer's share exactly once")
	matter = w.institutions.create_matter(w, 1, spec)
	share = w.institutions.accept_share(w, 3, matter)
	manual_transfer(w, 3, f.source, "herb", 2, "take", {"purpose": "produce"})
	check(w.institutions.cancel_matter(w, 1, matter) and w.institutions.shares[share].state == "released" and not w.institutions.returns(w, 3).is_empty() and w.objects.amount(3, "herb", Stock.right(3)) == 0, "Cancelling normative work erased or privatized outstanding custody")
	manual_transfer(w, 3, f.source, "herb", 2, "put")
	check(w.institutions.returns(w, 3).is_empty() and Persistence.candidate(Persistence.capture(w), 0) != null, "Cancelled raw materials did not actually return and reconcile")

func records_expire_without_progress_replay() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	w.objects.add(f.source, "grain", 2, Stock.right(0, f.org))
	var matter: int = w.institutions.create_matter(w, 1, delivery_spec(f, 2, 2))
	var share: int = w.institutions.accept_share(w, 3, matter)
	manual_transfer(w, 3, f.source, "grain", 1, "take", {"purpose": "supply"})
	var first: Dictionary = manual_transfer(w, 3, f.destination, "grain", 1, "put")
	for index: int in 12:
		var run: int = w.next_run; w.next_run += 1
		w.commit_activity(run, "talk", 3, 1, [3, 1], w.elapsed_ms, Results.completed({"test_receipt": index}))
	check(not w.activity_results.records.has(int(first.id)) and w.institutions.shares[share].fulfilled == 1, "Pruning recent activity evidence recomputed persistent fulfilment")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "A pruned older result became mandatory for restoration")
	if restored == null: return
	w = restored
	manual_transfer(w, 3, f.source, "grain", 1, "take", {"purpose": "supply"})
	manual_transfer(w, 3, f.destination, "grain", 1, "put")
	check(w.institutions.shares[share].fulfilled == 2 and w.institutions.matters[matter].state == "completed", "Restored obligation did not continue after result pruning")

func original_harvest_uses_shared_declared_purpose() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	var source: int = w.source_objects[0]
	w.objects.records[source].organization = f.org
	w.objects.retitle(source, "stock", Stock.right(), Stock.right(0, f.org))
	w.knowledge.seed(w, 1, w.operation_target(source), 0)
	var spec: Dictionary = delivery_spec(f, 1, 1); spec.item = "wood"; spec.sources = [source]
	var matter: int = w.institutions.create_matter(w, 1, spec)
	var share: int = w.institutions.accept_share(w, 3, matter)
	move_actor(w, 3, w.Terrain.center(w.objects.records[source].tile))
	check(w.execute_operation(3, {"kind": "harvest", "target": source, "purpose": "supply"}) == "accepted", "Original harvest still bypassed the shared operation entry")
	advance(w, 200)
	check(w.pages[0].modes[2] == w.Units.Mode.HARVEST and w.reservations.get(source) == 3 and Persistence.candidate(Persistence.capture(w), 0) != null, "Reserved harvest lost its declared purpose during restoration")
	advance(w, 650)
	check(w.objects.amount(3, "wood") > 0 and w.work_runs.get(3, {}).is_empty(), "Declared-purpose harvest did not yield through its real body-work host")
	manual_transfer(w, 3, f.destination, "wood", 1, "put")
	check(w.institutions.shares[share].state == "completed" and Persistence.candidate(Persistence.capture(w), 0) != null, "Original resource source could not fulfil actual transport after declaring its legal purpose")

func _run() -> void:
	passive_handoff_and_cancellation()
	records_expire_without_progress_replay()
	original_harvest_uses_shared_declared_purpose()
	print("INSTITUTION_PRODUCTION_SHARES_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
