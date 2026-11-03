extends RefCounted
## Validate the real definition and corrupt independent copies at schema edges.

const Schema = preload("res://scripts/sim/simulation_schema.gd")
const SnapshotSchema = preload("res://scripts/sim/snapshot_schema.gd")


func run(runner: Object) -> void:
	var definition: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/village.json"))
	runner.assert_true(definition is Dictionary, "simulation definition is a JSON object")
	if not definition is Dictionary:
		return
	var base: Dictionary = definition
	runner.assert_true(Schema.validate_config(base), "current simulation definition passes the complete schema")
	_test_required_fields(runner, base)
	_test_numbers(runner, base)
	_test_places_and_stock(runner, base)
	_test_actions(runner, base)
	_test_profiles_and_offices(runner, base)
	_test_scenario_and_policy(runner, base)
	_test_variable_initial_conditions(runner, base)
	_test_snapshot_validation(runner)
	_test_weight_order(runner)


func _test_required_fields(runner: Object, base: Dictionary) -> void:
	for field: String in base:
		if field == "controlled_actor":
			continue
		var missing: Dictionary = base.duplicate(true)
		missing.erase(field)
		runner.assert_true(not Schema.validate_config(missing), "missing top-level %s is rejected" % field)
	for field: String in ["hunger_per_minute", "energy_per_minute", "work_energy_per_minute", "eat_below", "rest_below"]:
		var missing: Dictionary = base.duplicate(true)
		missing["needs"].erase(field)
		runner.assert_true(not Schema.validate_config(missing), "missing needs.%s is rejected" % field)
	for field: String in ["bias", "weights", "accept_threshold", "uncertainty_band", "outcome_effects"]:
		var missing: Dictionary = base.duplicate(true)
		missing["social_policy"].erase(field)
		runner.assert_true(not Schema.validate_config(missing), "missing policy.%s is rejected" % field)
	for value: Variant in [null, [], "config", 1]:
		runner.assert_true(not Schema.validate_config(value), "non-object simulation definition is rejected")


func _test_numbers(runner: Object, base: Dictionary) -> void:
	for field: String in [
		"navigation_budget", "move_minutes_per_cell", "decision_interval", "retry_minutes",
		"request_interval", "talk_radius", "history_limit", "action_timeout",
	]:
		_reject(runner, base, [field], 0, "%s must be positive" % field)
		_reject(runner, base, [field], -1, "%s cannot be negative" % field)
		_reject(runner, base, [field], 1.5, "%s must be a whole count of minutes or cells" % field)
	_reject(runner, base, ["navigation_radius"], -1, "negative navigation radius")
	_reject(runner, base, ["observation_radius"], -1, "negative observation radius")
	_reject(runner, base, ["seed"], NAN, "non-finite seed")
	_reject(runner, base, ["seed"], true, "boolean is not a seed number")
	_reject(runner, base, ["schema_version"], true, "boolean is not a schema version")
	_reject(runner, base, ["schema_version"], 2, "unknown definition version")
	for field: String in ["hunger_per_minute", "energy_per_minute", "work_energy_per_minute", "eat_below", "rest_below"]:
		_reject(runner, base, ["needs", field], -0.1, "negative need rate or threshold: " + field)
		_reject(runner, base, ["needs", field], 100.1, "need outside 0..100: " + field)
		_reject(runner, base, ["needs", field], INF, "non-finite need: " + field)


