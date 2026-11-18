extends RefCounted
## Canonical transport obligations live on Institutions. Indices reserve physical
## source quantities and destination room, never a second inventory.
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const LIMIT: int = 512

static func ensure(owner: RefCounted) -> void:
	if not owner._logistics_dirty: return
	owner._entrust_shipment.clear(); owner._shipments_by_actor.clear(); owner._shipments_by_source.clear(); owner._shipments_by_target.clear()
	owner._requests_by_department.clear(); owner._requests_by_supplier.clear()
	owner._recent_supply.clear()
	for id: int in owner.shipments:
		var s: Dictionary = owner.shipments[id]
		if s.state not in ["reserved", "carrying", "returning"]: continue
		_index(owner, s)
	for id: int in owner.supply_requests:
		var r: Dictionary = owner.supply_requests[id]
		if r.state not in ["requested", "accepted"]: _remember_request(owner, r); continue
		_append(owner._requests_by_department, int(r.department), id)
		_append(owner._requests_by_supplier, int(r.supplier), id)
	owner._logistics_dirty = false

static func _append(index: Dictionary, key: int, id: int) -> void:
	if not index.has(key): index[key] = []
	index[key].append(id)

static func _remove(index: Dictionary, key: int, id: int) -> void:
	if not index.has(key): return
	index[key].erase(id)
	if index[key].is_empty(): index.erase(key)

static func _index(owner: RefCounted, s: Dictionary) -> void:
	if s.state not in ["reserved", "carrying", "returning"]: return
	_append(owner._shipments_by_actor, int(s.actor), int(s.id))
	if s.state == "reserved": _append(owner._shipments_by_source, int(s.source), int(s.id))
	_append(owner._shipments_by_target, int(s.destination), int(s.id))
	if s.entrust > 0: owner._entrust_shipment[int(s.entrust)] = int(s.id)

static func _unindex(owner: RefCounted, s: Dictionary) -> void:
	_remove(owner._shipments_by_actor, int(s.actor), int(s.id))
	_remove(owner._shipments_by_source, int(s.source), int(s.id))
	_remove(owner._shipments_by_target, int(s.destination), int(s.id))
	owner._entrust_shipment.erase(int(s.entrust))

static func _close_request(owner: RefCounted, r: Dictionary) -> void:
	_remove(owner._requests_by_department, int(r.department), int(r.id))
	_remove(owner._requests_by_supplier, int(r.supplier), int(r.id))
	_remember_request(owner, r)

static func _remember_request(owner: RefCounted, r: Dictionary) -> void:
	for department: int in [int(r.department), int(r.supplier)]:
		if not owner._recent_supply.has(department): owner._recent_supply[department] = []
		owner._recent_supply[department].erase(int(r.id))
		owner._recent_supply[department].append(int(r.id))
		if owner._recent_supply[department].size() > 8: owner._recent_supply[department].pop_front()

static func source_claimed(owner: RefCounted, source: int, item: String, right: Dictionary = {}, excluded: int = 0) -> int:
	ensure(owner)
	var count: int = 0
	for id: int in owner._shipments_by_source.get(source, []):
		var s: Dictionary = owner.shipments[id]
		if id != excluded and s.item == item and Stock.matches(s.right, right): count += int(s.amount)
	return count

static func target_claimed(owner: RefCounted, target: int, excluded: int = 0) -> int:
	ensure(owner)
	var count: int = 0
	for id: int in owner._shipments_by_target.get(target, []):
		if id != excluded and owner.shipments[id].state != "returning": count += int(owner.shipments[id].amount)
	return count

static func request(owner: RefCounted, world: RefCounted, department: int, supplier: int, target: int, item: String, amount: int) -> int:
	var d: Dictionary = owner.departments.get(department, {})
	var source: Dictionary = owner.departments.get(supplier, {})
	if d.is_empty() or source.is_empty() or d.organization != source.organization or department == supplier or target not in d.facilities or not Items.valid(item) or amount < 1 or amount > 10000: return 0
	ensure(owner)
	for id: int in owner._requests_by_department.get(department, []):
		var r: Dictionary = owner.supply_requests[id]
		if r.target == target and r.item == item: return id # Coalesce an existing demand; do not multiply it each wake.
	compact(owner)
	if owner.supply_requests.size() >= LIMIT: return 0
	var id: int = owner.next_supply_request
	owner.next_supply_request += 1
	owner.supply_requests[id] = {"id": id, "department": department, "supplier": supplier, "target": target, "item": item, "amount": amount, "received": 0, "state": "requested", "created_ms": world.operation_time()}
	_append(owner._requests_by_department, department, id)
	_append(owner._requests_by_supplier, supplier, id)
	owner.Workflow.dirty(owner, supplier)
	owner.Departments.touch(owner)
	return id

