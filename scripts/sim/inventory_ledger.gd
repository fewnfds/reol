class_name SimInventory
extends RefCounted
## Quantities belong to containers. Reservations protect stock from other actions.
## Only successful operations are retained, so retrying one cannot duplicate goods.

const MAX_COUNT: int = 9007199254740991  # Largest exact integer in JSON numbers.

var containers: Dictionary = {}
var reservations: Dictionary = {}
var operations: Dictionary = {}
## Runtime-only epoch for readers of ground:* stock. Direct Dictionary writes
## do not pass through this ledger API and are outside its mutation contract.
## A successful restore always changes the epoch, even on the same instance.
var ground_revision: int = 0
## Disposition limits on real goods in the original containers, not extra stock.
var custody: Dictionary = {}


func create_container(id: String, initial: Dictionary) -> bool:
	if not _nonempty(id) or containers.has(id) or not _valid_items(initial):
		return false
	var ground: bool = id.begins_with("ground:")
	if ground and ground_revision >= MAX_COUNT:
		return false
	containers[id] = _copy_items(initial)
	if ground:
		ground_revision += 1
	return true


func quantity(container: String, item: String) -> int:
	if not containers.has(container):
		return 0
	var items: Dictionary = containers[container]
	return int(items.get(item, 0))


func available(container: String, item: String) -> int:
	var remaining: int = quantity(container, item)
	remaining -= entrusted(container, item)
	for reservation: Dictionary in reservations.values():
		if reservation["container"] == container and reservation["item"] == item:
			remaining -= int(reservation["amount"])
	return remaining


func entrusted(container: String, item: String) -> int:
	var amount: int = 0
	for note: Dictionary in custody.values():
		if note.container == container and note.item == item and note.settled_by.is_empty():
			amount += int(note.amount)
	return amount


func entrust(id: String, container: String, item: String, amount: int, basis: Dictionary) -> bool:
	var note: Dictionary = {"container": container, "item": item, "amount": amount, "basis": basis.duplicate(true), "settled_by": {}}
	if custody.has(id):
		return custody[id] == note
	if not _nonempty(id) or not containers.has(container) or not _nonempty(item) or not _valid_count(amount, false) or basis.is_empty() or available(container, item) < amount:
		return false
	if basis.get("domain") == "native" and not bool(basis.get("legacy", false)):
		if not operations.has(id):
			return false
		operations[id]["custody_origin"] = id
	custody[id] = note
	return true


func can_use(container: String, item: String, amount: int, custody_id: String = "") -> bool:
	if custody_id.is_empty():
		return available(container, item) >= amount
	if not custody.has(custody_id):
		return false
	var note: Dictionary = custody[custody_id]
	return note.container == container and note.item == item and int(note.amount) == amount and note.settled_by.is_empty() and available(container, item) >= 0


func settle_custody(id: String, domain: String, operation: String) -> void:
	if custody.has(id):
		custody[id].settled_by = {"domain": domain, "operation": operation}


func reserve(
	reservation_id: String, container: String, item: String, amount: int, owner_id: String
) -> bool:
	if not _nonempty(reservation_id) or not _nonempty(owner_id):
		return false
	var request: Dictionary = {
		"container": container, "item": item, "amount": amount, "owner_id": owner_id
	}
	if reservations.has(reservation_id):
		return reservations[reservation_id] == request
	if not containers.has(container) or not _nonempty(item) or not _valid_count(amount, false):
		return false
	if available(container, item) < amount:
		return false
	reservations[reservation_id] = request
	return true


func release(reservation_id: String) -> void:
	reservations.erase(reservation_id)


func transfer(
	operation_id: String,
	source: String,
	target: String,
	item: String,
	amount: int,
	reservation_id: String = "",
	custody_id: String = ""
) -> bool:
	if not _nonempty(operation_id):
		return false
	var request: Dictionary = {
		"kind": "transfer",
		"source": source,
		"target": target,
		"item": item,
		"amount": amount,
		"reservation_id": reservation_id,
	}
	if operations.has(operation_id):
		var previous: Dictionary = operations[operation_id].duplicate()
		previous.erase("custody_origin")
		return previous == request
	if not containers.has(source) or not containers.has(target) or source == target:
		return false
	if not _nonempty(item) or not _valid_count(amount, false):
		return false
	if reservation_id.is_empty():
		if not can_use(source, item, amount, custody_id):
			return false
	else:
		if not custody_id.is_empty():
			return false
		if not reservations.has(reservation_id):
			return false
		var reservation: Dictionary = reservations[reservation_id]
		if (
			reservation["container"] != source
			or reservation["item"] != item
			or int(reservation["amount"]) != amount
		):
			return false
		if quantity(source, item) < amount:
			return false
	var target_quantity: int = quantity(target, item)
	if amount > MAX_COUNT - target_quantity:
		return false
	var ground: bool = source.begins_with("ground:") or target.begins_with("ground:")
	if ground and ground_revision >= MAX_COUNT:
		return false
	var source_items: Dictionary = containers[source]
	var target_items: Dictionary = containers[target]
	source_items[item] = quantity(source, item) - amount
	target_items[item] = target_quantity + amount
	if not reservation_id.is_empty():
		release(reservation_id)
	operations[operation_id] = request
	if not custody_id.is_empty():
		settle_custody(custody_id, "inventory", operation_id)
	if ground:
		ground_revision += 1
	return true


