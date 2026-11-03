extends RefCounted
## Composition validation uses independently restored regions and embodiment.

const Methods = preload("res://scripts/sim/heat_method_schema.gd")
const Shape = preload("res://scripts/sim/avian_schema.gd")

const KINDS: Array[String] = ["observed", "taken", "placed", "studied", "backlash", "charged", "heated", "depleted", "failed", "cancelled", "examined", "fractured", "overcharged", "warmed", "use_learned", "drawn"]


static func validate(data: Dictionary, domain: RefCounted) -> bool:
	if not _keys(data, ["version", "objects", "active", "events", "experiences", "next_id"]) or data.version != 5 or not data.objects is Dictionary or not data.active is Dictionary or not data.events is Array or not data.experiences is Dictionary or not _count(data.next_id, 1):
		return false
	var world: RefCounted = domain.world
	for subject: Variant in data.experiences:
		if not subject is String or not world.embodiment._subjects.has(subject) or not SimEmbodiment._unique_texts(data.experiences[subject]):
			return false
		for background: String in data.experiences[subject]:
			if not domain.definitions.backgrounds.has(background):
				return false
	for id: Variant in data.objects:
		var item: Variant = data.objects[id]
		if not SimInventory._nonempty(id) or not item is Dictionary or not domain.definitions.types.has(item.get("definition")) or not domain.valid_location(item.get("region"), item.get("container")):
			return false
		var definition: Dictionary = domain.definitions.types[item.definition]
		if not SimArtifacts.type_has_capability(definition, "heat_storage"):
			if not _keys(item, ["definition", "region", "container"]) or domain.storage_region(str(item.region), str(definition.storage_place)).is_empty():
				return false
			continue
		if not _keys(item, ["definition", "region", "container", "charge", "damage"]):
			return false
		if not _count(item.charge) or int(item.charge) > int(definition.max_charge) or not world.regions[item.region].places.has(definition.workplace):
			return false
		if not _count(item.damage) or int(item.damage) > int(definition.damage_max) or (int(item.damage) == int(definition.damage_max) and int(item.charge) != 0):
			return false
		var action: Variant = world.regions[item.region].config.actions.get(definition.credited_action)
		if not action is Dictionary or action.get("kind") != "recipe" or action.target != definition.workplace:
			return false
		for recipe: Dictionary in definition.uses.values():
			if not world.regions[item.region].places.has(recipe.workplace):
				return false
	var allocated: Dictionary = {}
	var actions: Dictionary = {}
	var object_users: Dictionary = {}
	var actor_users: Dictionary = {}
	for actor: Variant in data.active:
		var job: Variant = data.active[actor]
		if not actor is String or not job is Dictionary:
			return false
		var job_keys: Array = ["id", "actor", "object", "verb", "region", "started_ms", "due_ms", "qi_spent", "previous_autonomous", "recipient"]
		if job.has("method"):
			job_keys.append("method")
		if job.has("draw"):
			job_keys.append("draw")
		if not _keys(job, job_keys) or actor_users.has(actor):
			return false
		if job.actor != actor or domain.actor_home(actor) != job.region or not _supported(data.objects, str(job.object), str(job.verb), domain) or not _allocated(job.id, "action", int(data.next_id), allocated):
			return false
		if not _valid_recipient(job.recipient, actor, job.verb, domain):
			return false
		if not _new_action_valid(job, data, domain):
			return false
		if not _count(job.started_ms) or (job.has("method") and (not SimArtifacts.type_has_capability(domain.definitions.types[data.objects[job.object].definition], "heat_storage") or not Methods.metadata_valid(job.method, job, domain, data.events, data.objects))):
			return false
		var terms: Dictionary = domain.job_terms(job, data.objects)
		if terms.is_empty() or not _count(job.started_ms) or job.started_ms > world.elapsed_ms or not _count(job.due_ms, int(world.elapsed_ms) + 1) or int(job.due_ms) - int(job.started_ms) != _duration(terms) or not _count(job.qi_spent) or job.qi_spent != terms.qi or not job.previous_autonomous is bool:
			return false
		var person: Dictionary = world.regions[job.region].actors[actor]
		if not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or not person.active.is_empty() or bool(person.autonomous) or object_users.has(job.object) or (world.services != null and world.services.owns_actor(actor)):
			return false
		var item: Dictionary = data.objects[job.object]
		var definition: Dictionary = domain.definitions.types[item.definition]
		if job.verb == "place" and not SimArtifacts.type_has_capability(definition, "heat_storage") and str(definition.storage_place).begins_with("site:") and not domain.storage_near(actor, str(item.region), str(definition.storage_place)):
			return false
		if job.verb == "warm" and (item.region != job.region or item.container != "actor:" + actor or int(item.charge) < int(domain.definitions.types[item.definition].warming_charge)):
			return false
		var invited_check: bool = not str(job.recipient).is_empty() and job.verb in ["examine", "study"] and item.container == "actor:" + str(job.recipient)
		actor_users[actor] = true
		if job.has("method") and not str(job.method.guide).is_empty():
			var guide_id: String = str(job.method.guide)
			var guide: Dictionary = world.regions[job.region].actors[guide_id]
			if actor_users.has(guide_id) or not guide.active.is_empty() or bool(guide.autonomous) or not bool(guide.alive) or (world.services != null and world.services.owns_actor(guide_id)):
				return false
			for channel: String in ["action", "motion", "communication"]:
				if not world.actor_controls(guide_id, channel) or not world.actor_controls(actor, channel):
					return false
			actor_users[guide_id] = true
			invited_check = item.container == "actor:" + guide_id
		if item.container.begins_with("actor:") and not invited_check and (item.region != job.region or item.container != "actor:" + actor):
			return false
		object_users[job.object] = actor
		if job.has("draw"):
			if object_users.has(job.draw.target):
				return false
			object_users[job.draw.target] = actor
		actions[job.id] = true
	var last_at: int = 0
	for event: Variant in data.events:
		if not event is Dictionary:
			return false
		var event_keys: Array = ["id", "action", "actor", "subject", "object", "kind", "at", "line", "region", "cell", "verb", "started_ms", "at_ms", "qi_spent", "effect_region", "recipient"]
		if event.has("method"):
			event_keys.append("method")
		if event.has("draw"):
			event_keys.append("draw")
		if not _keys(event, event_keys):
			return false
		if not _allocated(event.id, "event", int(data.next_id), allocated) or not _allocated(event.action, "action", int(data.next_id), allocated) or actions.has(event.action):
			return false
		if not event.actor is String or domain.actor_home(event.actor) != event.region or world.embodiment.subject_for_actor(event.actor) != event.subject or not data.objects.has(event.object) or not KINDS.has(event.kind) or not event.line is String:
			return false
		if not event.verb is String or not _valid_recipient(event.recipient, event.actor, event.verb, domain):
			return false
		if not _new_action_valid(event, data, domain):
			return false
		if not _supported(data.objects, str(event.object), str(event.verb), domain) or not world.regions.has(event.effect_region) or not _count(event.started_ms) or not _count(event.at_ms) or int(event.at_ms) > world.elapsed_ms or not _count(event.qi_spent) or not _count(event.at, last_at) or int(event.at) > int(world.current_time):
			return false
		if event.has("method") and (not SimArtifacts.type_has_capability(domain.definitions.types[data.objects[event.object].definition], "heat_storage") or not Methods.metadata_valid(event.method, event, domain, data.events, data.objects)):
			return false
		var terms: Dictionary = domain.job_terms(event, data.objects)
		if terms.is_empty() or event.qi_spent != terms.qi or int(event.at_ms) < int(event.started_ms) or int(event.at_ms) - int(event.started_ms) > _duration(terms) or (event.kind != "cancelled" and int(event.at_ms) - int(event.started_ms) != _duration(terms)):
			return false
		var expected: String = {"inspect": "observed", "take": "taken", "place": "placed", "study": "studied", "heat": "heated", "charge": "charged", "dry": "heated", "examine": "examined", "force": "overcharged", "warm": "warmed", "use_research": "use_learned", "draw": "drawn"}[event.verb]
		if not event.kind in [expected, "failed", "cancelled"] and not (event.kind == "backlash" and event.verb in ["heat", "charge", "dry", "force"]) and not (event.kind == "depleted" and event.verb in ["heat", "dry", "warm"]) and not (event.kind == "fractured" and event.verb == "force") and not (event.has("method") and event.kind in ["fractured", "overcharged"]):
			return false
		if not event.cell is Array or event.cell.size() != 2 or not _count(event.cell[0]) or not _count(event.cell[1]):
			return false
		last_at = int(event.at)
		actions[event.action] = true
		if event.kind == "heated":
			var item: Dictionary = data.objects[event.object]
			var definition: Dictionary = SimArtifacts.heat_recipe(domain.definitions.types[item.definition], str(event.verb))
			var operation: Variant = world.regions[event.effect_region].inventory.operations.get(str(event.action) + ":heat")
			if not operation is Dictionary or operation.get("kind") != "transform" or operation.container != definition.workplace or not _same_items(operation.inputs, definition.inputs) or not _same_items(operation.outputs, definition.outputs):
				return false
	return true


