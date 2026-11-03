class_name SimSoulAgency
extends RefCounted
## A resident chooses to communicate; a willing human still moves their own body.
## Only cross-domain contacts live here, never a copy of human social relations.

const Schema = preload("res://scripts/sim/soul_agency_schema.gd")
var manual: String = ""
var voice: Dictionary = {}
var errands: Dictionary = {}
var events: Array[Dictionary] = []
var social: SimSocialMemory = SimSocialMemory.new()
var next_id: int = 1
var _owner: WeakRef

var domain: RefCounted:
	get:
		return _owner.get_ref() if _owner != null else null
var world: RefCounted:
	get:
		return domain.world


func _init(parent: RefCounted) -> void:
	_owner = weakref(parent)


func activate(id: String) -> bool:
	if not manual.is_empty() or world.elapsed_ms != 0 or not domain.residents.has(id) or not domain.active.is_empty():
		return false
	manual = id
	domain.residents[id].awake = true
	domain.residents[id].recovery_ms = 0
	social.register_actor("subject:soul:" + id)
	return true


func owns_actor(actor: String) -> bool:
	return errands.has(actor)


func owns_soul(id: String) -> bool:
	return not voice.is_empty() and voice.soul == id


func point(id: String) -> Vector2:
	var item: Dictionary = domain.vessels[domain.residents[id].vessel]
	if str(item.container).begins_with("actor:"):
		return SimRouteTravel.point(world.regions[item.region].actors[str(item.container).trim_prefix("actor:")])
	return TileGrid.cell_to_world(SimRouteTravel.cell(world.regions[item.region].places[item.container].cell))


func _can_hear(id: String, actor: String) -> bool:
	var home: String = domain.actor_home(actor)
	return not home.is_empty() and bool(world.regions[home].actors[actor].alive) and point(id).distance_to(SimRouteTravel.point(world.regions[home].actors[actor])) <= float(domain.definitions.agency.sense_cells) * TileGrid.TILE_SIZE


func _introduced(actor: String) -> bool:
	for event: Dictionary in events:
		if event.actor == actor and event.kind == "accepted":
			return true
	return false


func perceive(id: String) -> Dictionary:
	if not domain.residents.has(id):
		return {}
	var mind: Dictionary = domain.residents[id]
	var item: Dictionary = domain.vessels[mind.vessel]
	var profile: Dictionary = domain.definitions.minds[mind.definition]
	var signals: Array[Dictionary] = []
	if bool(mind.awake) and int(item.damage) < int(domain.definitions.vessel_types[item.type].damage_max):
		for region: String in world.regions:
			for actor: String in world.regions[region].actors:
				if not _can_hear(id, actor):
					continue
				var offset: Vector2 = SimRouteTravel.point(world.regions[region].actors[actor]) - point(id)
				var label: String = "一道呼吸的气息"
				if _introduced(actor):
					label = world._content.get_pawn(StringName(world.regions[region].actors[actor].definition_id)).display_name
				signals.append({"id": actor, "label": label, "offset": [offset.x, offset.y]})
		signals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var da: float = Vector2(float(a.offset[0]), float(a.offset[1])).length_squared()
			var db: float = Vector2(float(b.offset[0]), float(b.offset[1])).length_squared()
			return a.id < b.id if is_equal_approx(da, db) else da < db)
	var energy: int = int(mind.energy)
	var line: String = "封纹内寂静，残识正在休息。" if not bool(mind.awake) else ("残识有些疲倦" if energy < int(domain.definitions.verbs.guide.attention) else "残识尚能凝聚")
	var latest: String = "你还记得旧日温石手法，却不知道如今的人事。"
	if not events.is_empty():
		latest = str(events.back().line)
	var carrying: bool = str(item.container).begins_with("actor:")
	var known_holder: bool = carrying and _introduced(str(item.container).trim_prefix("actor:"))
	return {"name": str(profile.name), "awake": bool(mind.awake), "line": line, "signals": signals, "latest": latest,
		"carried": carrying, "holder": str(item.container).trim_prefix("actor:") if known_holder else "", "busy": not voice.is_empty(),
		"seconds": ceili(float(int(voice.due_ms) - world.elapsed_ms) / 1000.0) if not voice.is_empty() else 0,
		"activity": {"wake": "凝聚残识", "observe": "感受近处灵机", "call": "向近处传意", "sleep": "收敛残识"}.get(voice.get("verb", ""), "随载体静听"),
		"errand": not errands.is_empty(), "seal_broken": int(item.damage) >= int(domain.definitions.vessel_types[item.type].damage_max)}


