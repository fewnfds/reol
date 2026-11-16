extends "res://tests/production_smoke.gd"

func public_passive_and_salvage() -> void:
	var w: RefCounted = peaceful()
	var org: int = organization(w)
	var chest: int = facility(w, "wood_chest", 124, 124, org)
	var stove: int = facility(w, "cook_stove", 128, 124, org)
	w.objects.add(stove, "wood", 4, Stock.right(0, org))
	w.objects.install_materials(stove)
	for actor: int in [1, 3]: Growth.seed(w.objects.records[actor], "herbalism", 0, false)
	for item: String in ["herb", "water"]:
		clear_private(w, 1, item)
		w.objects.add(chest, item, 4 if item == "herb" else 2, Stock.right(0, org))
	w.pages[0].positions[0] = Vector2(123.5, 124.5)
	carry(w, 1, chest, "herb", 2, "take", "produce")
	carry(w, 1, chest, "water", 1, "take", "produce")
	if not start(w, 1, "brew", stove): return
	advance(w, w.elapsed_ms + 1600)
	var ready: int = w.objects.records[stove].process.ready_ms
	w.institutions.admit(w, org, 1, [])
	w.institutions.admit(w, org, 3, ["cook"])
	check(w.begin_interaction(1, {"kind": "brew", "target": stove}) == "not_authorized" and w.begin_interaction(2, {"kind": "brew", "target": stove}) == "not_authorized" and w.begin_interaction(3, {"kind": "brew", "target": stove}) == "not_authorized", "Revoked, nonmember or wrong-purpose worker could collect public batch")
	w.kill(1, w.elapsed_ms)
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Public passive batch lost deceased custodian responsibility")
	if restored == null: return
	w = restored
	w.institutions.admit(w, org, 3, Array(w.institutions.PURPOSES))
	advance(w, ready)
	if not start(w, 3, "brew", stove): return
	advance(w, w.elapsed_ms + 250)
	w.end_run(3, w.elapsed_ms, "preempted")
	check(w.objects.records[stove].process.stage == "finish" and w.objects.records[stove].process.remaining_ms == 250, "Interrupted collection repeated prep or lost finish labor")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Partly collected public batch did not restore")
	if not start(w, 3, "brew", stove): return
	w.objects.records[stove].capacity = 1
	w.objects.add(stove, "wood", 1)
	advance(w, w.elapsed_ms + 300)
	check(w.objects.records[stove].process.remaining_ms == 1 and latest(w, 3).reason == "no_output_capacity", "Blocked collection did not retain final labor quantum")
	w.objects.add(stove, "wood", -1)
	if not start(w, 3, "brew", stove): return
	advance(w, w.elapsed_ms + 16)
	check(w.objects.amount(stove, "potion", Stock.right(0, org)) == 1 and w.institutions.entrustments.is_empty() and w.institutions.accounts[org][1].consumed == {"herb": 2, "water": 1} and w.institutions.accounts[org][1].delivered == {"potion": 1}, "Public passive conversion credited the wrong custodian or lost original title")
	check(w.objects.records[1].methods.herbalism.progress == 0 and w.objects.records[3].methods.herbalism.progress == 25, "Finishing interruption duplicated learning or taught a corpse")
	w.objects.records[stove].capacity = -1
	w.pages[0].positions[2] = Vector2(123.5, 124.5)
	carry(w, 3, chest, "herb", 2, "take", "produce")
	carry(w, 3, chest, "water", 1, "take", "produce")
	var mandate: int = w.institutions.entrustments.keys()[0]
	if not start(w, 3, "brew", stove): return
	advance(w, w.elapsed_ms + 300)
	w.end_run(3, w.elapsed_ms, "preempted")
	var herb: int = w.objects.total("herb")
	var wood: int = w.objects.total("wood")
	var result: Dictionary = w.facilities.demolish_result(w, stove, w.elapsed_ms)
	check(result.status == "completed" and w.objects.total("herb") == herb and w.objects.total("wood") == wood and w.objects.amount(result.facts.salvage_pile, "wood", Stock.right(0, org)) == 4, "Dismantling lost public WIP or actual body materials")
	var right: Dictionary = Stock.right(0, org, mandate)
	check(w.objects.amount(result.facts.salvage_pile, "herb", right) == 2 and w.objects.amount(result.facts.salvage_pile, "water", right) == 1, "WIP salvage laundered original issue")
	for item: String in ["herb", "water"]:
		var count: int = 2 if item == "herb" else 1
		w.objects.transfer(result.facts.salvage_pile, 3, item, count, right)
		var returned: Dictionary = w.institutions.move_goods(w, 3, chest, item, count, "put", {}, w.elapsed_ms)
		check(returned.status == "completed", "Actual WIP salvage could not be returned")
	check(w.institutions.entrustments.is_empty() and w.institutions.accounts[org][3].returned == {"herb": 2, "water": 1} and Persistence.candidate(Persistence.capture(w), 0) != null, "Returning salvaged input did not close real issue responsibility")