func _test_places_and_stock(runner: Object, base: Dictionary) -> void:
	_reject(runner, base, ["place_defs"], [], "empty facility definitions")
	_reject(runner, base, ["place_defs", 0, "id"], "", "blank facility ID")
	_reject(runner, base, ["place_defs", 0, "label"], 42, "non-text facility label")
	_reject(runner, base, ["place_defs", 0, "offset"], [0.5, 0], "fractional grid offset")
	_reject(runner, base, ["place_defs", 0, "offset"], [0], "incomplete grid offset")
	_reject(runner, base, ["place_defs", 0, "offset"], [2147483648, 0], "offset outside Vector2i range")
	_reject(runner, base, ["place_defs", 0, "id"], "actor:player", "facility conflicts with actor-container namespace")
	var duplicate: Dictionary = base.duplicate(true)
	duplicate["place_defs"].append(duplicate["place_defs"][0].duplicate(true))
	runner.assert_true(not Schema.validate_config(duplicate), "duplicate facility IDs are rejected")
	var orphan: Dictionary = base.duplicate(true)
	orphan["initial_stock"]["unknown_place"] = {"wood": 1}
	runner.assert_true(not Schema.validate_config(orphan), "stock container must name a declared facility")
	_reject(runner, base, ["initial_stock", "store", "wood"], -1, "negative initial stock")
	_reject(runner, base, ["initial_stock", "store", "wood"], 0.5, "fractional item count")
	_reject(runner, base, ["initial_stock", "store", "wood"], true, "boolean item count")
	_reject(runner, base, ["initial_stock", "store", "wood"], 9007199254740992, "count above exact JSON integer range")
	var empty_item: Dictionary = base.duplicate(true)
	empty_item["initial_stock"]["store"][""] = 1
	runner.assert_true(not Schema.validate_config(empty_item), "blank stock item ID is rejected")
	var no_source_container: Dictionary = base.duplicate(true)
	no_source_container["initial_stock"].erase("store")
	runner.assert_true(not Schema.validate_config(no_source_container), "material action source must have a container")


func _test_actions(runner: Object, base: Dictionary) -> void:
	for field: String in ["kind", "source", "target", "item", "amount", "minutes", "stock_below", "label"]:
		var missing: Dictionary = base.duplicate(true)
		missing["actions"]["deliver_wood"].erase(field)
		runner.assert_true(not Schema.validate_config(missing), "haul requires " + field)
	_reject(runner, base, ["actions", "deliver_wood", "kind"], "teleport", "unknown action kind")
	_reject(runner, base, ["actions", "deliver_wood", "source"], "unknown_place", "unknown action source")
	_reject(runner, base, ["actions", "deliver_wood", "target"], "unknown_place", "unknown action target")
	_reject(runner, base, ["actions", "deliver_wood", "target"], "store", "haul cannot transfer into its own source")
	_reject(runner, base, ["actions", "deliver_wood", "amount"], 0, "haul requires a positive count")
	_reject(runner, base, ["actions", "deliver_wood", "minutes"], 0, "action duration must be positive")
	_reject(runner, base, ["actions", "deliver_wood", "contribution"], -1, "negative institutional award")
	_reject(runner, base, ["actions", "deliver_wood", "stock_below"], -1, "negative replenishment threshold")
	_reject(runner, base, ["actions", "eat", "hunger_gain"], -1, "negative eating gain")
	_reject(runner, base, ["actions", "rest", "energy_gain"], 101, "rest gain outside need range")
	_reject(runner, base, ["actions", "cook", "inputs"], {}, "recipe requires actual inputs")
	_reject(runner, base, ["actions", "cook", "outputs"], {}, "recipe requires actual outputs")
	_reject(runner, base, ["actions", "cook", "inputs", "wood"], 0, "recipe ingredient count must be positive")
	_reject(runner, base, ["actions", "cook", "outputs", "meal"], -1, "recipe output count must be positive")
	var wrongly_routed: Dictionary = base.duplicate(true)
	wrongly_routed["actions"]["rest"]["source"] = "store"
	runner.assert_true(not Schema.validate_config(wrongly_routed), "rest cannot silently redirect to a source facility")
	for verb: String in ["eat", "rest", "report", "check_kitchen"]:
		var absent_builtin: Dictionary = base.duplicate(true)
		absent_builtin["actions"].erase(verb)
		runner.assert_true(not Schema.validate_config(absent_builtin), "runtime's %s action must be defined" % verb)


func _test_profiles_and_offices(runner: Object, base: Dictionary) -> void:
	_reject(runner, base, ["actor_profiles", "player"], "profile", "actor profile must be an object")
	_reject(runner, base, ["actor_profiles", "player", "hunger"], -1, "profile hunger cannot be negative")
	_reject(runner, base, ["actor_profiles", "player", "energy"], 101, "profile energy cannot exceed its scale")
	_reject(runner, base, ["actor_profiles", "player", "autonomous"], 0, "autonomy must be boolean")
	_reject(runner, base, ["actor_profiles", "player", "autonomous"], true, "controlled actor cannot also be autonomous")
	_reject(runner, base, ["actor_profiles", "player", "definition_id"], "", "profile definition reference must be nonempty")
	_reject(runner, base, ["actor_profiles", "lao_zhou", "benevolence"], 1.1, "benevolence outside 0..1")
	_reject(runner, base, ["actor_profiles", "lao_zhou", "duty"], "missing_action", "duty must reference a known action")
	_reject(runner, base, ["institution", "offices", "registrar", "holder"], "missing_actor", "office holder must reference a declared actor")
	_reject(runner, base, ["institution", "offices", "registrar", "holder"], 7, "office holder must be an actor ID")
	_reject(runner, base, ["institution", "offices", "registrar", "permissions"], ["record", "record"], "duplicate office capability")
	_reject(runner, base, ["institution", "offices", "registrar", "permissions"], ["all_powerful"], "unknown office capability")
	for invalid: Variant in ["missing_actor", "", 3, null]:
		_reject(runner, base, ["controlled_actor"], invalid, "invalid controlled actor")


