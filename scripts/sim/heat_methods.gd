class_name SimHeatMethods
extends RefCounted
## Immutable recipes only. Practice and knowledge come from original artifact jobs.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const Schema = preload("res://scripts/sim/heat_method_schema.gd")
var definitions: Dictionary = {}
var methods: Dictionary = {}
var next_id: int = 1
var _owner: WeakRef
var world: RefCounted:
	get:
		return _owner.get_ref()


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "artifact_type", "title_length", "flows", "pulses", "pulse_minutes", "safe_flow", "guide_qi", "lesson_risk"]) or data.version != 1 or data.artifact_type != "warm_stone":
		return false
	if not Shape.count(data.title_length, 1, 64) or not Shape.count(data.pulse_minutes, 1, 10) or not Shape.count(data.safe_flow, 1, 3) or not Shape.count(data.guide_qi, 1, 10) or not Shape.keys(data.flows, ["1", "2", "3"]) or not data.pulses is Array or data.pulses.is_empty():
		return false
	if not (data.lesson_risk is int or data.lesson_risk is float) or not is_finite(float(data.lesson_risk)) or data.lesson_risk < 0 or data.lesson_risk > 1:
		return false
	var seen: Dictionary = {}
	for pulse: Variant in data.pulses:
		if not Shape.count(pulse, 1, 10) or seen.has(int(pulse)):
			return false
		seen[int(pulse)] = true
	for value: Variant in data.flows.values():
		if not Shape.keys(value, ["label", "qi", "charge"]) or not SimInventory._nonempty(value.label) or not Shape.count(value.qi, 1, 10) or not Shape.count(value.charge, 1, 20):
			return false
	return true


func bind_world(authority: RefCounted) -> void:
	# Rebind a validated candidate without resetting its saved process.
	_owner = weakref(authority)


func initialize(parent: RefCounted, rules: Dictionary) -> bool:
	if not valid_definitions(rules):
		return false
	_owner = weakref(parent)
	definitions = rules.duplicate(true)
	var pulses: Array[int] = []
	for value: Variant in definitions.pulses:
		pulses.append(int(value))
	definitions.pulses = pulses
	return true


func compose(actor: String, object_id: String, title: String, flow: int, pulses: int, parent: String = "") -> Dictionary:
	var artifacts: RefCounted = world.artifacts
	if world.elapsed_ms != world.target_ms or not artifacts.objects.has(object_id) or artifacts.objects[object_id].definition != definitions.artifact_type or not artifacts.can_see(actor, object_id) or not bool(artifacts.describe(actor, object_id).get("method", false)):
		return reply(false, "先亲自学会这类温石的引流基础，再琢磨调整办法。")
	var subject: String = world.embodiment.subject_for_actor(actor)
	title = title.strip_edges()
	if title.is_empty() or title.length() > int(definitions.title_length) or title.contains("\n") or not definitions.flows.has(str(flow)) or not definitions.pulses.has(pulses):
		return reply(false, "给草案取个简短名字，并选定可尝试的流量与持续时间。")
	if not parent.is_empty() and (not methods.has(parent) or methods[parent].creator != subject):
		return reply(false, "只能在自己的已有草案上保存修订。")
	for id: String in methods:
		if methods[id].creator == subject and methods[id].flow == flow and methods[id].pulses == pulses:
			return reply(true, "这与已有版本的实际步骤相同，仍用原版本；改名不会增添本领。", id)
	var id: String = "heat_method:%d" % next_id
	next_id += 1
	methods[id] = {"creator": subject, "title": title, "flow": flow, "pulses": pulses, "parent": parent,
		"revision": int(methods[parent].revision) + 1 if not parent.is_empty() else 1, "created_ms": world.elapsed_ms}
	return reply(true, "已记下草案；还须实际试验，名字本身不能给石头供热。", id)


func knows(actor: String, id: String) -> bool:
	return known_from(actor, id, world.artifacts.events, world.elapsed_ms)


func known_from(actor: String, id: String, records: Array, at_ms: int) -> bool:
	for event: Variant in records:
		if event is Dictionary and event.get("actor") == actor and event.get("kind") in ["charged", "overcharged"] and event.get("at_ms", at_ms + 1) <= at_ms and event.get("method") is Dictionary and event.method.get("id") == id:
			return true
	return false


func learned_base(actor: String, object_id: String) -> bool:
	if not world.artifacts.objects.has(object_id) or world.artifacts.objects[object_id].definition != definitions.artifact_type:
		return false
	for event: Dictionary in world.artifacts.events:
		if event.actor == actor and event.kind == "charged" and event.get("method", {}).get("mode") == "learn":
			return true
	return false


