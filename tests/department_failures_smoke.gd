extends "res://tests/department_workflow_smoke.gd"
## Permission, interruption and restoration counterexamples for the same owners.

func setup_work() -> Dictionary:
	var w: RefCounted = peaceful()
	clear_private(w, 2, "grain"); clear_private(w, 2, "water")
	var o: RefCounted = w.institutions
	var org: int = organization(w, [1, 2, 3])
	var root: int = Departments.create(o, org, "总务")
	var kitchen: int = Departments.create(o, org, "厨房", root)
	var supply: int = Departments.create(o, org, "仓务", root)
	var store: int = facility(w, "wood_chest", 118, 124, org)
	var stove: int = facility(w, "cook_stove", 124, 124, org)
	var other: int = facility(w, "cook_stove", 130, 124, org)
	Departments.attach(o, w, supply, store)
	Departments.attach(o, w, kitchen, stove); Departments.attach(o, w, kitchen, other)
	o.departments[kitchen].groups = {"甲组": {"facilities": [stove]}, "乙组": {"facilities": [other]}}
	Departments.assign(o, kitchen, 1, ["produce"], [], true)
	Departments.assign(o, supply, 2, ["haul"], [], true)
	Departments.assign(o, supply, 3, ["haul"], [], true)
	Departments.grant(o, root, 1, "任意上级", Array(Departments.CAPABILITIES), true)
	return {"w": w, "o": o, "org": org, "root": root, "kitchen": kitchen, "supply": supply, "store": store, "stove": stove, "other": other}

func saveable(w: RefCounted, label: String) -> void:
	var candidate: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(candidate != null, label + ": legal state did not restore")
	if candidate != null: candidate.deferred.close()

func supply_claim(f: Dictionary, item: String = "grain", amount: int = 2, actor: int = 2) -> int:
	f.w.objects.add(f.store, item, amount, Stock.right(0, f.org))
	var request: int = f.o.Logistics.request(f.o, f.w, f.kitchen, f.supply, f.stove, item, amount)
	check(f.o.Logistics.accept(f.o, f.w, f.supply, request), "Fixture request refused")
	return f.o.Logistics.claim(f.o, f.w, actor, {"department": f.supply, "source": f.store, "target": f.stove, "item": item, "amount": amount, "request": request})

func take_shipment(f: Dictionary, id: int, actor: int = 2) -> void:
	var s: Dictionary = f.o.shipments[id]
	if not place_at(f.w, actor, f.store, "take"): return
	check(f.w.begin_transfer(actor, {"kind": "take", "target": f.store, "item": s.item, "amount": s.amount, "shipment": id, "purpose": "supply"}) == "accepted", "Take shipment refused")
	f.w.settle_action(actor, f.w.elapsed_ms)
	advance(f.w, f.w.elapsed_ms + 400)
	check(s.state == "carrying", "Actual take failed to retain transport obligation")

