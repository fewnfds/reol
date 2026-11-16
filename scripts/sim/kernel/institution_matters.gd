extends RefCounted
## Normative obligations belong to Institutions. Operations own the actual work;
## personal goals hold only the accepted share's identity, never its progress.
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Access = preload("res://scripts/sim/kernel/institution_access.gd")
const Query = preload("res://scripts/sim/kernel/operation_query.gd")
const MATTER_LIMIT: int = 512
const SHARE_LIMIT: int = 4096
const SOURCE_LIMIT: int = 32
const PERSON_LIMIT: int = 8
const KINDS: Array[String] = ["delivery", "produce", "operation"]

static func _base_view(owner: RefCounted, actor: int) -> Dictionary:
	# A delegated execution permission cannot mint another delegation.
	return {"id": actor, "permissions": owner.permissions(actor), "scope_grants": Access.scope_grants(owner, actor)}

static func _items(matter: Dictionary, target: Dictionary) -> Array:
	if matter.kind == "delivery": return [matter.item]
	var operation: Dictionary = Operations.OPERATIONS[matter.operation]
	var result: Array = operation.required_items.keys()
	var context: Dictionary = Query.stock_context(operation, target)
	if not str(context.get("item", "")).is_empty() and context.item not in result: result.append(context.item)
	for item: String in context.get("recipe_items", []):
		if item not in result: result.append(item)
	for item: String in operation.recipe.get("outputs", {}):
		if item not in result: result.append(item)
	if result.is_empty(): result = [matter.item] if not matter.item.is_empty() else []
	return result

static func _grant(organization: int, targets: Array, purposes: Array, items: Array) -> Dictionary:
	return {"organization": organization, "targets": targets.duplicate(), "purposes": purposes.duplicate(), "items": items.duplicate(), "all_items": false}

static func _terms_grants(world: RefCounted, matter: Dictionary) -> Array:
	return terms_grants(matter, world.objects.records, world.facilities.definitions)

static func terms_grants(matter: Dictionary, targets: Dictionary, buildings: Dictionary = {}) -> Array:
	if buildings.is_empty(): buildings = Query.BUILDINGS
	if matter.organization <= 0: return []
	var items: Array = _items(matter, targets.get(matter.target, {}))
	var operation: Dictionary = Operations.OPERATIONS.get(matter.operation, {})
	var purpose: String = "supply" if matter.kind == "delivery" else (str(operation.recipe.purpose) if not operation.recipe.is_empty() else ("cultivate" if operation.handler in ["sow", "tend", "gather", "cut", "uproot", "harvest"] else str(operation.handler)))
	var result: Array = [_grant(matter.organization, [matter.target], ["put"] if matter.kind == "delivery" else [purpose], items)]
	var source_items: Array = items if matter.kind == "delivery" else operation.required_items.keys()
	for source: int in matter.sources:
		var record: Dictionary = targets.get(source, {})
		# Vanished references remain contractual history, not a new location or
		# an implicit permission on a replacement object.
		if record.is_empty(): continue
		var handler: String = "supply" if buildings.get(record.definition, {}).get("capabilities", {}).has("stock_source") else ("cultivate" if record.kind in ["resource", "plant"] else "take")
		if not source_items.is_empty(): result.append(_grant(matter.organization, [source], [handler, purpose] if handler != purpose else [purpose], source_items))
	return result

