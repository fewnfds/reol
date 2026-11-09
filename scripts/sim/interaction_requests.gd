class_name SimInteractionRequests
extends RefCounted
## Stateless intent boundary. Jobs, consent, evidence and costs stay in domains.

const VERBS: Array[String] = ["ask_harvest","examine", "study", "fetch_herb", "trade", "watch_supply", "withdraw_work", "offer_food", "accept_labor", "claim_wage", "converse", "diagnose", "treat", "site_arrangement", "borrow_source", "verify_return", "explain_source", "ask_source_care", "withdraw_source_care", "field_clue", "private_exchange"]
const STATUSES: Array[String] = ["invalid", "unheard", "not_understood", "incapable", "unavailable", "refused", "started", "pending", "completed", "unconfirmed", "cancelled"]


static func valid_definitions(data: Variant) -> bool:
	if not data is Dictionary or not SimEmbodiment._keys(data, ["version", "communication_cells", "media", "human_media", "bird_media", "verbs", "status_labels"]) or data.version != 1:
		return false
	if not SimInventory._valid_count(data.communication_cells, false) or not data.media is Dictionary or not SimEmbodiment._keys(data.media, ["spoken", "gesture"]):
		return false
	for value: Variant in data.media.values():
		if not SimInventory._nonempty(value):
			return false
	for field: String in ["human_media", "bird_media"]:
		if not SimEmbodiment._unique_texts(data[field]) or data[field].is_empty():
			return false
		for medium: String in data[field]:
			if not data.media.has(medium):
				return false
	if not data.verbs is Dictionary or not SimEmbodiment._keys(data.verbs, VERBS) or not data.status_labels is Dictionary or not SimEmbodiment._keys(data.status_labels, STATUSES):
		return false
	for verb: String in VERBS:
		var entry: Variant = data.verbs[verb]
		if not entry is Dictionary or not SimEmbodiment._keys(entry, ["label", "object_kind", "bird_understands"]) or not SimInventory._nonempty(entry.label) or not entry.bird_understands is bool:
			return false
		var kind: String = {"ask_harvest": "plant", "private_exchange": "private_artifact", "field_clue": "field_question", "trade": "trade_offer", "fetch_herb": "avian_site", "watch_supply": "work_plan", "withdraw_work": "work_agreement", "offer_food": "provisions", "accept_labor": "labor_offer", "claim_wage": "labor_contract", "converse": "conversation_topic", "diagnose": "body", "treat": "body", "site_arrangement": "site_case", "borrow_source": "source_offer", "verify_return": "source_note", "explain_source": "care_basis", "ask_source_care": "care_arrangement", "withdraw_source_care": "care_arrangement"}.get(verb, "artifact")
		if entry.object_kind != kind:
			return false
	for value: Variant in data.status_labels.values():
		if not SimInventory._nonempty(value):
			return false
	return true