static func accept(owner: RefCounted, world: RefCounted, department: int, id: int) -> bool:
	var r: Dictionary = owner.supply_requests.get(id, {})
	if r.is_empty() or r.supplier != department or r.state != "requested": return false
	r.state = "accepted"
	owner.Workflow.dirty(owner, department)
	owner.Departments.touch(owner)
	return true

static func request_outstanding(owner: RefCounted, id: int) -> int:
	var r: Dictionary = owner.supply_requests.get(id, {})
	if r.is_empty(): return 0
	var count: int = int(r.received)
	ensure(owner)
	for shipment: int in owner._shipments_by_target.get(int(r.target), []):
		if owner.shipments[shipment].request == id and owner.shipments[shipment].state != "returning": count += int(owner.shipments[shipment].amount)
	return maxi(0, int(r.amount) - count)

static func permits_delivery(world: RefCounted, source: int, target: int, item: String) -> bool:
	var policy: Dictionary = world.objects.records.get(source, {}).get("storage_policy", {})
	return policy.get("destinations", []).is_empty() or target in policy.destinations

static func accepts(world: RefCounted, target: int, item: String) -> bool:
	var record: Dictionary = world.objects.records.get(target, {})
	if record.get("kind") == "source" and world.facilities.definitions.get(record.definition, {}).get("capabilities", {}).get("stock_source", {}).get("item") != item: return false
	return Stock.storage_accepts(record.get("storage_policy", {}), item)

static func claim(owner: RefCounted, world: RefCounted, actor: int, offer: Dictionary) -> int:
	ensure(owner)
	if not owner._shipments_by_actor.get(actor, []).is_empty() or not world.combat.alive(world, actor): return 0
	var source: int = int(offer.get("source", 0))
	var target: int = int(offer.get("target", 0))
	var department: int = int(offer.get("department", 0))
	var item: String = str(offer.get("item", ""))
	var d: Dictionary = owner.departments.get(department, {})
	if d.is_empty() or source == target or not world.objects.records.has(source) or not world.objects.records.has(target) or not Items.valid(item): return 0
	if not owner.Departments.labor_allowed(owner, actor, source, "haul") or source not in d.facilities: return 0
	if not permits_delivery(world, source, target, item) or not accepts(world, target, item): return 0
	var request_id: int = int(offer.get("request", 0))
	if target not in d.facilities:
		var r: Dictionary = owner.supply_requests.get(request_id, {})
		if r.get("state") != "accepted" or r.supplier != department or r.target != target or r.item != item: return 0
	var right: Dictionary = Stock.right(0, int(d.organization))
	if world.objects.records[target].organization != d.organization: return 0
	var amount: int = mini(int(offer.get("amount", 0)), world.objects.available_amount(source, item, right))
	amount = mini(amount, mini(world.objects.free_capacity(target), world.objects.free_capacity(actor)))
	if request_id > 0: amount = mini(amount, request_outstanding(owner, request_id))
	compact(owner); ensure(owner)
	if amount <= 0 or owner.shipments.size() >= LIMIT: return 0
	var id: int = owner.next_shipment
	owner.next_shipment += 1
	owner.shipments[id] = {"id": id, "department": department, "actor": actor, "source": source, "destination": target, "item": item, "amount": amount, "right": right, "request": request_id, "state": "reserved", "entrust": 0, "created_ms": world.operation_time()}
	_index(owner, owner.shipments[id])
	owner.Workflow.dirty(owner, department)
	return id

static func current(owner: RefCounted, actor: int) -> Dictionary:
	ensure(owner)
	var ids: Array = owner._shipments_by_actor.get(actor, [])
	return owner.shipments[int(ids[0])] if not ids.is_empty() else {}

static func transfer_reason(owner: RefCounted, actor: int, target: int, item: String, amount: int, handler: String, id: int) -> String:
	var s: Dictionary = owner.shipments.get(id, {})
	if s.is_empty() or s.actor != actor or s.item != item or s.amount != amount: return "shipment_changed"
	if handler == "take" and s.state == "reserved" and s.source == target: return ""
	if handler == "put" and s.state in ["carrying", "returning"] and s.destination == target: return ""
	return "shipment_changed"