static func _authorized(owner: RefCounted, world: RefCounted, actor: int, matter: Dictionary) -> bool:
	var target: Dictionary = world.objects.records.get(matter.target, {})
	if target.is_empty(): return false
	if matter.organization == 0: return matter.kind == "operation" and matter.operation == "construct" and target.kind == "blueprint" and target.owner in [0, actor] and target.organization == 0
	if not owner.memberships.get(matter.organization, {}).has(actor) or target.organization != matter.organization or target.owner != 0: return false
	var view: Dictionary = _base_view(owner, actor)
	for source: int in matter.sources:
		var record: Dictionary = world.objects.records.get(source, {})
		if record.is_empty() or record.kind == "actor" or record.organization != matter.organization or record.owner != 0: return false
	for grant: Dictionary in _terms_grants(world, matter):
		for id: int in grant.targets:
			var place: Dictionary = world.objects.records.get(id, {})
			if place.get("organization") != matter.organization or place.get("owner") != 0: return false
			if grant.items.is_empty() and not Stock.permits_at(view, place, "commission"): return false
			for purpose: String in grant.purposes:
				if grant.items.is_empty():
					if not Stock.permits_at(view, place, purpose): return false
				for item: String in grant.items:
					if not Stock.permits_at(view, place, "commission", item) or not Stock.permits_at(view, place, purpose, item): return false
	return true

static func create(owner: RefCounted, world: RefCounted, issuer: int, spec: Dictionary) -> int:
	if not world.actor_slots.has(issuer) or not world.combat.alive(world, issuer): return 0
	for key: Variant in spec:
		if key not in ["kind", "organization", "target", "item", "operation", "sources", "total", "quota", "deadline_ms"]: return 0
	var matter: Dictionary = {"id": owner.next_matter, "issuer": issuer, "organization": spec.get("organization", 0), "kind": spec.get("kind", ""),
		"target": spec.get("target", 0), "item": spec.get("item", ""), "operation": spec.get("operation", ""), "sources": spec.get("sources", []).duplicate() if spec.get("sources", []) is Array else null,
		"total": spec.get("total", 1), "quota": spec.get("quota", 1), "deadline_ms": spec.get("deadline_ms", 0), "version": 1, "created_ms": world.operation_time(), "state": "active", "archived": 0}
	if not _matter_valid(owner, world, matter) or not _authorized(owner, world, issuer, matter): return 0
	for target: int in [matter.target] + matter.sources:
		world.knowledge.refresh(world, issuer, target, world.operation_time())
		var clue: Dictionary = world.knowledge.view(issuer, target, world.operation_time())
		if clue.is_empty() or int(clue.get("tile", -1)) < 0: return 0
	if matter.kind == "delivery" and world.objects.records[matter.target].kind != "chest": return 0
	if matter.kind != "delivery" and not Query.evaluate(Operations.OPERATIONS[matter.operation], world.operation_actor(issuer), world.operation_target(matter.target)).applicable: return 0
	if matter.kind == "produce":
		var operation: Dictionary = Operations.OPERATIONS[matter.operation]
		if operation.recipe.is_empty() or not operation.recipe.outputs.has(matter.item): return 0
		if operation.recipe.id not in world.facilities.definitions.get(world.objects.records[matter.target].definition, {}).get("capabilities", {}).get(operation.recipe.facility_capability, {}).get("recipes", []): return 0
	compact(owner, world)
	if owner.matters.size() >= MATTER_LIMIT: return 0
	owner.next_matter += 1
	owner.matters[matter.id] = matter
	return matter.id

static func shares_for(owner: RefCounted, actor: int) -> Array:
	var result: Array = []
	for id: int in owner._shares_by_actor.get(actor, []):
		var share: Dictionary = owner.shares[id]
		if share.state == "accepted": result.append(share)
	return result

static func shares_in(owner: RefCounted, matter: int) -> Array:
	var result: Array = []
	for id: int in owner._shares_by_matter.get(matter, []): result.append(owner.shares[id])
	return result

static func _index(owner: RefCounted, share: Dictionary) -> void:
	if share.state == "accepted":
		if not owner._shares_by_actor.has(share.actor): owner._shares_by_actor[share.actor] = []
		owner._shares_by_actor[share.actor].append(share.id)
	if not owner._shares_by_matter.has(share.matter): owner._shares_by_matter[share.matter] = []
	owner._shares_by_matter[share.matter].append(share.id)

