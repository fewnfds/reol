extends RefCounted
## Composition validation uses independently restored regions and embodiment.

const Methods = preload("res://scripts/sim/heat_method_schema.gd")
const Shape = preload("res://scripts/sim/avian_schema.gd")

const KINDS: Array[String] = ["observed", "taken", "placed", "studied", "backlash", "charged", "heated", "depleted", "failed", "cancelled", "examined", "fractured", "overcharged", "warmed", "use_learned", "drawn", "exchanged", "enabled", "disabled"]


static func validate(data: Dictionary, domain: RefCounted) -> bool:
	if not _keys(data, ["version", "objects", "active", "events", "experiences", "next_id"]) or data.version != SimArtifacts.VERSION or not data.objects is Dictionary or not data.active is Dictionary or not data.events is Array or not data.experiences is Dictionary or not _count(data.next_id, 1):
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
		if SimArtifacts.type_has_capability(definition, "thermal_exchange"):
			if not _keys(item, ["definition", "region", "container", "stored_q", "enabled"]) or not _count(item.stored_q) or int(item.stored_q) > int(definition.thermal.capacity_q) or not item.enabled is bool:
				return false
			if domain.storage_region(str(item.region), str(definition.storage_place)).is_empty() or bool(item.enabled) and not domain.thermal_fixed_location(item):
				return false
			continue
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
		if SimArtifacts.type_has_capability(definition, "thermal_exchange"):
			if job.verb in ["take", "place"] and bool(item.enabled):
				return false
			if job.verb in ["enable", "disable"] and (not domain.thermal_fixed_location(item) or bool(item.enabled) != (job.verb == "disable")):
				return false
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
		if event.has("exchange"):
			event_keys.append("exchange")
		if event.get("kind") == "warmed":
			event_keys.append("heat_amount")
		if event.get("kind") in ["enabled", "disabled"]:
			event_keys.append("device_container")
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
		if not world.regions.has(event.effect_region) or not _count(event.started_ms) or not _count(event.at_ms) or int(event.at_ms) > world.elapsed_ms or not _count(event.qi_spent) or not _count(event.at, last_at) or int(event.at) > int(world.current_time):
			return false
		if event.verb == "private_exchange":
			var field: Variant = world.get("field_opportunities")
			if field == null or field.sites.is_empty() or event.object != field.definitions.site.object or event.kind != "exchanged" or not SimInventory._nonempty(event.get("exchange")) or event.has("method") or event.has("draw"):
				return false
			if int(event.qi_spent) != 0 or event.effect_region != domain.actor_home(str(event.recipient)) or int(event.at_ms) <= int(event.started_ms) or int(event.at) != floori(float(event.at_ms) / 60000.0) or not Shape.cell_valid(event.cell):
				return false
			if _action_number(str(event.action)) >= _serial_number(str(event.id), "event"):
				return false
			last_at = int(event.at)
			actions[event.action] = true
			continue
		if event.has("exchange") or event.kind == "exchanged" or not _supported(data.objects, str(event.object), str(event.verb), domain):
			return false
		if event.kind == "warmed":
			# The candidate's original heat authority is initialized before artifact
			# restoration. Never guess an amount from today's disk definitions or
			# tolerate an absent amount in this current artifact format.
			var heat: Variant = world.get("local_heat")
			if heat == null or not heat.definitions is Dictionary or not Shape.count(heat.definitions.get("pulse_energy"), 1, SimLocalHeat.MAX_INTEGER) or not Shape.count(event.heat_amount, 1, SimLocalHeat.MAX_INTEGER) or event.heat_amount != heat.definitions.pulse_energy:
				return false
		if event.has("method") and (not SimArtifacts.type_has_capability(domain.definitions.types[data.objects[event.object].definition], "heat_storage") or not Methods.metadata_valid(event.method, event, domain, data.events, data.objects)):
			return false
		var terms: Dictionary = domain.job_terms(event, data.objects)
		if terms.is_empty() or event.qi_spent != terms.qi or int(event.at_ms) < int(event.started_ms) or int(event.at_ms) - int(event.started_ms) > _duration(terms) or (event.kind != "cancelled" and int(event.at_ms) - int(event.started_ms) != _duration(terms)):
			return false
		var expected: String = {"inspect": "observed", "take": "taken", "place": "placed", "study": "studied", "heat": "heated", "charge": "charged", "dry": "heated", "examine": "examined", "force": "overcharged", "warm": "warmed", "use_research": "use_learned", "draw": "drawn", "enable": "enabled", "disable": "disabled"}[event.verb]
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
	return _thermal_lifecycle_valid(data, domain)