func saturated_salvage() -> void:
	var w: RefCounted = peaceful()
	var stove: int = facility(w, "cook_stove", 124, 124, 0)
	if not start(w, 1, "cook", stove): return
	w.end_run(1, w.elapsed_ms, "preempted")
	for owner: int in range(2, Stock.MAX_GROUPS + 2): w.objects.add(stove, "grain", 1, Stock.right(owner))
	var before: int = w.objects.total("grain")
	check(w.facilities.demolish_result(w, stove, w.elapsed_ms).reason == "salvage_capacity" and w.objects.total("grain") == before and w.objects.records[stove].has("work_stock"), "Overfull salvage groups silently erased material")
	var pile: int = w.objects.create("pile", "grain", w.Terrain.index(Vector2i(125, 125)))
	w.objects.transfer(stove, pile, "grain", 1, Stock.right(2))
	check(w.facilities.demolish_result(w, stove, w.elapsed_ms).status == "completed" and w.objects.audit_total("grain") == before and w.objects.total("grain") == before, "Cleared salvage group could not preserve every real ingredient")

func precursor_and_revocation() -> void:
	for interrupted: bool in [true, false]:
		var w: RefCounted = peaceful()
		var stove: int = facility(w, "cook_stove", 124, 124, 0)
		w.objects.add(3, "grain", 2)
		w.objects.add(3, "water", 1)
		w.pages[0].positions[0] = Vector2(120.5, 125.5)
		check(w.begin_interaction(1, {"kind": "cook", "target": stove}) == "accepted", "Precursor did not reserve real approach")
		at_stove(w, 3, stove)
		check(w.begin_interaction(3, {"kind": "cook", "target": stove}) == "accepted" and w.actions[3].expected_run == w.actions[1].run_id, "Queued empty carrier did not bind its actual precursor")
		w.settle_action(3, 0)
		advance(w, 1200)
		check(w.objects.records[stove].has("process") and w.actions[3].expected_process == w.objects.records[stove].process.id, "Approaching continuation failed to adopt the actual batch identity")
		if interrupted: w.end_run(1, w.elapsed_ms, "preempted")
		advance(w, 6200)
		check(w.objects.amount(stove, "meal") == 3 and not w.actions.has(3), "Queued precursor silently opened a second batch")
		check(latest(w, 3).status == "completed" if interrupted else latest(w, 3).reason == "process_changed", "Precursor continuation handled interruption/completion incorrectly")
	var w: RefCounted = peaceful()
	var org: int = organization(w)
	var chest: int = facility(w, "wood_chest", 124, 124, org)
	var stove: int = facility(w, "cook_stove", 128, 124, org)
	w.objects.add(chest, "grain", 2, Stock.right(0, org))
	w.objects.add(chest, "water", 1, Stock.right(0, org))
	w.pages[0].positions[0] = Vector2(123.5, 124.5)
	carry(w, 1, chest, "grain", 2, "take", "cook")
	carry(w, 1, chest, "water", 1, "take", "cook")
	if not start(w, 1, "cook", stove): return
	advance(w, w.elapsed_ms + 500)
	w.institutions.admit(w, org, 1, [])
	var remaining: int = w.objects.records[stove].process.remaining_ms
	check(not w.actions.has(1) and remaining == 3500, "Revocation allowed further unauthorized labor")
	advance(w, w.elapsed_ms + 1000)
	check(w.objects.records[stove].process.remaining_ms == remaining, "Revoked worker accrued labor after permission loss")
	var neutral: int = facility(w, "cook_stove", 132, 124, 0)
	w.objects.add(3, "grain", 2)
	w.objects.add(3, "water", 1)
	if not start(w, 3, "cook", neutral): return
	w.end_run(3, w.elapsed_ms, "preempted")
	check(w.begin_interaction(1, {"kind": "demolish", "target": neutral}) == "not_authorized" and w.facilities.demolish_result(w, neutral, w.elapsed_ms, 1).reason == "not_authorized", "Neutral bench allowed another person's WIP to be dismantled")

func _run() -> void:
	public_passive_and_salvage()
	saturated_salvage()
	precursor_and_revocation()
	print("PRODUCTION_AUTHORITY_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