func command(id: String, verb: String, target: String = "") -> Dictionary:
	if manual != id or not domain.residents.has(id) or world.elapsed_ms != world.target_ms:
		return _reply(false, "眼下不能支配这段残识。")
	if verb == "cancel":
		if not voice.is_empty():
			_record(id, str(voice.target), "cancelled", "你收回传意；已付出的注意没有退还。")
			voice = {}
		for actor: String in errands.keys():
			_finish_errand(errands[actor], false, "你撤回了请求；已收起的旧戒仍由对方保管。")
		return _reply(true, "请求已撤回，世界与实际保管位置继续。")
	if not domain.definitions.agency.actions.has(verb) or not voice.is_empty():
		return _reply(false, "先完成或收回正在进行的传意。")
	var mind: Dictionary = domain.residents[id]
	var vessel: String = str(mind.vessel)
	for job: Dictionary in domain.active.values():
		if job.vessel == vessel:
			return _reply(false, "载体正被人接触，暂无法凝神。")
	if verb == "wake" and mind.awake or verb != "wake" and not mind.awake:
		return _reply(false, "你已清醒。" if mind.awake else "先凝聚残识，才能感知和传意。")
	if not world.embodiment.controls("subject:soul:" + id, "vessel:" + vessel, "communication"):
		return _reply(false, "眼下无法支配自己的传意。")
	var item: Dictionary = domain.vessels[vessel]
	if verb in ["call", "observe"] and int(item.damage) >= int(domain.definitions.vessel_types[item.type].damage_max):
		return _reply(false, "封纹断开，传意与外感暂时受阻；仍可收敛休息。")
	if verb == "call" and (not _can_hear(id, target) or not errands.is_empty()):
		return _reply(false, "只能向眼下感到的气息传意，已有携戒约定须先处理。")
	if verb != "call" and not target.is_empty():
		return _reply(false, "这次凝神不需要指定别人。")
	var terms: Dictionary = domain.definitions.agency.actions[verb]
	if int(mind.energy) < int(terms.attention) or world.elapsed_ms > SimInventory.MAX_COUNT - int(terms.ms):
		return _reply(false, "残识难以继续凝聚；先收敛休息一段时间。")
	mind.energy = int(mind.energy) - int(terms.attention)
	voice = {"id": _allocate("action"), "soul": id, "verb": verb, "target": target, "started_ms": world.elapsed_ms, "due_ms": world.elapsed_ms + int(terms.ms), "spent": int(terms.attention)}
	return _reply(true, "已开始凝神，需%d秒；你仍不能替别人决定行动。" % ceili(float(terms.ms) / 1000.0))


func next_boundary_ms() -> int:
	var boundary: int = SimInventory.MAX_COUNT
	if not voice.is_empty():
		if not world.embodiment.controls("subject:soul:" + str(voice.soul), "vessel:" + str(domain.residents[voice.soul].vessel), "communication"):
			return world.elapsed_ms + 1
		boundary = int(voice.due_ms)
	for actor: String in errands:
		var job: Dictionary = errands[actor]
		if not world.actor_controls(actor, "motion") or not world.actor_controls(actor, "action"):
			return world.elapsed_ms + 1
		boundary = mini(boundary, int(job.due_ms))
		if job.phase != "pickup":
			boundary = mini(boundary, SimRouteTravel.crossing_ms(job, world.regions[job.region].actors[actor], world.elapsed_ms))
	return boundary


