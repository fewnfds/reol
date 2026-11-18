extends RefCounted
## Sparse departmental coordination. Actual work stays on Operations/ActionGate.
const State = preload("res://scripts/sim/kernel/state.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")

static func dirty(owner: RefCounted, department: int) -> void:
	if department > 0 and owner.departments.has(department) and not owner._work_dirty.has(department): owner._work_dirty[department] = true

static func stock_changed(owner: RefCounted, target: int) -> void:
	owner.Departments.ensure(owner)
	dirty(owner, int(owner._facility_department.get(target, 0)))
	owner.Logistics.ensure(owner)
	for id: int in owner._shipments_by_source.get(target, []): dirty(owner, int(owner.shipments[id].department))
	for id: int in owner._shipments_by_target.get(target, []): dirty(owner, int(owner.shipments[id].department))

static func rebuild(owner: RefCounted, world: RefCounted) -> void:
	owner._work_dirty.clear(); owner._work_offers.clear()
	owner._work_retry.clear(); owner._work_cursor.clear()
	owner._order_wip.clear(); owner._process_due.clear()
	for record: Dictionary in world.objects.records.values():
		if record.has("process"):
			owner.Orders.reserve(owner, record.process)
			process_due(owner, int(record.id), record.process)
	for id: int in owner.departments: dirty(owner, id)
	rebuild_due(owner)

static func process_due(owner: RefCounted, target: int, process: Dictionary) -> void:
	if process.stage != "passive" or process.paused: return
	owner._process_due.append({"target": target, "process": process.id, "at": process.ready_ms})
	owner._process_due.sort_custom(func(a: Dictionary, b: Dictionary): return a.at < b.at)

static func rebuild_due(owner: RefCounted) -> void:
	owner._order_due.clear()
	for m: Dictionary in owner.matters.values():
		if m.kind == "department" and m.repeat: owner._order_due.append({"id": m.id, "at": m.next_cycle_ms})
	owner._order_due.sort_custom(func(a: Dictionary, b: Dictionary): return a.at < b.at if a.at != b.at else a.id < b.id)

static func service(owner: RefCounted, world: RefCounted, at: int) -> void:
	owner.Departments.ensure(owner)
	while not owner._work_retry.is_empty() and int(owner._work_retry[0].at) <= at:
		var retry: Dictionary = owner._work_retry.pop_front()
		if owner.departments.has(int(retry.department)): owner._work_dirty[int(retry.department)] = false
	if not owner._process_due.is_empty() and int(owner._process_due[0].at) <= at:
		var due: Dictionary = owner._process_due.pop_front()
		var process: Dictionary = world.objects.records.get(int(due.target), {}).get("process", {})
		if process.get("id") == due.process and not process.paused: dirty(owner, int(owner._facility_department.get(int(due.target), 0)))
	# Only known deadlines and relevant dirty departments are serviced; no NPC poll.
	if not owner._order_due.is_empty() and int(owner._order_due[0].at) <= at:
		var due: Dictionary = owner._order_due.pop_front()
		owner.Orders.rollover(owner, world, int(due.id), at)
		rebuild_due(owner)
	for piece: int in 2:
		if owner._work_dirty.is_empty(): break
		var id: int = int(owner._work_dirty.keys()[0])
		var retrying: bool = not owner._work_dirty[id]
		owner._work_dirty.erase(id)
		var offers: Array = offers(owner, world, id)
		var previous: Array = owner._work_offers.get(id, [])
		owner._work_offers[id] = offers
		var added: Array = offers if retrying else offers.filter(func(offer: Dictionary): return not previous.any(func(old: Dictionary): return _key(old) == _key(offer)))
		if not added.is_empty(): _wake_ready(owner, world, id, added, at)

static func _key(offer: Dictionary) -> String:
	# Source alternatives are one demand, not independent vacancies.
	return "%s:%d:%s:%d:%s" % [offer.kind, int(offer.target), str(offer.get("item", "")), int(offer.get("request", 0)), str(offer.get("operation", offer.get("op", "")))]

