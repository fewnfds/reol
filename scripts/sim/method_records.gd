class_name SimMethodRecords
extends RefCounted
## Unique written carriers; material quantities and learned practice stay elsewhere.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const Schema = preload("res://scripts/sim/method_record_schema.gd")
const VERBS: Array[String] = ["write", "read", "take", "place", "give"]
var definitions: Dictionary = {}
var objects: Dictionary = {}
var active: Dictionary = {}
var events: Array[Dictionary] = []
var next_id: int = 1
var _owner: WeakRef
var world: RefCounted:
	get:
		return _owner.get_ref()


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "material", "cost", "write_minutes", "read_minutes", "handling_minutes", "interaction_cells", "observation_cells", "policy"]) or data.version != 1 or not SimInventory._nonempty(data.material):
		return false
	for field: String in ["cost", "write_minutes", "read_minutes", "handling_minutes", "interaction_cells", "observation_cells"]:
		if not Shape.count(data[field], 1, 60):
			return false
	return data.policy is Dictionary and not SimSocialMemory.new()._normalized_policy(data.policy).is_empty() and data.observation_cells >= data.interaction_cells


func bind_world(authority: RefCounted) -> void:
	# Rebind a validated candidate without resetting its saved process.
	_owner = weakref(authority)


func initialize(authority: RefCounted, rules: Dictionary) -> bool:
	if authority == null or not valid_definitions(rules):
		return false
	_owner = weakref(authority)
	definitions = rules.duplicate(true)
	return true


func home(actor: String) -> String:
	for region: String in world.regions:
		if world.regions[region].has_actor(actor):
			return region
	return ""


func valid_location(region: Variant, container: Variant) -> bool:
	if not region is String or not container is String or not world.regions.has(region):
		return false
	var sim: VillageSimulation = world.regions[region]
	return sim.inventory.containers.has(container) and (sim.places.has(container) or str(container).begins_with("actor:") and sim.has_actor(str(container).trim_prefix("actor:")))


func cell_at(region: String, container: String) -> Vector2i:
	var sim: VillageSimulation = world.regions[region]
	return SimRouteTravel.cell(sim.synchronize_actor(container.trim_prefix("actor:")).cell if container.begins_with("actor:") else sim.places[container].cell)


func near(actor: String, id: String, radius: float = -1.0) -> bool:
	var region: String = home(actor)
	if region.is_empty() or not objects.has(id) or not world.regions[region].synchronize_actor(actor).alive:
		return false
	return cell_at(region, "actor:" + actor).distance_to(cell_at(str(objects[id].region), str(objects[id].container))) <= (float(definitions.interaction_cells) if radius < 0 else radius)


func held(actor: String, id: String) -> bool:
	return objects.has(id) and objects[id].region == home(actor) and objects[id].container == "actor:" + actor


func accessible(actor: String, id: String) -> bool:
	return near(actor, id) and (not str(objects[id].container).begins_with("actor:") or held(actor, id))


func owns_actor(actor: String) -> bool:
	return active.has(actor)


func _reserved(id: String) -> bool:
	for job: Dictionary in active.values():
		if job.object == id:
			return true
	return false


func read_source(actor: String, method: String, at_ms: int = -1) -> String:
	var limit: int = world.elapsed_ms if at_ms < 0 else at_ms
	for index: int in range(events.size() - 1, -1, -1):
		var event: Dictionary = events[index]
		if event.actor == actor and event.verb == "read" and event.outcome == "completed" and event.method == method and event.finished_ms <= limit:
			return str(event.object)
	return ""


func has_read(actor: String, method: String, at_ms: int = -1) -> bool:
	return not read_source(actor, method, at_ms).is_empty()


func can_write(actor: String, method: String) -> bool:
	return world.heat_methods.methods.has(method) and (world.heat_methods.methods[method].creator == world.embodiment.subject_for_actor(actor) or world.heat_methods.knows(actor, method) or has_read(actor, method))


func duration(verb: String) -> int:
	return int(definitions.write_minutes if verb == "write" else definitions.read_minutes if verb == "read" else definitions.handling_minutes) * 60000


