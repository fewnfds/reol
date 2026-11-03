extends RefCounted
## Candidate-only checks for physical custody, private learning and paid actions.

const AgencyShape = preload("res://scripts/sim/soul_agency_schema.gd")


static func keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size():
		return false
	for key: Variant in expected:
		if not value.has(key):
			return false
	return true


static func count(value: Variant, minimum: int = 0, maximum: int = SimInventory.MAX_COUNT) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == int(value) and value >= minimum and value <= maximum


static func definitions_valid(data: Variant) -> bool:
	if not keys(data, ["version", "interaction_cells", "observation_cells", "recovery_ms", "verbs", "vessel_types", "minds", "lessons", "agency"]) or data.version != 1:
		return false
	for field: String in ["interaction_cells", "observation_cells", "recovery_ms"]:
		if not count(data[field], 1, 3600000):
			return false
	if not keys(data.verbs, ["take", "place", "give", "wake", "listen", "promise", "fulfill", "guide", "sleep", "force"]):
		return false
	for terms: Variant in data.verbs.values():
		if not keys(terms, ["label", "ms", "qi", "attention"]) or not SimInventory._nonempty(terms.label) or not count(terms.ms, 1, 3600000) or not count(terms.qi, 0, 1000) or not count(terms.attention, 0, 1000):
			return false
	for field: String in ["vessel_types", "minds", "lessons"]:
		if not data[field] is Dictionary or data[field].is_empty():
			return false
		for id: Variant in data[field]:
			if not SimInventory._nonempty(id):
				return false
	for shape: Variant in data.vessel_types.values():
		if not keys(shape, ["name", "unknown_name", "appearance", "damage_max", "opening_damage", "force_damage"]) or not count(shape.damage_max, 1, 1000) or not count(shape.opening_damage, 0, int(shape.damage_max) - 1) or not count(shape.force_damage, 1, int(shape.damage_max)):
			return false
		for field: String in ["name", "unknown_name", "appearance"]:
			if not SimInventory._nonempty(shape[field]):
				return false
	for mind: Variant in data.minds.values():
		if not keys(mind, ["name", "energy_max", "opening_energy", "knowledge", "goal_region", "goal_place", "greeting", "old_memory"]) or not count(mind.energy_max, 1, 1000) or not count(mind.opening_energy, 0, int(mind.energy_max)) or not SimEmbodiment._unique_texts(mind.knowledge):
			return false
		for field: String in ["name", "goal_region", "goal_place", "greeting", "old_memory"]:
			if not SimInventory._nonempty(mind[field]):
				return false
	for lesson: Variant in data.lessons.values():
		if not keys(lesson, ["artifact_definition", "line"]) or not SimInventory._nonempty(lesson.artifact_definition) or not SimInventory._nonempty(lesson.line):
			return false
	if not keys(data.agency, ["sense_cells", "actions"]) or not count(data.agency.sense_cells, 1, 20) or not keys(data.agency.actions, ["wake", "observe", "call", "sleep"]):
		return false
	for terms: Variant in data.agency.actions.values():
		if not keys(terms, ["ms", "attention"]) or not count(terms.ms, 1, 3600000) or not count(terms.attention, 0, 1000):
			return false
	return true


static func arguments_valid(verb: String, target: Variant, recipient: Variant, destination: Variant, domain: RefCounted) -> bool:
	if not target is String or not recipient is String or not destination is String:
		return false
	if (verb == "guide") != (not target.is_empty()) or (verb == "give") != (not recipient.is_empty()) or (verb == "place") != (not destination.is_empty()):
		return false
	if verb == "guide" and not domain.world.artifacts.objects.has(target):
		return false
	if verb == "give" and domain.actor_home(recipient).is_empty():
		return false
	if verb == "place":
		if destination.get_slice_count(":") != 2 or not domain.world.regions.has(destination.get_slice(":", 0)) or not domain.world.regions[destination.get_slice(":", 0)].places.has(destination.get_slice(":", 1)):
			return false
	return true


