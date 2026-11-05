extends RefCounted
## Compact immutable creation provenance. Decode is a transient projection;
## never expand every static object's repeated request/result into saved state.

const Shape = preload("res://scripts/sim/avian_schema.gd")


static func encode(request: Dictionary, result: Dictionary, at_ms: int, sequence: int) -> Variant:
	if request.op != "spawn":
		return {"request": request.duplicate(true), "result": result.duplicate(true), "at_ms": at_ms, "sequence": sequence}
	if request.to.has("cell"):
		return ["spawn_ground", request.id, request.definition, request.to.region, int(request.to.cell[0]), int(request.to.cell[1]), at_ms, sequence]
	return ["spawn_container", request.id, request.definition, request.to.region, request.to.container, at_ms, sequence]


static func decode(raw: Variant, command: String) -> Dictionary:
	if raw is Dictionary:
		return raw if Shape.keys(raw, ["request", "result", "at_ms", "sequence"]) and raw.request is Dictionary and raw.request.get("op") != "spawn" else {}
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