static func _unindex_active(owner: RefCounted, share: Dictionary) -> void:
	owner._shares_by_actor.get(share.actor, []).erase(share.id)
	if owner._shares_by_actor.get(share.actor, []).is_empty(): owner._shares_by_actor.erase(share.actor)

static func _erase_share(owner: RefCounted, share: Dictionary) -> void:
	_unindex_active(owner, share)
	owner._shares_by_matter.get(share.matter, []).erase(share.id)
	if owner._shares_by_matter.get(share.matter, []).is_empty(): owner._shares_by_matter.erase(share.matter)
	owner.shares.erase(share.id)

static func occupied(owner: RefCounted, matter: Dictionary) -> int:
	var count: int = matter.archived
	for share: Dictionary in shares_in(owner, int(matter.id)):
		count += int(share.quota) if share.state == "accepted" else int(share.fulfilled)
	return count

static func construction_assigned(owner: RefCounted, target: int) -> bool:
	for matter: Dictionary in owner.matters.values():
		if matter.state == "active" and matter.operation == "construct" and matter.target == target and occupied(owner, matter) > 0: return true
	return false

static func accept(owner: RefCounted, world: RefCounted, actor: int, id: int, quota: int = 0, temporary: bool = false) -> int:
	if not owner.matters.has(id) or not world.actor_slots.has(actor) or not world.combat.alive(world, actor): return 0
	var matter: Dictionary = owner.matters[id]
	if matter.state != "active" or (matter.organization > 0 and not owner.memberships[matter.organization].has(actor)) or (matter.deadline_ms > 0 and matter.deadline_ms <= world.operation_time()): return 0
	var clue: Dictionary = world.knowledge.view(actor, int(matter.target), world.operation_time())
	if not clue.is_empty() and int(clue.get("tile", -1)) < 0: return 0
	var existing: Array = shares_for(owner, actor)
	for share: Dictionary in existing:
		if share.matter == id: return share.id
	if matter.operation == "construct" and construction_assigned(owner, int(matter.target)): return 0
	if existing.size() >= PERSON_LIMIT: return 0
	var available: int = int(matter.total) - occupied(owner, matter)
	if quota == 0: quota = mini(int(matter.quota), available)
	if quota <= 0 or quota > available: return 0
	compact(owner, world)
	if owner.shares.size() >= SHARE_LIMIT: return 0
	var share: Dictionary = {"id": owner.next_share, "matter": id, "actor": actor, "quota": quota, "fulfilled": 0, "state": "accepted", "created_ms": world.operation_time(), "deadline_ms": matter.deadline_ms, "last_result_id": world.activity_results.next_id - 1}
	owner.next_share += 1
	owner.shares[share.id] = share
	_index(owner, share)
	if world.livelihood.add_goal(world, actor, "matter_share", {"matter": id, "share": int(share.id)}, int(matter.issuer)) == 0:
		_erase_share(owner, share)
		return 0
	if temporary and not world.objects.records[actor].get("autonomous", false):
		world.livelihood.record(world, actor).borrowed_autonomy = true
		world.objects.records[actor].autonomous = true
	owner.reconcile(world, actor)
	return share.id

static func views(owner: RefCounted, world: RefCounted, actor: int) -> Dictionary:
	var result: Dictionary = {}
	for share: Dictionary in shares_for(owner, actor):
		var matter: Dictionary = owner.matters[share.matter]
		var entry: Dictionary = {"matter": matter.id, "issuer": matter.issuer, "organization": matter.organization, "kind": matter.kind, "target": matter.target, "operation": matter.operation, "item": matter.item, "sources": matter.sources.duplicate(), "share": share.id, "quota": share.quota, "remaining": int(share.quota) - int(share.fulfilled), "deadline_ms": share.deadline_ms, "overdue": share.deadline_ms > 0 and world.operation_time() >= share.deadline_ms}
		result[share.id] = entry
	return result