func settle_at_ms(now: int) -> void:
	if not voice.is_empty():
		var id: String = str(voice.soul)
		if not world.embodiment.controls("subject:soul:" + id, "vessel:" + str(domain.residents[id].vessel), "communication"):
			_record(id, str(voice.target), "cancelled", "传意中断；已付注意没有退还。")
			voice = {}
		elif now >= int(voice.due_ms):
			var command_row: Dictionary = voice
			voice = {}
			_complete_voice(command_row)
	var actors: Array = errands.keys()
	actors.sort()
	for actor: String in actors:
		var job: Dictionary = errands[actor]
		var sim: RefCounted = world.regions[job.region]
		world.synchronize_region(job.region)
		if not world.actor_controls(actor, "motion") or not world.actor_controls(actor, "action") or not _custody_matches(job):
			_finish_errand(job, false, "对方没能继续携戒，实际物品留在当前保管处。")
			continue
		if job.phase != "pickup":
			if not job.path.is_empty() and sim._step_validator.is_valid() and not bool(sim._step_validator.call(SimRouteTravel.cell(sim.actors[actor].cell), SimRouteTravel.cell(job.path[0]) - SimRouteTravel.cell(sim.actors[actor].cell))):
				_finish_errand(job, false, "路已不通，对方停止赶路；旧戒没有退回原处。")
				continue
			SimRouteTravel.project(job, sim.actors[actor], now)
			world.invalidate_region(job.region)
		if now < int(job.due_ms):
			continue
		if job.phase == "pickup":
			var item: Dictionary = domain.vessels[job.vessel]
			if not domain.near(actor, job.vessel):
				_finish_errand(job, false, "对方未能在近处收起旧戒。")
				continue
			item.region = job.region
			item.container = "actor:" + actor
			job.picked = true
			if not _route(job, SimRouteTravel.cell(world.regions[job.goal_region].places[job.goal_place].cell), "carry"):
				_finish_errand(job, false, "对方已收起旧戒，但暂时找不到去药圃的路。")
		else:
			if not job.path.is_empty():
				sim.set_actor_cell(actor, SimRouteTravel.cell(job.path.pop_front()))
			if not job.path.is_empty():
				SimRouteTravel.begin_segment(job, sim.actors[actor], now, _speed())
			elif job.phase == "approach":
				job.phase = "pickup"
				job.segment_started_ms = now
				job.segment_from = sim.actors[actor].position.duplicate()
				job.due_ms = now + int(domain.definitions.verbs.take.ms)
			else:
				_finish_errand(job, true, "对方践约把同一枚旧戒带到了药圃；你可以亲自感受此地草木。")


func _complete_voice(row: Dictionary) -> void:
	var id: String = str(row.soul)
	match str(row.verb):
		"wake":
			domain.residents[id].awake = true
			domain.residents[id].recovery_ms = 0
			_record(id, "", "wake", "你重新凝聚残识；世界没有为这次苏醒重置。")
		"sleep":
			domain.residents[id].awake = false
			domain.residents[id].recovery_ms = 0
			_record(id, "", "sleep", "你收敛残识，在原载体中休息。")
		"observe":
			var profile: Dictionary = domain.definitions.minds[domain.residents[id].definition]
			var at_goal: bool = point(id).distance_to(TileGrid.cell_to_world(SimRouteTravel.cell(world.regions[profile.goal_region].places[profile.goal_place].cell))) <= float(domain.definitions.agency.sense_cells) * TileGrid.TILE_SIZE
			_record(id, "", "observed", "近处药木的气息与旧日不同；这是你此刻亲历的新认识。" if at_goal else "你只感到封纹附近的呼吸与散乱灵机；远处人事仍不知道。")
		"call": _request_carry(id, str(row.target))


func _request_carry(id: String, actor: String) -> void:
	if not _can_hear(id, actor):
		_record(id, actor, "unheard", "那道气息已离开传意范围，没有收到明确回应。")
		return
	var region: String = domain.actor_home(actor)
	var sim: RefCounted = world.regions[region]
	world.synchronize_region(region)
	var body: Dictionary = sim.actors[actor]
	var profile: Dictionary = domain.definitions.minds[domain.residents[id].definition]
	var subject: String = "subject:soul:" + id
	var responder: String = world.embodiment.subject_for_actor(actor)
	social.register_actor(responder)
	social.configure(sim.config.social_policy)
	var relation: Dictionary = social.relation(responder, subject)
	var free: bool = domain._available(actor)
	var context: Dictionary = {"energy": floorf(float(body.energy) / 20.0) / 5.0, "busy": 0.0 if free else 1.0, "distance": 0.0, "duty": 0.0, "offer": 0.0,
		"benevolence": float(sim.config.actor_profiles[actor].get("benevolence", 0.5)), "affinity": relation.get("affinity", 0.0), "reliability": relation.get("reliability", 0.5),
		"terms": {"vessel": str(domain.residents[id].vessel), "region": str(profile.goal_region), "place": str(profile.goal_place)}}
	var decision: Dictionary = social.evaluate_request(subject, responder, "carry_vessel", context, sim.config.social_policy, sim._rng, world.current_time)
	world.invalidate_region(region)
	var vessel: String = str(domain.residents[id].vessel)
	var item: Dictionary = domain.vessels[vessel]
	if decision.get("status") != "accepted" or not free or not world.actor_controls(actor, "communication") or str(item.container).begins_with("actor:") and item.container != "actor:" + actor:
		_record(id, actor, "refused", "对方未答应携戒；他可能正有自己的事，也不愿擅取别人手中之物。", str(decision.get("id", "")))
		return
	var name: String = world._content.get_pawn(StringName(body.definition_id)).display_name
	var job: Dictionary = {"id": _allocate("errand"), "soul": id, "actor": actor, "region": region, "request": str(decision.id), "vessel": vessel,
		"goal_region": str(profile.goal_region), "goal_place": str(profile.goal_place), "phase": "", "path": [], "due_ms": world.elapsed_ms + 1,
		"segment_started_ms": world.elapsed_ms, "segment_from": body.position.duplicate(), "started_ms": world.elapsed_ms, "previous_autonomous": bool(body.autonomous), "picked": item.container == "actor:" + actor}
	if not _route(job, SimRouteTravel.cell(world.regions[profile.goal_region].places[profile.goal_place].cell) if bool(job.picked) else domain.vessel_cell(vessel), "carry" if bool(job.picked) else "approach"):
		_record(id, actor, "refused", "对方愿意帮忙，却暂时找不到通往旧戒或药圃的路。", str(decision.id))
		return
	body.autonomous = false
	body.goal = "回应戒中传意，携戒看药圃"
	errands[actor] = job
	_record(id, actor, "accepted", "对方自报%s，答应替你携戒去药圃；他仍按自己的身体与道路行动。" % name, str(decision.id))
	world.invalidate_region(region)


