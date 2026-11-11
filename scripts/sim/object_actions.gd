extends RefCounted
## Timed transaction lifecycle; no second clock, quantities or position facts.
## This authority seam does not grant player reach/consent or plan NPC work.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const MAX_ACTIVE: int = 256


static func schedule(owner: SimObjectLifecycle, request: Dictionary, actor: String, duration_ms: int, require_contact: bool = false) -> Dictionary:
	var world: RegionalSimulation = owner.world
	if world == null or owner._committing or owner._settling or world.environment_boundary_active() or not owner._request_valid(request) or request.op not in ["move", "stock_transfer"] or duration_ms < 1 or duration_ms > 86400000:
		return owner._fail("invalid_action")
	var id: String = request.command
	if owner.actions.has(id):
		var previous: Dictionary = owner.actions[id]
		return {"ok": true, "action": previous.duplicate(true)} if previous.actor == actor and int(previous.due_ms) - int(previous.started_ms) == duration_ms and owner._same(previous.request, request) and bool(previous.get("contact", false)) == require_contact else owner._fail("command_conflict")
	if owner.receipts.has(id):
		return owner._fail("command_conflict")
	if owner._active_actions.size() >= MAX_ACTIVE or owner.actions.size() >= owner.MAX_RECEIPTS or world.elapsed_ms != world.target_ms or world.elapsed_ms > SimInventory.MAX_COUNT - duration_ms:
		return owner._fail("action_capacity_or_pending_time")
	var home: String = world.artifacts.actor_home(actor)
	if home.is_empty() or not world.synchronize_region(home):
		return owner._fail("actor_unavailable")
	var person: Dictionary = world.regions[home].synchronize_actor(actor)
	if not SimActionContract.can_begin(world, home, actor):
		return owner._fail("actor_busy")
	if blocked(owner, request):
		return owner._fail("target_reserved")
	if request.from.region != home or request.to.region != home:
		return owner._fail("cross_region_unsupported")
	if request.op == "move":
		var checked: Dictionary = owner._movable(request.id)
		if not bool(checked.ok):
			return checked
		var item: Dictionary = world.artifacts.objects[request.id]
		if not owner._same(request.from, {"region": item.region, "container": item.container}):
			return owner._fail("source_changed")
	if require_contact and not contact_valid(owner, request, actor):
		return owner._fail("contact_changed")
	var target: Dictionary = owner._destination(request.to, {}, Vector2i.ONE, id)
	if not bool(target.ok):
		return target
	if request.to.has("cell"):
		var size: Vector2i = owner._size(world.artifacts.definitions.types[world.artifacts.objects[request.id].definition]) if request.op == "move" else Vector2i.ONE
		var clearance: Dictionary = owner.stock_destination(home, target.cell, request.item) if request.op == "stock_transfer" else owner.ground.can_place(home, target.cell, size, request.from.container if str(request.from.container).begins_with("ground:") else "")
		if not bool(clearance.ok):
			return clearance
	var reservation: String = ""
	if request.op == "stock_transfer":
		if not owner._stock_container_mutable(home, request.from.container, request.item):
			return owner._fail("container_contract_unsupported")
		reservation = "object_lifecycle:" + id
		if not world.regions[home].inventory.reserve(reservation, request.from.container, request.item, int(request.amount), actor):
			return owner._fail("insufficient_available_stock")
	var action: Dictionary = {"actor": actor, "region": home, "request": request.duplicate(true), "started_ms": world.elapsed_ms, "due_ms": world.elapsed_ms + duration_ms,
		"finished_ms": -1, "status": "active", "reservation": reservation, "previous_autonomous": bool(person.autonomous), "position": person.position.duplicate(), "result": {}}
	if require_contact:
		action["contact"] = true
	owner.actions[id] = action
	owner._active_actions[id] = true
	SimActionContract.occupy(world, home, actor)
	return {"ok": true, "action": action.duplicate(true)}


