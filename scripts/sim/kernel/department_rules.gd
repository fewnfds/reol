extends RefCounted
## Rules over Institutions' canonical departmental records. Titles carry no authority.
const State = preload("res://scripts/sim/kernel/state.gd")
const CAPABILITIES: Array[String] = ["view", "people", "facilities", "production", "supply", "delegate"]
const DUTIES: Array[String] = ["produce", "haul", "gather", "cultivate"]
const LIMIT: int = 256

static func create(owner: RefCounted, organization: int, title: String, parent: int = 0) -> int:
	if parent < 0 or owner.departments.size() >= LIMIT or not owner.organizations.has(organization) or title.strip_edges().is_empty() or title.length() > 80: return 0
	if parent > 0 and owner.departments.get(parent, {}).get("organization") != organization: return 0
	var ancestor: int = parent
	for depth: int in 16:
		if ancestor == 0: break
		if depth == 15: return 0
		ancestor = int(owner.departments[ancestor].parent)
	var id: int = owner.next_department
	owner.next_department += 1
	owner.departments[id] = {"id": id, "organization": organization, "title": title, "parent": parent, "head": 0, "facilities": [], "workers": {}, "groups": {}, "grants": {}, "revision": 1, "production": {}, "supplier": 0}
	owner.department_revision += 1
	owner.people_revision += 1
	owner._department_index_dirty = true
	return id

static func rebuild(owner: RefCounted) -> void:
	owner._work_departments.clear()
	owner._labor_targets.clear()
	owner._management_departments.clear()
	owner._facility_department.clear()
	owner._department_children.clear()
	for id: int in owner.departments:
		var dept: Dictionary = owner.departments[id]
		if not owner._department_children.has(int(dept.parent)): owner._department_children[int(dept.parent)] = []
		owner._department_children[int(dept.parent)].append(id)
		for actor: int in dept.workers:
			if not owner._work_departments.has(actor): owner._work_departments[actor] = []
			owner._work_departments[actor].append(id)
			if not owner._labor_targets.has(actor): owner._labor_targets[actor] = {}
			var assignment: Dictionary = dept.workers[actor]
			var targets: Dictionary = {}
			if assignment.department_wide:
				for target: int in dept.facilities: targets[target] = true
			else:
				for group: String in assignment.groups:
					for target: int in dept.groups[group].facilities: targets[target] = true
			for duty: String in assignment.duties:
				if not owner._labor_targets[actor].has(duty): owner._labor_targets[actor][duty] = {}
				owner._labor_targets[actor][duty].merge(targets)
		for actor: int in dept.grants:
			if not owner._management_departments.has(actor): owner._management_departments[actor] = []
			owner._management_departments[actor].append(id)
		for facility: int in dept.facilities: owner._facility_department[facility] = id
	owner._department_index_dirty = false

static func ensure(owner: RefCounted) -> void:
	if owner._department_index_dirty: rebuild(owner)

static func changed(owner: RefCounted, department: int, structural: bool = false) -> void:
	owner.department_revision += 1
	if owner.departments.has(department): owner.departments[department].revision += 1
	if structural:
		owner._department_index_dirty = true
		owner.people_revision += 1
	owner.Workflow.dirty(owner, department)

static func touch(owner: RefCounted) -> void:
	owner.department_revision += 1

static func allowed(owner: RefCounted, actor: int, department: int, capability: String, group: String = "", inheritable: bool = false) -> bool:
	return _authority_department(owner, actor, department, capability, group, inheritable) > 0

static func _authority_department(owner: RefCounted, actor: int, department: int, capability: String, group: String, inheritable: bool = false) -> int:
	ensure(owner)
	var current: int = department
	for depth: int in 16:
		var dept: Dictionary = owner.departments.get(current, {})
		if dept.is_empty(): return 0
		var grant: Dictionary = dept.grants.get(actor, {})
		if capability in grant.get("capabilities", []) and (not inheritable or grant.get("descendants", false)) and (current == department or grant.get("descendants", false)):
			var scope: String = str(grant.get("group", ""))
			if scope.is_empty() or (current == department and not group.is_empty() and scope == group): return current
		current = int(dept.parent)
		if current == 0: break
	return 0

