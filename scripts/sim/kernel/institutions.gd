extends RefCounted
## Organization permissions and entrusted purpose, separate from physical custody.
## Historical counters are evidence, never another spendable stock balance.
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Results = preload("res://scripts/sim/kernel/activity_results.gd")
const Access = preload("res://scripts/sim/kernel/institution_access.gd")
const Defs = preload("res://scripts/sim/kernel/institution_defs.gd")
const Matters = preload("res://scripts/sim/kernel/institution_matters.gd")
const Duties = preload("res://scripts/sim/kernel/institution_duties.gd")
const Channels = preload("res://scripts/sim/kernel/institution_channels.gd")
const Departments = preload("res://scripts/sim/kernel/department_rules.gd")
const Orders = preload("res://scripts/sim/kernel/department_orders.gd")
const Logistics = preload("res://scripts/sim/kernel/department_logistics.gd")
const Workflow = preload("res://scripts/sim/kernel/department_workflow.gd")
const STATE_FIELDS: Array = ["next_organization", "organizations", "memberships", "next_entrust", "entrustments", "accounts", "next_appointment", "appointments", "services", "catalog_signature", "next_matter", "matters", "next_share", "shares", "matter_ledger", "channels", "next_department", "departments", "department_revision", "next_shipment", "shipments", "next_supply_request", "supply_requests"]
const PURPOSES: Array[String] = Stock.PURPOSES
const ISSUE_PURPOSES: Array[String] = Stock.ISSUE_PURPOSES
const COUNTERS: Array[String] = ["issued", "consumed", "produced", "delivered", "returned", "donated"]
var next_organization: int = 1
var organizations: Dictionary = {}
var memberships: Dictionary = {}
var next_entrust: int = 1
var entrustments: Dictionary = {}
var accounts: Dictionary = {}
var next_appointment: int = 1
var appointments: Dictionary = {}
var services: Dictionary = {}
var catalog_signature: String = Defs.SIGNATURE
var next_matter: int = 1
var matters: Dictionary = {}
var next_share: int = 1
var shares: Dictionary = {}
var matter_ledger: Dictionary = {}
var _shares_by_actor: Dictionary = {} # Rebuilt identity index, never another progress store.
var _shares_by_matter: Dictionary = {}
var channels: Dictionary = {}
var _channel_shares: Dictionary = {}
var next_shipment: int = 1
var shipments: Dictionary = {}
var next_supply_request: int = 1
var supply_requests: Dictionary = {}
var _logistics_dirty: bool = true
var _entrust_shipment: Dictionary = {}
var _process_due: Array = []
var _shipments_by_actor: Dictionary = {}
var _shipments_by_source: Dictionary = {}
var _shipments_by_target: Dictionary = {}
var _requests_by_department: Dictionary = {}
var _requests_by_supplier: Dictionary = {}
var _recent_supply: Dictionary = {} # Bounded closed request references for management feedback.
var _orders_dirty: bool = true
var _orders_by_department: Dictionary = {}
var _order_wip: Dictionary = {}
var _order_due: Array = []
var _work_dirty: Dictionary = {}
var _work_offers: Dictionary = {}
var _work_retry: Array = [] # Known retry deadlines for still-unclaimed ready work.
var next_department: int = 1
var departments: Dictionary = {}
var department_revision: int = 1
var _department_index_dirty: bool = true
var _work_departments: Dictionary = {}
var _labor_targets: Dictionary = {} # actor -> duty -> target set, derived from assignments.
var _work_cursor: Dictionary = {} # Fair departmental wake rotation; not saved.
var _management_departments: Dictionary = {}
var _facility_department: Dictionary = {}
var _department_children: Dictionary = {}
var _access_dirty: bool = true
var _appointments_by_actor: Dictionary = {}
var _services_by_actor: Dictionary = {}
var _services_by_org: Dictionary = {}

func inventory_changed(target: int) -> void:
	Workflow.stock_changed(self, target)

func source_reserved(source: int, item: String, right: Dictionary, excluded: int) -> int:
	return Logistics.source_claimed(self, source, item, right, excluded)