static func _duration(terms: Dictionary) -> int:
	return int(terms.get("duration_ms", int(terms.get("minutes", 0)) * 60000))


static func _new_action_valid(row: Dictionary, data: Dictionary, domain: RefCounted) -> bool:
	if (row.verb == "draw") != row.has("draw"):
		return false
	if row.verb in ["enable", "disable"]:
		if row.has("method") or row.recipient != "" or not _count(row.get("started_ms")) or not data.objects.has(row.object):
			return false
		var item: Dictionary = data.objects[row.object]
		if not SimArtifacts.type_has_capability(domain.definitions.types[item.definition], "thermal_exchange"):
			return false
		return row.verb == "disable" or _thermal_study_before(row, data.events, domain)
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


static func _thermal_study_before(row: Dictionary, events: Array, domain: RefCounted) -> bool:
	var subject: String = domain.world.embodiment.subject_for_actor(str(row.actor))
	for event: Variant in events:
		if not event is Dictionary or event.get("kind") != "studied" or event.get("subject") != subject or event.get("object") != row.object or not _count(event.get("at_ms")):
			continue
		if _before(event, row):
			return true
	return false


static func _thermal_lifecycle_valid(data: Dictionary, domain: RefCounted) -> bool:
	# Opening devices are disabled. Successful toggles and transfers must preserve
	# that state; the heat candidate independently validates their exact receipts.
	var states: Dictionary = {}
	var last_times: Dictionary = {}
	var anchors: Dictionary = {}
	for id: String in data.objects:
		var item: Dictionary = data.objects[id]
		if SimArtifacts.type_has_capability(domain.definitions.types[item.definition], "thermal_exchange"):
			states[id] = false
			last_times[id] = 0
	for event: Dictionary in data.events:
		var id: String = str(event.object)
		if not states.has(id):
			continue
		if int(event.at_ms) < int(last_times[id]):
			return false
		last_times[id] = int(event.at_ms)
		if event.kind in ["taken", "placed", "exchanged"] and bool(states[id]):
			return false
		if event.kind not in ["enabled", "disabled"]:
			continue
		var next: bool = event.kind == "enabled"
		if bool(states[id]) == next or _action_number(str(event.action)) >= _serial_number(str(event.id), "event") or int(event.at) != floori(float(event.at_ms) / 60000.0):
			return false
		if not event.device_container is String or not domain.thermal_fixed_location({"region": event.effect_region, "container": event.device_container}):
			return false
		var place: Dictionary = domain.world.regions[event.effect_region].places[event.device_container]
		if SimRouteTravel.cell(place.cell) != SimRouteTravel.cell(event.cell):
			return false
		var anchor: Dictionary = {"region": str(event.effect_region), "container": str(event.device_container)}
		if next:
			anchors[id] = anchor
		elif anchors.get(id, {}) != anchor:
			return false
		else:
			anchors.erase(id)
		states[id] = next
	for id: String in states:
		if bool(data.objects[id].enabled) != bool(states[id]):
			return false
		if bool(states[id]):
			var item: Dictionary = data.objects[id]
			if anchors.get(id, {}) != {"region": str(item.region), "container": str(item.container)}:
				return false
	return true