static func _duration(terms: Dictionary) -> int:
	return int(terms.get("duration_ms", int(terms.get("minutes", 0)) * 60000))


static func _new_action_valid(row: Dictionary, data: Dictionary, domain: RefCounted) -> bool:
	if (row.verb == "draw") != row.has("draw"):
		return false
	if row.verb not in ["use_research", "draw"]:
		return true
	if row.has("method") or row.recipient != "" or not _count(row.get("started_ms")):
		return false
	var tool: Dictionary = data.objects[row.object]
	var definition: Dictionary = domain.definitions.types[tool.definition]
	if not SimArtifacts.type_has_capability(definition, "remote_draw"):
		return false
	var evidence: String = "studied" if row.verb == "use_research" else "use_learned"
	if not _evidence_before(row, data.events, evidence):
		return false
	if row.verb == "use_research":
		return true
	var draw: Variant = row.draw
	if not Shape.keys(draw, ["target", "from_region", "from_container", "from_cell", "caster_position"]) or not draw.target is String or draw.target == row.object or not data.objects.has(draw.target):
		return false
	if data.objects[draw.target].definition != "wooden_sword" or not draw.from_region is String or not draw.from_container is String or str(draw.from_container).begins_with("actor:") or not domain.valid_location(draw.from_region, draw.from_container):
		return false
	if not Shape.cell_valid(draw.from_cell) or not Shape.position_valid(draw.caster_position):
		return false
	if SimRouteTravel.cell(draw.from_cell) != domain._location_cell(str(draw.from_region), str(draw.from_container)):
		return false
	var origin := Vector2(float(draw.caster_position[0]), float(draw.caster_position[1]))
	var destination: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(draw.from_cell))
	if row.get("kind") == "drawn" and (row.get("effect_region") != row.region or not Shape.cell_valid(row.get("cell")) or SimRouteTravel.cell(row.cell) != TileGrid.world_to_cell(origin)):
		return false
	return origin.distance_to(destination) <= float(definition.drawing.range_cells) * TileGrid.TILE_SIZE