func capacity_reserved(target: int, excluded: int) -> int:
	return Logistics.target_claimed(self, target, excluded)

func management(world: RefCounted, actor: int, request: Dictionary) -> String:
	return Departments.command(self, world, actor, request)

func create_matter(world: RefCounted, issuer: int, spec: Dictionary) -> int:
	return Matters.create(self, world, issuer, spec)

func accept_share(world: RefCounted, actor: int, matter: int, quota: int = 0, temporary: bool = false) -> int:
	return Matters.accept(self, world, actor, matter, quota, temporary)

func release_share(world: RefCounted, actor: int, share: int) -> bool:
	return Matters.release(self, world, actor, share)

func cancel_matter(world: RefCounted, actor: int, matter: int) -> bool:
	return Matters.cancel(self, world, actor, matter)

func revise_matter(world: RefCounted, actor: int, matter: int, total: int, quota: int, deadline: int) -> bool:
	return Matters.revise(self, world, actor, matter, total, quota, deadline)

func outcome(world: RefCounted, result: Dictionary) -> void:
	Orders.outcome(self, world, result)
	Matters.outcome(self, world, result)

func appoint(world: RefCounted, organization: int, actor: int, role: String, targets: Array, duty_scope: Dictionary = {}) -> int:
	return Access.appoint(self, world, organization, actor, role, targets, duty_scope)

func commit(world: RefCounted, actor: int, action: Dictionary, at: int) -> Dictionary:
	return Channels.commit(self, world, actor, action, at)

func revoke(world: RefCounted, appointment: int) -> bool:
	return Access.revoke(self, world, appointment)

func arrange_service(world: RefCounted, target: int, purpose: String, actors: Array = [], members: bool = false) -> bool:
	return Access.arrange(self, world, target, purpose, actors, members)

func clear_service(world: RefCounted, target: int, purpose: String) -> bool:
	return Access.clear_service(self, world, target, purpose)

func membership_view(actor: int) -> Array:
	var result: Array = []
	for organization: int in memberships:
		if memberships[organization].has(actor): result.append({"organization": organization, "name": str(organizations[organization].name)})
	return result

func public_profile(observer: int, actor: int) -> Dictionary:
	# Membership is not asset ownership. In this first sect, appointments and
	# allocated rest places are public to fellow members of that organization.
	var shared: Array = []
	var result: Dictionary = {"id": actor, "memberships": [], "public_roles": [], "service_targets": {"rest": []}}
	for entry: Dictionary in membership_view(actor):
		if memberships[entry.organization].has(observer):
			shared.append(int(entry.organization)); result.memberships.append(entry)
	for duty: Dictionary in Duties.views(self, actor).values():
		if duty.organization in shared: result.public_roles.append(str(duty.title))
	for target: int in services:
		var rule: Dictionary = services[target].get("rest", {})
		if not rule.is_empty() and rule.organization in shared and (actor in rule.actors or rule.members): result.service_targets.rest.append(target)
	return result

func access_view(world: RefCounted, actor: int) -> Dictionary:
	var returned: Dictionary = {}
	var pending: Array = return_bundles(world, actor)
	for bundle: Dictionary in pending:
		if not returned.has(int(bundle.organization)): returned[int(bundle.organization)] = {}
		for item: String in bundle.items: _add(returned[int(bundle.organization)], item, int(bundle.items[item]))
	return {"memberships": membership_view(actor), "permissions": permissions(actor), "scope_grants": Access.scope_grants(self, actor) + Matters.grants(self, world, actor) + Departments.grants(self, actor) + Workflow.grants(self, actor), "task_access": Matters.task_access(self, actor), "responsibilities": Matters.views(self, world, actor), "duties": Duties.views(self, actor), "reports": Channels.own_receipts(self, actor, true), "channel_receipts": Channels.own_receipts(self, actor), "service_targets": Access.service_targets(self, actor), "return_items": returned, "return_bundles": pending}

