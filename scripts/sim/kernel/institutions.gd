extends RefCounted
## Organization permissions and entrusted purpose, separate from physical custody.
## Historical counters are evidence, never another spendable stock balance.
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Results = preload("res://scripts/sim/kernel/activity_results.gd")
const STATE_FIELDS: Array = ["next_organization", "organizations", "memberships", "next_entrust", "entrustments", "accounts"]
const PURPOSES: Array[String] = ["take", "put", "eat", "rest", "cook", "construct", "demolish", "cultivate", "equip", "study", "supply"]
const ISSUE_PURPOSES: Array[String] = ["cook", "construct", "cultivate", "equip", "study", "supply"]
const COUNTERS: Array[String] = ["issued", "consumed", "produced", "delivered", "returned", "donated"]
var next_organization: int = 1
var organizations: Dictionary = {}
var memberships: Dictionary = {}
var next_entrust: int = 1
var entrustments: Dictionary = {}
var accounts: Dictionary = {}

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
	return true

func permits(actor: int, organization: int, purpose: String) -> bool:
	return purpose in memberships.get(organization, {}).get(actor, [])

func transfer_context_valid(context: Dictionary) -> bool:
	if context.has("purpose") and (not context.purpose is String or (not context.purpose.is_empty() and context.purpose not in ISSUE_PURPOSES)): return false
	if context.has("donate") and not context.donate is bool: return false
	if context.has("source_organization") and (not context.source_organization is int or (context.source_organization != 0 and not organizations.has(context.source_organization))): return false
	return true

func permissions(actor: int) -> Dictionary:
	var result: Dictionary = {}
	for organization: int in memberships:
		if memberships[organization].has(actor): result[organization] = memberships[organization][actor].duplicate()
	return result

func bundles(world: RefCounted, actor: int) -> Array:
	var result: Array = []
	for right: Dictionary in world.objects.groups(actor):
		var purpose: String = ""
		if right != Stock.right(actor):
			var mandate: Dictionary = entrustments.get(int(right.entrust), {})
			if mandate.is_empty() or mandate.custodian != actor or right.owner != 0 or right.organization != mandate.organization or right.phase != "issued" or not permits(actor, right.organization, mandate.purpose): continue
			purpose = mandate.purpose
		var bundle: Dictionary = right.duplicate()
		bundle["purpose"] = purpose
		bundle["items"] = world.objects.inventory_summary(actor, right)
		result.append(bundle)
	return result

func input_right(world: RefCounted, actor: int, required: Dictionary, purpose: String, organization: int = 0) -> Dictionary:
	return Stock.input_group({"bundles": bundles(world, actor)}, required, purpose, organization)

func readable(world: RefCounted, actor: int) -> Dictionary:
	var result: Dictionary = world.objects.usable_summary(actor)
	for bundle: Dictionary in bundles(world, actor):
		if bundle.purpose == "study":
			for item: String in bundle.items: result[item] = int(result.get(item, 0)) + int(bundle.items[item])
	return result

func returns(world: RefCounted, actor: int) -> Array:
	var result: Array = []
	for right: Dictionary in world.objects.groups(actor):
		if right.entrust > 0 and entrustments.has(right.entrust) and not result.has(right.organization): result.append(right.organization)
	return result

func equipment_right(world: RefCounted, actor: int, item: String) -> Dictionary:
	for bundle: Dictionary in bundles(world, actor):
		if int(bundle.items.get(item, 0)) > 0 and (bundle.owner == actor or bundle.purpose == "equip"): return Stock.attribution(bundle)
	return {}

