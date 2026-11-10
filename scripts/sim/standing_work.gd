class_name SimStandingWork
extends RefCounted
## A promise changes the actor's next intention; it never owns their body/jobs.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const NEVER: int = 9007199254740991
var entries: Dictionary = {}
var _by_actor: Dictionary = {}
var definitions: Dictionary = {}
var _owner: WeakRef
var world: RefCounted:
	get:
		return _owner.get_ref()


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "policy", "plans"]) or data.version != 1 or not data.policy is Dictionary or SimSocialMemory.new()._normalized_policy(data.policy).is_empty() or not data.plans is Dictionary or data.plans.is_empty():
		return false
	for id: Variant in data.plans:
		var plan: Variant = data.plans[id]
		if not SimInventory._nonempty(id) or not Shape.keys(plan, ["label", "duty", "place", "minutes"]) or not Shape.count(plan.minutes, 1, 1440):
			return false
		for field: String in ["label", "duty", "place"]:
			if not SimInventory._nonempty(plan[field]):
				return false
	return true


func bind_world(authority: RefCounted) -> void:
	# Rebind a validated candidate without resetting its saved process.
	_owner = weakref(authority)


func initialize(authority: RefCounted, rules: Dictionary) -> bool:
	if authority == null or not valid_definitions(rules):
		return false
	for sim: VillageSimulation in authority.regions.values():
		for plan: Dictionary in rules.plans.values():
			if not sim.config.actions.has(plan.duty) or sim.config.actions[plan.duty].kind != "haul" or sim.config.actions[plan.duty].target != plan.place or not sim.places.has(plan.place):
				return false
	_owner = weakref(authority)
	definitions = rules.duplicate(true)
	entries = {}
	_by_actor = {}
	return true


func ask(region: String, requester: String, responder: String, plan_id: String) -> Dictionary:
	if not world.regions.has(region) or not definitions.plans.has(plan_id):
		return _reply(false, "invalid", "还没有这样的常备安排。")
	world.synchronize_region(region)
	var sim: VillageSimulation = world.regions[region]
	if not sim.has_actor(requester) or not sim.has_actor(responder) or requester == responder or not _can_talk(sim, requester, responder):
		return _reply(false, "unheard", "先走到同一聚落的对方面前，才能商量。")
	var actor: Dictionary = sim.synchronize_actor(responder)
	if not actor.autonomous:
		return _reply(false, "unavailable", "对方的打算需要本人另作选择，不能替他自动答应。")
	if _by_actor.has(responder):
		var prior: Dictionary = entries[_by_actor[responder]]
		if prior.requester == requester and prior.plan == plan_id:
			return _answer(prior)
		return _reply(false, "unavailable", "对方已经答应另一项照看安排，不能把它挤掉。")
	if not world.native_action_allowed(responder):
		return _reply(false, "unavailable", "对方还有已经承担的事，眼下不能另作安排。")
	var plan: Dictionary = definitions.plans[plan_id]
	var duration: int = int(plan.minutes) * 60000
	if world.elapsed_ms > NEVER - duration:
		return _reply(false, "unavailable", "这一时段尚不能安排。")
	var profile: Dictionary = sim.config.actor_profiles[responder]
	var context: Dictionary = {
		"energy": floorf(float(actor.energy) / 20.0) / 5.0,
		"busy": 0.0 if actor.active.is_empty() else 1.0,
		"distance": floorf(sim._distance(requester, responder) / float(sim.config.talk_radius) * 4.0) / 4.0,
		"risk": 0.0, "duty": 1.0 if profile.get("duty") == plan.duty else 0.0,
		"offer": 0.0, "benevolence": float(profile.get("benevolence", 0.5)),
		"reliability": float(sim.social.relation(responder, requester).reliability),
		"affinity": float(sim.social.relation(responder, requester).affinity),
		"terms": {"plan": plan_id, "minutes": int(plan.minutes), "period": floori(float(world.elapsed_ms) / duration)},
	}
	var decision: Dictionary = sim.social.evaluate_request(requester, responder, "standing:" + plan_id, context, definitions.policy, sim._rng, sim.tick_index)
	if not decision.has("id"):
		return _reply(false, "unavailable", "这番安排还没商量清楚。")
	var id: String = "standing:" + region + ":" + str(decision.id)
	if entries.has(id):
		return _answer(entries[id])
	var accepted: bool = decision.status == "accepted"
	var note: Dictionary = {"id": id, "region": region, "requester": requester, "responder": responder, "plan": plan_id,
		"decision": decision.id, "started_ms": world.elapsed_ms, "until_ms": world.elapsed_ms + duration,
		"status": "active" if accepted else "refused", "ended_ms": -1 if accepted else world.elapsed_ms,
		"event": sim.observe("standing_work", requester, responder, {"task": "standing:" + plan_id, "status": decision.status, "participants": {"until_ms": world.elapsed_ms + duration}}), "end_event": ""}
	entries[id] = note
	if accepted:
		_by_actor[responder] = id
		if actor.active.is_empty():
			actor.retry_ms = mini(int(actor.retry_ms), world.elapsed_ms + 1)
		world.invalidate_region(region)
	return _answer(note)