func _test_scenario_and_policy(runner: Object, base: Dictionary) -> void:
	_reject(runner, base, ["scenario", "requester"], "missing_actor", "unknown scenario requester")
	_reject(runner, base, ["scenario", "helpers"], ["missing_actor"], "unknown scenario helper")
	_reject(runner, base, ["scenario", "helpers"], ["lao_zhou", "lao_zhou"], "duplicate scenario helper")
	_reject(runner, base, ["scenario", "helpers"], ["a_he"], "requester cannot ask themselves")
	var disabled: Dictionary = base.duplicate(true)
	disabled["scenario"]["helpers"] = []
	runner.assert_true(Schema.validate_config(disabled), "empty helpers disable automatic requests")
	_reject(runner, base, ["scenario", "task"], "missing_action", "unknown scenario action")
	_reject(runner, base, ["scenario", "task"], "inspect", "shortage scenario requires an inventory delivery action")
	_reject(runner, base, ["social_policy", "bias"], INF, "non-finite request bias")
	_reject(runner, base, ["social_policy", "uncertainty_band"], -0.1, "negative dice uncertainty band")
	_reject(runner, base, ["social_policy", "context_step"], 0, "request context precision must be positive")
	_reject(runner, base, ["social_policy", "context_step"], 1.1, "request context precision outside its scale")
	_reject(runner, base, ["social_policy", "weights", "risk"], NAN, "non-finite request weight")
	var unknown_factor: Dictionary = base.duplicate(true)
	unknown_factor["social_policy"]["weights"]["omniscient_reputation"] = 1.0
	runner.assert_true(not Schema.validate_config(unknown_factor), "unknown social factor is not silently ignored")
	_reject(runner, base, ["social_policy", "outcome_effects", "fulfilled"], [0.1], "relationship effect needs two components")
	_reject(runner, base, ["social_policy", "outcome_effects", "fulfilled"], [1.1, 0], "relationship effect outside its scale")
	var unknown_outcome: Dictionary = base.duplicate(true)
	unknown_outcome["social_policy"]["outcome_effects"]["unknown_outcome"] = [0.1, 0.1]
	runner.assert_true(not Schema.validate_config(unknown_outcome), "unknown relationship outcome is rejected")


func _test_variable_initial_conditions(runner: Object, base: Dictionary) -> void:
	var changed: Dictionary = base.duplicate(true)
	changed["seed"] = -5
	changed["decision_interval"] = 3
	changed["actions"]["deliver_wood"]["minutes"] = 12
	changed["initial_stock"]["store"]["wood"] = 0
	changed["actor_profiles"]["lao_zhou"]["energy"] = 100
	changed["actor_profiles"]["lao_zhou"]["hunger"] = 0
	changed["actor_profiles"]["lao_zhou"]["duty"] = ""
	changed["actor_profiles"]["a_he"] = {}
	changed["institution"]["offices"]["registrar"]["holder"] = ""
	changed["social_policy"]["bias"] = -0.2
	runner.assert_true(Schema.validate_config(changed), "rates, stock, profiles, vacancies and policy remain tunable initial conditions")
	var renamed: Dictionary = base.duplicate(true)
	renamed["controlled_actor"] = "traveler"
	renamed["actor_profiles"]["traveler"] = renamed["actor_profiles"]["player"]
	renamed["actor_profiles"].erase("player")
	renamed["initial_stock"]["cookhouse"] = renamed["initial_stock"]["kitchen"]
	renamed["initial_stock"].erase("kitchen")
	for place: Dictionary in renamed["place_defs"]:
		if place["id"] == "kitchen":
			place["id"] = "cookhouse"
	for action: Dictionary in renamed["actions"].values():
		for field: String in ["source", "target"]:
			if action.get(field) == "kitchen":
				action[field] = "cookhouse"
	runner.assert_true(Schema.validate_config(renamed), "schema does not freeze initial actor or facility content IDs")
	var before: String = JSON.stringify(renamed)
	Schema.validate_config(renamed)
	runner.assert_eq(JSON.stringify(renamed), before, "validation does not mutate configuration")