static func validate(data: Variant, domain: RefCounted, registry_override: SimEmbodiment = null) -> bool:
	if not keys(data, ["version", "elapsed_ms", "vessels", "residents", "pacts", "active", "events", "next_id", "agency"]) or data.version != 2 or not count(data.elapsed_ms) or data.elapsed_ms != domain.world.elapsed_ms or not count(data.next_id, 1):
		return false
	for field: String in ["vessels", "residents", "pacts", "active"]:
		if not data[field] is Dictionary:
			return false
	if not data.events is Array or not keys(data.pacts, data.residents.keys()):
		return false
	for id: Variant in data.vessels:
		var item: Variant = data.vessels[id]
		if not SimInventory._nonempty(id) or domain.world.artifacts.objects.has(id) or not keys(item, ["type", "region", "container", "damage"]) or not domain.definitions.vessel_types.has(item.type) or not domain.valid_location(item.region, item.container) or not count(item.damage, 0, int(domain.definitions.vessel_types[item.type].damage_max)):
			return false
	var used_vessels: Dictionary = {}
	for id: Variant in data.residents:
		var mind: Variant = data.residents[id]
		if not SimInventory._nonempty(id) or not keys(mind, ["definition", "vessel", "energy", "recovery_ms", "awake", "knowledge"]) or not domain.definitions.minds.has(mind.definition) or not data.vessels.has(mind.vessel) or used_vessels.has(mind.vessel) or not mind.awake is bool:
			return false
		var profile: Dictionary = domain.definitions.minds[mind.definition]
		if not count(mind.energy, 0, int(profile.energy_max)) or not count(mind.recovery_ms, 0, int(domain.definitions.recovery_ms) - 1) or ((mind.awake or mind.energy == profile.energy_max) and mind.recovery_ms != 0) or mind.knowledge != profile.knowledge:
			return false
		if not domain.world.regions.has(profile.goal_region) or not domain.world.regions[profile.goal_region].places.has(profile.goal_place):
			return false
		var registry: SimEmbodiment = registry_override if registry_override != null else domain.world.embodiment
		var subject: String = "subject:soul:" + str(id)
		var carrier: String = "vessel:" + str(mind.vessel)
		if not registry._subjects.has(subject) or registry._subjects[subject].legacy_actor != "" or not registry._carriers.has(carrier) or registry._carriers[carrier].form != "soul_ring" or registry.carrier_for_source("soul_vessel", str(mind.vessel)) != carrier or registry.residence_of(subject) != carrier:
			return false
		for channel: String in registry._controls[carrier]:
			if channel != "communication" or registry._controls[carrier][channel] != subject:
				return false
		if mind.awake and int(data.vessels[mind.vessel].damage) == int(domain.definitions.vessel_types[data.vessels[mind.vessel].type].damage_max):
			return false
		if not data.pacts[id] is Dictionary:
			return false
		for actor: Variant in data.pacts[id]:
			var pact: Variant = data.pacts[id][actor]
			if not actor is String or domain.actor_home(actor).is_empty() or not keys(pact, ["state", "pledged_ms", "settled_ms"]) or not pact.state in ["pledged", "fulfilled", "broken"] or not count(pact.pledged_ms, 0, int(data.elapsed_ms)) or not count(pact.settled_ms, 0, int(data.elapsed_ms)):
				return false
			if pact.state == "pledged" and pact.settled_ms != 0 or pact.state != "pledged" and pact.settled_ms < pact.pledged_ms:
				return false
		used_vessels[mind.vessel] = true
	if used_vessels.size() != data.vessels.size():
		return false
	var ids: Dictionary = {}
	var action_ids: Dictionary = {}
	var occupied: Dictionary = {}
	for actor: Variant in data.active:
		var job: Variant = data.active[actor]
		if not keys(job, ["id", "actor", "soul", "vessel", "verb", "target", "recipient", "destination", "region", "started_ms", "due_ms", "qi_spent", "soul_spent", "previous_autonomous"]) or job.actor != actor or not _common(job, data, domain) or not _allocated(job.id, "action", int(data.next_id), ids) or not job.previous_autonomous is bool:
			return false
		var terms: Dictionary = domain.definitions.verbs[job.verb]
		if not count(job.due_ms, int(data.elapsed_ms) + 1) or int(job.due_ms) - int(job.started_ms) != int(terms.ms) or occupied.has(job.vessel):
			return false
		var person: Dictionary = domain.world.regions[job.region].actors[actor]
		if not person.active.is_empty() or person.autonomous or not domain.world.actor_controls(actor, "action") or not domain.world.actor_controls(actor, "motion") or not domain.world.actor_controls(actor, "communication") or (domain.world.services != null and domain.world.services.owns_actor(actor)) or domain.world.artifacts.owns_actor(actor):
			return false
		var item: Dictionary = data.vessels[job.vessel]
		if job.verb != "take" and (item.region != job.region or item.container != "actor:" + str(actor)) or job.verb == "take" and str(item.container).begins_with("actor:"):
			return false
		if job.verb in ["guide", "listen", "promise", "fulfill", "sleep"] and not data.residents[job.soul].awake:
			return false
		if not str(job.verb) in ["take", "place", "give"] and not domain.world.embodiment.controls("subject:soul:" + str(job.soul), "vessel:" + str(job.vessel), "communication"):
			return false
		var source: RefCounted = domain.world.regions[item.region]
		var cell: Vector2i = SimRouteTravel.cell(source.actors[str(item.container).trim_prefix("actor:")].cell if str(item.container).begins_with("actor:") else source.places[item.container].cell)
		if SimRouteTravel.cell(person.cell).distance_to(cell) > float(domain.definitions.interaction_cells):
			return false
		if job.verb == "guide":
			for experiment: Dictionary in domain.world.artifacts.active.values():
				if experiment.object == job.target:
					return false
		if job.verb == "guide" and (data.pacts[job.soul].get(actor, {}).get("state") != "fulfilled" or not _kept_before(data, str(job.soul), str(actor), int(job.started_ms))):
			return false
		occupied[job.vessel] = true
		action_ids[job.id] = true
	var previous_ms: int = 0
	for event: Variant in data.events:
		if not keys(event, ["id", "action", "actor", "soul", "vessel", "verb", "target", "recipient", "destination", "region", "started_ms", "at_ms", "qi_spent", "soul_spent", "kind", "line"]) or not _common(event, data, domain) or not _allocated(event.id, "event", int(data.next_id), ids) or not _allocated(event.action, "action", int(data.next_id), ids) or action_ids.has(event.action) or not event.line is String:
			return false
		if not count(event.at_ms, previous_ms, int(data.elapsed_ms)) or event.at_ms < event.started_ms or not event.kind in [event.verb, "cancelled", "failed"]:
			return false
		var duration: int = int(event.at_ms) - int(event.started_ms)
		if duration > int(domain.definitions.verbs[event.verb].ms) or not event.kind in ["failed", "cancelled"] and duration != int(domain.definitions.verbs[event.verb].ms):
			return false
		if event.kind == "guide" and not _kept_before(data, str(event.soul), str(event.actor), int(event.started_ms)):
			return false
		previous_ms = int(event.at_ms)
		action_ids[event.action] = true
	for soul: String in data.pacts:
		for actor: String in data.pacts[soul]:
			var pact: Dictionary = data.pacts[soul][actor]
			if not _event_at(data, soul, actor, "promise", int(pact.pledged_ms)):
				return false
			if pact.state == "fulfilled" and not _event_at(data, soul, actor, "fulfill", int(pact.settled_ms)):
				return false
			if pact.state == "broken" and not (_event_at(data, soul, actor, "place", int(pact.settled_ms)) or _event_at(data, soul, actor, "give", int(pact.settled_ms)) or _event_at(data, soul, actor, "force", int(pact.settled_ms))):
				return false
	return AgencyShape.validate(data.agency, domain, data)