func base_known_from(actor: String, object_id: String, at_ms: int) -> bool:
	if world.artifacts.Understanding.practiced(world.artifacts, actor, "warm_stone_control"):
		return true
	for event: Dictionary in world.artifacts.events:
		if event.actor != actor or int(event.at_ms) > at_ms:
			continue
		if event.object == object_id and event.kind == "studied" or event.kind == "charged" and event.get("method", {}).get("mode") == "learn":
			return true
	for event: Dictionary in world.soul_vessels.events:
		if event.actor == actor and event.target == object_id and event.kind == "guide" and int(event.at_ms) <= at_ms:
			return true
	return false


func visible_methods(actor: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var subject: String = world.embodiment.subject_for_actor(actor)
	for id: String in methods:
		if methods[id].creator == subject or knows(actor, id) or world.method_records != null and world.method_records.has_read(actor, id):
			rows.append({"id": id, "label": label(id), "known": knows(actor, id), "flow": int(methods[id].flow), "pulses": int(methods[id].pulses)})
	return rows


func label(id: String) -> String:
	return str(methods[id].title) + " · 第%d版" % int(methods[id].revision)


func terms(id: String) -> Dictionary:
	var method: Dictionary = methods[id]
	var flow: Dictionary = definitions.flows[str(int(method.flow))]
	return {"minutes": int(method.pulses) * int(definitions.pulse_minutes), "qi": int(flow.qi) * int(method.pulses), "label": label(id) + "（" + str(flow.label) + "温养）"}


func start(actor: String, object_id: String, id: String, mode: String = "trial", guide: String = "", consent: String = "") -> Dictionary:
	return world.artifacts._begin(actor, "charge", object_id, false, "", {"id": id, "mode": mode, "guide": guide, "consent": consent})


func prepare(actor: String, object_id: String, request: Dictionary) -> Dictionary:
	if not Shape.keys(request, ["id", "mode", "guide", "consent"]) or not methods.has(request.id) or not request.mode in ["trial", "use", "learn", "record"] or not request.guide is String or not request.consent is String:
		return reply(false, "还没有可核对的方法版本。")
	var artifacts: RefCounted = world.artifacts
	if not artifacts.objects.has(object_id) or artifacts.objects[object_id].definition != definitions.artifact_type:
		return reply(false, "这个版本尚未验证可用于这样的器物。")
	if request.mode != "learn":
		if not request.guide.is_empty() or not request.consent.is_empty() or not bool(artifacts.describe(actor, object_id).get("method", false)):
			return reply(false, "先学会引流基础，再独立照此操作。")
		if request.mode == "trial" and methods[request.id].creator != world.embodiment.subject_for_actor(actor) or request.mode == "use" and not knows(actor, str(request.id)):
			return reply(false, "这不是你已经掌握或亲自拟定的版本。")
		if request.mode == "record" and (world.method_records == null or not world.method_records.has_read(actor, str(request.id))):
			return reply(false, "先实际读完载有这一版步骤的记录，再尝试照着练。")
	else:
		if not _lesson_ready(str(request.guide), actor, object_id, str(request.id)) or not consent_valid(str(request.guide), actor, object_id, str(request.id), str(request.consent)):
			return reply(false, "须先有在场教师和本人同意，再亲手练习。")
		if knows(actor, str(request.id)):
			return reply(false, "你已练过这个版本，无需再为同一次学习付出。")
	return reply(true, "可以开始。")


func teach(teacher: String, learner: String, object_id: String, id: String) -> Dictionary:
	if world.elapsed_ms != world.target_ms or not _lesson_ready(teacher, learner, object_id, id) or knows(learner, id):
		return reply(false, "先学会这一版，再与空闲、愿学的同门一起靠近温石；已学过的版本不重复传授。")
	var sim: RefCounted = world.regions[world.artifacts.actor_home(learner)]
	var person: Dictionary = sim.actors[learner]
	var relation: Dictionary = sim.social.relation(learner, teacher)
	var context: Dictionary = {"energy": floorf(float(person.energy) / 20.0) / 5.0, "busy": 0.0, "distance": 0.0, "duty": 0.0, "offer": 0.0, "risk": float(definitions.lesson_risk),
		"benevolence": float(sim.config.actor_profiles[learner].get("benevolence", 0.5)), "affinity": relation.get("affinity", 0.0), "reliability": relation.get("reliability", 0.5), "terms": {"object": object_id, "method": id}}
	var decision: Dictionary = sim.social.evaluate_request(teacher, learner, "heat_lesson", context, sim.config.social_policy, sim._rng, world.current_time)
	world.invalidate_region(world.artifacts.actor_home(learner))
	if decision.get("status") != "accepted":
		return reply(false, "对方暂未答应这次练习；他也有自己的安排。")
	return start(learner, object_id, id, "learn", teacher, str(decision.id))


func _lesson_ready(teacher: String, learner: String, object_id: String, id: String) -> bool:
	var artifacts: RefCounted = world.artifacts
	if teacher == learner or not methods.has(id) or not knows(teacher, id) or not artifacts.objects.has(object_id) or artifacts.objects[object_id].definition != definitions.artifact_type:
		return false
	var home: String = artifacts.actor_home(teacher)
	if home.is_empty() or artifacts.actor_home(learner) != home or not artifacts._near(teacher, object_id) or not artifacts._near(learner, object_id):
		return false
	var sim: RefCounted = world.regions[home]
	for actor: String in [teacher, learner]:
		var body: Dictionary = sim.actors[actor]
		if not bool(body.alive) or not body.active.is_empty() or not world.native_action_allowed(actor) or not world.actor_controls(actor, "motion") or not world.actor_controls(actor, "communication"):
			return false
	if int(sim.actors[teacher].qi) < int(definitions.guide_qi) or int(sim.actors[learner].qi) < int(terms(id).qi):
		return false
	var container: String = str(artifacts.objects[object_id].container)
	if container.begins_with("actor:") and container not in ["actor:" + teacher, "actor:" + learner]:
		return false
	for job: Dictionary in artifacts.active.values():
		if job.object == object_id:
			return false
	return world.soul_vessels == null or not world.soul_vessels.target_in_use(object_id)


func consent_valid(teacher: String, learner: String, object_id: String, id: String, consent: String) -> bool:
	var home: String = world.artifacts.actor_home(learner) if world.artifacts != null else ""
	if home.is_empty():
		return false
	for request: Dictionary in world.regions[home].social.requests.values():
		if request.id == consent and request.requester == teacher and request.responder == learner and request.task == "heat_lesson" and request.status == "accepted" and request.context.get("terms") is Dictionary and request.context.terms.get("object") == object_id and request.context.terms.get("method") == id:
			return true
	return false


func preferred(actor: String) -> String:
	var chosen: String = ""
	var ids: Array = methods.keys()
	ids.sort()
	for id: String in ids:
		if not knows(actor, id) or int(methods[id].flow) > int(definitions.safe_flow):
			continue
		if chosen.is_empty() or int(methods[id].flow) < int(methods[chosen].flow):
			chosen = id
	return chosen


func read_candidate(actor: String) -> String:
	if world.method_records == null:
		return ""
	for id: String in world._sorted_keys(methods):
		if world.method_records.has_read(actor, id) and not knows(actor, id) and int(methods[id].flow) <= int(definitions.safe_flow):
			return id
	return ""


func apply_charge(job: Dictionary) -> void:
	var artifacts: RefCounted = world.artifacts
	var item: Dictionary = artifacts.objects[job.object]
	var shape: Dictionary = artifacts.definitions.types[item.definition]
	var method: Dictionary = methods[job.method.id]
	if int(method.flow) > int(definitions.safe_flow):
		if int(item.damage) >= int(shape.unsafe_damage):
			item.damage = int(shape.damage_max)
			item.charge = 0
			var person: Dictionary = world.regions[job.region].actors[job.actor]
			person.stamina = maxi(0, int(person.stamina) - int(shape.force_backlash_stamina))
			artifacts._finish_record(job, "fractured", "急灌撑开了旧裂隙，石芯崩断、余热散尽；回卷震得手臂发麻。")
			return
		item.damage = mini(int(shape.damage_max), int(item.damage) + int(shape.force_damage))
	var before: int = int(item.charge)
	var gain: int = int(definitions.flows[str(int(method.flow))].charge) * int(method.pulses)
	item.charge = mini(int(shape.max_charge), before + gain)
	if int(item.charge) == before:
		artifacts._finish_record(job, "failed", "石芯没有再积下可辨的余热，投入已逸散；这次不能证实草案有效。")
		return
	var kind: String = "overcharged" if int(method.flow) > int(definitions.safe_flow) else "charged"
	var line: String = "依照“%s”循纹温养，石芯确实积下余热；这只验证了当时的器物与办法。" % label(str(job.method.id))
	if kind == "overcharged":
		line += "接缝发出轻响，这种急灌已留下真实损伤。"
	elif job.method.mode == "learn":
		line = "在%s当面指导下，你亲手完成“%s”；掌握的是这一版，不包括后续修订。" % [world.regions[job.region]._name(str(job.method.guide)), label(str(job.method.id))]
	artifacts._finish_record(job, kind, line)


func to_dict() -> Dictionary:
	return {"version": 1, "methods": methods.duplicate(true), "next_id": next_id}


static func empty_state() -> Dictionary:
	return {"version": 1, "methods": {}, "next_id": 1}


func restore(data: Dictionary) -> bool:
	if not Schema.directory_valid(data, self):
		return false
	methods = data.methods.duplicate(true)
	next_id = int(data.next_id)
	return true


static func reply(ok: bool, line: String, id: String = "") -> Dictionary:
	return {"ok": ok, "line": line, "method": id}
