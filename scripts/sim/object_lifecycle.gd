class_name SimObjectLifecycle
extends RefCounted
## Authority/editor transactions. Player reach, knowledge and consent are a
## separate adapter. Original artifacts and village ledgers retain all goods.

signal committed(change: Dictionary)

const Shape = preload("res://scripts/sim/avian_schema.gd")
const ActionProcess = preload("res://scripts/sim/object_actions.gd")
const Receipt = preload("res://scripts/sim/object_receipts.gd")
const MAX_RECEIPTS: int = 524288
var ground := SimGroundPlacements.new()
var receipts: Dictionary = {}
var created: Dictionary = {}
var actions: Dictionary = {}
var _owner: WeakRef
var _committing: bool = false
var _settling: bool = false
var _active_actions: Dictionary = {}
var _contained: Dictionary = {}
var _environment_cache: WeakRef
## Optional authority used only by an exclusive acceptance session. Ordinary
## game worlds keep the original synchronous lifecycle unchanged.
var _environment_guard: WeakRef
var _environment_pending: Dictionary = {}

var world: RegionalSimulation:
	get: return _owner.get_ref() if _owner != null else null


static func empty_state() -> Dictionary:
	return {"version": 1, "ground": {"version": 1, "slots": {}}, "receipts": {}, "created": {}, "actions": {}}


func initialize(authority: RegionalSimulation) -> bool:
	if authority == null:
		return false
	_owner = weakref(authority)
	return ground.configure(authority)


func bind_world(authority: RegionalSimulation) -> void:
	_owner = weakref(authority)
	# A restored owner is private until this final binding.
	ground.rebind(authority)


func manages(id: String) -> bool:
	return created.has(id)


func execute(request: Dictionary) -> Dictionary:
	if _committing or world == null:
		return _fail("transaction_busy")
	if world.artifact_transfers != null and world.artifact_transfers.checking:
		return _fail("transaction_busy")
	if not _request_valid(request):
		return _fail("invalid_request")
	if environment_change_pending() or world.environment_boundary_active():
		return _fail("transaction_busy")
	if receipts.has(request.command):
		var previous: Dictionary = _receipt(request.command)
		return previous.result.duplicate(true) if _same(previous.request, request) else _fail("command_conflict")
	if actions.has(request.command):
		return _fail("action_owns_command")
	if world.elapsed_ms != world.target_ms:
		return _fail("pending_time")
	if ActionProcess.blocked(self, request):
		return _fail("target_reserved")
	return _execute(request)


func _execute(request: Dictionary, reservation: String = "", notify: bool = true) -> Dictionary:
	if environment_change_pending():
		if _environment_pending.request.command != request.command or not _same(_environment_pending.request, request) or str(_environment_pending.reservation) != reservation or bool(_environment_pending.notify) != notify:
			return _fail("transaction_busy")
		return _resume_environment_change(_environment_pending.public_handle)
	if receipts.size() >= MAX_RECEIPTS:
		return _fail("receipt_limit")
	var guard: RefCounted = _environment_guard.get_ref() if _environment_guard != null else null
	if guard != null:
		if _unsupported_environment_change(request):
			return _fail("environment_operation_unsupported")
		if _changes_ground_artifact(request):
			return _begin_environment_move(request, reservation, notify, guard)
	var cache: RefCounted = _environment_cache.get_ref() if _environment_cache != null else null
	var fields: SimWorldEnvironmentFields = world.environment_fields as SimWorldEnvironmentFields
	var proof: Variant
	_committing = true
	if fields != null:
		# Queries used by the field candidate require every region at the already
		# committed world time. This must precede its observer-free commit span.
		var at_ms: int = world.elapsed_ms
		var target_ms: int = world.target_ms
		if not world.synchronize_regions() or world.object_lifecycle != self or world.environment_fields != fields \
				or world.elapsed_ms != at_ms or world.target_ms != target_ms:
			_committing = false
			return _fail("source_unavailable")
		var prepared: Dictionary = fields.prepare_object_change(request)
		if not bool(prepared.get("ok", false)):
			_committing = false
			return prepared
		proof = prepared.get("proof")
		if world.object_lifecycle != self or world.environment_fields != fields or world.elapsed_ms != at_ms \
				or world.target_ms != target_ms or not fields.can_commit_object_change(proof):
			fields.cancel_object_change(proof)
			_committing = false
			return _fail("environment_change_stale")
	if cache != null:
		cache.before_object_change()
	var result: Dictionary
	match str(request.op):
		"spawn": result = _spawn(request)
		"move": result = _move(request)
		"remove": result = _remove(request)
		"stock_transfer": result = _stock_transfer(request, reservation)
		_: result = _fail("unsupported_operation")
	if fields != null:
		if bool(result.get("ok", false)):
			var published: Dictionary = fields.finish_object_change(result, proof)
			assert(bool(published.get("ok", false)), "preflighted environment commit failed")
		else:
			fields.cancel_object_change(proof)
	if bool(result.ok):
		receipts[request.command] = Receipt.encode(request, result, world.elapsed_ms, receipts.size() + 1)
		if cache != null:
			# Invalidate before any external notification, including timed actions.
			# This is a disposable base cache, never physical environment history.
			cache.objects_changed(result)
	_committing = false
	if bool(result.ok) and notify:
		_publish(request, result)
	return result


