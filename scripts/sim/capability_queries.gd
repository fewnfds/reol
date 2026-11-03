class_name SimCapabilityQueries
extends RefCounted
## A disposable view of one's own original evidence, never a learned-state owner.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const NODE_IDS: Array[String] = ["sword", "qi_bolt", "qi_guard", "stone_channeling", "heat_methods", "record_steps", "mobile_guard"]
const NODE_KINDS: Array[String] = ["combat", "combat", "combat", "foundation", "versioned_method", "written_steps", "practice"]


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "nodes", "edges"]) or not Shape.count(data.version, 1, 1) or not Shape.keys(data.nodes, NODE_IDS) or not data.edges is Array:
		return false
	for index: int in NODE_IDS.size():
		var node: Variant = data.nodes[NODE_IDS[index]]
		if not Shape.keys(node, ["label", "kind", "summary"]) or not SimInventory._nonempty(node.label) or not SimInventory._nonempty(node.summary) or node.kind != NODE_KINDS[index]:
			return false
	var seen: Dictionary = {}
	for value: Variant in data.edges:
		if not Shape.keys(value, ["from", "to", "kind", "label"]) or not NODE_IDS.has(value.from) or not NODE_IDS.has(value.to) or value.from == value.to or value.kind not in ["requirement", "records", "combination"] or not SimInventory._nonempty(value.label):
			return false
		var key: String = str(value.from) + ":" + str(value.to) + ":" + str(value.kind)
		if seen.has(key):
			return false
		seen[key] = true
	return true


static func project(world: RefCounted, actor: String, requested_actor: String = "") -> Dictionary:
	# Checking the requested identity precedes all opponent-domain reads. This
	# first view has no hearsay inspector for another person's private skills.
	var result: Dictionary = {"allowed": false, "actor": actor, "at_ms": -1, "line": "这里只回顾本人亲历的本领，尚不能查看别人的私有学习记录。", "nodes": [], "edges": []}
	if world == null or not requested_actor.is_empty() and requested_actor != actor:
		return result
	var person: Dictionary = _body(world, actor)
	if person.is_empty() or world.get("_content") == null:
		result.line = "这套小网目前只支持原地面人身的亲历；其他形体尚无适配展示。"
		return result
	var definitions: Dictionary = world._content.get("capability_network") if world._content.get("capability_network") is Dictionary else {}
	if not valid_definitions(definitions):
		result.line = "本领目录尚未就绪。"
		return result
	var nodes: Array[Dictionary] = []
	for id: String in NODE_IDS:
		var node: Dictionary = _node(id, definitions.nodes[id])
		match id:
			"sword", "qi_bolt", "qi_guard": _combat(world, actor, id, node)
			"stone_channeling": _stone(world, actor, node)
			"heat_methods": _heat(world, actor, node)
			"record_steps": _records(world, actor, node)
			"mobile_guard": _mobile(world, actor, node)
		nodes.append(node)
	result.allowed = true
	result.at_ms = int(world.elapsed_ms)
	result.line = "只据本人经历与有来源的记忆回顾；读过、拟过和练成分别成立。"
	result.nodes = nodes
	result.edges = definitions.edges.duplicate(true)
	return result


static func _node(id: String, definition: Dictionary) -> Dictionary:
	var sources: Array[Dictionary] = []
	var instances: Array[Dictionary] = []
	var actions: Array[Dictionary] = []
	var missing: Array[String] = []
	return {"id": id, "label": str(definition.label), "kind": str(definition.kind), "state": "unknown", "line": str(definition.summary), "sources": sources, "instances": instances, "actions": actions, "missing": missing}


static func _source(kind: String, domain: String, id: String, at_ms: int, actor: String, source: String = "", object_id: String = "") -> Dictionary:
	# -1 is deliberate: opening backgrounds have no recorded historical date.
	return {"kind": kind, "domain": domain, "id": id, "at_ms": at_ms, "actor": actor, "source": source, "object": object_id}


static func _action(verb: String, label: String, object_id: String = "", content_id: String = "", missing: Array = []) -> Dictionary:
	return {"id": verb + ":" + object_id + ":" + content_id, "verb": verb, "label": label, "object": object_id, "content_id": content_id, "enabled": missing.is_empty(), "line": "眼下可尝试；真正行动仍由原规则复核。" if missing.is_empty() else "；".join(missing)}


