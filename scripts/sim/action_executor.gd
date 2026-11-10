class_name SimActionExecutor
extends RefCounted
## Absolute-time native actions over the shared world milliseconds. No scene/UI access.

const MINUTE_MS: int = 60000

var _owner: WeakRef
var _sim: RefCounted:
	get:
		return _owner.get_ref()


func _init(simulation: RefCounted) -> void:
	_owner = weakref(simulation)


func begin(actor_id: String, action_id: String, request_id: String = "", requester: String = "") -> bool:
	if not _sim.actors.has(actor_id) or not _sim.config.actions.has(action_id):
		return false
	var actor: Dictionary = _sim.actors[actor_id]
	if not actor.active.is_empty() or not actor.alive:
		return false
	var definition: Dictionary = _sim.config.actions[action_id]
	var action: Dictionary = {
		"id": _sim.allocate_id("action"), "action": action_id, "phase": "travel",
		"path": [], "due_ms": 0, "segment_started_ms": _sim.elapsed_ms, "segment_from": actor.position.duplicate(),
		"reservations": [], "request_id": request_id, "requester": requester,
		"started_ms": _sim.elapsed_ms, "destination": "", "carrying": false,
	}
	var kind: String = definition.kind
	var destination: String = str(definition.get("source", definition.get("target", "")))
	# Only the actual consignment resumes a public delivery; personal goods stay personal.
	if kind in ["haul", "gather"] and not _custody(actor_id, action_id, definition.item, int(definition.amount)).is_empty():
		action.carrying = true
		destination = definition.target
	if kind == "consume" and _sim.inventory.available("actor:" + actor_id, definition.item) >= int(definition.amount):
		action.carrying = true
	if not _sim.places.has(destination):
		return false
	if kind in ["haul", "consume"] and not bool(action.carrying):
		if not _reserve(action, actor_id, destination, definition.item, int(definition.amount)):
			return false
	elif kind in ["gather", "forage"] and not bool(action.carrying):
		if not _reserve(action, actor_id, SimLandResources.container_id(str(definition.resource)), definition.item, int(definition.amount)):
			return false
	elif kind == "irrigate":
		# Reserve only the actor's disposable water. It stays in the original
		# pocket, protected throughout travel and work, until the land commits it.
		if not _sim.land_resources.can_irrigate(str(definition.resource)) or not _reserve(action, actor_id, "actor:" + actor_id, str(definition.item), int(definition.amount)):
			return false
	elif kind == "recipe":
		for item: String in _sorted_items(definition.inputs):
			var missing: int = int(definition.inputs[item]) if _custody(actor_id, action_id, item, int(definition.inputs[item])).is_empty() else 0
			if missing > 0 and not _reserve(action, actor_id, destination, item, missing):
				_release(action)
				return false
	if not _route(actor, action, destination):
		_release(action)
		actor.goal = "路途不通，稍后再试"
		return false
	actor.active = action
	_sim.invalidate_actor_boundary(actor_id)
	actor.goal = definition.label
	_sim.notify_labor("start", actor_id, action)
	return true


func project(actor_id: String, at_ms: int) -> void:
	var actor: Dictionary = _sim.actors[actor_id]
	var action: Dictionary = actor.active
	if action.is_empty() or action.phase != "travel" or action.path.is_empty():
		return
	if not _sim.has_cached_boundary_ahead(actor_id) and not SimRouteTravel.repair(_sim, actor_id, action, at_ms, _sim.places[action.destination].cell):
		cancel(actor_id, "route_blocked")
		return
	_sim.project_actor_route(actor_id, action, at_ms)


func settle(actor_id: String) -> void:
	var actor: Dictionary = _sim.actors[actor_id]
	var action: Dictionary = actor.active
	if action.is_empty():
		return
	if not _sim.actor_controls(actor_id, "action") or not _sim.actor_controls(actor_id, "motion"):
		cancel(actor_id, "control_lost")
		return
	if _sim.elapsed_ms - int(action.started_ms) > int(_sim.config.action_timeout) * MINUTE_MS:
		cancel(actor_id, "timeout")
		return
	if _sim.elapsed_ms < int(action.due_ms):
		return
	if action.phase == "travel":
		if not action.path.is_empty():
			var target: Array = action.path.pop_front()
			_sim.set_actor_cell(actor_id, _cell(target))
			if not action.path.is_empty():
				_begin_segment(actor, action)
				return
		_arrive(actor_id, actor, action)
	else:
		_finish(actor_id, actor, action)


