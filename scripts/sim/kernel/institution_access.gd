extends RefCounted
## Appointment/service rules operate on Institutions' state, never a second owner.
const Defs = preload("res://scripts/sim/kernel/institution_defs.gd")
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
const Duties = preload("res://scripts/sim/kernel/institution_duties.gd")
const SERVICES: Array[String] = ["rest", "eat"]
const LIMIT: int = 4096

static func index(owner: RefCounted) -> void:
	if not owner._access_dirty: return
	owner._appointments_by_actor.clear()
	owner._services_by_actor.clear()
	owner._services_by_org.clear()
	for id: int in owner.appointments:
		var a: Dictionary = owner.appointments[id]
		if not a.active: continue
		if not owner._appointments_by_actor.has(int(a.actor)): owner._appointments_by_actor[int(a.actor)] = []
		owner._appointments_by_actor[int(a.actor)].append(id)
	for target: int in owner.services:
		for purpose: String in owner.services[target]:
			var rule: Dictionary = owner.services[target][purpose]
			if rule.members:
				if not owner._services_by_org.has(int(rule.organization)): owner._services_by_org[int(rule.organization)] = {}
				owner._services_by_org[int(rule.organization)][target] = true
			else:
				for actor: int in rule.actors:
					if not owner._services_by_actor.has(actor): owner._services_by_actor[actor] = {}
					owner._services_by_actor[actor][target] = true
	owner._access_dirty = false

static func appointments_for(owner: RefCounted, actor: int) -> Array:
	index(owner)
	return owner._appointments_by_actor.get(actor, [])

static func scope_grants(owner: RefCounted, actor: int) -> Array:
	var result: Array = []
	for id: int in appointments_for(owner, actor):
		var appointment: Dictionary = owner.appointments[id]
		var role: Dictionary = Defs.ROLES[appointment.role]
		result.append({"organization": appointment.organization, "targets": appointment.targets.duplicate(), "purposes": role.purposes, "items": role.items, "all_items": role.all_items})
	return result

static func service_targets(owner: RefCounted, actor: int) -> Dictionary:
	index(owner)
	var result: Dictionary = {}
	var targets: Dictionary = owner._services_by_actor.get(actor, {}).duplicate()
	for organization: int in owner.memberships:
		if owner.memberships[organization].has(actor): targets.merge(owner._services_by_org.get(organization, {}))
	for target: int in targets:
		for purpose: String in owner.services[target]:
			var rule: Dictionary = owner.services[target][purpose]
			if actor in rule.actors or (rule.members and owner.memberships.get(rule.organization, {}).has(actor)):
				if not result.has(purpose): result[purpose] = []
				result[purpose].append(target)
	return result

static func service_flags(owner: RefCounted, target: int) -> Dictionary:
	var result: Dictionary = {}
	for purpose: String in owner.services.get(target, {}): result[purpose] = true
	return result

static func personal_place(owner: RefCounted, actor: int, target: int) -> bool:
	for rule: Dictionary in owner.services.get(target, {}).values():
		if not rule.members and actor in rule.actors: return true
	return false

static func known_personal_places(owner: RefCounted, actor: int, subjects: Dictionary) -> Dictionary:
	# Retain acquired personal allocations, never fetch a location from truth.
	var result: Dictionary = {}
	for target: int in subjects:
		var clue: Dictionary = subjects[target]
		if clue.origin != "heard" and int(clue.view.get("tile", -1)) >= 0 and personal_place(owner, actor, target): result[target] = true
	return result

static func _targets_valid(world: RefCounted, organization: int, targets: Array, active: bool) -> bool:
	if targets.is_empty() or targets.size() > 128: return false
	for target: Variant in targets:
		if not target is int or target <= 0 or target >= world.objects.next_id or targets.count(target) != 1: return false
		if active:
			var record: Dictionary = world.objects.records.get(target, {})
			if record.is_empty() or record.kind == "actor" or record.organization != organization or record.owner != 0: return false
	return true

