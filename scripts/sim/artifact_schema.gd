extends RefCounted
## Composition validation uses independently restored regions and embodiment.

const Methods = preload("res://scripts/sim/heat_method_schema.gd")

const KINDS: Array[String] = ["observed", "taken", "placed", "studied", "backlash", "charged", "heated", "depleted", "failed", "cancelled", "examined", "fractured", "overcharged", "warmed"]


static func validate(data: Dictionary, domain: RefCounted) -> bool:
	if not _keys(data, ["version", "objects", "active", "events", "experiences", "next_id"]) or data.version != 4 or not data.objects is Dictionary or not data.active is Dictionary or not data.events is Array or not data.experiences is Dictionary or not _count(data.next_id, 1):
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
		if not _keys(job, job_keys) or actor_users.has(actor):
			return false
		if job.actor != actor or domain.actor_home(actor) != job.region or not _supported(data.objects, str(job.object), str(job.verb), domain) or not _allocated(job.id, "action", int(data.next_id), allocated):
			return false
		if not _valid_recipient(job.recipient, actor, job.verb, domain):
			return false
		if not _count(job.started_ms) or (job.has("method") and (not SimArtifacts.type_has_capability(domain.definitions.types[data.objects[job.object].definition], "heat_storage") or not Methods.metadata_valid(job.method, job, domain, data.events, data.objects))):
			return false
		var terms: Dictionary = domain.job_terms(job, data.objects)
		if not _count(job.started_ms) or job.started_ms > world.elapsed_ms or not _count(job.due_ms, int(world.elapsed_ms) + 1) or int(job.due_ms) - int(job.started_ms) != int(terms.minutes) * 60000 or not _count(job.qi_spent) or job.qi_spent != terms.qi or not job.previous_autonomous is bool:
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
		actions[job.id] = true
	var last_at: int = 0
	for event: Variant in data.events:
		if not event is Dictionary:
			return false
		var event_keys: Array = ["id", "action", "actor", "subject", "object", "kind", "at", "line", "region", "cell", "verb", "started_ms", "at_ms", "qi_spent", "effect_region", "recipient"]
		if event.has("method"):
			event_keys.append("method")
		if not _keys(event, event_keys):
			return false
		if not _allocated(event.id, "event", int(data.next_id), allocated) or not _allocated(event.action, "action", int(data.next_id), allocated) or actions.has(event.action):
			return false
		if not event.actor is String or domain.actor_home(event.actor) != event.region or world.embodiment.subject_for_actor(event.actor) != event.subject or not data.objects.has(event.object) or not KINDS.has(event.kind) or not event.line is String:
			return false
		if not event.verb is String or not _valid_recipient(event.recipient, event.actor, event.verb, domain):
			return false
		if not _supported(data.objects, str(event.object), str(event.verb), domain) or not world.regions.has(event.effect_region) or not _count(event.started_ms) or not _count(event.at_ms) or int(event.at_ms) > world.elapsed_ms or not _count(event.qi_spent) or not _count(event.at, last_at) or int(event.at) > int(world.current_time):
			return false
		if event.has("method") and (not SimArtifacts.type_has_capability(domain.definitions.types[data.objects[event.object].definition], "heat_storage") or not Methods.metadata_valid(event.method, event, domain, data.events, data.objects)):
			return false
		var terms: Dictionary = domain.job_terms(event, data.objects)
		if event.qi_spent != terms.qi or int(event.at_ms) < int(event.started_ms) or int(event.at_ms) - int(event.started_ms) > int(terms.minutes) * 60000 or (event.kind != "cancelled" and int(event.at_ms) - int(event.started_ms) != int(terms.minutes) * 60000):
			return false
		var expected: String = {"inspect": "observed", "take": "taken", "place": "placed", "study": "studied", "heat": "heated", "charge": "charged", "dry": "heated", "examine": "examined", "force": "overcharged", "warm": "warmed"}[event.verb]
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


static func _supported(objects: Dictionary, id: String, verb: String, domain: RefCounted) -> bool:
	if not objects.has(id):
		return false
	var definition: Dictionary = domain.definitions.types[objects[id].definition]
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