static func submit(world: RefCounted, intent: Dictionary) -> Dictionary:
	if world == null or not _valid_intent(world, intent):
		return result("invalid", "还没说明清楚要向谁、用什么方式、对哪件东西提出什么要求。")
	if intent.verb != "trade" and not intent.conditions.is_empty():
		return result("invalid", "这次还不能约定额外条款，请先当面商量这一件事。")
	if intent.verb == "trade" and not SimEmbodiment._keys(intent.conditions, ["lots"]):
		return result("invalid", "本次买卖只约定整数份数，不能私改常备价或附加其他条款。")
	if world.elapsed_ms != world.target_ms:
		return result("unavailable", "世界事务仍在接续，请稍后再提出请求。")
	var sender: Dictionary = _resolve(world, str(intent.sender))
	var receiver: Dictionary = _resolve(world, str(intent.receiver))
	if sender.is_empty() or receiver.is_empty() or intent.sender == intent.receiver or sender.kind != "human":
		return result("invalid", "这副身体还没有这样向对方表达请求的办法。")
	var actor: String = str(sender.id)
	if not world.actor_controls(actor, "communication"):
		return result("unheard", "眼下无法支配自己的声音或手势。")
	if not _known_object(world, actor, intent.object, str(receiver.id) if receiver.kind == "human" else ""):
		return result("unheard", "先看清要谈的东西；不能向对方指认自己眼下找不到的对象。")
	world.synchronize_region(str(sender.region))
	world.synchronize_region(str(receiver.region))
	var person: Dictionary = world.regions[sender.region].actors[actor]
	var target_cell: Vector2i = _receiver_cell(world, receiver)
	var distance: float = SimBodyGeometry.contact_distance(SimRouteTravel.point(person), world.large_bodies.point(str(receiver.id)), world.large_bodies.size()) / float(TileGrid.TILE_SIZE) if receiver.kind == "large" else SimRouteTravel.cell(person.cell).distance_to(target_cell)
	if not bool(person.alive) or distance > float(world._content.interaction_requests.communication_cells):
		return result("unheard", "离得太远，没能把请求传到对方那里。")
	var rules: Dictionary = world._content.interaction_requests
	if receiver.kind == "plant":
		if intent.medium != "spoken" or intent.verb != "ask_harvest" or intent.object.id != receiver.id:
			return result("not_understood", "枝叶收拢，未应允此事。")
		var answer: Dictionary = world.plants.communicate(actor, str(receiver.id), "ask_harvest")
		return result("completed" if answer.ok else "unheard", str(answer.get("line", "草木没有回应。")))
	if receiver.kind == "large":
		if not world.embodiment.controls(str(intent.receiver), SimLargeBodies.carrier_id(str(receiver.id)), "communication"):
			return result("unheard", "山兽没有回应。")
		if intent.medium != "gesture" or intent.verb != "offer_food":
			return result("not_understood", "它只看着你手中的东西，听不懂这一番要求。")
		var fed: Dictionary = world.large_bodies.offer_food(actor, str(receiver.id), str(intent.object.id))
		return result(str(fed.code), str(fed.line), {"domain": "large_bodies", "id": str(fed.id), "performer": str(intent.receiver)} if fed.ok else {})
	if intent.verb == "offer_food":
		return result("incapable", "眼下这套递食手势还没有与对方谈妥交接的办法。")
	if receiver.kind == "bird":
		if not world.avian_life.controls(str(receiver.id), "communication"):
			return result("unheard", "它眼下没有回应你的声音或手势。")
		if not rules.bird_media.has(intent.medium) or not bool(rules.verbs[intent.verb].bird_understands):
			return result("not_understood", "它偏了偏头，没明白这番要求；看见或听见，不等于理解你的意思。")
	else:
		if not world.actor_controls(str(receiver.id), "communication"):
			return result("unheard", "对方眼下无法与你交流。")
		if not rules.human_media.has(intent.medium):
			return result("not_understood", "对方没明白这种表达方式。")
	if intent.verb == "field_clue":
		if receiver.kind != "human":
			return result("incapable", "对方还不能用人的语言说明野外去处。")
		if intent.medium != "spoken":
			return result("not_understood", "光靠比划，没能问清外面的去处。")
		var answer: Dictionary = world.field_opportunities.learn_from(actor, str(receiver.id))
		return result(str(answer.get("code", "completed" if answer.ok else "unavailable")), str(answer.line), answer.get("process", {}))
	if intent.verb == "private_exchange":
		if receiver.kind != "human":
			return result("incapable", "对方还没有当面商量钱物交割的办法。")
		if intent.medium != "spoken":
			return result("not_understood", "须当面说清具体器物和标价，光靠比划没有谈妥交易。")
		var exchange: RefCounted = world.get("private_exchange")
		if exchange == null:
			return result("unavailable", "眼下没有可办理的私人器物交割。")
		var answer: Dictionary = exchange.request(actor, str(receiver.id), str(intent.object.id))
		var exchange_process: Dictionary = {"domain": "private_exchange", "id": str(answer.id), "performer": str(intent.receiver)} if answer.ok else {}
		return result(str(answer.code), str(answer.line), exchange_process)
	if intent.verb in ["explain_source", "ask_source_care", "withdraw_source_care"]:
		if receiver.kind != "human":
			return result("incapable", "对方还不能用人的语言商量看护与借源依据。")
		if intent.medium != "spoken":
			return result("not_understood", "须当面说清谁作了什么安排，光比划不足以说明。")
		var care: RefCounted = world.get("source_care")
		if care == null:
			return result("unavailable", "当地还没有这项看护安排。")
		var answer: Dictionary
		if intent.verb == "explain_source":
			answer = care.explain(actor, str(receiver.id), str(intent.object.id))
		elif intent.verb == "ask_source_care":
			answer = care.inquire(actor, str(receiver.id), str(intent.object.id))
		else:
			answer = care.withdraw(actor, str(receiver.id), str(intent.object.id))
		return result(str(answer.code), str(answer.line), answer.get("process", {}))
	if intent.verb in ["site_arrangement", "borrow_source", "verify_return"]:
		if receiver.kind != "human":
			return result("incapable", "这项公源安排需要指定任职的人当面办理。")
		if intent.medium != "spoken":
			return result("not_understood", "光靠指点，没能说清这次公源借用或归还的具体条款。")
		var affairs: RefCounted = world.get("site_affairs")
		if affairs == null:
			return result("unavailable", "这里还没有这种公源借用安排。")
		var answer: Dictionary
		if intent.verb == "site_arrangement":
			answer = affairs.announce(actor, str(receiver.id), str(intent.object.id))
		elif intent.verb == "borrow_source":
			answer = affairs.request_loan(actor, str(receiver.id), str(intent.object.id))
		else:
			answer = affairs.request_return(actor, str(receiver.id), str(intent.object.id))
		return result(str(answer.code), str(answer.line), answer.get("process", {}))
	if intent.verb in ["diagnose", "treat"]:
		if receiver.kind != "human":
			return result("incapable", "对方还没有用这副身体查看和处理人身不适的办法。")
		var medical: Dictionary = world.health.request(actor, str(receiver.id), str(intent.verb))
		var medical_process: Dictionary = {"domain": "health", "id": str(medical.id), "performer": str(intent.receiver)} if medical.ok else {}
		return result(str(medical.code), str(medical.line), medical_process)
	if intent.verb == "converse":
		if intent.medium != "spoken":
			return result("not_understood", "光靠比划，没能问清对方的经历与门路。")
		return SimCapabilityConversation.ask(world, actor, str(receiver.id), str(intent.object.id))
	if intent.verb in ["watch_supply", "withdraw_work"]:
		if receiver.kind != "human" or sender.region != receiver.region:
			return result("incapable", "这项安排需要同一聚落里能自行商量的同伴。")
		var answer: Dictionary
		if intent.verb == "watch_supply":
			answer = world.standing_work.ask(str(sender.region), actor, str(receiver.id), str(intent.object.id))
		else:
			var note: Dictionary = world.standing_work.entries[str(intent.object.id)]
			if note.requester != actor or note.responder != receiver.id:
				return result("invalid", "需要向原来答应这项安排的人当面说清楚。")
			answer = world.standing_work.withdraw(str(note.id), actor)
		var reference: Dictionary = {} if str(answer.id).is_empty() else {"domain": "standing_work", "id": answer.id, "performer": str(intent.receiver)}
		return result("completed" if intent.verb == "withdraw_work" and answer.ok else str(answer.code), str(answer.line), reference)
	if intent.verb in ["accept_labor", "claim_wage"]:
		if receiver.kind != "human" or sender.region != receiver.region:
			return result("incapable", "这项现金差事需要当地有任职权限的人当面办理。")
		var labor: Dictionary = world.budgeted_labor.accept(actor, str(receiver.region), str(receiver.id), str(intent.object.id)) if intent.verb == "accept_labor" else world.budgeted_labor.request_claim(actor, str(intent.object.id), str(receiver.id))
		var domain: String = "budgeted_labor" if intent.verb == "accept_labor" else "services"
		var process: Dictionary = {"domain": domain, "id": str(labor.id), "performer": str(intent.receiver)} if labor.ok else {}
		return result("started" if labor.ok else "refused", str(labor.line), process)
	if intent.verb == "trade":
		var quoted: Dictionary = world.services._trade.authorize(actor, str(receiver.region), str(receiver.id), str(intent.object.id), intent.conditions.lots)
		var status: String = "started" if quoted.ok else "incapable" if quoted.reason == "no_authority" else "invalid" if quoted.reason == "invalid_terms" else "unavailable"
		var trade_process: Dictionary = {"domain": "services", "id": str(quoted.id), "performer": str(intent.receiver)} if quoted.ok else {}
		return result(status, "对方按常备条件签下本次办理；先到交货点清点，现场缺钱缺货仍会中止。" if quoted.ok else str(quoted.line), trade_process)
	if intent.verb == "fetch_herb":
		var site_id: String = str(intent.object.id)
		var birds: SimAvianLife = world.avian_life
		if not birds.sites.has(site_id) or birds.sites[site_id].type != "crevice":
			return result("invalid", "这不是一处可以指认取药的石隙。")
		var carrier: String = world.embodiment.residence_of(str(intent.receiver))
		if not birds.can_enter(carrier, site_id):
			return result("incapable", "这副身形伸不进那道狭口；没有合适工具，光是答应也取不到药。")
		if receiver.kind != "bird":
			return result("incapable", "对方还没有用这副身体在这里取药的办法。")
		var bird_reply: Dictionary = birds.ask_herb(actor, str(receiver.id), site_id)
		var bird_process: Dictionary = {}
		if bool(bird_reply.ok):
			bird_process = {"domain": "avian", "id": str(birds.events.back().id), "performer": str(intent.receiver)}
		return _wrap(bird_reply, bird_process)
	var reply: Dictionary = world.artifacts.request_check(actor, str(receiver.id), str(intent.verb), str(intent.object.id))
	var process: Dictionary = {}
	if bool(reply.ok):
		process = {"domain": "artifacts", "id": str(world.artifacts.active[receiver.id].id), "performer": str(intent.receiver)}
	return _wrap(reply, process)