func bind_environment_cache(cache: RefCounted) -> bool:
	var previous: RefCounted = _environment_cache.get_ref() if _environment_cache != null else null
	if cache != null and previous != null and previous != cache:
		return false
	_environment_cache = weakref(cache) if cache != null else null
	return true


func bind_environment_boundary_guard(guard: RefCounted) -> bool:
	if guard != null and world != null and world.environment_fields is SimWorldEnvironmentFields:
		return false
	if _committing or _settling or environment_change_pending():
		return false
	var previous: RefCounted = _environment_guard.get_ref() if _environment_guard != null else null
	if guard != null and previous != null and previous != guard:
		return false
	_environment_guard = weakref(guard) if guard != null else null
	return true


func environment_change_pending() -> bool:
	return not _environment_pending.is_empty()


func resume_environment_change(handle: Variant) -> Dictionary:
	if _settling or _committing or world == null or world.environment_boundary_active():
		return _fail("transaction_busy")
	return _resume_environment_change(handle)


func cancel_environment_change(handle: Variant) -> Dictionary:
	if _settling or _committing or world == null or world.environment_boundary_active():
		return _fail("transaction_busy")
	return _cancel_environment_change(handle)


func _cancel_environment_change(handle: Variant) -> Dictionary:
	if not environment_change_pending() or not is_same(handle, _environment_pending.public_handle):
		return _fail("invalid_handle")
	var guard: RefCounted = _environment_guard.get_ref() if _environment_guard != null else null
	if guard != null:
		guard.cancel_move(_environment_pending.guard_handle)
	_environment_pending.clear()
	return {"ok": true}


func _begin_environment_move(request: Dictionary, reservation: String, notify: bool, guard: RefCounted) -> Dictionary:
	var planned: Dictionary = prepare_move_plan(request)
	if not bool(planned.get("ok", false)):
		return planned
	var context: Variant = world.environment_event_context()
	var prepared: Dictionary = guard.prepare_move(planned.plan, context)
	if not bool(prepared.get("ok", false)):
		return prepared
	if not prepared.has("handle"):
		return _fail("environment_invalid_handle")
	var handle := EnvironmentPendingHandle.new()
	_environment_pending = {"public_handle": handle, "guard_handle": prepared.handle, "guard": guard,
		"request": request.duplicate(true), "reservation": reservation, "notify": notify,
		"plan": planned.plan, "context": context}
	if bool(prepared.get("pending", false)):
		return {"ok": true, "pending": true, "handle": handle}
	return _finish_environment_change(prepared.get("proof"))


func _resume_environment_change(handle: Variant) -> Dictionary:
	if not environment_change_pending() or not is_same(handle, _environment_pending.public_handle):
		return _fail("invalid_handle")
	var guard: RefCounted = _environment_guard.get_ref() if _environment_guard != null else null
	if guard == null or guard != _environment_pending.guard:
		_environment_pending.clear()
		return _fail("environment_guard_lost")
	var result: Dictionary = guard.resume_move(_environment_pending.guard_handle)
	if not bool(result.get("ok", false)):
		guard.cancel_move(_environment_pending.guard_handle)
		_environment_pending.clear()
		return result
	if bool(result.get("pending", false)):
		return {"ok": true, "pending": true, "handle": handle}
	return _finish_environment_change(result.get("proof"))


func _finish_environment_change(proof: Variant) -> Dictionary:
	var pending: Dictionary = _environment_pending
	var guard: RefCounted = pending.guard
	var command: String = str(pending.request.command)
	var timed: bool = not bool(pending.notify)
	if receipts.size() >= MAX_RECEIPTS or receipts.has(command) or (actions.has(command) and not timed) or (timed and (not _active_actions.has(command) or actions[command].status != "active")) or ActionProcess.blocked(self, pending.request, command if timed else ""):
		guard.cancel_move(pending.guard_handle)
		_environment_pending.clear()
		return _fail("transaction_stale")
	var check: Dictionary = prepare_move_plan(pending.request)
	if not bool(check.get("ok", false)) or not _same_move_plan(check.get("plan", {}), pending.plan):
		guard.cancel_move(pending.guard_handle)
		_environment_pending.clear()
		return check if not bool(check.get("ok", false)) else _fail("environment_plan_stale")
	var valid: Dictionary = guard.can_commit_move(proof, pending.plan, pending.context)
	if not bool(valid.get("ok", false)):
		guard.cancel_move(pending.guard_handle)
		_environment_pending.clear()
		return valid
	# The original physical write and the already-validated environment publish
	# are a synchronous transaction with no signal, callback, yield or observer.
	_committing = true
	var result: Dictionary = _move(pending.request)
	if not bool(result.get("ok", false)):
		_committing = false
		guard.cancel_move(pending.guard_handle)
		_environment_pending.clear()
		return result
	var published: Dictionary = guard.commit_move(proof, pending.plan)
	assert(bool(published.get("ok", false)), "preflighted environment commit failed")
	receipts[pending.request.command] = Receipt.encode(pending.request, result, world.elapsed_ms, receipts.size() + 1)
	_committing = false
	_environment_pending = {}
	if bool(pending.notify):
		_publish(pending.request, result)
	return result