static func appoint(owner: RefCounted, world: RefCounted, organization: int, actor: int, role: String, targets: Array, duty_scope: Dictionary = {}) -> int:
	if owner.appointments.size() >= LIMIT or not owner.memberships.get(organization, {}).has(actor) or not world.actor_slots.has(actor) or not world.combat.alive(world, actor) or not Defs.ROLES.has(role) or not _targets_valid(world, organization, targets, true): return 0
	if not Duties.scope_valid(world, role, duty_scope, targets, true): return 0
	for appointment: Dictionary in owner.appointments.values():
		if appointment.active and appointment.organization == organization and appointment.actor == actor and appointment.role == role and appointment.targets == targets and appointment.duty_scope == duty_scope: return appointment.id
	var id: int = owner.next_appointment
	owner.next_appointment += 1
	owner.appointments[id] = {"id": id, "organization": organization, "actor": actor, "role": role, "targets": targets.duplicate(), "active": true, "since_ms": world.operation_time(), "duty_scope": duty_scope.duplicate(true)}
	owner._access_dirty = true
	if not world.livelihood.reconcile_duties(world, actor): owner.appointments.erase(id); return 0
	owner.reconcile(world, actor)
	return id

static func revoke(owner: RefCounted, world: RefCounted, appointment: int) -> bool:
	if not owner.appointments.has(appointment) or not owner.appointments[appointment].active: return false
	owner.appointments[appointment].active = false
	owner._access_dirty = true
	world.livelihood.reconcile_duties(world, int(owner.appointments[appointment].actor))
	owner.reconcile(world, int(owner.appointments[appointment].actor))
	return true

static func _service_supported(world: RefCounted, target: int, purpose: String) -> bool:
	var record: Dictionary = world.objects.records.get(target, {})
	if record.is_empty() or record.kind in ["actor", "blueprint"] or record.organization <= 0 or record.owner != 0: return false
	var capabilities: Dictionary = world.facilities.definitions.get(record.definition, {}).get("capabilities", {})
	return capabilities.has("rest") if purpose == "rest" else (purpose == "eat" and (capabilities.has("storage") or capabilities.has("workbench")))

static func arrange(owner: RefCounted, world: RefCounted, target: int, purpose: String, actors: Array, members: bool) -> bool:
	if not _service_supported(world, target, purpose) or actors.size() > 256 or (members and not actors.is_empty()) or (not members and actors.is_empty()): return false
	var organization: int = world.objects.records[target].organization
	for actor: Variant in actors:
		if not actor is int or not world.actor_slots.has(actor) or not world.combat.alive(world, actor) or not owner.memberships[organization].has(actor) or actors.count(actor) != 1: return false
	var previous: Dictionary = owner.services.get(target, {}).get(purpose, {}).duplicate()
	if not owner.services.has(target): owner.services[target] = {}
	owner.services[target][purpose] = {"organization": organization, "actors": actors.duplicate(), "members": members}
	owner._access_dirty = true
	_service_changed(owner, world, target, previous, owner.services[target][purpose])
	return true

static func clear_service(owner: RefCounted, world: RefCounted, target: int, purpose: String) -> bool:
	if not owner.services.get(target, {}).has(purpose): return false
	var previous: Dictionary = owner.services[target][purpose].duplicate()
	owner.services[target].erase(purpose)
	owner._access_dirty = true
	if owner.services[target].is_empty(): owner.services.erase(target)
	_service_changed(owner, world, target, previous, {})
	return true

static func _service_changed(owner: RefCounted, world: RefCounted, target: int, previous: Dictionary, current: Dictionary) -> void:
	var organization: int = world.objects.records[target].organization
	for actor: int in owner.memberships[organization]:
		# Newly available access merits reconsideration. Losing an unused bed
		# does not force every unrelated resident to replan their current work.
		if current.is_empty() or current.get("members", false) or actor in previous.get("actors", []) or actor in current.get("actors", []) or world.actions.get(actor, {}).get("target", 0) == target:
			owner.reconcile(world, actor, target)

