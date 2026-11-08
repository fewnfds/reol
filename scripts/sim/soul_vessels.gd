class_name SimSoulVessels
extends RefCounted
## Physical vessels and independent residents. Custody never grants mind control.
## Human practice stays on the original body; this domain owns its teaching proof.

const VERSION: int = 2
const VERBS: Array[String] = ["take", "place", "give", "wake", "listen", "promise", "fulfill", "guide", "sleep", "force"]
const Schema = preload("res://scripts/sim/soul_vessel_schema.gd")

var definitions: Dictionary = {}
var vessels: Dictionary = {}
var residents: Dictionary = {}
var pacts: Dictionary = {}
var active: Dictionary = {}
var events: Array[Dictionary] = []
var elapsed_ms: int = 0
var next_id: int = 1
var agency: SimSoulAgency
var _owner: WeakRef

var world: RefCounted:
	get:
		return _owner.get_ref() if _owner != null else null


static func valid_definitions(data: Variant) -> bool:
	return Schema.definitions_valid(data)


func bind_world(authority: RefCounted) -> void:
	# Rebind a validated candidate without resetting its saved process.
	_owner = weakref(authority)


func initialize(authority: RefCounted, content: Dictionary) -> bool:
	if authority == null or not valid_definitions(content):
		return false
	_owner = weakref(authority)
	definitions = content.duplicate(true)
	elapsed_ms = authority.elapsed_ms
	agency = SimSoulAgency.new(self)
	return true


static func subject_id(id: String) -> String:
	return "subject:soul:" + id


static func carrier_id(id: String) -> String:
	return "vessel:" + id


func bindings() -> Dictionary:
	var result: Dictionary = {}
	for id: String in residents:
		result[subject_id(id)] = str(residents[id].vessel)
	return result


func spawn_opening(scenario: Dictionary) -> bool:
	if not vessels.is_empty() or not residents.is_empty() or not Schema.keys(scenario, ["version", "vessels", "residents"]) or scenario.version != 1 or not scenario.vessels is Array or not scenario.residents is Array:
		return false
	var state: Dictionary = empty_state(elapsed_ms)
	var registry := SimEmbodiment.new()
	if not registry.configure(world._content.body_forms) or not registry.restore(world.embodiment.to_dict()):
		return false
	for row: Variant in scenario.vessels:
		if not Schema.keys(row, ["id", "type", "region", "container"]) or not SimInventory._nonempty(row.id) or state.vessels.has(row.id) or not definitions.vessel_types.has(row.type) or not valid_location(row.region, row.container):
			return false
		state.vessels[row.id] = {"type": row.type, "region": row.region, "container": row.container, "damage": int(definitions.vessel_types[row.type].opening_damage)}
	for row: Variant in scenario.residents:
		if not Schema.keys(row, ["id", "definition", "vessel"]) or not SimInventory._nonempty(row.id) or state.residents.has(row.id) or not definitions.minds.has(row.definition) or not state.vessels.has(row.vessel):
			return false
		var profile: Dictionary = definitions.minds[row.definition]
		state.residents[row.id] = {"definition": row.definition, "vessel": row.vessel, "energy": int(profile.opening_energy), "recovery_ms": 0, "awake": false, "knowledge": profile.knowledge.duplicate()}
		state.pacts[row.id] = {}
		var subject: String = subject_id(row.id)
		var carrier: String = carrier_id(row.vessel)
		if not registry.add_subject(subject) or not registry.add_carrier(carrier, "soul_ring", {"kind": "soul_vessel", "id": row.vessel}) or not registry.reside(subject, carrier) or not registry.grant_control(subject, carrier, "communication"):
			return false
	# Stage both sources and references; validation cannot mutate live ownership.
	var valid: bool = Schema.validate(state, self, registry) and registry.matches_legacy_actors(world._actor_ids(world.regions), world.avian_life.birds.keys(), _bindings_from(state.residents), world.large_bodies.bodies.keys())
	if not valid:
		return false
	_assign(state)
	world.embodiment = registry
	return true