static func _combat(world: RefCounted, actor: String, method: String, node: Dictionary) -> void:
	var conflicts: RefCounted = world.get("conflicts")
	if conflicts == null:
		node.missing.append("这处世界尚未接入原交锋手段。")
		return
	var person: Dictionary = _body(world, actor)
	var definition: String = str(person.definition_id)
	if conflicts.rules.backgrounds.get(definition, []).has(method):
		node.sources.append(_source("background", "conflicts", definition + ":" + method, -1, actor, definition))
	for lesson: Dictionary in conflicts.lessons.values():
		if lesson.pupil == actor and lesson.status == "completed" and int(lesson.finished_ms) <= int(world.elapsed_ms) and lesson.methods.has(method):
			node.sources.append(_source("lesson", "conflicts", str(lesson.id), int(lesson.finished_ms), actor, str(lesson.teacher)))
	var known: bool = not node.sources.is_empty()
	node.state = "learned" if known else "unknown"
	if not known:
		node.missing.append("尚未亲自学会；须实际向近处愿意的人请教。")
	else:
		node.missing.assign(_combat_missing(world, actor, method))
	node.actions.append(_action("cast", "在原交锋中施展" + str(node.label), "", method, node.missing))


static func _combat_missing(world: RefCounted, actor: String, method: String) -> Array[String]:
	var missing: Array[String] = []
	var conflicts: RefCounted = world.conflicts
	var person: Dictionary = _body(world, actor)
	var spec: Dictionary = conflicts.rules.methods[method]
	if conflicts.conflict_for(actor).is_empty():
		missing.append("尚未处于已表明敌意的原交锋。")
	if not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion"):
		missing.append("眼下无法自行支配行动和走位。")
	if conflicts.action_blocks(actor) or world.body_action_owns(actor, &"conflicts") or not person.active.is_empty():
		missing.append("先结束当前动作、反应间歇或其他身体事务。")
	if world.health != null and not world.health.can_fight(actor):
		missing.append("眼下伤势不宜继续交手。")
	if method != "sword" and world.health != null and world.health.blocks_channeling(actor):
		missing.append("经脉灼涩，暂不能运气施术。")
	if method == "sword" and world.artifacts.held_weapon(actor).is_empty():
		missing.append("手中尚无实际保管的可用木剑。")
	if int(person.qi) < int(spec.qi):
		missing.append("本人眼下灵气不足。")
	if int(person.stamina) < int(spec.stamina):
		missing.append("本人眼下体力不足。")
	if method == "qi_guard" and conflicts.barriers.has(actor):
		missing.append("原护障尚未散去，不能叠成新容量。")
	return missing


static func _stone(world: RefCounted, actor: String, node: Dictionary) -> void:
	var artifacts: RefCounted = world.get("artifacts")
	if artifacts == null:
		node.missing.append("这处世界尚无可回顾的温石经历。")
		return
	var subject: String = world.embodiment.subject_for_actor(actor)
	var learned: bool = false
	for background: String in artifacts.experiences.get(subject, []):
		if artifacts.definitions.backgrounds[background].practice == "warm_stone_control":
			node.sources.append(_source("opening_experience", "artifacts", background, -1, actor, background))
			learned = true
	for event: Dictionary in artifacts.events:
		if int(event.at_ms) > int(world.elapsed_ms) or not _thermal(artifacts, str(event.object)):
			continue
		if event.actor == actor and (event.kind == "studied" or event.kind == "charged" and event.get("method", {}).get("mode") == "learn"):
			var guide: String = str(event.get("method", {}).get("guide", ""))
			node.sources.append(_source("artifact_event", "artifacts", str(event.id), int(event.at_ms), actor, actor if guide.is_empty() else guide, str(event.object)))
			learned = true
		elif event.recipient == actor and event.kind == "studied":
			node.sources.append(_source("reported", "artifacts", str(event.id), int(event.at_ms), actor, str(event.actor), str(event.object)))
	if world.get("soul_vessels") != null:
		for event: Dictionary in world.soul_vessels.events:
			if event.actor == actor and event.kind == "guide" and int(event.at_ms) <= int(world.elapsed_ms) and _thermal(artifacts, str(event.target)):
				node.sources.append(_source("guided_practice", "soul_vessels", str(event.id), int(event.at_ms), actor, str(event.soul), str(event.target)))
				learned = true
	node.state = "learned" if learned else "reported" if not node.sources.is_empty() else "unknown"
	if not learned:
		node.missing.append("本人尚无亲手掌握引流的经历；听人说明不等于会用。")
	var ready_objects: Array[String] = _known_stones(world, actor)
	if ready_objects.is_empty():
		node.missing.append("眼下没有本人认得且可接近的温石。")
	for object_id: String in ready_objects:
		var missing: Array[String] = _artifact_missing(world, actor, object_id, int(artifacts.definitions.verbs.study.qi))
		if not learned:
			node.actions.append(_action("study", "亲自循纹探查", object_id, "", missing))
		else:
			node.actions.append(_action("inspect_artifact", "在原器物页选择引流用途", object_id, "", _artifact_missing(world, actor, object_id, 0)))