static func grant(owner: RefCounted, department: int, actor: int, title: String, capabilities: Array, descendants: bool = false, group: String = "", issuer: int = 0) -> bool:
	var dept: Dictionary = owner.departments.get(department, {})
	if dept.is_empty() or not owner.memberships.get(int(dept.organization), {}).has(actor) or title.length() > 80: return false
	if not group.is_empty() and not dept.groups.has(group): return false
	for value: Variant in capabilities:
		if not value is String or value not in CAPABILITIES or capabilities.count(value) != 1: return false
	dept.grants[actor] = {"title": title, "capabilities": capabilities.duplicate(), "descendants": descendants, "group": group, "issuer": issuer}
	changed(owner, department, true)
	return true

static func assign(owner: RefCounted, department: int, actor: int, duties: Array, groups: Array = [], department_wide: bool = false) -> bool:
	var dept: Dictionary = owner.departments.get(department, {})
	if dept.is_empty() or not owner.memberships.get(int(dept.organization), {}).has(actor): return false
	for value: Variant in duties:
		if not value is String or value not in DUTIES or duties.count(value) != 1: return false
	for value: Variant in groups:
		if not value is String or not dept.groups.has(value) or groups.count(value) != 1: return false
	dept.workers[actor] = {"duties": duties.duplicate(), "groups": groups.duplicate(), "department_wide": department_wide}
	changed(owner, department, true)
	return true

static func attach(owner: RefCounted, world: RefCounted, department: int, facility: int) -> bool:
	ensure(owner)
	var dept: Dictionary = owner.departments.get(department, {})
	var record: Dictionary = world.objects.records.get(facility, {})
	if dept.is_empty() or record.get("kind", "actor") == "actor" or record.get("organization") != dept.organization or int(record.get("owner", 0)) != 0: return false
	if owner._facility_department.has(facility): return int(owner._facility_department[facility]) == department
	dept.facilities.append(facility)
	changed(owner, department, true)
	return true

static func worker_targets(owner: RefCounted, actor: int, duty: String = "", department: int = 0) -> Array:
	ensure(owner)
	var result: Array = []
	for id: int in owner._work_departments.get(actor, []):
		if department > 0 and id != department: continue
		var dept: Dictionary = owner.departments[id]
		var assignment: Dictionary = dept.workers[actor]
		if assignment.duties.is_empty() or (not duty.is_empty() and duty not in assignment.duties): continue
		if assignment.department_wide:
			for target: int in dept.facilities:
				if target not in result: result.append(target)
		else:
			for group: String in assignment.groups:
				for target: int in dept.groups[group].facilities:
					if target not in result: result.append(target)
	return result

static func labor_allowed(owner: RefCounted, actor: int, target: int, duty: String) -> bool:
	ensure(owner)
	# Unmanaged legacy content keeps its own authority until migrated.
	if not owner._facility_department.has(target): return true
	return owner._labor_targets.get(actor, {}).get(duty, {}).has(target)

static func grants(owner: RefCounted, actor: int) -> Array:
	ensure(owner)
	var result: Array = []
	for id: int in owner._work_departments.get(actor, []):
		var dept: Dictionary = owner.departments[id]
		var duties: Array = dept.workers[actor].duties
		var purposes: Array = []
		if "haul" in duties: purposes.append_array(["take", "put", "supply"])
		if "produce" in duties: purposes.append_array(["produce", "cook"])
		if "gather" in duties or "cultivate" in duties: purposes.append_array(["cultivate", "supply", "take", "put"])
		var targets: Array = worker_targets(owner, actor, "", id)
		if targets.is_empty() or purposes.is_empty(): continue
		result.append({"organization": dept.organization, "targets": targets, "purposes": purposes, "items": [], "all_items": true})
	return result

static func _delegate_origin(owner: RefCounted, actor: int, department: int) -> Dictionary:
	var current: int = department
	for depth: int in 16:
		var d: Dictionary = owner.departments.get(current, {})
		if d.is_empty(): break
		var g: Dictionary = d.grants.get(actor, {})
		# Issuer ancestry is provenance, not this former delegate's current
		# authority. Revoking descendants must not hide their superior's identity.
		if not g.is_empty(): return g
		current = int(d.parent)
	return {}