static func pending(world: RefCounted, subject: String) -> Array[Dictionary]:
	var processes: Array[Dictionary] = []
	var sender: Dictionary = _resolve(world, subject)
	if sender.is_empty() or sender.kind != "human":
		return processes
	var active_exchanges: Array[Dictionary] = []
	var exchange: RefCounted = world.get("private_exchange")
	if exchange != null:
		for process: Dictionary in exchange.pending(str(sender.id)):
			if exchange.observe(str(sender.id), process).status == "pending":
				active_exchanges.append(process)
			else:
				processes.append(process)
	for note: Dictionary in world.standing_work.entries.values():
		if note.requester == sender.id and note.status != "refused" and world.elapsed_ms < int(note.until_ms):
			processes.append({"domain": "standing_work", "id": str(note.id), "performer": world.embodiment.subject_for_actor(str(note.responder))})
	for note: Dictionary in world.budgeted_labor.contracts.values():
		if note.actor == sender.id and note.status in ["working", "paused", "payable"]:
			processes.append({"domain": "budgeted_labor", "id": str(note.id), "performer": world.embodiment.subject_for_actor(str(note.issuer))})
	var affairs: RefCounted = world.get("site_affairs")
	if affairs != null:
		processes.append_array(affairs.pending(str(sender.id)))
	var care: RefCounted = world.get("source_care")
	if care != null:
		processes.append_array(care.pending(str(sender.id)))
	if world.services != null and world.services.active_jobs.has(sender.id):
		var job: Dictionary = world.services.jobs[world.services.active_jobs[sender.id]]
		if job.kind in ["trade", "claim_wage"]:
			processes.append({"domain": "services", "id": str(job.id), "performer": world.embodiment.subject_for_actor(str(job.options.issuer))})
	for job: Dictionary in world.artifacts.active.values():
		if job.recipient == sender.id:
			processes.append({"domain": "artifacts", "id": str(job.id), "performer": world.embodiment.subject_for_actor(str(job.actor))})
	for bird_id: String in world.avian_life.birds:
		if world.avian_life.birds[bird_id].errand.get("requester") != sender.id:
			continue
		for index: int in range(world.avian_life.events.size() - 1, -1, -1):
			var event: Dictionary = world.avian_life.events[index]
			if event.bird == bird_id and event.kind == "agreed":
				if event.details.get("actor") == sender.id:
					processes.append({"domain": "avian", "id": str(event.id), "performer": SimAvianLife.subject_id(bird_id)})
				break
	# Prefer the current bodily task over older, still-open arrangements when
	# the request panel reconstructs its last ongoing process after loading.
	processes.append_array(world.health.pending(str(sender.id)))
	processes.append_array(active_exchanges)
	return processes