func reconcile(world: RefCounted, actor: int, target: int = 0) -> void:
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor): return
	Logistics.reconcile_worker(self, world, actor)
	var action: Dictionary = world.actions.get(actor, {})
	var denied: bool = false
	if not action.is_empty() and world._finishing.get(actor) != action.run_id and (target == 0 or action.target == target):
		denied = not world.OperationQuery.access_reason(world.Operations.OPERATIONS[action.kind], world.operation_actor(actor), world.operation_target(action.target), action, world.facilities.definitions).is_empty()
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	if action.is_empty() and world.work_runs.has(actor) and page.modes[slot % 256] in [world.Units.Mode.RESOURCE, world.Units.Mode.HARVEST]:
		var index: int = page.source_ids[slot % 256]
		if index >= 0 and index < world.source_objects.size():
			var source: int = world.source_objects[index]
			if world.objects.records.has(source) and (target == 0 or source == target): denied = not world.OperationQuery.access_reason(world.Operations.OPERATIONS.harvest, world.operation_actor(actor), world.operation_target(source), {"item": "wood", "purpose": str(world.work_runs.get(actor, {}).get("purpose", "cultivate"))}, world.facilities.definitions).is_empty()
	if denied:
		world.end_run(actor, world.operation_time(), "not_authorized", Results.refused("not_authorized"))
		world.clear_navigation(actor)
	if world.objects.records[actor].get("autonomous", false): world.decisions.wake(world, actor, world.operation_time(), "permissions_changed")

func create(name: String) -> int:
	assert(not name.is_empty() and name.length() <= 80)
	var id: int = next_organization
	next_organization += 1
	organizations[id] = {"id": id, "name": name}
	memberships[id] = {}
	accounts[id] = {}
	return id

func admit(world: RefCounted, organization: int, actor: int, grants: Array) -> bool:
	if not organizations.has(organization) or not world.actor_slots.has(actor): return false
	for purpose: Variant in grants:
		if purpose not in PURPOSES or grants.count(purpose) != 1: return false
	memberships[organization][actor] = grants.duplicate()
	reconcile(world, actor)
	return true

func permits(actor: int, organization: int, purpose: String) -> bool:
	return purpose in memberships.get(organization, {}).get(actor, [])

func transfer_context_valid(context: Dictionary) -> bool:
	if context.has("shipment") and (not context.shipment is int or not shipments.has(context.shipment)): return false
	if context.has("purpose") and (not context.purpose is String or (not context.purpose.is_empty() and context.purpose not in ISSUE_PURPOSES)): return false
	if context.has("donate") and not context.donate is bool: return false
	if context.has("source_organization") and (not context.source_organization is int or (context.source_organization != 0 and not organizations.has(context.source_organization))): return false
	if context.has("origins"):
		if not context.origins is Array or context.origins.size() > Matters.SOURCE_LIMIT: return false
		for origin: Variant in context.origins:
			if not origin is int or origin < 1 or context.origins.count(origin) != 1: return false
	return true

func permissions(actor: int) -> Dictionary:
	var result: Dictionary = {}
	for organization: int in memberships:
		if memberships[organization].has(actor): result[organization] = memberships[organization][actor].duplicate()
	return result

func bundles(world: RefCounted, actor: int, view: Dictionary = {}) -> Array:
	var result: Array = []
	if view.is_empty(): view = access_view(world, actor)
	for right: Dictionary in world.objects.groups(actor):
		var purpose: String = ""
		if right != Stock.right(actor):
			var mandate: Dictionary = entrustments.get(int(right.entrust), {})
			if mandate.is_empty() or mandate.custodian != actor or right.owner != 0 or right.organization != mandate.organization or right.phase != "issued": continue
			purpose = mandate.purpose
		var bundle: Dictionary = right.duplicate()
		bundle["purpose"] = purpose
		bundle["origin"] = int(entrustments.get(int(right.entrust), {}).get("origin", 0))
		bundle["items"] = world.objects.inventory_summary(actor, right)
		if right.entrust > 0:
			for item: String in bundle.items.keys():
				if not Stock.permits_purpose(view, int(right.organization), purpose, item): bundle.items.erase(item)
			if bundle.items.is_empty(): continue
		result.append(bundle)
	return result

