class_name SimSnapshotSchema
extends RefCounted
## Checks snapshot shape and references before the live world is touched.

const ConfigSchema = preload("res://scripts/sim/simulation_schema.gd")
const Inventory = preload("res://scripts/sim/inventory_ledger.gd")
const Social = preload("res://scripts/sim/social_memory.gd")
const Book = preload("res://scripts/sim/institution_book.gd")
const MAX_COUNT: int = 9007199254740991


static func validate(data: Dictionary, content: ReolContentDB, allowed_subjects: Dictionary = {}, external_inventory: Dictionary = {}) -> bool:
	if content == null or not _json_value(data) or not _count(data.get("version"), 1) or data["version"] != 7:
		return false
	if not ConfigSchema.validate_config(data.get("config")) or not SimPersonalForaging.matches(data.config, content.personal_foraging):
		return false
	for field: String in [
		"actors", "places", "situations", "authorizations", "interaction_results",
		"inventory", "social", "institutions",
	]:
		if not data.get(field) is Dictionary:
			return false
	if not _count(data.get("tick_index")) or not _count(data.get("next_id"), 1):
		return false
	if not data.get("rng_state") is String or not data["rng_state"].is_valid_int():
		return false
	if str(int(data["rng_state"])) != data["rng_state"]:
		return false
	var tick: int = int(data["tick_index"])
	if not _count(data.get("elapsed_ms")) or tick != floori(float(data.elapsed_ms) / 60000.0):
		return false
	var settings: Dictionary = data["config"]
	if not _number(data.get("last_request")) or float(data["last_request"]) != floorf(float(data["last_request"])):
		return false
	if float(data["last_request"]) < -float(settings["request_interval"]) or float(data["last_request"]) > tick:
		return false
	var actors: Dictionary = data["actors"]
	var places: Dictionary = data["places"]
	if not _same_keys(actors, settings["actor_profiles"]):
		return false
	if data.get("controlled_actor") != settings.get("controlled_actor", "player") or not actors.has(data["controlled_actor"]):
		return false
	var expected_places: Dictionary = {}
	for definition: Dictionary in settings["place_defs"]:
		expected_places[definition["id"]] = true
	if not _same_keys(places, expected_places):
		return false
	for location: Variant in places.values():
		if not location is Dictionary or not _text(location.get("label")) or not _cell(location.get("cell")):
			return false
	var inventory := Inventory.new()
	var social := Social.new()
	var institutions := Book.new()
	if not inventory.restore(data["inventory"]) or not social.restore(data["social"]) or not institutions.restore(data["institutions"]):
		return false
	if not SimEntrustedGoods.valid_native(data, inventory, bool(external_inventory.get("service_custody", false))):
		return false
	if not SimLandResources.valid_state(data.get("land_resources"), settings, places, inventory, int(data.elapsed_ms), content.land_resources, int(external_inventory.get("rainfall_limit", 0))):
		return false
	if social.actor_count() != actors.size():
		return false
	for actor: String in actors:
		if not social.has_actor(actor):
			return false
	if not SimCapabilityConversation.valid_history(social, content.capability_conversation, tick):
		return false
	var expected_containers: Dictionary = expected_places.duplicate()
	for id: String in settings.get("resource_sources", {}):
		expected_containers[SimLandResources.container_id(id)] = true
	for actor_id: String in actors:
		expected_containers["actor:" + actor_id] = true
	for id: String in external_inventory.get("containers", {}):
		if expected_containers.has(id):
			return false
		expected_containers[id] = true
	if not _same_keys(inventory.containers, expected_containers):
		return false
	var events: Dictionary = {}
	for event: Dictionary in social.events:
		if not _count(event["tick"]) or int(event["tick"]) > tick:
			return false
		if event.kind == "stock_statement" and not SimStockInformation.valid_statement(event, places):
			return false
		events[event["id"]] = event
	var decisions: Dictionary = {}
	for request: Dictionary in social.requests.values():
		if int(request["tick"]) > tick:
			return false
		decisions[request["id"]] = request
	var seen_receipts: Dictionary = {}
	var seen_actions: Dictionary = {}
	var seen_reservations: Dictionary = {}
	for actor_id: String in actors:
		var actor: Variant = actors[actor_id]
		if not _actor(actor_id, actor, settings["actor_profiles"][actor_id], content, places, inventory.containers, tick):
			return false
		for receipt: Variant in actor["receipts"]:
			if not _receipt(receipt, actor_id, events, settings["actions"], seen_receipts):
				return false
		if not actor["active"].is_empty():
			if not _active(actor_id, actor, data, inventory, decisions, seen_actions, seen_reservations):
				return false
	# Opening controller is scenario content; runtime autonomy may change when
	# the player begins a nonhuman life. Session validation checks that binding.
	for id: String in external_inventory.get("reservations", {}):
		if seen_reservations.has(id) or not inventory.reservations.has(id):
			return false
		seen_reservations[id] = true
	if seen_reservations.size() != inventory.reservations.size():
		return false
	if not _institutions(institutions, settings["institution"], actors, events, allowed_subjects):
		return false
	if not _interactions(data["interaction_results"], decisions, events):
		return false
	for key: Variant in data["authorizations"]:
		var authorization: Variant = data["authorizations"][key]
		if not authorization is Dictionary or not _keys(authorization, ["issuer", "subject", "scope"]):
			return false
		if not actors.has(authorization["issuer"]) or not actors.has(authorization["subject"]) or not _text(authorization["scope"]):
			return false
		if key != str(authorization["subject"]) + ":" + str(authorization["scope"]):
			return false
	if not _situations(data["situations"], tick, int(data["next_id"])):
		return false
	for operation_id: String in inventory.operations:
		if not external_inventory.get("operations", {}).has(operation_id) and not _allocated_before(operation_id, "action:", int(data["next_id"])):
			return false
	return true