static func _changes_ground_artifact(request: Dictionary) -> bool:
	return request.op == "move" and (str(request.from.container).begins_with("ground:") or request.to.has("cell"))


static func _unsupported_environment_change(request: Dictionary) -> bool:
	match str(request.op):
		"spawn": return request.to.has("cell")
		"remove": return str(request.from.container).begins_with("ground:")
		"stock_transfer": return str(request.from.container).begins_with("ground:") or request.to.has("cell")
	return false


func _publish(request: Dictionary, result: Dictionary) -> void:
	if committed.get_connections().is_empty():
		return
	var notice: Dictionary = {"command": request.command, "op": request.op, "at_ms": world.elapsed_ms, "result": result.duplicate(true), "ground_revision": ground.revision,
		"old_ground_cells": _notice_cells(result.get("from", {})), "new_ground_cells": _notice_cells(result.get("to", {}))}
	_freeze(notice)
	committed.emit(notice)


func _notice_cells(location: Dictionary) -> Array[Vector2i]:
	if location.has("container") and ground.slots.has(location.container):
		return ground_cells(ground.slots[location.container])
	var empty: Array[Vector2i] = []
	return empty


func diagnostics() -> Dictionary:
	return {"visibility": "authority_only", "ground": ground.stats(), "managed_identities": created.size(), "receipts": receipts.size(),
		"actions": actions.size(), "active_actions": _active_actions.size(), "container_groups": _contained.size(),
		"world_time_ms": world.elapsed_ms, "target_time_ms": world.target_ms, "has_backlog": world.target_ms > world.elapsed_ms}


func _receipt(command: String) -> Dictionary:
	return Receipt.decode(receipts.get(command), command)


func schedule(request: Dictionary, actor: String, duration_ms: int, require_contact: bool = false) -> Dictionary:
	if world != null and world.artifact_transfers != null and world.artifact_transfers.checking:
		return _fail("transaction_busy")
	return ActionProcess.schedule(self, request, actor, duration_ms, require_contact)


func owns_actor(actor: String) -> bool:
	for id: String in _active_actions:
		if actions[id].actor == actor:
			return true
	return false


func previous_autonomy(actor: String) -> bool:
	for id: String in _active_actions:
		if actions[id].actor == actor:
			return bool(actions[id].previous_autonomous)
	return false


func cancel(actor: String) -> bool:
	if _owner != null and world != null and world.has_method("accepts_commands") and not world.accepts_commands():
		return false
	if world != null and world.artifact_transfers != null and world.artifact_transfers.checking:
		return false
	if environment_change_pending() and not world.environment_boundary_active():
		return false
	return ActionProcess.cancel(self, actor)


func next_boundary_ms() -> int:
	var result: int = SimInventory.MAX_COUNT
	for id: String in _active_actions:
		result = mini(result, int(actions[id].due_ms))
	return result


func settle_at_ms(at_ms: int) -> bool:
	return ActionProcess.settle(self, at_ms)


func _spawn(request: Dictionary) -> Dictionary:
	var id: String = request.id
	if created.has(id) or world.artifacts.objects.has(id) or world.soul_vessels.vessels.has(id):
		return _fail("identity_used")
	var definition: Variant = world.artifacts.definitions.types.get(request.definition)
	if not definition is Dictionary or not definition.has("placement"):
		return _fail("unsupported_definition")
	var target: Dictionary = _destination(request.to, {"kind": "artifact", "id": id}, _size(definition), request.command)
	if not bool(target.ok):
		return target
	# The opt-in passive definition has no secondary heat/charge initialization.
	if not bool(target.get("ground", false)) and not world.artifacts.valid_location(target.region, target.container):
		return _fail("invalid_location")
	if bool(target.get("ground", false)):
		var placed: Dictionary = ground.register_slot(target.container, target.region, {"kind": "artifact", "id": id}, target.cell, _size(definition))
		if not bool(placed.ok):
			return placed
	world.artifacts.objects[id] = {"definition": request.definition, "region": target.region, "container": target.container}
	created[id] = request.command
	_index_contained(id, target.region, target.container, true)
	world.invalidate_region(target.region)
	return {"ok": true, "reference": {"kind": "artifact", "id": id}, "to": _location(target)}