func _reject(runner: Object, base: Dictionary, path: Array, replacement: Variant, label: String) -> void:
	var changed: Dictionary = base.duplicate(true)
	var cursor: Variant = changed
	for index: int in range(path.size() - 1):
		cursor = cursor[path[index]]
	cursor[path[path.size() - 1]] = replacement
	runner.assert_true(not Schema.validate_config(changed), label)


func _snapshot_fixture(runner: Object, content: ReolContentDB, extra_profiles: Dictionary = {}) -> RefCounted:
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/village.json"))
	settings["actor_profiles"].merge(extra_profiles.duplicate(true), true)
	settings["scenario"]["helpers"] = []
	var actor_ids: Array = settings["actor_profiles"].keys()
	actor_ids.sort()
	var cells: Dictionary = {}
	for index: int in range(actor_ids.size()):
		var actor_id: String = actor_ids[index]
		settings["actor_profiles"][actor_id]["autonomous"] = false
		cells[actor_id] = [100 + index, 100]
	var places: Dictionary = {}
	for place: Dictionary in settings["place_defs"]:
		places[place["id"]] = {
			"label": place["label"],
			"cell": [100 + int(place["offset"][0]), 100 + int(place["offset"][1])],
		}
	var simulation: RefCounted = load("res://scripts/sim/village_simulation.gd").new()
	if not simulation.initialize(content, settings, cells, places):
		runner.assert_true(false, "snapshot fixture initializes")
		return null
	simulation.set_navigation(_snapshot_path)
	return simulation


func _snapshot_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [from_cell]
	var cursor: Vector2i = from_cell
	while cursor.x != to_cell.x:
		cursor.x += 1 if cursor.x < to_cell.x else -1
		path.append(cursor)
	while cursor.y != to_cell.y:
		cursor.y += 1 if cursor.y < to_cell.y else -1
		path.append(cursor)
	return path