static func _actor(
	actor_id: String, value: Variant, profile: Dictionary, content: ReolContentDB, places: Dictionary,
	containers: Dictionary, tick: int
) -> bool:
	if not value is Dictionary:
		return false
	if not _point(value.get("facing")):
		return false
	var heading := Vector2(float(value.facing[0]), float(value.facing[1]))
	if absf(heading.length() - 1.0) > 0.001:
		return false
	for field: String in ["definition_id", "rank_id", "goal"]:
		if not value.get(field) is String:
			return false
	if value["definition_id"] != profile.get("definition_id", actor_id) or not _cell(value.get("cell")):
		return false
	var definition: PawnDef = content.get_pawn(StringName(value["definition_id"]))
	if definition == null or content.get_rank(StringName(value["rank_id"])) == null:
		return false
	if not _count(value.get("qi")) or int(value["qi"]) > definition.max_qi:
		return false
	if not _count(value.get("stamina")) or int(value["stamina"]) > definition.max_stamina:
		return false
	for field: String in ["hunger", "energy", "mood"]:
		if not _range(value.get(field), 0.0, 100.0):
			return false
	if not value.get("alive") is bool or not value.get("autonomous") is bool or not _count(value.get("retry_ms")):
		return false
	if not _point(value.get("position")) or not value.get("need_carry") is Dictionary or not _keys(value.need_carry, ["hunger", "energy"]):
		return false
	var point := Vector2(float(value.position[0]), float(value.position[1]))
	if TileGrid.world_to_cell(point) != Vector2i(int(value.cell[0]), int(value.cell[1])):
		return false
	if not _count(value.get("exertion_until_ms")) or not _count(value.get("stamina_carry")) or int(value.stamina_carry) >= 1000:
		return false
	for field: String in ["hunger", "energy"]:
		if not _count(value.need_carry[field]) or int(value.need_carry[field]) >= 60000:
			return false
	if not value.get("active") is Dictionary or not value.get("receipts") is Array or not value.get("stock_memory") is Dictionary:
		return false
	if not value["alive"] and not value["active"].is_empty():
		return false
	for place_id: Variant in value["stock_memory"]:
		var memory: Variant = value["stock_memory"][place_id]
		if not places.has(place_id) or not containers.has(place_id) or not memory is Dictionary:
			return false
		if not _keys(memory, ["items", "tick"]) or not _count(memory["tick"]) or int(memory["tick"]) > tick:
			return false
		if not memory["items"] is Dictionary:
			return false
		for item: Variant in memory["items"]:
			if not _text(item) or not _count(memory["items"][item]):
				return false
	return true