static func observe(world: RefCounted, subject: String, process: Dictionary) -> Dictionary:
	var sender: Dictionary = _resolve(world, subject)
	if sender.is_empty() or sender.kind != "human" or not SimEmbodiment._keys(process, ["domain", "id", "performer"]):
		return result("unconfirmed", "没有能够核对的后续。")
	if process.domain == "private_exchange":
		var exchange: RefCounted = world.get("private_exchange")
		return exchange.observe(str(sender.id), process) if exchange != null else result("unconfirmed", "本人没有这次私人交割的后续。")
	if process.domain == "source_care":
		var care: RefCounted = world.get("source_care")
		if care == null:
			return result("unconfirmed", "本人没有这项看护后续。")
		var reply: Dictionary = care.observe(str(sender.id), process)
		return reply
	if process.domain == "site_affairs":
		var affairs: RefCounted = world.get("site_affairs")
		if affairs == null:
			return result("unconfirmed", "本人还没有可核对的公源借用后续。")
		# A verifier owns the travelling body; only the domain's original
		# requester, personal evidence and received answer grant this view.
		var reply: Dictionary = affairs.observe(str(sender.id), process)
		return result(str(reply.code), str(reply.line), reply.get("process", process))
	if process.domain == "health":
		return world.health.observe(str(sender.id), process)
	if process.domain == "conversation":
		return SimCapabilityConversation.recall(world, str(sender.id), process)
	if process.domain == "large_bodies":
		for event: Dictionary in world.large_bodies.events:
			if event.id == process.id and event.actor == sender.id and SimLargeBodies.subject_id(str(event.body)) == process.performer:
				return result("completed", "你记得亲手递出了那份饭食；这不代表山兽此后的行动由你支配。", process)
		return result("unconfirmed", "本人没有这次递食的记忆。")
	if process.domain == "budgeted_labor":
		var note: Dictionary = world.budgeted_labor.contracts.get(process.id, {})
		if note.is_empty() or note.actor != sender.id or world.embodiment.subject_for_actor(str(note.issuer)) != process.performer:
			return result("unconfirmed", "这不是本人签下的现金差事。")
		var status: String = "completed" if note.status in ["payable", "paid"] else "cancelled" if note.status in ["cancelled", "expired"] else "pending"
		return result(status, str(world.budgeted_labor.describe(str(sender.id), str(note.id)).line), process)
	if process.domain == "standing_work":
		var note: Dictionary = world.standing_work.entries.get(process.id, {})
		if note.is_empty() or note.requester != sender.id or world.embodiment.subject_for_actor(str(note.responder)) != process.performer:
			return result("unconfirmed", "这不是本人当时商量的安排。")
		var description: Dictionary = world.standing_work.describe(str(sender.id), str(note.id))
		return result(str(description.code), str(description.line), process)
	if process.domain == "services" and world.services != null and world.services.jobs.has(process.id):
		var job: Dictionary = world.services.jobs[process.id]
		if job.kind not in ["trade", "claim_wage"] or job.actor != sender.id or world.embodiment.subject_for_actor(str(job.options.issuer)) != process.performer:
			return result("unconfirmed", "这不是本人获签的那笔买卖。")
		var waiting: String = "仍在前往功德堂或核验交付，工钱尚未入包。" if job.kind == "claim_wage" else "仍在前往交货点或清点，钱货尚未转移。"
		return result("pending" if job.status == "active" else "completed" if job.status == "completed" else "cancelled", waiting if job.status == "active" else str(job.outcome), process)
	if process.domain == "artifacts":
		for job: Dictionary in world.artifacts.active.values():
			if job.id == process.id and job.recipient == sender.id and world.embodiment.subject_for_actor(str(job.actor)) == process.performer:
				if not world.artifacts._near(str(sender.id), str(job.object)):
					return result("unconfirmed", "你已离开，尚未听到对方的后续说明。")
				return result("pending", "对方仍在动手检查；尚未得到结论。", process)
		for event: Dictionary in world.artifacts.events:
			if event.action == process.id and event.recipient == sender.id and event.subject == process.performer:
				var status: String = "completed" if event.kind in ["examined", "studied"] else "cancelled"
				return result(status, world.regions[event.region]._name(str(event.actor)) + "：" + str(event.line), process)
	elif process.domain == "avian":
		var receiver: Dictionary = _resolve(world, str(process.performer))
		if receiver.is_empty() or receiver.kind != "bird":
			return result("unconfirmed", "眼下找不到那个身影。")
		var found: bool = false
		var latest: String = ""
		for event: Dictionary in world.avian_life.events:
			if event.bird == receiver.id and event.kind == "agreed":
				latest = str(event.id)
			if event.id == process.id and event.bird == receiver.id and event.kind == "agreed" and event.details.get("actor") == sender.id:
				found = true
		if found and world.avian_life.visible_to(str(sender.id), str(receiver.id)):
			if latest == process.id and world.avian_life.birds[receiver.id].errand.get("requester") == sender.id:
				return result("pending", str(world.avian_life.describe(str(sender.id), str(receiver.id)).line), process)
			return result("unconfirmed", "它已停下这趟奔波；药是否交到，仍需亲自去药圃确认。", process)
	return result("unconfirmed", "尚未当面确认结果；答应过不等于你已经知道事情办成了。", process)