func _test_snapshot_validation(runner: Object) -> void:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "snapshot content loads")
		return
	var simulation: Variant = _snapshot_fixture(runner, content)
	if simulation == null:
		return
	var idle: Dictionary = simulation.to_dict()
	runner.assert_true(SnapshotSchema.validate(idle, content), "newly initialized world is a valid snapshot")
	_reject_snapshot(runner, idle, content, ["actors", "player", "definition_id"], "missing", "unknown pawn definition")
	_reject_snapshot(runner, idle, content, ["actors", "player", "definition_id"], "chen_shouzhuo", "actor cannot impersonate another definition")
	_reject_snapshot(runner, idle, content, ["actors", "player", "rank_id"], "missing", "unknown institutional rank")
	_reject_snapshot(runner, idle, content, ["actors", "player", "qi"], 100000, "qi above pawn maximum")
	_reject_snapshot(runner, idle, content, ["actors", "player", "stamina"], -1, "negative stamina")
	_reject_snapshot(runner, idle, content, ["actors", "player", "mood"], 101, "mood outside need scale")
	_reject_snapshot(runner, idle, content, ["actors", "player", "alive"], "alive", "non-boolean life state")
	_reject_snapshot(runner, idle, content, ["controlled_actor"], "a_he", "snapshot cannot silently change controlled actor")
	_reject_snapshot(runner, idle, content, ["places", "kitchen", "cell"], [-1, 0], "negative facility cell")
	_reject_snapshot(runner, idle, content, ["places", "kitchen", "label"], null, "missing facility label")
	var missing_actor: Dictionary = idle.duplicate(true)
	missing_actor["actors"].erase("lao_zhou")
	runner.assert_true(not SnapshotSchema.validate(missing_actor, content), "snapshot actor IDs must match its definition")
	var invalid_memory: Dictionary = idle.duplicate(true)
	invalid_memory["actors"]["player"]["stock_memory"]["kitchen"] = {"items": {"wood": 1}, "tick": 1}
	runner.assert_true(not SnapshotSchema.validate(invalid_memory, content), "future stock observation is rejected")
	invalid_memory["actors"]["player"]["stock_memory"]["kitchen"] = {"items": {"wood": -1}, "tick": 0}
	runner.assert_true(not SnapshotSchema.validate(invalid_memory, content), "negative remembered item count is rejected")
	runner.assert_true(simulation.submit_action("player", "deliver_wood"), "snapshot fixture begins real hauling")
	var active: Dictionary = simulation.to_dict()
	runner.assert_true(SnapshotSchema.validate(active, content), "travelling action and reservations form a valid snapshot")
	_reject_snapshot(runner, active, content, ["actors", "player", "active", "remaining"], NAN, "non-finite action timer")
	_reject_snapshot(runner, active, content, ["actors", "player", "active", "move_left"], -1, "negative movement timer")
	_reject_snapshot(runner, active, content, ["actors", "player", "active", "started"], 1, "action start in the future")
	_reject_snapshot(runner, active, content, ["actors", "player", "active", "path"], [[1, 1]], "path cannot teleport or miss destination")
	_reject_snapshot(runner, active, content, ["actors", "player", "active", "phase"], "work", "work phase must be at destination")
	_reject_snapshot(runner, active, content, ["actors", "player", "active", "request_id"], "request_404", "orphan action agreement")
	_reject_snapshot(runner, active, content, ["next_id"], 1, "active action ID cannot be reused")
	var limit: int = int(simulation.config["action_timeout"]) + 2
	while not simulation.actors["player"]["active"].is_empty() and int(simulation.tick_index) < limit:
		simulation.step()
	var completed: Dictionary = simulation.to_dict()
	runner.assert_true(SnapshotSchema.validate(completed, content), "completed work and earned receipt form a valid snapshot")
	if not completed["actors"]["player"]["receipts"].is_empty():
		_reject_snapshot(runner, completed, content, ["actors", "player", "receipts", 0, "amount"], 999, "receipt cannot inflate witnessed work credit")
		_reject_snapshot(runner, completed, content, ["actors", "player", "receipts", 0, "event"], "event_404", "receipt needs an existing completion event")
		var wrong_owner: Dictionary = completed.duplicate(true)
		wrong_owner["actors"]["a_he"]["receipts"] = wrong_owner["actors"]["player"]["receipts"].duplicate(true)
		runner.assert_true(not SnapshotSchema.validate(wrong_owner, content), "completion evidence cannot be claimed by another actor")
	_reject_snapshot(runner, completed, content, ["next_id"], 1, "completed inventory action IDs cannot be reused")
	var authorization: Dictionary = completed.duplicate(true)
	authorization["authorizations"]["player:gate"] = {"issuer": "missing", "subject": "player", "scope": "gate"}
	runner.assert_true(not SnapshotSchema.validate(authorization, content), "access authorization needs a real issuer")
	var json_snapshot: Dictionary = JSON.parse_string(JSON.stringify(completed, "", true, true))
	runner.assert_true(SnapshotSchema.validate(json_snapshot, content), "snapshot validation accepts its actual JSON roundtrip")
	_test_resumed_recipe_snapshot(runner, content)
	_test_request_snapshot(runner, content)
	_test_shared_definition_instances(runner, content)


func _test_resumed_recipe_snapshot(runner: Object, content: ReolContentDB) -> void:
	var simulation: Variant = _snapshot_fixture(runner, content)
	if simulation == null:
		return
	simulation.inventory.containers["actor:player"]["wood"] = 1
	simulation.inventory.containers["kitchen"]["wood"] = 0
	runner.assert_true(not simulation.submit_action("player", "cook"), "public recipe cannot silently use personal wood when public supply is missing")
	runner.assert_eq(simulation.inventory.quantity("actor:player", "wood"), 1, "failed public recipe preserves the personal ingredient")
	runner.assert_true(SnapshotSchema.validate(simulation.to_dict(), content), "rejected public recipe leaves a valid snapshot")