func next_boundary_ms(actor: Dictionary) -> int:
	var action: Dictionary = actor.active
	if action.is_empty():
		return 0x3fffffffffffffff
	var deadline: int = mini(int(action.due_ms), int(action.started_ms) + int(_sim.config.action_timeout) * MINUTE_MS + 1)
	if action.phase == "travel":
		deadline = mini(deadline, SimRouteTravel.next_boundary(action, actor, _sim.elapsed_ms, _sim._step_validator))
	return maxi(_sim.elapsed_ms + 1, deadline)


func cancel(actor_id: String, reason: String = "cancelled") -> void:
	if not _sim.actors.has(actor_id):
		return
	var actor: Dictionary = _sim.actors[actor_id]
	if actor.active.is_empty():
		return
	var action: Dictionary = actor.active
	_release(action)
	actor.active = {}
	_sim.invalidate_actor_boundary(actor_id)
	actor.goal = "行动中断"
	actor.retry_ms = _sim.elapsed_ms + int(_sim.config.retry_minutes) * MINUTE_MS
	_sim.action_finished(actor_id, action, false, reason)


func _reserve(action: Dictionary, owner: String, container: String, item: String, amount: int) -> bool:
	var reservation: String = "%s:%s" % [action.id, item]
	if not _sim.inventory.reserve(reservation, container, item, amount, owner):
		return false
	action.reservations.append(reservation)
	return true


func _route(actor: Dictionary, action: Dictionary, place_id: String) -> bool:
	var start := Vector2i(int(actor.cell[0]), int(actor.cell[1]))
	var data: Array = _sim.places[place_id].cell
	var target := Vector2i(int(data[0]), int(data[1]))
	var path: Array[Vector2i] = _sim.find_path(start, target)
	if path.is_empty() and start != target:
		return false
	action.path = []
	for cell: Vector2i in path:
		if cell != start:
			action.path.append([cell.x, cell.y])
	action.destination = place_id
	action.phase = "travel"
	var point: Vector2 = _sim.actor_position(actor)
	if not point.is_equal_approx(TileGrid.cell_to_world(start)):
		action.path.push_front([start.x, start.y])
	_begin_segment(actor, action)
	return true


func _begin_segment(actor: Dictionary, action: Dictionary) -> void:
	SimRouteTravel.begin_segment(action, actor, _sim.elapsed_ms, float(_sim.motion_rules.motion.speed))


static func _cell(raw: Array) -> Vector2i:
	return Vector2i(int(raw[0]), int(raw[1]))


func _arrive(actor_id: String, actor: Dictionary, action: Dictionary) -> void:
	var definition: Dictionary = _sim.config.actions[action.action]
	var kind: String = definition.kind
	var pocket: String = "actor:" + actor_id
	if kind == "gather" and bool(action.carrying):
		_finish(actor_id, actor, action)
		return
	if kind == "haul" and not bool(action.carrying):
		if not _sim.inventory.transfer(
			action.id + ":pickup", definition.source, pocket,
			definition.item, int(definition.amount), str(action.reservations[0])
		):
			cancel(actor_id, "stock_missing")
			return
		SimEntrustedGoods.record_native(_sim, actor_id, action, str(definition.item), int(definition.amount), str(action.id) + ":pickup")
		action.reservations.clear()
		action.carrying = true
		_sim.observe("picked_up", actor_id, "", {"item": definition.item, "amount": definition.amount})
		if not _route(actor, action, definition.target):
			cancel(actor_id, "route_blocked")
		return
	if (kind == "consume" and not bool(action.carrying)) or kind == "recipe":
		# All ingredients remain reserved until arrival. Preflight before any move.
		for reservation_id: String in action.reservations:
			if not _sim.inventory.reservations.has(reservation_id):
				cancel(actor_id, "reservation_lost")
				return
			var reservation: Dictionary = _sim.inventory.reservations[reservation_id]
			if int(reservation.amount) > SimInventory.MAX_COUNT - _sim.inventory.quantity(pocket, reservation.item):
				cancel(actor_id, "container_full")
				return
		for reservation_id: String in action.reservations:
			var reservation: Dictionary = _sim.inventory.reservations[reservation_id]
			if not _sim.inventory.transfer(
				action.id + ":input:" + str(reservation.item), reservation.container,
				pocket, reservation.item, int(reservation.amount), reservation_id
			):
				cancel(actor_id, "stock_missing")
				return
			if kind == "recipe":
				SimEntrustedGoods.record_native(_sim, actor_id, action, str(reservation.item), int(reservation.amount), str(action.id) + ":input:" + str(reservation.item))
		action.reservations.clear()
		action.carrying = true
	action.phase = "work"
	action.segment_started_ms = _sim.elapsed_ms
	action.segment_from = actor.position.duplicate()
	action.due_ms = _sim.elapsed_ms + int(definition.minutes) * MINUTE_MS