static func eligible(owner: RefCounted, actor: int, offer: Dictionary) -> bool:
	if offer.kind == "management":
		return owner.departments[int(offer.department)].head == actor and owner.Departments.allowed(owner, actor, int(offer.department), "supply")
	if offer.kind == "transport": return owner.Logistics.current(owner, actor).is_empty() and owner.Departments.labor_allowed(owner, actor, int(offer.source), "haul")
	return owner.Departments.labor_allowed(owner, actor, int(offer.target), "produce")

static func _wake_ready(owner: RefCounted, world: RefCounted, id: int, ready: Array, at: int) -> void:
	var dept: Dictionary = owner.departments[id]
	var candidates: Array = dept.workers.keys()
	if int(dept.head) > 0 and dept.head not in candidates: candidates.append(int(dept.head))
	if candidates.is_empty(): return
	var cursor: int = int(owner._work_cursor.get(id, 0)) % candidates.size()
	var used: Dictionary = {}; var slots: Dictionary = {}
	for offer: Dictionary in ready:
		var key: String = _key(offer)
		if slots.has(key): continue
		for offset: int in candidates.size():
			var index: int = (cursor + offset) % candidates.size()
			var actor: int = int(candidates[index])
			if used.has(actor) or not world.actor_slots.has(actor) or not world.combat.alive(world, actor) or not world.gate.current(actor).is_empty() or not world.objects.records[actor].get("autonomous", false) or world.decisions.records.get(actor, {}).get("manual", false): continue
			if not eligible(owner, actor, offer): continue
			world.decisions.wake(world, actor, at, "department_work", used.size() * 50)
			used[actor] = true; slots[key] = true; cursor = (index + 1) % candidates.size()
			break
	owner._work_cursor[id] = cursor
	# If a selected person chooses urgent needs or a stale path, try the next
	# qualified person later. A claimed/removed offer cancels the retry naturally.
	if not used.is_empty() and not owner._work_retry.any(func(due: Dictionary): return due.department == id):
		owner._work_retry.append({"department": id, "at": at + 1000})
		owner._work_retry.sort_custom(func(a: Dictionary, b: Dictionary): return a.at < b.at)

static func _transport(result: Array, owner: RefCounted, world: RefCounted, department: int, source: int, target: int, item: String, amount: int, request: int = 0) -> void:
	if source == target or not world.objects.records.has(source) or not world.objects.records.has(target): return
	var right: Dictionary = Stock.right(0, int(owner.departments[department].organization))
	var count: int = mini(amount, mini(world.objects.available_amount(source, item, right), world.objects.free_capacity(target)))
	if count <= 0 or not owner.Logistics.accepts(world, target, item) or not owner.Logistics.permits_delivery(world, source, target, item): return
	result.append({"kind": "transport", "department": department, "source": source, "target": target, "item": item, "amount": count, "request": request})

static func incoming(owner: RefCounted, target: int, item: String) -> int:
	owner.Logistics.ensure(owner)
	var count: int = 0
	for id: int in owner._shipments_by_target.get(target, []):
		var s: Dictionary = owner.shipments[id]
		if s.item == item and s.state != "returning": count += int(s.amount)
	return count