static func grants(owner: RefCounted, world: RefCounted, actor: int) -> Array:
	var result: Array = []
	for share: Dictionary in shares_for(owner, actor):
		var matter: Dictionary = owner.matters[share.matter]
		if matter.organization > 0 and owner.memberships[matter.organization].has(actor): result.append_array(_terms_grants(world, matter))
	return result

static func task_access(owner: RefCounted, actor: int) -> Dictionary:
	var result: Dictionary = {}
	for share: Dictionary in shares_for(owner, actor):
		var matter: Dictionary = owner.matters[share.matter]
		if matter.organization == 0 and matter.kind == "operation" and matter.operation == "construct": result[matter.target] = ["construct"]
	return result

static func _can_manage(owner: RefCounted, world: RefCounted, actor: int, matter: Dictionary, delegating: bool = false) -> bool:
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor): return false
	if matter.organization == 0: return actor == matter.issuer
	if not owner.memberships.get(matter.organization, {}).has(actor): return false
	var place: Dictionary = {"id": matter.target, "organization": matter.organization}
	var view: Dictionary = _base_view(owner, actor)
	var items: Array = _items(matter, world.objects.records.get(matter.target, {}))
	if delegating:
		for grant: Dictionary in _terms_grants(world, matter):
			for target: int in grant.targets:
				var scope: Dictionary = {"id": target, "organization": matter.organization}
				for purpose: String in ["commission"] + grant.purposes:
					if grant.items.is_empty() and not Stock.permits_at(view, scope, purpose): return false
					for item: String in grant.items:
						if not Stock.permits_at(view, scope, purpose, item): return false
	if items.is_empty(): return Stock.permits_at(view, place, "commission")
	for item: String in items:
		if not Stock.permits_at(view, place, "commission", item): return false
	return true

static func release(owner: RefCounted, world: RefCounted, actor: int, id: int) -> bool:
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor): return false
	if not owner.shares.has(id) or owner.shares[id].state != "accepted": return false
	var share: Dictionary = owner.shares[id]
	if actor != share.actor and not _can_manage(owner, world, actor, owner.matters[share.matter]): return false
	share.state = "released"
	_unindex_active(owner, share)
	_notify_closed(world, share, false)
	owner.reconcile(world, share.actor)
	return true

static func cancel(owner: RefCounted, world: RefCounted, actor: int, id: int) -> bool:
	if not owner.matters.has(id) or owner.matters[id].state != "active" or not _can_manage(owner, world, actor, owner.matters[id]): return false
	owner.matters[id].state = "cancelled"
	for share: Dictionary in shares_in(owner, id):
		if share.state == "accepted":
			share.state = "released"; _unindex_active(owner, share); _notify_closed(world, share, false); owner.reconcile(world, share.actor)
	world.society.on_matter_closed(world, id)
	return true

static func revise(owner: RefCounted, world: RefCounted, actor: int, id: int, total: int, quota: int, deadline: int) -> bool:
	if not owner.matters.has(id): return false
	var matter: Dictionary = owner.matters[id]
	if matter.operation == "construct" and total != 1: return false
	if matter.state != "active" or not _can_manage(owner, world, actor, matter, true) or total < occupied(owner, matter) or total < 1 or total > 1000000 or quota < 1 or quota > total or (deadline != 0 and deadline < world.operation_time()): return false
	matter.merge({"total": total, "quota": quota, "deadline_ms": deadline, "version": int(matter.version) + 1}, true)
	var fulfilled: int = matter.archived
	for share: Dictionary in shares_in(owner, id): fulfilled += int(share.fulfilled)
	if fulfilled == total:
		matter.state = "completed"
		world.society.on_matter_closed(world, id)
	return true

static func _notify_closed(world: RefCounted, share: Dictionary, completed: bool) -> void:
	world.society.on_share_closed(world, share, completed)
	world.livelihood.share_closed(world, share, completed)