static func transferred(owner: RefCounted, world: RefCounted, id: int, handler: String, amount: int, entrust: int, at: int) -> void:
	var s: Dictionary = owner.shipments.get(id, {})
	if s.is_empty(): return
	ensure(owner)
	_unindex(owner, s)
	if handler == "take":
		if amount <= 0: s.state = "cancelled"
		else: s.amount = amount; s.entrust = entrust; s.state = "carrying"
	else:
		if s.state == "carrying" and s.request > 0:
			var r: Dictionary = owner.supply_requests[s.request]
			r.received += amount
			if r.received >= r.amount: r.state = "completed"; _close_request(owner, r)
			owner.Workflow.dirty(owner, int(r.department))
			s.amount -= amount
			if s.amount <= 0: s.state = "completed"
		else:
			s.amount -= amount
			if s.amount <= 0: s.state = "completed"
	_index(owner, s)
	owner.Workflow.dirty(owner, int(s.department))
	if s.request > 0: owner.Workflow.dirty(owner, int(owner.supply_requests[s.request].department))
	owner.Departments.touch(owner)

static func retarget(owner: RefCounted, world: RefCounted, s: Dictionary, excluded: int = 0) -> void:
	var previous: int = int(s.destination)
	ensure(owner); _unindex(owner, s)
	var d: Dictionary = owner.departments[int(s.department)]
	var choices: Array = [int(s.source)] + d.facilities
	s.destination = 0
	for target: int in choices:
		var record: Dictionary = world.objects.records.get(target, {})
		if target == excluded or record.is_empty() or record.organization != s.right.organization or record.kind not in ["chest", "pile", "source"] or world.objects.free_capacity(target) < int(s.amount) or not accepts(world, target, str(s.item)): continue
		s.destination = target; break
	if s.destination == 0:
		s.destination = _return_pile(owner, world, s)
	_index(owner, s)
	_stop_old_transfer(world, s)
	_cleanup_return_pile(owner, world, previous)

static func _return_pile(owner: RefCounted, world: RefCounted, s: Dictionary) -> int:
	# A physical handover at the carrier, never a virtual refund or a search
	# which alternates forever between previously unreachable warehouses.
	var point: Vector2 = world.combat.position(world, int(s.actor))
	var tile: int = world.Terrain.index(Vector2i(point.floor()))
	var old: Dictionary = world.objects.records.get(int(s.destination), {})
	if old.get("kind") == "pile" and old.definition == "returned_goods" and old.organization == s.right.organization and old.tile == tile and accepts(world, int(old.id), str(s.item)):
		return int(old.id)
	var pile: int = world.objects.create("pile", "returned_goods", tile)
	world.objects.records[pile].organization = int(s.right.organization)
	owner.Departments.attach(owner, world, int(s.department), pile)
	return pile

static func _cleanup_return_pile(owner: RefCounted, world: RefCounted, target: int) -> void:
	# Only a generated, empty, unreferenced handover site can be discarded.
	# Actual goods and another carrier's destination always survive.
	var record: Dictionary = world.objects.records.get(target, {})
	if record.get("kind") != "pile" or record.definition != "returned_goods" or world.objects.count_inventory(target) > 0: return
	ensure(owner)
	if not owner._shipments_by_target.get(target, []).is_empty() or not owner._shipments_by_source.get(target, []).is_empty(): return
	world.remove_static(target)

static func _stop_old_transfer(world: RefCounted, s: Dictionary) -> void:
	if world.actions.get(int(s.actor), {}).get("shipment") != s.id: return
	world.end_run(int(s.actor), world.operation_time(), "shipment_changed")
	world.clear_navigation(int(s.actor))

static func cancel_request(owner: RefCounted, world: RefCounted, id: int) -> void:
	var r: Dictionary = owner.supply_requests.get(id, {})
	if r.is_empty() or r.state not in ["requested", "accepted"]: return
	ensure(owner)
	r.state = "cancelled"; _close_request(owner, r)
	for shipment: int in owner._shipments_by_target.get(int(r.target), []).duplicate():
		if owner.shipments[shipment].request == id: cancel(owner, world, shipment)
	owner.Workflow.dirty(owner, int(r.department)); owner.Workflow.dirty(owner, int(r.supplier))
	owner.Departments.touch(owner)

static func cancel_requests(owner: RefCounted, world: RefCounted, department: int, target: int = 0) -> void:
	ensure(owner)
	for id: int in owner._requests_by_department.get(department, []).duplicate():
		if target == 0 or owner.supply_requests[id].target == target: cancel_request(owner, world, id)