static func offers(owner: RefCounted, world: RefCounted, department: int) -> Array:
	var result: Array = []
	var d: Dictionary = owner.departments[department]
	owner.Logistics.ensure(owner)
	# Only designated public piles belong to this department's work. Do not
	# discover the world's loose/private goods in every worker's planning pass.
	for source: int in d.facilities:
		if world.objects.records.get(source, {}).get("kind") != "pile": continue
		for item: String in world.objects.inventory_summary(source):
			for destination: int in d.facilities:
				if world.objects.records.get(destination, {}).get("kind") == "chest": _transport(result, owner, world, department, source, destination, item, world.objects.available_amount(source, item))
	for id: int in owner._requests_by_supplier.get(department, []):
		var r: Dictionary = owner.supply_requests[id]
		if r.state == "requested":
			result.append({"kind": "management", "department": department, "op": "accept_supply", "request": id, "target": r.target})
		else:
			var missing: int = owner.Logistics.request_outstanding(owner, id)
			for source: int in d.facilities:
				if world.objects.records.get(source, {}).get("kind") in ["chest", "source", "pile"]: _transport(result, owner, world, department, source, int(r.target), str(r.item), missing, id)
	for target: int in d.production:
		if not world.objects.records.has(target): continue
		var config: Dictionary = d.production[target]
		var record: Dictionary = world.objects.records[target]
		var process: Dictionary = record.get("process", {})
		var recipe: Dictionary = Operations.OPERATIONS[config.operation].recipe
		# Finished goods must leave the finite workshop through a real shipment.
		for item: String in world.objects.inventory_summary(target):
			if item in recipe.inputs and owner.Orders.open(owner, int(config.order)): continue
			for destination: int in d.facilities:
				if world.objects.records.get(destination, {}).get("kind") == "chest": _transport(result, owner, world, department, target, destination, item, world.objects.available_amount(target, item))
		if not process.is_empty():
			if not world.reservations.has(target) and not process.paused and (process.stage != "passive" or world.operation_time() >= int(process.ready_ms)):
				result.append({"kind": "produce", "department": department, "target": target, "operation": process.operation})
			continue
		if not owner.Orders.open(owner, int(config.order)): continue
		var missing: Dictionary = {}
		var ready: bool = true
		for item: String in recipe.inputs:
			var available: int = world.objects.available_amount(target, item, Stock.right(0, int(d.organization)))
			if available < int(recipe.inputs[item]): ready = false
			var count: int = maxi(0, int(recipe.inputs[item]) - available - incoming(owner, target, item))
			if count > 0: missing[item] = count
		if ready:
			if world.reservations.has(target): continue
			result.append({"kind": "produce", "department": department, "target": target, "operation": config.operation})
			continue
		if missing.is_empty(): continue # All missing goods are in transit, not in the workshop.
		var total: int = 0
		for count: int in missing.values(): total += count
		var growth: int = maxi(0, world.Production._count(recipe.outputs) - world.Production._count(recipe.inputs))
		if world.objects.free_capacity(target) < total + growth: continue
		for item: String in missing:
			var found: bool = false
			for source: int in d.facilities:
				if source == target or world.objects.records.get(source, {}).get("kind") not in ["chest", "pile", "source"]: continue
				var previous: int = result.size()
				_transport(result, owner, world, department, source, target, item, int(missing[item]))
				if result.size() > previous: found = true
			if not found and int(d.supplier) > 0:
				var pending: bool = false
				for id: int in owner._requests_by_department.get(department, []):
					if owner.supply_requests[id].target == target and owner.supply_requests[id].item == item: pending = true; break
				if not pending: result.append({"kind": "management", "department": department, "op": "request_supply", "supplier": d.supplier, "target": target, "item": item, "amount": int(missing[item])})
	return result

static func personal(owner: RefCounted, world: RefCounted, actor: int, department: int = 0, group: String = "") -> Array:
	owner.Departments.ensure(owner)
	var result: Array = []
	var shipment: Dictionary = owner.Logistics.current(owner, actor)
	if not shipment.is_empty() and department in [0, int(shipment.department)]:
		var target: int = int(shipment.source) if shipment.state == "reserved" else int(shipment.destination)
		if target > 0 and world.objects.records.has(target): result.append({"kind": "shipment", "shipment": shipment.id, "department": shipment.department, "target": target, "operation": "take" if shipment.state == "reserved" else "put", "item": shipment.item, "amount": shipment.amount})
	var departments: Array = owner._work_departments.get(actor, []).duplicate()
	for id: int in owner._management_departments.get(actor, []):
		if id not in departments: departments.append(id)
	for id: int in departments:
		if department > 0 and id != department: continue
		var d: Dictionary = owner.departments[id]
		var candidates: Array = owner._work_offers.get(id, [])
		for offset: int in candidates.size():
			if result.size() >= 8: return result
			var offer: Dictionary = candidates[(offset + actor + world.operation_time() / 1000) % candidates.size()]
			if not group.is_empty() and int(offer.get("source", offer.target)) not in d.groups[group].facilities: continue
			if not eligible(owner, actor, offer): continue
			result.append(State.copy(offer))
	return result

