extends "res://tests/institution_channel_edges_smoke.gd"

func remote_source_is_reinspected_after_a_blocked_notice() -> void:
	var f: Dictionary = duties_fixture()
	var w: RefCounted = f.world
	for appointment: int in [f.kitchen, f.meals]: w.institutions.revoke(w, appointment)
	var source: int = workshop(w, f.org, "wood_chest", Vector2i(170, 120))
	w.objects.add(source, "grain", 2, Stock.right(0, f.org)); w.objects.add(source, "water", 1, Stock.right(0, f.org))
	w.flush_topology()
	w.objects.records[3].sight_range = 3.0; w.objects.records[4].sight_range = 3.0
	w.set_capability_overrides(3, {"work": false})
	resident(w, 3, [source, f.stove, f.board]); resident(w, 4, [f.board])
	check(w.institutions.appoint(w, f.org, 3, "kitchen_steward", [source, f.stove, f.board], {"target": int(f.stove), "sources": [source], "channel": int(f.board)}) > 0, "Remote source duty did not use the same appointment contract")
	w.decisions.prepare(w, 0)
	while w.elapsed_ms < 60000 and w.objects.amount(f.stove, "meal") < 3: advance(w, w.elapsed_ms + 16)
	check(w.objects.amount(f.stove, "meal") == 3 and w.objects.amount(source, "grain") == 0 and w.objects.amount(source, "water") == 0, "Remote worker did not really exhaust the one-batch source")
	for index: int in 3: check(w.institutions.consume_at(w, 1, f.stove, "meal", 1, "eat"), "First remote batch did not actually leave the destination")
	advance(w, w.elapsed_ms + 60000)
	check(w.institutions.matters.size() == 1 and w.institutions.matters.values()[0].state == "cancelled", "A blocked remote notice was reissued from pre-notice source knowledge")
	var post: Dictionary = w.institutions.channels[f.board].posts.values()[0]
	var observation: Dictionary = w.knowledge.records[3].subjects[source]
	check(post.state == "closed" and observation.origin == "seen" and int(observation.seen_ms) >= int(post.closed_ms) and observation.view.inventory.is_empty(), "Remote manager stopped without actually revisiting the exhausted source")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Remote exhausted source and real reinspection failed recovery")

func vanished_source_without_prior_stock_is_reportable() -> void:
	var f: Dictionary = posted_fixture()
	var w: RefCounted = f.world
	w.objects.records[4].sight_range = 2.0
	var result: Dictionary = onsite(w, 4, f.board, "accept_post", {"matter": int(f.matter)})
	var share: int = int(result.facts.get("share", 0))
	check(share > 0 and not w.knowledge.view(4, f.source, w.elapsed_ms).has("inventory"), "Distant worker already knew an unvisited source's contents")
	for item: String in w.objects.inventory_summary(f.source): w.objects.add(f.source, item, -w.objects.amount(f.source, item))
	check(w.remove_static(f.source), "Actual old source could not be removed")
	w.objects.records[4].autonomous = true; w.decisions.resume(w, 4, w.elapsed_ms)
	advance(w, w.elapsed_ms + 20000)
	var signature: Dictionary = w.institutions.channels[f.board].posts[f.matter].signatures[share]
	check(w.knowledge.view(4, f.source, w.elapsed_ms).tile == -1 and w.institutions.shares[share].state == "released" and signature.status == "blocked", "A known empty site without old inventory permanently trapped the responsibility")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Historical removed source and explicit blocked report failed recovery")

func _run() -> void:
	remote_source_is_reinspected_after_a_blocked_notice()
	vanished_source_without_prior_stock_is_reportable()
	print("INSTITUTION_DUTY_DISTANCE_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
