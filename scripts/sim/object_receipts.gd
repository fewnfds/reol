extends RefCounted
## Compact immutable creation and stock provenance. Decode is a transient projection;
## never expand every static object's repeated request/result into saved state.

const Shape = preload("res://scripts/sim/avian_schema.gd")


static func encode(request: Dictionary, result: Dictionary, at_ms: int, sequence: int) -> Variant:
	if request.op == "stock_transfer" and _compact_stock_valid(request, result):
		var operation: String = "object_lifecycle:" + str(request.command)
		var reserved: bool = result.reservation == operation
		if request.to.has("cell"):
			# An empty target denotes the new ground container; retain a different
			# actual container when the transfer merged into an existing pile.
			var actual: String = "" if result.to.container == "ground:" + str(request.command) else result.to.container
			return ["stock_cell", request.from.region, request.from.container, request.item, request.amount, request.to.cell[0], request.to.cell[1], actual, reserved, at_ms, sequence]
		return ["stock_container", request.from.region, request.from.container, request.item, request.amount, request.to.container, reserved, at_ms, sequence]
	if request.op != "spawn":
		return {"request": request.duplicate(true), "result": result.duplicate(true), "at_ms": at_ms, "sequence": sequence}
	if request.to.has("cell"):
		return ["spawn_ground", request.id, request.definition, request.to.region, int(request.to.cell[0]), int(request.to.cell[1]), at_ms, sequence]
	return ["spawn_container", request.id, request.definition, request.to.region, request.to.container, at_ms, sequence]


static func decode(raw: Variant, command: String) -> Dictionary:
	if raw is Dictionary:
		return raw if Shape.keys(raw, ["request", "result", "at_ms", "sequence"]) and raw.request is Dictionary and raw.request.get("op") != "spawn" else {}
	if raw is Array and not raw.is_empty() and raw[0] in ["stock_cell", "stock_container"]:
		return _decode_stock(raw, command)
	if not raw is Array or raw.size() not in [7, 8]:
		return {}
	var ground: bool = raw[0] == "spawn_ground" and raw.size() == 8
	if not ground and (raw[0] != "spawn_container" or raw.size() != 7):
		return {}
	for index: int in [1, 2, 3]:
		if not SimInventory._nonempty(raw[index]):
			return {}
	var target: Dictionary = {"region": raw[3]}
	var location: Dictionary = {"region": raw[3]}
	if ground:
		if not Shape.cell_valid([raw[4], raw[5]]):
			return {}
		target["cell"] = [int(raw[4]), int(raw[5])]
		location["container"] = "ground:" + command
	else:
		if not SimInventory._nonempty(raw[4]) or str(raw[4]).begins_with("ground:"):
			return {}
		target["container"] = raw[4]
		location["container"] = raw[4]
	var request: Dictionary = {"command": command, "op": "spawn", "id": raw[1], "definition": raw[2], "to": target}
	return {"request": request, "result": {"ok": true, "reference": {"kind": "artifact", "id": raw[1]}, "to": location}, "at_ms": raw[-2], "sequence": raw[-1]}


static func _compact_stock_valid(request: Dictionary, result: Dictionary) -> bool:
	# Never drop fields if a future producer adds data or changes the contract.
	if not Shape.keys(request, ["command", "op", "from", "to", "item", "amount"]) or not SimInventory._nonempty(request.get("command")) or not SimInventory._nonempty(request.get("item")) or not Shape.count(request.get("amount"), 1):
		return false
	if not Shape.keys(request.get("from"), ["region", "container"]) or not SimInventory._nonempty(request.from.get("region")) or not SimInventory._nonempty(request.from.get("container")) or not request.get("to") is Dictionary or request.to.get("region") != request.from.region:
		return false
	var ground: bool = request.to.has("cell")
	if ground:
		if not Shape.keys(request.to, ["region", "cell"]) or not Shape.cell_valid(request.to.cell):
			return false
	elif not Shape.keys(request.to, ["region", "container"]) or not SimInventory._nonempty(request.to.get("container")):
		return false
	if not Shape.keys(result, ["ok", "reference", "from", "to", "amount", "item", "inventory_operation", "reservation"]) or not result.get("ok") is bool or not result.ok or not result.get("amount") is int or result.amount != int(request.amount):
		return false
	if not Shape.keys(result.get("to"), ["region", "container"]) or result.to.region != request.to.region or not SimInventory._nonempty(result.to.get("container")):
		return false
	if ground and not str(result.to.container).begins_with("ground:") or not ground and result.to.container != request.to.container:
		return false
	var operation: String = "object_lifecycle:" + str(request.command)
	return result.from == request.from and result.item == request.item and result.inventory_operation == operation and result.reservation is String and result.reservation in ["", operation] and result.reference == {"kind": "stock", "domain": "village", "region": request.to.region, "container": result.to.container, "item": request.item}


static func _decode_stock(raw: Array, command: String) -> Dictionary:
	var ground: bool = raw[0] == "stock_cell"
	if raw.size() != (11 if ground else 9):
		return {}
	for index: int in [1, 2, 3]:
		if not SimInventory._nonempty(raw[index]):
			return {}
	if not Shape.count(raw[4], 1):
		return {}
	var target: Dictionary = {"region": raw[1]}
	var actual: String
	var reserved: Variant
	if ground:
		if not Shape.cell_valid([raw[5], raw[6]]) or not raw[7] is String or not raw[7].is_empty() and not raw[7].begins_with("ground:"):
			return {}
		target["cell"] = [int(raw[5]), int(raw[6])]
		actual = "ground:" + command if raw[7].is_empty() else raw[7]
		reserved = raw[8]
	else:
		if not SimInventory._nonempty(raw[5]):
			return {}
		target["container"] = raw[5]
		actual = raw[5]
		reserved = raw[6]
	if not reserved is bool:
		return {}
	var source: Dictionary = {"region": raw[1], "container": raw[2]}
	var location: Dictionary = {"region": raw[1], "container": actual}
	var operation: String = "object_lifecycle:" + command
	var request: Dictionary = {"command": command, "op": "stock_transfer", "from": source, "to": target, "item": raw[3], "amount": int(raw[4])}
	var result: Dictionary = {"ok": true, "reference": {"kind": "stock", "domain": "village", "region": raw[1], "container": actual, "item": raw[3]}, "from": source.duplicate(true), "to": location, "amount": int(raw[4]), "item": raw[3], "inventory_operation": operation, "reservation": operation if reserved else ""}
	return {"request": request, "result": result, "at_ms": raw[-2], "sequence": raw[-1]}