func permissions_and_scopes() -> void:
	var f: Dictionary = setup_work(); var o: RefCounted = f.o; var w: RefCounted = f.w
	var order: int = o.Orders.create(o, w, 1, f.kitchen, "cook", "meal", 10)
	var child: int = o.Orders.create(o, w, 1, f.kitchen, "cook", "meal", 4, "乙组", order)
	Departments.grant(o, f.kitchen, 2, "自定义甲组长", ["people", "production", "supply", "delegate"], false, "甲组", 1)
	Departments.grant(o, f.kitchen, 3, "乙组成员", ["view"], false, "乙组", 1)
	var attempts: Array = [
		{"op": "configure", "facility": f.other, "order": child},
		{"op": "order_control", "order": order, "mode": "cancel"},
		{"op": "supplier", "supplier": f.supply},
		{"op": "storage", "facility": f.other, "items": []},
		{"op": "request_supply", "target": f.other, "item": "grain", "amount": 2, "supplier": f.supply},
		{"op": "assign", "worker": 3, "duties": ["produce"], "groups": ["甲组"]},
		{"op": "grant", "worker": 3, "capabilities": ["view"], "title": "越界"},
		{"op": "batch", "facility": f.other, "process": 1, "mode": "cancel"},
		{"op": "coordinator", "worker": 2}]
	for command: Dictionary in attempts:
		var before: Dictionary = o.departments[f.kitchen].duplicate(true)
		command.merge({"department": f.kitchen, "group": "甲组"})
		check(o.management(w, 2, command) == "not_authorized" and before == o.departments[f.kitchen], "Group command escaped scope: " + str(command.op))
	check(o.management(w, 2, {"op": "member", "department": f.kitchen, "group": "甲组", "worker": 4, "enabled": true}) == "invalid_worker", "A nonmember entered a work group")
	Departments.assign(o, f.kitchen, 3, ["produce"], ["甲组"])
	check(Departments.labor_allowed(o, 3, f.stove, "produce") and not Departments.labor_allowed(o, 3, f.other, "produce"), "Actor/duty target index crossed groups")
	Departments.assign(o, f.kitchen, 3, ["produce"], [], false)
	check(not Departments.labor_allowed(o, 3, f.stove, "produce"), "Empty group silently became department-wide")
	check(w.begin_interaction(2, {"kind": "cook", "target": f.stove}) == "not_authorized", "Legacy broad organization rights bypassed production work assignment")
	check(o.management(w, 1, {"op": "grant", "department": f.kitchen, "worker": 2, "capabilities": ["view", "delegate"], "title": "任意名"}) == "management_updated", "Superior could not replace own delegated authority")
	check(o.management(w, 2, {"op": "grant", "department": f.root, "worker": 1, "capabilities": [], "title": "夺权"}) == "not_authorized", "Subordinate revoked superior")
	check(o.management(w, 1, {"op": "assign", "department": f.kitchen, "worker": 3, "duties": ["produce"], "department_wide": "yes"}) == "invalid_configuration", "Malformed explicit work range was adopted")
	saveable(w, "Group permissions")
	var bad: Dictionary = Persistence.capture(w)
	bad.domains.institutions.departments[f.kitchen].production[f.stove] = {"operation": "cook", "order": child}
	check(Persistence.candidate(bad, 0) == null, "Cross-group production binding restored")
	w.deferred.close()

func transport_interruptions() -> void:
	var f: Dictionary = setup_work(); var w: RefCounted = f.w; var o: RefCounted = f.o
	var id: int = supply_claim(f)
	check(id > 0, "Initial transport claim failed")
	if id <= 0: return
	check(w.begin_transfer(2, {"kind": "take", "target": f.store, "item": "grain", "amount": 2, "shipment": id, "purpose": "supply"}) == "accepted", "Reserved approach failed")
	w.end_run(2, w.elapsed_ms, "preempted"); w.clear_navigation(2)
	check(o.shipments[id].state == "cancelled" and w.objects.available_amount(f.store, "grain") == 2 and w.objects.reserved_capacity(f.stove) == 0, "Interrupted approach kept source/space locked")
	saveable(w, "Cancelled before take")
	id = o.Logistics.claim(o, w, 2, {"department": f.supply, "source": f.store, "target": f.stove, "item": "grain", "amount": 2, "request": o.next_supply_request - 1})
	take_shipment(f, id); saveable(w, "Carrying")
	var captured: Dictionary = Persistence.capture(w)
	captured.domains.institutions.shipments[id].amount += 1
	check(Persistence.candidate(captured, 0) == null, "Invented in-transit goods restored")
	# Generic custody cannot divert an active transport bundle.
	check(w.institutions.move_goods(w, 2, f.store, "grain", 2, "put", {}, w.elapsed_ms).status == "refused", "Generic return stole active shipment")
	w.objects.records[f.store].capacity = 0
	o.Logistics.cancel_request(o, w, o.next_supply_request - 1)
	var s: Dictionary = o.shipments[id]
	check(s.state == "returning" and s.destination != f.store and w.objects.records[s.destination].kind == "pile", "Full source failed to route a physical return")
	saveable(w, "Returning to physical pile")
	check(place_at(w, 2, s.destination, "put"), "No return position")
	check(w.begin_transfer(2, {"kind": "put", "target": s.destination, "item": s.item, "amount": s.amount, "shipment": id, "purpose": "supply"}) == "accepted", "Physical return refused")
	w.settle_action(2, w.elapsed_ms); advance(w, w.elapsed_ms + 400)
	check(s.state == "completed" and w.objects.amount(s.destination, "grain", Stock.right(0, f.org)) == 2 and o.Logistics.current(o, 2).is_empty(), "Return lost goods or kept carrier locked")
	saveable(w, "Returned")
	w.deferred.close()