static func forget_target(owner: RefCounted, world: RefCounted, target: int) -> void:
	owner.Departments.ensure(owner)
	var department: int = int(owner._facility_department.get(target, 0))
	if department > 0:
		var dept: Dictionary = owner.departments[department]
		dept.facilities.erase(target)
		dept.production.erase(target)
		for group: Dictionary in dept.groups.values(): group.facilities.erase(target)
		owner.Departments.changed(owner, department, true)
	owner._access_dirty = true
	owner.services.erase(target)
	for appointment: Dictionary in owner.appointments.values():
		if not appointment.active or target not in appointment.targets: continue
		appointment.targets.erase(target)
		if not appointment.duty_scope.is_empty():
			appointment.duty_scope.sources.erase(target)
			if appointment.duty_scope.has("sites"):
				appointment.duty_scope.sites.erase(target)
				if target == appointment.duty_scope.destination or appointment.duty_scope.sites.is_empty() or appointment.duty_scope.sources.is_empty(): appointment.active = false
			elif target in [appointment.duty_scope.target, appointment.duty_scope.channel] or appointment.duty_scope.sources.is_empty(): appointment.active = false
		if appointment.targets.is_empty():
			appointment.active = false
			appointment.targets = [target] # Keep the historical scope; no active grant.
		world.livelihood.reconcile_duties(world, int(appointment.actor))
		owner.reconcile(world, appointment.actor)

static func valid(owner: RefCounted, world: RefCounted) -> bool:
	if not Defs.ERRORS.is_empty() or owner.catalog_signature != Defs.SIGNATURE or owner.next_appointment < 1 or owner.next_appointment > 999999999999 or owner.appointments.size() > LIMIT or owner.services.size() > LIMIT: return false
	for id: Variant in owner.appointments:
		var entry: Variant = owner.appointments[id]
		if not id is int or id < 1 or id >= owner.next_appointment or not entry is Dictionary or entry.size() != 8 or not entry.get("id") is int or entry.id != id or not entry.get("organization") is int or not owner.organizations.has(entry.organization): return false
		if not entry.get("actor") is int or entry.actor < 1 or entry.actor >= world.objects.next_id or not owner.memberships[entry.organization].has(entry.actor) or not entry.get("role") is String or not Defs.ROLES.has(entry.role) or not entry.get("active") is bool: return false
		if not entry.get("targets") is Array or not _targets_valid(world, entry.organization, entry.targets, entry.active) or not entry.get("since_ms") is int or entry.since_ms < 0 or entry.since_ms > world.elapsed_ms: return false
		if not Duties.scope_valid(world, entry.role, entry.get("duty_scope"), entry.targets, bool(entry.active)): return false
	for target: Variant in owner.services:
		if not target is int or not owner.services[target] is Dictionary or owner.services[target].is_empty() or owner.services[target].size() > SERVICES.size(): return false
		for purpose: Variant in owner.services[target]:
			if not purpose is String or purpose not in SERVICES or not _service_supported(world, target, purpose): return false
			var rule: Variant = owner.services[target][purpose]
			if not rule is Dictionary or rule.size() != 3 or not rule.get("organization") is int or not owner.organizations.has(rule.organization) or not owner.memberships.get(rule.organization) is Dictionary or rule.organization != world.objects.records[target].organization or not rule.get("actors") is Array or rule.actors.size() > 256 or not rule.get("members") is bool: return false
			if (rule.members and not rule.actors.is_empty()) or (not rule.members and rule.actors.is_empty()): return false
			for actor: Variant in rule.actors:
				if not actor is int or actor < 1 or actor >= world.objects.next_id or not owner.memberships[rule.organization].has(actor) or rule.actors.count(actor) != 1: return false
	return true