static func _evidence_before(row: Dictionary, events: Array, kind: String) -> bool:
	var action: String = str(row.get("action", row.id))
	for event: Variant in events:
		if not event is Dictionary or event.get("kind") != kind or event.get("actor") != row.actor or event.get("object") != row.object or not _count(event.get("at_ms")):
			continue
		if int(event.at_ms) <= int(row.started_ms) and _action_number(str(event.get("action", ""))) < _action_number(action) and _action_number(str(event.get("action", ""))) > 0:
			return true
	return false


static func _action_number(id: String) -> int:
	if id.get_slice_count(":") != 3 or not id.begins_with("artifact:action:"):
		return 0
	return int(id.get_slice(":", 2))


static func cross_valid(domain: RefCounted) -> bool:
	# This runs only after artifacts, bodies, health, geometry, souls and
	# sources have all been restored into the independent candidate world.
	var actions: Array = domain.events.duplicate()
	actions.append_array(domain.active.values())
	var soul_actions: Array = domain.world.soul_vessels.events.duplicate()
	soul_actions.append_array(domain.world.soul_vessels.active.values())
	var targets: Dictionary = {}
	for row: Dictionary in actions:
		if row.verb not in ["use_research", "draw"]:
			continue
		if not _held_before(row, domain):
			return false
		for other: Dictionary in actions:
			if str(other.get("action", other.id)) == str(row.get("action", row.id)) or not _overlap(row, other):
				continue
			if row.actor == other.actor or row.actor == other.get("method", {}).get("guide") or _same_object(row, other):
				return false
		for other: Dictionary in soul_actions:
			if _overlap(row, other) and (row.actor == other.actor or _uses_object(row, str(other.target))):
				return false
		if row.verb == "draw":
			targets[row.draw.target] = true
			var previous: Dictionary = _latest_transfer_before(str(row.draw.target), row, domain)
			if not previous.is_empty() and (previous.region != row.draw.from_region or previous.container != row.draw.from_container):
				return false
	for id: String in targets:
		var last: Dictionary = _latest_transfer(str(id), domain)
		var item: Dictionary = domain.objects[id]
		if not last.is_empty() and (last.region != item.region or last.container != item.container):
			return false
	for actor: String in domain.active:
		var job: Dictionary = domain.active[actor]
		if job.verb in ["use_research", "draw"] and not str(domain._continuation_reason(job)).is_empty():
			return false
	return true


