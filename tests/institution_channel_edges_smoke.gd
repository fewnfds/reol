extends "res://tests/institution_channels_smoke.gd"

func posted_fixture() -> Dictionary:
	var f: Dictionary = duties_fixture()
	for actor: int in [3, 4]: f.world.release(actor); f.world.objects.records[actor].autonomous = false
	f.matter = onsite(f.world, 3, f.board, "post_duty", {"appointment": int(f.kitchen)}).facts.matter
	return f

func stale_claim_and_authorized_local_closure() -> void:
	var f: Dictionary = posted_fixture()
	var w: RefCounted = f.world
	onsite(w, 1, f.board, "read_channel")
	for actor: int in [3, 4]: check(onsite(w, actor, f.board, "accept_post", {"matter": int(f.matter)}).reason == "accepted_share", "Two real signers failed to consume exactly the published total")
	check(w.knowledge.records[1].channels[f.board].posts[f.matter].unclaimed == 6, "Unvisited record was wirelessly updated after somebody else signed")
	check(onsite(w, 1, f.board, "accept_post", {"matter": int(f.matter)}).reason == "no_open_share" and w.knowledge.records[1].channels[f.board].posts[f.matter].unclaimed == 0, "A stale failed claim did not read the record actually in front of the actor")
	check(onsite(w, 4, f.board, "close_post", {"matter": int(f.matter)}).reason == "not_authorized", "A delegated worker gained administrative withdrawal rights")
	w.institutions.revoke(w, f.kitchen)
	var new_board: int = workshop(w, f.org, "notice_desk", Vector2i(150, 140))
	w.flush_topology()
	for target: int in [f.stove, f.source, f.board, new_board]: w.knowledge.seed(w, 1, w.operation_target(target), w.elapsed_ms)
	var appointment: int = w.institutions.appoint(w, f.org, 1, "kitchen_steward", [f.stove, f.source, new_board], {"target": int(f.stove), "sources": [int(f.source)], "channel": new_board})
	check(appointment > 0, "Replacement could not take a real responsibility scope")
	check(onsite(w, 1, new_board, "post_duty", {"appointment": appointment}).reason == "already_posted_elsewhere", "Changing desks bypassed an existing allocation")
	check(onsite(w, 1, f.board, "close_post", {"matter": int(f.matter)}).reason == "post_closed", "An authorized replacement could not withdraw the old local record")
	check(w.institutions.shares.values().all(func(share: Dictionary): return share.state == "released") and w.institutions.channels[f.board].posts[f.matter].signatures.values().all(func(signature: Dictionary): return signature.status == "accepted"), "Local withdrawal invented worker reports or failed to release actual obligations")
	move_actor(w, 1, Vector2(125.5, 120.5)); w.knowledge.refresh(w, 1, f.source, w.elapsed_ms)
	move_actor(w, 1, Vector2(127.5, 123.5)); w.knowledge.refresh(w, 1, f.stove, w.elapsed_ms)
	check(onsite(w, 1, new_board, "post_duty", {"appointment": appointment}).reason == "matter_posted", "Withdrawn old records permanently blocked the replacement desk")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Replaced appointments/local withdrawal failed historical recovery")

func full_destination_does_not_reissue() -> void:
	var f: Dictionary = duties_fixture()
	var w: RefCounted = f.world
	w.set_capability_overrides(3, {"work": false})
	w.objects.records[f.destination].capacity = 2
	w.objects.add(f.destination, "wood", 2, Stock.right(0, f.org))
	w.decisions.prepare(w, 0); advance(w, 45000)
	check(w.institutions.matters.values().all(func(matter: Dictionary): return matter.kind != "delivery"), "A known full destination repeatedly generated impossible delivery orders")
	w.objects.add(f.destination, "wood", -2)
	advance(w, w.elapsed_ms + 30000)
	check(w.objects.amount(f.destination, "meal") == 2 and w.objects.amount(4, "meal") == 0, "Actual free space did not allow partial delivery and return of unusable remainder")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Full destination/partial delivery response did not restore")

