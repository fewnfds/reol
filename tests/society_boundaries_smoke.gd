extends "res://tests/society_state_smoke.gd"

func offers_revisions_and_aliases() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	w.objects.add(f.source, "grain", 5, Stock.right(0, f.org))
	var matter: int = w.institutions.create_matter(w, 1, delivery_spec(f, 3, 2))
	var result: Dictionary = w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 4, "matter": matter}, 0)
	check(result.status == "completed", "Offer fixture refused")
	if result.status != "completed": return
	var id: int = int(result.facts.request)
	var share: int = w.institutions.accept_share(w, 3, matter, 2)
	manual_transfer(w, 3, int(f.source), "grain", 1, "take", {"purpose": "supply"})
	manual_transfer(w, 3, int(f.destination), "grain", 1, "put")
	check(w.institutions.release_share(w, 3, share) and w.institutions.revise_matter(w, 1, matter, 1, 1, 0), "Partial-release/downsize fixture failed")
	check(w.society.requests[id].state == "cancelled" and w.institutions.matters[matter].state == "completed" and Persistence.candidate(Persistence.capture(w), 0) != null, "Revision completed a matter but stranded its unaccepted request")
	# A second subject at the same store is a different request; a changed offer
	# must not silently rewrite terms already conveyed to a recipient.
	move_actor(w, 4, w.combat.position(w, 1))
	var grain: int = w.institutions.create_matter(w, 1, delivery_spec(f, 3, 1))
	var wood_spec: Dictionary = delivery_spec(f, 3, 1); wood_spec.item = "wood"
	var wood: int = w.institutions.create_matter(w, 1, wood_spec)
	var first: Dictionary = w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 4, "matter": grain}, w.elapsed_ms)
	var second: Dictionary = w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 4, "matter": wood}, w.elapsed_ms)
	check(first.status == "completed" and second.status == "completed", "Different material topics at one store collided")
	if first.status != "completed": return
	id = int(first.facts.request)
	w.institutions.revise_matter(w, 1, grain, 4, 1, w.elapsed_ms + 10000)
	check(w.society.respond(w, 4, id, "accept", w.elapsed_ms).reason == "terms_changed" and w.society.requests[id].share == 0, "Changed normative terms were accepted through a stale request")
	move_actor(w, 3, w.combat.position(w, 1))
	var existing: int = w.institutions.accept_share(w, 3, grain, 1)
	var alias: Dictionary = w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 3, "matter": grain}, w.elapsed_ms)
	check(existing > 0 and alias.status == "completed", "Existing-share alias fixture failed")
	if alias.status == "completed":
		id = int(alias.facts.request)
		check(w.society.respond(w, 3, id, "accept", w.elapsed_ms).reason == "already_accepted" and w.society.requests[id].share == 0 and w.institutions.Matters.shares_for(w.institutions, 3).size() == 1, "Contact adopted a share already accepted elsewhere")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Revised/refused offers failed restore")
	# Force real institution history compaction, without manually erasing a
	# referenced matter. Closed social history must tolerate the missing record.
	for index: int in 512:
		var historical: int = w.institutions.create_matter(w, 1, delivery_spec(f, 1, 1))
		check(historical > 0 and w.institutions.cancel_matter(w, 1, historical), "History pressure fixture could not close a matter")
	check(not w.institutions.matters.has(matter) and Persistence.candidate(Persistence.capture(w), 0) != null, "Compacting old normative records invalidated social history")

func directional_capacity_and_contact_retention() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	var actors: Array = []
	var matter: int = w.institutions.create_matter(w, 1, delivery_spec(f, 60, 1))
	for index: int in 70:
		var actor: int = w.spawn_actor(w.Terrain.index(Vector2i(123, 120)))
		check(actor > 0, "Capacity fixture could not create real participant")
		if actor <= 0: return
		w.objects.records[actor].side = 0
		w.institutions.admit(w, int(f.org), actor, [])
		actors.append(actor)
	for index: int in 50:
		var actor: int = int(actors[index])
		var offered: Dictionary = w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": actor, "matter": matter}, 0)
		check(offered.status == "completed", "One issuer was blocked by eight already-accepted requests")
		if offered.status != "completed": return
		check(w.society.respond(w, actor, int(offered.facts.request), "accept", 0).reason == "accepted_share", "Many-person consent fixture failed")
	for index: int in range(50, 70): w.society.Contacts.acknowledge(w.society, w, 1, int(actors[index]), 0)
	check(w.society.Contacts.views(w.society, 1).size() == w.society.Contacts.LIMIT, "Acquaintance journal did not remain bounded")
	for index: int in 50: check(w.society.Contacts.known(w.society, 1, int(actors[index])), "Incidental encounters erased an active request contact")
	check(w.institutions.Matters.occupied(w.institutions, w.institutions.matters[matter]) == 50 and Persistence.candidate(Persistence.capture(w), 0) != null, "Many-person accepted requests lost exact allocations or restoration")

func cooldown_capacity_recovers() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	var first: int = 0
	for index: int in 32:
		var matter: int = w.institutions.create_matter(w, 1, delivery_spec(f, 2, 1))
		var result: Dictionary = w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 3, "matter": matter}, 0)
		check(result.status == "completed", "Independent refusal fixture failed")
		if result.status != "completed": return
		var id: int = int(result.facts.request)
		if first == 0: first = id
		w.society.respond(w, 3, id, "refuse", 0)
	var extra: int = w.institutions.create_matter(w, 1, delivery_spec(f, 2, 1))
	check(w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 4, "matter": extra}, 0).reason == "too_many_requests" and w.society.requests.has(first), "Capacity admission erased a still-cooling refusal")
	advance(w, 30001)
	check(w.society.deliver_request(w, 1, {"kind": "offer_matter", "target": 4, "matter": extra}, w.elapsed_ms).status == "completed", "Elapsed refusals permanently blocked fresh work")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Capacity recovery did not restore")

func _run() -> void:
	if "--capacity" in OS.get_cmdline_user_args(): directional_capacity_and_contact_retention()
	elif "--cooldown" in OS.get_cmdline_user_args(): cooldown_capacity_recovers()
	else: offers_revisions_and_aliases()
	print("SOCIETY_BOUNDARIES_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