static func _credit(owner: RefCounted, world: RefCounted, share: Dictionary, amount: int, result: Dictionary) -> int:
	if result.id <= share.last_result_id or share.state != "accepted": return 0
	var count: int = mini(amount, int(share.quota) - int(share.fulfilled))
	if count <= 0: return 0
	share.fulfilled += count
	share.last_result_id = result.id
	if share.fulfilled == share.quota:
		share.state = "completed"
		_unindex_active(owner, share)
		_notify_closed(world, share, true)
		owner.reconcile(world, share.actor)
	return count

static func outcome(owner: RefCounted, world: RefCounted, result: Dictionary) -> void:
	if result.is_empty() or result.status != "completed" or result.reason == "process_waiting": return
	if result.operation == "construct": world.society.Requests.construction_completed(world.society, int(result.target), int(result.at_ms))
	var actors: Array = [result.actor]
	for labor: Dictionary in result.facts.get("labor", []):
		if labor.worked_ms > 0 and labor.actor not in actors: actors.append(int(labor.actor))
	var remaining: Dictionary = {}
	var used_origins: Dictionary = {}
	var touched: Dictionary = {}
	for actor: int in actors:
		for share: Dictionary in shares_for(owner, actor):
			var matter: Dictionary = owner.matters[share.matter]
			if matter.state != "active" or result.id <= share.last_result_id or result.at_ms < share.created_ms: continue
			var key: String = "%s:%d:%s" % [matter.kind, matter.target, matter.item if matter.kind != "operation" else matter.operation]
			var possible: int = 0
			var origins: Array = []
			if matter.kind == "delivery" and actor == result.actor and result.operation == "put" and result.target == matter.target and result.facts.get("item") == matter.item:
				for index: int in result.facts.get("deliveries", []).size():
					var line: Dictionary = result.facts.deliveries[index]
					if line.organization == matter.organization and line.origin != matter.target and line.origin in matter.sources:
						possible += maxi(0, int(line.amount) - int(used_origins.get(index, 0)))
						origins.append(index)
			elif matter.kind == "produce" and result.target == matter.target and result.operation == matter.operation and result.facts.get("output_organization") == matter.organization:
				possible = int(result.facts.get("produced", {}).get(matter.item, 0))
			elif matter.kind == "operation" and actor == result.actor and result.target == matter.target and result.operation == matter.operation: possible = 1
			if possible <= 0: continue
			if matter.kind == "delivery":
				var credited: int = _credit(owner, world, share, possible, result)
				if credited > 0: touched[matter.id] = true
				for index: int in origins:
					var count: int = mini(credited, int(result.facts.deliveries[index].amount) - int(used_origins.get(index, 0)))
					used_origins[index] = int(used_origins.get(index, 0)) + count
					credited -= count
			else:
				if not remaining.has(key): remaining[key] = possible
				var credited: int = _credit(owner, world, share, mini(possible, int(remaining[key])), result)
				remaining[key] -= credited
				if credited > 0: touched[matter.id] = true
		# Even a matching but uncredited obligation has consumed this submission
		# boundary. Replaying it cannot redirect the same output into a later share.
		for share: Dictionary in shares_for(owner, actor): share.last_result_id = maxi(int(share.last_result_id), int(result.id))
	if result.operation == "construct":
		for matter: Dictionary in owner.matters.values():
			if matter.state == "active" and matter.operation == "construct" and matter.target == result.target: touched[matter.id] = true
	for id: int in touched:
		var matter: Dictionary = owner.matters[id]
		if matter.state != "active": continue
		var fulfilled: int = matter.archived
		for share: Dictionary in shares_in(owner, int(matter.id)): fulfilled += int(share.fulfilled)
		if fulfilled == matter.total: matter.state = "completed"
		elif matter.kind == "operation" and matter.operation == "construct" and result.operation == "construct" and result.target == matter.target:
			matter.state = "satisfied"
			for share: Dictionary in shares_in(owner, int(matter.id)):
				if share.state == "accepted":
					share.state = "released"; _unindex_active(owner, share); _notify_closed(world, share, false); owner.reconcile(world, share.actor)
		if matter.state != "active": world.society.on_matter_closed(world, id)

