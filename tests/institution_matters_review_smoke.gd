extends "res://tests/institution_matters_smoke.gd"

func scoped_issue_and_normative_input() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	w.objects.add(f.source, "grain", 4, Stock.right(0, f.org))
	var delivery: int = w.institutions.create_matter(w, 1, delivery_spec(f, 4, 4))
	var produce: int = w.institutions.create_matter(w, 1, {"kind": "produce", "organization": f.org, "target": f.stove, "operation": "cook", "item": "meal", "total": 3, "quota": 3})
	var share: int = w.institutions.accept_share(w, 3, delivery)
	check(share > 0 and w.institutions.accept_share(w, 3, produce) > 0, "Separate scoped duties could not be accepted")
	var request: Dictionary = {"kind": "take", "target": int(f.source), "item": "grain", "amount": 2, "purpose": "cook"}
	check(w.execute_operation(3, request) == "not_authorized" and w.institutions.move_goods(w, 3, f.source, "grain", 2, "take", request, 0).reason == "not_authorized" and w.objects.amount(f.source, "grain") == 4, "Permission to cook elsewhere authorized taking cooking materials at a supply-only store")
	check(w.institutions.create_matter(w, 1, {"kind": "operation", "organization": f.org, "target": f.stove, "operation": "cook"}) == 0, "Recipe production bypassed its output ownership contract as a generic operation")
	check(w.execute_operation(1, {"kind": "offer_matter", "target": 4, "matter": delivery, "quota": -1}) == "invalid_matter_offer" and w.gate.current(1).is_empty(), "Invalid offer entered a host which could not be restored")
	var data: Dictionary = Persistence.capture(w)
	data.domains.institutions.shares[share].actor = f.source
	check(Persistence.candidate(data, 0) == null, "An extant store could hold a personal accepted share")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Valid scoped responsibilities no longer restore")
	manual_transfer(w, 3, f.source, "grain", 1, "take", {"purpose": "supply"})
	manual_transfer(w, 3, f.destination, "grain", 1, "put")
	check(w.institutions.release_share(w, 3, share) and w.institutions.revise_matter(w, 1, delivery, 2, 1, 0) and w.institutions.shares[share].quota == 4 and Persistence.candidate(Persistence.capture(w), 0) != null, "Downsizing a matter invalidated its released historical quota")

func known_full_and_gone_sites() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	w.objects.add(f.source, "grain", 2, Stock.right(0, f.org))
	w.objects.records[f.destination].capacity = 1
	w.objects.add(f.destination, "wood", 1, Stock.right(0, f.org))
	resident(w, 3, [f.source, f.destination])
	var matter: int = w.institutions.create_matter(w, 1, delivery_spec(f, 2, 2))
	check(w.institutions.accept_share(w, 3, matter) > 0, "Full destination fixture did not retain its obligation")
	w.decisions.prepare(w, 0); advance(w, 2500)
	check(w.objects.amount(f.source, "grain") == 2 and w.objects.amount(3, "grain") == 0, "Known-full destination caused unnecessary material withdrawal")
	f = commission_fixture(); w = f.world
	w.objects.add(f.source, "grain", 2, Stock.right(0, f.org))
	resident(w, 3, [f.source, f.stove])
	matter = w.institutions.create_matter(w, 1, {"kind": "produce", "organization": f.org, "target": f.stove, "operation": "cook", "item": "meal", "sources": [f.source], "total": 3, "quota": 3})
	var share: int = w.institutions.accept_share(w, 3, matter)
	w.decisions.prepare(w, 0)
	while w.objects.amount(3, "grain") == 0 and w.elapsed_ms < 3500: advance(w, w.elapsed_ms + 100)
	check(w.objects.amount(3, "grain") == 2, "Production fixture did not really fetch its first prerequisite")
	w.release(3)
	var site: int = w.objects.records[f.stove].tile
	check(w.remove_static(f.stove, w.elapsed_ms), "Empty worksite could not be removed")
	move_actor(w, 3, w.Terrain.center(site))
	w.knowledge.refresh(w, 3, f.stove, w.elapsed_ms, true)
	w.decisions.resume(w, 3, w.elapsed_ms); advance(w, w.elapsed_ms + 7000)
	check(w.objects.amount(3, "grain") == 0 and w.objects.amount(f.source, "grain") == 2 and w.institutions.shares[share].state == "accepted", "Known-gone worksite retained unusable materials or silently cancelled its responsibility")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "A responsibility with a historical removed site failed restore")

func wrong_source_materials_return_before_more_issue() -> void:
	var f: Dictionary = commission_fixture()
	var w: RefCounted = f.world
	var other: int = workshop(w, f.org, "wood_chest", Vector2i(123, 122))
	w.flush_topology()
	w.objects.add(other, "grain", 1, Stock.right(0, f.org)); w.objects.add(f.source, "grain", 2, Stock.right(0, f.org))
	w.institutions.admit(w, f.org, 3, Array(w.institutions.PURPOSES))
	manual_transfer(w, 3, other, "grain", 1, "take", {"purpose": "supply"})
	w.institutions.admit(w, f.org, 3, [])
	resident(w, 3, [other, f.source, f.destination])
	var matter: int = w.institutions.create_matter(w, 1, delivery_spec(f, 2, 2))
	var share: int = w.institutions.accept_share(w, 3, matter)
	w.decisions.prepare(w, w.elapsed_ms); advance(w, w.elapsed_ms + 10000)
	check(w.institutions.shares[share].fulfilled == 2 and w.objects.amount(f.destination, "grain") == 2 and w.objects.amount(3, "grain") == 0 and w.institutions.returns(w, 3).is_empty(), "Supply retention kept an irrelevant origin instead of returning it and fulfilling the actual source-scoped share")
	check(w.objects.amount(f.source, "grain") + w.objects.amount(other, "grain") == 1 and Persistence.candidate(Persistence.capture(w), 0) != null, "Source-scoped handoff duplicated or lost goods")

func _run() -> void:
	scoped_issue_and_normative_input()
	known_full_and_gone_sites()
	wrong_source_materials_return_before_more_issue()
	print("INSTITUTION_MATTERS_REVIEW_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
