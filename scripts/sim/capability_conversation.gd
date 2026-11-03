class_name SimCapabilityConversation
extends RefCounted
## A private attributed utterance, not a public catalogue or an ability grant.
## Only original social ledgers persist it; asking/recalling creates no skills.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const TASK: String = "capability_conversation"
const KIND: String = "capability_statement"


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "minimum_energy", "topics", "introduction", "qualification", "statements", "policy"]) or data.version != 1 or not Shape.count(data.minimum_energy, 0, 100) or not Shape.keys(data.topics, ["ways"]) or not SimInventory._nonempty(data.topics.ways) or not SimInventory._nonempty(data.introduction) or not SimInventory._nonempty(data.qualification) or not data.statements is Dictionary or data.statements.is_empty() or not data.policy is Dictionary:
		return false
	if SimSocialMemory.new()._normalized_policy(data.policy).is_empty():
		return false
	for id: Variant in data.statements:
		var entry: Variant = data.statements[id]
		if not SimInventory._nonempty(id) or not Shape.keys(entry, ["rule", "value", "line"]) or not SimInventory._nonempty(entry.line):
			return false
		if entry.rule == "native_haul" and entry.value == "haul" or entry.rule == "own_duty" and entry.value == "cook" or entry.rule == "practice" and entry.value in ["stonecraft", "herbal_meridian_care"] or entry.rule == "learned_base" and entry.value == "warm_stone" or entry.rule == "permission" and entry.value in ["record", "pay", "authorize"]:
			continue
		return false
	return true


static func ask(world: RefCounted, listener: String, speaker: String, topic: String) -> Dictionary:
	if world.elapsed_ms != world.target_ms:
		return SimInteractionRequests.result("invalid", "先等世界事务结算完，再当面询问。")
	return _ask(world, listener, speaker, topic)


static func ask_autonomous(world: RefCounted, listener: String, speaker: String, topic: String) -> Dictionary:
	if not world.autonomous_decision(listener):
		return SimInteractionRequests.result("invalid", "只有本人当下的自主决策才能提出询问。")
	return _ask(world, listener, speaker, topic)


static func _ask(world: RefCounted, listener: String, speaker: String, topic: String) -> Dictionary:
	var rules: Dictionary = world._content.capability_conversation
	var home: String = world.services.actor_home(speaker)
	var other: String = world.services.actor_home(listener)
	if home.is_empty() or other.is_empty() or listener == speaker or not rules.topics.has(topic):
		return SimInteractionRequests.result("invalid", "需要明确向谁询问哪件事。")
	world.synchronize_region(home)
	world.synchronize_region(other)
	var sim: VillageSimulation = world.regions[home]
	var person: Dictionary = sim.actors[speaker]
	var questioner: Dictionary = world.regions[other].actors[listener]
	if not world.actor_controls(listener, "communication") or not world.actor_controls(speaker, "communication") or SimRouteTravel.cell(person.cell).distance_to(SimRouteTravel.cell(questioner.cell)) > float(world._content.interaction_requests.communication_cells):
		return SimInteractionRequests.result("unheard", "相距太远或眼下无法说话，尚未听到这番自述。")
	if not world.native_action_allowed(speaker) or float(person.energy) < float(rules.minimum_energy):
		return SimInteractionRequests.result("unavailable", "对方正需专心或休息，暂不愿停下来介绍。")
	var claims: Array[String] = _self_description(world, speaker, rules)
	var scope: String = home if home == other else "services"
	var memory: SimSocialMemory = _ledger(world, scope)
	var relation: Dictionary = memory.relation(speaker, listener)
	var context: Dictionary = {"energy": float(person.energy) / 100.0, "busy": 0.0 if person.active.is_empty() else 1.0,
		"benevolence": float(sim.config.actor_profiles.get(speaker, {}).get("benevolence", 0.5)),
		"reliability": relation.reliability, "affinity": relation.affinity, "terms": {"topic": topic, "claims": claims}}
	var rng: RandomNumberGenerator = sim._rng if scope != "services" else world.services._rng
	var decision: Dictionary = memory.evaluate_request(listener, speaker, TASK, context, rules.policy, rng, world.current_time)
	world.invalidate_region(home)
	if decision.get("status") != "accepted":
		return SimInteractionRequests.result("refused", "对方不想向你介绍这些，短答也要看彼此处境。")
	for event: Dictionary in memory.events:
		if event.kind == KIND and event.details.get("private", {}).get("decision") == decision.id:
			return _answer(world, scope, event)
	var witnesses: Array[String] = []
	var id: String = memory.record(KIND, speaker, listener,
		{"participants": {"topic": topic, "claims": claims, "text": _quote(claims, rules)}, "private": {"decision": decision.id}}, witnesses, world.current_time)
	return _answer(world, scope, memory._event_by_id[id])