func _mandate(actor: int, organization: int, purpose: String, now: int) -> int:
	for id: int in entrustments:
		var record: Dictionary = entrustments[id]
		if record.custodian == actor and record.organization == organization and record.purpose == purpose: return id
	var id: int = next_entrust
	next_entrust += 1
	entrustments[id] = {"id": id, "organization": organization, "custodian": actor, "purpose": purpose,
		"issued": {}, "consumed": {}, "produced": {}, "delivered": {}, "returned": {}, "created_ms": now, "updated_ms": now}
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
	var access: String = Stock.access_reason(world.operation_actor(actor), world.operation_target(target), handler)
	if not access.is_empty(): return Results.refused(access)
	var source: int = target if handler == "take" else actor
	var destination: int = actor if handler == "take" else target
	var amount: int = 0
	var mandates: Array = []
	var reason: String = "no_authorized_goods"
	var corpse: bool = handler == "take" and world.actor_slots.has(source) and not world.combat.alive(world, source)
	var candidates: Array = world.objects.groups(source, corpse)
	var destination_org: int = int(world.objects.records[target].organization)
	if handler == "put" and destination_org > 0:
		# Returning this organization's entrusted stock precedes depositing one's
		# own goods. The latter retains its title unless donation is explicit.
		candidates.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.organization != destination_org or a.entrust == 0) < int(b.organization != destination_org or b.entrust == 0))
	for right: Dictionary in candidates:
		if amount >= requested: break
		var replacement: Dictionary = right
		var mandate: Dictionary = entrustments.get(int(right.entrust), {})
		var accounting: String = ""
		var organization: int = int(world.objects.records[target].organization)
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
			elif right.organization > 0 and (permits(actor, right.organization, "take") or (right.entrust > 0 and (world.objects.records[target].kind == "pile" or corpse) and (mandate.get("custodian") == actor or permits(actor, right.organization, "supply")))):
				if right.entrust == 0:
					if world.objects.goods_amount(source, item, right, corpse) <= 0: continue
					var purpose: String = str(context.get("purpose", ""))
					if purpose.is_empty(): reason = "purpose_required"; continue
					if purpose not in ISSUE_PURPOSES: reason = "invalid_purpose"; continue
					if not permits(actor, right.organization, purpose): reason = "not_authorized"; continue
					created = _mandate(actor, right.organization, purpose, now)
					mandate = entrustments[created]
					replacement = Stock.right(0, right.organization, created)
					accounting = "issued"
				elif mandate.is_empty() or mandate.organization != right.organization: continue
			else: continue
		else:
			if context.get("donate", false) and right != Stock.right(actor): continue
			if organization > 0 and not permits(actor, organization, "put") and not (right.organization == organization and right.entrust > 0): continue
			if right == Stock.right(actor):
				if context.get("donate", false):
					if organization <= 0 or not permits(actor, organization, "put"): continue
					replacement = Stock.right(0, organization)
					accounting = "donated"
			elif right.organization > 0:
				if organization != right.organization or (right.entrust == 0 and not permits(actor, organization, "put")): continue
				if right.entrust > 0:
					if mandate.is_empty(): continue
					accounting = "returned" if right.phase == "issued" else "delivered"
					replacement = Stock.right(0, organization)
			elif right != Stock.right(): continue
		var moved: int = world.objects.transfer_possessions(source, destination, item, requested - amount, right, replacement, corpse)
		if moved <= 0:
			if created > 0: _close(created, now, false)
			continue
		amount += moved
		if accounting == "donated": _add(_account(organization, actor).donated, item, moved)
		elif not accounting.is_empty():
			_add(mandate[accounting], item, moved)
			mandate.updated_ms = now
			if not mandates.has(mandate.id): mandates.append(mandate.id)
			_close(mandate.id, now)
	return Results.completed({"item": item, "requested": requested, "amount": amount, "source": source, "destination": destination, "entrustments": mandates}, "transferred") if amount > 0 else Results.refused(reason)

func consume_at(world: RefCounted, actor: int, target: int, item: String, count: int, purpose: String) -> bool:
	for right: Dictionary in world.objects.groups(target):
		var legal: bool = right == Stock.right(actor) or right == Stock.right()
		if right.organization > 0 and right.entrust == 0 and permits(actor, right.organization, purpose): legal = true
		if legal and world.objects.consume(target, {item: count}, right): return true
	return false