static func can_replace_grant(owner: RefCounted, actor: int, department: int, previous: Dictionary) -> bool:
	if previous.is_empty(): return true
	var issuer: int = int(previous.issuer)
	var seen: Dictionary = {}
	for depth: int in 32:
		if issuer == actor: return true
		if issuer == 0 or seen.has(issuer): return false
		seen[issuer] = true
		issuer = int(_delegate_origin(owner, issuer, department).get("issuer", 0))
	return false

static func manages_person(owner: RefCounted, actor: int, subject: int) -> bool:
	if actor == subject: return false
	ensure(owner)
	# Scope the lookup to the subject's current work and personnel roles.
	for id: int in owner._work_departments.get(subject, []) + owner._management_departments.get(subject, []):
		var department: Dictionary = owner.departments[id]
		var grant: Dictionary = department.grants.get(subject, {})
		var assignment: Dictionary = department.workers.get(subject, {})
		var groups: Array
		if "people" in grant.get("capabilities", []):
			if not can_replace_grant(owner, actor, id, grant): continue
			groups = [str(grant.group)]
		else:
			if assignment.get("duties", []).is_empty(): continue
			groups = [""] if assignment.department_wide else assignment.groups
		for group: String in groups:
			var origin: int = _authority_department(owner, actor, id, "people", group)
			if origin == 0: continue
			var own: Dictionary = owner.departments[origin].grants[actor]
			if not can_replace_grant(owner, subject, origin, own): return true
	return false