static func cancel(owner: RefCounted, world: RefCounted, id: int) -> void:
	var s: Dictionary = owner.shipments.get(id, {})
	if s.is_empty() or s.state not in ["reserved", "carrying", "returning"]: return
	ensure(owner)
	_unindex(owner, s)
	if s.state == "reserved": s.state = "cancelled"
	else:
		s.state = "returning"
		retarget(owner, world, s)
		_stop_old_transfer(world, s)
		owner.Workflow.dirty(owner, int(s.department))
		if s.request > 0: owner.Workflow.dirty(owner, int(owner.supply_requests[s.request].department))
		return
	_index(owner, s)
	_stop_old_transfer(world, s)
	owner.Workflow.dirty(owner, int(s.department))
	if s.request > 0: owner.Workflow.dirty(owner, int(owner.supply_requests[s.request].department))

static func blocked(owner: RefCounted, world: RefCounted, id: int, reason: String) -> void:
	var s: Dictionary = owner.shipments.get(id, {})
	if s.is_empty(): return
	if s.state == "reserved": cancel(owner, world, id)
	elif reason in ["path_failed", "no_operation_place", "target_gone", "invalid_target", "not_authorized", "storage_rejected", "full", "out_of_reach"]:
		if s.state == "carrying": cancel(owner, world, id)
		elif s.state == "returning":
			var previous: int = int(s.destination)
			ensure(owner); _unindex(owner, s)
			s.destination = _return_pile(owner, world, s)
			_index(owner, s)
			_stop_old_transfer(world, s)
			_cleanup_return_pile(owner, world, previous)
			owner.Workflow.dirty(owner, int(s.department))

static func policy_changed(owner: RefCounted, world: RefCounted, target: int) -> void:
	ensure(owner)
	var ids: Dictionary = {}
	for id: int in owner._shipments_by_source.get(target, []): ids[id] = true
	for id: int in owner._shipments_by_target.get(target, []): ids[id] = true
	for id: int in ids:
		var s: Dictionary = owner.shipments[id]
		if not accepts(world, int(s.destination), str(s.item)) or (s.state == "reserved" and not permits_delivery(world, int(s.source), int(s.destination), str(s.item))):
			cancel(owner, world, id)

static func reconcile_worker(owner: RefCounted, world: RefCounted, actor: int) -> void:
	var s: Dictionary = current(owner, actor)
	if s.get("state") != "reserved" or owner.Departments.labor_allowed(owner, actor, int(s.source), "haul"): return
	cancel(owner, world, int(s.id))

static func forget(owner: RefCounted, world: RefCounted, target: int) -> void:
	ensure(owner)
	var ids: Array = owner._shipments_by_source.get(target, []).duplicate()
	for id: int in owner._shipments_by_target.get(target, []):
		if id not in ids: ids.append(id)
	for id: int in owner._shipments_by_actor.get(target, []):
		if id not in ids: ids.append(id)
	for id: int in ids:
		var s: Dictionary = owner.shipments[id]
		var previous: int = int(s.destination)
		if s.actor == target: _unindex(owner, s); s.state = "lost"
		elif s.destination == target:
			if s.state == "reserved": _unindex(owner, s); s.state = "cancelled"
			else: s.state = "returning"; retarget(owner, world, s, target)
		elif s.state == "reserved": _unindex(owner, s); s.state = "cancelled"
		else: continue # An already collected source is historical provenance.
		_stop_old_transfer(world, s)
		_cleanup_return_pile(owner, world, previous)
		owner.Workflow.dirty(owner, int(s.department))
	for d: int in owner._requests_by_department.keys():
		for id: int in owner._requests_by_department[d].duplicate():
			if owner.supply_requests[id].target == target: cancel_request(owner, world, id)

static func compact(owner: RefCounted) -> void:
	if owner.shipments.size() < LIMIT - 16 and owner.supply_requests.size() < LIMIT - 16: return
	for id: int in owner.shipments.keys():
		if owner.shipments[id].state in ["completed", "cancelled", "lost"]: owner.shipments.erase(id)
	var retained: Dictionary = {}
	for s: Dictionary in owner.shipments.values(): retained[int(s.request)] = true
	for id: int in owner.supply_requests.keys():
		if owner.supply_requests[id].state in ["completed", "cancelled"] and not retained.has(id): owner.supply_requests.erase(id)
	owner._logistics_dirty = true