func destination(target: String) -> Dictionary:
	if target.get_slice_count("/") != 2:
		return {}
	var region: String = target.get_slice("/", 0)
	var place: String = target.get_slice("/", 1)
	return {"region": region, "container": place} if world.regions.has(region) and world.regions[region].places.has(place) else {}


func _available(actor: String) -> bool:
	var region: String = home(actor)
	return not region.is_empty() and world.native_action_allowed(actor) and world.actor_controls(actor, "motion") and world.regions[region].synchronize_actor(actor).active.is_empty()


func begin(actor: String, verb: String, id: String = "", method: String = "", target: String = "", during_commit: bool = false) -> Dictionary:
	if not verb in VERBS or home(actor).is_empty() or not during_commit and world.elapsed_ms != world.target_ms:
		return reply(false, "世界事务仍在接续，或缺少明确的操作。")
	world.synchronize_regions()
	if not _available(actor) or world.elapsed_ms > SimInventory.MAX_COUNT - duration(verb):
		return reply(false, "先完成或中断手头的事情，再动手。")
	var region: String = home(actor)
	var sim: VillageSimulation = world.regions[region]
	var person: Dictionary = sim.synchronize_actor(actor)
	var consent: String = ""
	var source: String = ""
	var from_region: String = region
	var from_container: String = "actor:" + actor
	if verb == "write":
		if not id.is_empty() or not target.is_empty() or not can_write(actor, method):
			return reply(false, "只能刻写自己拟定、练过或实际读完的步骤。")
		if sim.inventory.available(from_container, str(definitions.material)) < int(definitions.cost):
			return reply(false, "缺少可自行使用的木料；公差领用物不能拿来刻写私牍。")
		source = read_source(actor, method)
		id = "method_record:%d" % next_id
	else:
		if not method.is_empty() or not accessible(actor, id) or _reserved(id):
			return reply(false, "先靠近可接触的木牍；别人手里或正被使用的不能直接拿来。")
		method = str(objects[id].method)
		from_region = str(objects[id].region)
		from_container = str(objects[id].container)
		if verb == "take" and held(actor, id) or verb in ["place", "give"] and not held(actor, id):
			return reply(false, "取放要以实际持有的木牍为准。")
		if verb in ["read", "take"] and not target.is_empty():
			return reply(false, "阅读和收起无需指定接收者。")
		if verb == "read" and has_read(actor, method):
			return reply(false, "你已经读过这一版；再次拿到不等于新添一门本领。")
		if verb == "place":
			var place: Dictionary = destination(target)
			if place.is_empty() or cell_at(region, "actor:" + actor).distance_to(cell_at(str(place.region), str(place.container))) > float(definitions.interaction_cells):
				return reply(false, "先走到要放置的设施旁边。")
		if verb == "give":
			var answer: Dictionary = _consent(actor, target, id)
			if not answer.ok:
				return answer
			consent = str(answer.id)
	var job_id: String = "method_record:action:%d" % next_id
	if verb == "write" and not sim.inventory.consume(job_id + ":material", "actor:" + actor, str(definitions.material), int(definitions.cost)):
		return reply(false, "木料已不可用，刻写没有开始。")
	next_id += 1
	active[actor] = {"id": job_id, "actor": actor, "region": region, "verb": verb, "object": id, "method": method, "source": source, "target": target, "consent": consent,
		"started_ms": world.elapsed_ms, "due_ms": world.elapsed_ms + duration(verb), "previous_autonomous": bool(person.autonomous), "from_region": from_region, "from_container": from_container}
	person.autonomous = false
	person.goal = "刻写木牍" if verb == "write" else "阅读木牍" if verb == "read" else "交接木牍"
	world.invalidate_region(region)
	return reply(true, str(person.goal) + "已经开始；完成后才形成记录或交接结果。", job_id)