static func command(owner: RefCounted, world: RefCounted, actor: int, request: Dictionary) -> String:
	for field: String in ["department", "revision", "worker", "facility", "process"]:
		if request.has(field) and not request[field] is int: return "invalid_configuration"
	for field: String in ["op", "group", "title", "mode"]:
		if request.has(field) and not request[field] is String: return "invalid_configuration"
	if request.has("department_wide") and not request.department_wide is bool: return "invalid_configuration"
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor): return "dead"
	var id: int = int(request.get("department", 0))
	var dept: Dictionary = owner.departments.get(id, {})
	if dept.is_empty(): return "department_gone"
	var op: String = str(request.get("op", ""))
	var capability: String = str({"assign": "people", "group": "people", "coordinator": "people", "grant": "delegate", "attach": "facilities", "create": "delegate", "batch": "production", "member": "people", "order": "production", "configure": "production", "order_control": "production", "supplier": "supply", "request_supply": "supply", "accept_supply": "supply", "storage": "supply", "cancel_supply": "supply"}.get(op, ""))
	var group: String = str(request.get("group", ""))
	if not group.is_empty() and not dept.groups.has(group) and op != "group": return "invalid_configuration"
	if capability.is_empty() or not allowed(owner, actor, id, capability, group): return "not_authorized"
	if op in ["group", "attach", "create"] and not allowed(owner, actor, id, capability): return "not_authorized"
	if op in ["assign", "grant", "member"] and (not world.actor_slots.has(int(request.get("worker", 0))) or not world.combat.alive(world, int(request.get("worker", 0))) or not owner.memberships.get(int(dept.organization), {}).has(int(request.get("worker", 0)))): return "invalid_worker"
	if request.has("revision") and request.revision != dept.revision: return "configuration_changed"
	if op in ["order", "configure", "order_control", "supplier", "request_supply", "accept_supply", "storage", "cancel_supply"]:
		return owner.Workflow.command(owner, world, actor, request)
	match op:
		"coordinator":
			var worker: int = int(request.get("worker", 0))
			if not group.is_empty(): return "not_authorized"
			if worker > 0 and (not world.actor_slots.has(worker) or not world.combat.alive(world, worker) or not allowed(owner, worker, id, "supply")): return "invalid_worker"
			if worker < 0: return "invalid_worker"
			dept.head = worker
			changed(owner, id)
			if worker > 0: owner.reconcile(world, worker)
		"assign":
			if not request.get("duties") is Array or not request.get("groups", []) is Array: return "invalid_configuration"
			var worker: int = int(request.get("worker", 0))
			if not group.is_empty(): return "not_authorized" # Group membership has a separate, non-destructive operation.
			if not assign(owner, id, worker, request.duties, request.get("groups", []), request.get("department_wide", false)): return "invalid_configuration"
			owner.reconcile(world, worker)
		"group":
			if group.is_empty() or group.length() > 40 or not request.get("facilities") is Array: return "invalid_configuration"
			for facility: Variant in request.facilities:
				if not facility is int or facility not in dept.facilities or request.facilities.count(facility) != 1: return "invalid_configuration"
			dept.groups[group] = {"facilities": request.facilities.duplicate()}
			for target: int in dept.production.keys():
				var order: Dictionary = owner.matters.get(int(dept.production[target].order), {})
				if order.get("group") == group and target not in request.facilities: dept.production.erase(target)
			changed(owner, id, true)
			for worker: int in dept.workers: owner.reconcile(world, worker)
		"member":
			var worker: int = int(request.get("worker", 0))
			if group.is_empty() or not dept.groups.has(group) or not request.get("enabled") is bool: return "invalid_configuration"
			var config: Dictionary = dept.workers.get(worker, {"duties": [], "groups": [], "department_wide": false})
			if config.department_wide: return "not_authorized"
			if request.enabled and group not in config.groups: config.groups.append(group)
			elif not request.enabled: config.groups.erase(group)
			dept.workers[worker] = config
			changed(owner, id, true)
			owner.reconcile(world, worker)
		"batch":
			var target: int = int(request.get("facility", 0))
			if target not in dept.facilities or (not group.is_empty() and target not in dept.groups[group].facilities): return "not_authorized"
			var reason: String = world.Production.control(world, target, int(request.get("process", 0)), str(request.get("mode", "")), world.operation_time())
			if reason != "management_updated": return reason
			changed(owner, id)
		"grant":
			if not request.get("capabilities") is Array: return "invalid_configuration"
			for right: Variant in request.capabilities:
				if not right is String or not allowed(owner, actor, id, right, group): return "not_authorized"
			if not request.get("descendants", false) is bool: return "invalid_configuration"
			if request.get("descendants", false):
				if not group.is_empty(): return "not_authorized"
				for right: String in request.capabilities + ["delegate"]:
					if not allowed(owner, actor, id, right, "", true): return "not_authorized"
			var worker: int = int(request.get("worker", 0))
			var previous: Dictionary = dept.grants.get(worker, {})
			if not previous.is_empty() and not group.is_empty() and previous.group != group: return "not_authorized"
			if worker == actor: return "not_authorized"
			if not can_replace_grant(owner, actor, id, previous): return "not_authorized"
			if previous.get("descendants", false) and not allowed(owner, actor, id, "delegate", "", true): return "not_authorized"
			if not grant(owner, id, worker, str(request.get("title", "")), request.capabilities, request.get("descendants", false), group, actor): return "invalid_configuration"
			owner.reconcile(world, worker)
		"attach":
			if not attach(owner, world, id, int(request.get("facility", 0))): return "invalid_configuration"
		"create":
			if create(owner, int(dept.organization), str(request.get("title", "")), id) <= 0: return "invalid_configuration"
	return "management_updated"