static func has_work(owner: RefCounted, world: RefCounted, actor: int) -> bool:
	owner.Departments.ensure(owner)
	if not owner.Logistics.current(owner, actor).is_empty(): return true
	var departments: Array = owner._work_departments.get(actor, []).duplicate()
	for id: int in owner._management_departments.get(actor, []):
		if id not in departments: departments.append(id)
	for id: int in departments:
		for offer: Dictionary in owner._work_offers.get(id, []):
			if eligible(owner, actor, offer): return true
	return false

static func adopt(owner: RefCounted, world: RefCounted, actor: int, offer: Dictionary) -> String:
	var department: int = int(offer.get("department", 0))
	if not owner.departments.has(department): return "department_gone"
	if offer.get("kind") == "management":
		if owner.departments.get(department, {}).get("head") != actor: return "not_authorized"
		var reason: String = owner.management(world, actor, offer)
		return "completed" if reason == "management_updated" else reason
	if offer.get("kind") == "produce":
		if not owner.Departments.labor_allowed(owner, actor, int(offer.target), "produce"): return "not_authorized"
		return world.begin_interaction(actor, {"kind": offer.operation, "target": offer.target, "autonomous": true})
	var shipment: Dictionary
	if offer.get("kind") == "transport":
		var matched: Dictionary = State.copy(offer)
		matched.amount = transport_amount(owner, world, offer)
		if matched.amount <= 0: return "shipment_changed"
		var id: int = owner.Logistics.claim(owner, world, actor, matched)
		if id == 0: return "shipment_changed"
		shipment = owner.shipments[id]
	else:
		shipment = owner.shipments.get(int(offer.get("shipment", 0)), {})
		if shipment.is_empty() or shipment.actor != actor: return "shipment_changed"
	if shipment.state == "returning" and (not world.objects.records.has(int(shipment.destination)) or world.objects.free_capacity(int(shipment.destination)) == 0): owner.Logistics.retarget(owner, world, shipment)
	var operation: String = "take" if shipment.state == "reserved" else "put"
	var target: int = int(shipment.source) if operation == "take" else int(shipment.destination)
	var reason: String = world.begin_transfer(actor, {"kind": operation, "target": target, "item": shipment.item, "amount": shipment.amount, "shipment": shipment.id, "purpose": "supply", "autonomous": true})
	if reason != "accepted": owner.Logistics.blocked(owner, world, int(shipment.id), reason)
	return reason

static func valid_offer(offer: Variant) -> bool:
	if not offer is Dictionary or offer.get("kind") not in ["produce", "transport", "shipment"]: return false
	for field: String in ["department", "target"]:
		if not offer.get(field) is int or offer[field] < 1: return false
	if offer.kind == "produce": return offer.get("operation") is String and not Operations.OPERATIONS.get(offer.operation, {}).get("recipe", {}).is_empty()
	if offer.kind == "shipment": return offer.get("shipment") is int and offer.shipment > 0
	return offer.get("source") is int and offer.source > 0 and offer.get("item") is String and preload("res://scripts/sim/kernel/items.gd").valid(offer.item) and offer.get("amount") is int and offer.amount > 0 and offer.get("request", 0) is int