func bounded_record_history_and_provenance() -> void:
	var f: Dictionary = posted_fixture()
	var w: RefCounted = f.world
	# Reading one's own note restores the original scenario clue, never invents
	# a firsthand visit to the remote source.
	var original: Dictionary = w.institutions.channels[f.board].posts[f.matter].clues[1].duplicate(true)
	w.objects.records[3].sight_range = 2.0
	w.knowledge.records[3].subjects.erase(f.source)
	onsite(w, 3, f.board, "read_channel")
	var recovered: Dictionary = w.knowledge.records[3].subjects[f.source]
	check(recovered.origin == original.origin and recovered.observer == original.observer and recovered.source == original.source and recovered.seen_ms == original.seen_ms and not recovered.view.has("inventory"), "Rereading one's note fabricated firsthand inventory evidence")
	check(onsite(w, 3, f.board, "close_post", {"matter": int(f.matter)}).reason == "post_closed", "History fixture could not close its first record")
	for index: int in 34:
		move_actor(w, 3, Vector2(124.5, 120.5)); w.knowledge.refresh(w, 3, f.source, w.elapsed_ms)
		move_actor(w, 3, Vector2(127.5, 123.5)); w.knowledge.refresh(w, 3, f.stove, w.elapsed_ms)
		var result: Dictionary = onsite(w, 3, f.board, "post_duty", {"appointment": int(f.kitchen)})
		check(result.reason == "matter_posted", "Closed history exhausted the bounded record carrier: " + str(result.reason))
		if result.reason != "matter_posted": break
		check(onsite(w, 3, f.board, "close_post", {"matter": int(result.facts.matter)}).reason == "post_closed", "History fixture could not close its actual posted record")
	check(w.institutions.channels[f.board].posts.size() == w.institutions.Channels.POST_LIMIT and Persistence.candidate(Persistence.capture(w), 0) != null, "Carrier history failed bounded reuse or restoration")

func distinct_material_purposes_survive_hunger() -> void:
	var f: Dictionary = posted_fixture()
	var w: RefCounted = f.world
	resident(w, 4, [f.source, f.destination, f.stove, f.board])
	w.objects.records[4].autonomous = false
	var delivery: int = w.institutions.create_matter(w, 1, {"kind": "delivery", "organization": f.org, "target": f.destination, "item": "grain", "sources": [int(f.source)], "total": 2, "quota": 2})
	var share: int = w.institutions.accept_share(w, 4, delivery)
	w.objects.records[4].autonomous = true; w.decisions.resume(w, 4, w.elapsed_ms)
	while w.elapsed_ms < 12000 and w.objects.amount(4, "grain") < 2: advance(w, w.elapsed_ms + 16)
	check(w.objects.amount(4, "grain") == 2, "Dual-purpose fixture never physically acquired delivery stock")
	w.command({"kind": "interrupt", "actor": 4})
	check(w.institutions.accept_share(w, 4, f.matter, 3) > 0, "A second independent actual production responsibility was refused")
	w.objects.add(4, "meal", 1, Stock.right(4)); w.pages[0].hunger[3] = 1000
	w.objects.records[4].autonomous = true; w.decisions.resume(w, 4, w.elapsed_ms)
	advance(w, w.elapsed_ms + 6000)
	check(w.objects.amount(4, "meal", Stock.right(4)) == 0 and w.pages[0].hunger[3] > 3900, "Concurrent responsibilities prevented an urgent personal meal")
	while w.elapsed_ms < 30000 and (w.institutions.shares[share].fulfilled != 2 or w.objects.amount(f.stove, "meal") < 3): advance(w, w.elapsed_ms + 16)
	check(w.institutions.shares[share].fulfilled == 2 and w.objects.amount(f.destination, "grain") == 2 and w.objects.amount(f.stove, "meal") == 3 and w.objects.amount(f.source, "grain") == 8 and w.objects.amount(4, "grain") == 0, "Distinct supply/cook mandates were returned and reissued instead of completing both real purposes: " + str({"delivery": w.institutions.shares[share], "destination": w.objects.inventory_summary(f.destination), "source": w.objects.inventory_summary(f.source), "stove": w.objects.inventory_summary(f.stove), "actor": w.objects.inventory_summary(4), "life": w.livelihood.describe(4)}))
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Concurrent purposes and urgent personal interruption failed restoration")

func duty_places_survive_bounded_personal_memory() -> void:
	var f: Dictionary = duties_fixture()
	var w: RefCounted = f.world
	for index: int in 135:
		var pile: int = w.objects.create("pile", "wood", w.Terrain.index(Vector2i(200 + index % 20, 200 + index / 20)))
		w.objects.add(pile, "wood", 1)
		w.knowledge.seed(w, 3, w.operation_target(pile), w.elapsed_ms)
	var subjects: Dictionary = w.knowledge.records[3].subjects
	check(subjects.size() == w.knowledge.SUBJECT_LIMIT and [f.source, f.destination, f.stove, f.board].all(func(target: int): return subjects.has(target)), "Ordinary bounded memories displaced every working place of a current duty")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Bounded personal memories with protected duty places failed restore")

func _run() -> void:
	stale_claim_and_authorized_local_closure()
	full_destination_does_not_reissue()
	bounded_record_history_and_provenance()
	distinct_material_purposes_survive_hunger()
	duty_places_survive_bounded_personal_memory()
	print("INSTITUTION_CHANNEL_EDGES_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