func input_right(world: RefCounted, actor: int, required: Dictionary, purpose: String, organization: int = 0) -> Dictionary:
	return Stock.input_group({"bundles": bundles(world, actor)}, required, purpose, organization)

func readable(world: RefCounted, actor: int, available: Variant = null) -> Dictionary:
	var result: Dictionary = world.objects.usable_summary(actor)
	if available == null: available = bundles(world, actor)
	for bundle: Dictionary in available:
		if bundle.purpose == "study":
			for item: String in bundle.items: result[item] = int(result.get(item, 0)) + int(bundle.items[item])
	return result

func returns(world: RefCounted, actor: int) -> Array:
	var result: Array = []
	for right: Dictionary in world.objects.groups(actor):
		if right.entrust > 0 and entrustments.has(right.entrust) and not result.has(right.organization): result.append(right.organization)
	return result

func return_bundles(world: RefCounted, actor: int) -> Array:
	# Knowing what one carries does not grant permission to use it. Revoked
	# mandates are deliberately present here so their physical stock can return.
	var result: Array = []
	for right: Dictionary in world.objects.groups(actor):
		if right.entrust <= 0 or not entrustments.has(right.entrust): continue
		var bundle: Dictionary = right.duplicate()
		bundle["purpose"] = str(entrustments[right.entrust].purpose)
		bundle["origin"] = int(entrustments[right.entrust].origin)
		bundle["items"] = world.objects.inventory_summary(actor, right)
		result.append(bundle)
	return result

func equipment_right(world: RefCounted, actor: int, item: String) -> Dictionary:
	if world.objects.amount(actor, item, Stock.right(actor)) > 0: return Stock.right(actor)
	for bundle: Dictionary in bundles(world, actor):
		if int(bundle.items.get(item, 0)) > 0 and (bundle.owner == actor or bundle.purpose == "equip"): return Stock.attribution(bundle)
	return {}

func _mandate(actor: int, organization: int, purpose: String, now: int, origin: int = 0, shipment: int = 0) -> int:
	for id: int in entrustments:
		var record: Dictionary = entrustments[id]
		if shipment == 0 and record.custodian == actor and record.organization == organization and record.purpose == purpose and record.origin == origin and not _entrust_shipment.has(int(record.id)): return id
	var id: int = next_entrust
	next_entrust += 1
	entrustments[id] = {"id": id, "organization": organization, "custodian": actor, "purpose": purpose,
		"issued": {}, "consumed": {}, "produced": {}, "delivered": {}, "returned": {}, "created_ms": now, "updated_ms": now, "origin": origin}
	return id

static func _add(counter: Dictionary, item: String, amount: int) -> void:
	if amount > 0: counter[item] = int(counter.get(item, 0)) + amount

func _account(organization: int, actor: int) -> Dictionary:
	if not accounts[organization].has(actor):
		var entry: Dictionary = {"completed": 0}
		for field: String in COUNTERS: entry[field] = {}
		accounts[organization][actor] = entry
	return accounts[organization][actor]

func _close(id: int, now: int, changed: bool = true) -> void:
	if not entrustments.has(id): return
	var record: Dictionary = entrustments[id]
	if changed: record.updated_ms = now
	if record.issued.is_empty() and record.produced.is_empty():
		entrustments.erase(id)
		return
	for item: String in record.issued:
		if int(record.issued[item]) != int(record.consumed.get(item, 0)) + int(record.returned.get(item, 0)): return
	for item: String in record.produced:
		if int(record.produced[item]) != int(record.delivered.get(item, 0)): return
	var account: Dictionary = _account(record.organization, record.custodian)
	for field: String in COUNTERS:
		for item: String in record.get(field, {}): _add(account[field], item, int(record[field][item]))
	account.completed += 1
	entrustments.erase(id)