static func view(owner: RefCounted, world: RefCounted, actor: int, selected: int = 0, requested_group: String = "", page: int = 0) -> Dictionary:
	ensure(owner)
	var accessible: Dictionary = {}
	for id: int in owner._work_departments.get(actor, []): accessible[id] = true
	var pending: Array = owner._management_departments.get(actor, []).duplicate()
	while not pending.is_empty():
		var id: int = int(pending.pop_back())
		accessible[id] = true
		for child: int in owner._department_children.get(id, []):
			if CAPABILITIES.any(func(capability: String): return allowed(owner, actor, child, capability)): pending.append(child)
	var result: Dictionary = {"actor": actor, "revision": owner.department_revision, "departments": [], "selected": {}, "at_ms": world.operation_time(), "request": {"department": selected, "group": requested_group, "page": page}}
	for id: int in accessible:
		var d: Dictionary = owner.departments[id]
		result.departments.append({"id": id, "title": d.title, "parent": d.parent})
	if not accessible.has(selected): selected = int(accessible.keys()[0]) if not accessible.is_empty() else 0
	if selected == 0: return result
	var dept: Dictionary = owner.departments[selected]
	var scopes: Array = []
	if CAPABILITIES.any(func(capability: String): return allowed(owner, actor, selected, capability)): scopes.append("")
	for group: String in dept.groups:
		if CAPABILITIES.any(func(capability: String): return allowed(owner, actor, selected, capability, group)): scopes.append(group)
	var scope: String = requested_group if requested_group in scopes else (str(scopes[0]) if not scopes.is_empty() else "")
	var capabilities: Array = []
	for capability: String in CAPABILITIES:
		if allowed(owner, actor, selected, capability, scope): capabilities.append(capability)
	var detail: Dictionary = {"id": selected, "title": dept.title, "revision": dept.revision, "parent": dept.parent, "capabilities": capabilities, "workers": [], "groups": {}, "facilities": [], "scope": scope, "scopes": scopes, "candidates": [], "grants": {}}
	var managed: bool = not capabilities.is_empty()
	detail["head"] = dept.head
	detail["my_work"] = owner.Workflow.personal(owner, world, actor, selected, scope)
	for worker: int in dept.workers:
		var config: Dictionary = dept.workers[worker]
		if not managed and worker != actor: continue
		if not scope.is_empty() and not config.department_wide and scope not in config.groups: continue
		var configuration: Dictionary = State.copy(config)
		if not scope.is_empty(): configuration.groups = [scope] if scope in config.groups else []
		configuration.merge({"id": worker, "name": world.objects.records.get(worker, {}).get("name", str(worker)), "role": dept.grants.get(worker, {}).get("title", "成员"), "working": world.gate.current(worker).get("domain", "idle")})
		detail.workers.append(configuration)
	if managed:
		for worker: int in dept.grants:
			if scope.is_empty() or dept.grants[worker].group == scope: detail.grants[worker] = State.copy(dept.grants[worker])
		for group: String in dept.groups:
			if scope.is_empty() or scope == group: detail.groups[group] = State.copy(dept.groups[group])
		var targets: Array = dept.facilities if scope.is_empty() else dept.groups[scope].facilities
		for facility: int in targets:
			var record: Dictionary = world.objects.records.get(facility, {})
			if record.is_empty(): continue
			detail.facilities.append({"id": facility, "definition": record.definition, "inventory": world.objects.inventory_summary(facility), "capacity": record.capacity, "reserved_capacity": world.objects.reserved_capacity(facility), "storage_policy": State.copy(record.get("storage_policy", {})), "process": world.Production.view(record, world.actions.get(world.reservations.get(facility, 0), {}), world.operation_time())})
		if page in [1, 5] and ("people" in capabilities or "delegate" in capabilities):
			for worker: int in owner.memberships[int(dept.organization)]:
				if world.actor_slots.has(worker) and world.combat.alive(world, worker): detail.candidates.append({"id": worker, "name": world.objects.records[worker].get("name", str(worker))})
	detail["orders"] = owner.Orders.view(owner, selected, scope) if managed else []
	detail["parent_orders"] = []
	if managed and not scope.is_empty():
		for order: Dictionary in owner.Orders.list(owner, selected):
			if order.parent_order == 0 and order.state == "active": detail.parent_orders.append({"id": order.id, "operation": order.operation, "item": order.item, "unallocated": owner.Orders.unallocated(owner, order)})
	detail["production"] = {}
	if managed:
		for target: int in dept.production:
			if scope.is_empty() or target in dept.groups[scope].facilities: detail.production[target] = State.copy(dept.production[target])
	detail["supplier"] = dept.supplier
	detail["supply_requests"] = []
	detail["suppliers"] = []
	if managed:
		for d: Dictionary in owner.departments.values():
			if d.organization == dept.organization and d.id != selected: detail.suppliers.append({"id": d.id, "title": d.title})
		owner.Logistics.ensure(owner)
		for id: int in owner._requests_by_department.get(selected, []) + owner._requests_by_supplier.get(selected, []) + owner._recent_supply.get(selected, []):
			var request: Dictionary = owner.supply_requests[id]
			if not scope.is_empty() and request.target not in dept.groups[scope].facilities: continue
			var value: Dictionary = State.copy(request)
			value["in_transit"] = int(request.amount) - int(request.received) - owner.Logistics.request_outstanding(owner, id)
			detail.supply_requests.append(value)
	if not managed:
		for target: int in worker_targets(owner, actor, "", selected):
			var record: Dictionary = world.objects.records.get(target, {})
			if not record.is_empty(): detail.facilities.append({"id": target, "definition": record.definition, "inventory": world.objects.inventory_summary(target), "capacity": record.capacity, "reserved_capacity": world.objects.reserved_capacity(target), "process": world.Production.view(record, world.actions.get(world.reservations.get(target, 0), {}), world.operation_time())})
	result.selected = detail
	return result