static func compact(owner: RefCounted, world: RefCounted) -> void:
	if owner.matters.size() < MATTER_LIMIT and owner.shares.size() < SHARE_LIMIT: return
	for id: int in owner.shares.keys():
		if owner.shares.size() < SHARE_LIMIT: break
		var share: Dictionary = owner.shares[id]
		if share.state == "accepted" or owner.matters[share.matter].state != "active": continue
		if owner.Channels.retains_share(owner, share): continue
		_notify_closed(world, share, share.state == "completed")
		owner.matters[share.matter].archived += int(share.fulfilled)
		_erase_share(owner, share)
	for id: int in owner.matters.keys():
		if owner.matters.size() < MATTER_LIMIT and owner.shares.size() < SHARE_LIMIT: break
		var matter: Dictionary = owner.matters[id]
		if matter.state == "active": continue
		if owner.Channels.retains_matter(owner, id): continue
		if owner.matters.size() < MATTER_LIMIT and owner._shares_by_matter.get(id, []).is_empty(): continue
		if not owner.matter_ledger.has(matter.organization): owner.matter_ledger[matter.organization] = {"completed": 0, "cancelled": 0, "satisfied": 0, "delivery": 0, "produce": 0, "operation": 0}
		var ledger: Dictionary = owner.matter_ledger[matter.organization]
		ledger[matter.state] += 1
		ledger[matter.kind] += int(matter.archived)
		for share: Dictionary in shares_in(owner, id):
			_notify_closed(world, share, share.state == "completed")
			ledger[matter.kind] += int(share.fulfilled)
			_erase_share(owner, share)
		owner.matters.erase(id)
		if owner.matters.size() < MATTER_LIMIT and owner.shares.size() < SHARE_LIMIT: break

static func _matter_valid(owner: RefCounted, world: RefCounted, matter: Variant) -> bool:
	if not matter is Dictionary or matter.size() != 15: return false
	for field: String in ["id", "issuer", "organization", "target", "total", "quota", "deadline_ms", "version", "created_ms", "archived"]:
		if not matter.get(field) is int: return false
	if matter.id < 1 or matter.issuer < 1 or matter.issuer >= world.objects.next_id or matter.target < 1 or matter.target >= world.objects.next_id or matter.organization < 0 or (matter.organization > 0 and not owner.organizations.has(matter.organization)): return false
	if matter.get("kind") not in KINDS or matter.get("state") not in ["active", "completed", "cancelled", "satisfied"] or matter.total < 1 or matter.total > 1000000 or matter.quota < 1 or matter.quota > matter.total or matter.archived < 0 or matter.archived > matter.total: return false
	if matter.version < 1 or matter.version > 999999999999 or matter.created_ms < 0 or matter.created_ms > world.operation_time() or matter.deadline_ms < 0 or (matter.deadline_ms > 0 and matter.deadline_ms < matter.created_ms): return false
	if not matter.get("item") is String or not matter.get("operation") is String or not matter.get("sources") is Array or matter.sources.size() > SOURCE_LIMIT: return false
	for source: Variant in matter.sources:
		if not source is int or source < 1 or source >= world.objects.next_id or matter.sources.count(source) != 1 or (matter.kind == "delivery" and source == matter.target): return false
	if matter.kind in ["delivery", "produce"] and not Items.valid(matter.item): return false
	if matter.kind == "delivery" and (matter.organization <= 0 or not matter.operation.is_empty() or matter.sources.is_empty()): return false
	if matter.kind != "delivery" and not Operations.OPERATIONS.has(matter.operation): return false
	if matter.kind == "produce" and (matter.organization <= 0 or Operations.OPERATIONS[matter.operation].recipe.is_empty() or not Operations.OPERATIONS[matter.operation].recipe.outputs.has(matter.item)): return false
	if matter.kind == "operation" and (not matter.item.is_empty() or not Operations.OPERATIONS[matter.operation].recipe.is_empty() or (matter.operation == "construct" and matter.total != 1)): return false
	if matter.organization == 0 and (matter.kind != "operation" or matter.operation != "construct" or not matter.sources.is_empty()): return false
	return true