func _route(job: Dictionary, target: Vector2i, phase: String) -> bool:
	var sim: RefCounted = world.regions[job.region]
	var body: Dictionary = sim.actors[job.actor]
	var path: Array[Vector2i] = sim.find_path(SimRouteTravel.cell(body.cell), target)
	if path.is_empty() and SimRouteTravel.cell(body.cell) != target:
		return false
	job.path = []
	for cell: Vector2i in path:
		if cell != SimRouteTravel.cell(body.cell):
			job.path.append([cell.x, cell.y])
	if not SimRouteTravel.point(body).is_equal_approx(TileGrid.cell_to_world(SimRouteTravel.cell(body.cell))):
		job.path.push_front(body.cell.duplicate())
	job.phase = phase
	SimRouteTravel.begin_segment(job, body, world.elapsed_ms, _speed())
	return true


func _custody_matches(job: Dictionary) -> bool:
	var item: Dictionary = domain.vessels[job.vessel]
	return item.region == job.region and item.container == "actor:" + str(job.actor) if bool(job.picked) else not str(item.container).begins_with("actor:")


func _finish_errand(job: Dictionary, success: bool, line: String) -> void:
	var body: Dictionary = world.regions[job.region].actors[job.actor]
	body.autonomous = bool(job.previous_autonomous)
	body.goal = "刚结束携戒相助" if success else "携戒请求已中断"
	_record(str(job.soul), str(job.actor), "arrived" if success else "interrupted", line, str(job.request))
	errands.erase(job.actor)
	world.invalidate_region(job.region)


func _record(id: String, actor: String, kind: String, line: String, request: String = "") -> void:
	events.append({"id": _allocate("event"), "soul": id, "actor": actor, "kind": kind, "at_ms": world.elapsed_ms, "line": line, "request": request})


func _allocate(kind: String) -> String:
	var id: String = "soul_agency:" + kind + ":" + str(next_id)
	next_id += 1
	return id


func _speed() -> float:
	return float(world.regions.values()[0].motion_rules.motion.speed)


func to_dict() -> Dictionary:
	return {"version": 1, "manual": manual, "voice": voice.duplicate(true), "errands": errands.duplicate(true), "events": events.duplicate(true), "social": social.to_dict(), "next_id": next_id}


func restore(data: Variant) -> bool:
	if not Schema.validate(data, domain, domain.to_dict()):
		return false
	assign_state(data)
	return true


func assign_state(data: Dictionary) -> void:
	manual = str(data.manual)
	voice = data.voice.duplicate(true)
	errands = data.errands.duplicate(true)
	events.assign(data.events.duplicate(true))
	social.restore(data.social)
	next_id = int(data.next_id)


static func empty_state() -> Dictionary:
	return {"version": 1, "manual": "", "voice": {}, "errands": {}, "events": [], "social": SimSocialMemory.new().to_dict(), "next_id": 1}


static func _reply(ok: bool, line: String) -> Dictionary:
	return {"ok": ok, "line": line}