func _test_request_snapshot(runner: Object, content: ReolContentDB) -> void:
	var simulation: Variant = _snapshot_fixture(runner, content)
	if simulation == null:
		return
	simulation.config["social_policy"]["bias"] = 1.0
	simulation.config["social_policy"]["uncertainty_band"] = 0.0
	var answer: Dictionary = simulation.request_help("a_he", "shi_tou")
	runner.assert_eq(answer.get("status"), "accepted", "snapshot request fixture has an actual agreement")
	if not answer.has("id") or answer.get("status") != "accepted":
		return
	var travelling: Dictionary = simulation.to_dict()
	runner.assert_true(SnapshotSchema.validate(travelling, content), "accepted request, social decision and active helper agree")
	_reject_snapshot(runner, travelling, content, ["interaction_results", answer["id"], "responder"], "player", "interaction cannot substitute another responder")
	_reject_snapshot(runner, travelling, content, ["actors", "shi_tou", "active", "requester"], "player", "active helper must serve the recorded requester")
	var limit: int = int(simulation.config["action_timeout"]) + 2
	while not simulation.actors["shi_tou"]["active"].is_empty() and int(simulation.tick_index) < limit:
		if simulation.actors["shi_tou"]["active"]["phase"] == "work":
			runner.assert_true(SnapshotSchema.validate(simulation.to_dict(), content), "at-station work and carried inputs form a valid snapshot")
			break
		simulation.step()
	while not simulation.actors["shi_tou"]["active"].is_empty() and int(simulation.tick_index) < limit:
		simulation.step()
	runner.assert_true(SnapshotSchema.validate(simulation.to_dict(), content), "fulfilled request execution remains valid for saving")


func _test_shared_definition_instances(runner: Object, content: ReolContentDB) -> void:
	var profiles: Dictionary = {"player_copy": {"definition_id": "player", "hunger": 25, "energy": 40}}
	var simulation: Variant = _snapshot_fixture(runner, content, profiles)
	if simulation == null:
		return
	runner.assert_eq(simulation.actors["player"]["definition_id"], simulation.actors["player_copy"]["definition_id"], "two actor instances can share one immutable definition")
	var original_hunger: float = simulation.actors["player"]["hunger"]
	simulation.actors["player_copy"]["hunger"] = 10.0
	runner.assert_eq(simulation.actors["player"]["hunger"], original_hunger, "shared definition does not share instance needs")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(simulation.to_dict(), "", true, true))
	runner.assert_true(SnapshotSchema.validate(snapshot, content), "shared-definition instances are valid snapshot references")
	var restored: Variant = _snapshot_fixture(runner, content, profiles)
	if restored == null:
		return
	runner.assert_true(restored.restore(snapshot), "shared-definition actor instances restore successfully")
	runner.assert_eq(restored.actors["player_copy"]["hunger"], 10.0, "copied instance keeps its own saved needs")
	runner.assert_eq(restored.actors["player"]["hunger"], original_hunger, "original instance keeps its own saved needs")


func _reject_snapshot(
	runner: Object, base: Dictionary, content: ReolContentDB, path: Array,
	replacement: Variant, label: String
) -> void:
	var changed: Dictionary = base.duplicate(true)
	var cursor: Variant = changed
	for index: int in range(path.size() - 1):
		cursor = cursor[path[index]]
	cursor[path[path.size() - 1]] = replacement
	runner.assert_true(not SnapshotSchema.validate(changed, content), label)


func _test_weight_order(runner: Object) -> void:
	var script: Script = load("res://scripts/sim/social_memory.gd")
	var social: Variant = script.new()
	social.register_actor("a")
	social.register_actor("b")
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var first_policy: Dictionary = {
		"bias": 0.0, "accept_threshold": 0.5, "uncertainty_band": 0.1,
		"weights": {"energy": 0.3, "busy": -0.7, "duty": 0.25, "reliability": 0.15},
	}
	var reverse_policy: Dictionary = first_policy.duplicate(true)
	reverse_policy["weights"] = {"reliability": 0.15, "duty": 0.25, "busy": -0.7, "energy": 0.3}
	var context: Dictionary = {"duty": 0.5, "busy": 0.0}
	var first: Dictionary = social.evaluate_request("a", "b", "task", context, first_policy, rng, 1)
	var previous_rng: int = rng.state
	var repeated: Dictionary = social.evaluate_request("a", "b", "task", context, reverse_policy, rng, 2)
	runner.assert_eq(repeated["id"], first["id"], "reordered social weights preserve semantic request identity")
	runner.assert_eq(repeated["score"], first["score"], "reordered weights cannot alter accumulation order")
	runner.assert_eq(rng.state, previous_rng, "reordering weights never grants a new roll")