func move_goods(world: RefCounted, actor: int, target: int, item: String, requested: int, handler: String, context: Dictionary, now: int) -> Dictionary:
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor) or not world.objects.records.has(target) or not Items.valid(item) or requested <= 0 or handler not in ["take", "put"] or not transfer_context_valid(context): return Results.refused("invalid_transfer_context")
	var actor_view: Dictionary = world.operation_actor(actor)
	if handler == "put" and not Logistics.accepts(world, target, item): return Results.refused("storage_rejected")
	var shipment_id: int = int(context.get("shipment", 0))
	if shipment_id > 0:
		var shipment_reason: String = Logistics.transfer_reason(self, actor, target, item, requested, handler, shipment_id)
		if not shipment_reason.is_empty(): return Results.refused(shipment_reason)
	var target_view: Dictionary = world.operation_target(target, shipment_id)
	var access_context: Dictionary = context.duplicate(); access_context["item"] = item
	var access: String = Stock.access_reason(actor_view, target_view, handler, access_context)
	if not access.is_empty(): return Results.refused(access)
	var source: int = target if handler == "take" else actor
	var destination: int = actor if handler == "take" else target
	var amount: int = 0
	var mandates: Array = []
	var reason: String = "no_authorized_goods"
	var returned: int = 0
	var supply_returned: int = 0
	var deliveries: Array = []
	var corpse: bool = handler == "take" and world.actor_slots.has(source) and not world.combat.alive(world, source)
	var candidates: Array = world.objects.groups(source, corpse)
	var destination_org: int = int(world.objects.records[target].organization)
	if handler == "put" and destination_org > 0:
		# Returning this organization's entrusted stock precedes depositing one's
		# own goods. The latter retains its title unless donation is explicit.
		candidates.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.organization != destination_org or a.entrust == 0) < int(b.organization != destination_org or b.entrust == 0))
	for right: Dictionary in candidates:
		if amount >= requested or mandates.size() >= 64: break
		if handler == "put" and _entrust_shipment.has(int(right.entrust)) and int(_entrust_shipment[int(right.entrust)]) != shipment_id: continue
		if shipment_id > 0:
			var shipment: Dictionary = shipments[shipment_id]
			if handler == "take" and right != shipment.right: continue
			if handler == "put" and int(right.entrust) != int(shipment.entrust): continue
		var replacement: Dictionary = right
		var mandate: Dictionary = entrustments.get(int(right.entrust), {})
		var accounting: String = ""
		var organization: int = int(world.objects.records[target].organization)
		var batch_place: Dictionary = target_view.duplicate(); batch_place["organization"] = int(right.organization)
		var created: int = 0
		if handler == "take":
			var declared: String = str(context.get("purpose", ""))
			# An explicit issue request never silently retrieves a private deposit
			# or somebody's already-issued stock for a different purpose.
			if not declared.is_empty():
				if right.organization <= 0 or (int(context.get("source_organization", 0)) > 0 and right.organization != int(context.source_organization)): continue
				if right.entrust > 0 and mandate.get("purpose") != declared: continue
			if right == Stock.right(): replacement = Stock.right(actor)
			elif right == Stock.right(actor): pass
			elif right.organization > 0 and (Stock.permits_at(actor_view, batch_place, "take", item) or (right.entrust > 0 and (world.objects.records[target].kind == "pile" or corpse) and (mandate.get("custodian") == actor or Stock.permits_purpose(actor_view, right.organization, "supply", item)))):
				if right.entrust == 0:
					if world.objects.goods_amount(source, item, right, corpse) <= 0: continue
					var purpose: String = str(context.get("purpose", ""))
					if purpose.is_empty(): reason = "purpose_required"; continue
					if purpose not in ISSUE_PURPOSES: reason = "invalid_purpose"; continue
					if not Stock.permits_issue(actor_view, target_view, int(right.organization), purpose, item): reason = "not_authorized"; continue
					created = _mandate(actor, right.organization, purpose, now, source if purpose == "supply" else 0, shipment_id)
					mandate = entrustments[created]
					replacement = Stock.right(0, right.organization, created)
					accounting = "issued"
				elif mandate.is_empty() or mandate.organization != right.organization: continue
			else: continue
		else:
			if not str(context.get("purpose", "")).is_empty() and mandate.get("purpose", "") != context.purpose: continue
			if context.has("origins") and int(mandate.get("origin", 0)) not in context.origins: continue
			# Manual supply uses the same source policy as automatic shipments.
			# A contracted shipment already has its own accepted destination;
			# its cancellation/return lifecycle owns later policy changes.
			if shipment_id == 0 and mandate.get("purpose") == "supply" and int(mandate.get("origin", 0)) != destination and not Logistics.permits_delivery(world, int(mandate.origin), destination, item):
				reason = "supply_destination_required"; continue
			if context.get("donate", false) and right != Stock.right(actor): continue
			if organization > 0 and not Stock.permits_at(actor_view, target_view, "put", item) and not (right.organization == organization and right.entrust > 0 and target_view.kind in ["chest", "workbench"]): continue
			if right == Stock.right(actor):
				if context.get("donate", false):
					if organization <= 0 or not Stock.permits_at(actor_view, target_view, "put", item): continue
					replacement = Stock.right(0, organization)
					accounting = "donated"
			elif right.organization > 0:
				if organization != right.organization or (right.entrust == 0 and not Stock.permits_at(actor_view, target_view, "put", item)): continue
				if right.entrust > 0:
					if mandate.is_empty(): continue
					accounting = "returned" if right.phase == "issued" else "delivered"
					replacement = Stock.right(0, organization)
			elif right != Stock.right(): continue
		var supply_delivery: bool = accounting == "returned" and mandate.get("purpose") == "supply" and int(mandate.get("origin", 0)) != destination
		if supply_delivery and deliveries.size() >= 16: break # Publish complete bounded evidence for every adopted transfer.
		var moved: int = world.objects.transfer_possessions(source, destination, item, requested - amount, right, replacement, corpse, shipment_id)
		if moved <= 0:
			if created > 0: _close(created, now, false)
			continue
		amount += moved
		if accounting == "returned": returned += moved
		if accounting == "returned" and mandate.purpose == "supply": supply_returned += moved
		if supply_delivery: deliveries.append({"organization": int(right.organization), "origin": int(mandate.origin), "amount": moved})
		if accounting == "donated": _add(_account(organization, actor).donated, item, moved)
		elif not accounting.is_empty():
			_add(mandate[accounting], item, moved)
			mandate.updated_ms = now
			if not mandates.has(mandate.id): mandates.append(mandate.id)
			_close(mandate.id, now)
	if shipment_id > 0:
		Logistics.transferred(self, world, shipment_id, handler, amount, int(mandates[0]) if not mandates.is_empty() else 0, now)
	return Results.completed({"item": item, "requested": requested, "amount": amount, "returned": returned, "supply_returned": supply_returned, "deliveries": deliveries, "source": source, "destination": destination, "entrustments": mandates}, "transferred") if amount > 0 else Results.refused(reason)

