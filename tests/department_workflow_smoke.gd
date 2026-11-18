extends "res://tests/production_smoke.gd"
const Departments = preload("res://scripts/sim/kernel/department_rules.gd")

func place_at(w: RefCounted, actor: int, target: int, operation: String) -> bool:
	var slot: int = w.actor_slots[actor]
	var page: RefCounted = w.pages[slot / 256]
	var point: Vector2 = w.facilities.interaction_point(w, target, page.positions[slot % 256], page.radii[slot % 256], false, operation, actor)
	if point.x < 0: check(false, "No fixture work position"); return false
	page.positions[slot % 256] = point
	w.stations.invalidate()
	return true

func ship(w: RefCounted, actor: int, id: int) -> bool:
	var s: Dictionary = w.institutions.shipments[id]
	for operation: String in ["take", "put"]:
		var target: int = int(s.source) if operation == "take" else int(s.destination)
		if not place_at(w, actor, target, operation): return false
		var reason: String = w.begin_transfer(actor, {"kind": operation, "target": target, "item": s.item, "amount": s.amount, "shipment": id, "purpose": "supply"})
		check(reason == "accepted", "Shipment admission refused: " + operation + ":" + reason)
		if reason != "accepted": return false
		w.settle_action(actor, w.elapsed_ms)
		advance(w, w.elapsed_ms + 400)
		check(latest(w, actor).status == "completed" and latest(w, actor).facts.get("amount", 0) > 0, "Shipment did not physically move goods: " + str(latest(w, actor)))
	return s.state == "completed"

func workflow() -> void:
	var w: RefCounted = peaceful()
	var owner: RefCounted = w.institutions
	var org: int = organization(w, [1, 2, 3])
	var root: int = Departments.create(owner, org, "总务")
	var kitchen: int = Departments.create(owner, org, "厨房", root)
	var warehouse: int = Departments.create(owner, org, "仓储", root)
	var store: int = facility(w, "wood_chest", 120, 124, org)
	var stove: int = facility(w, "cook_stove", 125, 124, org)
	var output: int = facility(w, "wood_chest", 129, 124, org)
	if store == 0 or output == 0: return
	Departments.attach(owner, w, warehouse, store)
	Departments.attach(owner, w, kitchen, stove)
	Departments.attach(owner, w, kitchen, output)
	Departments.assign(owner, warehouse, 2, ["haul"], [], true)
	Departments.assign(owner, warehouse, 3, ["haul"], [], true)
	Departments.assign(owner, kitchen, 1, ["produce"], [], true)
	Departments.assign(owner, kitchen, 3, ["haul"], [], true)
	Departments.grant(owner, root, 1, "自定义负责人", Array(Departments.CAPABILITIES), true)
	w.objects.add(store, "grain", 2, Stock.right(0, org))
	w.objects.add(store, "water", 1, Stock.right(0, org))
	check(owner.management(w, 1, {"department": kitchen, "op": "order", "operation": "cook", "item": "meal", "total": 1}) == "management_updated", "Order creation refused")
	var order: int = owner.next_matter - 1
	check(owner.management(w, 1, {"department": kitchen, "op": "configure", "facility": stove, "order": order}) == "management_updated", "Workshop configuration refused")
	for item: String in ["grain", "water"]:
		var amount: int = 2 if item == "grain" else 1
		var request: int = owner.Logistics.request(owner, w, kitchen, warehouse, stove, item, amount)
		check(request > 0 and owner.Logistics.accept(owner, w, warehouse, request), "Supply request did not accept")
		var offer: Dictionary = {"department": warehouse, "source": store, "target": stove, "item": item, "amount": amount, "request": request}
		var id: int = owner.Logistics.claim(owner, w, 2, offer)
		check(id > 0 and owner.Logistics.claim(owner, w, 3, offer) == 0, "Last source/capacity was claimed twice")
		if id <= 0: return
		check(w.objects.available_amount(store, item, Stock.right(0, org)) == 0 and not w.objects.consume(store, {item: 1}, Stock.right(0, org)), "External consumption stole shipment reservation")
		check(Persistence.candidate(Persistence.capture(w), 0) != null, "Reserved shipment did not restore")
		check(ship(w, 2, id), "Take/put did not close shipment")
		check(owner.supply_requests[request].received == amount and owner.supply_requests[request].state == "completed", "Request credited before delivery or failed physical receipt")
		check(Persistence.candidate(Persistence.capture(w), 0) != null, "Delivered shipment did not restore")
	check(owner.matters[order].fulfilled == 0, "Delivery counted as production")
	Growth.seed(w.objects.records[1], "cooking", 0)
	if not start(w, 1, "cook", stove): return
	check(owner._order_wip.get(order) == 3 and not owner.Orders.open(owner, order), "WIP did not guard last batch")
	advance(w, w.elapsed_ms + 3200)
	check(owner.matters[order].fulfilled == 3 and owner.matters[order].state == "completed" and w.objects.amount(stove, "meal") == 3, "Rounded whole batch failed unique target credit")
	var offer: Dictionary = {"department": kitchen, "source": stove, "target": output, "item": "meal", "amount": 3}
	var shipment: int = owner.Logistics.claim(owner, w, 3, offer)
	check(shipment > 0 and ship(w, 3, shipment), "Finished goods did not enter real output store")
	check(owner.matters[order].fulfilled == 3 and Persistence.candidate(Persistence.capture(w), 0) != null, "Output haul duplicated credit or failed restore")
	w.objects.add(stove, "grain", 2, Stock.right(0, org)); w.objects.add(stove, "water", 1, Stock.right(0, org))
	var leftovers: Array = owner.Workflow.offers(owner, w, kitchen).filter(func(value: Dictionary): return value.kind == "transport" and value.source == stove and value.item == "grain")
	check(not leftovers.is_empty() and owner.Workflow.transport_amount(owner, w, leftovers[0]) == 2, "Closed production target stranded unused ingredients on its workshop")
	var next_order: int = owner.Orders.create(owner, w, 1, kitchen, "cook", "meal", 6)
	check(owner.management(w, 1, {"department": kitchen, "op": "configure", "facility": stove, "order": next_order}) == "management_updated", "Next production binding failed")
	if not start(w, 1, "cook", stove): return
	w.objects.add(stove, "grain", 1, Stock.right(0, org))
	var outgoing: Array = owner.Workflow.offers(owner, w, kitchen)
	check(not outgoing.any(func(value: Dictionary): return value.kind == "transport" and value.source == stove and value.item == "grain"), "Active production need bounced spare ingredients back into storage")

func _run() -> void:
	workflow()
	print("DEPARTMENT_WORKFLOW_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