static func _receipt(
	value: Variant, actor_id: String, events: Dictionary, actions: Dictionary, seen: Dictionary
) -> bool:
	if not value is Dictionary or not _keys(value, ["event", "amount"]):
		return false
	if not _text(value["event"]) or not _count(value["amount"], 1) or not events.has(value["event"]) or seen.has(value["event"]):
		return false
	var event: Dictionary = events[value["event"]]
	var task: Variant = event["details"].get("task")
	if event["kind"] != "completed" or event["actor"] != actor_id or not actions.has(task):
		return false
	var public_details: Variant = event["details"].get("public", {})
	if not public_details is Dictionary or not _count(public_details.get("work_credit"), 1):
		return false
	if int(value["amount"]) != int(public_details["work_credit"]) or int(value["amount"]) > int(actions[task].get("contribution", 0)):
		return false
	seen[value["event"]] = true
	return true


static func _active(
	actor_id: String, actor: Dictionary, data: Dictionary, inventory: RefCounted,
	decisions: Dictionary, seen_actions: Dictionary, seen_reservations: Dictionary
) -> bool:
	var action: Dictionary = actor["active"]
	var expected: Array = ["id", "action", "phase", "path", "reservations", "request_id", "requester", "destination", "carrying"]
	expected.append_array(["due_ms", "segment_started_ms", "segment_from", "started_ms"])
	if not _keys(action, expected):
		return false
	if not _text(action["id"]) or not action["id"].begins_with("action:") or seen_actions.has(action["id"]):
		return false
	if action["id"].get_slice_count(":") != 2 or not _allocated_before(action["id"], "action:", int(data["next_id"])):
		return false
	if not data["config"]["actions"].has(action["action"]) or not data["places"].has(action["destination"]):
		return false
	if not action["phase"] in ["travel", "work"] or not action["path"] is Array or not action["reservations"] is Array:
		return false
	if not action["carrying"] is bool:
		return false
	var definition: Dictionary = data["config"]["actions"][action["action"]]
	if not _count(action.get("started_ms")) or int(action.started_ms) > int(data.elapsed_ms) or not _count(action.get("due_ms")) or int(action.due_ms) <= int(data.elapsed_ms) or not _count(action.get("segment_started_ms")) or int(action.segment_started_ms) > int(data.elapsed_ms) or int(action.segment_started_ms) < int(action.started_ms) or not _point(action.get("segment_from")):
		return false
	if action.phase == "work" and int(action.due_ms) - int(action.segment_started_ms) > int(definition.minutes) * 60000:
		return false
	var expected_destination: String = str(definition.get("source", definition.get("target", "")))
	if definition["kind"] in ["haul", "gather"] and action["carrying"]:
		expected_destination = definition["target"]
	if action["destination"] != expected_destination:
		return false
	var cursor: Array = actor["cell"]
	for cell: Variant in action["path"]:
		if not _cell(cell) or (not _adjacent(cursor, cell) and not _same_cell(cursor, cell)):
			return false
		cursor = cell
	var destination: Array = data["places"][action["destination"]]["cell"]
	if not _same_cell(cursor, destination):
		return false
	if action["phase"] == "work" and (not action["path"].is_empty() or not _same_cell(actor["cell"], destination)):
		return false
	var point := Vector2(float(actor.position[0]), float(actor.position[1]))
	var origin := Vector2(float(action.segment_from[0]), float(action.segment_from[1]))
	var target: Vector2 = TileGrid.cell_to_world(Vector2i(int(destination[0]), int(destination[1])))
	if action.phase == "travel" and not action.path.is_empty():
		var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SimLocalMotion.RULES_PATH))
		if not SimRouteTravel.valid_segment(action, actor, int(data.elapsed_ms), float(rules.motion.speed)):
			return false
		target = TileGrid.cell_to_world(Vector2i(int(action.path[0][0]), int(action.path[0][1])))
		var ratio: float = float(int(data.elapsed_ms) - int(action.segment_started_ms)) / float(int(action.due_ms) - int(action.segment_started_ms))
		if not point.is_equal_approx(origin.lerp(target, ratio)):
			return false
	elif not point.is_equal_approx(target):
		return false
	if not action["request_id"] is String or not action["requester"] is String:
		return false
	if action["request_id"].is_empty():
		if not action["requester"].is_empty():
			return false
	else:
		if not decisions.has(action["request_id"]) or not data["interaction_results"].has(action["request_id"]):
			return false
		var request: Dictionary = decisions[action["request_id"]]
		var execution: Variant = data["interaction_results"][action["request_id"]]
		if request["responder"] != actor_id or request["requester"] != action["requester"] or request["task"] != action["action"] or request["status"] != "accepted":
			return false
		if not execution is Dictionary or execution.get("status") != "accepted" or execution.has("execution"):
			return false
	var expected_inputs: Dictionary = {}
	if definition["kind"] in ["consume", "haul", "gather", "forage", "irrigate"]:
		expected_inputs[definition["item"]] = int(definition["amount"])
	elif definition["kind"] == "recipe":
		expected_inputs = definition["inputs"]
	if definition.kind in ["forage", "irrigate"] and action.carrying:
		return false
	if definition.kind == "irrigate" and (action.phase == "work" and int(action.due_ms) - int(action.segment_started_ms) != int(definition.minutes) * 60000):
		return false
	if action["phase"] == "work" and not expected_inputs.is_empty() and not action["carrying"] and definition.kind not in ["gather", "forage", "irrigate"]:
		return false
	if expected_inputs.is_empty() and action["carrying"]:
		return false
	if action["carrying"]:
		if not action["reservations"].is_empty():
			return false
		for item: String in expected_inputs:
			var usable: bool = inventory.available("actor:" + actor_id, item) >= int(expected_inputs[item])
			if definition.kind in ["haul", "gather", "recipe"]:
				usable = not SimEntrustedGoods.find(inventory, actor_id, str(action.action), item, int(expected_inputs[item])).is_empty()
			if not usable:
				return false
	else:
		var missing_inputs: Dictionary = expected_inputs.duplicate()
		if definition["kind"] == "recipe":
			for item: String in expected_inputs:
				var missing: int = int(expected_inputs[item]) if SimEntrustedGoods.find(inventory, actor_id, str(action.action), item, int(expected_inputs[item])).is_empty() else 0
				if missing == 0:
					missing_inputs.erase(item)
				else:
					missing_inputs[item] = missing
		if action["reservations"].size() != missing_inputs.size():
			return false
		for reservation_id: Variant in action["reservations"]:
			if not _text(reservation_id) or seen_reservations.has(reservation_id) or not inventory.reservations.has(reservation_id):
				return false
			var reservation: Dictionary = inventory.reservations[reservation_id]
			if not missing_inputs.has(reservation["item"]):
				return false
			var source_container: String = SimLandResources.container_id(str(definition.resource)) if definition.kind in ["gather", "forage"] else str(action.destination)
			if definition.kind == "irrigate":
				source_container = "actor:" + actor_id
			if reservation_id != action["id"] + ":" + str(reservation["item"]) or reservation["owner_id"] != actor_id or reservation["container"] != source_container or int(reservation["amount"]) != int(missing_inputs[reservation["item"]]):
				return false
			seen_reservations[reservation_id] = true
	seen_actions[action["id"]] = true
	return true