func _move(request: Dictionary) -> Dictionary:
	var checked: Dictionary = _movable(request.id)
	if not bool(checked.ok):
		return checked
	var item: Dictionary = world.artifacts.objects[request.id]
	var before: Dictionary = {"region": item.region, "container": item.container}
	if not _same(before, request.from):
		return _fail("source_changed")
	if request.to.region != before.region:
		return _fail("cross_region_unsupported")
	var target: Dictionary = _destination(request.to, {"kind": "artifact", "id": request.id}, _size(world.artifacts.definitions.types[item.definition]), request.command)
	if not bool(target.ok):
		return target
	if before.region == target.region and before.container == target.container:
		return _fail("same_location")
	if bool(target.get("ground", false)):
		var placed: Dictionary = ground.register_slot(target.container, target.region, {"kind": "artifact", "id": request.id}, target.cell, _size(world.artifacts.definitions.types[item.definition]), str(item.container))
		if not bool(placed.ok):
			return placed
	item.region = target.region
	item.container = target.container
	_index_contained(request.id, before.region, before.container, false)
	_index_contained(request.id, target.region, target.container, true)
	if str(before.container).begins_with("ground:"):
		ground.deactivate(before.container)
	world.invalidate_region(before.region)
	world.invalidate_region(target.region)
	return {"ok": true, "reference": {"kind": "artifact", "id": request.id}, "from": before, "to": _location(target)}


func prepare_move_plan(request: Dictionary) -> Dictionary:
	# The exclusive caller synchronizes relevant regions before this read-only
	# preflight. It must not advance a region while preparing a candidate.
	if world == null or not _request_valid(request) or request.op != "move":
		return _fail("invalid_request")
	var source_region: String = str(request.from.region)
	if not world.regions.has(source_region) or int(world.regions[source_region].elapsed_ms) != world.elapsed_ms:
		return _fail("unsynchronized_region")
	if request.to.region != source_region:
		return _fail("cross_region_unsupported")
	var checked: Dictionary = _movable_synchronized(request.id)
	if not bool(checked.ok):
		return checked
	var item: Dictionary = world.artifacts.objects[request.id]
	var before: Dictionary = {"region": item.region, "container": item.container}
	if not _same(before, request.from):
		return _fail("source_changed")
	var size: Vector2i = _size(world.artifacts.definitions.types[item.definition])
	var target: Dictionary = _destination_synchronized(request.to, request.command)
	if not bool(target.ok):
		return target
	if before.region == target.region and before.container == target.container:
		return _fail("same_location")
	var old_slot: String = str(before.container) if str(before.container).begins_with("ground:") else ""
	if not old_slot.is_empty():
		var old: Dictionary = ground.locate(source_region, old_slot)
		if not bool(old.get("ok", false)) or not bool(old.get("active", false)) or not _same(old.get("reference"), {"kind": "artifact", "id": request.id}):
			return _fail("source_changed")
	if bool(target.ground):
		var key: String = JSON.stringify({"kind": "artifact", "id": request.id}, "", true)
		var stats: Dictionary = ground.stats()
		if int(stats.slots) >= SimGroundPlacements.MAX_SLOTS:
			return _fail("slot_capacity")
		if key.length() > SimGroundPlacements.MAX_REFERENCE_CHARACTERS - int(stats.reference_characters):
			return _fail("reference_capacity")
		var metadata: int = key.length() + str(target.container).length() + str(target.region).length()
		if metadata > SimGroundPlacements.MAX_METADATA_CHARACTERS - int(stats.metadata_characters):
			return _fail("metadata_capacity")
		var clearance: Dictionary = ground.can_place(source_region, target.cell, size, old_slot)
		if not bool(clearance.ok):
			return clearance
	var plan: Dictionary = {"request": request.duplicate(true), "reference": {"kind": "artifact", "id": request.id}, "definition": str(item.definition),
		"from": before, "target": target, "size": size, "at_ms": world.elapsed_ms,
		"ground_revision": ground.revision, "artifact_generation": world.artifacts.state_generation}
	_freeze(plan)
	return {"ok": true, "plan": plan}


static func _same_move_plan(a: Dictionary, b: Dictionary) -> bool:
	return _same(a, b)


func _remove(request: Dictionary) -> Dictionary:
	var checked: Dictionary = _movable(request.id)
	if not bool(checked.ok):
		return checked
	var item: Dictionary = world.artifacts.objects[request.id]
	var before: Dictionary = {"region": item.region, "container": item.container}
	if not _same(before, request.from):
		return _fail("source_changed")
	world.artifacts.objects.erase(request.id)
	_index_contained(request.id, before.region, before.container, false)
	if str(before.container).begins_with("ground:"):
		ground.deactivate(before.container)
	world.invalidate_region(before.region)
	return {"ok": true, "reference": {"kind": "artifact", "id": request.id}, "from": before, "removed": true}


func _movable(id: String) -> Dictionary:
	# The finite legacy domains retain their historical objects. Only definitions
	# explicitly enrolled in this lifecycle may be created, moved or terminated.
	if not created.has(id) or not world.artifacts.objects.has(id):
		return _fail("not_managed")
	if not _synchronize_operation_region(world.artifacts.objects[id].region):
		return _fail("source_unavailable")
	return _movable_synchronized(id)