func duty_for(actor: String, at_ms: int) -> String:
	if not _by_actor.has(actor):
		return ""
	var note: Dictionary = entries[_by_actor[actor]]
	return str(definitions.plans[note.plan].duty) if at_ms < int(note.until_ms) else ""


func withdraw(id: String, actor: String) -> Dictionary:
	if not entries.has(id) or not actor in [entries[id].requester, entries[id].responder]:
		return _reply(false, "unheard", "没有本人参与的这项约定。")
	var note: Dictionary = entries[id]
	world.synchronize_region(str(note.region))
	var sim: VillageSimulation = world.regions[note.region]
	if note.status != "active":
		return _reply(false, "cancelled", "这项约定已经结束。", id)
	if not world.actor_controls(actor, "communication") or (actor != note.responder and not _can_talk(sim, actor, str(note.responder))):
		return _reply(false, "unheard", "远处的打算不能遥控取消；需要当面说清楚。", id)
	_close(note, "withdrawn", world.elapsed_ms, actor if actor != note.responder else "")
	return _reply(true, "cancelled", "已说明不再照看新活；正在做的事和受托物资仍按原过程收尾。", id)


func next_boundary_ms() -> int:
	var boundary: int = NEVER
	for id: String in _by_actor.values():
		boundary = mini(boundary, int(entries[id].until_ms))
	return boundary


func settle_at_ms(at_ms: int) -> void:
	for id: String in _by_actor.values().duplicate():
		var note: Dictionary = entries[id]
		if at_ms >= int(note.until_ms):
			world.synchronize_region(str(note.region))
			_close(note, "expired", int(note.until_ms))


func _close(note: Dictionary, status: String, at_ms: int, listener: String = "") -> void:
	note.status = status
	note.ended_ms = at_ms
	var sim: VillageSimulation = world.regions[note.region]
	# The distant requester is not an automatic witness to a private withdrawal.
	note.end_event = sim.observe("standing_work_ended", str(note.responder), listener, {"task": "standing:" + str(note.plan), "status": status})
	_by_actor.erase(note.responder)
	world.invalidate_region(str(note.region))


func _can_talk(sim: VillageSimulation, left: String, right: String) -> bool:
	return world.actor_controls(left, "communication") and world.actor_controls(right, "communication") and sim._distance(left, right) <= float(world._content.interaction_requests.communication_cells)


func _answer(note: Dictionary) -> Dictionary:
	if note.status == "refused":
		return _reply(false, "refused", "对方没有答应这段照看安排；还要顾及自己的体力、职责与看法。", str(note.id))
	if note.status != "active":
		return _reply(false, "cancelled", "这一轮安排已经结束；同样说法不会把旧承诺重新开始。", str(note.id))
	return _reply(true, "started", "对方答应照看这一段供给；会先顾吃饭歇息，再按本人所知检查和干活，期限不会因重复请求延长。", str(note.id))


static func _reply(ok: bool, code: String, line: String, id: String = "") -> Dictionary:
	return {"ok": ok, "code": code, "line": line, "id": id}


static func empty_state() -> Dictionary:
	return {"version": 1, "entries": {}}


func to_dict() -> Dictionary:
	return {"version": 1, "entries": entries.duplicate(true)}