func _consent(actor: String, recipient: String, id: String) -> Dictionary:
	var region: String = home(recipient)
	if region.is_empty():
		return reply(false, "没有能接下这份木牍的人。")
	var sim: VillageSimulation = world.regions[region]
	if actor == recipient or not world.actor_controls(actor, "communication") or not world.actor_controls(recipient, "communication") or distance(actor, recipient) > float(definitions.interaction_cells):
		return reply(false, "先到对方面前，说明想把这份木牍交给他。")
	var body: Dictionary = sim.synchronize_actor(recipient)
	if not body.autonomous or not _available(recipient):
		return reply(false, "对方正在忙，或须由本人另作选择。")
	var memory: SimSocialMemory = social_for(actor, recipient)
	if memory == null:
		return reply(false, "眼下还没有可传达这番商量的渠道。")
	var relation: Dictionary = memory.relation(recipient, actor)
	var context: Dictionary = {"energy": floorf(float(body.energy) / 20.0) / 5.0, "busy": 0.0, "distance": 0.0, "risk": 0.0, "duty": 0.0, "offer": 0.0,
		"benevolence": float(sim.config.actor_profiles[recipient].get("benevolence", 0.5)), "affinity": relation.affinity, "reliability": relation.reliability, "terms": {"record": id}}
	var rng: RandomNumberGenerator = sim._rng if home(actor) == region else world.services._rng
	var decision: Dictionary = memory.evaluate_request(actor, recipient, "receive_method_record", context, definitions.policy, rng, world.current_time)
	world.invalidate_region(region)
	return reply(decision.get("status") == "accepted", "对方愿意接下木牍，仍需实际交到手里。" if decision.get("status") == "accepted" else "对方没有答应接下；他也有自己的打算。", str(decision.get("id", "")))


func social_for(actor: String, recipient: String) -> SimSocialMemory:
	if home(actor) == home(recipient):
		return world.regions[home(recipient)].social
	return null if world.services == null else world.services.social


func distance(left: String, right: String) -> float:
	return cell_at(home(left), "actor:" + left).distance_to(cell_at(home(right), "actor:" + right))


func _connected(job: Dictionary) -> bool:
	if not world.actor_controls(str(job.actor), "action") or not world.actor_controls(str(job.actor), "motion"):
		return false
	if job.verb != "write" and (not accessible(str(job.actor), str(job.object)) or objects[job.object].region != job.from_region or objects[job.object].container != job.from_container):
		return false
	if job.verb == "give":
		return world.actor_controls(str(job.actor), "communication") and world.actor_controls(str(job.target), "communication") and distance(str(job.actor), str(job.target)) <= float(definitions.interaction_cells)
	if job.verb == "place":
		var place: Dictionary = destination(str(job.target))
		return not place.is_empty() and cell_at(str(job.region), "actor:" + str(job.actor)).distance_to(cell_at(str(place.region), str(place.container))) <= float(definitions.interaction_cells)
	return true


func has_settlement_work(_at_ms: int) -> bool:
	return not active.is_empty()


func next_boundary_ms() -> int:
	var next: int = SimInventory.MAX_COUNT
	for job: Dictionary in active.values():
		if not _connected(job):
			return world.elapsed_ms + 1
		next = mini(next, int(job.due_ms))
	return next


func settle_at_ms(at_ms: int) -> void:
	var actors: Array = active.keys()
	actors.sort()
	for actor: String in actors:
		world.synchronize_region(str(active[actor].region))
		if not _connected(active[actor]):
			_finish(active[actor], "failed")
		elif at_ms >= int(active[actor].due_ms):
			_finish(active[actor], "completed")


func cancel(actor: String) -> bool:
	if _owner != null and world != null and world.has_method("accepts_commands") and not world.accepts_commands():
		return false
	if not active.has(actor):
		return false
	_finish(active[actor], "cancelled")
	return true