static func _common(row: Dictionary, data: Dictionary, domain: RefCounted) -> bool:
	if not row.actor is String or not row.region is String or not domain.world.regions.has(row.region) or domain.actor_home(row.actor) != row.region or not data.residents.has(row.soul) or data.residents[row.soul].vessel != row.vessel or not domain.definitions.verbs.has(row.verb) or not count(row.started_ms, 0, int(data.elapsed_ms)) or not arguments_valid(str(row.verb), row.target, row.recipient, row.destination, domain):
		return false
	var terms: Dictionary = domain.definitions.verbs[row.verb]
	if not count(row.qi_spent) or row.qi_spent != terms.qi or not count(row.soul_spent, 0, int(terms.attention)) or (row.verb != "force" and row.soul_spent != terms.attention):
		return false
	if row.verb == "give":
		if row.recipient == row.actor:
			return false
		var consent: bool = false
		for request: Dictionary in domain.world.regions[domain.actor_home(row.recipient)].social.requests.values():
			if request.requester == row.actor and request.responder == row.recipient and request.task == "vessel_custody" and request.status == "accepted" and request.context.get("terms", {}).get("vessel") == row.vessel and int(request.tick) * 60000 <= int(row.started_ms):
				consent = true
		if not consent:
			return false
	if row.verb == "guide":
		var profile: Dictionary = domain.definitions.minds[data.residents[row.soul].definition]
		var found: bool = false
		for knowledge: String in profile.knowledge:
			if domain.definitions.lessons.has(knowledge) and domain.definitions.lessons[knowledge].artifact_definition == domain.world.artifacts.objects[row.target].definition:
				found = true
		if not found:
			return false
	return true


static func _event_at(data: Dictionary, soul: String, actor: String, kind: String, at_ms: int) -> bool:
	for event: Variant in data.events:
		if event is Dictionary and event.get("soul") == soul and event.get("actor") == actor and event.get("kind") == kind and event.get("at_ms") == at_ms:
			return true
	return false


static func _kept_before(data: Dictionary, soul: String, actor: String, at_ms: int) -> bool:
	var kept: bool = false
	for event: Variant in data.events:
		if not event is Dictionary or event.get("soul") != soul or event.get("actor") != actor or not count(event.get("at_ms"), 0, at_ms):
			continue
		if event.get("kind") == "fulfill":
			kept = true
		elif event.get("kind") in ["force", "promise"]:
			kept = false
	return kept


static func _allocated(value: Variant, kind: String, next_id: int, seen: Dictionary) -> bool:
	if not value is String or seen.has(value) or value.get_slice_count(":") != 3 or not value.begins_with("soul:" + kind + ":"):
		return false
	var suffix: String = value.get_slice(":", 2)
	if not suffix.is_valid_int() or suffix != str(int(suffix)) or not count(int(suffix), 1, next_id - 1):
		return false
	seen[value] = true
	return true