static func _evidence_before(row: Dictionary, events: Array, kind: String) -> bool:
	for event: Variant in events:
		if not event is Dictionary or event.get("kind") != kind or event.get("actor") != row.actor or event.get("object") != row.object or not _count(event.get("at_ms")):
			continue
		if _before(event, row):
			return true
	return false


static func _action_number(id: String) -> int:
	return _serial_number(id, "action")


static func _serial_number(id: String, kind: String) -> int:
	if id.get_slice_count(":") != 3 or not id.begins_with("artifact:" + kind + ":"):
		return 0
	var suffix: String = id.get_slice(":", 2)
	if not suffix.is_valid_int() or int(suffix) < 1 or suffix != str(int(suffix)):
		return 0
	return int(suffix)


static func cross_valid(domain: RefCounted) -> bool:
	# This runs only after artifacts, bodies, health, geometry, souls and
	# sources have all been restored into the independent candidate world.
	if not _exchange_cross_valid(domain):
		return false
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


static func _exchange_cross_valid(domain: RefCounted) -> bool:
	var world: RefCounted = domain.world
	var exchange: Variant = world.get("private_exchange")
	if exchange == null or not exchange.jobs is Dictionary or not _count(domain.next_id, 1):
		return false
	var moments: Dictionary = {}
	var event_by_id: Dictionary = {}
	var events_by_action: Dictionary = {}
	var artifact_actions: Array = []
	var last_event_number: int = 0
	for event: Variant in domain.events:
		if not event is Dictionary or not _remember_moment(moments, event.get("action"), "action", event.get("started_ms"), domain.next_id) or not _remember_moment(moments, event.get("id"), "event", event.get("at_ms"), domain.next_id):
			return false
		var event_number: int = _serial_number(event.id, "event")
		if event_number <= _action_number(event.action) or event_number <= last_event_number:
			return false
		last_event_number = event_number
		event_by_id[event.id] = event
		events_by_action[event.action] = event
		artifact_actions.append(event)
	for row: Variant in domain.active.values():
		if not row is Dictionary or not _remember_moment(moments, row.get("id"), "action", row.get("started_ms"), domain.next_id):
			return false
		artifact_actions.append(row)
	var completed: Dictionary = {}
	var jobs: Array[Dictionary] = []
	var outstanding: int = domain.active.size()
	for key: Variant in exchange.jobs:
		var job: Variant = exchange.jobs[key]
		if not key is String or not job is Dictionary or job.get("id") != key or not SimInventory._nonempty(job.get("buyer")) or not SimInventory._nonempty(job.get("seller")) or job.buyer == job.seller:
			return false
		if not SimInventory._nonempty(job.get("object")) or not SimInventory._nonempty(job.get("source_event")) or not job.get("buyer_region") is String or not job.get("seller_region") is String or domain.actor_home(str(job.buyer)) != job.buyer_region or domain.actor_home(str(job.seller)) != job.seller_region:
			return false
		if not _count(job.get("started_ms")) or not _count(job.get("due_ms")) or int(job.started_ms) >= int(job.due_ms) or int(job.started_ms) > int(world.elapsed_ms) or not Shape.position_valid(job.get("seller_position")):
			return false
		if not job.get("artifact_action") is String or not job.get("artifact_event") is String or not job.get("artifact_release") is String or job.get("status") not in ["active", "completed", "cancelled", "failed"]:
			return false
		var action: String = str(job.artifact_action)
		var event: Dictionary = event_by_id.get(job.artifact_event, {})
		if job.status == "completed":
			if job.artifact_release != "" or event.is_empty() or events_by_action.get(action, {}) != event or completed.has(job.artifact_event) or not _count(job.get("finished_ms")) or int(job.finished_ms) != int(job.due_ms) or int(job.finished_ms) > int(world.elapsed_ms):
				return false
			if not _exchange_matches(event, job, domain):
				return false
			completed[job.artifact_event] = true
		else:
			if job.artifact_event != "" or events_by_action.has(action) or not _remember_moment(moments, action, "action", job.started_ms, domain.next_id):
				return false
			if job.status == "active":
				if job.get("finished_ms") != -1 or job.artifact_release != "" or int(job.due_ms) <= int(world.elapsed_ms):
					return false
				outstanding += 1
			else:
				if not _count(job.get("finished_ms"), int(job.started_ms)) or int(job.finished_ms) > int(world.elapsed_ms) or int(job.finished_ms) > int(job.due_ms):
					return false
				if not _remember_moment(moments, job.artifact_release, "release", job.finished_ms, domain.next_id) or _serial_number(job.artifact_release, "release") <= _action_number(action):
					return false
		var holder_query: Dictionary = {"object": job.object, "actor": job.seller, "region": job.seller_region, "started_ms": job.started_ms, "id": action}
		if holder_source_before(holder_query, domain) != job.source_event:
			return false
		jobs.append(job)
	for event: Dictionary in domain.events:
		if event.kind == "exchanged" and not completed.has(event.id):
			return false
	if int(domain.next_id) > SimInventory.MAX_COUNT - outstanding:
		return false
	var sequence: Array = moments.keys()
	sequence.sort()
	var previous_ms: int = 0
	for number: int in sequence:
		if int(moments[number]) < previous_ms:
			return false
		previous_ms = int(moments[number])
	for index: int in jobs.size():
		var job: Dictionary = jobs[index]
		for prior_index: int in range(index):
			var other: Dictionary = jobs[prior_index]
			if _exchange_overlap(job, other) and (job.object == other.object or job.buyer in [other.buyer, other.seller] or job.seller in [other.buyer, other.seller]):
				return false
		for other: Dictionary in artifact_actions:
			if other.get("action", other.get("id")) == job.artifact_action:
				continue
			if _exchange_artifact_overlap(job, other) and (other.actor in [job.buyer, job.seller] or other.get("method", {}).get("guide") in [job.buyer, job.seller] or _uses_object(other, str(job.object))):
				return false
		var other_domains: Array = world.soul_vessels.events.duplicate()
		other_domains.append_array(world.soul_vessels.active.values())
		for other: Dictionary in other_domains:
			if _exchange_external_overlap(job, other) and (other.actor in [job.buyer, job.seller] or other.get("target") == job.object):
				return false
		other_domains = world.spirit_sources.records.values()
		other_domains.append_array(world.spirit_sources.active.values())
		for other: Dictionary in other_domains:
			if _exchange_external_overlap(job, other) and (other.actor in [job.buyer, job.seller] or other.get("object") == job.object):
				return false
	return true