static func contact_valid(owner: SimObjectLifecycle, request: Dictionary, actor: String) -> bool:
	# Optional physical handling constraint, persisted on the original action.
	# Recheck at its deadline: a wall built during the work can break contact.
	if request.op != "move":
		return false
	var world: RegionalSimulation = owner.world
	var home: String = world.artifacts.actor_home(actor)
	if home.is_empty() or request.from.region != home or request.to.region != home:
		return false
	var hand: String = "actor:" + actor
	var cell: Vector2i
	if str(request.from.container).begins_with("ground:") and request.to.get("container") == hand:
		var slot: Dictionary = owner.ground.locate(home, request.from.container)
		if not bool(slot.get("ok", false)) or not bool(slot.get("active", false)) or slot.reference != {"kind": "artifact", "id": request.id}:
			return false
		cell = slot.cell
	elif request.from.container == hand and request.to.has("cell"):
		cell = SimRouteTravel.cell(request.to.cell)
	else:
		return false
	var origin: Vector2 = SimRouteTravel.point(world.regions[home].synchronize_actor(actor))
	var target: Vector2 = TileGrid.cell_to_world(cell)
	var level: int = SimConflictSpace.level(world, origin)
	return origin.distance_to(target) <= float(world.artifacts.definitions.interaction_radius) * TileGrid.TILE_SIZE and level == SimConflictSpace.level(world, target) and SimConflictSpace.clear_segment(world, origin, target, level)


static func blocked(owner: SimObjectLifecycle, request: Dictionary, except_id: String = "") -> bool:
	if owner._active_actions.is_empty():
		return false
	var wanted: Array[String] = _keys(owner, request)
	for id: String in owner._active_actions:
		if id == except_id:
			continue
		for key: String in _keys(owner, owner.actions[id].request):
			if wanted.has(key):
				return true
	return false


static func _keys(owner: SimObjectLifecycle, request: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	if request.has("id"):
		keys.append("object:" + str(request.id))
	if request.op == "stock_transfer":
		keys.append("stock:" + str(request.from.region) + ":" + str(request.from.container) + ":" + str(request.item))
	if request.has("to") and request.to.has("cell"):
		var size := Vector2i.ONE
		var definition: Variant = null
		if request.op == "spawn":
			definition = owner.world.artifacts.definitions.types.get(request.definition)
		elif request.op == "move" and owner.world.artifacts.objects.has(request.id):
			definition = owner.world.artifacts.definitions.types.get(owner.world.artifacts.objects[request.id].definition)
		if definition is Dictionary and definition.has("placement"):
			size = owner._size(definition)
		for y: int in range(int(request.to.cell[1]), int(request.to.cell[1]) + size.y):
			for x: int in range(int(request.to.cell[0]), int(request.to.cell[0]) + size.x):
				keys.append("ground:" + str(x) + ":" + str(y))
	return keys


static func settle(owner: SimObjectLifecycle, at_ms: int) -> bool:
	# Active set is bounded, ordered for same-millisecond deterministic commits.
	var ids: Array = owner._active_actions.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return int(owner.actions[a].due_ms) < int(owner.actions[b].due_ms) or int(owner.actions[a].due_ms) == int(owner.actions[b].due_ms) and a < b)
	for id: String in ids:
		if owner.world == null or owner.world.object_lifecycle != owner:
			return true
		# A preceding completion callback can cancel another action at this same
		# deadline. Snapshot iteration is not authority to execute cancelled work.
		if not owner._active_actions.has(id) or owner.actions[id].status != "active":
			continue
		var action: Dictionary = owner.actions[id]
		if int(action.due_ms) > at_ms:
			continue
		owner._settling = true
		var result: Dictionary = owner._fail("actor_changed")
		if SimActionContract.can_continue(owner.world, action.region, action.actor, &"object_lifecycle", action.position):
			result = owner._execute(action.request, action.reservation, false) if not bool(action.get("contact", false)) or contact_valid(owner, action.request, action.actor) else owner._fail("contact_changed")
		_finish(owner, id, "completed" if bool(result.ok) else "failed", result)
		owner._settling = false
		if owner.world == null or owner.world.object_lifecycle != owner:
			return true
		if bool(result.ok):
			owner._publish(action.request, result)
	return true


static func cancel(owner: SimObjectLifecycle, actor: String) -> bool:
	if owner._committing or owner._settling:
		return false
	for id: String in owner._active_actions.keys():
		if owner.actions[id].actor == actor:
			_finish(owner, id, "cancelled", owner._fail("cancelled"))
			return true
	return false