static func _held_before(row: Dictionary, domain: RefCounted) -> bool:
	var field: RefCounted = domain.world.field_opportunities
	if not field is SimFieldOpportunities or field.sites.is_empty() or row.object != field.definitions.site.object:
		return false
	var site: Dictionary = field.sites.get(field.definitions.site.id, {})
	if site.is_empty() or int(row.started_ms) < int(site.opened_ms):
		return false
	var custody: Dictionary = {"region": str(site.region), "container": str(site.container)}
	for event: Dictionary in _ordered_events(domain):
		if event.object != row.object or event.kind not in ["taken", "placed"] or not _before(event, row):
			continue
		custody = _transfer(event, str(row.object), domain)
	return custody.region == row.region and custody.container == "actor:" + str(row.actor)


static func _overlap(a: Dictionary, b: Dictionary) -> bool:
	var end_a: int = int(a.get("at_ms", a.get("due_ms", 0)))
	var end_b: int = int(b.get("at_ms", b.get("due_ms", 0)))
	return int(a.started_ms) < end_b and int(b.started_ms) < end_a


static func _uses_object(row: Dictionary, id: String) -> bool:
	return not id.is_empty() and (row.object == id or row.get("draw", {}).get("target") == id)


static func _same_object(a: Dictionary, b: Dictionary) -> bool:
	return _uses_object(a, str(b.object)) or _uses_object(a, str(b.get("draw", {}).get("target", "")))


static func _before(event: Dictionary, row: Dictionary) -> bool:
	return int(event.at_ms) <= int(row.started_ms) and _action_number(str(event.action)) < _action_number(str(row.get("action", row.id)))


static func _ordered_events(domain: RefCounted) -> Array:
	var events: Array = domain.events.duplicate()
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.at_ms) < int(b.at_ms) or int(a.at_ms) == int(b.at_ms) and _action_number(str(a.action)) < _action_number(str(b.action)))
	return events


static func _latest_transfer_before(id: String, row: Dictionary, domain: RefCounted) -> Dictionary:
	var result: Dictionary = {}
	for event: Dictionary in _ordered_events(domain):
		if _before(event, row):
			var transferred: Dictionary = _transfer(event, id, domain)
			if not transferred.is_empty():
				result = transferred
	return result


static func _latest_transfer(id: String, domain: RefCounted) -> Dictionary:
	var result: Dictionary = {}
	for event: Dictionary in _ordered_events(domain):
		var transferred: Dictionary = _transfer(event, id, domain)
		if not transferred.is_empty():
			result = transferred
	return result


static func _transfer(event: Dictionary, id: String, domain: RefCounted) -> Dictionary:
	if event.kind == "drawn" and event.get("draw", {}).get("target") == id:
		return {"region": str(event.region), "container": "actor:" + str(event.actor)}
	if event.object != id:
		return {}
	if event.kind == "taken":
		return {"region": str(event.region), "container": "actor:" + str(event.actor)}
	if event.kind == "placed":
		var definition: Dictionary = domain.definitions.types[domain.objects[id].definition]
		return {"region": str(event.effect_region), "container": str(definition.get("storage_place", definition.get("workplace", "")))}
	return {}


static func _supported(objects: Dictionary, id: String, verb: String, domain: RefCounted) -> bool:
	if not objects.has(id):
		return false
	var definition: Dictionary = domain.definitions.types[objects[id].definition]
	if verb == "draw":
		return SimArtifacts.type_has_capability(definition, "remote_draw")
	return (domain.definitions.verbs if SimArtifacts.type_has_capability(definition, "heat_storage") else definition.actions).has(verb)


static func _valid_recipient(value: Variant, actor: String, verb: String, domain: RefCounted) -> bool:
	return value is String and (value.is_empty() or (value != actor and verb in ["examine", "study"] and not domain.actor_home(value).is_empty()))


static func _same_items(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size():
		return false
	for item: String in expected:
		if actual.get(item) != expected[item]:
			return false
	return true


static func _allocated(value: Variant, kind: String, next_id: int, seen: Dictionary) -> bool:
	if not value is String or seen.has(value) or value.get_slice_count(":") != 3 or not value.begins_with("artifact:" + kind + ":"):
		return false
	var suffix: String = value.get_slice(":", 2)
	if not suffix.is_valid_int() or suffix != str(int(suffix)) or int(suffix) < 1 or int(suffix) >= next_id:
		return false
	seen[value] = true
	return true


static func _keys(data: Dictionary, keys: Array) -> bool:
	if data.size() != keys.size():
		return false
	for key: Variant in data:
		if not key is String or not keys.has(key):
			return false
	return true


static func _count(value: Variant, minimum: int = 0) -> bool:
	return SimInventory._valid_count(value) and value >= minimum