static func _institutions(book: RefCounted, settings: Dictionary, actors: Dictionary, events: Dictionary, allowed_subjects: Dictionary) -> bool:
	if book.institutions.size() != 1 or not book.institutions.has(settings["id"]):
		return false
	var offices: Dictionary = book.institutions[settings["id"]]["offices"]
	if not _same_keys(offices, settings["offices"]):
		return false
	for office_id: String in offices:
		var holder: String = offices[office_id]["holder"]
		if not holder.is_empty() and not actors.has(holder):
			return false
		if offices[office_id]["permissions"] != settings["offices"][office_id]["permissions"]:
			return false
	for entry: Dictionary in book.entries:
		if not actors.has(entry["issuer"]) or (not actors.has(entry["subject"]) and not allowed_subjects.has(entry["subject"])):
			return false
		if str(entry["evidence"]).begins_with("event_") and not events.has(entry["evidence"]):
			return false
	return true


static func _interactions(results: Dictionary, decisions: Dictionary, events: Dictionary) -> bool:
	for request_id: Variant in results:
		var result: Variant = results[request_id]
		if not result is Dictionary or not decisions.has(request_id):
			return false
		var decision: Dictionary = decisions[request_id]
		for field: String in ["id", "requester", "responder", "task", "context", "policy", "score", "chance", "roll", "uncertain", "tick"]:
			if not result.has(field) or not _same_value(result[field], decision[field]):
				return false
		if not result.get("status") in ["accepted", "refused", "unfulfilled"] or not result.get("reason") is String or not result.get("message") is String:
			return false
		if (decision["status"] == "refused" and result["status"] != "refused") or (decision["status"] == "accepted" and result["status"] == "refused"):
			return false
		if result.has("execution") and (result["status"] != "accepted" or not result["execution"] in ["fulfilled", "interrupted"]):
			return false
		if not events.has(result.get("event_id")):
			return false
		var event: Dictionary = events[result["event_id"]]
		if event["kind"] != "request" or event["actor"] != decision["requester"] or event["target"] != decision["responder"] or event["details"].get("task") != decision["task"]:
			return false
	return true


