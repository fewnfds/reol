extends RefCounted
## Department obligations use Institutions.matters; no personal Share is minted.
const State = preload("res://scripts/sim/kernel/state.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
const DAY_MS: int = 1200000

static func ensure(owner: RefCounted) -> void:
	if not owner._orders_dirty: return
	owner._orders_by_department.clear()
	for id: int in owner.matters:
		var m: Dictionary = owner.matters[id]
		if m.kind != "department": continue
		if not owner._orders_by_department.has(int(m.department)): owner._orders_by_department[int(m.department)] = []
		owner._orders_by_department[int(m.department)].append(id)
	owner._orders_dirty = false

static func create(owner: RefCounted, world: RefCounted, actor: int, department: int, operation: String, item: String, total: int, group: String = "", parent: int = 0, repeat: bool = false) -> int:
	var dept: Dictionary = owner.departments.get(department, {})
	var recipe: Dictionary = Operations.OPERATIONS.get(operation, {}).get("recipe", {})
	if dept.is_empty() or dept.facilities.is_empty() or parent < 0 or not recipe.get("outputs", {}).has(item) or total < 1 or total > 1000000: return 0
	if not group.is_empty() and (not dept.groups.has(group) or parent == 0): return 0
	if parent > 0:
		var root: Dictionary = owner.matters.get(parent, {})
		if root.get("kind") != "department" or root.department != department or root.parent_order != 0 or root.operation != operation or root.item != item or root.state != "active" or group.is_empty() or repeat: return 0
		if total > unallocated(owner, root): return 0
	compact(owner, world)
	if owner.matters.size() >= owner.Matters.MATTER_LIMIT: return 0
	var now: int = world.operation_time()
	var id: int = owner.next_matter
	owner.next_matter += 1
	owner.matters[id] = {"id": id, "issuer": actor, "organization": dept.organization, "kind": "department", "target": int(dept.facilities[0]), "item": item, "operation": operation, "sources": [], "total": total, "quota": total, "deadline_ms": 0, "version": 1, "created_ms": now, "state": "active", "archived": 0,
		"department": department, "group": group, "parent_order": parent, "fulfilled": 0, "last_result_id": 0, "repeat": repeat, "next_cycle_ms": (now / DAY_MS + 1) * DAY_MS if repeat else 0, "paused": false}
	owner._orders_dirty = true
	owner.Departments.changed(owner, department)
	return id

static func list(owner: RefCounted, department: int) -> Array:
	ensure(owner)
	var result: Array = []
	for id: int in owner._orders_by_department.get(department, []): result.append(owner.matters[id])
	return result

static func open(owner: RefCounted, id: int) -> bool:
	var m: Dictionary = owner.matters.get(id, {})
	if m.get("kind") != "department" or m.state != "active" or m.paused: return false
	if int(m.fulfilled) + int(owner._order_wip.get(id, 0)) >= int(m.total): return false
	if m.parent_order == 0: return unallocated(owner, m) > 0
	var parent: Dictionary = owner.matters[int(m.parent_order)]
	return parent.state == "active" and not parent.paused and int(parent.fulfilled) + int(owner._order_wip.get(int(parent.id), 0)) < int(parent.total)

static func unallocated(owner: RefCounted, root: Dictionary) -> int:
	var remaining: int = int(root.total) - int(root.fulfilled) - int(owner._order_wip.get(int(root.id), 0))
	for m: Dictionary in list(owner, int(root.department)):
		if m.parent_order == root.id and m.state == "active": remaining -= maxi(0, int(m.total) - int(m.fulfilled) - int(owner._order_wip.get(int(m.id), 0)))
	return maxi(0, remaining)

static func binding(owner: RefCounted, target: int, operation: String) -> Dictionary:
	owner.Departments.ensure(owner)
	var department: int = int(owner._facility_department.get(target, 0))
	if department == 0: return {"order": 0, "allocation": 0}
	var config: Dictionary = owner.departments[department].production.get(target, {})
	var id: int = int(config.get("order", 0))
	if config.get("operation") != operation or not open(owner, id): return {}
	var m: Dictionary = owner.matters[id]
	if not m.group.is_empty() and target not in owner.departments[department].groups[m.group].facilities: return {}
	return {"order": id if m.parent_order == 0 else int(m.parent_order), "allocation": id if m.parent_order > 0 else 0}

static func reserve(owner: RefCounted, process: Dictionary) -> void:
	for id: int in [int(process.order), int(process.allocation)]:
		if id > 0:
			var m: Dictionary = owner.matters[id]
			var amount: int = int(Operations.OPERATIONS[process.operation].recipe.outputs.get(m.item, 0))
			owner._order_wip[id] = int(owner._order_wip.get(id, 0)) + amount

static func release(owner: RefCounted, process: Dictionary) -> void:
	for id: int in [int(process.get("order", 0)), int(process.get("allocation", 0))]:
		if id > 0:
			var m: Dictionary = owner.matters[id]
			owner._order_wip[id] = maxi(0, int(owner._order_wip.get(id, 0)) - int(Operations.OPERATIONS[process.operation].recipe.outputs.get(m.item, 0)))

static func outcome(owner: RefCounted, world: RefCounted, result: Dictionary) -> void:
	if result.status != "completed" or result.reason == "process_waiting": return
	for id: int in [int(result.facts.get("order", 0)), int(result.facts.get("allocation", 0))]:
		var m: Dictionary = owner.matters.get(id, {})
		if m.get("kind") != "department" or result.id <= int(m.last_result_id) or result.operation != m.operation or result.facts.get("output_organization") != m.organization: continue
		m.fulfilled += int(result.facts.get("produced", {}).get(m.item, 0))
		m.last_result_id = result.id
		if m.fulfilled >= m.total and m.state == "active": m.state = "completed"
		owner.Departments.touch(owner)
		owner.Workflow.dirty(owner, int(m.department))

static func rollover(owner: RefCounted, world: RefCounted, id: int, at: int) -> int:
	var m: Dictionary = owner.matters.get(id, {})
	if m.get("kind") != "department" or m.state == "cancelled" or not m.repeat or m.next_cycle_ms == 0 or m.next_cycle_ms > at: return 0
	var children: Array = []
	for child: Dictionary in list(owner, int(m.department)):
		if child.parent_order == id and child.state != "cancelled": children.append(child)
	# Closing the old period does not depend on space for the next one. Keep
	# the retry credential, and allocate the whole successor family together;
	# a lone new root would otherwise strand lines bound to old allocations.
	if m.state == "active": m.state = "expired"
	for child: Dictionary in children:
		if child.state == "active": child.state = "expired"
	compact(owner, world, 1 + children.size())
	if owner.matters.size() + 1 + children.size() > owner.Matters.MATTER_LIMIT or owner.departments[int(m.department)].facilities.is_empty():
		m.next_cycle_ms = at + 1000
		owner.Departments.changed(owner, int(m.department))
		return 0
	var next: int = create(owner, world, int(m.issuer), int(m.department), str(m.operation), str(m.item), int(m.total), "", 0, true)
	if next == 0: m.next_cycle_ms = at + 1000; return 0
	owner.matters[next].paused = m.paused
	var replacements: Dictionary = {id: next}
	for child: Dictionary in children:
		var allocation: int = create(owner, world, int(child.issuer), int(child.department), str(child.operation), str(child.item), int(child.total), str(child.group), next)
		if allocation > 0:
			replacements[int(child.id)] = allocation
			owner.matters[allocation].paused = child.paused
	for config: Dictionary in owner.departments[int(m.department)].production.values():
		if replacements.has(int(config.order)): config.order = replacements[int(config.order)]
	m.next_cycle_ms = 0
	m.repeat = false
	return next

static func view(owner: RefCounted, department: int, group: String = "") -> Array:
	var result: Array = []
	for m: Dictionary in list(owner, department):
		if not group.is_empty() and m.group != group: continue
		var entry: Dictionary = State.copy(m)
		entry["wip"] = int(owner._order_wip.get(int(m.id), 0))
		result.append(entry)
	return result

static func compact(owner: RefCounted, world: RefCounted, headroom: int = 16) -> void:
	if owner.matters.size() < owner.Matters.MATTER_LIMIT - headroom: return
	var retained: Dictionary = {}
	for d: Dictionary in owner.departments.values():
		for config: Dictionary in d.production.values(): retained[int(config.order)] = true
	for m: Dictionary in owner.matters.values():
		if m.kind != "department" or m.parent_order == 0: continue
		retained[int(m.parent_order)] = true
		# Pending daily successors still need every uncancelled allocation,
		# including a group which currently has no bound workshop.
		if m.state != "cancelled" and owner.matters[int(m.parent_order)].repeat: retained[int(m.id)] = true
	for id: int in owner.matters.keys():
		var m: Dictionary = owner.matters[id]
		if m.kind == "department" and m.state != "active" and not m.repeat and int(owner._order_wip.get(id, 0)) == 0 and not retained.has(id) and world.operation_time() - int(m.created_ms) > DAY_MS * 2:
			owner.matters.erase(id); owner._orders_dirty = true

static func valid_matter(owner: RefCounted, world: RefCounted, m: Dictionary) -> bool:
	if m.size() != 23: return false
	for field: String in ["id", "issuer", "organization", "target", "total", "quota", "deadline_ms", "version", "created_ms", "archived", "department", "parent_order", "fulfilled", "last_result_id", "next_cycle_ms"]:
		if not m.get(field) is int: return false
	if m.id < 1 or m.id >= owner.next_matter or m.issuer < 1 or m.issuer >= world.objects.next_id or m.target < 1 or m.target >= world.objects.next_id or m.parent_order < 0: return false
	var d: Dictionary = owner.departments.get(m.department, {})
	if d.is_empty() or m.organization != d.organization or not m.get("group") is String or (not m.group.is_empty() and not d.groups.has(m.group)): return false
	if m.get("state") not in ["active", "completed", "cancelled", "expired"] or not m.get("paused") is bool or not m.get("repeat") is bool: return false
	if m.total < 1 or m.total > 1000000 or m.quota != m.total or m.archived != 0 or m.fulfilled < 0 or m.fulfilled > m.total + 1000000 or (m.state == "completed" and m.fulfilled < m.total) or (m.state == "active" and m.fulfilled >= m.total): return false
	if m.last_result_id < 0 or m.last_result_id >= world.activity_results.next_id or (m.fulfilled > 0 and m.last_result_id == 0) or m.created_ms < 0 or m.created_ms > world.operation_time() or m.version < 1 or m.deadline_ms != 0 or m.sources != []: return false
	if not m.get("operation") is String or not m.get("item") is String or not Operations.OPERATIONS.get(m.operation, {}).get("recipe", {}).get("outputs", {}).has(m.item): return false
	if m.repeat != (m.next_cycle_ms > 0) or m.next_cycle_ms < 0 or m.next_cycle_ms > world.operation_time() + DAY_MS: return false
	if m.state == "cancelled" and m.repeat: return false
	if m.parent_order > 0:
		var parent: Dictionary = owner.matters.get(m.parent_order, {})
		if parent.get("kind") != "department" or parent.get("parent_order") != 0 or parent.department != m.department or parent.operation != m.operation or parent.item != m.item or m.repeat or m.group.is_empty(): return false
	elif not m.group.is_empty(): return false
	return true