static func transport_amount(owner: RefCounted, world: RefCounted, offer: Dictionary) -> int:
	# Recheck this one demand at adoption, never rebuild a whole department.
	var d: Dictionary = owner.departments.get(int(offer.get("department", 0)), {})
	var source: int = int(offer.get("source", 0)); var target: int = int(offer.get("target", 0))
	var item: String = str(offer.get("item", "")); var request: int = int(offer.get("request", 0))
	if d.is_empty() or source not in d.facilities or not world.objects.records.has(target): return 0
	if request > 0:
		var r: Dictionary = owner.supply_requests.get(request, {})
		if r.get("state") != "accepted" or r.supplier != d.id or r.item != item or r.target != target: return 0
		return mini(int(offer.amount), owner.Logistics.request_outstanding(owner, request))
	if target not in d.facilities: return 0
	if world.objects.records.get(source, {}).get("kind") == "pile" and world.objects.records[target].kind == "chest": return int(offer.amount)
	if d.production.has(target):
		var config: Dictionary = d.production[target]
		if world.objects.records[target].has("process") or not owner.Orders.open(owner, int(config.order)): return 0
		var recipe: Dictionary = Operations.OPERATIONS[config.operation].recipe
		var missing: int = maxi(0, int(recipe.inputs.get(item, 0)) - world.objects.available_amount(target, item, Stock.right(0, int(d.organization))) - incoming(owner, target, item))
		var total: int = 0
		for material: String in recipe.inputs: total += maxi(0, int(recipe.inputs[material]) - world.objects.available_amount(target, material, Stock.right(0, int(d.organization))) - incoming(owner, target, material))
		var growth: int = maxi(0, world.Production._count(recipe.outputs) - world.Production._count(recipe.inputs))
		return mini(int(offer.amount), missing) if world.objects.free_capacity(target) >= total + growth else 0
	if d.production.has(source) and world.objects.records[target].kind == "chest":
		var recipe: Dictionary = Operations.OPERATIONS[d.production[source].operation].recipe
		if item in recipe.inputs and owner.Orders.open(owner, int(d.production[source].order)): return 0
		return int(offer.amount)
	return 0

static func grants(owner: RefCounted, actor: int) -> Array:
	var s: Dictionary = owner.Logistics.current(owner, actor)
	if s.is_empty(): return []
	return [{"organization": s.right.organization, "targets": [s.source, s.destination], "purposes": ["take", "put", "supply"], "items": [s.item], "all_items": false}]

static func _in_scope(d: Dictionary, target: int, group: String) -> bool:
	return target in d.facilities and (group.is_empty() or target in d.groups[group].facilities)