func can_consume(operation_id: String, container: String, item: String, amount: int, custody_id: String = "") -> bool:
	if not _nonempty(operation_id):
		return false
	var request: Dictionary = {
		"kind": "consume", "container": container, "item": item, "amount": amount
	}
	if operations.has(operation_id):
		return operations[operation_id] == request
	if container.begins_with("ground:") and ground_revision >= MAX_COUNT:
		return false
	if not containers.has(container) or not _nonempty(item) or not _valid_count(amount, false):
		return false
	if not can_use(container, item, amount, custody_id):
		return false
	return true


func consume(operation_id: String, container: String, item: String, amount: int, custody_id: String = "") -> bool:
	if not can_consume(operation_id, container, item, amount, custody_id):
		return false
	if operations.has(operation_id):
		return true
	var items: Dictionary = containers[container]
	items[item] = quantity(container, item) - amount
	operations[operation_id] = {"kind": "consume", "container": container, "item": item, "amount": amount}
	if not custody_id.is_empty():
		settle_custody(custody_id, "inventory", operation_id)
	if container.begins_with("ground:"):
		ground_revision += 1
	return true


func transform(operation_id: String, container: String, inputs: Dictionary, outputs: Dictionary) -> bool:
	if not _nonempty(operation_id) or not containers.has(container) or inputs.is_empty() or outputs.is_empty() or not _positive_items(inputs) or not _positive_items(outputs):
		return false
	var request: Dictionary = {"kind": "transform", "container": container, "inputs": _copy_items(inputs), "outputs": _copy_items(outputs)}
	if operations.has(operation_id):
		return operations[operation_id] == request
	for item: String in inputs:
		if available(container, item) < int(inputs[item]):
			return false
	for item: String in outputs:
		var after_inputs: int = quantity(container, item) - int(inputs.get(item, 0))
		if int(outputs[item]) > MAX_COUNT - after_inputs:
			return false
	var ground: bool = container.begins_with("ground:")
	if ground and ground_revision >= MAX_COUNT:
		return false
	# Preflight everything, then commit the complete transformation once.
	for item: String in inputs:
		containers[container][item] = quantity(container, item) - int(inputs[item])
	for item: String in outputs:
		containers[container][item] = quantity(container, item) + int(outputs[item])
	operations[operation_id] = request
	if ground:
		ground_revision += 1
	return true


func to_dict() -> Dictionary:
	return {
		"containers": containers.duplicate(true),
		"reservations": reservations.duplicate(true),
		"operations": operations.duplicate(true),
		"custody": custody.duplicate(true),
	}