static func _valid_intent(world: RefCounted, intent: Dictionary) -> bool:
	if not SimEmbodiment._keys(intent, ["sender", "receiver", "verb", "object", "medium", "conditions"]):
		return false
	for field: String in ["sender", "receiver", "verb", "medium"]:
		if not SimInventory._nonempty(intent[field]):
			return false
	if not intent.conditions is Dictionary or not intent.object is Dictionary or not SimEmbodiment._keys(intent.object, ["kind", "id"]):
		return false
	var rules: Dictionary = world._content.interaction_requests
	return rules.verbs.has(intent.verb) and rules.media.has(intent.medium) and intent.object.kind == rules.verbs[intent.verb].object_kind and SimInventory._nonempty(intent.object.id)


static func _known_object(world: RefCounted, actor: String, object: Dictionary, receiver: String = "") -> bool:
	if object.kind == "plant":
		if world.plants == null or not world.plants.bodies.has(object.id):
			return false
		var region: String = str(world.plants.bodies[object.id].region)
		return world.regions[region].actors.has(actor) and SimRouteTravel.cell(world.regions[region].actors[actor].cell).distance_to(world.plants.cell_of(object.id)) <= float(world.regions[region].config.observation_radius)
	if object.kind == "private_artifact":
		var exchange: RefCounted = world.get("private_exchange")
		if exchange == null or receiver.is_empty():
			return false
		for choice: Dictionary in exchange.offered_objects(actor, receiver):
			if choice.id == object.id:
				return true
		return false
	if object.kind == "field_question":
		return object.id == "nearby_ruins"
	if object.kind in ["care_basis", "care_arrangement"]:
		var care: RefCounted = world.get("source_care")
		if care == null:
			return false
		var choices: Array[Dictionary] = care.basis_for(actor, receiver) if object.kind == "care_basis" else care.arrangements_for(actor, receiver)
		for choice: Dictionary in choices:
			if choice.id == object.id:
				return true
		return false
	if object.kind in ["site_case", "source_offer", "source_note"]:
		var affairs: RefCounted = world.get("site_affairs")
		if affairs == null:
			return false
		var choices: Array[Dictionary] = []
		if object.kind == "site_case":
			choices.append_array(affairs.known_cases(actor))
			choices.append_array(affairs.inquiry_cases(actor, receiver))
		elif object.kind == "source_offer":
			choices = affairs.offers_for(actor)
		else:
			choices = affairs.notes_for(actor)
		for choice: Dictionary in choices:
			if choice.id == object.id:
				return true
		return false
	if object.kind == "body":
		return object.id == actor and world.health.eligible(actor)
	if object.kind == "conversation_topic":
		return world._content.capability_conversation.topics.has(object.id)
	if object.kind == "labor_offer":
		return world.budgeted_labor.definitions.offers.has(object.id)
	if object.kind == "labor_contract":
		return world.budgeted_labor.contracts.has(object.id) and world.budgeted_labor.contracts[object.id].actor == actor
	if object.kind == "provisions":
		var home: String = world.artifacts.actor_home(actor)
		return not home.is_empty() and object.id == world.large_bodies.definitions.food and world.regions[home].inventory.available("actor:" + actor, str(object.id)) >= int(world.large_bodies.definitions.food_amount)
	if object.kind == "work_agreement":
		return world.standing_work.entries.has(object.id) and world.standing_work.entries[object.id].requester == actor
	if object.kind == "work_plan":
		if not world.standing_work.definitions.plans.has(object.id):
			return false
		var home: String = world.artifacts.actor_home(actor)
		var sim: VillageSimulation = world.regions[home]
		var place: String = world.standing_work.definitions.plans[object.id].place
		return SimRouteTravel.cell(sim.actors[actor].cell).distance_to(SimRouteTravel.cell(sim.places[place].cell)) <= float(sim.config.observation_radius)
	if object.kind == "trade_offer":
		return world.services != null and world.services.definitions.trade.offers.has(object.id)
	if object.kind == "artifact":
		return world.artifacts.can_see(actor, str(object.id))
	if not world.avian_life.sites.has(object.id):
		return false
	var owner: String = world.artifacts.actor_home(actor)
	var sim: RefCounted = world.regions[owner]
	return bool(sim.actors[actor].alive) and SimRouteTravel.cell(sim.actors[actor].cell).distance_to(SimRouteTravel.cell(world.avian_life.sites[object.id].cell)) <= float(sim.config.observation_radius)