static func _heat(world: RefCounted, actor: String, node: Dictionary) -> void:
	var methods: RefCounted = world.get("heat_methods")
	if methods == null:
		return
	var subject: String = world.embodiment.subject_for_actor(actor)
	for id: String in _sorted(methods.methods):
		var method: Dictionary = methods.methods[id]
		var sources: Array[Dictionary] = []
		var own_draft: bool = method.creator == subject and int(method.created_ms) <= int(world.elapsed_ms)
		if own_draft:
			sources.append(_source("method_draft", "heat_methods", id, int(method.created_ms), actor, actor))
		var practiced: bool = false
		for event: Dictionary in world.artifacts.events:
			if event.actor == actor and event.kind in ["charged", "overcharged"] and int(event.at_ms) <= int(world.elapsed_ms) and event.get("method", {}).get("id") == id:
				var guide: String = str(event.method.get("guide", ""))
				sources.append(_source("artifact_event", "artifacts", str(event.id), int(event.at_ms), actor, actor if guide.is_empty() else guide, str(event.object)))
				practiced = true
		var read: bool = false
		for event: Dictionary in world.method_records.events:
			if event.actor == actor and event.verb == "read" and event.outcome == "completed" and int(event.finished_ms) <= int(world.elapsed_ms) and event.method == id:
				sources.append(_source("record_read", "method_records", str(event.id), int(event.finished_ms), actor, str(event.object), str(event.object)))
				read = true
		if sources.is_empty():
			continue
		var instance: Dictionary = _instance("heat_methods:" + id, methods.label(id), "versioned_method", id, "")
		instance.sources = sources
		instance.state = "learned" if practiced else "read" if read else "draft"
		instance.line = "已亲手验证这一版的实际结果；后续修订仍须另学。" if practiced else "本人实际读过这一版步骤，尚未亲手验证。" if read else "这是本人拟定的草案，尚未被成功试验验证。"
		var stones: Array[String] = _known_stones(world, actor)
		if stones.is_empty():
			instance.missing.append("先实际取得能亲手操作的温石。")
		for object_id: String in stones:
			var missing: Array[String] = _artifact_missing(world, actor, object_id, int(methods.terms(id).qi))
			if not methods.base_known_from(actor, object_id, int(world.elapsed_ms)):
				missing.append("先亲自学会这类温石的引流基础。")
			var mode: String = "use" if practiced else "record" if read else "trial"
			instance.actions.append(_action("heat_method:" + mode, "实际温养这一版", object_id, id, missing))
		node.instances.append(instance)
		node.sources.append_array(sources)
	if node.instances.is_empty():
		node.missing.append("本人尚无拟定、阅读或亲手实践过的具体版本。")
	else:
		node.state = "known_versions"


static func _records(world: RefCounted, actor: String, node: Dictionary) -> void:
	var records: RefCounted = world.get("method_records")
	if records == null:
		return
	# Only personal reading or current possession reveals an instance here.
	# Merely seeing somebody else's unread carrier grants no recipe title.
	var own: Dictionary = {}
	for event: Dictionary in records.events:
		if event.actor == actor and event.verb == "read" and event.outcome == "completed" and int(event.finished_ms) <= int(world.elapsed_ms):
			if not own.has(event.object):
				own[event.object] = []
			own[event.object].append(event)
	for id: String in _sorted(records.objects):
		if records.held(actor, id) and not own.has(id):
			own[id] = []
	for id: String in _sorted(own):
		var reads: Array = own[id]
		var content_id: String = str(reads[0].method) if not reads.is_empty() else ""
		var label: String = world.heat_methods.label(content_id) if not content_id.is_empty() else "尚未读过的木牍"
		var instance: Dictionary = _instance("record_steps:" + id, label, "written_steps", content_id, id)
		instance.state = "read" if not reads.is_empty() else "held_unread"
		instance.line = "本人实际读完过这份记录；原记录后来被带走也不抹去经历。" if not reads.is_empty() else "木牍正在本人行囊中，尚不能凭持有知道步骤。"
		for event: Dictionary in reads:
			instance.sources.append(_source("record_read", "method_records", str(event.id), int(event.finished_ms), actor, id, id))
		if reads.is_empty():
			var missing: Array[String] = _idle_missing(world, actor)
			if not records.accessible(actor, id):
				missing.append("先实际接近且获得这份记录的操作条件。")
			if records._reserved(id):
				missing.append("这份记录正在原过程中使用。")
			instance.actions.append(_action("read", "亲自阅读这份木牍", id, "", missing))
		node.instances.append(instance)
		node.sources.append_array(instance.sources)
	if node.instances.is_empty():
		node.missing.append("本人尚无实际读过或持有的记录。")
	else:
		node.state = "read" if not node.sources.is_empty() else "held_unread"