func _finish(actor_id: String, actor: Dictionary, action: Dictionary) -> void:
	var definition: Dictionary = _sim.config.actions[action.action]
	var pocket: String = "actor:" + actor_id
	if definition.kind == "forage":
		if not _sim.land_resources.extract(action, actor_id, definition):
			cancel(actor_id, "source_unavailable")
			return
		_release(action)
		action["credit_earned"] = 0
		actor.active = {}
		actor.goal = "采下的实物已留在行囊"
		actor.retry_ms = _sim.elapsed_ms + int(_sim.config.decision_interval) * MINUTE_MS
		_sim.action_finished(actor_id, action, true, "fulfilled")
		return
	if definition.kind == "gather" and not bool(action.carrying):
		if not _sim.land_resources.extract(action, actor_id, definition):
			cancel(actor_id, "source_unavailable")
			return
		SimEntrustedGoods.record_native(_sim, actor_id, action, str(definition.item), int(definition.amount), str(action.id) + ":harvest")
		action.reservations.clear()
		action.carrying = true
		_sim.observe("picked_up", actor_id, "", {"item": definition.item, "amount": definition.amount})
		if not _route(actor, action, definition.target):
			cancel(actor_id, "route_blocked")
		return
	var succeeded: bool = true
	action["credit_earned"] = 0
	# Only a still-needed delivery/production qualifies for standing work credit.
	if definition.kind in ["haul", "gather"]:
		var stock: int = _sim.inventory.quantity(definition.target, definition.item)
		if stock < int(definition.stock_below):
			action["credit_earned"] = int(definition.get("contribution", 0))
	elif definition.kind == "recipe":
		for item: String in _sorted_items(definition.outputs):
			if _sim.inventory.quantity(definition.target, item) < int(definition.stock_below):
				action["credit_earned"] = int(definition.get("contribution", 0))
	match str(definition.kind):
		"irrigate":
			# The source validates and commits this same reservation, water use and
			# soil input together. Never release or consume it before that call.
			succeeded = _sim.land_resources.irrigate(action, actor_id, definition)
		"haul", "gather":
			var held: String = _custody(actor_id, str(action.action), str(definition.item), int(definition.amount))
			if held.is_empty():
				cancel(actor_id, "consignment_lost")
				return
			succeeded = _sim.inventory.transfer(
				action.id + ":delivery", pocket, definition.target,
				definition.item, int(definition.amount), "", held
			)
		"consume":
			succeeded = _sim.inventory.consume(action.id + ":eat", pocket, definition.item, int(definition.amount))
			if succeeded:
				actor.hunger = minf(100.0, float(actor.hunger) + float(definition.hunger_gain))
		"rest":
			actor.energy = minf(100.0, float(actor.energy) + float(definition.energy_gain))
		"recipe":
			for item: String in _sorted_items(definition.outputs):
				if int(definition.outputs[item]) > SimInventory.MAX_COUNT - _sim.inventory.quantity(definition.target, item):
					cancel(actor_id, "container_full")
					return
			for item: String in _sorted_items(definition.inputs):
				if _custody(actor_id, str(action.action), item, int(definition.inputs[item])).is_empty():
					cancel(actor_id, "ingredients_lost")
					return
			for item: String in _sorted_items(definition.inputs):
				_sim.inventory.consume(action.id + ":recipe:" + item, pocket, item, int(definition.inputs[item]), _custody(actor_id, str(action.action), item, int(definition.inputs[item])))
			# The recipe is an explicit resource source, with consumed inputs and time.
			var target: Dictionary = _sim.inventory.containers[definition.target]
			for item: String in _sorted_items(definition.outputs):
				target[item] = _sim.inventory.quantity(definition.target, item) + int(definition.outputs[item])
	_release(action)
	actor.active = {}
	_sim.invalidate_actor_boundary(actor_id)
	actor.goal = "已完成" if succeeded else "未能完成"
	actor.retry_ms = _sim.elapsed_ms + int(_sim.config.decision_interval) * MINUTE_MS
	_sim.action_finished(actor_id, action, succeeded, "fulfilled" if succeeded else "execution_failed")


func _release(action: Dictionary) -> void:
	for reservation_id: String in action.reservations:
		_sim.inventory.release(reservation_id)
	action.reservations.clear()


static func _sorted_items(items: Dictionary) -> Array:
	var keys: Array = items.keys()
	keys.sort()
	return keys


func _custody(actor: String, purpose: String, item: String, amount: int) -> String:
	return SimEntrustedGoods.find(_sim.inventory, actor, purpose, item, amount)