static func valid(owner: RefCounted, world: RefCounted) -> bool:
	if owner.next_matter < 1 or owner.next_matter > 999999999999 or owner.next_share < 1 or owner.next_share > 999999999999 or owner.matters.size() > MATTER_LIMIT or owner.shares.size() > SHARE_LIMIT or owner.matter_ledger.size() > owner.organizations.size() + 1: return false
	owner._shares_by_actor.clear()
	owner._shares_by_matter.clear()
	var previous: int = 0
	for id: Variant in owner.matters:
		var matter: Variant = owner.matters[id]
		if not id is int or id <= previous or id >= owner.next_matter or not _matter_valid(owner, world, matter) or matter.id != id: return false
		previous = id
	previous = 0
	for id: Variant in owner.shares:
		var share: Variant = owner.shares[id]
		if not id is int or id <= previous or id >= owner.next_share or not share is Dictionary or share.size() != 9: return false
		previous = id
		for field: String in ["id", "matter", "actor", "quota", "fulfilled", "created_ms", "deadline_ms", "last_result_id"]:
			if not share.get(field) is int: return false
		if share.id != id or not owner.matters.has(share.matter) or share.actor < 1 or share.actor >= world.objects.next_id or share.get("state") not in ["accepted", "completed", "released"]: return false
		if world.objects.records.has(share.actor) and world.objects.records[share.actor].kind != "actor": return false
		var matter: Dictionary = owner.matters[share.matter]
		# Released portions no longer occupy capacity; later downsizing must not
		# rewrite or invalidate their originally accepted historical quota.
		if share.quota < 1 or share.quota > 1000000 or share.fulfilled < 0 or share.fulfilled > share.quota or ((share.state == "completed") != (share.fulfilled == share.quota)): return false
		if share.created_ms < matter.created_ms or share.created_ms > world.elapsed_ms or share.deadline_ms < 0 or (share.deadline_ms > 0 and share.deadline_ms < share.created_ms) or share.last_result_id < 0 or share.last_result_id >= world.activity_results.next_id: return false
		if share.fulfilled > 0 and share.last_result_id == 0: return false
		if share.state == "accepted" and matter.state != "active": return false
		_index(owner, share)
	for actor: int in owner._shares_by_actor:
		var active: Array = shares_for(owner, actor)
		if active.size() > PERSON_LIMIT: return false
		var seen: Dictionary = {}
		for share: Dictionary in active:
			if seen.has(share.matter): return false
			seen[share.matter] = true
	var construction_allocations: Dictionary = {}
	for matter: Dictionary in owner.matters.values():
		if occupied(owner, matter) > matter.total: return false
		if matter.state == "active" and matter.operation == "construct" and occupied(owner, matter) > 0:
			if construction_allocations.has(matter.target): return false
			construction_allocations[matter.target] = true
		var fulfilled: int = matter.archived
		for share: Dictionary in shares_in(owner, int(matter.id)): fulfilled += int(share.fulfilled)
		if (matter.state == "completed") != (fulfilled == matter.total): return false
	for org: Variant in owner.matter_ledger:
		var ledger: Variant = owner.matter_ledger[org]
		if not org is int or (org != 0 and not owner.organizations.has(org)) or not ledger is Dictionary or ledger.size() != 6: return false
		for field: String in ["completed", "cancelled", "satisfied", "delivery", "produce", "operation"]:
			if not ledger.get(field) is int or ledger[field] < 0: return false
	return true