func _movable_synchronized(id: String) -> Dictionary:
	if not created.has(id) or not world.artifacts.objects.has(id):
		return _fail("not_managed")
	if ground.revision >= SimGroundPlacements.MAX_REVISION - 2:
		return _fail("revision_capacity")
	if world.artifacts.target_in_use(id):
		return _fail("object_in_use")
	for event: Dictionary in world.artifacts.events:
		if event.object == id or event.get("draw", {}).get("target") == id:
			return _fail("legacy_dependency")
	# Opt-in physical props do not participate in legacy source/vessel protocols.
	return {"ok": true}


func _stock_transfer(request: Dictionary, reservation: String) -> Dictionary:
	var source: Dictionary = request.from
	if not world.regions.has(source.region):
		return _fail("not_found")
	if source.region != request.to.region:
		return _fail("cross_ledger_unsupported")
	if not _synchronize_operation_region(source.region):
		return _fail("source_unavailable")
	var inventory: SimInventory = world.regions[source.region].inventory
	if not _stock_container_mutable(source.region, source.container, request.item):
		return _fail("container_contract_unsupported")
	if not inventory.containers.has(source.container) or not inventory.can_use(source.container, request.item, int(request.amount)) and reservation.is_empty():
		return _fail("insufficient_available_stock")
	var target: Dictionary = _destination(request.to, {}, Vector2i.ONE, request.command)
	if not bool(target.ok):
		return target
	var fresh: bool = bool(target.get("ground", false))
	if fresh:
		var compatible: Dictionary = stock_destination(source.region, target.cell, request.item)
		if not bool(compatible.ok):
			return compatible
		if compatible.has("container"):
			target.container = compatible.container
			fresh = false
	elif not _stock_container_mutable(target.region, target.container, request.item):
		return _fail("container_contract_unsupported")
	if target.container == source.container:
		return _fail("same_location")
	if inventory.quantity(target.container, request.item) > SimInventory.MAX_COUNT - int(request.amount):
		return _fail("quantity_overflow")
	if not reservation.is_empty():
		var note: Variant = inventory.reservations.get(reservation)
		if not note is Dictionary or note.container != source.container or note.item != request.item or note.amount != request.amount:
			return _fail("reservation_changed")
	# No observers between preflight and this short, synchronous commit.
	var target_ref: Dictionary = {"kind": "stock", "domain": "village", "region": source.region, "container": target.container, "item": request.item}
	if fresh:
		var placed: Dictionary = ground.register_slot(target.container, target.region, target_ref, target.cell)
		if not bool(placed.ok):
			return placed
		inventory.create_container(target.container, {})
	var operation: String = "object_lifecycle:" + str(request.command)
	if not inventory.transfer(operation, source.container, target.container, request.item, int(request.amount), reservation):
		# Preflight covers every ledger condition; this is a development invariant.
		# Do not publish a half transaction if a future ledger condition is added.
		if fresh:
			inventory.containers.erase(target.container)
			ground.discard_uncommitted(target.container)
		return _fail("ledger_rejected")
	if str(source.container).begins_with("ground:") and inventory.quantity(source.container, request.item) == 0:
		ground.deactivate(source.container)
	world.invalidate_region(source.region)
	return {"ok": true, "reference": target_ref, "from": source.duplicate(true), "to": _location(target), "amount": int(request.amount), "item": request.item, "inventory_operation": operation, "reservation": reservation}


func _destination(raw: Dictionary, _reference: Dictionary, _size_hint: Vector2i, command: String) -> Dictionary:
	if not world.regions.has(raw.region):
		return _fail("not_found")
	if not _synchronize_operation_region(raw.region):
		return _fail("source_unavailable")
	return _destination_synchronized(raw, command)


func _synchronize_operation_region(region: String) -> bool:
	if _committing and world.environment_fields is SimWorldEnvironmentFields:
		# A second synchronize_region emits changed even at the same time. The
		# field proof may not have an observer between preparation and publish.
		return world.regions.has(region) and int(world.regions[region].elapsed_ms) == world.elapsed_ms
	return world.synchronize_region(region)


func _destination_synchronized(raw: Dictionary, command: String) -> Dictionary:
	if not world.regions.has(raw.region) or int(world.regions[raw.region].elapsed_ms) != world.elapsed_ms:
		return _fail("unsynchronized_region")
	if raw.has("cell"):
		var cell := Vector2i(int(raw.cell[0]), int(raw.cell[1]))
		var id: String = "ground:" + command
		if ground.slots.has(id):
			return _fail("identity_used")
		# Occupancy is checked by register_slot; stock may merge into one live pile.
		return {"ok": true, "ground": true, "region": raw.region, "container": id, "cell": cell}
	if str(raw.container).begins_with("ground:"):
		return _fail("use_ground_cell")
	# A locatable construction/production/escrow container has its own mutation
	# protocol. A query granting its position is not permission to mutate it.
	if not world.artifacts.valid_location(raw.region, raw.container):
		return _fail("container_contract_unsupported")
	var anchor: Dictionary = SimStorageQuery.locate(world, {"domain": "village", "region": raw.region, "container": raw.container})
	if not bool(anchor.ok):
		return anchor
	return {"ok": true, "ground": false, "region": raw.region, "container": raw.container}