static func _bindings_from(minds: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in minds:
		result[subject_id(id)] = str(minds[id].vessel)
	return result


func valid_location(region: Variant, container: Variant) -> bool:
	return world.artifacts.valid_location(region, container)


func actor_home(actor: String) -> String:
	return world.artifacts.actor_home(actor)


func vessel_cell(id: String) -> Vector2i:
	var item: Dictionary = vessels[id]
	var sim: RefCounted = world.regions[item.region]
	return SimRouteTravel.cell(sim.actors[item.container.trim_prefix("actor:")].cell if str(item.container).begins_with("actor:") else sim.places[item.container].cell)


func near(actor: String, id: String) -> bool:
	var home: String = actor_home(actor)
	return not home.is_empty() and vessels.has(id) and bool(world.regions[home].actors[actor].alive) and SimRouteTravel.cell(world.regions[home].actors[actor].cell).distance_to(vessel_cell(id)) <= float(definitions.interaction_cells)


func can_see(actor: String, id: String) -> bool:
	var home: String = actor_home(actor)
	return not home.is_empty() and vessels.has(id) and bool(world.regions[home].actors[actor].alive) and SimRouteTravel.cell(world.regions[home].actors[actor].cell).distance_to(vessel_cell(id)) <= float(definitions.observation_cells)


func resident_of(vessel: String) -> String:
	for id: String in residents:
		if residents[id].vessel == vessel:
			return id
	return ""


func owns_actor(actor: String) -> bool:
	return active.has(actor) or agency.owns_actor(actor)


func target_in_use(id: String) -> bool:
	for job: Dictionary in active.values():
		if job.target == id:
			return true
	return false


func _communication(soul: String) -> bool:
	return world.embodiment.controls(subject_id(soul), carrier_id(str(residents[soul].vessel)), "communication")


func _held(actor: String, id: String) -> bool:
	return vessels[id].region == actor_home(actor) and vessels[id].container == "actor:" + actor


func _available(actor: String) -> bool:
	var home: String = actor_home(actor)
	return not home.is_empty() and world.actor_controls(actor, "action") and world.actor_controls(actor, "motion") and world.actor_controls(actor, "communication") and world.regions[home].actors[actor].active.is_empty() and not world.local_action_owns(actor) and not world.artifacts.owns_actor(actor) and (world.services == null or not world.services.owns_actor(actor))


func _at_goal(actor: String, soul: String) -> bool:
	var mind: Dictionary = definitions.minds[residents[soul].definition]
	return _held(actor, str(residents[soul].vessel)) and SimRouteTravel.cell(world.regions[actor_home(actor)].actors[actor].cell).distance_to(SimRouteTravel.cell(world.regions[mind.goal_region].places[mind.goal_place].cell)) <= float(definitions.interaction_cells)


func _lesson(soul: String, target: String) -> String:
	if not world.artifacts.objects.has(target):
		return ""
	for known: String in residents[soul].knowledge:
		if definitions.lessons.has(known) and definitions.lessons[known].artifact_definition == world.artifacts.objects[target].definition:
			return known
	return ""


func _can_practice(actor: String, target: String) -> bool:
	if not world.artifacts.objects.has(target) or not world.artifacts._near(actor, target):
		return false
	if world.spirit_sources != null and world.spirit_sources.target_in_use(target):
		return false
	if world.artifacts.target_in_use(target):
		return false
	var item: Dictionary = world.artifacts.objects[target]
	return not str(item.container).begins_with("actor:") or (item.region == actor_home(actor) and item.container == "actor:" + actor)


func begin(actor: String, verb: String, vessel: String, target: String = "", recipient: String = "", destination: String = "") -> Dictionary:
	if not VERBS.has(verb) or not vessels.has(vessel) or world.elapsed_ms != world.target_ms:
		return _reply(false, "眼下找不到可这样接触的旧戒。")
	world.synchronize_regions()
	if not near(actor, vessel) or not _available(actor):
		return _reply(false, "先走近旧戒，并完成或中断手头的事情。")
	var item: Dictionary = vessels[vessel]
	var soul: String = resident_of(vessel)
	var mind: Dictionary = residents[soul]
	var terms: Dictionary = definitions.verbs[verb]
	if agency.owns_soul(soul) or agency.manual == soul and verb in ["listen", "promise", "fulfill", "guide", "sleep"]:
		return _reply(false, "戒中人有自己的意志，眼下没有答应这种配合。")
	for job: Dictionary in active.values():
		if job.vessel == vessel:
			return _reply(false, "这枚旧戒正在被人接触。")
	if not Schema.arguments_valid(verb, target, recipient, destination, self):
		return _reply(false, "这次接触缺少明确的对象或去处。")
	if str(item.container).begins_with("actor:") and not _held(actor, vessel):
		return _reply(false, "旧戒在别人手里；须由持有人同意交接。")
	if verb == "take" and _held(actor, vessel):
		return _reply(false, "旧戒已在你手中。")
	if verb != "take" and not _held(actor, vessel):
		return _reply(false, "先把旧戒取在手中，才能贴近传意或交接。")
	if verb == "place" and not _near_destination(actor, destination):
		return _reply(false, "先到准备放下旧戒的设施旁。")
	if verb == "give" and (recipient == actor or not _available(recipient) or not near(recipient, vessel)):
		return _reply(false, "对方不在近处，或正有自己的事。")
	if verb == "give" and actor_home(recipient) != actor_home(actor):
		return _reply(false, "目前只可与同聚落的同门协商保管；异地访客的保管约定尚未开放。")
	if verb in ["wake", "force"] and bool(mind.awake):
		return _reply(false, "戒中已经有微弱回应，无需反复唤醒。")
	if not verb in ["take", "place", "give", "wake", "force"] and not bool(mind.awake):
		return _reply(false, "戒中没有回应；他似乎正在休眠。")
	if not verb in ["take", "place", "give"] and int(item.damage) >= int(definitions.vessel_types[item.type].damage_max):
		return _reply(false, "封纹已经断开，眼下无法继续传意。")
	if not verb in ["take", "place", "give"] and not _communication(soul):
		return _reply(false, "传意通道眼下没有回应。")
	if not verb in ["take", "place", "give", "force"] and int(mind.energy) < int(terms.attention):
		return _reply(false, "他回应得很疲倦，暂不愿继续；需要一段休眠。")
	if verb == "guide":
		if pacts[soul].get(actor, {}).get("state") != "fulfilled":
			return _reply(false, "他没有答应指导：先履行带他看药圃的约定。")
		if _lesson(soul, target).is_empty() or not _can_practice(actor, target):
			return _reply(false, "他眼下不能指导这件东西；把能亲手操作的温石带到近处再谈。")
	if verb == "fulfill" and (pacts[soul].get(actor, {}).get("state") != "pledged" or not _at_goal(actor, soul)):
		return _reply(false, "须先有约定，再亲自携戒到山门药圃旁。")
	if verb == "promise" and pacts[soul].get(actor, {}).get("state") in ["pledged", "fulfilled"]:
		return _reply(false, "他记得这次约定，无需反复许诺。")
	var home: String = actor_home(actor)
	var person: Dictionary = world.regions[home].actors[actor]
	if int(person.qi) < int(terms.qi) or world.elapsed_ms > SimInventory.MAX_COUNT - int(terms.ms):
		return _reply(false, "眼下没有足够灵气或时间完成这次接触。")
	if verb == "give" and not _accept_custody(actor, recipient, vessel):
		return _reply(false, "对方权衡后暂未答应接手；他有自己的打算。")
	var id: String = _allocate("action")
	person.qi = int(person.qi) - int(terms.qi)
	var attention: int = mini(int(mind.energy), int(terms.attention))
	mind.energy = int(mind.energy) - attention
	active[actor] = {"id": id, "actor": actor, "soul": soul, "vessel": vessel, "verb": verb, "target": target, "recipient": recipient, "destination": destination,
		"region": home, "started_ms": world.elapsed_ms, "due_ms": world.elapsed_ms + int(terms.ms), "qi_spent": int(terms.qi), "soul_spent": attention, "previous_autonomous": bool(person.autonomous)}
	person.autonomous = false
	person.goal = str(terms.label)
	world.invalidate_region(home)
	return _reply(true, "%s；需%d秒，已投入%d灵气。" % [terms.label, ceili(float(terms.ms) / 1000.0), int(terms.qi)])


func _accept_custody(actor: String, recipient: String, vessel: String) -> bool:
	var home: String = actor_home(recipient)
	var sim: RefCounted = world.regions[home]
	var person: Dictionary = sim.actors[recipient]
	var relation: Dictionary = sim.social.relation(recipient, actor)
	var context: Dictionary = {"energy": floorf(float(person.energy) / 20.0) / 5.0, "busy": 0.0, "distance": 0.0, "duty": 0.0, "offer": 0.0,
		"benevolence": float(sim.config.actor_profiles[recipient].get("benevolence", 0.5)), "affinity": relation.get("affinity", 0.0), "reliability": relation.get("reliability", 0.5), "terms": {"vessel": vessel}}
	var decision: Dictionary = sim.social.evaluate_request(actor, recipient, "vessel_custody", context, sim.config.social_policy, sim._rng, world.current_time)
	world.invalidate_region(home)
	return decision.get("status") == "accepted"


func _near_destination(actor: String, destination: String) -> bool:
	var region: String = destination.get_slice(":", 0)
	var place: String = destination.get_slice(":", 1)
	return SimRouteTravel.cell(world.regions[actor_home(actor)].actors[actor].cell).distance_to(SimRouteTravel.cell(world.regions[region].places[place].cell)) <= float(definitions.interaction_cells)


func next_boundary_ms() -> int:
	var boundary: int = agency.next_boundary_ms()
	for actor: String in active:
		if not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or not world.actor_controls(actor, "communication"):
			return world.elapsed_ms + 1
		if not str(active[actor].verb) in ["take", "place", "give"] and not _communication(str(active[actor].soul)):
			return world.elapsed_ms + 1
		boundary = mini(boundary, int(active[actor].due_ms))
	return boundary


func settle_at_ms(tick: int) -> void:
	var delta: int = tick - elapsed_ms
	for id: String in residents:
		var mind: Dictionary = residents[id]
		if not bool(mind.awake):
			var total: int = delta + int(mind.recovery_ms)
			var maximum: int = int(definitions.minds[mind.definition].energy_max)
			@warning_ignore("integer_division")
			var gained: int = total / int(definitions.recovery_ms)
			mind.energy = mini(maximum, int(mind.energy) + gained)
			mind.recovery_ms = total % int(definitions.recovery_ms) if int(mind.energy) < maximum else 0
	elapsed_ms = tick
	var actors: Array = active.keys()
	actors.sort()
	for actor: String in actors:
		world.synchronize_region(active[actor].region)
		if not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or not world.actor_controls(actor, "communication"):
			cancel(actor)
		elif not str(active[actor].verb) in ["take", "place", "give"] and not _communication(str(active[actor].soul)):
			cancel(actor)
		elif int(active[actor].due_ms) <= tick:
			_complete(active[actor])
	agency.settle_at_ms(tick)


func _complete(job: Dictionary) -> void:
	var actor: String = str(job.actor)
	var item: Dictionary = vessels[job.vessel]
	var mind: Dictionary = residents[job.soul]
	var profile: Dictionary = definitions.minds[mind.definition]
	if not near(actor, job.vessel) or (job.verb != "take" and not _held(actor, job.vessel)):
		_finish(job, "failed", "已经离开旧戒，这次接触没有完成。")
		return
	var line: String = ""
	match str(job.verb):
		"take":
			if str(item.container).begins_with("actor:"):
				_finish(job, "failed", "旧戒已被人收起，不能重复取走。")
				return
			item.region = job.region
			item.container = "actor:" + actor
			line = "旧戒已收好；保管它不等于支配戒中意志。"
		"place", "give":
			if job.verb == "place" and not _near_destination(actor, job.destination) or job.verb == "give" and (not near(job.recipient, job.vessel) or not _available(job.recipient)):
				_finish(job, "failed", "交接条件已经变化，旧戒仍由原持有人保管。")
				return
			for promisor: String in pacts[job.soul]:
				var pact: Dictionary = pacts[job.soul][promisor]
				if pact.state == "pledged":
					pact.state = "broken"
					pact.settled_ms = elapsed_ms
			if job.verb == "give":
				item.region = actor_home(job.recipient)
				item.container = "actor:" + str(job.recipient)
				line = "对方接过了同一枚旧戒；戒中人的记忆与约定随他保留。"
			else:
				item.region = str(job.destination).get_slice(":", 0)
				item.container = str(job.destination).get_slice(":", 1)
				line = "旧戒已放妥；未履行便离手的约定，他会记住。"
		"wake", "force":
			if job.verb == "force":
				var shape: Dictionary = definitions.vessel_types[item.type]
				item.damage = mini(int(shape.damage_max), int(item.damage) + int(shape.force_damage))
				if pacts[job.soul].has(actor):
					pacts[job.soul][actor].state = "broken"
					pacts[job.soul][actor].settled_ms = elapsed_ms
			if int(item.damage) >= int(definitions.vessel_types[item.type].damage_max):
				mind.awake = false
				line = "封纹断开了；戒中只剩沉默，强唤没有换来配合。"
			else:
				mind.awake = true
				mind.recovery_ms = 0
				line = "封纹传来抵触：别再强叩了。先前的约定不能替这次伤害作保；想合作，须重新履约。" if job.verb == "force" else str(profile.greeting)
		"listen": line = str(profile.old_memory)
		"promise":
			pacts[job.soul][actor] = {"state": "pledged", "pledged_ms": elapsed_ms, "settled_ms": 0}
			line = "他记下你的承诺：亲自带他到山门药圃，再谈指导。"
		"fulfill":
			if not _at_goal(actor, job.soul):
				_finish(job, "failed", "没有在约定的药圃旁完成交流。")
				return
			pacts[job.soul][actor].state = "fulfilled"
			pacts[job.soul][actor].settled_ms = elapsed_ms
			line = "他借封纹感到了近处药木的气息，记得这回是你践了约。"
		"guide":
			if not _can_practice(actor, job.target):
				_finish(job, "failed", "温石已不在能亲手练习的近处；这次只听到一半，尚未学成。")
				return
			line = str(definitions.lessons[_lesson(str(job.soul), str(job.target))].line)
		"sleep":
			mind.awake = false
			mind.recovery_ms = 0
			line = "他自行收敛残识，愿意先歇息一阵；旧事不会随休眠重置。"
	_finish(job, str(job.verb), line)


func cancel(actor: String) -> bool:
	if _owner != null and world != null and world.has_method("accepts_commands") and not world.accepts_commands():
		return false
	if not active.has(actor):
		return false
	_finish(active[actor], "cancelled", "接触中断，已付灵气与注意不会退还；未完成的手法不会因此学会。")
	return true


func _finish(job: Dictionary, kind: String, line: String) -> void:
	var record: Dictionary = job.duplicate(true)
	record.erase("previous_autonomous")
	record.erase("due_ms")
	record["action"] = str(record.id)
	record.id = _allocate("event")
	record["at_ms"] = elapsed_ms
	record["kind"] = kind
	record["line"] = line
	events.append(record)
	var person: Dictionary = world.regions[job.region].actors[job.actor]
	person.autonomous = bool(job.previous_autonomous)
	person.goal = "回味方才交流" if kind != "cancelled" else "接触已中断"
	active.erase(job.actor)
	world.invalidate_region(job.region)


func learned(actor: String, object_id: String) -> bool:
	for event: Dictionary in events:
		if event.actor == actor and event.target == object_id and event.kind == "guide":
			return true
	return false


func lesson_line(actor: String, object_id: String) -> String:
	for index in range(events.size() - 1, -1, -1):
		var event: Dictionary = events[index]
		if event.actor == actor and event.target == object_id and event.kind == "guide":
			return "你的受教记录：" + str(event.line)
	return ""


func describe(actor: String, id: String) -> Dictionary:
	if not can_see(actor, id):
		return {"known": false}
	var item: Dictionary = vessels[id]
	var shape: Dictionary = definitions.vessel_types[item.type]
	var last: Dictionary = {}
	var met: bool = false
	for event: Dictionary in events:
		if event.vessel == id and (event.actor == actor or event.recipient == actor):
			last = event
			met = met or event.kind in ["wake", "force", "listen", "promise", "fulfill", "guide"]
	var line: String = str(shape.appearance)
	if int(item.damage) >= int(shape.damage_max):
		line += "\n封纹已断，传意处一片黯淡。"
	if not last.is_empty():
		line += "\n你亲历的接触：" + str(last.line)
	return {"known": true, "label": str(shape.name) if met else str(shape.unknown_name), "line": line, "met": met, "held": _held(actor, id), "near": near(actor, id), "cell": [vessel_cell(id).x, vessel_cell(id).y]}


func status(actor: String) -> Dictionary:
	if active.has(actor):
		var job: Dictionary = active[actor]
		return {"busy": true, "line": str(definitions.verbs[job.verb].label), "remaining": ceili(float(int(job.due_ms) - world.elapsed_ms) / 60000.0), "seconds": ceili(float(int(job.due_ms) - world.elapsed_ms) / 1000.0)}
	for index in range(events.size() - 1, -1, -1):
		if events[index].actor == actor:
			return {"busy": false, "line": str(events[index].line), "event": str(events[index].id)}
	return {"busy": false, "line": "眼下没有正在接触的旧戒。"}


func to_dict() -> Dictionary:
	return {"version": VERSION, "elapsed_ms": elapsed_ms, "vessels": vessels.duplicate(true), "residents": residents.duplicate(true), "pacts": pacts.duplicate(true), "active": active.duplicate(true), "events": events.duplicate(true), "next_id": next_id, "agency": agency.to_dict()}


func restore(data: Variant) -> bool:
	if not Schema.validate(data, self):
		return false
	_assign(data)
	return true


func _assign(data: Dictionary) -> void:
	vessels = data.vessels.duplicate(true)
	residents = data.residents.duplicate(true)
	pacts = data.pacts.duplicate(true)
	active = data.active.duplicate(true)
	events.assign(data.events.duplicate(true))
	elapsed_ms = int(data.elapsed_ms)
	next_id = int(data.next_id)
	agency.assign_state(data.agency)


static func empty_state(now: int) -> Dictionary:
	return {"version": VERSION, "elapsed_ms": now, "vessels": {}, "residents": {}, "pacts": {}, "active": {}, "events": [], "next_id": 1, "agency": SimSoulAgency.empty_state()}


func _allocate(kind: String) -> String:
	var id: String = "soul:" + kind + ":" + str(next_id)
	next_id += 1
	return id


static func _reply(ok: bool, line: String) -> Dictionary:
	return {"ok": ok, "line": line}