static func command(owner: RefCounted, world: RefCounted, actor: int, request: Dictionary) -> String:
	var id: int = int(request.department)
	var d: Dictionary = owner.departments[id]
	var op: String = str(request.op)
	for key: String in ["facility", "target", "order", "parent_order", "total", "amount", "supplier", "request", "min_tier", "max_tier"]:
		if request.has(key) and not request[key] is int: return "invalid_configuration"
	for key: String in ["operation", "item", "mode"]:
		if request.has(key) and not request[key] is String: return "invalid_configuration"
	if request.has("repeat") and not request.repeat is bool: return "invalid_configuration"
	var scope: String = str(request.get("group", ""))
	if not scope.is_empty():
		if op in ["supplier", "accept_supply"]: return "not_authorized"
		if op in ["configure", "storage"] and not _in_scope(d, int(request.get("facility", 0)), scope): return "not_authorized"
		if op == "request_supply" and not _in_scope(d, int(request.get("target", 0)), scope): return "not_authorized"
		if op in ["configure", "order_control"] and owner.matters.get(int(request.get("order", 0)), {}).get("group") != scope: return "not_authorized"
		if op == "cancel_supply" and not _in_scope(d, int(owner.supply_requests.get(int(request.get("request", 0)), {}).get("target", 0)), scope): return "not_authorized"
	match op:
		"order":
			if owner.Orders.create(owner, world, actor, id, str(request.get("operation", "")), str(request.get("item", "")), int(request.get("total", 0)), str(request.get("group", "")), int(request.get("parent_order", 0)), request.get("repeat", false)) == 0: return "invalid_configuration"
			owner.Workflow.rebuild_due(owner)
		"configure":
			var target: int = int(request.get("facility", 0))
			var order: Dictionary = owner.matters.get(int(request.get("order", 0)), {})
			if target not in d.facilities or order.get("kind") != "department" or order.state != "active" or order.department != id or (not order.group.is_empty() and target not in d.groups[order.group].facilities): return "invalid_configuration"
			var recipe: Dictionary = Operations.OPERATIONS[order.operation].recipe
			if recipe.id not in world.facilities.definitions.get(world.objects.records[target].definition, {}).get("capabilities", {}).get(recipe.facility_capability, {}).get("recipes", []): return "unsupported_recipe"
			owner.Logistics.cancel_requests(owner, world, id, target)
			d.production[target] = {"operation": order.operation, "order": order.id}
		"order_control":
			var order: Dictionary = owner.matters.get(int(request.get("order", 0)), {})
			if order.get("kind") != "department" or order.department != id: return "invalid_configuration"
			var mode: String = str(request.get("mode", ""))
			if mode == "cancel":
				order.state = "cancelled"; order.repeat = false; order.next_cycle_ms = 0
				if order.parent_order == 0:
					for child: Dictionary in owner.Orders.list(owner, id):
						if child.parent_order == order.id and child.state == "active": child.state = "cancelled"
			elif mode in ["pause", "resume"]: order.paused = mode == "pause"
			else: return "invalid_configuration"
		"supplier":
			var supplier: int = int(request.get("supplier", 0))
			if supplier == id or (supplier > 0 and owner.departments.get(supplier, {}).get("organization") != d.organization): return "invalid_configuration"
			owner.Logistics.cancel_requests(owner, world, id)
			d.supplier = supplier
		"request_supply":
			if owner.Logistics.request(owner, world, id, int(request.get("supplier", d.supplier)), int(request.get("target", 0)), str(request.get("item", "")), int(request.get("amount", 0))) == 0: return "invalid_configuration"
		"cancel_supply":
			var r: Dictionary = owner.supply_requests.get(int(request.get("request", 0)), {})
			if r.is_empty() or id not in [int(r.department), int(r.supplier)]: return "not_authorized"
			owner.Logistics.cancel_request(owner, world, int(r.id))
		"accept_supply":
			if not owner.Logistics.accept(owner, world, id, int(request.get("request", 0))): return "request_changed"
		"storage":
			var target: int = int(request.get("facility", 0))
			if target not in d.facilities or not request.get("items", []) is Array or not request.get("destinations", []) is Array: return "invalid_configuration"
			for item: Variant in request.get("items", []):
				if not item is String or not preload("res://scripts/sim/kernel/items.gd").valid(item): return "invalid_configuration"
			var destinations: Array = request.get("destinations", [])
			for place: Variant in destinations:
				if not place is int or not world.objects.records.has(place) or world.objects.records[place].organization != d.organization: return "invalid_configuration"
			var low: int = int(request.get("min_tier", 1))
			var high: int = int(request.get("max_tier", 99))
			if low < 1 or high < low or high > 99: return "invalid_configuration"
			var policy: Dictionary = {"items": request.get("items", []).duplicate(), "min_tier": low, "max_tier": high, "destinations": destinations.duplicate()}
			if not Stock.valid_storage_policy(policy, world.objects.next_id): return "invalid_configuration"
			world.objects.records[target]["storage_policy"] = policy
			owner.Logistics.policy_changed(owner, world, target)
		_:
			return "invalid_configuration"
	if op in ["request_supply", "accept_supply", "cancel_supply"]: owner.Departments.touch(owner)
	else: owner.Departments.changed(owner, id)
	dirty(owner, id)
	return "management_updated"