func _stock_container_mutable(region: String, container: String, item: String) -> bool:
	var sim: VillageSimulation = world.regions[region]
	if container.begins_with("ground:"):
		var slot: Dictionary = ground.locate(region, container)
		return bool(slot.ok) and bool(slot.active) and slot.reference.kind == "stock" and slot.reference.domain == "village" and slot.reference.item == item
	return sim.places.has(container) or container.begins_with("actor:") and sim.actors.has(container.trim_prefix("actor:"))


func stock_destination(region: String, cell: Vector2i, item: String) -> Dictionary:
	# Shared immediate/timed preflight. Matching material can join a live stack;
	# other ground occupancy is not flattened or silently replaced.
	var hits: Dictionary = ground.query_cell(cell)
	if not bool(hits.ok):
		return hits
	if hits.ids.is_empty():
		return ground.can_place(region, cell)
	var slot: Dictionary = ground.slots[hits.ids[0]]
	if slot.region != region or slot.reference.kind != "stock" or slot.reference.item != item or slot.reference.domain != "village":
		return _fail("occupied")
	var clearance: Dictionary = ground.can_place(region, cell, Vector2i.ONE, hits.ids[0])
	if not bool(clearance.ok):
		return clearance
	return {"ok": true, "container": hits.ids[0]}


static func _location(target: Dictionary) -> Dictionary:
	return {"region": target.region, "container": target.container}


static func _size(definition: Dictionary) -> Vector2i:
	var value: Array = definition.placement.footprint
	return Vector2i(int(value[0]), int(value[1]))


static func _request_valid(request: Dictionary) -> bool:
	if not SimInventory._nonempty(request.get("command")) or str(request.command).length() > 128 or not request.get("op") is String:
		return false
	var fields: Array = ["command", "op"]
	match str(request.op):
		"spawn":
			fields.append_array(["id", "definition", "to"])
			if not SimInventory._nonempty(request.get("id")) or not SimInventory._nonempty(request.get("definition")):
				return false
		"move", "remove":
			fields.append_array(["id", "from"])
			if request.op == "move":
				fields.append("to")
			if not SimInventory._nonempty(request.get("id")) or not _location_valid(request.get("from"), false):
				return false
		"stock_transfer":
			fields.append_array(["from", "to", "item", "amount"])
			if not _location_valid(request.get("from"), false) or not SimInventory._nonempty(request.get("item")) or not Shape.count(request.get("amount"), 1):
				return false
		_: return false
	return Shape.keys(request, fields) and (request.op == "remove" or _location_valid(request.get("to"), true))


static func _location_valid(raw: Variant, allow_cell: bool) -> bool:
	if not raw is Dictionary or not SimInventory._nonempty(raw.get("region")):
		return false
	if allow_cell and raw.has("cell"):
		return Shape.keys(raw, ["region", "cell"]) and Shape.cell_valid(raw.cell)
	return Shape.keys(raw, ["region", "container"]) and SimInventory._nonempty(raw.get("container"))


func to_dict() -> Dictionary:
	return {"version": 1, "ground": ground.to_dict(), "receipts": receipts.duplicate(true), "created": created.duplicate(true), "actions": actions.duplicate(true)}


func restore(data: Dictionary) -> bool:
	if not Shape.keys(data, ["version", "ground", "receipts", "created", "actions"]) or data.version != 1 or not data.receipts is Dictionary or data.receipts.size() > MAX_RECEIPTS or not data.created is Dictionary or not data.actions is Dictionary:
		return false
	var next_ground := SimGroundPlacements.new()
	if not next_ground.configure(world) or not data.ground is Dictionary or not next_ground.restore(data.ground):
		return false
	for id: Variant in data.receipts:
		if not id is String:
			return false
		var row: Dictionary = Receipt.decode(data.receipts[id], id)
		if row.is_empty() or not row.request is Dictionary or not _request_valid(row.request) or row.request.command != id or not row.result is Dictionary or row.result.get("ok") != true or not Shape.count(row.at_ms, 0, world.elapsed_ms) or not Shape.count(row.sequence, 1, data.receipts.size()):
			return false
		if row.request.op == "stock_transfer" and not Shape.count(row.result.get("amount"), 1):
			return false
	for id: Variant in data.created:
		if not id is String or not data.created[id] is String or not data.receipts.has(data.created[id]):
			return false
		var request: Dictionary = Receipt.decode(data.receipts[data.created[id]], data.created[id]).request
		if request.op != "spawn" or request.id != id:
			return false
	ground = next_ground
	receipts = data.receipts.duplicate(true)
	for id: String in receipts:
		if receipts[id] is Dictionary and receipts[id].request.op == "stock_transfer":
			receipts[id].result.amount = int(receipts[id].result.amount)
	created = data.created.duplicate(true)
	actions = data.actions.duplicate(true)
	return true