static func _situations(values: Dictionary, tick: int, next_id: int) -> bool:
	for key: Variant in values:
		var situation: Variant = values[key]
		if not _text(key) or not situation is Dictionary:
			return false
		if not situation.get("status") in ["open", "resolved"] or not _count(situation.get("since")) or int(situation["since"]) > tick or not _text(situation.get("item")):
			return false
		if not _text(situation.get("id")) or not situation["id"].begins_with("situation:") or not _allocated_before(situation["id"], "situation:", next_id):
			return false
		if situation["status"] == "resolved":
			if not _count(situation.get("resolved_at")) or int(situation["resolved_at"]) < int(situation["since"]) or int(situation["resolved_at"]) > tick:
				return false
		elif situation.has("resolved_at"):
			return false
	return true


static func _allocated_before(value: String, prefix: String, next_id: int) -> bool:
	if not value.begins_with(prefix):
		return true
	var suffix: String = value.trim_prefix(prefix).get_slice(":", 0)
	return suffix.is_valid_int() and str(int(suffix)) == suffix and int(suffix) >= 1 and int(suffix) < next_id


static func _same_keys(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for key: Variant in left:
		if not right.has(key):
			return false
	return true


static func _keys(value: Dictionary, required: Array) -> bool:
	if value.size() != required.size():
		return false
	for field: String in required:
		if not value.has(field):
			return false
	return true


static func _same_value(left: Variant, right: Variant) -> bool:
	if _number(left) and _number(right):
		return float(left) == float(right)
	if left is Dictionary and right is Dictionary:
		if not _same_keys(left, right):
			return false
		for key: Variant in left:
			if not _same_value(left[key], right[key]):
				return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index: int in range(left.size()):
			if not _same_value(left[index], right[index]):
				return false
		return true
	return left == right


static func _cell(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _count(value[0]) and _count(value[1]) and float(value[0]) <= 2147483647 and float(value[1]) <= 2147483647


static func _adjacent(left: Array, right: Array) -> bool:
	var dx: int = absi(int(left[0]) - int(right[0]))
	var dy: int = absi(int(left[1]) - int(right[1]))
	return dx <= 1 and dy <= 1 and dx + dy > 0


static func _same_cell(left: Array, right: Array) -> bool:
	return int(left[0]) == int(right[0]) and int(left[1]) == int(right[1])


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _range(value: Variant, minimum: float, maximum: float) -> bool:
	return _number(value) and float(value) >= minimum and float(value) <= maximum


static func _count(value: Variant, minimum: int = 0) -> bool:
	return _range(value, minimum, MAX_COUNT) and float(value) == floorf(float(value))


static func _text(value: Variant) -> bool:
	return (value is String or value is StringName) and not str(value).strip_edges().is_empty()


static func _json_value(value: Variant, depth: int = 0) -> bool:
	if depth > 32:
		return false
	if value == null or value is String or value is bool:
		return true
	if value is int or value is float:
		return is_finite(float(value))
	if value is Array:
		for child: Variant in value:
			if not _json_value(child, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not (key is String or key is StringName) or not _json_value(value[key], depth + 1):
				return false
		return true
	return false


static func _point(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])