static func _exchange_matches(event: Dictionary, job: Dictionary, domain: RefCounted) -> bool:
	if event.get("kind") != "exchanged" or event.get("verb") != "private_exchange" or event.get("exchange") != job.id or event.get("action") != job.artifact_action:
		return false
	if event.get("object") != job.object or event.get("actor") != job.seller or event.get("recipient") != job.buyer or event.get("region") != job.seller_region or event.get("effect_region") != job.buyer_region:
		return false
	if event.get("started_ms") != job.started_ms or event.get("at_ms") != job.finished_ms or event.get("subject") != domain.world.embodiment.subject_for_actor(str(job.seller)):
		return false
	var point := Vector2(float(job.seller_position[0]), float(job.seller_position[1]))
	return SimRouteTravel.cell(event.cell) == TileGrid.world_to_cell(point)


static func _remember_moment(moments: Dictionary, id: Variant, kind: String, at_ms: Variant, next_id: int) -> bool:
	if not _count(at_ms) or not _allocated(id, kind, next_id, {}):
		return false
	var number: int = _serial_number(id, kind)
	if moments.has(number):
		return false
	moments[number] = int(at_ms)
	return true


static func _before_point(ms_a: int, serial_a: int, ms_b: int, serial_b: int) -> bool:
	return ms_a < ms_b or ms_a == ms_b and serial_a < serial_b