func consumed(right: Dictionary, inputs: Dictionary, now: int) -> void:
	if right.entrust == 0: return
	assert(entrustments.has(right.entrust) and right.phase == "issued")
	for item: String in inputs: _add(entrustments[right.entrust].consumed, item, int(inputs[item]))
	_close(right.entrust, now)

func acquire_yield(world: RefCounted, actor: int, target: int, item: String, count: int, now: int) -> int:
	var object: Dictionary = world.objects.records[target]
	if object.owner == 0 and object.organization == 0: return world.objects.claim(target, actor, item, count)
	if object.owner == actor: return world.objects.transfer(target, actor, item, count, Stock.right(actor))
	if object.organization <= 0 or not permits(actor, object.organization, "cultivate"): return 0
	var id: int = _mandate(actor, object.organization, "cultivate", now)
	var moved: int = world.objects.transfer(target, actor, item, count, Stock.right(0, object.organization), Stock.right(0, object.organization, id))
	_add(entrustments[id].issued, item, moved)
	_close(id, now, moved > 0)
	return moved

func convert(world: RefCounted, actor: int, target: int, inputs: Dictionary, outputs: Dictionary, purpose: String, now: int) -> Dictionary:
	var organization: int = int(world.objects.records[target].organization)
	var right: Dictionary = input_right(world, actor, inputs, purpose, organization)
	if right.is_empty(): return Results.refused("missing_authorized_ingredients")
	var output_right: Dictionary = Stock.right(actor) if organization == 0 else Stock.right(0, organization)
	if not world.objects.can_receive(target, outputs, output_right): return Results.refused("no_output_capacity")
	if not world.objects.consume(actor, inputs, right): return Results.refused("missing_authorized_ingredients")
	var mandate: Dictionary = entrustments.get(int(right.entrust), {})
	for item: String in outputs: world.objects.add(target, item, int(outputs[item]), output_right)
	if not mandate.is_empty():
		for item: String in inputs: _add(mandate.consumed, item, int(inputs[item]))
		for item: String in outputs:
			_add(mandate.produced, item, int(outputs[item]))
			_add(mandate.delivered, item, int(outputs[item]))
		_close(mandate.id, now)
	return Results.completed({"consumed": inputs.duplicate(), "produced": outputs.duplicate(), "destination": target, "entrust": int(right.entrust)})

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

func valid(world: RefCounted) -> bool:
	if next_organization < 1 or next_organization > Stock.MAX_COUNT or next_entrust < 1 or next_entrust > 999999999999: return false
	for id: Variant in organizations:
		if not id is int or id <= 0 or id >= next_organization or not organizations[id] is Dictionary or organizations[id].size() != 2 or organizations[id].get("id") != id or not organizations[id].get("name") is String or organizations[id].name.is_empty() or organizations[id].name.length() > 80: return false
	if memberships.size() != organizations.size() or accounts.size() != organizations.size(): return false
	for organization: Variant in memberships:
		if not organizations.has(organization) or not memberships[organization] is Dictionary or not accounts.get(organization) is Dictionary: return false
		for actor: Variant in memberships[organization]:
			if not actor is int or actor <= 0 or actor >= world.objects.next_id or not memberships[organization][actor] is Array: return false
			for purpose: Variant in memberships[organization][actor]:
				if purpose not in PURPOSES or memberships[organization][actor].count(purpose) != 1: return false
	for id: Variant in entrustments:
		var record: Variant = entrustments[id]
		if not id is int or id <= 0 or id >= next_entrust or not record is Dictionary or record.size() != 11 or record.get("id") != id or not organizations.has(record.get("organization")) or not record.get("custodian") is int or record.custodian <= 0 or record.custodian >= world.objects.next_id or record.get("purpose") not in PURPOSES: return false
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