func player_shipment_view() -> void:
	var f: Dictionary = setup_work()
	var w: RefCounted = f.w
	var owner: RefCounted = f.o
	check(Departments.assign(owner, f.supply, 1, ["haul"], [], true), "Player transport duty was not assigned")
	var own: int = w.objects.amount(1, "grain", Stock.right(1))
	var id: int = supply_claim(f, "grain", 3, 1)
	check(id > 0 and not w.describe(1).has("carried_shipment"), "A reservation appeared as physically carried goods")
	if id <= 0: w.deferred.close(); return
	take_shipment(f, id, 1)
	var view: Dictionary = w.describe(1)
	var subject: Dictionary = view.get("carried_shipment", {})
	check(subject.get("item") == "grain" and subject.get("count") == 3 and view.inventory.grain == own + 3, "Carrying view lost or duplicated the owned and shipped quantities")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Player carrying state could not restore")
	if restored != null:
		check(restored.describe(1).get("carried_shipment") == subject, "Restore changed the carrying view")
		restored.deferred.close()
	owner.Logistics.cancel_request(owner, w, int(owner.shipments[id].request))
	var returning: Dictionary = w.describe(1).get("carried_shipment", {})
	check(returning.get("state") == "returning" and returning.get("count") == 3, "Cancelling the request hid the goods on the return trip")
	var destination: int = int(owner.shipments[id].destination)
	if place_at(w, 1, destination, "put"):
		check(w.begin_transfer(1, {"kind": "put", "target": destination, "item": "grain", "amount": 3, "shipment": id, "purpose": "supply"}) == "accepted", "Player return was refused")
		w.settle_action(1, w.elapsed_ms)
		advance(w, w.elapsed_ms + 400)
		check(not w.describe(1).has("carried_shipment") and w.objects.amount(1, "grain") == own, "Return left cargo behind or used personal goods")
	w.deferred.close()

func transport_deaths_and_removal() -> void:
	for stage: String in ["reserved", "carrying", "returning"]:
		var f: Dictionary = setup_work(); var id: int = supply_claim(f)
		if id <= 0: check(false, "Death fixture claim refused"); continue
		if stage != "reserved": take_shipment(f, id)
		var abandoned: int = 0
		if stage == "returning":
			f.w.objects.records[f.store].capacity = 0
			f.o.Logistics.cancel(f.o, f.w, id)
			abandoned = int(f.o.shipments[id].destination)
		var before: int = f.w.objects.audit_total("grain")
		f.w.kill(2)
		check(f.o.Logistics.current(f.o, 2).is_empty() and f.w.objects.reserved_capacity(f.stove) == 0 and f.w.objects.audit_total("grain") == before, "Death erased goods or retained transport locks: " + stage)
		if abandoned > 0: check(not f.w.objects.records.has(abandoned), "Dead carrier left an empty generated handover site in departmental assets")
		saveable(f.w, "Death " + stage)
		f.w.deferred.close()
	var f: Dictionary = setup_work(); var id: int = supply_claim(f)
	take_shipment(f, id)
	check(f.w.remove_static(f.stove), "Fixture empty destination could not be removed")
	check(f.o.shipments[id].state == "returning" and f.o.shipments[id].destination != f.stove, "Removed destination stayed on a return")
	saveable(f.w, "Removed destination")
	f.w.deferred.close()
	f = setup_work(); id = supply_claim(f); take_shipment(f, id)
	var total: int = f.w.objects.audit_total("grain")
	check(f.w.remove_actor(2) and f.o.Logistics.current(f.o, 2).is_empty() and f.w.objects.audit_total("grain") == total, "Removed carrier lost goods or retained reservation")
	saveable(f.w, "Removed historical carrier")
	f.w.deferred.close()