static func inventory_scope(data: Variant, region: String) -> Dictionary:
	var result: Dictionary = {"containers": {}, "operations": {}, "reservations": {}}
	if not data is Dictionary or not data.get("ground") is Dictionary or not data.ground.get("slots") is Dictionary or not data.get("receipts") is Dictionary:
		return result
	for id: Variant in data.ground.slots:
		var slot: Variant = data.ground.slots[id]
		if slot is Dictionary and slot.get("region") == region and slot.get("reference") is Dictionary and slot.reference.get("kind") == "stock" and slot.reference.get("domain") == "village":
			result.containers[id] = true
	for id: Variant in data.receipts:
		if not id is String:
			continue
		var row: Dictionary = Receipt.decode(data.receipts[id], id)
		if row.get("request") is Dictionary and row.request.get("op") == "stock_transfer" and row.request.get("from") is Dictionary and row.request.from.get("region") == region:
			result.operations["object_lifecycle:" + str(id)] = true
	if data.get("actions") is Dictionary:
		for id: Variant in data.actions:
			var action: Variant = data.actions[id]
			if action is Dictionary and action.get("status") == "active" and action.get("region") == region and action.get("request") is Dictionary and action.request.get("op") == "stock_transfer":
				result.reservations["object_lifecycle:" + str(id)] = true
	return result


func cross_valid() -> bool:
	# Validate original quantities/objects and receipts in the independent candidate.
	for id: String in world.artifacts.objects:
		var item: Dictionary = world.artifacts.objects[id]
		if world.artifacts.definitions.types[item.definition].has("placement") and not created.has(id):
			return false
	for id: String in ground.slots:
		var slot: Dictionary = ground.slots[id]
		if not world.regions.has(slot.region):
			return false
		if not id.begins_with("ground:") or not receipts.has(id.trim_prefix("ground:")):
			return false
		var origin: Dictionary = _receipt(id.trim_prefix("ground:"))
		if not origin.request.has("to") or not origin.request.to.has("cell") or not _same(origin.request.to.cell, slot.cell) or origin.request.to.region != slot.region or not _same(origin.result.get("to"), {"region": slot.region, "container": id}):
			return false
		var reference: Dictionary = slot.reference
		if reference.kind == "stock":
			if reference.domain != "village" or reference.container != id or origin.request.op != "stock_transfer" or origin.request.item != reference.item or not _same(slot.size, [1, 1]):
				return false
			var inventory: SimInventory = world.regions[slot.region].inventory
			if not inventory.containers.has(id):
				return false
			for item: String in inventory.containers[id]:
				if item != reference.item:
					return false
			if bool(slot.active) != (inventory.quantity(id, reference.item) > 0):
				return false
		else:
			if origin.request.op not in ["spawn", "move"] or origin.request.id != reference.id or not created.has(reference.id):
				return false
			var creation: Dictionary = _receipt(created[reference.id]).request
			var definition: Variant = world.artifacts.definitions.types.get(creation.definition)
			if not definition is Dictionary or not definition.has("placement") or not _same(slot.size, definition.placement.footprint):
				return false
			if bool(slot.active):
				var item: Variant = world.artifacts.objects.get(reference.id)
				if not item is Dictionary or item.region != slot.region or item.container != id:
					return false
		if bool(slot.active) and world.map_data != null:
			for cell: Vector2i in ground_cells(slot):
				if not world.map_data.terrain_is_walkable(cell) or world.construction != null and world.construction.blocked(cell):
					return false
	var removed: Dictionary = {}
	var sequences: Dictionary = {}
	for command: String in receipts:
		var row: Dictionary = _receipt(command)
		if sequences.has(int(row.sequence)):
			return false
		sequences[int(row.sequence)] = command
	var locations: Dictionary = {}
	var last_ms: int = -1
	for sequence: int in range(1, receipts.size() + 1):
		var row: Dictionary = _receipt(sequences[sequence])
		var request: Dictionary = row.request
		if int(row.at_ms) < last_ms:
			return false
		last_ms = int(row.at_ms)
		if request.op in ["spawn", "move", "remove"] and not _same(row.result.get("reference"), {"kind": "artifact", "id": request.id}):
			return false
		if request.op != "spawn" and not _same(row.result.get("from"), request.from):
			return false
		if request.op != "remove":
			var destination: Dictionary = request.to
			if not destination.has("cell") and not _same(destination, row.result.get("to")):
				return false
			if destination.has("cell"):
				var slot: Variant = ground.slots.get(row.result.get("to", {}).get("container"))
				if not slot is Dictionary or slot.region != destination.region or not _same(slot.cell, destination.cell):
					return false
		if request.op == "spawn":
			if locations.has(request.id) or created.get(request.id) != request.command or not _location_valid(row.result.get("to"), false):
				return false
			locations[request.id] = row.result.to
		elif request.op in ["move", "remove"]:
			if not locations.has(request.id) or removed.has(request.id) or not _same(locations[request.id], request.from):
				return false
			if request.op == "remove":
				removed[request.id] = true
			else:
				if not _location_valid(row.result.get("to"), false):
					return false
				locations[request.id] = row.result.to
	for id: String in created:
		var opening: Dictionary = _receipt(created[id]).request
		var definition: Variant = world.artifacts.definitions.types.get(opening.definition)
		if not definition is Dictionary or not definition.has("placement"):
			return false
		var exists: bool = world.artifacts.objects.has(id)
		if exists == removed.has(id) or exists and (world.artifacts.objects[id].definition != opening.definition or not _same(locations.get(id), {"region": world.artifacts.objects[id].region, "container": world.artifacts.objects[id].container})):
			return false
	for id: String in receipts:
		var row: Dictionary = _receipt(id)
		if row.request.op == "stock_transfer":
			var request: Dictionary = row.request
			if not Shape.keys(row.result, ["ok", "reference", "from", "to", "amount", "item", "inventory_operation", "reservation"]) or row.result.amount != request.amount or row.result.item != request.item or row.result.inventory_operation != "object_lifecycle:" + id or not _same(row.result.reference, {"kind": "stock", "domain": "village", "region": request.to.region, "container": row.result.get("to", {}).get("container"), "item": request.item}):
				return false
			if not world.regions.has(request.from.region) or request.from.region != request.to.region:
				return false
			var reservation: String = "object_lifecycle:" + id if actions.has(id) else ""
			if row.result.get("reservation") != reservation:
				return false
			var expected: Dictionary = {"kind": "transfer", "source": request.from.container, "target": row.result.get("to", {}).get("container"), "item": request.item, "amount": request.amount, "reservation_id": row.result.get("reservation", "")}
			if not _same(world.regions[request.from.region].inventory.operations.get("object_lifecycle:" + id), expected):
				return false
	if not ActionProcess.cross_valid(self):
		return false
	_contained.clear()
	for id: String in created:
		if world.artifacts.objects.has(id):
			var item: Dictionary = world.artifacts.objects[id]
			_index_contained(id, item.region, item.container, true)
	return true