func _finish(job: Dictionary, outcome: String) -> void:
	if outcome == "completed":
		if job.verb == "write":
			objects[job.object] = {"method": job.method, "scribe": job.actor, "source": job.source, "created_ms": world.elapsed_ms, "region": job.region, "container": "actor:" + str(job.actor)}
		elif job.verb == "take":
			objects[job.object].region = job.region
			objects[job.object].container = "actor:" + str(job.actor)
		elif job.verb == "place":
			var place: Dictionary = destination(str(job.target))
			objects[job.object].region = place.region
			objects[job.object].container = place.container
		elif job.verb == "give":
			objects[job.object].region = home(str(job.target))
			objects[job.object].container = "actor:" + str(job.target)
	var record: Dictionary = job.duplicate(true)
	record["outcome"] = outcome
	record["finished_ms"] = world.elapsed_ms
	events.append(record)
	var person: Dictionary = world.regions[job.region].synchronize_actor(job.actor)
	person.autonomous = bool(job.previous_autonomous)
	person.goal = "刚结束刻写" if job.verb == "write" else "刚结束阅读" if job.verb == "read" else "刚结束交接"
	person.retry_ms = world.elapsed_ms + int(world.regions[job.region].config.decision_interval) * 60000
	active.erase(job.actor)
	world.invalidate_region(str(job.region))
	SimActionContract.job_finished(world, "method_records", job, job.actor, outcome)


func consider_reading() -> void:
	var holders: Dictionary = {}
	for id: String in objects:
		var container: String = str(objects[id].container)
		if container.begins_with("actor:"):
			holders[container.trim_prefix("actor:")] = true
	if holders.is_empty():
		return
	for region: String in world._sorted_keys(world.regions):
		var sim: VillageSimulation = world.regions[region]
		for actor: String in world._sorted_keys(holders):
			if not sim.has_actor(actor):
				continue
			var person: Dictionary = sim.synchronize_actor(actor)
			if not person.autonomous or not person.active.is_empty() or int(person.retry_ms) - int(sim.config.decision_interval) * 60000 != world.elapsed_ms or person.hunger <= sim.config.needs.eat_below or person.energy <= sim.config.needs.rest_below or not _available(actor):
				continue
			for id: String in world._sorted_keys(objects):
				if held(actor, id) and not has_read(actor, str(objects[id].method)):
					if begin(actor, "read", id, "", "", true).ok:
						break


func visible(actor: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: String in world._sorted_keys(objects):
		if near(actor, id, float(definitions.observation_cells)):
			var known: bool = can_write(actor, str(objects[id].method))
			rows.append({"id": id, "label": (world.heat_methods.label(str(objects[id].method)) if known else "刻有细密步骤的木牍") + (" · 随身" if held(actor, id) else " · 眼前"), "accessible": accessible(actor, id)})
	return rows


func status(actor: String) -> Dictionary:
	if active.has(actor):
		var job: Dictionary = active[actor]
		return {"busy": true, "line": ("刻写" if job.verb == "write" else "阅读" if job.verb == "read" else "交接") + "中；还需%d分钟。" % ceili(float(int(job.due_ms) - world.elapsed_ms) / 60000.0)}
	for index: int in range(events.size() - 1, -1, -1):
		var event: Dictionary = events[index]
		if event.actor != actor:
			continue
		if event.outcome != "completed":
			return {"busy": false, "line": "过程未完成；已经投入的木料不退，没有获得新知识或完成交接。"}
		return {"busy": false, "line": "已读完“%s”的步骤；尚需基础和亲手实践，才能验证当时条件下的用法。" % world.heat_methods.label(str(event.method)) if event.verb == "read" else "已刻成一份实物木牍；他人须实际接触和阅读。" if event.verb == "write" else "木牍已实际交接；对方如何理解，还需当面了解。"}
	return {"busy": false, "line": "木牍记录步骤，不保证照做就能成功；持有与理解、练成各不相同。"}


static func empty_state() -> Dictionary:
	return {"version": 1, "objects": {}, "active": {}, "events": [], "next_id": 1}


func to_dict() -> Dictionary:
	return {"version": 1, "objects": objects.duplicate(true), "active": active.duplicate(true), "events": events.duplicate(true), "next_id": next_id}


func restore(data: Dictionary, practice: Array) -> bool:
	if not Schema.validate(data, self, practice):
		return false
	objects = data.objects.duplicate(true)
	active = data.active.duplicate(true)
	events.assign(data.events.duplicate(true))
	next_id = int(data.next_id)
	return true


static func reply(ok: bool, line: String, id: String = "") -> Dictionary:
	return {"ok": ok, "line": line, "id": id}
