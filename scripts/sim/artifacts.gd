class_name SimArtifacts
extends RefCounted
## Unique objects, personal experiments and committed material effects.
## Container references own location; observations never expose private charge.

const VERSION: int = 8
const DEFINITIONS_VERSION: int = 1
const MAX_ACTION_MINUTES: int = 150119987579
const VERBS: Array[String] = ["inspect", "take", "place", "study", "heat", "charge", "dry", "examine", "force", "warm"]
const Schema = preload("res://scripts/sim/artifact_schema.gd")
const Understanding = preload("res://scripts/sim/artifact_understanding.gd")
const Drawing = preload("res://scripts/sim/artifact_drawing.gd")
const Space = preload("res://scripts/sim/conflict_space.gd")

var definitions: Dictionary = {}
var objects: Dictionary = {}
var active: Dictionary = {}
var events: Array[Dictionary] = []
var experiences: Dictionary = {}
var next_id: int = 1
var _owner: WeakRef
var _warming_decisions: Dictionary = {}

var world: RefCounted:
	get:
		return _owner.get_ref() if _owner != null else null

var transfers: SimArtifactTransfers:
	get: return world.artifact_transfers if world != null else null


static func valid_definitions(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != DEFINITIONS_VERSION or not data.get("verbs") is Dictionary or not data.get("types") is Dictionary or not _count(data.get("interaction_radius"), 1):
		return false
	if data.verbs.size() != VERBS.size() or data.types.is_empty():
		return false
	if not data.get("autonomy") is Dictionary or not _count(data.autonomy.get("min_qi_reserve")):
		return false
	if not data.get("backgrounds") is Dictionary:
		return false
	for background_id: Variant in data.backgrounds:
		if not SimInventory._nonempty(background_id):
			return false
		var background: Variant = data.backgrounds[background_id]
		if not background is Dictionary or not background.get("practice") in ["stonecraft", "warm_stone_control"] or not SimInventory._nonempty(background.get("line")):
			return false
	for verb: String in VERBS:
		var action: Variant = data.verbs.get(verb)
		if not action is Dictionary or not SimInventory._nonempty(action.get("label")) or not _count(action.get("minutes"), 1) or not _count(action.get("qi")):
			return false
	for id: Variant in data.types:
		var item: Variant = data.types[id]
		if not SimInventory._nonempty(id) or not item is Dictionary:
			return false
		if item.has("capabilities"):
			if not _valid_tool_definition(item):
				return false
			if item.capabilities[0] == "remote_draw":
				for target_id: String in item.drawing.target_definitions:
					if not data.types.has(target_id) or not data.types[target_id] is Dictionary or data.types[target_id].get("capabilities") != ["weapon"]:
						return false
			continue
		for field: String in ["name", "unknown_name", "appearance", "method", "workplace", "credited_action"]:
			if not SimInventory._nonempty(item.get(field)):
				return false
		for field: String in ["max_charge", "opening_charge", "heat_cost", "charge_gain", "backlash_stamina", "warming_charge"]:
			if not _count(item.get(field), 0 if field == "opening_charge" else 1):
				return false
		if item.opening_charge > item.max_charge or item.heat_cost > item.max_charge or item.charge_gain > item.max_charge or item.warming_charge > item.max_charge:
			return false
		for field: String in ["damage_max", "opening_damage", "unsafe_damage", "force_damage", "force_charge_gain", "force_backlash_stamina"]:
			if not _count(item.get(field), 0 if field == "opening_damage" else 1):
				return false
		if item.opening_damage >= item.damage_max or item.unsafe_damage >= item.damage_max or item.force_damage > item.damage_max or item.force_charge_gain > item.max_charge:
			return false
		for field: String in ["inputs", "outputs"]:
			if not item.get(field) is Dictionary or item[field].is_empty() or not SimInventory._positive_items(item[field]):
				return false
		if not item.get("uses") is Dictionary or not item.uses.has("dry") or not _valid_heat_recipe(item) or not _valid_heat_recipe(item.uses.dry) or int(item.uses.dry.heat_cost) > int(item.max_charge):
			return false
	return true


static func _valid_tool_definition(item: Dictionary) -> bool:
	var keys: Array = ["name", "unknown_name", "appearance", "method", "material_cue", "capabilities", "storage_place", "actions"]
	if not item.get("capabilities") is Array or item.capabilities.size() != 1 or item.capabilities[0] not in ["weapon", "remote_draw", "thermal_exchange"]:
		return false
	var remote: bool = item.capabilities[0] == "remote_draw"
	var thermal: bool = item.capabilities[0] == "thermal_exchange"
	if remote:
		keys.append("drawing")
	if thermal:
		keys.append("thermal")
		if item.has("lighting"):
			keys.append("lighting")
	if not Schema._keys(item, keys):
		return false
	for field: String in ["name", "unknown_name", "appearance", "method", "material_cue", "storage_place"]:
		if not SimInventory._nonempty(item[field]):
			return false
	var action_keys: Array = ["inspect", "take", "place", "study", "examine"]
	if remote:
		action_keys.append("use_research")
	if thermal:
		action_keys.append_array(["enable", "disable"])
	if not item.actions is Dictionary or not Schema._keys(item.actions, action_keys):
		return false
	for verb: String in action_keys:
		var action: Variant = item.actions[verb]
		var costs_qi: bool = verb in ["use_research", "enable"]
		if not action is Dictionary or not Schema._keys(action, ["label", "minutes", "qi"]) or not SimInventory._nonempty(action.label) or not _count(action.minutes, 1) or not _count(action.qi, 1 if costs_qi else 0) or (not costs_qi and action.qi != 0):
			return false
		if thermal and int(action.minutes) > MAX_ACTION_MINUTES:
			return false
	if remote:
		var drawing: Variant = item.drawing
		if not drawing is Dictionary or not Schema._keys(drawing, ["duration_ms", "qi", "range_cells", "target_definitions"]) or not _count(drawing.duration_ms, 1) or not _count(drawing.qi, 1) or not _count(drawing.range_cells, 1) or not drawing.target_definitions is Array or drawing.target_definitions != ["wooden_sword"]:
			return false
	if thermal:
		var rule: Variant = item.thermal
		if not rule is Dictionary or not Schema._keys(rule, ["mode", "rate_q_per_ms", "capacity_q", "opening_q"]) or rule.mode not in ["emit", "absorb"]:
			return false
		if not _count(rule.rate_q_per_ms, 1) or not _count(rule.capacity_q, 1) or not _count(rule.opening_q) or int(rule.opening_q) > int(rule.capacity_q):
			return false
		if item.has("lighting") and (rule.mode != "emit" or not SimLightPropagation.valid_definition(item.lighting)):
			return false
	return true


static func type_has_capability(definition: Dictionary, capability: String) -> bool:
	# Legacy thermal objects retain their exact definitions and saved shape.
	# A tool declares its own capabilities; it does not inherit thermal verbs.
	return definition.get("capabilities", ["heat_storage"]).has(capability)


func has_capability(id: String, capability: String) -> bool:
	return objects.has(id) and type_has_capability(definitions.types[objects[id].definition], capability)


func verbs_for(id: String) -> Dictionary:
	if not objects.has(id):
		return {}
	var definition: Dictionary = definitions.types[objects[id].definition]
	var verbs: Dictionary = (definitions.verbs if type_has_capability(definition, "heat_storage") else definition.actions).duplicate(true)
	if type_has_capability(definition, "remote_draw"):
		verbs["draw"] = _draw_terms(definition)
	return verbs


static func _draw_terms(definition: Dictionary) -> Dictionary:
	return {"label": "引取木剑", "minutes": 0, "qi": int(definition.drawing.qi), "duration_ms": int(definition.drawing.duration_ms)}


func shape_studied(actor: String, id: String) -> bool:
	return Understanding.has_personal_event(self, actor, id, "studied")


func learned_use(actor: String, id: String) -> bool:
	return has_capability(id, "remote_draw") and Understanding.has_personal_event(self, actor, id, "use_learned")


func target_in_use(id: String, except_exchange: String = "") -> bool:
	for job: Dictionary in active.values():
		if job.object == id or job.get("draw", {}).get("target") == id:
			return true
	var exchange: Variant = world.get("private_exchange") if world != null else null
	if exchange != null and exchange.target_in_use(id, except_exchange):
		return true
	return false


func can_reserve_exchange_action() -> bool:
	return _can_start_action()


func _can_start_action() -> bool:
	# Every live artifact or exchange action retains one termination slot.
	var outstanding: int = active.size()
	var exchange: Variant = world.get("private_exchange") if world != null else null
	if exchange != null:
		for job: Dictionary in exchange.jobs.values():
			if job.status == "active":
				outstanding += 1
	return next_id <= SimInventory.MAX_COUNT - outstanding - 2


func reserve_exchange_action() -> String:
	if not can_reserve_exchange_action():
		return ""
	return _allocate("action")


func reserve_exchange_release() -> String:
	# Release orders a cancelled/failed exchange without a fictitious transfer.
	if next_id >= SimInventory.MAX_COUNT:
		return ""
	return _allocate("release")


func current_holder_source(object_id: String, actor: String) -> String:
	var field: Variant = world.get("field_opportunities") if world != null else null
	if field == null or field.sites.is_empty() or object_id != field.definitions.site.object or not objects.has(object_id):
		return ""
	var home: String = actor_home(actor)
	var item: Dictionary = objects[object_id]
	if home.is_empty() or item.region != home or item.container != "actor:" + actor:
		return ""
	var custody: Dictionary = Schema.field_custody(self, int(world.elapsed_ms))
	if custody.get("region") != home or custody.get("container") != "actor:" + actor:
		return ""
	return str(custody.get("source", ""))


func can_record_exchange(job: Dictionary) -> bool:
	# Consent and wallets belong to the exchange domain and must already have
	# been preflighted before this synchronous original-object commit.
	if world == null or next_id >= SimInventory.MAX_COUNT:
		return false
	var exchange: Variant = world.get("private_exchange")
	if exchange == null or not job.get("id") is String or not exchange.jobs.has(job.id) or exchange.jobs[job.id] != job:
		return false
	if job.get("status") != "active" or job.get("artifact_event") != "" or job.get("artifact_release") != "" or job.get("finished_ms") != -1:
		return false
	if not SimInventory._nonempty(job.get("seller")) or not SimInventory._nonempty(job.get("buyer")) or job.seller == job.buyer or not SimInventory._nonempty(job.get("object")):
		return false
	if not objects.has(job.object) or (has_capability(str(job.object), "thermal_exchange") and bool(objects[job.object].enabled)):
		return false
	if not job.get("seller_region") is String or not job.get("buyer_region") is String or actor_home(str(job.seller)) != job.seller_region or actor_home(str(job.buyer)) != job.buyer_region or str(job.seller_region).is_empty() or str(job.buyer_region).is_empty():
		return false
	if not Schema._count(job.get("started_ms")) or not Schema._count(job.get("due_ms")) or int(job.due_ms) != int(world.elapsed_ms) or int(job.started_ms) >= int(job.due_ms):
		return false
	if not Schema._allocated(job.get("artifact_action"), "action", next_id, {}) or not Schema.Shape.position_valid(job.get("seller_position")):
		return false
	if not SimInventory._nonempty(job.get("source_event")) or current_holder_source(str(job.object), str(job.seller)) != job.source_event:
		return false
	var seller_point := Vector2(float(job.seller_position[0]), float(job.seller_position[1]))
	if SimRouteTravel.point(world.regions[job.seller_region].actors[job.seller]) != seller_point:
		return false
	for item: Dictionary in active.values():
		if item.id == job.artifact_action:
			return false
	for event: Dictionary in events:
		if event.action == job.artifact_action:
			return false
	for other: Dictionary in exchange.jobs.values():
		if other.id != job.id and other.artifact_action == job.artifact_action:
			return false
	if target_in_use(str(job.object), str(job.id)):
		return false
	if world.soul_vessels != null and world.soul_vessels.target_in_use(str(job.object)):
		return false
	if world.spirit_sources != null and world.spirit_sources.target_in_use(str(job.object)):
		return false
	return true


func record_exchange(job: Dictionary) -> String:
	if not can_record_exchange(job):
		return ""
	var item: Dictionary = objects[job.object]
	var seller_point := Vector2(float(job.seller_position[0]), float(job.seller_position[1]))
	var cell: Vector2i = TileGrid.world_to_cell(seller_point)
	var event_id: String = _allocate("event")
	item.region = str(job.buyer_region)
	item.container = "actor:" + str(job.buyer)
	events.append({"id": event_id, "action": str(job.artifact_action), "actor": str(job.seller),
		"subject": world.embodiment.subject_for_actor(str(job.seller)), "object": str(job.object),
		"kind": "exchanged", "at": int(world.current_time), "line": "双方当面交割，原器物已交到对方手边。",
		"region": str(job.seller_region), "cell": [cell.x, cell.y], "verb": "private_exchange",
		"started_ms": int(job.started_ms), "at_ms": int(world.elapsed_ms), "qi_spent": 0,
		"effect_region": str(job.buyer_region), "recipient": str(job.buyer), "exchange": str(job.id)})
	return event_id


func held_weapon(actor: String) -> String:
	var home: String = actor_home(actor)
	if home.is_empty():
		return ""
	for id: String in world._sorted_keys(objects):
		if objects[id].region == home and objects[id].container == "actor:" + actor and has_capability(id, "weapon"):
			return id
	return ""


static func _valid_heat_recipe(recipe: Variant) -> bool:
	if not recipe is Dictionary or not SimInventory._nonempty(recipe.get("workplace")) or not _count(recipe.get("heat_cost"), 1) or not recipe.get("credited_action") is String or not SimInventory._nonempty(recipe.get("success_line")) or not SimInventory._nonempty(recipe.get("failure_line")):
		return false
	for field: String in ["inputs", "outputs"]:
		if not recipe.get(field) is Dictionary or recipe[field].is_empty() or not SimInventory._positive_items(recipe[field]):
			return false
	return true


static func heat_recipe(definition: Dictionary, verb: String) -> Dictionary:
	if not type_has_capability(definition, "heat_storage"):
		return {}
	return definition if verb == "heat" else definition.uses.get(verb, {})


func initialize(authority: RefCounted, content: Dictionary) -> bool:
	if authority == null or not valid_definitions(content):
		return false
	_owner = weakref(authority)
	definitions = content.duplicate(true)
	return true


func bind_world(authority: RefCounted) -> void:
	_owner = weakref(authority)
	_warming_decisions.clear()


func spawn_opening(scenario: Dictionary) -> bool:
	# Scene bootstrap may occur at a nonzero clock before a saved candidate is
	# committed. Only the explicit scenario assembler calls this operation.
	if not objects.is_empty() or not active.is_empty() or not events.is_empty() or scenario.get("version") != DEFINITIONS_VERSION or not scenario.get("objects") is Array:
		return false
	var candidates: Dictionary = {}
	for row: Variant in scenario.objects:
		if not row is Dictionary or not SimInventory._nonempty(row.get("id")) or candidates.has(row.id) or not definitions.types.has(row.get("definition")) or not valid_location(row.get("region"), row.get("container")):
			return false
		var definition: Dictionary = definitions.types[row.definition]
		candidates[row.id] = {"definition": row.definition, "region": row.region, "container": row.container}
		if type_has_capability(definition, "heat_storage"):
			candidates[row.id]["charge"] = int(definition.opening_charge)
			candidates[row.id]["damage"] = int(definition.opening_damage)
		elif type_has_capability(definition, "thermal_exchange"):
			candidates[row.id]["stored_q"] = int(definition.thermal.opening_q)
			candidates[row.id]["enabled"] = false
	var snapshot: Dictionary = empty_state()
	snapshot.objects = candidates
	if not scenario.get("experiences", {}) is Dictionary:
		return false
	snapshot.experiences = scenario.get("experiences", {}).duplicate(true)
	if not Schema.validate(snapshot, self):
		return false
	objects = candidates
	experiences = snapshot.experiences
	return true


func spawn_field_object(id: String, definition_id: String, region: String, container: String) -> bool:
	# Called by the field authority's explicit scenario/activation commit.
	# The field owns provenance; this domain alone owns the unique real object.
	# A slot is a location reference, never a mirrored inventory container.
	if world == null or not SimInventory._nonempty(id) or objects.has(id) or not definitions.types.has(definition_id) or not container.begins_with("site:") or not valid_location(region, container):
		return false
	var definition: Dictionary = definitions.types[definition_id]
	if type_has_capability(definition, "heat_storage") or type_has_capability(definition, "thermal_exchange"):
		return false
	for item: Dictionary in objects.values():
		if item.region == region and item.container == container:
			return false
	var snapshot: Dictionary = to_dict()
	snapshot.objects[id] = {"definition": definition_id, "region": region, "container": container}
	if not Schema.validate(snapshot, self):
		return false
	objects[id] = snapshot.objects[id]
	world.invalidate_region(region)
	return true


func owns_actor(actor: String) -> bool:
	if active.has(actor):
		return true
	for job: Dictionary in active.values():
		if job.get("method", {}).get("guide") == actor:
			return true
	return false


func previous_autonomy(actor: String) -> bool:
	if active.has(actor):
		return bool(active[actor].previous_autonomous)
	for job: Dictionary in active.values():
		if job.get("method", {}).get("guide") == actor:
			return bool(job.method.guide_was_autonomous)
	return false


func actor_home(actor: String) -> String:
	for region: String in world.regions:
		if world.regions[region].actors.has(actor):
			return region
	return ""


func valid_location(region: Variant, container: Variant) -> bool:
	if not region is String or not container is String or not world.regions.has(region):
		return false
	if container.begins_with("site:"):
		var field: Variant = world.get("field_opportunities")
		return field != null and bool(field.valid_slot(region, container))
	var sim: RefCounted = world.regions[region]
	return sim.inventory.containers.has(container) and (sim.places.has(container) or (container.begins_with("actor:") and sim.actors.has(container.trim_prefix("actor:"))))


func thermal_fixed_location(item: Dictionary) -> bool:
	# An active device belongs to an existing fixed place, never an actor or the
	# field opportunity's dedicated site slot. The original object owns location.
	var region: Variant = item.get("region")
	var container: Variant = item.get("container")
	return valid_location(region, container) and not str(container).begins_with("actor:") and not str(container).begins_with("site:") and world.regions[region].places.has(container)


func object_cell(id: String) -> Vector2i:
	var item: Dictionary = objects[id]
	return _location_cell(str(item.region), str(item.container))


func storage_region(region: String, container: String) -> String:
	if not container.begins_with("site:"):
		return region if valid_location(region, container) else ""
	# A fixed field slot keeps its original registrar even when a visitor has
	# carried the object home. Its physical cell does not belong to that visitor.
	var owner: String = ""
	for candidate: String in world.regions:
		if valid_location(candidate, container):
			if not owner.is_empty():
				return ""
			owner = candidate
	return owner


func storage_near(actor: String, region: String, container: String) -> bool:
	var home: String = actor_home(actor)
	var destination: String = storage_region(region, container)
	if container.begins_with("site:"):
		return not destination.is_empty() and _clear_reach(actor, destination, container, float(definitions.interaction_radius) * TileGrid.TILE_SIZE)
	return not home.is_empty() and not destination.is_empty() and _cell(world.regions[home].actors[actor].cell).distance_to(_location_cell(destination, container)) <= float(definitions.interaction_radius)


func _location_cell(region: String, container: String) -> Vector2i:
	if not valid_location(region, container):
		return Vector2i(-1, -1)
	if container.begins_with("site:"):
		return world.get("field_opportunities").slot_cell(region, container)
	var sim: RefCounted = world.regions[region]
	var raw: Array = sim.actors[container.trim_prefix("actor:")].cell if container.begins_with("actor:") else sim.places[container].cell
	return _cell(raw)


func can_see(actor: String, id: String) -> bool:
	var home: String = actor_home(actor)
	if not home.is_empty() and objects.has(id) and has_capability(id, "remote_draw"):
		var item: Dictionary = objects[id]
		return _clear_reach(actor, str(item.region), str(item.container), float(world.regions[home].config.observation_radius) * TileGrid.TILE_SIZE)
	return not home.is_empty() and bool(world.regions[home].actors[actor].alive) and objects.has(id) and _cell(world.regions[home].actors[actor].cell).distance_to(object_cell(id)) <= float(world.regions[home].config.observation_radius)


func describe(actor: String, id: String) -> Dictionary:
	return Understanding.describe(self, actor, id)


func begin(actor: String, verb: String, id: String) -> Dictionary:
	if transfers != null and transfers.checking:
		return _response(false, "器物变更仍在校验，请稍后再动手。")
	if verb == "draw":
		return _response(false, "须先选择要引取的具体实物。")
	return _begin(actor, verb, id, false)


func begin_draw(actor: String, tool: String, target: String) -> Dictionary:
	if transfers != null and transfers.checking:
		return _response(false, "器物变更仍在校验，请稍后再动手。")
	if world.elapsed_ms != world.target_ms:
		return _response(false, "世界事务仍在接续，请稍后再动手。")
	var home: String = actor_home(actor)
	if home.is_empty() or not objects.has(tool) or not objects.has(target):
		return _response(false, "找不到引物环或选中的实物。")
	world.synchronize_region(home)
	world.synchronize_region(str(objects[tool].region))
	world.synchronize_region(str(objects[target].region))
	var reason: String = Drawing.readiness(self, actor, tool, target)
	if not reason.is_empty():
		return _response(false, reason)
	var person: Dictionary = world.regions[home].actors[actor]
	var terms: Dictionary = verbs_for(tool).draw
	if int(person.qi) < int(terms.qi):
		return _response(false, "你的灵气不足以引取这件实物。")
	if int(world.elapsed_ms) > SimInventory.MAX_COUNT - int(terms.duration_ms) or not _can_start_action():
		return _response(false, "当前时间无法安排这次操作。")
	if world.spirit_sources == null or not world.spirit_sources.ensure_qi_baseline(actor):
		return _response(false, "当前无法核对本人已有的灵气。")
	var item: Dictionary = objects[target]
	var cell: Vector2i = object_cell(target)
	var metadata: Dictionary = {"target": target, "from_region": str(item.region), "from_container": str(item.container),
		"from_cell": [cell.x, cell.y], "caster_position": person.position.duplicate()}
	var action_id: String = _allocate("action")
	person.qi = int(person.qi) - int(terms.qi)
	active[actor] = {"id": action_id, "actor": actor, "object": tool, "verb": "draw", "region": home,
		"started_ms": world.elapsed_ms, "due_ms": int(world.elapsed_ms) + int(terms.duration_ms),
		"qi_spent": int(terms.qi), "previous_autonomous": bool(person.autonomous), "recipient": "", "draw": metadata}
	person.autonomous = false
	person.goal = str(terms.label)
	world.invalidate_region(home)
	return _response(true, "已凝神引取；完成前木剑仍在原处，已投入%d灵气。" % int(terms.qi))


func _begin(actor: String, verb: String, id: String, during_commit: bool, recipient: String = "", method: Dictionary = {}) -> Dictionary:
	var home: String = actor_home(actor)
	if verb == "draw" or home.is_empty() or not objects.has(id) or not verbs_for(id).has(verb):
		return _response(false, "暂时找不到可这样使用的器物。")
	if not during_commit and world.elapsed_ms != world.target_ms:
		return _response(false, "世界事务仍在接续，请稍后再动手。")
	world.synchronize_region(home)
	world.synchronize_region(objects[id].region)
	if not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion"):
		return _response(false, "眼下无法支配身体操作它。")
	var person: Dictionary = world.regions[home].actors[actor]
	if world.health != null and verb in ["heat", "charge", "dry", "force", "warm", "use_research", "enable"] and world.health.blocks_channeling(actor):
		return _response(false, "手臂仍灼涩，引流不顺；先停下催动，休养或求助。")
	if not bool(person.alive) or not person.active.is_empty() or owns_actor(actor) or world.local_action_owns(actor) or (world.services != null and world.services.owns_actor(actor)):
		return _response(false, "先完成或中断手头的事情。")
	if target_in_use(id):
		return _response(false, "有人正在操作它，请稍等。")
	if world.soul_vessels != null and world.soul_vessels.target_in_use(id):
		return _response(false, "有人正借它练习手法，请稍等。")
	if world.spirit_sources != null and world.spirit_sources.target_in_use(id):
		return _response(false, "有人正借它引息，请等对方完成或中断。")
	if not _near(actor, id):
		return _response(false, "先靠近器物，再动手查看。")
	if not method.is_empty():
		if verb != "charge" or not recipient.is_empty():
			return _response(false, "这份草案目前只说明怎样温养储热。")
		var prepared: Dictionary = world.heat_methods.prepare(actor, id, method)
		if not bool(prepared.ok):
			return prepared
	var item: Dictionary = objects[id]
	var invited_check: bool = not recipient.is_empty() and verb in ["examine", "study"] and item.container == "actor:" + recipient
	invited_check = invited_check or (not method.is_empty() and method.mode == "learn" and item.container == "actor:" + str(method.guide))
	if item.container.begins_with("actor:") and not invited_check and (item.container != "actor:" + actor or item.region != home):
		return _response(false, "它还在别人手中，须先取得对方同意。")
	var definition: Dictionary = definitions.types[item.definition]
	if type_has_capability(definition, "thermal_exchange"):
		if verb in ["take", "place"] and bool(item.enabled):
			return _response(false, "先关闭这块石头，再改变它的归处。")
		if verb == "enable":
			if not shape_studied(actor, id):
				return _response(false, "先亲自循纹探查，弄明白怎样启用它。")
			if bool(item.enabled):
				return _response(false, "这块石头已经启用。")
			if not thermal_fixed_location(item):
				return _response(false, "先把石头放在固定地点，再启用它。")
		if verb == "disable" and not bool(item.enabled):
			return _response(false, "这块石头已经关闭。")
	if verb == "use_research":
		var research_reason: String = Drawing.research_readiness(self, actor, id)
		if not research_reason.is_empty():
			return _response(false, research_reason)
	if verb == "warm":
		var readiness: Dictionary = _warming_readiness(actor, id)
		if not bool(readiness.ok):
			return readiness
	var workplace: String = str(heat_recipe(definition, verb).workplace) if verb in ["heat", "dry"] else str(definition.workplace) if type_has_capability(definition, "heat_storage") else str(definition.storage_place)
	if verb in ["heat", "place", "dry"] and not storage_near(actor, str(item.region), workplace):
		var location_label: String = "原野外存放处" if workplace.begins_with("site:") else str(world.regions[item.region].places[workplace].label)
		return _response(false, ("先到%s备好材料，再操作石头。" if type_has_capability(definition, "heat_storage") else "先到%s近旁，再放置这件器物。") % location_label)
	if verb == "place" and item.container != "actor:" + actor:
		return _response(false, "它已经放在灶房了。" if type_has_capability(definition, "heat_storage") else "这件器物并不在你手中。")
	if verb == "take" and item.container == "actor:" + actor:
		return _response(false, "石头已经在你手中。" if type_has_capability(definition, "heat_storage") else "这件器物已经在你手中。")
	var terms: Dictionary = verbs_for(id)[verb] if method.is_empty() else world.heat_methods.terms(str(method.id))
	if int(person.qi) < int(terms.qi):
		return _response(false, "你的灵气不足以继续这次尝试。")
	@warning_ignore("integer_division")
	var maximum_minutes: int = (SimInventory.MAX_COUNT - int(world.elapsed_ms)) / 60000
	if int(terms.minutes) > maximum_minutes:
		return _response(false, "当前时间无法安排这次操作。")
	if not _can_start_action():
		return _response(false, "当前无法安排这次操作。")
	if verb in ["use_research", "enable"] and (world.spirit_sources == null or not world.spirit_sources.ensure_qi_baseline(actor)):
		return _response(false, "当前无法核对本人已有的灵气。")
	var action_id: String = _allocate("action")
	person.qi = int(person.qi) - int(terms.qi)
	active[actor] = {"id": action_id, "actor": actor, "object": id, "verb": verb, "region": home,
		"started_ms": world.elapsed_ms, "due_ms": world.elapsed_ms + int(terms.minutes) * 60000,
		"qi_spent": int(terms.qi), "previous_autonomous": bool(person.autonomous), "recipient": recipient}
	if not method.is_empty():
		var meta: Dictionary = method.duplicate(true)
		meta["guide_was_autonomous"] = false
		meta["guide_qi"] = 0
		if not str(meta.guide).is_empty():
			var guide: Dictionary = world.regions[home].actors[meta.guide]
			meta.guide_was_autonomous = bool(guide.autonomous)
			meta.guide_qi = int(world.heat_methods.definitions.guide_qi)
			guide.qi = int(guide.qi) - int(meta.guide_qi)
			guide.autonomous = false
			guide.goal = "当面指导" + str(terms.label)
		active[actor]["method"] = meta
	person.autonomous = false
	person.goal = str(terms.label)
	world.invalidate_region(home)
	if verb == "warm":
		return _response(true, "%s；需%d分钟，完成后才耗去石内一份余热，中断不会释热。" % [terms.label, int(terms.minutes)])
	return _response(true, "%s；需%d分钟，已投入%d灵气。" % [terms.label, int(terms.minutes), int(terms.qi)])


func request_check(requester: String, responder: String, verb: String, id: String) -> Dictionary:
	var home: String = actor_home(responder)
	if home.is_empty() or requester == responder or actor_home(requester) != home or not verb in ["examine", "study"] or not objects.has(id) or not _near(requester, id) or not _near(responder, id):
		return _response(false, "先和选中的同门一起靠近器物，再谈检查。", "unheard")
	if not world.actor_controls(requester, "communication") or not world.actor_controls(responder, "communication"):
		return _response(false, "眼下无法与对方交流。", "unheard")
	world.synchronize_region(home)
	var sim: VillageSimulation = world.regions[home]
	var person: Dictionary = sim.actors[responder]
	if not person.active.is_empty() or not world.native_action_allowed(responder):
		return _response(false, "对方有自己的事情或眼下不便动手。", "unavailable")
	if not verbs_for(id).has(verb) or int(person.qi) < int(verbs_for(id)[verb].qi):
		return _response(false, "对方表示眼下没有余力进行这次探查。", "incapable")
	var relation: Dictionary = sim.social.relation(responder, requester)
	var context: Dictionary = {"energy": floorf(float(person.energy) / 20.0) / 5.0,
		"busy": 0.0, "distance": 0.0, "duty": 0.0, "offer": 0.0,
		"benevolence": float(sim.config.actor_profiles[responder].get("benevolence", 0.5)),
		"affinity": relation.get("affinity", 0.0), "reliability": relation.get("reliability", 0.5),
		"terms": {"object": id, "verb": verb}}
	var decision: Dictionary = sim.social.evaluate_request(requester, responder, "artifact_check", context, sim.config.social_policy, sim._rng, world.current_time)
	world.invalidate_region(home)
	if decision.get("status") != "accepted":
		return _response(false, "对方权衡后暂未答应；他也有自己的安排。", "refused")
	return _begin(responder, verb, id, false, requester)


func cancel(actor: String) -> bool:
	if transfers != null and transfers.checking:
		return false
	if not active.has(actor):
		for job: Dictionary in active.values():
			if job.get("method", {}).get("guide") == actor:
				_finish_record(job, "cancelled", "指导中断，已投入的灵气没有退回，学员尚未练成这一版。")
				return true
		return false
	var line: String = "释热中断，石中余热没有耗去，身边也没有留下暖流。" if active[actor].verb == "warm" else "操作中断，已投入的灵气没有退回。"
	_finish_record(active[actor], "cancelled", line)
	return true


func next_boundary_ms() -> int:
	var boundary: int = SimInventory.MAX_COUNT
	for actor: String in active:
		if not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or not _method_connected(active[actor]) or not _continuation_reason(active[actor]).is_empty():
			return world.elapsed_ms + 1
		boundary = mini(boundary, int(active[actor].due_ms))
	return boundary


func settle_at_ms(tick: int) -> void:
	var actors: Array = active.keys()
	actors.sort()
	for actor: String in actors:
		# A previous completion observer may cancel another pending action.
		if not active.has(actor):
			continue
		world.synchronize_region(active[actor].region)
		if not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or not _method_connected(active[actor]) or not _continuation_reason(active[actor]).is_empty():
			cancel(actor)
		elif int(active[actor].due_ms) <= tick:
			_complete(active[actor])


func _complete(job: Dictionary) -> void:
	var item: Dictionary = objects[job.object]
	var definition: Dictionary = definitions.types[item.definition]
	var sim: RefCounted = world.regions[job.region]
	var person: Dictionary = sim.actors[job.actor]
	if job.verb == "draw":
		var reason: String = _continuation_reason(job)
		if not reason.is_empty():
			_finish_record(job, "failed", reason)
			return
		_move_and_finish(job, str(job.draw.target), str(job.region), "actor:" + str(job.actor), "drawn", "木剑已从原处引到本人手边；原物没有复制。")
		return
	if job.verb == "use_research":
		var reason: String = _continuation_reason(job)
		if not reason.is_empty():
			_finish_record(job, "failed", reason)
			return
	if not _near(job.actor, job.object):
		_finish_record(job, "failed", "已离开器物，操作没有完成。")
		return
	if not type_has_capability(definition, "heat_storage"):
		_complete_tool(job, item, definition)
		return
	match str(job.verb):
		"inspect": _finish_record(job, "observed", ("石面仍有余温" if int(item.charge) > 0 else "石面已冷") + "，细纹似乎通向石芯；用法还需摸索。")
		"examine": _finish_record(job, "examined", Understanding.material_line(self, str(job.actor), item))
		"take":
			_move_and_finish(job, str(job.object), str(job.region), "actor:" + str(job.actor), "taken", "石头已收在手边；拿到它还不等于懂得使用。")
		"place":
			_move_and_finish(job, str(job.object), str(item.region), str(definition.workplace), "placed", "石头已放回灶旁。")
		"study": _finish_record(job, "studied", "循纹探查后，你摸清了导热与温养的手法。")
		"warm": _finish_warming(job)
		"heat", "charge", "dry", "force":
			if job.has("method"):
				if int(item.damage) >= int(definition.damage_max):
					_finish_record(job, "failed", "石芯已断，依照草案也积不起余热。")
				else:
					world.heat_methods.apply_charge(job)
				return
			if not bool(describe(job.actor, job.object).method):
				person.stamina = maxi(0, int(person.stamina) - int(definition.backlash_stamina))
				_finish_record(job, "backlash", "灵气没有循纹而行，回卷震得手臂发麻，体力受损。")
				return
			if int(item.damage) >= int(definition.damage_max):
				_finish_record(job, "failed", "石芯已崩断，灵气没能沿断纹积成余热。")
				return
			if job.verb == "force":
				if int(item.damage) >= int(definition.unsafe_damage):
					item.damage = int(definition.damage_max)
					item.charge = 0
					person.stamina = maxi(0, int(person.stamina) - int(definition.force_backlash_stamina))
					_finish_record(job, "fractured", "灵气撑开了石芯接缝，余热散尽；回卷震得手臂发麻。")
				else:
					item.damage = mini(int(definition.damage_max), int(item.damage) + int(definition.force_damage))
					item.charge = mini(int(definition.max_charge), int(item.charge) + int(definition.force_charge_gain))
					_finish_record(job, "overcharged", "石芯猛然发热，接缝发出一声轻响；以后能否承受还需检查。")
				return
			if job.verb == "charge":
				item.charge = mini(int(definition.max_charge), int(item.charge) + int(definition.charge_gain))
				_finish_record(job, "charged", "石芯重新温热起来；储能有容限，投入的灵气不会凭空退回。")
				return
			_finish_heat(job, heat_recipe(definition, str(job.verb)))


func _move_and_finish(job: Dictionary, id: String, region: String, container: String, kind: String, line: String) -> void:
	var item: Dictionary = objects[id]
	if has_capability(id, "thermal_exchange") and bool(item.enabled):
		_finish_record(job, "failed", "石头仍在作用，先关闭后才能搬动；原物留在原处。")
		return
	var change: Dictionary = SimArtifactTransfers.describe(id, item, region, container, int(world.elapsed_ms), str(job.id), str(job.verb))
	if not transfers.allows(change):
		# The existing action paid its time/qi; only the proposed move is refused.
		_finish_record(job, "failed", "器物归处变更未获准，原物仍留在原处。")
		return
	item.region = region
	item.container = container
	world.invalidate_region(str(change.from.region))
	_finish_record(job, kind, line)
	transfers.publish(change)


func _complete_tool(job: Dictionary, item: Dictionary, definition: Dictionary) -> void:
	match str(job.verb):
		"inspect": _finish_record(job, "observed", str(definition.appearance))
		"examine": _finish_record(job, "examined", Understanding.material_line(self, str(job.actor), item))
		"take":
			_move_and_finish(job, str(job.object), str(job.region), "actor:" + str(job.actor), "taken", "已取在自己手边；持有器物不等于学会相应技法。")
		"place":
			if str(definition.storage_place).begins_with("site:") and not storage_near(str(job.actor), str(item.region), str(definition.storage_place)):
				_finish_record(job, "failed", "已离开原野外存放处，器物仍由本人保管。")
				return
			var destination: String = storage_region(str(item.region), str(definition.storage_place))
			if destination.is_empty():
				_finish_record(job, "failed", "原存放处眼下不再有效，器物仍由本人保管。")
				return
			_move_and_finish(job, str(job.object), destination, str(definition.storage_place), "placed", "已放在约定的存放处，随身不再保管它。")
		"study": _finish_record(job, "studied", str(definition.method))
		"use_research": _finish_record(job, "use_learned", "本人持环循纹试探后，学会将同高无遮挡、短距内的松置木剑引到手边。")
		"enable", "disable": _finish_thermal_switch(job, item)


func _finish_thermal_switch(job: Dictionary, item: Dictionary) -> void:
	var enabled: bool = job.verb == "enable"
	if bool(item.enabled) == enabled or not thermal_fixed_location(item):
		_finish_record(job, "failed", "石头的状态或固定位置已经改变，这次没有切换。")
		return
	if enabled and not shape_studied(str(job.actor), str(job.object)):
		_finish_record(job, "failed", "本人还不懂这块石头的用法，这次没有启用。")
		return
	var heat: Variant = world.get("local_heat")
	if heat == null or not heat.has_method("can_switch_device") or not heat.has_method("switch_device") or not bool(heat.call("can_switch_device", str(job.object), enabled)):
		_finish_record(job, "failed", "这块石头眼下无法切换；原来的状态没有改变。")
		return
	var point: Vector2i = object_cell(str(job.object))
	var change: Dictionary = {"action": str(job.id), "actor": str(job.actor), "object": str(job.object),
		"at_ms": int(world.elapsed_ms), "region": str(item.region), "container": str(item.container),
		"cell": [point.x, point.y], "enabled": enabled}
	var previous: bool = bool(item.enabled)
	item.enabled = enabled
	if not bool(heat.call("switch_device", change)):
		item.enabled = previous
		_finish_record(job, "failed", "切换未能提交；石头仍保持原来的状态。")
		return
	# No yield or observer runs between the thermal commit and the original
	# artifact event. The thermal authority owns no copy of this device's stock.
	_finish_record(job, "enabled" if enabled else "disabled", "石头已启用。" if enabled else "石头已关闭，周围的温度不会因此瞬间重设。")
	world.invalidate_region(str(item.region))


func _finish_heat(job: Dictionary, recipe: Dictionary) -> void:
	var item: Dictionary = objects[job.object]
	var local: RefCounted = world.regions[item.region]
	var person: Dictionary = world.regions[job.region].actors[job.actor]
	world.synchronize_region(item.region)
	if _cell(person.cell).distance_to(_cell(local.places[recipe.workplace].cell)) > float(definitions.interaction_radius):
		_finish_record(job, "failed", "已离开备料处，热工艺没有接续。")
		return
	if int(item.charge) < int(recipe.heat_cost):
		_finish_record(job, "depleted", "石芯几乎没有余热，无法继续供热。")
		return
	var credit: int = 0
	var action: Dictionary = local.config.actions.get(recipe.credited_action, {})
	for output: String in recipe.outputs:
		if not action.is_empty() and local.inventory.quantity(recipe.workplace, output) < int(action.stock_below):
			credit = int(action.get("contribution", 0))
	if not local.inventory.transform(str(job.id) + ":heat", recipe.workplace, recipe.inputs, recipe.outputs):
		_finish_record(job, "failed", str(recipe.failure_line))
		return
	item.charge = int(item.charge) - int(recipe.heat_cost)
	if not action.is_empty() and local.actors.has(job.actor):
		local.action_finished(job.actor, {"requester": "", "request_id": "", "action": recipe.credited_action, "credit_earned": credit}, true, "artifact_heat")
	if local.actors.has(job.actor):
		local.observe_current_surroundings(job.actor)
	world.invalidate_region(item.region)
	_finish_record(job, "heated", str(recipe.success_line) + ("凭据需另去登记。" if credit > 0 and local.actors.has(job.actor) else ""))


func _warming_readiness(actor: String, id: String) -> Dictionary:
	var home: String = actor_home(actor)
	if home.is_empty() or not objects.has(id) or not has_capability(id, "heat_storage") or world.local_heat == null:
		return _response(false, "眼下没有可以在手边释热的器物。")
	var item: Dictionary = objects[id]
	if item.region != home or item.container != "actor:" + actor:
		return _response(false, "先把温火石取在自己手中，才能控制暖流落在身边。")
	if not bool(describe(actor, id).get("method", false)):
		return _response(false, "还没有摸清导热手法，不能稳妥地把余热释在身边。")
	if world.health != null and world.health.blocks_channeling(actor):
		return _response(false, "手臂仍灼涩，引流不顺；先休养或求助。")
	var definition: Dictionary = definitions.types[item.definition]
	if int(item.damage) >= int(definition.damage_max):
		return _response(false, "石芯已经崩断，导不出可控的暖流。")
	if int(item.charge) < int(definition.warming_charge):
		return _response(false, "循纹试过，石中已没有足够余热；要先温养再试。")
	return _response(true, "")


func _finish_warming(job: Dictionary) -> void:
	var readiness: Dictionary = _warming_readiness(str(job.actor), str(job.object))
	if not bool(readiness.ok):
		_finish_record(job, "failed", str(readiness.line))
		return
	var item: Dictionary = objects[job.object]
	var cell: Vector2i = object_cell(str(job.object))
	var amount: int = int(world.local_heat.definitions.pulse_energy)
	if not world.local_heat.can_deposit(cell, amount):
		_finish_record(job, "failed", "此处暂时无法再接纳暖流，石中余热没有耗去。")
		return
	var source: Dictionary = {"action": job.id, "actor": job.actor, "object": job.object,
		"at_ms": world.elapsed_ms, "cell": [cell.x, cell.y], "amount": amount}
	# The thermal authority settles the previous interval before this call.
	# There is no yield or callback between the accepted deposit and the debit
	# plus source event. A rejected deposit never spends the original charge.
	if not world.local_heat.deposit(source):
		_finish_record(job, "failed", "暖流没有接续，石中余热仍保留着。")
		return
	item.charge = int(item.charge) - int(definitions.types[item.definition].warming_charge)
	_finish_record(job, "warmed", "石中一份余热已释在此处，近旁暖了些；余热会渐渐散去，不会跟着离开的人。", amount)


func _warming_choice(actor: String, at_ms: int) -> String:
	var home: String = actor_home(actor)
	if home.is_empty() or world.environment == null:
		return ""
	var conditions: Dictionary = world.environment.local_conditions(actor, at_ms)
	if conditions.is_empty():
		return ""
	# The lowest admissible temperature can offer a future decision. The
	# regional clock rechecks actual conditions before starting a warming job.
	var human: Dictionary = world.environment.definitions.human
	var warmth: int = clampi(world.environment.insulation_for(actor), 0, int(human.max_insulation_tenths))
	if int(conditions.temperature_min_tenths) >= int(human.comfort_min_tenths) - warmth:
		return ""
	# Only the holder's own controlled object is considered. This never seeks
	# another person's private store or creates an opening stone for a need.
	for id: String in world._sorted_keys(objects):
		if objects[id].region == home and objects[id].container == "actor:" + actor and bool(_warming_readiness(actor, id).ok):
			return id
	return ""


func wants_warming_decision(actor: String, at_ms: int) -> bool:
	var home: String = actor_home(actor)
	if home.is_empty() or not bool(world.regions[home].actors[actor].autonomous) or not world.standing_work.duty_for(actor, at_ms).is_empty():
		return false
	var contract: String = world.budgeted_labor.latest_for(actor)
	if not contract.is_empty() and world.budgeted_labor.contracts[contract].status in ["working", "paused"]:
		return false
	return not _warming_choice(actor, at_ms).is_empty()


func note_warming_decision(actor: String, at_ms: int) -> void:
	# Only the regional initiative router calls this after choosing warmth
	# over the later livelihood option. Pure wishes/previews never write it.
	_warming_decisions[actor] = at_ms


func consider_warming() -> void:
	var handed_off: Dictionary = _warming_decisions.duplicate()
	_warming_decisions.clear()
	for actor: String in world._actor_ids(world.regions):
		if int(handed_off.get(actor, -1)) != world.elapsed_ms or not world.autonomous_decision(actor):
			continue
		var started: bool = false
		if wants_warming_decision(actor, world.elapsed_ms):
			var id: String = _warming_choice(actor, world.elapsed_ms)
			if not id.is_empty():
				started = bool(_begin(actor, "warm", id, true).ok)
		if not started:
			# A same-timestamp heat source may make the offered action useless.
			# Resume ordinary needs/duties instead of wasting a whole decision
			# interval. The ownership guard above preserves health/clothing jobs.
			var home: String = actor_home(actor)
			world.regions[home]._choose_routine(actor, false)
			world.invalidate_region(home)


func consider_methods() -> void:
	if objects.is_empty():
		return
	# Called only after the regional clock commits. Never mutate an authority
	# from inside a village that is still advancing ahead of that authority.
	var region_ids: Array = world.regions.keys()
	region_ids.sort()
	for region: String in region_ids:
		var sim: VillageSimulation = world.regions[region]
		var ids: Array = sim.actors.keys()
		ids.sort()
		for actor: String in ids:
			var person: Dictionary = sim.actors[actor]
			if not bool(person.autonomous) or not person.active.is_empty() or int(person.retry_ms) - int(sim.config.decision_interval) * 60000 != world.elapsed_ms or not world.native_action_allowed(actor):
				continue
			if float(person.hunger) <= float(sim.config.needs.eat_below) or float(person.energy) <= float(sim.config.needs.rest_below):
				continue
			var duty: String = str(sim.config.actor_profiles[actor].get("duty", ""))
			if duty.is_empty() or sim.config.actions[duty].kind != "recipe" or sim.config.actions[duty].target != "kitchen" or not sim.needs_action(actor, duty):
				continue
			var stock: Dictionary = sim.stock_understanding(actor, "kitchen", "wood")
			if not bool(stock.known) or float(stock.amount) > 0:
				continue
			var objects_seen: Array = objects.keys()
			objects_seen.sort()
			for id: String in objects_seen:
				var definition: Dictionary = definitions.types[objects[id].definition]
				if not type_has_capability(definition, "heat_storage"):
					continue
				var view: Dictionary = describe(actor, id)
				if not bool(view.get("near", false)) or (bool(view.get("method", false)) and definition.credited_action != duty):
					continue
				var verb: String = "heat" if bool(view.method) else "inspect"
				if bool(view.method):
					for index: int in range(events.size() - 1, -1, -1):
						if events[index].actor == actor and events[index].object == id:
							if events[index].kind == "depleted":
								verb = "charge"
							break
				if not bool(view.method):
					for event: Dictionary in events:
						if event.actor == actor and event.object == id and event.kind == "observed":
							verb = "study"
				var learned: String = world.heat_methods.preferred(actor) if verb == "charge" else ""
				var method: Dictionary = {} if learned.is_empty() else {"id": learned, "mode": "use", "guide": "", "consent": ""}
				if learned.is_empty() and verb == "charge":
					learned = world.heat_methods.read_candidate(actor)
					if not learned.is_empty():
						method = {"id": learned, "mode": "record", "guide": "", "consent": ""}
				var terms: Dictionary = definitions.verbs[verb] if method.is_empty() else world.heat_methods.terms(learned)
				if int(person.qi) < int(terms.qi) + int(definitions.autonomy.min_qi_reserve):
					continue
				if bool(_begin(actor, verb, id, true, "", method).ok):
					break


func _finish_record(job: Dictionary, kind: String, line: String, heat_amount: int = 0) -> Dictionary:
	var person: Dictionary = world.regions[job.region].actors[job.actor]
	person.autonomous = bool(job.previous_autonomous)
	# Other characters can see a finished activity, not its private conclusion.
	# The operator and a present recipient read the actual note through describe.
	person.goal = "刚结束" + str(verbs_for(str(job.object))[job.verb].label)
	person.retry_ms = world.elapsed_ms + int(world.regions[job.region].config.decision_interval) * 60000
	if job.has("method") and not str(job.method.guide).is_empty():
		var guide: Dictionary = world.regions[job.region].actors[job.method.guide]
		guide.autonomous = bool(job.method.guide_was_autonomous)
		guide.goal = "刚结束当面指导"
		guide.retry_ms = person.retry_ms
	var position_value: Vector2i = object_cell(job.object)
	var recipient: String = str(job.recipient)
	if not recipient.is_empty() and (not _near(recipient, job.object) or not world.actor_controls(recipient, "communication") or not world.actor_controls(job.actor, "communication")):
		recipient = ""
	var record: Dictionary = {"id": _allocate("event"), "action": job.id, "actor": job.actor,
		"subject": world.embodiment.subject_for_actor(job.actor), "object": job.object,
		"kind": kind, "at": world.current_time, "line": line, "region": job.region,
		"verb": job.verb, "started_ms": job.started_ms, "at_ms": world.elapsed_ms, "qi_spent": job.qi_spent, "effect_region": objects[job.object].region,
		"cell": [position_value.x, position_value.y], "recipient": recipient}
	if kind == "warmed":
		# Publish the exact accepted transfer before any event observer sees it.
		# Failed/cancelled actions never claim a thermal source amount.
		record["heat_amount"] = heat_amount
	if kind in ["enabled", "disabled"]:
		# A cell alone cannot distinguish separate places occupying the same tile.
		record["device_container"] = str(objects[job.object].container)
	if job.has("method"):
		record["method"] = job.method.duplicate(true)
	if job.has("draw"):
		record["draw"] = job.draw.duplicate(true)
	events.append(record)
	if world.health != null:
		world.health.record_effect(record)
	active.erase(job.actor)
	world.invalidate_region(job.region)
	return record


func status(actor: String, object_id: String = "") -> Dictionary:
	if active.has(actor):
		var job: Dictionary = active[actor]
		if job.verb == "draw":
			var seconds: int = ceili(float(int(job.due_ms) - int(world.elapsed_ms)) / 1000.0)
			return {"busy": true, "line": str(job_terms(job).label), "remaining": 0, "seconds": seconds}
		return {"busy": true, "line": str(job_terms(job).label), "remaining": ceili(float(int(job.due_ms) - int(world.elapsed_ms)) / 60000.0)}
	for job: Dictionary in active.values():
		if job.get("method", {}).get("guide") == actor:
			return {"busy": true, "line": "当面指导" + str(job_terms(job).label), "remaining": ceili(float(int(job.due_ms) - int(world.elapsed_ms)) / 60000.0)}
		if job.recipient == actor and (object_id.is_empty() or job.object == object_id) and _near(actor, job.object):
			return {"busy": false, "checking": true, "line": "同门正在" + str(verbs_for(str(job.object))[job.verb].label), "remaining": ceili(float(int(job.due_ms) - int(world.elapsed_ms)) / 60000.0)}
	for index in range(events.size() - 1, -1, -1):
		var event: Dictionary = events[index]
		if not object_id.is_empty() and event.object != object_id:
			continue
		if event.get("method", {}).get("guide") == actor:
			return {"busy": false, "event": str(event.id), "line": world.regions[event.region]._name(str(event.actor)) + "的练习记录：" + str(event.line)}
		if event.actor == actor:
			return {"busy": false, "event": str(event.id), "line": str(event.line)}
		if event.recipient == actor and event.kind in ["examined", "studied"]:
			return {"busy": false, "event": str(event.id), "line": world.regions[event.region]._name(str(event.actor)) + "：" + str(event.line)}
	return {"busy": false, "line": "灶旁的暗红石头值得仔细看看。"}


func job_terms(job: Dictionary, candidate_objects: Dictionary = {}) -> Dictionary:
	if job.has("method"):
		return world.heat_methods.terms(str(job.method.id))
	# Candidate validation runs before its object state is committed locally.
	var source: Dictionary = objects if candidate_objects.is_empty() else candidate_objects
	if not source.has(job.object):
		return {}
	var definition: Dictionary = definitions.types[source[job.object].definition]
	if job.verb == "draw" and type_has_capability(definition, "remote_draw"):
		return _draw_terms(definition)
	var verbs: Dictionary = definitions.verbs if type_has_capability(definition, "heat_storage") else definition.actions
	return verbs.get(str(job.verb), {})


func _continuation_reason(job: Dictionary) -> String:
	if job.verb == "use_research":
		return Drawing.research_readiness(self, str(job.actor), str(job.object), true)
	if job.verb == "draw":
		return Drawing.readiness(self, str(job.actor), str(job.object), str(job.draw.target), {}, true, job.draw)
	return ""


func _method_connected(job: Dictionary) -> bool:
	if not job.has("method") or str(job.method.guide).is_empty():
		return true
	for actor: String in [str(job.actor), str(job.method.guide)]:
		if not bool(world.regions[job.region].actors[actor].alive) or not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or not world.actor_controls(actor, "communication") or not _near(actor, str(job.object)):
			return false
	return true


func to_dict() -> Dictionary:
	return {"version": VERSION, "objects": objects.duplicate(true), "active": active.duplicate(true), "events": events.duplicate(true), "experiences": experiences.duplicate(true), "next_id": next_id}


static func empty_state() -> Dictionary:
	return {"version": VERSION, "objects": {}, "active": {}, "events": [], "experiences": {}, "next_id": 1}


func restore(data: Dictionary) -> bool:
	if not Schema.validate(data, self):
		return false
	_warming_decisions.clear()
	objects = data.objects.duplicate(true)
	active = data.active.duplicate(true)
	events.assign(data.events.duplicate(true))
	experiences = data.experiences.duplicate(true)
	for item: Dictionary in objects.values():
		if type_has_capability(definitions.types[item.definition], "heat_storage"):
			item.charge = int(item.charge)
			item.damage = int(item.damage)
		elif type_has_capability(definitions.types[item.definition], "thermal_exchange"):
			item.stored_q = int(item.stored_q)
	for job: Dictionary in active.values():
		for field: String in ["started_ms", "due_ms", "qi_spent"]:
			job[field] = int(job[field])
		if job.has("draw"):
			job.draw.from_cell = [int(job.draw.from_cell[0]), int(job.draw.from_cell[1])]
	for event: Dictionary in events:
		for field: String in ["at", "at_ms", "started_ms", "qi_spent"]:
			event[field] = int(event[field])
		if event.kind == "warmed":
			event.heat_amount = int(event.heat_amount)
		event.cell = [int(event.cell[0]), int(event.cell[1])]
		if event.has("draw"):
			event.draw.from_cell = [int(event.draw.from_cell[0]), int(event.draw.from_cell[1])]
	next_id = int(data.next_id)
	return true


func _near(actor: String, id: String) -> bool:
	var home: String = actor_home(actor)
	if not home.is_empty() and objects.has(id) and has_capability(id, "remote_draw"):
		var item: Dictionary = objects[id]
		return _clear_reach(actor, str(item.region), str(item.container), float(definitions.interaction_radius) * TileGrid.TILE_SIZE)
	return not home.is_empty() and objects.has(id) and _cell(world.regions[home].actors[actor].cell).distance_to(object_cell(id)) <= float(definitions.interaction_radius)


func _clear_reach(actor: String, region: String, container: String, radius: float) -> bool:
	var home: String = actor_home(actor)
	if home.is_empty() or not valid_location(region, container) or not bool(world.regions[home].actors[actor].alive):
		return false
	var from: Vector2 = SimRouteTravel.point(world.regions[home].actors[actor])
	var target: Vector2 = SimRouteTravel.point(world.regions[region].actors[container.trim_prefix("actor:")]) if container.begins_with("actor:") else TileGrid.cell_to_world(_location_cell(region, container))
	var level: int = Space.level(world, from)
	return from.distance_to(target) <= radius and level == Space.level(world, target) and Space.clear_segment(world, from, target, level)


func _allocate(kind: String) -> String:
	var id: String = "artifact:%s:%d" % [kind, next_id]
	next_id += 1
	return id


static func _response(ok: bool, line: String, code: String = "") -> Dictionary:
	var response: Dictionary = {"ok": ok, "line": line}
	if not code.is_empty():
		response.code = code
	return response


static func _cell(raw: Array) -> Vector2i:
	return Vector2i(int(raw[0]), int(raw[1]))


static func _count(value: Variant, minimum: int = 0) -> bool:
	return SimInventory._valid_count(value) and value >= minimum
