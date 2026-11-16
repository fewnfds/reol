extends "res://tests/institution_duties_smoke.gd"

func onsite(w: RefCounted, actor: int, board: int, kind: String, parameters: Dictionary = {}) -> Dictionary:
	var request: Dictionary = {"kind": kind, "target": board}
	request.merge(parameters, true)
	var cell: Vector2i = w.Terrain.cell(w.objects.records[board].tile)
	move_actor(w, actor, Vector2(cell) + Vector2(-0.5, 0.5))
	check(w.execute_operation(actor, request) == "accepted", "Records operation failed common admission: " + str(request))
	w.settle_action(actor, w.elapsed_ms); advance(w, w.elapsed_ms + 450)
	return w.activity_results.view(actor).back()

func local_records_and_explicit_reports() -> void:
	var f: Dictionary = duties_fixture()
	var w: RefCounted = f.world
	for actor: int in [3, 4]: w.release(actor); w.objects.records[actor].autonomous = false
	move_actor(w, 3, Vector2(180.5, 180.5))
	var result: Dictionary = onsite(w, 3, f.board, "post_duty", {"appointment": int(f.kitchen)})
	check(result.reason == "matter_posted", "A legitimately inspected stock shortage was not posted")
	var matter: int = result.facts.matter
	# Move beyond sight before reading; only the board is visited, not the stove.
	move_actor(w, 4, Vector2(180.5, 180.5)); w.objects.records[4].sight_range = 2.0
	w.knowledge.record(4).subjects.clear(); w.knowledge.record(4).channels.clear(); w.knowledge.record(4).due_ms = 10000
	var remote_cell := Vector2i(150, 140)
	check(w.facilities.placement(w, "ground", w.facilities.footprint("notice_desk", w.Terrain.index(remote_cell))) == "accepted", "Remote desk fixture overlaps an original facility")
	var board: int = workshop(w, f.org, "notice_desk", remote_cell)
	w.flush_topology()
	# Publish using the same explicit appointment at a physically separate desk.
	w.institutions.revoke(w, f.kitchen)
	var job: int = w.institutions.appoint(w, f.org, 3, "kitchen_steward", [f.source, f.stove, board], {"target": int(f.stove), "sources": [int(f.source)], "channel": board})
	# The live semantic key prevents a second simultaneous notice elsewhere.
	result = onsite(w, 3, board, "post_duty", {"appointment": job})
	check(result.reason == "already_posted_elsewhere" and w.institutions.matters.size() == 1, "Different record carriers duplicated the same real shortage")
	move_actor(w, 4, Vector2(122.5, 124.5))
	result = onsite(w, 4, f.board, "read_channel")
	check(result.reason == "records_read" and w.knowledge.records[4].channels[f.board].posts.has(matter) and not w.knowledge.view(4, f.stove, w.elapsed_ms).has("inventory"), "Reading a physical notice revealed remote live inventory")
	result = onsite(w, 4, f.board, "accept_post", {"matter": matter})
	var share: int = int(result.facts.get("share", 0))
	check(share > 0 and w.institutions.Matters.occupied(w.institutions, w.institutions.matters[matter]) == 3, "On-site acceptance did not allocate a real share")
	manual_transfer(w, 4, f.source, "grain", 2, "take", {"purpose": "cook"})
	manual_transfer(w, 4, f.source, "water", 1, "take", {"purpose": "cook"})
	move_actor(w, 4, Vector2(127.5, 123.5))
	check(w.execute_operation(4, {"kind": "cook", "target": int(f.stove)}) == "accepted", "Accepted board share did not use the actual production host")
	w.settle_action(4, w.elapsed_ms); advance(w, w.elapsed_ms + 6000)
	check(w.institutions.shares[share].state == "completed" and w.institutions.channels[f.board].posts[matter].signatures[share].reported == 0, "Remote completion wirelessly rewrote the physical notice")
	result = onsite(w, 4, f.board, "report_matter", {"share": share})
	check(result.reason == "matter_reported" and w.institutions.channels[f.board].posts[matter].signatures[share].reported == 3 and w.objects.amount(f.stove, "meal") == 3, "Actual return/report failed to record the worker's real output")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Posted terms and explicit report did not restore")
	var bad: Dictionary = Persistence.capture(w)
	bad.domains.institutions.appointments[job].duty_scope.channel = f.source
	check(Persistence.candidate(bad, 0) == null, "A duty bound to a non-record carrier restored")
	bad = Persistence.capture(w)
	bad.domains.knowledge.records[4].channels[f.board].posts[matter].reported = 10000
	check(Persistence.candidate(bad, 0) == null, "Forged personal record quantities restored")
	bad = Persistence.capture(w)
	var forged: Dictionary = bad.domains.institutions.channels[f.board].posts[matter]
	forged.terms.target = f.source
	forged.key = w.institutions.Channels._key(f.org, forged.terms)
	check(Persistence.candidate(bad, 0) == null, "A published contract with another canonical target restored")
	check(w.institutions.revise_matter(w, 3, matter, 9, 2, w.elapsed_ms + 60000), "Legitimate later matter revision failed")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "An older published snapshot was mistaken for a forged current revision")
	w.knowledge.seed(w, 4, w.operation_target(2), w.elapsed_ms)
	bad = Persistence.capture(w)
	bad.domains.knowledge.records[4].subjects[2].view.post_revision = 1
	check(Persistence.candidate(bad, 0) == null, "A person masquerading as a record carrier restored")

func water_uses_the_same_duty_and_original_source_host() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	f.board = workshop(w, f.org, "notice_desk", Vector2i(121, 124))
	var well: int = workshop(w, f.org, "water_well", Vector2i(125, 124))
	w.flush_topology()
	w.objects.add(well, "water", 6, Stock.right(0, f.org))
	resident(w, 3, [well, f.destination, f.board]); resident(w, 4, [f.board])
	check(w.institutions.appoint(w, f.org, 3, "water_steward", [well, f.destination, f.board], {"target": int(f.destination), "sources": [well], "channel": int(f.board)}) > 0, "Water service needed a separate job engine")
	w.decisions.prepare(w, 0); advance(w, 30000)
	check(w.objects.amount(f.destination, "water", Stock.right(0, f.org)) == 6 and w.facilities.completed.get("draw_water", 0) > 0 and w.objects.records[well].source_generated > 0, "Authored water duty did not use finite real source collection and delivery")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Actual source replenishment/channel responsibility did not restore")

func _run() -> void:
	local_records_and_explicit_reports()
	water_uses_the_same_duty_and_original_source_host()
	print("INSTITUTION_CHANNELS_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