static func _finish(owner: SimObjectLifecycle, id: String, status: String, result: Dictionary) -> void:
	var action: Dictionary = owner.actions[id]
	action.status = status
	action.finished_ms = owner.world.elapsed_ms
	action.result = result.duplicate(true)
	owner._active_actions.erase(id)
	SimActionContract.release(owner.world, action.region, action.actor, action.previous_autonomous, action.reservation)
	SimActionContract.publish_finished(owner.world, SimActionContract.view(owner.world, "object_lifecycle", id, action.actor, action.request.op, "work", int(action.started_ms), int(action.due_ms), status, action.request.get("id", "")), result.get("reason", "completed"))


static func cross_valid(owner: SimObjectLifecycle) -> bool:
	var actors: Dictionary = {}
	var active: Dictionary = {}
	var world: RegionalSimulation = owner.world
	for id: Variant in owner.actions:
		var action: Variant = owner.actions[id]
		var fields: Array = ["actor", "region", "request", "started_ms", "due_ms", "finished_ms", "status", "reservation", "previous_autonomous", "position", "result"]
		if action is Dictionary and action.has("contact"):
			if not action.contact is bool or not action.contact:
				return false
			fields.append("contact")
		if not id is String or not action is Dictionary or not Shape.keys(action, fields) or not action.request is Dictionary or not owner._request_valid(action.request) or action.request.command != id or action.request.op not in ["move", "stock_transfer"] or not action.previous_autonomous is bool or not action.result is Dictionary or not action.reservation is String or not SimLocalMotion._vector(action.position):
			return false
		if action.has("contact") and action.request.op != "move":
			return false
		if not world.regions.has(action.region) or not world.regions[action.region].has_actor(action.actor) or action.request.from.region != action.region or action.request.to.region != action.region:
			return false
		if not Shape.count(action.started_ms, 0, world.elapsed_ms) or not Shape.count(action.due_ms, int(action.started_ms) + 1, mini(SimInventory.MAX_COUNT, int(action.started_ms) + 86400000)):
			return false
		var expected: String = "object_lifecycle:" + str(id) if action.request.op == "stock_transfer" else ""
		if action.reservation != expected:
			return false
		var inventory: SimInventory = world.regions[action.region].inventory
		if action.status == "active":
			if not Shape.count(action.due_ms, world.elapsed_ms + 1) or action.finished_ms != -1 or not action.result.is_empty() or owner.receipts.has(id) or actors.has(action.actor):
				return false
			var person: Dictionary = world.regions[action.region].synchronize_actor(action.actor)
			if not bool(person.alive) or bool(person.autonomous) or not person.active.is_empty() or not owner._same(person.position, action.position) or not world.actor_controls(action.actor, "action") or not world.actor_controls(action.actor, "motion") or world.owns_for_scope(action.actor, &"body", &"object_lifecycle"):
				return false
			if not expected.is_empty() and not owner._same(inventory.reservations.get(expected), {"container": action.request.from.container, "item": action.request.item, "amount": action.request.amount, "owner_id": action.actor}):
				return false
			if action.request.op == "move":
				var item: Variant = world.artifacts.objects.get(action.request.id)
				if not item is Dictionary or not owner.manages(action.request.id) or not owner._same(action.request.from, {"region": item.region, "container": item.container}):
					return false
			actors[action.actor] = true
			active[id] = true
		elif action.status in ["completed", "failed", "cancelled"]:
			if not Shape.count(action.finished_ms, int(action.started_ms), mini(int(action.due_ms), world.elapsed_ms)) or inventory.reservations.has(expected):
				return false
			if action.status == "completed":
				if int(action.finished_ms) != int(action.due_ms) or not owner.receipts.has(id):
					return false
				var receipt: Dictionary = owner._receipt(id)
				if receipt.is_empty() or not owner._same(receipt.request, action.request) or not owner._same(receipt.result, action.result):
					return false
			elif owner.receipts.has(id) or action.result.get("ok") != false or not action.result.get("reason") is String:
				return false
		else:
			return false
	if active.size() > MAX_ACTIVE:
		return false
	owner._active_actions = active
	for id: String in active:
		if blocked(owner, owner.actions[id].request, id):
			return false
	for region: String in world.regions:
		for id: String in world.regions[region].inventory.reservations:
			if id.begins_with("object_lifecycle:") and not active.has(id.trim_prefix("object_lifecycle:")):
				return false
	return true