func in_transit_is_not_ready() -> void:
	var f: Dictionary = setup_work()
	var order: int = f.o.Orders.create(f.o, f.w, 1, f.kitchen, "cook", "meal", 3)
	f.o.departments[f.kitchen].production[f.stove] = {"operation": "cook", "order": order}
	supply_claim(f, "grain", 2)
	# The second item has its own carrier, sharing the finite destination room.
	f.w.objects.add(f.store, "water", 1, Stock.right(0, f.org))
	var request: int = f.o.Logistics.request(f.o, f.w, f.kitchen, f.supply, f.stove, "water", 1)
	f.o.Logistics.accept(f.o, f.w, f.supply, request)
	f.o.Logistics.claim(f.o, f.w, 3, {"department": f.supply, "source": f.store, "target": f.stove, "item": "water", "amount": 1, "request": request})
	var offers: Array = f.o.Workflow.offers(f.o, f.w, f.kitchen)
	check(not offers.any(func(offer: Dictionary): return offer.kind == "produce"), "In-transit material advertised an empty workshop as ready")
	f.w.deferred.close()

func loose_goods_and_manual_policy() -> void:
	var f: Dictionary = setup_work(); var w: RefCounted = f.w; var o: RefCounted = f.o
	Departments.assign(o, f.kitchen, 3, ["haul"], [], true)
	var output: int = facility(w, "wood_chest", 133, 124, f.org)
	Departments.attach(o, w, f.kitchen, output)
	var pile: int = w.objects.create("pile", "grain", w.Terrain.index(Vector2i(126, 127)))
	w.objects.records[pile].organization = f.org
	w.objects.add(pile, "grain", 4, Stock.right(0, f.org))
	Departments.attach(o, w, f.kitchen, pile)
	var order: int = o.Orders.create(o, w, 1, f.kitchen, "cook", "meal", 3)
	o.departments[f.kitchen].production[f.stove] = {"operation": "cook", "order": order}
	var offers: Array = o.Workflow.offers(o, w, f.kitchen)
	check(offers.any(func(offer: Dictionary): return offer.kind == "transport" and offer.source == pile and offer.target == f.stove) and offers.any(func(offer: Dictionary): return offer.kind == "transport" and offer.source == pile and offer.target == output), "Designated public loose goods cannot supply workshop or enter storage")
	var recovery: Dictionary = offers.filter(func(offer: Dictionary): return offer.kind == "transport" and offer.source == pile and offer.target == output)[0]
	check(o.Workflow.transport_amount(o, w, recovery) == 4, "Loose-goods recovery could not be revalidated locally")
	var shipment: int = o.Logistics.claim(o, w, 3, recovery)
	check(shipment > 0 and ship(w, 3, shipment) and not w.objects.records.has(pile) and w.objects.amount(output, "grain", Stock.right(0, f.org)) == 4, "Loose-goods recovery did not physically transfer or remove empty source")
	check(pile not in o.departments[f.kitchen].facilities, "Empty loose source retained departmental asset reference")
	# A manual pickup cannot evade a source's selected workshop by declaring
	# a different use or by depositing the same public batch elsewhere.
	w.objects.add(f.store, "grain", 2, Stock.right(0, f.org))
	w.objects.records[f.store]["storage_policy"] = {"items": [], "min_tier": 1, "max_tier": 99, "destinations": [f.stove]}
	check(o.move_goods(w, 2, f.store, "grain", 1, "take", {"purpose": "cook"}, w.elapsed_ms).reason == "supply_destination_required", "Manual issue bypassed source destinations by changing declared purpose")
	check(o.move_goods(w, 2, f.store, "grain", 1, "take", {"purpose": "supply"}, w.elapsed_ms).status == "completed", "Manual authorized supply pickup refused")
	check(o.move_goods(w, 2, f.other, "grain", 1, "put", {"purpose": "supply"}, w.elapsed_ms).reason == "supply_destination_required", "Manual put bypassed selected supply destination")
	check(o.move_goods(w, 2, f.stove, "grain", 1, "put", {"purpose": "supply"}, w.elapsed_ms).status == "completed", "Manual permitted supply delivery refused")
	saveable(w, "Loose recovery and manual policy")
	w.deferred.close()