func restore(data: Dictionary) -> bool:
	if ground_revision >= MAX_COUNT:
		return false
	var raw_containers: Variant = data.get("containers")
	var raw_reservations: Variant = data.get("reservations")
	var raw_operations: Variant = data.get("operations")
	if (
		not raw_containers is Dictionary
		or not raw_reservations is Dictionary
		or not raw_operations is Dictionary
	):
		return false
	var next_containers: Dictionary = {}
	for id: Variant in raw_containers:
		if not _nonempty(id) or not raw_containers[id] is Dictionary:
			return false
		var items: Dictionary = raw_containers[id]
		if not _valid_items(items):
			return false
		next_containers[id] = _copy_items(items)
	var next_reservations: Dictionary = {}
	var reserved_totals: Dictionary = {}
	for id: Variant in raw_reservations:
		if not _nonempty(id) or not raw_reservations[id] is Dictionary:
			return false
		var reservation: Dictionary = raw_reservations[id]
		if not _valid_reservation(reservation, next_containers):
			return false
		var container: String = reservation["container"]
		var item: String = reservation["item"]
		var amount: int = int(reservation["amount"])
		var totals: Dictionary = reserved_totals.get(container, {})
		var previous: int = int(totals.get(item, 0))
		var items: Dictionary = next_containers[container]
		if amount > int(items.get(item, 0)) - previous:
			return false
		totals[item] = previous + amount
		reserved_totals[container] = totals
		next_reservations[id] = {
			"container": container,
			"item": item,
			"amount": amount,
			"owner_id": reservation["owner_id"],
		}
	var next_operations: Dictionary = {}
	for id: Variant in raw_operations:
		if not _nonempty(id) or not raw_operations[id] is Dictionary:
			return false
		var operation: Dictionary = raw_operations[id]
		if not _valid_operation(operation, next_containers):
			return false
		var normalized: Dictionary = operation.duplicate(true)
		if operation.kind == "transform":
			normalized["inputs"] = _copy_items(operation.inputs)
			normalized["outputs"] = _copy_items(operation.outputs)
		else:
			normalized["amount"] = int(operation["amount"])
		next_operations[id] = normalized
	var raw_custody: Variant = data.get("custody", {})
	if not raw_custody is Dictionary:
		return false
	var held_totals: Dictionary = reserved_totals.duplicate(true)
	var settlements: Dictionary = {}
	for id: Variant in raw_custody:
		var note: Variant = raw_custody[id]
		if not _nonempty(id) or not note is Dictionary or note.size() != 5 or not next_containers.has(note.get("container")) or not _nonempty(note.get("item")) or not _valid_count(note.get("amount"), false) or not note.get("basis") is Dictionary or note.basis.is_empty() or not note.get("settled_by") is Dictionary:
			return false
		if note.settled_by.is_empty():
			var totals: Dictionary = held_totals.get(note.container, {})
			var previous: int = int(totals.get(note.item, 0))
			if int(note.amount) > int(next_containers[note.container].get(note.item, 0)) - previous:
				return false
			totals[note.item] = previous + int(note.amount)
			held_totals[note.container] = totals
		else:
			if note.settled_by.size() != 2 or not note.settled_by.get("domain") in ["inventory", "service"] or not _nonempty(note.settled_by.get("operation")):
				return false
			var key: String = str(note.settled_by.domain) + ":" + str(note.settled_by.operation)
			if settlements.has(key):
				return false
			settlements[key] = true
			if note.settled_by.domain == "inventory":
				var op: Dictionary = next_operations.get(note.settled_by.operation, {})
				if op.get("kind") not in ["transfer", "consume"] or op.get("source", op.get("container")) != note.container or op.get("item") != note.item or op.get("amount") != note.amount:
					return false
	for id: String in next_operations:
		if next_operations[id].has("custody_origin") and (next_operations[id].custody_origin != id or not raw_custody.has(id)):
			return false
	containers = next_containers
	reservations = next_reservations
	operations = next_operations
	custody = raw_custody.duplicate(true)
	ground_revision += 1
	return true


static func _nonempty(value: Variant) -> bool:
	return value is String and not String(value).strip_edges().is_empty()


static func _valid_count(value: Variant, allow_zero: bool = true) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	if not is_finite(number) or number != floorf(number):
		return false
	return number >= (0 if allow_zero else 1) and number <= MAX_COUNT


static func _valid_items(items: Dictionary) -> bool:
	for item: Variant in items:
		if not _nonempty(item) or not _valid_count(items[item]):
			return false
	return true


static func _copy_items(items: Dictionary) -> Dictionary:
	var copied: Dictionary = {}
	for item: Variant in items:
		copied[item] = int(items[item])
	return copied


static func _positive_items(items: Dictionary) -> bool:
	for item: Variant in items:
		if not _nonempty(item) or not _valid_count(items[item], false):
			return false
	return true


static func _valid_reservation(record: Dictionary, known_containers: Dictionary) -> bool:
	return (
		record.size() == 4
		and _nonempty(record.get("container"))
		and known_containers.has(record["container"])
		and _nonempty(record.get("item"))
		and _nonempty(record.get("owner_id"))
		and _valid_count(record.get("amount"), false)
	)


static func _valid_operation(record: Dictionary, known_containers: Dictionary) -> bool:
	if record.get("kind") == "transform":
		return record.size() == 4 and _nonempty(record.get("container")) and known_containers.has(record.container) and record.get("inputs") is Dictionary and record.get("outputs") is Dictionary and not record.inputs.is_empty() and not record.outputs.is_empty() and _positive_items(record.inputs) and _positive_items(record.outputs)
	if not _nonempty(record.get("item")) or not _valid_count(record.get("amount"), false):
		return false
	match record.get("kind"):
		"transfer":
			return (
				(record.size() == 6 or (record.size() == 7 and _nonempty(record.get("custody_origin"))))
				and _nonempty(record.get("source"))
				and _nonempty(record.get("target"))
				and known_containers.has(record["source"])
				and known_containers.has(record["target"])
				and record["source"] != record["target"]
				and record.get("reservation_id") is String
				and (
					String(record["reservation_id"]).is_empty()
					or _nonempty(record["reservation_id"])
				)
			)
		"consume":
			return (
				record.size() == 4
				and _nonempty(record.get("container"))
				and known_containers.has(record["container"])
			)
	return false