func consume_at(world: RefCounted, actor: int, target: int, item: String, count: int, purpose: String) -> bool:
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor) or not world.objects.records.has(target) or not Items.valid(item) or count <= 0: return false
	var view: Dictionary = world.operation_actor(actor)
	var place: Dictionary = world.operation_target(target)
	if not Stock.access_reason(view, place, purpose, {"item": item}).is_empty(): return false
	for right: Dictionary in world.objects.groups(target):
		var legal: bool = right == Stock.right(actor) or right == Stock.right()
		var batch_place: Dictionary = place.duplicate(); batch_place["organization"] = int(right.organization)
		if right.organization > 0 and right.entrust == 0 and Stock.permits_at(view, batch_place, purpose, item): legal = true
		if legal and world.objects.consume(target, {item: count}, right): return true
	return false

func consumed(right: Dictionary, inputs: Dictionary, now: int) -> void:
	if right.entrust == 0: return
	assert(entrustments.has(right.entrust) and right.phase == "issued")
	for item: String in inputs: _add(entrustments[right.entrust].consumed, item, int(inputs[item]))
	_close(right.entrust, now)

func acquire_yield(world: RefCounted, actor: int, target: int, item: String, count: int, now: int, purpose: String = "cultivate") -> int:
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor) or not world.objects.records.has(target) or not Items.valid(item) or count <= 0 or purpose not in ISSUE_PURPOSES: return 0
	var object: Dictionary = world.objects.records[target]
	if object.owner == 0 and object.organization == 0: return world.objects.claim(target, actor, item, count)
	if object.owner == actor: return world.objects.transfer(target, actor, item, count, Stock.right(actor))
	if object.organization <= 0 or not Stock.permits_at(world.operation_actor(actor), world.operation_target(target), purpose, item): return 0
	if world.objects.amount(target, item, Stock.right(0, object.organization)) <= 0 or not world.objects.can_receive(actor, {item: 1}, Stock.right(0, object.organization, next_entrust)): return 0
	var id: int = _mandate(actor, object.organization, purpose, now, target if purpose == "supply" else 0)
	var moved: int = world.objects.transfer(target, actor, item, count, Stock.right(0, object.organization), Stock.right(0, object.organization, id))
	_add(entrustments[id].issued, item, moved)
	_close(id, now, moved > 0)
	return moved