static func _self_description(world: RefCounted, speaker: String, rules: Dictionary) -> Array[String]:
	var sim: VillageSimulation = world.regions[world.services.actor_home(speaker)]
	var claims: Array[String] = []
	for id: String in rules.statements:
		var entry: Dictionary = rules.statements[id]
		var known: bool = false
		match entry.rule:
			"native_haul":
				for action: Dictionary in sim.config.actions.values():
					known = known or action.kind == entry.value
			"practice":
				if entry.value == "herbal_meridian_care":
					known = world.health.can_diagnose(speaker)
				else:
					known = world.artifacts.Understanding.practiced(world.artifacts, speaker, str(entry.value))
			"own_duty":
				known = sim.config.actor_profiles.get(speaker, {}).get("duty") == entry.value
			"learned_base":
				for object_id: String in world.artifacts.objects:
					if world.artifacts.objects[object_id].definition == entry.value:
						known = known or world.heat_methods.base_known_from(speaker, object_id, world.elapsed_ms)
			"permission":
				known = sim.institutions.has_permission(str(sim.config.institution.id), speaker, str(entry.value))
		if known:
			claims.append(id)
	return claims


static func _quote(claims: Array, rules: Dictionary) -> String:
	var lines: Array[String] = [str(rules.introduction)]
	for id: String in claims:
		lines.append("· " + str(rules.statements[id].line))
	lines.append(str(rules.qualification))
	return "\n".join(lines)


static func _answer(world: RefCounted, scope: String, event: Dictionary) -> Dictionary:
	return SimInteractionRequests.result("completed", "对方答了几句。你记下的是他的自述，后续事情仍须另行商量。",
		{"domain": "conversation", "id": scope + ":" + str(event.id), "performer": world.embodiment.subject_for_actor(str(event.actor))})


static func recall(world: RefCounted, listener: String, process: Dictionary) -> Dictionary:
	if not Shape.keys(process, ["domain", "id", "performer"]) or process.domain != "conversation" or not process.id is String:
		return SimInteractionRequests.result("unconfirmed", "没有本人听到的自述。")
	var scope: String = str(process.id).get_slice(":", 0)
	var id: String = str(process.id).get_slice(":", 1)
	var memory: SimSocialMemory = _ledger(world, scope)
	if memory == null or not memory.knowledge.has(listener):
		return SimInteractionRequests.result("unconfirmed", "没有本人听到的自述。")
	var known: Dictionary = memory.knowledge[listener].get(id, {})
	if known.get("kind") != KIND or known.get("target") != listener or world.embodiment.subject_for_actor(str(known.get("actor", ""))) != process.performer or not known.details.has("text"):
		return SimInteractionRequests.result("unconfirmed", "这不是对方向你说过的话。")
	var home: String = world.services.actor_home(str(known.actor))
	var name: String = world.regions[home]._name(str(known.actor))
	return SimInteractionRequests.result("completed", "你记得%s当时说：\n%s" % [name, str(known.details.text)], process)


static func latest(world: RefCounted, listener: String) -> Dictionary:
	var home: String = world.services.actor_home(listener)
	if home.is_empty():
		return {}
	var found: Dictionary = {}
	var last_tick: int = -1
	for scope: String in [home, "services"]:
		var memory: SimSocialMemory = _ledger(world, scope)
		for known: Dictionary in memory.knowledge[listener].values():
			if known.kind == KIND and known.target == listener and int(known.tick) >= last_tick:
				last_tick = int(known.tick)
				found = {"domain": "conversation", "id": scope + ":" + str(known.id), "performer": world.embodiment.subject_for_actor(str(known.actor))}
	return found


static func _ledger(world: RefCounted, scope: String) -> SimSocialMemory:
	if scope == "services":
		return world.services.social
	return world.regions[scope].social if world.regions.has(scope) else null


static func valid_history(memory: SimSocialMemory, rules: Dictionary, now: int) -> bool:
	var used: Dictionary = {}
	for event: Dictionary in memory.events:
		if event.kind != KIND:
			continue
		if event.actor == event.target or event.target.is_empty() or not event.witnesses.is_empty() or event.tick > now or not Shape.keys(event.details, ["participants", "private"]) or not Shape.keys(event.details.participants, ["topic", "claims", "text"]) or not Shape.keys(event.details.private, ["decision"]):
			return false
		var details: Dictionary = event.details.participants
		if not rules.topics.has(details.topic) or not details.claims is Array:
			return false
		# New available statements never add words to an older utterance. Validate
		# its recorded subset against the original decision, not current abilities.
		var seen: Dictionary = {}
		for id: Variant in details.claims:
			if not id is String or not rules.statements.has(id) or seen.has(id):
				return false
			seen[id] = true
		if details.text != _quote(details.claims, rules):
			return false
		var key: Variant = event.details.private.decision
		if not key is String or used.has(key):
			return false
		var decision: Dictionary = {}
		for entry: Dictionary in memory.requests.values():
			if entry.id == key:
				decision = entry
		if decision.get("task") != TASK or decision.get("status") != "accepted" or decision.get("requester") != event.target or decision.get("responder") != event.actor or decision.get("tick") != event.tick or not Shape.same_record(decision.context.terms, {"topic": details.topic, "claims": details.claims}):
			return false
		used[key] = true
	for decision: Dictionary in memory.requests.values():
		if decision.task == TASK and decision.status == "accepted" and not used.has(decision.id):
			return false
	return true