func _index_contained(id: String, region: String, container: String, adding: bool) -> void:
	if container.begins_with("ground:"):
		return
	var key: String = JSON.stringify([region, container])
	if adding:
		if not _contained.has(key):
			_contained[key] = {"region": region, "container": container, "ids": {}}
		_contained[key].ids[id] = true
	elif _contained.has(key):
		_contained[key].ids.erase(id)
		if _contained[key].ids.is_empty():
			_contained.erase(key)


func artifact_candidates(center: Vector2i, radius: int, budget: int = 4096) -> Dictionary:
	if radius < 0 or radius > 64 or budget < 1 or world == null or center.x < 0 or center.y < 0 or center.x >= WorldMapData.WORLD_SIZE or center.y >= WorldMapData.WORLD_SIZE:
		return _fail("invalid_query")
	var start := Vector2i(maxi(0, center.x - radius), maxi(0, center.y - radius))
	var end := Vector2i(mini(WorldMapData.WORLD_SIZE, center.x + radius + 1), mini(WorldMapData.WORLD_SIZE, center.y + radius + 1))
	var area := Rect2i(start, end - start)
	var captured: Dictionary = ground.query(area, budget)
	if not bool(captured.ok):
		return captured
	var used: int = int(captured.work_used)
	var ids: Array[String] = []
	for id: String in world.artifacts.legacy_object_ids():
		used += 1
		if used > budget:
			return _fail("budget_exhausted")
		ids.append(id)
	for slot_id: String in captured.ids:
		var reference: Dictionary = ground.slots[slot_id].reference
		if reference.kind == "artifact":
			ids.append(reference.id)
	for group: Dictionary in _contained.values():
		used += 1
		if used > budget:
			return _fail("budget_exhausted")
		var anchor: Dictionary = SimStorageQuery.locate(world, {"domain": "village", "region": group.region, "container": group.container})
		if not bool(anchor.ok):
			return anchor
		if not area.has_point(anchor.cell):
			continue
		for id: String in group.ids:
			used += 1
			if used > budget:
				return _fail("budget_exhausted")
			ids.append(id)
	return {"ok": true, "ids": ids, "work_used": used, "visibility": "authority_only", "scope": "local_artifact_candidates"}


static func ground_cells(slot: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y: int in range(int(slot.cell[1]), int(slot.cell[1]) + int(slot.size[1])):
		for x: int in range(int(slot.cell[0]), int(slot.cell[0]) + int(slot.size[0])):
			result.append(Vector2i(x, y))
	return result


static func _same(a: Variant, b: Variant) -> bool:
	return RegionalSimulation._normalized(a) == RegionalSimulation._normalized(b)


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for entry: Variant in value.values():
			_freeze(entry)
		value.make_read_only()
	elif value is Array:
		for entry: Variant in value:
			_freeze(entry)
		value.make_read_only()


class EnvironmentPendingHandle:
	extends RefCounted