static func _exchange_end(job: Dictionary) -> Array[int]:
	if job.status == "active":
		return [int(job.due_ms), SimInventory.MAX_COUNT]
	var serial: int = _serial_number(str(job.artifact_event), "event") if job.status == "completed" else _serial_number(str(job.artifact_release), "release")
	return [int(job.finished_ms), serial]


static func _exchange_overlap(a: Dictionary, b: Dictionary) -> bool:
	var end_a: Array[int] = _exchange_end(a)
	var end_b: Array[int] = _exchange_end(b)
	return _before_point(int(a.started_ms), _action_number(str(a.artifact_action)), end_b[0], end_b[1]) and _before_point(int(b.started_ms), _action_number(str(b.artifact_action)), end_a[0], end_a[1])


static func _exchange_artifact_overlap(job: Dictionary, other: Dictionary) -> bool:
	var job_end: Array[int] = _exchange_end(job)
	var other_end_ms: int = int(other.get("at_ms", other.get("due_ms", 0)))
	var other_end_serial: int = _serial_number(str(other.id), "event") if other.has("at_ms") else SimInventory.MAX_COUNT
	var other_action: int = _action_number(str(other.get("action", other.id)))
	return _before_point(int(job.started_ms), _action_number(str(job.artifact_action)), other_end_ms, other_end_serial) and _before_point(int(other.started_ms), other_action, job_end[0], job_end[1])


static func _exchange_external_overlap(job: Dictionary, other: Dictionary) -> bool:
	var end: int = int(job.due_ms) if job.status == "active" else int(job.finished_ms)
	var other_end: int = int(other.get("at_ms", other.get("finished_ms", other.get("due_ms", 0))))
	return int(job.started_ms) < other_end and int(other.started_ms) < end


static func _held_before(row: Dictionary, domain: RefCounted) -> bool:
	return not holder_source_before(row, domain).is_empty()


static func holder_source_before(row: Dictionary, domain: RefCounted) -> String:
	var field: Variant = domain.world.get("field_opportunities")
	if field == null or field.sites.is_empty() or row.get("object") != field.definitions.site.object or not _count(row.get("started_ms")):
		return ""
	var custody: Dictionary = field_custody(domain, int(row.started_ms), str(row.get("action", row.get("id", ""))))
	if custody.get("region") != row.get("region") or custody.get("container") != "actor:" + str(row.get("actor", "")):
		return ""
	return str(custody.get("source", ""))


static func field_custody(domain: RefCounted, at_ms: int, before_action: String = "") -> Dictionary:
	# Reconstruct the unique original object; no object/holder is inferred from
	# an exchange request. An empty result means the history cannot be proved.
	var field: Variant = domain.world.get("field_opportunities")
	if field == null or not field.definitions.get("site") is Dictionary:
		return {}
	var rule: Dictionary = field.definitions.site
	var site: Variant = field.sites.get(rule.get("id", ""))
	if not site is Dictionary or not _count(site.get("opened_ms")) or at_ms < int(site.opened_ms):
		return {}
	var limit: int = _action_number(before_action) if not before_action.is_empty() else 0
	if not before_action.is_empty() and limit == 0:
		return {}
	var state: Dictionary = {"region": str(site.region), "container": str(site.container), "source": ""}
	for event: Dictionary in _ordered_events(domain):
		if event.get("object") != rule.object or int(event.at_ms) > at_ms:
			continue
		if limit > 0 and _serial_number(str(event.id), "event") >= limit:
			continue
		if int(event.started_ms) < int(site.opened_ms):
			return {}
		if event.kind == "taken":
			if state.region != site.region or state.container != site.container or event.effect_region != event.region:
				return {}
			state = {"region": str(event.region), "container": "actor:" + str(event.actor), "source": str(event.id)}
		elif event.kind == "placed":
			if state.region != event.region or state.container != "actor:" + str(event.actor) or event.effect_region != site.region:
				return {}
			state = {"region": str(site.region), "container": str(site.container), "source": ""}
		elif event.kind == "exchanged":
			if state.region != event.region or state.container != "actor:" + str(event.actor) or event.effect_region != domain.actor_home(str(event.recipient)):
				return {}
			state = {"region": str(event.effect_region), "container": "actor:" + str(event.recipient), "source": str(event.id)}
	return state