static func valid(owner: RefCounted, world: RefCounted) -> bool:
	if owner.next_shipment < 1 or owner.next_supply_request < 1 or owner.shipments.size() > LIMIT or owner.supply_requests.size() > LIMIT: return false
	for id: Variant in owner.supply_requests:
		var r: Variant = owner.supply_requests[id]
		if not id is int or id <= 0 or id >= owner.next_supply_request or not r is Dictionary or r.size() != 9: return false
		for field: String in ["id", "department", "supplier", "target", "amount", "received", "created_ms"]:
			if not r.get(field) is int: return false
		if r.id != id or not owner.departments.has(r.department) or not owner.departments.has(r.supplier) or r.department == r.supplier or r.target < 1 or r.target >= world.objects.next_id or not r.get("item") is String or not Items.valid(r.item): return false
		if owner.departments[r.department].organization != owner.departments[r.supplier].organization: return false
		if r.get("state") not in ["requested", "accepted", "completed", "cancelled"] or r.amount < 1 or r.amount > 10000 or r.received < 0 or r.received > r.amount or ((r.state == "completed") != (r.received == r.amount)) or r.created_ms < 0 or r.created_ms > world.operation_time(): return false
		if r.state in ["requested", "accepted"] and r.target not in owner.departments[r.department].facilities: return false
	var actors: Dictionary = {}
	var entrusts: Dictionary = {}
	var pending: Dictionary = {}
	for id: Variant in owner.shipments:
		var s: Variant = owner.shipments[id]
		if not id is int or id <= 0 or id >= owner.next_shipment or not s is Dictionary or s.size() != 12: return false
		for field: String in ["id", "department", "actor", "source", "destination", "amount", "request", "entrust", "created_ms"]:
			if not s.get(field) is int: return false
		if s.id != id or not owner.departments.has(s.department) or s.actor < 1 or s.actor >= world.objects.next_id or (world.objects.records.has(s.actor) and world.objects.records[s.actor].kind != "actor") or s.source < 1 or s.source >= world.objects.next_id or s.destination < 0 or s.destination >= world.objects.next_id: return false
		if not s.get("item") is String or not Items.valid(s.item) or s.get("state") not in ["reserved", "carrying", "returning", "completed", "cancelled", "lost"] or s.amount < 0 or s.amount > 10000 or s.created_ms < 0 or s.created_ms > world.operation_time() or not Stock.valid_right(s.get("right"), world.objects.next_id): return false
		if s.request < 0 or s.entrust < 0 or (s.request > 0 and not owner.supply_requests.has(s.request)): return false
		if s.request > 0:
			var r: Dictionary = owner.supply_requests[s.request]
			if r.supplier != s.department or r.item != s.item: return false
			if s.state in ["reserved", "carrying"]:
				if r.state != "accepted" or r.target != s.destination: return false
				pending[int(s.request)] = int(pending.get(int(s.request), 0)) + int(s.amount)
		if s.right != Stock.right(0, int(owner.departments[s.department].organization)): return false
		if s.state in ["reserved", "carrying", "returning"]:
			if actors.has(s.actor) or s.amount <= 0 or not world.combat.alive(world, int(s.actor)) or not owner.memberships[int(s.right.organization)].has(s.actor) or not world.objects.records.has(s.destination): return false
			actors[s.actor] = true
			if s.state == "reserved":
				if s.entrust != 0 or not world.objects.records.has(s.source) or not world.objects.records.has(s.destination): return false
			else:
				var e: Dictionary = owner.entrustments.get(s.entrust, {})
				if entrusts.has(s.entrust) or e.get("custodian") != s.actor or e.get("organization") != s.right.organization or e.get("purpose") != "supply" or world.objects.amount(s.actor, s.item, Stock.right(0, int(s.right.organization), int(s.entrust))) != s.amount: return false
				entrusts[s.entrust] = true
	for id: int in pending:
		if int(pending[id]) + int(owner.supply_requests[id].received) > int(owner.supply_requests[id].amount): return false
	owner._logistics_dirty = true
	ensure(owner)
	for source: int in owner._shipments_by_source:
		var seen: Dictionary = {}
		for id: int in owner._shipments_by_source[source]:
			var s: Dictionary = owner.shipments[id]
			if seen.has(s.item): continue
			seen[s.item] = true
			if source_claimed(owner, source, str(s.item), s.right) + world.objects.locked_amount(source, str(s.item), s.right) > world.objects.amount(source, str(s.item), s.right): return false
	for target: int in owner._shipments_by_target:
		if target == 0: continue
		if not world.objects.records.has(target): return false
		var r: Dictionary = world.objects.records[target]
		if int(r.capacity) >= 0 and world.objects.count_inventory(target) + int(r.get("process", {}).get("net_growth", 0)) + target_claimed(owner, target) > int(r.capacity): return false
	return true