func restore(data: Dictionary) -> bool:
	if not Shape.keys(data, ["version", "entries"]) or data.version != 1 or not data.entries is Dictionary:
		return false
	var actors: Dictionary = {}
	for id: Variant in data.entries:
		var note: Variant = data.entries[id]
		if not Shape.keys(note, ["id", "region", "requester", "responder", "plan", "decision", "started_ms", "until_ms", "status", "ended_ms", "event", "end_event"]) or note.id != id or not world.regions.has(note.region) or not definitions.plans.has(note.plan) or not note.status in ["active", "refused", "expired", "withdrawn"]:
			return false
		var sim: VillageSimulation = world.regions[note.region]
		if not sim.has_actor(note.requester) or not sim.has_actor(note.responder) or note.requester == note.responder or id != "standing:" + str(note.region) + ":" + str(note.decision) or not Shape.count(note.started_ms, 0, world.elapsed_ms) or not Shape.count(note.until_ms, 1, NEVER):
			return false
		var plan: Dictionary = definitions.plans[note.plan]
		if int(note.until_ms) - int(note.started_ms) != int(plan.minutes) * 60000:
			return false
		var decision: Dictionary = {}
		for cached: Dictionary in sim.social.requests.values():
			if cached.id == note.decision:
				decision = cached
		if decision.is_empty() or decision.requester != note.requester or decision.responder != note.responder or decision.task != "standing:" + str(note.plan) or (note.status == "refused") != (decision.status == "refused") or int(decision.tick) != floori(float(note.started_ms) / 60000.0):
			return false
		var terms: Dictionary = {"plan": note.plan, "minutes": int(plan.minutes), "period": floori(float(note.started_ms) / (int(plan.minutes) * 60000))}
		if not Shape.same_record(decision.context.get("terms"), terms) or not Shape.same_record(decision.policy, sim.social._normalized_policy(definitions.policy)):
			return false
		var event: Dictionary = sim.social._event_by_id.get(note.event, {})
		if event.get("kind") != "standing_work" or event.get("actor") != note.requester or event.get("target") != note.responder or event.get("tick") != decision.tick or event.details.get("task") != decision.task or event.details.get("status") != decision.status or event.details.get("participants", {}).get("until_ms") != note.until_ms:
			return false
		if note.status == "active":
			if note.ended_ms != -1 or note.end_event != "" or int(note.until_ms) <= world.elapsed_ms or actors.has(note.responder):
				return false
			actors[note.responder] = id
		elif note.status == "refused":
			if note.ended_ms != note.started_ms or note.end_event != "":
				return false
		else:
			if not Shape.count(note.ended_ms, int(note.started_ms), mini(int(note.until_ms), world.elapsed_ms)) or (note.status == "expired" and note.ended_ms != note.until_ms):
				return false
			var ended: Dictionary = sim.social._event_by_id.get(note.end_event, {})
			var targets: Array = [""] if note.status == "expired" else ["", note.requester]
			if ended.get("kind") != "standing_work_ended" or ended.get("actor") != note.responder or not ended.get("target") in targets or ended.get("tick") != floori(float(note.ended_ms) / 60000.0) or ended.details.get("status") != note.status or ended.details.get("task") != decision.task:
				return false
	for region: String in world.regions:
		var sim: VillageSimulation = world.regions[region]
		for decision: Dictionary in sim.social.requests.values():
			if str(decision.task).begins_with("standing:") and not data.entries.has("standing:" + region + ":" + str(decision.id)):
				return false
	entries = data.entries.duplicate(true)
	_by_actor = actors
	return true


func describe(viewer: String, id: String) -> Dictionary:
	if not entries.has(id) or not viewer in [entries[id].requester, entries[id].responder]:
		return _reply(false, "unconfirmed", "没有本人参与商量的安排。")
	var note: Dictionary = entries[id]
	var sim: VillageSimulation = world.regions[note.region]
	if note.status == "refused":
		return _answer(note)
	if world.elapsed_ms >= int(note.until_ms):
		return _reply(true, "completed", "原定照看时段已过；实际做成了什么，还要到场核对。", id)
	if note.status == "withdrawn" and sim.social.knowledge[viewer].has(note.end_event):
		return _reply(false, "cancelled", "你已经得知对方不再接这项安排的新活；原过程仍正常收尾。", id)
	var other: String = str(note.responder) if viewer == note.requester else str(note.requester)
	if not _can_talk(sim, viewer, other):
		return _reply(false, "unconfirmed", "你记得约定还在期限内，尚未当面核对对方近况。", id)
	var action: Dictionary = sim.synchronize_actor(note.responder).active
	var activity: String = "暂未看见他进行这类劳动；之前做了多少还需核对。"
	if not action.is_empty():
		activity = "你看见他正在" + str(sim.config.actions[action.action].label) + ("，仍在路上。" if action.phase == "travel" else "。")
	return _reply(true, "pending", "原约定尚在期限内；" + activity, id)