static func serial_floor_valid(domain: RefCounted, floor_value: Variant, at_value: Variant) -> bool:
	# The proposal snapshots next_id without consuming it; every subsequently
	# retained original action, result or release must agree with that boundary.
	if not _count(floor_value, 1) or int(floor_value) > int(domain.next_id) or not _count(at_value) or int(at_value) > int(domain.world.elapsed_ms):
		return false
	var floor_number: int = int(floor_value)
	var at_ms: int = int(at_value)
	for event: Variant in domain.events:
		if not event is Dictionary or not _floor_point(_action_number(str(event.get("action", ""))), event.get("started_ms"), floor_number, at_ms) or not _floor_point(_serial_number(str(event.get("id", "")), "event"), event.get("at_ms"), floor_number, at_ms):
			return false
	for job: Variant in domain.active.values():
		if not job is Dictionary or not _floor_point(_action_number(str(job.get("id", ""))), job.get("started_ms"), floor_number, at_ms):
			return false
	var exchange: Variant = domain.world.get("private_exchange")
	if exchange == null or not exchange.jobs is Dictionary:
		return false
	for job: Variant in exchange.jobs.values():
		if not job is Dictionary or not _floor_point(_action_number(str(job.get("artifact_action", ""))), job.get("started_ms"), floor_number, at_ms):
			return false
		if job.get("status") in ["cancelled", "failed"] and not _floor_point(_serial_number(str(job.get("artifact_release", "")), "release"), job.get("finished_ms"), floor_number, at_ms):
			return false
	return true


static func _floor_point(number: int, value: Variant, floor_number: int, at_ms: int) -> bool:
	if number < 1 or not _count(value):
		return false
	return int(value) <= at_ms if number < floor_number else int(value) >= at_ms


static func _overlap(a: Dictionary, b: Dictionary) -> bool:
	var end_a: int = int(a.get("at_ms", a.get("due_ms", 0)))
	var end_b: int = int(b.get("at_ms", b.get("due_ms", 0)))
	return int(a.started_ms) < end_b and int(b.started_ms) < end_a


static func _uses_object(row: Dictionary, id: String) -> bool:
	return not id.is_empty() and (row.object == id or row.get("draw", {}).get("target") == id)


static func _same_object(a: Dictionary, b: Dictionary) -> bool:
	return _uses_object(a, str(b.object)) or _uses_object(a, str(b.get("draw", {}).get("target", "")))


static func _before(event: Dictionary, row: Dictionary) -> bool:
	var completed: int = _serial_number(str(event.get("id", "")), "event")
	var started: int = _action_number(str(row.get("action", row.get("id", ""))))
	return completed > 0 and started > 0 and completed < started and int(event.at_ms) <= int(row.started_ms)


static func _ordered_events(domain: RefCounted) -> Array:
	var events: Array = domain.events.duplicate()
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.at_ms) < int(b.at_ms) or int(a.at_ms) == int(b.at_ms) and _serial_number(str(a.id), "event") < _serial_number(str(b.id), "event"))
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
	if event.kind == "exchanged":
		return {"region": str(event.effect_region), "container": "actor:" + str(event.recipient)}
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
	if not value is String:
		return false
	if verb == "private_exchange":
		return not value.is_empty() and value != actor and not domain.actor_home(value).is_empty()
	return value.is_empty() or (value != actor and verb in ["examine", "study"] and not domain.actor_home(value).is_empty())


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