static func _resolve(world: RefCounted, subject: String) -> Dictionary:
	if world.plants != null and subject.begins_with("subject:plant:"):
		var id: String = subject.trim_prefix("subject:plant:")
		if world.plants.bodies.has(id) and world.plants.bodies[id].subject == subject:
			return {"kind": "plant", "id": id, "region": str(world.plants.bodies[id].region)}
	if world.embodiment.residence_of(subject).is_empty():
		return {}
	for region: String in world.regions:
		for actor: String in world.regions[region].actors:
			if world.embodiment.subject_for_actor(actor) == subject:
				return {"kind": "human", "id": actor, "region": region}
	for bird_id: String in world.avian_life.birds:
		if SimAvianLife.subject_id(bird_id) == subject:
			return {"kind": "bird", "id": bird_id, "region": str(world.avian_life.birds[bird_id].region)}
	for id: String in world.large_bodies.bodies:
		if SimLargeBodies.subject_id(id) == subject:
			return {"kind": "large", "id": id, "region": str(world.large_bodies.bodies[id].region)}
	return {}


static func _receiver_cell(world: RefCounted, receiver: Dictionary) -> Vector2i:
	if receiver.kind == "plant":
		return world.plants.cell_of(str(receiver.id))
	if receiver.kind == "large":
		return world.large_bodies.body_cell(str(receiver.id))
	return world.avian_life.body_cell(str(receiver.id)) if receiver.kind == "bird" else SimRouteTravel.cell(world.regions[receiver.region].actors[receiver.id].cell)


static func _wrap(reply: Dictionary, process: Dictionary) -> Dictionary:
	return result("started" if bool(reply.ok) else str(reply.get("code", "unavailable")), str(reply.line), process)


static func result(status: String, line: String, process: Dictionary = {}) -> Dictionary:
	return {"ok": status in ["started", "pending", "completed"], "status": status, "line": line, "process": process.duplicate(true)}