func convert_at(world: RefCounted, target: int, inputs: Dictionary, outputs: Dictionary, right: Dictionary, now: int, field: String) -> Dictionary:
	var output_right: Dictionary = Stock.right(int(right.owner), int(right.organization))
	if field != "stock" or not world.objects.convert(target, inputs, outputs, right, int(world.objects.records[target].get("process", {}).get("id", 0))): return Results.refused("conversion_blocked")
	var mandate: Dictionary = entrustments.get(int(right.entrust), {})
	if not mandate.is_empty():
		for item: String in inputs: _add(mandate.consumed, item, int(inputs[item]))
		for item: String in outputs:
			_add(mandate.produced, item, int(outputs[item]))
			_add(mandate.delivered, item, int(outputs[item]))
		_close(mandate.id, now)
	return Results.completed({"consumed": inputs.duplicate(), "produced": outputs.duplicate(), "destination": target, "entrust": int(right.entrust), "output_owner": int(output_right.owner), "output_organization": int(output_right.organization)})

func complete_asset(world: RefCounted, target: int, field: String, now: int) -> Array:
	var used: Array = []
	var contents: Dictionary = world.objects.records[target].get(field, {})
	var groups: Dictionary = {}
	for item: String in contents:
		for batch: Dictionary in contents[item]:
			if batch.entrust == 0: continue
			var id: int = batch.entrust
			assert(batch.phase == "issued" and entrustments.has(id))
			_add(entrustments[id].consumed, item, int(batch.count))
			groups[id] = Stock.attribution(batch)
	for id: int in groups:
		world.objects.retitle(target, field, groups[id], Stock.right(0, groups[id].organization))
		used.append(id)
		_close(id, now)
	return used