static func _mobile(world: RefCounted, actor: String, node: Dictionary) -> void:
	var practice: RefCounted = world.get("capability_practice")
	if practice == null:
		node.missing.append("行步练气过程尚未接入。")
		return
	var proof: Dictionary = practice.learned_record(actor, "mobile_guard", int(world.elapsed_ms))
	if not proof.is_empty():
		node.state = "learned"
		node.sources.append(_source("practice", "capability_practice", str(proof.id), int(proof.finished_ms), actor, actor))
		node.line = "本人实际完成过行步练气；原护障动作内可有限缓步，其他出招和反应锁照旧。"
		return
	var status: Dictionary = practice.status(actor)
	if bool(status.active):
		node.state = "practicing"
		node.line = str(status.line)
		node.actions.append(_action("cancel_practice", "中断练习，保留已付代价", "", str(status.id)))
		return
	var reason: String = practice.readiness(actor, "mobile_guard")
	if not reason.is_empty():
		node.missing.append(reason)
	node.state = "can_practice" if reason.is_empty() else "conditions_missing"
	node.actions.append(_action("practice", "实际练习行气护身", "", "mobile_guard", node.missing))


static func _instance(id: String, label: String, kind: String, content_id: String, object_id: String) -> Dictionary:
	var row: Dictionary = _node(id, {"label": label, "kind": kind, "summary": ""})
	row["content_id"] = content_id
	row["object"] = object_id
	return row


static func _known_stones(world: RefCounted, actor: String) -> Array[String]:
	var result: Array[String] = []
	for id: String in _sorted(world.artifacts.objects):
		if not _thermal(world.artifacts, id) or not world.artifacts.can_see(actor, id):
			continue
		var item: Dictionary = world.artifacts.objects[id]
		if not str(item.container).begins_with("actor:") or item.container == "actor:" + actor:
			result.append(id)
	return result


static func _artifact_missing(world: RefCounted, actor: String, id: String, qi: int) -> Array[String]:
	var missing: Array[String] = _idle_missing(world, actor)
	if not world.artifacts._near(actor, id):
		missing.append("先实际走到能操作器物的近处。")
	var object_busy: bool = false
	for job: Dictionary in world.artifacts.active.values():
		object_busy = object_busy or job.object == id
	if object_busy or world.soul_vessels != null and world.soul_vessels.target_in_use(id) or world.spirit_sources != null and world.spirit_sources.target_in_use(id):
		missing.append("这件温石正在原过程中使用。")
	if int(_body(world, actor).qi) < qi:
		missing.append("本人眼下灵气不足以完成这次尝试。")
	if world.health != null and world.health.blocks_channeling(actor):
		missing.append("经脉灼涩，暂不宜催动引流。")
	return missing


static func _idle_missing(world: RefCounted, actor: String) -> Array[String]:
	var result: Array[String] = []
	var person: Dictionary = _body(world, actor)
	if world.elapsed_ms != world.target_ms:
		result.append("先等世界事务接续到眼下。")
	if not bool(person.alive) or not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion"):
		result.append("眼下不能自行支配这具身体。")
	if not person.active.is_empty() or world.body_action_owns(actor):
		result.append("先完成或明确中断手头的身体事务。")
	return result


static func _thermal(artifacts: RefCounted, id: String) -> bool:
	return artifacts.objects.has(id) and artifacts.objects[id].definition == "warm_stone"


static func _body(world: RefCounted, actor: String) -> Dictionary:
	for sim: VillageSimulation in world.regions.values():
		if sim.actors.has(actor):
			return sim.actors[actor]
	return {}


static func _sorted(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for id: String in values:
		result.append(id)
	result.sort()
	return result