func final_review_lifecycles() -> void:
	var f: Dictionary = setup_work(); var w: RefCounted = f.w; var o: RefCounted = f.o
	var id: int = supply_claim(f); take_shipment(f, id)
	var s: Dictionary = o.shipments[id]
	var before: int = w.objects.audit_total("grain")
	var outcome: Dictionary = w.command({"kind": "drop", "actor": 2, "item": "grain", "amount": 2})
	check(not outcome.ok and outcome.reason == "entrusted_goods_cannot_be_dropped" and w.objects.amount(2, "grain", Stock.right(0, f.org, s.entrust)) == 2, "Drop tore goods out of a live shipment")
	check(o.Workflow.adopt(o, w, 2, {"kind": "shipment", "department": f.supply, "shipment": id, "target": s.destination}) == "accepted", "Carrier could not begin delivery before cancellation")
	o.Logistics.cancel_request(o, w, int(s.request))
	check(s.state == "returning" and not w.actions.has(2) and w.pages[0].positions[1] == w.pages[0].targets[1], "Request cancellation kept obsolete destination movement")
	var second: int = facility(w, "wood_chest", 132, 128, f.org)
	Departments.attach(o, w, f.supply, second)
	o.Logistics.blocked(o, w, id, "path_failed")
	check(w.objects.records[int(s.destination)].kind == "pile" and w.objects.records[int(s.destination)].tile == w.Terrain.index(Vector2i(w.combat.position(w, 2))), "Unreachable return kept alternating warehouse destinations")
	var fallback: int = int(s.destination)
	var objects: int = w.objects.records.size()
	o.Logistics.blocked(o, w, id, "path_failed")
	check(int(s.destination) == fallback and w.objects.records.size() == objects, "Repeated return failure multiplied empty physical handover sites")
	# Only the outstanding return leg remains; do not take the same shipment again.
	if place_at(w, 2, int(s.destination), "put"):
		check(w.begin_transfer(2, {"kind": "put", "target": int(s.destination), "item": s.item, "amount": s.amount, "shipment": id, "purpose": "supply"}) == "accepted", "Physical fallback handover refused")
		w.settle_action(2, w.elapsed_ms); advance(w, w.elapsed_ms + 400)
	check(s.state == "completed" and w.objects.audit_total("grain") == before, "Return fallback did not close actual custody")
	saveable(w, "Final review transport lifecycle")
	Departments.grant(o, f.root, 2, "中间管事", ["delegate", "view"], true, "", 1)
	check(o.management(w, 2, {"department": f.kitchen, "op": "grant", "worker": 3, "capabilities": ["view"], "title": "下属"}) == "management_updated", "Intermediate delegation failed")
	check(o.management(w, 1, {"department": f.root, "op": "grant", "worker": 2, "capabilities": [], "descendants": false, "title": "撤职"}) == "management_updated", "Top administrator could not revoke intermediate delegate")
	check(o.management(w, 1, {"department": f.kitchen, "op": "grant", "worker": 3, "capabilities": [], "title": "撤回"}) == "management_updated", "Revoked issuer hid superior's downstream revocation rights")
	w.deferred.close()