func valid(world: RefCounted, bodies_ready: bool = true) -> bool:
	if not Departments.valid(self, world) or (bodies_ready and not Logistics.valid(self, world)): return false
	if next_organization < 1 or next_organization > Stock.MAX_COUNT or next_entrust < 1 or next_entrust > 999999999999: return false
	for id: Variant in organizations:
		if not id is int or id <= 0 or id >= next_organization or not organizations[id] is Dictionary or organizations[id].size() != 2 or not organizations[id].get("id") is int or organizations[id].id != id or not organizations[id].get("name") is String or organizations[id].name.is_empty() or organizations[id].name.length() > 80: return false
	if memberships.size() != organizations.size() or accounts.size() != organizations.size(): return false
	for organization: Variant in memberships:
		if not organizations.has(organization) or not memberships[organization] is Dictionary or not accounts.get(organization) is Dictionary: return false
		for actor: Variant in memberships[organization]:
			if not actor is int or actor <= 0 or actor >= world.objects.next_id or not memberships[organization][actor] is Array: return false
			for purpose: Variant in memberships[organization][actor]:
				if purpose not in PURPOSES or memberships[organization][actor].count(purpose) != 1: return false
	if not Access.valid(self, world) or not Matters.valid(self, world) or not Channels.valid(self, world): return false
	for id: Variant in entrustments:
		var record: Variant = entrustments[id]
		if not id is int or id <= 0 or id >= next_entrust or not record is Dictionary or record.size() != 12 or not record.get("id") is int or record.id != id or not record.get("organization") is int or not organizations.has(record.organization) or not record.get("custodian") is int or record.custodian <= 0 or record.custodian >= world.objects.next_id or record.get("purpose") not in PURPOSES: return false
		if not record.get("origin") is int or record.origin < 0 or record.origin >= world.objects.next_id or ((record.purpose == "supply") != (record.origin > 0)): return false
		if not record.get("created_ms") is int or not record.get("updated_ms") is int or record.created_ms < 0 or record.updated_ms < record.created_ms or record.updated_ms > world.elapsed_ms: return false
		for field: String in COUNTERS:
			if field != "donated" and not _counter_valid(record.get(field)): return false
	for organization: Variant in accounts:
		if not organizations.has(organization) or not accounts[organization] is Dictionary: return false
		for actor: Variant in accounts[organization]:
			var account: Variant = accounts[organization][actor]
			if not actor is int or actor <= 0 or actor >= world.objects.next_id or not account is Dictionary or account.size() != 7 or not account.get("completed") is int or account.completed < 0: return false
			for field: String in COUNTERS:
				if not _counter_valid(account.get(field)): return false
	var outstanding: Dictionary = {}
	for target: int in world.objects.records:
		var object: Dictionary = world.objects.records[target]
		if object.organization > 0 and not organizations.has(object.organization): return false
		var material: Array = []
		for field: String in ["stock", "materials"]:
			for batches: Array in object.get(field, {}).values(): material.append_array(batches)
		for gear: Dictionary in object.get("equipment", {}).values(): material.append(gear)
		for batch: Dictionary in material:
			if batch.organization > 0 and not organizations.has(batch.organization): return false
		# Preserve the item key when validating actual outstanding quantities.
		for field: String in ["stock", "materials"]:
			for item: String in object.get(field, {}):
				for batch: Dictionary in object[field][item]:
					if not _outstanding(outstanding, batch, item, int(batch.count)): return false
		for gear: Dictionary in object.get("equipment", {}).values():
			if not _outstanding(outstanding, gear, gear.item, 1): return false
	for id: int in entrustments:
		var record: Dictionary = entrustments[id]
		var expected: Dictionary = {"issued": {}, "produced": {}}
		for item: String in record.issued:
			var count: int = int(record.issued[item]) - int(record.consumed.get(item, 0)) - int(record.returned.get(item, 0))
			if count < 0: return false
			if count > 0: expected.issued[item] = count
		for item: String in record.consumed:
			if not record.issued.has(item): return false
		for item: String in record.returned:
			if not record.issued.has(item): return false
		for item: String in record.produced:
			var count: int = int(record.produced[item]) - int(record.delivered.get(item, 0))
			if count < 0: return false
			if count > 0: expected.produced[item] = count
		for item: String in record.delivered:
			if not record.produced.has(item): return false
		if expected.issued.is_empty() and expected.produced.is_empty(): return false
		if outstanding.get(id, {"issued": {}, "produced": {}}) != expected: return false
	return true

func _outstanding(result: Dictionary, right: Dictionary, item: String, count: int) -> bool:
	if right.entrust == 0: return true
	var record: Dictionary = entrustments.get(int(right.entrust), {})
	if record.is_empty() or right.owner != 0 or right.organization != record.organization: return false
	if not result.has(right.entrust): result[right.entrust] = {"issued": {}, "produced": {}}
	_add(result[right.entrust][right.phase], item, count)
	return true

static func _counter_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() > 256: return false
	for item: Variant in value:
		if not item is String or not Items.valid(item) or not value[item] is int or value[item] <= 0 or value[item] > 1000000000000000: return false
	return true