static func valid(owner: RefCounted, world: RefCounted) -> bool:
	if owner.next_department < 1 or owner.department_revision < 1 or owner.departments.size() > LIMIT: return false
	var facilities: Dictionary = {}
	for id: Variant in owner.departments:
		var d: Variant = owner.departments[id]
		if not id is int or id <= 0 or id >= owner.next_department or not d is Dictionary: return false
		if d.size() != 12 or not d.get("id") is int or d.id != id or not d.get("organization") is int or not owner.organizations.has(d.organization) or not d.get("title") is String or d.title.strip_edges().is_empty() or d.title.length() > 80: return false
		if not d.get("parent") is int or not d.get("head") is int or not d.get("revision") is int or d.revision < 1 or not d.get("facilities") is Array or not d.get("workers") is Dictionary or not d.get("groups") is Dictionary or not d.get("grants") is Dictionary: return false
		if d.head < 0 or (d.head > 0 and not owner.memberships.get(d.organization, {}).has(d.head)): return false
		if not d.get("supplier") is int or (d.supplier != 0 and owner.departments.get(d.supplier, {}).get("organization") != d.organization) or not d.get("production") is Dictionary: return false
		for target: Variant in d.production:
			var c: Variant = d.production[target]
			if not target is int or target not in d.facilities or not c is Dictionary or c.size() != 2 or not c.get("order") is int or owner.matters.get(c.order, {}).get("department") != id or c.get("operation") != owner.matters[c.order].operation: return false
			var group: Variant = owner.matters[c.order].get("group")
			if not group is String or (not group.is_empty() and target not in d.groups.get(group, {}).get("facilities", [])): return false
		var parent: int = d.parent
		for depth: int in 16:
			if parent == 0: break
			if parent == id or owner.departments.get(parent, {}).get("organization") != d.organization or depth == 15: return false
			parent = int(owner.departments[parent].get("parent", -1))
		for target: Variant in d.facilities:
			if not target is int or facilities.has(target) or world.objects.records.get(target, {}).get("organization") != d.organization or world.objects.records[target].kind == "actor" or world.objects.records[target].owner != 0: return false
			facilities[target] = true
		for group: Variant in d.groups:
			if not group is String or group.is_empty() or group.length() > 40 or not d.groups[group] is Dictionary or d.groups[group].size() != 1 or not d.groups[group].get("facilities") is Array: return false
			for target: Variant in d.groups[group].facilities:
				if target not in d.facilities or d.groups[group].facilities.count(target) != 1: return false
		for worker: Variant in d.workers:
			if not worker is int or not owner.memberships[d.organization].has(worker) or not d.workers[worker] is Dictionary: return false
			var config: Dictionary = d.workers[worker]
			if config.size() != 3 or not config.get("department_wide") is bool or not config.get("duties") is Array or not config.get("groups") is Array: return false
			for duty: Variant in config.duties:
				if duty not in DUTIES or config.duties.count(duty) != 1: return false
			for group: Variant in config.groups:
				if not d.groups.has(group) or config.groups.count(group) != 1: return false
		for worker: Variant in d.grants:
			if not worker is int or not owner.memberships[d.organization].has(worker) or not d.grants[worker] is Dictionary: return false
			var g: Dictionary = d.grants[worker]
			if g.size() != 5 or not g.get("title") is String or g.title.length() > 80 or not g.get("issuer") is int or g.issuer < 0 or g.issuer >= world.objects.next_id or not g.get("capabilities") is Array or not g.get("descendants") is bool or not g.get("group") is String or (not g.group.is_empty() and (not d.groups.has(g.group) or g.descendants)): return false
			for capability: Variant in g.capabilities:
				if capability not in CAPABILITIES or g.capabilities.count(capability) != 1: return false
	return true