func daily_allocations() -> void:
	var f: Dictionary = setup_work(); var w: RefCounted = f.w; var o: RefCounted = f.o
	var parent: int = o.Orders.create(o, w, 1, f.kitchen, "cook", "meal", 10, "", 0, true)
	var abandoned: int = o.Orders.create(o, w, 1, f.kitchen, "cook", "meal", 10, "甲组", parent)
	o.matters[abandoned].state = "cancelled"
	var child: int = o.Orders.create(o, w, 1, f.kitchen, "cook", "meal", 6, "甲组", parent)
	var paused: int = o.Orders.create(o, w, 1, f.kitchen, "cook", "meal", 4, "乙组", parent)
	o.matters[paused].paused = true
	check(child > 0 and paused > 0 and not o.Orders.open(o, parent) and o.Orders.open(o, child), "Parent double-assigned its group allocations or blocked a valid group")
	o.departments[f.kitchen].production[f.stove] = {"operation": "cook", "order": child}
	o.departments[f.kitchen].production[f.other] = {"operation": "cook", "order": paused}
	w.objects.add(f.stove, "grain", 2, Stock.right(0, f.org)); w.objects.add(f.stove, "water", 1, Stock.right(0, f.org))
	Growth.seed(w.objects.records[1], "cooking", 0)
	if not start(w, 1, "cook", f.stove): return
	advance(w, 1000); w.end_run(1, w.elapsed_ms, "preempted"); w.clear_navigation(1)
	w.elapsed_ms = o.Orders.DAY_MS # Boundary fixture, not a normal-autonomy/performance result.
	var next: int = o.Orders.rollover(o, w, parent, w.elapsed_ms)
	var next_child: int = int(o.departments[f.kitchen].production[f.stove].order)
	var next_paused: int = int(o.departments[f.kitchen].production[f.other].order)
	check(next > 0 and next_child > child and next_paused > paused and o.matters[next_paused].paused, "Rollover revived a cancelled allocation, lost a valid binding or dropped pause")
	check(w.objects.records[f.stove].process.order == parent and o.matters[parent].state == "expired", "Rollover reassigned an already-started batch")
	advance(w, w.elapsed_ms + 50) # Bring derived slice clocks to the synthetic boundary.
	w.facilities.Sources.pulse(w, w.elapsed_ms)
	saveable(w, "Old work across daily rollover")
	if not start(w, 1, "cook", f.stove): return
	advance(w, w.elapsed_ms + 2500)
	check(o.matters[parent].fulfilled == 3 and o.matters[parent].state == "expired" and o.matters[next].fulfilled == 0 and o.matters[child].fulfilled == 3, "Late old batch credited next day or revived its expired objective")
	saveable(w, "Late production credit")
	var bad: Dictionary = Persistence.capture(w)
	bad.domains.institutions.matters[next_child].total = 100; bad.domains.institutions.matters[next_child].quota = 100
	check(Persistence.candidate(bad, 0) == null, "Over-allocated group quota restored")
	bad = Persistence.capture(w)
	bad.domains.institutions.matters[next].state = "cancelled"
	check(Persistence.candidate(bad, 0) == null, "Cancelled order retained a renewable daily credential")
	w.deferred.close()

func rollover_capacity_retry() -> void:
	var f: Dictionary = setup_work(); var w: RefCounted = f.w; var o: RefCounted = f.o
	var parent: int = o.Orders.create(o, w, 1, f.kitchen, "cook", "meal", 10, "", 0, true)
	var child: int = o.Orders.create(o, w, 1, f.kitchen, "cook", "meal", 10, "甲组", parent)
	o.departments[f.kitchen].production[f.stove] = {"operation": "cook", "order": child}
	var unrelated: Array = []
	while o.matters.size() < o.Matters.MATTER_LIMIT:
		var added: int = o.Orders.create(o, w, 1, f.kitchen, "cook", "meal", 1)
		if added == 0: check(false, "Could not fill matter capacity fixture"); break
		unrelated.append(added)
	o.matters.erase(unrelated.pop_back()); o._orders_dirty = true # Root alone would fit; its child would not.
	w.elapsed_ms = o.Orders.DAY_MS
	var serial: int = o.next_matter
	check(o.Orders.rollover(o, w, parent, w.elapsed_ms) == 0 and o.next_matter == serial, "Rollover partially minted a day without room for its allocations")
	check(o.matters[parent].state == "expired" and o.matters[child].state == "expired" and o.matters[parent].repeat and o.matters[parent].next_cycle_ms == w.elapsed_ms + 1000, "Failed rollover kept old-period work active or lost its retry")
	o.matters.erase(unrelated.pop_back()); o._orders_dirty = true
	w.elapsed_ms += 1000
	var next: int = o.Orders.rollover(o, w, parent, w.elapsed_ms)
	var next_child: int = int(o.departments[f.kitchen].production[f.stove].order)
	check(next > 0 and next_child != child and o.matters[next_child].parent_order == next and not o.matters[parent].repeat, "Capacity recovery lost a group's next-day configuration")
	advance(w, w.elapsed_ms + 50)
	w.facilities.Sources.pulse(w, w.elapsed_ms)
	saveable(w, "Rollover capacity recovery")
	w.deferred.close()

func removal_during_pickup() -> void:
	var f: Dictionary = setup_work(); var w: RefCounted = f.w; var o: RefCounted = f.o
	var id: int = supply_claim(f)
	check(o.Workflow.adopt(o, w, 2, {"kind": "shipment", "department": f.supply, "shipment": id, "target": f.store}) == "accepted" and w.actions.get(2, {}).get("target") == f.store, "Pickup approach fixture did not start")
	check(w.remove_static(f.stove), "Could not remove idle destination during pickup approach")
	check(o.shipments[id].state == "cancelled" and not w.actions.has(2) and w.pages[0].positions[1] == w.pages[0].targets[1] and w.objects.amount(f.store, "grain") == 2, "Removed delivery target left its cancelled pickup still walking")
	saveable(w, "Destination removed before pickup")
	w.deferred.close()

func return_prefers_whole_batch_room() -> void:
	var f: Dictionary = setup_work(); var w: RefCounted = f.w; var o: RefCounted = f.o
	var second: int = facility(w, "wood_chest", 132, 128, f.org)
	Departments.attach(o, w, f.supply, second)
	var id: int = supply_claim(f); take_shipment(f, id)
	w.objects.records[f.store].capacity = 1
	o.Logistics.cancel_request(o, w, int(o.shipments[id].request))
	check(o.shipments[id].destination == second, "Return ignored a store able to receive the whole outstanding batch")
	saveable(w, "Whole-batch return destination")
	w.deferred.close()

func rollover_compaction_headroom() -> void:
	var f: Dictionary = setup_work(); var w: RefCounted = f.w; var o: RefCounted = f.o
	var parent: int = o.Orders.create(o, w, 1, f.kitchen, "cook", "meal", 17, "", 0, true)
	var children: Array = []
	for index: int in 17:
		var group: String = "轮换组%d" % index
		o.departments[f.kitchen].groups[group] = {"facilities": [f.stove]}
		children.append(o.Orders.create(o, w, 1, f.kitchen, "cook", "meal", 1, group, parent))
	while o.matters.size() < o.Matters.MATTER_LIMIT - 17:
		var id: int = o.Orders.create(o, w, 1, f.kitchen, "cook", "meal", 1)
		if id == 0: check(false, "History fixture exhausted unexpectedly"); break
		o.matters[id].state = "cancelled"
	w.elapsed_ms = o.Orders.DAY_MS * 3
	var next: int = o.Orders.rollover(o, w, parent, w.elapsed_ms)
	check(next > 0, "Seventeen allocations could not use reclaimable historical capacity")
	var renewed: int = 0
	for m: Dictionary in o.Orders.list(o, f.kitchen):
		if m.parent_order == next: renewed += 1
	for id: int in children: check(o.matters.has(id), "Compaction erased an unbound allocation while its family was waiting to renew")
	check(renewed == 17, "Rollover compaction dropped unbound group allocations")
	advance(w, w.elapsed_ms + 50); w.facilities.Sources.pulse(w, w.elapsed_ms)
	saveable(w, "Compacted successor family")
	w.deferred.close()

func _run() -> void:
	permissions_and_scopes()
	transport_interruptions()
	player_shipment_view()
	transport_deaths_and_removal()
	in_transit_is_not_ready()
	loose_goods_and_manual_policy()
	final_review_lifecycles()
	daily_allocations()
	rollover_capacity_retry()
	removal_during_pickup()
	return_prefers_whole_batch_room()
	rollover_compaction_headroom()
	print("DEPARTMENT_FAILURES_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
